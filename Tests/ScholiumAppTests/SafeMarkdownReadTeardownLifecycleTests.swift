import AppKit
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

extension MarkdownEditorWebViewIntegrationTests {
    @Test("Dismantling a reader releases its native owners while JavaScript readiness remains held")
    func heldReadinessTeardownReleasesNativeOwners() async throws {
        let callbacks = TeardownCallbacks()
        let fixture = HeldReadinessFixture(callbacks: callbacks)
        defer { fixture.close() }

        do {
            try await fixture.waitForHeldReadiness()
            try #require(fixture.hasMountedOwners)
            #expect(callbacks.ready == 0 && callbacks.failures.isEmpty)
            fixture.unmount()
            try await waitForReaderTeardown { fixture.hasReleasedOwners }
            // No release, stopLoading or replacement navigation may make this
            // pass. The unresolved page must no longer own a Swift callback.
            #expect(callbacks.ready == 0 && callbacks.failures.isEmpty)
            #expect(callbacks.afterDeparture == 0)
            #expect(fixture.sourceIsExact)
        } catch {
            // Recover only after the ownership assertion has already failed.
            // The fixture keeps weak witnesses, so cleanup adds no passing
            // lifetime to the native/WebKit ownership oracle above.
            await fixture.releaseGateForFailureCleanup()
            throw error
        }
    }

    @Test(
        "Reader teardown cancels its initial selection presentation without caller cancellation",
        arguments: [false, true])
    func heldSelectionPresentationIsOwnedByReader(retainWebViewForLateResult: Bool) async throws {
        let callbacks = TeardownCallbacks()
        let fixture = HeldReadinessFixture(callbacks: callbacks, exposesSelectionPresenter: true)
        defer { fixture.close() }
        let observation = SelectionPresenterObservation()
        var presenterTask: Task<Void, any Error>?
        var externalWebView: WKWebView?
        do {
            // Finish normal initialization before arming a second readiness
            // gate. Its getter can then witness this command specifically.
            try await fixture.prepareHeldSelectionPresentation()
            if retainWebViewForLateResult {
                externalWebView = fixture.retainWebViewForLateResult()
                try #require(externalWebView != nil)
            }
            presenterTask = try fixture.startSelectionPresenter(observation: observation)
            try await fixture.waitForSelectionPresenterToEnterReadiness()
            fixture.unmount()

            // Do not cancel the caller. Dismantling the page must finish the
            // command it admitted before waiting for a floating-surface receipt.
            try await waitForReaderTeardown { observation.finishes == 1 }
            let finished = try #require(presenterTask)
            #expect(!finished.isCancelled, "The external caller was never cancelled by the test")
            do {
                try await finished.value
                Issue.record("The departed reader's selection command did not throw cancellation")
            } catch {
                #expect(error is CancellationError)
            }
            #expect(!observation.returnedNormally)
            try await waitForReaderTeardown { fixture.hasReleasedCallbackOwners }
            #expect(callbacks.inquiries == 0 && callbacks.afterDeparture == 0)

            if retainWebViewForLateResult {
                #expect(!fixture.nativeViewHasReleased, "This case deliberately keeps the old physical page alive")
                // Ownership is already revoked. Now prove that the old JS call
                // really proceeds through ShowSelectionActions after release.
                try await fixture.releaseSecondGateAndObserveLatePresenter()
                #expect(observation.finishes == 1 && !observation.returnedNormally)
                #expect(callbacks.inquiries == 0 && callbacks.afterDeparture == 0)
                #expect(callbacks.ready == 1 && callbacks.failures.isEmpty)
            }
            autoreleasepool { externalWebView = nil }
            try await waitForReaderTeardown { fixture.hasReleasedOwners }
            #expect(callbacks.ready == 1 && callbacks.failures.isEmpty)
            #expect(fixture.sourceIsExact)
        } catch {
            // Only a failed oracle may cancel the external caller or resolve
            // the second gate. Neither operation establishes successful teardown.
            presenterTask?.cancel()
            await fixture.releaseGateForFailureCleanup()
            autoreleasepool { externalWebView = nil }
            throw error
        }
    }

