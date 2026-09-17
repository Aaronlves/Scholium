import Combine
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
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: Self.enabledKey)
        model = defaults.string(forKey: Self.modelKey) ?? Self.defaultModel
    }
}
