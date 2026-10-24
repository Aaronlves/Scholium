import Combine
import Foundation
import ScholiumContracts

/// Owns one receipt's asynchronous presentation. Only the Application's bound
/// result proves Undo; refreshing projections never changes that result.
@MainActor
final class AgentChangeReceiptSession: ObservableObject {
    typealias ReviewLoader = @MainActor (UUID) async throws -> AgentChangeReview
    typealias Undo = @MainActor (AgentChange) async throws -> AgentChangeUndoResult
    typealias Refresh = @MainActor () async throws -> Void

    let changeID: UUID
    @Published private(set) var review: AgentChangeReview?
    @Published private(set) var isLoading = true
    @Published private(set) var isUndoing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionErrorMessage: String?
    @Published private(set) var refreshWarning: String?
    @Published private(set) var undoResult: AgentChangeUndoResult?
    private var unverifiedUndoResult = false
    private var isClosed = false
    private var lifetime = UUID()
    private var loadRequest: UUID?

    init(changeID: UUID) { self.changeID = changeID }

    var canUndo: Bool {
        !isClosed && undoResult == nil && !unverifiedUndoResult
            && !isLoading && !isUndoing && errorMessage == nil && review?.isDirectUndoAvailable == true
    }

    func reload(using loadReview: ReviewLoader, refreshAfterUndo: Refresh = {}) async {
        guard !isClosed else { return }
        let request = UUID()
        let origin = lifetime
        loadRequest = request
        isLoading = true
        errorMessage = nil
        refreshWarning = nil
        if undoResult != nil { review = nil }
        func isCurrent() -> Bool { !isClosed && lifetime == origin && loadRequest == request }
        defer { if isCurrent() { isLoading = false } }

        if undoResult != nil {
            do { try await refreshAfterUndo() } catch {
                guard isCurrent() else { return }
                refreshWarning = refreshMessage(error)
            }
        }
        guard isCurrent() else { return }
        do {
            let loaded = try await loadReview(changeID)
            guard isCurrent() else { return }
            try Task.checkCancellation()
            guard loaded.change.id == changeID else { throw AgentChangeError.mismatchedBinding(changeID) }
            if undoResult != nil && loaded.change.state != .undone {
                throw ReceiptRefreshError.completedUndoNotReflected
            }
            review = loaded
        } catch {
            guard isCurrent() else { return }
            review = nil
            if undoResult != nil {
                if refreshWarning == nil { refreshWarning = refreshMessage(error) }
            } else if !(error is CancellationError) {
                errorMessage = ScholiumErrorLocalization.message(error)
            }
        }
    }

    func undoChange(
        _ change: AgentChange, undo: Undo, loadReview: ReviewLoader, refreshAfterUndo: Refresh = {}
    ) async {
        guard canUndo, review?.change == change, change.id == changeID else { return }
        let origin = lifetime
        isUndoing = true
        actionErrorMessage = nil
        defer { if !isClosed && lifetime == origin { isUndoing = false } }
        do {
            try Task.checkCancellation()
            let result = try await undo(change)
            guard !isClosed && lifetime == origin else { return }
            // A malformed response cannot prove completion or authorize replay.
            guard result.changeID == change.id, result.noteID == change.noteID,
                result.restoredFingerprint == change.beforeFingerprint
            else {
                unverifiedUndoResult = true
                throw AgentChangeError.mismatchedBinding(change.id)
            }
            undoResult = result
            isUndoing = false
            await reload(using: loadReview, refreshAfterUndo: refreshAfterUndo)
        } catch {
            guard !isClosed && lifetime == origin else { return }
            if !(error is CancellationError) { actionErrorMessage = ScholiumErrorLocalization.message(error) }
        }
    }

    /// Closing revokes presentation, not an already admitted source operation.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        lifetime = UUID()
        loadRequest = nil
        isLoading = false
        isUndoing = false
    }

    private func refreshMessage(_ error: any Error) -> String {
        if error is CancellationError {
            return String(localized: "Receipt refresh was interrupted.", table: "Localizable", bundle: .module)
        }
        return ScholiumErrorLocalization.message(error)
    }
}

private enum ReceiptRefreshError: LocalizedError {
    case completedUndoNotReflected
    var errorDescription: String? {
        String(localized: "The refreshed receipt does not yet show the completed Undo.", table: "Localizable", bundle: .module)
    }
}
