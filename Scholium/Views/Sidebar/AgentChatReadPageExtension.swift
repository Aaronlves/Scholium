import AppKit
import ScholiumContracts
import SwiftUI
import WebKit

enum ReadReplyEvent {
    case interaction
    case layout(height: CGFloat, intrinsicWidth: CGFloat?, objects: [ReadReplyObject])
    case quote(String)
    case selectionContext(String, point: NSPoint, view: NSView)
    case noteContext(URL, point: NSPoint, view: NSView)
}

/// Identifies inline rich content to the transcript-owned wheel boundary.
final class AgentChatReadWebView: WKWebView {}

/// Untrusted DOM geometry is a bounded presentation projection, never content authority.
struct ReadReplyObject: Identifiable, Equatable {
    let id: String
    let frame: CGRect
    let naturalSize: CGSize

    static func decode(_ value: Any?) -> [Self]? {
        guard let entries = value as? [[String: Any]], entries.count < 10_000 else { return nil }
        var result: [Self] = []
        var identities: Set<String> = []
        for entry in entries {
            guard let identity = entry["identity"] as? String, !identity.isEmpty, identity.utf8.count < 128,
                identities.insert(identity).inserted
            else { return nil }
            let keys = ["left", "top", "width", "height", "naturalWidth", "naturalHeight"]
            let numbers = keys.compactMap { entry[$0] as? Double }
            guard numbers.count == keys.count,
                numbers.allSatisfy({ $0.isFinite && abs($0) < 1_000_000 }),
                numbers.dropFirst(2).allSatisfy({ $0 > 0 })
            else { return nil }
            result.append(
                Self(
                    id: identity,
                    frame: CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]),
                    naturalSize: CGSize(width: numbers[4], height: numbers[5])))
        }
        return result
    }
}

/// Chat owns reply lifecycle, reply events and the transcript-specific WebKit
/// subclass. The neutral Review reader only transports this bounded extension.
@MainActor
final class AgentChatReadPageExtension: ScholiumReadPageExtension {
    var onEvent: ((ReadReplyEvent) -> Void)?
    private var replyNavigationReady = false
    private var pendingReplyUpdate: (() -> Void)?
    private var replyPageFingerprint: String?
    private var replyUpdateTask: Task<Void, Never>?
    private var replyPageGeneration: UInt64 = 0

    init(onEvent: ((ReadReplyEvent) -> Void)? = nil) {
        self.onEvent = onEvent
    }

    func update(onEvent: @escaping (ReadReplyEvent) -> Void) {
        self.onEvent = onEvent
    }

    var requiresDedicatedWebView: Bool { true }
    var requiresMathRuntime: Bool { true }
    var replyProjectionEnabled: Bool { true }

