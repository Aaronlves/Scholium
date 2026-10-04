import AppKit
import ScholiumContracts
import SwiftUI

/// One native multiline editor owns the entire message input region, including
/// whitespace, selection, Undo, marked text and Return commands.
struct AgentChatComposerInput: NSViewRepresentable {
    @Environment(\.isEnabled) private var environmentIsEnabled
    @Binding var text: String
    @Binding var isFocused: Bool
    let nativeSession: AgentChatComposerSession
    let readCurrentDraft: () -> String
    private var conversationID: UUID? { nativeSession.conversationID }
    let isEnabled: Bool
    let submit: () -> Void
    var completion: AgentChatComposerCompletion? = nil
    var candidates: [AgentChatComposerCandidate] = []
    var candidateQuery: AgentChatComposerQuery? = nil
    var canChooseCompletion: ((AgentChatComposerCandidate) -> Bool)? = nil
    var chooseCompletion: ((AgentChatComposerCandidate, @escaping (Bool) -> Void) -> Void)? = nil
    var transferMaterials: (([AgentChatTransferredMaterial], AgentChatLocalMaterial.CaptureOrigin) -> Void)? = nil
    var maximumHeight: CGFloat? = nil

    func makeNSView(context: Context) -> AgentChatComposerMountView {
        AgentChatComposerMountView(session: nativeSession)
    }

    func updateNSView(_ mount: AgentChatComposerMountView, context: Context) {
        guard !mount.isRetired else { return }
        mount.install(nativeSession)
        let host = nativeSession.host
        // An outgoing representable can still carry a Binding render snapshot.
        // Only the captured conversation's live owner may replace native input.
        let modelText = readCurrentDraft()
        var replacedDraft = false
        if host.completion !== completion { host.completion?.detach(from: host.editor) }
        host.completion = completion
        completion?.candidates = candidates
        completion?.candidateQuery = candidateQuery
        completion?.canAccept = canChooseCompletion
        completion?.choose = chooseCompletion
        host.editor.onCompletionKey = { [weak completion] event in completion?.keyDown(event) ?? false }
        if host.conversationID != conversationID {
            // Finish the previous native draft through its captured binding.
            host.commitCurrentDraft()
            host.editor.unmarkText()
            host.conversationID = conversationID
            host.editor.replaceDraft(modelText, selection: NSRange(location: (modelText as NSString).length, length: 0))
            host.lastPublishedText = modelText
            replacedDraft = true
        } else if host.editor.string != modelText, !host.editor.hasMarkedText() {
            if modelText != host.lastPublishedText, host.editor.string != host.lastPublishedText {
                nativeSession.retainInput(host.editor.string)
            }
            let selection = host.editor.selectedRange()
            host.editor.replaceDraft(modelText, selection: NSRange(location: min(selection.location, (modelText as NSString).length), length: 0))
            host.lastPublishedText = modelText
            replacedDraft = true
        }
        host.editor.completionConversationID = conversationID
        completion?.attach(to: host.editor, in: conversationID)
        // Replacement notifications occur before the new identity is attached;
        // publish the initialized draft's query only after that handoff finishes.
        completion?.refresh(from: host.editor, in: conversationID)
        host.onEdit = { text = $0 }
        host.readDraft = readCurrentDraft
        host.onRetainInput = { [weak nativeSession] in nativeSession?.retainInput($0) }
        host.onFocus = { if isFocused != $0 { isFocused = $0 } }
        host.editor.onSubmit = submit
        host.editor.onTransferMaterials = transferMaterials
        host.editor.isEditable = isEnabled && environmentIsEnabled
        host.editor.isSelectable = isEnabled && environmentIsEnabled
        let font = ScholiumChatAppearance.messageNSFont
        if host.editor.font != font {
            host.editor.font = font
            host.invalidateIntrinsicContentSize()
            host.needsLayout = true
        }
        if host.focusValue != isFocused {
            host.focusValue = isFocused
            host.requestedFocus = isFocused
            host.needsLayout = true
        }
        if replacedDraft {
            host.invalidateIntrinsicContentSize()
            host.needsLayout = true
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AgentChatComposerMountView, context: Context) -> CGSize? {
        // SwiftUI also probes an unbounded size. Do not pass that probe into
        // AppKit's text layout or its constraint system.
        let proposedWidth = proposal.width ?? nsView.bounds.width
        let width =
            proposedWidth.isFinite && proposedWidth < CGFloat.greatestFiniteMagnitude
            ? max(1, proposedWidth) : max(1, nsView.bounds.width)
        return CGSize(width: width, height: nativeSession.host.fittingHeight(width: width, maximumHeight: maximumHeight))
    }

    static func dismantleNSView(_ mount: AgentChatComposerMountView, coordinator: ()) {
        mount.detach()
    }
}

@MainActor final class AgentChatComposerHost: NSScrollView, NSTextViewDelegate {
    let editor = AgentChatComposerTextView(frame: .zero)
    weak var completion: AgentChatComposerCompletion?
    var conversationID: UUID?
    var onEdit: ((String) -> Void)?
    var readDraft: (() -> String)?
    var onRetainInput: ((String) -> Void)?
    var onFocus: ((Bool) -> Void)?
    var focusValue = false
    var requestedFocus: Bool?
    var lastPublishedText = ""
    private let measurementStorage = NSTextStorage()
    private let measurementLayout = NSLayoutManager()
    private let measurementContainer = NSTextContainer(containerSize: .zero)

