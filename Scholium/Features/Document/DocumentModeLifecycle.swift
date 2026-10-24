import AppKit
import Foundation
import ScholiumContracts

/// One explicit mode/activation request. Readiness may execute it once, but
/// cannot manufacture a later request after the researcher moved focus.
@MainActor
struct DocumentEditorFocusIntent {
    let id = UUID()
    let mode: MarkdownEditorMode
    let revision: UInt64
    let openingPresentationID: UUID
    let context: DocumentModeFocusContext
}

/// Shared by a requested editor focus and the failure return from Review.
/// Capture before the first suspension so newer native interaction revokes both.
@MainActor
final class DocumentModeFocusContext: NSObject {
    private weak var window: NSWindow?
    private weak var responder: NSResponder?
    private weak var fieldEditorOwner: NSTextField?
    private let capturedFieldEditor: Bool
    private var revoked = false

    init(window: NSWindow, responder: NSResponder?) {
        self.window = window
        self.responder = responder
        let fieldEditor = responder as? NSTextView
        let usesFieldEditor = fieldEditor?.isFieldEditor == true
        capturedFieldEditor = usesFieldEditor
        fieldEditorOwner = usesFieldEditor ? fieldEditor?.delegate as? NSTextField : nil
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(revoke(_:)), name: NSWindow.didResignKeyNotification, object: window)
        NotificationCenter.default.addObserver(
            self, selector: #selector(revoke(_:)), name: NSApplication.didResignActiveNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func revoke(_ notification: Notification) { revoked = true }

    /// Like Find's native return authority, losing activation permanently
    /// revokes this request. AppKit's shared field editor also requires the
    /// captured field owner, rather than just an unchanged responder pointer.
    func permitsFocus(in editor: MarkdownEditorSession) -> Bool {
        guard !revoked, let window, let webView = editor.webView,
            webView.window === window, window.isKeyWindow, !webView.isHiddenOrHasHiddenAncestor,
            window.attachedSheet == nil,
            (window.firstResponder as? any NSTextInputClient)?.hasMarkedText() != true
        else { return false }
        let current = window.firstResponder
        if current == nil || current === window || editor.hasWritingFocus { return true }
        guard current === responder else { return false }
        if capturedFieldEditor {
            return fieldEditorOwner != nil && (current as? NSTextView)?.delegate === fieldEditorOwner
        }
        return true
    }
}

extension DocumentController {
    func requestPresentationMode(
        _ mode: NotePresentationMode,
        session: DocumentSessionModel,
        target: DocumentEditingTarget,
        source: String,
        revision: DocumentFingerprint?
    ) {
        guard retainsSession(session, for: target), selectedDocument?.editingTarget == target,
            !session.presentationIsClosed, !session.editorSession.isComposing
        else { return }
        if mode == .read {
            requestReview(session: session, target: target)
            return
        }
        guard let editorMode = mode.editorMode else { return }
        session.cancelReviewHandoff()
        if session.isEditing {
            session.switchEditorMode(to: editorMode)
            requestEditorFocus(session: session, target: target)
        } else {
            beginEditing(session: session, target: target, source: source, revision: revision, mode: editorMode)
        }
        rememberPresentationMode(mode)
    }

    private func requestReview(session: DocumentSessionModel, target: DocumentEditingTarget) {
        session.cancelEditorFocusIntent()
        guard session.isEditing else {
            session.resetPresentation()
            rememberPresentationMode(.read)
            return
        }
        guard !session.returnToReadAfterSave else { return }
        if !session.editorSession.hasAttachedWebView {
            // An unmounted clean session has no focus/input to hand off. A
            // dirty or save-bearing session still fails finishEditing's exact
            // preservation guards instead of waiting for a page acquisition.
            do {
                try finishEditing(session: session, target: target)
                rememberPresentationMode(.read)
            } catch {
                session.editError = ScholiumErrorLocalization.message(error)
                session.canRetrySave = Self.saveFailureAllowsRetry(error)
                setSaveError(session.editError)
            }
            return
        }
        let originContext = session.editorSession.webView?.window.map {
            DocumentModeFocusContext(window: $0, responder: $0.firstResponder)
        }
        session.beginReviewHandoff { [weak self, weak session] id in
            guard let self, let session else { return }
            @MainActor func ownsHandoff() -> Bool {
                !Task.isCancelled && session.reviewHandoffID == id && !session.presentationIsClosed
                    && self.retainsSession(session, for: target)
                    && self.selectedDocument?.editingTarget == target
            }
            guard ownsHandoff() else { return }
            do {
                let anchor = try? await session.editorSession.currentScrollAnchor()
                guard ownsHandoff() else { return }
                session.adoptEditorScrollPositionForReview(anchor: anchor)
                // Revoke focus before awaiting initialization. Input accepted
                // before the acknowledged blur belongs in this final save.
                await session.editorSession.resignFocusAndWait()
                guard ownsHandoff() else { return }
                try await self.flushForExternalOperation(session: session, target: target)
                guard ownsHandoff() else { return }
                let fingerprint = DocumentFingerprint(content: session.originalEditingSource).sha256
                if session.renderedReadReadyFingerprint != fingerprint {
                    session.renderedReadReadyFingerprint = ""
                }
                try self.finishEditing(session: session, target: target)
                self.rememberPresentationMode(.read)
            } catch is CancellationError {
                return
            } catch {
                guard ownsHandoff() else { return }
                session.editError = ScholiumErrorLocalization.message(error)
                session.canRetrySave = Self.saveFailureAllowsRetry(error)
                self.setSaveError(session.editError)
                session.completeReviewHandoff(id)
                // A failed save restores only the initiating native context;
                // an intervening field/sheet/window owns its newer focus.
                if let originContext {
                    self.requestEditorFocus(session: session, target: target, nativeContext: originContext)
                }
            }
        }
    }

