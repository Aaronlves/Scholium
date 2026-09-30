import AppKit

/// One native toolbar item contains the continuous Document-tab surface.
/// DocumentTabController owns membership, order, and committed selection.
@MainActor
final class DocumentToolbarTabItem: NSToolbarItem {
    static let identifier = NSToolbarItem.Identifier("scholium.toolbar.documentTabs")
    static let pasteboardType = NSPasteboard.PasteboardType("com.scholium.document-tab")

    let control: DocumentToolbarTabStrip
    weak var owner: DocumentToolbarTabs?

    init(owner: DocumentToolbarTabs) {
        self.owner = owner
        control = DocumentToolbarTabStrip()
        super.init(itemIdentifier: Self.identifier)
        isBordered = false
        view = control
        paletteLabel = ScholiumL10n.string("Document Tabs")
        label = ScholiumL10n.string("Document Tabs")
        visibilityPriority = .high
        control.owner = owner
    }

    func refresh(tabs: [DocumentTabItem], selectedID: UUID?) {
        let menu = NSMenu(title: ScholiumL10n.string("Document Tabs"))
        for tab in tabs {
            let entry = NSMenuItem(title: tab.title, action: #selector(selectFromOverflow(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = tab.id
            entry.state = tab.id == selectedID ? .on : .off
            entry.toolTip = tab.toolTip
            menu.addItem(entry)
        }
        let overflow = NSMenuItem(title: ScholiumL10n.string("Document Tabs"), action: nil, keyEquivalent: "")
        overflow.submenu = menu
        menuFormRepresentation = overflow
    }

    @objc private func selectFromOverflow(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { owner?.select(id) }
    }
}

/// Transient toolbar-tab interactions. This projection never owns Document
/// membership or a retained editor session.
@MainActor
final class DocumentToolbarTabs: NSObject {
    private(set) var tabs: [DocumentTabItem] = []
    private(set) var selectedID: UUID?
    private lazy var toolbarItem = DocumentToolbarTabItem(owner: self)
    private var controls: [UUID: DocumentToolbarTabControl] = [:]
    private var draggedID: UUID?
    private var cancelled = false
    private var cancellationMonitor: Any?
    private weak var gapControl: DocumentToolbarTabControl?
    private struct DragPreview {
        let tab: NSImage
        let destination: NSImage
        var showsDestination = false
    }
    private var dragPreview: DragPreview?

    var select: (UUID) -> Void = { _ in }
    var close: (UUID) -> Void = { _ in }
    var detach: (UUID, NSPoint?) -> Void = { _, _ in }
    var reorder: (UUID, Int) -> Void = { _, _ in }

    var visibleIdentifiers: [NSToolbarItem.Identifier] {
        tabs.count > 1 ? [DocumentToolbarTabItem.identifier] : []
    }

    func item(for identifier: NSToolbarItem.Identifier) -> DocumentToolbarTabItem? {
        identifier == DocumentToolbarTabItem.identifier ? toolbarItem : nil
    }

    func control(for id: UUID) -> DocumentToolbarTabControl? { controls[id] }

    func update(tabs: [DocumentTabItem], selectedID: UUID?) {
        guard self.tabs != tabs || self.selectedID != selectedID else { return }
        self.tabs = tabs
        self.selectedID = selectedID
        for id in Set(controls.keys).subtracting(tabs.map(\.id)) {
            controls.removeValue(forKey: id)?.invalidate()
        }
        for tab in tabs {
            let control = controls[tab.id] ?? DocumentToolbarTabControl(tab: tab, owner: self)
            controls[tab.id] = control
            control.refresh(tab: tab, selected: tab.id == selectedID)
        }
        toolbarItem.control.update(controls: tabs.compactMap { controls[$0.id] }, selectedID: selectedID)
        toolbarItem.refresh(tabs: tabs, selectedID: selectedID)
        if let draggedID, !tabs.contains(where: { $0.id == draggedID }) { clearDrag() }
    }

    func invalidate() {
        clearDrag()
        for control in controls.values { control.invalidate() }
        controls.removeAll()
        toolbarItem.menuFormRepresentation = nil
        toolbarItem.owner = nil
        toolbarItem.control.update(controls: [], selectedID: nil)
        toolbarItem.control.invalidateContextRouting()
        select = { _ in }
        close = { _ in }
        detach = { _, _ in }
        reorder = { _, _ in }
    }