    private func waitForReaderTeardown(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "A dismantled reader still owns its WebView or captured callback while readiness is held")
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @MainActor
    private final class TeardownCallbacks {
        var ready = 0
        var failures: [String] = []
        var hasDeparted = false
        var afterDeparture = 0
        var inquiries = 0

        func didBecomeReady() {
            ready += 1
            if hasDeparted { afterDeparture += 1 }
        }

        func didFail(_ message: String) {
            failures.append(message)
            if hasDeparted { afterDeparture += 1 }
        }
    }

    @MainActor
    private final class TeardownCallbackLifetime {
        func observe() {}
    }

    @MainActor
    private final class SelectionPresenterPort {
        var presenter: DocumentSelectionActionPresenter?
    }

    @MainActor
    private final class SelectionPresenterObservation {
        var finishes = 0
        var returnedNormally = false
    }

    @MainActor
    private final class HeldReadinessFixture {
        private let source: String
        private let document: NoteDocument
        private let callbacks: TeardownCallbacks
        private let window: NSWindow
        private var host: NSHostingController<AnyView>?
        private weak var webView: WKWebView?
        private weak var coordinator: SafeMarkdownReadWebView.Coordinator?
        private weak var callbackLifetime: TeardownCallbackLifetime?
        private let selectionPresenterPort = SelectionPresenterPort()

        init(callbacks: TeardownCallbacks, exposesSelectionPresenter: Bool = false) {
            _ = NSApplication.shared
            let source = "\u{FEFF}# Reader teardown\r\n\r\nExact Cafe\u{301} 中文🦉 **source**.\r\n"
            self.source = source
            self.callbacks = callbacks
            document = NoteDocument(relativePath: "Teardown.md", rawContent: source)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let lifetime = TeardownCallbackLifetime()
            callbackLifetime = lifetime
            let inquire: AgentSelectionInquiryHandler?
            if exposesSelectionPresenter {
                inquire = { [lifetime, callbacks] _, _ in
                    lifetime.observe()
                    callbacks.inquiries += 1
                    if callbacks.hasDeparted { callbacks.afterDeparture += 1 }
                    return nil
                }
            } else {
                inquire = nil
            }
            let presenterPort = selectionPresenterPort
            let surface = SafeMarkdownReadWebView(
                documentID: document.relativePath,
                document: document,
                htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
                presentationCSS: "", userCSS: "",
                onLinkClick: { [lifetime] _ in lifetime.observe() },
                onOpenExternalURL: { _ in },
                onAskAgent: inquire,
                onSelectionActionPresenterReady: { [presenterPort] presenter in
                    presenterPort.presenter = presenter
                },
                onRenderingFailure: { [lifetime, callbacks] message in
                    lifetime.observe()
                    callbacks.didFail(message)
                },
                onRenderingReady: { [lifetime, callbacks] in
                    lifetime.observe()
                    callbacks.didBecomeReady()
                },
                pageExtension: HeldReadinessPage())
            let host = NSHostingController(rootView: AnyView(surface))
            self.host = host
            window.contentViewController = host
            window.orderFrontRegardless()
        }

        var sourceIsExact: Bool { document.sourceBytes == Data(source.utf8) }
        var hasMountedOwners: Bool {
            autoreleasepool { webView != nil && coordinator != nil && callbackLifetime != nil }
        }
        var hasReleasedOwners: Bool {
            autoreleasepool { webView == nil && coordinator == nil && callbackLifetime == nil }
        }
        var hasReleasedCallbackOwners: Bool {
            autoreleasepool { coordinator == nil && callbackLifetime == nil }
        }
        var nativeViewHasReleased: Bool { autoreleasepool { webView == nil } }

        func retainWebViewForLateResult() -> WKWebView? { autoreleasepool { webView } }

