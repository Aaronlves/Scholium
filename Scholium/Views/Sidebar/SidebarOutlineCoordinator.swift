import AppKit
import ScholiumContracts
import SwiftUI

extension SidebarOutlineSourceList {
    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        static let columnIdentifier = NSUserInterfaceItemIdentifier(
            "ScholiumSidebarOutlineColumn"
        )
        private static let cellIdentifier = NSUserInterfaceItemIdentifier(
            "ScholiumSidebarOutlineCell"
        )
        private static let rowIdentifier = NSUserInterfaceItemIdentifier(
            "ScholiumSidebarOutlineRow"
        )

        private var configuration: SidebarOutlineSourceList
        private weak var outlineView: NSOutlineView?
        private weak var scrollView: NSScrollView?
        private var roots: [SidebarOutlineItem] = []
        private var itemsByID: [String: SidebarOutlineItem] = [:]
        private var noteItemsByPath: [String: SidebarOutlineItem] = [:]
        private var structure: [SidebarOutlineStructureEntry] = []
        private var lastProjectionRevision: UInt64?
        private var lastSynchronizedExpandedFolderIDs: Set<String>?
        private var isSynchronizingExpansion = false
        private var isSynchronizingSelection = false
        private var hasSynchronizedActiveDocument = false
        private var lastActiveDocumentPath: String?
        private var lastRevealGeneration: UInt64?
        private var lastFocusRequestGeneration: UInt64
        private var lastRequestedFocusPath: String?

        init(configuration: SidebarOutlineSourceList) {
            self.configuration = configuration
            lastFocusRequestGeneration = configuration.focusRequestGeneration
        }

        func attach(outlineView: NSOutlineView, scrollView: NSScrollView) {
            self.outlineView = outlineView
            self.scrollView = scrollView
            outlineView.target = self
            outlineView.action = #selector(activateOutlineClick(_:))
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollBoundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            (scrollView as? SidebarOutlineScrollView)?.rootMenuProvider = { [weak self] in
                self?.makeRootMenu()
            }
            if let outlineView = outlineView as? SidebarOutlineView {
                outlineView.activationHandler = { [weak self] in
                    self?.activateNativeSelection()
                }
                outlineView.focusPresentationHandler = { [weak self, weak outlineView] in
                    guard let self, let outlineView else { return }
                    self.refreshAvailableRows(in: outlineView)
                }
            }
        }

        func detach(from scrollView: NSScrollView) {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            (scrollView as? SidebarOutlineScrollView)?.rootMenuProvider = nil
            if outlineView?.target as AnyObject? === self {
                outlineView?.target = nil
                outlineView?.action = nil
            }
            if let outlineView = outlineView as? SidebarOutlineView {
                outlineView.activationHandler = nil
                outlineView.focusPresentationHandler = nil
            }
        }

        func apply(configuration: SidebarOutlineSourceList) {
            self.configuration = configuration
            guard let outlineView else { return }
            outlineView.setAccessibilityLabel(
                configuration.accessibilityLocationName
            )

            let previousNativeSelectionID = selectedItemID(in: outlineView)
            let activeDocumentChanged = !hasSynchronizedActiveDocument
                || lastActiveDocumentPath != configuration.selectedDocumentPath
            var structureChanged = false
            if outlineView.rowHeight != configuration.rowHeight {
                outlineView.rowHeight = configuration.rowHeight
                outlineView.noteHeightOfRows(withIndexesChanged: IndexSet(
                    integersIn: 0..<outlineView.numberOfRows
                ))
            }

            if lastProjectionRevision != configuration.projectionRevision {
                let newStructure = sidebarOutlineStructure(from: configuration.roots)
                reconcile(configuration.roots)
                if structure != newStructure {
                    structure = newStructure
                    (outlineView as? SidebarOutlineView)?.invalidateHoverForReload()
                    outlineView.reloadData()
                    structureChanged = true
                }
                lastProjectionRevision = configuration.projectionRevision
            }

            if sidebarExpansionSynchronizationIsRequired(
                previouslyApplied: lastSynchronizedExpandedFolderIDs,
                desired: configuration.expandedFolderIDs,
                structureChanged: structureChanged
            ) {
                synchronizeExpansion(in: outlineView)
                lastSynchronizedExpandedFolderIDs = configuration.expandedFolderIDs
            }
            synchronizeSelection(
                in: outlineView,
                previousNativeSelectionID: previousNativeSelectionID,
                activeDocumentChanged: activeDocumentChanged
            )
            refreshAvailableRows(in: outlineView)
            handleRevealRequest(in: outlineView)
            handleFocusRequest(in: outlineView)
            handleSourceListFocus(in: outlineView)
            (outlineView as? SidebarOutlineView)?.scheduleHoverReconciliation()
        }

