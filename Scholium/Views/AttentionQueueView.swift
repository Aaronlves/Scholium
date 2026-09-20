import AppKit
import Combine
import ScholiumContracts

/// Native Notifications content for the window-owned transient popover.
///
/// The session and presentation state remain the only domain/presentation
/// owners. AppKit owns the search field, table selection, keyboard traversal,
/// row reuse, and responder chain. This controller only projects those
/// immutable inputs and translates native intents back to the session.
@MainActor
final class AttentionQueueViewController: NSViewController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation {
    private enum FilterTag: Int {
        case all
        case agentChanges
        case settlements
    }

    private enum Row {
        case category(String)
        case agentChange(AgentChange)
        case settlement(WorkspaceSettlementRequirement)

        var id: String {
            switch self {
            case .category(let title): "category:\(title)"
            case .agentChange(let change): "agent-change:\(change.id.uuidString.lowercased())"
            case .settlement(let requirement): "settlement:\(requirement.noteID.uuidString.lowercased())"
            }
        }

        var isSelectable: Bool {
            switch self {
            case .category: false
            case .agentChange, .settlement: true
            }
        }
    }

    private let presentation: AttentionPresentationState
    private let session: AttentionPopoverSession
    private let rootStack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let scopeLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private let refreshStatusStack = NSStackView()
    private let refreshStatusImage = NSImageView()
    private let refreshStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let retryButton = NSButton(title: "", target: nil, action: nil)
    private let listScrollView = NSScrollView()
    private let tableView = AttentionQueueTableView()
    private let stateStack = NSStackView()
    private let stateImage = NSImageView()
    private let stateProgress = NSProgressIndicator()
    private let stateTitle = NSTextField(labelWithString: "")
    private let stateDetail = NSTextField(wrappingLabelWithString: "")
    private let stateAction = NSButton(title: "", target: nil, action: nil)

    private var rows: [Row] = []
    private var observations: Set<AnyCancellable> = []
    private var lastFilterFocusRequestGeneration: UInt64
    private var hasAppliedInitialFocus = false
    private var isUpdatingProjection = false

    init(
        presentation: AttentionPresentationState,
        session: AttentionPopoverSession
    ) {
        self.presentation = presentation
        self.session = session
        lastFilterFocusRequestGeneration = presentation.filterFocusRequestGeneration
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()
        root.setAccessibilityIdentifier("scholium.attentionQueue")
        view = root

        configureControls()
        configureTable()
        configureStates()
        installLayout(in: root)
        observePresentation()
        reloadFromModel()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if session.isLoadingInitialContent {
            Task { [weak self] in
                guard let self else { return }
                await self.session.refresh()
            }
        }
        focusInitialContentIfNeeded()
    }

