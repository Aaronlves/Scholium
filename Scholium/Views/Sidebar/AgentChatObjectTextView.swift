import AppKit

final class AgentChatObjectTextView: NSTextView {
    private var retainedStorage: NSTextStorage?

    convenience init() { self.init(frame: .zero, textContainer: nil) }
    override init(frame: NSRect, textContainer: NSTextContainer?) {
        let container =
            textContainer
            ?? NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        if textContainer == nil {
            let storage = NSTextStorage()
            let layout = NSLayoutManager()
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            retainedStorage = storage
        }
        super.init(frame: frame, textContainer: container)
        isEditable = false
        isSelectable = true
        isRichText = true
        drawsBackground = false
        textContainerInset = .zero
        self.textContainer?.lineFragmentPadding = 0
        isHorizontallyResizable = false
        isVerticallyResizable = true
        self.textContainer?.widthTracksTextView = true
        setAccessibilityIdentifier("scholium.chat.objectText")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func measuredHeight(width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: attributedString())
        let layout = NSLayoutManager()
        let container = NSTextContainer(
            containerSize: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        return ceil(layout.usedRect(for: container).height)
    }

}
