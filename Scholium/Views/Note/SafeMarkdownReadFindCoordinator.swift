import AppKit
import Foundation
import WebKit

/// A Find dismissal may return focus only while its native initiator still
/// owns that handoff. AppKit reuses field editors, so responder identity alone
/// cannot distinguish the Find field from a newer text-field interaction.
@MainActor
final class DocumentFindFocusReturnAuthority: NSObject {
    private weak var window: NSWindow?
    private weak var responder: NSResponder?
    private weak var findField: NSTextField?
    private let capturedFieldEditor: Bool
    private var revoked = false

    init?(webView: WKWebView) {
        guard let window = webView.window, window.isKeyWindow,
            !webView.isHiddenOrHasHiddenAncestor, window.attachedSheet == nil,
            (window.firstResponder as? any NSTextInputClient)?.hasMarkedText() != true
        else { return nil }
        let responder = window.firstResponder
        let fieldEditor = responder as? NSTextView
        let findField = fieldEditor?.isFieldEditor == true ? fieldEditor?.delegate as? NSTextField : responder as? NSTextField
        let isFindField =
            findField.map {
                ["scholium.documentFind.query", "scholium.documentFind.replacement"].contains($0.accessibilityIdentifier())
            } ?? false
        guard
            responder == nil || responder === window
                || (responder as? NSView)?.isDescendant(of: webView) == true || isFindField
        else { return nil }
        self.window = window
        self.responder = responder
        self.findField = isFindField ? findField : nil
        capturedFieldEditor = fieldEditor?.isFieldEditor == true
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(revoke(_:)), name: NSWindow.didResignKeyNotification, object: window)
        NotificationCenter.default.addObserver(
            self, selector: #selector(revoke(_:)), name: NSApplication.didResignActiveNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func revoke(_ notification: Notification) { revoked = true }

    func canRestore(to webView: WKWebView) -> Bool {
        guard !revoked, let window, webView.window === window, window.isKeyWindow,
            !webView.isHiddenOrHasHiddenAncestor, window.attachedSheet == nil,
            (window.firstResponder as? any NSTextInputClient)?.hasMarkedText() != true
        else { return false }
        let current = window.firstResponder
        if current == nil || current === window || (current as? NSView)?.isDescendant(of: webView) == true { return true }
        guard current === responder else { return false }
        if capturedFieldEditor {
            return findField != nil && (current as? NSTextView)?.delegate === findField
        }
        return findField != nil && current === findField
    }
}

/// Owns one Review find request, its applied identity, and the cancellable
/// WebKit query. Page load identity remains supplied by the parent coordinator.
@MainActor
final class SafeMarkdownReadFindCoordinator {
    var bridgeContentWorld = SafeMarkdownReadWebView.bridgeContentWorld
    private var request: DocumentFindPresentationRequest?
    private var report: ((UInt64, Result<DocumentFindResult, any Error>) -> Void)?
    private var appliedRequestID: UInt64?
    private var task: Task<Void, Never>?

    func update(
        request: DocumentFindPresentationRequest?,
        report: ((UInt64, Result<DocumentFindResult, any Error>) -> Void)?
    ) {
        self.request = request
        self.report = report
    }

    func resetForDocumentChange() {
        appliedRequestID = nil
        cancel()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func applyIfNeeded(
        pageIsReady: Bool,
        in webView: WKWebView,
        isCurrent: @escaping @MainActor () -> Bool
    ) {
        guard pageIsReady,
            let request,
            request.id != appliedRequestID
        else { return }
        appliedRequestID = request.id
        let arguments: [String: Any]
        switch request.operation {
        case .clear:
            arguments = ["operation": "clear"]
        case .execute(let action):
            arguments = [
                "operation": "execute",
                "action": action.rawValue,
                "query": request.query,
                "replacement": request.replacement,
                "caseSensitive": request.caseSensitive,
                "wholeWord": request.wholeWord,
            ]
        }
        task?.cancel()
        let focusReturn: DocumentFindFocusReturnAuthority?
        if case .clear = request.operation {
            focusReturn = DocumentFindFocusReturnAuthority(webView: webView)
        } else {
            focusReturn = nil
        }
        task = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            do {
                let raw = try await webView.callAsyncJavaScript(
                    "return window.scholiumReviewFind?.perform(request)",
                    arguments: ["request": arguments],
                    in: nil,
                    contentWorld: self.bridgeContentWorld
                )
                guard !Task.isCancelled,
                    isCurrent(),
                    self.request?.id == request.id,
                    let payload = raw as? [String: Any],
                    let current = (payload["current"] as? NSNumber)?.intValue,
                    let total = (payload["total"] as? NSNumber)?.intValue,
                    current >= 0,
                    total >= 0,
                    current <= total
                else { return }
                if case .clear = request.operation, focusReturn?.canRestore(to: webView) == true {
                    webView.window?.makeFirstResponder(webView)
                }
                self.report?(
                    request.id,
                    .success(DocumentFindResult(current: current, total: total))
                )
            } catch {
                guard !Task.isCancelled,
                    isCurrent(),
                    self.request?.id == request.id
                else { return }
                self.report?(request.id, .failure(error))
            }
        }
    }
}
