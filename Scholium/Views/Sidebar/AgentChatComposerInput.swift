import AppKit
import SwiftUI

/// One native multiline editor owns the entire message input region, including
/// whitespace, selection, Undo, marked text and Return commands.
struct AgentChatComposerInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let conversationID: UUID?
    let isEnabled: Bool
    let submit: () -> Void

    func makeNSView(context: Context) -> AgentChatComposerHost {
        AgentChatComposerHost()
    }

    func updateNSView(_ host: AgentChatComposerHost, context: Context) {
        if host.conversationID != conversationID {
            // Finish the previous native draft through its captured binding.
            host.commitCurrentDraft()
            host.editor.unmarkText()
            host.conversationID = conversationID
            host.editor.string = text
            host.editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            host.editor.undoManager?.removeAllActions()
            host.lastPublishedText = text
        } else if host.editor.string != text, !host.editor.hasMarkedText() {
            let selection = host.editor.selectedRange()
            host.editor.string = text
            host.editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            host.lastPublishedText = text
        }
        host.onEdit = { text = $0 }
        host.onFocus = { isFocused = $0 }
        host.editor.onSubmit = submit
        host.editor.isEditable = isEnabled
        host.editor.isSelectable = isEnabled
        if host.focusValue != isFocused {
            host.focusValue = isFocused
            host.requestedFocus = isFocused
        }
        host.invalidateIntrinsicContentSize()
        host.needsLayout = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AgentChatComposerHost, context: Context) -> CGSize? {
        // SwiftUI also probes an unbounded size. Do not pass that probe into
        // AppKit's text layout or its constraint system.
        let proposedWidth = proposal.width ?? nsView.bounds.width
        let width = proposedWidth.isFinite && proposedWidth < CGFloat.greatestFiniteMagnitude
            ? max(1, proposedWidth) : max(1, nsView.bounds.width)
        return CGSize(width: width, height: nsView.fittingHeight(width: width))
    }

    static func dismantleNSView(_ host: AgentChatComposerHost, coordinator: ()) {
        host.commitCurrentDraft()
        host.onEdit = nil; host.onFocus = nil; host.editor.onSubmit = nil
        host.editor.delegate = nil
    }
}

@MainActor final class AgentChatComposerHost: NSScrollView, NSTextViewDelegate {
    let editor = AgentChatComposerTextView(frame: .zero)
    var conversationID: UUID?
    var onEdit: ((String) -> Void)?
    var onFocus: ((Bool) -> Void)?
    var focusValue = false
    var requestedFocus: Bool?
    var lastPublishedText = ""

    init() {
        super.init(frame: .zero)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        autohidesScrollers = true
        editor.isRichText = false
        editor.importsGraphics = false
        editor.drawsBackground = false
        editor.allowsUndo = true
        editor.font = .systemFont(ofSize: NSFont.systemFontSize)
        editor.textColor = .textColor
        editor.textContainerInset = NSSize(width: 4, height: 6)
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.delegate = self
        editor.setAccessibilityLabel(String(localized: "Message", bundle: .module))
        editor.setAccessibilityIdentifier("scholium.chat.message")
        documentView = editor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let height = measuredTextHeight(width: contentSize.width)
        // NSTextView, not a click overlay, receives every point in the input slot.
        editor.minSize = NSSize(width: 0, height: contentSize.height)
        editor.setFrameSize(NSSize(width: contentSize.width, height: max(contentSize.height, height)))
        if let requestedFocus, let window {
            self.requestedFocus = nil
            if requestedFocus, window.firstResponder !== editor { window.makeFirstResponder(editor) }
            if !requestedFocus, window.firstResponder === editor { window.makeFirstResponder(nil) }
        }
    }

    func fittingHeight(width: CGFloat) -> CGFloat {
        let lineHeight = editor.layoutManager?.defaultLineHeight(for: editor.font ?? .systemFont(ofSize: NSFont.systemFontSize)) ?? 17
        return min(max(40, measuredTextHeight(width: width)), lineHeight * 7 + 12)
    }

    private func measuredTextHeight(width: CGFloat) -> CGFloat {
        guard let container = editor.textContainer, let manager = editor.layoutManager else { return 40 }
        editor.setFrameSize(NSSize(width: max(1, width), height: editor.frame.height))
        container.containerSize = NSSize(width: max(1, width - 2 * editor.textContainerInset.width), height: CGFloat.greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        return ceil(manager.usedRect(for: container).height + 2 * editor.textContainerInset.height)
    }

    func commitCurrentDraft() {
        guard editor.string != lastPublishedText else { return }
        lastPublishedText = editor.string
        onEdit?(editor.string)
    }
    func textDidChange(_ notification: Notification) {
        commitCurrentDraft()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }
    func textDidBeginEditing(_ notification: Notification) { onFocus?(true) }
    func textDidEndEditing(_ notification: Notification) {
        commitCurrentDraft()
        onFocus?(false)
    }
}

@MainActor final class AgentChatComposerTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText() {
            if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option) {
                insertNewlineIgnoringFieldEditor(nil)
            } else {
                onSubmit?()
            }
            return
        }
        super.keyDown(with: event)
    }
}