    /// Called by the toolbar after the NSPopover has attached the controller's
    /// view to its window. AppKit must own this handoff; SwiftUI focus state is
    /// deliberately not involved.
    func focusInitialContentIfNeeded() {
        guard !hasAppliedInitialFocus else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.view.window else { return }
            self.hasAppliedInitialFocus = true
            window.makeFirstResponder(self.tableView)
        }
    }

    private func configureControls() {
        titleLabel.stringValue = ScholiumL10n.string("Notifications")
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize + 1, weight: .semibold)
        titleLabel.setAccessibilityLabel(titleLabel.stringValue)
        titleLabel.setAccessibilityRole(.staticText)

        scopeLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        scopeLabel.textColor = .secondaryLabelColor
        scopeLabel.setAccessibilityRole(.staticText)

        searchField.placeholderString = ScholiumL10n.string("Search")
        searchField.sendsSearchStringImmediately = true
        searchField.maximumRecents = 0
        searchField.delegate = self
        searchField.searchMenuTemplate = makeSearchMenu()
        searchField.setAccessibilityLabel(ScholiumL10n.string("Search Notifications"))
        searchField.setAccessibilityIdentifier("scholium.attentionSearch")
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        refreshStatusStack.orientation = .horizontal
        refreshStatusStack.alignment = .centerY
        refreshStatusStack.spacing = ScholiumGrid.Spacing.inlineControlGap
        refreshStatusStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        refreshStatusImage.imageScaling = .scaleProportionallyDown
        refreshStatusImage.setContentHuggingPriority(.required, for: .horizontal)
        refreshStatusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        refreshStatusLabel.textColor = .secondaryLabelColor
        refreshStatusLabel.maximumNumberOfLines = 0
        refreshStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        retryButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: ScholiumL10n.string("Retry")
        )
        retryButton.title = ""
        retryButton.bezelStyle = .texturedRounded
        retryButton.controlSize = .small
        retryButton.target = self
        retryButton.action = #selector(retryRefresh(_:))
        retryButton.toolTip = ScholiumL10n.string("Retry")
        retryButton.setAccessibilityLabel(ScholiumL10n.string("Retry"))
        retryButton.setAccessibilityIdentifier("scholium.attentionRetry")
        refreshStatusStack.addArrangedSubview(refreshStatusImage)
        refreshStatusStack.addArrangedSubview(refreshStatusLabel)
        refreshStatusStack.addArrangedSubview(NSView())
        refreshStatusStack.addArrangedSubview(retryButton)
    }

    private func configureTable() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.activate = { [weak self] in self?.activateSelectedRow(nil) }
        tableView.headerView = nil
        tableView.style = .inset
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnSelection = false
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = []
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.usesAutomaticRowHeights = true
        tableView.backgroundColor = .clear
        tableView.setAccessibilityLabel(ScholiumL10n.string("Notifications"))
        tableView.setAccessibilityIdentifier("scholium.attentionList")

        let column = NSTableColumn(identifier: .init("notification"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        listScrollView.borderType = .noBorder
        listScrollView.hasVerticalScroller = true
        listScrollView.hasHorizontalScroller = false
        listScrollView.autohidesScrollers = true
        listScrollView.drawsBackground = false
        listScrollView.documentView = tableView
    }

    private func configureStates() {
        stateStack.orientation = .vertical
        stateStack.alignment = .centerX
        stateStack.spacing = ScholiumGrid.Spacing.inlineControlGap
        stateStack.edgeInsets = NSEdgeInsets(
            top: ScholiumGrid.Spacing.regionContentInset,
            left: ScholiumGrid.Spacing.regionContentInset,
            bottom: ScholiumGrid.Spacing.regionContentInset,
            right: ScholiumGrid.Spacing.regionContentInset
        )

        stateImage.imageScaling = .scaleProportionallyDown
        stateImage.setAccessibilityElement(false)
        stateProgress.style = .spinning
        stateProgress.controlSize = .small
        stateProgress.setAccessibilityElement(false)
        stateTitle.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        stateTitle.alignment = .center
        stateDetail.alignment = .center
        stateDetail.textColor = .secondaryLabelColor
        stateDetail.maximumNumberOfLines = 0
        stateAction.bezelStyle = .rounded
        stateAction.controlSize = .small
        stateAction.target = self
        stateAction.action = #selector(retryRefresh(_:))
        stateAction.setAccessibilityIdentifier("scholium.attentionStateAction")

        stateStack.addArrangedSubview(stateImage)
        stateStack.addArrangedSubview(stateProgress)
        stateStack.addArrangedSubview(stateTitle)
        stateStack.addArrangedSubview(stateDetail)
        stateStack.addArrangedSubview(stateAction)
    }

    private func installLayout(in root: NSView) {
        rootStack.orientation = .vertical
        rootStack.alignment = .width
        rootStack.spacing = 0
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(headerView())

        let divider = NSBox()
        divider.boxType = .separator
        rootStack.addArrangedSubview(divider)
        rootStack.addArrangedSubview(listScrollView)
        rootStack.addArrangedSubview(stateStack)
        root.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: root.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            listScrollView.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            listScrollView.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            stateStack.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            stateStack.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
        ])
    }

    private func headerView() -> NSView {
        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .width
        header.spacing = ScholiumGrid.Spacing.inlineControlGap
        header.edgeInsets = NSEdgeInsets(
            top: ScholiumGrid.Spacing.nestedContentInset,
            left: ScholiumGrid.Spacing.sectionSeparation,
            bottom: ScholiumGrid.Spacing.nestedContentInset,
            right: ScholiumGrid.Spacing.sectionSeparation
        )
        header.translatesAutoresizingMaskIntoConstraints = false

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = ScholiumGrid.Spacing.labelAccessoryGap
        titleRow.addArrangedSubview(titleLabel)
        titleRow.addArrangedSubview(scopeLabel)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleRow.addArrangedSubview(spacer)

        header.addArrangedSubview(titleRow)
        header.addArrangedSubview(searchField)
        header.addArrangedSubview(refreshStatusStack)
        NSLayoutConstraint.activate([
            titleRow.widthAnchor.constraint(equalTo: header.widthAnchor),
            searchField.widthAnchor.constraint(equalTo: header.widthAnchor),
            refreshStatusStack.widthAnchor.constraint(equalTo: header.widthAnchor),
        ])
        return header
    }

    private func observePresentation() {
        presentation.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.reloadFromModel() }
            .store(in: &observations)
        session.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.reloadFromModel() }
            .store(in: &observations)
    }

    private func reloadFromModel() {
        guard isViewLoaded, !isUpdatingProjection else { return }
        isUpdatingProjection = true
        defer { isUpdatingProjection = false }

        let previousFocusGeneration = lastFilterFocusRequestGeneration
        rows = makeRows()
        let visibleIDs = rows.compactMap { row -> String? in
            row.isSelectable ? row.id : nil
        }
        presentation.reconcileVisibleItems(visibleIDs)
        lastFilterFocusRequestGeneration = presentation.filterFocusRequestGeneration

        updateHeader()
        updateRefreshStatus()
        updateState()
        tableView.reloadData()

        let selectedIndex = presentation.selectedItemID.flatMap { id in
            rows.firstIndex { $0.id == id && $0.isSelectable }
        }
        let selection = selectedIndex.map { IndexSet(integer: $0) } ?? []
        if tableView.selectedRowIndexes != selection {
            tableView.selectRowIndexes(selection, byExtendingSelection: false)
        }

        if presentation.filterFocusRequestGeneration != previousFocusGeneration {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.view.window else { return }
                window.makeFirstResponder(self.searchField)
            }
        }
    }

    private func makeRows() -> [Row] {
        let changes = session.visibleAgentChanges(for: presentation, locale: .current)
        let settlements = session.visibleSettlementRequirements(for: presentation, locale: .current)

        var result: [Row] = []
        if !changes.isEmpty {
            result.append(.category(ScholiumL10n.string("Agent Changes")))
            result.append(contentsOf: changes.map(Row.agentChange))
        }
        if !settlements.isEmpty {
            result.append(.category(ScholiumL10n.string("Settlement Reminders")))
            result.append(contentsOf: settlements.map(Row.settlement))
        }
        return result
    }

    private func updateHeader() {
        if presentation.noteScope != nil {
            scopeLabel.stringValue = ScholiumL10n.dynamicString("This Note")
        } else if let workspaceSlot = presentation.workspaceSlot {
            scopeLabel.stringValue = ScholiumL10n.dynamicString(workspaceSlot.displayName)
        } else {
            scopeLabel.stringValue = ""
        }
        scopeLabel.isHidden = scopeLabel.stringValue.isEmpty

        if (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true,
            searchField.stringValue != presentation.filter.query
        {
            searchField.stringValue = presentation.filter.query
        }
    }

    private func updateRefreshStatus() {
        guard let status = refreshStatus else {
            refreshStatusStack.isHidden = true
            return
        }
        refreshStatusStack.isHidden = false
        refreshStatusImage.image = NSImage(
            systemSymbolName: status.symbol,
            accessibilityDescription: status.message
        )
        refreshStatusImage.contentTintColor = status.color
        refreshStatusLabel.stringValue = status.message
        retryButton.isHidden = !status.offersRetry
        retryButton.isEnabled = !session.isRefreshing
        refreshStatusStack.setAccessibilityLabel(status.message)
        refreshStatusStack.setAccessibilityIdentifier("scholium.attentionRefreshStatus")
    }

    private func updateState() {
        let hasItems = rows.contains(where: { $0.isSelectable })
        listScrollView.isHidden = !hasItems
        stateStack.isHidden = hasItems

        guard !hasItems else {
            stateProgress.stopAnimation(nil)
            return
        }
        if session.isLoadingInitialContent {
            stateImage.isHidden = true
            stateProgress.isHidden = false
            stateProgress.startAnimation(nil)
            stateTitle.stringValue = ScholiumL10n.string("Loading Notifications…")
            stateDetail.stringValue = ""
            stateAction.isHidden = true
            return
        }

        stateProgress.stopAnimation(nil)
        stateProgress.isHidden = true
        stateImage.isHidden = false
        if let error = completeErrorMessage {
            stateImage.image = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: nil
            )
            stateTitle.stringValue = ScholiumL10n.string("Could Not Load Notifications")
            stateDetail.stringValue = error
            stateAction.title = ScholiumL10n.string("Retry")
            stateAction.isHidden = false
            stateAction.isEnabled = !session.isRefreshing
            return
        }

        stateImage.image = NSImage(
            systemSymbolName: "checkmark.circle",
            accessibilityDescription: nil
        )
        let query = presentation.filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        stateTitle.stringValue = query.isEmpty && presentation.notificationFilter == .all
            ? ScholiumL10n.string("No Notifications")
            : ScholiumL10n.string("No Matching Notifications")
        stateDetail.stringValue = ""
        stateAction.isHidden = true
    }

    private var completeErrorMessage: String? {
        let messages = [session.agentChangesError, session.catalogError].compactMap { $0 }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    private struct RefreshStatus {
        let symbol: String
        let message: String
        let color: NSColor
        let offersRetry: Bool
    }

    private var refreshStatus: RefreshStatus? {
        if session.isRefreshing, rows.contains(where: { $0.isSelectable }) {
            return RefreshStatus(
                symbol: "arrow.triangle.2.circlepath",
                message: AttentionNotificationCopy.refreshing(),
                color: ScholiumColorRole.information.nsColor,
                offersRetry: false
            )
        }
        switch session.derivedRefreshStatus {
        case .opening:
            return RefreshStatus(
                symbol: "arrow.triangle.2.circlepath",
                message: AttentionNotificationCopy.refreshing(),
                color: ScholiumColorRole.information.nsColor,
                offersRetry: false
            )
        case .stale(let issue):
            return RefreshStatus(
                symbol: "clock.badge.exclamationmark",
                message: AttentionNotificationCopy.stale(reason: issue.reason),
                color: ScholiumColorRole.attention.nsColor,
                offersRetry: true
            )
        case .failed(let issue):
            return RefreshStatus(
                symbol: "exclamationmark.triangle",
                message: AttentionNotificationCopy.refreshFailed(reason: issue.reason),
                color: ScholiumColorRole.destructive.nsColor,
                offersRetry: true
            )
        case .current, nil:
            if let error = session.agentChangesError {
                return RefreshStatus(
                    symbol: "exclamationmark.triangle",
                    message: ScholiumL10n.string("Agent Changes Unavailable") + ". " + error,
                    color: ScholiumColorRole.destructive.nsColor,
                    offersRetry: true
                )
            }
            if let error = session.catalogError, session.catalogIsAvailable {
                return RefreshStatus(
                    symbol: "exclamationmark.triangle",
                    message: AttentionNotificationCopy.refreshFailed(reason: error),
                    color: ScholiumColorRole.destructive.nsColor,
                    offersRetry: true
                )
            }
            return nil
        }
    }

    private func makeSearchMenu() -> NSMenu {
        let menu = NSMenu(title: ScholiumL10n.string("Search"))
        let choices: [(String, FilterTag)] = [
            ("All Notifications", .all),
            ("Agent Changes", .agentChanges),
            ("Settlement Reminders", .settlements),
        ]
        for (title, tag) in choices {
            let item = NSMenuItem(
                title: ScholiumL10n.dynamicString(title),
                action: #selector(selectFilter(_:)),
                keyEquivalent: ""
            )
            item.tag = tag.rawValue
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @objc private func selectFilter(_ sender: NSMenuItem) {
        guard let tag = FilterTag(rawValue: sender.tag) else { return }
        switch tag {
        case .all: presentation.notificationFilter = .all
        case .agentChanges: presentation.notificationFilter = .agentChanges
        case .settlements: presentation.notificationFilter = .settlements
        }
        reloadFromModel()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let tag = FilterTag(rawValue: menuItem.tag) else { return false }
        let selected: Bool
        switch tag {
        case .all: selected = presentation.notificationFilter == .all
        case .agentChanges: selected = presentation.notificationFilter == .agentChanges
        case .settlements: selected = presentation.notificationFilter == .settlements
        }
        menuItem.state = selected ? .on : .off
        return true
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField,
            (field.currentEditor() as? NSTextView)?.hasMarkedText() != true
        else { return }
        presentation.filter = AttentionQueueFilter(query: field.stringValue)
        reloadFromModel()
    }

    @objc private func retryRefresh(_ sender: Any?) {
        Task { [weak self] in
            guard let self else { return }
            await self.session.refresh()
        }
    }

    @objc private func activateSelectedRow(_ sender: Any?) {
        let rowIndex = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard rows.indices.contains(rowIndex) else { return }
        inspect(rows[rowIndex])
    }

    private func inspect(_ row: Row) {
        switch row {
        case .category:
            return
        case .agentChange(let change):
            session.inspect(change)
        case .settlement(let requirement):
            session.inspect(requirement)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard rows.indices.contains(row) else { return false }
        if case .category = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        rows.indices.contains(row) && rows[row].isSelectable
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let id = rows.indices.contains(tableView.selectedRow) && rows[tableView.selectedRow].isSelectable
            ? rows[tableView.selectedRow].id
            : nil
        presentation.select(id)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        switch rows[row] {
        case .category(let title):
            let identifier = NSUserInterfaceItemIdentifier("attention.category")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? AttentionCategoryCell
                ?? AttentionCategoryCell(identifier: identifier)
            cell.configure(title: title)
            return cell
        case .agentChange(let change):
            let cell = makeItemCell(tableView: tableView)
            let state = ScholiumL10n.localized(
                AgentChangePresentation.stateTitle(
                    for: change,
                    endingRevisionState: session.endingRevisionState(for: change)
                )
            )
            cell.configure(
                symbol: AgentChangePresentation.operationSymbol(for: change.operation),
                color: ScholiumColorRole.agentAuthorship.nsColor,
                title: session.noteTitle(for: change),
                detail: ScholiumL10n.localized(
                    AgentChangePresentation.operationTitle(for: change.operation)
                ) + " · " + state,
                date: (change.confirmedAt ?? change.createdAt).formatted(
                    Date.FormatStyle(date: .abbreviated, time: .shortened)
                ),
                accessibilityLabel: agentChangeAccessibilitySummary(change)
            )
            cell.setAccessibilityIdentifier(
                "scholium.notification.agentChange.\(change.id.uuidString.lowercased())"
            )
            return cell
        case .settlement(let requirement):
            let cell = makeItemCell(tableView: tableView)
            cell.configure(
                symbol: "exclamationmark.circle",
                color: ScholiumColorRole.attention.nsColor,
                title: requirement.title,
                detail: ScholiumL10n.string("Current Revision Not Settled"),
                date: nil,
                accessibilityLabel: String.localizedStringWithFormat(
                    ScholiumL10n.string("Current Revision Not Settled, %@"),
                    requirement.title
                ) + ", " + requirement.note.relativePath
            )
            cell.setAccessibilityIdentifier(
                "scholium.notification.settlement.\(requirement.noteID.uuidString.lowercased())"
            )
            return cell
        }
    }

    private func makeItemCell(tableView: NSTableView) -> AttentionItemCell {
        let identifier = NSUserInterfaceItemIdentifier("attention.item")
        return tableView.makeView(withIdentifier: identifier, owner: self) as? AttentionItemCell
            ?? AttentionItemCell(identifier: identifier)
    }

    private func agentChangeAccessibilitySummary(_ change: AgentChange) -> String {
        [
            ScholiumL10n.localized(AgentChangePresentation.operationTitle(for: change.operation)),
            session.noteTitle(for: change),
            AgentChangePresentation.path(for: change),
            ScholiumL10n.localized(
                AgentChangePresentation.stateTitle(
                    for: change,
                    endingRevisionState: session.endingRevisionState(for: change)
                )
            ),
            (change.confirmedAt ?? change.createdAt).formatted(.dateTime),
        ].joined(separator: ", ")
    }
}

@MainActor
private final class AttentionQueueTableView: NSTableView {
    var activate: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount == 1 else { return }
        activate?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            activate?()
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
private final class AttentionCategoryCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.setAccessibilityElement(false)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ScholiumGrid.Spacing.sectionSeparation),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ScholiumGrid.Spacing.sectionSeparation),
            label.topAnchor.constraint(equalTo: topAnchor, constant: ScholiumGrid.Spacing.labelAccessoryGap),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -ScholiumGrid.Spacing.opticalAlignmentAdjustment),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { nil }

    func configure(title: String) {
        label.stringValue = title
        setAccessibilityLabel(title)
    }
}

