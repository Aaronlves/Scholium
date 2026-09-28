import Foundation
import ScholiumContracts
import ScholiumCore

/// Settings access for a selected registered Triptych. It never opens or
/// activates a vault, and only touches machine-local Changes metadata.
public actor DocumentChangeArchiveOperations {
    private let store: DocumentReviewStore
    private let receipts: AgentChangeStore
    private let runtime: WorkspaceRuntime
    private let triptychID: UUID

    init(
        store: DocumentReviewStore, receipts: AgentChangeStore,
        runtime: WorkspaceRuntime, triptychID: UUID
    ) {
        self.store = store
        self.receipts = receipts
        self.runtime = runtime
        self.triptychID = triptychID
    }

    public func retention() async throws -> DocumentChangeRetention {
        try await store.retention()
    }

    public func setRetention(_ retention: DocumentChangeRetention) async throws {
        do {
            try await store.setRetention(retention)
        } catch {
            await runtime.publishDocumentChangesChanged(triptychID: triptychID)
            throw error
        }
        do {
            _ = try await store.expireHistory()
        } catch {
            await runtime.publishDocumentChangesChanged(triptychID: triptychID)
            throw DocumentChangeError.historyChangedCleanupPending(error.localizedDescription)
        }
        try await runtime.finishDocumentChangesCleanup(triptychID: triptychID)
    }

    public func reviewedHistory() async throws -> [ReviewedDocumentChange] {
        let expired: Bool
        do {
            expired = try await store.expireHistory()
        } catch {
            await runtime.publishDocumentChangesChanged(triptychID: triptychID)
            throw error
        }
        if expired {
            try await runtime.finishDocumentChangesCleanup(triptychID: triptychID)
        }
        return try await store.history()
    }

    public func deleteReviewedHistory(ids: [UUID]) async throws {
        do {
            try await store.deleteHistory(ids: Set(ids))
        } catch {
            await runtime.publishDocumentChangesChanged(triptychID: triptychID)
            throw error
        }
        try await runtime.finishDocumentChangesCleanup(triptychID: triptychID)
    }

    public func clearReviewedHistory() async throws {
        do {
            try await store.clearHistory()
        } catch {
            await runtime.publishDocumentChangesChanged(triptychID: triptychID)
            throw error
        }
        try await runtime.finishDocumentChangesCleanup(triptychID: triptychID)
    }

    public func historyUsage() async throws -> DocumentChangeHistoryUsage {
        let usage = try await store.historyUsage()
        let receiptBytes = try await receipts.retainedByteCount()
        return DocumentChangeHistoryUsage(
            count: usage.count, byteCount: usage.byteCount,
            protectedByteCount: usage.protectedByteCount + receiptBytes
        )
    }
}
