import AppKit
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@MainActor
struct ResearchSearchFieldTests {
    @Test("Completion preserves the native caret and yields to marked text")
    func completionAndComposition() async throws {
        _ = NSApplication.shared
        var query = "tit:alpha OR beta"
        var observedCaret = -1
        func view(_ replacementID: UInt64, caret: Int? = nil) -> ResearchSearchField {
            ResearchSearchField(
                text: Binding(get: { query }, set: { query = $0 }), placeholder: "Search",
                scope: .constant(.triptych), openAdvanced: nil, isActive: true, focusRequestID: nil,
                replacementID: replacementID, beganEditing: {}, endedEditing: {}, command: { _ in true },
                replacementCaretUTF16: caret, selectionChanged: { observedCaret = $0 })
        }
        let host = NSHostingView(rootView: view(0))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 60),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> ResearchSearchField.Field? {
            if let field = view as? ResearchSearchField.Field { return field }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        let field = try #require(find(host))
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        #expect(observedCaret == 3)
        editor.setSelectedRange(NSRange(location: 0, length: 3))
        #expect(observedCaret == -1)
        query = "title:alpha OR beta"
        host.rootView = view(1, caret: 6)
        try await Task.sleep(for: .milliseconds(80))
        host.layoutSubtreeIfNeeded()
        #expect(editor.string == query)
        #expect(editor.selectedRange() == NSRange(location: 6, length: 0))
        let coordinator = try #require(field.delegate as? ResearchSearchField.Coordinator)
        editor.setMarkedText(
            "zhong", selectedRange: NSRange(location: 5, length: 0),
            replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(query == "title:alpha OR beta")
        #expect(!coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        host.rootView = view(2, caret: 0)
        try await Task.sleep(for: .milliseconds(80))
        #expect(editor.hasMarkedText() && editor.string == "zhong")
    }

    @Test("Advanced Search cannot offer its own launch action")
    func advancedMenuHasNoRecursiveEntry() {
        let quick = field(openAdvanced: {})
        let advanced = field(openAdvanced: nil)
        let quickMenu = ResearchSearchField.Coordinator(quick).makeSearchMenu()
        let advancedMenu = ResearchSearchField.Coordinator(advanced).makeSearchMenu()
        #expect(quickMenu.items.contains { $0.action == #selector(ResearchSearchField.Coordinator.advancedSearch(_:)) })
        #expect(!advancedMenu.items.contains { $0.action == #selector(ResearchSearchField.Coordinator.advancedSearch(_:)) })
        #expect(advancedMenu.items.filter { $0.submenu != nil }.count == 1)
        for menu in [quickMenu, advancedMenu] {
            #expect(
                menu.items.first?.submenu?.items.map(\.title) == [
                    ScholiumL10n.string("This Vault"), ScholiumL10n.string("Triptych"),
                ])
        }
    }

    @Test("Search filter menus expose current scope and preserve the query")
    func filtersPreserveQuery() throws {
        var query = "aurora-fixture"
        var scope: SearchPresentationScope = .triptych
        let field = ResearchSearchField(
            text: Binding(get: { query }, set: { query = $0 }),
            placeholder: "Search", scope: Binding(get: { scope }, set: { scope = $0 }),
            openAdvanced: {},
            isActive: true, focusRequestID: nil, replacementID: 0, beganEditing: {}, endedEditing: {}, command: { _ in false })
        let coordinator = ResearchSearchField.Coordinator(field)
        let menu = coordinator.makeSearchMenu()
        let thisVault = try #require(menu.items.first?.submenu?.items[0])
        coordinator.selectScope(thisVault)
        #expect(scope == .currentVault)
        #expect(coordinator.validateMenuItem(thisVault))
        #expect(thisVault.state == .on)
        #expect(query == "aurora-fixture")
        coordinator.clearFilters(NSMenuItem())
        #expect(scope == .triptych)
        #expect(query == "aurora-fixture")
    }

    private func field(openAdvanced: (() -> Void)?) -> ResearchSearchField {
        ResearchSearchField(
            text: .constant(""), placeholder: "Search",
            scope: .constant(.triptych), openAdvanced: openAdvanced,
            isActive: false, focusRequestID: nil, replacementID: 0, beganEditing: {}, endedEditing: {}, command: { _ in false })
    }
}
