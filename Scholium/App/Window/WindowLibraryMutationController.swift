import Combine
import Foundation
import ScholiumContracts

struct WindowMarkdownImportFailure: Sendable {
    let sourceName: String
    let reason: String
}

struct WindowMarkdownImportBatchOutcome: Sendable {
    let destinationName: String
    let documents: [NoteDocument]
    let failures: [WindowMarkdownImportFailure]
    let derivedRefreshWarnings: [String]
    let identityRecoveryWarnings: [String]
    let presentationWarning: String?
}

private enum WindowLibraryMutationError: LocalizedError {
    case folderMutationInProgress

    var errorDescription: String? {
        switch self {
        case .folderMutationInProgress:
            String(
                localized: "Another folder operation is already in progress.",
                table: "Localizable",
                bundle: .module
            )
        }
    }
}

struct WindowLibraryMutationContext {
    let assignmentID: UUID
    let vault: RegisteredVault
    let sourceScope: LibrarySourceScope
}

@MainActor
struct WindowLibraryMutationDependencies {
    typealias CurrencyAwareOperation = @MainActor @Sendable (
        DocumentTransitionCoordinator.Currency
    ) async throws -> Void

    let context: @MainActor () -> WindowLibraryMutationContext?
    let enqueueDocumentTransition: @MainActor (
        _ operation: @escaping CurrencyAwareOperation,
        _ didFail: @escaping @MainActor @Sendable (Error) -> Void,
        _ didFinish: @escaping @MainActor @Sendable () -> Void
    ) -> Void
    let flushEditors: @MainActor (UUID) async throws -> Void
    let flushActiveTarget: @MainActor (NoteMutationTarget) async throws -> Void
    let expectedRevision: @MainActor (NoteMutationTarget) throws -> DocumentFingerprint
    let committedNoteCreated: @MainActor (
        WorkspaceMutationOutcome<WorkspaceManagedNoteCommit>,
        @MainActor () -> Bool
    ) async -> Void
    let committedFolderCreated: @MainActor (WorkspaceMutationOutcome<VaultRelativeFolderPath>) async -> Void
    let committedFolderMoved: @MainActor (WorkspaceMutationOutcome<FolderMoveCommit>) async -> Void
    let committedNoteDuplicated: @MainActor (
        WorkspaceMutationOutcome<NoteDocument>,
        NoteMutationTarget,
        String
    ) async -> Void
    let committedNoteMoved: @MainActor (
        WorkspaceMutationOutcome<TriptychMoveCommit>,
        NoteMutationTarget
    ) async -> Void
    let committedSystemTrash: @MainActor (
        SystemTrashDeletionPreview,
        WorkspaceMutationOutcome<SystemTrashDeletionCommit>?
    ) async -> Void
    let importedDocumentsCommitted: @MainActor (RegisteredVault) async throws -> Void
    let presentImportOutcome: @MainActor (WindowMarkdownImportBatchOutcome) -> Void
    let presentSystemTrash: @MainActor (SystemTrashDeletionPreview) -> Void
    let clearPresentedAlert: @MainActor () -> Void
    let reportError: @MainActor (String) -> Void
    let reportInformation: @MainActor (String) -> Void
    let refreshTransactionRecovery: @MainActor () async -> Void
}

/// Owns Library mutation identity, operation serialization, cancellation, and
/// system-Trash retry state. WindowModel supplies only cross-feature projection,
/// navigation, and presentation callbacks after authoritative mutations.
@MainActor
final class WindowLibraryMutationController: ObservableObject {
    @Published private(set) var isCreatingNote = false
    @Published private(set) var isMutatingFolder = false

    private let dependencies: WindowLibraryMutationDependencies
    private var operations: (any LibraryMutationUseCases)?
    private var markdownImportTask: Task<Void, Never>?
    private var folderMutationTask: Task<Void, Never>?
    private var mutationTaskCancellations: [UUID: @MainActor () -> Void] = [:]

    init(dependencies: WindowLibraryMutationDependencies) {
        self.dependencies = dependencies
    }

    deinit {
        markdownImportTask?.cancel()
        folderMutationTask?.cancel()
    }

    func bind(to operations: any LibraryMutationUseCases) {
        cancelAll()
        self.operations = operations
    }

    func unbind() {
        cancelAll()
        operations = nil
    }

    func cancelAll() {
        markdownImportTask?.cancel()
        markdownImportTask = nil
        folderMutationTask?.cancel()
        folderMutationTask = nil
        mutationTaskCancellations.values.forEach { $0() }
        mutationTaskCancellations.removeAll()
    }

