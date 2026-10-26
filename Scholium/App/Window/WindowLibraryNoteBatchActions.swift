import Foundation
import ScholiumContracts

@MainActor
private struct LibraryNoteBatchAdmission {
    let operations: any LibraryMutationUseCases
    let isCurrent: @MainActor () -> Bool
    let originIsCurrent: @MainActor () -> Bool
}

enum LibraryNoteBatchError: LocalizedError {
    case operationInProgress
    case selectionChanged
    case revisionChainChanged

    var errorDescription: String? {
        switch self {
        case .operationInProgress:
            String(localized: "Another Library operation is already in progress.", table: "Localizable", bundle: .module)
        case .selectionChanged:
            String(localized: "The selected notes changed. Select them again before continuing.", table: "Localizable", bundle: .module)
        case .revisionChainChanged:
            String(localized: "A selected note changed outside this batch. Review it before continuing.", table: "Localizable", bundle: .module)
        }
    }
}

extension WindowLibraryMutationController {
    func prepareNoteBatch(_ targets: [NoteMutationTarget]) async throws -> LibraryNoteBatchRequest {
        guard !isBatchWorking, !hasActiveLibraryMutation else {
            throw LibraryNoteBatchError.operationInProgress
        }
        guard let context = dependencies.context(), context.sourceScope == .library,
            !targets.isEmpty, targets.allSatisfy({ $0.documentID.vaultID == context.vault.id }),
            Set(targets.map(\.stableNoteID)).count == targets.count,
            Set(targets.map(\.documentID)).count == targets.count
        else { throw LibraryNoteBatchError.selectionChanged }
        let admittedBinding = bindingID
        isBatchWorking = true
        defer { isBatchWorking = false }
        try await dependencies.flushEditors(context.assignmentID)
        try Task.checkCancellation()
        guard bindingID == admittedBinding,
            dependencies.context()?.assignmentID == context.assignmentID,
            dependencies.context()?.vault.id == context.vault.id,
            dependencies.context()?.sourceScope == .library
        else { throw CancellationError() }
        let captured = try dependencies.captureBatchTargets(targets)
        guard captured.count == targets.count,
            zip(captured, targets).allSatisfy({ $0.documentID == $1.documentID && $0.stableNoteID == $1.stableNoteID })
        else { throw LibraryNoteBatchError.selectionChanged }
        return LibraryNoteBatchRequest(assignmentID: context.assignmentID, vaultID: context.vault.id, targets: captured)
    }

    func cancelNoteBatch() { batchCancellation?() }

    func moveNotes(_ request: LibraryNoteBatchRequest, toFolder folderRelativePath: String) async -> LibraryNoteBatchOutcome {
        let operation = LibraryNoteBatchOperation.move(folderRelativePath: folderRelativePath)
        return await ownNoteBatch(request, operation: operation) { [self] admission in
            await LibraryNoteBatchExecution.move(
                request, toFolder: folderRelativePath,
                isCurrent: admission.isCurrent,
                move: { [self] target, destination in
                    try await dependencies.flushEditors(request.assignmentID)
                    try Task.checkCancellation()
                    guard admission.isCurrent() else { throw CancellationError() }
                    return try await admission.operations.move(target, to: destination)
                },
                didCommit: { [self] outcome, target in
                    await dependencies.committedNoteMoved(outcome, target, admission.isCurrent)
                },
                didFail: { [self] in
                    if admission.isCurrent() { await dependencies.refreshTransactionRecovery() }
                }
            )
        }
    }

    func prepareNotesSystemTrash(_ request: LibraryNoteBatchRequest) async throws -> SystemTrashDeletionPreview {
        guard !isBatchWorking, !hasActiveLibraryMutation else { throw LibraryNoteBatchError.operationInProgress }
        guard batchIsCurrent(request) else { throw LibraryNoteBatchError.selectionChanged }
        let admittedBinding = bindingID
        let operations = try requireOperations()
        isBatchWorking = true
        defer { isBatchWorking = false }
        var sources: [SystemTrashDeletionSourceTarget] = []
        for target in request.targets {
            try Task.checkCancellation()
            guard bindingID == admittedBinding, batchIsCurrent(request) else { throw CancellationError() }
            let preview = try await operations.prepareSystemTrash(target)
            guard preview.triptychID == request.assignmentID else { throw LibraryNoteBatchError.selectionChanged }
            sources.append(contentsOf: preview.sources)
        }
        try Task.checkCancellation()
        guard bindingID == admittedBinding, batchIsCurrent(request) else { throw CancellationError() }
        return SystemTrashDeletionPreview(triptychID: request.assignmentID, sources: sources)
    }

