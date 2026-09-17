import Combine
import CoreFoundation
import Foundation

/// Machine-local writing assistance, independent of conversation preferences.
@MainActor
final class WritingContinuationPreferences: ObservableObject {
    static let shared = WritingContinuationPreferences()
    static let enabledKey = "scholium.writingContinuation.enabled"
    static let modelKey = "scholium.writingContinuation.model"
    static let defaultModel = "gpt-5.6-luna"

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Self.enabledKey) }
    }
    @Published var model: String {
        didSet { defaults.set(model, forKey: Self.modelKey) }
    }
    @Published private(set) var loadError: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawEnabled = defaults.object(forKey: Self.enabledKey)
        let rawModel = defaults.object(forKey: Self.modelKey)
        let boolean = rawEnabled as? NSNumber
        let validBoolean = boolean.map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        enabled = validBoolean ? boolean!.boolValue : false
        let storedModel = rawModel as? String
        let validModel = storedModel.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        model = validModel ? storedModel! : Self.defaultModel
        if (rawEnabled != nil && !validBoolean) || (rawModel != nil && !validModel) {
            loadError = ScholiumL10n.string(
                "Some writing assistance settings could not be loaded. Defaults are used for unavailable values; saved settings remain unchanged until edited or restored."
            )
        }
    }

    func restoreDefaults() {
        enabled = false
        model = Self.defaultModel
        defaults.removeObject(forKey: Self.enabledKey)
        defaults.removeObject(forKey: Self.modelKey)
        loadError = nil
    }
}
