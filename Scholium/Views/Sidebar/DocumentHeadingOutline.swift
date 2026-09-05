import AppKit
import ScholiumContracts
import SwiftUI

/// The native outline owns disclosure, selection, scrolling and keyboard input.
/// Its nodes project source headings; navigation never edits their source.
struct DocumentHeadingOutline: NSViewRepresentable {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var projection: DocumentInformationProjection
    let openHeading: (Int, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let outline = HeadingOutlineView()
        outline.headerView = nil
        outline.style = .sourceList
        outline.backgroundColor = .clear
        outline.focusRingType = .none
        outline.allowsMultipleSelection = false
        outline.allowsEmptySelection = true
        let column = NSTableColumn(identifier: .init("heading"))
        column.minWidth = 0
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outline.target = context.coordinator
        outline.action = #selector(Coordinator.pointerActivate(_:))
        outline.delegate = context.coordinator
        outline.dataSource = context.coordinator
        outline.setAccessibilityLabel(ScholiumL10n.string("Outline"))
        outline.setAccessibilityIdentifier("scholium.documentOutline")
        outline.accept = { [weak coordinator = context.coordinator] in coordinator?.accept() }
        scroll.documentView = outline
        context.coordinator.outline = outline
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        if let outline = view.documentView as? NSOutlineView {
            outline.rowSizeStyle = dynamicTypeSize.isAccessibilitySize ? .large : .default
        }
        context.coordinator.update(projection, openHeading: openHeading)
    }

    @MainActor
    final class Node: NSObject {
        let key: String
        var heading: HeadingNode
        var children: [Node] = []
        init(key: String, heading: HeadingNode) { self.key = key; self.heading = heading }
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        weak var outline: HeadingOutlineView?
        private var documentID: DocumentInformationDocumentID?
        private var headings: [HeadingNode] = []
        private var roots: [Node] = []
        private var nodes: [String: Node] = [:]
        private var synchronizing = false
        private var currentLine: Int?
        private var openHeading: ((Int, Bool) -> Void)?

        func update(_ projection: DocumentInformationProjection, openHeading: @escaping (Int, Bool) -> Void) {
            self.openHeading = openHeading
            guard let outline else { return }
            synchronizing = true
            defer { synchronizing = false }
            let changedDocument = documentID != projection.documentID
            let changedHeadings = headings != projection.headings
            if changedDocument || changedHeadings {
                if changedDocument { nodes = [:] }
                documentID = projection.documentID
                headings = projection.headings
                var next: [String: Node] = [:]
                var occurrences: [String: Int] = [:]
                var parents: [Node] = []
                roots = []
                for heading in headings {
                    let stem = "\(heading.level):\(heading.text)"
                    let occurrence = occurrences[stem, default: 0]
                    occurrences[stem] = occurrence + 1
                    let key = "\(stem):\(occurrence)"
                    let node = nodes[key] ?? Node(key: key, heading: heading)
                    node.heading = heading
                    node.children = []
                    next[key] = node
                    while let parent = parents.last, parent.heading.level >= heading.level { parents.removeLast() }
                    if let parent = parents.last { parent.children.append(node) } else { roots.append(node) }
                    parents.append(node)
                }
                nodes = next
                outline.reloadData()
                if changedDocument { outline.expandItem(nil, expandChildren: true) }
            }
            if changedDocument || changedHeadings || currentLine != projection.currentHeadingLine {
                currentLine = projection.currentHeadingLine
                if let node = nodes.values.first(where: { $0.heading.span.start.line == currentLine }) {
                    let row = outline.row(forItem: node)
                    if row >= 0 {
                        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                        outline.scrollRowToVisible(row)
                    } else { outline.deselectAll(nil) }
                } else { outline.deselectAll(nil) }
            }
        }
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            (item as? Node)?.children.count ?? roots.count
        }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            ((item as? Node)?.children ?? roots)[index]
        }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            !(item as! Node).children.isEmpty
        }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? Node else { return nil }
            let id = NSUserInterfaceItemIdentifier("headingCell")
            let cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
            if cell.textField == nil {
                cell.identifier = id
                let label = NSTextField(labelWithString: "")
                label.font = .systemFont(ofSize: NSFont.systemFontSize)
                label.lineBreakMode = .byTruncatingTail
                label.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(label)
                cell.textField = label
                NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            }
            cell.textField?.stringValue = node.heading.text
            cell.toolTip = node.heading.text
            cell.setAccessibilityLabel(node.heading.text)
            cell.setAccessibilityValue(String(localized: "Heading level \(node.heading.level)"))
            return cell
        }
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !synchronizing, let outline,
                  let node = outline.item(atRow: outline.selectedRow) as? Node else { return }
            currentLine = node.heading.span.start.line
            if outline.navigatingWithKeyboard { openHeading?(node.heading.span.start.line, false) }
        }
        @objc func pointerActivate(_ sender: Any?) { accept() }
        func accept() {
            guard let outline, let node = outline.item(atRow: outline.selectedRow) as? Node else { return }
            openHeading?(node.heading.span.start.line, true)
        }
    }
}

final class HeadingOutlineView: NSOutlineView {
    var navigatingWithKeyboard = false
    var accept: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { accept?(); return }
        navigatingWithKeyboard = true
        defer { navigatingWithKeyboard = false }
        super.keyDown(with: event)
    }
}
