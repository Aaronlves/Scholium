import AppKit
import SwiftUI

/// The Settings view owns the query and destination. AppKit owns text input,
/// temporary result presentation and its single keyboard selection.
struct ScholiumSettingsSearchField: NSViewRepresentable {
    @Binding var text: String
    let reveal: (SettingsSearchTarget) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSSearchField {
        Self.makeSearchField(coordinator: context.coordinator)
    }

    static func makeSearchField(coordinator: Coordinator) -> NSSearchField {
        let field = NSSearchField()
        let cell = SettingsSearchFieldCell(textCell: "")
        field.cell = cell
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        cell.isScrollable = true
        field.placeholderString = ScholiumL10n.string("Search Settings")
        field.sendsSearchStringImmediately = true
        field.delegate = coordinator
        field.target = coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        cell.editor.revealResults = { [weak coordinator] in coordinator?.showResults() }
        field.setAccessibilityLabel(ScholiumL10n.string("Search Settings"))
        field.setAccessibilityIdentifier("scholium.settings.search")
        coordinator.field = field
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
            context.coordinator.closeResults()
        }
    }

    static func dismantleNSView(_ field: NSSearchField, coordinator: Coordinator) {
        coordinator.closeResults()
        field.delegate = nil
        field.target = nil
        (field.cell as? SettingsSearchFieldCell)?.editor.revealResults = nil
        coordinator.field = nil
    }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ScholiumSettingsSearchField
        weak var field: NSSearchField?
        private let popover = NSPopover()
        private let results = SettingsSearchResultsController()

        init(parent: ScholiumSettingsSearchField) {
            self.parent = parent
            super.init()
            popover.behavior = .semitransient
            popover.animates = false
            popover.contentViewController = results
            results.choose = { [weak self] target in
                guard let self else { return }
                closeResults()
                parent.reveal(target)
            }
            results.cancel = { [weak self] in
                guard let self else { return }
                closeResults()
                if let field { field.window?.makeFirstResponder(field) }
            }
        }

        @objc func searchChanged(_ sender: NSSearchField) {
            parent.text = sender.stringValue
            showResults()
        }

        func controlTextDidBeginEditing(_ notification: Notification) { showResults() }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch NSStringFromSelector(command) {
            case "moveDown:", "moveUp:":
                guard !parent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                if !popover.isShown { showResults() }
                results.moveSelection(by: NSStringFromSelector(command) == "moveDown:" ? 1 : -1)
                return true
            case "insertNewline:":
                guard popover.isShown, results.selectedTarget != nil else { return false }
                results.activateSelection()
                return true
            case "cancelOperation:":
                guard popover.isShown else { return false }
                closeResults()
                return true
            default: return false
            }
        }

        func closeResults() { popover.close() }

        fileprivate func showResults() {
            guard let field, let window = field.window,
                !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { closeResults(); return }
            let editor = field.currentEditor() as? NSTextView
            guard editor?.hasMarkedText() != true else { return }
            results.update(SettingsSearchTarget.matches(field.stringValue))
            popover.contentSize = results.preferredContentSize
            if !popover.isShown {
                let responder: NSResponder = editor ?? field
                let selection = editor?.selectedRange()
                popover.show(relativeTo: field.bounds, of: field,
                    preferredEdge: field.isFlipped ? .maxY : .minY)
                // Preserve the actual field editor, including its insertion point.
                window.makeKey()
                if window.firstResponder !== responder {
                    // AppKit may detach the field editor while presenting.
                    // Re-enter only in that case, preserving the insertion range.
                    if editor?.window === window {
                        window.makeFirstResponder(responder)
                    } else {
                        window.makeFirstResponder(field)
                        if let selection, let current = field.currentEditor() as? NSTextView {
                            current.setSelectedRange(selection)
                        }
                    }
                }
            }
        }
    }
}

/// NSCell's public editor hook keeps repeat clicks local to this search field;
/// an already active field editor receives clicks instead of NSSearchField.
@MainActor private final class SettingsSearchFieldCell: NSSearchFieldCell {
    let editor: SettingsSearchFieldEditor = {
        let editor = SettingsSearchFieldEditor()
        editor.isFieldEditor = true
        editor.isRichText = false
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}

@MainActor private final class SettingsSearchFieldEditor: NSTextView {
    var revealResults: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        revealResults?()
    }
}