@MainActor
private final class AttentionItemCell: NSTableCellView {
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    private let textStack = NSStackView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.row)

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        icon.setAccessibilityElement(false)
        addSubview(icon)

        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 2
        titleLabel.setAccessibilityElement(false)
        detailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 2
        detailLabel.setAccessibilityElement(false)
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = ScholiumGrid.Spacing.labelAccessoryGap
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(detailLabel)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)

        dateLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        dateLabel.textColor = .secondaryLabelColor
        dateLabel.setContentHuggingPriority(.required, for: .horizontal)
        dateLabel.setAccessibilityElement(false)
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dateLabel)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ScholiumGrid.Spacing.labelAccessoryGap),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: ScholiumGrid.Dimension.iconTrackWidth),
            icon.heightAnchor.constraint(equalToConstant: ScholiumGrid.Dimension.iconTrackWidth),
            textStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: ScholiumGrid.Spacing.inlineControlGap),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: ScholiumGrid.Spacing.inlineControlGap),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -ScholiumGrid.Spacing.inlineControlGap),
            dateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: ScholiumGrid.Spacing.labelAccessoryGap),
            dateLabel.topAnchor.constraint(equalTo: textStack.topAnchor),
            dateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ScholiumGrid.Spacing.labelAccessoryGap),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: dateLabel.leadingAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(
        symbol: String,
        color: NSColor,
        title: String,
        detail: String,
        date: String?,
        accessibilityLabel: String
    ) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = color
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        dateLabel.stringValue = date ?? ""
        dateLabel.isHidden = date == nil
        setAccessibilityLabel(accessibilityLabel)
        toolTip = accessibilityLabel
    }
}
