import AppKit
import Combine

/// Projects one reader session into actual native toolbar items. AppKit owns
/// their measuring, grouping and interaction; the controller admits commands.
@MainActor
final class PDFReaderToolbarController: NSObject, NSToolbarItemValidation, NSMenuDelegate, NSPopoverDelegate, NSTextFieldDelegate {
    enum Presentation { case actions, expanded, compact }
    static let navigationID = ScholiumWorkspaceToolbarController.Item.readerControls
    static let searchID = NSToolbarItem.Identifier("scholium.pdf.search.toggle")
    static let actionsID = NSToolbarItem.Identifier("scholium.pdf.actions")
    static let compactID = NSToolbarItem.Identifier("scholium.pdf.compactControls")
    static let allIdentifiers = [navigationID, searchID, actionsID, compactID]

    static func itemIdentifiers(for presentation: Presentation) -> [NSToolbarItem.Identifier] {
        switch presentation {
        case .actions: [actionsID]
        case .expanded: [navigationID, .space, searchID, actionsID]
        case .compact: [navigationID, .space, compactID]
        }
    }

    private weak var controller: PDFReaderController?
    private weak var window: NSWindow?
    private weak var toolbar: NSToolbar?
    private weak var readerView: NSView?
    private var observation: AnyCancellable?
    private var pageFocusObservation: NSObjectProtocol?
    private var isInvalidated = false
    private let presentationDidChange: @MainActor () -> Void
    private(set) var presentation = Presentation.actions
    private var regionWidth: CGFloat?
    private var trailingPaneSwitchCount = 0
    private let navigation = NSToolbarItemGroup(itemIdentifier: navigationID)
    private let previous = NSToolbarItem(itemIdentifier: .init("scholium.pdf.previous"))
    private let next = NSToolbarItem(itemIdentifier: .init("scholium.pdf.next"))
    private let search = NSToolbarItem(itemIdentifier: searchID)
    private let pageItem = NSToolbarItem(itemIdentifier: .init("scholium.pdf.page.control"))
    private let actions = NSMenuToolbarItem(itemIdentifier: actionsID)
    private let compact = NSMenuToolbarItem(itemIdentifier: compactID)
    private let page = NSTextField(string: "1")
    private let count = NSTextField(labelWithString: "")
    private let pageContent = NSStackView()
    private var pageWidth: NSLayoutConstraint!
    private var measuredPageCount: Int?
    private var projectedContext: PDFReaderNoteContext?
    private var projectedDocument: ObjectIdentifier?
    private var projectedPageNumber: Int?
    private var actionMenu: PDFReaderCommandMenu!
    private let overflow = NSMenu()
    private let searchPopover = NSPopover()
    private var searchController: PDFReaderSearchViewController?
    private var searchContext: PDFReaderNoteContext?
    private var searchDocument: ObjectIdentifier?
    private weak var responderBeforeSearch: NSResponder?
    private var restoresSearchFocus = false
    private let presentationActivity: PDFReaderPresentationActivity
    private var overflowToken: PDFReaderPresentationActivity.Token?
    private var searchToken: PDFReaderPresentationActivity.Token?
    private var pageFocusToken: PDFReaderPresentationActivity.Token?
    private var pageFocusRevoked = false

    var itemIdentifiers: [NSToolbarItem.Identifier] { Self.itemIdentifiers(for: presentation) }

