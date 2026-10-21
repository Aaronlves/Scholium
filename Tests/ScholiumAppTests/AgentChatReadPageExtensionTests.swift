import AppKit
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat read page extension admission", .serialized)
@MainActor
struct AgentChatReadPageExtensionTests {
    @Test("Reply geometry requires a bounded layout viewport width")
    func replyLayoutViewport() {
        var measurements: [CGSize] = []
        let page = AgentChatReadPageExtension { event in
            if case .layout(let height, let viewportWidth, _, _) = event {
                measurements.append(CGSize(width: viewportWidth, height: height))
            }
        }
        let payload: [String: Any] = ["height": 24.0, "intrinsicWidth": 54.0, "objects": []]
        #expect(page.handleMessage(type: "replyLayout", payload: payload, webView: nil))
        for invalid in [0.0, -1.0, Double.infinity, Double.nan, 1_000_000.0] {
            #expect(page.handleMessage(type: "replyLayout", payload: payload.merging(["viewportWidth": invalid]) { _, next in next }, webView: nil))
        }
        #expect(measurements.isEmpty)
        for width in [360.0, 240.0] {
            #expect(page.handleMessage(type: "replyLayout", payload: payload.merging(["viewportWidth": width]) { _, next in next }, webView: nil))
        }
        #expect(measurements == [CGSize(width: 360, height: 24), CGSize(width: 240, height: 24)])
    }

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