    func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        AgentChatReadWebView(frame: .zero, configuration: configuration)
    }

    func preservesPage(
        currentDocumentID: String,
        nextDocumentID: String,
        hasLoadedPage: Bool
    ) -> Bool {
        hasLoadedPage && currentDocumentID == nextDocumentID
    }

    func canUpdateInPlace(
        currentDocumentID: String,
        nextDocumentID: String,
        hasLoadedPage: Bool
    ) -> Bool {
        preservesPage(
            currentDocumentID: currentDocumentID,
            nextDocumentID: nextDocumentID,
            hasLoadedPage: hasLoadedPage
        ) && replyPageFingerprint != nil
    }

    func acceptsMessageWithoutCurrentFingerprint(type: String) -> Bool {
        type == "replyInteraction"
    }

    func willBeginLoad(fingerprint _: String) {
        replyPageGeneration &+= 1
        replyNavigationReady = false
        pendingReplyUpdate = nil
        replyPageFingerprint = nil
        replyUpdateTask?.cancel()
        replyUpdateTask = nil
    }

    func updateIfNeeded(
        body: String,
        source: String,
        fingerprint: String,
        signature: String,
        documentID: String,
        loadGeneration: UInt64,
        presentationCSS: String,
        userCSS: String,
        in webView: WKWebView,
        isCurrent: @escaping @MainActor () -> Bool,
        didApply: @escaping @MainActor (_ source: String, _ fingerprint: String) -> Void,
        didFail: @escaping @MainActor (_ error: any Error) -> Void
    ) -> Bool {
        guard replyPageFingerprint != nil else { return false }
        let pageGeneration = replyPageGeneration
        let update = { [weak self, weak webView] in
            guard let self, let webView else { return }
            let previousTask = self.replyUpdateTask
            self.replyUpdateTask = Task { @MainActor [weak self, weak webView] in
                await previousTask?.value
                guard let self, let webView, !Task.isCancelled,
                    isCurrent(), self.replyPageGeneration == pageGeneration,
                    let previousFingerprint = self.replyPageFingerprint
                else { return }
                defer { if isCurrent() { self.replyUpdateTask = nil } }
                do {
                    guard body.utf8.count <= 16_777_216 else { throw CocoaError(.coderReadCorrupt) }
                    let updated = try await webView.callAsyncJavaScript(
                        """
                        if (window.scholiumReadReady) await window.scholiumReadReady;
                        return await window.scholiumUpdateReply?.(update) === true;
                        """,
                        arguments: [
                            "update": [
                                "version": 7, "documentID": documentID, "loadGeneration": loadGeneration,
                                "previousFingerprint": previousFingerprint, "fingerprint": fingerprint,
                                "html": body, "presentationCSS": presentationCSS, "userCSS": userCSS,
                            ]
                        ], in: nil, contentWorld: SafeMarkdownReadWebView.bridgeContentWorld)
                    guard !Task.isCancelled, self.replyPageGeneration == pageGeneration else { return }
                    guard updated as? Bool == true else { throw CocoaError(.coderReadCorrupt) }
                    // JavaScript may commit while a newer source becomes current.
                    // The next queued update must start from the actual DOM revision;
                    // only the current source may publish readiness and selection.
                    self.replyPageFingerprint = fingerprint
                    if isCurrent() { didApply(source, fingerprint) }
                } catch {
                    guard !Task.isCancelled, self.replyPageGeneration == pageGeneration, isCurrent() else { return }
                    didFail(error)
                }
            }
        }
        if replyNavigationReady {
            update()
        } else {
            pendingReplyUpdate = update
        }
        return true
    }

    func didFinishNavigation(
        _ navigation: WKNavigation?,
        isCurrent: @escaping @MainActor () -> Bool
    ) {
        guard isCurrent() else { return }
        replyNavigationReady = true
        let pending = pendingReplyUpdate
        pendingReplyUpdate = nil
        pending?()
    }

    func didFinalizePage(fingerprint: String) {
        replyPageFingerprint = fingerprint
    }

    func handleMessage(
        type: String,
        payload: [String: Any],
        webView: WKWebView?
    ) -> Bool {
        switch type {
        case "replyInteraction":
            onEvent?(.interaction)
        case "replyLayout":
            guard let height = payload["height"] as? Double, height.isFinite, height > 0,
                height < 1_000_000
            else { return true }
            let width = payload["intrinsicWidth"] as? Double
            guard payload["intrinsicWidth"] is NSNull
                    || width.map({ $0.isFinite && $0 > 0 && $0 < 1_000_000 }) == true,
                let objects = ReadReplyObject.decode(payload["objects"])
            else { return true }
            onEvent?(.layout(height: height, intrinsicWidth: width.map { CGFloat($0) }, objects: objects))
        case "replyNoteContext":
            guard let rawURL = payload["url"] as? String, rawURL.utf8.count <= 8_192,
                let url = URL(string: rawURL), AgentChatReference.parse(url) != nil,
                let left = payload["left"] as? Double, let top = payload["top"] as? Double,
                left.isFinite, top.isFinite, let view = webView,
                view.bounds.contains(NSPoint(x: left, y: top))
            else { return true }
            onEvent?(.noteContext(url, point: NSPoint(x: left, y: top), view: view))
        case "replySelectionContext":
            guard let text = payload["text"] as? String, !text.isEmpty, text.utf8.count <= 65_536,
                let left = payload["left"] as? Double, let top = payload["top"] as? Double,
                left.isFinite, top.isFinite, let view = webView,
                view.bounds.contains(NSPoint(x: left, y: top))
            else { return true }
            onEvent?(.selectionContext(text, point: NSPoint(x: left, y: top), view: view))
        case "replyQuote":
            if let text = payload["text"] as? String, !text.isEmpty, text.utf8.count <= 65_536 {
                onEvent?(.quote(text))
            }
        default:
            return false
        }
        return true
    }

    func cancel() {
        replyPageGeneration &+= 1
        replyUpdateTask?.cancel()
        replyUpdateTask = nil
        pendingReplyUpdate = nil
        replyNavigationReady = false
        replyPageFingerprint = nil
    }
}

