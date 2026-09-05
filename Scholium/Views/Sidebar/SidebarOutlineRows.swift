import AppKit
import SwiftUI

enum SidebarSourceListInputModality: Equatable {
    case pointer
    case keyboard
}

/// Keeps selection and keyboard focus as separate presentation facts for the
/// Sidebar's native source lists. AppKit remains the selection and responder
/// owner; this adapter only prevents a pointer-created first responder from
/// being painted as keyboard focus.
@MainActor
final class SidebarSourceListSelectionPresentation {
    private(set) var inputModality: SidebarSourceListInputModality = .pointer
    private var lastAppliedEmphasis: Bool?

    func recordPointerInteraction() {
        inputModality = .pointer
    }

    func recordKeyboardInteraction() {
        inputModality = .keyboard
    }

    func recordResponderEvent(_ eventType: NSEvent.EventType?) {
        switch eventType {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            recordPointerInteraction()
        case .keyDown:
            recordKeyboardInteraction()
        default:
            break
        }
    }

    func selectionIsEmphasized(
        isKeyWindow: Bool,
        isFirstResponder: Bool
    ) -> Bool {
        inputModality == .keyboard && isKeyWindow && isFirstResponder
    }

    func selectionIsEmphasized(in tableView: NSTableView) -> Bool {
        guard let window = tableView.window else { return false }
        return selectionIsEmphasized(
            isKeyWindow: window.isKeyWindow,
            isFirstResponder: window.firstResponder === tableView
        )
    }

    /// Returns true only when hosted row content must refresh its foreground.
    @discardableResult
    func synchronize(in tableView: NSTableView) -> Bool {
        let isEmphasized = selectionIsEmphasized(in: tableView)
        tableView.enumerateAvailableRowViews { rowView, _ in
            guard rowView.isSelected,
                  rowView.isEmphasized != isEmphasized else { return }
            rowView.isEmphasized = isEmphasized
        }
        let changed = lastAppliedEmphasis != isEmphasized
        lastAppliedEmphasis = isEmphasized
        return changed
    }
}

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

/// AppKit continues to set row emphasis as responder/window state changes.
/// The only custom rule is to suppress that emphasis for pointer activation.
@MainActor
class SidebarSourceListRowView: NSTableRowView {
    var allowsKeyboardEmphasis: (() -> Bool)?
    var emphasisDidChange: (() -> Void)?

    override var isEmphasized: Bool {
        get { super.isEmphasized }
        set {
            let emphasized = newValue && (allowsKeyboardEmphasis?() ?? false)
            guard super.isEmphasized != emphasized else { return }
            super.isEmphasized = emphasized
            emphasisDidChange?()
        }
    }
}

@MainActor
final class SidebarOutlineRowView: SidebarSourceListRowView {
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
    private let selectionPresentation = SidebarSourceListSelectionPresentation()
    var selectionPresentationDidChange: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        focusRingType = .none
    }

    var usesEmphasizedSelectionForeground: Bool {
        selectionPresentation.selectionIsEmphasized(in: self)
    }

    func configureSelectionPresentation(for row: SidebarSourceListRowView) {
        row.allowsKeyboardEmphasis = { [weak self] in
            self?.selectionPresentation.inputModality == .keyboard
        }
        row.emphasisDidChange = { [weak self] in
            self?.selectionPresentationDidChange?()
        }
    }

    func requestKeyboardFocus() {
        selectionPresentation.recordKeyboardInteraction()
        window?.makeFirstResponder(self)
        synchronizeSelectionPresentation()
    }

    override func mouseDown(with event: NSEvent) {
        selectionPresentation.recordPointerInteraction()
        super.mouseDown(with: event)
        synchronizeSelectionPresentation()
    }

    override func keyDown(with event: NSEvent) {
        selectionPresentation.recordKeyboardInteraction()
        super.keyDown(with: event)
        synchronizeSelectionPresentation()
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        guard becameFirstResponder else { return false }
        selectionPresentation.recordResponderEvent(NSApp.currentEvent?.type)
        synchronizeSelectionPresentation()
        return true
    }

    override func resignFirstResponder() -> Bool {
        let resignedFirstResponder = super.resignFirstResponder()
        if resignedFirstResponder {
            enumerateAvailableRowViews { row, _ in row.isEmphasized = false }
            selectionPresentationDidChange?()
        }
        return resignedFirstResponder
    }

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

    private func synchronizeSelectionPresentation() {
        if selectionPresentation.synchronize(in: self) {
            selectionPresentationDidChange?()
        }
    }
}

@MainActor
final class SidebarOutlineScrollView: NSScrollView {
    var rootMenuProvider: (() -> NSMenu?)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        focusRingType = .none
    }

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
