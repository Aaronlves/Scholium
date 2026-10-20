import AppKit
import ScholiumContracts
import SwiftUI
import WebKit

typealias DocumentSelectionActionPresenter = @MainActor (AgentChatSelectionInquiry) async throws -> Bool

struct SafeMarkdownReadWebView: NSViewRepresentable {
    static let configurationVersion = 8
    @Environment(\.scholiumDocumentSurfaceVisibility)
    private var surfaceVisibility
    @Environment(\.documentToolbarUnderlap) private var toolbarUnderlap
    /// Standalone readers isolate app-owned bridge scripts and their native
    /// handler in this named world. Embedded Review uses the editor page world
    /// and transports reader events through the editor's bound envelope.
    static let bridgeContentWorldName = "ScholiumRead"
    static let bridgeContentWorld = WKContentWorld.world(name: bridgeContentWorldName)

    let documentID: String
    var documentTitle = ""
    /// Source, revision and frontmatter boundaries come from one already
    /// prepared immutable snapshot; native page construction never reparses it.
    let document: NoteDocument
    private var fingerprint: String { document.fingerprint.sha256 }
    let htmlBody: String
    let presentationCSS: String
    let userCSS: String
    /// Stable caller-owned revisions avoid hashing bounded-but-nontrivial
    /// preview payloads during unrelated SwiftUI updates.
    var configurationRevision: String? = nil
    var linkPreviews: [DocumentLinkPreview] = []
    /// A caller-owned revision lets preview data converge without becoming a
    /// document-load identity or hashing bounded HTML on every SwiftUI pass.
    var linkPreviewRevision: String? = nil
    let onLinkClick: (String) -> Void
    var onImagePreview: ((String) -> Void)? = nil
    let onOpenExternalURL: (URL) -> Void
    var onAskAgent: AgentSelectionInquiryHandler? = nil
    var onPassageAction: ((DocumentPassageAction, MarkdownSourceSelectionSnapshot) -> Void)? = nil
    var onSelectionActionPresenterReady: ((@escaping DocumentSelectionActionPresenter) -> Void)? = nil
    var onPreviewFailure: ((DocumentPreviewFailure) -> Void)? = nil
    var onSelectionChange: ((MarkdownReviewSelection?) -> Void)? = nil
    /// Derived visibility only. Review remains the sole selection-surface
    /// owner; the coordinator transports mode changes to its retained page.
    var selectionSurfaceIsActive = true
    /// The caller's acknowledgement of the coordinator's finalized revision.
    /// A retained page can re-announce readiness when a reconstructed outer
    /// session has lost this derived state without forcing a duplicate load.
    var renderingReadinessIsAcknowledged = false
    let onRenderingFailure: ((String) -> Void)?
    var onRenderingLoading: (() -> Void)? = nil
    var onRenderingReady: (() -> Void)? = nil
    var pageExtension: (any ScholiumReadPageExtension)? = nil
    var onRenderedDiagramSize: ((CGSize) -> Void)? = nil
    var findRequest: DocumentFindPresentationRequest? = nil
    var onFindResult: ((UInt64, Result<DocumentFindResult, any Error>) -> Void)? = nil
    var observedScrollPosition = ObservedScrollPosition()
    var scrollRestoreRequest: ScrollRestoreRequest? = nil
    var onScrollRestoreConsumed: ((UInt64, String) -> Void)? = nil
    var onScrollFractionChange: ((Double) -> Void)? = nil
    var onScrollAnchorChange: ((EditorScrollAnchor) -> Void)? = nil
    var sourceLocationRequest: DocumentSourceLocationRequest? = nil
    var onSourceRangeUnavailable: ((UUID) -> Void)? = nil
    var onSourceRevisionChanged: ((UUID) -> Void)? = nil
    var onSourceLocationReached: ((UUID) -> Void)? = nil
    #if DEBUG
        var testingForcesFinalizationFailure = false
        var testingScrollRestoreDelayMilliseconds = 0
    #endif

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(
            documentID: documentID,
            fingerprint: fingerprint,
            onLinkClick: onLinkClick,
            onImagePreview: onImagePreview,
            onOpenExternalURL: onOpenExternalURL,
            onSelectionChange: onSelectionChange,
            selectionSurfaceIsActive: selectionSurfaceIsActive,
            renderingReadinessIsAcknowledged: renderingReadinessIsAcknowledged,
            onRenderingFailure: onRenderingFailure,
            onRenderingLoading: onRenderingLoading,
            onRenderingReady: onRenderingReady,
            findRequest: findRequest,
            onFindResult: onFindResult,
            observedScrollPosition: observedScrollPosition,
            scrollRestoreRequest: scrollRestoreRequest,
            onScrollRestoreConsumed: onScrollRestoreConsumed,
            onScrollFractionChange: onScrollFractionChange,
            onScrollAnchorChange: onScrollAnchorChange,
            sourceLocationRequest: sourceLocationRequest,
            onSourceLocationReached: onSourceLocationReached
        )
        #if DEBUG
            coordinator.testingForcesFinalizationFailure = testingForcesFinalizationFailure
            coordinator.testingScrollRestoreDelayMilliseconds = testingScrollRestoreDelayMilliseconds
        #endif
        coordinator.pageExtension = pageExtension
        coordinator.onRenderedDiagramSize = onRenderedDiagramSize
        coordinator.onAskAgent = onAskAgent
        coordinator.floatingPreviewFailure = onPreviewFailure
        coordinator.onPassageAction = onPassageAction
        coordinator.onSourceRangeUnavailable = onSourceRangeUnavailable
        coordinator.onSourceRevisionChanged = onSourceRevisionChanged
        return coordinator
    }

    func makeNSView(context: Context) -> DocumentWebViewContainer {
        let webView: WKWebView
        let contentController: WKUserContentController
        if pageExtension == nil, let prepared = ScholiumWebKitProcessPrewarmer.shared.takeReadWebView() {
            webView = prepared
            contentController = prepared.configuration.userContentController
        } else {
            contentController = WKUserContentController()
            let configuration = WKWebViewConfiguration()
            configuration.userContentController = contentController
            configuration.websiteDataStore = ScholiumWebKitRuntime.nonPersistentDataStore
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            ScholiumWebFontResources.install(in: configuration)
            webView =
                pageExtension?.makeWebView(configuration: configuration)
                ?? DocumentNativeWebView(frame: .zero, configuration: configuration)
        }
        contentController.add(
            context.coordinator,
            contentWorld: Self.bridgeContentWorld,
            name: Coordinator.messageHandlerName
        )
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityElement(true)
        webView.setAccessibilityLabel(ScholiumL10n.string("Rendered Markdown"))
        webView.setAccessibilityIdentifier("scholium.renderedDocument.loading")
        context.coordinator.surfaceVisibility = surfaceVisibility
        context.coordinator.loadIfNeeded(
            htmlBody,
            documentTitle: documentTitle,
            document: document,
            presentationCSS: presentationCSS,
            userCSS: userCSS,
            configurationRevision: configurationRevision,
            linkPreviews: linkPreviews,
            linkPreviewRevision: linkPreviewRevision,
            in: webView
        )
        let container = DocumentWebViewContainer(
            webView: webView,
            keyEquivalentRoute: { event in
                ScholiumCommandKeyEquivalentRouter.route(event)
            }
        )
        container.setSurfaceVisibility(surfaceVisibility)
        container.toolbarUnderlapEnabled = toolbarUnderlap
        context.coordinator.surfaceVisibility = surfaceVisibility
        let presenter = context.coordinator.selectionActionPresenter(in: webView)
        Task { @MainActor in onSelectionActionPresenterReady?(presenter) }
        return container
    }

    func updateNSView(_ container: DocumentWebViewContainer, context: Context) {
        container.toolbarUnderlapEnabled = toolbarUnderlap
        let webView = container.webView
        container.setSurfaceVisibility(surfaceVisibility)
        context.coordinator.surfaceVisibility = surfaceVisibility
        #if DEBUG
            context.coordinator.testingForcesFinalizationFailure = testingForcesFinalizationFailure
            context.coordinator.testingScrollRestoreDelayMilliseconds =
                testingScrollRestoreDelayMilliseconds
        #endif
        context.coordinator.pageExtension = pageExtension
        context.coordinator.onRenderedDiagramSize = onRenderedDiagramSize
        context.coordinator.onAskAgent = onAskAgent
        context.coordinator.floatingPreviewFailure = onPreviewFailure
        context.coordinator.onPassageAction = onPassageAction
        context.coordinator.onSourceRangeUnavailable = onSourceRangeUnavailable
        context.coordinator.onSourceRevisionChanged = onSourceRevisionChanged
        context.coordinator.update(
            documentID: documentID,
            fingerprint: fingerprint,
            onLinkClick: onLinkClick,
            onImagePreview: onImagePreview,
            onOpenExternalURL: onOpenExternalURL,
            onSelectionChange: onSelectionChange,
            selectionSurfaceIsActive: selectionSurfaceIsActive,
            renderingReadinessIsAcknowledged: renderingReadinessIsAcknowledged,
            onRenderingFailure: onRenderingFailure,
            onRenderingLoading: onRenderingLoading,
            onRenderingReady: onRenderingReady,
            findRequest: findRequest,
            onFindResult: onFindResult,
            observedScrollPosition: observedScrollPosition,
            scrollRestoreRequest: scrollRestoreRequest,
            onScrollRestoreConsumed: onScrollRestoreConsumed,
            onScrollFractionChange: onScrollFractionChange,
            onScrollAnchorChange: onScrollAnchorChange,
            sourceLocationRequest: sourceLocationRequest,
            onSourceLocationReached: onSourceLocationReached,
            webView: webView
        )
        context.coordinator.loadIfNeeded(
            htmlBody,
            documentTitle: documentTitle,
            document: document,
            presentationCSS: presentationCSS,
            userCSS: userCSS,
            configurationRevision: configurationRevision,
            linkPreviews: linkPreviews,
            linkPreviewRevision: linkPreviewRevision,
            in: webView
        )
    }

    /// Binds the existing Reader interaction owner to the shared editor page.
    /// It installs neither a WebView, navigation delegate, script nor handler.
    func embeddedProjection(using coordinator: Coordinator, in webView: WKWebView) -> MarkdownEditorReviewProjection {
        coordinator.onAskAgent = onAskAgent
        coordinator.floatingPreviewFailure = onPreviewFailure
        coordinator.onPassageAction = onPassageAction
        coordinator.onSourceRangeUnavailable = onSourceRangeUnavailable
        coordinator.onSourceRevisionChanged = onSourceRevisionChanged
        coordinator.update(
            documentID: documentID,
            fingerprint: fingerprint,
            onLinkClick: onLinkClick,
            onImagePreview: onImagePreview,
            onOpenExternalURL: onOpenExternalURL,
            onSelectionChange: onSelectionChange,
            selectionSurfaceIsActive: selectionSurfaceIsActive,
            renderingReadinessIsAcknowledged: renderingReadinessIsAcknowledged,
            onRenderingFailure: onRenderingFailure,
            onRenderingLoading: onRenderingLoading,
            onRenderingReady: onRenderingReady,
            findRequest: findRequest,
            onFindResult: onFindResult,
            observedScrollPosition: observedScrollPosition,
            scrollRestoreRequest: scrollRestoreRequest,
            onScrollRestoreConsumed: onScrollRestoreConsumed,
            onScrollFractionChange: onScrollFractionChange,
            onScrollAnchorChange: onScrollAnchorChange,
            sourceLocationRequest: sourceLocationRequest,
            onSourceLocationReached: onSourceLocationReached,
            webView: webView
        )
        let projection = coordinator.prepareEmbeddedProjection(
            body: htmlBody, documentTitle: documentTitle, document: document,
            presentationCSS: presentationCSS, userCSS: userCSS, linkPreviews: linkPreviews,
            configurationRevision: configurationRevision, linkPreviewRevision: linkPreviewRevision, in: webView)
        return projection
    }

    static func dismantleNSView(_ container: DocumentWebViewContainer, coordinator: Coordinator) {
        let webView = container.webView
        Task { @MainActor [weak webView] in
            guard let webView else { return }
            _ = try? await webView.evaluateJavaScript(
                "window.scholiumSetReviewSelectionSurfaceActive?.(false)",
                in: nil,
                contentWorld: SafeMarkdownReadWebView.bridgeContentWorld
            )
        }
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.messageHandlerName,
            contentWorld: Self.bridgeContentWorld
        )
        webView.navigationDelegate = nil
        coordinator.activeWebView = nil
        coordinator.cancelPendingPageWork()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private typealias ScrollRestoreClaim = SafeMarkdownReadScrollRestoration.Claim

        static let messageHandlerName = "scholiumRead"
        private static let maximumSelectionLength = 32_000
        private var documentID: String
        private var fingerprint: String
        private var onLinkClick: (String) -> Void
        private var onImagePreview: ((String) -> Void)?
        private var onOpenExternalURL: (URL) -> Void
        var onAskAgent: AgentSelectionInquiryHandler?
        var floatingPreviewFailure: ((DocumentPreviewFailure) -> Void)?
        var onPassageAction: ((DocumentPassageAction, MarkdownSourceSelectionSnapshot) -> Void)?
        private var onSelectionChange: ((MarkdownReviewSelection?) -> Void)?
        private let selectionCoordinator: SafeMarkdownReadSelectionCoordinator
        private let floatingSurfaces = DocumentFloatingSurfaceController()

        func selectionActionPresenter(in webView: WKWebView) -> DocumentSelectionActionPresenter {
            { [weak self, weak webView] inquiry in
                guard let self, let webView, self.activeWebView === webView,
                    self.surfaceVisibility.isActive, self.selectionCoordinator.isActive, self.onAskAgent != nil
                else { return false }
                let expectedGeneration = self.loadGeneration
                return try await self.floatingSurfaces.presentSelectionInquiry(inquiry, in: webView) {
                    let surfaceID = try await webView.callAsyncJavaScript(
                        """
                        if (window.scholiumReadReady) await window.scholiumReadReady;
                        return await window.scholiumShowSelectionActions?.();
                        """,
                        arguments: [:], in: nil, contentWorld: self.bridgeContentWorld
                    )
                    guard self.loadGeneration == expectedGeneration,
                        self.activeWebView === webView, self.surfaceVisibility.isActive
                    else { return nil }
                    return surfaceID as? Int
                }
            }
        }
        private let findCoordinator = SafeMarkdownReadFindCoordinator()
        private let runtimeCoordinator = SafeMarkdownReadRuntimeCoordinator()
        private var renderingReadinessIsAcknowledged: Bool
        private var onRenderingFailure: ((String) -> Void)?
        private var onRenderingLoading: (() -> Void)?
        var pageExtension: (any ScholiumReadPageExtension)? = nil

        var onRenderedDiagramSize: ((CGSize) -> Void)?
        private var onRenderingReady: (() -> Void)?
        private var scrollRestoration: SafeMarkdownReadScrollRestoration
        private var hasLoadedPage = false
        private var loadGeneration: UInt64 = 0
        private var activeLoadSignature: String?
        private var activeNavigation: WKNavigation?
        private var loadFinalizationTask: Task<Void, Never>?
        private var sourceLineNavigationTask: Task<Void, Never>?
        private var linkPreviewUpdateTask: Task<Void, Never>?
        private var desiredLinkPreviewRevision = ""
        private var appliedLinkPreviewRevision = ""
        private var loadingLinkPreviewRevision = ""
        private var desiredLinkPreviews: [DocumentLinkPreview] = []
        private var deferredLoadTask: Task<Void, Never>?
        private var desiredPresentationCSS = ""
        private var desiredUserCSS = ""
        private var appliedPresentationCSS = ""
        private var appliedUserCSS = ""
        private var presentationStyleRevision: UInt64 = 0
        private var presentationStyleTask: Task<Void, Never>?
        private var onScrollFractionChange: ((Double) -> Void)?

        private var onScrollAnchorChange: ((EditorScrollAnchor) -> Void)?
        private var selectionSource = ""
        private var sourceUTF16Length = 0
        private var sourceLocationRequest: DocumentSourceLocationRequest?
        private var onSourceLocationReached: ((UUID) -> Void)?
        private var lastReachedSourceLocationID: UUID?
        var onSourceRangeUnavailable: ((UUID) -> Void)?
        var onSourceRevisionChanged: ((UUID) -> Void)?
        private var loadedSignature: String?
        private var finalizedSignature: String?
        private var pageIsReady = false
        private var isEmbeddedProjection = false
        private var embeddedSurfaceIsActive = false
        private var embeddedPresentationIsReady = false
        var onEmbeddedScrollPositionChange: ((ObservedScrollPosition) -> Void)?

        /// Session preparation owns the shared viewport until its current
        /// Review mode is acknowledged. Find and source locators are explicit
        /// navigation intents and run only after that restoration completes.
        private var canApplyReadingNavigation: Bool {
            !isEmbeddedProjection
                || (embeddedSurfaceIsActive && embeddedPresentationIsReady && surfaceVisibility.isActive)
        }
        private var cachedEmbeddedProjection: MarkdownEditorReviewProjection?
        private var cachedEmbeddedProjectionIdentity: String?
        var bridgeContentWorld = SafeMarkdownReadWebView.bridgeContentWorld
        weak var activeWebView: WKWebView?
        var surfaceVisibility: DocumentSurfaceVisibility = .active
        #if DEBUG
            var testingForcesFinalizationFailure = false
            var testingScrollRestoreDelayMilliseconds = 0
        #endif

        init(
            documentID: String,
            fingerprint: String,
            onLinkClick: @escaping (String) -> Void,
            onImagePreview: ((String) -> Void)? = nil,
            onOpenExternalURL: @escaping (URL) -> Void,
            onSelectionChange: ((MarkdownReviewSelection?) -> Void)?,
            selectionSurfaceIsActive: Bool,
            renderingReadinessIsAcknowledged: Bool,
            onRenderingFailure: ((String) -> Void)?,
            onRenderingLoading: (() -> Void)?,
            onRenderingReady: (() -> Void)?,
            findRequest: DocumentFindPresentationRequest?,
            onFindResult: ((UInt64, Result<DocumentFindResult, any Error>) -> Void)?,
            observedScrollPosition: ObservedScrollPosition,
            scrollRestoreRequest: ScrollRestoreRequest?,
            onScrollRestoreConsumed: ((UInt64, String) -> Void)?,
            onScrollFractionChange: ((Double) -> Void)?,
            onScrollAnchorChange: ((EditorScrollAnchor) -> Void)?,
            sourceLocationRequest: DocumentSourceLocationRequest?,
            onSourceLocationReached: ((UUID) -> Void)?
        ) {
            self.documentID = documentID
            self.fingerprint = fingerprint
            self.onLinkClick = onLinkClick
            self.onImagePreview = onImagePreview
            self.onOpenExternalURL = onOpenExternalURL
            self.onSelectionChange = onSelectionChange
            selectionCoordinator = SafeMarkdownReadSelectionCoordinator(
                isActive: selectionSurfaceIsActive
            )
            self.renderingReadinessIsAcknowledged = renderingReadinessIsAcknowledged
            self.onRenderingFailure = onRenderingFailure
            self.onRenderingLoading = onRenderingLoading
            self.onRenderingReady = onRenderingReady
            findCoordinator.update(request: findRequest, report: onFindResult)
            scrollRestoration = SafeMarkdownReadScrollRestoration(
                observedPosition: observedScrollPosition,
                request: scrollRestoreRequest,
                onCallerRequestConsumed: onScrollRestoreConsumed
            )
            self.onScrollFractionChange = onScrollFractionChange
            self.onScrollAnchorChange = onScrollAnchorChange
            self.sourceLocationRequest = sourceLocationRequest
            self.onSourceLocationReached = onSourceLocationReached
        }

        func update(
            documentID: String,
            fingerprint: String,
            onLinkClick: @escaping (String) -> Void,
            onImagePreview: ((String) -> Void)? = nil,
            onOpenExternalURL: @escaping (URL) -> Void,
            onSelectionChange: ((MarkdownReviewSelection?) -> Void)?,
            selectionSurfaceIsActive: Bool,
            renderingReadinessIsAcknowledged: Bool,
            onRenderingFailure: ((String) -> Void)?,
            onRenderingLoading: (() -> Void)?,
            onRenderingReady: (() -> Void)?,
            findRequest: DocumentFindPresentationRequest?,
            onFindResult: ((UInt64, Result<DocumentFindResult, any Error>) -> Void)?,
            observedScrollPosition: ObservedScrollPosition,
            scrollRestoreRequest: ScrollRestoreRequest?,
            onScrollRestoreConsumed: ((UInt64, String) -> Void)?,
            onScrollFractionChange: ((Double) -> Void)?,
            onScrollAnchorChange: ((EditorScrollAnchor) -> Void)?,
            sourceLocationRequest: DocumentSourceLocationRequest?,
            onSourceLocationReached: ((UUID) -> Void)?,
            webView: WKWebView
        ) {
            let documentChanged = self.documentID != documentID || self.fingerprint != fingerprint
            if documentChanged
                && !(pageExtension?.preservesPage(
                    currentDocumentID: self.documentID,
                    nextDocumentID: documentID,
                    hasLoadedPage: hasLoadedPage
                ) == true)
            {
                loadedSignature = nil
                finalizedSignature = nil
                appliedLinkPreviewRevision = ""
                loadingLinkPreviewRevision = ""
                lastReachedSourceLocationID = nil
                pageIsReady = false
                selectionCoordinator.resetForDocumentChange()
                findCoordinator.resetForDocumentChange()
                hasLoadedPage = false
                cancelPendingPageWork()
                webView.setAccessibilityIdentifier("scholium.renderedDocument.loading")
            }
            activeWebView = webView
            self.documentID = documentID
            self.fingerprint = fingerprint
            self.onLinkClick = onLinkClick
            self.onImagePreview = onImagePreview
            self.onOpenExternalURL = onOpenExternalURL
            self.onSelectionChange = onSelectionChange
            self.renderingReadinessIsAcknowledged = renderingReadinessIsAcknowledged
            self.onRenderingFailure = onRenderingFailure
            self.onRenderingLoading = onRenderingLoading
            self.onRenderingReady = onRenderingReady
            findCoordinator.update(request: findRequest, report: onFindResult)
            var observedScrollPosition = observedScrollPosition
            if observedScrollPosition.anchor?.sourceFingerprint != fingerprint {
                observedScrollPosition.anchor = nil
            }
            scrollRestoration.update(
                observedPosition: observedScrollPosition,
                onCallerRequestConsumed: onScrollRestoreConsumed
            )
            scrollRestoration.adoptCallerRequest(scrollRestoreRequest)
            self.onScrollFractionChange = onScrollFractionChange
            self.onScrollAnchorChange = onScrollAnchorChange
            self.sourceLocationRequest = sourceLocationRequest
            self.onSourceLocationReached = onSourceLocationReached
            selectionCoordinator.update(isActive: selectionSurfaceIsActive)
            schedulePostLoadPositioningIfNeeded(in: webView)
            applySelectionCommandsIfNeeded(in: webView)
            applyFindRequestIfNeeded(in: webView)
        }

        func setEmbeddedSurfaceActive(_ active: Bool) {
            defer { embeddedSurfaceIsActive = active }
            guard !active else { return }
            embeddedPresentationIsReady = false
            surfaceVisibility = .retained
            guard isEmbeddedProjection, embeddedSurfaceIsActive else { return }
            // A new mount has a new event/Find/selection lifetime, even when
            // its committed source revision is unchanged.
            loadGeneration &+= 1
            cachedEmbeddedProjectionIdentity = nil
            pageIsReady = false
            finalizedSignature = nil
            floatingSurfaces.reset()
            selectionCoordinator.resetForDocumentChange()
            findCoordinator.resetForDocumentChange()
            sourceLineNavigationTask?.cancel()
            sourceLineNavigationTask = nil
            loadFinalizationTask?.cancel()
            loadFinalizationTask = nil
            scrollRestoration.cancelClaim()
        }

        func setEmbeddedPresentationReady(_ ready: Bool) {
            embeddedPresentationIsReady = ready
            guard ready else {
                sourceLineNavigationTask?.cancel()
                sourceLineNavigationTask = nil
                return
            }
        }

        func prepareEmbeddedProjection(
            body: String, documentTitle: String, document: NoteDocument,
            presentationCSS: String, userCSS: String, linkPreviews: [DocumentLinkPreview],
            configurationRevision: String?, linkPreviewRevision: String?, in webView: WKWebView
        ) -> MarkdownEditorReviewProjection {
            isEmbeddedProjection = true
            bridgeContentWorld = .page
            findCoordinator.bridgeContentWorld = .page
            runtimeCoordinator.bridgeContentWorld = .page
            selectionCoordinator.bridgeContentWorld = .page
            activeWebView = webView
            let signature = "embedded:\(documentID):\(fingerprint)"
            let projectionIdentity = [
                signature, documentTitle, configurationRevision ?? String(body.hashValue),
                linkPreviewRevision ?? String(linkPreviews.hashValue),
                String(presentationCSS.hashValue), String(userCSS.hashValue),
            ].joined(separator: ":")
            if cachedEmbeddedProjectionIdentity == projectionIdentity, let cachedEmbeddedProjection {
                return cachedEmbeddedProjection
            }
            if activeLoadSignature != signature {
                loadGeneration &+= 1
                pageIsReady = false
                finalizedSignature = nil
                activeLoadSignature = signature
                loadedSignature = signature
                selectionSource = document.rawContent
                sourceUTF16Length = document.rawContent.utf16.count
            }
            let localization = WebKitInterfaceLocalization.current()
            let complete = Self.documentHTML(
                body: body, frontmatter: document.rawFrontmatter,
                frontmatterHasAuthoredBodyBlankLine: !document.body.isEmpty
                    && document.body.prefix { !$0.isNewline }.allSatisfy(\.isWhitespace),
                documentTitle: documentTitle, localization: localization)
            let lower = complete.range(of: "<body>")!.upperBound
            let upper = complete.range(of: "</body>")!.lowerBound
            let markup = String(complete[lower..<upper])
            let cssLower = complete.range(of: "<style>")!.upperBound
            let cssUpper = complete.range(of: "</style>")!.lowerBound
            let css = String(complete[cssLower..<cssUpper])
            if let previous = cachedEmbeddedProjection,
                previous.sourceFingerprint == fingerprint,
                previous.htmlBody != markup || previous.css != css
            {
                loadGeneration &+= 1
                pageIsReady = false
                finalizedSignature = nil
            }
            let configuration = Self.bridgeConfiguration(
                documentID: documentID, fingerprint: fingerprint, loadGeneration: loadGeneration,
                selectionEnabled: onSelectionChange != nil, imagePreviewsEnabled: onImagePreview != nil,
                replyProjection: false, linkPreviews: linkPreviews,
                presentationCSS: presentationCSS, userCSS: userCSS, localization: localization)
            let projection = MarkdownEditorReviewProjection(
                sourceFingerprint: fingerprint, htmlBody: markup, css: css, configuration: configuration)
            cachedEmbeddedProjection = projection
            cachedEmbeddedProjectionIdentity = projectionIdentity
            return projection
        }

        func loadIfNeeded(
            _ body: String,
            documentTitle: String,
            document: NoteDocument,
            presentationCSS: String,
            userCSS: String,
            configurationRevision: String?,
            linkPreviews: [DocumentLinkPreview],
            linkPreviewRevision: String?,
            in webView: WKWebView
        ) {
            let source = document.rawContent
            let interfaceLocalization = WebKitInterfaceLocalization.current()
            if desiredPresentationCSS != presentationCSS || desiredUserCSS != userCSS {
                presentationStyleRevision &+= 1
                desiredPresentationCSS = presentationCSS
                desiredUserCSS = userCSS
            }
            let capabilitySignature = "\(onSelectionChange != nil):\(onImagePreview != nil)"
            let previewRevision = linkPreviewRevision ?? String(linkPreviews.hashValue)
            let signature =
                configurationRevision.map {
                    "revision:\($0):\(documentTitle.hashValue):\(capabilitySignature):\(interfaceLocalization.languageTag)"
                }
                ?? [
                    fingerprint,
                    String(body.utf8.count),
                    String(documentTitle.hashValue),
                    String(presentationCSS.hashValue),
                    String(userCSS.hashValue),
                    String(linkPreviews.hashValue),
                    capabilitySignature,
                ].joined(separator: ":")
            desiredLinkPreviews = linkPreviews
            desiredLinkPreviewRevision = previewRevision
            guard loadedSignature != signature else {
                reannounceFinalizedRenderingIfNeeded(
                    signature: signature,
                    in: webView
                )
                applyLinkPreviewsIfNeeded(in: webView)
                schedulePresentationStyleUpdate(in: webView)
                applySelectionCommandsIfNeeded(in: webView)
                applyFindRequestIfNeeded(in: webView)
                return
            }
            if pageExtension?.canUpdateInPlace(
                currentDocumentID: self.documentID,
                nextDocumentID: documentID,
                hasLoadedPage: hasLoadedPage
            ) == true {
                loadedSignature = signature
                let generation = loadGeneration
                let expectedDocumentID = documentID
                let didStart =
                    pageExtension?.updateIfNeeded(
                        body: body,
                        source: source,
                        fingerprint: fingerprint,
                        signature: signature,
                        documentID: expectedDocumentID,
                        loadGeneration: generation,
                        presentationCSS: presentationCSS,
                        userCSS: userCSS,
                        in: webView,
                        isCurrent: { [weak self, weak webView] in
                            guard let self, let webView else { return false }
                            return self.activeWebView === webView
                                && self.loadGeneration == generation
                                && self.loadedSignature == signature
                        },
                        didApply: { [weak self, weak webView] source, _ in
                            guard let self, let webView,
                                self.activeWebView === webView,
                                self.loadedSignature == signature
                            else { return }
                            self.selectionSource = source
                            self.sourceUTF16Length = source.utf16.count
                            self.pageIsReady = true
                            self.finalizedSignature = signature
                            self.renderingReadinessIsAcknowledged = true
                            webView.setAccessibilityIdentifier("scholium.renderedDocument.\(expectedDocumentID)")
                            self.onRenderingReady?()
                        },
                        didFail: { [weak self, weak webView] error in
                            guard let self, self.loadedSignature == signature else { return }
                            #if DEBUG
                                if let webView, !Task.isCancelled,
                                    self.activeWebView === webView, self.loadGeneration == generation
                                {
                                    PerformanceProbe.shared.recordQAReaderFailure(
                                        phase: .presentationUpdate, generation: generation, error: error)
                                }
                            #endif
                            self.onRenderingFailure?(error.localizedDescription)
                        }
                    ) == true
                if didStart { return }
            }
            selectionSource = source
            sourceUTF16Length = source.utf16.count
            let publishesLoadingTransition =
                hasLoadedPage
                || renderingReadinessIsAcknowledged
            scrollRestoration.ensureRequest(
                fingerprint: fingerprint,
                reason: hasLoadedPage ? .webViewRebuild : .documentLoad
            )
            hasLoadedPage = true
            loadGeneration &+= 1
            let expectedLoadGeneration = loadGeneration
            activeLoadSignature = signature
            activeNavigation = nil
            cancelPendingPageWork(keepingLoadIdentity: true)
            pageExtension?.willBeginLoad(fingerprint: fingerprint)
            loadedSignature = signature
            finalizedSignature = nil
            renderingReadinessIsAcknowledged = false
            presentationStyleTask?.cancel()
            presentationStyleTask = nil
            appliedPresentationCSS = presentationCSS
            appliedUserCSS = userCSS
            loadingLinkPreviewRevision = previewRevision
            pageIsReady = false
            selectionCoordinator.resetForDocumentChange()
            findCoordinator.resetForDocumentChange()
            activeWebView = webView
            let includesMathRuntime = Self.requiresMathRuntime(
                body: body,
                linkPreviews: linkPreviews
            )
            installBridgeScripts(
                presentationCSS: presentationCSS,
                userCSS: userCSS,
                linkPreviews: linkPreviews,
                includesMathRuntime: includesMathRuntime || pageExtension?.requiresMathRuntime == true,
                loadGeneration: loadGeneration,
                localization: interfaceLocalization,
                in: webView
            )
            let html = Self.documentHTML(
                body: body,
                frontmatter: document.rawFrontmatter,
                frontmatterHasAuthoredBodyBlankLine: !document.body.isEmpty
                    && document.body.prefix { !$0.isNewline }.allSatisfy(\.isWhitespace),
                documentTitle: documentTitle,
                includesMathRuntime: includesMathRuntime || pageExtension?.requiresMathRuntime == true,
                localization: interfaceLocalization
            )
            let expectedSignature = signature
            if !publishesLoadingTransition {
                PerformanceProbe.shared.markReadNavigationStarted(
                    documentID: documentID
                )
                let navigation = webView.loadHTMLString(html, baseURL: nil)
                guard activeWebView === webView,
                    loadedSignature == expectedSignature,
                    activeLoadSignature == expectedSignature,
                    loadGeneration == expectedLoadGeneration
                else { return }
                activeNavigation = navigation
                return
            }
            deferredLoadTask?.cancel()
            deferredLoadTask = Task { @MainActor [weak self, weak webView] in
                guard let self, let webView,
                    self.activeWebView === webView,
                    self.loadedSignature == expectedSignature
                else { return }
                self.onRenderingLoading?()
                await Task.yield()
                guard self.activeWebView === webView,
                    self.loadedSignature == expectedSignature,
                    self.activeLoadSignature == expectedSignature,
                    self.loadGeneration == expectedLoadGeneration
                else { return }
                PerformanceProbe.shared.markReadNavigationStarted(
                    documentID: self.documentID
                )
                let navigation = webView.loadHTMLString(html, baseURL: nil)
                guard self.activeWebView === webView,
                    self.loadedSignature == expectedSignature,
                    self.activeLoadSignature == expectedSignature,
                    self.loadGeneration == expectedLoadGeneration
                else { return }
                self.activeNavigation = navigation
            }
        }

        /// Installs the app-owned math runtime and generated Read bundle into the
        /// named content world before the next page load. The page world
        /// receives no scripts, so research text and CSS can never reach a
        /// script boundary.
        private func installBridgeScripts(
            presentationCSS: String,
            userCSS: String,
            linkPreviews: [DocumentLinkPreview],
            includesMathRuntime: Bool,
            loadGeneration: UInt64,
            localization: WebKitInterfaceLocalization,
            in webView: WKWebView
        ) {
            let contentController = webView.configuration.userContentController
            contentController.removeAllUserScripts()
            if includesMathRuntime, !ScholiumMathAssets.runtimeJavaScript.isEmpty {
                contentController.addUserScript(
                    WKUserScript(
                        source: ScholiumMathAssets.runtimeJavaScript,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true,
                        in: bridgeContentWorld
                    ))
            }
            if let readerScript = Self.readerScript {
                contentController.addUserScript(
                    WKUserScript(
                        source: readerScript,
                        injectionTime: .atDocumentEnd,
                        forMainFrameOnly: true,
                        in: bridgeContentWorld
                    ))
            }
            contentController.addUserScript(
                WKUserScript(
                    source: Self.bridgeScript(
                        documentID: documentID,
                        fingerprint: fingerprint,
                        loadGeneration: loadGeneration,
                        selectionEnabled: onSelectionChange != nil,
                        imagePreviewsEnabled: onImagePreview != nil,
                        replyProjection: pageExtension?.replyProjectionEnabled == true,
                        linkPreviews: linkPreviews,
                        presentationCSS: presentationCSS,
                        userCSS: userCSS,
                        localization: localization
                    ),
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true,
                    in: bridgeContentWorld
                ))
        }

        private func applyFindRequestIfNeeded(in webView: WKWebView) {
            let generation = loadGeneration
            findCoordinator.applyIfNeeded(
                pageIsReady: pageIsReady && canApplyReadingNavigation && selectionCoordinator.isActive,
                in: webView,
                isCurrent: { [weak self, weak webView] in
                    guard let self, let webView else { return false }
                    return self.activeWebView === webView
                        && self.pageIsReady
                        && self.canApplyReadingNavigation
                        && self.loadGeneration == generation
                        && self.selectionCoordinator.isActive
                }
            )
        }

        private func applyLinkPreviewsIfNeeded(in webView: WKWebView) {
            guard pageIsReady,
                desiredLinkPreviewRevision != appliedLinkPreviewRevision,
                activeWebView === webView,
                let signature = activeLoadSignature,
                linkPreviewUpdateTask == nil
            else { return }
            let generation = loadGeneration
            linkPreviewUpdateTask = Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                defer {
                    if self.isCurrentLoad(generation: generation, signature: signature, in: webView) {
                        self.linkPreviewUpdateTask = nil
                    }
                }
                guard !Task.isCancelled,
                    self.isCurrentLoad(generation: generation, signature: signature, in: webView)
                else { return }
                // Navigation completion precedes asynchronous reader setup.
                // One load-owned task waits for the API, then converges on the
                // latest catalog instead of cancelling/restarting pending work.
                let ready = try? await webView.callAsyncJavaScript(
                    """
                    if (window.scholiumReadReady) await window.scholiumReadReady;
                    return typeof window.scholiumSetLinkPreviews === 'function';
                    """,
                    arguments: [:],
                    in: nil,
                    contentWorld: self.bridgeContentWorld
                )
                guard ready as? Bool == true else { return }
                while !Task.isCancelled,
                    self.isCurrentLoad(generation: generation, signature: signature, in: webView),
                    self.desiredLinkPreviewRevision != self.appliedLinkPreviewRevision
                {
                    let revision = self.desiredLinkPreviewRevision
                    let previews = Self.linkPreviewArguments(self.desiredLinkPreviews)
                    let result = try? await webView.callAsyncJavaScript(
                        "return window.scholiumSetLinkPreviews?.(previews) === true",
                        arguments: ["previews": previews],
                        in: nil,
                        contentWorld: self.bridgeContentWorld
                    )
                    guard !Task.isCancelled,
                        result as? Bool == true,
                        self.isCurrentLoad(generation: generation, signature: signature, in: webView)
                    else { return }
                    self.appliedLinkPreviewRevision = revision
                }
            }
        }

        private func applyPresentationStylesIfNeeded(
            in webView: WKWebView,
            generation: UInt64,
            signature: String
        ) async -> Bool {
            guard pageIsReady,
                activeWebView === webView,
                loadGeneration == generation,
                activeLoadSignature == signature,
                loadedSignature == signature
            else { return false }
            let presentationCSS = desiredPresentationCSS
            let userCSS = desiredUserCSS
            guard presentationCSS != appliedPresentationCSS || userCSS != appliedUserCSS else {
                return true
            }
            let result: Any?
            do {
                result = try await webView.callAsyncJavaScript(
                    """
                    return await window.scholiumSetPresentationCSS?.(presentationCSS, userCSS) === true;
                    """,
                    arguments: [
                        "presentationCSS": presentationCSS,
                        "userCSS": userCSS,
                    ],
                    in: nil,
                    contentWorld: self.bridgeContentWorld
                )
            } catch {
                #if DEBUG
                    if !Task.isCancelled,
                        isCurrentLoad(generation: generation, signature: signature, in: webView),
                        desiredPresentationCSS == presentationCSS, desiredUserCSS == userCSS
                    {
                        PerformanceProbe.shared.recordQAReaderFailure(
                            phase: .presentationUpdate, generation: generation, error: error)
                    }
                #endif
                result = nil
            }
            guard !Task.isCancelled,
                result as? Bool == true,
                activeWebView === webView,
                loadGeneration == generation,
                activeLoadSignature == signature,
                loadedSignature == signature
            else { return false }
            // The bridge serializes its own updates. If SwiftUI published a
            // newer style while this call was in flight, let finalization or
            // the newer scheduled task apply that value instead of treating
            // the older, already-valid update as a load failure.
            guard desiredPresentationCSS == presentationCSS,
                desiredUserCSS == userCSS
            else { return true }
            appliedPresentationCSS = presentationCSS
            appliedUserCSS = userCSS
            return true
        }

        private func schedulePresentationStyleUpdate(in webView: WKWebView) {
            guard pageIsReady,
                let signature = activeLoadSignature,
                finalizedSignature == signature
            else { return }
            let generation = loadGeneration
            let revision = presentationStyleRevision
            presentationStyleTask?.cancel()
            presentationStyleTask = Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                let applied = await self.applyPresentationStylesIfNeeded(
                    in: webView,
                    generation: generation,
                    signature: signature
                )
                guard applied,
                    !Task.isCancelled,
                    self.presentationStyleRevision == revision,
                    self.activeWebView === webView,
                    self.loadedSignature == signature,
                    self.finalizedSignature == signature
                else { return }
                self.presentationStyleTask = nil
                if !self.renderingReadinessIsAcknowledged {
                    self.renderingReadinessIsAcknowledged = true
                    self.onRenderingReady?()
                }
            }
        }

        private func applySelectionCommandsIfNeeded(in webView: WKWebView) {
            guard let signature = activeLoadSignature else { return }
            let generation = loadGeneration
            selectionCoordinator.applyIfNeeded(
                pageIsReady: pageIsReady && canApplyReadingNavigation,
                in: webView,
                isCurrent: { [weak self, weak webView] in
                    guard let self, let webView else { return false }
                    return self.canApplyReadingNavigation
                        && self.isCurrentLoad(
                            generation: generation,
                            signature: signature,
                            in: webView
                        )
                }
            )
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            let extensionMessageIsCurrent: Bool
            if pageExtension == nil {
                extensionMessageIsCurrent = true
            } else {
                guard let messageWebView = message.webView else { return }
                extensionMessageIsCurrent = activeWebView === messageWebView
            }
            guard message.name == Self.messageHandlerName,
                let payload = message.body as? [String: Any]
            else { return }
            receive(payload, in: message.webView, extensionMessageIsCurrent: extensionMessageIsCurrent)
        }

        func receiveEmbedded(_ payload: [String: Any], in webView: WKWebView) {
            guard isEmbeddedProjection, activeWebView === webView else { return }
            receive(payload, in: webView, extensionMessageIsCurrent: true)
        }

        private func receive(_ payload: [String: Any], in webView: WKWebView?, extensionMessageIsCurrent: Bool) {
            guard
                payload["version"] as? Int == SafeMarkdownReadWebView.configurationVersion,
                payload["documentID"] as? String == documentID,
                (payload["loadGeneration"] as? NSNumber)?.uint64Value == loadGeneration,
                let type = payload["type"] as? String,
                extensionMessageIsCurrent,
                payload["fingerprint"] as? String == fingerprint
                    || pageExtension?.acceptsMessageWithoutCurrentFingerprint(type: type) == true
            else { return }

            if pageExtension?.handleMessage(type: type, payload: payload, webView: webView) == true {
                return
            }

            switch type {
            case "ready":
                guard isEmbeddedProjection, let webView else { return }
                pageIsReady = true
                finalizedSignature = activeLoadSignature
                renderingReadinessIsAcknowledged = true
                webView.setAccessibilityLabel(ScholiumL10n.string("Rendered Markdown"))
                webView.setAccessibilityIdentifier("scholium.renderedDocument.\(documentID)")
                onRenderingReady?()
                applySelectionCommandsIfNeeded(in: webView)
                applyFindRequestIfNeeded(in: webView)
                schedulePostLoadPositioningIfNeeded(in: webView)

            case "floatingSurface":
                guard surfaceVisibility.isActive,
                    let event = DocumentFloatingEvent.decode(payload["event"]),
                    event.kind != .suggestions, let webView = webView,
                    !event.allowsAgentInquiry || onAskAgent != nil
                else { return }
                let expectedGeneration = loadGeneration
                floatingSurfaces.onPreviewFailure = { [weak self] failure in
                    guard let self, self.loadGeneration == expectedGeneration, self.surfaceVisibility.isActive else { return }
                    self.floatingPreviewFailure?(failure)
                }
                floatingSurfaces.present(event, in: webView, inquire: onAskAgent) {
                    [weak self, weak webView] id, action, index in
                    guard let self, let webView, self.loadGeneration == expectedGeneration else {
                        return false
                    }
                    let accepted = try? await webView.callAsyncJavaScript(
                        "return window.scholiumNativeFloatingEvent?.(id, action, index)",
                        arguments: ["id": id, "action": action.rawValue, "index": index],
                        in: nil, contentWorld: self.bridgeContentWorld
                    )
                    return accepted as? Bool == true && self.loadGeneration == expectedGeneration
                }
            case "requestMathRuntime":
                guard isEmbeddedProjection, let webView, activeWebView === webView else { return }
                runtimeCoordinator.requestMath(in: webView) { [weak self, weak webView] in
                    guard let self, let webView else { return false }
                    return self.activeWebView === webView && self.isEmbeddedProjection
                }
            case "requestMermaidRuntime":
                guard let webView = webView,
                    activeWebView === webView
                else { return }
                requestMermaidRuntime(in: webView)
            case "internalLink":
                guard surfaceVisibility.isActive,
                    let target = payload["target"] as? String,
                    !target.isEmpty,
                    target.utf8.count <= 8_192
                else { return }
                onLinkClick(target)

            case "imagePreview":
                guard surfaceVisibility.isActive,
                    let webView = webView, activeWebView === webView,
                    payload["fingerprint"] as? String == fingerprint,
                    let target = imagePreviewTarget(payload)
                else { return }
                onImagePreview?(target)

            case "imageContextMenu":
                guard surfaceVisibility.isActive,
                    payload["payloadFingerprint"] as? String == fingerprint,
                    let webView = webView
                else { return }
                presentImageContextMenu(payload, in: webView)

            case "passageContextMenu":
                guard surfaceVisibility.isActive else { return }
                if let webView = webView { presentPassageMenu(payload, in: webView) }
            case "selectionChanged":
                guard surfaceVisibility.isActive else { return }
                guard payload["text"] != nil else {
                    onSelectionChange?(nil)
                    return
                }
                onSelectionChange?(reviewSelection(from: payload))
            case "scrollChanged":
                receiveScrollPosition(
                    fractionValue: payload["fraction"],
                    anchorValue: payload["anchor"]
                )
            default:
                return
            }
        }

        private func imagePreviewTarget(_ payload: [String: Any]) -> String? {
            guard onImagePreview != nil,
                let target = payload["target"] as? String,
                !target.isEmpty, target.utf8.count <= 8_192
            else { return nil }
            return target
        }

        private func presentImageContextMenu(_ payload: [String: Any], in webView: WKWebView) {
            guard activeWebView === webView, let target = imagePreviewTarget(payload),
                let x = payload["clientX"] as? Double, let y = payload["clientY"] as? Double,
                x.isFinite, y.isFinite
            else { return }
            let generation = loadGeneration
            let capturedFingerprint = fingerprint
            let menu = NSMenu()
            let item = PassageMenuItem(title: ScholiumL10n.string("View Original Image"), enabled: true) {
                [weak self, weak webView] in
                guard let self, let webView, self.activeWebView === webView,
                    self.surfaceVisibility.isActive,
                    self.loadGeneration == generation, self.fingerprint == capturedFingerprint
                else { return }
                self.onImagePreview?(target)
            }
            item.identifier = NSUserInterfaceItemIdentifier("scholium.image.viewOriginal")
            menu.addItem(item)
            menu.autoenablesItems = false
            let point = NSPoint(
                x: min(max(0, x), webView.bounds.width),
                y: webView.isFlipped ? y : webView.bounds.height - y)
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView, self.activeWebView === webView, webView.window != nil,
                    self.surfaceVisibility.isActive,
                    self.loadGeneration == generation, self.fingerprint == capturedFingerprint
                else { return }
                menu.popUp(positioning: nil, at: point, in: webView)
            }
        }

        private func presentPassageMenu(_ payload: [String: Any], in webView: WKWebView) {
            guard selectionCoordinator.isActive, onPassageAction != nil,
                let x = payload["clientX"] as? Double, let y = payload["clientY"] as? Double,
                x.isFinite, y.isFinite, let lower = payload["paragraphLower"] as? Int,
                let upper = payload["paragraphUpper"] as? Int, upper > lower,
                let span = try? ParagraphAnchorPlanner.paragraph(
                    in: NoteDocument(relativePath: documentID, rawContent: selectionSource), atUTF16: lower),
                span.utf16LowerBound == lower, upper <= span.utf16UpperBound
            else { return }
            let snapshot: MarkdownSourceSelectionSnapshot?
            if let selected = payload["selection"] as? [String: Any] {
                snapshot = reviewSelection(from: selected).flatMap {
                    MarkdownReviewSourceSelection.passage($0, source: selectionSource, paragraphSpan: span)
                }
            } else {
                snapshot = DocumentPassageSnapshot.capture(source: selectionSource, range: span.nsRange)
            }
            let menu = NSMenu()
            let copy = NSMenuItem(title: ScholiumL10n.string("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "")
            menu.addItem(copy)
            menu.addItem(.separator())
            let generation = loadGeneration
            for action in DocumentPassageAction.allCases {
                let item = PassageMenuItem(title: action.title, enabled: snapshot != nil) { [weak self, weak webView] in
                    guard let self, let webView, self.activeWebView === webView,
                        self.loadGeneration == generation, self.selectionCoordinator.isActive, let snapshot,
                        snapshot.source.utf8.elementsEqual(self.selectionSource.utf8)
                    else { return }
                    self.onPassageAction?(action, snapshot)
                }
                item.identifier = NSUserInterfaceItemIdentifier("scholium.passage.\(action.rawValue)")
                menu.addItem(item)
            }
            menu.autoenablesItems = false
            let point = NSPoint(
                x: min(max(0, x), webView.bounds.width),
                y: webView.isFlipped ? y : webView.bounds.height - y)
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView, self.loadGeneration == generation, webView.window != nil else { return }
                menu.popUp(positioning: nil, at: point, in: webView)
            }
        }

        private func requestMermaidRuntime(in webView: WKWebView) {
            runtimeCoordinator.requestMermaid(
                in: webView,
                isCurrent: { [weak self, weak webView] in
                    guard let self, let webView else { return false }
                    return self.activeWebView === webView
                }
            )
        }

        private func reviewSelection(
            from payload: [String: Any]
        ) -> MarkdownReviewSelection? {
            guard let selected = payload["text"] as? String,
                !selected.isEmpty,
                selected.utf16.count <= Self.maximumSelectionLength
            else { return nil }
            let contextBefore = String((payload["contextBefore"] as? String ?? "").suffix(80))
            let contextAfter = String((payload["contextAfter"] as? String ?? "").prefix(80))
            var exact: Range<Int>?
            if let lower = payload["blockLower"] as? Int, let upper = payload["blockUpper"] as? Int,
                let text = payload["blockText"] as? String,
                let start = payload["selectionLower"] as? Int, let end = payload["selectionUpper"] as? Int
            {
                exact = MarkdownReviewSourceSelection.exactReviewRange(
                    blockLower: lower, blockUpper: upper,
                    blockText: text, selectionLower: start, selectionUpper: end, excerpt: selected,
                    source: selectionSource)
            }
            return MarkdownReviewSelection(
                startLine: max(1, payload["startLine"] as? Int ?? 1),
                endLine: max(1, payload["endLine"] as? Int ?? 1),
                excerpt: selected,
                utf16LowerBound: exact?.lowerBound,
                utf16UpperBound: exact?.upperBound,
                contextBefore: contextBefore,
                contextAfter: contextAfter
            )
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            pageExtension?.didFinishNavigation(
                navigation,
                isCurrent: { [weak self, weak webView] in
                    guard let self, let webView else { return false }
                    return self.activeWebView === webView
                        && self.activeNavigation === navigation
                }
            )
            guard let activeNavigation,
                activeNavigation === navigation,
                let expectedSignature = activeLoadSignature,
                loadedSignature == expectedSignature
            else { return }
            let expectedLoadGeneration = loadGeneration
            PerformanceProbe.shared.markReadNavigationFinished(
                documentID: documentID
            )
            pageIsReady = true
            appliedLinkPreviewRevision = loadingLinkPreviewRevision
            applyLinkPreviewsIfNeeded(in: webView)
            applySelectionCommandsIfNeeded(in: webView)
            applyFindRequestIfNeeded(in: webView)
            let restoreClaim = scrollRestoration.claimIfReady(
                pageIsReady: pageIsReady,
                fingerprint: fingerprint
            )
            let expectedDocumentID = documentID
            let expectedFingerprint = fingerprint
            loadFinalizationTask?.cancel()
            loadFinalizationTask = Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                var claimWasFinished = false
                defer {
                    if let restoreClaim, !claimWasFinished {
                        self.scrollRestoration.finish(restoreClaim, consumed: false)
                    }
                }
                do {
                    var reachedSourceLocationID: UUID?
                    guard
                        self.isCurrentLoad(
                            navigation: navigation,
                            generation: expectedLoadGeneration,
                            signature: expectedSignature,
                            in: webView
                        )
                    else { return }
                    var restoreSucceeded = false
                    if restoreClaim != nil {
                        await self.waitForTestingScrollRestoreDelayIfNeeded()
                    }
                    let result = try await webView.callAsyncJavaScript(
                        """
                        if (window.scholiumReadReady) await window.scholiumReadReady;
                        if (window.scholiumMermaidReady) await window.scholiumMermaidReady;
                        if (document.fonts?.ready) await document.fonts.ready;
                        return true;
                        """,
                        arguments: [:],
                        in: nil,
                        contentWorld: self.bridgeContentWorld
                    )
                    guard result as? Bool == true,
                        self.isCurrentLoad(
                            navigation: navigation,
                            generation: expectedLoadGeneration,
                            signature: expectedSignature,
                            in: webView
                        ),
                        self.documentID == expectedDocumentID,
                        self.fingerprint == expectedFingerprint
                    else { return }
                    guard
                        await self.applyPresentationStylesIfNeeded(
                            in: webView,
                            generation: expectedLoadGeneration,
                            signature: expectedSignature
                        )
                    else {
                        guard !Task.isCancelled else { return }
                        throw CocoaError(.coderReadCorrupt)
                    }
                    guard
                        self.isCurrentLoad(
                            navigation: navigation,
                            generation: expectedLoadGeneration,
                            signature: expectedSignature,
                            in: webView
                        )
                    else { return }
                    let policy = ScholiumLifecyclePolicy()
                    let duration = policy.bridgeRequest.components
                    let milliseconds =
                        Double(duration.seconds) * 1_000
                        + Double(duration.attoseconds) / 1_000_000_000_000_000
                    let expiresAt = Int64((Date().timeIntervalSince1970 * 1_000 + milliseconds).rounded(.down))
                    try await withScholiumLifecycleDeadline(phase: .bridgeRequest, timeout: policy.bridgeRequest) {
                        while true {
                            try Task.checkCancellation()
                            let previewRevision = self.desiredLinkPreviewRevision
                            await self.linkPreviewUpdateTask?.value
                            guard
                                self.isCurrentLoad(
                                    navigation: navigation, generation: expectedLoadGeneration,
                                    signature: expectedSignature, in: webView)
                            else { throw CancellationError() }
                            if previewRevision != self.desiredLinkPreviewRevision { continue }
                            guard self.appliedLinkPreviewRevision == previewRevision,
                                await self.applyPresentationStylesIfNeeded(
                                    in: webView, generation: expectedLoadGeneration,
                                    signature: expectedSignature)
                            else { throw CocoaError(.coderReadCorrupt) }
                            let sourceLocationID = self.sourceLocationRequest?.id
                            if let restoreClaim {
                                restoreSucceeded = await self.restoreScrollPosition(
                                    restoreClaim, generation: expectedLoadGeneration,
                                    signature: expectedSignature, in: webView)
                            }
                            let reachedLocation = await self.scrollToSourceLineIfNeeded(
                                generation: expectedLoadGeneration,
                                signature: expectedSignature, in: webView,
                                repositioningForPreparation: true)
                            reachedSourceLocationID = reachedLocation ? sourceLocationID : nil
                            let settled = try await webView.callAsyncJavaScript(
                                "return await window.scholiumReadPreparation.settle(documentID, fingerprint, loadGeneration, expiresAt);",
                                arguments: [
                                    "documentID": expectedDocumentID,
                                    "fingerprint": expectedFingerprint,
                                    "loadGeneration": expectedLoadGeneration,
                                    "expiresAt": expiresAt,
                                ],
                                in: nil,
                                contentWorld: self.bridgeContentWorld
                            )
                            guard let geometry = settled as? [String: Any],
                                geometry["settled"] as? Bool == true,
                                self.isCurrentLoad(
                                    navigation: navigation, generation: expectedLoadGeneration,
                                    signature: expectedSignature, in: webView)
                            else { throw CancellationError() }
                            if previewRevision != self.desiredLinkPreviewRevision
                                || self.appliedPresentationCSS != self.desiredPresentationCSS
                                || self.appliedUserCSS != self.desiredUserCSS
                                || self.sourceLocationRequest?.id != sourceLocationID
                                || geometry["geometryChanged"] as? Bool == true
                            {
                                continue
                            }
                            break
                        }
                    }
                    webView.setAccessibilityIdentifier(
                        "scholium.renderedDocument.\(expectedDocumentID)"
                    )
                    await self.reportDiagramSize(in: webView, signature: expectedSignature)
                    guard
                        self.isCurrentLoad(
                            navigation: navigation, generation: expectedLoadGeneration,
                            signature: expectedSignature, in: webView)
                    else { return }
                    #if DEBUG
                        if self.testingForcesFinalizationFailure {
                            throw TestingReadFinalizationError.forced
                        }
                    #endif
                    if let restoreClaim {
                        self.scrollRestoration.finish(restoreClaim, consumed: restoreSucceeded)
                        claimWasFinished = true
                    }
                    self.finalizedSignature = expectedSignature
                    if let reachedSourceLocationID,
                        self.sourceLocationRequest?.id == reachedSourceLocationID
                    {
                        self.onSourceLocationReached?(reachedSourceLocationID)
                    }
                    self.pageExtension?.didFinalizePage(fingerprint: expectedFingerprint)
                    self.renderingReadinessIsAcknowledged = true
                    self.schedulePresentationStyleUpdate(in: webView)
                    self.onRenderingReady?()
                } catch {
                    self.failCurrentLoadFinalization(
                        navigation: navigation,
                        generation: expectedLoadGeneration,
                        signature: expectedSignature,
                        in: webView,
                        error: error
                    )
                }
            }
        }

        #if DEBUG
            private enum TestingReadFinalizationError: LocalizedError {
                case forced

                var errorDescription: String? {
                    "The Read finalization failure was requested by the test harness."
                }
            }
        #endif

        private func failCurrentLoadFinalization(
            navigation: WKNavigation,
            generation: UInt64,
            signature: String,
            in webView: WKWebView,
            error: any Error
        ) {
            guard
                isCurrentLoad(
                    navigation: navigation,
                    generation: generation,
                    signature: signature,
                    in: webView
                )
            else { return }
            #if DEBUG
                if !Task.isCancelled {
                    PerformanceProbe.shared.recordQAReaderFailure(
                        phase: .finalization, generation: generation, error: error)
                }
            #endif
            sourceLineNavigationTask?.cancel()
            sourceLineNavigationTask = nil
            scrollRestoration.cancelClaim()
            loadFinalizationTask = nil
            pageIsReady = false
            // Keep the failed signature installed. Restoration reports can
            // update the outer SwiftUI state while finalization is failing;
            // clearing this identity would let that update re-enter the same
            // failed load before the owner has chosen an explicit retry.
            finalizedSignature = nil
            renderingReadinessIsAcknowledged = false
            loadGeneration &+= 1
            activeLoadSignature = nil
            activeNavigation = nil
            webView.setAccessibilityIdentifier("scholium.renderedDocument.failed")
            onRenderingFailure?(error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            #if DEBUG
                if activeWebView === webView {
                    PerformanceProbe.shared.recordQAReaderFailure(phase: .processTerminated, generation: loadGeneration)
                }
            #endif
            pageIsReady = false
            loadedSignature = nil
            finalizedSignature = nil
            renderingReadinessIsAcknowledged = false
            cancelPendingPageWork()
            webView.setAccessibilityIdentifier("scholium.renderedDocument.failed")
            onRenderingFailure?(
                WebKitInterfaceLocalization.current()
                    .string("The Review renderer stopped unexpectedly.")
            )
        }

        /// Read-only SVG layout projection, never a source or viewport measurement.
        private func reportDiagramSize(in webView: WKWebView, signature: String) async {
            guard onRenderedDiagramSize != nil else { return }
            let result = try? await webView.evaluateJavaScript(
                """
                (() => { const svg = document.querySelector('.scholium-mermaid-output')?.shadowRoot?.querySelector('svg');
                  const box = svg?.viewBox?.baseVal;
                  return box ? [box.width, box.height] : null; })()
                """, in: nil, contentWorld: self.bridgeContentWorld)
            guard activeWebView === webView, loadedSignature == signature,
                let values = result as? [Double], values.count == 2,
                values.allSatisfy({ $0.isFinite && $0 > 0 && $0 < 1_000_000 })
            else { return }
            onRenderedDiagramSize?(CGSize(width: values[0], height: values[1]))
        }

        /// Reconnects a finalized retained page to reconstructed SwiftUI
        /// session state. Yielding avoids publishing ObservableObject state
        /// during `updateNSView`; the acknowledgement prevents an update loop.
        private func reannounceFinalizedRenderingIfNeeded(
            signature: String,
            in webView: WKWebView
        ) {
            guard finalizedSignature == signature,
                !renderingReadinessIsAcknowledged
            else { return }
            Task { @MainActor [weak self, weak webView] in
                await Task.yield()
                guard let self, let webView,
                    self.activeWebView === webView,
                    self.loadedSignature == signature,
                    self.finalizedSignature == signature,
                    !self.renderingReadinessIsAcknowledged
                else { return }
                self.renderingReadinessIsAcknowledged = true
                self.onRenderingReady?()
            }
        }

        private func restoreScrollPosition(
            _ claim: ScrollRestoreClaim,
            generation: UInt64,
            signature: String,
            in webView: WKWebView
        ) async -> Bool {
            let request = claim.request
            guard !isEmbeddedProjection, request.fingerprint == fingerprint,
                scrollRestoration.owns(claim),
                isCurrentLoad(
                    generation: generation,
                    signature: signature,
                    in: webView
                )
            else { return false }
            let fraction = request.position.fraction
            let anchorValue: Any
            if let anchor = request.position.anchor,
                anchor.sourceFingerprint == fingerprint,
                anchor.isValid(forUTF16Length: sourceUTF16Length)
            {
                anchorValue =
                    [
                        "sourceUTF16Offset": anchor.sourceUTF16Offset,
                        "blockUTF16LowerBound": anchor.blockUTF16LowerBound,
                        "blockUTF16UpperBound": anchor.blockUTF16UpperBound,
                        "relativeBlockPosition": anchor.relativeBlockPosition,
                        "fallbackFraction": anchor.fallbackFraction,
                    ] as [String: Any]
            } else {
                anchorValue = NSNull()
            }
            let expectedDocumentID = documentID
            let expectedFingerprint = fingerprint
            let result = try? await webView.callAsyncJavaScript(
                """
                if (window.scholiumReadReady) await window.scholiumReadReady;
                if (window.scholiumMermaidReady) await window.scholiumMermaidReady;
                if (document.fonts?.ready) await document.fonts.ready;
                const extent = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
                window.scholiumReadScroll?.recordRestoreAttempt?.();
                const restored = Boolean(anchor && window.scholiumReadScroll?.restore(anchor));
                if (!restored) {
                  if (window.scholiumReadScroll?.setFraction) window.scholiumReadScroll.setFraction(fallbackFraction);
                  else window.scrollTo({top: fallbackFraction === 0 ? 0 : extent * fallbackFraction, behavior: 'auto'});
                }
                const fraction = window.scholiumReadScroll?.fraction?.() ?? (extent > 0 ? Math.max(0, Math.min(1, window.scrollY / extent)) : 0);
                return {
                  restored,
                  fraction,
                  anchor: window.scholiumReadScroll?.current(fraction) ?? null
                };
                """,
                arguments: [
                    "anchor": anchorValue,
                    "fallbackFraction": fraction,
                ],
                in: nil,
                contentWorld: self.bridgeContentWorld
            )
            guard activeWebView === webView,
                loadGeneration == generation,
                activeLoadSignature == signature,
                scrollRestoration.owns(claim),
                documentID == expectedDocumentID,
                fingerprint == expectedFingerprint,
                let payload = result as? [String: Any]
            else { return false }
            if payload["restored"] as? Bool == true,
                let requestedAnchor = request.position.anchor
            {
                receiveRestoredScrollPosition(
                    requestedAnchor,
                    fractionValue: payload["fraction"]
                )
            } else {
                receiveScrollPosition(
                    fractionValue: payload["fraction"],
                    anchorValue: payload["anchor"]
                )
            }
            return true
        }

        private func schedulePostLoadPositioningIfNeeded(in webView: WKWebView) {
            let navigation = activeNavigation
            guard pageIsReady, canApplyReadingNavigation, isEmbeddedProjection || navigation != nil,
                let signature = activeLoadSignature
            else { return }
            let hasPendingRequest =
                !isEmbeddedProjection
                && scrollRestoration.hasPendingRequest(
                    fingerprint: fingerprint
                )
            let hasPendingLocation =
                sourceLocationRequest.map { $0.id != lastReachedSourceLocationID } == true
            guard hasPendingRequest || hasPendingLocation else { return }

            let generation = loadGeneration
            let finalization = loadFinalizationTask
            sourceLineNavigationTask?.cancel()
            sourceLineNavigationTask = Task { @MainActor [weak self, weak webView] in
                await finalization?.value
                guard !Task.isCancelled, let self, let webView, self.canApplyReadingNavigation,
                    self.isCurrentLoad(
                        navigation: navigation,
                        generation: generation,
                        signature: signature,
                        in: webView
                    )
                else { return }
                let restoreClaim =
                    self.isEmbeddedProjection
                    ? nil
                    : self.scrollRestoration.claimIfReady(
                        pageIsReady: self.pageIsReady,
                        fingerprint: self.fingerprint
                    )
                var claimWasFinished = false
                defer {
                    if let restoreClaim, !claimWasFinished {
                        self.scrollRestoration.finish(restoreClaim, consumed: false)
                    }
                }
                var restoreSucceeded = false
                if let restoreClaim {
                    await self.waitForTestingScrollRestoreDelayIfNeeded()
                    restoreSucceeded = await self.restoreScrollPosition(
                        restoreClaim,
                        generation: generation,
                        signature: signature,
                        in: webView
                    )
                }
                await self.scrollToSourceLineIfNeeded(
                    generation: generation,
                    signature: signature,
                    in: webView
                )
                guard
                    self.isCurrentLoad(
                        navigation: navigation,
                        generation: generation,
                        signature: signature,
                        in: webView
                    )
                else { return }
                if let restoreClaim {
                    self.scrollRestoration.finish(
                        restoreClaim,
                        consumed: restoreSucceeded
                    )
                    claimWasFinished = true
                }
            }
        }

        private func waitForTestingScrollRestoreDelayIfNeeded() async {
            #if DEBUG
                let delay = max(0, testingScrollRestoreDelayMilliseconds)
                guard delay > 0 else { return }
                try? await Task.sleep(for: .milliseconds(delay))
            #endif
        }

        private func isCurrentLoad(
            navigation: WKNavigation? = nil,
            generation: UInt64,
            signature: String,
            in webView: WKWebView
        ) -> Bool {
            guard activeWebView === webView,
                pageIsReady,
                loadGeneration == generation,
                activeLoadSignature == signature,
                loadedSignature == signature
            else { return false }
            if let navigation {
                return activeNavigation === navigation
            }
            return isEmbeddedProjection || activeNavigation != nil
        }

        func cancelPendingPageWork(keepingLoadIdentity: Bool = false) {
            pageExtension?.cancel()
            floatingSurfaces.reset()
            loadFinalizationTask?.cancel()
            loadFinalizationTask = nil
            sourceLineNavigationTask?.cancel()
            sourceLineNavigationTask = nil
            linkPreviewUpdateTask?.cancel()
            linkPreviewUpdateTask = nil
            presentationStyleTask?.cancel()
            presentationStyleTask = nil
            deferredLoadTask?.cancel()
            deferredLoadTask = nil
            selectionCoordinator.cancel()
            findCoordinator.cancel()
            runtimeCoordinator.cancel()
            scrollRestoration.cancelClaim()
            pageIsReady = false
            guard !keepingLoadIdentity else { return }
            loadGeneration &+= 1
            activeLoadSignature = nil
            activeNavigation = nil
        }

        private func receiveScrollPosition(
            fractionValue: Any?,
            anchorValue: Any?
        ) {
            guard surfaceVisibility.isActive,
                let fraction = (fractionValue as? NSNumber)?.doubleValue,
                fraction.isFinite,
                (0...1).contains(fraction)
            else { return }
            var observation = ObservedScrollPosition(fraction: fraction)
            defer {
                if isEmbeddedProjection, canApplyReadingNavigation {
                    onEmbeddedScrollPositionChange?(observation)
                }
            }
            scrollRestoration.observedPosition.updateFraction(fraction)
            onScrollFractionChange?(fraction)
            guard let raw = anchorValue as? [String: Any],
                let sourceOffset = (raw["sourceUTF16Offset"] as? NSNumber)?.intValue,
                let lowerBound = (raw["blockUTF16LowerBound"] as? NSNumber)?.intValue,
                let upperBound = (raw["blockUTF16UpperBound"] as? NSNumber)?.intValue,
                let relativePosition = (raw["relativeBlockPosition"] as? NSNumber)?.doubleValue
            else {
                return
            }
            let anchor = EditorScrollAnchor(
                sourceFingerprint: fingerprint,
                sourceUTF16Offset: sourceOffset,
                blockUTF16LowerBound: lowerBound,
                blockUTF16UpperBound: upperBound,
                relativeBlockPosition: relativePosition,
                fallbackFraction: fraction
            )
            if anchor.isValid(forUTF16Length: sourceUTF16Length) {
                observation.anchor = anchor
                scrollRestoration.observedPosition.anchor = anchor
                onScrollAnchorChange?(anchor)
            }
        }

        private func receiveRestoredScrollPosition(
            _ requestedAnchor: EditorScrollAnchor,
            fractionValue: Any?
        ) {
            guard let fraction = (fractionValue as? NSNumber)?.doubleValue,
                fraction.isFinite,
                (0...1).contains(fraction),
                requestedAnchor.sourceFingerprint == fingerprint,
                requestedAnchor.isValid(forUTF16Length: sourceUTF16Length)
            else { return }
            scrollRestoration.observedPosition.updateFraction(fraction)
            onScrollFractionChange?(fraction)
            let anchor = EditorScrollAnchor(
                sourceFingerprint: requestedAnchor.sourceFingerprint,
                sourceUTF16Offset: requestedAnchor.sourceUTF16Offset,
                blockUTF16LowerBound: requestedAnchor.blockUTF16LowerBound,
                blockUTF16UpperBound: requestedAnchor.blockUTF16UpperBound,
                relativeBlockPosition: requestedAnchor.relativeBlockPosition,
                fallbackFraction: fraction
            )
            scrollRestoration.observedPosition.anchor = anchor
            onScrollAnchorChange?(anchor)
        }

        @discardableResult
        private func scrollToSourceLineIfNeeded(
            generation: UInt64,
            signature: String,
            in webView: WKWebView,
            repositioningForPreparation: Bool = false
        ) async -> Bool {
            guard !Task.isCancelled, let request = sourceLocationRequest,
                canApplyReadingNavigation,
                repositioningForPreparation || request.id != lastReachedSourceLocationID
            else {
                return false
            }
            guard isCurrentLoad(generation: generation, signature: signature, in: webView) else { return false }
            if let expected = request.sourceFingerprint, expected != fingerprint {
                let firstReceipt = lastReachedSourceLocationID != request.id
                lastReachedSourceLocationID = request.id
                if firstReceipt { onSourceRevisionChanged?(request.id) }
                return false
            }
            if request.requiresExactSelection, let range = request.range {
                return await selectSourceRange(
                    range, requestID: request.id, generation: generation, signature: signature, in: webView)
            }
            guard let line = request.line,
                line > 0,
                isCurrentLoad(
                    generation: generation,
                    signature: signature,
                    in: webView
                )
            else { return false }
            let result = try? await webView.callAsyncJavaScript(
                """
                if (!await window.scholiumReadNavigation?.reveal(requested)) return false;
                const extent = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
                const fraction = window.scholiumReadScroll?.fraction?.() ?? (extent > 0 ? Math.max(0, Math.min(1, window.scrollY / extent)) : 0);
                return {
                  reached: true,
                  fraction,
                  anchor: window.scholiumReadScroll?.current(fraction) ?? null
                };
                """,
                arguments: ["requested": line],
                in: nil,
                contentWorld: self.bridgeContentWorld
            )
            guard !Task.isCancelled, canApplyReadingNavigation, let payload = result as? [String: Any],
                payload["reached"] as? Bool == true,
                sourceLocationRequest?.id == request.id,
                isCurrentLoad(
                    generation: generation,
                    signature: signature,
                    in: webView
                )
            else { return false }
            receiveScrollPosition(
                fractionValue: payload["fraction"],
                anchorValue: payload["anchor"]
            )
            let firstReceipt = lastReachedSourceLocationID != request.id
            lastReachedSourceLocationID = request.id
            if firstReceipt, finalizedSignature == signature { onSourceLocationReached?(request.id) }
            return true
        }

        @discardableResult
        private func selectSourceRange(
            _ range: SearchSourceRange, requestID: UUID, generation: UInt64,
            signature: String, in webView: WKWebView
        ) async -> Bool {
            func isCurrent() -> Bool {
                !Task.isCancelled && canApplyReadingNavigation && sourceLocationRequest?.id == requestID
                    && isCurrentLoad(generation: generation, signature: signature, in: webView)
            }
            guard isCurrent() else { return false }
            let lower = range.utf16LowerBound
            let upper = range.utf16UpperBound
            let candidate = try? await webView.callAsyncJavaScript(
                "return window.scholiumReadNavigation?.rangeCandidate(lower, upper) ?? null;",
                arguments: ["lower": lower, "upper": upper], in: nil,
                contentWorld: self.bridgeContentWorld)
            guard isCurrent() else { return false }
            var reached = false
            if lower >= 0, upper > lower, upper <= selectionSource.utf16.count,
                let selected = Range(NSRange(location: lower, length: upper - lower), in: selectionSource),
                let block = candidate as? [String: Any],
                let blockLower = block["blockLower"] as? Int, let blockUpper = block["blockUpper"] as? Int,
                let blockText = block["blockText"] as? String,
                MarkdownReviewSourceSelection.exactReviewRange(
                    blockLower: blockLower, blockUpper: blockUpper,
                    blockText: blockText, selectionLower: lower - blockLower,
                    selectionUpper: upper - blockLower,
                    excerpt: String(selectionSource[selected]), source: selectionSource) == lower..<upper
            {
                let result = try? await webView.callAsyncJavaScript(
                    "return window.scholiumReadNavigation?.revealRange(lower, upper, expected) === true;",
                    arguments: ["lower": lower, "upper": upper, "expected": block], in: nil,
                    contentWorld: self.bridgeContentWorld)
                reached = result as? Bool == true
            }
            guard isCurrent() else { return false }
            let firstReceipt = lastReachedSourceLocationID != requestID
            lastReachedSourceLocationID = requestID
            if reached {
                if finalizedSignature == signature {
                    webView.window?.makeFirstResponder(webView)
                    if firstReceipt { onSourceLocationReached?(requestID) }
                }
            } else {
                if firstReceipt { onSourceRangeUnavailable?(requestID) }
            }
            return reached
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: any Error
        ) {
            guard activeNavigation === navigation else { return }
            #if DEBUG
                if activeWebView === webView, activeNavigation != nil {
                    PerformanceProbe.shared.recordQAReaderFailure(phase: .navigation, generation: loadGeneration, error: error)
                }
            #endif
            cancelPendingPageWork()
            onRenderingFailure?(error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            guard activeNavigation === navigation else { return }
            #if DEBUG
                if activeWebView === webView, activeNavigation != nil {
                    PerformanceProbe.shared.recordQAReaderFailure(phase: .provisionalNavigation, generation: loadGeneration, error: error)
                }
            #endif
            cancelPendingPageWork()
            onRenderingFailure?(error.localizedDescription)
        }

        static func allowsExternalLink(_ url: URL) -> Bool {
            guard url.absoluteString.utf8.count <= 8_192,
                let scheme = url.scheme?.lowercased()
            else { return false }
            return ["http", "https", "mailto", "zotero"].contains(scheme)
        }

        /// The shared editor page remains navigation-closed. Only its active,
        /// committed Reader can hand the existing external-link action to native.
        @discardableResult
        func openEmbeddedExternalLink(_ url: URL, sourceFingerprint: String, in webView: WKWebView) -> Bool {
            guard isEmbeddedProjection, activeWebView === webView,
                surfaceVisibility.isActive, selectionCoordinator.isActive,
                pageIsReady, finalizedSignature == activeLoadSignature,
                fingerprint == sourceFingerprint, Self.allowsExternalLink(url)
            else { return false }
            onOpenExternalURL(url)
            return true
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.navigationType == .other, url.absoluteString == "about:blank" {
                decisionHandler(.allow)
                return
            }
            if navigationAction.navigationType == .linkActivated, Self.allowsExternalLink(url) {
                onOpenExternalURL(url)
            }
            decisionHandler(.cancel)
        }

        static func documentHTML(
            body: String,
            frontmatter: String? = nil,
            frontmatterHasAuthoredBodyBlankLine: Bool = false,
            documentTitle: String? = nil,
            includesMathRuntime: Bool? = nil,
            localization: WebKitInterfaceLocalization = .current()
        ) -> String {
            let includesMathRuntime =
                includesMathRuntime
                ?? requiresMathRuntime(body: body, linkPreviews: [])
            let mathCSS = includesMathRuntime ? ScholiumMathAssets.css : ""
            let titleMarkup =
                documentTitle.flatMap { title -> String? in
                    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return nil }
                    return """
                        <div class="scholium-note-title" role="heading" aria-level="1" dir="auto" data-scholium-protected="note-title">\(escapedHTMLText(title))</div>
                        """
                } ?? ""
            let frontmatterMarkup =
                frontmatter.map {
                    frontmatterMarkup(
                        for: $0,
                        hasAuthoredBodyBlankLine: frontmatterHasAuthoredBodyBlankLine,
                        localization: localization
                    )
                } ?? ""
            let bodyMarkup =
                if body.isEmpty {
                    """
                    <section class="scholium-document-empty-state" role="status" aria-label="\(escapedHTMLText(localization.string("Empty Note")))" data-scholium-protected="empty-document">
                      <p>\(escapedHTMLText(localization.string("This note has no body content.")))</p>
                    </section>
                    """
                } else {
                    body
                }
            return """
                <!doctype html>
                <html lang="\(localization.languageTag)">
                <head>
                  <meta charset="utf-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1">
                  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'none'; img-src data:; connect-src 'none'; font-src scholium-font: data:">
                  <style>\(ScholiumWebFonts.css)\n\(ScholiumTableStyles.css)\n\(ScholiumFootnoteStyles.css)\n\(ScholiumAttachmentStyles.css)\n\(mathCSS)\n\(ScholiumMermaidAssets.css)\n\(ScholiumPreviewStyles.css)\n\(ScholiumWebSymbolAssets.cssVariables)\n\(baseCSS)</style>
                  <style id="scholium-presentation-css"></style>
                  <style id="scholium-user-css"></style>
                </head>
                <body>
                  <main id="scholium-document" class="scholium-document">\(titleMarkup)\(frontmatterMarkup)\(bodyMarkup)</main>
                  <aside id="scholium-preview-popover" class="scholium-preview-popover" data-scholium-protected="preview-popover" role="note" aria-labelledby="scholium-preview-title" aria-live="polite" hidden>
                    <h2 id="scholium-preview-title" class="scholium-preview-title"></h2>
                    <p class="scholium-preview-metadata" hidden></p>
                    <div class="scholium-preview-body scholium-document"></div>
                  </aside>
                </body>
                </html>
                """
        }

        private static func frontmatterMarkup(
            for source: String,
            hasAuthoredBodyBlankLine: Bool,
            localization: WebKitInterfaceLocalization
        ) -> String {
            let renderedLines = FrontmatterPresentation.lines(in: source)
                .map(frontmatterLineMarkup)
                .joined()
            let label = escapedHTMLText(localization.string("YAML frontmatter"))
            let delimiter =
                "<div class=\"scholium-frontmatter-line scholium-frontmatter-delimiter-line\" aria-hidden=\"true\">---</div>"
            let wrapperClass =
                hasAuthoredBodyBlankLine
                ? "scholium-frontmatter-source scholium-frontmatter-followed-by-blank-line"
                : "scholium-frontmatter-source"
            return """
                <div class="\(wrapperClass)" role="group" aria-label="\(label)" data-scholium-protected="frontmatter">\(delimiter)\(renderedLines)\(delimiter)</div>
                """
        }

        private static func frontmatterLineMarkup(_ line: FrontmatterPresentation.Line) -> String {
            let content: String
            switch line.role {
            case .blank:
                content = ""
            case .comment:
                content = "<span class=\"cm-live-yaml-comment\">\(escapedHTMLText(line.text))</span>"
            case .mapping(let key, let value, let valueKind):
                content =
                    "<span class=\"cm-live-yaml-key\">\(escapedHTMLText(key))</span>:<span class=\"\(valueKind.cssClass)\">\(escapedHTMLText(value))</span>"
            case .value(let valueKind):
                content = "<span class=\"\(valueKind.cssClass)\">\(escapedHTMLText(line.text))</span>"
            }
            return
                "<div class=\"scholium-frontmatter-line\" data-scholium-yaml-rendered=\"true\" dir=\"auto\">\(content)</div>"
        }

        private static func escapedHTMLText(_ value: String) -> String {
            value
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
        }

        /// Mathematics is an immutable optional projection. Avoid parsing the
        /// large runtime and embedded font stylesheet for ordinary prose, but
        /// retain the exact existing path whenever the document or an initial
        /// bounded preview contains a rendered mathematics node.
        static func requiresMathRuntime(
            body: String,
            linkPreviews: [DocumentLinkPreview]
        ) -> Bool {
            func containsMath(_ html: String) -> Bool {
                html.contains("data-math-source=\"")
                    && html.contains("data-math-kind=\"")
            }
            return containsMath(body)
                || linkPreviews.contains { containsMath($0.htmlBody) }
        }

        /// Starts the generated, type-checked Read runtime with one bounded
        /// configuration value in the named content world. Research text never
        /// enters executable JavaScript.
        struct ReadBridgeConfiguration: Codable, Hashable, Sendable {
            let version: Int
            let documentID: String
            let fingerprint: String
            let loadGeneration: UInt64
            let selectionEnabled: Bool
            let imagePreviewsEnabled: Bool
            let replyProjection: Bool
            let testingEnabled: Bool
            let presentationCSS: String
            let userCSS: String
            let localization: WebKitInterfaceLocalization
            let linkPreviews: [ReadLinkPreview]
        }

        private static let readerScript = ScholiumDocumentWebResources.text(named: "reader.bundle", extension: "js")

        static func bridgeScript(
            documentID: String,
            fingerprint: String,
            loadGeneration: UInt64,
            selectionEnabled: Bool,
            imagePreviewsEnabled: Bool = false,
            replyProjection: Bool = false,
            linkPreviews: [DocumentLinkPreview],
            presentationCSS: String,
            userCSS: String,
            localization: WebKitInterfaceLocalization = .current()
        ) -> String {
            let configuration = bridgeConfiguration(
                documentID: documentID, fingerprint: fingerprint, loadGeneration: loadGeneration,
                selectionEnabled: selectionEnabled, imagePreviewsEnabled: imagePreviewsEnabled,
                replyProjection: replyProjection, linkPreviews: linkPreviews,
                presentationCSS: presentationCSS, userCSS: userCSS, localization: localization)
            let payload = base64JSON(configuration)
            return """
                const encodedConfiguration = "\(payload)";
                const configuration = JSON.parse(new TextDecoder().decode(
                  Uint8Array.from(atob(encodedConfiguration), character => character.charCodeAt(0))
                ));
                if (!window.scholiumRead || typeof window.scholiumRead.initialize !== 'function') {
                  throw new Error('The bundled Read runtime could not start.');
                }
                window.scholiumRead.initialize(configuration);
                """
        }

        private static func bridgeConfiguration(
            documentID: String, fingerprint: String, loadGeneration: UInt64,
            selectionEnabled: Bool, imagePreviewsEnabled: Bool, replyProjection: Bool,
            linkPreviews: [DocumentLinkPreview], presentationCSS: String, userCSS: String,
            localization: WebKitInterfaceLocalization
        ) -> ReadBridgeConfiguration {
            #if DEBUG
                let testingEnabled = true
            #else
                let testingEnabled = false
            #endif
            let previews = linkPreviews.prefix(
                DocumentPreviewCatalogBuilder.maximumLinkCount
            ).map {
                ReadLinkPreview(
                    utf16LowerBound: $0.sourceSpan.utf16LowerBound,
                    utf16UpperBound: $0.sourceSpan.utf16UpperBound,
                    title: String($0.title.prefix(240)),
                    isEmbedded: $0.syntax == .embed,
                    fragment: $0.fragment.map { String($0.prefix(240)) },
                    htmlBody: $0.syntax == .embed
                        ? $0.htmlBody
                        : String($0.htmlBody.prefix(24_000))
                )
            }
            return ReadBridgeConfiguration(
                version: SafeMarkdownReadWebView.configurationVersion,
                documentID: documentID,
                fingerprint: fingerprint,
                loadGeneration: loadGeneration,
                selectionEnabled: selectionEnabled,
                imagePreviewsEnabled: imagePreviewsEnabled,
                replyProjection: replyProjection,
                testingEnabled: testingEnabled,
                presentationCSS: presentationCSS,
                userCSS: userCSS,
                localization: localization,
                linkPreviews: previews
            )
        }

        struct ReadLinkPreview: Codable, Hashable, Sendable {
            let utf16LowerBound: Int
            let utf16UpperBound: Int
            let title: String
            let isEmbedded: Bool
            let fragment: String?
            let htmlBody: String
        }

        private static func linkPreviewArguments(
            _ previews: [DocumentLinkPreview]
        ) -> [[String: Any]] {
            previews.prefix(DocumentPreviewCatalogBuilder.maximumLinkCount).map { preview in
                [
                    "utf16LowerBound": preview.sourceSpan.utf16LowerBound,
                    "utf16UpperBound": preview.sourceSpan.utf16UpperBound,
                    "title": String(preview.title.prefix(240)),
                    "isEmbedded": preview.syntax == .embed,
                    "fragment": preview.fragment.map { String($0.prefix(240)) } ?? NSNull(),
                    "htmlBody": preview.syntax == .embed
                        ? preview.htmlBody
                        : String(preview.htmlBody.prefix(24_000)),
                ]
            }
        }

        private static func base64JSON<T: Encodable>(_ value: T) -> String {
            guard let data = try? JSONEncoder().encode(value) else { return "W10=" }
            return data.base64EncodedString()
        }

        static let baseCSS = """
            html, body { margin: 0; min-height: 100%; overflow-x: hidden; background: var(--scholium-color-document-background); color: var(--scholium-color-primary-text); }
            html.scholium-viewport-resize-suppresses-overlay-scrollbar { scrollbar-width: none; }
            body { font-family: var(--scholium-document-body-font-family); font-size: var(--scholium-document-prose-font-size); line-height: var(--scholium-rhythm-prose-line-height); }
            \(ReviewSelectionPresentation.css)
            .scholium-link-annotation-button > span { background: currentColor; -webkit-mask: var(--scholium-system-symbol-text-bubble) center / contain no-repeat; mask: var(--scholium-system-symbol-text-bubble) center / contain no-repeat; }
            img, video, svg { max-width: 100%; height: auto; }
            \(ScholiumCalloutStyles.css)
            .raw-html, .raw-html-inline { color: GrayText; }
            @media (prefers-contrast: more) {
            }
            \(ScholiumWebDesignTokens.documentPresentationCSS)
            """
    }
}
