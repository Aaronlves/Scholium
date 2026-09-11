import AppKit
import Foundation
import Testing

@testable import ScholiumApp

@Suite("Selection action preferences", .serialized)
@MainActor struct SelectionActionPreferencesTests {
    @Test("Limits reject invalid drafts without replacing saved actions; order and enable state survive reopening")
    func persistence() throws {
        let domain = "selection-actions-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = SelectionActionPreferences(defaults: defaults)
        #expect(SelectionActionPreferences.validationError(store.actions) == nil)
        var draft = store.actions.reversed().map { $0 }
        draft[0].name = "核对原文"
        draft[0].isEnabled = false
        try store.save(draft)
        let saved = try #require(defaults.data(forKey: SelectionActionPreferences.key))
        #expect(SelectionActionPreferences(defaults: defaults).actions == draft)
        var invalid = draft
        invalid[0].name = "超过六个汉字的操作名称"
        #expect(throws: (any Error).self) { try store.save(invalid) }
        invalid[0].name = "A\nB"
        #expect(SelectionActionPreferences.validationError(invalid) != nil)
        invalid = draft
        invalid[0].prompt = "  "
        #expect(SelectionActionPreferences.validationError(invalid) != nil)
        #expect(SelectionActionPreferences.validationError((0..<6).map { _ in .init(name: "Test", prompt: "Explain") }) != nil)
        #expect(defaults.data(forKey: SelectionActionPreferences.key) == saved)
        store.restoreDefaults()
        #expect(store.actions.count == 3 && defaults.data(forKey: SelectionActionPreferences.key) == nil)
    }
    @Test("Unreadable settings stay unchanged and expose repair")
    func invalidStorage() throws {
        let domain = "selection-actions-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let data = Data("invalid".utf8)
        defaults.set(data, forKey: SelectionActionPreferences.key)
        let store = SelectionActionPreferences(defaults: defaults)
        #expect(store.actions.isEmpty && store.loadError != nil)
        #expect(defaults.data(forKey: SelectionActionPreferences.key) == data)
    }
}