    func menu(for id: UUID) -> NSMenu? {
        guard tabs.contains(where: { $0.id == id }) else { return nil }
        let menu = NSMenu()
        for (title, action) in [
            ("Move to Separate Window", #selector(moveTab(_:))),
            ("Close Tab", #selector(closeTab(_:))),
        ] {
            let item = NSMenuItem(title: ScholiumL10n.dynamicString(title), action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = id
            menu.addItem(item)
        }
        return menu
    }

    @objc private func moveTab(_ item: NSMenuItem) {
        if let id = item.representedObject as? UUID { detach(id, nil) }
    }

    @objc private func closeTab(_ item: NSMenuItem) {
        if let id = item.representedObject as? UUID { close(id) }
    }

    func selectNeighbor(of id: UUID, offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), tabs.count > 1 else { return }
        let next = tabs[(index + offset + tabs.count) % tabs.count].id
        controls[next]?.focusSelection()
        select(next)
    }

    func beginDrag(from control: DocumentToolbarTabControl, gesture: NSPanGestureRecognizer, initialEvent: NSEvent?) {
        guard let item = prepareDraggingItem(from: control) else { return }
        let session: NSDraggingSession?
        if #available(macOS 27.0, *) {
            session = control.beginDraggingSession(items: [item], gesture: gesture, source: control)
        } else if let initialEvent {
            session = control.beginDraggingSession(with: [item], event: initialEvent, source: control)
        } else {
            session = nil
        }
        guard let session else {
            clearDrag()
            return
        }
        session.draggingFormation = .none
        control.isDragPlaceholder = true
    }

    func prepareDraggingItem(from control: DocumentToolbarTabControl) -> NSDraggingItem? {
        guard draggedID == nil, control.owner === self,
            controls[control.tab.id] === control, tabStripScreenFrame() != nil,
            let bitmap = control.bitmapImageRepForCachingDisplay(in: control.bounds)
        else { return nil }
        control.cacheDisplay(in: control.bounds, to: bitmap)
        let image = NSImage(size: control.bounds.size)
        image.addRepresentation(bitmap)
        draggedID = control.tab.id
        cancelled = false
        dragPreview = DragPreview(tab: image, destination: detachmentLabel())
        let pasteboard = NSPasteboardItem()
        pasteboard.setString(control.tab.id.uuidString, forType: DocumentToolbarTabItem.pasteboardType)
        let item = NSDraggingItem(pasteboardWriter: pasteboard)
        item.setDraggingFrame(control.bounds, contents: image)
        cancellationMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancelDrag() }
            return event
        }
        return item
    }

    func draggingUpdated(over control: DocumentToolbarTabControl, sender: any NSDraggingInfo) -> NSDragOperation {
        guard !cancelled, let source = sender.draggingSource as? DocumentToolbarTabControl,
            source.owner === self, control.owner === self,
            let draggedID,
            source.tab.id == draggedID, controls[draggedID] === source,
            sender.draggingPasteboard.string(forType: DocumentToolbarTabItem.pasteboardType) == draggedID.uuidString,
            let window = source.window, control.window === window,
            sender.draggingDestinationWindow === window
        else { return [] }
        let point = control.convert(sender.draggingLocation, from: nil)
        if gapControl !== control { gapControl?.dropSide = nil }
        gapControl = control
        let physicalLeading = point.x < control.bounds.midX
        let isRTL = control.userInterfaceLayoutDirection == .rightToLeft
        control.dropSide = physicalLeading == isRTL ? .after : .before
        return .move
    }

    func draggingExited(_ control: DocumentToolbarTabControl) {
        if gapControl === control { gapControl = nil }
        control.dropSide = nil
    }

    func performDrop(on control: DocumentToolbarTabControl) -> Bool {
        guard !cancelled, control.owner === self, gapControl === control, let draggedID,
            let source = tabs.firstIndex(where: { $0.id == draggedID }),
            let target = tabs.firstIndex(where: { $0.id == control.tab.id }),
            let side = control.dropSide
        else { return false }
        let boundary = target + (side == .after ? 1 : 0)
        let destination = boundary > source ? boundary - 1 : boundary
        control.dropSide = nil
        gapControl = nil
        reorder(draggedID, min(max(0, destination), tabs.count - 1))
        return true
    }

