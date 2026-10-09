import AppKit
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat outgoing navigation", .serialized)
@MainActor
struct AgentChatNavigationTests {
    @Test("An outgoing native reply stays painted but gives up pointer, keyboard and accessibility interaction")
    func outgoingReplyRetainsRenderingWithoutInteraction() throws {
        _ = NSApplication.shared
        var interactions = 0
        var layouts = 0
        let page = AgentChatReadPageExtension()
        page.update(
            onEvent: { event in
                switch event {
                case .layout: layouts += 1
                default: interactions += 1
                }
            }, isInteractive: true)
        let reader = try #require(page.makeWebView(configuration: WKWebViewConfiguration()) as? AgentChatReadWebView)
        reader.frame = NSRect(x: 0, y: 0, width: 320, height: 300)
        let window = NSWindow(contentRect: reader.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = reader
        defer {
            window.contentView = nil
            window.close()
        }
        let retainedIdentity = ObjectIdentifier(reader)
        #expect(!reader.isHidden && reader.isChatInteractive)
        #expect(page.handleMessage(type: "replyInteraction", payload: [:], webView: reader))
        #expect(interactions == 1)

        page.update(
            onEvent: { event in
                switch event {
                case .layout: layouts += 1
                default: interactions += 1
                }
            }, isInteractive: false)
        #expect(!reader.isHidden, "Outgoing pixels survive until the navigation owner finishes the move.")
        #expect(!reader.acceptsFirstResponder)
        #expect(reader.hitTest(NSPoint(x: 20, y: 20)) == nil)
        #expect(reader.isAccessibilityHidden())
        #expect(page.handleMessage(type: "replyInteraction", payload: [:], webView: reader))
        #expect(page.handleMessage(type: "replyQuote", payload: ["text": "Late selected reply"], webView: reader))
        #expect(interactions == 1, "A queued bridge event cannot reopen controls after Back.")
        let preview: [String: Any] = [
            "event": [
                "type": "previewSurface",
                "surface": [
                    "id": 1, "left": 20.0, "top": 20.0, "bottom": 40.0, "html": "<p>Footnote</p>", "css": "",
                ],
            ]
        ]
        #expect(DocumentFloatingEvent.decode(preview["event"]) != nil)
        #expect(page.handleMessage(type: "floatingSurface", payload: preview, webView: reader))
        let dismissal: [String: Any] = ["event": ["type": "dismissSurface", "kind": "preview", "id": 1]]
        #expect(!page.handleMessage(type: "floatingSurface", payload: dismissal, webView: reader))
        #expect(page.handleMessage(type: "replyLayout", payload: ["height": 120.0, "intrinsicWidth": NSNull(), "objects": []], webView: reader))
        #expect(layouts == 1, "Retaining inert pixels must not discard native layout convergence.")

        page.update(onEvent: { _ in interactions += 1 }, isInteractive: true)
        #expect(ObjectIdentifier(reader) == retainedIdentity)
        #expect(reader.isChatInteractive && !reader.isAccessibilityHidden())
        #expect(!reader.isHidden)
        #expect(!page.handleMessage(type: "floatingSurface", payload: preview, webView: reader))
        #expect(page.handleMessage(type: "replyInteraction", payload: [:], webView: reader))
        #expect(interactions == 2)
    }

    @Test("The outgoing transcript removes its native wheel monitor while its surface remains painted")
    func outgoingScrollBoundaryStopsRouting() async throws {
        _ = NSApplication.shared
        func content(interactive: Bool) -> some View {
            AgentChatScrollBoundary()
                .frame(width: 320, height: 300)
                .disabled(!interactive)
                .environment(\.scholiumDocumentSurfaceVisibility, .active)
        }
        let host = NSHostingView(rootView: content(interactive: true))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        func boundary(in view: NSView) -> AgentChatScrollBoundary.BoundaryView? {
            (view as? AgentChatScrollBoundary.BoundaryView) ?? view.subviews.lazy.compactMap { boundary(in: $0) }.first
        }
        try await settle(host) { boundary(in: host) != nil }
        let retained = try #require(boundary(in: host))
        #expect(retained.isActive)
        host.rootView = content(interactive: false)
        try await settle(host) { !retained.isActive }
        #expect(!retained.isHiddenOrHasHiddenAncestor)
        host.rootView = content(interactive: true)
        try await settle(host) { retained.isActive }
        #expect(boundary(in: host) === retained)
    }

    private func settle(_ host: NSView, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while true {
            host.window?.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            if condition() { return }
            try #require(ContinuousClock.now < deadline, "Chat navigation did not reach its expected native interaction state")
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