    init(controller: PDFReaderController, presentationDidChange: @escaping @MainActor () -> Void) {
        self.controller = controller
        presentationActivity = controller.presentationActivity
        self.presentationDidChange = presentationDidChange
        super.init()
        configure(previous, symbol: "chevron.left", label: "Previous PDF Page", action: #selector(previousPage))
        configure(next, symbol: "chevron.right", label: "Next PDF Page", action: #selector(nextPage))
        configure(search, symbol: "magnifyingglass", label: "Search PDF", action: #selector(openSearch))
        configure(actions, symbol: "ellipsis", label: "PDF Actions", action: nil)
        configure(compact, symbol: "ellipsis", label: "PDF Reader", action: nil)
        actions.showsIndicator = false
        compact.showsIndicator = false
        navigation.label = ScholiumL10n.string("PDF Reader")
        navigation.paletteLabel = navigation.label
        navigation.controlRepresentation = .expanded
        navigation.visibilityPriority = .high
        page.alignment = .center
        page.controlSize = ScholiumNativeToolbarPresentation.controlSize
        page.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: page.controlSize), weight: .regular)
        page.isBezeled = false
        page.isBordered = false
        page.drawsBackground = false
        page.usesSingleLineMode = true
        page.setAccessibilityLabel(ScholiumL10n.string("PDF Page"))
        page.setAccessibilityIdentifier("scholium.pdf.page")
        page.target = self
        page.action = #selector(goToPage)
        page.delegate = self
        pageWidth = page.widthAnchor.constraint(equalToConstant: ScholiumMetrics.PDFReader.toolsControlSize)
        pageWidth.isActive = true
        count.font = page.font
        count.textColor = .secondaryLabelColor
        count.setContentHuggingPriority(.required, for: .horizontal)
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        pageContent.orientation = .horizontal
        pageContent.alignment = .centerY
        pageContent.spacing = ScholiumGrid.Spacing.labelAccessoryGap
        pageContent.edgeInsets = NSEdgeInsets(top: 0, left: ScholiumGrid.Spacing.labelAccessoryGap, bottom: 0, right: ScholiumGrid.Spacing.labelAccessoryGap)
        pageContent.addArrangedSubview(page)
        pageContent.addArrangedSubview(count)
        pageItem.label = page.accessibilityLabel() ?? ""
        pageItem.paletteLabel = pageItem.label
        pageItem.view = pageContent
        navigation.subitems = [previous, pageItem, next]
        actionMenu = PDFReaderCommandMenu(controller: controller, kind: .actions) { [weak self] in self?.allowsCommands == true }
        actions.menu = actionMenu.menu
        overflow.autoenablesItems = false
        overflow.delegate = self
        for (title, action) in [("Previous PDF Page", #selector(previousPage)), ("Next PDF Page", #selector(nextPage)), ("Search PDF", #selector(openSearch))] {
            let item = NSMenuItem(title: ScholiumL10n.dynamicString(title), action: action, keyEquivalent: "")
            item.target = self
            overflow.addItem(item)
        }
        overflow.addItem(.separator())
        let more = NSMenuItem(title: ScholiumL10n.string("PDF Actions"), action: nil, keyEquivalent: "")
        more.identifier = .init(Self.actionsID.rawValue + ".group")
        more.submenu = actionMenu.makeOverflowMenu()
        overflow.addItem(more)
        compact.menu = overflow
        let navigationMenu = NSMenuItem(title: navigation.label, action: nil, keyEquivalent: "")
        navigationMenu.submenu = overflow
        navigation.menuFormRepresentation = navigationMenu
        searchPopover.behavior = .transient
        searchPopover.delegate = self
        presentation = controller.document == nil ? .actions : .expanded
        observation = controller.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    func item(for identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch identifier {
        case Self.navigationID: navigation
        case Self.searchID: search
        case Self.actionsID: actions
        case Self.compactID: compact
        default: nil
        }
    }

    func install(in window: NSWindow, toolbar: NSToolbar, readerView: NSView?) {
        guard !isInvalidated else { return }
        if self.window !== window || self.toolbar !== toolbar {
            removePageFocusObservation()
            endPageFocus()
            pageFocusRevoked = hasPageFocus
            pageFocusObservation = NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.synchronizePageFocus()
                }
            }
        }
        self.window = window
        self.toolbar = toolbar
        self.readerView = readerView
        refresh()
    }

    func setRegionWidth(width: CGFloat, trailingPaneSwitchCount: Int) {
        guard width.isFinite, width > 0, !isInvalidated else { return }
        regionWidth = width
        self.trailingPaneSwitchCount = max(0, trailingPaneSwitchCount)
        refresh()
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refresh() }

    func menuWillOpen(_ menu: NSMenu) {
        guard !isInvalidated, menu === overflow, overflowToken == nil else { return }
        overflowToken = presentationActivity.begin()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === overflow else { return }
        endOverflowPresentation()
    }

    private func endOverflowPresentation() {
        if let token = overflowToken {
            overflowToken = nil
            presentationActivity.end(token)
        }
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === page else { return }
        synchronizePageFocus()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === page else { return }
        endPageFocus()
    }

    private var hasPageFocus: Bool {
        guard let window, page.window === window, !page.isHiddenOrHasHiddenAncestor,
            let editor = page.currentEditor()
        else { return false }
        return window.firstResponder === editor
    }

    private var canKeepPageEditor: Bool {
        guard let controller, !isInvalidated, hasToolbarBinding, controller.isVisible,
            controller.document != nil, hasPageFocus, !pageFocusRevoked
        else { return false }
        return projectedContext == controller.context && projectedDocument == controller.document.map(ObjectIdentifier.init)
    }

    private func updatePageAdmission() {
        // Disabling a focused NSTextField destroys its field editor. Keep only
        // that existing draft through a temporary freeze; actions stay guarded.
        let enabled = controller?.document != nil && (allowsCommands || canKeepPageEditor)
        page.isEnabled = enabled
        navigation.isEnabled = enabled
    }

    private func synchronizePageFocus() {
        guard !isInvalidated, let controller else { return }
        updatePageAdmission()
        guard hasPageFocus else {
            pageFocusRevoked = false
            endPageFocus()
            return
        }
        if !controller.isVisible || !hasToolbarBinding || projectedContext != controller.context
            || projectedDocument != controller.document.map(ObjectIdentifier.init)
        {
            // A surviving field editor belongs to the previous presentation
            // after hide/replacement. It must leave before a fresh focus pins
            // the new reader; a late window update cannot revive that lifetime.
            pageFocusRevoked = true
            endPageFocus()
            return
        }
        // Temporary command admission barriers pause this pin without revoking
        // the same native editor's presentation lifetime when they are lifted.
        guard allowsCommands, controller.document != nil, !pageFocusRevoked else {
            endPageFocus()
            return
        }
        if pageFocusToken == nil { pageFocusToken = presentationActivity.begin() }
    }

    private func endPageFocus() {
        if let token = pageFocusToken {
            pageFocusToken = nil
            presentationActivity.end(token)
        }
    }

    private func removePageFocusObservation() {
        if let pageFocusObservation { NotificationCenter.default.removeObserver(pageFocusObservation) }
        pageFocusObservation = nil
    }

    func refresh() {
        guard !isInvalidated, let controller else { return }
        let available = allowsCommands
        let loaded = controller.document != nil
        let documentID = controller.document.map(ObjectIdentifier.init)
        let changedDocument = projectedContext != controller.context || projectedDocument != documentID
        if !available || changedDocument {
            actionMenu.cancelTracking()
            overflow.cancelTracking()
            endOverflowPresentation()
            if hasPageFocus, changedDocument || !controller.isVisible || !hasToolbarBinding { pageFocusRevoked = true }
            endPageFocus()
        }
        projectedContext = controller.context
        projectedDocument = documentID
        previous.isEnabled = validateToolbarItem(previous)
        next.isEnabled = validateToolbarItem(next)
        updatePageAdmission()
        // Preserve an unsubmitted field draft through unrelated projections,
        // but actual navigation or document replacement must display its page.
        if changedDocument || projectedPageNumber != controller.pageNumber
            || page.currentEditor() == nil || window?.firstResponder !== page.currentEditor()
        {
            page.stringValue = String(controller.pageNumber)
        }
        projectedPageNumber = controller.pageNumber
        count.stringValue = "/ \(controller.pageCount)"
        if measuredPageCount != controller.pageCount {
            measuredPageCount = controller.pageCount
            let digits = NSTextField(labelWithString: String(max(1, controller.pageCount)))
            digits.font = page.font
            pageWidth.constant = max(
                ScholiumMetrics.PDFReader.toolsControlSize,
                digits.fittingSize.width + ScholiumGrid.Spacing.inlineControlGap)
        }
        search.isEnabled = validateToolbarItem(search)
        compact.isEnabled = available && loaded
        actionMenu.update(controller: controller)
        actions.isEnabled = actionMenu.isEnabled
        actions.toolTip = controller.filename ?? actions.label
        overflow.items[0].isEnabled = previous.isEnabled
        overflow.items[1].isEnabled = next.isEnabled
        overflow.items[2].isEnabled = search.isEnabled
        let expandedWidth =
            pageContent.fittingSize.width
            + CGFloat(4 + trailingPaneSwitchCount) * ScholiumMetrics.PDFReader.toolbarItemAllowance
            + ScholiumGrid.Spacing.nestedContentInset * 2
        let compactPresentation = regionWidth.map { $0 < expandedWidth } ?? false
        let nextPresentation: Presentation = !loaded ? .actions : compactPresentation ? .compact : .expanded
        let changed = presentation != nextPresentation
        presentation = nextPresentation
        let subitems = compactPresentation ? [pageItem] : [previous, pageItem, next]
        if navigation.subitems != subitems { navigation.subitems = subitems }
        if searchPopover.isShown {
            if !available || !loaded || searchContext != controller.context || searchDocument != controller.document.map(ObjectIdentifier.init) {
                closeSearch()
            } else {
                searchController?.refresh()
            }
        }
        if changed { presentationDidChange() }
        synchronizePageFocus()
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        observation?.cancel()
        observation = nil
        removePageFocusObservation()
        closeSearch()
        searchPopover.delegate = nil
        actionMenu.invalidate()
        overflow.cancelTracking()
        endOverflowPresentation()
        endPageFocus()
        overflow.delegate = nil
        for item in overflow.items {
            item.target = nil
            item.action = nil
        }
        overflow.removeAllItems()
        for item in [navigation, previous, next, search, pageItem, actions, compact] {
            item.target = nil
            item.action = nil
            item.menuFormRepresentation = nil
            item.isEnabled = false
            item.isHidden = true
        }
        page.target = nil
        page.action = nil
        page.delegate = nil
        page.isEnabled = false
        controller = nil
        window = nil
        toolbar = nil
        readerView = nil
    }

    private var hasToolbarBinding: Bool { toolbar != nil && window?.toolbar === toolbar }

    private var allowsCommands: Bool {
        !isInvalidated && hasToolbarBinding
            && controller?.isVisible == true && controller?.canUseReaderCommands == true
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        if item === navigation || item === pageItem, canKeepPageEditor { return true }
        guard allowsCommands, let controller else { return false }
        if item === actions { return actionMenu.isEnabled }
        guard controller.document != nil else { return false }
        if item === previous { return controller.pageNumber > 1 }
        if item === next { return controller.pageNumber < controller.pageCount }
        return item === navigation || item === pageItem || item === search || item === compact
    }

    private func configure(_ item: NSToolbarItem, symbol: String, label: String, action: Selector?) {
        item.label = ScholiumL10n.dynamicString(label)
        item.paletteLabel = item.label
        item.toolTip = item.label
        item.image = ScholiumNativeToolbarPresentation.symbol(named: symbol, accessibilityDescription: item.label)
        item.isBordered = true
        item.style = .plain
        item.visibilityPriority = .high
        item.target = action == nil ? nil : self
        item.action = action
    }

    @objc private func previousPage() {
        guard allowsCommands, let controller, controller.pageNumber > 1 else { return }
        controller.goToPage(controller.pageNumber - 1)
    }

    @objc private func nextPage() {
        guard allowsCommands, let controller, controller.pageNumber < controller.pageCount else { return }
        controller.goToPage(controller.pageNumber + 1)
    }

    @objc private func goToPage() {
        guard allowsCommands, let controller, controller.document != nil else { return }
        if let number = Int(page.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) { controller.goToPage(number) }
        page.stringValue = String(controller.pageNumber)
    }

    @objc private func openSearch() {
        guard allowsCommands, let controller, controller.document != nil,
            let window, let anchor = readerView, anchor.window === window, !anchor.isHiddenOrHasHiddenAncestor
        else { return }
        if searchPopover.isShown {
            closeSearch(restoringFocus: true)
            return
        }
        responderBeforeSearch =
            (window.firstResponder as? NSTextView)?.delegate as? NSView
            ?? window.firstResponder
        let content = PDFReaderSearchViewController(controller: controller) { [weak self] in self?.closeSearch(restoringFocus: true) }
        searchController = content
        searchContext = controller.context
        searchDocument = controller.document.map(ObjectIdentifier.init)
        searchPopover.contentViewController = content
        let windowRect = anchor.convert(anchor.bounds, to: nil)
        let point = anchor.convert(NSPoint(x: windowRect.midX, y: window.contentLayoutRect.maxY), from: nil)
        searchPopover.show(relativeTo: NSRect(origin: point, size: .zero), of: anchor, preferredEdge: .minY)
    }

    private func closeSearch(restoringFocus: Bool = false) {
        restoresSearchFocus = restoringFocus
        searchPopover.close()
        endSearchPresentation()
        searchPopover.contentViewController = nil
        searchController = nil
        searchContext = nil
        searchDocument = nil
    }

    func popoverWillShow(_ notification: Notification) {
        guard !isInvalidated, notification.object as? NSPopover === searchPopover, searchToken == nil else { return }
        searchToken = presentationActivity.begin()
    }

    private func endSearchPresentation() {
        if let token = searchToken {
            searchToken = nil
            presentationActivity.end(token)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        endSearchPresentation()
        if restoresSearchFocus, !isInvalidated, let responder = responderBeforeSearch as? NSView,
            responder.window === window, !responder.isHiddenOrHasHiddenAncestor
        {
            window?.makeFirstResponder(responder)
        }
        restoresSearchFocus = false
        responderBeforeSearch = nil
        searchPopover.contentViewController = nil
        searchController = nil
        searchContext = nil
        searchDocument = nil
    }
}

@MainActor
private final class PDFReaderSearchViewController: NSViewController, NSTextFieldDelegate {
    private weak var controller: PDFReaderController?
    private let close: () -> Void
    private let field = NSTextField(string: "")
    private let status = NSTextField(labelWithString: "")
    private var previous: NSButton!
    private var next: NSButton!

    init(controller: PDFReaderController, close: @escaping () -> Void) {
        self.controller = controller
        self.close = close
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        field.stringValue = controller?.searchQuery ?? ""
        field.placeholderString = ScholiumL10n.string("Search PDF")
        field.setAccessibilityLabel(ScholiumL10n.string("Search PDF"))
        field.setAccessibilityIdentifier("scholium.pdf.search")
        field.target = self
        field.action = #selector(nextMatch)
        field.delegate = self
        field.widthAnchor.constraint(equalToConstant: 220).isActive = true
        previous = button("chevron.up", label: "Previous PDF Match", action: #selector(previousMatch))
        next = button("chevron.down", label: "Next PDF Match", action: #selector(nextMatch))
        let row = NSStackView(views: [field, previous, next])
        row.spacing = 6
        row.alignment = .centerY
        let stack = NSStackView(views: [row, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        view = stack
        preferredContentSize = NSSize(width: 320, height: 72)
        refresh()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(field)
    }

    func refresh() {
        status.stringValue = controller?.searchStatus ?? ""
        status.isHidden = status.stringValue.isEmpty
        let canFind = controller?.canUseReaderCommands == true && !field.stringValue.isEmpty
        previous?.isEnabled = canFind
        next?.isEnabled = canFind
    }

    func controlTextDidChange(_ notification: Notification) {
        controller?.searchQuery = field.stringValue
        refresh()
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            close()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { previousMatch() } else { nextMatch() }
            return true
        }
        return false
    }

    @objc private func previousMatch() {
        controller?.searchQuery = field.stringValue
        controller?.find(backwards: true)
        refresh()
    }
    @objc private func nextMatch() {
        controller?.searchQuery = field.stringValue
        controller?.find()
        refresh()
    }

    private func button(_ symbol: String, label: String, action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(ScholiumL10n.dynamicString(label))
        button.toolTip = ScholiumL10n.dynamicString(label)
        button.isBordered = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }
}

/// Core reader actions participate in the custom toolbar's native key-view
/// sequence even when the system limits ordinary decorative toolbar buttons.
@MainActor
final class PDFReaderToolbarButton: NSButton {
    var focusDidChange: (@MainActor (Bool) -> Void)?
    override var acceptsFirstResponder: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }
    override var canBecomeKeyView: Bool { acceptsFirstResponder }

    override func becomeFirstResponder() -> Bool {
        focusDidChange?(true)
        let accepted = super.becomeFirstResponder()
        if !accepted { focusDidChange?(false) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { focusDidChange?(false) }
        return resigned
    }
}
