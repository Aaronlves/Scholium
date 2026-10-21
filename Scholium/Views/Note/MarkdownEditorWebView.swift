import AppKit
import ScholiumContracts
import SwiftUI
import WebKit

/// The representable can exist while its preceding document page is being
/// cleared. Only the fully initialized container joins the native hierarchy.
@MainActor
final class MarkdownEditorMountView: NSView {
    private(set) var container: DocumentWebViewContainer?
    var pendingRepresentation: MarkdownEditorWebView?
    var acquisition: Task<Void, Never>?
    var isDismantled = false

    func install(_ container: DocumentWebViewContainer) {
        guard !isDismantled, self.container == nil else { return }
        self.container = container
        pendingRepresentation = nil
        container.frame = bounds
        container.autoresizingMask = [.width, .height]
        addSubview(container)
    }
}

struct MarkdownEditorWebView: NSViewRepresentable {
    @Environment(\.scholiumDocumentSurfaceVisibility)
    private var surfaceVisibility
    @Environment(\.documentToolbarUnderlap) private var toolbarUnderlap
    @ObservedObject var session: MarkdownEditorSession
    let documentID: String
    let documentTitle: String
    let performanceDocumentID: String
    let source: String
    let mode: MarkdownEditorMode
    let presentationCSS: String
    let userCSS: String
    let requiresMathRuntime: Bool
    let linkCompletionQuery:
        @MainActor (
            EditorLinkCompletionKind,
            String
        ) async -> EditorLinkCompletionResponse
    let linkPreviews: [DocumentLinkPreview]
    let initialScrollFraction: Double
    let initialScrollAnchor: EditorScrollAnchor?
    let onDocumentActivity: () -> Void
    let onRequestSave: () -> Void
    let onRequestFind: (DocumentFindShortcut) -> Void
    let onRequestDocumentTitleRename:
        @MainActor (
            String,
            String
        ) async throws -> String
    let onPasteImage: (EditorPastedImageSource) -> Bool
    let onLinkActivation: (String) -> Void
    let onImagePreview: (String) -> Void
    let onScrollFractionChange: (Double) -> Void
    let onScrollAnchorChange: (EditorScrollAnchor) -> Void

    var onAskAgent: AgentSelectionInquiryHandler? = nil
    var onPreviewFailure: ((DocumentPreviewFailure) -> Void)? = nil
    var onPassageAction: ((DocumentPassageAction) -> Void)? = nil
    var writingContinuationEnabled = false
    var writingContinuationContextKey = ""
    var writingIndexContextKey = ""
    var writingContinuationQuery: EditorWritingContinuationQuery = { _, _ in .unavailable(nil) }
    var imageResourceContextKey = ""
    var imageResourcesQuery: EditorImageResourceQuery = { _ in [:] }
    var citationSnapshot: ZoteroCitationSnapshot? = nil
    var review: SafeMarkdownReadWebView? = nil

    static func requiresMathRuntime(linkPreviews: [DocumentLinkPreview]) -> Bool {
        linkPreviews.contains {
            $0.htmlBody.contains("data-math-source=\"")
                && $0.htmlBody.contains("data-math-kind=\"")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            session: session,
            performanceDocumentID: performanceDocumentID,
            onDocumentActivity: onDocumentActivity,
            onRequestSave: onRequestSave,
            onRequestFind: onRequestFind,
            onRequestDocumentTitleRename: onRequestDocumentTitleRename,
            linkCompletionQuery: linkCompletionQuery,
            onLinkActivation: onLinkActivation,
            onImagePreview: onImagePreview,
            onScrollFractionChange: onScrollFractionChange,
            onScrollAnchorChange: onScrollAnchorChange
        )
    }

    func makeNSView(context: Context) -> MarkdownEditorMountView {
        PerformanceProbe.shared.markNoteOpeningMilestone(
            .mountRequested, attemptID: PerformanceProbe.shared.currentNoteOpeningAttempt(documentID: performanceDocumentID)
        )
        let mount = MarkdownEditorMountView()
        mount.pendingRepresentation = self
        let pool = session.webViewPool
        if let reusedWebView = pool?.take() {
            attach(to: mount, coordinator: context.coordinator, reusedWebView: reusedWebView)
        } else if let pool, pool.hasOutgoingView {
            mount.acquisition = Task { @MainActor [weak mount, coordinator = context.coordinator] in
                let prepared = await pool.takeWhenPrepared()
                guard let mount, !mount.isDismantled, !Task.isCancelled else {
                    if let prepared { pool.recycle(prepared) }
                    return
                }
                mount.acquisition = nil
                guard let representation = mount.pendingRepresentation else {
                    if let prepared { pool.recycle(prepared) }
                    return
                }
                representation.attach(
                    to: mount, coordinator: coordinator, reusedWebView: prepared)
            }
        } else {
            attach(to: mount, coordinator: context.coordinator, reusedWebView: nil)
        }
        return mount
    }

