import Combine
import Foundation
import Testing

@testable import ScholiumApp

@Suite("Agent context access preferences")
@MainActor
struct AgentContextAccessPreferencesTests {
    @Test("Fresh installation preserves Chat metadata access and keeps external and text grants off")
    func defaultsAndPureReads() throws {
        let fixture = try AgentContextAccessPreferenceFixture()
        defer { fixture.cleanup() }
        let preferences = AgentContextAccessPreferences(defaults: fixture.defaults)
        #expect(preferences.allowsState(for: .chat))
        #expect(!preferences.allowsState(for: .external))
        #expect(!preferences.allowsWorkingText(for: .chat))
        #expect(!preferences.allowsWorkingText(for: .external))
        #expect(preferences.revision == 0)
        #expect(preferences.invalidStoredKeys.isEmpty)
        for key in fixture.keys { #expect(fixture.defaults.object(forKey: key) == nil) }
    }

    @Test("Malformed grants deny access without rewriting their stored values")
    func malformedValuesFailClosed() throws {
        let fixture = try AgentContextAccessPreferenceFixture()
        defer { fixture.cleanup() }
        let malformed: [Any] = ["true", "YES", 1, 0, ["allow": true]]
        for key in fixture.keys {
            for value in malformed {
                fixture.defaults.set(value, forKey: key)
                let preferences = AgentContextAccessPreferences(defaults: fixture.defaults)
                #expect(preferences.invalidStoredKeys.contains(key))
                switch key {
                case AgentContextAccessPreferences.chatStateKey:
                    #expect(!preferences.allowsState(for: .chat))
                case AgentContextAccessPreferences.externalStateKey:
                    #expect(!preferences.allowsState(for: .external))
                case AgentContextAccessPreferences.chatWorkingTextKey:
                    #expect(!preferences.allowsWorkingText(for: .chat))
                default:
                    #expect(!preferences.allowsWorkingText(for: .external))
                }
                #expect(fixture.defaults.object(forKey: key) as? NSObject == value as? NSObject)
                #expect(preferences.revision == 0)
            }
        }
        let preferences = AgentContextAccessPreferences(defaults: fixture.defaults)
        preferences.chatStateAccess = false
        #expect(fixture.defaults.object(forKey: AgentContextAccessPreferences.chatStateKey) as? Bool == false)
        #expect(!preferences.invalidStoredKeys.contains(AgentContextAccessPreferences.chatStateKey))
        #expect(preferences.revision == 0)
    }

    @Test("Each caller's state and working-text choices persist independently")
    func independentPersistence() throws {
        let fixture = try AgentContextAccessPreferenceFixture()
        defer { fixture.cleanup() }
        let preferences = AgentContextAccessPreferences(defaults: fixture.defaults)
        preferences.chatStateAccess = false
        preferences.chatWorkingTextAccess = true
        preferences.externalStateAccess = true
        preferences.externalWorkingTextAccess = false
        let restored = AgentContextAccessPreferences(defaults: fixture.defaults)
        #expect(!restored.allowsState(for: .chat))
        #expect(restored.allowsWorkingText(for: .chat))
        #expect(restored.allowsState(for: .external))
        #expect(!restored.allowsWorkingText(for: .external))
        #expect(restored.invalidStoredKeys.isEmpty)
        #expect(fixture.defaults.object(forKey: ChatSidebarPreferences.enabledKey) == nil)
    }

    @Test("Revocation and re-enabling synchronously invalidate an earlier capture even when access returns")
    func revisionRevokesEarlierCapture() throws {
        let fixture = try AgentContextAccessPreferenceFixture()
        defer { fixture.cleanup() }
        let preferences = AgentContextAccessPreferences(defaults: fixture.defaults)
        let capturedRevision = preferences.revision
        var publishedRevisions: [UInt64] = []
        let observation = preferences.$revision.dropFirst().sink { publishedRevisions.append($0) }
        defer { observation.cancel() }
        preferences.chatStateAccess = false
        #expect(!preferences.allowsState(for: .chat))
        #expect(preferences.revision != capturedRevision)
        preferences.chatStateAccess = true
        #expect(preferences.allowsState(for: .chat))
        #expect(preferences.revision == capturedRevision + 2)
        #expect(publishedRevisions == [1, 2])
        preferences.chatStateAccess = true
        #expect(preferences.revision == 2)
        preferences.chatWorkingTextAccess = true
        preferences.externalStateAccess = true
        preferences.externalWorkingTextAccess = true
        #expect(preferences.revision == 5)
        #expect(publishedRevisions == [1, 2, 3, 4, 5])
    }
}

@MainActor
private struct AgentContextAccessPreferenceFixture {
    let suiteName: String
    let defaults: UserDefaults
    var keys: [String] {
        [
            AgentContextAccessPreferences.chatStateKey, AgentContextAccessPreferences.externalStateKey,
            AgentContextAccessPreferences.chatWorkingTextKey, AgentContextAccessPreferences.externalWorkingTextKey,
        ]
    }

    init() throws {
        let suiteName = "Scholium.AgentContextAccess.\(UUID())"
        self.suiteName = suiteName
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func cleanup() { defaults.removePersistentDomain(forName: suiteName) }
}
