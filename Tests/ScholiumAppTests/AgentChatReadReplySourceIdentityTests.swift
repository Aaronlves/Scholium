import AppKit
import Combine
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat reader exact source identity", .serialized)
@MainActor
struct AgentChatReadReplySourceIdentityTests {
    final class Input: ObservableObject {
        @Published var source: ScholiumExactUTF8.SourceIdentity
        init(_ source: String) { self.source = .init(source) }
    }

    private struct Reply: View {
        @ObservedObject var input: Input
        let session: AgentChatReadingSession
        let presentationID: UUID
        var usesMarkdown = false

        var body: some View {
            Group {
                if usesMarkdown {
                    AgentChatMarkdown(text: input.source.source, readerID: "exact-reply")
                } else {
                    AgentChatReadReply(source: input.source.source, readerID: "exact-reply", quote: nil, openLink: { _ in })
                }
            }
            .environment(\.chatReadingPresentation, .init(id: presentationID, session: session))
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @Test("A failed page's source revision waits for scrolling to end before creating a successor")
    func failedReaderReentersPreparation() async throws {
        _ = NSApplication.shared
        let input = Input("**Disposable failed reader.**")
        let session = AgentChatReadingSession()
        let presentationID = UUID()
        session.beginPresentation(presentationID)
        let host = NSHostingView(rootView: Reply(input: input, session: session, presentationID: presentationID))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            session.endPresentation(presentationID)
            window.contentView = nil
            window.close()
        }
        func reader(_ view: NSView) -> WKWebView? {
            (view as? WKWebView) ?? view.subviews.lazy.compactMap { reader($0) }.first
        }
        func turn() async throws {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        func settle(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while !condition() {
                try #require(ContinuousClock.now < deadline, "Failed reader lifecycle did not settle")
                try await turn()
            }
        }
        try await settle { session.areReadersHydrated(["exact-reply"]) }
        let failed = try #require(reader(host))
        let delegate = try #require(failed.navigationDelegate)
        // Exercise the real product failure callback without killing a process
        // that could also host other tests' WebKit pages.
        delegate.webViewWebContentProcessDidTerminate?(failed)
        try await settle { reader(host) == nil }
        session.beginUserScroll()
        let replacement = "**Exact replacement after failure. 中文😀**"
        input.source = .init(replacement)
        let pausedUntil = ContinuousClock.now.advanced(by: .milliseconds(300))
        while ContinuousClock.now < pausedUntil {
            try await turn()
            try #require(reader(host) == nil, "A retired failed page must reenter the scrolling-aware startup queue")
        }
        session.endUserScroll()
        try await settle { reader(host) != nil && session.areReadersHydrated(["exact-reply"]) }
        let successor = try #require(reader(host))
        #expect(successor !== failed)
        let content = try await successor.evaluateJavaScript("document.querySelector('#scholium-document')?.textContent") as? String
        #expect(content?.contains("Exact replacement after failure. 中文😀") == true)
    }

    @Test("Canonically equal replacement reaches the retained reader without reloading its page", arguments: [false, true])
    func nativeReaderReceivesByteChangedSource(usesMarkdown: Bool) async throws {
        _ = NSApplication.shared
        let original = "**Café 中文😀**\r\n\r\nRetained synthetic reader.\r\n"
        let replacement = "**Cafe\u{301} 中文😀**\r\n\r\nRetained synthetic reader.\r\n"
        try #require(original == replacement && !original.utf8.elementsEqual(replacement.utf8))
        let input = Input(original)
        let session = AgentChatReadingSession()
        let presentationID = UUID()
        session.beginPresentation(presentationID)
        let host = NSHostingView(rootView: Reply(input: input, session: session, presentationID: presentationID, usesMarkdown: usesMarkdown))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        func reader(_ view: NSView) -> WKWebView? {
            (view as? WKWebView) ?? view.subviews.lazy.compactMap { reader($0) }.first
        }
        func settle(_ stage: String, _ condition: () async throws -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while !(try await condition()) {
                if ContinuousClock.now >= deadline {
                    let state = try? await reader(host)?.evaluateJavaScript(
                        "({state:document.readyState,sourceLength:document.querySelector('#scholium-document')?.textContent?.length})")
                    let hydrated = session.areReadersHydrated(["exact-reply"])
                    let webID = reader(host)?.accessibilityIdentifier() ?? "none"
                    print("CHAT_SOURCE_STATE stage=\(stage) hydrated=\(hydrated) web=\(webID) state=\(String(describing: state))")
                }
                try #require(ContinuousClock.now < deadline, "The synthetic exact-source reader did not settle at \(stage)")
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        try await settle("initial hydration") { session.areReadersHydrated(["exact-reply"]) }
        let web = try #require(reader(host))
        let initialTitle = try #require(try await web.evaluateJavaScript("document.querySelector('#scholium-document strong')?.textContent") as? String)
        try #require(initialTitle.utf8.elementsEqual("Café 中文😀".utf8))
        _ = try await web.evaluateJavaScript("window.__scholiumSyntheticSourceLifetime = true")

        input.source = .init(replacement)
        try await settle("byte-distinct replacement") {
            let title = try await web.evaluateJavaScript("document.querySelector('#scholium-document strong')?.textContent") as? String
            return session.areReadersHydrated(["exact-reply"]) && title?.utf8.elementsEqual("Cafe\u{301} 中文😀".utf8) == true
        }
        #expect(reader(host) === web)
        #expect(try await web.evaluateJavaScript("window.__scholiumSyntheticSourceLifetime === true") as? Bool == true)

        input.source = .init(replacement + "\r\n追加 👩‍🔬 exact appended source.\r\n")
        try await settle("append") {
            let text = try await web.evaluateJavaScript("document.querySelector('#scholium-document')?.textContent") as? String
            return session.areReadersHydrated(["exact-reply"]) && text?.contains("追加 👩‍🔬 exact appended source.") == true
        }
        #expect(reader(host) === web)
        #expect(try await web.evaluateJavaScript("window.__scholiumSyntheticSourceLifetime === true") as? Bool == true)
    }
}
