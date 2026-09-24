// Modified by Scholium; upstream attribution: ThirdParty/Edmund/NOTICE.md.
import AppKit

extension EditorTextView {
    /// Composition in either native input surface belongs to the same source session.
    public var isComposingSource: Bool {
        hasMarkedText() || (cellEditorController?.isComposing ?? false)
    }

    // Input methods can call this directly, independently of key events and
    // menu validation. A read-only surface must not acquire provisional text.
    public override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard isEditable, viewMode != .reading else { return }
        clearInlineGhost()
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        scheduleSourceStateNotification()
    }
    public override func unmarkText() {
        super.unmarkText()
        scheduleSourceStateNotification()
    }
}
