import ScholiumContracts
import AppKit
import SwiftUI
import WebKit

struct SafeMarkdownReadWebView: NSViewRepresentable {
    /// App-owned bridge scripts and the native message handler live in a
    /// named content world. Research-authored CSS and Markdown never enter
    /// that world, and the page world exposes no native handler or script.
    static let bridgeContentWorldName = "ScholiumRead"
    static let bridgeContentWorld = WKContentWorld.world(name: bridgeContentWorldName)

    let documentID: String
    let fingerprint: String
    let source: String
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
    let onOpenExternalURL: (URL) -> Void
    /// A lightweight researcher Comment saved into the active Discussion.
    var onCommentSelection: ((PassageCommentSubmission) -> Void)? = nil
    var commentComposerRequestID: UUID? = nil
    var commentResolution: PassageCommentResolution? = nil
    var commentAnchors: [ReviewCommentAnchor] = []
    var commentAnchorRevision: String? = nil
    var onOpenCommentAnchor: ((ReviewCommentAnchor) -> Void)? = nil
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
    var findRequest: DocumentFindPresentationRequest? = nil
    var onFindResult: ((UInt64, Result<DocumentFindResult, any Error>) -> Void)? = nil
    var observedScrollPosition = ObservedScrollPosition()
    var scrollRestoreRequest: ScrollRestoreRequest? = nil
    var onScrollRestoreConsumed: ((UInt64, String) -> Void)? = nil
    var onScrollFractionChange: ((Double) -> Void)? = nil
    var onScrollAnchorChange: ((EditorScrollAnchor) -> Void)? = nil
    var targetSourceLine: Int? = nil
    var onSourceLineReached: (() -> Void)? = nil
    #if DEBUG
    var testingForcesFinalizationFailure = false
    var testingScrollRestoreDelayMilliseconds = 0
    #endif

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(
            documentID: documentID,
            fingerprint: fingerprint,
            onLinkClick: onLinkClick,
            onOpenExternalURL: onOpenExternalURL,
            onCommentSelection: onCommentSelection,
            commentComposerRequestID: commentComposerRequestID,
            commentResolution: commentResolution,
            commentAnchors: commentAnchors,
            commentAnchorRevision: commentAnchorRevision,
            onOpenCommentAnchor: onOpenCommentAnchor,
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
            targetSourceLine: targetSourceLine,
            onSourceLineReached: onSourceLineReached
        )
        #if DEBUG
        coordinator.testingForcesFinalizationFailure = testingForcesFinalizationFailure
        coordinator.testingScrollRestoreDelayMilliseconds = testingScrollRestoreDelayMilliseconds
        #endif
        return coordinator
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView: WKWebView
        let contentController: WKUserContentController
        if let prepared = ScholiumWebKitProcessPrewarmer.shared.takeReadWebView() {
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
            webView = WKWebView(frame: .zero, configuration: configuration)
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
        context.coordinator.loadIfNeeded(
            htmlBody,
            source: source,
            presentationCSS: presentationCSS,
            userCSS: userCSS,
            configurationRevision: configurationRevision,
            linkPreviews: linkPreviews,
            linkPreviewRevision: linkPreviewRevision,
            commentAnchors: commentAnchors,
            commentAnchorRevision: commentAnchorRevision,
            in: webView
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        #if DEBUG
        context.coordinator.testingForcesFinalizationFailure = testingForcesFinalizationFailure
        context.coordinator.testingScrollRestoreDelayMilliseconds = testingScrollRestoreDelayMilliseconds
        #endif
        context.coordinator.update(
            documentID: documentID,
            fingerprint: fingerprint,
            onLinkClick: onLinkClick,
            onOpenExternalURL: onOpenExternalURL,
            onCommentSelection: onCommentSelection,
            commentComposerRequestID: commentComposerRequestID,
            commentResolution: commentResolution,
            commentAnchors: commentAnchors,
            commentAnchorRevision: commentAnchorRevision,
            onOpenCommentAnchor: onOpenCommentAnchor,
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
            targetSourceLine: targetSourceLine,
            onSourceLineReached: onSourceLineReached,
            webView: webView
        )
        context.coordinator.loadIfNeeded(
            htmlBody,
            source: source,
            presentationCSS: presentationCSS,
            userCSS: userCSS,
            configurationRevision: configurationRevision,
            linkPreviews: linkPreviews,
            linkPreviewRevision: linkPreviewRevision,
            commentAnchors: commentAnchors,
            commentAnchorRevision: commentAnchorRevision,
            in: webView
        )
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        Task { @MainActor [weak webView] in
            guard let webView else { return }
            _ = try? await webView.evaluateJavaScript(
                "window.scholiumSetReviewSelectionSurfaceActive?.(false)",
                in: nil,
                contentWorld: SafeMarkdownReadWebView.bridgeContentWorld
            )
        }
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.messageHandlerName
        )
        webView.navigationDelegate = nil
        coordinator.activeWebView = nil
        coordinator.cancelPendingPageWork()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private typealias ScrollRestoreClaim = SafeMarkdownReadScrollRestoration.Claim

        static let messageHandlerName = "scholiumRead"
        private static let maximumSelectionLength = 2_000
        private static let vectorSymbolDataURIs: [String: String] = [
            "neutral": ScholiumWebSymbolAssets.dataURI(for: .link),
            "supports": ScholiumWebSymbolAssets.dataURI(for: .plus),
            "opposes": ScholiumWebSymbolAssets.dataURI(for: .minus),
            "incompatible": ScholiumWebSymbolAssets.dataURI(for: .xmark),
            "comment": ScholiumWebSymbolAssets.dataURI(for: .textBubble),
        ]

        private var documentID: String
        private var fingerprint: String
        private var onLinkClick: (String) -> Void
        private var onOpenExternalURL: (URL) -> Void
        private var onCommentSelection: ((PassageCommentSubmission) -> Void)?
        private var onOpenCommentAnchor: ((ReviewCommentAnchor) -> Void)?
        private var onSelectionChange: ((MarkdownReviewSelection?) -> Void)?
        private let selectionCoordinator: SafeMarkdownReadSelectionCoordinator
        private let findCoordinator = SafeMarkdownReadFindCoordinator()
        private let runtimeCoordinator = SafeMarkdownReadRuntimeCoordinator()
        private var renderingReadinessIsAcknowledged: Bool
        private var onRenderingFailure: ((String) -> Void)?
        private var onRenderingLoading: (() -> Void)?
        private var onRenderingReady: (() -> Void)?
        private var scrollRestoration: SafeMarkdownReadScrollRestoration
        private var hasLoadedPage = false
        private var loadGeneration: UInt64 = 0
        private var activeLoadSignature: String?
        private var activeNavigation: WKNavigation?
        private var loadFinalizationTask: Task<Void, Never>?
        private var sourceLineNavigationTask: Task<Void, Never>?
        private var linkPreviewUpdateTask: Task<Void, Never>?
        private var commentAnchorUpdateTask: Task<Void, Never>?
        private var desiredLinkPreviewRevision = ""
        private var appliedLinkPreviewRevision = ""
        private var loadingLinkPreviewRevision = ""
        private var desiredLinkPreviews: [DocumentLinkPreview] = []
        private var desiredCommentAnchorRevision = ""
        private var appliedCommentAnchorRevision = ""
        private var loadingCommentAnchorRevision = ""
        private var desiredCommentAnchors: [ReviewCommentAnchor] = []
        private var commentAnchorsByID: [String: ReviewCommentAnchor] = [:]
        private var onScrollFractionChange: ((Double) -> Void)?

        private var onScrollAnchorChange: ((EditorScrollAnchor) -> Void)?
        private var sourceUTF16Length = 0
        private var sourceUTF8Length = 0
        private var source = ""
        private var targetSourceLine: Int?
        private var onSourceLineReached: (() -> Void)?
        private var lastReachedSourceLine: Int?
        private var loadedSignature: String?
        private var finalizedSignature: String?
        private var pageIsReady = false
        weak var activeWebView: WKWebView?
        #if DEBUG
        var testingForcesFinalizationFailure = false
        var testingScrollRestoreDelayMilliseconds = 0
        #endif

        init(
            documentID: String,
            fingerprint: String,
            onLinkClick: @escaping (String) -> Void,
            onOpenExternalURL: @escaping (URL) -> Void,
            onCommentSelection: ((PassageCommentSubmission) -> Void)?,
            commentComposerRequestID: UUID?,
            commentResolution: PassageCommentResolution?,
            commentAnchors: [ReviewCommentAnchor],
            commentAnchorRevision: String?,
            onOpenCommentAnchor: ((ReviewCommentAnchor) -> Void)?,
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
            targetSourceLine: Int?,
            onSourceLineReached: (() -> Void)?
        ) {
            self.documentID = documentID
            self.fingerprint = fingerprint
            self.onLinkClick = onLinkClick
            self.onOpenExternalURL = onOpenExternalURL
            self.onCommentSelection = onCommentSelection
            self.onOpenCommentAnchor = onOpenCommentAnchor
            self.onSelectionChange = onSelectionChange
            desiredCommentAnchors = commentAnchors
            desiredCommentAnchorRevision = commentAnchorRevision
                ?? Self.commentAnchorRevision(for: commentAnchors)
            commentAnchorsByID = Self.commentAnchorsByID(commentAnchors)
            selectionCoordinator = SafeMarkdownReadSelectionCoordinator(
                composerRequestID: commentComposerRequestID,
                resolution: commentResolution,
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
            self.targetSourceLine = targetSourceLine
            self.onSourceLineReached = onSourceLineReached
        }

        func update(
            documentID: String,
            fingerprint: String,
            onLinkClick: @escaping (String) -> Void,
            onOpenExternalURL: @escaping (URL) -> Void,
            onCommentSelection: ((PassageCommentSubmission) -> Void)?,
            commentComposerRequestID: UUID?,
            commentResolution: PassageCommentResolution?,
            commentAnchors: [ReviewCommentAnchor],
            commentAnchorRevision: String?,
            onOpenCommentAnchor: ((ReviewCommentAnchor) -> Void)?,
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
            targetSourceLine: Int?,
            onSourceLineReached: (() -> Void)?,
            webView: WKWebView
        ) {
            let documentChanged = self.documentID != documentID || self.fingerprint != fingerprint
            if documentChanged {
                loadedSignature = nil
                finalizedSignature = nil
                appliedLinkPreviewRevision = ""
                loadingLinkPreviewRevision = ""
                appliedCommentAnchorRevision = ""
                loadingCommentAnchorRevision = ""
                lastReachedSourceLine = nil
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
            self.onOpenExternalURL = onOpenExternalURL
            self.onCommentSelection = onCommentSelection
            self.onOpenCommentAnchor = onOpenCommentAnchor
            self.onSelectionChange = onSelectionChange
            desiredCommentAnchors = commentAnchors
            desiredCommentAnchorRevision = commentAnchorRevision
                ?? Self.commentAnchorRevision(for: commentAnchors)
            commentAnchorsByID = Self.commentAnchorsByID(commentAnchors)
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
            self.targetSourceLine = targetSourceLine
            self.onSourceLineReached = onSourceLineReached
            selectionCoordinator.update(
                composerRequestID: commentComposerRequestID,
                resolution: commentResolution,
                isActive: selectionSurfaceIsActive
            )
            schedulePostLoadPositioningIfNeeded(in: webView)
            applySelectionCommandsIfNeeded(in: webView)
            applyCommentAnchorsIfNeeded(in: webView)
            applyFindRequestIfNeeded(in: webView)
        }

        func loadIfNeeded(
            _ body: String,
            source: String,
            presentationCSS: String,
            userCSS: String,
            configurationRevision: String?,
            linkPreviews: [DocumentLinkPreview],
            linkPreviewRevision: String?,
            commentAnchors: [ReviewCommentAnchor],
            commentAnchorRevision: String?,
            in webView: WKWebView
        ) {
            let interfaceLocalization = WebKitInterfaceLocalization.current()
            let capabilitySignature = "\(onCommentSelection != nil):\(onSelectionChange != nil)"
            let previewRevision = linkPreviewRevision ?? String(linkPreviews.hashValue)
            let anchorRevision = commentAnchorRevision
                ?? Self.commentAnchorRevision(for: commentAnchors)
            let signature = configurationRevision.map {
                "revision:\($0):\(capabilitySignature):\(interfaceLocalization.languageTag)"
            } ?? [
                fingerprint,
                String(body.utf8.count),
                String(presentationCSS.hashValue),
                String(userCSS.hashValue),
                String(linkPreviews.hashValue),
                capabilitySignature,
            ].joined(separator: ":")
            desiredLinkPreviews = linkPreviews
            desiredLinkPreviewRevision = previewRevision
            desiredCommentAnchors = commentAnchors
            desiredCommentAnchorRevision = anchorRevision
            commentAnchorsByID = Self.commentAnchorsByID(commentAnchors)
            guard loadedSignature != signature else {
                reannounceFinalizedRenderingIfNeeded(
                    signature: signature,
                    in: webView
                )
                applyLinkPreviewsIfNeeded(in: webView)
                applyCommentAnchorsIfNeeded(in: webView)
                applySelectionCommandsIfNeeded(in: webView)
                applyFindRequestIfNeeded(in: webView)
                return
            }
            self.source = source
            sourceUTF16Length = source.utf16.count
            sourceUTF8Length = source.utf8.count
            let publishesLoadingTransition = hasLoadedPage
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
            loadedSignature = signature
            finalizedSignature = nil
            renderingReadinessIsAcknowledged = false
            loadingLinkPreviewRevision = previewRevision
            loadingCommentAnchorRevision = anchorRevision
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
                commentAnchors: commentAnchors,
                includesMathRuntime: includesMathRuntime,
                loadGeneration: loadGeneration,
                localization: interfaceLocalization,
                in: webView
            )
            let html = Self.documentHTML(
                body: body,
                includesMathRuntime: includesMathRuntime,
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
                      loadGeneration == expectedLoadGeneration else { return }
                activeNavigation = navigation
                return
            }
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView,
                      self.activeWebView === webView,
                      self.loadedSignature == expectedSignature else { return }
                self.onRenderingLoading?()
                await Task.yield()
                guard self.activeWebView === webView,
                      self.loadedSignature == expectedSignature,
                      self.activeLoadSignature == expectedSignature,
                      self.loadGeneration == expectedLoadGeneration else { return }
                PerformanceProbe.shared.markReadNavigationStarted(
                    documentID: self.documentID
                )
                let navigation = webView.loadHTMLString(html, baseURL: nil)
                guard self.activeWebView === webView,
                      self.loadedSignature == expectedSignature,
                      self.activeLoadSignature == expectedSignature,
                      self.loadGeneration == expectedLoadGeneration else { return }
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
            commentAnchors: [ReviewCommentAnchor],
            includesMathRuntime: Bool,
            loadGeneration: UInt64,
            localization: WebKitInterfaceLocalization,
            in webView: WKWebView
        ) {
            let contentController = webView.configuration.userContentController
            contentController.removeAllUserScripts()
            if includesMathRuntime, !ScholiumMathAssets.runtimeJavaScript.isEmpty {
                contentController.addUserScript(WKUserScript(
                    source: ScholiumMathAssets.runtimeJavaScript,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true,
                    in: SafeMarkdownReadWebView.bridgeContentWorld
                ))
            }
            if let readerScript = Self.readerScript {
                contentController.addUserScript(WKUserScript(
                    source: readerScript,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true,
                    in: SafeMarkdownReadWebView.bridgeContentWorld
                ))
            }
            contentController.addUserScript(WKUserScript(
                source: Self.bridgeScript(
                    documentID: documentID,
                    fingerprint: fingerprint,
                    loadGeneration: loadGeneration,
                    commentEnabled: onCommentSelection != nil,
                    selectionEnabled: onSelectionChange != nil,
                    linkPreviews: linkPreviews,
                    commentAnchors: commentAnchors,
                    presentationCSS: presentationCSS,
                    userCSS: userCSS,
                    localization: localization
                ),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
                in: SafeMarkdownReadWebView.bridgeContentWorld
            ))
        }

        private func applyFindRequestIfNeeded(in webView: WKWebView) {
            let generation = loadGeneration
            findCoordinator.applyIfNeeded(
                pageIsReady: pageIsReady,
                in: webView,
                isCurrent: { [weak self, weak webView] in
                    guard let self, let webView else { return false }
                    return self.activeWebView === webView
                        && self.pageIsReady
                        && self.loadGeneration == generation
                }
            )
        }

        private func applyLinkPreviewsIfNeeded(in webView: WKWebView) {
            guard pageIsReady,
                  desiredLinkPreviewRevision != appliedLinkPreviewRevision,
                  activeWebView === webView else { return }
            let revision = desiredLinkPreviewRevision
            let previews = Self.linkPreviewArguments(desiredLinkPreviews)
            linkPreviewUpdateTask?.cancel()
            linkPreviewUpdateTask = Task { @MainActor [weak self, weak webView] in
                guard let self, let webView, self.activeWebView === webView else { return }
                let result = try? await webView.callAsyncJavaScript(
                    "return window.scholiumSetLinkPreviews?.(previews) === true",
                    arguments: ["previews": previews],
                    in: nil,
                    contentWorld: SafeMarkdownReadWebView.bridgeContentWorld
                )
                guard !Task.isCancelled,
                      result as? Bool == true,
                      self.activeWebView === webView,
                      self.desiredLinkPreviewRevision == revision else { return }
                self.appliedLinkPreviewRevision = revision
            }
        }

        private func applyCommentAnchorsIfNeeded(in webView: WKWebView) {
            guard pageIsReady,
                  desiredCommentAnchorRevision != appliedCommentAnchorRevision,
                  activeWebView === webView else { return }
            let revision = desiredCommentAnchorRevision
            let anchors = Self.commentAnchorArguments(desiredCommentAnchors)
            commentAnchorUpdateTask?.cancel()
            commentAnchorUpdateTask = Task { @MainActor [weak self, weak webView] in
                guard let self, let webView, self.activeWebView === webView else { return }
                let result = try? await webView.callAsyncJavaScript(
                    "return window.scholiumSetCommentAnchors?.(anchors) === true",
                    arguments: ["anchors": anchors],
                    in: nil,
                    contentWorld: SafeMarkdownReadWebView.bridgeContentWorld
                )
                guard !Task.isCancelled,
                      result as? Bool == true,
                      self.activeWebView === webView,
                      self.desiredCommentAnchorRevision == revision else { return }
                self.appliedCommentAnchorRevision = revision
            }
        }

        private func applySelectionCommandsIfNeeded(in webView: WKWebView) {
            guard let signature = activeLoadSignature else { return }
            let generation = loadGeneration
            selectionCoordinator.applyIfNeeded(
                pageIsReady: pageIsReady,
                in: webView,
                isCurrent: { [weak self, weak webView] in
                    guard let self, let webView else { return false }
                    return self.isCurrentLoad(
                        generation: generation,
                        signature: signature,
                        in: webView
                    )
                }
            )
        }

        private func resolveComment(
            _ resolution: PassageCommentResolution,
            in webView: WKWebView
        ) {
            selectionCoordinator.updateResolution(resolution)
            applySelectionCommandsIfNeeded(in: webView)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.messageHandlerName,
                  let payload = message.body as? [String: Any],
                  payload["version"] as? Int == 1,
                  payload["documentID"] as? String == documentID,
                  payload["fingerprint"] as? String == fingerprint,
                  (payload["loadGeneration"] as? NSNumber)?.uint64Value == loadGeneration,
                  let type = payload["type"] as? String else { return }

            switch type {
            case "requestMermaidRuntime":
                guard let webView = message.webView else { return }
                requestMermaidRuntime(in: webView)
            case "internalLink":
                guard let target = payload["target"] as? String,
                      !target.isEmpty,
                      target.utf8.count <= 8_192 else { return }
                onLinkClick(target)
            case "commentSubmitted":
                guard let requestID = payload["requestID"] as? String,
                      !requestID.isEmpty else { return }
                guard let comment = payload["comment"] as? String,
                      !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      comment.utf8.count <= 16_384,
                      let selection = reviewSelection(from: payload),
                      let lineRange = ResearchActionSelectionCapture.commentLineRange(
                          for: selection,
                          in: source,
                          relativePath: documentID
                      ) else {
                    if let activeWebView {
                        resolveComment(
                            PassageCommentResolution(
                                requestID: requestID,
                                succeeded: false
                            ),
                            in: activeWebView
                        )
                    }
                    return
                }
                onCommentSelection?(PassageCommentSubmission(
                    requestID: requestID,
                    documentID: documentID,
                    fingerprint: DocumentFingerprint(
                        sha256: fingerprint,
                        byteCount: sourceUTF8Length
                    ),
                    startLine: lineRange.lowerBound,
                    endLine: lineRange.upperBound,
                    commentedText: selection.excerpt,
                    text: comment
                ))
            case "commentAnchorActivated":
                guard let anchorID = payload["anchorID"] as? String,
                      anchorID.utf8.count <= 160,
                      let anchor = commentAnchorsByID[anchorID] else { return }
                onOpenCommentAnchor?(anchor)
            case "selectionChanged":
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
                  selected.utf16.count <= Self.maximumSelectionLength else { return nil }
            let contextBefore = String((payload["contextBefore"] as? String ?? "").suffix(80))
            let contextAfter = String((payload["contextAfter"] as? String ?? "").prefix(80))
            return MarkdownReviewSelection(
                startLine: max(1, payload["startLine"] as? Int ?? 1),
                endLine: max(1, payload["endLine"] as? Int ?? 1),
                excerpt: selected,
                contextBefore: contextBefore,
                contextAfter: contextAfter
            )
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            guard let activeNavigation,
                  activeNavigation === navigation,
                  let expectedSignature = activeLoadSignature,
                  loadedSignature == expectedSignature else { return }
            let expectedLoadGeneration = loadGeneration
            PerformanceProbe.shared.markReadNavigationFinished(
                documentID: documentID
            )
            pageIsReady = true
            appliedLinkPreviewRevision = loadingLinkPreviewRevision
            appliedCommentAnchorRevision = loadingCommentAnchorRevision
            applyLinkPreviewsIfNeeded(in: webView)
            applyCommentAnchorsIfNeeded(in: webView)
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
                    guard self.isCurrentLoad(
                        navigation: navigation,
                        generation: expectedLoadGeneration,
                        signature: expectedSignature,
                        in: webView
                    ) else { return }
                    var restoreSucceeded = false
                    if let restoreClaim {
                        await self.waitForTestingScrollRestoreDelayIfNeeded()
                        restoreSucceeded = await self.restoreScrollPosition(
                            restoreClaim,
                            generation: expectedLoadGeneration,
                            signature: expectedSignature,
                            in: webView
                        )
                    }
                    #if DEBUG
                    if self.testingForcesFinalizationFailure {
                        throw TestingReadFinalizationError.forced
                    }
                    #endif
                    let result = try await webView.callAsyncJavaScript(
                        """
                        if (window.scholiumReadReady) await window.scholiumReadReady;
                        if (window.scholiumMermaidReady) await window.scholiumMermaidReady;
                        if (document.fonts?.ready) await document.fonts.ready;
                        return true;
                        """,
                        arguments: [:],
                        in: nil,
                        contentWorld: SafeMarkdownReadWebView.bridgeContentWorld
                    )
                    guard result as? Bool == true,
                          self.isCurrentLoad(
                              navigation: navigation,
                              generation: expectedLoadGeneration,
                              signature: expectedSignature,
                              in: webView
                          ),
                          self.documentID == expectedDocumentID,
                          self.fingerprint == expectedFingerprint else { return }
                    await self.scrollToSourceLineIfNeeded(
                        generation: expectedLoadGeneration,
                        signature: expectedSignature,
                        in: webView
                    )
                    guard self.isCurrentLoad(
                        navigation: navigation,
                        generation: expectedLoadGeneration,
                        signature: expectedSignature,
                        in: webView
                    ) else { return }
                    if let restoreClaim {
                        self.scrollRestoration.finish(
                            restoreClaim,
                            consumed: restoreSucceeded
                        )
                        claimWasFinished = true
                    }
                    webView.setAccessibilityIdentifier(
                        "scholium.renderedDocument.\(expectedDocumentID)"
                    )
                    self.finalizedSignature = expectedSignature
                    self.renderingReadinessIsAcknowledged = true
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
            guard isCurrentLoad(
                navigation: navigation,
                generation: generation,
                signature: signature,
                in: webView
            ) else { return }
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

        /// Reconnects a finalized retained page to reconstructed SwiftUI
        /// session state. Yielding avoids publishing ObservableObject state
        /// during `updateNSView`; the acknowledgement prevents an update loop.
        private func reannounceFinalizedRenderingIfNeeded(
            signature: String,
            in webView: WKWebView
        ) {
            guard finalizedSignature == signature,
                  !renderingReadinessIsAcknowledged else { return }
            Task { @MainActor [weak self, weak webView] in
                await Task.yield()
                guard let self, let webView,
                      self.activeWebView === webView,
                      self.loadedSignature == signature,
                      self.finalizedSignature == signature,
                      !self.renderingReadinessIsAcknowledged else { return }
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
            guard request.fingerprint == fingerprint,
                  scrollRestoration.owns(claim),
                  isCurrentLoad(
                      generation: generation,
                      signature: signature,
                      in: webView
                  ) else { return false }
            let fraction = request.position.fraction
            let anchorValue: Any
            if let anchor = request.position.anchor,
               anchor.sourceFingerprint == fingerprint,
               anchor.isValid(forUTF16Length: sourceUTF16Length) {
                anchorValue = [
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
                let extent = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
                for (let attempt = 0; attempt < 50 && extent <= 0; attempt += 1) {
                  await new Promise(resolve => setTimeout(resolve, 10));
                  extent = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
                }
                window.scholiumReadScroll?.recordRestoreAttempt?.();
                const restored = Boolean(anchor && window.scholiumReadScroll?.restore(anchor));
                if (!restored) window.scrollTo({top: extent * fallbackFraction, behavior: 'auto'});
                const fraction = extent > 0 ? Math.max(0, Math.min(1, window.scrollY / extent)) : 0;
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
                contentWorld: SafeMarkdownReadWebView.bridgeContentWorld
            )
            guard activeWebView === webView,
                  loadGeneration == generation,
                  activeLoadSignature == signature,
                  scrollRestoration.owns(claim),
                  documentID == expectedDocumentID,
                  fingerprint == expectedFingerprint,
                  let payload = result as? [String: Any] else { return false }
            if payload["restored"] as? Bool == true,
               let requestedAnchor = request.position.anchor {
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
            guard pageIsReady,
                  let navigation = activeNavigation,
                  let signature = activeLoadSignature else { return }
            let hasPendingRequest = scrollRestoration.hasPendingRequest(
                fingerprint: fingerprint
            )
            let hasPendingSourceLine = targetSourceLine.map {
                $0 > 0 && $0 != lastReachedSourceLine
            } == true
            guard hasPendingRequest || hasPendingSourceLine else { return }

            let generation = loadGeneration
            let finalization = loadFinalizationTask
            sourceLineNavigationTask?.cancel()
            sourceLineNavigationTask = Task { @MainActor [weak self, weak webView] in
                await finalization?.value
                guard let self, let webView,
                      self.isCurrentLoad(
                          navigation: navigation,
                          generation: generation,
                          signature: signature,
                          in: webView
                      ) else { return }
                let restoreClaim = self.scrollRestoration.claimIfReady(
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
                guard self.isCurrentLoad(
                    navigation: navigation,
                    generation: generation,
                    signature: signature,
                    in: webView
                ) else { return }
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
                  loadedSignature == signature else { return false }
            if let navigation {
                return activeNavigation === navigation
            }
            return activeNavigation != nil
        }

        func cancelPendingPageWork(keepingLoadIdentity: Bool = false) {
            loadFinalizationTask?.cancel()
            loadFinalizationTask = nil
            sourceLineNavigationTask?.cancel()
            sourceLineNavigationTask = nil
            linkPreviewUpdateTask?.cancel()
            linkPreviewUpdateTask = nil
            commentAnchorUpdateTask?.cancel()
            commentAnchorUpdateTask = nil
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
            guard let fraction = (fractionValue as? NSNumber)?.doubleValue,
                  fraction.isFinite,
                  (0 ... 1).contains(fraction) else { return }
            scrollRestoration.observedPosition.updateFraction(fraction)
            onScrollFractionChange?(fraction)
            guard let raw = anchorValue as? [String: Any],
                  let sourceOffset = (raw["sourceUTF16Offset"] as? NSNumber)?.intValue,
                  let lowerBound = (raw["blockUTF16LowerBound"] as? NSNumber)?.intValue,
                  let upperBound = (raw["blockUTF16UpperBound"] as? NSNumber)?.intValue,
                  let relativePosition = (raw["relativeBlockPosition"] as? NSNumber)?.doubleValue else {
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
                  (0 ... 1).contains(fraction),
                  requestedAnchor.sourceFingerprint == fingerprint,
                  requestedAnchor.isValid(forUTF16Length: sourceUTF16Length) else { return }
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

        private func scrollToSourceLineIfNeeded(
            generation: UInt64,
            signature: String,
            in webView: WKWebView
        ) async {
            guard let line = targetSourceLine,
                  line > 0,
                  line != lastReachedSourceLine,
                  isCurrentLoad(
                      generation: generation,
                      signature: signature,
                      in: webView
                  ) else { return }
            let result = try? await webView.callAsyncJavaScript(
                """
                const items = Array.from(document.querySelectorAll('[data-source-line]'));
                let target = items.find(item => Number(item.dataset.sourceLine) === requested);
                if (!target) {
                  target = items.filter(item => Number(item.dataset.sourceLine) <= requested).pop() || items[0];
                }
                if (!target) return false;
                target.scrollIntoView({block:'start', behavior:'auto'});
                target.tabIndex = -1;
                target.focus({preventScroll:true});
                const extent = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
                const fraction = extent > 0 ? Math.max(0, Math.min(1, window.scrollY / extent)) : 0;
                return {
                  reached: true,
                  fraction,
                  anchor: window.scholiumReadScroll?.current(fraction) ?? null
                };
                """,
                arguments: ["requested": line],
                in: nil,
                contentWorld: SafeMarkdownReadWebView.bridgeContentWorld
            )
            guard let payload = result as? [String: Any],
                  payload["reached"] as? Bool == true,
                  targetSourceLine == line,
                  isCurrentLoad(
                      generation: generation,
                      signature: signature,
                      in: webView
                  ) else { return }
            receiveScrollPosition(
                fractionValue: payload["fraction"],
                anchorValue: payload["anchor"]
            )
            lastReachedSourceLine = line
            onSourceLineReached?()
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: any Error
        ) {
            guard activeNavigation === navigation else { return }
            cancelPendingPageWork()
            onRenderingFailure?(error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            guard activeNavigation === navigation else { return }
            cancelPendingPageWork()
            onRenderingFailure?(error.localizedDescription)
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
            if navigationAction.navigationType == .linkActivated,
               let scheme = url.scheme?.lowercased(),
               ["http", "https", "mailto", "zotero"].contains(scheme) {
                onOpenExternalURL(url)
            }
            decisionHandler(.cancel)
        }

        static func documentHTML(
            body: String,
            includesMathRuntime: Bool? = nil,
            localization: WebKitInterfaceLocalization = .current()
        ) -> String {
            #if DEBUG
            let qaCommentSubmitControl = Bundle.main.bundleIdentifier == "com.scholium.qa"
                ? #"<button id="qa-submit-comment" class="scholium-qa-only-control" type="button"></button>"#
                : ""
            #else
            let qaCommentSubmitControl = ""
            #endif
            let includesMathRuntime = includesMathRuntime
                ?? requiresMathRuntime(body: body, linkPreviews: [])
            let mathCSS = includesMathRuntime ? ScholiumMathAssets.css : ""
            return """
            <!doctype html>
            <html lang="\(localization.languageTag)">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'none'; img-src data:; connect-src 'none'; font-src scholium-font: data:">
              <style>\(ScholiumWebFonts.css)\n\(ScholiumTableStyles.css)\n\(ScholiumFootnoteStyles.css)\n\(mathCSS)\n\(ScholiumMermaidAssets.css)\n\(ScholiumPreviewStyles.css)\n\(baseCSS)</style>
              <style id="scholium-presentation-css"></style>
              <style id="scholium-user-css"></style>
            </head>
            <body>
              <main id="scholium-document" class="scholium-document">\(body)</main>
              <aside id="scholium-preview-popover" class="scholium-preview-popover" data-scholium-protected="preview-popover" role="tooltip" aria-live="polite" hidden>
                <h2 class="scholium-preview-title"></h2>
                <p class="scholium-preview-metadata" hidden></p>
                <div class="scholium-preview-body scholium-document"></div>
              </aside>
              <div id="selection-actions" class="scholium-selection-actions" hidden>
                <div id="selection-toolbar" class="scholium-selection-toolbar" role="toolbar">
                  <button id="comment-selection" class="scholium-selection-control" type="button">
                    <span class="scholium-selection-label"></span>
                  </button>
                </div>
                <div id="comment-composer" aria-busy="false" hidden>
                  <textarea id="comment-text" rows="2" maxlength="16384" aria-describedby="comment-help"></textarea>
                  <span id="comment-help" role="status" aria-live="polite" aria-atomic="true"></span>
                  \(qaCommentSubmitControl)
                </div>
              </div>
            </body>
            </html>
            """
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
        private struct ReadBridgeConfiguration: Encodable {
            let version: Int
            let documentID: String
            let fingerprint: String
            let loadGeneration: UInt64
            let commentEnabled: Bool
            let selectionEnabled: Bool
            let testingEnabled: Bool
            let presentationCSS: String
            let userCSS: String
            let localization: WebKitInterfaceLocalization
            let linkPreviews: [ReadLinkPreview]
            let commentAnchors: [ReadCommentAnchor]
            let vectorSymbols: [String: String]
        }

        private static var readerScript: String? {
            ScholiumDocumentWebResources.text(named: "reader.bundle", extension: "js")
        }

        static func bridgeScript(
            documentID: String,
            fingerprint: String,
            loadGeneration: UInt64,
            commentEnabled: Bool,
            selectionEnabled: Bool,
            linkPreviews: [DocumentLinkPreview],
            commentAnchors: [ReviewCommentAnchor],
            presentationCSS: String,
            userCSS: String,
            localization: WebKitInterfaceLocalization = .current()
        ) -> String {
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
                    relationship: $0.relationship?.rawValue,
                    fragment: $0.fragment.map { String($0.prefix(240)) },
                    htmlBody: $0.syntax == .embed
                        ? $0.htmlBody
                        : String($0.htmlBody.prefix(24_000))
                )
            }
            let configuration = ReadBridgeConfiguration(
                version: 1,
                documentID: documentID,
                fingerprint: fingerprint,
                loadGeneration: loadGeneration,
                commentEnabled: commentEnabled,
                selectionEnabled: selectionEnabled,
                testingEnabled: testingEnabled,
                presentationCSS: presentationCSS,
                userCSS: userCSS,
                localization: localization,
                linkPreviews: previews,
                commentAnchors: commentAnchors.prefix(4_096).map(ReadCommentAnchor.init),
                vectorSymbols: vectorSymbolDataURIs
            )
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

        private struct ReadLinkPreview: Encodable {
            let utf16LowerBound: Int
            let utf16UpperBound: Int
            let title: String
            let isEmbedded: Bool
            let relationship: String?
            let fragment: String?
            let htmlBody: String
        }

        private struct ReadCommentAnchor: Encodable {
            let id: String
            let discussionID: String
            let statementID: String
            let startLine: Int
            let endLine: Int
            let commentCount: Int

            init(_ anchor: ReviewCommentAnchor) {
                id = anchor.id
                discussionID = anchor.discussionID.uuidString.lowercased()
                statementID = anchor.statementID.uuidString.lowercased()
                startLine = anchor.startLine
                endLine = anchor.endLine
                commentCount = anchor.commentCount
            }
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
                    "relationship": preview.relationship?.rawValue ?? NSNull(),
                    "fragment": preview.fragment.map { String($0.prefix(240)) } ?? NSNull(),
                    "htmlBody": preview.syntax == .embed
                        ? preview.htmlBody
                        : String(preview.htmlBody.prefix(24_000)),
                ]
            }
        }

        private static func commentAnchorArguments(
            _ anchors: [ReviewCommentAnchor]
        ) -> [[String: Any]] {
            anchors.prefix(4_096).map { anchor in
                [
                    "id": anchor.id,
                    "discussionID": anchor.discussionID.uuidString.lowercased(),
                    "statementID": anchor.statementID.uuidString.lowercased(),
                    "startLine": anchor.startLine,
                    "endLine": anchor.endLine,
                    "commentCount": anchor.commentCount,
                ]
            }
        }

        private static func commentAnchorsByID(
            _ anchors: [ReviewCommentAnchor]
        ) -> [String: ReviewCommentAnchor] {
            Dictionary(
                anchors.prefix(4_096).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        private static func commentAnchorRevision(
            for anchors: [ReviewCommentAnchor]
        ) -> String {
            anchors.map { anchor in
                "\(anchor.id):\(anchor.statementID.uuidString.lowercased()):\(anchor.commentCount)"
            }.joined(separator: "|")
        }

        private static func base64JSON<T: Encodable>(_ value: T) -> String {
            guard let data = try? JSONEncoder().encode(value) else { return "W10=" }
            return data.base64EncodedString()
        }

        static let baseCSS = """
        html, body { margin: 0; min-height: 100%; overflow-x: hidden; background: var(--scholium-color-document-background); color: var(--scholium-color-primary-text); }
        html.scholium-viewport-resize-suppresses-overlay-scrollbar { scrollbar-width: none; }
        body { font-family: Alegreya, Georgia, serif; font-size: var(--scholium-document-prose-font-size); line-height: var(--scholium-rhythm-prose-line-height); }
        \(ReviewSelectionPresentation.css)
        .scholium-document.scholium-has-comment-anchors { position: relative; }
        .scholium-review-comment-range {
          background-color: color-mix(in srgb, var(--scholium-color-accent) 6%, transparent) !important;
          background-image: linear-gradient(to right, color-mix(in srgb, var(--scholium-color-accent) 44%, var(--scholium-color-separator)) 0 2px, transparent 2px) !important;
        }
        .scholium-review-comment-range-active {
          background-color: color-mix(in srgb, var(--scholium-color-accent) 12%, transparent) !important;
          background-image: linear-gradient(to right, var(--scholium-color-accent) 0 3px, transparent 3px) !important;
        }
        .scholium-review-comment-range:dir(rtl) {
          background-image: linear-gradient(to left, color-mix(in srgb, var(--scholium-color-accent) 44%, var(--scholium-color-separator)) 0 2px, transparent 2px) !important;
        }
        .scholium-review-comment-range-active:dir(rtl) {
          background-image: linear-gradient(to left, var(--scholium-color-accent) 0 3px, transparent 3px) !important;
        }
        .scholium-review-comment-anchor {
          appearance: none;
          position: absolute;
          z-index: 4;
          box-sizing: border-box;
          inline-size: 28px;
          block-size: 28px;
          padding: 5px;
          border: 1px solid var(--scholium-color-separator);
          border-radius: var(--scholium-corner-document-control);
          color: var(--scholium-color-secondary-text);
          background-color: color-mix(in srgb, var(--scholium-color-document-background) 92%, var(--scholium-color-primary-text) 8%);
          cursor: pointer;
        }
        .scholium-review-comment-anchor::before {
          content: "";
          display: block;
          inline-size: 100%;
          block-size: 100%;
          background-color: currentColor;
          -webkit-mask: var(--scholium-comment-symbol) center / contain no-repeat;
          mask: var(--scholium-comment-symbol) center / contain no-repeat;
        }
        .scholium-review-comment-anchor::after {
          content: attr(data-comment-count);
          position: absolute;
          inset-block-start: -5px;
          inset-inline-end: -5px;
          box-sizing: border-box;
          min-inline-size: 14px;
          block-size: 14px;
          padding-inline: 3px;
          border-radius: var(--scholium-corner-inline-status);
          color: var(--scholium-color-document-background);
          background-color: var(--scholium-color-accent);
          font: 600 9px/14px -apple-system, BlinkMacSystemFont, sans-serif;
          font-variant-numeric: tabular-nums;
          text-align: center;
        }
        .scholium-review-comment-anchor[data-comment-count="1"]::after { display: none; }
        #selection-actions { position: absolute; }
        .scholium-document .scholium-vector-link { display: inline; opacity: 1; visibility: visible; color: var(--scholium-color-accent); line-height: inherit; text-decoration: none; }
        .scholium-document .scholium-vector-neutral,
        .scholium-document .scholium-vector-supports,
        .scholium-document .scholium-vector-opposes,
        .scholium-document .scholium-vector-incompatible { color: var(--scholium-color-accent); }
        .scholium-vector-icon { display: inline-block; width: .52em; height: .52em; margin-inline-start: .08em; vertical-align: .58em; background-color: currentColor; -webkit-mask-position: center; -webkit-mask-size: contain; -webkit-mask-repeat: no-repeat; mask-position: center; mask-size: contain; mask-repeat: no-repeat; }
        code { font-family: "Victor Mono", ui-monospace, monospace; }
        img, video, svg { max-width: 100%; height: auto; }
        \(ScholiumCalloutStyles.css)
        #selection-actions.scholium-comment-composing { padding: 6px; }
        #comment-composer { position: relative; display: grid; gap: 5px; width: clamp(220px, calc(100vw - 28px), 288px); }
        #comment-composer[hidden], #selection-toolbar[hidden] { display: none; }
        #comment-text { appearance: none; box-sizing: border-box; width: 100%; min-height: 64px; max-height: 132px; resize: none; overflow-y: auto; padding: 8px 9px; border: 0; border-radius: var(--scholium-corner-editorial-text-editor); outline: 0; color: var(--scholium-color-primary-text); caret-color: var(--scholium-color-accent); background: var(--scholium-color-document-background); font: 13px/17px -apple-system, BlinkMacSystemFont, sans-serif; }
        #comment-text::placeholder { color: var(--scholium-color-muted-text); opacity: .72; }
        #comment-text:focus-visible { box-shadow: inset 0 0 0 1px var(--scholium-content-focus-ring); }
        #comment-text:read-only { opacity: .72; }
        #comment-help { padding-inline: 2px; color: var(--scholium-color-muted-text); font: 10px/13px -apple-system, BlinkMacSystemFont, sans-serif; white-space: nowrap; }
        #comment-composer[data-state="error"] #comment-help { color: var(--scholium-color-destructive); }
        #comment-composer[data-state="saving"] #comment-help { color: var(--scholium-color-secondary-text); }
        .scholium-qa-only-control { position: absolute; inset-inline-end: 0; inset-block-end: 0; box-sizing: border-box; inline-size: 20px; block-size: 20px; padding: 0; overflow: hidden; border: 0; color: transparent; background: transparent; font: 0/0 -apple-system, BlinkMacSystemFont, sans-serif; }
        .scholium-qa-only-control:focus-visible { outline: 1px solid var(--scholium-content-focus-ring); outline-offset: 0; }
        .raw-html, .raw-html-inline { color: GrayText; }
        @media (prefers-contrast: more) {
          #comment-text:focus-visible { box-shadow: inset 0 0 0 2px var(--scholium-content-focus-ring); }
          .scholium-review-comment-range { background-color: transparent !important; background-image: linear-gradient(to right, var(--scholium-color-accent) 0 3px, transparent 3px) !important; }
          .scholium-review-comment-range:dir(rtl) { background-image: linear-gradient(to left, var(--scholium-color-accent) 0 3px, transparent 3px) !important; }
          .scholium-review-comment-anchor { border-width: 2px; border-color: var(--scholium-color-primary-text); }
        }
        \(ScholiumWebDesignTokens.documentPresentationCSS)
        """
    }
}