    func finishDrag(at point: NSPoint, operation: NSDragOperation, window: NSWindow?) {
        let id = draggedID
        let movesOutside = isDetachmentDrop(at: point, operation: operation, window: window)
        clearDrag()
        if movesOutside, let id, tabs.contains(where: { $0.id == id }) { detach(id, point) }
    }

    func shouldAnimateDragReturn(at point: NSPoint, operation: NSDragOperation, window: NSWindow?) -> Bool {
        let movesOutside = isDetachmentDrop(at: point, operation: operation, window: window)
        return !movesOutside && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func cancelDrag() {
        cancelled = true
        gapControl?.dropSide = nil
        gapControl = nil
    }

    private func tabStripScreenFrame() -> NSRect? {
        let strip = toolbarItem.control
        guard let window = strip.window, !strip.isHiddenOrHasHiddenAncestor,
            window.toolbar?.isVisible != false, !strip.visibleRect.isEmpty
        else { return nil }
        return window.convertToScreen(strip.convert(strip.visibleRect, to: nil))
    }

    private func isDetachmentDrop(at point: NSPoint, operation: NSDragOperation, window: NSWindow?) -> Bool {
        guard !cancelled, operation.isEmpty, let draggedID,
            controls[draggedID]?.window === window, window != nil,
            point.x.isFinite, point.y.isFinite,
            let frame = tabStripScreenFrame()
        else { return false }
        return !frame.contains(point)
    }

    func draggingPreviewComponents(at point: NSPoint, window: NSWindow?) -> [NSDraggingImageComponent]? {
        guard let preview = dragPreview else { return nil }
        let tab = NSDraggingImageComponent(key: .icon)
        tab.contents = preview.tab
        tab.frame = NSRect(origin: .zero, size: preview.tab.size)
        guard isDetachmentDrop(at: point, operation: [], window: window) else { return [tab] }
        let destination = NSDraggingImageComponent(key: .label)
        destination.contents = preview.destination
        destination.frame = NSRect(
            x: (preview.tab.size.width - preview.destination.size.width) / 2,
            y: -preview.destination.size.height - ScholiumGrid.Spacing.inlineControlGap,
            width: preview.destination.size.width, height: preview.destination.size.height)
        return [tab, destination]
    }

    func updateDraggingPreview(_ session: NSDraggingSession, at point: NSPoint, window: NSWindow?) {
        let detaches = isDetachmentDrop(at: point, operation: [], window: window)
        guard let preview = dragPreview, preview.showsDestination != detaches,
            let components = draggingPreviewComponents(at: point, window: window)
        else { return }
        dragPreview?.showsDestination = detaches
        // AppKit owns the image and its cursor anchor. Components may extend
        // beyond the item bounds, so its original draggingFrame stays intact.
        session.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
            item.imageComponentsProvider = { components }
        }
    }

    private func detachmentLabel() -> NSImage {
        let padding = ScholiumGrid.Spacing.inlineControlGap
        let label = NSAttributedString(
            string: ScholiumL10n.string("Move to Separate Window"),
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.labelColor])
        let size = NSSize(width: ceil(label.size().width) + padding * 2, height: ceil(label.size().height) + padding * 2)
        let appearance = toolbarItem.control.effectiveAppearance
        return NSImage(size: size, flipped: false) { rect in
            appearance.performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.setFill()
                rect.fill()
                label.draw(at: NSPoint(x: padding, y: padding))
            }
            return true
        }
    }

    private func clearDrag() {
        if let cancellationMonitor { NSEvent.removeMonitor(cancellationMonitor) }
        cancellationMonitor = nil
        if let draggedID { controls[draggedID]?.isDragPlaceholder = false }
        gapControl?.dropSide = nil
        gapControl = nil
        draggedID = nil
        dragPreview = nil
    }
}

/// A single material well keeps adjacent tabs on one surface. The scroll view
/// lets the toolbar compress this item without clipping the selected tab.
@MainActor
final class DocumentToolbarTabStrip: NSVisualEffectView {
    weak var owner: DocumentToolbarTabs?
    private static let minimumWidth = DocumentToolbarTabControl.preferredInactiveWidth
    static let height: CGFloat = 36
    static let contentHeight = height - 2
    private static let edgeInset: CGFloat = 4
    private static let separatorSpace: CGFloat = 6

