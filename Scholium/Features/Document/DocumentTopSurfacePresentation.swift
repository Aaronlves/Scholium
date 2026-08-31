/// Resolves the single window-level notice that may cover the Document top.
/// Durable Action activity state remains with its existing owner; this value
/// defines presentation priority only.
enum DocumentTopSurfacePresentation: Equatable {
    case persistentFeedback
    case researchNotifications
    case notificationPermissionNotice
    case none

    static func resolve(
        hasPersistentFeedback: Bool,
        hasActionNotifications: Bool,
        hasSettlementReminder: Bool,
        hasNotificationPermissionNotice: Bool
    ) -> Self {
        if hasPersistentFeedback { return .persistentFeedback }
        if hasActionNotifications || hasSettlementReminder {
            return .researchNotifications
        }
        if hasNotificationPermissionNotice { return .notificationPermissionNotice }
        return .none
    }
}
