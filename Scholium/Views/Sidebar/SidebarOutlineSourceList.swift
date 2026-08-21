import AppKit
import ScholiumContracts
import SwiftUI

/// AppKit does not resolve SwiftUI's `LocalizedStringKey` values. Keep every
/// native menu, tooltip, and accessibility string behind one explicit locale
/// projection while leaving researcher-authored Folder and Note titles intact.
struct SidebarNativeStrings {
    let locale: Locale

    var libraryName: String { ScholiumL10n.string("Library", locale: locale) }

    var newNote: String { ScholiumL10n.string("New Note", locale: locale) }
    var newFolder: String { ScholiumL10n.string("New Folder", locale: locale) }

    func disclosureLabel(isExpanded: Bool, title: String) -> String {
        let format = isExpanded
            ? ScholiumL10n.string("Collapse %@", locale: locale)
            : ScholiumL10n.string("Expand %@", locale: locale)
        return String(format: format, locale: locale, title)
    }

    func folderAccessibilityValue(isEmpty: Bool, isExpanded: Bool) -> String {
        if isEmpty {
            return ScholiumL10n.string("Empty folder", locale: locale)
        }
        return ScholiumL10n.string(
            isExpanded ? "Expanded" : "Collapsed",
            locale: locale
        )
    }
}

/// AppKit owns the populated Library list: hierarchy, exact
/// scroll extent, and row reuse. SwiftUI remains responsible only for
/// Scholium's row content and location-valid actions inside the small set of
/// visible native cells.
struct SidebarOutlineSourceList: NSViewRepresentable {
    let roots: [TreeNode]
    let projectionRevision: UInt64
    let locale: Locale
    @Binding var expandedFolders: Set<String>
    /// A value snapshot makes disclosure changes observable to
    /// `updateNSView`; the Binding remains the sole write path.
    let expandedFolderIDs: Set<String>
    let rowHeight: CGFloat
    let selectedDocumentPath: String?
    let context: SidebarTreeContext
    let dropInventory: SidebarTreeDropInventory
    let revealRequest: DiscoveryLibraryRevealRequest?
    let disclosureScope: LibraryDisclosureScope?
    let focusRequestGeneration: UInt64
    let requestedFocusPath: String?
    let onConsumeRevealRequest: (DiscoveryLibraryRevealRequest) -> Void
    let onFocusRequestHandled: () -> Void
    let onSelect: (WindowDocumentLocation) -> Void
    let onMoveNoteDrop: (SidebarNoteDragItem, String?) -> Void
    let onMoveFolderDrop: (SidebarFolderDragItem, String?) -> Void

    var nativeStrings: SidebarNativeStrings {
        SidebarNativeStrings(locale: locale)
    }

    var accessibilityLocationName: String {
        nativeStrings.libraryName
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(configuration: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = SidebarOutlineScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false

        let outlineView = SidebarOutlineView()
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.headerView = nil
        outlineView.backgroundColor = .clear
        outlineView.style = .sourceList
        outlineView.floatsGroupRows = false
        outlineView.usesAutomaticRowHeights = false
        outlineView.rowSizeStyle = .custom
        outlineView.rowHeight = rowHeight
        outlineView.intercellSpacing = .zero
        outlineView.indentationPerLevel = 0
        outlineView.indentationMarkerFollowsCell = false
        outlineView.selectionHighlightStyle = .none
        outlineView.draggingDestinationFeedbackStyle = .sourceList
        outlineView.allowsEmptySelection = true
        outlineView.allowsMultipleSelection = false
        outlineView.allowsColumnSelection = false
        outlineView.allowsColumnReordering = false
        outlineView.allowsColumnResizing = false
        outlineView.verticalMotionCanBeginDrag = true
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outlineView.focusRingType = .none
        outlineView.setAccessibilityIdentifier("scholium.noteList")
        outlineView.setAccessibilityLabel(accessibilityLocationName)
        outlineView.registerForDraggedTypes(sidebarNativeDraggingTypes)
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        outlineView.setDraggingSourceOperationMask([], forLocal: false)

        let column = NSTableColumn(identifier: Coordinator.columnIdentifier)
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        scrollView.documentView = outlineView
        context.coordinator.attach(outlineView: outlineView, scrollView: scrollView)
        context.coordinator.apply(configuration: self)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.apply(configuration: self)
    }

    static func dismantleNSView(
        _ scrollView: NSScrollView,
        coordinator: Coordinator
    ) {
        coordinator.detach(from: scrollView)
    }
}
