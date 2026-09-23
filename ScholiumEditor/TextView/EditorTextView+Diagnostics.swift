// Modified by Scholium; upstream attribution: ThirdParty/Edmund/NOTICE.md.
import AppKit

extension EditorTextView {
    func verifyEditorInvariants(_ context: String) {
        #if DEBUG
            guard let storage = textStorage else { return }
            assert(
                storage.length == (rawSource as NSString).length,
                "Editor storage length diverged from source")
        #endif
    }
}
