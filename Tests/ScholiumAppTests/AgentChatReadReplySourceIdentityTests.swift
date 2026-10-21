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
        var isStreaming = false

        var body: some View {
            Group {
                if usesMarkdown {
                    AgentChatMarkdown(text: input.source.source, readerID: "exact-reply", isStreaming: isStreaming)
                } else {
                    AgentChatReadReply(source: input.source.source, readerID: "exact-reply", isStreaming: isStreaming, quote: nil, openLink: { _ in })
                }
            }
            .environment(\.chatReadingPresentation, .init(id: presentationID, session: session))
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @Test("Plain streamed replies load mathematics in place only when needed, preserving selection and world isolation")
    func streamedMathematicsLoadsInRetainedPage() async throws {
        _ = NSApplication.shared
        let original = "Retained prefix 中文 e\u{301} 😀.\r\n\r\nOrdinary synthetic paragraph.\r\n"
        let input = Input(original)
        let session = AgentChatReadingSession()
        let presentationID = UUID()
        session.beginPresentation(presentationID)
        let host = NSHostingView(rootView: Reply(input: input, session: session, presentationID: presentationID, isStreaming: true))
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
        func settle(_ condition: () async throws -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while !(try await condition()) {
                try #require(ContinuousClock.now < deadline, "The retained mathematics reader did not settle")
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        try await settle { session.areReadersHydrated(["exact-reply"]) }
        let web = try #require(reader(host))
        let native = try #require(web.navigationDelegate as? SafeMarkdownReadWebView.Coordinator)
        func bridge(_ script: String) async throws -> Any? {
            try await web.callAsyncJavaScript(
                script, arguments: [:], in: nil, contentWorld: SafeMarkdownReadWebView.bridgeContentWorld)
        }
        func nativeSourceMatches(_ source: String) -> Bool {
            let current = Mirror(reflecting: native).children.first { $0.label == "selectionSource" }?.value as? String
            return current?.utf8.elementsEqual(source.utf8) == true
        }
        func expectSelectionAndLifetime() async throws {
            #expect(reader(host) === web)
            #expect(try await web.evaluateJavaScript("window.__scholiumSyntheticMathLifetime === true") as? Bool == true)
            let selection = try #require(
                try await bridge(
                    """
                    const selection = getSelection();
                    return {text: selection?.toString(), anchor: selection?.anchorOffset, focus: selection?.focusOffset};
                    """) as? [String: Any])
            #expect(selection["text"] as? String == "Retained prefix")
            #expect(selection["anchor"] as? Int == "Retained prefix".utf16.count)
            #expect(selection["focus"] as? Int == 0)
            #expect(try await web.evaluateJavaScript("window.scholiumMath?.version === 1") as? Bool == false)
        }
        #expect(try await bridge("return window.scholiumMath?.version === 1;") as? Bool == false)
        #expect(try await bridge("return getComputedStyle(document.documentElement).getPropertyValue('--scholium-math-css-ready').trim();") as? String == "")
        _ = try await web.evaluateJavaScript("window.__scholiumSyntheticMathLifetime = true")
        // Establish a controlled backwards DOM selection. The separate pointer
        // selection suite owns native event delivery and Copy availability.
        let selected =
            try await bridge(
                """
                const text = document.querySelector('#scholium-document p')?.firstChild;
                if (!text || text.nodeType !== Node.TEXT_NODE) return false;
                getSelection().setBaseAndExtent(text, 'Retained prefix'.length, text, 0);
                return getSelection().toString() === 'Retained prefix';
                """) as? Bool
        try #require(selected == true)

        let plain = original + "\r\nMore plain prose.\r\n"
        input.source = .init(plain)
        try await settle { nativeSourceMatches(plain) && session.areReadersHydrated(["exact-reply"]) }
        #expect(try await bridge("return window.scholiumMath?.version === 1;") as? Bool == false)
        #expect(try await bridge("return document.querySelectorAll('#scholium-lazy-math-css').length;") as? Int == 0)
        try await expectSelectionAndLifetime()
        _ = try await bridge(
            """
            window.__scholiumMathMarkerReads = 0;
            const prototype = Object.getPrototypeOf(getComputedStyle(document.documentElement));
            const readProperty = prototype.getPropertyValue;
            prototype.getPropertyValue = function(name) {
                if (name === '--scholium-math-css-ready') window.__scholiumMathMarkerReads++;
                return readProperty.call(this, name);
            };
            """)

        let mathematics = plain + "\r\nInline $x^2 + y^2$.\r\n\r\n$$\r\nz^2 = x^2 + y^2\r\n$$\r\n"
        for (source, count) in [(mathematics, 2), (mathematics + "\r\nAnother inline $a+b$.\r\n", 3)] {
            input.source = .init(source)
            try await settle {
                let rendered = try await bridge("return document.querySelectorAll('#scholium-document .scholium-math-rendered .katex').length;") as? Int
                return nativeSourceMatches(source) && session.areReadersHydrated(["exact-reply"]) && rendered == count
            }
            #expect(try await bridge("return window.scholiumMath?.version === 1;") as? Bool == true)
            #expect(try await bridge("return document.querySelectorAll('#scholium-lazy-math-css').length;") as? Int == 1)
            #expect(
                try await bridge("return window.__scholiumMathMarkerReads;") as? Int == 1,
                "Later mathematics must reuse the prepared page without invoking its loader.")
            #expect(
                try await bridge(
                    """
                    await document.fonts.ready;
                    return getComputedStyle(document.querySelector('#scholium-document .katex')).fontFamily.includes('KaTeX_Main');
                    """) as? Bool == true)
            try await expectSelectionAndLifetime()
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
