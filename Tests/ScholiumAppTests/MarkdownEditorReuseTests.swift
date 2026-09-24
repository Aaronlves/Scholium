import AppKit
import Combine
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Markdown editor document switching", .serialized)
@MainActor
struct MarkdownEditorReuseTests {
    @Test("Invalidating request bookkeeping does not recycle a still-running bridge dispatch")
    func bridgeDispatchMustActuallyFinishBeforeReuse() async throws {
        let dispatcher = SuspendingPerformanceDispatcher()
        let session = MarkdownEditorSession(bridgeDispatcher: dispatcher)
        let harness = SwitchingHarness()
        let source = "# Dispatch fixture\r\n\r\n中文 😀。\r\n"
        defer {
            dispatcher.resume()
            harness.close()
        }
        try await harness.show(session, source: source, title: "Dispatch")
        let query = Task { try await session.queryPerformanceSamples() }
        defer { query.cancel() }
        try await dispatcher.waitUntilSuspended()
        #expect(!session.canRecycleWebView)

        // Commit acknowledgement invalidates the tracked request queue. The
        // dispatcher deliberately ignores that cancellation until resumed;
        // the physical bridge call still owns the old WebView throughout.
        let acknowledgement = try await session.acknowledgeCommittedSnapshot(
            expectedText: source,
            committedText: source,
            fingerprint: DocumentFingerprint(content: source),
            documentID: session.documentID)
        #expect(acknowledgement == .clean)
        #expect(!dispatcher.completed)
        #expect(!session.canRecycleWebView)

        dispatcher.resume()
        do {
            _ = try await query.value
            Issue.record("The query from the superseded request epoch was accepted.")
        } catch MarkdownEditorSession.SessionError.staleRequest {
            // Expected: the commit advanced request identity.
        } catch is CancellationError {
            // A lifecycle deadline may surface the queue cancellation first.
        } catch {
            Issue.record("The invalidated query failed for an unexpected reason: \(error)")
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !dispatcher.completed || !session.canRecycleWebView {
            guard ContinuousClock.now < deadline else {
                Issue.record("The completed bridge dispatch did not release runtime reuse admission.")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(session.canRecycleWebView)
        #expect(Data(try await session.currentText().utf8) == Data(source.utf8))
        await harness.closeAndDrain()
    }

    @Test("A pooled runtime switches A to B to A without source, selection, or Undo leakage")
    func pooledRuntimePreservesDocumentState() async throws {
        let pool = MarkdownEditorWebViewPool()
        let harness = SwitchingHarness()
        defer {
            harness.close()
            pool.removeAll()
        }
        let sourceA = "\u{FEFF}# A\r\n\r\n原文 😀 e\u{301}。\r\n尾段\r\n"
        let sourceB = "# B\r\n\r\n独立笔记 🦉。\r\n"
        let sessionA = makeSession(pool: pool)
        let sessionB = makeSession(pool: pool)

        try await harness.show(sessionA, source: sourceA, title: "A")
        let firstWebView = try #require(sessionA.webView)
        let firstTransport = sessionA.sessionID
        _ = try await harness.javascript("window.reuseTestNavigationSentinel = 'first-navigation';")
        let editedA = sourceA + "新增 😀。\r\n"
        _ = try await sessionA.send(
            .replacePassage(
                expectedText: sourceA, fromUTF16: 0, toUTF16: sourceA.utf16.count,
                replacement: editedA, preserveSelection: false
            ), in: firstWebView)
        #expect(Data(try await sessionA.currentText().utf8) == Data(editedA.utf8))
        let selectionA = try #require(sessionA.context?.selections)
        #expect(sessionA.context?.undoLabel != nil)

        try await harness.hideCapturingState()
        #expect(!sessionA.hasAttachedWebView)
        try await harness.show(sessionB, source: sourceB, title: "B")
        #expect(sessionB.webView === firstWebView)
        #expect(try await harness.javascript("return window.reuseTestNavigationSentinel;") as? String == "first-navigation")
        #expect(Data(try await sessionB.currentText().utf8) == Data(sourceB.utf8))
        #expect(sessionB.context?.undoLabel == nil)
        try await harness.undo()
        #expect(Data(try await sessionB.currentText().utf8) == Data(sourceB.utf8))
        #expect(Data(sessionA.checkedSource.utf8) == Data(editedA.utf8))

        try await harness.hideCapturingState()
        // The parent input remains the opening snapshot. Reattachment must
        // restore A's checked dirty source instead of replaying stale input.
        try await harness.show(sessionA, source: sourceA, title: "A")
        #expect(!sessionB.hasAttachedWebView)
        #expect(sessionA.webView === firstWebView)
        #expect(sessionA.sessionID != firstTransport)
        #expect(try await harness.javascript("return window.reuseTestNavigationSentinel;") as? String == "first-navigation")
        #expect(Data(try await sessionA.currentText().utf8) == Data(editedA.utf8))
        #expect(sessionA.context?.selections == selectionA)
        #expect(sessionA.context?.undoLabel != nil)
        try await harness.undo()
        #expect(Data(try await sessionA.currentText().utf8) == Data(sourceA.utf8))
        #expect(Data(sessionB.checkedSource.utf8) == Data(sourceB.utf8))
        await harness.closeAndDrain()
    }

    @Test("A window pool cannot supply another window and clearing it evicts its cached surface")
    func poolIsolationAndEviction() async throws {
        let firstPool = MarkdownEditorWebViewPool()
        let secondPool = MarkdownEditorWebViewPool()
        let harness = SwitchingHarness()
        defer {
            harness.close()
            firstPool.removeAll()
            secondPool.removeAll()
        }
        let first = makeSession(pool: firstPool)
        let second = makeSession(pool: secondPool)
        try await harness.show(first, source: "# Window one\n", title: "One")
        let firstWebView = try #require(first.webView)
        try await harness.hideCapturingState()
        #expect(!first.hasAttachedWebView)
        #expect(secondPool.take() == nil)
        try await harness.show(second, source: "# Window two\n", title: "Two")
        #expect(second.webView !== firstWebView)
        #expect(first.checkedSource == "# Window one\n")
        let recycled = try #require(firstPool.take())
        #expect(recycled === firstWebView)
        firstPool.recycle(recycled)
        // Cancel while the new asynchronous admission is pending. Its late
        // completion must not repopulate the pool after the window clears it.
        firstPool.removeAll()
        #expect(firstPool.take() == nil)
        _ = try await recycled.callAsyncJavaScript(
            "return typeof window.scholiumEditor === 'object';",
            arguments: [:], in: nil, contentWorld: .page)
        await Task.yield()
        #expect(!firstPool.hasPreparedView)
        #expect(firstPool.take() == nil)
        #expect(second.hasAttachedWebView)
        #expect(try await second.currentText() == "# Window two\n")
        await harness.closeAndDrain()
    }

    @Test("Direct SwiftUI document replacement eventually reuses a prepared runtime")
    func directReplacementUsesPreparedRuntime() async throws {
        let pool = MarkdownEditorWebViewPool()
        let harness = SwitchingHarness()
        defer {
            harness.close()
            pool.removeAll()
        }
        let sessions = (0..<4).map { _ in makeSession(pool: pool) }
        var pageSentinels: Set<String> = []
        var observedViews: [WeakWebView] = []
        for index in sessions.indices {
            let source = "# Synthetic \(index)\r\n\r\n独立正文 😀 \(index)。\r\n"
            if index == 0 {
                try await harness.show(sessions[index], source: source, title: "\(index)", mode: .livePreview)
            } else {
                // One SwiftUI update replaces identity. There is no empty
                // intermediate state or wait for pool admission in this path.
                try await harness.replace(sessions[index], source: source, title: "\(index)", mode: .livePreview)
                #expect(!sessions[index - 1].hasAttachedWebView)
            }
            let webView = try #require(sessions[index].webView)
            if !observedViews.contains(where: { $0.value === webView }) {
                observedViews.append(WeakWebView(webView))
            }
            let sentinel = try #require(
                try await webView.callAsyncJavaScript(
                    "window.reuseTestNavigationSentinel ??= candidate; return window.reuseTestNavigationSentinel;",
                    arguments: ["candidate": "page-\(index)"], in: nil, contentWorld: .page) as? String)
            pageSentinels.insert(sentinel)
            #expect(Data(try await sessions[index].currentText().utf8) == Data(source.utf8))
            #expect(sessions[index].context?.undoLabel == nil)
        }
        // A replacement may allocate before the outgoing page is cleared;
        // subsequent replacements must consume an already prepared page.
        #expect(observedViews.count < sessions.count)
        #expect(pageSentinels.count < sessions.count)
        await harness.closeAndDrain()
    }

    @Test(
        "Synthetic attached editor preparation records bridge-ready and DOM-layout samples",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_EDITOR_REUSE_MEASURE"] == "1")
    )
    func syntheticSwitchMeasurement() async throws {
        // Predeclared protocol: identical synthetic sources, two discarded
        // warmups and five retained transitions per path, no latency gate.
        // The boundary is mounted bridge readiness plus nonzero DOM layout.
        // This internal preparation scenario does not measure visible paint,
        // responsiveness to input, or the complete app navigation journey.
        let baseline = try await measureSwitches(reusesRuntime: false)
        let reused = try await measureSwitches(reusesRuntime: true)
        for sample in [baseline, reused] {
            print(
                "EDITOR_SWITCH_PREPARATION_SCENARIO path=\(sample.name) warmups=2 retained=5 "
                    + "newWKWebViews=\(sample.newWebViewCount) "
                    + "milliseconds=\(sample.milliseconds.map { String(format: "%.3f", $0) }.joined(separator: ","))")
        }
        #expect(baseline.milliseconds.count == 5)
        #expect(reused.milliseconds.count == 5)
        #expect(baseline.newWebViewCount == 8)
        #expect(reused.newWebViewCount == 1)
    }

    private func makeSession(pool: MarkdownEditorWebViewPool?) -> MarkdownEditorSession {
        let session = MarkdownEditorSession()
        session.webViewPool = pool
        return session
    }

    private struct SwitchMeasurements {
        let name: String
        let milliseconds: [Double]
        let newWebViewCount: Int
    }

    private func measureSwitches(reusesRuntime: Bool) async throws -> SwitchMeasurements {
        let pool = reusesRuntime ? MarkdownEditorWebViewPool() : nil
        let harness = SwitchingHarness()
        defer {
            harness.close()
            pool?.removeAll()
        }
        let sources = ["A", "B"].map { name in
            "# Synthetic \(name)\r\n\r\n"
                + (0..<60).map { "Paragraph \($0): 中文 😀 e\u{301} synthetic source.\r\n\r\n" }.joined()
        }
        let sessions = [makeSession(pool: pool), makeSession(pool: pool)]
        var observedViews: [WeakWebView] = []
        func recordView(_ session: MarkdownEditorSession) throws {
            let webView = try #require(session.webView)
            if !observedViews.contains(where: { $0.value === webView }) {
                observedViews.append(WeakWebView(webView))
            }
        }
        try await harness.show(sessions[0], source: sources[0], title: "A", mode: .livePreview)
        try recordView(sessions[0])
        var milliseconds: [Double] = []
        for iteration in 0..<7 {
            let next = (iteration + 1) % 2
            let start = ContinuousClock.now
            try await harness.hideCapturingState()
            try await harness.show(
                sessions[next], source: sources[next], title: next == 0 ? "A" : "B", mode: .livePreview)
            let elapsed = start.duration(to: ContinuousClock.now).components
            if iteration >= 2 {
                milliseconds.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
            }
            try recordView(sessions[next])
            #expect(Data(try await sessions[next].currentText().utf8) == Data(sources[next].utf8))
        }
        await harness.closeAndDrain()
        return SwitchMeasurements(
            name: reusesRuntime ? "pooled" : "reconstructed",
            milliseconds: milliseconds,
            newWebViewCount: observedViews.count)
    }

    @MainActor
    private final class SuspendingPerformanceDispatcher: MarkdownEditorBridgeDispatching {
        private let production = WKWebViewMarkdownEditorBridgeDispatcher()
        private var continuation: CheckedContinuation<Void, Never>?
        private var intercepted = false
        private(set) var completed = false

        func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
            let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
            if !intercepted, case .queryPerformance = request.operation {
                intercepted = true
                // CheckedContinuation intentionally does not react to task
                // cancellation, matching an outstanding WebKit callback.
                await withCheckedContinuation { continuation = $0 }
                defer { completed = true }
                return try await production.dispatch(requestJSON: requestJSON, in: webView)
            }
            return try await production.dispatch(requestJSON: requestJSON, in: webView)
        }

        func waitUntilSuspended() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while continuation == nil {
                guard ContinuousClock.now < deadline else {
                    Issue.record("The performance query did not enter its suspended bridge dispatch.")
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        func resume() {
            continuation?.resume()
            continuation = nil
        }
    }

    @MainActor
    private final class WeakWebView {
        weak var value: WKWebView?
        init(_ value: WKWebView) { self.value = value }
    }

    @MainActor
    private final class Attachment: ObservableObject {
        @Published var current: Document?
    }

    private struct Document {
        let session: MarkdownEditorSession
        let source: String
        let title: String
        let mode: MarkdownEditorMode
    }

    @MainActor
    private final class SwitchingHarness {
        private let attachment = Attachment()
        private let window: NSWindow
        private let previousActivationPolicy: NSApplication.ActivationPolicy
        private var hostingController: NSViewController?
        private var closed = false

        init() {
            _ = NSApplication.shared
            previousActivationPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.regular)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let host = NSHostingController(
                rootView: SwitchingRoot(attachment: attachment)
                    .frame(width: 720, height: 520))
            host.sizingOptions = []
            hostingController = host
            window.contentViewController = host
            window.setContentSize(NSSize(width: 720, height: 520))
            host.view.frame = window.contentView?.bounds ?? .zero
            host.view.autoresizingMask = [.width, .height]
            host.view.layoutSubtreeIfNeeded()
            window.center()
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }

        func show(
            _ session: MarkdownEditorSession, source: String, title: String,
            mode: MarkdownEditorMode = .source
        ) async throws {
            #expect(attachment.current == nil)
            attachment.current = Document(session: session, source: source, title: title, mode: mode)
            try await waitUntilPrepared(session)
        }

        func replace(
            _ session: MarkdownEditorSession, source: String, title: String,
            mode: MarkdownEditorMode = .source
        ) async throws {
            let previous = try #require(attachment.current?.session)
            try await previous.captureStateForViewReconstruction()
            attachment.current = Document(session: session, source: source, title: title, mode: mode)
            try await waitUntilPrepared(session)
        }

        private func waitUntilPrepared(_ session: MarkdownEditorSession) async throws {
            try await wait("Target editor did not become ready in its window") {
                session.isReady && session.isLoaded && session.hasAttachedWebView
                    && session.webView?.window === self.window
            }
            hostingController?.view.layoutSubtreeIfNeeded()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            window.orderFrontRegardless()
            window.displayIfNeeded()
            // The standalone test helper establishes prepared DOM layout;
            // display-service paint requires a separate app-based journey.
            let laidOut =
                try await javascript(
                    """
                    const editor = document.querySelector('.cm-editor');
                    const rect = editor?.getBoundingClientRect();
                    return !!rect && rect.width > 0 && rect.height > 0
                        && document.querySelector('.cm-content')?.textContent.length > 0;
                    """) as? Bool
            #expect(laidOut == true)
        }

        func hideCapturingState() async throws {
            let session = try #require(attachment.current?.session)
            try await session.captureStateForViewReconstruction()
            attachment.current = nil
            try await wait("SwiftUI did not detach the preceding editor") { !session.hasAttachedWebView }
            if let pool = session.webViewPool {
                // Await production admission, which erases the preceding
                // document before publishing a reusable shell. Measurement
                // includes this wait in the transition's elapsed time.
                try await wait("The detached runtime was not prepared for reuse") { pool.hasPreparedView }
            }
        }

        func javascript(_ body: String, arguments: [String: Any] = [:]) async throws -> Any? {
            let webView = try #require(attachment.current?.session.webView)
            return try await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page)
        }

        func undo() async throws {
            _ = try await javascript(
                """
                document.querySelector('.cm-content').dispatchEvent(new KeyboardEvent('keydown', {
                    key: 'z', code: 'KeyZ', keyCode: 90, which: 90,
                    metaKey: true, bubbles: true, cancelable: true
                }));
                """)
        }

        private func wait(_ message: String, until predicate: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while !predicate() {
                guard ContinuousClock.now < deadline else {
                    Issue.record(Comment(rawValue: message))
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        func close() {
            guard !closed else { return }
            closed = true
            window.orderOut(nil)
            window.contentViewController = nil
            hostingController = nil
            window.close()
            NSApp.setActivationPolicy(previousActivationPolicy)
        }

        func closeAndDrain() async {
            let session = attachment.current?.session
            close()
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while session?.hasAttachedWebView == true, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            #expect(session?.hasAttachedWebView != true)
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    private struct SwitchingRoot: View {
        @ObservedObject var attachment: Attachment

        var body: some View {
            if let document = attachment.current {
                EditorSurface(
                    session: document.session, source: document.source,
                    title: document.title, mode: document.mode
                )
                .id(document.session.bridgeDocumentID)
            } else {
                Color.clear
            }
        }
    }

    private struct EditorSurface: View {
        @ObservedObject var session: MarkdownEditorSession
        let source: String
        let title: String
        let mode: MarkdownEditorMode

        var body: some View {
            DocumentEditorHost(
                documentID: session.openingPresentationID.uuidString,
                presentsEditor: true, retainsEditor: true, editorIsReady: session.isLoaded
            ) {
                Color.clear
            } editor: {
                MarkdownEditorWebView(
                    session: session,
                    documentID: session.bridgeDocumentID,
                    documentTitle: title,
                    performanceDocumentID: title,
                    source: source,
                    mode: mode,
                    presentationCSS: "",
                    userCSS: "",
                    requiresMathRuntime: false,
                    linkCompletionQuery: { _, _ in [] },
                    linkPreviews: [],
                    initialScrollFraction: 0,
                    initialScrollAnchor: nil,
                    onDocumentActivity: {},
                    onRequestSave: {},
                    onRequestFind: { _ in },
                    onRequestDocumentTitleRename: { _, requested in requested },
                    onPasteImage: { _ in false },
                    onLinkActivation: { _ in },
                    onScrollFractionChange: { _ in },
                    onScrollAnchorChange: { _ in })
            }
        }
    }
}
