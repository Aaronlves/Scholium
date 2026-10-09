import Foundation
import Testing

@testable import ScholiumApp

@Suite("Writing continuation preferences")
@MainActor
struct WritingAssistancePreferencesTests {
    @Test("AI is opt-in and initializing preferences writes no settings")
    func defaultsAreNonMutating() throws {
        let domain = "writing-continuation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = WritingAssistancePreferences(defaults: defaults)
        #expect(!preferences.continuationEnabled)
        #expect(preferences.model == WritingAssistancePreferences.defaultModel)
        #expect(defaults.object(forKey: WritingAssistancePreferences.enabledKey) == nil)
        #expect(defaults.object(forKey: WritingAssistancePreferences.modelKey) == nil)
    }

    @Test("Enabled state and independent model persist; disabling retains the chosen model")
    func persistsWithoutChangingOtherPreferences() throws {
        let domain = "writing-continuation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("queue", forKey: AgentChatInputBehavior.key)
        let preferences = WritingAssistancePreferences(defaults: defaults)
        preferences.continuationEnabled = true
        preferences.model = "fixture-low-cost-model"
        let reopened = WritingAssistancePreferences(defaults: defaults)
        #expect(reopened.continuationEnabled)
        #expect(reopened.model == "fixture-low-cost-model")
        reopened.continuationEnabled = false
        #expect(WritingAssistancePreferences(defaults: defaults).model == "fixture-low-cost-model")
        #expect(defaults.string(forKey: AgentChatInputBehavior.key) == "queue")
    }

    @Test("An unavailable model identifier is preserved rather than substituted")
    func preservesUnknownModel() throws {
        let domain = "writing-continuation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("model-not-in-current-inventory", forKey: WritingAssistancePreferences.modelKey)
        let preferences = WritingAssistancePreferences(defaults: defaults)
        #expect(preferences.model == "model-not-in-current-inventory")
        #expect(defaults.string(forKey: WritingAssistancePreferences.modelKey) == preferences.model)
    }
    @Test("Malformed enablement cannot opt in to AI and recovery leaves unrelated preferences unchanged")
    func malformedBoolean() throws {
        let domain = "writing-continuation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("YES", forKey: WritingAssistancePreferences.enabledKey)
        defaults.set("chosen-model", forKey: WritingAssistancePreferences.modelKey)
        defaults.set("queue", forKey: AgentChatInputBehavior.key)
        let preferences = WritingAssistancePreferences(defaults: defaults)
        #expect(!preferences.continuationEnabled && preferences.model == "chosen-model")
        #expect(preferences.loadError != nil)
        #expect(defaults.string(forKey: WritingAssistancePreferences.enabledKey) == "YES")
        preferences.restoreDefaults()
        #expect(preferences.loadError == nil && !preferences.continuationEnabled)
        #expect(defaults.object(forKey: WritingAssistancePreferences.enabledKey) == nil)
        #expect(defaults.string(forKey: AgentChatInputBehavior.key) == "queue")
    }

    @Test("Repairing one invalid field clears its warning and preserves the valid peer", arguments: [true, false])
    func repairingInvalidField(repairEnabled: Bool) throws {
        let domain = "writing-continuation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: WritingAssistancePreferences.enabledKey)
        defaults.set("chosen-model", forKey: WritingAssistancePreferences.modelKey)
        if repairEnabled {
            defaults.set("YES", forKey: WritingAssistancePreferences.enabledKey)
        } else {
            defaults.set(17, forKey: WritingAssistancePreferences.modelKey)
        }
        let preferences = WritingAssistancePreferences(defaults: defaults)
        #expect(preferences.loadError != nil)
        if repairEnabled {
            preferences.continuationEnabled = true
        } else {
            preferences.model = "chosen-model"
        }
        #expect(preferences.loadError == nil)
        #expect(preferences.continuationEnabled)
        #expect(preferences.model == "chosen-model")
        let reopened = WritingAssistancePreferences(defaults: defaults)
        #expect(reopened.loadError == nil)
        #expect(reopened.continuationEnabled)
        #expect(reopened.model == "chosen-model")
    }

    @Test("Repairing one field leaves another invalid stored field and its warning intact")
    func partialRepairKeepsOtherFailure() throws {
        let domain = "writing-continuation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("YES", forKey: WritingAssistancePreferences.enabledKey)
        defaults.set(17, forKey: WritingAssistancePreferences.modelKey)
        let preferences = WritingAssistancePreferences(defaults: defaults)
        preferences.continuationEnabled = true
        #expect(preferences.loadError != nil)
        #expect(defaults.integer(forKey: WritingAssistancePreferences.modelKey) == 17)
        preferences.model = "repaired-model"
        #expect(preferences.loadError == nil)
        #expect(preferences.continuationEnabled)
        #expect(defaults.string(forKey: WritingAssistancePreferences.modelKey) == "repaired-model")
    }

}
