import AppKit
import SwiftUI

func sidebarOutlineRowHeight(usesAccessibilitySize: Bool) -> CGFloat {
    usesAccessibilitySize
        ? ScholiumMetrics.Library.accessibilityHierarchyRowHeight
        : ScholiumMetrics.Library.hierarchyRowHeight
}

func sidebarOutlineDocumentIsSelected(
    notePath: String?,
    selectedDocumentPath: String?
) -> Bool {
    guard let notePath, let selectedDocumentPath else { return false }
    return notePath == selectedDocumentPath
}

func sidebarOutlineStructure(
    from roots: [TreeNode]
) -> [SidebarOutlineStructureEntry] {
    var result: [SidebarOutlineStructureEntry] = []
    result.reserveCapacity(roots.count)

    func append(_ node: TreeNode) {
        result.append(SidebarOutlineStructureEntry(
            id: node.id,
            childIDs: node.children.map(\.id),
            isFolder: node.isFolder
        ))
        node.children.forEach(append)
    }
    roots.forEach(append)
    return result
}

struct SidebarOutlineStructureEntry: Equatable {
    let id: String
    let childIDs: [String]
    let isFolder: Bool
}

func sidebarExpansionSynchronizationIsRequired(
    previouslyApplied: Set<String>?,
    desired: Set<String>,
    structureChanged: Bool
) -> Bool {
    structureChanged || previouslyApplied != desired
}

@MainActor
final class SidebarOutlineItem: NSObject {
    var node: TreeNode
    weak var parent: SidebarOutlineItem?
    var children: [SidebarOutlineItem] = []

    var id: String { node.id }
    var isExpandable: Bool { node.isFolder && !children.isEmpty }

    init(node: TreeNode) {
        self.node = node
    }
}

@MainActor
final class SidebarOutlineHostingCell: NSTableCellView {
    private var hostingView: SidebarOutlineRowHostingView?
    private var disclosureButton: NSButton?
    private var disclosureDepth = 0
    private var onDisclosure: (() -> Void)?
    private var pointerHovered = false

    func configure(
        with row: SidebarTreeNodeRow,
        isHovered: Bool,
        disclosureLabel: String?,
        disclosureIsExpanded: Bool,
        disclosureDepth: Int,
        onDisclosure: (() -> Void)?
    ) {
        self.disclosureDepth = disclosureDepth
        self.onDisclosure = onDisclosure
        pointerHovered = isHovered
        if let hostingView {
            hostingView.rootView = row
        } else {
            let hostingView = SidebarOutlineRowHostingView(rootView: row)
            hostingView.sizingOptions = []
            hostingView.frame = bounds
            hostingView.autoresizingMask = [.width, .height]
            addSubview(hostingView)
            self.hostingView = hostingView
        }
        let button = disclosureButton ?? makeDisclosureButton()
        button.isHidden = disclosureLabel == nil
        button.state = disclosureIsExpanded ? .on : .off
        button.toolTip = disclosureLabel
        button.setAccessibilityLabel(disclosureLabel)
        positionDisclosureButton()
    }

    func setHovered(_ hovering: Bool) {
        guard pointerHovered != hovering else { return }
        pointerHovered = hovering
    }

    private func makeDisclosureButton() -> NSButton {
        let button = NSButton()
        button.bezelStyle = .disclosure
        button.setButtonType(.pushOnPushOff)
        button.controlSize = .small
        button.title = ""
        button.target = self
        button.action = #selector(activateDisclosure)
        addSubview(button, positioned: .above, relativeTo: hostingView)
        disclosureButton = button
        positionDisclosureButton()
        return button
    }

    override func layout() {
        super.layout()
        hostingView?.frame = bounds
        positionDisclosureButton()
    }

    /// Populated rows are native outline interactions. SwiftUI renders the
    /// label and menus, but a primary-button press outside the explicit native
    /// accessories belongs to NSOutlineView so AppKit can distinguish a click
    /// from the start of a drag without a second gesture recognizer.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let nativeHit = super.hitTest(point)
        if nativeHit === disclosureButton {
            return nativeHit
        }
        guard NSApp.currentEvent?.type == .leftMouseDown else {
            return nativeHit
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        if let outlineView = enclosingOutlineView {
            outlineView.mouseDown(with: event)
            return
        }
        super.mouseDown(with: event)
    }

