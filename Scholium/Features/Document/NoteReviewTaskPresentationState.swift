import Foundation
import ScholiumContracts

/// Session-only presentation for the current Note Review task. Durable Review
/// truth remains in the portable Note Review store; this value remembers only
/// whether one exact pending-activity set is visible or was dismissed in this
/// retained Document session.
struct NoteReviewTaskPresentationState: Equatable, Sendable {
    struct Identity: Equatable, Hashable, Sendable {
        let noteID: UUID
        let activityIDs: [String]

        init?(_ reviewState: WorkspaceNoteReviewState?) {
            guard let reviewState,
                  reviewState.status == .needsReview,
                  !reviewState.pendingActivities.isEmpty else { return nil }
            noteID = reviewState.noteID
            activityIDs = reviewState.pendingActivities.map(\.id).sorted()
        }
    }

    private(set) var presentedIdentity: Identity?
    private(set) var dismissedIdentity: Identity?

    var isPresented: Bool { presentedIdentity != nil }

    func isPresented(for noteID: UUID?) -> Bool {
        guard let noteID else { return false }
        return presentedIdentity?.noteID == noteID
    }

    mutating func reconcile(_ reviewState: WorkspaceNoteReviewState?) {
        guard let identity = Identity(reviewState) else {
            presentedIdentity = nil
            dismissedIdentity = nil
            return
        }
        if dismissedIdentity == identity {
            presentedIdentity = nil
            return
        }
        presentedIdentity = identity
    }

    mutating func present(_ reviewState: WorkspaceNoteReviewState?) {
        guard let identity = Identity(reviewState) else { return }
        dismissedIdentity = nil
        presentedIdentity = identity
    }

    mutating func dismiss(_ reviewState: WorkspaceNoteReviewState?) {
        guard let identity = Identity(reviewState) else {
            presentedIdentity = nil
            return
        }
        dismissedIdentity = identity
        presentedIdentity = nil
    }

    mutating func complete() {
        presentedIdentity = nil
        dismissedIdentity = nil
    }
}
