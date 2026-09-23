// Modified by Scholium; upstream attribution: ThirdParty/Edmund/NOTICE.md.
import AppKit

extension EditorTextView {
    public override func keyDown(with event: NSEvent) {
        if onNativeKeyDown?(event) == true { return }
        if viewMode == .reading, [36, 76].contains(event.keyCode),
            event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
            selectedRange().length == 0, nativeLinkTarget(at: selectedRange().location) != nil
        {
            openNativeLink(nil)
            return
        }
        super.keyDown(with: event)
    }
}