    private let scrollView = NSScrollView()
    private let row = NSStackView()
    private(set) var contextEventMonitor: Any?
    private var contextRoutingInvalidated = false
    private lazy var rowWidth = row.widthAnchor.constraint(equalToConstant: Self.minimumWidth)
    private var controls: [DocumentToolbarTabControl] = []
    private var separators: [NSBox] = []
    private var widthEqualities: [NSLayoutConstraint] = []
    private var equalWidthIDs: [UUID] = []
    private var selectedID: UUID?
    private var revealSelected = true
    private var previousViewportWidth: CGFloat = 0

    isolated deinit {
        if let contextEventMonitor { NSEvent.removeMonitor(contextEventMonitor) }
    }

    var orderedTabIDs: [UUID] { controls.map { $0.tab.id } }
    func control(for id: UUID) -> DocumentToolbarTabControl? {
        controls.first { $0.tab.id == id }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let viewportPoint = scrollView.convert(event.locationInWindow, from: nil)
        guard scrollView.bounds.contains(viewportPoint) else { return nil }
        let rowPoint = row.convert(event.locationInWindow, from: nil)
        return controls.first { $0.frame.contains(rowPoint) }?.menuForTab()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow { removeContextEventMonitor() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !contextRoutingInvalidated, contextEventMonitor == nil else { return }
        contextEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) {
            [weak self] event in
            guard let self else { return event }
            return self.handleContextEvent(event)
        }
    }

    func removeContextEventMonitor() {
        if let contextEventMonitor { NSEvent.removeMonitor(contextEventMonitor) }
        contextEventMonitor = nil
    }

    func invalidateContextRouting() {
        contextRoutingInvalidated = true
        removeContextEventMonitor()
        unregisterDraggedTypes()
        owner = nil
    }

