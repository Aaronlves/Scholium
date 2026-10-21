import AppKit

/// A transient choice list. AppKit draws the sole selection; pointer movement
/// changes that same choice. The caller owns acceptance and any external state.
@MainActor
final class NativeFloatingChoiceList: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    struct Item: Equatable {
        let label: String
        var detail = ""
        var indentation: CGFloat = 0
        var accessibilityValue = ""
        var disabled = false
    }

    let table = FloatingChoiceTable()
    private(set) var items: [Item] = []
    var select: ((Int) -> Void)?
    var choose: ((Int) -> Void)?
    private var synchronizing = false
    private var measuredWidth: CGFloat?
    private var measuredFonts: (label: NSFont, detail: NSFont)?
    #if DEBUG
        private(set) var measuredWidthItemCount = 0
    #endif

    init(acceptsKeyboard: Bool) {
        super.init(frame: .zero)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        autohidesScrollers = true
        automaticallyAdjustsContentInsets = false
        table.ownsKeyboard = acceptsKeyboard
        table.focusRingType = .none
        table.headerView = nil
        table.style = .inset
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.selectionHighlightStyle = .regular
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let column = NSTableColumn(identifier: .init("choice"))
        column.minWidth = 0
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        table.pointToRow = { [weak self] row in self?.point(to: row) }
        table.acceptRow = { [weak self] row in self?.accept(row) }
        documentView = table
        if !acceptsKeyboard {
            // CodeMirror owns the only accessible listbox and active descendant.
            setAccessibilityElement(false)
            setAccessibilityChildren([])
            table.setAccessibilityElement(false)
            table.setAccessibilityChildren([])
        }
    }

    required init?(coder: NSCoder) { nil }

    func update(items: [Item], selected: Int? = nil) {
        synchronizing = true
        defer { synchronizing = false }
        if self.items != items {
            if !self.items.elementsEqual(
                items,
                by: {
                    $0.label == $1.label && $0.detail == $1.detail && $0.indentation == $1.indentation
                })
            {
                measuredWidth = nil
            }
            self.items = items
            table.reloadData()
            invalidateIntrinsicContentSize()
        }
        let selected = selected ?? (table.ownsKeyboard && table.selectedRow < 0 && !items.isEmpty ? 0 : nil)
        if let selected, table.selectedRow != selected {
            table.selectRowIndexes(
                items.indices.contains(selected) ? IndexSet(integer: selected) : [],
                byExtendingSelection: false)
        }
        if table.selectedRow >= 0 { table.scrollRowToVisible(table.selectedRow) }
    }

    override var intrinsicContentSize: NSSize { preferredSize }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        measuredWidth = nil
        invalidateIntrinsicContentSize()
    }

    override func layout() {
        super.layout()
        table.setFrameSize(NSSize(width: contentSize.width, height: table.frame.height))
        table.sizeLastColumnToFit()
    }

    var nativeVerticalPadding: CGFloat {
        guard !items.isEmpty else { return 0 }
        let firstRow = table.rect(ofRow: 0)
        let finalRow = table.rect(ofRow: items.count - 1)
        return firstRow.minY + max(0, table.fittingSize.height - finalRow.maxY)
    }

    var preferredSize: NSSize {
        let labelFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let detailFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        if measuredFonts?.label != labelFont || measuredFonts?.detail != detailFont {
            measuredFonts = (labelFont, detailFont)
            measuredWidth = nil
        }
        if measuredWidth == nil {
            measuredWidth = items.reduce(CGFloat.zero) { width, item in
                #if DEBUG
                    measuredWidthItemCount += 1
                #endif
                let label = (item.label as NSString).size(withAttributes: [.font: labelFont]).width
                let detail = (item.detail as NSString).size(withAttributes: [.font: detailFont]).width
                return max(width, max(label, detail) + item.indentation + 32)
            }
        }
        let visibleRows = min(items.count, ScholiumMetrics.Completion.maximumVisibleRows)
        let height: CGFloat
        if visibleRows > 0 {
            // Inset tables add native space before the first row and after the
            // last row. Use AppKit's laid-out row geometry so a short list does
            // not clip its bottom selection plate inside the scroll view.
            let bottomInset = nativeVerticalPadding - table.rect(ofRow: 0).minY
            height = ceil(table.rect(ofRow: visibleRows - 1).maxY + bottomInset)
        } else {
            height = 0
        }
        return NSSize(width: min(368, ceil(measuredWidth ?? 0)), height: height)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { rowHeight(items[row]) }

    private func rowHeight(_ item: Item) -> CGFloat {
        item.detail.isEmpty ? ScholiumMetrics.Completion.rowHeight : ScholiumMetrics.Completion.detailedRowHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell =
            tableView.makeView(withIdentifier: .init("choiceCell"), owner: self) as? FloatingChoiceCell
            ?? FloatingChoiceCell()
        cell.configure(items[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = FloatingChoiceRow()
        view.retainsEditorFocus = !table.ownsKeyboard
        view.accept = { [weak self] in self?.accept(row) }
        view.setAccessibilityLabel(items[row].label)
        view.setAccessibilityValue(items[row].accessibilityValue)
        view.setAccessibilityEnabled(!items[row].disabled)
        view.acceptsChoice = !items[row].disabled
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !synchronizing, items.indices.contains(table.selectedRow) else { return }
        select?(table.selectedRow)
    }

    private func point(to row: Int) {
        guard items.indices.contains(row), row != table.selectedRow else { return }
        if table.ownsKeyboard {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            // Selection returns through the editor projection; never keep a
            // second hover index that can disagree with keyboard navigation.
            select?(row)
        }
    }

    private func accept(_ row: Int) {
        guard items.indices.contains(row), !items[row].disabled else { return }
        choose?(row)
    }
}

@MainActor
final class FloatingChoiceTable: NSTableView {
    var ownsKeyboard = false
    var pointToRow: ((Int) -> Void)?
    var acceptRow: ((Int) -> Void)?
    private var pointerTracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { ownsKeyboard }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        pointerTracking = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseMoved(with event: NSEvent) {
        pointToRow?(row(at: convert(event.locationInWindow, from: nil)))
    }
    override func mouseDown(with event: NSEvent) {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard index >= 0 else { return }
        pointToRow?(index)
        acceptRow?(index)
    }
    override func keyDown(with event: NSEvent) {
        if ownsKeyboard, event.keyCode == 36 || event.keyCode == 76 {
            acceptRow?(selectedRow)
        } else {
            super.keyDown(with: event)
        }
    }
}

private final class FloatingChoiceRow: NSTableRowView {
    var retainsEditorFocus = false
    var accept: (() -> Void)?
    var acceptsChoice = true
    // The editor retains keyboard focus. Use AppKit's secondary selection
    // treatment for its auxiliary choice; AppKit owns colors and contrast.
    override var isEmphasized: Bool {
        get { retainsEditorFocus ? false : super.isEmphasized }
        set { super.isEmphasized = retainsEditorFocus ? false : newValue }
    }
    override func accessibilityPerformPress() -> Bool {
        guard acceptsChoice, let accept else { return false }
        accept()
        return true
    }
}

private final class FloatingChoiceCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private var leading: NSLayoutConstraint!
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = .init("choiceCell")
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [label, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        for field in [label, detail] {
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        addSubview(stack)
        textField = label
        leading = stack.leadingAnchor.constraint(equalTo: leadingAnchor)
        NSLayoutConstraint.activate([
            leading, stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { detail.cell?.backgroundStyle = backgroundStyle }
    }
    func configure(_ item: NativeFloatingChoiceList.Item) {
        label.stringValue = item.label
        label.textColor = item.disabled ? .disabledControlTextColor : .labelColor
        detail.stringValue = item.detail
        detail.isHidden = item.detail.isEmpty
        leading.constant = item.indentation
        toolTip = item.detail.isEmpty ? item.label : "\(item.label)\n\(item.detail)"
    }
}
