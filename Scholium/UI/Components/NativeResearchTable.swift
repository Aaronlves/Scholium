import AppKit
import SwiftUI

/// A compact research-object table. SwiftUI owns rows and selected identity;
/// AppKit owns its column geometry, row reuse, and native interaction.
struct NativeResearchTable: NSViewRepresentable {
    struct Column: Equatable {
        let id: String
        let title: String
        var width: CGFloat? = nil
        var secondary = false
    }

    struct Row: Equatable {
        let id: String
        let cells: [String]
        var help = ""
    }

    let columns: [Column]
    let rows: [Row]
    @Binding var selection: String?
    let accessibilityLabel: String
    let identifier: String
    var primaryAction: ((String) -> Void)? = nil

    func makeNSView(context: Context) -> NativeResearchTableView {
        NativeResearchTableView()
    }

    func updateNSView(_ view: NativeResearchTableView, context: Context) {
        view.onSelection = { selection = $0 }
        view.onPrimaryAction = primaryAction
        view.table.isEnabled = context.environment.isEnabled
        view.table.allowsColumnResizing = false
        view.setAccessibilityLabel(accessibilityLabel)
        view.table.setAccessibilityLabel(accessibilityLabel)
        view.table.setAccessibilityIdentifier(identifier)
        view.update(columns: columns, rows: rows, selectedID: selection)
    }

    static func dismantleNSView(_ view: NativeResearchTableView, coordinator: Void) {
        view.onSelection = nil
        view.onPrimaryAction = nil
    }
}

@MainActor
final class NativeResearchTableView: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    typealias Column = NativeResearchTable.Column
    typealias Row = NativeResearchTable.Row

    let table = NSTableView()
    private(set) var columns: [Column] = []
    private(set) var rows: [Row] = []
    var onSelection: ((String?) -> Void)?
    var onPrimaryAction: ((String) -> Void)?
    private var updatingRows = false

    init() {
        super.init(frame: .zero)
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        drawsBackground = true
        backgroundColor = .controlBackgroundColor
        table.style = .inset
        table.backgroundColor = .controlBackgroundColor
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.allowsColumnSelection = false
        table.allowsColumnReordering = false
        table.allowsColumnResizing = false
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.intercellSpacing.width = 0
        table.rowSizeStyle = .default
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openSelectedRow(_:))
        documentView = table
    }

    required init?(coder: NSCoder) { nil }

    func update(columns: [Column], rows: [Row], selectedID: String?) {
        updatingRows = true
        defer { updatingRows = false }
        let structuralChange = self.columns.map(\.id) != columns.map(\.id)
        let changedRows = self.rows != rows
        self.columns = columns
        self.rows = rows
        table.usesAlternatingRowBackgroundColors = !rows.isEmpty
        if structuralChange {
            for column in table.tableColumns { table.removeTableColumn(column) }
            for definition in columns {
                let column = NSTableColumn(identifier: .init(definition.id))
                column.isEditable = false
                column.minWidth = 0
                column.resizingMask = definition.width == nil ? .autoresizingMask : []
                column.width = definition.width ?? 0
                table.addTableColumn(column)
            }
        }
        for (column, definition) in zip(table.tableColumns, columns) {
            column.title = definition.title
        }
        if changedRows || structuralChange { table.reloadData() }
        let selection = selectedID.flatMap { id in rows.firstIndex { $0.id == id } }
        let indexes = selection.map { IndexSet(integer: $0) } ?? []
        if table.selectedRowIndexes != indexes {
            table.selectRowIndexes(indexes, byExtendingSelection: false)
        }
        table.sizeToFit()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = max(0, contentSize.width)
        if abs(table.frame.width - width) > 0.01 {
            table.setFrameSize(NSSize(width: width, height: table.frame.height))
        }
        table.sizeToFit()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row), let tableColumn,
            let index = columns.firstIndex(where: { $0.id == tableColumn.identifier.rawValue })
        else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("researchCell.\(columns[index].id)")
        let cell =
            tableView.makeView(withIdentifier: identifier, owner: self) as? ResearchTableCell
            ?? ResearchTableCell(identifier: identifier, showsDocument: index == 0)
        let text = rows[row].cells.indices.contains(index) ? rows[row].cells[index] : ""
        cell.configure(text: text, secondary: columns[index].secondary, help: index == 0 && !rows[row].help.isEmpty ? rows[row].help : text)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = NSTableRowView()
        view.setAccessibilityLabel(rows[row].cells.joined(separator: ", "))
        return view
    }

    func selectionShouldChange(in tableView: NSTableView) -> Bool { tableView.isEnabled }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.isEnabled, !updatingRows else { return }
        onSelection?(rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id : nil)
    }

    @objc private func openSelectedRow(_ sender: Any?) {
        guard table.isEnabled, rows.indices.contains(table.clickedRow) else { return }
        onPrimaryAction?(rows[table.clickedRow].id)
    }

}

private final class ResearchTableCell: NSTableCellView {
    private var secondary = false

    init(identifier: NSUserInterfaceItemIdentifier, showsDocument: Bool) {
        super.init(frame: .zero)
        self.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField = label
        var contents: [NSView] = []
        if showsDocument {
            let image = NSImageView()
            image.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
            image.setAccessibilityElement(false)
            imageView = image
            contents.append(image)
        }
        contents.append(label)
        let stack = NSStackView(views: contents)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = NSFont.systemFontSize / 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyTextStyle() }
    }

    func configure(text: String, secondary: Bool, help: String) {
        self.secondary = secondary
        textField?.stringValue = text
        textField?.setAccessibilityLabel(text)
        toolTip = help
        applyTextStyle()
    }

    private func applyTextStyle() {
        textField?.cell?.backgroundStyle = backgroundStyle
        let color: NSColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : secondary ? .secondaryLabelColor : .labelColor
        textField?.textColor = color
        imageView?.contentTintColor = color
    }
}