    func contextMenu(for event: NSEvent) -> NSMenu? {
        guard
            event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)),
            let window, event.window === window,
            let toolbar = window.toolbar, toolbar.isVisible,
            toolbar.visibleItems?.contains(where: {
                $0.itemIdentifier == DocumentToolbarTabItem.identifier && $0.view === self
            }) == true,
            !isHiddenOrHasHiddenAncestor,
            !controls.contains(where: \.isDragPlaceholder),
            scrollView.contentView.bounds.contains(
                scrollView.contentView.convert(event.locationInWindow, from: nil)
            )
        else { return nil }
        return menu(for: event)
    }

    private func handleContextEvent(_ event: NSEvent) -> NSEvent? {
        guard let menu = contextMenu(for: event) else { return event }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        return nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.minimumWidth, height: Self.height))
        material = .titlebar
        blendingMode = .withinWindow
        state = .followsWindowActiveState
        wantsLayer = true
        registerForDraggedTypes([DocumentToolbarTabItem.pasteboardType])
        layer?.cornerRadius = Self.height / 2
        layer?.masksToBounds = true
        setAccessibilityElement(false)
        widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumWidth).isActive = true
        setContentHuggingPriority(.init(49), for: .horizontal)
        // NSToolbarItem measures its minimum below AppKit's fitting-size
        // compression priority. With no intrinsic width, AppKit can allocate
        // the toolbar's available span to this item.
        setContentCompressionResistancePriority(
            .init(NSLayoutConstraint.Priority.fittingSizeCompression.rawValue - 1),
            for: .horizontal)
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.contentView.drawsBackground = false
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = Self.separatorSpace / 2 - 0.5
        row.translatesAutoresizingMaskIntoConstraints = false
        rowWidth.isActive = true
        row.heightAnchor.constraint(equalToConstant: Self.contentHeight).isActive = true
        scrollView.documentView = row
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError("Code-only document toolbar tabs") }

    func dropTarget(at windowPoint: NSPoint) -> DocumentToolbarTabControl? {
        let point = row.convert(windowPoint, from: nil)
        return controls.first { point.x < $0.frame.midX } ?? controls.last
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let target = dropTarget(at: sender.draggingLocation) else { return [] }
        return owner?.draggingUpdated(over: target, sender: sender) ?? []
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        for control in controls { owner?.draggingExited(control) }
    }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { draggingUpdated(sender) == .move }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard draggingUpdated(sender) == .move, let target = dropTarget(at: sender.draggingLocation) else { return false }
        return owner?.performDrop(on: target) ?? false
    }

    func update(controls newControls: [DocumentToolbarTabControl], selectedID: UUID?) {
        if self.selectedID != selectedID {
            revealSelected = true
        } else if selectedIsFullyVisible() {
            // Retain visibility through title/order changes, while respecting
            // a researcher who deliberately scrolled away from the selection.
            revealSelected = true
        }
        self.selectedID = selectedID
        let orderChanged = controls.map { $0.tab.id } != newControls.map { $0.tab.id }
        let firstResponder = window?.firstResponder
        controls = newControls
        while separators.count < max(0, controls.count - 1) {
            let separator = NSBox()
            separator.boxType = .separator
            separator.setAccessibilityElement(false)
            separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
            separator.heightAnchor.constraint(equalToConstant: 16).isActive = true
            separators.append(separator)
        }
        while separators.count > max(0, controls.count - 1) {
            separators.removeLast()
        }
        if orderChanged {
            NSLayoutConstraint.deactivate(widthEqualities)
            widthEqualities.removeAll()
            equalWidthIDs.removeAll()
            for view in row.arrangedSubviews {
                row.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            for (index, control) in controls.enumerated() {
                row.addArrangedSubview(control)
                if index < separators.count { row.addArrangedSubview(separators[index]) }
            }
            if let focusedView = firstResponder as? NSView,
                controls.contains(where: { focusedView.isDescendant(of: $0) })
            {
                window?.makeFirstResponder(firstResponder)
            }
        }
        for (index, separator) in separators.enumerated() {
            let selected = selectedID
            separator.alphaValue = controls[index].tab.id == selected || controls[index + 1].tab.id == selected ? 0 : 1
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let wasSelectedVisible = selectedIsFullyVisible()
        scrollView.frame = bounds.insetBy(dx: Self.edgeInset, dy: 1)
        scrollView.layoutSubtreeIfNeeded()
        let viewportWidth = scrollView.contentView.bounds.width
        if abs(viewportWidth - previousViewportWidth) > 0.5 {
            if previousViewportWidth == 0 || wasSelectedVisible { revealSelected = true }
            previousViewportWidth = viewportWidth
        }
        let minimumRowWidth =
            CGFloat(controls.count) * DocumentToolbarTabControl.minimumWidth
            + CGFloat(max(0, controls.count - 1)) * Self.separatorSpace
        let width = max(viewportWidth, minimumRowWidth)
        rowWidth.constant = width
        let equalShare =
            controls.isEmpty
            ? 0
            : (width - CGFloat(max(0, controls.count - 1)) * Self.separatorSpace)
                / CGFloat(controls.count)
        let biasSelection =
            controls.count >= 4
            && equalShare < DocumentToolbarTabControl.preferredInactiveWidth
            && width > minimumRowWidth
        let equalControls =
            biasSelection
            ? controls.filter { $0.tab.id != selectedID }
            : controls
        let equalIDs = equalControls.map { $0.tab.id }
        if equalIDs != equalWidthIDs {
            NSLayoutConstraint.deactivate(widthEqualities)
            widthEqualities = equalControls.dropFirst().map {
                $0.widthAnchor.constraint(equalTo: equalControls[0].widthAnchor)
            }
            NSLayoutConstraint.activate(widthEqualities)
            equalWidthIDs = equalIDs
        }
        row.frame = NSRect(x: 0, y: 0, width: width, height: Self.contentHeight)
        row.layoutSubtreeIfNeeded()
        if revealSelected, let selected = controls.first(where: { $0.tab.id == selectedID }), viewportWidth > 0 {
            let visible = scrollView.contentView.documentVisibleRect
            let targetX: CGFloat
            if selected.frame.minX < visible.minX {
                targetX = selected.frame.minX
            } else if selected.frame.maxX > visible.maxX {
                targetX = selected.frame.maxX - visible.width
            } else {
                targetX = visible.minX
            }
            let maximumX = max(0, row.frame.width - visible.width)
            scrollView.contentView.scroll(to: NSPoint(x: min(max(0, targetX), maximumX), y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            revealSelected = false
        }
    }

    private func selectedIsFullyVisible() -> Bool {
        guard let selected = controls.first(where: { $0.tab.id == selectedID }),
            selected.frame.width > 0
        else { return false }
        let visible = scrollView.contentView.documentVisibleRect
        return visible.width > 0 && selected.frame.minX >= visible.minX - 0.5
            && selected.frame.maxX <= visible.maxX + 0.5
    }
}

/// The same content view carries the stable buttons inside the selected glass
/// or directly on the shared titlebar material after Document selection commits.
@MainActor
final class DocumentToolbarTabControl: NSView, NSDraggingSource, NSGestureRecognizerDelegate {
    enum DropSide { case before, after }
    static let minimumWidth: CGFloat = 112
    private static let height = DocumentToolbarTabStrip.contentHeight
    private static let closeWidth: CGFloat = 28
    private static let insertionGap: CGFloat = 10
    static let preferredInactiveWidth: CGFloat = 180

    var tab: DocumentTabItem
    weak var owner: DocumentToolbarTabs?
    var dropSide: DropSide? { didSet { needsLayout = true } }
    var isDragPlaceholder = false {
        didSet {
            alphaValue = isDragPlaceholder ? 0.15 : 1
            updateCloseVisibility()
        }
    }
    private let selectedSurface = NSGlassEffectView()
    private let emptyGlassContent = NSView()
    private let content = NSView()
    private let selection = DocumentToolbarTabButton()
    private let closeButton = NSButton()
    private var pointerIsInside = false
    private var hoverArea: NSTrackingArea?
    private var mouseDownEvent: NSEvent?
    private lazy var dragGesture = NSPanGestureRecognizer(target: self, action: #selector(dragTab(_:)))

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.preferredInactiveWidth, height: Self.height)
    }
    override var mouseDownCanMoveWindow: Bool { false }

    init(tab: DocumentTabItem, owner: DocumentToolbarTabs) {
        self.tab = tab
        self.owner = owner
        super.init(frame: NSRect(x: 0, y: 0, width: Self.minimumWidth, height: Self.height))
        widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumWidth).isActive = true
        setContentHuggingPriority(.init(100), for: .horizontal)
        setContentCompressionResistancePriority(.init(750), for: .horizontal)
        registerForDraggedTypes([DocumentToolbarTabItem.pasteboardType])
        selectedSurface.style = .regular
        selectedSurface.tintColor = nil
        selectedSurface.cornerRadius = Self.height / 2
        selectedSurface.contentView = emptyGlassContent
        selectedSurface.setAccessibilityElement(false)
        addSubview(selectedSurface)
        content.setAccessibilityElement(false)
        addSubview(content)
        selection.owner = self
        selection.setButtonType(.onOff)
        selection.target = self
        selection.action = #selector(selectTab)
        selection.isBordered = false
        selection.controlSize = .small
        selection.lineBreakMode = .byTruncatingTail
        selection.setAccessibilityRole(.radioButton)
        selection.setAccessibilityIdentifier("scholium.documentTab.\(tab.id.uuidString)")
        content.addSubview(selection)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.controlSize = .small
        closeButton.target = self
        closeButton.action = #selector(closeDocument)
        closeButton.toolTip = ScholiumL10n.string("Close Tab")
        closeButton.setAccessibilityLabel(ScholiumL10n.string("Close Tab"))
        content.addSubview(closeButton)
        dragGesture.delegate = self
        selection.addGestureRecognizer(dragGesture)
        refresh(tab: tab, selected: false)
    }

    required init?(coder: NSCoder) { fatalError("Code-only document toolbar tab") }

    func refresh(tab: DocumentTabItem, selected: Bool) {
        self.tab = tab
        setContentHuggingPriority(.init(selected ? 250 : 750), for: .horizontal)
        setContentCompressionResistancePriority(.init(selected ? 750 : 250), for: .horizontal)
        selection.title = tab.title
        selection.state = selected ? .on : .off
        let firstResponder = window?.firstResponder
        if selected {
            if selectedSurface.contentView !== content { selectedSurface.contentView = content }
        } else if content.superview !== self {
            selectedSurface.contentView = emptyGlassContent
            addSubview(content)
        }
        selectedSurface.isHidden = !selected
        if firstResponder === selection || firstResponder === closeButton {
            window?.makeFirstResponder(firstResponder)
        }
        selection.toolTip = tab.toolTip
        selection.setAccessibilityLabel(tab.title)
        selection.setAccessibilityValue(selected ? 1 : 0)
        invalidateIntrinsicContentSize()
        updateCloseVisibility()
    }

    func invalidate() {
        owner = nil
        selection.owner = nil
        selection.gestureRecognizers.removeAll()
        selection.target = nil
        selection.action = nil
        closeButton.target = nil
        closeButton.action = nil
        unregisterDraggedTypes()
    }

    override func layout() {
        super.layout()
        let leading = dropSide == .before ? Self.insertionGap : 0
        let trailing = dropSide == .after ? Self.insertionGap : 0
        let surfaceFrame = NSRect(
            x: leading, y: 0,
            width: max(0, bounds.width - leading - trailing), height: bounds.height)
        selectedSurface.frame = surfaceFrame
        content.frame = NSRect(
            origin: content.superview === self ? NSPoint(x: leading, y: 0) : .zero,
            size: surfaceFrame.size)
        closeButton.frame = NSRect(
            x: 0, y: (bounds.height - Self.closeWidth) / 2,
            width: Self.closeWidth, height: Self.closeWidth)
        selection.frame = NSRect(
            x: Self.closeWidth, y: 0,
            width: max(0, surfaceFrame.width - Self.closeWidth * 2), height: bounds.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        hoverArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        if let hoverArea { addTrackingArea(hoverArea) }
    }

    override func mouseEntered(with event: NSEvent) {
        pointerIsInside = true
        updateCloseVisibility()
    }
    override func mouseExited(with event: NSEvent) {
        pointerIsInside = false
        updateCloseVisibility()
    }

    func updateCloseVisibility() {
        closeButton.isHidden =
            isDragPlaceholder
            || (!pointerIsInside
                && window?.firstResponder !== selection && window?.firstResponder !== closeButton)
    }

    func focusSelection() { window?.makeFirstResponder(selection) }
    @objc func selectTab() {
        owner?.select(tab.id)
        // A native toggle responds before the asynchronous document transition
        // commits. Keep its appearance bound to the authoritative tab owner.
        selection.state = owner?.selectedID == tab.id ? .on : .off
    }
    @objc private func closeDocument() { owner?.close(tab.id) }

    func menuForTab() -> NSMenu? { owner?.menu(for: tab.id) }
    func selectNeighbor(offset: Int) { owner?.selectNeighbor(of: tab.id, offset: offset) }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        if event.type == .leftMouseDown { mouseDownEvent = event }
        return true
    }

    @objc private func dragTab(_ gesture: NSPanGestureRecognizer) {
        guard gesture.state == .began else { return }
        owner?.beginDrag(from: self, gesture: gesture, initialEvent: mouseDownEvent)
        mouseDownEvent = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuForTab() }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        owner?.draggingUpdated(over: self, sender: sender) ?? []
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { owner?.draggingExited(self) }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        owner?.draggingUpdated(over: self, sender: sender) == .move
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { owner?.performDrop(on: self) ?? false }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, movedTo point: NSPoint) {
        owner?.updateDraggingPreview(session, at: point, window: window)
    }
    func draggingSession(_ session: NSDraggingSession, endedAt point: NSPoint, operation: NSDragOperation) {
        owner?.updateDraggingPreview(session, at: point, window: window)
        session.animatesToStartingPositionsOnCancelOrFail =
            owner?.shouldAnimateDragReturn(
                at: point, operation: operation, window: window)
            ?? !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        owner?.finishDrag(at: point, operation: operation, window: window)
    }
}

@MainActor
final class DocumentToolbarTabButton: NSButton {
    weak var owner: DocumentToolbarTabControl?
    override var mouseDownCanMoveWindow: Bool { false }
    override func menu(for event: NSEvent) -> NSMenu? { owner?.menuForTab() }
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        owner?.updateCloseVisibility()
        return result
    }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        owner?.updateCloseVisibility()
        return result
    }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        [
            NSAccessibilityCustomAction(
                name: ScholiumL10n.string("Close Tab"), target: self,
                selector: #selector(accessibilityClose))
        ]
    }
    @objc private func accessibilityClose() -> Bool {
        guard let owner else { return false }
        owner.owner?.close(owner.tab.id)
        return true
    }
    override func accessibilityPerformPress() -> Bool {
        owner?.selectTab()
        return true
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 124:
            let direction = event.keyCode == 123 ? -1 : 1
            owner?.selectNeighbor(offset: userInterfaceLayoutDirection == .rightToLeft ? -direction : direction)
        case 36: owner?.selectTab()
        default: super.keyDown(with: event)
        }
    }
}