        func prepareHeldSelectionPresentation() async throws {
            try await waitForHeldReadiness()
            guard let view = webView else {
                Issue.record("The selection fixture lost its mounted WebView")
                throw SelectionFixtureFailure.missingWebView
            }
            _ = try await view.callAsyncJavaScript(
                "window.__scholiumTeardownReadiness.release();", arguments: [:], in: nil,
                contentWorld: SafeMarkdownReadWebView.bridgeContentWorld)
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while callbacks.ready != 1 || selectionPresenterPort.presenter == nil {
                try #require(callbacks.failures.isEmpty)
                try #require(ContinuousClock.now < deadline, "The reader did not finish normal initialization before the selection command")
                try await Task.sleep(for: .milliseconds(20))
            }
            _ = try await view.callAsyncJavaScript(
                """
                const ready = window.scholiumReadReady;
                let release;
                const held = new Promise(resolve => { release = resolve; });
                const show = window.scholiumShowSelectionActions;
                const state = window.__scholiumTeardownReadiness = {
                    reads: 0, released: false, selectionCalls: 0, selectionSettled: 0,
                    release() { state.released = true; release(); }
                };
                Object.defineProperty(window, 'scholiumReadReady', {
                    configurable: true,
                    get() { state.reads++; return Promise.all([ready, held]); }
                });
                window.scholiumShowSelectionActions = async (...args) => {
                    state.selectionCalls++;
                    try { return await show?.(...args); }
                    finally { state.selectionSettled++; }
                };
                """,
                arguments: [:], in: nil, contentWorld: SafeMarkdownReadWebView.bridgeContentWorld)
        }

        func startSelectionPresenter(observation: SelectionPresenterObservation) throws -> Task<Void, any Error> {
            let presenter = try #require(selectionPresenterPort.presenter)
            return Task { @MainActor in
                defer { observation.finishes += 1 }
                _ = try await presenter(.ask)
                observation.returnedNormally = true
            }
        }

