import AppKit
import Combine

/// One presentation owner for the reader controls in workspace and detached
/// toolbars. The reader controller remains the command and document owner.
@MainActor
final class PDFReaderToolbarItem: NSToolbarItem, NSMenuDelegate, NSPopoverDelegate, NSTextFieldDelegate {
    private weak var controller: PDFReaderController?
    private weak var window: NSWindow?
    private var observation: AnyCancellable?
    private var isInvalidated = false
    private let previous = PDFReaderToolbarButton()
    private let next = PDFReaderToolbarButton()
    private let search = PDFReaderToolbarButton()
    private let compact = PDFReaderToolbarButton()
    private(set) var usesCompactPresentation = false
    private var regionWidth: CGFloat?
    private var trailingPaneSwitchCount = 0
    private let page = NSTextField(string: "1")
    private let count = NSTextField(labelWithString: "")
    private var menus: [PDFReaderNativeMenuButton] = []
    private let overflow = NSMenu()
    private let searchPopover = NSPopover()
    private var searchController: PDFReaderSearchViewController?
    private var searchContext: PDFReaderNoteContext?
    private var searchDocument: ObjectIdentifier?
    private var restoresSearchFocus = false

    init(identifier: NSToolbarItem.Identifier, controller: PDFReaderController) {
        self.controller = controller
        super.init(itemIdentifier: identifier)
        label = ScholiumL10n.string("PDF Reader")
        paletteLabel = label
        isBordered = true
        style = .plain
        visibilityPriority = .high
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        stack.setAccessibilityIdentifier("scholium.pdf.controls")
        stack.setAccessibilityLabel(label)
        configure(previous, symbol: "chevron.left", label: "Previous PDF Page", action: #selector(previousPage))
        configure(next, symbol: "chevron.right", label: "Next PDF Page", action: #selector(nextPage))
        configure(search, symbol: "magnifyingglass", label: "Search PDF", action: #selector(openSearch))
        search.setAccessibilityIdentifier("scholium.pdf.search.toggle")
        configure(compact, symbol: "slider.horizontal.3", label: "PDF Reader", action: #selector(openCompactMenu))
        compact.setAccessibilityIdentifier("scholium.pdf.compactControls")
        compact.setAccessibilityRole(.menuButton)
        compact.isHidden = true
        page.alignment = .center
        page.controlSize = .regular
        page.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        page.setAccessibilityLabel(ScholiumL10n.string("PDF Page"))
        page.setAccessibilityIdentifier("scholium.pdf.page")
        page.target = self
        page.delegate = self
        page.action = #selector(goToPage)
        page.widthAnchor.constraint(equalToConstant: 32).isActive = true
        count.font = page.font
        count.textColor = .secondaryLabelColor
        for control in [previous, page, count, next] { stack.addArrangedSubview(control) }
        for kind in [PDFReaderMenuButton.Kind.zoom, .annotations, .actions] {
            let button = PDFReaderNativeMenuButton(controller: controller, kind: kind) { [weak self] in self?.allowsCommands == true }
            menus.append(button)
            if kind == .annotations { stack.addArrangedSubview(search) }
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(compact)
        stack.frame = NSRect(x: 0, y: 0, width: 244, height: 28)
        view = stack
        overflow.autoenablesItems = false
        overflow.delegate = self
        for (title, action) in [
            ("Previous PDF Page", #selector(previousPage)), ("Next PDF Page", #selector(nextPage)),
            ("Search PDF", #selector(openSearch)),
        ] {
            let item = NSMenuItem(title: ScholiumL10n.dynamicString(title), action: action, keyEquivalent: "")
            item.target = self
            overflow.addItem(item)
        }
        overflow.addItem(.separator())
        for (kind, button) in zip([PDFReaderMenuButton.Kind.zoom, .annotations, .actions], menus) {
            let item = NSMenuItem(title: ScholiumL10n.dynamicString(kind.title), action: nil, keyEquivalent: "")
            item.identifier = .init(kind.identifier + ".group")
            item.submenu = button.makeOverflowMenu()
            overflow.addItem(item)
        }
        let root = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        root.submenu = overflow
        menuFormRepresentation = root
        searchPopover.behavior = .transient
        searchPopover.delegate = self
        observation = controller.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    func install(in window: NSWindow) { if !isInvalidated { self.window = window } }

    /// AppKit can constrain a tracking separator before the whole toolbar
    /// overflows. Adapt to the actual reading region, retaining every command.
    func setRegionWidth(width: CGFloat, trailingPaneSwitchCount: Int) {
        guard width.isFinite, width > 0, !isInvalidated else { return }
        regionWidth = width
        self.trailingPaneSwitchCount = max(0, trailingPaneSwitchCount)
        refresh()
    }

    override func validate() { refresh() }
    func menuNeedsUpdate(_ menu: NSMenu) { refresh() }

    func refresh() {
        guard !isInvalidated, let controller else { return }
        let available = allowsCommands
        let loaded = controller.document != nil
        isEnabled = available
        toolTip = controller.filename ?? label
        previous.isEnabled = available && loaded && controller.pageNumber > 1
        next.isEnabled = available && loaded && controller.pageNumber < controller.pageCount
        page.isEnabled = available && loaded
        // A focused field retains the user's incomplete page entry until submit.
        if page.currentEditor() == nil || window?.firstResponder !== page.currentEditor() { page.stringValue = String(controller.pageNumber) }
        count.stringValue = "/ \(controller.pageCount)"
        search.isEnabled = available && loaded
        // Reserve native pane switches and their chrome within the reader's
        // trailing region rather than forcing its real divider to move.
        let compactPresentation = regionWidth.map { $0 < 244 + CGFloat(trailingPaneSwitchCount) * 44 + 16 } ?? false
        let presentationChanged = usesCompactPresentation != compactPresentation
        usesCompactPresentation = compactPresentation
        page.isHidden = !loaded
        count.isHidden = !loaded
        for control in [previous, next, search] { control.isHidden = !loaded || compactPresentation }
        compact.isHidden = !loaded || !compactPresentation
        compact.isEnabled = available && loaded
        for (index, menu) in menus.enumerated() {
            menu.update(controller: controller)
            menu.isHidden = compactPresentation && loaded || index < 2 && !loaded
        }
        overflow.items[0].isEnabled = previous.isEnabled
        overflow.items[1].isEnabled = next.isEnabled
        overflow.items[2].isEnabled = search.isEnabled
        menuFormRepresentation?.isEnabled = available
        if let stack = view as? NSStackView {
            let desiredWidth = max(loaded ? (compactPresentation ? 92 : 244) : 28, stack.fittingSize.width)
            if abs(stack.frame.width - desiredWidth) > 0.5 || presentationChanged {
                stack.setFrameSize(NSSize(width: desiredWidth, height: 28))
                stack.invalidateIntrinsicContentSize()
            }
        }
        if searchPopover.isShown {
            if !available || !loaded || !controller.isVisible || toolbar == nil || isHidden
                || searchContext != controller.context || searchDocument != controller.document.map(ObjectIdentifier.init)
            {
                closeSearch()
            } else {
                searchController?.refresh()
            }
        }
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        observation?.cancel()
        observation = nil
        closeSearch()
        searchPopover.delegate = nil
        for menu in menus { menu.invalidate() }
        for control in [previous, next, search, compact] {
            control.target = nil
            control.action = nil
            control.isEnabled = false
        }
        page.target = nil
        page.delegate = nil
        page.action = nil
        page.isEnabled = false
        for item in overflow.items {
            item.target = nil
            item.action = nil
        }
        overflow.cancelTracking()
        overflow.removeAllItems()
        overflow.delegate = nil
        let inert = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        inert.isEnabled = false
        menuFormRepresentation = inert
        controller = nil
        window = nil
        isEnabled = false
        isHidden = true
    }

    private var allowsCommands: Bool {
        !isInvalidated && toolbar != nil && !isHidden && controller?.isVisible == true && controller?.canUseReaderCommands == true
    }

    private func configure(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.image = ScholiumNativeToolbarPresentation.symbol(named: symbol)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.controlSize = ScholiumNativeToolbarPresentation.controlSize
        button.setButtonType(.momentaryPushIn)
        button.setAccessibilityLabel(ScholiumL10n.dynamicString(label))
        button.toolTip = ScholiumL10n.dynamicString(label)
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
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
        if let number = Int(page.stringValue) { controller.goToPage(number) }
        page.stringValue = String(controller.pageNumber)
        window?.makeFirstResponder(page)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === page, allowsCommands else { return false }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            let following: [NSView] = [next, menus[0], search, menus[1], menus[2], compact]
            guard let candidate = following.first(where: { !$0.isHiddenOrHasHiddenAncestor && $0.canBecomeKeyView }) else { return false }
            return window?.makeFirstResponder(candidate) == true
        }
        return false
    }

    @objc private func openCompactMenu() {
        guard allowsCommands, compact.isEnabled, !compact.isHiddenOrHasHiddenAncestor else { return }
        refresh()
        overflow.popUp(positioning: nil, at: NSPoint(x: compact.bounds.minX, y: compact.bounds.minY), in: compact)
    }

    @objc private func openSearch() {
        guard !isInvalidated, let controller, controller.canUseReaderCommands,
            controller.document != nil, controller.isVisible, toolbar != nil, !isHidden,
            let window, let content = window.contentView
        else { return }
        if searchPopover.isShown {
            closeSearch(restoringFocus: true)
            return
        }
        let searchController = PDFReaderSearchViewController(controller: controller) { [weak self] in self?.closeSearch(restoringFocus: true) }
        self.searchController = searchController
        searchContext = controller.context
        searchDocument = controller.document.map(ObjectIdentifier.init)
        searchPopover.contentViewController = searchController
        let anchor = usesCompactPresentation ? compact : search
        if anchor.window === window, !anchor.isHiddenOrHasHiddenAncestor {
            searchPopover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        } else {
            let point = content.convert(NSPoint(x: window.contentLayoutRect.maxX - 20, y: window.contentLayoutRect.maxY), from: nil)
            searchPopover.show(relativeTo: NSRect(origin: point, size: .zero), of: content, preferredEdge: .minY)
        }
    }

    private func closeSearch(restoringFocus: Bool = false) {
        restoresSearchFocus = restoringFocus
        searchPopover.close()
        searchPopover.contentViewController = nil
        searchController = nil
        searchContext = nil
        searchDocument = nil
    }

    func popoverDidClose(_ notification: Notification) {
        let anchor = usesCompactPresentation ? compact : search
        if restoresSearchFocus, !isInvalidated, anchor.window === window, anchor.isEnabled, !anchor.isHiddenOrHasHiddenAncestor {
            window?.makeFirstResponder(anchor)
        }
        restoresSearchFocus = false
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
        let row = NSStackView(views: [
            field, button("chevron.up", label: "Previous PDF Match", action: #selector(previousMatch)),
            button("chevron.down", label: "Next PDF Match", action: #selector(nextMatch)),
        ])
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
    }

    func controlTextDidChange(_ notification: Notification) { controller?.searchQuery = field.stringValue }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            close()
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
private final class PDFReaderToolbarButton: NSButton {
    override var acceptsFirstResponder: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }
    override var canBecomeKeyView: Bool { acceptsFirstResponder }
}