    init() {
        super.init(frame: .zero)
        measurementStorage.addLayoutManager(measurementLayout)
        measurementLayout.addTextContainer(measurementContainer)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        autohidesScrollers = true
        editor.isRichText = false
        editor.importsGraphics = false
        editor.registerForDraggedTypes(Array(Set(editor.registeredDraggedTypes + AgentChatPasteboardSnapshot.materialTypes)))
        editor.drawsBackground = false
        editor.allowsUndo = true
        editor.font = ScholiumChatAppearance.messageNSFont
        editor.textColor = .textColor
        editor.textContainerInset = NSSize(width: 4, height: 6)
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.onFocusChange = { [weak self] in self?.onFocus?($0) }
        editor.onCompositionChange = { [weak self] in
            guard let self else { return }
            self.completion?.refresh(from: self.editor, in: self.conversationID)
        }
        editor.delegate = self
        editor.setAccessibilityLabel(String(localized: "Message", bundle: .module))
        editor.setAccessibilityHelp(AgentChatComposerTextView.placeholder)
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

    func fittingHeight(width: CGFloat, maximumHeight: CGFloat? = nil) -> CGFloat {
        let lineHeight = editor.layoutManager?.defaultLineHeight(for: editor.font ?? .systemFont(ofSize: NSFont.systemFontSize)) ?? 17
        let natural = min(max(40, measuredTextHeight(width: width)), lineHeight * 7 + 12)
        guard let maximumHeight, maximumHeight.isFinite else { return natural }
        return min(natural, max(lineHeight + 2 * editor.textContainerInset.height, maximumHeight))
    }

    private func measuredTextHeight(width: CGFloat) -> CGFloat {
        // SwiftUI sizing probes must not resize the live NSTextView or change
        // its accessibility frame, selection, wrapping or candidate anchor.
        // Keep TextKit's derived layout between identical SwiftUI probes. Reply
        // updates do not change the draft; rebuilding all its glyphs for every
        // proposal competes with both typing and streaming on the main actor.
        let content = editor.attributedString()
        if !measurementStorage.isEqual(to: content) {
            measurementStorage.setAttributedString(content)
        }
        let usesFontLeading = editor.layoutManager?.usesFontLeading ?? true
        if measurementLayout.usesFontLeading != usesFontLeading {
            measurementLayout.usesFontLeading = usesFontLeading
        }
        let size = NSSize(width: max(1, width - 2 * editor.textContainerInset.width), height: CGFloat.greatestFiniteMagnitude)
        if measurementContainer.containerSize != size { measurementContainer.containerSize = size }
        let padding = editor.textContainer?.lineFragmentPadding ?? 5
        if measurementContainer.lineFragmentPadding != padding { measurementContainer.lineFragmentPadding = padding }
        measurementLayout.ensureLayout(for: measurementContainer)
        return ceil(measurementLayout.usedRect(for: measurementContainer).height + 2 * editor.textContainerInset.height)
    }

    func commitCurrentDraft() {
        guard editor.string != lastPublishedText else { return }
        if let model = readDraft?(), model != lastPublishedText {
            onRetainInput?(editor.string)
            return
        }
        lastPublishedText = editor.string
        onEdit?(editor.string)
    }

    func suspend() {
        // Leaving the page finishes its native input session without replacing
        // the visible preedit text. Publish to the old conversation before its
        // binding detaches; no marked range can migrate into another draft.
        commitCurrentDraft()
        if editor.hasMarkedText() { editor.unmarkText() }
        if let window, window.firstResponder === editor { window.makeFirstResponder(nil) }
        commitCurrentDraft()
        if let model = readDraft?(), model != lastPublishedText {
            let selection = editor.selectedRange()
            editor.replaceDraft(model, selection: NSRange(location: min(selection.location, model.utf16.count), length: 0))
            lastPublishedText = model
        }
        onEdit = nil
        readDraft = nil
        onRetainInput = nil
        onFocus = nil
        editor.onSubmit = nil
        editor.onTransferMaterials = nil
        editor.onCompletionKey = nil
        completion?.detach(from: editor)
        completion = nil
        editor.isEditable = false
        editor.isSelectable = false
        focusValue = false
        requestedFocus = nil
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

    func undoManager(for view: NSTextView) -> UndoManager? {
        // Native text actions use the retained conversation's typing history.
        view === editor ? editor.undoManager : nil
    }
}

@MainActor final class AgentChatComposerTextView: NSTextView {
    // Native typing history belongs to this draft, never to another input or
    // a document that happens to share its window's responder chain.
    private let draftUndoManager = UndoManager()
    override var undoManager: UndoManager? { draftUndoManager }

    /// Application replacement (including Send clearing the draft) invalidates
    /// native typing ranges. Ordinary typing and completion keep their history.
    func replaceDraft(_ text: String, selection: NSRange) {
        breakUndoCoalescing()
        draftUndoManager.removeAllActions()
        draftUndoManager.disableUndoRegistration()
        defer { draftUndoManager.enableUndoRegistration() }
        string = text
        setSelectedRange(selection)
    }

    static var placeholder: String { String(localized: "/ commands · @ notes · $ skills", bundle: .module) }

    // Placeholder visibility follows the native buffer, including uncommitted
    // input-method text, rather than the asynchronously published SwiftUI draft.
    var showsPlaceholder: Bool { string.isEmpty && !hasMarkedText() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsPlaceholder else { return }
        let origin = textContainerOrigin
        let padding = textContainer?.lineFragmentPadding ?? 0
        (Self.placeholder as NSString).draw(
            in: NSRect(
                x: origin.x + padding, y: origin.y,
                width: max(0, bounds.width - 2 * (origin.x + padding)),
                height: max(0, bounds.height - origin.y)),
            withAttributes: [
                .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.placeholderTextColor,
            ])
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onCompositionChange?()
        needsDisplay = true
    }

    override func unmarkText() {
        super.unmarkText()
        onCompositionChange?()
        needsDisplay = true
    }

    override func didChangeText() {
        super.didChangeText()
        onCompositionChange?()
        needsDisplay = true
    }

    var onFocusChange: ((Bool) -> Void)?
    var onCompositionChange: (() -> Void)?
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
