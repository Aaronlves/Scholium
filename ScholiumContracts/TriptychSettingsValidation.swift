import Foundation

public enum TriptychSettingsValidationError: LocalizedError, Equatable, Sendable {
    case invalidAttentionDismissalDays
    public var errorDescription: String? { "Attention dismissal days must be positive." }
}

public enum TriptychSettingsValidator {
    public static func validate(_ settings: TriptychSettings) throws {
        guard settings.attentionDismissalDays > 0 else {
            throw TriptychSettingsValidationError.invalidAttentionDismissalDays
        }
    }
}