    private func attach(
        to mount: MarkdownEditorMountView,
        coordinator: Coordinator,
        reusedWebView: WindowAttachedWebView?
    ) {
        guard !mount.isDismantled, mount.container == nil else { return }
        if let reusedWebView, reusedWebView.editorHandoffLease?.isRetired == true {
            // Delivery can expire before its MainActor receiver runs. Keep
            // the retired page quarantined and use the ordinary fresh path.
            attach(to: mount, coordinator: coordinator, reusedWebView: nil)
            return
        }
        let openingMeasurement = PerformanceProbe.shared.currentNoteOpeningAttempt(documentID: performanceDocumentID)
        PerformanceProbe.shared.markNoteOpeningMilestone(.pageAcquired, attemptID: openingMeasurement)
        let attachmentSource = session.sourceForViewAttachment(
            proposedSource: source,
            documentID: documentID
        )
        let contentController = reusedWebView?.configuration.userContentController ?? WKUserContentController()
        contentController.add(coordinator, name: "scholium")
        let interfaceLocalization = WebKitInterfaceLocalization.current()
        let editorScript = PerformanceProbe.shared.measureNoteOpeningWork(
            .editorScriptLoad, documentID: performanceDocumentID, editorSessionID: session.sessionID,
            operation: { Self.editorScript }
        )
        let webView: WindowAttachedWebView
        if let reusedWebView {
            webView = reusedWebView
        } else {
            let measuresBootstrap = PerformanceProbe.shared.measuresNoteOpeningLifecycle
            if measuresBootstrap {
                contentController.addUserScript(
                    WKUserScript(
                        source: "try { performance.mark('scholium-editor:bootstrap-document-start'); } catch {}",
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true
                    ))
            }
            let editorStartFailure = Self.jsonLiteral(
                interfaceLocalization.string("The Markdown editor could not start.")
            )
            contentController.addUserScript(
                WKUserScript(
                    source: """
                        window.addEventListener('error', function(event) {
                            window.webkit.messageHandlers.scholium.postMessage({
                                type: 'editorError',
                                message: event.message || \(editorStartFailure)
                            });
                        });
                        """,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                ))
            if PerformanceProbe.shared.measuresEditorKeyToPaint
                || PerformanceProbe.shared.measuresEditorCachedPreview
                || PerformanceProbe.shared.measuresEditorVisibleProjection
            {
                let metric: String
                if PerformanceProbe.shared.measuresEditorCachedPreview {
                    metric = "editor_cached_preview"
                } else if PerformanceProbe.shared.measuresEditorVisibleProjection {
                    metric = "editor_visible_projection"
                } else {
                    metric = "editor_key_to_paint"
                }
                contentController.addUserScript(
                    WKUserScript(
                        source: "window.scholiumPerformanceMetric = '\(metric)';",
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true
                    ))
            }
            if requiresMathRuntime, !ScholiumMathAssets.runtimeJavaScript.isEmpty {
                contentController.addUserScript(
                    WKUserScript(
                        source: ScholiumMathAssets.runtimeJavaScript,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true
                    ))
            }
            if let editorScript {
                let injectedScript =
                    measuresBootstrap
                    ? "try { performance.mark('scholium-editor:bootstrap-bundle-start'); } catch {}\n"
                        + editorScript
                        + "\n;try { performance.mark('scholium-editor:bootstrap-bundle-end'); } catch {}"
                    : editorScript
                contentController.addUserScript(
                    WKUserScript(
                        source: injectedScript,
                        injectionTime: .atDocumentEnd,
                        forMainFrameOnly: true
                    ))
            }
            contentController.addUserScript(
                WKUserScript(
                    source: """
                        window.webkit.messageHandlers.scholium.postMessage({
                            type: 'documentEnded',
                            editorReady: typeof window.scholiumEditor === 'object'
                        });
                        """,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                ))

            let configuration = WKWebViewConfiguration()
            configuration.userContentController = contentController
            configuration.websiteDataStore = ScholiumWebKitRuntime.nonPersistentDataStore
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            ScholiumWebFontResources.install(in: configuration)

            webView = WindowAttachedWebView(frame: .zero, configuration: configuration)
        }
        coordinator.activeWebView = webView
        PerformanceProbe.shared.markNoteOpeningMilestone(.webViewPrepared, attemptID: openingMeasurement)
        webView.editorSession = session
        webView.onPasteImage = onPasteImage
        webView.onImagePreview = onImagePreview
        webView.onPassageAction = onPassageAction
        webView.navigationDelegate = coordinator
        webView.setValue(false, forKey: "drawsBackground")
        coordinator.documentID = documentID
        coordinator.documentTitle = documentTitle
        coordinator.lastModeInput = mode
        coordinator.presentationCSS = presentationCSS
        coordinator.userCSS = userCSS
        coordinator.linkPreviews = linkPreviews
        coordinator.writingContinuationEnabled = writingContinuationEnabled
        coordinator.writingContinuationContextKey = writingContinuationContextKey
        coordinator.writingIndexContextKey = writingIndexContextKey
        coordinator.writingContinuationQuery = writingContinuationQuery
        coordinator.initialScrollFraction = initialScrollFraction
        coordinator.initialScrollAnchor = initialScrollAnchor
        if requiresMathRuntime {
            coordinator.requestMathRuntimeIfNeeded(in: webView)
        }
        coordinator.onAskAgent = onAskAgent
        coordinator.onPreviewFailure = onPreviewFailure
        coordinator.performanceDocumentID = performanceDocumentID
        coordinator.onDocumentActivity = onDocumentActivity
        coordinator.onRequestSave = onRequestSave
        coordinator.onRequestFind = onRequestFind
        coordinator.onRequestDocumentTitleRename = onRequestDocumentTitleRename
        coordinator.linkCompletionQuery = linkCompletionQuery
        coordinator.onLinkActivation = onLinkActivation
        coordinator.onImagePreview = onImagePreview
        coordinator.onScrollFractionChange = onScrollFractionChange
        coordinator.onScrollAnchorChange = onScrollAnchorChange
        session.setPresentationCSS(presentationCSS)
        session.setDocumentTitle(documentTitle)
        session.setWritingContinuation(enabled: writingContinuationEnabled, contextKey: writingContinuationContextKey)
        session.setWritingIndexContext(writingIndexContextKey)
        session.setScrollPosition(anchor: initialScrollAnchor, fallbackFraction: initialScrollFraction)
        session.attach(webView)
        coordinator.bindSourceActivity(to: webView)
        let openingSessionID = session.sessionID
        PerformanceProbe.shared.bindNoteOpening(
            attemptID: openingMeasurement, documentID: performanceDocumentID, editorSessionID: openingSessionID
        )
        coordinator.noteOpeningAttemptID = openingMeasurement
        coordinator.noteOpeningSessionID = openingSessionID
        session.installImageResourceQuery(imageResourcesQuery, contextKey: imageResourceContextKey)
        session.webViewPool?.registerAttached(webView)
        coordinator.updateReview(review, documentID: documentID, mode: mode, in: webView)
        session.prepareForViewAttachment(attachmentSource, documentID: documentID, mode: mode, citationSnapshot: citationSnapshot)
        PerformanceProbe.shared.markNoteOpeningMilestone(
            .sessionPrepared, attemptID: openingMeasurement, editorSessionID: openingSessionID
        )

        let editorHTML = PerformanceProbe.shared.measureNoteOpeningWork(
            .editorResourceValidation, documentID: performanceDocumentID, editorSessionID: openingSessionID
        ) {
            Self.editorHTML(localization: interfaceLocalization)
        }
        guard let editorHTML, editorScript != nil
        else {
            session.reportError(String(localized: "The bundled Markdown editor resources could not be found.", table: "Localizable", bundle: .module))
            let container = DocumentWebViewContainer(
                webView: webView,
                keyEquivalentRoute: { event in
                    ScholiumCommandKeyEquivalentRouter.route(event)
                }
            )
            container.toolbarUnderlapEnabled = toolbarUnderlap
            mount.install(container)
            return
        }
        if reusedWebView != nil {
            webView.onFirstWindowAttachment = { [weak webView, weak coordinator, performanceDocumentID] in
                guard let webView else { return }
                PerformanceProbe.shared.markEditActivationAttached(
                    documentID: performanceDocumentID, reusedPage: true
                )
                PerformanceProbe.shared.markNoteOpeningPhase(
                    .attached, attemptID: openingMeasurement, editorSessionID: openingSessionID
                )
                coordinator?.resumePreparedPage(in: webView, editorHTML: editorHTML)
            }
        } else {
            coordinator.awaitingEditorLoad = true
            webView.onFirstWindowAttachment = { [weak webView, weak coordinator, performanceDocumentID] in
                guard let webView else { return }
                PerformanceProbe.shared.markEditActivationAttached(
                    documentID: performanceDocumentID, reusedPage: false
                )
                PerformanceProbe.shared.markNoteOpeningPhase(
                    .attached, attemptID: openingMeasurement, editorSessionID: openingSessionID
                )
                if let coordinator {
                    coordinator.loadEditorHTML(editorHTML, in: webView)
                } else {
                    webView.loadHTMLString(editorHTML, baseURL: nil)
                }
            }
        }
        let container = PerformanceProbe.shared.measureNoteOpeningWork(
            .editorContainerConstruction, documentID: performanceDocumentID, editorSessionID: openingSessionID
        ) {
            DocumentWebViewContainer(
                webView: webView,
                keyEquivalentRoute: { event in
                    ScholiumCommandKeyEquivalentRouter.route(event)
                }
            )
        }
        container.setSurfaceVisibility(surfaceVisibility)
        container.toolbarUnderlapEnabled = toolbarUnderlap
        coordinator.surfaceVisibility = surfaceVisibility
        PerformanceProbe.shared.markNoteOpeningMilestone(
            .containerPrepared, attemptID: openingMeasurement, editorSessionID: openingSessionID
        )
        mount.install(container)
    }