@MainActor final class SettingsSearchResultsController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    let table = SettingsSearchResultsTable()
    private(set) var targets: [SettingsSearchTarget] = []
    var choose: ((SettingsSearchTarget) -> Void)?
    var cancel: (() -> Void)?

    var selectedTarget: SettingsSearchTarget? {
        targets.indices.contains(table.selectedRow) ? targets[table.selectedRow] : nil
    }

    override func loadView() {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        table.headerView = nil
        table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: 0)
        let titleFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let detailFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        table.rowHeight = ceil(titleFont.ascender - titleFont.descender + titleFont.leading
            + detailFont.ascender - detailFont.descender + detailFont.leading
            + ScholiumMetrics.Settings.rowDetailSpacing + ScholiumGrid.Spacing.inlineControlGap * 2)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.addTableColumn(NSTableColumn(identifier: .init("setting")))
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(activateSelection)
        table.activate = { [weak self] in self?.activateSelection() }
        table.cancel = { [weak self] in self?.cancel?() }
        table.setAccessibilityLabel(ScholiumL10n.string("Search Results"))
        table.setAccessibilityIdentifier("scholium.settings.searchResults")
        scroll.documentView = table
        let container = NSView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scroll)
        let inset = ScholiumGrid.Spacing.inlineControlGap
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            scroll.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
        ])
        view = container
    }

    func update(_ targets: [SettingsSearchTarget]) {
        loadViewIfNeeded()
        self.targets = targets
        table.reloadData()
        table.deselectAll(nil)
        preferredContentSize = NSSize(
            width: ScholiumMetrics.Settings.searchResultsWidth,
            height: table.rowHeight * CGFloat(min(max(targets.count, 1), 8))
                + ScholiumGrid.Spacing.inlineControlGap * 2)
    }

    func moveSelection(by offset: Int) {
        guard !targets.isEmpty else { return }
        let current = table.selectedRow
        let row = current < 0 ? (offset > 0 ? 0 : targets.count - 1)
            : min(max(current + offset, 0), targets.count - 1)
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc func activateSelection() {
        if let selectedTarget { choose?(selectedTarget) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { max(targets.count, 1) }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { !targets.isEmpty }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = SettingsSearchResultCell()
        if targets.isEmpty {
            cell.setAccessibilityRole(.staticText)
            cell.title.stringValue = ScholiumL10n.string("No Search Results")
            cell.detail.isHidden = true
            cell.setAccessibilityIdentifier("scholium.settings.noResults")
        } else {
            let target = targets[row]
            cell.title.stringValue = String(localized: target.title)
            cell.detail.stringValue = String(localized: target.destination.title)
            cell.setAccessibilityIdentifier("scholium.settings.result.\(target.id)")
            cell.activate = { [weak self] in
                guard let self, let currentRow = targets.firstIndex(where: { $0.id == target.id }) else { return false }
                table.selectRowIndexes(IndexSet(integer: currentRow), byExtendingSelection: false)
                activateSelection()
                return true
            }
        }
        cell.setAccessibilityLabel([cell.title.stringValue, cell.detail.stringValue].filter { !$0.isEmpty }.joined(separator: ", "))
        return cell
    }
}

@MainActor final class SettingsSearchResultsTable: NSTableView {
    var activate: (() -> Void)?
    var cancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { activate?() }
        else if event.keyCode == 53 { cancel?() }
        else { super.keyDown(with: event) }
    }

    override func accessibilityPerformConfirm() -> Bool {
        guard selectedRow >= 0 else { return false }
        activate?()
        return true
    }
}

@MainActor private final class SettingsSearchResultCell: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")
    var activate: (() -> Bool)?

    override func accessibilityPerformPress() -> Bool { activate?() ?? false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        title.font = .systemFont(ofSize: NSFont.systemFontSize)
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        detail.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = ScholiumMetrics.Settings.rowDetailSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        textField = title
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ScholiumGrid.Spacing.inlineControlGap),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ScholiumGrid.Spacing.inlineControlGap),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Settings results are code-only") }
}
