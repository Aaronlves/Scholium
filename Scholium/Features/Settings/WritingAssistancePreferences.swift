import Combine
import CoreFoundation
import Foundation

/// Machine-local writing assistance, independent of conversation preferences.
@MainActor
final class WritingAssistancePreferences: ObservableObject {
    static let shared = WritingAssistancePreferences()
    static let enabledKey = "scholium.writingContinuation.enabled"
    static let modelKey = "scholium.writingContinuation.model"
    static let effortKey = "scholium.writingContinuation.effort"
    static let defaultModel = "gpt-5.6-luna"

    @Published var continuationEnabled: Bool {
        didSet {
            defaults.set(continuationEnabled, forKey: Self.enabledKey)
            invalidStoredKeys.remove(Self.enabledKey)
        }
    }
    @Published var model: String {
        didSet {
            defaults.set(model, forKey: Self.modelKey)
            if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                invalidStoredKeys.insert(Self.modelKey)
            } else {
                invalidStoredKeys.remove(Self.modelKey)
            }
        }
    }
    /// Nil follows the selected model's fastest advertised effort. Explicit
    /// values remain intact when a different connection cannot support them.
    @Published var continuationEffort: String? {
        didSet {
            if let continuationEffort {
                defaults.set(continuationEffort, forKey: Self.effortKey)
                if continuationEffort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    invalidStoredKeys.insert(Self.effortKey)
                } else {
                    invalidStoredKeys.remove(Self.effortKey)
                }
            } else {
                defaults.removeObject(forKey: Self.effortKey)
                invalidStoredKeys.remove(Self.effortKey)
            }
        }
    }
    @Published private(set) var invalidStoredKeys: Set<String>
    private let defaults: UserDefaults

    var continuationEffortIsValid: Bool { !invalidStoredKeys.contains(Self.effortKey) }

    /// The existing editor invalidation channel binds both pieces of generation
    /// configuration. The length prefix keeps arbitrary model IDs unambiguous.
    var continuationContextKey: String {
        let effort = continuationEffort.map { "explicit:\($0)" } ?? "automatic"
        return "\(model.utf8.count):\(model)|\(effort)"
    }

    var loadError: String? {
        guard !invalidStoredKeys.isEmpty else { return nil }
        return ScholiumL10n.string(
            "Some writing assistance settings could not be loaded. Saved settings remain unchanged until edited or restored."
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawEnabled = defaults.object(forKey: Self.enabledKey)
        let rawModel = defaults.object(forKey: Self.modelKey)
        let rawEffort = defaults.object(forKey: Self.effortKey)
        let boolean = rawEnabled as? NSNumber
        let validBoolean = boolean.map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        continuationEnabled = validBoolean ? boolean!.boolValue : false
        let storedModel = rawModel as? String
        let validModel = storedModel.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        model = validModel ? storedModel! : Self.defaultModel
        // A malformed explicit value must not become Automatic. Its stored
        // bytes remain untouched until the researcher chooses a replacement.
        continuationEffort = rawEffort == nil ? nil : (rawEffort as? String ?? "")
        invalidStoredKeys = []
        if rawEffort != nil && (continuationEffort?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false) {
            invalidStoredKeys.insert(Self.effortKey)
        }
        if rawEnabled != nil && !validBoolean { invalidStoredKeys.insert(Self.enabledKey) }
        if rawModel != nil && !validModel { invalidStoredKeys.insert(Self.modelKey) }
    }

    func restoreDefaults() {
        continuationEnabled = false
        model = Self.defaultModel
        continuationEffort = nil
        defaults.removeObject(forKey: Self.enabledKey)
        defaults.removeObject(forKey: Self.modelKey)
        invalidStoredKeys = []
    }
}
