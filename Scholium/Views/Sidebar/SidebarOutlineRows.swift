import AppKit
import SwiftUI

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

@MainActor
final class SidebarOutlineHostingCell: NSTableCellView {
    private var hostingView: NSHostingView<SidebarTreeNodeRow>?

    // AppKit owns selection emphasis. Only project its cell background into
    // SwiftUI text; never write selection or responder state back to the row.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            guard oldValue != backgroundStyle, var row = hostingView?.rootView else { return }
            row.usesEmphasizedSelectionForeground = backgroundStyle == .emphasized
            hostingView?.rootView = row
        }
    }

    func configure(with row: SidebarTreeNodeRow) {
        var row = row
        row.usesEmphasizedSelectionForeground = backgroundStyle == .emphasized
        if let hostingView {
            hostingView.rootView = row
        } else {
            let hostingView = NSHostingView(rootView: row)
            hostingView.sizingOptions = []
            hostingView.frame = bounds
            hostingView.autoresizingMask = [.width, .height]
            addSubview(hostingView)
            self.hostingView = hostingView
        }
    }

    override func layout() {
        super.layout()
        hostingView?.frame = bounds
    }

    /// Populated rows are native outline interactions. SwiftUI renders the
    /// label and menus, but a primary-button press outside the explicit native
    /// accessories belongs to NSOutlineView so AppKit can distinguish a click
    /// from the start of a drag without a second gesture recognizer.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let nativeHit = super.hitTest(point)
        if NSApp.currentEvent?.type == .rightMouseDown,
            let outlineView = enclosingOutlineView as? SidebarOutlineView,
            outlineView.selectedRowIndexes.count > 1,
            outlineView.selectedRowIndexes.contains(outlineView.row(for: self))
        {
            return self
        }
        guard NSApp.currentEvent?.type == .leftMouseDown else { return nativeHit }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        if let outlineView = enclosingOutlineView {
            outlineView.mouseDown(with: event)
            return
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if let outlineView = enclosingOutlineView as? SidebarOutlineView,
            let menu = outlineView.selectionMenuProvider?(outlineView.row(for: self))
        {
            return menu
        }
        return super.menu(for: event)
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
final class SidebarOutlineRowView: NSTableRowView {
    func configure(
        item: SidebarOutlineItem,
        isExpanded: Bool,
        nativeStrings: SidebarNativeStrings
    ) {
        let label =
            item.node.note?.title
            ?? item.node.note?.displayName
            ?? item.node.name
        setAccessibilityLabel(label)
        setAccessibilityIdentifier(
            item.node.isFolder
                ? "scholium.folderRow.\(item.id)"
                : "scholium.noteRow.\(item.id)"
        )
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
}

@MainActor
final class SidebarOutlineView: NSOutlineView {
    var chatAccessibilityAction: (() -> NSAccessibilityCustomAction?)?
    var selectionAccessibilityActions: (() -> [NSAccessibilityCustomAction])?
    var selectionMenuProvider: ((Int) -> NSMenu?)?
    var trashSelection: (() -> Bool)?
    var openSelection: (() -> Bool)?
    var dragSelectionIsValid: ((IndexSet) -> Bool)?

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        let native = super.accessibilityCustomActions() ?? []
        let selectionActions = selectionAccessibilityActions?() ?? []
        let chatActions = chatAccessibilityAction?().map { [$0] } ?? []
        return native + selectionActions + chatActions
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        return selectionMenuProvider?(row) ?? super.menu(for: event)
    }

    func requestKeyboardFocus() {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return }
        window?.makeFirstResponder(self)
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
        // The hosted row retains SwiftUI context-menu and accessibility
        // surfaces. Let NSTableView keep drag recognition for the containing
        // native row; the data source's process-private pasteboard writer
        // remains the per-item authorization boundary.
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