/// Chat's thin host adapter. The shared reader remains responsible for safe
/// HTML, source locations and WebKit lifetime; this view supplies only the
/// transcript-specific page extension and callback.
struct AgentChatReadWebViewSurface: View {
    let documentID: String
    let documentTitle: String
    let fingerprint: String
    let source: String
    let htmlBody: String
    let presentationCSS: String
    let userCSS: String
    let onLinkClick: (String) -> Void
    let onOpenExternalURL: (URL) -> Void
    let renderingReadinessIsAcknowledged: Bool
    let onRenderingFailure: ((String) -> Void)?
    let onRenderingLoading: (() -> Void)?
    let onRenderingReady: (() -> Void)?
    let onEvent: (ReadReplyEvent) -> Void
    @State private var pageExtension: AgentChatReadPageExtension

    init(
        documentID: String,
        documentTitle: String = "",
        fingerprint: String,
        source: String,
        htmlBody: String,
        presentationCSS: String,
        userCSS: String,
        onLinkClick: @escaping (String) -> Void,
        onOpenExternalURL: @escaping (URL) -> Void,
        renderingReadinessIsAcknowledged: Bool,
        onRenderingFailure: ((String) -> Void)?,
        onRenderingLoading: (() -> Void)?,
        onRenderingReady: (() -> Void)?,
        onEvent: @escaping (ReadReplyEvent) -> Void
    ) {
        self.documentID = documentID
        self.documentTitle = documentTitle
        self.fingerprint = fingerprint
        self.source = source
        self.htmlBody = htmlBody
        self.presentationCSS = presentationCSS
        self.userCSS = userCSS
        self.onLinkClick = onLinkClick
        self.onOpenExternalURL = onOpenExternalURL
        self.renderingReadinessIsAcknowledged = renderingReadinessIsAcknowledged
        self.onRenderingFailure = onRenderingFailure
        self.onRenderingLoading = onRenderingLoading
        self.onRenderingReady = onRenderingReady
        self.onEvent = onEvent
        _pageExtension = State(initialValue: AgentChatReadPageExtension(onEvent: onEvent))
    }

    var body: some View {
        let _ = pageExtension.update(onEvent: onEvent)
        SafeMarkdownReadWebView(
            documentID: documentID,
            documentTitle: documentTitle,
            fingerprint: fingerprint,
            source: source,
            htmlBody: htmlBody,
            presentationCSS: presentationCSS,
            userCSS: userCSS,
            onLinkClick: onLinkClick,
            onOpenExternalURL: onOpenExternalURL,
            selectionSurfaceIsActive: false,
            renderingReadinessIsAcknowledged: renderingReadinessIsAcknowledged,
            onRenderingFailure: onRenderingFailure,
            onRenderingLoading: onRenderingLoading,
            onRenderingReady: onRenderingReady,
            pageExtension: pageExtension
        )
    }
}