        func waitForSelectionPresenterToEnterReadiness() async throws {
            guard let view = webView else { throw SelectionFixtureFailure.missingWebView }
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while (try await view.callAsyncJavaScript(
                """
                const state = window.__scholiumTeardownReadiness;
                return state.reads > 0 && !state.released && state.selectionCalls === 0;
                """, arguments: [:], in: nil,
                contentWorld: SafeMarkdownReadWebView.bridgeContentWorld)) as? Bool != true
            {
                try #require(ContinuousClock.now < deadline, "The selection command did not enter its own held readiness call")
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        func releaseSecondGateAndObserveLatePresenter() async throws {
            guard let view = webView else { throw SelectionFixtureFailure.missingWebView }
            _ = try await view.callAsyncJavaScript(
                "window.__scholiumTeardownReadiness.release();", arguments: [:], in: nil,
                contentWorld: SafeMarkdownReadWebView.bridgeContentWorld)
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while (try await view.callAsyncJavaScript(
                """
                const state = window.__scholiumTeardownReadiness;
                return state.released && state.selectionCalls === 1 && state.selectionSettled === 1;
                """, arguments: [:], in: nil,
                contentWorld: SafeMarkdownReadWebView.bridgeContentWorld)) as? Bool != true
            {
                try #require(ContinuousClock.now < deadline, "The old physical selection call did not return after its gate released")
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(
                try await view.evaluateJavaScript(
                    "document.querySelector('#scholium-document') !== null", in: nil,
                    contentWorld: SafeMarkdownReadWebView.bridgeContentWorld) as? Bool == true)
        }

        private enum SelectionFixtureFailure: Error { case missingWebView }

        func waitForHeldReadiness() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !(try await heldReadinessHasEntered()) {
                try #require(ContinuousClock.now < deadline, "The real reader did not enter its held readiness call")
                try await Task.sleep(for: .milliseconds(20))
            }
            try #require(sourceIsExact)
        }

        private func heldReadinessHasEntered() async throws -> Bool {
            let mountedView: WKWebView? = autoreleasepool {
                guard let host, let view = Self.findWebView(in: host.view) else { return nil }
                webView = view
                // Objective-C delegate getters and weak loads must not leave
                // the observer's own retain in the test runner's outer pool.
                coordinator = view.navigationDelegate as? SafeMarkdownReadWebView.Coordinator
                return view
            }
            guard let view = mountedView else { return false }
            // This round trip never awaits scholiumReadReady itself. Both the
            // real production initialization and a getter awaiting the held
            // promise must be observable before teardown is admitted.
            let result = try await view.callAsyncJavaScript(
                """
                const state = window.__scholiumTeardownReadiness;
                return Boolean(state?.productionSettled && state.reads > 0 && !state.released
                    && document.querySelector('#scholium-document')?.textContent.includes(marker));
                """,
                arguments: ["marker": "Exact Cafe\u{301} 中文🦉"],
                in: nil, contentWorld: SafeMarkdownReadWebView.bridgeContentWorld)
            return result as? Bool == true
        }

        func unmount() {
            callbacks.hasDeparted = true
            host?.rootView = AnyView(EmptyView())
            window.contentViewController = nil
            host = nil
        }

        func releaseGateForFailureCleanup() async {
            if let webView {
                _ = try? await webView.callAsyncJavaScript(
                    "window.__scholiumTeardownReadiness?.release();",
                    arguments: [:], in: nil,
                    contentWorld: SafeMarkdownReadWebView.bridgeContentWorld)
                webView.stopLoading()
            }
        }

        func close() {
            unmount()
            window.orderOut(nil)
            window.close()
        }

        private static func findWebView(in view: NSView) -> WKWebView? {
            if let view = view as? WKWebView { return view }
            for child in view.subviews {
                if let found = findWebView(in: child) { return found }
            }
            return nil
        }
    }

    @MainActor
    private final class HeldReadinessPage: ScholiumReadPageExtension {
        let requiresMathRuntime = false
        let replyProjectionEnabled = false
        func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
            HeldReadinessWebView(frame: .zero, configuration: configuration)
        }
        func preservesPage(currentDocumentID: String, nextDocumentID: String, hasLoadedPage: Bool) -> Bool { false }
        func canUpdateInPlace(currentDocumentID: String, nextDocumentID: String, hasLoadedPage: Bool) -> Bool { false }
        func acceptsMessageWithoutCurrentFingerprint(type: String) -> Bool { false }
        func willBeginLoad(fingerprint: String) {}
        func updateIfNeeded(
            body: String, source: String, fingerprint: String, signature: String, documentID: String,
            loadGeneration: UInt64, presentationCSS: String, userCSS: String, in webView: WKWebView,
            isCurrent: @escaping @MainActor () -> Bool,
            didApply: @escaping @MainActor (String, String) -> Void,
            didFail: @escaping @MainActor (any Error) -> Void
        ) -> Bool { false }
        func didFinishNavigation(_ navigation: WKNavigation?, isCurrent: @escaping @MainActor () -> Bool) {}
        func didFinalizePage(fingerprint: String) {}
        func handleMessage(type: String, payload: [String: Any], webView: WKWebView?) -> Bool { false }
        func cancel() {}
    }

    @MainActor
    private final class HeldReadinessWebView: DocumentNativeWebView {
        override func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
            // Product construction has already installed and cleared its own
            // scripts. Add the test barrier to that same named content world.
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: Self.gateScript, injectionTime: .atDocumentStart,
                    forMainFrameOnly: true, in: SafeMarkdownReadWebView.bridgeContentWorld))
            return super.loadHTMLString(string, baseURL: baseURL)
        }

        private static let gateScript = """
            (() => {
                let productionReady = Promise.resolve();
                let release;
                const held = new Promise(resolve => { release = resolve; });
                const state = window.__scholiumTeardownReadiness = {
                    reads: 0, productionSettled: false, released: false,
                    release() { state.released = true; release(); }
                };
                Object.defineProperty(window, 'scholiumReadReady', {
                    configurable: true,
                    get() {
                        state.reads++;
                        return Promise.all([productionReady, held]);
                    },
                    set(value) {
                        productionReady = Promise.resolve(value).then(() => { state.productionSettled = true; });
                    }
                });
            })();
            """
    }
}
