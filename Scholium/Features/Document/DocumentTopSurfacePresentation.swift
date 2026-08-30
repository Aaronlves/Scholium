/// Resolves the single task or notice that may own the top of the Document.
/// Durable Review and Action activity state remain with their existing owners;
/// this value defines presentation priority only.
enum DocumentTopSurfacePresentation: Equatable {
    case noteReviewTask
    case persistentFeedback
    case actionNotificationStack
    case notificationPermissionNotice
    case none

    static func resolve(
        noteReviewTaskIsPresented: Bool,
        hasPersistentFeedback: Bool,
        hasActionNotifications: Bool,
        hasNotificationPermissionNotice: Bool
    ) -> Self {
        if noteReviewTaskIsPresented { return .noteReviewTask }
        if hasPersistentFeedback { return .persistentFeedback }
        if hasActionNotifications { return .actionNotificationStack }
        if hasNotificationPermissionNotice { return .notificationPermissionNotice }
        return .none
    }
}
