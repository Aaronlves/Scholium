import ScholiumContracts
import AppKit
import SwiftUI
import WebKit

struct MarkdownEditorWebView: NSViewRepresentable {
    @ObservedObject var session: MarkdownEditorSession
    let documentID: String
    let performanceDocumentID: String
    let source: String
    let mode: MarkdownEditorMode
    let presentationCSS: String
    let userCSS: String
    let requiresMathRuntime: Bool
    let linkCompletionQuery: @MainActor (
        EditorLinkCompletionKind,
        String
    ) async -> [EditorLinkCompletion]
    let linkPreviews: [DocumentLinkPreview]
    let initialScrollFraction: Double
    let initialScrollAnchor: EditorScrollAnchor?
    let onDocumentActivity: () -> Void
    let onRequestSave: () -> Void
    let onRequestFind: (DocumentFindShortcut) -> Void
    let onRequestImportImage: () -> Void
    let onRequestIndexImage: () -> Void
    let onPasteImage: (EditorPastedImageSource) -> Bool
    let onLinkActivation: (String) -> Void
    let onScrollFractionChange: (Double) -> Void
    let onScrollAnchorChange: (EditorScrollAnchor) -> Void

    static func requiresMathRuntime(
        source: String,
        linkPreviews: [DocumentLinkPreview]
    ) -> Bool {
        source.contains("$") || linkPreviews.contains {
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
            onRequestImportImage: onRequestImportImage,
            onRequestIndexImage: onRequestIndexImage,
            linkCompletionQuery: linkCompletionQuery,
            onLinkActivation: onLinkActivation,
            onScrollFractionChange: onScrollFractionChange,
            onScrollAnchorChange: onScrollAnchorChange
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let attachmentSource = session.sourceForViewAttachment(
            proposedSource: source,
            documentID: documentID
        )
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "scholium")
        let interfaceLocalization = WebKitInterfaceLocalization.current()
        let editorStartFailure = Self.jsonLiteral(
            interfaceLocalization.string("The Markdown editor could not start.")
        )
        contentController.addUserScript(WKUserScript(
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
            || PerformanceProbe.shared.measuresEditorVisibleProjection {
            let metric: String
            if PerformanceProbe.shared.measuresEditorCachedPreview {
                metric = "editor_cached_preview"
            } else if PerformanceProbe.shared.measuresEditorVisibleProjection {
                metric = "editor_visible_projection"
            } else {
                metric = "editor_key_to_paint"
            }
            contentController.addUserScript(WKUserScript(
                source: "window.scholiumPerformanceMetric = '\(metric)';",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        if requiresMathRuntime, !ScholiumMathAssets.runtimeJavaScript.isEmpty {
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
        configuration.websiteDataStore = ScholiumWebKitRuntime.nonPersistentDataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        ScholiumWebFontResources.install(in: configuration)

        let webView = WindowAttachedWebView(frame: .zero, configuration: configuration)
        context.coordinator.activeWebView = webView
        webView.editorSession = session
        webView.onPasteImage = onPasteImage
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.documentID = documentID
        context.coordinator.source = attachmentSource
        context.coordinator.startingFingerprint = DocumentFingerprint(content: attachmentSource).sha256
        context.coordinator.lastModeInput = mode
        context.coordinator.presentationCSS = presentationCSS
        context.coordinator.userCSS = userCSS
        context.coordinator.linkPreviews = linkPreviews
        context.coordinator.initialScrollFraction = initialScrollFraction
        context.coordinator.initialScrollAnchor = initialScrollAnchor
        if requiresMathRuntime {
            context.coordinator.requestMathRuntimeIfNeeded(in: webView)
        }
        context.coordinator.performanceDocumentID = performanceDocumentID
        session.setPresentationCSS(presentationCSS)
        session.setScrollPosition(anchor: initialScrollAnchor, fallbackFraction: initialScrollFraction)
        session.attach(webView)
        session.loadDocument(attachmentSource, documentID: documentID, mode: mode)

        guard let editorHTML = Self.editorHTML(localization: interfaceLocalization),
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
        context.coordinator.activeWebView = webView
        if let webView = webView as? WindowAttachedWebView {
            webView.editorSession = session
            webView.onPasteImage = onPasteImage
        }
        context.coordinator.performanceDocumentID = performanceDocumentID
        context.coordinator.onDocumentActivity = onDocumentActivity
        context.coordinator.onRequestSave = onRequestSave
        context.coordinator.onRequestFind = onRequestFind
        context.coordinator.onRequestImportImage = onRequestImportImage
        context.coordinator.onRequestIndexImage = onRequestIndexImage
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
            context.coordinator.cancelLinkCompletionQuery()
            context.coordinator.documentID = documentID
            context.coordinator.source = source
            context.coordinator.startingFingerprint = DocumentFingerprint(content: source).sha256
            context.coordinator.lastDocumentVersion = 0
            session.loadDocument(source, documentID: documentID, mode: mode)
            session.setLinkPreviews(linkPreviews, in: source)
            session.setScrollPosition(anchor: initialScrollAnchor, fallbackFraction: initialScrollFraction)
        } else if context.coordinator.lastModeInput != mode {
            context.coordinator.cancelLinkCompletionQuery()
            context.coordinator.lastModeInput = mode
            session.setMode(mode)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        if let webView = webView as? WindowAttachedWebView {
            webView.editorSession = nil
            webView.onPasteImage = nil
        }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scholium")
        webView.navigationDelegate = nil
        coordinator.activeWebView = nil
        coordinator.session.removeCommittedTextSynchronizer()
        coordinator.session.removeSourceChangeHandler()
        coordinator.cancelMermaidRuntimeLoad()
        coordinator.cancelMathRuntimeLoad()
        coordinator.cancelLinkCompletionQuery()
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
        editorHTML(localization: .current())
    }

    static func editorHTML(
        localization: WebKitInterfaceLocalization
    ) -> String? {
        guard let directory = editorResourceDirectory,
              let css = try? String(
                contentsOf: directory.appendingPathComponent("editor.css"),
                encoding: .utf8
              ),
              !ScholiumCalloutStyles.css.isEmpty else { return nil }
        return """
        <!doctype html>
        <html lang="\(localization.languageTag)">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="scholium-interface-localization" content="\(localization.base64JSON())">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'none'; img-src data:; font-src scholium-font: data:">
            <style>\(ScholiumWebFonts.css)\n\(css)\n\(ScholiumCalloutStyles.css)\n\(ScholiumTableStyles.css)\n\(ScholiumFootnoteStyles.css)\n\(ScholiumMathAssets.css)\n\(ScholiumMermaidAssets.css)\n\(ScholiumPreviewStyles.css)\n\(ScholiumWebSymbolAssets.cssVariables)\n\(ScholiumWebDesignTokens.documentPresentationCSS)</style>
            <style id="scholium-presentation-css"></style>
            <style id="scholium-user-css"></style>
          </head>
          <body><main id="editor"></main></body>
        </html>
        """
    }

    private static func jsonLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8) else { return "\"\"" }
        return literal
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let session: MarkdownEditorSession
        var onDocumentActivity: () -> Void
        var onRequestSave: () -> Void
        var onRequestFind: (DocumentFindShortcut) -> Void
        var onRequestImportImage: () -> Void
        var onRequestIndexImage: () -> Void
        var linkCompletionQuery: @MainActor (
            EditorLinkCompletionKind,
            String
        ) async -> [EditorLinkCompletion]
        var onLinkActivation: (String) -> Void
        var onScrollFractionChange: (Double) -> Void
        var onScrollAnchorChange: (EditorScrollAnchor) -> Void
        var documentID = ""
        var performanceDocumentID: String
        weak var activeWebView: WKWebView?
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
        private var mermaidRuntimeLoadTask: Task<Void, Never>?
        private var mermaidRuntimeLoadID: UUID?
        private var mathRuntimeLoadTask: Task<Void, Never>?
        private var linkCompletionQueryTask: Task<Void, Never>?
        private var linkCompletionQueryTaskID: UUID?

        init(
            session: MarkdownEditorSession,
            performanceDocumentID: String,
            onDocumentActivity: @escaping () -> Void,
            onRequestSave: @escaping () -> Void,
            onRequestFind: @escaping (DocumentFindShortcut) -> Void,
            onRequestImportImage: @escaping () -> Void,
            onRequestIndexImage: @escaping () -> Void,
            linkCompletionQuery: @escaping @MainActor (
                EditorLinkCompletionKind,
                String
            ) async -> [EditorLinkCompletion],
            onLinkActivation: @escaping (String) -> Void,
            onScrollFractionChange: @escaping (Double) -> Void,
            onScrollAnchorChange: @escaping (EditorScrollAnchor) -> Void
        ) {
            self.session = session
            self.performanceDocumentID = performanceDocumentID
            self.onDocumentActivity = onDocumentActivity
            self.onRequestSave = onRequestSave
            self.onRequestFind = onRequestFind
            self.onRequestImportImage = onRequestImportImage
            self.onRequestIndexImage = onRequestIndexImage
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
            session.installSourceChangeHandler { [weak self] in
                guard let self else { return }
                self.onDocumentActivity()
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "scholium" else { return }
            if let object = message.body as? [String: Any],
               object["type"] as? String == "documentChanged" {
                applyIncrementalDocumentChange(
                    object,
                    in: message.webView ?? activeWebView
                )
                return
            }
            guard JSONSerialization.isValidJSONObject(message.body),
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
                session.reportError(
                    payload.message
                        ?? WebKitInterfaceLocalization.current()
                        .string("The Markdown editor could not start.")
                )
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
                applyEditorChanges(
                    from: payload,
                    in: message.webView ?? activeWebView
                )
            case "performanceSample":
                guard validEnvelope(payload),
                      let metric = payload.metric,
                      let duration = payload.durationMilliseconds,
                      duration.isFinite,
                      duration > 0 else { return }
                switch metric {
                case "editor_key_to_paint":
                    PerformanceProbe.shared.recordEditorKeyToPaint(
                        documentID: performanceDocumentID,
                        durationMilliseconds: duration
                    )
                case "editor_cached_preview":
                    PerformanceProbe.shared.recordEditorWebDuration(
                        documentID: performanceDocumentID,
                        metric: .editorCachedPreview,
                        durationMilliseconds: duration
                    )
                case "editor_visible_projection":
                    PerformanceProbe.shared.recordEditorWebDuration(
                        documentID: performanceDocumentID,
                        metric: .editorVisibleProjection,
                        durationMilliseconds: duration
                    )
                default:
                    return
                }
            case "requestSave":
                guard validEnvelope(payload) else { return }
                onRequestSave()
            case "requestDocumentFind":
                guard validEnvelope(payload), let action = payload.action else { return }
                onRequestFind(action)
            case "requestImportImage":
                guard validEnvelope(payload) else { return }
                onRequestImportImage()
            case "requestIndexImage":
                guard validEnvelope(payload) else { return }
                onRequestIndexImage()
            case "requestImagePaste":
                guard validEnvelope(payload),
                      let webView = message.webView as? WindowAttachedWebView else { return }
                _ = webView.consumePastedImage()
            case "requestMermaidRuntime":
                guard validEnvelope(payload), let webView = message.webView else { return }
                requestMermaidRuntime(in: webView)
            case "requestMathRuntime":
                guard validEnvelope(payload),
                      let webView = message.webView ?? activeWebView else { return }
                requestMathRuntime(in: webView)
            case "linkCompletionQuery":
                guard validEnvelope(payload),
                      let requestID = payload.requestID,
                      UUID(uuidString: requestID) != nil,
                      let completionKind = payload.completionKind,
                      let query = payload.query,
                      query.utf16.count <= 512 else { return }
                let requestedDocumentID = documentID
                let requestedFingerprint = startingFingerprint
                let requestedVersion = lastDocumentVersion
                let taskID = UUID()
                cancelLinkCompletionQuery()
                linkCompletionQueryTaskID = taskID
                linkCompletionQueryTask = Task { @MainActor [weak self, weak webView = message.webView] in
                    guard let self, let webView else { return }
                    defer {
                        if self.linkCompletionQueryTaskID == taskID {
                            self.linkCompletionQueryTask = nil
                            self.linkCompletionQueryTaskID = nil
                        }
                    }
                    let candidates = await linkCompletionQuery(completionKind, query)
                    guard !Task.isCancelled,
                          requestedDocumentID == documentID,
                          requestedFingerprint == startingFingerprint,
                          requestedVersion == lastDocumentVersion,
                          webView.navigationDelegate === self else { return }
                    let payload = candidates.prefix(100).map { candidate in
                        var value = [
                            "label": candidate.label,
                            "insertion": candidate.insertion,
                            "detail": candidate.detail,
                            "path": candidate.path,
                            "isAmbiguous": candidate.isAmbiguous,
                        ] as [String: Any]
                        if let displayText = candidate.displayText {
                            value["displayText"] = displayText
                        }
                        return value
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
            case "contextMenuRequested":
                guard validEnvelope(payload),
                      let clientX = payload.clientX,
                      let clientY = payload.clientY,
                      clientX.isFinite,
                      clientY.isFinite,
                      let context = payload.context,
                      markdownEditorSelectionRangesAreValid(
                          context.selections,
                          forEditorUTF16Length: source.utf16.count
                      ),
                      let mode = payload.mode,
                      mode == lastModeInput,
                      let webView = message.webView as? WindowAttachedWebView else { return }
                webView.presentEditorContextMenu(
                    clientX: clientX,
                    clientY: clientY,
                    context: context,
                    mode: mode
                )
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
            cancelMermaidRuntimeLoad()
            cancelMathRuntimeLoad()
            cancelLinkCompletionQuery()
            hasSignaledReady = false
            awaitingEditorLoad = true
            guard let editorHTML = MarkdownEditorWebView.editorHTML else {
                session.reportError(String(localized: "The Markdown editor resources could not be reloaded.", table: "Localizable", bundle: .module))
                return
            }
            webView.loadHTMLString(editorHTML, baseURL: nil)
        }

        private func requestMermaidRuntime(in webView: WKWebView) {
            guard mermaidRuntimeLoadTask == nil else { return }
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
                      !Task.isCancelled else { return }
                await ScholiumMermaidRuntimeLoader.installAndNotify(in: webView)
            }
        }

        private func requestMathRuntime(in webView: WKWebView) {
            guard mathRuntimeLoadTask == nil else { return }
            mathRuntimeLoadTask = Task { @MainActor [weak self, weak webView] in
                guard let self else { return }
                defer { self.mathRuntimeLoadTask = nil }
                guard let webView,
                      webView.navigationDelegate === self,
                      !Task.isCancelled else { return }
                _ = await ScholiumMathRuntimeLoader.installAndRefresh(in: webView)
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
        }

        func cancelLinkCompletionQuery() {
            linkCompletionQueryTask?.cancel()
            linkCompletionQueryTask = nil
            linkCompletionQueryTaskID = nil
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

        private func applyEditorChanges(
            from payload: EditorBridgeMessage,
            in webView: WKWebView?
        ) {
            guard let rawChanges = payload.changes,
                  let baseGeneration = payload.baseGeneration,
                  let resultingGeneration = payload.resultingGeneration,
                  payload.documentVersion == resultingGeneration,
                  session.acceptEditorChanges(
                    rawChanges,
                    baseGeneration: baseGeneration,
                    resultingGeneration: resultingGeneration
                  ) else { return }
            lastDocumentVersion = resultingGeneration
            if rawChanges.contains(where: { $0.insert.contains("$") }),
               let webView {
                requestMathRuntime(in: webView)
            }
        }

        /// The app-private WebKit bridge has already converted the JavaScript
        /// object into Foundation values. Ordinary typing takes this checked
        /// direct path so a small delta is not encoded back to JSON and decoded
        /// again on every English or IME transaction. Less frequent envelopes
        /// retain the complete Codable decoder above.
        private func applyIncrementalDocumentChange(
            _ object: [String: Any],
            in webView: WKWebView?
        ) {
            guard integer(object["protocolVersion"]) == markdownEditorProtocolVersion,
                  object["sessionID"] as? String == session.sessionID.uuidString,
                  object["documentID"] as? String == documentID,
                  object["startingFingerprint"] as? String == startingFingerprint,
                  let documentVersion = integer(object["documentVersion"]),
                  let baseGeneration = integer(object["baseGeneration"]),
                  let resultingGeneration = integer(object["resultingGeneration"]),
                  documentVersion == resultingGeneration,
                  let rawChanges = object["changes"] as? [Any],
                  !rawChanges.isEmpty,
                  rawChanges.count <= 512 else { return }

            var insertedUTF8Bytes = 0
            var changes: [EditorBridgeChange] = []
            changes.reserveCapacity(rawChanges.count)
            for rawChange in rawChanges {
                guard let change = rawChange as? [String: Any],
                      let from = integer(change["from"]),
                      let to = integer(change["to"]),
                      let insertion = change["insert"] as? String,
                      from >= 0,
                      to >= from else { return }
                insertedUTF8Bytes += insertion.utf8.count
                guard insertedUTF8Bytes <= MarkdownEditorDeltaApplier.maximumResultUTF8Bytes else {
                    return
                }
                changes.append(EditorBridgeChange(from: from, to: to, insert: insertion))
            }
            guard session.acceptEditorChanges(
                changes,
                baseGeneration: baseGeneration,
                resultingGeneration: resultingGeneration
            ) else { return }
            lastDocumentVersion = resultingGeneration
            if changes.contains(where: { $0.insert.contains("$") }),
               let webView {
                requestMathRuntime(in: webView)
            }
        }

        private func integer(_ value: Any?) -> Int? {
            guard let number = value as? NSNumber else { return nil }
            let integer = number.intValue
            guard NSNumber(value: integer) == number else { return nil }
            return integer
        }
    }
}
