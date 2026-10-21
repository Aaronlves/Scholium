import Foundation
import ScholiumContracts
import Testing
import WebKit

@testable import ScholiumApp

extension MarkdownEditorWebViewIntegrationTests {
    @Test("A Review projection update sends its full presentation once while mode and configuration converge")
    func reviewProjectionPresentationHasSingleFlight() async throws {
        let source =
            "\u{FEFF}# Synthetic presentation\r\n\r\n"
            + (0..<128).map {
                "Paragraph \($0): disposable source preserves 中文, 🦉 and cafe\u{301}.\r\n\r\n"
            }.joined()
        let bridge = PresentationConvergenceBarrier()
        let harness = EditorHarness(
            source: source, bridgeDispatcher: bridge, initialMode: .review,
            ordersWindowFront: false)
        defer {
            bridge.release()
            harness.close()
        }
        let document = NoteDocument(relativePath: harness.documentID, rawContent: source)
        let rendered = SafeMarkdownRenderer.render(document).htmlBody
        func review(css: String) -> SafeMarkdownReadWebView {
            SafeMarkdownReadWebView(
                documentID: harness.documentID, documentTitle: "Synthetic presentation", document: document,
                htmlBody: rendered, presentationCSS: css, userCSS: "",
                configurationRevision: document.fingerprint.sha256,
                onLinkClick: { _ in }, onOpenExternalURL: { _ in },
                onSelectionChange: { _ in }, onRenderingFailure: { Issue.record(Comment(rawValue: $0)) })
        }
        harness.configureReview(review(css: ""))
        do {
            try await harness.waitUntilReady()
            try await harness.waitUntilPresentedMode(.review)
            let webView = try #require(harness.session.webView)
            // Establish a real source-neutral WebKit response after initial
            // Review readiness before arming the measured update.
            _ = try await harness.session.send(.queryContext, in: webView)
            _ = try await harness.callPageJavaScript(
                """
                const root = document.querySelector('main#scholium-document');
                const text = root.querySelector('p').firstChild;
                const range = document.createRange(); range.setStart(text, 0); range.setEnd(text, 9);
                const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
                window.__presentationConvergenceProbe = {root, selected: selection.toString()};
                """)

            let css = ".scholium-document { --presentation-convergence-fixture: 1; }"
            bridge.arm()
            harness.configureReview(review(css: css))
            // Keep the first real WebKit response suspended. Both callers must
            // join this delivery instead of queueing the same full HTML again.
            try await bridge.waitUntilSuspended()
            bridge.release()
            _ = try await harness.session.send(.queryContext, in: webView)
            let sample = bridge.finishSample()
            print(
                "REVIEW_PRESENTATION_CONVERGENCE requests=\(sample.requests) request_bytes=\(sample.bytes) elapsed_ms=\(sample.milliseconds) source_bytes=\(source.utf8.count)"
            )
            #expect(sample.requests == 1, "A single projection update must not deliver its full HTML twice.")
            #expect(sample.bytes > rendered.utf8.count)
            let presentation = try #require(
                try await harness.callPageJavaScript(
                    """
                    const root = document.querySelector('main#scholium-document');
                    return {sameRoot: root === window.__presentationConvergenceProbe.root,
                        selected: window.getSelection()?.toString(),
                        expectedSelected: window.__presentationConvergenceProbe.selected,
                        applied: getComputedStyle(root).getPropertyValue('--presentation-convergence-fixture').trim()};
                    """) as? [String: Any])
            #expect(presentation["applied"] as? String == "1")
            #expect(presentation["sameRoot"] as? Bool == true)
            #expect(presentation["selected"] as? String == presentation["expectedSelected"] as? String)
            #expect(harness.session.webView === webView)
            #expect(harness.session.presentedMode == .review)
            #expect(!harness.session.isDirty)
            #expect(Data(try await harness.session.currentText().utf8) == Data(source.utf8))
            await harness.closeAndDrain()
        } catch {
            bridge.release()
            await harness.closeAndDrain()
            throw error
        }
    }

    @Test("A pending Review presentation delivers the latest configuration after its in-flight response")
    func reviewPresentationConvergenceRetainsLatestConfiguration() async throws {
        try await withReviewPresentationFixture { harness, bridge in
            let webView = try #require(harness.session.webView)
            bridge.arm()
            harness.setDocumentTitle("First presentation")
            try await bridge.waitUntilSuspended()
            // Update the session synchronously at its actual suspension point;
            // the matching SwiftUI input prevents a later view update reverting it.
            harness.setDocumentTitle("Latest presentation")
            harness.session.setDocumentTitle("Latest presentation")
            bridge.release()
            try await bridge.waitUntilCompletedPresentations(2)
            #expect(bridge.presentations.map(\.configuration.documentTitle) == ["First presentation", "Latest presentation"])
            #expect(bridge.finishSample().requests == 2)
            harness.setMode(.livePreview)
            try await harness.waitUntilPresentedMode(.livePreview)
            #expect(
                try await harness.callPageJavaScript("return document.querySelector('[data-scholium-title-input]')?.value;") as? String
                    == "Latest presentation")
            #expect(harness.session.webView === webView)
            #expect(!harness.session.isDirty)
        }
    }

    @Test("A failed Review presentation remains pending and can be delivered again")
    func reviewPresentationConvergenceRetriesFailedDelivery() async throws {
        try await withReviewPresentationFixture { harness, bridge in
            bridge.arm(failsAfterApplication: true)
            harness.setDocumentTitle("Retry presentation")
            try await bridge.waitUntilSuspended()
            bridge.release()
            try await bridge.waitUntilCompletedPresentations(1)
            // The background delivery intentionally ignores transport failure.
            // Repeating a setter must retry rather than acknowledge that failure.
            // Dispatcher completion precedes the session's failure cleanup, so
            // retry the same value until that owner can start the next delivery.
            let retryDeadline = ContinuousClock.now.advanced(by: .seconds(5))
            while bridge.presentations.count < 2 {
                try #require(ContinuousClock.now < retryDeadline, "The failed presentation remained stuck instead of permitting retry.")
                harness.session.setDocumentTitle("Retry presentation")
                try await Task.sleep(for: .milliseconds(10))
            }
            try await bridge.waitUntilCompletedPresentations(2)
            let deliveries = bridge.presentations
            #expect(deliveries.count == 2)
            #expect(deliveries.first?.configuration == deliveries.last?.configuration)
            #expect(bridge.injectedFailureCount == 1)
            bridge.finishSample()
            harness.setMode(.livePreview)
            try await harness.waitUntilPresentedMode(.livePreview)
            #expect(
                try await harness.callPageJavaScript("return document.querySelector('[data-scholium-title-input]')?.value;") as? String
                    == "Retry presentation")
            #expect(!harness.session.isDirty)
        }
    }

    @Test("A cancelled old-page presentation cannot acknowledge or clear the replacement page's delivery")
    func reviewPresentationConvergenceRejectsOldPageResponse() async throws {
        try await withReviewPresentationFixture { harness, bridge in
            let oldWebView = try #require(harness.session.webView)
            let oldSessionID = harness.session.sessionID
            bridge.arm()
            harness.setDocumentTitle("Old page presentation")
            try await bridge.waitUntilSuspended()
            try await harness.detachEditorView()
            harness.setDocumentTitle("Current page presentation")
            harness.reattachEditorView()
            try await harness.waitUntilReady()
            try await harness.waitUntilPresentedMode(.review)
            let currentWebView = try #require(harness.session.webView)
            #expect(currentWebView !== oldWebView)
            #expect(harness.session.sessionID != oldSessionID)
            harness.setDocumentTitle("New page update")
            harness.session.setDocumentTitle("New page update")
            try await bridge.waitUntilCompletedPresentations(1)
            #expect(bridge.presentations.last?.sessionID == harness.session.sessionID)
            bridge.release()
            try await bridge.waitUntilCompletedPresentations(2)
            harness.setDocumentTitle("Final page update")
            harness.session.setDocumentTitle("Final page update")
            try await bridge.waitUntilCompletedPresentations(3)
            #expect(bridge.presentations.last?.configuration.documentTitle == "Final page update")
            #expect(bridge.presentations.last?.sessionID == harness.session.sessionID)
            bridge.finishSample()
            harness.setMode(.livePreview)
            try await harness.waitUntilPresentedMode(.livePreview)
            #expect(
                try await harness.callPageJavaScript("return document.querySelector('[data-scholium-title-input]')?.value;") as? String
                    == "Final page update")
            #expect(harness.session.webView === currentWebView)
            #expect(harness.session.errorMessage == nil)
            #expect(!harness.session.isDirty)
        }
    }

    private func withReviewPresentationFixture(
        _ body: @MainActor (EditorHarness, PresentationConvergenceBarrier) async throws -> Void
    ) async throws {
        let source = "\u{FEFF}# Synthetic concurrency\r\n\r\nDisposable 中文 🦉 cafe\u{301} source.\r\n"
        let bridge = PresentationConvergenceBarrier()
        let harness = EditorHarness(
            source: source, bridgeDispatcher: bridge, initialMode: .review,
            ordersWindowFront: false)
        defer {
            bridge.release()
            harness.close()
        }
        let document = NoteDocument(relativePath: harness.documentID, rawContent: source)
        harness.configureReview(
            SafeMarkdownReadWebView(
                documentID: harness.documentID, document: document,
                htmlBody: SafeMarkdownRenderer.render(document).htmlBody, presentationCSS: "", userCSS: "",
                configurationRevision: document.fingerprint.sha256,
                onLinkClick: { _ in }, onOpenExternalURL: { _ in },
                onRenderingFailure: { Issue.record(Comment(rawValue: $0)) }))
        do {
            try await harness.waitUntilReady()
            try await harness.waitUntilPresentedMode(.review)
            _ = try await harness.session.send(.queryContext, in: #require(harness.session.webView))
            try await body(harness, bridge)
            #expect(Data(try await harness.session.currentText().utf8) == Data(source.utf8))
            await harness.closeAndDrain()
        } catch {
            bridge.release()
            await harness.closeAndDrain()
            throw error
        }
    }

    @MainActor
    private final class PresentationConvergenceBarrier: MarkdownEditorBridgeDispatching {
        struct Presentation {
            let sessionID: UUID
            let configuration: MarkdownEditorPresentationConfiguration
        }
        private enum InjectedFailure: Error { case responseLostAfterApplication }
        private let production = WKWebViewMarkdownEditorBridgeDispatcher()
        private var continuation: CheckedContinuation<Void, Never>?
        private var armed = false
        private var suspended = false
        private var startedAt: ContinuousClock.Instant?
        private var requestCount = 0
        private var requestBytes = 0
        private var failsAfterApplication = false
        private var completedPresentations = 0
        private(set) var injectedFailureCount = 0
        private(set) var presentations: [Presentation] = []

        func arm(failsAfterApplication: Bool = false) {
            armed = true
            suspended = false
            requestCount = 0
            requestBytes = 0
            self.failsAfterApplication = failsAfterApplication
            completedPresentations = 0
            injectedFailureCount = 0
            presentations = []
            startedAt = .now
        }

        func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
            let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
            let measuresPresentation: Bool
            if armed, case .setPresentation(let configuration) = request.operation {
                measuresPresentation = true
                requestCount += 1
                requestBytes += requestJSON.utf8.count
                presentations.append(Presentation(sessionID: request.sessionID, configuration: configuration))
            } else {
                measuresPresentation = false
            }
            defer { if measuresPresentation { completedPresentations += 1 } }
            let result = try await production.dispatch(requestJSON: requestJSON, in: webView)
            if measuresPresentation, !suspended {
                suspended = true
                await withCheckedContinuation { continuation = $0 }
                if failsAfterApplication {
                    injectedFailureCount += 1
                    throw InjectedFailure.responseLostAfterApplication
                }
            }
            return result
        }

        func waitUntilCompletedPresentations(_ count: Int) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while completedPresentations < count {
                try #require(ContinuousClock.now < deadline, "The expected presentation responses did not finish.")
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        func waitUntilSuspended() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while continuation == nil {
                try #require(ContinuousClock.now < deadline, "The projection update did not reach its controlled WebKit response barrier.")
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        func release() {
            let pending = continuation
            continuation = nil
            pending?.resume()
        }

        @discardableResult
        func finishSample() -> (requests: Int, bytes: Int, milliseconds: Double) {
            armed = false
            let duration = startedAt?.duration(to: .now).components
            let milliseconds =
                duration.map {
                    Double($0.seconds) * 1_000 + Double($0.attoseconds) / 1_000_000_000_000_000
                } ?? 0
            return (requestCount, requestBytes, milliseconds)
        }
    }
}
