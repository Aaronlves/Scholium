import AppKit
import ScholiumContracts
import SwiftUI

/// One native multiline editor owns the entire message input region, including
/// whitespace, selection, Undo, marked text and Return commands.
struct AgentChatComposerInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let conversationID: UUID?
    let isEnabled: Bool
    let submit: () -> Void
    var completion: AgentChatComposerCompletion? = nil
    var candidates: [AgentChatComposerCandidate] = []
    var candidateQuery: AgentChatComposerQuery? = nil
    var chooseCompletion: ((AgentChatComposerCandidate) -> Void)? = nil
    var transferMaterials: (([AgentChatTransferredMaterial], AgentChatLocalMaterial.CaptureOrigin) -> Void)? = nil

    func makeNSView(context: Context) -> AgentChatComposerHost {
        AgentChatComposerHost()
    }

    func updateNSView(_ host: AgentChatComposerHost, context: Context) {
        host.completion = completion
        host.editor.completionConversationID = conversationID
        completion?.editor = host.editor
        completion?.candidates = candidates
        completion?.candidateQuery = candidateQuery
        completion?.choose = chooseCompletion
        host.editor.onCompletionKey = { [weak completion] event in completion?.keyDown(event) ?? false }
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
        host.onFocus = { if isFocused != $0 { isFocused = $0 } }
        host.editor.onSubmit = submit
        host.editor.onTransferMaterials = transferMaterials
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
        let width =
            proposedWidth.isFinite && proposedWidth < CGFloat.greatestFiniteMagnitude
            ? max(1, proposedWidth) : max(1, nsView.bounds.width)
        return CGSize(width: width, height: nsView.fittingHeight(width: width))
    }

    static func dismantleNSView(_ host: AgentChatComposerHost, coordinator: ()) {
        host.commitCurrentDraft()
        host.onEdit = nil
        host.onFocus = nil
        host.editor.onSubmit = nil
        host.editor.onTransferMaterials = nil
        host.editor.onFocusChange = nil
        host.editor.delegate = nil
        host.editor.onCompletionKey = nil
        host.completion?.detach(from: host.editor)
        host.completion = nil
    }
}

@MainActor final class AgentChatComposerHost: NSScrollView, NSTextViewDelegate {
    let editor = AgentChatComposerTextView(frame: .zero)
    weak var completion: AgentChatComposerCompletion?
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
        editor.registerForDraggedTypes(Array(Set(editor.registeredDraggedTypes + AgentChatPasteboardSnapshot.materialTypes)))
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
        editor.onFocusChange = { [weak self] in self?.onFocus?($0) }
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
        editor.textContainer?.containerSize = NSSize(
            width: max(1, contentSize.width - 2 * editor.textContainerInset.width),
            height: CGFloat.greatestFiniteMagnitude)
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
        // SwiftUI sizing probes must not resize the live NSTextView or change
        // its accessibility frame, selection, wrapping or candidate anchor.
        let storage = NSTextStorage(attributedString: editor.attributedString())
        let manager = NSLayoutManager()
        manager.usesFontLeading = editor.layoutManager?.usesFontLeading ?? true
        let container = NSTextContainer(
            containerSize: NSSize(
                width: max(1, width - 2 * editor.textContainerInset.width), height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = editor.textContainer?.lineFragmentPadding ?? 5
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
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
        completion?.refresh(from: editor, in: conversationID)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }
    func textViewDidChangeSelection(_ notification: Notification) {
        completion?.refresh(from: editor, in: conversationID)
    }
    func textDidEndEditing(_ notification: Notification) {
        commitCurrentDraft()
    }
}

@MainActor final class AgentChatComposerTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChange?(false) }
        return accepted
    }
    var onSubmit: (() -> Void)?
    var completionConversationID: UUID?
    var onCompletionKey: ((NSEvent) -> Bool)?
    var onTransferMaterials: (([AgentChatTransferredMaterial], AgentChatLocalMaterial.CaptureOrigin) -> Void)?

    override func paste(_ sender: Any?) {
        if captureMaterials(from: .general, origin: .clipboard) { return }
        super.paste(sender)
    }

    @discardableResult
    func captureMaterials(from pasteboard: NSPasteboard, origin: AgentChatLocalMaterial.CaptureOrigin) -> Bool {
        guard isEditable, !hasMarkedText(), let onTransferMaterials else { return false }
        let materials = AgentChatPasteboardSnapshot.read(pasteboard)
        guard !materials.isEmpty else { return false }
        onTransferMaterials(materials, origin)
        return true
    }

    private func isMaterialDrag(_ sender: any NSDraggingInfo) -> Bool {
        onTransferMaterials != nil && sender.draggingPasteboard.availableType(from: AgentChatPasteboardSnapshot.materialTypes) != nil
    }

    private func materialDragOperation(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isEditable && !hasMarkedText() && sender.draggingSourceOperationMask.contains(.copy) ? .copy : []
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isMaterialDrag(sender) ? materialDragOperation(sender) : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isMaterialDrag(sender) ? materialDragOperation(sender) : super.draggingUpdated(sender)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isMaterialDrag(sender) ? materialDragOperation(sender) == .copy : super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard isMaterialDrag(sender) else { return super.performDragOperation(sender) }
        guard materialDragOperation(sender) == .copy else { return false }
        return captureMaterials(from: sender.draggingPasteboard, origin: .drop)
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        if let sender, isMaterialDrag(sender) { return }
        super.concludeDragOperation(sender)
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)), isEditable, onTransferMaterials != nil, !hasMarkedText(),
            NSPasteboard.general.availableType(from: AgentChatPasteboardSnapshot.materialTypes) != nil
        {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }

    override func keyDown(with event: NSEvent) {
        if !hasMarkedText(), onCompletionKey?(event) == true { return }
        if event.keyCode == 36 || event.keyCode == 76, !hasMarkedText() {
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
