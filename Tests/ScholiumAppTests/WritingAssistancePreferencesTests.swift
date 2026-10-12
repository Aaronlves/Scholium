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
        #expect(preferences.continuationEffort == nil && preferences.continuationEffortIsValid)
        #expect(defaults.object(forKey: WritingAssistancePreferences.enabledKey) == nil)
        #expect(defaults.object(forKey: WritingAssistancePreferences.modelKey) == nil)
        #expect(defaults.object(forKey: WritingAssistancePreferences.effortKey) == nil)
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
        preferences.continuationEffort = "minimal"
        let reopened = WritingAssistancePreferences(defaults: defaults)
        #expect(reopened.continuationEnabled)
        #expect(reopened.model == "fixture-low-cost-model")
        #expect(reopened.continuationEffort == "minimal")
        reopened.continuationEnabled = false
        #expect(WritingAssistancePreferences(defaults: defaults).model == "fixture-low-cost-model")
        #expect(WritingAssistancePreferences(defaults: defaults).continuationEffort == "minimal")
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

    @Test("Unsupported explicit effort is preserved; Automatic removes only its own override")
    func preservesUnknownEffort() throws {
        let domain = "writing-continuation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("future-effort", forKey: WritingAssistancePreferences.effortKey)
        defaults.set("chosen-model", forKey: WritingAssistancePreferences.modelKey)
        defaults.set(true, forKey: WritingAssistancePreferences.enabledKey)
        defaults.set("queue", forKey: AgentChatInputBehavior.key)
        let preferences = WritingAssistancePreferences(defaults: defaults)
        #expect(preferences.continuationEffort == "future-effort")
        #expect(defaults.string(forKey: WritingAssistancePreferences.effortKey) == "future-effort")
        preferences.model = "another-model"
        #expect(preferences.continuationEffort == "future-effort")
        preferences.continuationEffort = nil
        #expect(defaults.object(forKey: WritingAssistancePreferences.effortKey) == nil)
        #expect(preferences.continuationEnabled && preferences.model == "another-model")
        #expect(defaults.string(forKey: AgentChatInputBehavior.key) == "queue")
    }

    @Test("Malformed explicit effort cannot become Automatic and partial repair keeps its failure")
    func malformedEffort() throws {
        let domain = "writing-continuation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(17, forKey: WritingAssistancePreferences.effortKey)
        defaults.set("YES", forKey: WritingAssistancePreferences.enabledKey)
        defaults.set("chosen-model", forKey: WritingAssistancePreferences.modelKey)
        let preferences = WritingAssistancePreferences(defaults: defaults)
        #expect(preferences.continuationEffort != nil && !preferences.continuationEffortIsValid)
        #expect(preferences.loadError != nil)
        #expect(defaults.integer(forKey: WritingAssistancePreferences.effortKey) == 17)
        preferences.continuationEnabled = true
        #expect(preferences.loadError != nil && !preferences.continuationEffortIsValid)
        #expect(defaults.integer(forKey: WritingAssistancePreferences.effortKey) == 17)
        preferences.continuationEffort = "low"
        let reopened = WritingAssistancePreferences(defaults: defaults)
        #expect(reopened.loadError == nil && reopened.continuationEffortIsValid)
        #expect(reopened.continuationEffort == "low" && reopened.model == "chosen-model")
    }

    @Test("Empty effort remains invalid until an explicit repair", arguments: ["", "  "])
    func emptyEffort(effort: String) throws {
        let domain = "writing-continuation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(effort, forKey: WritingAssistancePreferences.effortKey)
        let preferences = WritingAssistancePreferences(defaults: defaults)
        #expect(preferences.continuationEffort == effort && !preferences.continuationEffortIsValid)
        #expect(defaults.string(forKey: WritingAssistancePreferences.effortKey) == effort)
        preferences.continuationEffort = nil
        #expect(preferences.loadError == nil && preferences.continuationEffortIsValid)
    }

    @Test("Model and effort changes independently invalidate the existing editor configuration key")
    func continuationConfigurationIdentity() throws {
        let domain = "writing-continuation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = WritingAssistancePreferences(defaults: defaults)
        let automatic = preferences.continuationContextKey
        preferences.continuationEffort = "none"
        let none = preferences.continuationContextKey
        #expect(none != automatic)
        preferences.continuationEffort = "low"
        let low = preferences.continuationContextKey
        #expect(low != none && low != automatic)
        preferences.model = "another-model"
        #expect(preferences.continuationContextKey != low)
        #expect(WritingAssistancePreferences(defaults: defaults).continuationContextKey == preferences.continuationContextKey)
        preferences.restoreDefaults()
        #expect(preferences.continuationContextKey == automatic)
        #expect(defaults.object(forKey: WritingAssistancePreferences.effortKey) == nil)
    }

}
