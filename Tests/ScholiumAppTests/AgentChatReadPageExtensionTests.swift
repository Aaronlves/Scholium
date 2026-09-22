import AppKit
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat read page extension admission", .serialized)
@MainActor
struct AgentChatReadPageExtensionTests {
    @Test("Only interaction telemetry may omit the current reply fingerprint")
    func fingerprintBypassIsLimitedToInteractionTelemetry() {
        let pageExtension = AgentChatReadPageExtension()

        #expect(pageExtension.acceptsMessageWithoutCurrentFingerprint(type: "replyInteraction"))
        for type in [
            "replyLayout", "replyNoteContext", "replySelectionContext", "replyQuote",
        ] {
            #expect(!pageExtension.acceptsMessageWithoutCurrentFingerprint(type: type))
        }
    }

    @Test("A newer reply follows an in-flight DOM commit or replaced page without stale publication", arguments: [false, true])
    func overlappingReplyUpdates(replacePage: Bool) async throws {
        _ = NSApplication.shared
        let webView = WKWebView(frame: .zero)
        webView.loadHTMLString("<html><body id='fixture'></body></html>", baseURL: nil)
        defer { webView.stopLoading() }
        let world = SafeMarkdownReadWebView.bridgeContentWorld
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if (try? await webView.callAsyncJavaScript(
                "return document.body?.id === 'fixture';", arguments: [:], in: nil, contentWorld: world)) as? Bool == true
            {
                break
            }
            await Task.yield()
        }
        _ = try await webView.callAsyncJavaScript(
            """
            window.replyState = {fingerprint: 'initial', body: '', calls: 0};
            window.releaseReply = null;
            window.scholiumUpdateReply = async update => {
                if (update.previousFingerprint !== window.replyState.fingerprint) return false;
                window.replyState = {fingerprint: update.fingerprint, body: update.html,
                    calls: window.replyState.calls + 1};
                document.body.textContent = update.html;
                if (update.fingerprint === 'first') {
                    await new Promise(resolve => { window.releaseReply = resolve; });
                }
                return true;
            };
            """, arguments: [:], in: nil, contentWorld: world)
        let page = AgentChatReadPageExtension()
        page.didFinalizePage(fingerprint: "initial")
        page.didFinishNavigation(nil, isCurrent: { true })
        var current = "first"
        var applied: [String] = []
        var failures = 0
        func submit(_ fingerprint: String, source: String) {
            let admitted = page.updateIfNeeded(
                body: source, source: source, fingerprint: fingerprint, signature: fingerprint,
                documentID: "reply", loadGeneration: 1, presentationCSS: "", userCSS: "", in: webView,
                isCurrent: { current == fingerprint },
                didApply: { source, _ in applied.append(source) },
                didFail: { _ in failures += 1 })
            #expect(admitted)
        }
        submit("first", source: "First prefix")
        var firstIsSuspended = false
        while ContinuousClock.now < deadline {
            firstIsSuspended =
                (try await webView.callAsyncJavaScript(
                    "return typeof window.releaseReply === 'function';", arguments: [:], in: nil, contentWorld: world)) as? Bool == true
            if firstIsSuspended { break }
            await Task.yield()
        }
        try #require(firstIsSuspended)
        if replacePage {
            // Keep the source-current callback true while replacing the page:
            // page lifetime must independently reject the cancelled completion.
            page.willBeginLoad(fingerprint: "replacement")
            _ = try await webView.callAsyncJavaScript(
                """
                window.replyState.fingerprint = 'replacement';
                document.body.textContent = 'Replacement page';
                window.releaseReply();
                """, arguments: [:], in: nil, contentWorld: world)
            // Drive a bounded native/WebKit round trip after the old promise
            // resolves before allowing the replacement to accept new source.
            _ = try await webView.callAsyncJavaScript(
                "return document.body.textContent;", arguments: [:], in: nil, contentWorld: world)
            #expect(applied.isEmpty)
            #expect(!page.canUpdateInPlace(currentDocumentID: "reply", nextDocumentID: "reply", hasLoadedPage: true))
            page.didFinalizePage(fingerprint: "replacement")
            page.didFinishNavigation(nil, isCurrent: { true })
        }
        current = "latest"
        let latest = "First prefix with 中文, **exact Markdown**, and 🦉."
        submit("latest", source: latest)
        _ = try await webView.callAsyncJavaScript(
            "window.releaseReply();", arguments: [:], in: nil, contentWorld: world)
        while applied.isEmpty && failures == 0 && ContinuousClock.now < deadline { await Task.yield() }
        let result = try #require(
            try await webView.callAsyncJavaScript(
                "return {fingerprint: window.replyState.fingerprint, body: document.body.textContent};",
                arguments: [:], in: nil, contentWorld: world) as? [String: String])
        #expect(failures == 0)
        #expect(applied == [latest])
        #expect(result["fingerprint"] == "latest")
        #expect(result["body"] == latest)
        page.cancel()
    }

}
