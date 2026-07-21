import ScholiumContracts
import AppKit
import SwiftUI
import WebKit

struct SafeMarkdownReadWebView: NSViewRepresentable {
    let documentID: String
    let fingerprint: String
    let source: String
    let htmlBody: String
    let presentationCSS: String
    let userCSS: String
    /// Stable caller-owned revisions avoid hashing bounded-but-nontrivial
    /// comment and preview payloads during unrelated SwiftUI updates.
    var configurationRevision: String? = nil
    let researcherComments: [ResearcherComment]
    var linkPreviews: [DocumentLinkPreview] = []
    let onLinkClick: (String) -> Void
    let onOpenExternalURL: (URL) -> Void
    let onCommentSelection: ((MarkdownReviewSelection) -> Void)?
    var onSelectionChange: ((MarkdownReviewSelection?) -> Void)? = nil
    let onCommentActivation: ((UUID) -> Void)?
    let onRenderingFailure: ((String) -> Void)?
    var onRenderingLoading: (() -> Void)? = nil
    var onRenderingReady: (() -> Void)? = nil
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
            onSelectionChange: onSelectionChange,
            onCommentActivation: onCommentActivation,
            onRenderingFailure: onRenderingFailure,
            onRenderingLoading: onRenderingLoading,
            onRenderingReady: onRenderingReady,
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
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: Coordinator.messageHandlerName)
        if !ScholiumMathAssets.runtimeJavaScript.isEmpty {
            contentController.addUserScript(WKUserScript(
                source: ScholiumMathAssets.runtimeJavaScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
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
            researcherComments: researcherComments,
            linkPreviews: linkPreviews,
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
            onSelectionChange: onSelectionChange,
            onCommentActivation: onCommentActivation,
            onRenderingFailure: onRenderingFailure,
            onRenderingLoading: onRenderingLoading,
            onRenderingReady: onRenderingReady,
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
            researcherComments: researcherComments,
            linkPreviews: linkPreviews,
            in: webView
        )
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.messageHandlerName
        )
        webView.navigationDelegate = nil
        coordinator.activeWebView = nil
        coordinator.cancelPendingPageWork()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private struct ScrollRestoreIdentity: Equatable {
            let id: UInt64
            let fingerprint: String
        }

        private struct ScrollRestoreClaim {
            let token: UInt64
            let request: ScrollRestoreRequest
            let ownership: ScrollRestoreOwnership
        }

        private enum ScrollRestoreOwnership {
            case caller
            case coordinator
        }

        static let messageHandlerName = "scholiumRead"
        private static let maximumSelectionLength = 2_000
        /// SwiftUI can briefly replay an acknowledged value after a newer
        /// WebView-rebuild request has completed. Keep a small, fixed history
        /// so that old one-shot IDs cannot become restoration commands again.
        private static let consumedScrollRestoreHistoryLimit = 64
        private static let vectorSymbolDataURIs = Dictionary(
            uniqueKeysWithValues: [
                "link", "arrow.right.circle", "arrow.left.circle", "xmark.circle",
            ].map { ($0, symbolDataURI(named: $0)) }
        )

        private var documentID: String
        private var fingerprint: String
        private var onLinkClick: (String) -> Void
        private var onOpenExternalURL: (URL) -> Void
        private var onCommentSelection: ((MarkdownReviewSelection) -> Void)?
        private var onSelectionChange: ((MarkdownReviewSelection?) -> Void)?
        private var onCommentActivation: ((UUID) -> Void)?
        private var onRenderingFailure: ((String) -> Void)?
        private var onRenderingLoading: (() -> Void)?
        private var onRenderingReady: (() -> Void)?
        private var scrollRestoreRequest: ScrollRestoreRequest?
        private var scrollRestoreOwnership: ScrollRestoreOwnership?
        private var observedScrollPosition: ObservedScrollPosition
        private var onScrollRestoreConsumed: ((UInt64, String) -> Void)?
        private var consumedScrollRestoreRequests: [ScrollRestoreIdentity] = []
        private var inFlightScrollRestoreClaim: ScrollRestoreClaim?
        private var nextScrollRestoreClaimToken: UInt64 = 0
        private var nextInternalScrollRestoreRequestID = UInt64.max
        private var hasLoadedPage = false
        private var loadGeneration: UInt64 = 0
        private var activeLoadSignature: String?
        private var activeNavigation: WKNavigation?
        private var loadFinalizationTask: Task<Void, Never>?
        private var sourceLineNavigationTask: Task<Void, Never>?
        private var onScrollFractionChange: ((Double) -> Void)?
        private var onScrollAnchorChange: ((EditorScrollAnchor) -> Void)?
        private var sourceUTF16Length = 0
        private var targetSourceLine: Int?
        private var onSourceLineReached: (() -> Void)?
        private var lastReachedSourceLine: Int?
        private var loadedSignature: String?
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
            onCommentSelection: ((MarkdownReviewSelection) -> Void)?,
            onSelectionChange: ((MarkdownReviewSelection?) -> Void)?,
            onCommentActivation: ((UUID) -> Void)?,
            onRenderingFailure: ((String) -> Void)?,
            onRenderingLoading: (() -> Void)?,
            onRenderingReady: (() -> Void)?,
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
            self.onSelectionChange = onSelectionChange
            self.onCommentActivation = onCommentActivation
            self.onRenderingFailure = onRenderingFailure
            self.onRenderingLoading = onRenderingLoading
            self.onRenderingReady = onRenderingReady
            self.scrollRestoreRequest = scrollRestoreRequest
            scrollRestoreOwnership = scrollRestoreRequest == nil ? nil : .caller
            self.observedScrollPosition = observedScrollPosition
            self.onScrollRestoreConsumed = onScrollRestoreConsumed
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
            onCommentSelection: ((MarkdownReviewSelection) -> Void)?,
            onSelectionChange: ((MarkdownReviewSelection?) -> Void)?,
            onCommentActivation: ((UUID) -> Void)?,
            onRenderingFailure: ((String) -> Void)?,
            onRenderingLoading: (() -> Void)?,
            onRenderingReady: (() -> Void)?,
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
                lastReachedSourceLine = nil
                pageIsReady = false
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
            self.onSelectionChange = onSelectionChange
            self.onCommentActivation = onCommentActivation
            self.onRenderingFailure = onRenderingFailure
            self.onRenderingLoading = onRenderingLoading
            self.onRenderingReady = onRenderingReady
            self.observedScrollPosition = observedScrollPosition
            if self.observedScrollPosition.anchor?.sourceFingerprint != fingerprint {
                self.observedScrollPosition.anchor = nil
            }
            self.onScrollRestoreConsumed = onScrollRestoreConsumed
            adoptCallerScrollRestoreRequest(scrollRestoreRequest)
            self.onScrollFractionChange = onScrollFractionChange
            self.onScrollAnchorChange = onScrollAnchorChange
            self.targetSourceLine = targetSourceLine
            self.onSourceLineReached = onSourceLineReached
            schedulePostLoadPositioningIfNeeded(in: webView)
        }

        private func adoptCallerScrollRestoreRequest(_ request: ScrollRestoreRequest?) {
            guard let request else {
                guard scrollRestoreOwnership == .caller else { return }
                if inFlightScrollRestoreClaim?.ownership == .caller {
                    inFlightScrollRestoreClaim = nil
                }
                scrollRestoreRequest = nil
                scrollRestoreOwnership = nil
                return
            }
            guard !hasConsumedScrollRestoreRequest(request) else {
                if scrollRestoreOwnership == .caller,
                   scrollRestoreRequest.map({ sameScrollRestoreIdentity($0, request) }) == true {
                    scrollRestoreRequest = nil
                    scrollRestoreOwnership = nil
                }
                return
            }
            scrollRestoreRequest = request
            scrollRestoreOwnership = .caller
        }

        func loadIfNeeded(
            _ body: String,
            source: String,
            presentationCSS: String,
            userCSS: String,
            configurationRevision: String?,
            researcherComments: [ResearcherComment],
            linkPreviews: [DocumentLinkPreview],
            in webView: WKWebView
        ) {
            let capabilitySignature = "\(onCommentSelection != nil):\(onSelectionChange != nil)"
            let signature = configurationRevision.map {
                "revision:\($0):\(capabilitySignature)"
            } ?? [
                fingerprint,
                String(body.utf8.count),
                String(presentationCSS.hashValue),
                String(userCSS.hashValue),
                String(researcherComments.hashValue),
                String(linkPreviews.hashValue),
                capabilitySignature,
            ].joined(separator: ":")
            guard loadedSignature != signature else { return }
            sourceUTF16Length = source.utf16.count
            ensureScrollRestoreRequest(
                reason: hasLoadedPage ? .webViewRebuild : .documentLoad
            )
            hasLoadedPage = true
            loadGeneration &+= 1
            let expectedLoadGeneration = loadGeneration
            activeLoadSignature = signature
            activeNavigation = nil
            cancelPendingPageWork(keepingLoadIdentity: true)
            loadedSignature = signature
            pageIsReady = false
            activeWebView = webView
            let html = Self.documentHTML(
                body: body,
                source: source,
                documentID: documentID,
                fingerprint: fingerprint,
                loadGeneration: expectedLoadGeneration,
                commentEnabled: onCommentSelection != nil,
                selectionEnabled: onSelectionChange != nil,
                researcherComments: researcherComments,
                linkPreviews: linkPreviews,
                presentationCSS: presentationCSS,
                userCSS: userCSS
            )
            let expectedSignature = signature
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
                let navigation = webView.loadHTMLString(html, baseURL: nil)
                guard self.activeWebView === webView,
                      self.loadedSignature == expectedSignature,
                      self.activeLoadSignature == expectedSignature,
                      self.loadGeneration == expectedLoadGeneration else { return }
                self.activeNavigation = navigation
            }
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
            case "internalLink":
                guard let target = payload["target"] as? String,
                      !target.isEmpty,
                      target.utf8.count <= 8_192 else { return }
                onLinkClick(target)
            case "commentSelection":
                guard let selection = reviewSelection(from: payload) else { return }
                onCommentSelection?(selection)
            case "selectionChanged":
                guard payload["text"] != nil else {
                    onSelectionChange?(nil)
                    return
                }
                onSelectionChange?(reviewSelection(from: payload))
            case "commentActivated":
                guard let rawID = payload["commentID"] as? String,
                      let id = UUID(uuidString: rawID) else { return }
                onCommentActivation?(id)
            case "scrollChanged":
                receiveScrollPosition(
                    fractionValue: payload["fraction"],
                    anchorValue: payload["anchor"]
                )
            default:
                return
            }
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
            pageIsReady = true
            let restoreClaim = claimScrollRestoreRequest()
            let expectedDocumentID = documentID
            let expectedFingerprint = fingerprint
            loadFinalizationTask?.cancel()
            loadFinalizationTask = Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                var claimWasFinished = false
                defer {
                    if let restoreClaim, !claimWasFinished {
                        self.finishScrollRestoreClaim(restoreClaim, consumed: false)
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
                        if (document.fonts?.ready) await document.fonts.ready;
                        return true;
                        """,
                        arguments: [:],
                        in: nil,
                        contentWorld: .page
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
                        self.finishScrollRestoreClaim(
                            restoreClaim,
                            consumed: restoreSucceeded
                        )
                        claimWasFinished = true
                    }
                    webView.setAccessibilityIdentifier(
                        "scholium.renderedDocument.\(expectedDocumentID)"
                    )
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
            inFlightScrollRestoreClaim = nil
            loadFinalizationTask = nil
            pageIsReady = false
            loadedSignature = nil
            loadGeneration &+= 1
            activeLoadSignature = nil
            activeNavigation = nil
            webView.setAccessibilityIdentifier("scholium.renderedDocument.failed")
            onRenderingFailure?(error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            pageIsReady = false
            loadedSignature = nil
            cancelPendingPageWork()
            webView.setAccessibilityIdentifier("scholium.renderedDocument.failed")
            onRenderingFailure?("The Read renderer stopped unexpectedly.")
        }

        private func restoreScrollPosition(
            _ claim: ScrollRestoreClaim,
            generation: UInt64,
            signature: String,
            in webView: WKWebView
        ) async -> Bool {
            let request = claim.request
            guard request.fingerprint == fingerprint,
                  inFlightScrollRestoreClaim?.token == claim.token,
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
                contentWorld: .page
            )
            guard activeWebView === webView,
                  loadGeneration == generation,
                  activeLoadSignature == signature,
                  inFlightScrollRestoreClaim?.token == claim.token,
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

        private func ensureScrollRestoreRequest(reason: ScrollRestoreReason) {
            if let request = scrollRestoreRequest,
               request.fingerprint == fingerprint,
               !hasConsumedScrollRestoreRequest(request) {
                return
            }
            let matchingAnchor = observedScrollPosition.anchor.flatMap { anchor in
                anchor.sourceFingerprint == fingerprint ? anchor : nil
            }
            scrollRestoreRequest = ScrollRestoreRequest(
                id: nextInternalScrollRestoreRequestID,
                fingerprint: fingerprint,
                position: ObservedScrollPosition(
                    fraction: observedScrollPosition.fraction,
                    anchor: matchingAnchor
                ),
                reason: reason
            )
            scrollRestoreOwnership = .coordinator
            nextInternalScrollRestoreRequestID &-= 1
        }

        private func claimScrollRestoreRequest() -> ScrollRestoreClaim? {
            guard pageIsReady,
                  let request = scrollRestoreRequest,
                  let ownership = scrollRestoreOwnership,
                  request.fingerprint == fingerprint,
                  !hasConsumedScrollRestoreRequest(request),
                  (inFlightScrollRestoreClaim?.request.id != request.id
                      || inFlightScrollRestoreClaim?.request.fingerprint != request.fingerprint) else {
                return nil
            }
            nextScrollRestoreClaimToken &+= 1
            let claim = ScrollRestoreClaim(
                token: nextScrollRestoreClaimToken,
                request: request,
                ownership: ownership
            )
            inFlightScrollRestoreClaim = claim
            return claim
        }

        private func finishScrollRestoreClaim(
            _ claim: ScrollRestoreClaim,
            consumed: Bool
        ) {
            guard inFlightScrollRestoreClaim?.token == claim.token else { return }
            inFlightScrollRestoreClaim = nil
            guard consumed else { return }
            recordConsumedScrollRestoreRequest(claim.request)
            if scrollRestoreRequest.map({ sameScrollRestoreIdentity($0, claim.request) }) == true {
                scrollRestoreRequest = nil
                scrollRestoreOwnership = nil
            }
            if claim.ownership == .caller {
                onScrollRestoreConsumed?(
                    claim.request.id,
                    claim.request.fingerprint
                )
            }
        }

        private func sameScrollRestoreIdentity(
            _ lhs: ScrollRestoreRequest,
            _ rhs: ScrollRestoreRequest
        ) -> Bool {
            lhs.id == rhs.id && lhs.fingerprint == rhs.fingerprint
        }

        private func hasConsumedScrollRestoreRequest(_ request: ScrollRestoreRequest) -> Bool {
            let identity = ScrollRestoreIdentity(
                id: request.id,
                fingerprint: request.fingerprint
            )
            return consumedScrollRestoreRequests.contains(identity)
        }

        private func recordConsumedScrollRestoreRequest(_ request: ScrollRestoreRequest) {
            let identity = ScrollRestoreIdentity(
                id: request.id,
                fingerprint: request.fingerprint
            )
            guard !consumedScrollRestoreRequests.contains(identity) else { return }
            consumedScrollRestoreRequests.append(identity)
            let overflow = consumedScrollRestoreRequests.count
                - Self.consumedScrollRestoreHistoryLimit
            if overflow > 0 {
                consumedScrollRestoreRequests.removeFirst(overflow)
            }
        }

        private func schedulePostLoadPositioningIfNeeded(in webView: WKWebView) {
            guard pageIsReady,
                  let navigation = activeNavigation,
                  let signature = activeLoadSignature else { return }
            let hasPendingRequest = scrollRestoreRequest.map { request in
                request.fingerprint == fingerprint
                    && !hasConsumedScrollRestoreRequest(request)
                    && (inFlightScrollRestoreClaim?.request.id != request.id
                        || inFlightScrollRestoreClaim?.request.fingerprint != request.fingerprint)
            } == true
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
                let restoreClaim = self.claimScrollRestoreRequest()
                var claimWasFinished = false
                defer {
                    if let restoreClaim, !claimWasFinished {
                        self.finishScrollRestoreClaim(restoreClaim, consumed: false)
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
                    self.finishScrollRestoreClaim(
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
            inFlightScrollRestoreClaim = nil
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
            observedScrollPosition.updateFraction(fraction)
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
                observedScrollPosition.anchor = anchor
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
            observedScrollPosition.updateFraction(fraction)
            onScrollFractionChange?(fraction)
            let anchor = EditorScrollAnchor(
                sourceFingerprint: requestedAnchor.sourceFingerprint,
                sourceUTF16Offset: requestedAnchor.sourceUTF16Offset,
                blockUTF16LowerBound: requestedAnchor.blockUTF16LowerBound,
                blockUTF16UpperBound: requestedAnchor.blockUTF16UpperBound,
                relativeBlockPosition: requestedAnchor.relativeBlockPosition,
                fallbackFraction: fraction
            )
            observedScrollPosition.anchor = anchor
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
                contentWorld: .page
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
            source: String,
            documentID: String,
            fingerprint: String,
            loadGeneration: UInt64 = 1,
            commentEnabled: Bool,
            selectionEnabled: Bool,
            researcherComments: [ResearcherComment],
            linkPreviews: [DocumentLinkPreview],
            presentationCSS: String,
            userCSS: String
        ) -> String {
            let encodedDocumentID = jsonLiteral(documentID)
            let encodedFingerprint = jsonLiteral(fingerprint)
            let commentFlag = commentEnabled ? "true" : "false"
            let selectionFlag = selectionEnabled ? "true" : "false"
            #if DEBUG
            let readScrollTestingMembers = """
                  restoreCount: 0,
                  recordRestoreAttempt() { this.restoreCount += 1; },
                  testingSnapshot() {
                    var previousTop = Number.NEGATIVE_INFINITY;
                    var visualOrderIsMonotonic = true;
                    for (const entry of scrollBlockRegistry.entries) {
                      const top = entry.element.getBoundingClientRect().top;
                      if (top + 1 < previousTop) visualOrderIsMonotonic = false;
                      previousTop = Math.max(previousTop, top);
                    }
                    return {
                      registryCount: scrollBlockRegistry.entries.length,
                      visualOrderIsMonotonic
                    };
                  },
            """
            #else
            let readScrollTestingMembers = ""
            #endif
            let noteDocument = NoteDocument(relativePath: documentID, rawContent: source)
            let renderedSpans = renderedSourceSpans(in: source, relativePath: documentID)
            let sourceLength = (source as NSString).length
            let annotations: [ReadCommentAnnotation] = researcherComments.compactMap { comment in
                let anchor = comment.anchor
                guard anchor.state == .attached,
                      anchor.fingerprint.sha256 == fingerprint,
                      anchor.utf16Range.lowerBound >= 0,
                      anchor.utf16Range.upperBound <= sourceLength,
                      let container = renderedSpans
                        .filter({ span in
                            span.utf16LowerBound <= anchor.utf16Range.lowerBound
                                && span.utf16UpperBound >= anchor.utf16Range.upperBound
                        })
                        .min(by: {
                            ($0.utf16UpperBound - $0.utf16LowerBound)
                                < ($1.utf16UpperBound - $1.utf16LowerBound)
                        }) else { return nil }
                let sourceSpanLength = max(1, container.utf16UpperBound - container.utf16LowerBound)
                let quotations = [
                    ResearcherCommentAnchorBuilder.renderedQuotation(
                        for: anchor,
                        in: noteDocument
                    ),
                    anchor.selectedText,
                    anchor.quotation,
                ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .reduce(into: [String]()) { result, quotation in
                    guard !quotation.isEmpty, !result.contains(quotation) else { return }
                    result.append(quotation)
                }
                guard !quotations.isEmpty else { return nil }
                return ReadCommentAnnotation(
                    id: comment.id,
                    quotations: quotations,
                    comment: String(comment.text.prefix(500)),
                    resolved: comment.resolvedAt != nil,
                    utf16LowerBound: anchor.utf16Range.lowerBound,
                    utf16UpperBound: anchor.utf16Range.upperBound,
                    containerUTF16LowerBound: container.utf16LowerBound,
                    containerUTF16UpperBound: container.utf16UpperBound,
                    relativePosition: Double(anchor.utf16Range.lowerBound - container.utf16LowerBound)
                        / Double(sourceSpanLength)
                )
            }
            let annotationPayload = base64JSON(annotations)
            let previewPayload = base64JSON(linkPreviews.prefix(DocumentPreviewCatalogBuilder.maximumLinkCount).map {
                ReadLinkPreview(
                    utf16LowerBound: $0.sourceSpan.utf16LowerBound,
                    utf16UpperBound: $0.sourceSpan.utf16UpperBound,
                    title: String($0.title.prefix(240)),
                    relationship: $0.relationship?.rawValue,
                    fragment: $0.fragment.map { String($0.prefix(240)) },
                    htmlBody: String($0.htmlBody.prefix(24_000))
                )
            })
            return """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:; connect-src 'none'; font-src data:">
              <style>\(ScholiumWebFonts.css)\n\(ScholiumTableStyles.css)\n\(ScholiumFootnoteStyles.css)\n\(ScholiumMathAssets.css)\n\(ScholiumPreviewStyles.css)\n\(baseCSS)</style>
              <style id="scholium-presentation-css">\(presentationCSS)</style>
              <style id="scholium-user-css">\(userCSS)</style>
            </head>
            <body>
              <main id="scholium-document" class="scholium-document">\(body)</main>
              <aside id="scholium-preview-popover" class="scholium-preview-popover" data-scholium-protected="preview-popover" role="tooltip" aria-live="polite" hidden>
                <h2 class="scholium-preview-title"></h2>
                <p class="scholium-preview-metadata"></p>
                <div class="scholium-preview-body"></div>
              </aside>
              <button id="comment-selection" type="button" hidden>Add Comment</button>
              <script>
              (() => {
                'use strict';
                const version = 1;
                const documentID = \(encodedDocumentID);
                const fingerprint = \(encodedFingerprint);
                const loadGeneration = \(loadGeneration);
                const commentEnabled = \(commentFlag);
                const selectionEnabled = \(selectionFlag);
                const commentAnnotations = JSON.parse(new TextDecoder().decode(
                  Uint8Array.from(atob(\(jsonLiteral(annotationPayload))), character => character.charCodeAt(0))
                ));
                const linkPreviews = JSON.parse(new TextDecoder().decode(
                  Uint8Array.from(atob(\(jsonLiteral(previewPayload))), character => character.charCodeAt(0))
                ));
                const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(messageHandlerName);
                const post = (type, extra = {}) => handler && handler.postMessage({version, documentID, fingerprint, loadGeneration, type, ...extra});
                const popover = document.getElementById('scholium-preview-popover');
                const previewTitle = popover.querySelector('.scholium-preview-title');
                const previewMetadata = popover.querySelector('.scholium-preview-metadata');
                const previewBody = popover.querySelector('.scholium-preview-body');
                const reviewButton = document.getElementById('comment-selection');
                const previewByRange = new Map(linkPreviews.map(preview => [
                  preview.utf16LowerBound + ':' + preview.utf16UpperBound,
                  preview
                ]));
                const origins = new Map();
                const vectorSemantics = {
                  neutral: {label: 'Related note', symbol: \(jsonLiteral(vectorSymbolDataURIs["link"] ?? ""))},
                  supports_target: {label: 'Supports', symbol: \(jsonLiteral(vectorSymbolDataURIs["arrow.right.circle"] ?? ""))},
                  supported_by_target: {label: 'Supported by', symbol: \(jsonLiteral(vectorSymbolDataURIs["arrow.left.circle"] ?? ""))},
                  incompatible: {label: 'Incompatible with', symbol: \(jsonLiteral(vectorSymbolDataURIs["xmark.circle"] ?? ""))}
                };

                function renderMathNodes() {
                  const runtime = window.scholiumMath;
                  if (!runtime || runtime.version !== 1) return;
                  document.querySelectorAll('.scholium-math[data-math-source][data-math-kind]').forEach(element => {
                    try {
                      const source = new TextDecoder().decode(
                        Uint8Array.from(atob(element.dataset.mathSource), character => character.charCodeAt(0))
                      );
                      const result = runtime.render({source, kind: element.dataset.mathKind});
                      if (!result.ok) {
                        element.classList.add('scholium-math-error');
                        element.setAttribute('aria-label', 'Mathematics could not be rendered. Source is shown.');
                        return;
                      }
                      const fallback = element.querySelector('.scholium-math-source');
                      const rendered = document.createElement('span');
                      rendered.className = 'scholium-math-output';
                      rendered.innerHTML = result.html;
                      fallback && fallback.before(rendered);
                      element.classList.add('scholium-math-rendered');
                    } catch (_) {
                      element.classList.add('scholium-math-error');
                    }
                  });
                }
                renderMathNodes();

                document.querySelectorAll('a.wiki-link[data-vector-kind]').forEach(link => {
                  const kind = link.dataset.vectorKind;
                  const semantics = vectorSemantics[kind];
                  if (!semantics) return;
                  const noteName = (link.textContent || '').trim();
                  link.classList.add('scholium-vector-link', 'scholium-vector-' + kind.replaceAll('_', '-'));
                  link.dataset.scholiumProtected = 'vector-link';
                  link.setAttribute('aria-label', semantics.label + ' ' + noteName);
                  link.title = semantics.label + ' ' + noteName;
                  const icon = document.createElement('span');
                  icon.className = 'scholium-vector-icon';
                  icon.setAttribute('aria-hidden', 'true');
                  icon.style.webkitMaskImage = `url("${semantics.symbol}")`;
                  icon.style.maskImage = `url("${semantics.symbol}")`;
                  link.prepend(icon);
                });

                function applyCommentAnnotations() {
                  const root = document.getElementById('scholium-document');
                  if (!root) return;
                  for (const annotation of commentAnnotations) {
                    const containers = Array.from(root.querySelectorAll('[data-source-utf16-start][data-source-utf16-end]'))
                      .filter(element => Number(element.dataset.sourceUtf16Start) === annotation.containerUTF16LowerBound
                        && Number(element.dataset.sourceUtf16End) === annotation.containerUTF16UpperBound);
                    const container = containers.sort((left, right) => {
                      const leftSize = Number(left.dataset.sourceUtf16End) - Number(left.dataset.sourceUtf16Start);
                      const rightSize = Number(right.dataset.sourceUtf16End) - Number(right.dataset.sourceUtf16Start);
                      return leftSize - rightSize;
                    })[0];
                    if (!container) continue;
                    const walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT, {
                      acceptNode(node) {
                        const parent = node.parentElement;
                        if (!parent || parent.closest('button, script, style, [aria-hidden="true"]')) {
                          return NodeFilter.FILTER_REJECT;
                        }
                        return NodeFilter.FILTER_ACCEPT;
                      }
                    });
                    const nodes = [];
                    let flattened = '';
                    while (walker.nextNode()) {
                      const node = walker.currentNode;
                      const start = flattened.length;
                      flattened += node.data;
                      nodes.push({node, start, end: flattened.length});
                    }
                    let quote = '';
                    let matches = [];
                    for (const candidate of annotation.quotations || []) {
                      const proposed = String(candidate || '');
                      if (!proposed) continue;
                      const proposedMatches = [];
                      let cursor = 0;
                      while (cursor <= flattened.length - proposed.length) {
                        const offset = flattened.indexOf(proposed, cursor);
                        if (offset < 0) break;
                        proposedMatches.push(offset);
                        cursor = offset + Math.max(1, proposed.length);
                      }
                      if (proposedMatches.length) {
                        quote = proposed;
                        matches = proposedMatches;
                        break;
                      }
                    }
                    if (!quote || !matches.length) continue;
                    const expectedOffset = Math.max(0, Math.min(1, Number(annotation.relativePosition) || 0))
                      * Math.max(0, flattened.length - quote.length);
                    const startOffset = matches.reduce((best, candidate) =>
                      Math.abs(candidate - expectedOffset) < Math.abs(best - expectedOffset) ? candidate : best,
                    matches[0]);
                    const endOffset = startOffset + quote.length;
                    const first = nodes.find(item => item.start <= startOffset && item.end > startOffset);
                    const last = nodes.find(item => item.start < endOffset && item.end >= endOffset);
                    if (!first || !last) continue;
                    const range = document.createRange();
                    range.setStart(first.node, startOffset - first.start);
                    range.setEnd(last.node, endOffset - last.start);
                    const mark = document.createElement('mark');
                    mark.className = 'researcher-comment-annotation' + (annotation.resolved ? ' resolved' : '');
                    mark.dataset.scholiumProtected = 'researcher-comment';
                    mark.dataset.commentId = annotation.id;
                    mark.tabIndex = 0;
                    mark.setAttribute('role', 'button');
                    mark.setAttribute('aria-label', 'Researcher comment: ' + annotation.comment);
                    mark.title = 'Researcher comment: ' + annotation.comment;
                    mark.style.color = 'inherit';
                    mark.style.background = annotation.resolved
                      ? 'color-mix(in srgb, GrayText 9%, transparent)'
                      : 'color-mix(in srgb, AccentColor 18%, Mark 82%)';
                    mark.style.borderBottom = '2px solid ' + (annotation.resolved ? 'GrayText' : 'AccentColor');
                    try {
                      const contents = range.extractContents();
                      mark.appendChild(contents);
                      range.insertNode(mark);
                    } catch (_) {
                      continue;
                    }
                  }
                }
                applyCommentAnnotations();

                function hidePopover() {
                  popover.hidden = true;
                  previewTitle.textContent = '';
                  previewMetadata.textContent = '';
                  previewBody.replaceChildren();
                }

                function positionPopover(anchor) {
                  popover.hidden = false;
                  const rect = anchor.getBoundingClientRect();
                  const measured = popover.getBoundingClientRect();
                  const left = Math.max(12, Math.min(rect.left, window.innerWidth - measured.width - 12));
                  const below = rect.bottom + 8;
                  const top = below + measured.height <= window.innerHeight - 12
                    ? below
                    : Math.max(12, rect.top - measured.height - 8);
                  popover.style.left = left + 'px';
                  popover.style.top = top + 'px';
                }

                function removeInteractivePreviewContent() {
                  previewBody.querySelectorAll('script, style, iframe, object, embed, form, input, button').forEach(node => node.remove());
                  previewBody.querySelectorAll('*').forEach(node => {
                    Array.from(node.attributes).forEach(attribute => {
                      if (attribute.name.toLowerCase().startsWith('on')) node.removeAttribute(attribute.name);
                    });
                    node.removeAttribute('href');
                    node.removeAttribute('contenteditable');
                    node.tabIndex = -1;
                  });
                }

                function showFootnotePopover(button) {
                  const ordinal = button.dataset.footnote;
                  const definition = document.getElementById('fn-' + ordinal);
                  const content = definition && definition.querySelector('.footnote-content');
                  if (!content) return;
                  previewTitle.textContent = 'Footnote ' + ordinal;
                  previewMetadata.textContent = 'Referenced footnote';
                  previewBody.replaceChildren(content.cloneNode(true));
                  removeInteractivePreviewContent();
                  positionPopover(button);
                }

                function showLinkPopover(link) {
                  const key = link.dataset.sourceUtf16Start + ':' + link.dataset.sourceUtf16End;
                  const preview = previewByRange.get(key);
                  if (!preview) return;
                  const relationship = vectorSemantics[preview.relationship || 'neutral'];
                  previewTitle.textContent = preview.title;
                  previewMetadata.textContent = (relationship ? relationship.label : 'Related note')
                    + (preview.fragment ? ' · ' + preview.fragment : '');
                  previewBody.innerHTML = preview.htmlBody;
                  removeInteractivePreviewContent();
                  positionPopover(link);
                }

                document.addEventListener('pointerover', event => {
                  const button = event.target.closest && event.target.closest('.footnote-reference');
                  if (button) { showFootnotePopover(button); return; }
                  const link = event.target.closest && event.target.closest('a.wiki-link');
                  if (link) showLinkPopover(link);
                });
                document.addEventListener('focusin', event => {
                  const button = event.target.closest && event.target.closest('.footnote-reference');
                  if (button) { showFootnotePopover(button); return; }
                  const link = event.target.closest && event.target.closest('a.wiki-link');
                  if (link) showLinkPopover(link);
                });
                document.addEventListener('pointerout', event => {
                  if (event.target.closest && event.target.closest('.footnote-reference, a.wiki-link')) hidePopover();
                });

                document.addEventListener('click', event => {
                  const annotation = event.target.closest && event.target.closest('[data-comment-id]');
                  if (annotation) {
                    post('commentActivated', {commentID: annotation.dataset.commentId});
                    event.preventDefault();
                    return;
                  }
                  const reference = event.target.closest && event.target.closest('.footnote-reference');
                  if (reference && !reference.disabled) {
                    const ordinal = reference.dataset.footnote;
                    const target = document.getElementById(reference.dataset.target);
                    if (target) {
                      origins.set(ordinal, reference.id);
                      target.tabIndex = -1;
                      target.scrollIntoView({block: 'center', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth'});
                      target.focus({preventScroll: true});
                    }
                    event.preventDefault();
                    return;
                  }
                  const back = event.target.closest && event.target.closest('.footnote-return');
                  if (back) {
                    const ordinal = back.dataset.footnote;
                    const originID = origins.get(ordinal) || 'fnref-' + ordinal + '-1';
                    const origin = document.getElementById(originID);
                    if (origin) {
                      origin.scrollIntoView({block: 'center', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth'});
                      origin.focus({preventScroll: true});
                    }
                    event.preventDefault();
                    return;
                  }
                  const link = event.target.closest && event.target.closest('a[href^="scholium-note:"]');
                  if (link) {
                    const encoded = link.getAttribute('href').slice('scholium-note:'.length);
                    post('internalLink', {target: decodeURIComponent(encoded)});
                    event.preventDefault();
                  }
                });

                document.addEventListener('keydown', event => {
                  const annotation = event.target.closest && event.target.closest('[data-comment-id]');
                  if (annotation && (event.key === 'Enter' || event.key === ' ')) {
                    post('commentActivated', {commentID: annotation.dataset.commentId});
                    event.preventDefault();
                    return;
                  }
                  if (event.key === 'Escape') {
                    hidePopover();
                    reviewButton.hidden = true;
                  }
                });

                if (selectionEnabled) {
                  document.addEventListener('selectionchange', () => {
                    const selection = window.getSelection();
                    const text = selection ? selection.toString().trim() : '';
                    if (!text) {
                      reviewButton.hidden = true;
                      post('selectionChanged');
                      return;
                    }
                    const range = selection.getRangeAt(0);
                    const main = document.getElementById('scholium-document');
                    if (!main || !main.contains(range.startContainer) || !main.contains(range.endContainer)) {
                      reviewButton.hidden = true;
                      post('selectionChanged');
                      return;
                    }
                    const rect = range.getBoundingClientRect();
                    const beforeRange = document.createRange();
                    beforeRange.selectNodeContents(main);
                    beforeRange.setEnd(range.startContainer, range.startOffset);
                    const afterRange = document.createRange();
                    afterRange.selectNodeContents(main);
                    afterRange.setStart(range.endContainer, range.endOffset);
                    const sourceElement = (range.startContainer.parentElement || range.startContainer)
                      .closest && (range.startContainer.parentElement || range.startContainer).closest('[data-source-line]');
                    const payload = {
                      text: text.slice(0, 2000),
                      contextBefore: beforeRange.toString().slice(-80),
                      contextAfter: afterRange.toString().slice(0, 80),
                      startLine: Number(sourceElement ? sourceElement.dataset.sourceLine : '1'),
                      endLine: Number(sourceElement ? sourceElement.dataset.sourceLine : '1')
                    };
                    post('selectionChanged', payload);
                    if (!commentEnabled) {
                      reviewButton.hidden = true;
                      return;
                    }
                    reviewButton.dataset.selection = payload.text;
                    reviewButton.dataset.contextBefore = payload.contextBefore;
                    reviewButton.dataset.contextAfter = payload.contextAfter;
                    reviewButton.dataset.sourceLine = String(payload.startLine);
                    reviewButton.style.left = Math.max(12, Math.min(rect.right - 145, window.innerWidth - 170)) + 'px';
                    reviewButton.style.top = Math.max(8, rect.top - 38) + 'px';
                    reviewButton.hidden = false;
                  });
                }
                if (commentEnabled) {
                  reviewButton.addEventListener('click', () => {
                    const text = reviewButton.dataset.selection || '';
                    if (text) post('commentSelection', {
                      text,
                      contextBefore: reviewButton.dataset.contextBefore || '',
                      contextAfter: reviewButton.dataset.contextAfter || '',
                      startLine: Number(reviewButton.dataset.sourceLine || '1'),
                      endLine: Number(reviewButton.dataset.sourceLine || '1')
                    });
                    reviewButton.hidden = true;
                  });
                }

                const scrollBlockRegistry = (() => {
                  const root = document.getElementById('scholium-document');
                  const entries = [];
                  const byElement = new WeakMap();
                  const byExactRange = new Map();
                  if (!root) return {
                    root,
                    entries,
                    byElement,
                    byExactRange,
                    bySource: [],
                    sourcePrefixMaximumUpper: []
                  };
                  const candidates = root.querySelectorAll('[data-source-utf16-start][data-source-utf16-end]');
                  for (const element of candidates) {
                    const lower = Number(element.dataset.sourceUtf16Start);
                    const upper = Number(element.dataset.sourceUtf16End);
                    if (!Number.isFinite(lower) || !Number.isFinite(upper) || upper < lower) continue;
                    const style = getComputedStyle(element);
                    if (style.display === 'inline' || style.display === 'contents'
                        || style.display === 'none' || style.visibility === 'hidden') continue;
                    const initialRect = element.getBoundingClientRect();
                    if (initialRect.height <= 0) continue;
                    const entry = {element, lower, upper, span: Math.max(0, upper - lower)};
                    element.dataset.scholiumScrollAnchor = String(entries.length);
                    entries.push(entry);
                    byElement.set(element, entry);
                    const key = lower + ':' + upper;
                    const existing = byExactRange.get(key);
                    if (!existing || entry.span < existing.span) byExactRange.set(key, entry);
                  }
                  const bySource = entries.slice().sort((left, right) =>
                    left.lower - right.lower || left.span - right.span);
                  let maximumUpper = Number.NEGATIVE_INFINITY;
                  const sourcePrefixMaximumUpper = bySource.map(entry => {
                    maximumUpper = Math.max(maximumUpper, entry.upper);
                    return maximumUpper;
                  });
                  return {
                    root,
                    entries,
                    byElement,
                    byExactRange,
                    bySource,
                    sourcePrefixMaximumUpper
                  };
                })();

                function scrollEntryForNode(node) {
                  const root = scrollBlockRegistry.root;
                  let element = node && (node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement);
                  while (element && element !== root) {
                    const entry = scrollBlockRegistry.byElement.get(element);
                    if (entry) return entry;
                    element = element.parentElement;
                  }
                  return null;
                }

                function scrollEntryAtProbe(probe) {
                  const registry = scrollBlockRegistry;
                  if (!registry.root || !registry.entries.length) return null;
                  const rootRect = registry.root.getBoundingClientRect();
                  const probeX = Math.max(1, Math.min(window.innerWidth - 1,
                    rootRect.left + Math.max(1, rootRect.width / 2)));
                  let entry = scrollEntryForNode(document.elementFromPoint(probeX, probe));
                  if (!entry && document.caretPositionFromPoint) {
                    entry = scrollEntryForNode(document.caretPositionFromPoint(probeX, probe)?.offsetNode);
                  }
                  if (!entry && document.caretRangeFromPoint) {
                    entry = scrollEntryForNode(document.caretRangeFromPoint(probeX, probe)?.startContainer);
                  }
                  if (entry) return entry;

                  // Margins can leave the probe over the document background.
                  // A logarithmic fallback reads only a bounded set of blocks.
                  let low = 0;
                  let high = registry.entries.length - 1;
                  let nearestIndex = 0;
                  let nearestDistance = Number.POSITIVE_INFINITY;
                  while (low <= high) {
                    const index = (low + high) >> 1;
                    const candidate = registry.entries[index];
                    const rect = candidate.element.getBoundingClientRect();
                    const distance = rect.top <= probe && rect.bottom > probe
                      ? 0
                      : Math.min(Math.abs(rect.top - probe), Math.abs(rect.bottom - probe));
                    if (distance < nearestDistance) {
                      nearestDistance = distance;
                      nearestIndex = index;
                    }
                    if (rect.bottom <= probe) low = index + 1;
                    else if (rect.top > probe) high = index - 1;
                    else return candidate;
                  }
                  const start = Math.max(0, nearestIndex - 2);
                  const end = Math.min(registry.entries.length, nearestIndex + 3);
                  let nearest = registry.entries[nearestIndex];
                  for (let index = start; index < end; index += 1) {
                    const candidate = registry.entries[index];
                    const rect = candidate.element.getBoundingClientRect();
                    const distance = rect.top <= probe && rect.bottom > probe
                      ? 0
                      : Math.min(Math.abs(rect.top - probe), Math.abs(rect.bottom - probe));
                    if (distance < nearestDistance) {
                      nearestDistance = distance;
                      nearest = candidate;
                    }
                  }
                  return nearest;
                }

                function scrollEntryForAnchor(anchor) {
                  const offset = Number(anchor.sourceUTF16Offset);
                  const lower = Number(anchor.blockUTF16LowerBound);
                  const upper = Number(anchor.blockUTF16UpperBound);
                  const exact = scrollBlockRegistry.byExactRange.get(lower + ':' + upper);
                  if (exact) return exact;
                  const entries = scrollBlockRegistry.bySource;
                  let low = 0;
                  let high = entries.length;
                  while (low < high) {
                    const middle = (low + high) >> 1;
                    if (entries[middle].lower <= offset) low = middle + 1;
                    else high = middle;
                  }
                  const insertion = low;
                  let containing = null;
                  for (let index = insertion - 1;
                       index >= 0 && scrollBlockRegistry.sourcePrefixMaximumUpper[index] >= offset;
                       index -= 1) {
                    const candidate = entries[index];
                    if (candidate.lower <= offset && candidate.upper >= offset
                        && (!containing || candidate.span < containing.span)) containing = candidate;
                  }
                  if (containing) return containing;
                  const before = entries[Math.max(0, insertion - 1)];
                  const after = entries[Math.min(entries.length - 1, insertion)];
                  if (!before) return after || null;
                  if (!after) return before;
                  return Math.abs(before.lower - offset) <= Math.abs(after.lower - offset) ? before : after;
                }

                function visibleScrollEntry(entry) {
                  let candidate = entry;
                  while (candidate) {
                    if (candidate.element.getBoundingClientRect().height > 0) return candidate;
                    var parent = candidate.element.parentElement;
                    candidate = null;
                    while (parent && parent !== scrollBlockRegistry.root) {
                      const registered = scrollBlockRegistry.byElement.get(parent);
                      if (registered) {
                        candidate = registered;
                        break;
                      }
                      parent = parent.parentElement;
                    }
                  }
                  return null;
                }

                function currentReadScrollAnchor(fraction) {
                  const probe = 8;
                  const selected = scrollEntryAtProbe(probe);
                  if (!selected) return null;
                  const rect = selected.element.getBoundingClientRect();
                  const relativeBlockPosition = Math.max(0, Math.min(1,
                    (probe - rect.top) / Math.max(1, rect.height)));
                  const sourceUTF16Offset = Math.max(selected.lower, Math.min(selected.upper,
                    Math.round(selected.lower + selected.span * relativeBlockPosition)));
                  return {
                    sourceUTF16Offset,
                    blockUTF16LowerBound: selected.lower,
                    blockUTF16UpperBound: selected.upper,
                    relativeBlockPosition,
                    fallbackFraction: fraction
                  };
                }

                function restoreReadScrollAnchor(anchor) {
                  if (!anchor || typeof anchor !== 'object') return false;
                  const offset = Number(anchor.sourceUTF16Offset);
                  const lower = Number(anchor.blockUTF16LowerBound);
                  const upper = Number(anchor.blockUTF16UpperBound);
                  const relative = Number(anchor.relativeBlockPosition);
                  if (![offset, lower, upper, relative].every(Number.isFinite)) return false;
                  const target = visibleScrollEntry(scrollEntryForAnchor(anchor));
                  if (!target) return false;
                  const rect = target.element.getBoundingClientRect();
                  const height = Math.max(1, rect.height);
                  const requestedOffset = Math.max(0, Math.min(1, relative)) * height;
                  // WebKit can resolve a one-pixel boundary to the preceding
                  // block after fractional layout or font substitution. Keep
                  // the probe four CSS pixels inside the requested block so a
                  // restore-generated scroll report resolves to that block.
                  const interiorOffset = height > 8
                    ? Math.max(4, Math.min(height - 4, requestedOffset))
                    : requestedOffset;
                  const requestedTop = window.scrollY + rect.top
                    + interiorOffset - 8;
                  window.scrollTo({top: Math.max(0, requestedTop), behavior: 'auto'});
                  return true;
                }

                window.scholiumReadScroll = {
                \(readScrollTestingMembers)
                  current(fraction) { return currentReadScrollAnchor(fraction); },
                  restore(anchor) {
                    return restoreReadScrollAnchor(anchor);
                  }
                };

                var scrollTimer;
                window.addEventListener('scroll', () => {
                  clearTimeout(scrollTimer);
                  scrollTimer = setTimeout(() => {
                    const extent = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
                    const fraction = extent > 0 ? Math.max(0, Math.min(1, window.scrollY / extent)) : 0;
                    post('scrollChanged', {fraction, anchor: currentReadScrollAnchor(fraction)});
                  }, 120);
                }, {passive: true});
                // Install only after the rendered document and its event
                // handlers exist. The native side also probes this API from
                // didFinish, so a dropped early message cannot lose a query.
              })();
              </script>
            </body>
            </html>
            """
        }

        private static func jsonLiteral(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let literal = String(data: data, encoding: .utf8) else { return "\"\"" }
            return literal
        }

        private struct ReadCommentAnnotation: Encodable {
            let id: UUID
            let quotations: [String]
            let comment: String
            let resolved: Bool
            let utf16LowerBound: Int
            let utf16UpperBound: Int
            let containerUTF16LowerBound: Int
            let containerUTF16UpperBound: Int
            let relativePosition: Double
        }

        private struct ReadLinkPreview: Encodable {
            let utf16LowerBound: Int
            let utf16UpperBound: Int
            let title: String
            let relationship: String?
            let fragment: String?
            let htmlBody: String
        }

        private static func renderedSourceSpans(
            in source: String,
            relativePath: String
        ) -> [SourceSpan] {
            let document = NoteDocument(relativePath: relativePath, rawContent: source)
            let semantic = MarkdownSemanticDocument(parsing: document)
            let outerCallouts = semantic.callouts.filter { callout in
                !semantic.callouts.contains { candidate in
                    candidate.span.utf16LowerBound < callout.span.utf16LowerBound
                        && candidate.span.utf16UpperBound >= callout.span.utf16UpperBound
                }
            }
            let removedDefinitions = semantic.footnoteDefinitions.filter { !$0.isInline }
            let replacedBlockSpans = outerCallouts.map(\.span) + removedDefinitions.map(\.span)
            let ordinaryBlocks = semantic.blocks.map(\.span).filter { block in
                !replacedBlockSpans.contains { replacement in
                    replacement.utf16LowerBound <= block.utf16LowerBound
                        && replacement.utf16UpperBound >= block.utf16UpperBound
                }
            }
            let renderedLinks = semantic.links
                .filter { $0.syntax != .markdown }
                .map(\.span)
            return ordinaryBlocks
                + outerCallouts.map(\.span)
                + semantic.footnoteDefinitions.map(\.span)
                + semantic.footnoteReferences.map(\.span)
                + renderedLinks
        }

        private static func base64JSON<T: Encodable>(_ value: T) -> String {
            guard let data = try? JSONEncoder().encode(value) else { return "W10=" }
            return data.base64EncodedString()
        }

        private static func symbolDataURI(named name: String) -> String {
            guard let image = NSImage(
                systemSymbolName: name,
                accessibilityDescription: nil
            )?.withSymbolConfiguration(.init(pointSize: 18, weight: .medium)),
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:]) else {
                return ""
            }
            return "data:image/png;base64,\(data.base64EncodedString())"
        }

        static let baseCSS = """
        html, body { margin: 0; min-height: 100%; overflow-x: hidden; background: var(--scholium-color-document-background); color: var(--scholium-color-primary-text); }
        body { font-family: Alegreya, Georgia, serif; font-size: var(--scholium-document-prose-font-size); line-height: var(--scholium-rhythm-prose-line-height); }
        p { margin: var(--scholium-rhythm-paragraph-gap) 0; } a { color: LinkText; text-underline-offset: .12em; }
        .scholium-document .scholium-vector-link { display: inline; opacity: 1; visibility: visible; font-size: max(.8rem, 1em); line-height: 1.2; text-decoration: underline; text-decoration-color: color-mix(in srgb, currentColor 46%, transparent); text-underline-offset: .15em; }
        .scholium-document .scholium-vector-neutral { color: var(--scholium-color-connection-neutral); }
        .scholium-document .scholium-vector-supports-target, .scholium-document .scholium-vector-supported-by-target { color: var(--scholium-color-connection-support); }
        .scholium-document .scholium-vector-incompatible { color: var(--scholium-color-connection-incompatible); }
        .scholium-vector-icon { display: inline-block; width: .92em; height: .92em; margin-right: .24em; vertical-align: -.08em; background-color: currentColor; -webkit-mask-position: center; -webkit-mask-size: contain; -webkit-mask-repeat: no-repeat; mask-position: center; mask-size: contain; mask-repeat: no-repeat; }
        .scholium-highlight { color: CanvasText; background: Mark; border-radius: 3px; padding-inline: .06em; }
        code, pre { font-family: "Victor Mono", ui-monospace, monospace; }
        code { font-size: .82em; padding: .08em .25em; border-radius: 4px; background: color-mix(in srgb, CanvasText 8%, transparent); }
        pre { box-sizing: border-box; max-width: 100%; padding: var(--scholium-rhythm-code-inset); overflow: auto; border-radius: 10px; background: color-mix(in srgb, CanvasText 7%, transparent); }
        img, video, svg { max-width: 100%; height: auto; }
        blockquote { margin: 1em 0; padding-left: var(--scholium-rhythm-quote-inset); border-left: 3px solid color-mix(in srgb, AccentColor 50%, transparent); color: color-mix(in srgb, CanvasText 78%, transparent); }
        \(ScholiumCalloutStyles.css)
        #comment-selection { position: fixed; z-index: 110; border: 1px solid color-mix(in srgb, AccentColor 40%, transparent); border-radius: 8px; padding: 6px 10px; color: CanvasText; background: color-mix(in srgb, Canvas 92%, AccentColor 8%); box-shadow: 0 6px 20px color-mix(in srgb, CanvasText 15%, transparent); }
        .researcher-comment-annotation { color: inherit; background: color-mix(in srgb, AccentColor 18%, Mark 82%); border-bottom: 2px solid AccentColor; border-radius: 3px; cursor: pointer; }
        .researcher-comment-annotation.resolved { background: color-mix(in srgb, GrayText 9%, transparent); border-bottom-color: GrayText; }
        .researcher-comment-annotation:focus { outline: 2px solid AccentColor; outline-offset: 2px; }
        .raw-html, .raw-html-inline { color: GrayText; }
        @media (prefers-contrast: more) { .scholium-document .scholium-vector-link { text-decoration-thickness: 2px; } }
        @media (prefers-reduced-transparency: reduce) { #comment-selection { background: Canvas; backdrop-filter: none; } }
        \(ScholiumWebDesignTokens.documentPresentationCSS)
        """
    }
}
