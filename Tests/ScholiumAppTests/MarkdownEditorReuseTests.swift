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

    @Test("A cleared idle page expires without discarding its document session")
    func idlePageExpires() async throws {
        let pool = MarkdownEditorWebViewPool(idleLifetime: .milliseconds(120))
        let harness = SwitchingHarness()
        defer {
            harness.close()
            pool.removeAll()
        }
        let source = "\u{FEFF}# Exact source\r\n\r\n中文 😀 e\u{301}。\r\n"
        let edited = source + "Added 🦉。\r\n"
        let session = makeSession(pool: pool)
        try await harness.show(session, source: source, title: "Exact")
        let previousWebView = WeakWebView(try #require(session.webView))
        do {
            let webView = try #require(session.webView)
            _ = try await session.send(
                .replacePassage(
                    expectedText: source, fromUTF16: 0, toUTF16: source.utf16.count,
                    replacement: edited, preserveSelection: false
                ), in: webView)
        }
        let selection = try #require(session.context?.selections)
        #expect(session.context?.undoLabel != nil)
        try await harness.hideCapturingState()
        #expect(pool.hasPreparedView)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while pool.hasPreparedView && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!pool.hasPreparedView)
        let releaseDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while previousWebView.value != nil && ContinuousClock.now < releaseDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(previousWebView.value == nil)
        let reopenStartedAt = ContinuousClock.now
        try await harness.show(session, source: source, title: "Exact")
        let reopenElapsed = reopenStartedAt.duration(to: ContinuousClock.now).components
        let reopenMilliseconds =
            Double(reopenElapsed.seconds) * 1_000
            + Double(reopenElapsed.attoseconds) / 1e15
        print("EDITOR_EXPIRED_REOPEN_PREPARATION_MS=\(String(format: "%.3f", reopenMilliseconds))")
        #expect(session.webView !== previousWebView.value)
        #expect(Data(try await session.currentText().utf8) == Data(edited.utf8))
        #expect(session.context?.selections == selection)
        #expect(session.context?.undoLabel != nil)
        try await harness.undo()
        #expect(Data(try await session.currentText().utf8) == Data(source.utf8))
        await harness.closeAndDrain()
    }

    @Test("Taking and replacing an idle page cancels its old expiry")
    func oldExpiryCannotEvictReplacement() async throws {
        let pool = MarkdownEditorWebViewPool(idleLifetime: .milliseconds(500))
        let harness = SwitchingHarness()
        defer {
            harness.close()
            pool.removeAll()
        }
        let session = makeSession(pool: pool)
        try await harness.show(session, source: "# Timer\n", title: "Timer")
        try await harness.hideCapturingState()
        try await Task.sleep(for: .milliseconds(300))
        let webView = try #require(pool.take())
        #expect(!pool.hasPreparedView)
        pool.recycle(webView)
        let admissionDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !pool.hasPreparedView && ContinuousClock.now < admissionDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(pool.hasPreparedView)
        try await Task.sleep(for: .milliseconds(250))
        #expect(pool.hasPreparedView)
        pool.invalidate()
        #expect(!pool.hasPreparedView)
        #expect(pool.take() == nil)
        await harness.closeAndDrain()
    }

    @Test("Direct SwiftUI A to B to A replacement reuses one safely prepared runtime")
    func directReplacementUsesPreparedRuntime() async throws {
        let pool = MarkdownEditorWebViewPool()
        let harness = SwitchingHarness()
        defer {
            harness.close()
            pool.removeAll()
        }
        let sessions = (0..<2).map { _ in makeSession(pool: pool) }
        let sources = [
            "\u{FEFF}# A\r\n\r\n中文 😀 e\u{301}。\r\n",
            "# B\r\n\r\n独立 🦉。\r\n",
        ]
        let editedA = sources[0] + "新增 😀。\r\n"
        let editedB = sources[1] + "只属于 B。\r\n"
        var pageSentinels: Set<String> = []
        var observedViews: [WeakWebView] = []
        for (step, index) in [0, 1, 0].enumerated() {
            let session = sessions[index]
            if step == 0 {
                try await harness.show(session, source: sources[index], title: "A", mode: .livePreview)
            } else {
                // One SwiftUI update replaces identity. There is no empty
                // intermediate state or wait for pool admission in this path.
                try await harness.replace(session, source: sources[index], title: index == 0 ? "A" : "B", mode: .livePreview)
                #expect(!sessions[1 - index].hasAttachedWebView)
            }
            let webView = try #require(session.webView)
            if !observedViews.contains(where: { $0.value === webView }) {
                observedViews.append(WeakWebView(webView))
            }
            let sentinel = try #require(
                try await webView.callAsyncJavaScript(
                    "window.reuseTestNavigationSentinel ??= candidate; return window.reuseTestNavigationSentinel;",
                    arguments: ["candidate": "page-\(step)"], in: nil, contentWorld: .page) as? String)
            pageSentinels.insert(sentinel)
            if step == 0 {
                _ = try await session.send(
                    .replacePassage(
                        expectedText: sources[0], fromUTF16: 0,
                        toUTF16: sources[0].utf16.count,
                        replacement: editedA, preserveSelection: false
                    ), in: webView)
                #expect(Data(try await session.currentText().utf8) == Data(editedA.utf8))
            } else if step == 1 {
                #expect(Data(try await session.currentText().utf8) == Data(sources[1].utf8))
                #expect(session.context?.undoLabel == nil)
                _ = try await session.send(
                    .replacePassage(
                        expectedText: sources[1], fromUTF16: 0,
                        toUTF16: sources[1].utf16.count,
                        replacement: editedB, preserveSelection: false
                    ), in: webView)
                #expect(Data(try await session.currentText().utf8) == Data(editedB.utf8))
            } else {
                #expect(Data(try await session.currentText().utf8) == Data(editedA.utf8))
                #expect(session.context?.undoLabel != nil)
                try await harness.undo()
                #expect(Data(try await session.currentText().utf8) == Data(sources[0].utf8))
                #expect(Data(sessions[1].checkedSource.utf8) == Data(editedB.utf8))
            }
        }
        #expect(observedViews.count == 1)
        #expect(pageSentinels.count == 1)
        await harness.closeAndDrain()
    }

    @Test("A page retires after its bounded safe reuses without losing document history")
    func boundedReuseRetiresDetachedPage() async throws {
        let pool = MarkdownEditorWebViewPool(maximumSafeReuses: 2)
        let harness = SwitchingHarness()
        defer {
            harness.close()
            pool.removeAll()
        }
        let sourceA = "\u{FEFF}# A\r\n\r\n中文 😀 e\u{301}。\r\n"
        let sourceB = "# B\r\n\r\n独立 🦉。\r\n"
        let sourceC = "# C\n"
        let editedA = sourceA + "A 的修改。\r\n"
        let editedB = sourceB + "B 的修改。\r\n"
        let a = makeSession(pool: pool)
        let b = makeSession(pool: pool)
        let c = makeSession(pool: pool)

        try await harness.show(a, source: sourceA, title: "A")
        var firstPage: WindowAttachedWebView? = try #require(a.webView as? WindowAttachedWebView)
        let retiredPage = WeakWebView(try #require(firstPage))
        _ = try await a.send(
            .replacePassage(
                expectedText: sourceA, fromUTF16: 0, toUTF16: sourceA.utf16.count,
                replacement: editedA, preserveSelection: false
            ), in: try #require(firstPage))

        try await harness.replace(b, source: sourceB, title: "B")
        #expect(b.webView === firstPage)
        #expect(firstPage?.editorReuseCount == 1)
        _ = try await b.send(
            .replacePassage(
                expectedText: sourceB, fromUTF16: 0, toUTF16: sourceB.utf16.count,
                replacement: editedB, preserveSelection: false
            ), in: try #require(firstPage))

        try await harness.replace(a, source: sourceA, title: "A")
        #expect(a.webView === firstPage)
        #expect(firstPage?.editorReuseCount == 2)
        #expect(Data(try await a.currentText().utf8) == Data(editedA.utf8))

        try await harness.replace(c, source: sourceC, title: "C")
        #expect(c.webView !== firstPage)
        #expect((c.webView as? WindowAttachedWebView)?.editorReuseCount == 0)
        #expect(Data(try await c.currentText().utf8) == Data(sourceC.utf8))
        // A delayed duplicate recycle cannot resurrect the retired page.
        pool.recycle(try #require(firstPage))
        #expect(pool.take() == nil)
        firstPage = nil
        let releaseDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while retiredPage.value != nil && ContinuousClock.now < releaseDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(retiredPage.value == nil)

        try await harness.replace(b, source: sourceB, title: "B")
        #expect(Data(try await b.currentText().utf8) == Data(editedB.utf8))
        try await harness.undo()
        #expect(Data(try await b.currentText().utf8) == Data(sourceB.utf8))
        #expect(Data(a.checkedSource.utf8) == Data(editedA.utf8))
        await harness.closeAndDrain()
    }

    @Test("A cancelled acquisition cannot take the outgoing page from its successor")
    func cancelledAcquisitionCannotStealPreparedPage() async throws {
        let gate = PreparationGate()
        let pool = MarkdownEditorWebViewPool(preparationGate: { await gate.pauseOnce() })
        let harness = SwitchingHarness()
        defer {
            gate.resume()
            harness.close()
            pool.removeAll()
        }
        let first = makeSession(pool: pool)
        try await harness.show(first, source: "# First\r\n\r\n中文 😀。\r\n", title: "First")
        let webView = try #require(first.webView)
        let cancelledPage = AcquiredPage()
        let cancelled = Task { @MainActor in
            cancelledPage.value = await pool.takeWhenPrepared()
        }
        try await waitForAcquisitions(pool, count: 1)
        cancelled.cancel()
        await cancelled.value
        #expect(cancelledPage.value == nil)
        let successorPage = AcquiredPage()
        let successor = Task { @MainActor in
            successorPage.value = await pool.takeWhenPrepared()
        }
        try await waitForAcquisitions(pool, count: 1)
        try await harness.hideWithoutWaitingForPool()
        try await gate.waitUntilPaused()
        #expect(!first.hasAttachedWebView)
        #expect(pool.waitingAcquisitionCount == 1)
        gate.resume()
        await successor.value
        let handedOff = try #require(successorPage.value)
        #expect(handedOff === webView)
        #expect(pool.waitingAcquisitionCount == 0)
        pool.recycle(handedOff)
        await harness.closeAndDrain()
    }

    @Test("A pending SwiftUI mount cannot attach after B is replaced by C")
    func replacedPendingMountCannotAttach() async throws {
        let gate = PreparationGate()
        let pool = MarkdownEditorWebViewPool(preparationGate: { await gate.pauseOnce() })
        let harness = SwitchingHarness()
        defer {
            gate.resume()
            harness.close()
            pool.removeAll()
        }
        let first = makeSession(pool: pool)
        let discarded = makeSession(pool: pool)
        let successor = makeSession(pool: pool)
        try await harness.show(first, source: "# A\r\n\r\n中文 😀。\r\n", title: "A")
        let originalPage = try #require(first.webView)
        _ = try await originalPage.callAsyncJavaScript(
            "window.reuseTestNavigationSentinel = 'original-page';",
            arguments: [:], in: nil, contentWorld: .page)
        try await harness.beginReplacement(
            discarded, source: "# B\n", title: "B")
        try await gate.waitUntilPaused()
        try await waitForAcquisitions(pool, count: 1)
        #expect(!discarded.hasAttachedWebView)
        let serial = pool.acquisitionSerial
        harness.replacePending(successor, source: "# C\r\n\r\n独立 🦉。\r\n", title: "C")
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while pool.acquisitionSerial == serial {
            guard ContinuousClock.now < deadline else {
                Issue.record("C did not register a pending page acquisition.")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        gate.resume()
        try await harness.waitForPrepared(successor)
        #expect(!discarded.hasAttachedWebView)
        #expect(successor.webView === originalPage)
        #expect(try await harness.javascript("return window.reuseTestNavigationSentinel;") as? String == "original-page")
        await harness.closeAndDrain()
    }

    @Test("Window invalidation resumes a waiting mount without publishing a late page")
    func invalidationWhilePreparingResumesWaiter() async throws {
        let gate = PreparationGate()
        let pool = MarkdownEditorWebViewPool(preparationGate: { await gate.pauseOnce() })
        let harness = SwitchingHarness()
        defer {
            gate.resume()
            harness.close()
            pool.removeAll()
        }
        let first = makeSession(pool: pool)
        try await harness.show(first, source: "# First\n", title: "First")
        let pendingPage = AcquiredPage()
        let pending = Task { @MainActor in
            pendingPage.value = await pool.takeWhenPrepared()
        }
        try await waitForAcquisitions(pool, count: 1)
        try await harness.hideWithoutWaitingForPool()
        try await gate.waitUntilPaused()
        pool.invalidate()
        await pending.value
        #expect(pendingPage.value == nil)
        gate.resume()
        await Task.yield()
        #expect(!pool.hasPreparedView)
        #expect(pool.waitingAcquisitionCount == 0)
        await harness.closeAndDrain()
    }

    @Test("An unanswered outgoing reset expires and cannot reclaim the new page")
    func expiredAcquisitionFallsBackToFreshPage() async throws {
        let gate = PreparationGate()
        let pool = MarkdownEditorWebViewPool(
            acquisitionDeadline: .milliseconds(400),
            preparationGate: { await gate.pauseOnce() })
        let harness = SwitchingHarness()
        defer {
            gate.resume()
            harness.close()
            pool.removeAll()
        }
        let first = makeSession(pool: pool)
        let second = makeSession(pool: pool)
        let sourceB = "\u{FEFF}# B\r\n\r\n新页 😀 e\u{301}。\r\n"
        try await harness.show(first, source: "# A\n", title: "A")
        let oldPage = try #require(first.webView)
        try await harness.beginReplacement(second, source: sourceB, title: "B")
        try await gate.waitUntilPaused()
        #expect(!second.hasAttachedWebView)
        try await harness.waitForPrepared(second)
        let newPage = try #require(second.webView)
        #expect(newPage !== oldPage)
        #expect(Data(try await second.currentText().utf8) == Data(sourceB.utf8))
        #expect(pool.waitingAcquisitionCount == 0)
        gate.resume()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while pool.preparationSettledSerial == 0 {
            guard ContinuousClock.now < deadline else {
                Issue.record("The abandoned reset did not settle after its gate was released.")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!pool.hasPreparedView)
        #expect(pool.take() == nil)
        #expect(second.webView === newPage)
        #expect(Data(try await second.currentText().utf8) == Data(sourceB.utf8))
        await harness.closeAndDrain()
    }

    private func waitForAcquisitions(_ pool: MarkdownEditorWebViewPool, count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while pool.waitingAcquisitionCount != count {
            guard ContinuousClock.now < deadline else {
                Issue.record("The expected page acquisition was not registered.")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    private final class AcquiredPage {
        var value: WindowAttachedWebView?
    }

    @MainActor
    private final class PreparationGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var intercepted = false

        func pauseOnce() async {
            guard !intercepted else { return }
            intercepted = true
            await withCheckedContinuation { continuation = $0 }
        }

        func waitUntilPaused() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while continuation == nil {
                guard ContinuousClock.now < deadline else {
                    Issue.record("The outgoing page did not reach its preparation gate.")
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
            try await beginReplacement(session, source: source, title: title, mode: mode)
            try await waitUntilPrepared(session)
        }

        func beginReplacement(
            _ session: MarkdownEditorSession, source: String, title: String,
            mode: MarkdownEditorMode = .source
        ) async throws {
            let previous = try #require(attachment.current?.session)
            try await previous.captureStateForViewReconstruction()
            attachment.current = Document(session: session, source: source, title: title, mode: mode)
            try await wait("Previous editor did not detach") { !previous.hasAttachedWebView }
        }

        func replacePending(
            _ session: MarkdownEditorSession, source: String, title: String,
            mode: MarkdownEditorMode = .source
        ) {
            attachment.current = Document(session: session, source: source, title: title, mode: mode)
            hostingController?.view.layoutSubtreeIfNeeded()
        }

        func waitForPrepared(_ session: MarkdownEditorSession) async throws {
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
            let pool = attachment.current?.session.webViewPool
            try await hideWithoutWaitingForPool()
            if let pool {
                try await wait("The detached runtime was not prepared for reuse") { pool.hasPreparedView }
            }
        }

        func hideWithoutWaitingForPool() async throws {
            let session = try #require(attachment.current?.session)
            try await session.captureStateForViewReconstruction()
            attachment.current = nil
            try await wait("SwiftUI did not detach the preceding editor") { !session.hasAttachedWebView }
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
