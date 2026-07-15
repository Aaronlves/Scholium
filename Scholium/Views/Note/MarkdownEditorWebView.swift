import ScholiumContracts
import SwiftUI
import WebKit

private final class WindowAttachedWebView: WKWebView {
    var onFirstWindowAttachment: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, let action = onFirstWindowAttachment else { return }
        onFirstWindowAttachment = nil
        action()
    }
}

enum NotePresentationMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case read
    case livePreview
    case source

    var id: String { rawValue }

    var title: String {
        switch self {
        case .read: "Read"
        case .livePreview: "Live Preview"
        case .source: "Source"
        }
    }

    var symbol: String {
        switch self {
        case .read: "book"
        case .livePreview: "text.page.badge.magnifyingglass"
        case .source: "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct EditorLinkCompletion: Encodable, Hashable {
    let label: String
    let insertion: String
    let detail: String
    let path: String
    let isAmbiguous: Bool
}

private struct EditorResearcherCommentAnnotation: Encodable, Hashable {
    let id: UUID
    let from: Int
    let to: Int
    let comment: String
    let resolved: Bool
}

private struct EditorBridgeChange: Codable {
    let from: Int
    let to: Int
    let insert: String
}

private struct EditorBridgeMessage: Codable {
    let type: String
    let bridgeVersion: Int?
    let sessionID: String?
    let documentID: String?
    let startingFingerprint: String?
    let documentVersion: Int?
    let changes: [EditorBridgeChange]?
    let dirty: Bool?
    let line: Int?
    let column: Int?
    let lineCount: Int?
    let message: String?
    let editorReady: Bool?
    let scrollFraction: Double?
    let commentID: String?
}

@MainActor
final class MarkdownEditorSession: ObservableObject {
    enum SessionError: LocalizedError {
        case unavailable
        case invalidResult
        case selectionTooLong

        var errorDescription: String? {
            switch self {
            case .unavailable: "The Markdown editor is not ready."
            case .invalidResult: "The Markdown editor returned an invalid document."
            case .selectionTooLong: "Select at most 2,000 characters for one source-anchored comment."
            }
        }
    }

    @Published private(set) var isReady = false
    @Published private(set) var isLoaded = false
    @Published private(set) var isDirty = false
    @Published private(set) var line = 1
    @Published private(set) var column = 1
    @Published private(set) var lineCount = 1
    @Published private(set) var errorMessage: String?
    private(set) var sessionID = UUID()
    private(set) var documentID = ""

    private weak var webView: WKWebView?
    private var pendingSource: String?
    private var pendingDocumentID = ""
    private var pendingMode: NotePresentationMode = .livePreview
    private var pendingUserCSS = ""
    private var pendingLine: Int?
    private var pendingLinkCompletions: [EditorLinkCompletion] = []
    private var pendingResearcherComments: [EditorResearcherCommentAnnotation] = []
    private var pendingScrollFraction: Double = 0
    private var startupTask: Task<Void, Never>?
    private var committedTextSynchronizer: ((String, String) -> Void)?

    fileprivate func attach(_ webView: WKWebView) {
        self.webView = webView
        sessionID = UUID()
        isReady = false
        isLoaded = false
        errorMessage = nil
        startupTask?.cancel()
        startupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self, !self.isReady else { return }
            self.reportError("Live Preview did not finish starting.")
        }
    }

    fileprivate func editorBecameReady() {
        startupTask?.cancel()
        isReady = true
        flushPendingState()
    }

    fileprivate func updateState(dirty: Bool?, line: Int?, column: Int?, lineCount: Int?) {
        if let dirty { isDirty = dirty }
        if let line { self.line = line }
        if let column { self.column = column }
        if let lineCount { self.lineCount = lineCount }
    }

    fileprivate func reportError(_ message: String) {
        startupTask?.cancel()
        errorMessage = message
        isLoaded = false
    }

    func loadDocument(_ source: String, documentID: String, mode: NotePresentationMode) {
        pendingSource = source
        pendingDocumentID = documentID
        self.documentID = documentID
        pendingMode = mode
        isLoaded = false
        isDirty = false
        errorMessage = nil
        flushPendingState()
    }

    func setMode(_ mode: NotePresentationMode) {
        guard mode != .read else { return }
        pendingMode = mode
        guard isReady, isLoaded, let webView else { return }
        Task {
            try? await Self.evaluateJavaScript(
                "window.scholiumEditor.setMode(\(Self.javascriptLiteral(mode.rawValue)))",
                in: webView
            )
        }
    }

    func setUserCSS(_ css: String) {
        pendingUserCSS = css
        guard isReady, let webView else { return }
        Task {
            try? await Self.evaluateJavaScript(
                "window.scholiumEditor.setUserCSS(\(Self.javascriptLiteral(css)))",
                in: webView
            )
        }
    }

    func goToLine(_ line: Int) {
        pendingLine = max(1, line)
        flushPendingLine()
    }

    func setScrollFraction(_ fraction: Double) {
        pendingScrollFraction = min(1, max(0, fraction))
        guard isReady, isLoaded, let webView else { return }
        Task {
            try? await Self.evaluateJavaScript(
                "window.scholiumEditor.setScrollFraction(\(pendingScrollFraction))",
                in: webView
            )
        }
    }

    func setLinkCompletions(_ candidates: [EditorLinkCompletion]) {
        pendingLinkCompletions = candidates
        guard isReady, let webView,
              let data = try? JSONEncoder().encode(candidates),
              let json = String(data: data, encoding: .utf8) else { return }
        Task {
            try? await Self.evaluateJavaScript(
                "window.scholiumEditor.setLinkCompletions(\(json))",
                in: webView
            )
        }
    }

    func setResearcherComments(_ comments: [ResearcherComment], in source: String) {
        let fingerprint = DocumentFingerprint(content: source)
        pendingResearcherComments = comments.compactMap { comment in
            guard let anchor = comment.anchor,
                  anchor.state == .attached,
                  anchor.fingerprint == fingerprint,
                  let from = Self.editorUTF16Offset(
                    forSourceUTF16Offset: anchor.utf16Range.lowerBound,
                    in: source
                  ),
                  let to = Self.editorUTF16Offset(
                    forSourceUTF16Offset: anchor.utf16Range.upperBound,
                    in: source
                  ),
                  to > from else { return nil }
            return EditorResearcherCommentAnnotation(
                id: comment.id,
                from: from,
                to: to,
                comment: String(comment.text.prefix(500)),
                resolved: comment.resolvedAt != nil
            )
        }
        guard isReady, isLoaded, let webView else { return }
        let payload = Self.jsonLiteral(pendingResearcherComments)
        Task {
            try? await Self.evaluateJavaScript(
                "window.scholiumEditor.setResearcherComments(\(payload))",
                in: webView
            )
        }
    }

    func currentText(for expectedDocumentID: String? = nil) async throws -> String {
        guard expectedDocumentID == nil || expectedDocumentID == documentID,
              isReady, isLoaded, let webView else { throw SessionError.unavailable }
        return try await Self.evaluateStringJavaScript("window.scholiumEditor.getText()", in: webView)
    }

    func currentSelection(
        for expectedDocumentID: String? = nil,
        in source: String? = nil
    ) async throws -> MarkdownReviewSelection? {
        guard expectedDocumentID == nil || expectedDocumentID == documentID,
              isReady, isLoaded, let webView else { throw SessionError.unavailable }
        guard let selection = try await Self.evaluateSelectionJavaScript(
            "window.scholiumEditor.getSelection()",
            in: webView
        ) else { return nil }
        guard let source, source.contains("\r\n"),
              let lower = selection.utf16LowerBound.flatMap({
                  Self.sourceUTF16Offset(forEditorUTF16Offset: $0, in: source)
              }),
              let upper = selection.utf16UpperBound.flatMap({
                  Self.sourceUTF16Offset(forEditorUTF16Offset: $0, in: source)
              }) else { return selection }
        return MarkdownReviewSelection(
            startLine: selection.startLine,
            endLine: selection.endLine,
            excerpt: selection.excerpt,
            utf16LowerBound: lower,
            utf16UpperBound: upper,
            contextBefore: selection.contextBefore,
            contextAfter: selection.contextAfter
        )
    }

    func synchronizeCommittedText(
        expectedText: String,
        committedText: String,
        fingerprint: DocumentFingerprint,
        documentID expectedDocumentID: String
    ) async throws -> Bool {
        guard expectedDocumentID == documentID,
              isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let script = """
        window.scholiumEditor.synchronizeCommittedText(
            \(Self.javascriptLiteral(expectedText)),
            \(Self.javascriptLiteral(committedText)),
            \(Self.javascriptLiteral(fingerprint.sha256))
        )
        """
        let synchronized = try await Self.evaluateBoolJavaScript(script, in: webView)
        guard synchronized, expectedDocumentID == documentID else { return false }
        isDirty = false
        committedTextSynchronizer?(committedText, fingerprint.sha256)
        return true
    }

    fileprivate func installCommittedTextSynchronizer(
        _ synchronizer: @escaping (String, String) -> Void
    ) {
        committedTextSynchronizer = synchronizer
    }

    fileprivate func removeCommittedTextSynchronizer() {
        committedTextSynchronizer = nil
    }

    func markClean() {
        isDirty = false
        guard isReady, let webView else { return }
        Task {
            try? await Self.evaluateJavaScript("window.scholiumEditor.markClean()", in: webView)
        }
    }

    func focus() {
        guard isReady, let webView else { return }
        Task {
            try? await Self.evaluateJavaScript("window.scholiumEditor.focus()", in: webView)
        }
    }

    func openFind() {
        performFindCommand("openFind")
    }

    func findNext() {
        performFindCommand("findNext")
    }

    func findPrevious() {
        performFindCommand("findPrevious")
    }

    func closeFind() {
        performFindCommand("closeFind")
    }

    private func performFindCommand(_ command: String) {
        guard isReady, isLoaded, let webView else { return }
        Task {
            try? await Self.evaluateJavaScript(
                "window.scholiumEditor.\(command)()",
                in: webView
            )
        }
    }

    private func flushPendingState() {
        guard isReady, let source = pendingSource, let webView else { return }
        pendingSource = nil
        let mode = pendingMode
        let documentID = pendingDocumentID
        let sessionID = sessionID.uuidString
        Task {
            do {
                let script = """
                window.scholiumEditor.setDocument(
                    \(Self.javascriptLiteral(source)),
                    \(Self.javascriptLiteral(sessionID)),
                    \(Self.javascriptLiteral(documentID)),
                    \(Self.javascriptLiteral(DocumentFingerprint(content: source).sha256))
                );
                window.scholiumEditor.setMode(\(Self.javascriptLiteral(mode.rawValue)));
                window.scholiumEditor.setUserCSS(\(Self.javascriptLiteral(pendingUserCSS)));
                window.scholiumEditor.setLinkCompletions(\(Self.jsonLiteral(pendingLinkCompletions)));
                window.scholiumEditor.setResearcherComments(\(Self.jsonLiteral(pendingResearcherComments)));
                window.scholiumEditor.setScrollFraction(\(pendingScrollFraction));
                true
                """
                try await Self.evaluateJavaScript(
                    script,
                    in: webView
                )
                isLoaded = true
                isDirty = false
                flushPendingLine()
                focus()
            } catch {
                isLoaded = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func flushPendingLine() {
        guard isReady, isLoaded, let line = pendingLine, let webView else { return }
        pendingLine = nil
        Task {
            try? await Self.evaluateJavaScript(
                "window.scholiumEditor.goToLine(\(line))",
                in: webView
            )
        }
    }

    private static func javascriptLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8) else { return "\"\"" }
        return literal
    }

    private static func jsonLiteral<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8) else { return "[]" }
        return literal
    }

    private static func evaluateJavaScript(_ script: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private static func evaluateStringJavaScript(_ script: String, in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let text = result as? String {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: SessionError.invalidResult)
                }
            }
        }
    }

    private static func evaluateBoolJavaScript(_ script: String, in webView: WKWebView) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let value = result as? Bool {
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(throwing: SessionError.invalidResult)
                }
            }
        }
    }

    private static func evaluateSelectionJavaScript(
        _ script: String,
        in webView: WKWebView
    ) async throws -> MarkdownReviewSelection? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if result == nil || result is NSNull {
                    continuation.resume(returning: nil)
                    return
                }
                guard let value = result as? [String: Any],
                      let startLine = (value["startLine"] as? NSNumber)?.intValue,
                      let endLine = (value["endLine"] as? NSNumber)?.intValue,
                      let excerpt = value["excerpt"] as? String,
                      let utf16LowerBound = (value["utf16LowerBound"] as? NSNumber)?.intValue,
                      let utf16UpperBound = (value["utf16UpperBound"] as? NSNumber)?.intValue,
                      let contextBefore = value["contextBefore"] as? String,
                      let contextAfter = value["contextAfter"] as? String else {
                    continuation.resume(throwing: SessionError.invalidResult)
                    return
                }
                guard utf16LowerBound >= 0,
                      utf16UpperBound > utf16LowerBound,
                      utf16UpperBound - utf16LowerBound <= 2_000 else {
                    continuation.resume(throwing: SessionError.selectionTooLong)
                    return
                }
                continuation.resume(returning: MarkdownReviewSelection(
                    startLine: startLine,
                    endLine: endLine,
                    excerpt: excerpt,
                    utf16LowerBound: utf16LowerBound,
                    utf16UpperBound: utf16UpperBound,
                    contextBefore: contextBefore,
                    contextAfter: contextAfter
                ))
            }
        }
    }

    private static func sourceUTF16Offset(
        forEditorUTF16Offset requestedOffset: Int,
        in source: String
    ) -> Int? {
        guard requestedOffset >= 0 else { return nil }
        let units = Array(source.utf16)
        var sourceOffset = 0
        var editorOffset = 0
        while sourceOffset < units.count, editorOffset < requestedOffset {
            if units[sourceOffset] == 13,
               sourceOffset + 1 < units.count,
               units[sourceOffset + 1] == 10 {
                sourceOffset += 2
            } else {
                sourceOffset += 1
            }
            editorOffset += 1
        }
        guard editorOffset == requestedOffset else { return nil }
        return sourceOffset
    }

    private static func editorUTF16Offset(
        forSourceUTF16Offset requestedOffset: Int,
        in source: String
    ) -> Int? {
        let units = Array(source.utf16)
        guard requestedOffset >= 0, requestedOffset <= units.count else { return nil }
        var sourceOffset = 0
        var editorOffset = 0
        while sourceOffset < requestedOffset {
            if units[sourceOffset] == 13,
               sourceOffset + 1 < units.count,
               units[sourceOffset + 1] == 10 {
                guard sourceOffset + 2 <= requestedOffset else { return nil }
                sourceOffset += 2
            } else {
                sourceOffset += 1
            }
            editorOffset += 1
        }
        return editorOffset
    }
}

