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

    func configure(with row: SidebarTreeNodeRow) {
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
    var nativeSelectionPresentationDidChange: (() -> Void)?

    override var isSelected: Bool {
        didSet {
            guard oldValue != isSelected else { return }
            nativeSelectionPresentationDidChange?()
        }
    }

    override var isEmphasized: Bool {
        didSet {
            guard oldValue != isEmphasized else { return }
            nativeSelectionPresentationDidChange?()
        }
    }

    func configure(
        item: SidebarOutlineItem,
        isExpanded: Bool,
        nativeStrings: SidebarNativeStrings
    ) {
        let label = item.node.note?.title
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
    override func canDragRows(
        with rowIndexes: IndexSet,
        at mouseDownPoint: NSPoint
    ) -> Bool {
        // The hosted row retains SwiftUI context-menu and accessibility
        // surfaces. Let NSTableView keep drag recognition for the containing
        // native row; the data source's process-private pasteboard writer
        // remains the per-item authorization boundary.
        return rowIndexes.count == 1
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
