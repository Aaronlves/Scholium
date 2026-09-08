import AppKit
import SwiftUI

/// Native read-only selection. AppKit owns selection/menu/layout; Chat owns the reply and draft.
struct AgentChatSelectableText: NSViewRepresentable {
  let source: String
  let quote: (NSRange, String) -> Void
  let openLink: (URL) -> Void

  func makeNSView(context: Context) -> AgentChatReplyTextView { AgentChatReplyTextView() }
  func updateNSView(_ view: AgentChatReplyTextView, context: Context) {
    view.quote = quote
    view.openLink = openLink
    view.displayReply(source)
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: AgentChatReplyTextView, context: Context)
    -> CGSize?
  {
    guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
    return CGSize(width: width, height: nsView.measuredHeight(width: width))
  }
  static func dismantleNSView(_ view: AgentChatReplyTextView, coordinator: ()) {
    view.quote = nil
    view.openLink = nil
  }
  /// One text storage preserves native selection and Copy across every displayed block.
  static func renderReply(_ source: String) -> NSAttributedString {
    let blocks = AgentChatMarkdownBlock.parse(source)
    let result = NSMutableAttributedString(string: "")
    var table: NSTextTable?
    var row = 0
    for (index, block) in blocks.enumerated() {
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
            cell, font: .preferredFont(forTextStyle: header ? .headline : .body),
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
      var font = NSFont.preferredFont(forTextStyle: .body)
      var text = block.text
      if block.isQuoted {
        paragraph.headIndent = 16
        paragraph.firstLineHeadIndent = 16
      }
      switch block.kind {
      case .heading:
        font = .preferredFont(forTextStyle: .headline)
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
    return result
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
        .font: font, .foregroundColor: NSColor.labelColor,
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

final class AgentChatReplyTextView: NSTextView, NSTextViewDelegate {
  private var retainedStorage: NSTextStorage?
  private var displayedSource: String?
  private var displayedBodyFont: NSFont?
  private var displayedHeadingFont: NSFont?

  func displayReply(_ source: String) {
    let body = NSFont.preferredFont(forTextStyle: .body)
    let heading = NSFont.preferredFont(forTextStyle: .headline)
    guard source != displayedSource || body != displayedBodyFont || heading != displayedHeadingFont
    else { return }
    let selection = selectedRange()
    let sourceChanged = displayedSource != source
    textStorage?.setAttributedString(AgentChatSelectableText.renderReply(source))
    displayedSource = source
    displayedBodyFont = body
    displayedHeadingFont = heading
    setSelectedRange(sourceChanged ? NSRange(location: 0, length: 0) : selection)
  }

  var quote: ((NSRange, String) -> Void)?
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
    delegate = self
    setAccessibilityIdentifier("scholium.chat.replyText")
    setAccessibilityLabel(ScholiumL10n.string("Agent Reply"))
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

  override func menu(for event: NSEvent) -> NSMenu? {
    let menu = super.menu(for: event) ?? NSMenu()
    let item = NSMenuItem(
      title: ScholiumL10n.string("Ask About Selection"), action: #selector(quoteSelection(_:)),
      keyEquivalent: "r")
    item.keyEquivalentModifierMask = [.command, .shift]
    item.target = self
    item.isEnabled = selectedRange().length > 0
    menu.insertItem(item, at: 0)
    menu.insertItem(.separator(), at: 1)
    return menu
  }
  override func keyDown(with event: NSEvent) {
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
      event.charactersIgnoringModifiers?.lowercased() == "r", selectedRange().length > 0
    {
      quoteSelection(nil)
      return
    }
    super.keyDown(with: event)
  }
  override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    if item.action == #selector(quoteSelection(_:)) {
      return quote != nil && selectedRange().length > 0
    }
    return super.validateUserInterfaceItem(item)
  }
  @objc func quoteSelection(_ sender: Any?) {
    let range = selectedRange()
    guard range.length > 0, Range(range, in: string) != nil else { return }
    quote?(range, string)
  }
  func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
    if let url = link as? URL { openLink?(url) }
    return true
  }
}