        private func reconcile(_ nodes: [TreeNode]) {
            var retainedIDs = Set<String>()

            func reconciledItem(
                for node: TreeNode,
                parent: SidebarOutlineItem?
            ) -> SidebarOutlineItem {
                retainedIDs.insert(node.id)
                let outlineItem = itemsByID[node.id] ?? SidebarOutlineItem(node: node)
                outlineItem.node = node
                outlineItem.parent = parent
                outlineItem.children = node.children.map {
                    reconciledItem(for: $0, parent: outlineItem)
                }
                itemsByID[node.id] = outlineItem
                return outlineItem
            }

            roots = nodes.map { reconciledItem(for: $0, parent: nil) }
            itemsByID = itemsByID.filter { retainedIDs.contains($0.key) }
            noteItemsByPath = Dictionary(uniqueKeysWithValues: itemsByID.values.compactMap {
                guard let path = $0.node.note?.relativePath else { return nil }
                return (path, $0)
            })
        }

        private func selectedItemID(in outlineView: NSOutlineView) -> String? {
            guard outlineView.selectedRow >= 0 else { return nil }
            return (outlineView.item(atRow: outlineView.selectedRow) as? SidebarOutlineItem)?.id
        }

        private func synchronizeSelection(
            in outlineView: NSOutlineView,
            previousNativeSelectionID: String?,
            activeDocumentChanged: Bool
        ) {
            defer {
                hasSynchronizedActiveDocument = true
                lastActiveDocumentPath = configuration.selectedDocumentPath
            }

            let desiredItem: SidebarOutlineItem?
            if activeDocumentChanged {
                desiredItem = configuration.selectedDocumentPath.flatMap {
                    noteItemsByPath[$0]
                }
            } else if let previousNativeSelectionID,
                      let previous = itemsByID[previousNativeSelectionID],
                      outlineView.row(forItem: previous) >= 0 {
                desiredItem = previous
            } else {
                desiredItem = configuration.selectedDocumentPath.flatMap {
                    noteItemsByPath[$0]
                }
            }

            isSynchronizingSelection = true
            defer { isSynchronizingSelection = false }
            guard let desiredItem else {
                if activeDocumentChanged {
                    outlineView.deselectAll(nil)
                }
                return
            }
            let row = outlineView.row(forItem: desiredItem)
            guard row >= 0 else {
                if activeDocumentChanged {
                    outlineView.deselectAll(nil)
                }
                return
            }
            if outlineView.selectedRow != row {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }

        private func synchronizeExpansion(in outlineView: NSOutlineView) {
            isSynchronizingExpansion = true
            defer { isSynchronizingExpansion = false }

            let expanded = configuration.expandedFolderIDs
            let collapsible = itemsByID.values
                .filter {
                    $0.isExpandable
                        && outlineView.isItemExpanded($0)
                        && !expanded.contains($0.id)
                }
                .sorted { $0.node.depth > $1.node.depth }
            for item in collapsible {
                outlineView.collapseItem(item, collapseChildren: false)
            }

            let expandable = itemsByID.values
                .filter {
                    $0.isExpandable
                        && expanded.contains($0.id)
                        && !outlineView.isItemExpanded($0)
                }
                .sorted { $0.node.depth < $1.node.depth }
            for item in expandable {
                outlineView.expandItem(item)
            }
        }

        private func refreshAvailableRows(in outlineView: NSOutlineView) {
            outlineView.enumerateAvailableRowViews { [weak self] rowView, row in
                guard let self,
                      row >= 0,
                      let item = outlineView.item(atRow: row) as? SidebarOutlineItem else {
                    return
                }
                let isHovered = (outlineView as? SidebarOutlineView)?
                    .isHovering(item) == true
                let isNativeFocused = outlineView.selectedRow == row
                    && outlineView.window?.firstResponder === outlineView
                (rowView as? SidebarOutlineRowView)?.configure(
                    item: item,
                    isExpanded: outlineView.isItemExpanded(item),
                    isHovered: isHovered,
                    isNativeFocused: isNativeFocused,
                    selectedDocumentPath: self.configuration.selectedDocumentPath,
                    nativeStrings: self.configuration.nativeStrings
                )
                guard let cell = outlineView.view(
                        atColumn: 0,
                        row: row,
                        makeIfNecessary: false
                      ) as? SidebarOutlineHostingCell else { return }
                self.configure(
                    cell: cell,
                    for: item,
                    isHovered: isHovered,
                    isNativeFocused: isNativeFocused
                )
            }
        }

        private func configure(
            cell: SidebarOutlineHostingCell,
            for item: SidebarOutlineItem,
            isHovered: Bool,
            isNativeFocused: Bool
        ) {
            let isExpanded = configuration.expandedFolderIDs.contains(item.id)
            let lifecycleNote = configuration.context.locationScope == .workspace
                ? nil
                : item.node.note
            let strings = configuration.nativeStrings
            cell.configure(
                with: hostedRow(for: item),
                isHovered: isHovered,
                disclosureLabel: item.isExpandable
                    ? strings.disclosureLabel(
                        isExpanded: isExpanded,
                        title: item.node.name
                    )
                    : nil,
                disclosureIsExpanded: isExpanded,
                disclosureDepth: item.node.depth,
                onDisclosure: item.isExpandable ? { [weak self] in
                    self?.toggleDisclosure(item)
                } : nil,
                putBackLabel: lifecycleNote.map {
                    strings.putBackLabel(title: $0.title ?? $0.displayName)
                },
                putBackIdentifier: lifecycleNote.map {
                    let encoded = $0.relativePath.addingPercentEncoding(
                        withAllowedCharacters: .alphanumerics
                    ) ?? $0.relativePath
                    return "scholium.lifecyclePutBack.\(encoded)"
                },
                putBackIsNativeFocused: isNativeFocused,
                putBackIsInProgress: lifecycleNote.flatMap(\.workspaceSnapshot).map {
                    configuration.putBackDocumentsInProgress.contains($0.id)
                } ?? false,
                onPutBack: lifecycleNote.map { note in
                    { [weak self] in self?.configuration.onPutBack(note) }
                }
            )
        }

        private func toggleDisclosure(_ item: SidebarOutlineItem) {
            var disclosure = configuration.expandedFolders
            if disclosure.contains(item.id) {
                disclosure.remove(item.id)
            } else {
                disclosure.insert(item.id)
            }
            configuration.expandedFolders = disclosure
        }

        private func hostedRow(
            for item: SidebarOutlineItem
        ) -> SidebarTreeNodeRow {
            SidebarTreeNodeRow(
                node: item.node,
                expandedFolders: configuration.$expandedFolders,
                selectedDocumentPath: configuration.selectedDocumentPath,
                context: configuration.context,
                onSelect: configuration.onSelect,
                onPutBack: configuration.onPutBack,
                onWillRemove: configuration.onWillRemove,
                onMutationFailed: configuration.onMutationFailed
            )
        }

        @objc private func scrollBoundsDidChange(_ notification: Notification) {
            (outlineView as? SidebarOutlineView)?.scheduleHoverReconciliation()
        }

        private func handleRevealRequest(in outlineView: NSOutlineView) {
            guard let request = configuration.revealRequest,
                  request.generation != lastRevealGeneration else { return }
            guard configuration.disclosureScope == request.scope else {
                lastRevealGeneration = request.generation
                configuration.onConsumeRevealRequest(request)
                return
            }

            guard let item = itemsByID[request.relativePath] else { return }
            expandAncestors(of: item, in: outlineView)
            lastRevealGeneration = request.generation

            DispatchQueue.main.async { [weak self, weak outlineView] in
                guard let self, let outlineView else { return }
                let row = outlineView.row(forItem: item)
                guard row >= 0 else {
                    self.lastRevealGeneration = nil
                    return
                }
                switch request.alignment {
                case .nearest:
                    outlineView.scrollRowToVisible(row)
                case .center:
                    self.center(row: row, in: outlineView)
                }
                self.configuration.onConsumeRevealRequest(request)
            }
        }

        private func handleFocusRequest(in outlineView: NSOutlineView) {
            guard let path = configuration.requestedFocusPath else {
                lastRequestedFocusPath = nil
                return
            }
            guard path != lastRequestedFocusPath,
                  let item = itemsByID[path] else { return }
            lastRequestedFocusPath = path
            expandAncestors(of: item, in: outlineView)
            let row = outlineView.row(forItem: item)
            guard row >= 0 else { return }
            isSynchronizingSelection = true
            outlineView.selectRowIndexes(
                IndexSet(integer: row),
                byExtendingSelection: false
            )
            isSynchronizingSelection = false
            outlineView.scrollRowToVisible(row)
            outlineView.window?.makeFirstResponder(outlineView)
            DispatchQueue.main.async { [weak self, weak outlineView] in
                guard let self, let outlineView else { return }
                self.refreshAvailableRows(in: outlineView)
                self.configuration.onFocusRequestHandled()
            }
        }

        private func handleSourceListFocus(in outlineView: NSOutlineView) {
            guard configuration.focusRequestGeneration != lastFocusRequestGeneration else {
                return
            }
            lastFocusRequestGeneration = configuration.focusRequestGeneration
            outlineView.window?.makeFirstResponder(outlineView)
        }

        private func expandAncestors(
            of item: SidebarOutlineItem,
            in outlineView: NSOutlineView
        ) {
            var ancestors: [SidebarOutlineItem] = []
            var parent = item.parent
            while let current = parent {
                ancestors.append(current)
                parent = current.parent
            }
            isSynchronizingExpansion = true
            for ancestor in ancestors.reversed() where ancestor.isExpandable {
                outlineView.expandItem(ancestor)
            }
            isSynchronizingExpansion = false
        }

        private func center(row: Int, in outlineView: NSOutlineView) {
            guard let scrollView else {
                outlineView.scrollRowToVisible(row)
                return
            }
            let rowRect = outlineView.rect(ofRow: row)
            let visibleHeight = scrollView.contentView.bounds.height
            let maximumY = max(0, outlineView.bounds.height - visibleHeight)
            let targetY = min(max(0, rowRect.midY - visibleHeight / 2), maximumY)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func makeRootMenu() -> NSMenu? {
            guard configuration.context.locationScope == .workspace else { return nil }
            let menu = NSMenu()

            let note = NSMenuItem(
                title: configuration.nativeStrings.newNote,
                action: #selector(createRootNote),
                keyEquivalent: ""
            )
            note.target = self
            note.image = NSImage(
                systemSymbolName: "doc.badge.plus",
                accessibilityDescription: nil
            )
            note.isEnabled = configuration.context.canMutateLibrary
            menu.addItem(note)

            let folder = NSMenuItem(
                title: configuration.nativeStrings.newFolder,
                action: #selector(createRootFolder),
                keyEquivalent: ""
            )
            folder.target = self
            folder.image = NSImage(
                systemSymbolName: "folder.badge.plus",
                accessibilityDescription: nil
            )
            folder.isEnabled = configuration.context.canMutateLibrary
            menu.addItem(folder)
            return menu
        }

        @objc private func createRootNote() {
            configuration.context.createUntitledNote(nil)
        }

        @objc private func createRootFolder() {
            configuration.context.createUntitledFolder(nil)
        }

        private func activateNativeSelection() {
            guard let outlineView,
                  outlineView.selectedRow >= 0,
                  let item = outlineView.item(
                      atRow: outlineView.selectedRow
                  ) as? SidebarOutlineItem else { return }
            if let note = item.node.note {
                configuration.onSelect(note)
            } else if item.isExpandable {
                toggleDisclosure(item)
            }
        }

        /// NSTableView's native single-click action is delivered on a
        /// completed click, including when the clicked Folder is already the
        /// native selection. A drag does not send this action. Keep Folder
        /// disclosure here instead of inferring activation from a selection
        /// notification and the process-wide current event.
        @objc private func activateOutlineClick(_ sender: NSOutlineView) {
            guard sender.clickedRow >= 0,
                  let item = sender.item(
                      atRow: sender.clickedRow
                  ) as? SidebarOutlineItem,
                  item.isExpandable else { return }
            toggleDisclosure(item)
        }

        private func dropFolderTarget(
            in outlineView: NSOutlineView,
            info: NSDraggingInfo
        ) -> SidebarOutlineItem? {
            let point = outlineView.convert(info.draggingLocation, from: nil)
            let row = outlineView.row(at: point)
            guard row >= 0 else { return nil }
            guard let item = outlineView.item(atRow: row) as? SidebarOutlineItem else {
                return nil
            }
            if item.node.isFolder, item.node.folderRelativePath != nil {
                return item
            }
            return nil
        }

        private func validatedDrop(
            payload: SidebarNativeDragPayload,
            folderRelativePath: String?
        ) -> Bool {
            sidebarNativeDropIsValid(
                payload,
                folderRelativePath: folderRelativePath,
                inventory: configuration.dropInventory
            )
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            numberOfChildrenOfItem item: Any?
        ) -> Int {
            (item as? SidebarOutlineItem)?.children.count ?? roots.count
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            child index: Int,
            ofItem item: Any?
        ) -> Any {
            if let item = item as? SidebarOutlineItem {
                return item.children[index]
            }
            return roots[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? SidebarOutlineItem)?.isExpandable == true
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            pasteboardWriterForItem item: Any
        ) -> (any NSPasteboardWriting)? {
            guard let item = item as? SidebarOutlineItem,
                  configuration.dropInventory.locationScope == .workspace,
                  configuration.dropInventory.canMutate else { return nil }

            if let note = item.node.note,
               let target = NoteLifecycleTarget(note),
               !CritiquePlacement.isManagedCritiquePath(note.relativePath) {
                let payload = SidebarNoteDragItem(target)
                guard !configuration.dropInventory.pendingNoteMoves.contains(payload.id),
                      configuration.dropInventory.notes.contains(where: {
                          NoteLifecycleTarget($0) == target
                      }) else { return nil }
                return pasteboardItem(
                    payload,
                    contentType: SidebarNoteDragItem.pasteboardType
                )
            }

            if let path = item.node.folderRelativePath,
               let vaultID = configuration.dropInventory.currentVaultID {
                let payload = SidebarFolderDragItem(FolderLifecycleTarget(
                    vaultID: vaultID,
                    relativePath: path
                ))
                guard payload.vaultID == configuration.dropInventory.currentVaultID,
                      !configuration.dropInventory.pendingFolderMoves.contains(payload.id),
                      sidebarDropFolderIsMutable(
                          path,
                          inventory: configuration.dropInventory
                      ) else { return nil }
                return pasteboardItem(
                    payload,
                    contentType: SidebarFolderDragItem.pasteboardType
                )
            }
            return nil
        }

        private func pasteboardItem<Payload: Encodable>(
            _ payload: Payload,
            contentType: String
        ) -> NSPasteboardItem? {
            guard let data = try? JSONEncoder().encode(payload) else { return nil }
            let item = NSPasteboardItem()
            item.setData(data, forType: NSPasteboard.PasteboardType(contentType))
            return item
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            validateDrop info: NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> NSDragOperation {
            guard let payload = sidebarNativeDragPayload(from: info),
                  let target = dropFolderTarget(in: outlineView, info: info),
                  let folderRelativePath = target.node.folderRelativePath,
                  validatedDrop(
                    payload: payload,
                    folderRelativePath: folderRelativePath
                  ) else {
                return []
            }
            outlineView.setDropItem(
                target,
                dropChildIndex: NSOutlineViewDropOnItemIndex
            )
            return .move
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: NSDraggingInfo,
            item: Any?,
            childIndex index: Int
        ) -> Bool {
            guard index == NSOutlineViewDropOnItemIndex,
                  let target = item as? SidebarOutlineItem,
                  target.node.isFolder,
                  let targetFolder = target.node.folderRelativePath,
                  let payload = sidebarNativeDragPayload(from: info) else {
                return false
            }
            guard validatedDrop(
                    payload: payload,
                    folderRelativePath: targetFolder
                  ) else { return false }
            commitSidebarNativeDrop(
                payload,
                folderRelativePath: targetFolder,
                onMoveNote: configuration.onMoveNoteDrop,
                onMoveFolder: configuration.onMoveFolderDrop
            )
            return true
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            shouldShowOutlineCellForItem item: Any
        ) -> Bool {
            true
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            item is SidebarOutlineItem
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isSynchronizingSelection,
                  let outlineView = notification.object as? NSOutlineView else { return }
            refreshAvailableRows(in: outlineView)
            guard outlineView.selectedRow >= 0,
                  let item = outlineView.item(
                      atRow: outlineView.selectedRow
                  ) as? SidebarOutlineItem else { return }
            if let note = item.node.note {
                configuration.onSelect(note)
            }
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            heightOfRowByItem item: Any
        ) -> CGFloat {
            configuration.rowHeight
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            viewFor tableColumn: NSTableColumn?,
            item: Any
        ) -> NSView? {
            guard let item = item as? SidebarOutlineItem else { return nil }
            let cell = outlineView.makeView(
                withIdentifier: Self.cellIdentifier,
                owner: self
            ) as? SidebarOutlineHostingCell ?? SidebarOutlineHostingCell()
            cell.identifier = Self.cellIdentifier
            configure(
                cell: cell,
                for: item,
                isHovered: (outlineView as? SidebarOutlineView)?
                    .isHovering(item) == true,
                isNativeFocused: outlineView.selectedRow == outlineView.row(forItem: item)
                    && outlineView.window?.firstResponder === outlineView
            )
            return cell
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            rowViewForItem item: Any
        ) -> NSTableRowView? {
            guard let item = item as? SidebarOutlineItem else { return nil }
            let row = outlineView.makeView(
                withIdentifier: Self.rowIdentifier,
                owner: self
            ) as? SidebarOutlineRowView ?? SidebarOutlineRowView()
            row.identifier = Self.rowIdentifier
            row.configure(
                item: item,
                isExpanded: outlineView.isItemExpanded(item),
                isHovered: (outlineView as? SidebarOutlineView)?
                    .isHovering(item) == true,
                isNativeFocused: outlineView.selectedRow == outlineView.row(forItem: item)
                    && outlineView.window?.firstResponder === outlineView,
                selectedDocumentPath: configuration.selectedDocumentPath,
                nativeStrings: configuration.nativeStrings
            )
            return row
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            updateExpansion(from: notification, expanded: true)
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            updateExpansion(from: notification, expanded: false)
        }

        private func updateExpansion(from notification: Notification, expanded: Bool) {
            guard !isSynchronizingExpansion,
                  let item = notification.userInfo?["NSObject"] as? SidebarOutlineItem else {
                return
            }
            var disclosure = configuration.expandedFolders
            if expanded {
                disclosure.insert(item.id)
            } else {
                disclosure.remove(item.id)
            }
            lastSynchronizedExpandedFolderIDs = disclosure
            configuration.expandedFolders = disclosure
        }
    }
}
