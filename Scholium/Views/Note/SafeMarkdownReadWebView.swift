import ScholiumContracts
import AppKit
import SwiftUI
import WebKit

struct SafeMarkdownReadWebView: NSViewRepresentable {
    let documentID: String
    let fingerprint: String
    let source: String
    let htmlBody: String
    let userCSS: String
    let researcherComments: [ResearcherComment]
    let onLinkClick: (String) -> Void
    let onOpenExternalURL: (URL) -> Void
    let onCommentSelection: ((MarkdownReviewSelection) -> Void)?
    var onSelectionChange: ((MarkdownReviewSelection?) -> Void)? = nil
    let onCommentActivation: ((UUID) -> Void)?
    let onRenderingFailure: ((String) -> Void)?
    var onRenderingReady: (() -> Void)? = nil
    var initialScrollFraction: Double = 0
    var onScrollFractionChange: ((Double) -> Void)? = nil
    var targetSourceLine: Int? = nil
    var onSourceLineReached: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            documentID: documentID,
            fingerprint: fingerprint,
            onLinkClick: onLinkClick,
            onOpenExternalURL: onOpenExternalURL,
            onCommentSelection: onCommentSelection,
            onSelectionChange: onSelectionChange,
            onCommentActivation: onCommentActivation,
            onRenderingFailure: onRenderingFailure,
            onRenderingReady: onRenderingReady,
            initialScrollFraction: initialScrollFraction,
            onScrollFractionChange: onScrollFractionChange,
            targetSourceLine: targetSourceLine,
            onSourceLineReached: onSourceLineReached
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: Coordinator.messageHandlerName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityElement(true)
        webView.setAccessibilityLabel("Rendered Markdown")
        webView.setAccessibilityIdentifier("scholium.renderedDocument.loading")
        context.coordinator.loadIfNeeded(
            htmlBody,
            source: source,
            userCSS: userCSS,
            researcherComments: researcherComments,
            in: webView
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(
            documentID: documentID,
            fingerprint: fingerprint,
            onLinkClick: onLinkClick,
            onOpenExternalURL: onOpenExternalURL,
            onCommentSelection: onCommentSelection,
            onSelectionChange: onSelectionChange,
            onCommentActivation: onCommentActivation,
            onRenderingFailure: onRenderingFailure,
            onRenderingReady: onRenderingReady,
            initialScrollFraction: initialScrollFraction,
            onScrollFractionChange: onScrollFractionChange,
            targetSourceLine: targetSourceLine,
            onSourceLineReached: onSourceLineReached,
            webView: webView
        )
        context.coordinator.loadIfNeeded(
            htmlBody,
            source: source,
            userCSS: userCSS,
            researcherComments: researcherComments,
            in: webView
        )
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.messageHandlerName
        )
        webView.navigationDelegate = nil
        coordinator.activeWebView = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageHandlerName = "scholiumRead"
        private static let maximumSelectionLength = 2_000
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
        private var onRenderingReady: (() -> Void)?
        private var initialScrollFraction: Double
        private var onScrollFractionChange: ((Double) -> Void)?
        private var targetSourceLine: Int?
        private var onSourceLineReached: (() -> Void)?
        private var lastReachedSourceLine: Int?
        private var loadedSignature: String?
        private var pageIsReady = false
        weak var activeWebView: WKWebView?