    @Test("An admission that expires during mathematics preparation cannot commit its reply")
    func mathematicsPreparationRechecksCurrency() async throws {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let page = AgentChatReadPageExtension()
        defer {
            page.cancel()
            webView.stopLoading()
        }
        let world = SafeMarkdownReadWebView.bridgeContentWorld
        func evaluate(_ script: String) async throws -> Any? {
            try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: world)
        }
        webView.loadHTMLString("<html><body id='math-admission'>Original reply</body></html>", baseURL: nil)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while (try? await evaluate("return document.body?.id === 'math-admission';")) as? Bool != true {
            try #require(ContinuousClock.now < deadline, "The mathematics admission page did not load")
            await Task.yield()
        }
        _ = try await evaluate(
            """
            window.replyCommits = 0;
            window.scholiumUpdateReply = async update => {
                window.replyCommits++;
                document.body.innerHTML = update.html;
                return true;
            };
            """)
        page.didFinalizePage(fingerprint: "original")
        page.didFinishNavigation(nil, isCurrent: { true })
        var admissionChecks = 0
        var publications = 0
        var failures = 0
        let expiredAdmitted = page.updateIfNeeded(
            body: #"<span class="scholium-math" data-math-source="eA==" data-math-kind="inline"><code>x</code></span>"#,
            source: "$x$", fingerprint: "expired", signature: "expired", documentID: "reply", loadGeneration: 1,
            presentationCSS: "", userCSS: "", in: webView,
            // This controlled admission is valid when its task enters,
            // then expires across the real asynchronous WebKit preparation.
            isCurrent: {
                admissionChecks += 1
                return admissionChecks == 1
            },
            didApply: { _, _ in publications += 1 }, didFail: { _ in failures += 1 })
        #expect(expiredAdmitted)
        while admissionChecks < 2 {
            try #require(ContinuousClock.now < deadline, "Mathematics preparation did not recheck its admission")
            await Task.yield()
        }
        #expect(try await evaluate("return window.scholiumMath?.version === 1;") as? Bool == true)
        #expect(try await evaluate("return document.querySelectorAll('#scholium-lazy-math-css').length;") as? Int == 1)
        #expect(try await evaluate("return window.replyCommits;") as? Int == 0)
        #expect(try await evaluate("return document.body.textContent;") as? String == "Original reply")
        #expect(publications == 0 && failures == 0)
        _ = try await evaluate(
            """
            window.mathMarkerReads = 0;
            const prototype = Object.getPrototypeOf(getComputedStyle(document.documentElement));
            const readProperty = prototype.getPropertyValue;
            prototype.getPropertyValue = function(name) {
                if (name === '--scholium-math-css-ready') window.mathMarkerReads++;
                return readProperty.call(this, name);
            };
            """)
        let currentAdmitted = page.updateIfNeeded(
            body: #"<span class="scholium-math" data-math-source="eA==" data-math-kind="inline"><code>x</code></span>"#,
            source: "$x$", fingerprint: "current", signature: "current", documentID: "reply", loadGeneration: 1,
            presentationCSS: "", userCSS: "", in: webView, isCurrent: { true },
            didApply: { _, _ in publications += 1 }, didFail: { _ in failures += 1 })
        #expect(currentAdmitted)
        while publications == 0 && failures == 0 {
            try #require(ContinuousClock.now < deadline, "The current mathematics reply did not commit")
            await Task.yield()
        }
        #expect(publications == 1 && failures == 0)
        #expect(try await evaluate("return window.replyCommits;") as? Int == 1)
        #expect(try await evaluate("return window.mathMarkerReads;") as? Int == 0, "A completed installation survives its source admission expiring.")
    }

    @Test("A newer reply follows an in-flight DOM commit or replaced page without stale publication", arguments: [false, true])
    func overlappingReplyUpdates(replacePage: Bool) async throws {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let page = AgentChatReadPageExtension()
        defer {
            page.cancel()
            webView.stopLoading()
        }
        do {
            webView.loadHTMLString("<html><body id='fixture'></body></html>", baseURL: nil)
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
        } catch {
            page.cancel()
            _ = try? await webView.callAsyncJavaScript(
                "window.releaseReply?.(); window.releaseReply = null;", arguments: [:], in: nil,
                contentWorld: SafeMarkdownReadWebView.bridgeContentWorld)
            throw error
        }
    }

    @Test("Repeated source currency cannot release a newer serialized reply-update tail")
    func repeatedSignatureKeepsSerializedTail() async throws {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let page = AgentChatReadPageExtension()
        defer {
            page.cancel()
            webView.stopLoading()
        }
        let world = SafeMarkdownReadWebView.bridgeContentWorld
        func evaluate(_ script: String) async throws -> Any? {
            try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: world)
        }
        func waitForJavaScript(_ expression: String) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while true {
                if (try await evaluate("return " + expression + ";")) as? Bool == true { return }
                try #require(ContinuousClock.now < deadline, "The owned reply fixture did not reach its gate")
                await Task.yield()
            }
        }
        func drainScheduledUpdates() async throws {
            // Cross both the main-actor task scheduler and this WebView's
            // JavaScript queue while the repeated-A promise remains held.
            for _ in 0..<3 {
                await Task.yield()
                _ = try await evaluate("return window.replyFixture.fingerprint;")
            }
        }
        do {
            webView.loadHTMLString("<html><body id='repeated-reply-fixture'></body></html>", baseURL: nil)
            try await waitForJavaScript("document.body?.id === 'repeated-reply-fixture'")
            _ = try await evaluate(
                """
                window.replyFixture = {
                    fingerprint: 'initial', entered: [], completed: [], rejected: [],
                    overlap: [], active: new Set(), releases: {}, aCalls: 0
                };
                window.releaseReplyGate = key => {
                    const release = window.replyFixture.releases[key];
                    delete window.replyFixture.releases[key];
                    release?.();
                };
                window.releaseAllReplyGates = () => {
                    for (const key of Object.keys(window.replyFixture.releases)) window.releaseReplyGate(key);
                };
                window.scholiumUpdateReply = async update => {
                    const state = window.replyFixture;
                    const key = update.fingerprint === 'A'
                        ? (++state.aCalls === 1 ? 'firstA' : 'repeatedA') : update.fingerprint;
                    if (update.previousFingerprint !== state.fingerprint) {
                        state.rejected.push(key);
                        return false;
                    }
                    state.entered.push(key);
                    if (state.active.size !== 0) state.overlap.push(key);
                    state.active.add(key);
                    state.fingerprint = update.fingerprint;
                    document.body.textContent = update.html;
                    try {
                        if (key === 'firstA' || key === 'repeatedA') {
                            await new Promise(resolve => { state.releases[key] = resolve; });
                        }
                    } finally {
                        state.active.delete(key);
                    }
                    state.completed.push(key);
                    return true;
                };
                """)
            page.didFinalizePage(fingerprint: "initial")
            page.didFinishNavigation(nil, isCurrent: { true })
            var currentSignature = "A"
            var applied: [String] = []
            var failures = 0
            let sources = [
                "A": "Repeated exact source — 中文 and 🦉.",
                "B": #"<span class="scholium-math" data-math-source="eA==" data-math-kind="inline">Superseded intermediate source.</span>"#,
                "D": "Current source after the repeated revision.",
                "E": "Final exact source with **Markdown** and 🦉.",
            ]
            func submit(_ signature: String) {
                currentSignature = signature
                let source = sources[signature]!
                let didScheduleUpdate = page.updateIfNeeded(
                    body: source, source: source, fingerprint: signature, signature: signature,
                    documentID: "reply", loadGeneration: 1, presentationCSS: "", userCSS: "", in: webView,
                    // A1 and repeated A intentionally share source currency,
                    // just as the production loadedSignature comparison does.
                    isCurrent: { currentSignature == signature },
                    didApply: { source, _ in applied.append(source) },
                    didFail: { _ in failures += 1 })
                #expect(didScheduleUpdate)
            }
            submit("A")
            try await waitForJavaScript("typeof window.replyFixture.releases.firstA === 'function'")
            submit("B")
            submit("A")
            _ = try await evaluate("window.releaseReplyGate('firstA');")
            try await waitForJavaScript("typeof window.replyFixture.releases.repeatedA === 'function'")
            #expect(applied == [sources["A"]!])
            submit("D")
            try await drainScheduledUpdates()
            let enteredWhileHeld = try #require(try await evaluate("return window.replyFixture.entered;") as? [String])
            #expect(enteredWhileHeld == ["firstA", "repeatedA"], "D must remain behind the newer A task, even after older A regains source currency.")
            _ = try await evaluate("window.releaseReplyGate('repeatedA');")
            let completionDeadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !applied.contains(sources["D"]!) && failures == 0 {
                try #require(ContinuousClock.now < completionDeadline, "D did not settle after its predecessor was released")
                await Task.yield()
            }
            try await drainScheduledUpdates()
            submit("E")
            let finalDeadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !applied.contains(sources["E"]!) && failures == 0 {
                try #require(ContinuousClock.now < finalDeadline, "The final source did not settle")
                await Task.yield()
            }
            let result = try #require(
                try await evaluate(
                    "return {fingerprint: window.replyFixture.fingerprint, body: document.body.textContent};") as? [String: String])
            let entered = try #require(try await evaluate("return window.replyFixture.entered;") as? [String])
            let completed = try #require(try await evaluate("return window.replyFixture.completed;") as? [String])
            let overlap = try #require(try await evaluate("return window.replyFixture.overlap;") as? [String])
            let rejected = try #require(try await evaluate("return window.replyFixture.rejected;") as? [String])
            #expect(entered == ["firstA", "repeatedA", "D", "E"])
            #expect(completed == ["firstA", "repeatedA", "D", "E"])
            #expect(overlap.isEmpty && rejected.isEmpty && failures == 0)
            #expect(applied == [sources["A"]!, sources["D"]!, sources["E"]!])
            #expect(result["fingerprint"] == "E" && result["body"] == sources["E"])
            #expect(try await evaluate("return window.scholiumMath?.version === 1;") as? Bool == false)
            #expect(try await evaluate("return document.querySelectorAll('#scholium-lazy-math-css').length;") as? Int == 0)
            _ = try await evaluate("window.releaseAllReplyGates();")
        } catch {
            // Failed assertions/bridge work must not strand either JavaScript
            // promise, including a gate reached during the cleanup round trip.
            page.cancel()
            _ = try? await evaluate("window.releaseAllReplyGates?.();")
            _ = try? await evaluate("window.releaseAllReplyGates?.();")
            throw error
        }
    }

}
