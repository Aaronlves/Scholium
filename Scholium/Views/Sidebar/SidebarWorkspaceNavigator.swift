import AppKit
import ScholiumContracts
import SwiftUI

/// The native single-choice Analyses / Topics / Works navigator. AppKit owns
/// selection, focus, inactive-window presentation, pointer behavior, and
/// Up/Down traversal. Scholium supplies only the research destinations and
/// their exact Note totals.
struct ScholiumTriptychWorkspaceNavigator: NSViewRepresentable {
    @Environment(\.locale) private var locale

    let selectedSlot: WorkspaceVaultSlot?
    let noteCounts: SidebarWorkspaceNoteCounts
    let select: (WorkspaceVaultSlot) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedSlot: selectedSlot,
            noteCounts: noteCounts,
            locale: locale,
            select: select
        )
    }

    func makeNSView(context: Context) -> SidebarWorkspaceTableView {
        let tableView = SidebarWorkspaceTableView()
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowSizeStyle = .default
        tableView.intercellSpacing = .zero
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnSelection = false
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.setAccessibilityLabel(
            ScholiumL10n.string("Triptych Workspaces", locale: locale)
        )
        tableView.setAccessibilityIdentifier("scholium.workspaceNavigator")

        let column = NSTableColumn(identifier: Coordinator.columnIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        context.coordinator.attach(tableView)
        return tableView
    }

    func updateNSView(
        _ tableView: SidebarWorkspaceTableView,
        context: Context
    ) {
        context.coordinator.apply(
            selectedSlot: selectedSlot,
            noteCounts: noteCounts,
            locale: locale,
            select: select
        )
        tableView.setAccessibilityLabel(
            ScholiumL10n.string("Triptych Workspaces", locale: locale)
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let columnIdentifier = NSUserInterfaceItemIdentifier(
            "ScholiumWorkspaceColumn"
        )
        private static let cellIdentifier = NSUserInterfaceItemIdentifier(
            "ScholiumWorkspaceCell"
        )

        private weak var tableView: SidebarWorkspaceTableView?
        private var selectedSlot: WorkspaceVaultSlot?
        private var noteCounts: SidebarWorkspaceNoteCounts
        private var locale: Locale
        private var select: (WorkspaceVaultSlot) -> Void
        private var isSynchronizingSelection = false

        init(
            selectedSlot: WorkspaceVaultSlot?,
            noteCounts: SidebarWorkspaceNoteCounts,
            locale: Locale,
            select: @escaping (WorkspaceVaultSlot) -> Void
        ) {
            self.selectedSlot = selectedSlot
            self.noteCounts = noteCounts
            self.locale = locale
            self.select = select
        }

        func attach(_ tableView: SidebarWorkspaceTableView) {
            self.tableView = tableView
            tableView.reloadData()
            synchronizeSelection(in: tableView)
        }

        func apply(
            selectedSlot: WorkspaceVaultSlot?,
            noteCounts: SidebarWorkspaceNoteCounts,
            locale: Locale,
            select: @escaping (WorkspaceVaultSlot) -> Void
        ) {
            let contentChanged = self.noteCounts != noteCounts || self.locale != locale
            self.selectedSlot = selectedSlot
            self.noteCounts = noteCounts
            self.locale = locale
            self.select = select
            guard let tableView else { return }
            if contentChanged { tableView.reloadData() }
            synchronizeSelection(in: tableView)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            WorkspaceVaultSlot.allCases.count
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard WorkspaceVaultSlot.allCases.indices.contains(row) else {
                return nil
            }
            let slot = WorkspaceVaultSlot.allCases[row]
            let cell = tableView.makeView(
                withIdentifier: Self.cellIdentifier,
                owner: self
            ) as? SidebarWorkspaceCell ?? SidebarWorkspaceCell()
            cell.identifier = Self.cellIdentifier
            cell.configure(
                title: ScholiumL10n.dynamicString(slot.displayName),
                noteCount: noteCounts.count(for: slot),
                noteCountDescription: noteCountDescription(for: slot),
                accessibilityIdentifier: "scholium.vault.\(slot.rawValue)",
                effectiveRowSizeStyle: tableView.effectiveRowSizeStyle
            )
            return cell
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            guard WorkspaceVaultSlot.allCases.indices.contains(row) else {
                return false
            }
            return noteCounts.count(for: WorkspaceVaultSlot.allCases[row]) != nil
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSynchronizingSelection,
                  let tableView = notification.object as? NSTableView,
                  WorkspaceVaultSlot.allCases.indices.contains(tableView.selectedRow)
            else { return }
            let slot = WorkspaceVaultSlot.allCases[tableView.selectedRow]
            guard noteCounts.count(for: slot) != nil, slot != selectedSlot else {
                return
            }
            select(slot)
        }

        private func synchronizeSelection(in tableView: NSTableView) {
            isSynchronizingSelection = true
            defer { isSynchronizingSelection = false }
            guard let selectedSlot,
                  let row = WorkspaceVaultSlot.allCases.firstIndex(of: selectedSlot),
                  noteCounts.count(for: selectedSlot) != nil
            else {
                tableView.deselectAll(nil)
                return
            }
            guard tableView.selectedRow != row else { return }
            tableView.selectRowIndexes(
                IndexSet(integer: row),
                byExtendingSelection: false
            )
        }

        private func noteCountDescription(for slot: WorkspaceVaultSlot) -> String {
            guard let noteCount = noteCounts.count(for: slot) else {
                return ScholiumL10n.string("Note count unavailable", locale: locale)
            }
            return String.localizedStringWithFormat(
                ScholiumL10n.string("%lld notes", locale: locale),
                Int64(noteCount)
            )
        }
    }
}

@MainActor
final class SidebarWorkspaceTableView: NSTableView {
    private let selectionPresentation = SidebarSourceListSelectionPresentation()

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: CGFloat(numberOfRows) * rowHeight
        )
    }

    override func reloadData() {
        super.reloadData()
        invalidateIntrinsicContentSize()
    }

    override func mouseDown(with event: NSEvent) {
        selectionPresentation.recordPointerInteraction()
        super.mouseDown(with: event)
        selectionPresentation.synchronize(in: self)
    }

    override func keyDown(with event: NSEvent) {
        selectionPresentation.recordKeyboardInteraction()
        super.keyDown(with: event)
        selectionPresentation.synchronize(in: self)
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        guard becameFirstResponder else { return false }
        selectionPresentation.recordResponderEvent(NSApp.currentEvent?.type)
        selectionPresentation.synchronize(in: self)
        return true
    }

    override func resignFirstResponder() -> Bool {
        let resignedFirstResponder = super.resignFirstResponder()
        if resignedFirstResponder {
            selectionPresentation.synchronize(in: self)
        }
        return resignedFirstResponder
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        selectionPresentation.synchronize(in: self)
    }
}

