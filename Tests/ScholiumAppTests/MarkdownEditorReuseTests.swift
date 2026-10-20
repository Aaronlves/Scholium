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
    @Test("Opening another leased tab never waits for or retires the retained editor")
    func leasedTabPageDoesNotBlockFreshAttachment() async throws {
        let store = DocumentSessionStore()
        let aKey = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        let bKey = DocumentSessionKey(vaultID: aKey.vaultID, noteID: UUID())
        let a = store.session(for: aKey).editorSession
        let pool = store.editorWebViewPool
        let aHarness = SwitchingHarness()
        let bHarness = SwitchingHarness()
        defer {
            bHarness.close()
            aHarness.close()
            store.removeAll()
        }
        let originalA = "\u{FEFF}# A\r\n\r\nRetained 中文 😀 e\u{301}。\r\n"
        let editedA = originalA + "A history remains exact.\r\n"
        let sourceB = "# B\n\nOnly B 🦉。\n"
        store.reconcileLeases(openTargets: [.workspace(aKey)], foregroundTarget: .workspace(aKey))
        try await aHarness.show(a, source: originalA, title: "A")
        let aPage = try #require(a.webView)
        _ = try await a.send(
            .replacePassage(
                expectedText: originalA, fromUTF16: 0, toUTF16: originalA.utf16.count,
                replacement: editedA, preserveSelection: false), in: aPage)
        try await a.captureStateForViewReconstruction(suspendForDetachment: true)
        let suspension = try #require(a.detachmentSuspensionID)
        let undo = try #require(a.context?.undoLabel)

        store.reconcileLeases(
            openTargets: [.workspace(aKey), .workspace(bKey)], foregroundTarget: .workspace(bKey))
        // Acquire B after its tab is leased; an unleased, unattached B
        // would correctly be reaped by the initial A-only reconciliation.
        let b = store.session(for: bKey).editorSession
        #expect(!pool.hasOutgoingView)
        let acquisitions = pool.acquisitionSerial
        #expect(await pool.takeWhenPrepared() == nil)
        try await bHarness.show(b, source: sourceB, title: "B")
        #expect(pool.acquisitionSerial == acquisitions)
        #expect(pool.waitingAcquisitionCount == 0)
        #expect(pool.qaDiagnosticCounts.abandonedLive == 0)
        #expect(a.webView === aPage)
        #expect(b.webView !== aPage)
        #expect(pool.qaDiagnosticCounts.attached == 2)
        #expect(a.context?.undoLabel == undo)
        #expect(Data(try await a.currentText().utf8) == Data(editedA.utf8))
        // B was created last and remains leased. A must still be available
        // as the outgoing donor when ordinary replacement releases its tab.
        store.reconcileLeases(openTargets: [.workspace(bKey)], foregroundTarget: .workspace(bKey))
        #expect(pool.hasOutgoingView)
        let departingPage = AcquiredPage()
        let departing = Task { @MainActor in departingPage.value = await pool.takeWhenPrepared() }
        defer { departing.cancel() }
        try await waitForAcquisitions(pool, count: 1)
        // Restoring A also releases B. The waiter bound to A must finish
        // instead of silently changing its timeout target to the new donor.
        store.reconcileLeases(openTargets: [.workspace(aKey)], foregroundTarget: .workspace(aKey))
        await departing.value
        #expect(departingPage.value == nil)
        #expect(pool.hasOutgoingView)
        #expect(pool.qaDiagnosticCounts.abandonedLive == 0)
        store.reconcileLeases(
            openTargets: [.workspace(aKey), .workspace(bKey)], foregroundTarget: .workspace(aKey))
        try await a.resumeAfterDetachment(suspensionID: suspension)
        try await aHarness.undo()
        #expect(Data(try await a.currentText().utf8) == Data(originalA.utf8))
        #expect(Data(try await b.currentText().utf8) == Data(sourceB.utf8))
        await bHarness.closeAndDrain()
        await aHarness.closeAndDrain()
    }

    @Test("Restoring an attached page's tab lease ends acquisition without a late retirement")
    func restoredTabLeaseCancelsPendingAcquisition() async throws {
        let pool = MarkdownEditorWebViewPool(acquisitionDeadline: .milliseconds(100))
        let a = makeSession(pool: pool)
        let harness = SwitchingHarness()
        defer {
            harness.close()
            pool.removeAll()
        }
        let source = "# Retained A\r\n\r\nUnchanged 中文 😀。\r\n"
        try await harness.show(a, source: source, title: "A")
        let page = try #require(a.webView)
        let acquiredPage = AcquiredPage()
        let acquired = Task { @MainActor in acquiredPage.value = await pool.takeWhenPrepared() }
        defer { acquired.cancel() }
        try await waitForAcquisitions(pool, count: 1)
        pool.reconcileTabLeases([a])
        await acquired.value
        #expect(acquiredPage.value == nil)
        #expect(pool.waitingAcquisitionCount == 0)
        try await Task.sleep(for: .milliseconds(150))
        #expect(!pool.hasOutgoingView)
        #expect(pool.qaDiagnosticCounts.abandonedLive == 0)
        #expect(a.webView === page)
        #expect(a.detachmentSuspensionID == nil)
        #expect(Data(try await a.currentText().utf8) == Data(source.utf8))
        await harness.closeAndDrain()
    }

    @Test("Transferring a session cannot leave a false outgoing page in its former pool")
    func transferredSessionCannotDonateToFormerPool() async throws {
        let origin = DocumentSessionStore()
        let destination = DocumentSessionStore()
        let key = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        let model = origin.session(for: key)
        let a = model.editorSession
        let pool = origin.editorWebViewPool
        let harness = SwitchingHarness()
        defer {
            harness.close()
            destination.removeAll()
            origin.removeAll()
        }
        let source = "# Transferred A\n\nExact source 😀。\n"
        origin.reconcileLeases(openTargets: [.workspace(key)], foregroundTarget: .workspace(key))
        try await harness.show(a, source: source, title: "A")
        let page = try #require(a.webView as? WindowAttachedWebView)
        #expect(origin.takeSession(for: .workspace(key)) === model)
        #expect(pool.qaDiagnosticCounts.attached == 0)
        destination.receiveSession(model, for: .workspace(key))
        #expect(a.webViewPool === destination.editorWebViewPool)
        // A late attachment observation must not turn a foreign page into
        // a donor, even before its former container has disappeared.
        pool.registerAttached(page)
        #expect(pool.qaDiagnosticCounts.attached == 0)
        #expect(!pool.hasOutgoingView)
        let acquisitions = pool.acquisitionSerial
        #expect(await pool.takeWhenPrepared() == nil)
        #expect(pool.acquisitionSerial == acquisitions)
        #expect(pool.qaDiagnosticCounts.abandonedLive == 0)
        #expect(a.webView === page)
        #expect(Data(try await a.currentText().utf8) == Data(source.utf8))
        await harness.closeAndDrain()
    }

    @Test("An older tab's acquisition timeout cannot retire a newer retained tab")
    func outgoingTimeoutCannotRetireAnotherRetainedPage() async throws {
        let pool = MarkdownEditorWebViewPool(acquisitionDeadline: .milliseconds(100))
        let a = makeSession(pool: pool)
        let b = makeSession(pool: pool)
        let aHarness = SwitchingHarness()
        let bHarness = SwitchingHarness()
        defer {
            bHarness.close()
            aHarness.close()
            pool.removeAll()
        }
        let sourceA = "# Outgoing A\r\n\r\nRetained exact A.\r\n"
        let sourceB = "\u{FEFF}# Retained B\r\n\r\n中文 😀 e\u{301}。\r\n"
        let editedB = sourceB + "B history.\r\n"
        pool.reconcileTabLeases([a, b])
        try await aHarness.show(a, source: sourceA, title: "A")
        try await bHarness.show(b, source: sourceB, title: "B")
        let bPage = try #require(b.webView)
        _ = try await b.send(
            .replacePassage(
                expectedText: sourceB, fromUTF16: 0, toUTF16: sourceB.utf16.count,
                replacement: editedB, preserveSelection: false), in: bPage)

        pool.reconcileTabLeases([b])
        #expect(pool.hasOutgoingView)
        #expect(await pool.takeWhenPrepared() == nil)
        #expect(pool.qaDiagnosticCounts.abandonedLive == 1)
        #expect(b.webView === bPage)
        #expect(Data(try await b.currentText().utf8) == Data(editedB.utf8))
        try await bHarness.undo()
        #expect(Data(try await b.currentText().utf8) == Data(sourceB.utf8))
        #expect(Data(try await a.currentText().utf8) == Data(sourceA.utf8))
        // Exclude A, then release B's lease. B is still a legitimate donor;
        // the timeout must not have blacklisted the last-created page.
        pool.forgetTransferredSession(a)
        pool.reconcileTabLeases([])
        #expect(pool.hasOutgoingView)
        await bHarness.closeAndDrain()
        await aHarness.closeAndDrain()
    }

    @Test("A detached page's reuse preparation remains waitable when its session regains a tab")
    func preparingPageRemainsWaitableAfterTabLeaseRestoration() async throws {
        let gate = PreparationGate()
        let pool = MarkdownEditorWebViewPool(preparationGate: { await gate.pauseOnce() })
        let a = makeSession(pool: pool)
        let harness = SwitchingHarness()
        defer {
            gate.resume()
            harness.close()
            pool.removeAll()
        }
        let source = "# Departing A\n\nSynthetic source.\n"
        try await harness.show(a, source: source, title: "A")
        let page = try #require(a.webView)
        let acquiredPage = AcquiredPage()
        let acquired = Task { @MainActor in acquiredPage.value = await pool.takeWhenPrepared() }
        defer { acquired.cancel() }
        try await waitForAcquisitions(pool, count: 1)
        try await harness.hideWithoutWaitingForPool()
        try await gate.waitUntilPaused()
        pool.reconcileTabLeases([a])
        #expect(pool.hasOutgoingView)
        #expect(pool.waitingAcquisitionCount == 1)
        #expect(!a.hasAttachedWebView)
        gate.resume()
        await acquired.value
        #expect(acquiredPage.value === page)
        #expect(pool.waitingAcquisitionCount == 0)
        #expect(pool.qaDiagnosticCounts.abandonedLive == 0)
        #expect(Data(a.checkedSource.utf8) == Data(source.utf8))
        await harness.closeAndDrain()
    }

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
        _ = try await harness.javascript(
            """
            const phases = ['document-start', 'bundle-start', 'entry', 'bundle-end'];
            const began = performance.now();
            phases.forEach((phase, index) => {
              const name = `scholium-editor:bootstrap-${phase}`;
              performance.clearMarks(name);
              performance.mark(name, {startTime: began + index});
            });
            """)

        try await harness.hideCapturingState()
        #expect(!sessionA.hasAttachedWebView)
        try await harness.show(sessionB, source: sourceB, title: "B")
        #expect(sessionB.webView === firstWebView)
        #expect(try await harness.javascript("return window.reuseTestNavigationSentinel;") as? String == "first-navigation")
        #expect(Data(try await sessionB.currentText().utf8) == Data(sourceB.utf8))
        #expect(sessionB.context?.undoLabel == nil)
        let samplesB = try await sessionB.queryPerformanceSamples()
        #expect(!samplesB.contains { $0.name == "bootstrap" })
        #expect(
            try await harness.javascript(
                """
                return ['document-start', 'bundle-start', 'entry', 'bundle-end'].every(phase =>
                  performance.getEntriesByName(`scholium-editor:bootstrap-${phase}`).length === 0);
                """) as? Bool == true)
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

    @Test("A frozen direct handoff stays quarantined until checked initialization without a blank reset")
    func frozenDirectHandoffPreservesDocumentIsolation() async throws {
        let pool = MarkdownEditorWebViewPool(acquisitionDeadline: .milliseconds(100))
        let dispatcher = HandoffInitializationDispatcher()
        let harness = SwitchingHarness()
        let a = makeSession(pool: pool)
        let b = MarkdownEditorSession(bridgeDispatcher: dispatcher)
        b.webViewPool = pool
        let originalA = "\u{FEFF}# A\r\n\r\nOnly A 中文 😀 e\u{301}。\r\n"
        let editedA = originalA + "Unsaved A。\r\n"
        let sourceB = "# B\n\nOnly B 🦉。\n"
        defer {
            dispatcher.gate.resume()
            harness.close()
            pool.removeAll()
        }
        try await harness.show(a, source: originalA, title: "A", mode: .livePreview)
        let page = try #require(a.webView as? WindowAttachedWebView)
        _ = try await a.send(
            .replacePassage(
                expectedText: originalA, fromUTF16: 0, toUTF16: originalA.utf16.count,
                replacement: editedA, preserveSelection: false), in: page)
        _ = try await harness.javascript(
            """
            window.handoffResetCount = 0;
            const reset = window.scholiumEditor.prepareForReuse;
            window.scholiumEditor.prepareForReuse = function() {
              window.handoffResetCount++;
              return reset.call(this);
            };
            document.getElementById('scholium-user-css').textContent = ':root { --handoff-old-owner: A; }';
            """)
        try await harness.beginReplacement(
            b, source: sourceB, title: "B", mode: .livePreview, suspendForDetachment: true)
        try await dispatcher.gate.waitUntilPaused()
        let lease = try #require(page.editorHandoffLease)
        #expect(b.webView === page)
        #expect(!lease.isRetired)
        #expect(lease.permitsInitialization)
        #expect(page.alphaValue == 0)
        #expect(!page.documentSurfaceAllowsInput)
        let container = try #require(page.superview as? DocumentWebViewContainer)
        #expect(container.accessibilityChildren()?.isEmpty == true)
        #expect(container.hitTest(.zero) == nil)
        #expect(!b.isLoaded)
        #expect(Data(b.checkedSource.utf8) == Data(sourceB.utf8))
        #expect(Data(a.checkedSource.utf8) == Data(editedA.utf8))
        #expect(try await harness.javascript("return window.handoffResetCount;") as? Int == 0)
        // The acquisition deadline must not become a shorter initialization
        // deadline after the destination has claimed the page.
        try await Task.sleep(for: .milliseconds(150))
        #expect(!lease.isRetired)
        dispatcher.gate.resume()
        try await harness.waitForPrepared(b)
        #expect(page.editorHandoffLease == nil)
        #expect(!lease.permitsInitialization)
        #expect(page.alphaValue == 1)
        #expect(Data(try await b.currentText().utf8) == Data(sourceB.utf8))
        #expect(b.context?.undoLabel == nil)
        #expect(try await harness.javascript("return window.handoffResetCount;") as? Int == 0)
        #expect(try await harness.javascript("return document.getElementById('scholium-user-css').textContent;") as? String == "")
        #expect(try await harness.javascript("return document.querySelector('[data-scholium-title-input]')?.value;") as? String == "B")
        try await harness.undo()
        #expect(Data(try await b.currentText().utf8) == Data(sourceB.utf8))
        try await harness.replace(
            a, source: originalA, title: "A", mode: .livePreview, suspendForDetachment: true)
        #expect(a.webView === page)
        #expect(Data(try await a.currentText().utf8) == Data(editedA.utf8))
        #expect(try await harness.javascript("return window.handoffResetCount;") as? Int == 0)
        try await harness.undo()
        #expect(Data(try await a.currentText().utf8) == Data(originalA.utf8))
        await harness.closeAndDrain()
    }

    @Test("A first attachment with synthetic pending-reload state waits for native completion")
    func firstAttachmentWaitsForObservedReload() async throws {
        let pool = MarkdownEditorWebViewPool()
        let harness = SwitchingHarness()
        let a = makeSession(pool: pool)
        let dispatcher = HandoffInitializationDispatcher()
        let b = MarkdownEditorSession(bridgeDispatcher: dispatcher)
        let sourceA = "\u{FEFF}# A\r\n\r\nFrozen A e\u{301} 😀。\r\n"
        let sourceB = "# B\r\n\r\nPending B 中文 🦉 without final newline"
        defer {
            dispatcher.gate.resume()
            harness.close()
            pool.removeAll()
        }
        try await harness.show(a, source: sourceA, title: "A")
        var acquiredPage: WindowAttachedWebView?
        let acquired = Task { @MainActor in
            acquiredPage = await pool.takeWhenPrepared()
        }
        defer { acquired.cancel() }
        try await waitForAcquisitions(pool, count: 1)
        try await harness.hideWithoutWaitingForPool(suspendForDetachment: true)
        await acquired.value
        let page = try #require(acquiredPage)
        let lease = try #require(page.editorHandoffLease)
        #expect(!lease.permitsInitialization)
        let coordinator = MarkdownEditorWebView.Coordinator(
            session: b, performanceDocumentID: "reload-ordering",
            onDocumentActivity: {}, onRequestSave: {}, onRequestFind: { _ in },
            onRequestDocumentTitleRename: { _, requested in requested },
            linkCompletionQuery: { _, _ in .current([]) }, onLinkActivation: { _ in },
            onImagePreview: { _ in }, onScrollFractionChange: { _ in }, onScrollAnchorChange: { _ in })
        let editorHTML = try #require(MarkdownEditorWebView.editorHTML)
        defer {
            b.detach(page)
            page.editorSession = nil
            page.navigationDelegate = nil
        }
        page.editorSession = b
        b.attach(page)
        b.loadDocument(sourceB, documentID: b.bridgeDocumentID, mode: .source)
        #expect(lease.permitsInitialization)
        coordinator.documentID = b.bridgeDocumentID
        // The real bundled page has completed its navigation. Inject only the
        // coordinator state left by an observed reload, independently of
        // WebKit's asynchronous stopLoading behavior; no process is killed.
        try #require(!page.isLoading)
        coordinator.awaitingEditorLoad = true
        #expect(coordinator.awaitingEditorLoad)
        #expect(!b.isReady && !b.isLoaded)
        #expect(dispatcher.initializationCount == 0)
        page.navigationDelegate = coordinator
        coordinator.resumePreparedPage(in: page, editorHTML: editorHTML)
        // isLoading is already false, so the pending-load guard itself must
        // prevent the claimed-lease shortcut from announcing readiness.
        #expect(coordinator.awaitingEditorLoad && !page.isLoading)
        #expect(!b.isReady && !b.isLoaded)
        #expect(dispatcher.initializationCount == 0)
        #expect(Data(b.checkedSource.utf8) == Data(sourceB.utf8))
        #expect(page.alphaValue == 0 && !page.documentSurfaceAllowsInput)
        coordinator.webView(page, didFinish: nil)
        try await dispatcher.gate.waitUntilPaused()
        #expect(!coordinator.awaitingEditorLoad)
        #expect(b.isReady && !b.isLoaded)
        #expect(dispatcher.initializationCount == 1)
        #expect(Data(a.checkedSource.utf8) == Data(sourceA.utf8))
        b.detach(page)
        #expect(!lease.permitsInitialization)
        dispatcher.gate.resume()
        try await harness.wait("The cancelled reload initialization did not settle") { dispatcher.completed }
        await harness.closeAndDrain()
    }

    @Test("Managed frozen A to B to A handoffs isolate same-ID companion fields and preserve ordinary Undo")
    func managedFrozenHandoffPreservesCompanionIsolation() async throws {
        let pool = MarkdownEditorWebViewPool()
        let dispatcher = HandoffInitializationDispatcher()
        let harness = SwitchingHarness()
        let a = makeSession(pool: pool)
        let b = MarkdownEditorSession(bridgeDispatcher: dispatcher)
        b.webViewPool = pool
        let vaultID = UUID()
        let sourceA = "\u{FEFF}# A\r\n\r\n[Shared](cite:c-shared)\nA e\u{301} 中文 😀。\r\n"
        let ordinaryEdit = "Ordinary A edit。"
        let editedA = sourceA + ordinaryEdit
        let sourceB = "# B\n\n[Shared](cite:c-shared)\nB e\u{301} 🦉 without final newline"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        func fixture(_ name: String, source: String) throws -> (snapshot: ZoteroCitationSnapshot, bytes: Data) {
            let noteID = UUID()
            let code = "ITEM CSL_CITATION {\"citationItems\":[{\"id\":\"\(name)\"}],\"opaque\":\"\(name) e\u{301} 中文 🧭\"}"
            let data = ZoteroCitationData(
                fields: [.init(id: "c-shared", kind: .citation, code: code, text: "Shared")],
                documentData: "<data>\r\n<prefs><pref name=\"noteType\" value=\"0\"/></prefs><!--\(name) e\u{301}--></data>",
                acceptedFields: [.init(id: "c-shared", code: code)])
            let fingerprint = DocumentFingerprint(content: source)
            let companion = ZoteroCitationCompanion(
                noteID: noteID, vaultID: vaultID, sourceFingerprint: fingerprint, data: data)
            try companion.validate(noteID: noteID, vaultID: vaultID, sourceFingerprint: fingerprint)
            let bytes = try encoder.encode(companion)
            #expect(try ZoteroCitationCompanion.decode(bytes) == companion)
            return (
                .init(
                    noteID: noteID, vaultID: vaultID, revision: DocumentFingerprint(data: bytes),
                    sourceFingerprint: fingerprint, data: data, status: .available), bytes
            )
        }
        func verifyPair(
            _ session: MarkdownEditorSession, source: String,
            fixture: (snapshot: ZoteroCitationSnapshot, bytes: Data)
        ) async throws {
            #expect(Data(try await session.currentText().utf8) == Data(source.utf8))
            #expect(Data(session.checkedSource.utf8) == Data(source.utf8))
            #expect(session.committedCitationSnapshot == fixture.snapshot)
            #expect(session.currentCitationSnapshot?.noteID == fixture.snapshot.noteID)
            #expect(session.currentCitationSnapshot?.sourceFingerprint == DocumentFingerprint(content: source))
            let data = try #require(session.checkedCitationData)
            // Deterministic companion bytes check opaque strings as UTF-8,
            // including NFD, rather than Swift's canonically equal Strings.
            let companion = ZoteroCitationCompanion(
                noteID: fixture.snapshot.noteID, vaultID: fixture.snapshot.vaultID,
                sourceFingerprint: try #require(fixture.snapshot.sourceFingerprint), data: data)
            #expect(try encoder.encode(companion) == fixture.bytes)
        }
        let fixtureA = try fixture("A", source: sourceA)
        let fixtureB = try fixture("B", source: sourceB)
        #expect(fixtureA.snapshot.noteID != fixtureB.snapshot.noteID)
        #expect(fixtureA.bytes != fixtureB.bytes)
        a.loadDocument(sourceA, documentID: a.bridgeDocumentID, mode: .livePreview, citationSnapshot: fixtureA.snapshot)
        b.loadDocument(sourceB, documentID: b.bridgeDocumentID, mode: .livePreview, citationSnapshot: fixtureB.snapshot)
        defer {
            dispatcher.gate.resume()
            harness.close()
            pool.removeAll()
        }
        try await harness.show(a, source: sourceA, title: "A", mode: .livePreview)
        let page = try #require(a.webView as? WindowAttachedWebView)
        _ = try await harness.javascript(
            """
            window.managedHandoffResetCount = 0;
            const reset = window.scholiumEditor.prepareForReuse;
            window.scholiumEditor.prepareForReuse = function() {
              window.managedHandoffResetCount++;
              return reset.call(this);
            };
            """)
        _ = try await a.send(
            .replacePassage(
                expectedText: sourceA, fromUTF16: sourceA.utf16.count, toUTF16: sourceA.utf16.count,
                replacement: ordinaryEdit, preserveSelection: false), in: page)
        try await verifyPair(a, source: editedA, fixture: fixtureA)
        try await harness.beginReplacement(
            b, source: sourceB, title: "B", mode: .livePreview, suspendForDetachment: true)
        try await dispatcher.gate.waitUntilPaused()
        #expect(b.webView === page && page.editorHandoffLease != nil)
        dispatcher.gate.resume()
        try await harness.waitForPrepared(b)
        try await verifyPair(b, source: sourceB, fixture: fixtureB)
        #expect(b.context?.undoLabel == nil)
        try await harness.undo()
        try await verifyPair(b, source: sourceB, fixture: fixtureB)
        try await harness.replace(
            a, source: sourceA, title: "A", mode: .livePreview, suspendForDetachment: true)
        #expect(a.webView === page)
        #expect(try await harness.javascript("return window.managedHandoffResetCount;") as? Int == 0)
        try await verifyPair(a, source: editedA, fixture: fixtureA)
        try await harness.undo()
        try await verifyPair(a, source: sourceA, fixture: fixtureA)
        #expect(Data(b.checkedSource.utf8) == Data(sourceB.utf8))
        let retainedBData = try #require(b.checkedCitationData)
        let expectedBData = try #require(fixtureB.snapshot.data)
        #expect(try encoder.encode(retainedBData) == encoder.encode(expectedBData))
        await harness.closeAndDrain()
    }

    @Test("Cancelling an executed handoff initialization retires its page before a late reply can reach C")
    func cancelledHandoffInitializationCannotAffectSuccessor() async throws {
        let pool = MarkdownEditorWebViewPool()
        let dispatcher = HandoffInitializationDispatcher(afterExecution: true)
        let harness = SwitchingHarness()
        let a = makeSession(pool: pool)
        let b = MarkdownEditorSession(bridgeDispatcher: dispatcher)
        b.webViewPool = pool
        let c = makeSession(pool: pool)
        let sourceA = "\u{FEFF}# A\r\n\r\nFrozen 😀。\r\n"
        let sourceB = "# B\n\nB already initialized。\n"
        let sourceC = "# C\r\n\r\nC stays exact e\u{301} 🦉。\r\n"
        defer {
            dispatcher.gate.resume()
            harness.close()
            pool.removeAll()
        }
        try await harness.show(a, source: sourceA, title: "A")
        let oldPage = try #require(a.webView as? WindowAttachedWebView)
        try await harness.beginReplacement(b, source: sourceB, title: "B", suspendForDetachment: true)
        try await dispatcher.gate.waitUntilPaused()
        let lease = try #require(oldPage.editorHandoffLease)
        #expect(!b.canRecycleWebView)
        harness.replacePending(c, source: sourceC, title: "C")
        try await harness.waitForPrepared(c)
        #expect(lease.isRetired)
        #expect(c.webView !== oldPage)
        #expect(oldPage.alphaValue == 0)
        #expect(!oldPage.documentSurfaceAllowsInput)
        dispatcher.gate.resume()
        try await harness.wait("The cancelled initialize callback did not settle") { dispatcher.completed }
        #expect(Data(try await c.currentText().utf8) == Data(sourceC.utf8))
        #expect(c.context?.undoLabel == nil)
        #expect(Data(b.checkedSource.utf8) == Data(sourceB.utf8))
        #expect(Data(a.checkedSource.utf8) == Data(sourceA.utf8))
        #expect(!pool.hasPreparedView)
        await harness.closeAndDrain()
    }

    @Test(
        "Rejected, exceptional or missing-runtime initialization cannot park an uncleared handoff page",
        arguments: ["native", "javascript", "missing-runtime"])
    func rejectedHandoffInitializationRetiresPage(rejection: String) async throws {
        let pool = MarkdownEditorWebViewPool()
        let dispatcher = HandoffInitializationDispatcher(
            rejects: rejection == "native", rejectsInJavaScript: rejection == "javascript",
            removesRuntime: rejection == "missing-runtime")
        let harness = SwitchingHarness()
        let a = makeSession(pool: pool)
        let b = MarkdownEditorSession(bridgeDispatcher: dispatcher)
        b.webViewPool = pool
        let c = makeSession(pool: pool)
        let sourceB = "\u{FEFF}# B\r\n\r\nB must survive transport failure 😀。\r\n"
        let sourceC = "# C\n\nIndependent successor e\u{301} 🦉。\n"
        defer {
            dispatcher.gate.resume()
            harness.close()
            pool.removeAll()
        }
        try await harness.show(a, source: "# A\n", title: "A")
        let page = try #require(a.webView as? WindowAttachedWebView)
        try await harness.beginReplacement(b, source: sourceB, title: "B", suspendForDetachment: true)
        try await dispatcher.gate.waitUntilPaused()
        let lease = try #require(page.editorHandoffLease)
        #expect(lease.permitsInitialization)
        dispatcher.gate.resume()
        try await harness.wait("The rejected initialize did not retire its page") { lease.isRetired && b.errorMessage != nil }
        #expect(!lease.permitsInitialization)
        #expect(!b.isLoaded)
        #expect(!b.canRecycleWebView)
        #expect(page.alphaValue == 0)
        #expect(!pool.hasPreparedView)
        #expect(pool.take() == nil)
        #expect(Data(b.checkedSource.utf8) == Data(sourceB.utf8))
        harness.replacePending(c, source: sourceC, title: "C")
        try await harness.waitForPrepared(c)
        #expect(c.webView !== page)
        #expect(Data(try await c.currentText().utf8) == Data(sourceC.utf8))
        #expect(c.context?.undoLabel == nil)
        #expect(Data(b.checkedSource.utf8) == Data(sourceB.utf8))
        #expect(page.alphaValue == 0 && !page.documentSurfaceAllowsInput)
        await harness.closeAndDrain()
    }

    @Test("Unclaimed frozen handoffs retire on cancellation, invalidation or acquisition expiry", arguments: ["cancelled", "invalidated", "expired"])
    func unclaimedFrozenHandoffCannotBecomeIdle(rejection: String) async throws {
        let pool = MarkdownEditorWebViewPool(acquisitionDeadline: .milliseconds(250))
        let harness = SwitchingHarness()
        let a = makeSession(pool: pool)
        defer {
            harness.close()
            pool.removeAll()
        }
        try await harness.show(a, source: "# A\r\n\r\nFrozen 中文。\r\n", title: "A")
        var acquiredPage: WindowAttachedWebView?
        let acquired = Task { @MainActor in
            acquiredPage = await pool.takeWhenPrepared()
        }
        defer { acquired.cancel() }
        try await waitForAcquisitions(pool, count: 1)
        try await harness.hideWithoutWaitingForPool(suspendForDetachment: true)
        await acquired.value
        let page = try #require(acquiredPage)
        let lease = try #require(page.editorHandoffLease)
        #expect(!lease.permitsInitialization)
        #expect(!pool.hasPreparedView)
        if rejection == "cancelled" { pool.recycle(page) }
        if rejection == "invalidated" { pool.invalidate() }
        try await harness.wait("The unclaimed handoff did not retire") { lease.isRetired }
        #expect(!lease.permitsInitialization)
        #expect(!lease.claim())
        #expect(!lease.commit())
        #expect(page.alphaValue == 0)
        #expect(!page.documentSurfaceAllowsInput)
        #expect(pool.take() == nil)
        #expect(pool.waitingAcquisitionCount == 0)
        #expect(a.hasDetachedPersistenceSnapshot)
        await harness.closeAndDrain()
    }

    @Test("A frozen departure with no waiter still clears source before parking")
    func frozenDepartureWithoutWaiterParksOnlyEmptyPage() async throws {
        let pool = MarkdownEditorWebViewPool()
        let harness = SwitchingHarness()
        let a = makeSession(pool: pool)
        defer {
            harness.close()
            pool.removeAll()
        }
        try await harness.show(a, source: "\u{FEFF}# A\r\n\r\nPrivate to A 😀。\r\n", title: "A")
        try await harness.hideWithoutWaitingForPool(suspendForDetachment: true)
        try await harness.wait("The source-free idle page was not prepared") { pool.hasPreparedView }
        let page = try #require(pool.take())
        #expect(page.editorHandoffLease == nil)
        #expect(
            try await page.callAsyncJavaScript(
                "return document.querySelector('.cm-content').textContent;",
                arguments: [:], in: nil, contentWorld: .page) as? String == "")
        #expect(
            try await page.callAsyncJavaScript(
                "return document.getElementById('scholium-user-css').textContent;",
                arguments: [:], in: nil, contentWorld: .page) as? String == "")
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
    private final class HandoffInitializationDispatcher: MarkdownEditorBridgeDispatching {
        private let production = WKWebViewMarkdownEditorBridgeDispatcher()
        let gate = PreparationGate()
        let afterExecution: Bool
        let rejects: Bool
        let rejectsInJavaScript: Bool
        let removesRuntime: Bool
        private(set) var initializationCount = 0
        private(set) var completed = false

        init(
            afterExecution: Bool = false, rejects: Bool = false, rejectsInJavaScript: Bool = false,
            removesRuntime: Bool = false
        ) {
            self.afterExecution = afterExecution
            self.rejects = rejects
            self.rejectsInJavaScript = rejectsInJavaScript
            self.removesRuntime = removesRuntime
        }

        func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
            let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
            guard case .initialize = request.operation else {
                return try await production.dispatch(requestJSON: requestJSON, in: webView)
            }
            initializationCount += 1
            defer { completed = true }
            if !afterExecution { await gate.pauseOnce() }
            if removesRuntime {
                let removed =
                    try await webView.callAsyncJavaScript(
                        "window.scholiumEditor = undefined; return typeof window.scholiumEditor === 'undefined';",
                        arguments: [:], in: nil, contentWorld: .page) as? Bool
                try #require(removed == true)
            }
            if rejectsInJavaScript {
                // Exercise the real JS rejection before setDocument has
                // replaced A. Keep the original request ID for native decoding.
                var object = try #require(JSONSerialization.jsonObject(with: Data(requestJSON.utf8)) as? [String: Any])
                object["knownGeneration"] = 1
                let data = try JSONSerialization.data(withJSONObject: object)
                return try await production.dispatch(
                    requestJSON: try #require(String(data: data, encoding: .utf8)), in: webView)
            }
            let result = try await production.dispatch(requestJSON: requestJSON, in: webView)
            if afterExecution { await gate.pauseOnce() }
            if rejects { throw MarkdownEditorSession.SessionError.invalidResult }
            return result
        }
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

    @MainActor
    private final class DepartureMeasurementDispatcher: MarkdownEditorBridgeDispatching {
        private let production = WKWebViewMarkdownEditorBridgeDispatcher()
        var suspensionCount = 0
        var scrollQueryCount = 0
        var suspensionAnchorCount = 0

        func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
            let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
            if case .suspendForDetachment = request.operation { suspensionCount += 1 }
            if case .queryScrollAnchor = request.operation { scrollQueryCount += 1 }
            let result = try await production.dispatch(requestJSON: requestJSON, in: webView)
            if case .suspendForDetachment = request.operation,
                (result as? [String: Any])?["scrollAnchor"] as? [String: Any] != nil
            {
                suspensionAnchorCount += 1
            }
            return result
        }
    }

    @Test("A frozen departure reuses its proven history and recaptures after commit or resume")
    func frozenDepartureCaptureIsIdempotent() async throws {
        let dispatcher = DepartureMeasurementDispatcher()
        let editor = MarkdownEditorSession(bridgeDispatcher: dispatcher)
        let harness = SwitchingHarness()
        defer { harness.close() }
        let original = "\u{FEFF}# Frozen\r\n\r\n" + String(repeating: "中文 😀 e\u{301} paragraph。\r\n\r\n", count: 80)
        let edited = original + "Unsaved draft。\r\n"
        try await harness.show(editor, source: original, title: "Frozen", mode: .livePreview)
        _ = try await editor.send(
            .replacePassage(
                expectedText: original, fromUTF16: 0, toUTF16: original.utf16.count,
                replacement: edited, preserveSelection: false), in: try #require(editor.webView))
        let selection = try #require(editor.context?.selections)
        let undo = try #require(editor.context?.undoLabel)
        try await harness.scroll(to: 0.25)
        let initialScrollQueries = dispatcher.scrollQueryCount
        try await editor.captureStateForViewReconstruction(suspendForDetachment: true)
        #expect(dispatcher.scrollQueryCount == initialScrollQueries)
        #expect(dispatcher.suspensionAnchorCount == 1)
        let firstAnchor = try #require(editor.retainedScrollAnchor)
        #expect(firstAnchor.sourceFingerprint == DocumentFingerprint(content: edited).sha256)
        #expect(firstAnchor.isValid(forUTF16Length: edited.utf16.count))
        #expect(firstAnchor.sourceUTF16Offset > 0)
        let suspensionID = try #require(editor.detachmentSuspensionID)
        // Frozen text still permits researcher scrolling while a save waits.
        try await harness.scroll(to: 0.75)
        try await editor.captureStateForViewReconstruction(suspendForDetachment: true)
        #expect(dispatcher.suspensionCount == 1)
        #expect(dispatcher.scrollQueryCount == initialScrollQueries + 1)
        let laterAnchor = try #require(editor.retainedScrollAnchor)
        #expect(laterAnchor.sourceFingerprint == firstAnchor.sourceFingerprint)
        #expect(laterAnchor.sourceUTF16Offset > firstAnchor.sourceUTF16Offset)
        #expect(laterAnchor.fallbackFraction > firstAnchor.fallbackFraction + 0.25)
        #expect(editor.detachmentSuspensionID == suspensionID)
        #expect(Data(try await editor.currentText().utf8) == Data(edited.utf8))
        #expect(editor.context?.selections == selection)
        #expect(editor.context?.undoLabel == undo)

        // A successful source commit rebases the fingerprint. The old capture
        // cannot authorize that new identity until WebKit proves it again.
        let committed = DocumentFingerprint(content: edited)
        let acknowledgement = try await editor.acknowledgeCommittedSnapshot(
            expectedText: edited, committedText: edited, fingerprint: committed, documentID: editor.documentID)
        #expect(acknowledgement == .clean)
        let scrollQueriesBeforeRebaseCapture = dispatcher.scrollQueryCount
        try await editor.captureStateForViewReconstruction(suspendForDetachment: true)
        #expect(dispatcher.suspensionCount == 2)
        #expect(dispatcher.suspensionAnchorCount == 2)
        #expect(dispatcher.scrollQueryCount == scrollQueriesBeforeRebaseCapture)
        #expect(editor.retainedScrollAnchor?.sourceFingerprint == committed.sha256)
        #expect(editor.startingFingerprint == committed.sha256)
        #expect(editor.context?.undoLabel == undo)
        let committedSuspensionID = try #require(editor.detachmentSuspensionID)

        try await editor.resumeAfterDetachment(suspensionID: committedSuspensionID)
        #expect(editor.detachmentSuspensionID == nil)
        try await harness.undo()
        #expect(Data(try await editor.currentText().utf8) == Data(original.utf8))
        try await harness.scroll(to: 0.45)
        let scrollQueriesBeforeResumeCapture = dispatcher.scrollQueryCount
        try await editor.captureStateForViewReconstruction(suspendForDetachment: true)
        #expect(dispatcher.suspensionCount == 3)
        #expect(dispatcher.suspensionAnchorCount == 3)
        #expect(dispatcher.scrollQueryCount == scrollQueriesBeforeResumeCapture)
        #expect(editor.retainedScrollAnchor?.sourceFingerprint == DocumentFingerprint(content: original).sha256)
        #expect(editor.detachmentSuspensionID != committedSuspensionID)
        #expect(Data(try await editor.currentText().utf8) == Data(original.utf8))
        let scrollQueriesBeforeOrdinaryCapture = dispatcher.scrollQueryCount
        try await harness.hideCapturingState()
        #expect(dispatcher.scrollQueryCount == scrollQueriesBeforeOrdinaryCapture + 1)
        let detachedAnchor = try #require(editor.retainedScrollAnchor)
        try await harness.show(editor, source: original, title: "Frozen", mode: .livePreview)
        let restoredAnchor = try #require(try await editor.currentScrollAnchor())
        #expect(restoredAnchor.sourceFingerprint == detachedAnchor.sourceFingerprint)
        #expect(restoredAnchor.blockUTF16LowerBound == detachedAnchor.blockUTF16LowerBound)
        #expect(restoredAnchor.blockUTF16UpperBound == detachedAnchor.blockUTF16UpperBound)
        #expect(Data(try await editor.currentText().utf8) == Data(original.utf8))
        await harness.closeAndDrain()
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
            mode: MarkdownEditorMode = .source, suspendForDetachment: Bool = false
        ) async throws {
            try await beginReplacement(
                session, source: source, title: title, mode: mode,
                suspendForDetachment: suspendForDetachment)
            try await waitUntilPrepared(session)
        }

        func beginReplacement(
            _ session: MarkdownEditorSession, source: String, title: String,
            mode: MarkdownEditorMode = .source, suspendForDetachment: Bool = false
        ) async throws {
            let previous = try #require(attachment.current?.session)
            try await previous.captureStateForViewReconstruction(suspendForDetachment: suspendForDetachment)
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

        func hideWithoutWaitingForPool(suspendForDetachment: Bool = false) async throws {
            let session = try #require(attachment.current?.session)
            try await session.captureStateForViewReconstruction(suspendForDetachment: suspendForDetachment)
            attachment.current = nil
            try await wait("SwiftUI did not detach the preceding editor") { !session.hasAttachedWebView }
        }

        func javascript(_ body: String, arguments: [String: Any] = [:]) async throws -> Any? {
            let webView = try #require(attachment.current?.session.webView)
            return try await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page)
        }

        func scroll(to fraction: Double) async throws {
            let scrolled =
                try await javascript(
                    """
                    const scroller = document.querySelector('.cm-scroller');
                    if (!scroller) return false;
                    const extent = scroller.scrollHeight - scroller.clientHeight;
                    if (extent <= 0) return false;
                    scroller.dispatchEvent(new WheelEvent('wheel', {deltaY: 1, bubbles: true}));
                    scroller.scrollTop = extent * fraction;
                    return scroller.scrollTop > 0;
                    """, arguments: ["fraction": fraction]) as? Bool
            try #require(scrolled == true)
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

        func wait(_ message: String, until predicate: () -> Bool) async throws {
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
                presentsEditor: true, retainsEditor: true, editorIsLoaded: session.isLoaded, editorIsReady: session.isLoaded
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
                    linkCompletionQuery: { _, _ in .current([]) },
                    linkPreviews: [],
                    initialScrollFraction: session.retainedScrollFraction(fallback: 0),
                    initialScrollAnchor: session.retainedScrollAnchor,
                    onDocumentActivity: {},
                    onRequestSave: {},
                    onRequestFind: { _ in },
                    onRequestDocumentTitleRename: { _, requested in requested },
                    onPasteImage: { _ in false },
                    onLinkActivation: { _ in }, onImagePreview: { _ in },
                    onScrollFractionChange: { _ in },
                    onScrollAnchorChange: { _ in },
                    citationSnapshot: session.committedCitationSnapshot)
            }
        }
    }
}
