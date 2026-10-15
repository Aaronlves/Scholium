import AppKit
import Observation
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat streaming presentation", .serialized) @MainActor
struct AgentChatStreamingPresentationTests {
    @Observable @MainActor final class Input {
        var source = "An **existing reply** with 中文 and a retained selection.\n\n"
    }
    @MainActor final class Readiness {
        let session = AgentChatReadingSession()
        let presentationID = UUID()
        init() { session.beginPresentation(presentationID) }
        var ready: Bool { session.areReadersHydrated(["reply"]) }
        private var lastReady = false
        var interruptions = 0
        func record(_ next: Bool) {
            if lastReady && !next { interruptions += 1 }
            lastReady = next
        }
    }
    struct Reply: View {
        let input: Input
        let readiness: Readiness
        var body: some View {
            AgentChatReadReply(source: input.source, readerID: "reply", quote: { _ in }, openLink: { _ in })
                .environment(\.chatReadingPresentation, .init(id: readiness.presentationID, session: readiness.session))
                .onChange(of: readiness.ready, initial: true) { _, next in readiness.record(next) }
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    @Test("Streaming keeps the measured reader visible and preserves selection")
    func streamingKeepsReaderVisible() async throws {
        _ = NSApplication.shared
        let input = Input()
        let readiness = Readiness()
        let host = NSHostingView(rootView: Reply(input: input, readiness: readiness))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        func settle(_ condition: () async throws -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while !(try await condition()) {
                try #require(ContinuousClock.now < deadline)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        func reader(_ view: NSView) -> WKWebView? {
            (view as? WKWebView) ?? view.subviews.lazy.compactMap { reader($0) }.first
        }
        try await settle { readiness.ready }
        let web = try #require(reader(host))
        let selected =
            try await web.evaluateJavaScript(
                """
                const range = document.createRange();
                range.selectNodeContents(document.querySelector('#scholium-document strong'));
                window.getSelection().removeAllRanges(); window.getSelection().addRange(range);
                window.getSelection().toString();
                """) as? String
        #expect(selected == "existing reply")
        let start = ContinuousClock.now
        for index in 0..<20 {
            input.source += "Stream \(index) 文😀. "
            let expected = "Stream \(index) 文😀."
            try await settle {
                let text = try await web.evaluateJavaScript("document.querySelector('#scholium-document').textContent") as? String
                return readiness.ready && text?.contains(expected) == true
            }
        }
        let selectionAfter = try await web.evaluateJavaScript("window.getSelection().toString()") as? String
        #expect(reader(host) === web)
        #expect(selectionAfter == selected)
        print("CHAT_STREAM_PRESENTATION updates=20 readiness_interruptions=\(readiness.interruptions) elapsed=\(start.duration(to: .now))")
        #expect(readiness.interruptions == 0)
    }

    @Test("Lists acquire their final structure during initial streaming and retain it through unfinished markup")
    func initialStreamingListsStayFormatted() async throws {
        _ = NSApplication.shared
        let input = Input()
        input.source = "1. **First**\n2. Second"
        let readiness = Readiness()
        let host = NSHostingView(rootView: Reply(input: input, readiness: readiness))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 600),
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
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while reader(host) == nil {
            try #require(ContinuousClock.now < deadline)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(1))
        }
        let web = try #require(reader(host))
        // Continue delivering chunks during the first navigation/runtime
        // handshake. Neither turn completion nor an idle source is available
        // to unblock Markdown hydration.
        var chunk = 0
        while !readiness.ready {
            try #require(ContinuousClock.now < deadline, "Initial streaming never reached its formatted reader.")
            input.source += " 中文😀\(chunk)"
            chunk += 1
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        var source = input.source
        let suffixes = [
            "\n3. Third **partial",
            " emphasis**\n   - Nested `inline",
            " code`\n\n```swift\nlet value = 1",
            "\n```\n\nReceived final text.",
        ]
        for suffix in suffixes {
            source += suffix
            input.source = source
            let expected =
                source.contains("Received final text.")
                ? "Received final text." : source.contains("let value") ? "let value" : source.contains("Nested") ? "Nested" : "Third"
            var metrics: [String: Any]?
            while ContinuousClock.now < deadline {
                host.layoutSubtreeIfNeeded()
                metrics =
                    try? await web.evaluateJavaScript(
                        """
                        (() => {
                            const root = document.querySelector('#scholium-document');
                            return root ? {text: root.textContent, items: root.querySelectorAll(':scope > ol > li').length,
                                nested: root.querySelectorAll('ol > li > ul > li').length,
                                code: root.querySelectorAll('pre code').length} : null;
                        })()
                        """) as? [String: Any]
                if readiness.ready, (metrics?["text"] as? String)?.contains(expected) == true { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let actual = try #require(metrics)
            #expect((actual["text"] as? String)?.contains(expected) == true)
            #expect(actual["items"] as? Int == 3)
            if source.contains("Nested") { #expect(actual["nested"] as? Int == 1) }
            if source.contains("let value") { #expect(actual["code"] as? Int == 1) }
            #expect(reader(host) === web)
        }
        #expect(readiness.interruptions == 0)
    }
}