@MainActor
private final class SidebarWorkspaceCell: NSTableCellView {
    private let titleField = NSTextField(labelWithString: "")
    private let countField = NSTextField(labelWithString: "")
    private var isAvailable = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        countField.alignment = .right
        countField.setContentHuggingPriority(.required, for: .horizontal)

        for field in [titleField, countField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            addSubview(field)
        }
        textField = titleField
        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: ScholiumGrid.Spacing.inlineControlGap
            ),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            countField.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleField.trailingAnchor,
                constant: ScholiumGrid.Spacing.inlineControlGap
            ),
            countField.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -ScholiumGrid.Spacing.inlineControlGap
            ),
            countField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SidebarWorkspaceCell is code-only")
    }

    func configure(
        title: String,
        noteCount: Int?,
        noteCountDescription: String,
        accessibilityIdentifier: String,
        effectiveRowSizeStyle: NSTableView.RowSizeStyle
    ) {
        let pointSize = NSFont.systemFontSize(
            for: sidebarControlSize(for: effectiveRowSizeStyle)
        )
        titleField.font = .systemFont(ofSize: pointSize)
        countField.font = .monospacedDigitSystemFont(
            ofSize: pointSize,
            weight: .regular
        )
        isAvailable = noteCount != nil
        titleField.stringValue = title
        countField.stringValue = noteCount?.formatted() ?? "—"
        titleField.setAccessibilityIdentifier(accessibilityIdentifier)
        titleField.setAccessibilityLabel(title)
        setAccessibilityLabel(title)
        setAccessibilityValue(noteCountDescription)
        setAccessibilityEnabled(isAvailable)
        setAccessibilityIdentifier(accessibilityIdentifier)
        updateColors()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateColors() }
    }

    private func updateColors() {
        if backgroundStyle == .emphasized {
            titleField.textColor = .alternateSelectedControlTextColor
            countField.textColor = .alternateSelectedControlTextColor
        } else if isAvailable {
            titleField.textColor = ScholiumColorRole.primaryText.nsColor
            countField.textColor = ScholiumColorRole.mutedText.nsColor
        } else {
            titleField.textColor = .disabledControlTextColor
            countField.textColor = .disabledControlTextColor
        }
    }
}
