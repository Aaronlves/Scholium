import AppKit

/// A content-tab strip, not a value selector. This is the only owner of tab
/// geometry and transient drag order. Membership changes have no animation.
@MainActor
final class DocumentTabStrip: NSView, NSDraggingSource {
    static let pasteboardType = NSPasteboard.PasteboardType("com.scholium.document-tab")
    private(set) var tabs: [DocumentTabItem] = []
    private(set) var selectedID: UUID?
    private var cells: [UUID: DocumentTabCell] = [:]
    var select: (UUID) -> Void = { _ in }
    var close: (UUID) -> Void = { _ in }
    var detach: (UUID, NSPoint?) -> Void = { _, _ in }
    var reorder: (UUID, Int) -> Void = { _, _ in }
    private var draggedID: UUID?
    private var previewOrder: [UUID]?
    private var cancelled = false
    private var cancellationMonitor: Any?
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([Self.pasteboardType])
        setAccessibilityElement(true)
        setAccessibilityRole(.tabGroup)
        setAccessibilityIdentifier("scholium.documentTabs")
        setAccessibilityLabel(ScholiumL10n.string("Document Tabs"))
    }
    required init?(coder: NSCoder) { fatalError("Code-only tab strip") }

    func update(tabs: [DocumentTabItem], selectedID: UUID?) {
        self.tabs = tabs
        self.selectedID = selectedID
        for id in Set(cells.keys).subtracting(tabs.map(\.id)) {
            cells.removeValue(forKey: id)?.removeFromSuperview()
        }
        for tab in tabs {
            let cell = cells[tab.id] ?? DocumentTabCell(tab: tab, strip: self)
            if cell.superview == nil { addSubview(cell); cells[tab.id] = cell }
            cell.tab = tab
            cell.toolTip = tab.toolTip
            cell.setAccessibilityLabel(tab.title)
            cell.setAccessibilityValue(tab.id == selectedID ? 1 : 0)
            cell.needsDisplay = true
        }
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let order = previewOrder ?? tabs.map(\.id)
        guard !order.isEmpty else { return }
        let width = bounds.width / CGFloat(order.count)
        for (index, id) in order.enumerated() {
            let visual = userInterfaceLayoutDirection == .rightToLeft ? order.count - 1 - index : index
            cells[id]?.frame = NSRect(x: CGFloat(visual) * width, y: 0, width: width, height: bounds.height)
            cells[id]?.needsLayout = true
        }
    }

    override func accessibilityChildren() -> [Any]? { tabs.compactMap { cells[$0.id] } }

    override func draw(_ dirtyRect: NSRect) {
        ScholiumDocumentTabStyle.track.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }

    func index(at point: NSPoint) -> Int? {
        guard bounds.contains(point), !tabs.isEmpty, bounds.width > 0 else { return nil }
        let index = min(tabs.count - 1, Int(point.x / (bounds.width / CGFloat(tabs.count))))
        return userInterfaceLayoutDirection == .rightToLeft ? tabs.count - 1 - index : index
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let index = index(at: convert(event.locationInWindow, from: nil)) else { return nil }
        return menu(for: tabs[index])
    }

    func menu(for tab: DocumentTabItem) -> NSMenu {
        let menu = NSMenu()
        for (title, action) in [("Move to Separate Window", #selector(moveTab(_:))), ("Close Tab", #selector(closeTab(_:)))] {
            let item = NSMenuItem(title: ScholiumL10n.dynamicString(title), action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = tab.id
            menu.addItem(item)
        }
        return menu
    }
    @objc private func moveTab(_ item: NSMenuItem) { if let id = item.representedObject as? UUID { detach(id, nil) } }
    @objc private func closeTab(_ item: NSMenuItem) { if let id = item.representedObject as? UUID { close(id) } }

    func selectNeighbor(of id: UUID, offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), !tabs.isEmpty else { return }
        let next = tabs[(index + offset + tabs.count) % tabs.count].id
        window?.makeFirstResponder(cells[next])
        select(next)
    }

    func beginDrag(_ cell: DocumentTabCell, gesture: NSPanGestureRecognizer, initialEvent: NSEvent?) {
        guard draggedID == nil, tabs.contains(where: { $0.id == cell.tab.id }) else { return }
        draggedID = cell.tab.id
        previewOrder = tabs.map(\.id)
        cancelled = false
        let draggedTab = cell.tab
        let drawing = NSImage(size: cell.bounds.size, flipped: true) { rect in
            DocumentTabCell.draw(tab: draggedTab, selected: true, in: rect)
            return true
        }
        // The drag server receives an immutable bitmap, with no deferred draw
        // callback into a live AppKit view or its actor-owned presentation.
        guard let data = drawing.tiffRepresentation, let image = NSImage(data: data) else { clearDrag(); return }
        let pasteboard = NSPasteboardItem()
        pasteboard.setString(cell.tab.id.uuidString, forType: Self.pasteboardType)
        let item = NSDraggingItem(pasteboardWriter: pasteboard)
        item.setDraggingFrame(cell.frame, contents: image)
        cancellationMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancelled = true }
            return event
        }
        let session: NSDraggingSession?
        if #available(macOS 27.0, *) {
            session = beginDraggingSession(items: [item], gesture: gesture, source: self)
        } else if let initialEvent {
            session = beginDraggingSession(with: [item], event: initialEvent, source: self)
        } else {
            session = nil
        }
        guard let session else { clearDrag(); return }
        session.draggingFormation = .none
        cell.isDragPlaceholder = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource as? DocumentTabStrip === self, let id = draggedID,
            sender.draggingPasteboard.string(forType: Self.pasteboardType) == id.uuidString,
            let index = index(at: convert(sender.draggingLocation, from: nil)) else { return [] }
        var order = tabs.map(\.id).filter { $0 != id }
        order.insert(id, at: min(index, order.count))
        if previewOrder != order { previewOrder = order; needsLayout = true; layoutSubtreeIfNeeded() }
        return .move
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        previewOrder = tabs.map(\.id)
        needsLayout = true
    }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        sender.draggingSource as? DocumentTabStrip === self && draggedID != nil
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard prepareForDragOperation(sender), let id = draggedID,
            let index = previewOrder?.firstIndex(of: id) else { return false }
        reorder(id, index)
        return true
    }
    func draggingSession(_ session: NSDraggingSession, endedAt point: NSPoint, operation: NSDragOperation) {
        let id = draggedID
        let movesOutside = !cancelled && operation.isEmpty && window.map { !$0.frame.contains(point) } == true
        session.animatesToStartingPositionsOnCancelOrFail = !movesOutside && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        clearDrag()
        if movesOutside, let id, tabs.contains(where: { $0.id == id }) { detach(id, point) }
    }
    private func clearDrag() {
        if let cancellationMonitor { NSEvent.removeMonitor(cancellationMonitor) }
        cancellationMonitor = nil
        if let id = draggedID { cells[id]?.isDragPlaceholder = false }
        draggedID = nil
        previewOrder = nil
        needsLayout = true
    }
}

