import AppKit
import ScholiumContracts
import ScholiumEditor
import SwiftUI

/// SwiftUI owns presentation; the retained session owns the one text view and
/// its source. Updating a view never reloads the document or creates Undo entries.
struct NativeMarkdownEditorView: NSViewRepresentable {
    @ObservedObject var session: MarkdownEditorSession
    let documentID: String
    let documentTitle: String
    var performanceDocumentID: String? = nil
    let source: String
    let mode: MarkdownEditorMode
    let appearance: DocumentAppearanceSettings
    let documentTextScale: Double
    let initialScrollFraction: Double
    let initialScrollAnchor: EditorScrollAnchor?
    let onDocumentActivity: () -> Void
    let onRequestSave: () -> Void
    let onRequestFind: (DocumentFindShortcut) -> Void
    let onLinkActivation: (String) -> Void
    let onScrollFractionChange: (Double) -> Void
    let onScrollAnchorChange: (EditorScrollAnchor) -> Void
    let interactions: NativeEditorInteractions

    func makeCoordinator() -> Coordinator { Coordinator(session: session, interactions: interactions) }

    func makeNSView(context: Context) -> NativeEditorContainer {
        session.performanceDocumentID = performanceDocumentID ?? documentID
        PerformanceProbe.shared.markReadTaskStarted(documentID: session.performanceDocumentID)
        if session.documentID != documentID {
            session.loadDocument(source, documentID: documentID, mode: mode)
        }
        installCallbacks(in: context.coordinator)
        session.applyAppearance(appearance, textScale: documentTextScale)
        context.coordinator.appearance = appearance
        context.coordinator.textScale = documentTextScale
        session.setDocumentTitle(documentTitle)
        session.setMode(mode)
        if session.pendingScrollAnchor == nil { session.pendingScrollAnchor = initialScrollAnchor }
        session.pendingScrollFraction = session.retainedScrollFraction(fallback: initialScrollFraction)
        let attachment = session.attachNativeView()
        context.coordinator.attachmentID = attachment
        PerformanceProbe.shared.markReadSourceReady(documentID: session.performanceDocumentID)
        let container = NativeEditorContainer(session: session)
        container.setAccessibilityIdentifier("scholium.document.\(session.performanceDocumentID)")
        context.coordinator.interactions.attach(to: session, attachmentID: attachment)
        return container
    }

    func updateNSView(_ nsView: NativeEditorContainer, context: Context) {
        context.coordinator.interactions.update(from: interactions)
        installCallbacks(in: context.coordinator)
        if context.coordinator.appearance != appearance || context.coordinator.textScale != documentTextScale {
            session.applyAppearance(appearance, textScale: documentTextScale)
            context.coordinator.appearance = appearance
            context.coordinator.textScale = documentTextScale
        }
        session.setDocumentTitle(documentTitle)
        if session.presentedMode != mode { session.setMode(mode) }
    }

    private func installCallbacks(in coordinator: Coordinator) {
        session.onDocumentActivity = onDocumentActivity
        session.onLinkActivation = onLinkActivation
        session.nativeEditor.openLinkMenuTitle = ScholiumL10n.string("Open Link")
        session.onScrollFractionChange = onScrollFractionChange
        session.onScrollAnchorChange = onScrollAnchorChange
        coordinator.interactions.onRequestSave = onRequestSave
        coordinator.interactions.onRequestFind = onRequestFind
    }

    static func dismantleNSView(_ nsView: NativeEditorContainer, coordinator: Coordinator) {
        if let attachment = coordinator.attachmentID,
            coordinator.session.isCurrentAttachment(attachment)
        {
            coordinator.interactions.detach()
            coordinator.session.detachNativeView(attachmentID: attachment)
        }
        if coordinator.session.scrollView.superview === nsView {
            coordinator.session.scrollView.removeFromSuperview()
        }
    }

    @MainActor final class Coordinator {
        let session: MarkdownEditorSession
        let interactions: NativeEditorInteractions
        var attachmentID: UUID?
        var appearance: DocumentAppearanceSettings?
        var textScale: Double?
        init(session: MarkdownEditorSession, interactions: NativeEditorInteractions) {
            self.session = session
            self.interactions = interactions
        }
    }
}

@MainActor
final class NativeEditorContainer: NSView {
    private weak var session: MarkdownEditorSession?

    init(session: MarkdownEditorSession) {
        self.session = session
        super.init(frame: session.scrollView.frame)
        addSubview(session.scrollView)
    }
    required init?(coder: NSCoder) { fatalError("NativeEditorContainer is constructed with a document session") }

    override func layout() {
        super.layout()
        guard let session else { return }
        // Document content fills the safe area below the toolbar title control.
        session.scrollView.frame = safeAreaRect
        guard window != nil, session.isLoaded, let mode = session.presentedMode else { return }
        let identity = session.performanceDocumentID
        PerformanceProbe.shared.markReadNativeLayoutStarted(documentID: identity)
        PerformanceProbe.shared.markReadNativeLayoutFinished(documentID: identity)
        if mode == .read {
            PerformanceProbe.shared.markReadReady(documentID: identity)
        } else {
            PerformanceProbe.shared.markEditorVisible(documentID: identity)
        }
        PerformanceProbe.shared.markEditorModeVisible(documentID: identity, mode: mode)
        PerformanceProbe.shared.markEditorModeReady(documentID: identity, mode: mode)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            needsLayout = true
            session?.activateAttachedView()
        }
    }
}
