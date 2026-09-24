import AppKit
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Inspector pane focus", .serialized)
@MainActor
struct InspectorPaneFocusTests {
    @Test("Hidden Links search resigns only its own field editor")
    func inactiveSearchPreservesOtherFocusAndQuery() async throws {
        _ = NSApplication.shared
        var query = "retained query"
        let binding = Binding(get: { query }, set: { query = $0 })
        func view(active: Bool) -> ContextSearchField {
            ContextSearchField(
                text: binding, prompt: "Find in Links",
                identifier: "scholium.links.search", isActive: active
            )
        }

        let host = NSHostingView(rootView: view(active: true))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        host.frame = NSRect(x: 0, y: 40, width: 360, height: 40)
        container.addSubview(host)
        window.contentView = container
        defer { window.close() }
        host.layoutSubtreeIfNeeded()

        func findField(in view: NSView) -> ContextSearchField.Field? {
            if let field = view as? ContextSearchField.Field { return field }
            return view.subviews.lazy.compactMap { findField(in: $0) }.first
        }
        let field = try #require(findField(in: host))
        #expect(window.makeFirstResponder(field))
        let fieldEditor = try #require(field.currentEditor())
        #expect(window.firstResponder === fieldEditor)

        host.rootView = view(active: false)
        try await settle(host) { !field.isEnabled && window.firstResponder !== fieldEditor }
        #expect(findField(in: host) === field)
        #expect(query == "retained query")

        host.rootView = view(active: true)
        try await settle(host) { field.isEnabled }
        let otherField = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        container.addSubview(otherField)
        #expect(window.makeFirstResponder(otherField))
        let otherEditor = try #require(otherField.currentEditor())

        host.rootView = view(active: false)
        try await settle(host) { !field.isEnabled }
        #expect(window.firstResponder === otherEditor)
        #expect(query == "retained query")
    }

    private func settle(_ host: NSView, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while true {
            host.layoutSubtreeIfNeeded()
            if condition() { return }
            try #require(ContinuousClock.now < deadline, "Native Inspector control did not update")
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