    private func positionDisclosureButton() {
        guard let button = disclosureButton else { return }
        let side = ScholiumMetrics.Library.leadingSlotWidth
        button.frame = NSRect(
            x: sidebarLibraryRowLeadingInset(depth: disclosureDepth),
            y: max(0, (bounds.height - side) / 2),
            width: side,
            height: side
        )
    }

    @objc private func activateDisclosure() {
        onDisclosure?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        pointerHovered = false
    }

    private var enclosingOutlineView: NSOutlineView? {
        var candidate: NSView? = superview
        while let view = candidate {
            if let outlineView = view as? NSOutlineView { return outlineView }
            candidate = view.superview
        }
        return nil
    }
}

@MainActor
private final class SidebarOutlineRowHostingView: NSHostingView<SidebarTreeNodeRow> {
    override func scrollWheel(with event: NSEvent) {
        guard let enclosingScrollView else {
            super.scrollWheel(with: event)
            return
        }
        enclosingScrollView.scrollWheel(with: event)
    }

}

@MainActor
final class SidebarOutlineRowView: NSTableRowView {
    private var isSelectedDocument = false
    private var isHovering = false
    private var isNativeFocused = false

    func configure(
        item: SidebarOutlineItem,
        isExpanded: Bool,
        isHovered: Bool,
        isNativeFocused: Bool,
        selectedDocumentPath: String?,
        nativeStrings: SidebarNativeStrings
    ) {
        isHovering = isHovered
        self.isNativeFocused = isNativeFocused
        isSelectedDocument = sidebarOutlineDocumentIsSelected(
            notePath: item.node.note?.relativePath,
            selectedDocumentPath: selectedDocumentPath
        )
        needsDisplay = true
        let label = item.node.note?.title
            ?? item.node.note?.displayName
            ?? item.node.name
        setAccessibilityLabel(label)
        setAccessibilityIdentifier(
            item.node.isFolder
                ? "scholium.folderRow.\(item.id)"
                : "scholium.noteRow.\(item.id)"
        )
        setAccessibilitySelected(isSelectedDocument || isNativeFocused)
        if item.node.isFolder {
            setAccessibilityValue(
                nativeStrings.folderAccessibilityValue(
                    isEmpty: item.node.children.isEmpty,
                    isExpanded: isExpanded
                )
            )
        } else {
            setAccessibilityValue(nil)
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        if isSelectedDocument {
            let opacity: CGFloat = window?.isKeyWindow == false ? 0.56 : 0.82
            NSColor(ScholiumColorRole.raisedSurfaceBackground.color)
                .withAlphaComponent(opacity)
                .setFill()
            bounds.fill()
        } else if isNativeFocused {
            NSColor(ScholiumColorRole.raisedSurfaceBackground.color)
                .withAlphaComponent(0.42)
                .setFill()
            bounds.fill()
        } else if isHovering {
            ScholiumContentInteractionSurface.nsColor(
                isHovering: true,
                isFocused: false,
                increasedContrast:
                    NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            )
                .setFill()
            bounds.fill()
        }
    }

    func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        needsDisplay = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovering = false
        isSelectedDocument = false
        isNativeFocused = false
        needsDisplay = true
    }

    override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {
        NSColor(ScholiumColorRole.raisedSurfaceBackground.color)
            .withAlphaComponent(0.48)
            .setFill()
        bounds.fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isSelectedDocument {
            NSColor(ScholiumColorRole.accent.color).setFill()
            NSRect(
                x: bounds.minX,
                y: bounds.minY,
                width: ScholiumMetrics.Library.selectionBoundaryWidth,
                height: bounds.height
            ).fill()
        }
    }
}

@MainActor
final class SidebarOutlineView: NSOutlineView {
    private var hoverTrackingArea: NSTrackingArea?
    private var hoveredItemID: String?
    private weak var hoveredRowView: SidebarOutlineRowView?
    private weak var hoveredCell: SidebarOutlineHostingCell?
    private var hoverReconciliationIsScheduled = false
    var activationHandler: (() -> Void)?
    var focusPresentationHandler: (() -> Void)?

