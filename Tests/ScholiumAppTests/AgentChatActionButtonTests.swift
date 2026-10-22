import AppKit
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Chat native message actions", .serialized)
@MainActor
struct AgentChatActionButtonTests {
    private final class Calls { var values: [String] = [] }
    private final class Owner {
        let value: String
        let calls: Calls
        init(_ value: String, calls: Calls) { self.value = value; self.calls = calls }
        func invoke() { calls.values.append(value) }
    }
    private struct Page: View {
        let owner: Owner?
        var enabled = true
        var body: some View {
            if let owner {
                AgentChatMessageActionVisibility {
                    Text("Synthetic message")
                } actions: {
                    AgentChatActionButton(label: "Quote in Reply", systemImage: "text.quote",
                        accessibilityID: "action-fixture", action: owner.invoke)
                        .disabled(!enabled)
                }
            } else {
                Text("Destination")
            }
        }
    }

    private struct CopyPage: View {
        let owner: Owner?
        let source: String
        var succeeds = true
        var body: some View {
            if let owner {
                AgentChatCopyButton(label: "Copy Markdown", contentIdentity: source) {
                    owner.invoke()
                    return succeeds
                }
            } else {
                Text("Destination")
            }
        }
    }

    private func buttons(_ root: NSView) -> [AgentChatActionButtonView] {
        (root as? AgentChatActionButtonView).map { [$0] } ?? root.subviews.flatMap(buttons)
    }

    private func settle(_ root: NSView, until condition: () -> Bool) async throws {
        for _ in 0..<100 {
            root.layoutSubtreeIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    @Test("A stable native button receives the latest action and releases action owners on update and dismantle")
    func actionLifetime() async throws {
        _ = NSApplication.shared
        let calls = Calls()
        weak var oldOwner: Owner?
        weak var newOwner: Owner?
        let root = autoreleasepool {
            let owner = Owner("old", calls: calls)
            oldOwner = owner
            return NSHostingView(rootView: Page(owner: owner))
        }
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 360, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await settle(root) { !buttons(root).isEmpty }
        let button = try #require(buttons(root).first)
        button.performClick(nil)
        #expect(calls.values == ["old"])
        #expect(button.accessibilityLabel() == "Quote in Reply")
        #expect(button.accessibilityIdentifier() == "action-fixture")
        #expect(button.toolTip == "Quote in Reply")
        #expect(button.imagePosition == .imageOnly)
        #expect(button.isTransparent)
        // NSControl exposes its native cell as the accessibility element.
        #expect(button.cell?.accessibilityRole() == .button)
        #expect(button.cell?.isAccessibilityElement() == true)
        #expect(button.cell?.accessibilityLabel() == "Quote in Reply")
        autoreleasepool {
            let owner = Owner("new", calls: calls)
            newOwner = owner
            root.rootView = Page(owner: owner, enabled: false)
        }
        try await settle(root) { !button.isEnabled && oldOwner == nil }
        #expect(button.imagePosition == .imageOnly)
        #expect(buttons(root).first === button)
        button.performClick(nil)
        #expect(calls.values == ["old"])
        root.rootView = Page(owner: newOwner, enabled: true)
        try await settle(root) { button.isEnabled }
        try #require(window.makeFirstResponder(button))
        try await settle(root) { !button.isTransparent }
        #expect(window.firstResponder === button)
        // Check the operation's observable result, as with standard NSButton.
        // Its SDK accessibility method can return false after sending action.
        _ = button.cell?.accessibilityPerformPress()
        #expect(calls.values == ["old", "new"])
        try #require(window.makeFirstResponder(nil))
        try await settle(root) { button.isTransparent }
        try #require(window.makeFirstResponder(button))
        try await settle(root) { !button.isTransparent }
        root.rootView = Page(owner: nil)
        try await settle(root) { newOwner == nil && buttons(root).isEmpty }
        // Keep the detached native view alive: dismantling must release its
        // operation even if an AppKit event or test still retains the control.
        withExtendedLifetime(button) {
            #expect(button.handler == nil)
            #expect(button.focusChanged == nil)
        }
    }

    @Test("Native Copy shares confirmed feedback, exact-source reset, expiry and action teardown")
    func copyFeedback() async throws {
        _ = NSApplication.shared
        let calls = Calls()
        weak var oldOwner: Owner?
        weak var newOwner: Owner?
        let root = autoreleasepool {
            let owner = Owner("old", calls: calls)
            oldOwner = owner
            return NSHostingView(rootView: CopyPage(owner: owner, source: "caf\u{e9}"))
        }
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 360, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await settle(root) { !buttons(root).isEmpty }
        let button = try #require(buttons(root).first)
        button.performClick(nil)
        try await settle(root) { button.title == "Copied" }
        #expect(button.imagePosition == .imageOnly)
        #expect(calls.values == ["old"])
        autoreleasepool {
            let owner = Owner("new", calls: calls)
            newOwner = owner
            root.rootView = CopyPage(owner: owner, source: "cafe\u{301}", succeeds: false)
        }
        try await settle(root) { button.title == "Copy Markdown" && oldOwner == nil }
        #expect(button.imagePosition == .imageOnly)
        #expect(buttons(root).first === button)
        button.performClick(nil)
        #expect(calls.values == ["old", "new"])
        #expect(button.title == "Copy Markdown")
        root.rootView = CopyPage(owner: newOwner, source: "cafe\u{301}")
        root.layoutSubtreeIfNeeded()
        button.performClick(nil)
        try await settle(root) { button.title == "Copied" }
        try await Task.sleep(for: .milliseconds(2100))
        try await settle(root) { button.title == "Copy Markdown" }
        button.performClick(nil)
        try await settle(root) { button.title == "Copied" }
        try #require(window.makeFirstResponder(button))
        root.rootView = CopyPage(owner: nil, source: "")
        try await settle(root) { newOwner == nil && buttons(root).isEmpty }
        withExtendedLifetime(button) {
            #expect(button.handler == nil)
            #expect(button.focusChanged == nil)
        }
    }
}
