import AppKit

func sidebarControlSize(
    for rowSizeStyle: NSTableView.RowSizeStyle
) -> NSControl.ControlSize {
    switch rowSizeStyle {
    case .small:
        .small
    case .large:
        .large
    case .default, .custom, .medium:
        .regular
    @unknown default:
        .regular
    }
}

struct SidebarSourceListRowPresentation: Equatable {
    let textPointSize: CGFloat

    init(effectiveRowSizeStyle: NSTableView.RowSizeStyle) {
        textPointSize = NSFont.systemFontSize(
            for: sidebarControlSize(for: effectiveRowSizeStyle)
        )
    }
}

func sidebarOutlineStructure(
    from roots: [TreeNode]
) -> [SidebarOutlineStructureEntry] {
    var result: [SidebarOutlineStructureEntry] = []
    result.reserveCapacity(roots.count)

    func append(_ node: TreeNode) {
        result.append(
            SidebarOutlineStructureEntry(
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

/// The outline supplies native row proxies. Their cell's real text-field
/// outlet supplies the reachable item name, identity and actions.
@MainActor
final class SidebarOutlineLabel: NSTextField {
    var folderState: String?
    var actionProvider: (() -> [NSAccessibilityCustomAction])?

    override func accessibilityValue() -> String? {
        if let folderState { return folderState }
        return super.accessibilityValue()
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        (super.accessibilityCustomActions() ?? []) + (actionProvider?() ?? [])
    }
}

@MainActor
final class SidebarOutlineCell: NSTableCellView {
    let titleLabel = SidebarOutlineLabel(labelWithString: "")
    private let itemImageView = NSImageView()
    private(set) var representationGeneration: UInt64 = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installContent()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installContent()
    }

    private func installContent() {
        textField = titleLabel
        imageView = itemImageView
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setAccessibilityElement(true)
        titleLabel.setAccessibilityRole(.staticText)
        itemImageView.translatesAutoresizingMaskIntoConstraints = false
        itemImageView.imageScaling = .scaleNone
        itemImageView.setAccessibilityElement(false)
        addSubview(itemImageView)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            itemImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            itemImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            itemImageView.widthAnchor.constraint(equalToConstant: ScholiumMetrics.Library.leadingSlotWidth),
            itemImageView.heightAnchor.constraint(equalToConstant: ScholiumMetrics.Library.leadingSlotWidth),
            titleLabel.leadingAnchor.constraint(
                equalTo: itemImageView.trailingAnchor, constant: ScholiumGrid.Spacing.inlineControlGap
            ),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -ScholiumMetrics.Library.rowHorizontalInset
            ),
        ])
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateForeground() }
    }

    func configure(
        item: SidebarOutlineItem,
        isExpanded: Bool,
        nativeStrings: SidebarNativeStrings,
        presentation: SidebarSourceListRowPresentation
    ) {
        let label = item.node.note?.title ?? item.node.note?.displayName ?? item.node.name
        if (objectValue as? SidebarOutlineItem) !== item { representationGeneration &+= 1 }
        objectValue = item
        titleLabel.stringValue = label
        titleLabel.font = .systemFont(ofSize: presentation.textPointSize)
        titleLabel.setAccessibilityLabel(label)
        titleLabel.setAccessibilityIdentifier(
            item.node.isFolder ? "scholium.folderRow.\(item.id)" : "scholium.noteRow.\(item.id)"
        )
        titleLabel.folderState = item.node.isFolder
            ? nativeStrings.folderAccessibilityValue(isEmpty: item.children.isEmpty, isExpanded: isExpanded)
            : nil
        titleLabel.toolTip = label
        toolTip = label
        itemImageView.image = NSImage(
            systemSymbolName: item.node.isFolder ? ScholiumSidebarItem.folder.symbol : ScholiumSidebarItem.note.symbol,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: presentation.textPointSize, weight: .regular))
        updateForeground()
    }

    private func updateForeground() {
        titleLabel.textColor = backgroundStyle == .emphasized
            ? .alternateSelectedControlTextColor : ScholiumColorRole.primaryText.nsColor
        itemImageView.contentTintColor = backgroundStyle == .emphasized
            ? .alternateSelectedControlTextColor : ScholiumColorRole.secondaryText.nsColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representationGeneration &+= 1
        titleLabel.actionProvider = nil
        titleLabel.folderState = nil
        titleLabel.setAccessibilityIdentifier(nil)
        titleLabel.setAccessibilityLabel(nil)
        titleLabel.toolTip = nil
        toolTip = nil
        objectValue = nil
    }

    /// The native outline owns click/drag recognition and context selection;
    /// the text field provides content semantics without becoming a responder.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let nativeHit = super.hitTest(point)
        switch NSApp.currentEvent?.type {
        case .leftMouseDown?, .rightMouseDown?: return nativeHit == nil ? nil : self
        default: return nativeHit
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let outlineView = enclosingOutlineView {
            outlineView.mouseDown(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        (enclosingOutlineView as? SidebarOutlineView)?.contextMenu(
            forRow: enclosingOutlineView?.row(for: self) ?? -1
        )
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
final class SidebarOutlineView: NSOutlineView {
    var chatAccessibilityAction: (() -> NSAccessibilityCustomAction?)?
    var selectionAccessibilityActions: (() -> [NSAccessibilityCustomAction])?
    var selectionMenuProvider: ((Int) -> NSMenu?)?
    var lifecycleDidBecomeUnavailable: (() -> Void)?
    var lifecycleDidBecomeAvailable: (() -> Void)?
    var trashSelection: (() -> Bool)?
    var openSelection: (() -> Bool)?
    var dragSelectionIsValid: ((IndexSet) -> Bool)?
    var primaryClickHandler: ((Int, NSEvent.ModifierFlags) -> Bool)?
    private(set) var isHandlingPrimaryMouseDown = false
    private var primaryMouseDownModifiers: NSEvent.ModifierFlags?

    override func mouseDown(with event: NSEvent) {
        isHandlingPrimaryMouseDown = true
        primaryMouseDownModifiers = event.modifierFlags
        defer {
            isHandlingPrimaryMouseDown = false
            primaryMouseDownModifiers = nil
        }
        super.mouseDown(with: event)
    }

    @objc func activateClickedRow(_ sender: Any?) {
        guard let modifiers = primaryMouseDownModifiers else { return }
        // NSTableView sends its action only after native click recognition.
        // Disclosure and drag retain their native behavior without activation.
        _ = primaryClickHandler?(clickedRow, modifiers)
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        let native = super.accessibilityCustomActions() ?? []
        let selectionActions = selectionAccessibilityActions?() ?? []
        let chatActions = chatAccessibilityAction?().map { [$0] } ?? []
        return native + selectionActions + chatActions
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        return contextMenu(forRow: row)
    }

    func contextMenu(forRow row: Int) -> NSMenu? {
        guard !isHiddenOrHasHiddenAncestor else { return nil }
        return selectionMenuProvider?(row)
    }

    @discardableResult
    func requestKeyboardFocus() -> Bool {
        guard let window, !isHiddenOrHasHiddenAncestor else { return false }
        return window.makeFirstResponder(self)
    }

    override func viewDidHide() {
        super.viewDidHide()
        lifecycleDidBecomeUnavailable?()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        lifecycleDidBecomeAvailable?()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow { lifecycleDidBecomeUnavailable?() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { lifecycleDidBecomeAvailable?() }
    }

    override func showContextMenuForSelection(_ sender: Any?) {
        guard selectedRow >= 0,
            let menu = contextMenu(forRow: selectedRow)
        else { return }
        // Keyboard and accessibility ShowMenu target the selected row, rather
        // than the midpoint of an outline containing unrelated rows.
        let rect = rect(ofRow: selectedRow)
        menu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.maxY), in: self)
    }

    override func insertNewline(_ sender: Any?) {
        if openSelection?() != true { super.insertNewline(sender) }
    }

    override func deleteBackward(_ sender: Any?) {
        if trashSelection?() != true { super.deleteBackward(sender) }
    }

    override func deleteForward(_ sender: Any?) {
        if trashSelection?() != true { super.deleteForward(sender) }
    }

    override func canDragRows(
        with rowIndexes: IndexSet,
        at mouseDownPoint: NSPoint
    ) -> Bool {
        // NSTableView owns recognition; the data source's process-private
        // pasteboard writer remains the per-item authorization boundary.
        return dragSelectionIsValid?(rowIndexes) ?? false
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