    func isHovering(_ item: SidebarOutlineItem) -> Bool {
        hoveredItemID == item.id
    }

    func scheduleHoverReconciliation() {
        guard !hoverReconciliationIsScheduled else { return }
        hoverReconciliationIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hoverReconciliationIsScheduled = false
            self.reconcileHoverWithCurrentPointer()
        }
    }

    func invalidateHoverForReload() {
        setHoveredItem(nil, rowView: nil, cell: nil)
    }

    override func canDragRows(
        with rowIndexes: IndexSet,
        at mouseDownPoint: NSPoint
    ) -> Bool {
        // The hosted row contains SwiftUI buttons for accessibility and menu
        // parity. NSTableView otherwise treats that hit as a trackable control
        // and declines to start its own drag. The data source's process-private
        // pasteboard writer remains the per-item authorization boundary.
        return rowIndexes.count == 1
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .mouseMoved,
                .activeInKeyWindow,
                .inVisibleRect,
            ],
            owner: self
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        reconcileHover(atWindowPoint: event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        reconcileHover(atWindowPoint: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHoveredItem(nil, rowView: nil, cell: nil)
    }

    private func reconcileHoverWithCurrentPointer() {
        guard let window else {
            setHoveredItem(nil, rowView: nil, cell: nil)
            return
        }
        reconcileHover(atWindowPoint: window.mouseLocationOutsideOfEventStream)
    }

    private func reconcileHover(atWindowPoint windowPoint: NSPoint) {
        guard window?.isKeyWindow == true else {
            setHoveredItem(nil, rowView: nil, cell: nil)
            return
        }
        let point = convert(windowPoint, from: nil)
        guard visibleRect.contains(point) else {
            setHoveredItem(nil, rowView: nil, cell: nil)
            return
        }

        var candidate = hitTest(point)
        while let view = candidate, view !== self {
            if let rowView = view as? SidebarOutlineRowView {
                let row = row(for: rowView)
                let item = row >= 0
                    ? item(atRow: row) as? SidebarOutlineItem
                    : nil
                let cell = row >= 0
                    ? self.view(
                        atColumn: 0,
                        row: row,
                        makeIfNecessary: false
                    ) as? SidebarOutlineHostingCell
                    : nil
                setHoveredItem(item, rowView: rowView, cell: cell)
                return
            }
            candidate = view.superview
        }
        setHoveredItem(nil, rowView: nil, cell: nil)
    }

    private func setHoveredItem(
        _ item: SidebarOutlineItem?,
        rowView: SidebarOutlineRowView?,
        cell: SidebarOutlineHostingCell?
    ) {
        let itemID = item?.id
        guard hoveredItemID != itemID
                || hoveredRowView !== rowView
                || hoveredCell !== cell else { return }
        hoveredRowView?.setHovering(false)
        hoveredCell?.setHovered(false)
        hoveredItemID = itemID
        hoveredRowView = rowView
        hoveredCell = cell
        rowView?.setHovering(item != nil)
        cell?.setHovered(item != nil)
    }

    override func keyDown(with event: NSEvent) {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        if event.modifierFlags.intersection(disallowedModifiers).isEmpty,
           event.keyCode == 36 || event.keyCode == 49 {
            activationHandler?()
            return
        }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusPresentationHandler?() }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            DispatchQueue.main.async { [weak self] in
                self?.focusPresentationHandler?()
            }
        }
        return accepted
    }

    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        guard row >= 0,
              let item = item(atRow: row) as? SidebarOutlineItem,
              item.isExpandable else {
            return super.frameOfOutlineCell(atRow: row)
        }
        return .zero
    }
}

@MainActor
final class SidebarOutlineScrollView: NSScrollView {
    var rootMenuProvider: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let outlineView = documentView as? NSOutlineView else {
            return super.menu(for: event)
        }
        let point = outlineView.convert(event.locationInWindow, from: nil)
        guard outlineView.row(at: point) < 0 else {
            return super.menu(for: event)
        }
        return rootMenuProvider?() ?? super.menu(for: event)
    }
}