    func updateNSView(_ mount: MarkdownEditorMountView, context: Context) {
        guard let container = mount.container else {
            mount.pendingRepresentation = self
            return
        }
        mount.pendingRepresentation = nil
        container.toolbarUnderlapEnabled = toolbarUnderlap
        let webView = container.webView
        if mode != .review {
            webView.setAccessibilityLabel(nil)
            webView.setAccessibilityIdentifier(nil)
        }
        container.setSurfaceVisibility(surfaceVisibility)
        context.coordinator.activeWebView = webView
        context.coordinator.surfaceVisibility = surfaceVisibility
        if let webView = webView as? WindowAttachedWebView {
            webView.editorSession = session
            webView.onPasteImage = onPasteImage
            webView.onImagePreview = onImagePreview
            webView.onPassageAction = onPassageAction
        }
        context.coordinator.onAskAgent = onAskAgent
        context.coordinator.onPreviewFailure = onPreviewFailure
        context.coordinator.performanceDocumentID = performanceDocumentID
        context.coordinator.onDocumentActivity = onDocumentActivity
        context.coordinator.onRequestSave = onRequestSave
        context.coordinator.onRequestFind = onRequestFind
        context.coordinator.onRequestDocumentTitleRename = onRequestDocumentTitleRename
        context.coordinator.linkCompletionQuery = linkCompletionQuery
        context.coordinator.writingContinuationQuery = writingContinuationQuery
        session.installImageResourceQuery(imageResourcesQuery, contextKey: imageResourceContextKey)
        if context.coordinator.writingContinuationEnabled != writingContinuationEnabled
            || context.coordinator.writingContinuationContextKey != writingContinuationContextKey
        {
            context.coordinator.writingContinuation.cancel(reason: .configuration)
            context.coordinator.writingContinuationEnabled = writingContinuationEnabled
            context.coordinator.writingContinuationContextKey = writingContinuationContextKey
            session.setWritingContinuation(enabled: writingContinuationEnabled, contextKey: writingContinuationContextKey)
        }
        if context.coordinator.writingIndexContextKey != writingIndexContextKey {
            context.coordinator.cancelWritingTermQuery()
            context.coordinator.writingIndexContextKey = writingIndexContextKey
            session.setWritingIndexContext(writingIndexContextKey)
        }
        context.coordinator.onLinkActivation = onLinkActivation
        context.coordinator.onImagePreview = onImagePreview
        context.coordinator.onScrollFractionChange = onScrollFractionChange
        context.coordinator.onScrollAnchorChange = onScrollAnchorChange
        context.coordinator.initialScrollFraction = initialScrollFraction
        context.coordinator.initialScrollAnchor = initialScrollAnchor
        if context.coordinator.documentTitle != documentTitle {
            context.coordinator.documentTitle = documentTitle
            session.setDocumentTitle(documentTitle)
        }
        if context.coordinator.presentationCSS != presentationCSS {
            context.coordinator.presentationCSS = presentationCSS
            session.setPresentationCSS(presentationCSS)
        }
        if context.coordinator.userCSS != userCSS {
            context.coordinator.userCSS = userCSS
            session.setUserCSS(userCSS)
        }
        if context.coordinator.linkPreviews != linkPreviews {
            context.coordinator.linkPreviews = linkPreviews
            session.setLinkPreviews(linkPreviews, in: source)
            if requiresMathRuntime {
                context.coordinator.requestMathRuntimeIfNeeded(in: webView)
            }
        }
        context.coordinator.updateReview(review, documentID: documentID, mode: mode, in: webView)
        if context.coordinator.documentID != documentID {
            context.coordinator.writingContinuation.cancel(reason: .document)
            context.coordinator.cancelLinkCompletionQuery()
            context.coordinator.cancelDocumentTitleRename()
            context.coordinator.documentID = documentID
            session.loadDocument(source, documentID: documentID, mode: mode, citationSnapshot: citationSnapshot)
            session.setLinkPreviews(linkPreviews, in: session.checkedSource)
            session.setScrollPosition(anchor: initialScrollAnchor, fallbackFraction: initialScrollFraction)
        } else if context.coordinator.lastModeInput != mode {
            context.coordinator.writingContinuation.cancel(reason: .mode)
            context.coordinator.cancelLinkCompletionQuery()
            context.coordinator.lastModeInput = mode
            session.setMode(mode)
        }
    }