/// One persistent, keyboard-focusable tab with native click/pan arbitration.
/// The close button is excluded from the tab gesture activation region.
@MainActor
final class DocumentTabCell: NSControl, NSGestureRecognizerDelegate {
    var tab: DocumentTabItem
    var isDragPlaceholder = false {
        didSet { needsDisplay = true; updateCloseVisibility() }
    }
    private weak var strip: DocumentTabStrip?
    private var mouseDownEvent: NSEvent?
    private lazy var dragGesture = NSPanGestureRecognizer(target: self, action: #selector(dragTab(_:)))
    private lazy var clickGesture = NSClickGestureRecognizer(target: self, action: #selector(selectTab))
    private let closeButton = NSButton()
    private var pointerIsInside = false
    private var hoverTrackingArea: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    init(tab: DocumentTabItem, strip: DocumentTabStrip) {
        self.tab = tab
        self.strip = strip
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        focusRingType = .exterior
        closeButton.image = ScholiumNativeToolbarPresentation.symbol(named: "xmark")
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.controlSize = .small
        closeButton.target = self
        closeButton.action = #selector(closeDocument)
        closeButton.toolTip = ScholiumL10n.string("Close Tab")
        closeButton.setAccessibilityLabel(ScholiumL10n.string("Close Tab"))
        closeButton.isHidden = true
        addSubview(closeButton)
        dragGesture.delegate = self
        clickGesture.delegate = self
        addGestureRecognizer(dragGesture)
        addGestureRecognizer(clickGesture)
    }
    required init?(coder: NSCoder) { fatalError("Code-only tab") }
    override func layout() {
        super.layout()
        let size = ScholiumDocumentTabStyle.closeSize
        closeButton.frame = NSRect(x: ScholiumDocumentTabStyle.closeInset,
            y: bounds.midY - size / 2, width: size, height: size)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTrackingArea = area
    }
    override func mouseEntered(with event: NSEvent) { pointerIsInside = true; updateCloseVisibility() }
    override func mouseExited(with event: NSEvent) { pointerIsInside = false; updateCloseVisibility() }
    override func becomeFirstResponder() -> Bool { closeButton.isHidden = false; return true }
    override func resignFirstResponder() -> Bool { updateCloseVisibility(); return true }
    private func updateCloseVisibility() {
        closeButton.isHidden = isDragPlaceholder || (!pointerIsInside && window?.firstResponder !== self && window?.firstResponder !== closeButton)
    }
    @objc private func closeDocument() { strip?.close(tab.id) }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        [NSAccessibilityCustomAction(name: ScholiumL10n.string("Close Tab"), target: self, selector: #selector(accessibilityClose))]
    }
    @objc private func accessibilityClose() -> Bool { closeDocument(); return true }

    override func draw(_ dirtyRect: NSRect) {
        guard !isDragPlaceholder else { return }
        Self.draw(tab: tab, selected: strip?.selectedID == tab.id, in: bounds)
    }
    static func draw(tab: DocumentTabItem, selected: Bool, in rect: NSRect) {
        if selected {
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: ScholiumDocumentTabStyle.borderInset, dy: ScholiumDocumentTabStyle.borderInset), xRadius: rect.height / 2, yRadius: rect.height / 2)
            ScholiumDocumentTabStyle.selectedFill.setFill(); shape.fill()
            ScholiumDocumentTabStyle.border.setStroke(); shape.lineWidth = ScholiumDocumentTabStyle.borderWidth; shape.stroke()
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let font = ScholiumDocumentTabStyle.font
        let height = font.ascender - font.descender
        let label = NSRect(x: rect.minX + ScholiumDocumentTabStyle.labelInset,
            y: rect.midY - height / 2, width: max(0, rect.width - 2 * ScholiumDocumentTabStyle.labelInset), height: height)
        (tab.title as NSString).draw(in: label, withAttributes: [.font: font, .foregroundColor: ScholiumDocumentTabStyle.foreground, .paragraphStyle: paragraph])
    }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: ScholiumDocumentTabStyle.borderInset, dy: ScholiumDocumentTabStyle.borderInset), xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }
    override var focusRingMaskBounds: NSRect { bounds }
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        if event.type == .leftMouseDown {
            let point = convert(event.locationInWindow, from: nil)
            guard closeButton.isHidden || !closeButton.frame.contains(point) else { return false }
            mouseDownEvent = event
        }
        return true
    }
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        gestureRecognizer === clickGesture && otherGestureRecognizer === dragGesture
    }
    @objc private func selectTab() { strip?.select(tab.id) }
    @objc private func dragTab(_ gesture: NSPanGestureRecognizer) {
        guard gesture.state == .began else { return }
        strip?.beginDrag(self, gesture: gesture, initialEvent: mouseDownEvent)
        mouseDownEvent = nil
    }
    override func menu(for event: NSEvent) -> NSMenu? { strip?.menu(for: tab) }
    override func accessibilityPerformPress() -> Bool { strip?.select(tab.id); return true }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 124:
            let direction = event.keyCode == 123 ? -1 : 1
            strip?.selectNeighbor(of: tab.id, offset: userInterfaceLayoutDirection == .rightToLeft ? -direction : direction)
        case 36, 49: strip?.select(tab.id)
        default: super.keyDown(with: event)
        }
    }
}

/// Direct layout avoids NSStackView's hidden-arranged-view collapse lifecycle.
@MainActor
final class DocumentTabContainerView: NSView {
    let strip: DocumentTabStrip
    let document: NSView
    var showsTabs = false { didSet { needsLayout = true } }
    override var isFlipped: Bool { true }
    init(strip: DocumentTabStrip, document: NSView) {
        self.strip = strip
        self.document = document
        super.init(frame: .zero)
        addSubview(strip)
        addSubview(document)
    }
    required init?(coder: NSCoder) { fatalError("Code-only tab container") }
    override func layout() {
        super.layout()
        let inset = ScholiumDocumentTabStyle.inset
        let headerHeight = showsTabs ? ScholiumDocumentTabStyle.height + 2 * inset : 0
        strip.isHidden = !showsTabs
        strip.frame = NSRect(x: inset, y: inset, width: max(0, bounds.width - 2 * inset), height: ScholiumDocumentTabStyle.height)
        document.frame = NSRect(x: 0, y: headerHeight, width: bounds.width, height: max(0, bounds.height - headerHeight))
    }
}
