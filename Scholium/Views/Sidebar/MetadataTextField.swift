import AppKit

/// A continuously mounted native control, including its own native field editor.
/// Tab is never intercepted; AppKit transfers the responder synchronously.
@MainActor final class MetadataTextField: NSTextField, NSTextFieldDelegate {
    weak var host: MetadataFieldsHost?
    var key = ""
    var identity = ""
    /// Latest session projection, including a synchronous cancelled draft.
    var representedValue = ""
    var changed: ((String) -> Void)?
    var allowsLineBreaks = false
    var multiline = false {
        didSet {
            usesSingleLineMode = !multiline
            maximumNumberOfLines = multiline ? 0 : 1
            cell?.wraps = multiline
            cell?.isScrollable = !multiline
        }
    }
    private(set) var hasInputFocus = false
    private var measuredWidth: CGFloat = 0

    init() {
        super.init(frame: .zero)
        let cell = MetadataTextCell(textCell: "")
        cell.owner = self
        self.cell = cell
        delegate = self
        isEditable = true; isSelectable = true
        isBordered = false; isBezeled = true; drawsBackground = false
        bezelStyle = .roundedBezel
        font = .systemFont(ofSize: ScholiumTypography.controlPointSize)
        textColor = ScholiumNativeColorRole.label.nsColor
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let width = bounds.width > 0 ? bounds.width : 112
        let height = multiline ? cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10000)).height ?? 24 : super.intrinsicContentSize.height
        return NSSize(width: NSView.noIntrinsicMetric, height: max(24, height))
    }

    override func layout() {
        super.layout()
        if multiline && abs(measuredWidth - bounds.width) > 0.5 {
            measuredWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { hasInputFocus = true; updateSurface() }
        return accepted
    }
    private func updateSurface() {
        drawsBackground = hasInputFocus
        needsDisplay = true
        noteFocusRingMaskChanged()
        (superview as? MetadataFieldRow)?.refreshActions()
    }

    func controlTextDidChange(_ notification: Notification) {
        let composing = (currentEditor() as? NSTextView)?.hasMarkedText() ?? false
        if composing { host?.session.composing.insert(identity) }
        else { host?.session.composing.remove(identity); changed?(stringValue) }
        invalidateIntrinsicContentSize()
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard (currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        changed?(stringValue)
        host?.session.composing.remove(identity)
        hasInputFocus = false; updateSurface()
        host?.session.requestCommit()
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        if command == #selector(NSResponder.cancelOperation(_:)) {
            guard host?.session.isSaving != true else { return true }
            host?.session.cancelDraft(key)
            stringValue = representedValue
            textView.string = representedValue
            textView.setSelectedRange(NSRange(location: 0, length: (representedValue as NSString).length))
            clearDraftUndo()
            return true
        }
        if command == #selector(NSResponder.insertNewline(_:)) {
            if allowsLineBreaks && NSApp.currentEvent?.modifierFlags.contains(.command) != true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                changed?(textView.string)
                window?.makeFirstResponder(host)
                host?.session.requestCommit()
            }
            return true
        }
        return false
    }
    func clearDraftUndo() {
        (cell as? MetadataTextCell)?.editor?.typingUndo.removeAllActions()
    }
}

@MainActor private final class MetadataTextCell: NSTextFieldCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        if owner?.hasInputFocus == true { super.draw(withFrame: cellFrame, in: controlView) }
        else { drawInterior(withFrame: cellFrame, in: controlView) }
    }
    weak var owner: MetadataTextField?
    var editor: MetadataFieldEditor?
    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        if editor == nil {
            let editor = MetadataFieldEditor()
            editor.isFieldEditor = true
            editor.isRichText = false
            editor.allowsUndo = true
            self.editor = editor
        }
        editor?.owner = owner
        return editor
    }
}

/// Text editing keeps its native Undo grouping. Once a field is committed,
/// Undo/Redo route to the Note's revision-checked Metadata transaction history.
@MainActor private final class MetadataFieldEditor: NSTextView {
    weak var owner: MetadataTextField?
    let typingUndo = UndoManager()
    override var undoManager: UndoManager? { typingUndo }

    @objc func undo(_ sender: Any?) {
        if typingUndo.canUndo { typingUndo.undo() }
        else { owner?.host?.undo(sender) }
    }
    @objc func redo(_ sender: Any?) {
        if typingUndo.canRedo { typingUndo.redo() }
        else { owner?.host?.redo(sender) }
    }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return typingUndo.canUndo || owner?.host?.session.undoManager.canUndo == true }
        if item.action == #selector(redo(_:)) { return typingUndo.canRedo || owner?.host?.session.undoManager.canRedo == true }
        return super.validateUserInterfaceItem(item)
    }
}
