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
    /// preview payloads during unrelated SwiftUI updates.
    var configurationRevision: String? = nil
    var linkPreviews: [DocumentLinkPreview] = []
    let onLinkClick: (String) -> Void
    let onOpenExternalURL: (URL) -> Void
    /// A lightweight researcher Comment saved into the active Discussion.
    var onCommentSelection: ((PassageCommentSubmission) -> Void)? = nil
    var commentComposerRequestID: UUID? = nil
    var commentResolution: PassageCommentResolution? = nil
    var onSelectionChange: ((MarkdownReviewSelection?) -> Void)? = nil
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
            commentComposerRequestID: commentComposerRequestID,
            commentResolution: commentResolution,
            onSelectionChange: onSelectionChange,
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
            commentComposerRequestID: commentComposerRequestID,
            commentResolution: commentResolution,
            onSelectionChange: onSelectionChange,
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
                "link", "plus.circle", "minus.circle",
            ].map { ($0, symbolDataURI(named: $0)) }
                + [("incompatible", incompatibleVectorSymbolDataURI)]
        )
        private static let incompatibleVectorSymbolDataURI: String = {
            let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
              <path d="M3.1 10.1c2.5-.2 4.5-.1 6.1.1L10 7.1M16.9 10.1c-2.5-.2-4.5-.1-6.1.1L10 13.1" fill="none" stroke="black" stroke-width="1.45" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
            """
            return "data:image/svg+xml;base64,\(Data(svg.utf8).base64EncodedString())"
        }()

        private var documentID: String
        private var fingerprint: String
        private var onLinkClick: (String) -> Void
        private var onOpenExternalURL: (URL) -> Void
        private var onCommentSelection: ((PassageCommentSubmission) -> Void)?
        private var commentComposerRequestID: UUID?
        private var commentResolution: PassageCommentResolution?
        private var onSelectionChange: ((MarkdownReviewSelection?) -> Void)?
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
        private var sourceUTF8Length = 0
        private var source = ""
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
            onCommentSelection: ((PassageCommentSubmission) -> Void)?,
            commentComposerRequestID: UUID?,
            commentResolution: PassageCommentResolution?,
            onSelectionChange: ((MarkdownReviewSelection?) -> Void)?,
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
            self.commentComposerRequestID = commentComposerRequestID
            self.commentResolution = commentResolution
            self.onSelectionChange = onSelectionChange
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
            onCommentSelection: ((PassageCommentSubmission) -> Void)?,
            commentComposerRequestID: UUID?,
            commentResolution: PassageCommentResolution?,
            onSelectionChange: ((MarkdownReviewSelection?) -> Void)?,
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
            requestCommentComposerIfNeeded(commentComposerRequestID, in: webView)
            resolveCommentIfNeeded(commentResolution, in: webView)
        }

        private func requestCommentComposerIfNeeded(_ requestID: UUID?, in webView: WKWebView) {
            guard let requestID, requestID != commentComposerRequestID else { return }
            commentComposerRequestID = requestID
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView, self.activeWebView === webView else { return }
                _ = try? await webView.callAsyncJavaScript(
                    "return window.scholiumShowCommentComposer?.() === true",
                    arguments: [:],
                    in: nil,
                    contentWorld: .page
                )
            }
        }

        private func resolveCommentIfNeeded(
            _ resolution: PassageCommentResolution?,
            in webView: WKWebView
        ) {
            guard let resolution, resolution != commentResolution else { return }
            commentResolution = resolution
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView, self.activeWebView === webView else { return }
                _ = try? await webView.callAsyncJavaScript(
                    "return window.scholiumResolveCommentSubmission?.(requestID, succeeded) === true",
                    arguments: [
                        "requestID": resolution.requestID,
                        "succeeded": resolution.succeeded,
                    ],
                    in: nil,
                    contentWorld: .page
                )
            }
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
                String(linkPreviews.hashValue),
                capabilitySignature,
            ].joined(separator: ":")
            guard loadedSignature != signature else { return }
            self.source = source
            sourceUTF16Length = source.utf16.count
            sourceUTF8Length = source.utf8.count
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
            case "commentSubmitted":
                guard let requestID = payload["requestID"] as? String,
                      !requestID.isEmpty else { return }
                guard let comment = payload["comment"] as? String,
                      !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      comment.utf8.count <= 16_384,
                      let selection = reviewSelection(from: payload),
                      let anchor = ResearchFunctionSelectionCapture.anchor(
                          for: selection,
                          in: source,
                          relativePath: documentID
                      ) else {
                    if let activeWebView {
                        resolveCommentIfNeeded(
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
                    startLine: anchor.line,
                    endLine: anchor.endLine,
                    text: comment
                ))
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
            let qaCommentSubmitControl = Bundle.main.bundleIdentifier == "com.scholium.qa"
                ? #"<button id="qa-submit-comment" class="scholium-qa-only-control" type="button">Submit Comment for QA</button>"#
                : ""
            #else
            let readScrollTestingMembers = ""
            let qaCommentSubmitControl = ""
            #endif
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
              <div id="selection-actions" class="scholium-selection-actions" hidden>
                <div id="selection-toolbar" class="scholium-selection-toolbar" role="toolbar" aria-label="Selection actions">
                  <button id="comment-selection" type="button">Comment</button>
                </div>
                <div id="comment-composer" hidden>
                  <textarea id="comment-text" rows="2" maxlength="16384" aria-label="Comment" aria-describedby="comment-help"></textarea>
                  <span id="comment-help">Return saves. Shift-Return inserts a line. Escape cancels.</span>
                  \(qaCommentSubmitControl)
                </div>
              </div>
              <script>
              (() => {
                'use strict';
                const version = 1;
                const documentID = \(encodedDocumentID);
                const fingerprint = \(encodedFingerprint);
                const loadGeneration = \(loadGeneration);
                const commentEnabled = \(commentFlag);
                const selectionEnabled = \(selectionFlag);
                const linkPreviews = JSON.parse(new TextDecoder().decode(
                  Uint8Array.from(atob(\(jsonLiteral(previewPayload))), character => character.charCodeAt(0))
                ));
                const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(messageHandlerName);
                const post = (type, extra = {}) => handler && handler.postMessage({version, documentID, fingerprint, loadGeneration, type, ...extra});
                const popover = document.getElementById('scholium-preview-popover');
                const previewTitle = popover.querySelector('.scholium-preview-title');
                const previewMetadata = popover.querySelector('.scholium-preview-metadata');
                const previewBody = popover.querySelector('.scholium-preview-body');
                const selectionActions = document.getElementById('selection-actions');
                const selectionToolbar = document.getElementById('selection-toolbar');
                const commentButton = document.getElementById('comment-selection');
                const commentComposer = document.getElementById('comment-composer');
                const commentText = document.getElementById('comment-text');
                const commentHelp = document.getElementById('comment-help');
                const qaCommentSubmit = document.getElementById('qa-submit-comment');
                let pendingCommentRequestID = null;
                let commentAnchorElement = null;
                let commentSelectionRange = null;
                const previewByRange = new Map(linkPreviews.map(preview => [
                  preview.utf16LowerBound + ':' + preview.utf16UpperBound,
                  preview
                ]));
                const origins = new Map();
                const vectorSemantics = {
                  neutral: {label: 'Related note', symbol: \(jsonLiteral(vectorSymbolDataURIs["link"] ?? ""))},
                  supports: {label: 'Supports', symbol: \(jsonLiteral(vectorSymbolDataURIs["plus.circle"] ?? ""))},
                  opposes: {label: 'Opposes', symbol: \(jsonLiteral(vectorSymbolDataURIs["minus.circle"] ?? ""))},
                  incompatible: {label: 'Incompatible', symbol: \(jsonLiteral(vectorSymbolDataURIs["incompatible"] ?? ""))}
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
                    + (preview.fragment ? ', ' + preview.fragment : '');
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
                  const reference = event.target.closest && event.target.closest('.footnote-reference');
                  if (reference && !reference.disabled) {
                    const ordinal = reference.dataset.footnote;
                    const target = document.getElementById(reference.dataset.target);
                    if (target) {
                      const origin = reference.closest('.footnote-reference-wrap') || reference;
                      origins.set(ordinal, origin.id);
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
                      const focusTarget = origin.matches('.footnote-reference')
                        ? origin
                        : origin.querySelector('.footnote-reference');
                      origin.scrollIntoView({block: 'center', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth'});
                      (focusTarget || origin).focus({preventScroll: true});
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
                  if (event.key === 'Escape') {
                    hidePopover();
                    if (!commentComposer.hidden) return;
                    commentComposer.hidden = true;
                    selectionToolbar.hidden = false;
                    commentText.value = '';
                    selectionActions.hidden = true;
                  }
                });

                function showCommentComposer() {
                  if (!commentEnabled || selectionActions.hidden || !commentButton.dataset.startLine) return false;
                  const startLine = Number(commentButton.dataset.startLine);
                  const endLine = Number(commentButton.dataset.endLine || commentButton.dataset.startLine);
                  const lineLabel = startLine === endLine
                    ? 'line ' + startLine
                    : 'lines ' + startLine + ' through ' + endLine;
                  commentText.setAttribute('aria-label', 'Comment for ' + lineLabel);
                  selectionToolbar.hidden = true;
                  commentComposer.hidden = false;
                  const measured = selectionActions.getBoundingClientRect();
                  const anchorLeft = Number(commentButton.dataset.anchorLeft || '12');
                  const anchorTop = Number(commentButton.dataset.anchorTop || '12');
                  selectionActions.style.left = Math.max(12, Math.min(anchorLeft, window.innerWidth - measured.width - 12)) + 'px';
                  selectionActions.style.top = Math.max(8, Math.min(anchorTop, window.innerHeight - measured.height - 12)) + 'px';
                  commentText.focus();
                  return true;
                }
                window.scholiumShowCommentComposer = showCommentComposer;

                function restoreCommentFocus() {
                  if (!commentAnchorElement) return;
                  commentAnchorElement.tabIndex = -1;
                  commentAnchorElement.focus({preventScroll: true});
                  if (commentSelectionRange) {
                    const selection = window.getSelection();
                    selection.removeAllRanges();
                    selection.addRange(commentSelectionRange);
                  }
                }

                window.scholiumResolveCommentSubmission = (requestID, succeeded) => {
                  if (!pendingCommentRequestID || requestID !== pendingCommentRequestID) return false;
                  pendingCommentRequestID = null;
                  commentText.disabled = false;
                  if (!succeeded) {
                    commentHelp.textContent = 'Could not save. Your Comment is still here.';
                    commentText.focus();
                    return true;
                  }
                  commentText.value = '';
                  commentHelp.textContent = 'Return saves. Shift-Return inserts a line. Escape cancels.';
                  commentComposer.hidden = true;
                  selectionToolbar.hidden = false;
                  selectionActions.hidden = true;
                  restoreCommentFocus();
                  return true;
                };

                if (selectionEnabled) {
                  const updateSelectionActions = () => {
                    // Focusing the Comment textarea collapses the document
                    // selection. Keep the anchored composer stable until the
                    // researcher saves or cancels it; that focus transition is
                    // not a request to discard the marginal note.
                    if (!commentComposer.hidden) return;
                    const selection = window.getSelection();
                    const text = selection ? selection.toString().trim() : '';
                    if (!text) {
                      commentSelectionRange = null;
                      selectionActions.hidden = true;
                      post('selectionChanged');
                      return;
                    }
                    const range = selection.getRangeAt(0);
                    const main = document.getElementById('scholium-document');
                    if (!main || !main.contains(range.startContainer) || !main.contains(range.endContainer)) {
                      commentSelectionRange = null;
                      selectionActions.hidden = true;
                      post('selectionChanged');
                      return;
                    }
                    const rect = range.getBoundingClientRect();
                    commentSelectionRange = range.cloneRange();
                    const beforeRange = document.createRange();
                    beforeRange.selectNodeContents(main);
                    beforeRange.setEnd(range.startContainer, range.startOffset);
                    const afterRange = document.createRange();
                    afterRange.selectNodeContents(main);
                    afterRange.setStart(range.endContainer, range.endOffset);
                    const sourceElement = (range.startContainer.parentElement || range.startContainer)
                      .closest && (range.startContainer.parentElement || range.startContainer).closest('[data-source-line]');
                    const endSourceElement = (range.endContainer.parentElement || range.endContainer)
                      .closest && (range.endContainer.parentElement || range.endContainer).closest('[data-source-line]');
                    const startLine = Number(sourceElement ? sourceElement.dataset.sourceLine : '1');
                    const endLine = Number(endSourceElement ? endSourceElement.dataset.sourceLine : String(startLine));
                    const payload = {
                      text: text.slice(0, 2000),
                      contextBefore: beforeRange.toString().slice(-80),
                      contextAfter: afterRange.toString().slice(0, 80),
                      startLine: Math.min(startLine, endLine),
                      endLine: Math.max(startLine, endLine)
                    };
                    post('selectionChanged', payload);
                    if (!commentEnabled) {
                      selectionActions.hidden = true;
                      return;
                    }
                    commentButton.dataset.startLine = String(payload.startLine);
                    commentButton.dataset.endLine = String(payload.endLine);
                    commentButton.dataset.selection = payload.text;
                    commentButton.dataset.contextBefore = payload.contextBefore;
                    commentButton.dataset.contextAfter = payload.contextAfter;
                    commentButton.dataset.anchorLeft = String(rect.left);
                    commentButton.dataset.anchorTop = String(rect.top - 38);
                    commentAnchorElement = sourceElement;
                    commentButton.hidden = !commentEnabled;
                    selectionActions.style.left = Math.max(12, Math.min(rect.right - 175, window.innerWidth - 200)) + 'px';
                    selectionActions.style.top = Math.max(8, rect.top - 38) + 'px';
                    selectionActions.hidden = false;
                  };
                  document.addEventListener('selectionchange', updateSelectionActions);
                  window.addEventListener('blur', () => {
                    if (commentComposer.hidden) selectionActions.hidden = true;
                  });
                }
                if (commentEnabled) {
                  // Keep the document selection alive through the button's
                  // pointer-down. The subsequent click owns the deliberate
                  // transition from the compact bar to the anchored field.
                  commentButton.addEventListener('mousedown', event => event.preventDefault());
                  commentButton.addEventListener('click', showCommentComposer);
                  let preservesNextInsertedLineBreak = false;
                  const makeRequestID = () => {
                    if (globalThis.crypto && typeof globalThis.crypto.randomUUID === 'function') {
                      return globalThis.crypto.randomUUID();
                    }
                    const bytes = new Uint8Array(16);
                    if (globalThis.crypto && typeof globalThis.crypto.getRandomValues === 'function') {
                      globalThis.crypto.getRandomValues(bytes);
                    } else {
                      for (let index = 0; index < bytes.length; index += 1) {
                        bytes[index] = Math.floor(Math.random() * 256);
                      }
                    }
                    bytes[6] = (bytes[6] & 0x0f) | 0x40;
                    bytes[8] = (bytes[8] & 0x3f) | 0x80;
                    const hex = Array.from(bytes, byte => byte.toString(16).padStart(2, '0'));
                    return hex.slice(0, 4).join('') + '-' + hex.slice(4, 6).join('') + '-'
                      + hex.slice(6, 8).join('') + '-' + hex.slice(8, 10).join('') + '-'
                      + hex.slice(10, 16).join('');
                  };
                  const submitComment = () => {
                    const comment = commentText.value.trim();
                    if (!comment || pendingCommentRequestID) return;
                    if (new TextEncoder().encode(comment).byteLength > 16384) {
                      commentHelp.textContent = 'This Comment is too long to save here.';
                      return;
                    }
                    pendingCommentRequestID = makeRequestID();
                    commentText.disabled = true;
                    commentHelp.textContent = 'Saving…';
                    post('commentSubmitted', {
                      requestID: pendingCommentRequestID,
                      comment,
                      text: commentButton.dataset.selection || '',
                      contextBefore: commentButton.dataset.contextBefore || '',
                      contextAfter: commentButton.dataset.contextAfter || '',
                      startLine: Number(commentButton.dataset.startLine || '1'),
                      endLine: Number(commentButton.dataset.endLine || commentButton.dataset.startLine || '1')
                    });
                  };
                  qaCommentSubmit && qaCommentSubmit.addEventListener('click', submitComment);
                  commentText.addEventListener('keydown', event => {
                    if (event.key === 'Escape') {
                      event.preventDefault();
                      event.stopPropagation();
                      if (pendingCommentRequestID) return;
                      commentText.value = '';
                      commentHelp.textContent = 'Return saves. Shift-Return inserts a line. Escape cancels.';
                      commentComposer.hidden = true;
                      selectionToolbar.hidden = false;
                      selectionActions.hidden = true;
                      restoreCommentFocus();
                      return;
                    }
                    const isReturn = event.key === 'Enter'
                      || event.key === 'Return'
                      || event.code === 'Enter'
                      || event.code === 'NumpadEnter';
                    if (!isReturn || event.isComposing) return;
                    if (event.shiftKey) {
                      preservesNextInsertedLineBreak = true;
                      setTimeout(() => { preservesNextInsertedLineBreak = false; }, 0);
                      return;
                    }
                    event.preventDefault();
                    submitComment();
                  });
                  // Accessibility text insertion can bypass DOM keydown while
                  // still producing an InputEvent whose type is insertText.
                  // Treat only an actually inserted line break as Return-to-save;
                  // a real Shift-Return marks exactly its following input as prose.
                  commentText.addEventListener('input', event => {
                    const insertedLineBreak = event.inputType === 'insertLineBreak'
                      || event.inputType === 'insertParagraph'
                      || (event.inputType === 'insertText'
                        && ((typeof event.data === 'string' && /[\\r\\n]/.test(event.data))
                          || /[\\r\\n]$/.test(commentText.value)));
                    if (!insertedLineBreak) return;
                    if (preservesNextInsertedLineBreak) {
                      preservesNextInsertedLineBreak = false;
                      return;
                    }
                    submitComment();
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

        private struct ReadLinkPreview: Encodable {
            let utf16LowerBound: Int
            let utf16UpperBound: Int
            let title: String
            let relationship: String?
            let fragment: String?
            let htmlBody: String
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
        .scholium-document .scholium-vector-supports { color: var(--scholium-color-connection-support); }
        .scholium-document .scholium-vector-opposes { color: var(--scholium-color-connection-incompatible); }
        .scholium-document .scholium-vector-incompatible { color: var(--scholium-color-connection-incompatible); }
        .scholium-vector-icon { display: inline-block; width: .92em; height: .92em; margin-right: .24em; vertical-align: -.08em; background-color: currentColor; -webkit-mask-position: center; -webkit-mask-size: contain; -webkit-mask-repeat: no-repeat; mask-position: center; mask-size: contain; mask-repeat: no-repeat; }
        .scholium-highlight { color: CanvasText; background: Mark; border-radius: 3px; padding-inline: .06em; }
        code, pre { font-family: "Victor Mono", ui-monospace, monospace; }
        code { font-size: .82em; padding: .08em .25em; border-radius: 4px; background: color-mix(in srgb, CanvasText 8%, transparent); }
        pre { box-sizing: border-box; max-width: 100%; padding: var(--scholium-rhythm-code-inset); overflow: auto; border-radius: 10px; background: color-mix(in srgb, CanvasText 7%, transparent); }
        img, video, svg { max-width: 100%; height: auto; }
        blockquote { margin: 1em 0; padding-left: var(--scholium-rhythm-quote-inset); border-left: 3px solid var(--scholium-color-accent); color: color-mix(in srgb, CanvasText 78%, transparent); }
        \(ScholiumCalloutStyles.css)
        #comment-composer { display: grid; gap: 4px; width: min(320px, calc(100vw - 32px)); }
        #comment-composer[hidden], #selection-toolbar[hidden] { display: none; }
        #comment-text { box-sizing: border-box; width: 100%; min-height: 58px; max-height: 132px; resize: vertical; padding: 7px 8px; border: 1px solid var(--scholium-color-separator); border-radius: 5px; color: var(--scholium-color-primary-text); background: var(--scholium-color-document-background); font: 13px/1.35 -apple-system, BlinkMacSystemFont, sans-serif; }
        #comment-text:focus-visible { outline: 2px solid var(--scholium-color-accent); outline-offset: 1px; }
        #comment-help { color: var(--scholium-color-muted-text); font: 11px/1.25 -apple-system, BlinkMacSystemFont, sans-serif; }
        .scholium-qa-only-control { justify-self: end; font: 10px -apple-system, BlinkMacSystemFont, sans-serif; }
        .raw-html, .raw-html-inline { color: GrayText; }
        @media (prefers-contrast: more) { .scholium-document .scholium-vector-link { text-decoration-thickness: 2px; } }
        \(ScholiumWebDesignTokens.documentPresentationCSS)
        """
    }
}
