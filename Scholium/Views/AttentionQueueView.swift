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
final class AttentionQueueViewController: NSViewController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private enum Row {
        case category(String)
        case change(DocumentChangeSummary)

        var id: String {
            switch self {
            case .category(let title): "category:\(title)"
            case .change(let change): "change:\(change.vaultID.uuidString.lowercased()):\(change.noteID.uuidString.lowercased())"
            }
        }

        var isSelectable: Bool {
            switch self {
            case .category: false
            case .change: true
            }
        }
    }

    private let session: AttentionPopoverSession
    private var presentation: AttentionPresentationState { session.presentation }
    private let rootStack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private let refreshStatusStack = NSStackView()
    private let refreshStatusImage = NSImageView()
    private let refreshStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let retryButton = NSButton(title: "", target: nil, action: nil)
    private let listScrollView = NSScrollView()
    private let tableView = AttentionQueueTableView()
    private let stateContainer = NSView()
    private let stateStack = NSStackView()
    private let stateImage = NSImageView()
    private let stateProgress = NSProgressIndicator()
    private let stateTitle = NSTextField(wrappingLabelWithString: "")
    private let stateDetail = NSTextField(wrappingLabelWithString: "")
    private let stateAction = NSButton(title: "", target: nil, action: nil)

    private var rows: [Row] = []
    private var observations: Set<AnyCancellable> = []
    private var hasAppliedInitialFocus = false
    private var isUpdatingProjection = false
    private var isApplyingSelection = false
    private var reloadIsScheduled = false

    init(session: AttentionPopoverSession) {
        self.session = session
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
            guard let self, !self.hasAppliedInitialFocus, let window = self.view.window else { return }
            let target: NSView = self.listScrollView.isHidden ? self.searchField : self.tableView
            self.hasAppliedInitialFocus = window.makeFirstResponder(target)
        }
    }

    private func configureControls() {
        titleLabel.stringValue = ScholiumL10n.string("Notifications")
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize + 1, weight: .semibold)
        titleLabel.setAccessibilityLabel(titleLabel.stringValue)
        titleLabel.setAccessibilityRole(.staticText)

        searchField.placeholderString = ScholiumL10n.string("Search")
        searchField.sendsSearchStringImmediately = true
        searchField.maximumRecents = 0
        searchField.delegate = self
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
        tableView.activate = { [weak self] row in self?.activateRow(at: row) ?? false }
        tableView.target = tableView
        tableView.action = #selector(AttentionQueueTableView.activateClickedRow(_:))
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
        stateStack.translatesAutoresizingMaskIntoConstraints = false

        stateImage.imageScaling = .scaleProportionallyDown
        stateImage.setAccessibilityElement(false)
        stateProgress.style = .spinning
        stateProgress.controlSize = .small
        stateProgress.setAccessibilityElement(false)
        stateTitle.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        stateTitle.alignment = .center
        stateTitle.maximumNumberOfLines = 2
        stateTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stateDetail.alignment = .center
        stateDetail.textColor = .secondaryLabelColor
        stateDetail.maximumNumberOfLines = 0
        stateDetail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
        rootStack.addArrangedSubview(stateContainer)
        stateContainer.addSubview(stateStack)
        stateContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
        root.addSubview(rootStack)

        let preferredStateWidth = stateStack.widthAnchor.constraint(
            equalTo: stateContainer.widthAnchor,
            constant: -2 * ScholiumGrid.Spacing.regionContentInset
        )
        preferredStateWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: root.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            listScrollView.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            listScrollView.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            stateContainer.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            stateContainer.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            stateStack.centerXAnchor.constraint(equalTo: stateContainer.centerXAnchor),
            stateStack.centerYAnchor.constraint(equalTo: stateContainer.centerYAnchor),
            stateStack.leadingAnchor.constraint(greaterThanOrEqualTo: stateContainer.leadingAnchor, constant: ScholiumGrid.Spacing.regionContentInset),
            stateStack.trailingAnchor.constraint(lessThanOrEqualTo: stateContainer.trailingAnchor, constant: -ScholiumGrid.Spacing.regionContentInset),
            stateStack.topAnchor.constraint(greaterThanOrEqualTo: stateContainer.topAnchor, constant: ScholiumGrid.Spacing.regionContentInset),
            stateStack.bottomAnchor.constraint(lessThanOrEqualTo: stateContainer.bottomAnchor, constant: -ScholiumGrid.Spacing.regionContentInset),
            stateStack.widthAnchor.constraint(lessThanOrEqualToConstant: ScholiumGrid.ContentState.readableWidth),
            preferredStateWidth,
            stateTitle.widthAnchor.constraint(equalTo: stateStack.widthAnchor),
            stateDetail.widthAnchor.constraint(equalTo: stateStack.widthAnchor),
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

        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(searchField)
        header.addArrangedSubview(refreshStatusStack)
        return header
    }

    private func observePresentation() {
        presentation.$filter
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleReload() }
            .store(in: &observations)
        presentation.$selectedItemID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] id in self?.updateSelection(id) }
            .store(in: &observations)
        presentation.$filterFocusRequestGeneration
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.focusFilter() }
            .store(in: &observations)
        session.objectWillChange
            .sink { [weak self] in self?.scheduleReload() }
            .store(in: &observations)
    }

    private func scheduleReload() {
        guard !reloadIsScheduled else { return }
        reloadIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            reloadIsScheduled = false
            reloadFromModel()
        }
    }

    private func reloadFromModel() {
        guard isViewLoaded, !isUpdatingProjection else { return }
        isUpdatingProjection = true
        defer { isUpdatingProjection = false }

        rows = makeRows()
        let visibleIDs = rows.compactMap { row -> String? in
            row.isSelectable ? row.id : nil
        }
        presentation.reconcileVisibleItems(visibleIDs)

        updateSearchField()
        updateRefreshStatus()
        updateState()
        tableView.reloadData()

        if listScrollView.isHidden, let window = view.window, window.firstResponder === tableView {
            window.makeFirstResponder(searchField)
        }

        updateSelection(presentation.selectedItemID)
    }

    private func updateSelection(_ id: String?) {
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        let selectedIndex = id.flatMap { id in
            rows.firstIndex { $0.id == id && $0.isSelectable }
        }
        let selection = selectedIndex.map { IndexSet(integer: $0) } ?? []
        if tableView.selectedRowIndexes != selection {
            tableView.selectRowIndexes(selection, byExtendingSelection: false)
        }
    }

    private func focusFilter() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.view.window else { return }
            window.makeFirstResponder(self.searchField)
        }
    }

    private func makeRows() -> [Row] {
        let changes = session.visibleDocumentChanges()

        var result: [Row] = []
        if !changes.isEmpty {
            result.append(.category(ScholiumL10n.string("Changes")))
            result.append(contentsOf: changes.map(Row.change))
        }
        return result
    }

    private func updateSearchField() {
        if (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true,
            searchField.stringValue != presentation.filter.query
        {
            searchField.stringValue = presentation.filter.query
        }
    }

    private func updateRefreshStatus() {
        if !rows.contains(where: { $0.isSelectable }), completeErrorMessage != nil {
            refreshStatusStack.isHidden = true
            return
        }
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
        stateContainer.isHidden = hasItems

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
            stateImage.contentTintColor = ScholiumColorRole.destructive.nsColor
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
        stateImage.contentTintColor = .secondaryLabelColor
        let query = presentation.filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        stateTitle.stringValue =
            query.isEmpty
            ? ScholiumL10n.string("No Notifications")
            : ScholiumL10n.string("No Matching Notifications")
        stateDetail.stringValue = ""
        stateAction.isHidden = true
    }

    private var completeErrorMessage: String? {
        let messages = [session.documentChangesError, session.catalogError].compactMap { $0 }
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
            if let error = session.documentChangesError {
                return RefreshStatus(
                    symbol: "exclamationmark.triangle",
                    message: ScholiumL10n.string("Changes Unavailable") + ". " + error,
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

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField,
            (field.currentEditor() as? NSTextView)?.hasMarkedText() != true
        else { return }
        presentation.filter = AttentionQueueFilter(query: field.stringValue)
    }

    @objc private func retryRefresh(_ sender: Any?) {
        Task { [weak self] in
            guard let self else { return }
            await self.session.refresh()
        }
    }

    private func activateRow(at rowIndex: Int) -> Bool {
        guard session.isPresented, rows.indices.contains(rowIndex), case .change(let shown) = rows[rowIndex],
            let current = session.visibleDocumentChanges().first(where: {
                $0.id == shown.id && $0.vaultID == shown.vaultID
            })
        else { return false }
        if tableView.selectedRow != rowIndex {
            tableView.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
        }
        return session.inspect(current)
    }

    private func activateItem(id: String) -> Bool {
        guard let row = rows.firstIndex(where: { $0.id == id && $0.isSelectable }) else { return false }
        return activateRow(at: row)
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
        guard !isUpdatingProjection, !isApplyingSelection else { return }
        let id =
            rows.indices.contains(tableView.selectedRow) && rows[tableView.selectedRow].isSelectable
            ? rows[tableView.selectedRow].id
            : nil
        presentation.select(id)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        switch rows[row] {
        case .category(let title):
            let identifier = NSUserInterfaceItemIdentifier("attention.category")
            let cell =
                tableView.makeView(withIdentifier: identifier, owner: self) as? AttentionCategoryCell
                ?? AttentionCategoryCell(identifier: identifier)
            cell.configure(title: title)
            return cell
        case .change(let change):
            let cell = makeItemCell(tableView: tableView)
            cell.configure(
                symbol: "doc.text.magnifyingglass",
                color: ScholiumColorRole.information.nsColor,
                title: session.noteTitle(for: change),
                detail: ScholiumL10n.string("Pending Changes"),
                date: change.savedAt?.formatted(
                    Date.FormatStyle(date: .abbreviated, time: .shortened)
                ),
                accessibilityLabel: changeAccessibilitySummary(change),
                accessibilityIdentifier: "scholium.notification.change.\(change.id.uuidString.lowercased())"
            )
            let id = rows[row].id
            cell.activate = { [weak self] in self?.activateItem(id: id) ?? false }
            return cell
        }
    }

    private func makeItemCell(tableView: NSTableView) -> AttentionItemCell {
        let identifier = NSUserInterfaceItemIdentifier("attention.item")
        return tableView.makeView(withIdentifier: identifier, owner: self) as? AttentionItemCell
            ?? AttentionItemCell(identifier: identifier)
    }

    private func changeAccessibilitySummary(_ change: DocumentChangeSummary) -> String {
        [
            ScholiumL10n.string("Pending Changes"),
            session.noteTitle(for: change),
            change.relativePath,
            change.savedAt?.formatted(.dateTime) ?? "",
        ].joined(separator: ", ")
    }
}

@MainActor
final class AttentionQueueTableView: NSTableView {
    var activate: ((Int) -> Bool)?

    @objc func activateClickedRow(_ sender: Any?) {
        // clickedRow is owned by AppKit's recognized click action. Reading it
        // after mouseDown's tracking loop has returned loses that context.
        _ = activate?(clickedRow)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            _ = activate?(selectedRow)
            return
        }
        super.keyDown(with: event)
    }

    override func accessibilityPerformConfirm() -> Bool { activate?(selectedRow) ?? false }
    override func accessibilityPerformPress() -> Bool { activate?(selectedRow) ?? false }
}

@MainActor
private final class AttentionNotificationButton: NSButton {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) != nil else { return nil }
        // The icon and wrapping labels are this button's presentation. Let the
        // native button own tracking across all of its content.
        return self
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
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ScholiumGrid.Dimension.iconTrackWidth + ScholiumGrid.Spacing.inlineControlGap),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
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
    var activate: (() -> Bool)?
    private let activationButton = AttentionNotificationButton(title: "", target: nil, action: nil)
    private let icon = NSImageView()
    private var iconColor: NSColor = .labelColor
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)
        activationButton.translatesAutoresizingMaskIntoConstraints = false
        activationButton.isBordered = false
        activationButton.target = self
        activationButton.action = #selector(activateNotification(_:))
        addSubview(activationButton)

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        icon.setAccessibilityElement(false)
        activationButton.addSubview(icon)
        imageView = icon

        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2
        titleLabel.isSelectable = false
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setAccessibilityElement(false)
        detailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 2
        detailLabel.isSelectable = false
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.setAccessibilityElement(false)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        activationButton.addSubview(titleLabel)
        activationButton.addSubview(detailLabel)
        textField = titleLabel

        NSLayoutConstraint.activate([
            activationButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            activationButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            activationButton.topAnchor.constraint(equalTo: topAnchor),
            activationButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.leadingAnchor.constraint(equalTo: activationButton.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: activationButton.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: ScholiumGrid.Dimension.iconTrackWidth),
            icon.heightAnchor.constraint(equalToConstant: ScholiumGrid.Dimension.iconTrackWidth),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: ScholiumGrid.Spacing.inlineControlGap),
            titleLabel.trailingAnchor.constraint(equalTo: activationButton.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: activationButton.topAnchor, constant: ScholiumGrid.Spacing.inlineControlGap),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: ScholiumGrid.Spacing.labelAccessoryGap),
            detailLabel.bottomAnchor.constraint(equalTo: activationButton.bottomAnchor, constant: -ScholiumGrid.Spacing.inlineControlGap),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyForegroundStyle() }
    }

    func configure(
        symbol: String,
        color: NSColor,
        title: String,
        detail: String,
        date: String?,
        accessibilityLabel: String,
        accessibilityIdentifier: String
    ) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        iconColor = color
        titleLabel.stringValue = title
        detailLabel.stringValue = date.map { "\(detail) · \($0)" } ?? detail
        activationButton.setAccessibilityLabel(accessibilityLabel)
        activationButton.setAccessibilityIdentifier(accessibilityIdentifier)
        // View-based NSTableView exposes the native button cell through its row
        // proxies. Both public representations name the same current action.
        activationButton.cell?.setAccessibilityLabel(accessibilityLabel)
        activationButton.cell?.setAccessibilityIdentifier(accessibilityIdentifier)
        toolTip = accessibilityLabel
        applyForegroundStyle()
    }

    @objc private func activateNotification(_ sender: Any?) { _ = activate?() }

    private func applyForegroundStyle() {
        let isSelected = backgroundStyle == .emphasized
        icon.contentTintColor = isSelected ? .alternateSelectedControlTextColor : iconColor
        titleLabel.cell?.backgroundStyle = backgroundStyle
        detailLabel.cell?.backgroundStyle = backgroundStyle
        titleLabel.textColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
        detailLabel.textColor = isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
    }
}