    func requestEditorFocusAfterActivation(session: DocumentSessionModel, target: DocumentEditingTarget) {
        guard session.editorFocusIntent == nil else { return }
        requestEditorFocus(session: session, target: target)
    }

    func requestEditorFocus(
        session: DocumentSessionModel,
        target: DocumentEditingTarget,
        authorizing: Bool = true,
        nativeContext: DocumentModeFocusContext? = nil
    ) {
        guard retainsSession(session, for: target), selectedDocument?.editingTarget == target,
            !session.presentationIsClosed, session.isEditing, !session.returnToReadAfterSave,
            let mode = session.activeEditorMode
        else { return }
        if let nativeContext, !nativeContext.permitsFocus(in: session.editorSession) { return }
        session.cancelEditorFocusIntent()
        if authorizing { session.editorSession.authorizeAutomaticFocus() }
        guard NSApp?.isActive == true, let window = session.editorSession.webView?.window ?? NSApp?.keyWindow,
            window.isKeyWindow
        else { return }
        session.editorFocusIntent = DocumentEditorFocusIntent(
            mode: mode, revision: session.editorSession.focusRequestRevision,
            openingPresentationID: session.editorSession.openingPresentationID,
            context: nativeContext ?? DocumentModeFocusContext(window: window, responder: window.firstResponder))
        reconcileEditorFocusIntent(for: session)
    }

    /// Called by the controller's coalesced session observer. It consumes only
    /// an existing intent, after native presentation has exposed the mode.
    func reconcileEditorFocusIntent(for session: DocumentSessionModel) {
        guard let selected = selectedDocument, retainsSession(session, for: selected.editingTarget) else { return }
        guard let intent = session.editorFocusIntent, session.editorFocusTask == nil else { return }
        let editor = session.editorSession
        guard session.isEditing, !session.returnToReadAfterSave, !session.presentationIsClosed,
            session.activeEditorMode == intent.mode,
            editor.openingPresentationID == intent.openingPresentationID,
            editor.focusRequestRevision == intent.revision
        else {
            session.cancelEditorFocusIntent()
            return
        }
        guard editor.isLoaded, editor.presentedMode == intent.mode,
            !session.isSavingEdit,
            editor.detachmentSuspensionID == nil
        else { return }
        session.editorFocusTask = Task { @MainActor [weak self, weak session] in
            guard let self, let session else { return }
            var waitsForIdle = false
            defer {
                if session.editorFocusIntent?.id == intent.id {
                    session.editorFocusTask = nil
                    if !waitsForIdle { session.editorFocusIntent = nil }
                }
            }
            await Task.yield()
            guard !Task.isCancelled else { return }
            try? await editor.focusIfPresented(in: intent.mode, requiringFocusRevision: intent.revision) { [weak self, weak session] in
                guard let self, let session, !Task.isCancelled,
                    session.editorFocusIntent?.id == intent.id,
                    !session.presentationIsClosed, !session.returnToReadAfterSave,
                    session.isEditing, session.activeEditorMode == intent.mode,
                    editor.openingPresentationID == intent.openingPresentationID,
                    let selected = self.selectedDocument,
                    self.peekRetainedSession(for: selected.editingTarget) === session,
                    NSApp?.isActive == true, intent.context.permitsFocus(in: editor),
                    !session.findPresentation.isPresented, !session.showConflictComparison
                else { return false }
                guard !session.isSavingEdit,
                    editor.detachmentSuspensionID == nil
                else {
                    waitsForIdle = true
                    return false
                }
                return session.inputResumeError == nil
            }
        }
    }
}
