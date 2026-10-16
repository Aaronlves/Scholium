import Foundation
import ScholiumContracts
import ScholiumCore

extension WorkspaceHandle {
    /// Every explicit rebuild uses the existing refresh capture/publication
    /// owner. Concurrent opens join it instead of starting duplicate work.
    func rebuildSearchIndex() async throws -> WorkspaceSnapshot {
        pendingSearchActivationToken = nil
        try await services.searchIndexOwner.retryFailedAdmission()
        let task = try startIndexRebuild()
        return try await task.value
    }

    /// Library activation resumes a cleared index without delaying source-ready
    /// live presentation. The same owned task is joined by explicit rebuilds.
    func resumeSearchIndexForActivation() async throws {
        try requireActive()
        try Task.checkCancellation()
        if mode == .live, !currentSnapshot.phase.isComplete {
            pendingSearchActivationToken = UUID()
            return
        }
        try await services.searchIndexOwner.retryFailedAdmission()
        let deferred = try await services.searchIndex.hasDeferredRebuild
        try Task.checkCancellation()
        guard deferred else { return }
        let task = try startIndexRebuild()
        if mode == .snapshot { _ = try await task.value }
    }

    /// Runs before the completion coordinator, never from inside its attempt.
    /// A later Clear consumes the activation intent while admission is pending.
    func admitSearchForOpeningCompletion() async throws {
        let index = try await services.searchIndex
        try requireActive()
        try Task.checkCancellation()
        while let intent = pendingSearchActivationToken {
            let deferred = try await index.hasDeferredRebuild
            try requireActive()
            try Task.checkCancellation()
            guard pendingSearchActivationToken == intent else { continue }
            pendingSearchActivationToken = nil
            if deferred {
                let task = try startIndexRebuild()
                _ = try await task.value
            }
            return
        }
    }

    private func startIndexRebuild() throws -> Task<WorkspaceSnapshot, Error> {
        try requireActive()
        if let indexRebuildTask { return indexRebuildTask }
        let task = Task(priority: .utility) {
            defer { indexRebuildTask = nil }
            return try await refreshCoordinator.request(
                WorkspaceRefreshPayload(
                    publication: .explicit, failureDisposition: .failed(affectedVaultIDs: []),
                    sourceCatalogPreparation: .rebuild, indexMaintenance: .rebuild))
        }
        indexRebuildTask = task
        return task
    }

    func clearSearchIndex() async throws -> (SearchIndexClearResult, String?) {
        try requireActive()
        pendingSearchActivationToken = nil
        latestIndexClearResult = nil
        do {
            _ = try await refreshCoordinator.request(
                WorkspaceRefreshPayload(
                    publication: .explicit, failureDisposition: .failed(affectedVaultIDs: []),
                    sourceCatalogPreparation: .none, indexMaintenance: .clear))
        } catch {
            // Clear commits before the derived Graph refresh. An error in that
            // later work cannot claim that the index deletion was rolled back.
            if let latestIndexClearResult { return (latestIndexClearResult, error.localizedDescription) }
            throw error
        }
        guard let latestIndexClearResult else { throw CancellationError() }
        return (latestIndexClearResult, nil)
    }
}