    func requestUntitledNoteCreation(in folderRelativePath: String?) {
        guard !isCreatingNote else { return }
        isCreatingNote = true
        dependencies.enqueueDocumentTransition({ [weak self] isCurrent in
            guard let self,
                  let context = self.dependencies.context(),
                  context.sourceScope == .library else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            let outcome = try await self.requireOperations().createUntitledNote(
                inVault: context.vault.id,
                folderRelativePath: folderRelativePath
            )
            await self.dependencies.committedNoteCreated(outcome, isCurrent)
        }, { [weak self] error in
            self?.dependencies.reportError(
                String(
                    localized: "Could not create note: \(error.localizedDescription)",
                    table: "Localizable",
                    bundle: .module
                )
            )
        }, { [weak self] in
            self?.isCreatingNote = false
        })
    }

    func requestUntitledFolderCreation(in parentRelativePath: String?) {
        guard !isMutatingFolder else { return }
        guard let context = dependencies.context(),
              context.sourceScope == .library else {
            dependencies.reportError(
                WorkspaceRegistryError.incompleteWorkspace.localizedDescription
            )
            return
        }
        isMutatingFolder = true
        folderMutationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.folderMutationTask = nil
                self.isMutatingFolder = false
            }
            do {
                let outcome = try await self.requireOperations().createUntitledFolder(
                    inVault: context.vault.id,
                    parentRelativePath: parentRelativePath
                )
                await self.dependencies.committedFolderCreated(outcome)
            } catch {
                self.dependencies.reportError(
                    String(
                        localized: "Could not create folder: \(error.localizedDescription)",
                        table: "Localizable",
                        bundle: .module
                    )
                )
            }
        }
    }

    func moveFolder(
        _ target: FolderMutationTarget,
        to destinationRelativePath: String
    ) async throws {
        try await withOwnedMutation { [self] in
            try await performMoveFolder(target, to: destinationRelativePath)
        }
    }

    private func performMoveFolder(
        _ target: FolderMutationTarget,
        to destinationRelativePath: String
    ) async throws {
        guard !isMutatingFolder else {
            throw WindowLibraryMutationError.folderMutationInProgress
        }
        guard let context = dependencies.context(),
              target.vaultID == context.vault.id else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        isMutatingFolder = true
        defer { isMutatingFolder = false }
        try await dependencies.flushEditors(context.assignmentID)
        do {
            let outcome = try await requireOperations().moveFolder(
                inVault: target.vaultID,
                from: target.relativePath,
                to: destinationRelativePath
            )
            await dependencies.committedFolderMoved(outcome)
        } catch {
            await dependencies.refreshTransactionRecovery()
            throw error
        }
    }

    func prepareFolderSystemTrash(_ target: FolderMutationTarget) async throws {
        try await withOwnedMutation { [self] in
            try await performPrepareFolderSystemTrash(target)
        }
    }

    private func performPrepareFolderSystemTrash(
        _ target: FolderMutationTarget
    ) async throws {
        guard !isMutatingFolder else {
            throw WindowLibraryMutationError.folderMutationInProgress
        }
        guard let context = dependencies.context() else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        isMutatingFolder = true
        defer { isMutatingFolder = false }
        try await dependencies.flushEditors(context.assignmentID)
        dependencies.presentSystemTrash(
            try await requireOperations().prepareFolderSystemTrash(
                inVault: target.vaultID,
                relativePath: target.relativePath
            )
        )
    }

    @discardableResult
    func duplicateNote(
        _ target: NoteMutationTarget,
        to requestedPath: String
    ) async throws -> NoteDocument {
        try await withOwnedMutation { [self] in
            try await performDuplicateNote(target, to: requestedPath)
        }
    }

    private func performDuplicateNote(
        _ target: NoteMutationTarget,
        to requestedPath: String
    ) async throws -> NoteDocument {
        guard dependencies.context() != nil else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await dependencies.flushActiveTarget(target)
        let authorizedTarget = try currentTarget(target)
        let destination = Self.markdownPath(requestedPath)
        let outcome = try await requireOperations().duplicate(
            authorizedTarget,
            to: destination
        )
        await dependencies.committedNoteDuplicated(outcome, target, destination)
        return outcome.committedValue
    }

    func moveNote(
        _ target: NoteMutationTarget,
        to requestedPath: String
    ) async throws {
        try await withOwnedMutation { [self] in
            try await performMoveNote(target, to: requestedPath)
        }
    }

    private func performMoveNote(
        _ target: NoteMutationTarget,
        to requestedPath: String
    ) async throws {
        guard dependencies.context() != nil else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await dependencies.flushActiveTarget(target)
        let authorizedTarget = try currentTarget(target)
        do {
            let outcome = try await requireOperations().move(
                authorizedTarget,
                to: Self.markdownPath(requestedPath)
            )
            await dependencies.committedNoteMoved(outcome, target)
        } catch {
            await dependencies.refreshTransactionRecovery()
            throw error
        }
    }

    func prepareNoteSystemTrash(_ target: NoteMutationTarget) async throws {
        try await withOwnedMutation { [self] in
            try await performPrepareNoteSystemTrash(target)
        }
    }

    private func performPrepareNoteSystemTrash(
        _ target: NoteMutationTarget
    ) async throws {
        guard let context = dependencies.context() else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await dependencies.flushEditors(context.assignmentID)
        let authorizedTarget = try currentTarget(target)
        dependencies.presentSystemTrash(
            try await requireOperations().prepareSystemTrash(authorizedTarget)
        )
    }

    func executeSystemTrash(_ preview: SystemTrashDeletionPreview) async throws {
        try await withOwnedMutation { [self] in
            try await performSystemTrash(preview)
        }
    }

    private func performSystemTrash(
        _ preview: SystemTrashDeletionPreview
    ) async throws {
        guard let context = dependencies.context(),
              preview.sources.first?.vaultID != nil else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await dependencies.flushEditors(context.assignmentID)
        do {
            let outcome = try await requireOperations().moveToSystemTrash(preview)
            await dependencies.committedSystemTrash(preview, outcome)
        } catch {
            await dependencies.refreshTransactionRecovery()
            await dependencies.committedSystemTrash(preview, nil)
            throw error
        }
    }

    func requestMarkdownImport(_ urls: [URL]) {
        guard markdownImportTask == nil else {
            dependencies.reportInformation(
                String(
                    localized: "A Markdown import is already in progress.",
                    table: "Localizable",
                    bundle: .module
                )
            )
            return
        }
        markdownImportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.markdownImportTask = nil }
            do {
                self.dependencies.presentImportOutcome(
                    try await self.importMarkdownFiles(urls)
                )
            } catch is CancellationError {
                return
            } catch {
                self.dependencies.reportError(error.localizedDescription)
            }
        }
    }

    func recoverInterruptedTransactions() async throws -> [String] {
        try await requireOperations().recoverInterruptedTransactions()
    }

    func importMarkdownFiles(
        _ urls: [URL]
    ) async throws -> WindowMarkdownImportBatchOutcome {
        guard let context = dependencies.context() else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        var imported: [NoteDocument] = []
        var failures: [WindowMarkdownImportFailure] = []
        var derivedRefreshWarnings: [String] = []
        var identityRecoveryWarnings: [String] = []
        for url in urls {
            try Task.checkCancellation()
            guard dependencies.context()?.assignmentID == context.assignmentID else {
                throw CancellationError()
            }
            do {
                let outcome = try await requireOperations().importMarkdown(
                    at: url,
                    intoVault: context.vault.id
                )
                imported.append(outcome.committedValue)
                if let warning = outcome.derivedRefreshWarning {
                    derivedRefreshWarnings.append(warning)
                }
                if let warning = outcome.identityRecoveryWarning {
                    identityRecoveryWarnings.append(warning)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(WindowMarkdownImportFailure(
                    sourceName: url.lastPathComponent,
                    reason: error.localizedDescription
                ))
            }
        }
        var presentationWarning: String?
        if !imported.isEmpty {
            do {
                try await dependencies.importedDocumentsCommitted(context.vault)
            } catch {
                presentationWarning = error.localizedDescription
            }
        }
        return WindowMarkdownImportBatchOutcome(
            destinationName: context.vault.name,
            documents: imported,
            failures: failures,
            derivedRefreshWarnings: derivedRefreshWarnings,
            identityRecoveryWarnings: identityRecoveryWarnings,
            presentationWarning: presentationWarning
        )
    }

    private func currentTarget(
        _ target: NoteMutationTarget
    ) throws -> NoteMutationTarget {
        NoteMutationTarget(
            documentID: target.documentID,
            stableNoteID: target.stableNoteID,
            revision: try dependencies.expectedRevision(target)
        )
    }

    private func requireOperations() throws -> any LibraryMutationUseCases {
        guard let operations else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return operations
    }

    private static func markdownPath(_ requestedPath: String) -> String {
        let trimmed = requestedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasSuffix(".md") ? trimmed : trimmed + ".md"
    }

    private func withOwnedMutation<T: Sendable>(
        _ operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        let operationID = UUID()
        let task = Task { try await operation() }
        mutationTaskCancellations[operationID] = { task.cancel() }
        defer { mutationTaskCancellations[operationID] = nil }
        return try await withTaskCancellationHandler {
            let value = try await task.value
            if task.isCancelled { throw CancellationError() }
            return value
        } onCancel: {
            task.cancel()
        }
    }
}
