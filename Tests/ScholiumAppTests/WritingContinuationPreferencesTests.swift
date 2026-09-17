import Foundation
import Testing

@testable import ScholiumApp

@Suite("Writing continuation preferences")
@MainActor
struct WritingContinuationPreferencesTests {
    @Test("AI is opt-in and initializing preferences writes no settings")
    func defaultsAreNonMutating() throws {
        let domain = "writing-continuation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = WritingContinuationPreferences(defaults: defaults)
        #expect(!preferences.enabled)
        #expect(preferences.model == WritingContinuationPreferences.defaultModel)
        #expect(defaults.object(forKey: WritingContinuationPreferences.enabledKey) == nil)
        #expect(defaults.object(forKey: WritingContinuationPreferences.modelKey) == nil)
    }

    @Test("Enabled state and independent model persist; disabling retains the chosen model")
    func persistsWithoutChangingOtherPreferences() throws {
        let domain = "writing-continuation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("queue", forKey: AgentChatInputBehavior.key)
        let preferences = WritingContinuationPreferences(defaults: defaults)
        preferences.enabled = true
        preferences.model = "fixture-low-cost-model"
        let reopened = WritingContinuationPreferences(defaults: defaults)
        #expect(reopened.enabled)
        #expect(reopened.model == "fixture-low-cost-model")
        reopened.enabled = false
        #expect(WritingContinuationPreferences(defaults: defaults).model == "fixture-low-cost-model")
        #expect(defaults.string(forKey: AgentChatInputBehavior.key) == "queue")
    }

    @Test("An unavailable model identifier is preserved rather than substituted")
    func preservesUnknownModel() throws {
        let domain = "writing-continuation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("model-not-in-current-inventory", forKey: WritingContinuationPreferences.modelKey)
        let preferences = WritingContinuationPreferences(defaults: defaults)
        #expect(preferences.model == "model-not-in-current-inventory")
        #expect(defaults.string(forKey: WritingContinuationPreferences.modelKey) == preferences.model)
    }
    @Test("Malformed enablement cannot opt in to AI and recovery leaves unrelated preferences unchanged")
    func malformedBoolean() throws {
        let domain = "writing-continuation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("YES", forKey: WritingContinuationPreferences.enabledKey)
        defaults.set("chosen-model", forKey: WritingContinuationPreferences.modelKey)
        defaults.set("queue", forKey: AgentChatInputBehavior.key)
        let preferences = WritingContinuationPreferences(defaults: defaults)
        #expect(!preferences.enabled && preferences.model == "chosen-model")
        #expect(preferences.loadError != nil)
        #expect(defaults.string(forKey: WritingContinuationPreferences.enabledKey) == "YES")
        preferences.restoreDefaults()
        #expect(preferences.loadError == nil && !preferences.enabled)
        #expect(defaults.object(forKey: WritingContinuationPreferences.enabledKey) == nil)
        #expect(defaults.string(forKey: AgentChatInputBehavior.key) == "queue")
    }

}
