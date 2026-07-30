import ScholiumContracts
import AppKit
import SwiftUI
import WebKit

struct MarkdownEditorWebView: NSViewRepresentable {
    @ObservedObject var session: MarkdownEditorSession
    let documentID: String
    let source: String
    let mode: MarkdownEditorMode
    let presentationCSS: String
    let userCSS: String
    let linkCompletionQuery: @MainActor (String) async -> [EditorLinkCompletion]
    let linkPreviews: [DocumentLinkPreview]
    let initialScrollFraction: Double
    let initialScrollAnchor: EditorScrollAnchor?
    let onDocumentChange: (String) -> Void
    let onRequestSave: () -> Void
    let onRequestSearch: () -> Void
    let onLinkActivation: (String) -> Void
    let onScrollFractionChange: (Double) -> Void
    let onScrollAnchorChange: (EditorScrollAnchor) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            session: session,
            onDocumentChange: onDocumentChange,
            onRequestSave: onRequestSave,
            onRequestSearch: onRequestSearch,
            linkCompletionQuery: linkCompletionQuery,
            onLinkActivation: onLinkActivation,
            onScrollFractionChange: onScrollFractionChange,
            onScrollAnchorChange: onScrollAnchorChange
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "scholium")
        contentController.addUserScript(WKUserScript(
            source: """
            window.addEventListener('error', function(event) {
                window.webkit.messageHandlers.scholium.postMessage({
                    type: 'editorError',
                    message: event.message || 'The Markdown editor could not start.'
                });
            });
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        if !ScholiumMathAssets.runtimeJavaScript.isEmpty {
            contentController.addUserScript(WKUserScript(
                source: ScholiumMathAssets.runtimeJavaScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        if let editorScript = Self.editorScript {
            contentController.addUserScript(WKUserScript(
                source: editorScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
        }
        contentController.addUserScript(WKUserScript(
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
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WindowAttachedWebView(frame: .zero, configuration: configuration)
        webView.editorSession = session
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.documentID = documentID
        context.coordinator.source = source
        context.coordinator.startingFingerprint = DocumentFingerprint(content: source).sha256
        context.coordinator.lastModeInput = mode
        context.coordinator.presentationCSS = presentationCSS
        context.coordinator.userCSS = userCSS
        context.coordinator.linkPreviews = linkPreviews
        context.coordinator.initialScrollFraction = initialScrollFraction
        context.coordinator.initialScrollAnchor = initialScrollAnchor
        session.setPresentationCSS(presentationCSS)
        session.setScrollPosition(anchor: initialScrollAnchor, fallbackFraction: initialScrollFraction)
        session.attach(webView)
        session.loadDocument(source, documentID: documentID, mode: mode)

        guard let editorHTML = Self.editorHTML,
              Self.editorScript != nil else {
            session.reportError(String(localized: "The bundled Markdown editor resources could not be found.", table: "Localizable", bundle: .module))
            return webView
        }
        context.coordinator.awaitingEditorLoad = true
        webView.onFirstWindowAttachment = { [weak webView] in
            webView?.loadHTMLString(editorHTML, baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if let webView = webView as? WindowAttachedWebView {
            webView.editorSession = session
        }
        context.coordinator.onDocumentChange = onDocumentChange
        context.coordinator.onRequestSave = onRequestSave
        context.coordinator.onRequestSearch = onRequestSearch
        context.coordinator.linkCompletionQuery = linkCompletionQuery
        context.coordinator.onLinkActivation = onLinkActivation
        context.coordinator.onScrollFractionChange = onScrollFractionChange
        context.coordinator.onScrollAnchorChange = onScrollAnchorChange
        context.coordinator.initialScrollFraction = initialScrollFraction
        context.coordinator.initialScrollAnchor = initialScrollAnchor
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
        }
        if context.coordinator.documentID != documentID {
            context.coordinator.documentID = documentID
            context.coordinator.source = source
            context.coordinator.startingFingerprint = DocumentFingerprint(content: source).sha256
            context.coordinator.lastDocumentVersion = 0
            session.loadDocument(source, documentID: documentID, mode: mode)
            session.setLinkPreviews(linkPreviews, in: source)
            session.setScrollPosition(anchor: initialScrollAnchor, fallbackFraction: initialScrollFraction)
        } else if context.coordinator.source != source {
            context.coordinator.source = source
            context.coordinator.startingFingerprint = DocumentFingerprint(content: source).sha256
            context.coordinator.lastDocumentVersion = 0
            session.loadDocument(source, documentID: documentID, mode: mode)
            session.setLinkPreviews(linkPreviews, in: source)
            session.setScrollPosition(anchor: initialScrollAnchor, fallbackFraction: initialScrollFraction)
        } else if context.coordinator.lastModeInput != mode {
            context.coordinator.lastModeInput = mode
            session.setMode(mode)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        if let webView = webView as? WindowAttachedWebView {
            webView.editorSession = nil
        }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scholium")
        webView.navigationDelegate = nil
        coordinator.session.removeCommittedTextSynchronizer()
        coordinator.session.removeSourceChangeHandler()
        coordinator.session.detach(webView)
    }

    private static var editorResourceDirectory: URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let packagedBundleURL = resourceURL
                .appendingPathComponent("Scholium_ScholiumApp.bundle", isDirectory: true)
            if let packagedResources = Bundle(url: packagedBundleURL)?.resourceURL,
               FileManager.default.fileExists(
                   atPath: packagedResources.appendingPathComponent("editor.bundle.js").path
               ) {
                return packagedResources
            }
        }
        return Bundle.module.url(forResource: "index", withExtension: "html")?
            .deletingLastPathComponent()
    }

    private static var editorScript: String? {
        guard let directory = editorResourceDirectory else { return nil }
        return try? String(
            contentsOf: directory.appendingPathComponent("editor.bundle.js"),
            encoding: .utf8
        )
    }

    static var editorHTML: String? {
        guard let directory = editorResourceDirectory,
              let css = try? String(
                contentsOf: directory.appendingPathComponent("editor.css"),
                encoding: .utf8
              ),
              !ScholiumCalloutStyles.css.isEmpty else { return nil }
        return """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'none'; img-src data:; font-src data:">
            <style>\(ScholiumWebFonts.css)\n\(css)\n\(ScholiumCalloutStyles.css)\n\(ScholiumTableStyles.css)\n\(ScholiumFootnoteStyles.css)\n\(ScholiumMathAssets.css)\n\(ScholiumPreviewStyles.css)\n\(ScholiumWebDesignTokens.documentPresentationCSS)</style>
            <style id="scholium-presentation-css"></style>
            <style id="scholium-user-css"></style>
          </head>
          <body><main id="editor"></main></body>
        </html>
        """
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let session: MarkdownEditorSession
        var onDocumentChange: (String) -> Void
        var onRequestSave: () -> Void
        var onRequestSearch: () -> Void
        var linkCompletionQuery: @MainActor (String) async -> [EditorLinkCompletion]
        var onLinkActivation: (String) -> Void
        var onScrollFractionChange: (Double) -> Void
        var onScrollAnchorChange: (EditorScrollAnchor) -> Void
        var documentID = ""
        var source = ""
        /// Diff cache for the last SwiftUI input delivered to the session.
        /// It never supplies initialization or recovery state and never writes
        /// a bridge acknowledgement back into the Document model.
        var lastModeInput: MarkdownEditorMode = .livePreview
        var presentationCSS = ""
        var userCSS = ""
        var linkPreviews: [DocumentLinkPreview] = []
        var awaitingEditorLoad = false
        var startingFingerprint = ""
        var lastDocumentVersion = 0
        var initialScrollFraction: Double = 0
        var initialScrollAnchor: EditorScrollAnchor?
        private var hasSignaledReady = false

        init(
            session: MarkdownEditorSession,
            onDocumentChange: @escaping (String) -> Void,
            onRequestSave: @escaping () -> Void,
            onRequestSearch: @escaping () -> Void,
            linkCompletionQuery: @escaping @MainActor (String) async -> [EditorLinkCompletion],
            onLinkActivation: @escaping (String) -> Void,
            onScrollFractionChange: @escaping (Double) -> Void,
            onScrollAnchorChange: @escaping (EditorScrollAnchor) -> Void
        ) {
            self.session = session
            self.onDocumentChange = onDocumentChange
            self.onRequestSave = onRequestSave
            self.onRequestSearch = onRequestSearch
            self.linkCompletionQuery = linkCompletionQuery
            self.onLinkActivation = onLinkActivation
            self.onScrollFractionChange = onScrollFractionChange
            self.onScrollAnchorChange = onScrollAnchorChange
            super.init()
            session.installCommittedTextSynchronizer { [weak self] source, fingerprint in
                guard let self else { return }
                self.source = source
                self.startingFingerprint = fingerprint
            }
            session.installSourceChangeHandler { [weak self] source in
                guard let self else { return }
                self.source = source
                self.onDocumentChange(source)
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "scholium",
                  JSONSerialization.isValidJSONObject(message.body),
                  let data = try? JSONSerialization.data(withJSONObject: message.body),
                  data.count <= markdownEditorMaximumInboundBytes,
                  let payload = try? JSONDecoder().decode(EditorBridgeMessage.self, from: data) else { return }

            switch payload.type {
            case "ready":
                signalReady()
            case "documentEnded":
                if payload.editorReady == true {
                    signalReady()
                } else {
                    session.reportError(String(localized: "The Markdown editor script did not initialize.", table: "Localizable", bundle: .module))
                }
            case "editorError":
                session.reportError(payload.message ?? "The Markdown editor could not start.")
            case "interactionChanged":
                guard validEnvelope(payload),
                      let selections = payload.selections,
                      let line = payload.line,
                      let column = payload.column,
                      let lineCount = payload.lineCount,
                      let documentVersion = payload.documentVersion else { return }
                session.updateInteraction(
                    selections: selections,
                    line: line,
                    column: column,
                    lineCount: lineCount,
                    documentVersion: documentVersion,
                    context: payload.context
                )
            case "documentChanged":
                guard validEnvelope(payload, allowingFutureVersion: true) else { return }
                applyEditorChanges(from: payload)
            case "requestSave":
                guard validEnvelope(payload) else { return }
                onRequestSave()
            case "requestSearch":
                guard validEnvelope(payload) else { return }
                onRequestSearch()
            case "linkCompletionQuery":
                guard validEnvelope(payload),
                      let requestID = payload.requestID,
                      UUID(uuidString: requestID) != nil,
                      let query = payload.query,
                      query.utf16.count <= 512 else { return }
                let requestedDocumentID = documentID
                let requestedFingerprint = startingFingerprint
                let requestedVersion = lastDocumentVersion
                Task { @MainActor [weak self, weak webView = message.webView] in
                    guard let self, let webView else { return }
                    let candidates = await linkCompletionQuery(query)
                    guard requestedDocumentID == documentID,
                          requestedFingerprint == startingFingerprint,
                          requestedVersion == lastDocumentVersion,
                          webView.navigationDelegate === self else { return }
                    let payload = candidates.prefix(100).map { candidate in
                        [
                            "label": candidate.label,
                            "insertion": candidate.insertion,
                            "detail": candidate.detail,
                            "path": candidate.path,
                            "isAmbiguous": candidate.isAmbiguous,
                        ] as [String: Any]
                    }
                    _ = try? await webView.callAsyncJavaScript(
                        "window.scholiumEditor.resolveLinkCompletionQuery(requestID, candidates)",
                        arguments: [
                            "requestID": requestID,
                            "candidates": payload,
                        ],
                        in: nil,
                        contentWorld: .page
                    )
                }
            case "linkActivated":
                guard validEnvelope(payload), let target = payload.target, !target.isEmpty else { return }
                onLinkActivation(target)
            case "scrollChanged":
                guard validEnvelope(payload),
                      let fraction = payload.scrollFraction,
                      fraction.isFinite,
                      (0...1).contains(fraction) else { return }
                if let anchor = session.recordScrollPosition(
                    payload.scrollAnchor,
                    fallbackFraction: fraction
                ) {
                    onScrollAnchorChange(anchor)
                } else {
                    session.recordScrollFraction(fraction)
                }
                onScrollFractionChange(fraction)
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
            session.reportError(error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            session.webContentProcessTerminated()
            hasSignaledReady = false
            awaitingEditorLoad = true
            guard let editorHTML = MarkdownEditorWebView.editorHTML else {
                session.reportError(String(localized: "The Markdown editor resources could not be reloaded.", table: "Localizable", bundle: .module))
                return
            }
            webView.loadHTMLString(editorHTML, baseURL: nil)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            // Only Scholium can initiate this in-memory first navigation; the
            // view has not exposed any interactive document yet.
            if awaitingEditorLoad {
                decisionHandler(.allow)
                return
            }
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.absoluteString == "about:blank" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        private func signalReady() {
            guard !hasSignaledReady else { return }
            hasSignaledReady = true
            session.editorBecameReady()
            session.setPresentationCSS(presentationCSS)
            session.setUserCSS(userCSS)
            session.setLinkPreviews(linkPreviews, in: source)
            session.setScrollPosition(
                anchor: session.retainedScrollAnchor ?? initialScrollAnchor,
                fallbackFraction: session.retainedScrollFraction(
                    fallback: initialScrollFraction
                )
            )
        }

        private func validEnvelope(
            _ payload: EditorBridgeMessage,
            allowingFutureVersion: Bool = false
        ) -> Bool {
            guard payload.protocolVersion == markdownEditorProtocolVersion,
                  payload.sessionID == session.sessionID.uuidString,
                  payload.documentID == documentID,
                  payload.startingFingerprint == startingFingerprint,
                  let version = payload.documentVersion else { return false }
            return allowingFutureVersion
                ? version >= session.generation
                : version == session.generation
        }

        private func applyEditorChanges(from payload: EditorBridgeMessage) {
            guard let rawChanges = payload.changes,
                  let baseGeneration = payload.baseGeneration,
                  let resultingGeneration = payload.resultingGeneration,
                  payload.documentVersion == resultingGeneration,
                  let nextSource = session.acceptEditorChanges(
                    rawChanges,
                    baseGeneration: baseGeneration,
                    resultingGeneration: resultingGeneration
                  ) else { return }
            source = nextSource
            lastDocumentVersion = resultingGeneration
        }
    }
}