struct MarkdownEditorWebView: NSViewRepresentable {
    @ObservedObject var session: MarkdownEditorSession
    let documentID: String
    let source: String
    let mode: NotePresentationMode
    let userCSS: String
    let linkCompletions: [EditorLinkCompletion]
    let researcherComments: [ResearcherComment]
    let initialScrollFraction: Double
    let onDocumentChange: (String) -> Void
    let onRequestSave: () -> Void
    let onCommentActivation: ((UUID) -> Void)?
    let onScrollFractionChange: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            session: session,
            onDocumentChange: onDocumentChange,
            onRequestSave: onRequestSave,
            onCommentActivation: onCommentActivation,
            onScrollFractionChange: onScrollFractionChange
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
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.documentID = documentID
        context.coordinator.source = source
        context.coordinator.startingFingerprint = DocumentFingerprint(content: source).sha256
        context.coordinator.mode = mode
        context.coordinator.userCSS = userCSS
        context.coordinator.linkCompletions = linkCompletions
        context.coordinator.researcherComments = researcherComments
        context.coordinator.initialScrollFraction = initialScrollFraction
        session.attach(webView)

        guard let editorHTML = Self.editorHTML,
              Self.editorScript != nil else {
            session.reportError("The bundled Markdown editor resources could not be found.")
            return webView
        }
        context.coordinator.awaitingEditorLoad = true
        webView.onFirstWindowAttachment = { [weak webView] in
            webView?.loadHTMLString(editorHTML, baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onDocumentChange = onDocumentChange
        context.coordinator.onRequestSave = onRequestSave
        context.coordinator.onCommentActivation = onCommentActivation
        context.coordinator.onScrollFractionChange = onScrollFractionChange
        context.coordinator.initialScrollFraction = initialScrollFraction
        if context.coordinator.userCSS != userCSS {
            context.coordinator.userCSS = userCSS
            session.setUserCSS(userCSS)
        }
        if context.coordinator.linkCompletions != linkCompletions {
            context.coordinator.linkCompletions = linkCompletions
            session.setLinkCompletions(linkCompletions)
        }
        if context.coordinator.researcherComments != researcherComments {
            context.coordinator.researcherComments = researcherComments
            session.setResearcherComments(researcherComments, in: source)
        }
        if context.coordinator.documentID != documentID {
            context.coordinator.documentID = documentID
            context.coordinator.source = source
            context.coordinator.startingFingerprint = DocumentFingerprint(content: source).sha256
            context.coordinator.lastDocumentVersion = 0
            session.loadDocument(source, documentID: documentID, mode: mode)
            session.setResearcherComments(researcherComments, in: source)
            session.setScrollFraction(initialScrollFraction)
        } else if context.coordinator.source != source {
            context.coordinator.source = source
            context.coordinator.startingFingerprint = DocumentFingerprint(content: source).sha256
            context.coordinator.lastDocumentVersion = 0
            session.loadDocument(source, documentID: documentID, mode: mode)
            session.setResearcherComments(researcherComments, in: source)
            session.setScrollFraction(initialScrollFraction)
        } else if context.coordinator.mode != mode {
            context.coordinator.mode = mode
            session.setMode(mode)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scholium")
        webView.navigationDelegate = nil
        coordinator.session.removeCommittedTextSynchronizer()
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

    private static var editorHTML: String? {
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
            <style>\(ScholiumWebFonts.css)\n\(css)\n\(ScholiumCalloutStyles.css)</style>
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
        var onCommentActivation: ((UUID) -> Void)?
        var onScrollFractionChange: (Double) -> Void
        var documentID = ""
        var source = ""
        var mode: NotePresentationMode = .livePreview
        var userCSS = ""
        var linkCompletions: [EditorLinkCompletion] = []
        var researcherComments: [ResearcherComment] = []
        var awaitingEditorLoad = false
        var startingFingerprint = ""
        var lastDocumentVersion = 0
        var initialScrollFraction: Double = 0
        private var hasSignaledReady = false

        init(
            session: MarkdownEditorSession,
            onDocumentChange: @escaping (String) -> Void,
            onRequestSave: @escaping () -> Void,
            onCommentActivation: ((UUID) -> Void)?,
            onScrollFractionChange: @escaping (Double) -> Void
        ) {
            self.session = session
            self.onDocumentChange = onDocumentChange
            self.onRequestSave = onRequestSave
            self.onCommentActivation = onCommentActivation
            self.onScrollFractionChange = onScrollFractionChange
            super.init()
            session.installCommittedTextSynchronizer { [weak self] source, fingerprint in
                guard let self else { return }
                self.source = source
                self.startingFingerprint = fingerprint
                self.lastDocumentVersion = 0
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "scholium",
                  JSONSerialization.isValidJSONObject(message.body),
                  let data = try? JSONSerialization.data(withJSONObject: message.body),
                  data.count <= 2_500_000,
                  let payload = try? JSONDecoder().decode(EditorBridgeMessage.self, from: data) else { return }

            switch payload.type {
            case "ready":
                signalReady()
            case "documentEnded":
                if payload.editorReady == true {
                    signalReady()
                } else {
                    session.reportError("The Markdown editor script did not initialize.")
                }
            case "editorError":
                session.reportError(payload.message ?? "The Markdown editor could not start.")
            case "stateChanged":
                guard validEnvelope(payload) else { return }
                session.updateState(
                    dirty: payload.dirty,
                    line: payload.line,
                    column: payload.column,
                    lineCount: payload.lineCount
                )
            case "documentChanged":
                guard validEnvelope(payload) else { return }
                applyEditorChanges(from: payload)
            case "requestSave":
                guard validEnvelope(payload) else { return }
                onRequestSave()
            case "commentActivated":
                guard validEnvelope(payload),
                      let rawID = payload.commentID,
                      let id = UUID(uuidString: rawID) else { return }
                onCommentActivation?(id)
            case "scrollChanged":
                guard validEnvelope(payload),
                      let fraction = payload.scrollFraction,
                      fraction.isFinite,
                      (0...1).contains(fraction) else { return }
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
            session.loadDocument(source, documentID: documentID, mode: mode)
            session.editorBecameReady()
            session.setUserCSS(userCSS)
            session.setLinkCompletions(linkCompletions)
            session.setResearcherComments(researcherComments, in: source)
            session.setScrollFraction(initialScrollFraction)
        }

        private func validEnvelope(_ payload: EditorBridgeMessage) -> Bool {
            guard payload.bridgeVersion == 1,
                  payload.sessionID == session.sessionID.uuidString,
                  payload.documentID == documentID,
                  payload.startingFingerprint == startingFingerprint,
                  let version = payload.documentVersion,
                  version >= lastDocumentVersion else { return false }
            return true
        }

        private func applyEditorChanges(from payload: EditorBridgeMessage) {
            guard let rawChanges = payload.changes,
                  !rawChanges.isEmpty,
                  rawChanges.count <= 512,
                  let version = payload.documentVersion,
                  version == lastDocumentVersion + 1 else { return }

            let sourceBeforeChanges = source
            let usesCRLF = sourceBeforeChanges.contains("\r\n")
            var changes: [MarkdownEditorDelta] = []
            var insertedUTF16Count = 0
            for raw in rawChanges {
                guard raw.from >= 0, raw.to >= raw.from else { return }
                insertedUTF16Count += raw.insert.utf16.count
                guard insertedUTF16Count <= 2_000_000 else { return }
                guard let rawFrom = Self.sourceUTF16Offset(
                    forEditorUTF16Offset: raw.from,
                    in: sourceBeforeChanges
                ), let rawTo = Self.sourceUTF16Offset(
                    forEditorUTF16Offset: raw.to,
                    in: sourceBeforeChanges
                ) else { return }
                changes.append(MarkdownEditorDelta(
                    fromUTF16: rawFrom,
                    toUTF16: rawTo,
                    insertion: usesCRLF
                        ? raw.insert.replacingOccurrences(of: "\n", with: "\r\n")
                        : raw.insert
                ))
            }
            guard let nextSource = try? MarkdownEditorDeltaApplier.apply(changes, to: source) else { return }
            source = nextSource
            lastDocumentVersion = version
            onDocumentChange(nextSource)
        }

        private static func sourceUTF16Offset(
            forEditorUTF16Offset requestedOffset: Int,
            in source: String
        ) -> Int? {
            guard requestedOffset >= 0 else { return nil }
            let units = Array(source.utf16)
            var sourceOffset = 0
            var editorOffset = 0
            while sourceOffset < units.count, editorOffset < requestedOffset {
                if units[sourceOffset] == 13,
                   sourceOffset + 1 < units.count,
                   units[sourceOffset + 1] == 10 {
                    sourceOffset += 2
                } else {
                    sourceOffset += 1
                }
                editorOffset += 1
            }
            guard editorOffset == requestedOffset else { return nil }
            return sourceOffset
        }
    }
}