        init(
            documentID: String,
            fingerprint: String,
            onLinkClick: @escaping (String) -> Void,
            onOpenExternalURL: @escaping (URL) -> Void,
            onCommentSelection: ((MarkdownReviewSelection) -> Void)?,
            onSelectionChange: ((MarkdownReviewSelection?) -> Void)?,
            onCommentActivation: ((UUID) -> Void)?,
            onRenderingFailure: ((String) -> Void)?,
            onRenderingReady: (() -> Void)?,
            initialScrollFraction: Double,
            onScrollFractionChange: ((Double) -> Void)?,
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
            self.onRenderingReady = onRenderingReady
            self.initialScrollFraction = min(1, max(0, initialScrollFraction))
            self.onScrollFractionChange = onScrollFractionChange
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
            onRenderingReady: (() -> Void)?,
            initialScrollFraction: Double,
            onScrollFractionChange: ((Double) -> Void)?,
            targetSourceLine: Int?,
            onSourceLineReached: (() -> Void)?,
            webView: WKWebView
        ) {
            if self.documentID != documentID || self.fingerprint != fingerprint {
                loadedSignature = nil
                lastReachedSourceLine = nil
                pageIsReady = false
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
            self.onRenderingReady = onRenderingReady
            self.initialScrollFraction = min(1, max(0, initialScrollFraction))
            self.onScrollFractionChange = onScrollFractionChange
            self.targetSourceLine = targetSourceLine
            self.onSourceLineReached = onSourceLineReached
            scrollToSourceLineIfNeeded(in: webView)
        }

        func loadIfNeeded(
            _ body: String,
            source: String,
            userCSS: String,
            researcherComments: [ResearcherComment],
            in webView: WKWebView
        ) {
            let contentSignature = String(body.utf8.count)
            let cssSignature = String(userCSS.hashValue)
            let commentSignature = String(researcherComments.hashValue)
            let capabilitySignature = "\(onCommentSelection != nil):\(onSelectionChange != nil)"
            let signature = [
                fingerprint,
                contentSignature,
                cssSignature,
                commentSignature,
                capabilitySignature,
            ]
                .joined(separator: ":")
            guard loadedSignature != signature else { return }
            loadedSignature = signature
            pageIsReady = false
            activeWebView = webView
            webView.loadHTMLString(
                Self.documentHTML(
                    body: body,
                    source: source,
                    documentID: documentID,
                    fingerprint: fingerprint,
                    commentEnabled: onCommentSelection != nil,
                    selectionEnabled: onSelectionChange != nil,
                    researcherComments: researcherComments,
                    userCSS: userCSS
                ),
                baseURL: nil
            )
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
                guard let fraction = payload["fraction"] as? Double,
                      fraction.isFinite,
                      (0...1).contains(fraction) else { return }
                onScrollFractionChange?(fraction)
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
            pageIsReady = true
            restoreScrollPosition(in: webView)
            scrollToSourceLineIfNeeded(in: webView)
            let expectedDocumentID = documentID
            let expectedFingerprint = fingerprint
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                do {
                    let result = try await webView.callAsyncJavaScript(
                        """
                        await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
                        return true;
                        """,
                        arguments: [:],
                        in: nil,
                        contentWorld: .page
                    )
                    guard result as? Bool == true,
                          self.activeWebView === webView,
                          self.documentID == expectedDocumentID,
                          self.fingerprint == expectedFingerprint else { return }
                    webView.setAccessibilityIdentifier(
                        "scholium.renderedDocument.\(expectedDocumentID)"
                    )
                    self.onRenderingReady?()
                } catch {
                    return
                }
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            pageIsReady = false
            loadedSignature = nil
            webView.setAccessibilityIdentifier("scholium.renderedDocument.failed")
            onRenderingFailure?("The Read renderer stopped unexpectedly.")
        }

        private func restoreScrollPosition(in webView: WKWebView) {
            let fraction = min(1, max(0, initialScrollFraction))
            webView.evaluateJavaScript("window.scrollTo(0, Math.max(0, document.documentElement.scrollHeight - window.innerHeight) * \(fraction));")
        }

        private func scrollToSourceLineIfNeeded(in webView: WKWebView) {
            guard let line = targetSourceLine, line > 0, line != lastReachedSourceLine else { return }
            let script = """
            (() => {
              const requested = \(line);
              const items = Array.from(document.querySelectorAll('[data-source-line]'));
              let target = items.find(item => Number(item.dataset.sourceLine) === requested);
              if (!target) {
                target = items.filter(item => Number(item.dataset.sourceLine) <= requested).pop() || items[0];
              }
              if (!target) return false;
              target.scrollIntoView({block:'start', behavior:'auto'});
              target.tabIndex = -1;
              target.focus({preventScroll:true});
              return true;
            })();
            """
            webView.evaluateJavaScript(script) { [weak self] value, _ in
                guard value as? Bool == true else { return }
                self?.lastReachedSourceLine = line
                self?.onSourceLineReached?()
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: any Error
        ) {
            onRenderingFailure?(error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
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

        private static func documentHTML(
            body: String,
            source: String,
            documentID: String,
            fingerprint: String,
            commentEnabled: Bool,
            selectionEnabled: Bool,
            researcherComments: [ResearcherComment],
            userCSS: String
        ) -> String {
            let encodedDocumentID = jsonLiteral(documentID)
            let encodedFingerprint = jsonLiteral(fingerprint)
            let commentFlag = commentEnabled ? "true" : "false"
            let selectionFlag = selectionEnabled ? "true" : "false"
            let noteDocument = NoteDocument(relativePath: documentID, rawContent: source)
            let renderedSpans = renderedSourceSpans(in: source, relativePath: documentID)
            let sourceLength = (source as NSString).length
            let annotations: [ReadCommentAnnotation] = researcherComments.compactMap { comment in
                guard let anchor = comment.anchor,
                      anchor.state == .attached,
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
            return """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:; connect-src 'none'; font-src data:">
              <style>\(ScholiumWebFonts.css)\n\(baseCSS)</style>
              <style id="scholium-user-css">\(userCSS)</style>
            </head>
            <body>
              <main id="scholium-document" class="scholium-document">\(body)</main>
              <div id="footnote-popover" role="tooltip" hidden></div>
              <button id="comment-selection" type="button" hidden>Add Comment</button>
              <script>
              (() => {
                'use strict';
                const version = 1;
                const documentID = \(encodedDocumentID);
                const fingerprint = \(encodedFingerprint);
                const commentEnabled = \(commentFlag);
                const selectionEnabled = \(selectionFlag);
                const commentAnnotations = JSON.parse(new TextDecoder().decode(
                  Uint8Array.from(atob(\(jsonLiteral(annotationPayload))), character => character.charCodeAt(0))
                ));
                const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(messageHandlerName);
                const post = (type, extra = {}) => handler && handler.postMessage({version, documentID, fingerprint, type, ...extra});
                const popover = document.getElementById('footnote-popover');
                const reviewButton = document.getElementById('comment-selection');
                const origins = new Map();
                const vectorSemantics = {
                  neutral: {label: 'Related note', symbol: \(jsonLiteral(vectorSymbolDataURIs["link"] ?? ""))},
                  supports_target: {label: 'Supports', symbol: \(jsonLiteral(vectorSymbolDataURIs["arrow.right.circle"] ?? ""))},
                  supported_by_target: {label: 'Supported by', symbol: \(jsonLiteral(vectorSymbolDataURIs["arrow.left.circle"] ?? ""))},
                  incompatible: {label: 'Incompatible with', symbol: \(jsonLiteral(vectorSymbolDataURIs["xmark.circle"] ?? ""))}
                };

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
                  popover.replaceChildren();
                }

                function showPopover(button) {
                  const ordinal = button.dataset.footnote;
                  const definition = document.getElementById('fn-' + ordinal);
                  const content = definition && definition.querySelector('.footnote-content');
                  if (!content) return;
                  popover.replaceChildren(content.cloneNode(true));
                  const rect = button.getBoundingClientRect();
                  popover.style.left = Math.max(16, Math.min(rect.left, window.innerWidth - 376)) + 'px';
                  popover.style.top = Math.min(window.innerHeight - 180, rect.bottom + 8) + 'px';
                  popover.hidden = false;
                }

                document.addEventListener('pointerover', event => {
                  const button = event.target.closest && event.target.closest('.footnote-reference');
                  if (button) showPopover(button);
                });
                document.addEventListener('focusin', event => {
                  const button = event.target.closest && event.target.closest('.footnote-reference');
                  if (button) showPopover(button);
                });
                document.addEventListener('pointerout', event => {
                  if (event.target.closest && event.target.closest('.footnote-reference')) hidePopover();
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

                var scrollTimer;
                window.addEventListener('scroll', () => {
                  clearTimeout(scrollTimer);
                  scrollTimer = setTimeout(() => {
                    const extent = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
                    const fraction = extent > 0 ? Math.max(0, Math.min(1, window.scrollY / extent)) : 0;
                    post('scrollChanged', {fraction});
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

        private static let baseCSS = """
        :root { color-scheme: light dark; \(ScholiumWebDesignTokens.rootCSSDeclarations) }
        html, body { margin: 0; min-height: 100%; overflow-x: hidden; background: var(--scholium-color-document-background); color: var(--scholium-color-primary-text); }
        body { font-family: Alegreya, Georgia, serif; font-size: 12pt; line-height: 1.58; }
        .scholium-document { box-sizing: border-box; min-width: 0; max-width: 920px; margin: 0 auto; padding: 44px 54px 45vh; overflow-wrap: anywhere; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.18; margin: 1.45em 0 .55em; text-wrap: balance; }
        h1 { font-size: 150%; } h2 { font-size: 130%; } h3 { font-size: 115%; } h4, h5, h6 { font-size: 100%; }
        p { margin: .7em 0; } a { color: LinkText; text-underline-offset: .12em; }
        .scholium-document .scholium-vector-link { display: inline; opacity: 1; visibility: visible; font-size: max(.8rem, 1em); line-height: 1.2; text-decoration: underline; text-decoration-color: color-mix(in srgb, currentColor 46%, transparent); text-underline-offset: .15em; }
        .scholium-document .scholium-vector-neutral { color: var(--scholium-color-connection-neutral); }
        .scholium-document .scholium-vector-supports-target, .scholium-document .scholium-vector-supported-by-target { color: var(--scholium-color-connection-support); }
        .scholium-document .scholium-vector-incompatible { color: var(--scholium-color-connection-incompatible); }
        .scholium-vector-icon { display: inline-block; width: .92em; height: .92em; margin-right: .24em; vertical-align: -.08em; background-color: currentColor; -webkit-mask-position: center; -webkit-mask-size: contain; -webkit-mask-repeat: no-repeat; mask-position: center; mask-size: contain; mask-repeat: no-repeat; }
        .scholium-highlight { color: CanvasText; background: Mark; border-radius: 3px; padding-inline: .06em; }
        code, pre { font-family: "Victor Mono", ui-monospace, monospace; }
        code { font-size: .82em; padding: .08em .25em; border-radius: 4px; background: color-mix(in srgb, CanvasText 8%, transparent); }
        pre { box-sizing: border-box; max-width: 100%; padding: 16px; overflow: auto; border-radius: 10px; background: color-mix(in srgb, CanvasText 7%, transparent); }
        img, video, svg { max-width: 100%; height: auto; }
        table { display: block; max-width: 100%; overflow-x: auto; }
        blockquote { margin: 1em 0; padding-left: 18px; border-left: 3px solid color-mix(in srgb, AccentColor 50%, transparent); color: color-mix(in srgb, CanvasText 78%, transparent); }
        (ScholiumCalloutStyles.css)
        .footnote-reference { appearance: none; border: 0; padding: 0 .1em; background: none; color: LinkText; font: 700 .65em system-ui; cursor: pointer; }
        .footnotes { margin-top: 3em; font-size: .86em; }
        .footnotes li { position: relative; padding-right: 2.5em; }
        .footnote-content > :first-child { margin-top: 0; }
        .footnote-return { position: absolute; right: 0; top: 0; border: 0; border-radius: 6px; color: LinkText; background: color-mix(in srgb, LinkText 9%, transparent); cursor: pointer; }
        #footnote-popover { position: fixed; z-index: 100; width: min(340px, calc(100vw - 32px)); max-height: 190px; overflow: auto; padding: 12px 16px; border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); border-radius: 12px; background: color-mix(in srgb, Canvas 94%, transparent); box-shadow: 0 12px 36px color-mix(in srgb, CanvasText 20%, transparent); backdrop-filter: blur(20px); font-size: 16px; }
        #comment-selection { position: fixed; z-index: 110; border: 1px solid color-mix(in srgb, AccentColor 40%, transparent); border-radius: 8px; padding: 6px 10px; color: CanvasText; background: color-mix(in srgb, Canvas 92%, AccentColor 8%); box-shadow: 0 6px 20px color-mix(in srgb, CanvasText 15%, transparent); }
        .researcher-comment-annotation { color: inherit; background: color-mix(in srgb, AccentColor 18%, Mark 82%); border-bottom: 2px solid AccentColor; border-radius: 3px; cursor: pointer; }
        .researcher-comment-annotation.resolved { background: color-mix(in srgb, GrayText 9%, transparent); border-bottom-color: GrayText; }
        .researcher-comment-annotation:focus { outline: 2px solid AccentColor; outline-offset: 2px; }
        .raw-html, .raw-html-inline { color: GrayText; }
        @media (prefers-color-scheme: dark) { :root { \(ScholiumWebDesignTokens.darkAppearanceCSSDeclarations) } }
        @media (prefers-contrast: more) { :root { \(ScholiumWebDesignTokens.increasedContrastCSSDeclarations) } .scholium-document .scholium-vector-link { text-decoration-thickness: 2px; } }
        @media (prefers-color-scheme: dark) and (prefers-contrast: more) { :root { \(ScholiumWebDesignTokens.darkIncreasedContrastCSSDeclarations) } }
        @media (max-width: 700px) { .scholium-document { padding: 28px 24px 45vh; } }
        @media (prefers-reduced-transparency: reduce) { #footnote-popover, #comment-selection { background: Canvas; backdrop-filter: none; } }
        """
    }
}
