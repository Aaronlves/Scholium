import AppKit
import SwiftUI

/// Attributed projection used only to copy and expand rich reply objects.
enum AgentChatObjectProjection {
    struct Layout {
        let text: NSAttributedString
        let blocks: [(block: AgentChatMarkdownBlock, range: NSRange)]
    }

    static func layoutReply(_ source: String) -> Layout {
        let blocks = AgentChatMarkdownBlock.parse(source)
        var ranges: [(block: AgentChatMarkdownBlock, range: NSRange)] = []
        let result = NSMutableAttributedString(string: "")
        var table: NSTextTable?
        var row = 0
        for (index, block) in blocks.enumerated() {
            let start = result.length
            defer { ranges.append((block, NSRange(location: start, length: result.length - start))) }
            if case .tableRow(let header) = block.kind {
                if table == nil {
                    table = NSTextTable()
                    table?.numberOfColumns = block.cells.count
                    table?.layoutAlgorithm = .fixedLayoutAlgorithm
                    table?.setContentWidth(100, type: .percentageValueType)
                    row = 0
                }
                for (column, cell) in block.cells.enumerated() {
                    let paragraph = NSMutableParagraphStyle()
                    let cellBlock = NSTextTableBlock(
                        table: table!, startingRow: row, rowSpan: 1,
                        startingColumn: column, columnSpan: 1)
                    cellBlock.setContentWidth(
                        100 / CGFloat(max(1, block.cells.count)), type: .percentageValueType)
                    cellBlock.setWidth(4, type: .absoluteValueType, for: .padding)
                    paragraph.textBlocks = [cellBlock]
                    append(
                        cell,
                        font: header
                            ? ScholiumChatAppearance.messageHeadingNSFont
                            : ScholiumChatAppearance.messageNSFont,
                        paragraph: paragraph, suffix: "\n", to: result)
                }
                row += 1
                continue
            }
            let followsTable = table != nil
            table = nil
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacingBefore = followsTable ? 12 : 0
            paragraph.paragraphSpacing = 12
            var font = ScholiumChatAppearance.messageNSFont
            var text = block.text
            if block.isQuoted {
                paragraph.headIndent = 16
                paragraph.firstLineHeadIndent = 16
            }
            switch block.kind {
            case .heading:
                font = ScholiumChatAppearance.messageHeadingNSFont
                paragraph.headerLevel = 1
            case .code:
                font = .monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
            case .list(let marker):
                text = AttributedString(marker + " ") + text
                paragraph.headIndent += 20
                paragraph.paragraphSpacing = 4
            default: break
            }
            append(
                text, font: font, paragraph: paragraph,
                suffix: index + 1 < blocks.count ? "\n" : "", to: result)
        }
        return Layout(text: result, blocks: ranges)
    }

    private static func append(
        _ text: AttributedString, font: NSFont,
        paragraph: NSParagraphStyle, suffix: String, to result: NSMutableAttributedString
    ) {
        let attributed = NSMutableAttributedString(attributedString: render(text, font: font))
        attributed.append(NSAttributedString(string: suffix, attributes: [.font: font]))
        attributed.addAttribute(
            .paragraphStyle, value: paragraph,
            range: NSRange(location: 0, length: attributed.length))
        result.append(attributed)
    }

    static func render(_ text: AttributedString, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for run in text.runs {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: ScholiumChatAppearance.messageNSForeground,
            ]
            var traits: NSFontTraitMask = []
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                traits.insert(.boldFontMask)
            }
            if run.inlinePresentationIntent?.contains(.emphasized) == true {
                traits.insert(.italicFontMask)
            }
            if !traits.isEmpty {
                attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: traits)
            }
            if run.inlinePresentationIntent?.contains(.code) == true {
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
                attributes[.backgroundColor] = ScholiumChatAppearance.inlineCodeBackground
            }
            if run.inlinePresentationIntent?.contains(.strikethrough) == true {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link { attributes[.link] = link }
            result.append(
                NSAttributedString(string: String(text[run.range].characters), attributes: attributes))
        }
        return result
    }
}

final class AgentChatObjectTextView: NSTextView, NSTextViewDelegate {
    private var retainedStorage: NSTextStorage?
    var openLink: ((URL) -> Void)?

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
        linkTextAttributes = [
            .foregroundColor: ScholiumChatAppearance.messageLinkNSForeground,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        delegate = self
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

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL { openLink?(url) }
        return true
    }
}
