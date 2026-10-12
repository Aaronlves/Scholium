import AppKit
import Foundation
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

#if DEBUG
    /// Diagnostic boundaries only: the session store, editor representable,
    /// demand renderer and hidden native layout. No Window navigation queue,
    /// Application hydration, disk save, native focus, paint or RSS is measured.
    @MainActor
    @Suite("Hidden document switching diagnostics", .serialized)
    struct DocumentSwitchPerformanceScenarioTests {
        @Test(
            "Measure retained A/B editor reconstruction with exact source, selection and Undo",
            .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_DOCUMENT_SWITCH"] == "1"))
        func warmRetainedEditorSwitches() async throws {
            try await withHarness { harness in
                let a = harness.documents[0]
                let b = harness.documents[1]
                a.model.beginEditing(in: .livePreview)
                b.model.beginEditing(in: .livePreview)
                try await harness.show(a)
                let editedA = a.source + "Additional synthetic paragraph 😀.\r\n"
                try await harness.edit(a, replacing: a.source, with: editedA)
                let selectionA = try await harness.selection(a)
                let viewportA = try #require(try await a.model.editorSession.currentScrollAnchor())
                var selectionB: [MarkdownEditorSelectionRange]?
                var pageTokens = Set<String>()
                pageTokens.insert(try await harness.pageToken(a))
                let initialTransport = a.model.editorSession.sessionID

                // Two excluded warmups, then twenty retained samples. The
                // default pool retires a page after sixteen safe reuses: a
                // fresh page is reported separately, never called warm reuse.
                for index in 0..<22 {
                    let target = index.isMultiple(of: 2) ? b : a
                    let expected = target === a ? editedA : b.source
                    let prior = try #require(harness.attachment.current)
                    let start = ContinuousClock.now
                    try await prior.model.editorSession.captureStateForViewReconstruction(suspendForDetachment: true)
                    let captured = ContinuousClock.now
                    harness.attachment.current = nil
                    try await harness.wait("outgoing editor detach") { !prior.model.editorSession.hasAttachedWebView }
                    try await harness.show(target, expectedSource: expected)
                    let ranges = try await harness.selection(target)
                    let settled = ContinuousClock.now
                    if target === a {
                        #expect(ranges == selectionA)
                        #expect(target.model.editorSession.isDirty)
                        #expect(try await harness.hasUndo(target))
                        let restoredViewport = try #require(try await target.model.editorSession.currentScrollAnchor())
                        #expect(restoredViewport.sourceFingerprint == viewportA.sourceFingerprint)
                        #expect(restoredViewport.blockUTF16LowerBound == viewportA.blockUTF16LowerBound)
                        #expect(restoredViewport.blockUTF16UpperBound == viewportA.blockUTF16UpperBound)
                    } else if let selectionB {
                        #expect(ranges == selectionB)
                    } else {
                        selectionB = ranges
                    }
                    #expect(!b.model.editorSession.isDirty)
                    #expect(a.model.editorSession.checkedSource.utf8.elementsEqual(editedA.utf8))
                    #expect(b.model.editorSession.checkedSource.utf8.elementsEqual(b.source.utf8))
                    #expect(harness.totalInitializations == index + 2)
                    #expect(harness.store.qaDiagnosticCounts.retained == 2)
                    #expect(harness.store.qaDiagnosticCounts.leased == 2)
                    #expect(harness.store.qaDiagnosticCounts.attachedWebView == 1)
                    #expect(harness.pool.qaDiagnosticCounts.waiting == 0)
                    #expect(await harness.cache.entryCount(workspaceID: harness.workspaceID) == 0)
                    let token = try await harness.pageToken(target)
                    let fresh = pageTokens.insert(token).inserted
                    print(
                        "DocumentSwitch boundary=capture-remount-layout index=\(index) phase=\(index < 2 ? "warmup" : "retained") "
                            + "page=\(fresh ? "fresh" : "reused") captureMs=\(Self.milliseconds(start.duration(to: captured))) "
                            + "remountMs=\(Self.milliseconds(captured.duration(to: settled))) totalMs=\(Self.milliseconds(start.duration(to: settled))) "
                            + "pages=\(pageTokens.count) initialize=\(harness.totalInitializations) "
                            + "sourceBytes=\(expected.utf8.count) sessions=2 attached=1 reviewEntries=0")
                    if index == 0 {
                        // A real Undo command on B must not consume A's history.
                        try await harness.undo(b)
                        try await harness.assertExactSource(b, expected: b.source)
                        #expect(!b.model.editorSession.isDirty)
                    }
                }
                #expect(harness.attachment.current === a)
                #expect(a.model.editorSession.sessionID != initialTransport)
                #expect(pageTokens.count == 2, "The measured run crosses the production pool's reuse limit once.")
                #expect(try await harness.hasUndo(a))
                try await harness.undo(a)
                try await harness.assertExactSource(a, expected: a.source)
                #expect(b.model.editorSession.checkedSource.utf8.elementsEqual(b.source.utf8))
            }
        }

        @Test(
            "Measure retained Edit/Source convergence without reinitializing or invoking Review",
            .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_DOCUMENT_SWITCH"] == "1"))
        func retainedEditSourceModes() async throws {
            try await withHarness { harness in
                let document = harness.documents[0]
                document.model.beginEditing(in: .livePreview)
                try await harness.show(document)
                let edited = document.source + "Synthetic mode-cycle edit.\r\n"
                try await harness.edit(document, replacing: document.source, with: edited)
                let selection = try await harness.selection(document)
                let webView = try #require(document.model.editorSession.webView)
                let transport = document.model.editorSession.sessionID
                let generation = document.model.editorSession.generation
                let initializations = harness.totalInitializations

                // Three excluded warmups and forty retained mode transitions.
                for index in 0..<43 {
                    let mode: MarkdownEditorMode = index.isMultiple(of: 2) ? .source : .livePreview
                    let start = ContinuousClock.now
                    document.model.switchEditorMode(to: mode)
                    try await harness.editorReady(document, expectedSource: edited, expectedMode: mode)
                    let ranges = try await harness.selection(document)
                    let elapsed = start.duration(to: .now)
                    #expect(ranges == selection)
                    #expect(document.model.editorSession.webView === webView)
                    #expect(document.model.editorSession.sessionID == transport)
                    #expect(document.model.editorSession.generation == generation)
                    #expect(document.model.editorSession.isDirty)
                    #expect(try await harness.hasUndo(document))
                    #expect(harness.totalInitializations == initializations)
                    let unexpected = await document.model.loadReadProjectionIfNeeded {
                        harness.rendererCalls += 1
                        return "unexpected Review demand"
                    }
                    #expect(unexpected == nil && harness.rendererCalls == 0)
                    #expect(await harness.cache.entryCount(workspaceID: harness.workspaceID) == 0)
                    print(
                        "DocumentMode boundary=mode-ack-layout index=\(index) phase=\(index < 3 ? "warmup" : "retained") "
                            + "mode=\(mode) milliseconds=\(Self.milliseconds(elapsed)) initialize=\(initializations) "
                            + "sourceBytes=\(edited.utf8.count) rendererCalls=0 reviewEntries=0 attached=1")
                }
                try await harness.undo(document)
                try await harness.assertExactSource(document, expected: document.source)
            }
        }

        @Test(
            "Measure clean Review/Edit/Review demand with one retained editor and bounded derived HTML",
            .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_DOCUMENT_SWITCH"] == "1"))
        func reviewEditorCycles() async throws {
            try await withHarness { harness in
                let document = harness.documents[0]
                let initialStart = ContinuousClock.now
                try await harness.prepareReview(document)
                try await harness.show(document)
                try await harness.readReady(document)
                print("DocumentReview boundary=first-projection-layout milliseconds=\(Self.milliseconds(initialStart.duration(to: .now)))")
                #expect(!document.model.editorSession.hasAttachedWebView)
                #expect(harness.totalInitializations == 0)
                var editorIdentity: ObjectIdentifier?
                var expectedSelection: [MarkdownEditorSelectionRange]?
                let nativeSessionIdentity = ObjectIdentifier(document.model.editorSession)

                // Two excluded warmup cycles, twenty retained cycles. The
                // first Edit allocation is explicitly cold. Review uses the
                // actual finalized Read page, never a forced-ready flag.
                for index in 0..<22 {
                    let start = ContinuousClock.now
                    document.model.beginEditing(in: .livePreview)
                    try await harness.editorReady(document, expectedSource: document.source, expectedMode: .livePreview)
                    let selection = try await harness.selection(document)
                    let entered = ContinuousClock.now
                    let web = try #require(document.model.editorSession.webView)
                    if let editorIdentity {
                        #expect(ObjectIdentifier(web) == editorIdentity)
                    } else {
                        editorIdentity = ObjectIdentifier(web)
                    }
                    if let expectedSelection { #expect(selection == expectedSelection) } else { expectedSelection = selection }
                    #expect(ObjectIdentifier(document.model.editorSession) == nativeSessionIdentity)
                    #expect(harness.totalInitializations == 1)
                    #expect(!document.model.hasUnsavedChanges)
                    document.model.finishEditing()
                    try await harness.prepareReview(document)
                    try await harness.readReady(document)
                    let returned = ContinuousClock.now
                    #expect(document.model.editorSession.webView === web)
                    #expect(document.model.editorSession.detachmentSuspensionID == nil)
                    #expect(document.model.editorSession.checkedSource.utf8.elementsEqual(document.source.utf8))
                    #expect(harness.store.qaDiagnosticCounts.attachedWebView == 1)
                    let stats = await harness.cache.qaDiagnosticStats()
                    #expect(stats.entryCount == 1)
                    #expect(stats.htmlUTF8ByteCount == document.model.renderedReadHTML.utf8.count)
                    print(
                        "DocumentReview boundary=edit-read-layout index=\(index) phase=\(index < 2 ? "warmup" : "retained") "
                            + "editPage=\(index == 0 ? "cold" : "retained") editMs=\(Self.milliseconds(start.duration(to: entered))) "
                            + "reviewMs=\(Self.milliseconds(entered.duration(to: returned))) initialize=1 rendererRequests=\(harness.rendererCalls) "
                            + "readPages=\(document.readPage.creationCount) reviewEntries=\(stats.entryCount) htmlBytes=\(stats.htmlUTF8ByteCount)")
                }
            }
        }

        private func withHarness(_ operation: @MainActor (HiddenHarness) async throws -> Void) async throws {
            let harness = HiddenHarness()
            do {
                try await operation(harness)
                await harness.closeAndDrain()
            } catch {
                await harness.closeAndDrain()
                throw error
            }
        }

        private static func milliseconds(_ duration: Duration) -> Double {
            let components = duration.components
            return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
        }

        @MainActor
        private final class FixtureDocument {
            let source: String
            let model: DocumentSessionModel
            let dispatcher: CountingDispatcher
            let readPage = DedicatedReadPage()

            init(key: DocumentSessionKey, label: String) {
                source =
                    "\u{FEFF}# Synthetic \(label)\r\n\r\n"
                    + (0..<60).map { "Paragraph \($0): 中文 😀 e\u{301} synthetic source.\r\n\r\n" }.joined()
                dispatcher = CountingDispatcher()
                let editor = MarkdownEditorSession(bridgeDispatcher: dispatcher, citationIntegration: UnavailableCitationPort())
                model = DocumentSessionModel(key: key, editorSession: editor)
                model.editingSource = source
                model.originalEditingSource = source
                model.editingRevision = DocumentFingerprint(content: source)
                editor.installSourceChangeHandler { [weak model] in
                    guard let model else { return }
                    model.editingSource = model.editorSession.checkedSource
                }
            }
        }

        @MainActor
        private final class Attachment: ObservableObject {
            @Published var current: FixtureDocument?
        }

        @MainActor
        private final class HiddenHarness {
            let workspaceID = UUID()
            let store = DocumentSessionStore()
            let cache = DocumentReadProjectionCache()
            let attachment = Attachment()
            let documents: [FixtureDocument]
            let window: NSWindow
            private var hosting: NSHostingController<Root>?
            private var closed = false
            var rendererCalls = 0
            var pool: MarkdownEditorWebViewPool { store.editorWebViewPool }
            var totalInitializations: Int { documents.reduce(0) { $0 + $1.dispatcher.initializations } }

            init() {
                _ = NSApplication.shared
                let vaultID = UUID()
                documents = ["A", "B"].map {
                    FixtureDocument(key: .init(vaultID: vaultID, noteID: UUID()), label: $0)
                }
                window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                for document in documents {
                    if let key = document.model.key { store.receiveSession(document.model, for: .workspace(key)) }
                }
                store.reconcileLeases(openTargets: documents.compactMap { $0.model.key.map(DocumentEditingTarget.workspace) }, foregroundTarget: nil)
                let controller = NSHostingController(rootView: Root(attachment: attachment))
                controller.sizingOptions = []
                hosting = controller
                window.contentViewController = controller
                window.setContentSize(NSSize(width: 720, height: 520))
                controller.view.frame = NSRect(x: 0, y: 0, width: 720, height: 520)
                controller.view.autoresizingMask = [.width, .height]
                controller.view.layoutSubtreeIfNeeded()
                #expect(!window.isVisible)
            }

            func show(_ document: FixtureDocument, expectedSource: String? = nil) async throws {
                let oldTransport = document.model.editorSession.sessionID
                attachment.current = document
                hosting?.view.layoutSubtreeIfNeeded()
                if document.model.isEditing {
                    try await wait("new target transport attachment") {
                        document.model.editorSession.hasAttachedWebView
                            && document.model.editorSession.sessionID != oldTransport
                            && document.model.editorSession.documentID == document.model.editorSession.bridgeDocumentID
                    }
                    try await editorReady(
                        document, expectedSource: expectedSource ?? document.source,
                        expectedMode: document.model.retainedEditorMode)
                }
                #expect(!window.isVisible)
            }

            func editorReady(_ document: FixtureDocument, expectedSource: String, expectedMode: MarkdownEditorMode) async throws {
                let editor = document.model.editorSession
                try await wait("target editor attachment") {
                    attachment.current === document && editor.hasAttachedWebView
                        && editor.documentID == editor.bridgeDocumentID && editor.webView?.window === window
                }
                // Join the real load owner after it has the correct identity.
                // Pending resume/convergence must finish before a sample ends.
                let loaded = try await editor.waitUntilLoadedForSave()
                try #require(loaded)
                try await wait("target source/mode/resume readiness") {
                    editor.isReady && editor.isLoaded && editor.presentedMode == expectedMode
                        && document.model.activeEditorMode == expectedMode && editor.errorMessage == nil
                        && editor.detachmentSuspensionID == nil && editor.canRecycleWebView
                        && document.model.detachmentResumeTask == nil
                        && self.container(for: editor.webView)?.surfaceVisibility == .active
                        && editor.webView?.isHidden == false
                }
                #expect(editor.startingFingerprint == DocumentFingerprint(content: document.source).sha256)
                try await assertExactSource(document, expected: expectedSource)
                hosting?.view.layoutSubtreeIfNeeded()
                let web = try #require(editor.webView)
                let laidOut =
                    try await web.callAsyncJavaScript(
                        "const rect = document.querySelector('.cm-editor')?.getBoundingClientRect(); return !!rect && rect.width > 0 && rect.height > 0 && document.querySelector('.cm-content')?.textContent.length > 0;",
                        arguments: [:], in: nil, contentWorld: .page) as? Bool
                #expect(laidOut == true)
                #expect(!window.isVisible)
            }

            func assertExactSource(_ document: FixtureDocument, expected: String) async throws {
                let source = try await document.model.editorSession.currentText(for: document.model.editorSession.bridgeDocumentID)
                #expect(source.utf8.elementsEqual(expected.utf8))
                #expect(DocumentFingerprint(content: source) == DocumentFingerprint(content: expected))
            }

            func selection(_ document: FixtureDocument) async throws -> [MarkdownEditorSelectionRange] {
                let editor = document.model.editorSession
                let result = try await editor.send(.querySelection, in: #require(editor.webView))
                let selection = try #require(result.selection)
                #expect(selection.documentID == editor.bridgeDocumentID)
                #expect(selection.fingerprint == editor.startingFingerprint)
                #expect(selection.generation == editor.generation)
                return selection.ranges
            }

            func edit(_ document: FixtureDocument, replacing source: String, with replacement: String) async throws {
                let editor = document.model.editorSession
                _ = try await editor.send(
                    .replacePassage(expectedText: source, fromUTF16: 0, toUTF16: source.utf16.count, replacement: replacement, preserveSelection: false),
                    in: #require(editor.webView))
                try await assertExactSource(document, expected: replacement)
                _ = try await selection(document)
            }

            func hasUndo(_ document: FixtureDocument) async throws -> Bool {
                let editor = document.model.editorSession
                let result = try await editor.send(.queryContext, in: #require(editor.webView))
                return result.context?.undoLabel != nil
            }

            func undo(_ document: FixtureDocument) async throws {
                let web = try #require(document.model.editorSession.webView)
                _ = try await web.callAsyncJavaScript(
                    "document.querySelector('.cm-content').dispatchEvent(new KeyboardEvent('keydown', {key:'z', code:'KeyZ', keyCode:90, which:90, metaKey:true, bubbles:true, cancelable:true}));",
                    arguments: [:], in: nil, contentWorld: .page)
            }

            func pageToken(_ document: FixtureDocument) async throws -> String {
                let web = try #require(document.model.editorSession.webView)
                let token =
                    try await web.callAsyncJavaScript(
                        "window.scholiumSwitchDiagnosticPageID ??= proposed; return window.scholiumSwitchDiagnosticPageID;",
                        arguments: ["proposed": UUID().uuidString], in: nil, contentWorld: .page) as? String
                return try #require(token)
            }

            func prepareReview(_ document: FixtureDocument) async throws {
                let fingerprint = DocumentFingerprint(content: document.source)
                document.model.prepareReadProjection(for: fingerprint.sha256)
                let key = DocumentReadProjectionKey(
                    workspaceID: workspaceID, stableTarget: document.model.editorSession.bridgeDocumentID,
                    relativePath: "Synthetic.md", fingerprint: fingerprint)
                let html = await document.model.loadReadProjectionIfNeeded {
                    self.rendererCalls += 1
                    return await self.cache.html(for: key, source: document.source)
                }
                let projection = try #require(html)
                try #require(document.model.requiresReadProjection)
                document.model.renderedReadHTML = projection
                document.model.renderedReadFingerprint = fingerprint.sha256
            }

            func readReady(_ document: FixtureDocument) async throws {
                let fingerprint = DocumentFingerprint(content: document.source).sha256
                try await wait("current finalized Review revision") {
                    attachment.current === document && !document.model.isEditing
                        && document.model.renderedReadReadyFingerprint == fingerprint
                        && document.readPage.finalizedFingerprint == fingerprint
                        && document.readPage.webView?.window === window
                        && document.model.failedReadFingerprint == nil
                        && self.container(for: document.readPage.webView)?.surfaceVisibility == .active
                        && document.readPage.webView?.isHidden == false
                        && (!document.model.retainsEditorSurface
                            || self.container(for: document.model.editorSession.webView)?.surfaceVisibility == .retained)
                }
                hosting?.view.layoutSubtreeIfNeeded()
                let web = try #require(document.readPage.webView)
                let laidOut =
                    try await web.callAsyncJavaScript(
                        "const rect = document.querySelector('#scholium-document')?.getBoundingClientRect(); return !!rect && rect.width > 0 && rect.height > 0 && document.querySelector('#scholium-document')?.textContent.includes('Paragraph 0');",
                        arguments: [:], in: nil, contentWorld: .page) as? Bool
                #expect(laidOut == true)
                #expect(document.model.renderedReadFingerprint == fingerprint)
                #expect(!window.isVisible)
            }

            private func container(for webView: WKWebView?) -> DocumentWebViewContainer? {
                var ancestor = webView?.superview
                while let view = ancestor {
                    if let container = view as? DocumentWebViewContainer { return container }
                    ancestor = view.superview
                }
                return nil
            }

            func wait(_ phase: String, until predicate: () -> Bool) async throws {
                let deadline = ContinuousClock.now.advanced(by: .seconds(10))
                while !predicate() {
                    try Task.checkCancellation()
                    guard ContinuousClock.now < deadline else {
                        let editor = attachment.current?.model.editorSession
                        Issue.record(
                            Comment(
                                rawValue:
                                    "Hidden diagnostic timeout phase=\(phase) ready=\(editor?.isReady ?? false) loaded=\(editor?.isLoaded ?? false) mode=\(String(describing: editor?.presentedMode)) suspended=\(editor?.detachmentSuspensionID != nil) error=\(editor?.errorMessage ?? "none")"
                            ))
                        throw MarkdownEditorSession.SessionError.unavailable
                    }
                    hosting?.view.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(2))
                }
            }

            func closeAndDrain() async {
                guard !closed else { return }
                closed = true
                #expect(!window.isVisible)
                attachment.current = nil
                window.contentViewController = nil
                hosting = nil
                window.close()
                let deadline = ContinuousClock.now.advanced(by: .seconds(2))
                while documents.contains(where: { $0.model.editorSession.hasAttachedWebView }), ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                #expect(documents.allSatisfy { !$0.model.editorSession.hasAttachedWebView })
                let oldPool = pool
                store.removeAll()
                await cache.removeAll()
                #expect(store.qaDiagnosticCounts.retained == 0)
                #expect(oldPool.qaDiagnosticCounts.idle == 0 && oldPool.qaDiagnosticCounts.waiting == 0)
                #expect(await cache.entryCount(workspaceID: workspaceID) == 0)
            }
        }

        private struct Root: View {
            @ObservedObject var attachment: Attachment
            var body: some View {
                if let document = attachment.current {
                    Surface(document: document, model: document.model).id(document.model.editorSession.bridgeDocumentID)
                } else {
                    Color.clear
                }
            }
        }

        private struct Surface: View {
            let document: FixtureDocument
            @ObservedObject var model: DocumentSessionModel
            var body: some View {
                let editor = model.editorSession
                let fingerprint = DocumentFingerprint(content: document.source).sha256
                DocumentEditorHost(
                    documentID: editor.openingPresentationID.uuidString,
                    presentsEditor: model.isEditing, retainsEditor: model.retainsEditorSurface,
                    editorIsLoaded: editor.isLoaded,
                    editorIsReady: editor.isReady && editor.isLoaded && editor.presentedMode == model.retainedEditorMode
                ) {
                    SafeMarkdownReadWebView(
                        documentID: editor.bridgeDocumentID, fingerprint: fingerprint, source: document.source,
                        htmlBody: model.renderedReadHTML, presentationCSS: "", userCSS: "",
                        onLinkClick: { _ in }, onOpenExternalURL: { _ in },
                        renderingReadinessIsAcknowledged: model.renderedReadReadyFingerprint == fingerprint,
                        onRenderingFailure: { _ in model.failedReadFingerprint = fingerprint },
                        onRenderingLoading: { model.renderedReadReadyFingerprint = "" },
                        onRenderingReady: {
                            guard !model.isEditing, model.renderedReadFingerprint == fingerprint else { return }
                            model.renderedReadReadyFingerprint = fingerprint
                        },
                        pageExtension: document.readPage,
                        observedScrollPosition: model.readScrollPosition,
                        onScrollFractionChange: { model.observeScrollFraction($0, on: .read) },
                        onScrollAnchorChange: { model.observeScrollAnchor($0, on: .read) })
                } editor: {
                    MarkdownEditorWebView(
                        session: editor, documentID: editor.bridgeDocumentID, documentTitle: "Synthetic",
                        performanceDocumentID: "synthetic-hidden-switch", source: document.source, mode: model.retainedEditorMode,
                        presentationCSS: "", userCSS: "", requiresMathRuntime: false,
                        linkCompletionQuery: { _, _ in .current([]) }, linkPreviews: [],
                        initialScrollFraction: model.editorScrollFraction, initialScrollAnchor: model.editorScrollAnchor,
                        onDocumentActivity: {}, onRequestSave: {}, onRequestFind: { _ in },
                        onRequestDocumentTitleRename: { _, requested in requested }, onPasteImage: { _ in false },
                        onLinkActivation: { _ in }, onImagePreview: { _ in },
                        onScrollFractionChange: { model.observeScrollFraction($0, on: .editor) },
                        onScrollAnchorChange: { model.observeScrollAnchor($0, on: .editor) })
                }
            }
        }

        @MainActor
        private final class CountingDispatcher: MarkdownEditorBridgeDispatching {
            private let production = WKWebViewMarkdownEditorBridgeDispatcher()
            private(set) var initializations = 0
            func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
                let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
                if case .initialize = request.operation { initializations += 1 }
                return try await production.dispatch(requestJSON: requestJSON, in: webView)
            }
        }

        private actor UnavailableCitationPort: ZoteroDocumentIntegrating {
            func run(
                transactionID: String, command: ZoteroDocumentCommand, documentID: String,
                authority: @escaping @Sendable () async -> ZoteroDocumentAuthority,
                handler: @escaping @Sendable (ZoteroDocumentCallback) async throws -> ZoteroDocumentReply
            ) async -> ZoteroDocumentIntegrationResult {
                Issue.record("A switching diagnostic must not request Zotero.")
                return .init(status: .unavailable, remoteCleanupConfirmed: false, callbackCount: 0, message: nil)
            }
            func cancelCurrentTransaction(transactionID: String) async {}
        }

        /// Forces a fixture-owned nonpersistent page rather than consuming the
        /// global prewarmer. All extension policy is neutral; actual Read load
        /// finalization, widgets, source mapping and readiness stay production.
        @MainActor
        private final class DedicatedReadPage: ScholiumReadPageExtension {
            let requiresDedicatedWebView = true
            let requiresMathRuntime = false
            let replyProjectionEnabled = false
            private(set) weak var webView: WKWebView?
            private(set) var creationCount = 0
            private(set) var finalizedFingerprint: String?
            func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
                let web = DocumentNativeWebView(frame: .zero, configuration: configuration)
                webView = web
                creationCount += 1
                finalizedFingerprint = nil
                return web
            }
            func preservesPage(currentDocumentID: String, nextDocumentID: String, hasLoadedPage: Bool) -> Bool { false }
            func canUpdateInPlace(currentDocumentID: String, nextDocumentID: String, hasLoadedPage: Bool) -> Bool { false }
            func acceptsMessageWithoutCurrentFingerprint(type: String) -> Bool { false }
            func willBeginLoad(fingerprint: String) { finalizedFingerprint = nil }
            func updateIfNeeded(
                body: String, source: String, fingerprint: String, signature: String, documentID: String,
                loadGeneration: UInt64, presentationCSS: String, userCSS: String, in webView: WKWebView,
                isCurrent: @escaping @MainActor () -> Bool,
                didApply: @escaping @MainActor (String, String) -> Void,
                didFail: @escaping @MainActor (any Error) -> Void
            ) -> Bool { false }
            func didFinishNavigation(_ navigation: WKNavigation?, isCurrent: @escaping @MainActor () -> Bool) {}
            func didFinalizePage(fingerprint: String) { finalizedFingerprint = fingerprint }
            func handleMessage(type: String, payload: [String: Any], webView: WKWebView?) -> Bool { false }
            func cancel() {}
        }
    }
#endif
