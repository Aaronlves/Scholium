import Foundation
import ScholiumContracts

/// Sequential orchestration; source policy and durable transactions stay in the
/// existing mutation use cases. Stop at the first failure or uncertain outcome.
@MainActor
enum LibraryNoteBatchExecution {
    static func move(
        _ request: LibraryNoteBatchRequest, toFolder folder: String,
        isCurrent: () -> Bool,
        move: (NoteMutationTarget, String) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit>,
        didCommit: (WorkspaceMutationOutcome<TriptychMoveCommit>, NoteMutationTarget) async -> Void,
        didFail: () async -> Void
    ) async -> LibraryNoteBatchOutcome {
        var targets = request.targets
        var results: [LibraryNoteBatchItemResult] = []
        var warnings: [String] = []
        var requiresRecovery = false
        var stopped = false
        var staleTargets = Set<UUID>()
        for index in targets.indices {
            let target = targets[index]
            let filename = (target.relativePath as NSString).lastPathComponent
            let destination = folder.isEmpty ? filename : folder + "/" + filename
            let status: LibraryNoteBatchItemStatus
            if staleTargets.contains(target.stableNoteID) {
                status = .failed(LibraryNoteBatchError.revisionChainChanged.localizedDescription)
                stopped = true
            } else if stopped {
                status = .unattempted
            } else if Task.isCancelled || !isCurrent() {
                status = .cancelled
                stopped = true
            } else {
                do {
                    let outcome = try await move(target, destination)
                    let commit = outcome.committedValue
                    // Preserve success even if publication, context, or cancellation
                    // changes after the authoritative operation returned.
                    status = .succeeded
                    warnings.append(contentsOf: [outcome.derivedRefreshWarning, outcome.identityRecoveryWarning].compactMap { $0 })
                    for next in targets.indices where next > index {
                        let pending = targets[next]
                        let rewrites = commit.rewrites.filter { $0.note == pending.documentID }
                        for rewrite in rewrites {
                            guard rewrite.previousRevision == targets[next].revision else {
                                staleTargets.insert(pending.stableNoteID)
                                break
                            }
                            targets[next] = NoteMutationTarget(
                                documentID: pending.documentID, stableNoteID: pending.stableNoteID,
                                revision: rewrite.committedRevision)
                        }
                    }
                    await didCommit(outcome, target)
                    if !staleTargets.isEmpty { stopped = true }
                    if outcome.identityRecoveryWarning != nil {
                        requiresRecovery = true
                        stopped = true
                    }
                } catch {
                    await didFail()
                    requiresRecovery = recoveryRecord(error) != nil
                    status =
                        requiresRecovery
                        ? .outcomeUnknown(error.localizedDescription)
                        : error is CancellationError ? .cancelled : .failed(error.localizedDescription)
                    stopped = true
                }
            }
            results.append(.init(target: target, destinationRelativePath: destination, status: status))
        }
        return LibraryNoteBatchOutcome(
            request: request, operation: .move(folderRelativePath: folder), items: results,
            recoveryRequired: requiresRecovery, warnings: warnings)
    }

    static func failure(
        _ request: LibraryNoteBatchRequest, operation: LibraryNoteBatchOperation, error: Error
    ) -> LibraryNoteBatchOutcome {
        LibraryNoteBatchOutcome(
            request: request, operation: operation,
            items: request.targets.enumerated().map { index, target in
                .init(
                    target: target, destinationRelativePath: nil,
                    status: index == 0 ? (error is CancellationError ? .cancelled : .failed(error.localizedDescription)) : .unattempted)
            },
            recoveryRequired: recoveryRecord(error) != nil, warnings: [])
    }

    static func trashFailure(
        _ request: LibraryNoteBatchRequest, preview: SystemTrashDeletionPreview, error: Error
    ) -> LibraryNoteBatchOutcome {
        guard let record = recoveryRecord(error), let plan = record.systemTrashDeletionPlan,
            plan.id == preview.id
        else { return failure(request, operation: .systemTrash, error: error) }
        var markedFailure = false
        let results: [LibraryNoteBatchItemResult] = request.targets.map { target in
            let source = preview.sources.first { $0.notes.contains { $0.noteID == target.stableNoteID } }
            let receipt = plan.sourceReceipts.first { $0.targetID == source?.id }
            let status: LibraryNoteBatchItemStatus
            switch receipt?.progress {
            case .movedToSystemTrash:
                status = .succeeded
            case .outcomeUnknown:
                status = .outcomeUnknown(error.localizedDescription)
                markedFailure = true
            case .pending:
                status = markedFailure ? .unattempted : .failed(error.localizedDescription)
                markedFailure = true
            case nil:
                status = .outcomeUnknown(error.localizedDescription)
                markedFailure = true
            }
            return .init(target: target, destinationRelativePath: nil, status: status)
        }
        return LibraryNoteBatchOutcome(
            request: request, operation: .systemTrash, items: results,
            recoveryRequired: true, warnings: [error.localizedDescription])
    }

    private static func recoveryRecord(_ error: Error) -> TriptychMutationRecoveryRecord? {
        guard let error = error as? TriptychTransactionError else { return nil }
        return switch error {
        case .recoveryRequired(let record), .recoveryPersistenceFailed(let record, _): record
        default: nil
        }
    }
}