    static func dismantleNSView(_ mount: MarkdownEditorMountView, coordinator: Coordinator) {
        mount.isDismantled = true
        mount.acquisition?.cancel()
        mount.acquisition = nil
        mount.pendingRepresentation = nil
        let webView = mount.container?.webView
        let ownsWebView = webView?.navigationDelegate === coordinator
        let ownsSession = ownsWebView && webView != nil && coordinator.session.webView === webView
        let canRecycle = ownsSession && coordinator.session.canRecycleWebView
        if ownsWebView, let webView = webView as? WindowAttachedWebView {
            webView.onFirstWindowAttachment = nil
            webView.editorSession = nil
            webView.onPasteImage = nil
            webView.onImagePreview = nil
            webView.onPassageAction = nil
        }
        if ownsWebView {
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "scholium")
            webView?.navigationDelegate = nil
        }
        coordinator.reviewCoordinator?.cancelPendingPageWork()
        coordinator.activeWebView = nil
        coordinator.session.removeSourceChangeHandler(owner: coordinator)
        if ownsSession { coordinator.session.removeImageResourceQuery() }
        coordinator.cancelMermaidRuntimeLoad()
        coordinator.cancelMathRuntimeLoad()
        coordinator.cancelLinkCompletionQuery()
        coordinator.writingContinuation.cancel(reason: .detached)
        coordinator.cancelDocumentTitleRename()
        guard ownsWebView, let webView else { return }
        coordinator.session.detach(webView)
        if canRecycle {
            coordinator.session.webViewPool?.recycle(
                webView, hasFrozenSnapshot: coordinator.session.hasDetachedPersistenceSnapshot)
        } else {
            coordinator.session.webViewPool?.abandonOutgoing(webView)
        }
    }

    private static var editorScript: String? {
        ScholiumDocumentWebResources.text(named: "editor.bundle", extension: "js")
    }

    static var editorHTML: String? {
        editorHTML(localization: .current())
    }

    static func editorHTML(
        localization: WebKitInterfaceLocalization
    ) -> String? {
        guard
            let css = ScholiumDocumentWebResources.text(
                named: "editor",
                extension: "css"
            ),
            !ScholiumCalloutStyles.css.isEmpty
        else { return nil }
        return """
            <!doctype html>
            <html lang="\(localization.languageTag)">
              <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <meta name="scholium-interface-localization" content="\(localization.base64JSON())">
                <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'none'; img-src data:; font-src scholium-font: data:">
                <style>\(ScholiumWebFonts.css)\n\(css)\n\(ScholiumCalloutStyles.css)\n\(ScholiumTableStyles.css)\n\(ScholiumFootnoteStyles.css)\n\(ScholiumAttachmentStyles.css)\n\(ScholiumMathAssets.css)\n\(ScholiumMermaidAssets.css)\n\(ScholiumPreviewStyles.css)\n\(ScholiumWebSymbolAssets.cssVariables)\n\(ScholiumWebDesignTokens.documentPresentationCSS)</style>
                <style id="scholium-presentation-css"></style>
                <style id="scholium-user-css"></style>
              </head>
              <body><main id="editor"></main></body>
            </html>
            """
    }

    private static func jsonLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
            let literal = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return literal
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        #if DEBUG
            struct TestingInputMessageTiming: Sendable {
                enum Kind: String, Sendable {
                    case documentChanged, interactionChanged, scrollChanged
                }

                let kind: Kind
                let documentVersion: Int
                let interactionRevision: Int?
                let accepted: Bool
                let receivedAt: ContinuousClock.Instant
                let decodedAt: ContinuousClock.Instant
                let admissionStartedAt: ContinuousClock.Instant
                let admissionCompletedAt: ContinuousClock.Instant
            }

            /// Opt-in observation of existing admission. No diagnostic value
            /// participates in message validation or document publication.
            var testingInputMessageObserver: ((TestingInputMessageTiming) -> Void)?
        #endif

        let session: MarkdownEditorSession
        var onDocumentActivity: () -> Void
        var onRequestSave: () -> Void
        var onRequestFind: (DocumentFindShortcut) -> Void
        var onRequestDocumentTitleRename:
            @MainActor (
                String,
                String
            ) async throws -> String
        var linkCompletionQuery:
            @MainActor (
                EditorLinkCompletionKind,
                String
            ) async -> EditorLinkCompletionResponse
        var writingContinuationEnabled = false
        var writingContinuationContextKey = ""
        var writingIndexContextKey = ""
        var writingContinuationQuery: EditorWritingContinuationQuery = { _, _ in .unavailable(nil) }
        var onLinkActivation: (String) -> Void
        var onImagePreview: (String) -> Void
        var onScrollFractionChange: (Double) -> Void
        var onScrollAnchorChange: (EditorScrollAnchor) -> Void
        var surfaceVisibility: DocumentSurfaceVisibility = .active {
            didSet {
                guard oldValue != surfaceVisibility else { return }
                reviewCoordinator?.surfaceVisibility = surfaceVisibility
                if !surfaceVisibility.isActive {
                    session.floatingSurfaces.dismissNotifyingOwner()
                    writingContinuation.cancel(reason: .inactive)
                    cancelWritingTermQuery()
                }
            }
        }
        var documentID = ""
        var documentTitle = ""
        var performanceDocumentID: String
        var noteOpeningAttemptID: UUID?
        var noteOpeningSessionID: UUID?
        weak var activeWebView: WKWebView?
        /// Diff cache for the last SwiftUI input delivered to the session.
        /// It never supplies initialization or recovery state and never writes
        /// a bridge acknowledgement back into the Document model.
        var lastModeInput: MarkdownEditorMode = .livePreview
        var reviewCoordinator: SafeMarkdownReadWebView.Coordinator?

        func updateReview(_ review: SafeMarkdownReadWebView?, documentID: String, mode: MarkdownEditorMode, in webView: WKWebView) {
            guard let review, mode == .review, review.selectionSurfaceIsActive else {
                reviewCoordinator?.setEmbeddedSurfaceActive(false)
                return
            }
            let publishesPresenter = reviewCoordinator == nil || reviewCoordinator?.activeWebView !== webView
            let coordinator = reviewCoordinator ?? review.makeCoordinator()
            reviewCoordinator = coordinator
            coordinator.setEmbeddedSurfaceActive(true)
            coordinator.surfaceVisibility = surfaceVisibility
            let fingerprint = review.document.fingerprint.sha256
            coordinator.onEmbeddedScrollPositionChange = { [weak self, weak webView] position in
                guard let self, let webView, self.surfaceVisibility.isActive,
                    self.activeWebView === webView, self.session.webView === webView,
                    self.documentID == documentID, self.session.documentID == documentID,
                    self.lastModeInput == .review, self.session.startingFingerprint == fingerprint
                else { return }
                self.session.recordReviewScrollPosition(position)
            }
            coordinator.setEmbeddedPresentationReady(
                session.isLoaded && session.presentedMode == .review
                    && session.documentID == documentID
                    && session.startingFingerprint == fingerprint)
            var projection = review.embeddedProjection(using: coordinator, in: webView)
            projection.documentID = documentID
            session.setReviewProjection(projection)
            if publishesPresenter {
                let presenter = coordinator.selectionActionPresenter(in: webView)
                Task { @MainActor in review.onSelectionActionPresenterReady?(presenter) }
            }
        }

        var presentationCSS = ""
        var userCSS = ""
        var linkPreviews: [DocumentLinkPreview] = []
        var awaitingEditorLoad = false
        var initialScrollFraction: Double = 0
        var initialScrollAnchor: EditorScrollAnchor?
        private var hasSignaledReady = false
        private var pageGeneration: UInt64 = 0
        private struct BootstrapNavigationObservation {
            let attemptID: UUID
            let editorSessionID: UUID
            let pageGeneration: UInt64
            var navigation: WKNavigation?
        }
        private var bootstrapNavigationObservation: BootstrapNavigationObservation?
        private var mermaidRuntimeLoadTask: Task<Void, Never>?
        private var mermaidRuntimeLoadID: UUID?
        private var mathRuntimeLoadTask: Task<Void, Never>?
        private var mathRuntimeLoadID: UUID?
        private var linkCompletionQueryTask: Task<Void, Never>?
        private var linkCompletionQueryTaskID: UUID?
        private var linkCompletionQueryKind: EditorLinkCompletionKind?
        private var linkCompletionQueryRequestID: String?
        let writingContinuation = EditorWritingContinuationController()
        private var documentTitleRenameTask: Task<Void, Never>?
        private var documentTitleRenameRequestID: String?

        init(
            session: MarkdownEditorSession,
            performanceDocumentID: String,
            onDocumentActivity: @escaping () -> Void,
            onRequestSave: @escaping () -> Void,
            onRequestFind: @escaping (DocumentFindShortcut) -> Void,
            onRequestDocumentTitleRename:
                @escaping @MainActor (
                    String,
                    String
                ) async throws -> String,
            linkCompletionQuery:
                @escaping @MainActor (
                    EditorLinkCompletionKind,
                    String
                ) async -> EditorLinkCompletionResponse,
            onLinkActivation: @escaping (String) -> Void,
            onImagePreview: @escaping (String) -> Void,
            onScrollFractionChange: @escaping (Double) -> Void,
            onScrollAnchorChange: @escaping (EditorScrollAnchor) -> Void
        ) {
            self.session = session
            self.performanceDocumentID = performanceDocumentID
            self.onDocumentActivity = onDocumentActivity
            self.onRequestSave = onRequestSave
            self.onRequestFind = onRequestFind
            self.onRequestDocumentTitleRename = onRequestDocumentTitleRename
            self.linkCompletionQuery = linkCompletionQuery
            self.onLinkActivation = onLinkActivation
            self.onImagePreview = onImagePreview
            self.onScrollFractionChange = onScrollFractionChange
            self.onScrollAnchorChange = onScrollAnchorChange
            super.init()
        }

        /// A representable's speculative coordinator owns no session callback.
        /// Only the page actually attached to this session may report activity.
        func bindSourceActivity(to webView: WKWebView) {
            guard session.webView === webView, webView.navigationDelegate === self else { return }
            activeWebView = webView
            session.installSourceChangeHandler(owner: self) { [weak self, weak webView] in
                guard let self, let webView,
                    self.activeWebView === webView,
                    self.session.webView === webView,
                    webView.navigationDelegate === self
                else { return }
                self.onDocumentActivity()
            }
        }

        var onAskAgent: AgentSelectionInquiryHandler?
        var onPreviewFailure: ((DocumentPreviewFailure) -> Void)?

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "scholium", let webView = message.webView,
                activeWebView === webView, session.webView === webView,
                webView.navigationDelegate === self
            else { return }
            #if DEBUG
                let timingObserver = testingInputMessageObserver
                let timingReceivedAt: ContinuousClock.Instant? = timingObserver == nil ? nil : .now
                var timingDecodedAt: ContinuousClock.Instant?
                var timingKind: TestingInputMessageTiming.Kind?
                var timingDocumentVersion: Int?
                var timingInteractionRevision: Int?
                var timingAdmissionStartedAt: ContinuousClock.Instant?
                var timingAdmissionCompletedAt: ContinuousClock.Instant?
                var timingAccepted = false
                defer {
                    if let timingObserver, let timingKind, let timingDocumentVersion,
                        let timingReceivedAt, let timingDecodedAt, let timingAdmissionStartedAt
                    {
                        timingObserver(
                            TestingInputMessageTiming(
                                kind: timingKind, documentVersion: timingDocumentVersion,
                                interactionRevision: timingInteractionRevision, accepted: timingAccepted,
                                receivedAt: timingReceivedAt, decodedAt: timingDecodedAt,
                                admissionStartedAt: timingAdmissionStartedAt,
                                admissionCompletedAt: timingAdmissionCompletedAt ?? .now))
                    }
                }
            #endif
            guard let payload = EditorBridgeMessageDecoder.decode(message.body) else { return }
            #if DEBUG
                if timingObserver != nil { timingDecodedAt = .now }
            #endif

            switch payload {
            case .reviewEvent(let envelope, let payloadJSON):
                guard validEnvelope(envelope), session.presentedMode == .review || lastModeInput == .review,
                    let webView = message.webView, activeWebView === webView,
                    let event = (try? JSONSerialization.jsonObject(with: payloadJSON)) as? [String: Any]
                else { return }
                reviewCoordinator?.receiveEmbedded(
                    event, in: webView, resolveImageResources: session.deliveredPreviewImageResources(for:))
            case .floatingSurface(let request):
                guard admitsFloatingSurface(request.event),
                    validEnvelope(request.envelope), let webView = message.webView,
                    !request.event.allowsAgentInquiry || onAskAgent != nil
                else { return }
                session.floatingSurfaces.onPreviewShown = { [documentID = performanceDocumentID] in
                    PerformanceProbe.shared.markEditorCachedPreviewVisible(documentID: documentID)
                }
                session.floatingSurfaces.onPreviewFailure = { [weak self] failure in
                    guard let self, self.surfaceVisibility.isActive else { return }
                    self.onPreviewFailure?(failure)
                }
                let previewImages: [String: String]
                if case .preview(let preview) = request.event {
                    previewImages = session.deliveredPreviewImageResources(for: preview.imageResourceKeys)
                } else {
                    previewImages = [:]
                }
                session.floatingSurfaces.present(request.event, in: webView, inquire: onAskAgent, imageResources: previewImages) {
                    [weak self, weak webView] id, action, index in
                    // Autosave rebases the disk fingerprint, not the live buffer
                    // revision. Validate that revision at event dispatch instead.
                    guard let self, let webView,
                        action == .dismiss || self.admitsFloatingSurface(request.event),
                        self.session.webView === webView,
                        request.envelope.sessionID == self.session.sessionID.uuidString,
                        request.envelope.documentID == self.documentID,
                        request.envelope.documentVersion == self.session.generation
                    else { return false }
                    let accepted = try? await webView.callAsyncJavaScript(
                        "return window.scholiumNativeFloatingEvent?.(id, action, index)",
                        arguments: ["id": id, "action": action.rawValue, "index": index],
                        in: nil, contentWorld: .page
                    )
                    return accepted as? Bool == true
                }
            case .ready:
                signalReady()
            case .documentEnded(let editorReady):
                if editorReady {
                    signalReady()
                } else {
                    session.reportError(String(localized: "The Markdown editor script did not initialize.", table: "Localizable", bundle: .module))
                }
            case .editorError(let error):
                guard validEnvelope(error.envelope) else { return }
                session.reportError(
                    error.message
                        ?? WebKitInterfaceLocalization.current()
                        .string("The Markdown editor could not start.")
                )
            case .interactionChanged(let interaction):
                #if DEBUG
                    if timingObserver != nil {
                        timingKind = .interactionChanged
                        timingDocumentVersion = interaction.envelope.documentVersion
                        timingInteractionRevision = interaction.interactionRevision
                        timingAdmissionStartedAt = .now
                    }
                #endif
                guard surfaceVisibility.isActive,
                    validEnvelope(interaction.envelope)
                else { return }
                // An old interaction may be queued behind a current snapshot.
                // Only the session's admitted interaction can cancel this round.
                let admitted = session.updateInteraction(
                    selections: interaction.selections,
                    line: interaction.line,
                    column: interaction.column,
                    lineCount: interaction.lineCount,
                    documentVersion: interaction.envelope.documentVersion,
                    interactionRevision: interaction.interactionRevision,
                    focusTarget: interaction.focusTarget,
                    context: interaction.context
                )
                #if DEBUG
                    if timingObserver != nil {
                        timingAccepted = admitted
                        timingAdmissionCompletedAt = .now
                    }
                #endif
                guard admitted else {
                    if writingContinuation.requestID != nil {
                        EditorWritingContinuationController.trace(
                            "ignoredEditorMessage", requestID: writingContinuation.requestID, detail: "interactionAdmission")
                    }
                    return
                }
                if interaction.context?.composing == true || interaction.focusTarget == .title
                    || (writingContinuation.editorCaret.map { caret in
                        interaction.selections != [.init(anchor: caret, head: caret)]
                    } ?? false)
                {
                    writingContinuation.cancel(reason: .interaction)
                }
            case .documentChanged(let change):
                #if DEBUG
                    let baseGeneration = session.generation
                    if timingObserver != nil {
                        timingKind = .documentChanged
                        timingDocumentVersion = change.envelope.documentVersion
                        timingAdmissionStartedAt = .now
                    }
                #endif
                // queryText can absorb a full snapshot before its queued delta.
                // A rejected duplicate has no authority over a current request.
                let admitted =
                    surfaceVisibility.isActive
                    && validEnvelope(change.envelope, allowingFutureGeneration: true)
                    && applyEditorChanges(change, in: message.webView ?? activeWebView)
                #if DEBUG
                    if timingObserver != nil {
                        timingAccepted = admitted
                        timingAdmissionCompletedAt = .now
                    }
                    PerformanceProbe.shared.recordQASaveStage(
                        .editorDeltaAdmission, sessionID: session.sessionID,
                        flags: [
                            .accepted: admitted, .surfaceActive: surfaceVisibility.isActive,
                            .sameTransport: change.envelope.sessionID == session.sessionID.uuidString,
                            .sameDocument: change.envelope.documentID == session.documentID,
                            .sameFingerprint: change.envelope.startingFingerprint == session.startingFingerprint,
                            .sameGeneration: change.baseGeneration == baseGeneration
                                && change.resultingGeneration == change.envelope.documentVersion,
                            .dirty: session.isDirty,
                        ],
                        counts: [.generation: baseGeneration, .messageGeneration: change.envelope.documentVersion]
                    )
                #endif
                if admitted {
                    writingContinuation.cancel(reason: .source)
                    cancelWritingTermQuery()
                }
            case .performanceSample(let performance):
                guard validEnvelope(performance.envelope),
                    performance.durationMilliseconds > 0
                else { return }
                switch performance.metric {
                case "editor_key_to_paint":
                    PerformanceProbe.shared.recordEditorKeyToPaint(
                        documentID: performanceDocumentID,
                        durationMilliseconds: performance.durationMilliseconds
                    )
                case "editor_visible_projection":
                    PerformanceProbe.shared.recordEditorWebDuration(
                        documentID: performanceDocumentID,
                        metric: .editorVisibleProjection,
                        durationMilliseconds: performance.durationMilliseconds
                    )
                default:
                    return
                }
            case .requestSave(let envelope):
                let admitted = surfaceVisibility.isActive && validEnvelope(envelope)
                #if DEBUG
                    PerformanceProbe.shared.recordQASaveStage(
                        .jsSaveAdmission, sessionID: session.sessionID,
                        flags: [
                            .accepted: admitted, .surfaceActive: surfaceVisibility.isActive,
                            .sameTransport: envelope.sessionID == session.sessionID.uuidString,
                            .sameDocument: envelope.documentID == session.documentID,
                            .sameFingerprint: envelope.startingFingerprint == session.startingFingerprint,
                            .sameGeneration: envelope.documentVersion == session.generation,
                            .dirty: session.isDirty, .composing: session.isComposing,
                        ],
                        counts: [.generation: session.generation, .messageGeneration: envelope.documentVersion]
                    )
                #endif
                guard admitted else { return }
                onRequestSave()
            case .requestEditorFocus(let envelope):
                guard surfaceVisibility.isActive,
                    validEnvelope(envelope), let webView = message.webView,
                    activeWebView === webView
                else { return }
                session.acceptNativeFocusAfterDrop(from: webView)
            case .requestDocumentFind(let request):
                guard surfaceVisibility.isActive, validEnvelope(request.envelope) else { return }
                onRequestFind(request.action)
            case .requestDocumentTitleRename(let request):
                guard surfaceVisibility.isActive,
                    validEnvelope(request.envelope),
                    let webView = message.webView ?? activeWebView
                else { return }
                guard request.expectedTitle == documentTitle else {
                    rejectChangedDocumentTitleRename(request, in: webView)
                    return
                }
                beginDocumentTitleRename(request, in: webView)
            case .requestImagePaste(let envelope):
                guard surfaceVisibility.isActive,
                    validEnvelope(envelope),
                    let webView = message.webView as? WindowAttachedWebView
                else { return }
                _ = webView.consumePastedImage()
            case .requestTextPaste(let request):
                guard surfaceVisibility.isActive,
                    validEnvelope(request.envelope),
                    session.acceptsInteractionRanges(request.selections, documentVersion: request.envelope.documentVersion),
                    let webView = message.webView,
                    let plainText = NSPasteboard.general.string(forType: .string)
                else { return }
                Task { @MainActor [weak self, weak webView] in
                    guard let self, let webView,
                        self.activeWebView === webView,
                        self.surfaceVisibility.isActive,
                        self.validEnvelope(request.envelope), !self.session.isComposing
                    else { return }
                    do {
                        try await self.session.pasteClipboard(plainText: plainText, selections: request.selections)
                    } catch {
                        guard self.activeWebView === webView, self.validEnvelope(request.envelope) else { return }
                        self.session.reportError(ScholiumErrorLocalization.message(error))
                    }
                }
            case .requestMermaidRuntime(let envelope):
                // Recovery installs its retained generation in setState before
                // native receives the initialization acknowledgement.
                guard validEnvelope(envelope, allowingFutureGeneration: true),
                    let webView = message.webView,
                    activeWebView === webView
                else { return }
                requestMermaidRuntime(in: webView)
            case .requestMathRuntime(let envelope):
                guard validEnvelope(envelope, allowingFutureGeneration: true),
                    let webView = message.webView ?? activeWebView,
                    activeWebView === webView
                else { return }
                requestMathRuntime(in: webView)
            case .cancelWritingTermQuery(let request):
                // An abort may arrive after the same document advanced its version.
                guard request.envelope.sessionID == session.sessionID.uuidString,
                    request.envelope.documentID == documentID
                else { return }
                cancelWritingTermQuery(requestID: request.requestID)
            case .cancelWritingContinuation(let request):
                // Cancellation remains valid after the same session has advanced a generation.
                guard request.envelope.sessionID == session.sessionID.uuidString,
                    request.envelope.documentID == documentID,
                    request.requestID == writingContinuation.requestID
                else { return }
                EditorWritingContinuationController.trace("pageCancelled", requestID: request.requestID, detail: request.reason.rawValue)
                writingContinuation.cancel(reason: .bridge)
            case .writingContinuationQuery(let request):
                guard surfaceVisibility.isActive,
                    validEnvelope(request.envelope), writingContinuationEnabled,
                    let webView = message.webView, activeWebView === webView,
                    session.acceptsInteractionRanges(
                        [.init(anchor: request.editorCaretUTF16Offset, head: request.editorCaretUTF16Offset)],
                        documentVersion: request.envelope.documentVersion)
                else {
                    EditorWritingContinuationController.trace("queryRejected", requestID: request.requestID, detail: "editorAdmission")
                    return
                }
                let contextKey = writingContinuationContextKey
                let page = pageGeneration
                let writingSource = session.checkedSource
                writingContinuation.start(
                    requestID: request.requestID,
                    sourceCaret: request.caretUTF16Offset,
                    editorCaret: request.editorCaretUTF16Offset,
                    query: writingContinuationQuery,
                    isCurrent: { [weak self, weak webView] in
                        guard let self, let webView else { return false }
                        return self.surfaceVisibility.isActive && self.writingContinuationEnabled
                            && contextKey == self.writingContinuationContextKey
                            && page == self.pageGeneration
                            && self.admitsWritingContinuationPublication(
                                request.envelope, source: writingSource, editorCaret: request.editorCaretUTF16Offset)
                            && self.activeWebView === webView
                    },
                    publish: { [weak webView] publication in
                        guard let webView else { return }
                        await Self.publishWritingContinuation(
                            publication, requestID: request.requestID, in: webView
                        )
                    }
                )
            case .requestCitationInsertion(let request):
                guard surfaceVisibility.isActive, validEnvelope(request.envelope) else { return }
                writingContinuation.cancel(reason: .citation)
                Task { @MainActor [weak self, weak session] in
                    guard let self, let session, self.surfaceVisibility.isActive, self.validEnvelope(request.envelope) else { return }
                    do { try await session.performCitation(.addEditCitation, reference: request.reference) } catch {
                        await session.announceCitationStatus(ScholiumErrorLocalization.message(error))
                    }
                }
            case .linkCompletionQuery(let request):
                guard surfaceVisibility.isActive, validEnvelope(request.envelope) else { return }
                let requestID = request.requestID
                let requestedDocumentID = documentID
                let requestedFingerprint = session.startingFingerprint
                let requestedVersion = session.generation
                startLinkCompletionQuery(
                    requestID: requestID, kind: request.completionKind, query: request.query,
                    isCurrent: { [weak self, weak webView = message.webView] in
                        guard let self, let webView else { return false }
                        return self.surfaceVisibility.isActive
                            && requestedDocumentID == self.documentID
                            && requestedFingerprint == self.session.startingFingerprint
                            && requestedVersion == self.session.generation
                            && webView.navigationDelegate === self
                    },
                    publish: { [weak webView = message.webView] response in
                        guard let webView else { return }
                        let payload = response.candidates.prefix(100).map { candidate in
                            var value =
                                [
                                    "label": candidate.label,
                                    "insertion": candidate.insertion,
                                    "detail": candidate.detail,
                                    "availability": candidate.availability.rawValue,
                                ] as [String: Any]
                            if let action = candidate.writingAction { value["writingAction"] = action }
                            if let count = candidate.replacementUTF16Count { value["replacementUTF16Count"] = count }
                            if let displayText = candidate.displayText {
                                value["displayText"] = displayText
                            }
                            if let reason = candidate.unavailableReason {
                                value["unavailableReason"] = reason
                            }
                            return value
                        }
                        let completionPayload: Any =
                            request.completionKind == .term
                            ? ["state": response.isCurrent ? "current" : "unavailable", "candidates": payload] as [String: Any]
                            : payload
                        _ = try? await webView.callAsyncJavaScript(
                            "window.scholiumEditor.resolveLinkCompletionQuery(requestID, candidates)",
                            arguments: [
                                "requestID": requestID,
                                "candidates": completionPayload,
                            ],
                            in: nil,
                            contentWorld: .page
                        )
                    }
                )
            case .linkActivated(let activation):
                guard surfaceVisibility.isActive, validEnvelope(activation.envelope) else { return }
                onLinkActivation(activation.target)
            case .imagePreview(let activation):
                guard surfaceVisibility.isActive, validEnvelope(activation.envelope), !session.isComposing else { return }
                onImagePreview(activation.target)
            case .contextMenuRequested(let request):
                guard surfaceVisibility.isActive,
                    validEnvelope(request.envelope),
                    session.acceptsInteractionRanges(
                        request.context.selections,
                        documentVersion: request.envelope.documentVersion
                    ),
                    request.mode == lastModeInput,
                    let webView = message.webView as? WindowAttachedWebView
                else { return }
                webView.presentEditorContextMenu(
                    clientX: request.clientX,
                    clientY: request.clientY,
                    context: request.context,
                    mode: request.mode
                )
            case .scrollChanged(let scroll):
                #if DEBUG
                    if timingObserver != nil {
                        timingKind = .scrollChanged
                        timingDocumentVersion = scroll.envelope.documentVersion
                        timingAdmissionStartedAt = .now
                    }
                #endif
                guard surfaceVisibility.isActive,
                    validEnvelope(scroll.envelope),
                    (0...1).contains(scroll.fraction)
                else { return }
                if let anchor = session.recordScrollPosition(
                    scroll.anchor,
                    fallbackFraction: scroll.fraction
                ) {
                    onScrollAnchorChange(anchor)
                } else {
                    session.recordScrollFraction(scroll.fraction)
                }
                onScrollFractionChange(scroll.fraction)
                #if DEBUG
                    if timingObserver != nil {
                        timingAccepted = true
                        timingAdmissionCompletedAt = .now
                    }
                #endif
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            markBootstrapNavigation(.bootstrapNavigationStarted, in: webView, navigation: navigation)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            markBootstrapNavigation(.bootstrapNavigationCommitted, in: webView, navigation: navigation)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            markBootstrapNavigation(.bootstrapNavigationFinished, in: webView, navigation: navigation)
            // The page and an injected end-of-document script both report
            // readiness. Keep this delegate as a last-resort signal on beta
            // WebKit builds that occasionally drop the first script message.
            guard awaitingEditorLoad else { return }
            awaitingEditorLoad = false
            signalReady()
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: any Error
        ) {
            session.reportError(ScholiumErrorLocalization.message(error))
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard activeWebView === webView, session.webView === webView else { return }
            PerformanceProbe.shared.invalidateNoteOpeningPage(editorSessionID: session.sessionID)
            reviewCoordinator?.setEmbeddedSurfaceActive(false)
            pageGeneration &+= 1
            session.webContentProcessTerminated()
            session.setReviewProjection(nil)
            cancelMermaidRuntimeLoad()
            cancelMathRuntimeLoad()
            cancelLinkCompletionQuery()
            writingContinuation.cancel(reason: .renderer)
            cancelDocumentTitleRename()
            hasSignaledReady = false
            awaitingEditorLoad = true
            guard let editorHTML = MarkdownEditorWebView.editorHTML else {
                session.reportError(String(localized: "The Markdown editor resources could not be reloaded.", table: "Localizable", bundle: .module))
                return
            }
            loadEditorHTML(editorHTML, in: webView)
        }

        private func requestMermaidRuntime(in webView: WKWebView) {
            guard activeWebView === webView,
                mermaidRuntimeLoadTask == nil
            else { return }
            let loadID = UUID()
            mermaidRuntimeLoadID = loadID
            mermaidRuntimeLoadTask = Task { @MainActor [weak self, weak webView] in
                guard let self else { return }
                defer {
                    if self.mermaidRuntimeLoadID == loadID {
                        self.mermaidRuntimeLoadTask = nil
                        self.mermaidRuntimeLoadID = nil
                    }
                }
                guard let webView,
                    webView.navigationDelegate === self,
                    self.activeWebView === webView,
                    !Task.isCancelled
                else { return }
                await ScholiumMermaidRuntimeLoader.installAndNotify(in: webView)
            }
        }

        private func requestMathRuntime(in webView: WKWebView) {
            guard activeWebView === webView,
                mathRuntimeLoadTask == nil
            else { return }
            let loadID = UUID()
            mathRuntimeLoadID = loadID
            mathRuntimeLoadTask = Task { @MainActor [weak self, weak webView] in
                guard let self else { return }
                defer {
                    if self.mathRuntimeLoadID == loadID {
                        self.mathRuntimeLoadTask = nil
                        self.mathRuntimeLoadID = nil
                    }
                }
                guard let webView,
                    webView.navigationDelegate === self,
                    self.activeWebView === webView,
                    !Task.isCancelled
                else { return }
                _ = await ScholiumMathRuntimeLoader.installAndRefresh(in: webView, contentWorld: .page)
            }
        }

        func requestMathRuntimeIfNeeded(in webView: WKWebView) {
            requestMathRuntime(in: webView)
        }

        func cancelMermaidRuntimeLoad() {
            mermaidRuntimeLoadTask?.cancel()
            mermaidRuntimeLoadTask = nil
            mermaidRuntimeLoadID = nil
        }

        func cancelMathRuntimeLoad() {
            mathRuntimeLoadTask?.cancel()
            mathRuntimeLoadTask = nil
            mathRuntimeLoadID = nil
        }

        @discardableResult
        func startLinkCompletionQuery(
            requestID: String, kind: EditorLinkCompletionKind, query: String,
            isCurrent: @escaping @MainActor () -> Bool,
            publish: @escaping @MainActor (EditorLinkCompletionResponse) async -> Void
        ) -> Task<Void, Never> {
            cancelLinkCompletionQuery()
            let taskID = UUID()
            linkCompletionQueryTaskID = taskID
            linkCompletionQueryKind = kind
            linkCompletionQueryRequestID = requestID
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    if self.linkCompletionQueryTaskID == taskID {
                        self.linkCompletionQueryTask = nil
                        self.linkCompletionQueryTaskID = nil
                        self.linkCompletionQueryKind = nil
                        self.linkCompletionQueryRequestID = nil
                    }
                }
                let candidates = await self.linkCompletionQuery(kind, query)
                guard !Task.isCancelled, self.linkCompletionQueryTaskID == taskID,
                    isCurrent()
                else { return }
                await publish(candidates)
            }
            linkCompletionQueryTask = task
            return task
        }

        func cancelLinkCompletionQuery() {
            linkCompletionQueryTask?.cancel()
            linkCompletionQueryTask = nil
            linkCompletionQueryTaskID = nil
            linkCompletionQueryKind = nil
            linkCompletionQueryRequestID = nil
        }

        func cancelWritingTermQuery(requestID: String? = nil) {
            guard linkCompletionQueryKind == .term,
                requestID == nil || requestID == linkCompletionQueryRequestID
            else { return }
            cancelLinkCompletionQuery()
        }

        private static func publishWritingContinuation(
            _ publication: EditorWritingContinuationController.Publication,
            requestID: String,
            in webView: WKWebView
        ) async {
            let script: String
            let value: [String: Any]
            switch publication {
            case .status(let status):
                script = "window.scholiumEditor.setWritingContinuationStatus(requestID, value)"
                value = ["phase": status.rawValue]
            case .result(let result):
                script = "return window.scholiumEditor.resolveWritingContinuation(requestID, value)"
                switch result {
                case .suggestion(let suffix):
                    value = suffix.utf16.count <= 512 ? ["text": suffix] : [:]
                case .unavailable(let reason):
                    if let reason, reason.showsInEditor {
                        let message = WebKitInterfaceLocalization.current().string(reason.localizationKey)
                        value = ["reason": String(message.prefix(512))]
                    } else {
                        value = ["reason": ""]
                    }
                }
            }
            do {
                let accepted = try await webView.callAsyncJavaScript(
                    script, arguments: ["requestID": requestID, "value": value],
                    in: nil, contentWorld: .page)
                if case .result = publication {
                    EditorWritingContinuationController.trace(
                        "bridgeResult", requestID: requestID,
                        detail: accepted as? Bool == true ? "acceptedPendingRequest" : "noPendingRequest")
                }
            } catch {
                EditorWritingContinuationController.trace("bridgeFailed", requestID: requestID)
            }
        }

        func cancelDocumentTitleRename() {
            documentTitleRenameTask?.cancel()
            documentTitleRenameTask = nil
            documentTitleRenameRequestID = nil
        }

        private func beginDocumentTitleRename(
            _ request: EditorDocumentTitleRenameMessage,
            in webView: WKWebView
        ) {
            guard documentTitleRenameTask == nil else { return }
            documentTitleRenameRequestID = request.requestID
            documentTitleRenameTask = Task { @MainActor [weak self, weak webView] in
                guard let self else { return }
                let result: (accepted: Bool, title: String, error: String)
                do {
                    let title = try await onRequestDocumentTitleRename(
                        request.expectedTitle,
                        request.requestedTitle
                    )
                    result = (true, title, "")
                } catch {
                    result = (
                        false,
                        request.expectedTitle,
                        String(ScholiumErrorLocalization.message(error).prefix(2_000))
                    )
                }
                guard !Task.isCancelled,
                    documentTitleRenameRequestID == request.requestID,
                    let webView,
                    webView.navigationDelegate === self
                else { return }
                documentTitleRenameTask = nil
                documentTitleRenameRequestID = nil
                _ = try? await webView.callAsyncJavaScript(
                    "window.scholiumEditor.resolveDocumentTitleRename(requestID, accepted, title, error)",
                    arguments: [
                        "requestID": request.requestID,
                        "accepted": result.accepted,
                        "title": result.title,
                        "error": result.error,
                    ],
                    in: nil,
                    contentWorld: .page
                )
            }
        }

        private func rejectChangedDocumentTitleRename(
            _ request: EditorDocumentTitleRenameMessage,
            in webView: WKWebView
        ) {
            let error = String(
                localized: "The note was renamed elsewhere. Review its current title before renaming again.",
                table: "Localizable",
                bundle: .module
            )
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView,
                    webView.navigationDelegate === self
                else { return }
                _ = try? await webView.callAsyncJavaScript(
                    "window.scholiumEditor.resolveDocumentTitleRename(requestID, accepted, title, error)",
                    arguments: [
                        "requestID": request.requestID,
                        "accepted": false,
                        "title": documentTitle,
                        "error": error,
                    ],
                    in: nil,
                    contentWorld: .page
                )
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
                surfaceVisibility.isActive, activeWebView === webView, session.webView === webView,
                lastModeInput == .review, session.presentedMode == .review, !session.isDirty,
                session.documentID == documentID, let url = navigationAction.request.url
            {
                reviewCoordinator?.openEmbeddedExternalLink(
                    url, sourceFingerprint: session.startingFingerprint, in: webView)
            }
            decisionHandler(
                Self.navigationPolicy(
                    url: navigationAction.request.url,
                    isMainFrame: navigationAction.targetFrame?.isMainFrame == true
                ))
        }

        static func navigationPolicy(
            url: URL?,
            isMainFrame: Bool
        ) -> WKNavigationActionPolicy {
            guard isMainFrame,
                url?.absoluteString == "about:blank"
            else { return .cancel }
            return .allow
        }

        /// Observe only the first controlled navigation of this attachment.
        /// Later reloads cannot fill gaps in its diagnostic timeline.
        func loadEditorHTML(_ editorHTML: String, in webView: WKWebView) {
            let observation: BootstrapNavigationObservation?
            if bootstrapNavigationObservation == nil, PerformanceProbe.shared.measuresNoteOpeningLifecycle,
                let attemptID = noteOpeningAttemptID, let editorSessionID = noteOpeningSessionID
            {
                let candidate = BootstrapNavigationObservation(
                    attemptID: attemptID, editorSessionID: editorSessionID, pageGeneration: pageGeneration)
                if isCurrentBootstrapObservation(candidate, in: webView) {
                    observation = candidate
                    bootstrapNavigationObservation = candidate
                    PerformanceProbe.shared.markNoteOpeningMilestone(
                        .bootstrapLoadRequested, attemptID: attemptID, editorSessionID: editorSessionID)
                } else {
                    observation = nil
                }
            } else {
                observation = nil
            }
            // The load always runs. Diagnostics never gate navigation or ready.
            let navigation = webView.loadHTMLString(editorHTML, baseURL: nil)
            if var observation {
                observation.navigation = navigation
                bootstrapNavigationObservation = observation
                if isCurrentBootstrapObservation(observation, in: webView) {
                    PerformanceProbe.shared.markNoteOpeningMilestone(
                        .bootstrapLoadReturned, attemptID: observation.attemptID,
                        editorSessionID: observation.editorSessionID)
                }
            }
        }

        private func isCurrentBootstrapObservation(
            _ observation: BootstrapNavigationObservation, in webView: WKWebView
        ) -> Bool {
            activeWebView === webView && session.webView === webView && webView.navigationDelegate === self
                && observation.pageGeneration == pageGeneration && observation.attemptID == noteOpeningAttemptID
                && observation.editorSessionID == noteOpeningSessionID && observation.editorSessionID == session.sessionID
        }

        private func markBootstrapNavigation(
            _ milestone: PerformanceProbe.NoteOpeningMilestone, in webView: WKWebView, navigation: WKNavigation?
        ) {
            guard let observation = bootstrapNavigationObservation, let navigation,
                observation.navigation === navigation, isCurrentBootstrapObservation(observation, in: webView)
            else { return }
            // These are native callback receipts, not WebContent CPU or process
            // launch times. A reload cannot complete the first navigation's span.
            PerformanceProbe.shared.markNoteOpeningMilestone(
                milestone, attemptID: observation.attemptID, editorSessionID: observation.editorSessionID)
        }

        /// Rebinding never inherits the outgoing document's ready state.
        /// A WebKit process may have died while idle: validate the page after
        /// native attachment, then use the ordinary initialization boundary.
        func resumePreparedPage(in webView: WKWebView, editorHTML: String) {
            let expectedGeneration = pageGeneration
            guard webView.navigationDelegate === self, session.webView === webView else { return }
            // A process-termination callback may already have started a reload
            // before the receiving view enters its window.
            guard !awaitingEditorLoad else { return }
            if let lease = (webView as? DocumentNativeWebView)?.editorHandoffLease,
                lease.permitsInitialization
            {
                guard !webView.isLoading else { return }
                // A frozen handoff has just acknowledged this live runtime.
                // Initialization remains the checked source boundary; probing
                // the same page first adds another WebKit round trip.
                signalReady()
                return
            }
            webView.callAsyncJavaScript(
                "return typeof window.scholiumEditor?.dispatch === 'function'",
                arguments: [:], in: nil, in: .page
            ) { [weak self, weak webView] result in
                guard let self, let webView, webView.navigationDelegate === self,
                    self.session.webView === webView,
                    self.pageGeneration == expectedGeneration
                else { return }
                if case .success(let available) = result, available as? Bool == true {
                    self.signalReady()
                } else {
                    self.awaitingEditorLoad = true
                    self.loadEditorHTML(editorHTML, in: webView)
                }
            }
        }

        private func signalReady() {
            guard !hasSignaledReady else { return }
            hasSignaledReady = true
            PerformanceProbe.shared.markEditActivationRendererReady(documentID: performanceDocumentID)
            PerformanceProbe.shared.markNoteOpeningPhase(
                .rendererReady, attemptID: noteOpeningAttemptID, editorSessionID: noteOpeningSessionID
            )
            session.setPresentationCSS(presentationCSS)
            session.setUserCSS(userCSS)
            session.setLinkPreviews(linkPreviews, in: session.checkedSource)
            session.setScrollPosition(
                anchor: session.retainedScrollAnchor ?? initialScrollAnchor,
                fallbackFraction: session.retainedScrollFraction(
                    fallback: initialScrollFraction
                )
            )
            // Stage the complete initial presentation and viewport before
            // declaring the renderer ready for its first initialization.
            session.editorBecameReady()
        }

        /// Persistence rebases the saved preimage without changing the live
        /// proposal. Publication must retain the exact source/caret proof.
        func admitsWritingContinuationPublication(
            _ envelope: EditorBridgeEnvelope, source: String, editorCaret: Int
        ) -> Bool {
            envelope.protocolVersion == markdownEditorProtocolVersion
                && envelope.sessionID == session.sessionID.uuidString
                && envelope.documentID == documentID
                && envelope.documentID == session.documentID
                && session.checkedSource.utf8.elementsEqual(source.utf8)
                && session.acceptsInsertionPoint(
                    .init(
                        sessionID: session.sessionID, documentID: envelope.documentID,
                        generation: envelope.documentVersion,
                        selection: .init(anchor: editorCaret, head: editorCaret)))
        }

        private func admitsFloatingSurface(_ event: DocumentFloatingEvent) -> Bool {
            guard surfaceVisibility.isActive else { return false }
            switch event {
            case .preview, .previewFailure, .suggestions:
                return lastModeInput == .livePreview
            case .selection:
                return lastModeInput != .review
            case .dismiss:
                return true
            }
        }

        private func validEnvelope(
            _ envelope: EditorBridgeEnvelope,
            allowingFutureGeneration: Bool = false
        ) -> Bool {
            guard envelope.protocolVersion == markdownEditorProtocolVersion,
                envelope.sessionID == session.sessionID.uuidString,
                envelope.documentID == session.documentID,
                envelope.startingFingerprint == session.startingFingerprint,
                activeWebView != nil, activeWebView === session.webView
            else { return false }
            return allowingFutureGeneration
                ? envelope.documentVersion >= session.generation
                : envelope.documentVersion == session.generation
        }

        private func applyEditorChanges(
            _ change: EditorDocumentChangeMessage,
            in webView: WKWebView?
        ) -> Bool {
            guard
                session.acceptEditorChanges(
                    change.changes,
                    baseGeneration: change.baseGeneration,
                    resultingGeneration: change.resultingGeneration,
                    citationManaged: change.citationManaged, citationData: change.citationData
                )
            else {
                if let webView,
                    change.resultingGeneration > session.generation
                {
                    session.reconcileAfterRejectedEditorChanges(
                        resultingGeneration: change.resultingGeneration,
                        in: webView
                    )
                }
                if writingContinuation.requestID != nil {
                    EditorWritingContinuationController.trace("ignoredEditorMessage", requestID: writingContinuation.requestID, detail: "deltaAdmission")
                }
                return false
            }
            return true
        }
    }
}
