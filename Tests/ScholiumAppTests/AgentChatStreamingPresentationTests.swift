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
        var ready = false
        var interruptions = 0
        func record(_ states: [String: Bool]) {
            let next = states["reply"] == true
            if ready && !next { interruptions += 1 }
            ready = next
        }
    }
    struct Reply: View {
        let input: Input
        let readiness: Readiness
        var body: some View {
            AgentChatReadReply(source: input.source, readerID: "reply", quote: { _ in }, openLink: { _ in })
                .onPreferenceChange(AgentChatReplyHydrationPreference.self) { readiness.record($0) }
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    @Test("Streaming keeps the measured reader visible and preserves selection")
    func streamingKeepsReaderVisible() async throws {
        _ = NSApplication.shared
        let input = Input()
        let readiness = Readiness()
        let host = NSHostingView(rootView: Reply(input: input, readiness: readiness))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
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
        let selected = try await web.evaluateJavaScript("""
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
}