    func executeNotesSystemTrash(_ preview: SystemTrashDeletionPreview) async -> LibraryNoteBatchOutcome {
        let targets = preview.sources.flatMap { source in
            source.notes.map { note in
                NoteMutationTarget(
                    documentID: VaultQualifiedNoteID(vaultID: source.vaultID, relativePath: note.relativePath),
                    stableNoteID: note.noteID, revision: note.expectedRevision)
            }
        }
        let request = LibraryNoteBatchRequest(
            id: preview.id, assignmentID: preview.triptychID,
            vaultID: preview.sources.first?.vaultID ?? UUID(), targets: targets)
        return await ownNoteBatch(request, operation: .systemTrash) { [self] admission in
            do {
                try Task.checkCancellation()
                guard admission.isCurrent() else { throw CancellationError() }
                try await dependencies.flushEditors(request.assignmentID)
                try Task.checkCancellation()
                guard admission.isCurrent() else { throw CancellationError() }
                let outcome = try await admission.operations.moveToSystemTrash(preview)
                await dependencies.committedSystemTrash(preview, outcome, admission.originIsCurrent)
                return LibraryNoteBatchOutcome(
                    request: request, operation: .systemTrash,
                    items: targets.map { .init(target: $0, destinationRelativePath: nil, status: .succeeded) },
                    recoveryRequired: outcome.committedValue.pendingCleanupRecovery != nil,
                    warnings: [outcome.committedValue.pendingCleanupWarning, outcome.derivedRefreshWarning, outcome.identityRecoveryWarning].compactMap { $0 })
            } catch {
                if admission.originIsCurrent() { await dependencies.refreshTransactionRecovery() }
                await dependencies.committedSystemTrash(preview, nil, admission.originIsCurrent)
                return LibraryNoteBatchExecution.trashFailure(request, preview: preview, error: error)
            }
        }
    }

    private func batchIsCurrent(_ request: LibraryNoteBatchRequest) -> Bool {
        guard let context = dependencies.context() else { return false }
        return context.assignmentID == request.assignmentID && context.vault.id == request.vaultID
            && context.sourceScope == .library
    }

    private func ownNoteBatch(
        _ request: LibraryNoteBatchRequest, operation: LibraryNoteBatchOperation,
        perform: @escaping @MainActor (LibraryNoteBatchAdmission) async -> LibraryNoteBatchOutcome
    ) async -> LibraryNoteBatchOutcome {
        guard !isBatchWorking, !hasActiveLibraryMutation else {
            return LibraryNoteBatchExecution.failure(request, operation: operation, error: LibraryNoteBatchError.operationInProgress)
        }
        let admittedBinding = bindingID
        let operations: any LibraryMutationUseCases
        do { operations = try requireOperations() } catch {
            return LibraryNoteBatchExecution.failure(request, operation: operation, error: error)
        }
        let originIsCurrent: @MainActor () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.bindingID == admittedBinding
                && self.dependencies.context()?.assignmentID == request.assignmentID
        }
        let admission = LibraryNoteBatchAdmission(
            operations: operations,
            isCurrent: { [weak self] in
                guard let self else { return false }
                return originIsCurrent() && self.batchIsCurrent(request)
            },
            // Committed Trash cleanup still belongs to this window while its
            // Library independently browses another role or source scope.
            originIsCurrent: originIsCurrent)
        isBatchWorking = true
        let task = Task { await perform(admission) }
        batchCancellation = { task.cancel() }
        defer {
            batchCancellation = nil
            isBatchWorking = false
        }
        // A cancellation after a commit must still return that commit's result.
        let outcome = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if bindingID == admittedBinding { lastBatchOutcome = outcome }
        return outcome
    }
}
