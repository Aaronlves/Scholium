import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Chat sidebar preference", .serialized)
@MainActor
struct ChatSidebarPreferencesTests {
    @Test("Unset and malformed preferences keep Chat off without rewriting stored values")
    func defaultsAndMalformedValues() {
        let fixture = ChatSidebarPreferenceFixture()
        defer { fixture.cleanup() }
        #expect(!fixture.preferences.isEnabled)
        #expect(fixture.defaults.object(forKey: ChatSidebarPreferences.enabledKey) == nil)
        for malformed in ["YES", "true", "false", 1, ["enabled": true]] as [Any] {
            fixture.defaults.set(malformed, forKey: ChatSidebarPreferences.enabledKey)
            #expect(!ChatSidebarPreferences(defaults: fixture.defaults).isEnabled)
            #expect(fixture.defaults.object(forKey: ChatSidebarPreferences.enabledKey) as? NSObject == malformed as? NSObject)
        }
    }

    @Test("An explicit setting survives a fresh preference owner in either state")
    func persistence() {
        let fixture = ChatSidebarPreferenceFixture()
        defer { fixture.cleanup() }
        fixture.preferences.isEnabled = true
        #expect(ChatSidebarPreferences(defaults: fixture.defaults).isEnabled)
        fixture.preferences.isEnabled = false
        #expect(!ChatSidebarPreferences(defaults: fixture.defaults).isEnabled)
        #expect(fixture.defaults.object(forKey: ChatSidebarPreferences.enabledKey) as? Bool == false)
    }

    @Test("Shared presentation changes every window without changing pane visibility, Inspector or document mode")
    func multipleWindows() async throws {
        let fixture = ChatSidebarPreferenceFixture(enabled: true)
        defer { fixture.cleanup() }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/chat-sidebar-tests/\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        let first = WindowModel(workspaceStore: store, chatSidebarPreferences: fixture.preferences)
        let second = WindowModel(workspaceStore: store, chatSidebarPreferences: fixture.preferences)
        first.shellState.selectInspectorMode(.related)
        first.shellState.showResearchInspector(true)
        second.shellState.selectInspectorMode(.links)
        second.shellState.showResearchInspector(false)
        first.rememberPresentationMode(.source)
        second.rememberPresentationMode(.read)
        let modes = [first.currentPresentationMode, second.currentPresentationMode]
        for _ in 0..<3 {
            fixture.preferences.isEnabled = true
            _ = first.shellState.activateSidebar(.chat)
            _ = second.shellState.activateSidebar(.chat)
            first.shellState.recordLibraryVisibility(true)
            second.shellState.recordLibraryVisibility(false)
            fixture.preferences.isEnabled = false
            #expect(!first.isChatSidebarEnabled && !second.isChatSidebarEnabled)
            #expect(first.shellState.sidebarContent == .library && second.shellState.sidebarContent == .library)
            #expect(first.shellState.libraryVisible && !second.shellState.libraryVisible)
            #expect(first.shellState.inspector.mode == .related && first.shellState.inspector.isVisible)
            #expect(second.shellState.inspector.mode == .links && !second.shellState.inspector.isVisible)
            #expect([first.currentPresentationMode, second.currentPresentationMode] == modes)
            fixture.preferences.isEnabled = true
            #expect(first.shellState.sidebarContent == .library && second.shellState.sidebarContent == .library)
        }
        await store.shutdownApplicationRuntime()
    }
}
