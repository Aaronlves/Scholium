import ScholiumContracts
import AppKit
import SwiftUI
import WebKit

struct MarkdownEditorWebView: NSViewRepresentable {
    @ObservedObject var session: MarkdownEditorSession
    let documentID: String
    let documentTitle: String
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
    var documentAttachments: [DocumentAttachmentSnapshot] = []
    var documentAttachmentRevealRevision: UInt64 = 0
    let initialScrollFraction: Double
    let initialScrollAnchor: EditorScrollAnchor?
    let onDocumentActivity: () -> Void
    let onRequestSave: () -> Void
    let onRequestFind: (DocumentFindShortcut) -> Void
    let onRequestImportImage: () -> Void
    let onRequestIndexImage: () -> Void
    let onRequestDocumentTitleRename: @MainActor (
        String,
        String
    ) async throws -> String
    var onPreviewDocumentAttachment: (UUID) -> Void = { _ in }
    var onAttachDocument: (DocumentAttachmentSelectionMode) -> Void = { _ in }
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
            onPreviewDocumentAttachment: onPreviewDocumentAttachment,
            onAttachDocument: onAttachDocument,
            onRequestDocumentTitleRename: onRequestDocumentTitleRename,
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
        context.coordinator.documentTitle = documentTitle
        context.coordinator.source = attachmentSource
        context.coordinator.startingFingerprint = DocumentFingerprint(content: attachmentSource).sha256
        context.coordinator.lastModeInput = mode
        context.coordinator.presentationCSS = presentationCSS
        context.coordinator.userCSS = userCSS
        context.coordinator.linkPreviews = linkPreviews
        context.coordinator.documentAttachments = documentAttachments
        context.coordinator.documentAttachmentRevealRevision =
            documentAttachmentRevealRevision
        context.coordinator.initialScrollFraction = initialScrollFraction
        context.coordinator.initialScrollAnchor = initialScrollAnchor
        if requiresMathRuntime {
            context.coordinator.requestMathRuntimeIfNeeded(in: webView)
        }
        context.coordinator.performanceDocumentID = performanceDocumentID
        session.setPresentationCSS(presentationCSS)
        session.setDocumentTitle(documentTitle)
        session.setDocumentAttachments(documentAttachments)
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
        context.coordinator.onPreviewDocumentAttachment = onPreviewDocumentAttachment
        context.coordinator.onAttachDocument = onAttachDocument
        context.coordinator.onRequestDocumentTitleRename = onRequestDocumentTitleRename
        context.coordinator.linkCompletionQuery = linkCompletionQuery
        context.coordinator.onLinkActivation = onLinkActivation
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
        }
        if context.coordinator.documentAttachments != documentAttachments {
            context.coordinator.documentAttachments = documentAttachments
            session.setDocumentAttachments(documentAttachments)
        }
        if context.coordinator.documentAttachmentRevealRevision
            != documentAttachmentRevealRevision {
            context.coordinator.documentAttachmentRevealRevision =
                documentAttachmentRevealRevision
            session.revealDocumentAttachmentControl()
        }
        if context.coordinator.documentID != documentID {
            context.coordinator.cancelLinkCompletionQuery()
            context.coordinator.cancelDocumentTitleRename()
            context.coordinator.documentID = documentID
            context.coordinator.source = source
            context.coordinator.startingFingerprint = DocumentFingerprint(content: source).sha256
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
        coordinator.cancelDocumentTitleRename()
        coordinator.session.detach(webView)
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
        guard let css = ScholiumDocumentWebResources.text(
                named: "editor",
                extension: "css"
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
        var onPreviewDocumentAttachment: (UUID) -> Void
        var onAttachDocument: (DocumentAttachmentSelectionMode) -> Void
        var onRequestDocumentTitleRename: @MainActor (
            String,
            String
        ) async throws -> String
        var linkCompletionQuery: @MainActor (
            EditorLinkCompletionKind,
            String
        ) async -> [EditorLinkCompletion]
        var onLinkActivation: (String) -> Void
        var onScrollFractionChange: (Double) -> Void
        var onScrollAnchorChange: (EditorScrollAnchor) -> Void
        var documentID = ""
        var documentTitle = ""
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
        var documentAttachments: [DocumentAttachmentSnapshot] = []
        var documentAttachmentRevealRevision: UInt64 = 0
        var awaitingEditorLoad = false
        var startingFingerprint = ""
        var initialScrollFraction: Double = 0
        var initialScrollAnchor: EditorScrollAnchor?
        private var hasSignaledReady = false
        private var mermaidRuntimeLoadTask: Task<Void, Never>?
        private var mermaidRuntimeLoadID: UUID?
        private var mathRuntimeLoadTask: Task<Void, Never>?
        private var linkCompletionQueryTask: Task<Void, Never>?
        private var linkCompletionQueryTaskID: UUID?
        private var documentTitleRenameTask: Task<Void, Never>?
        private var documentTitleRenameRequestID: String?

        init(
            session: MarkdownEditorSession,
            performanceDocumentID: String,
            onDocumentActivity: @escaping () -> Void,
            onRequestSave: @escaping () -> Void,
            onRequestFind: @escaping (DocumentFindShortcut) -> Void,
            onRequestImportImage: @escaping () -> Void,
            onRequestIndexImage: @escaping () -> Void,
            onPreviewDocumentAttachment: @escaping (UUID) -> Void,
            onAttachDocument: @escaping (DocumentAttachmentSelectionMode) -> Void,
            onRequestDocumentTitleRename: @escaping @MainActor (
                String,
                String
            ) async throws -> String,
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
            self.onPreviewDocumentAttachment = onPreviewDocumentAttachment
            self.onAttachDocument = onAttachDocument
            self.onRequestDocumentTitleRename = onRequestDocumentTitleRename
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
            guard let payload = EditorBridgeMessageDecoder.decode(message.body) else { return }

            switch payload {
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
                guard validEnvelope(interaction.envelope) else { return }
                session.updateInteraction(
                    selections: interaction.selections,
                    line: interaction.line,
                    column: interaction.column,
                    lineCount: interaction.lineCount,
                    documentVersion: interaction.envelope.documentVersion,
                    focusTarget: interaction.focusTarget,
                    context: interaction.context
                )
            case .documentChanged(let change):
                guard validEnvelope(change.envelope, allowingFutureGeneration: true) else {
                    return
                }
                applyEditorChanges(
                    change,
                    in: message.webView ?? activeWebView
                )
            case .performanceSample(let performance):
                guard validEnvelope(performance.envelope),
                      performance.durationMilliseconds > 0 else { return }
                switch performance.metric {
                case "editor_key_to_paint":
                    PerformanceProbe.shared.recordEditorKeyToPaint(
                        documentID: performanceDocumentID,
                        durationMilliseconds: performance.durationMilliseconds
                    )
                case "editor_cached_preview":
                    PerformanceProbe.shared.recordEditorWebDuration(
                        documentID: performanceDocumentID,
                        metric: .editorCachedPreview,
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
                guard validEnvelope(envelope) else { return }
                onRequestSave()
            case .requestDocumentFind(let request):
                guard validEnvelope(request.envelope) else { return }
                onRequestFind(request.action)
            case .requestImportImage(let envelope):
                guard validEnvelope(envelope) else { return }
                onRequestImportImage()
            case .requestIndexImage(let envelope):
                guard validEnvelope(envelope) else { return }
                onRequestIndexImage()
            case .requestDocumentTitleRename(let request):
                guard validEnvelope(request.envelope),
                      let webView = message.webView ?? activeWebView else { return }
                guard request.expectedTitle == documentTitle else {
                    rejectChangedDocumentTitleRename(request, in: webView)
                    return
                }
                beginDocumentTitleRename(request, in: webView)
            case .requestImagePaste(let envelope):
                guard validEnvelope(envelope),
                      let webView = message.webView as? WindowAttachedWebView else { return }
                _ = webView.consumePastedImage()
            case .requestMermaidRuntime(let envelope):
                guard validEnvelope(envelope), let webView = message.webView else { return }
                requestMermaidRuntime(in: webView)
            case .requestMathRuntime(let envelope):
                guard validEnvelope(envelope),
                      let webView = message.webView ?? activeWebView else { return }
                requestMathRuntime(in: webView)
            case .linkCompletionQuery(let request):
                guard validEnvelope(request.envelope) else { return }
                let requestID = request.requestID
                let requestedDocumentID = documentID
                let requestedFingerprint = startingFingerprint
                let requestedVersion = session.generation
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
                    let candidates = await linkCompletionQuery(
                        request.completionKind,
                        request.query
                    )
                    guard !Task.isCancelled,
                          requestedDocumentID == documentID,
                          requestedFingerprint == startingFingerprint,
                          requestedVersion == session.generation,
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
            case .linkActivated(let activation):
                guard validEnvelope(activation.envelope) else { return }
                onLinkActivation(activation.target)
            case .requestDocumentAttachmentPreview(let request):
                guard validEnvelope(request.envelope) else { return }
                onPreviewDocumentAttachment(request.attachmentID)
            case .requestDocumentAttachmentMenu(let request):
                guard validEnvelope(request.envelope),
                      let webView = message.webView ?? activeWebView else { return }
                presentDocumentAttachmentMenu(
                    clientX: request.clientX,
                    clientY: request.clientY,
                    in: webView,
                    choose: onAttachDocument
                )
            case .contextMenuRequested(let request):
                guard validEnvelope(request.envelope),
                      session.acceptsInteractionRanges(
                          request.context.selections,
                          documentVersion: request.envelope.documentVersion
                      ),
                      request.mode == lastModeInput,
                      let webView = message.webView as? WindowAttachedWebView else { return }
                webView.presentEditorContextMenu(
                    clientX: request.clientX,
                    clientY: request.clientY,
                    context: request.context,
                    mode: request.mode
                )
            case .scrollChanged(let scroll):
                guard validEnvelope(scroll.envelope),
                      (0...1).contains(scroll.fraction) else { return }
                if let anchor = session.recordScrollPosition(
                    scroll.anchor,
                    fallbackFraction: scroll.fraction
                ) {
                    onScrollAnchorChange(anchor)
                } else {
                    session.recordScrollFraction(scroll.fraction)
                }
                onScrollFractionChange(scroll.fraction)
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
            cancelDocumentTitleRename()
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
                        String(error.localizedDescription.prefix(2_000))
                    )
                }
                guard !Task.isCancelled,
                      documentTitleRenameRequestID == request.requestID,
                      let webView,
                      webView.navigationDelegate === self else { return }
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
                      webView.navigationDelegate === self else { return }
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
            decisionHandler(Self.navigationPolicy(
                url: navigationAction.request.url,
                isMainFrame: navigationAction.targetFrame?.isMainFrame == true
            ))
        }

        static func navigationPolicy(
            url: URL?,
            isMainFrame: Bool
        ) -> WKNavigationActionPolicy {
            guard isMainFrame,
                  url?.absoluteString == "about:blank" else { return .cancel }
            return .allow
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
            _ envelope: EditorBridgeEnvelope,
            allowingFutureGeneration: Bool = false
        ) -> Bool {
            guard envelope.protocolVersion == markdownEditorProtocolVersion,
                  envelope.sessionID == session.sessionID.uuidString,
                  envelope.documentID == documentID,
                  envelope.startingFingerprint == startingFingerprint else { return false }
            return allowingFutureGeneration
                ? envelope.documentVersion >= session.generation
                : envelope.documentVersion == session.generation
        }

        private func applyEditorChanges(
            _ change: EditorDocumentChangeMessage,
            in webView: WKWebView?
        ) {
            guard session.acceptEditorChanges(
                change.changes,
                baseGeneration: change.baseGeneration,
                resultingGeneration: change.resultingGeneration
            ) else {
                if let webView,
                   change.resultingGeneration > session.generation {
                    session.reconcileAfterRejectedEditorChanges(
                        resultingGeneration: change.resultingGeneration,
                        in: webView
                    )
                }
                return
            }
            if change.changes.contains(where: { $0.insert.contains("$") }),
               let webView {
                requestMathRuntime(in: webView)
            }
        }
    }
}
