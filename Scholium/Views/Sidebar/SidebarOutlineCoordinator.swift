import AppKit
import ScholiumContracts
import SwiftUI

extension SidebarOutlineSourceList {
    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDelegate {
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
        private var structure: [SidebarOutlineStructureEntry] = []
        private var lastProjectionRevision: UInt64?
        private var lastSynchronizedExpandedFolderIDs: Set<String>?
        private var isSynchronizingExpansion = false
        private var isSynchronizingSelection = false
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
            (outlineView as? SidebarOutlineView)?.chatAccessibilityAction = { [weak self, weak outlineView] in
                guard let self, let outlineView, self.outlineView === outlineView, outlineView.selectedRowIndexes.count == 1,
                    let item = outlineView.item(atRow: outlineView.selectedRow) as? SidebarOutlineItem,
                    let note = item.node.note, self.configuration.context.canAddNoteToChat(note)
                else { return nil }
                let selectedID = item.id
                return NSAccessibilityCustomAction(name: ScholiumL10n.string("Add to Chat", locale: self.configuration.locale)) {
                    [weak self, weak outlineView] in
                    guard let self, let outlineView, self.outlineView === outlineView,
                        outlineView.selectedRowIndexes.count == 1,
                        self.selectedItemID(in: outlineView) == selectedID,
                        self.configuration.context.canAddNoteToChat(note)
                    else { return false }
                    self.configuration.context.addNoteToChat(note)
                    return true
                }
            }
            if let nativeOutline = outlineView as? SidebarOutlineView {
                nativeOutline.selectionMenuProvider = { [weak self] row in self?.makeSelectionMenu(for: row) }
                nativeOutline.selectionAccessibilityActions = { [weak self] in self?.selectionAccessibilityActions() ?? [] }
                nativeOutline.trashSelection = { [weak self] in self?.trashSelection() ?? false }
                nativeOutline.openSelection = { [weak self] in self?.openSelection() ?? false }
                nativeOutline.dragSelectionIsValid = { [weak self] rows in self?.dragSelectionIsValid(rows) ?? false }
            }
            (scrollView as? SidebarOutlineScrollView)?.rootMenuProvider = { [weak self] in
                self?.makeRootMenu()
            }
        }

        func detach(from scrollView: NSScrollView) {
            (scrollView as? SidebarOutlineScrollView)?.rootMenuProvider = nil
            if let nativeOutline = outlineView as? SidebarOutlineView {
                nativeOutline.chatAccessibilityAction = nil
                nativeOutline.selectionMenuProvider = nil
                nativeOutline.selectionAccessibilityActions = nil
                nativeOutline.trashSelection = nil
                nativeOutline.openSelection = nil
                nativeOutline.dragSelectionIsValid = nil
            }
            self.outlineView = nil
            self.scrollView = nil
        }

        func apply(configuration: SidebarOutlineSourceList) {
            self.configuration = configuration
            guard let outlineView else { return }
            outlineView.setAccessibilityLabel(
                configuration.accessibilityLocationName
            )

            isSynchronizingSelection = true
            defer { isSynchronizingSelection = false }
            var structureChanged = false
            let desiredRowSizeStyle: NSTableView.RowSizeStyle =
                configuration.usesAccessibilitySize ? .large : .default
            if outlineView.rowSizeStyle != desiredRowSizeStyle {
                outlineView.rowSizeStyle = desiredRowSizeStyle
                outlineView.reloadData()
                structureChanged = true
            }

            if lastProjectionRevision != configuration.projectionRevision {
                let newStructure = sidebarOutlineStructure(from: configuration.roots)
                reconcile(configuration.roots)
                if structure != newStructure {
                    structure = newStructure
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
            synchronizeSelection(in: outlineView)
            refreshAvailableRows(in: outlineView)
            handleRevealRequest(in: outlineView)
            handleFocusRequest(in: outlineView)
            handleSourceListFocus(in: outlineView)
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

        }

        private func selectedItemID(in outlineView: NSOutlineView) -> String? {
            guard outlineView.selectedRow >= 0 else { return nil }
            return (outlineView.item(atRow: outlineView.selectedRow) as? SidebarOutlineItem)?.id
        }

        private func synchronizeSelection(in outlineView: NSOutlineView) {
            let rows = IndexSet(
                configuration.selectedRowIDs.compactMap { id in
                    guard let item = itemsByID[id] else { return nil }
                    let row = outlineView.row(forItem: item)
                    return row >= 0 ? row : nil
                })
            guard rows != outlineView.selectedRowIndexes else { return }
            outlineView.selectRowIndexes(rows, byExtendingSelection: false)
        }

        private func selectedItems(in outlineView: NSOutlineView) -> [SidebarOutlineItem] {
            outlineView.selectedRowIndexes.compactMap { outlineView.item(atRow: $0) as? SidebarOutlineItem }
        }

        private func selectedNoteTargets() -> [NoteMutationTarget]? {
            guard let outlineView, !outlineView.isHiddenOrHasHiddenAncestor,
                configuration.context.canMutateLibrary
            else { return nil }
            let items = selectedItems(in: outlineView)
            guard !items.isEmpty else { return nil }
            let targets = items.compactMap { $0.node.note.flatMap(NoteMutationTarget.init) }
            guard targets.count == items.count,
                targets.allSatisfy({ $0.documentID.vaultID == configuration.context.currentVaultID })
            else { return nil }
            return targets
        }

        private func makeSelectionMenu(for row: Int) -> NSMenu? {
            guard let outlineView, outlineView.selectedRowIndexes.count > 1,
                outlineView.selectedRowIndexes.contains(row)
            else { return nil }
            let menu = NSMenu()
            menu.autoenablesItems = false
            let targets = selectedNoteTargets()
            let enabled = targets != nil
            let move = NSMenuItem(
                title: ScholiumL10n.string("Move Notes…", locale: configuration.locale),
                action: #selector(moveSelectedNotes), keyEquivalent: "")
            move.target = self
            move.representedObject = targets
            move.isEnabled = enabled
            menu.addItem(move)
            let trash = NSMenuItem(
                title: ScholiumL10n.string("Move to Trash…", locale: configuration.locale),
                action: #selector(trashSelectedNotes), keyEquivalent: "")
            trash.target = self
            trash.representedObject = targets
            trash.isEnabled = enabled
            menu.addItem(trash)
            return menu
        }

        private func selectionAccessibilityActions() -> [NSAccessibilityCustomAction] {
            guard let outlineView, outlineView.selectedRowIndexes.count > 1,
                let targets = selectedNoteTargets()
            else { return [] }
            return [
                NSAccessibilityCustomAction(name: ScholiumL10n.string("Move Notes…", locale: configuration.locale)) { [weak self] in
                    guard let self, self.selectedNoteTargets() == targets else { return false }
                    self.configuration.onBatchMove(targets)
                    return true
                },
                NSAccessibilityCustomAction(name: ScholiumL10n.string("Move to Trash…", locale: configuration.locale)) { [weak self] in
                    guard let self, self.selectedNoteTargets() == targets else { return false }
                    self.configuration.onBatchTrash(targets)
                    return true
                },
            ]
        }

        @objc private func moveSelectedNotes(_ sender: NSMenuItem) {
            guard let targets = sender.representedObject as? [NoteMutationTarget],
                selectedNoteTargets() == targets
            else { return }
            configuration.onBatchMove(targets)
        }

        @objc private func trashSelectedNotes(_ sender: NSMenuItem) {
            guard let targets = sender.representedObject as? [NoteMutationTarget],
                selectedNoteTargets() == targets
            else { return }
            configuration.onBatchTrash(targets)
        }

        private func trashSelection() -> Bool {
            guard let targets = selectedNoteTargets() else { return false }
            if targets.count == 1, let target = targets.first {
                configuration.context.requestNoteTrash(target)
            } else {
                configuration.onBatchTrash(targets)
            }
            return true
        }

        private func openSelection() -> Bool {
            guard let outlineView, !outlineView.isHiddenOrHasHiddenAncestor,
                outlineView.selectedRowIndexes.count == 1,
                let note = selectedItems(in: outlineView).first?.node.note
            else { return false }
            configuration.onSelect(note)
            return true
        }

        private func dragSelectionIsValid(_ rows: IndexSet) -> Bool {
            guard let outlineView, !rows.isEmpty else { return false }
            let items = rows.compactMap { outlineView.item(atRow: $0) as? SidebarOutlineItem }
            guard items.count == rows.count else { return false }
            if items.count > 1, !items.allSatisfy({ $0.node.note != nil }) { return false }
            return items.allSatisfy { self.outlineView(outlineView, pasteboardWriterForItem: $0) != nil }
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
                    let item = outlineView.item(atRow: row) as? SidebarOutlineItem
                else {
                    return
                }
                (rowView as? SidebarOutlineRowView)?.configure(
                    item: item,
                    isExpanded: outlineView.isItemExpanded(item),
                    nativeStrings: self.configuration.nativeStrings
                )
                guard
                    let cell = outlineView.view(
                        atColumn: 0,
                        row: row,
                        makeIfNecessary: false
                    ) as? SidebarOutlineHostingCell
                else { return }
                self.configure(
                    cell: cell,
                    for: item,
                    in: outlineView
                )
            }
        }

        private func configure(
            cell: SidebarOutlineHostingCell,
            for item: SidebarOutlineItem,
            in outlineView: NSOutlineView
        ) {
            cell.configure(with: hostedRow(for: item, in: outlineView))
        }

        private func hostedRow(
            for item: SidebarOutlineItem,
            in outlineView: NSOutlineView
        ) -> SidebarTreeNodeRow {
            return SidebarTreeNodeRow(
                node: item.node,
                expandedFolders: configuration.$expandedFolders,
                context: configuration.context,
                presentation: SidebarSourceListRowPresentation(
                    effectiveRowSizeStyle: outlineView.effectiveRowSizeStyle
                )
            )
        }

        private func handleRevealRequest(in outlineView: NSOutlineView) {
            guard let request = configuration.revealRequest,
                request.generation != lastRevealGeneration
            else { return }
            guard configuration.disclosureScope == request.scope else {
                lastRevealGeneration = request.generation
                configuration.onConsumeRevealRequest(request)
                return
            }

            guard let item = itemsByID[request.relativePath] else { return }
            expandAncestors(of: item, in: outlineView)
            lastRevealGeneration = request.generation

            DispatchQueue.main.async { [weak self, weak outlineView] in
                guard let self,
                    let outlineView,
                    self.outlineView === outlineView,
                    self.configuration.disclosureScope == request.scope,
                    self.configuration.revealRequest == request
                else { return }
                let row = outlineView.row(forItem: item)
                guard row >= 0 else {
                    self.lastRevealGeneration = nil
                    return
                }
                if request.relativePath == self.configuration.selectedDocumentPath {
                    self.isSynchronizingSelection = true
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    self.isSynchronizingSelection = false
                    self.configuration.onSelectionChange([item.id])
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
            guard !outlineView.isHiddenOrHasHiddenAncestor,
                path != lastRequestedFocusPath,
                let item = itemsByID[path]
            else { return }
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
            (outlineView as? SidebarOutlineView)?.requestKeyboardFocus()
            let scope = configuration.disclosureScope
            let generation = configuration.focusRequestGeneration
            DispatchQueue.main.async { [weak self, weak outlineView] in
                guard let self,
                    let outlineView,
                    self.outlineView === outlineView,
                    self.configuration.disclosureScope == scope,
                    self.configuration.focusRequestGeneration == generation,
                    self.configuration.requestedFocusPath == path
                else { return }
                self.refreshAvailableRows(in: outlineView)
                self.configuration.onSelectionChange([item.id])
                self.configuration.onFocusRequestHandled()
            }
        }

        private func handleSourceListFocus(in outlineView: NSOutlineView) {
            guard !outlineView.isHiddenOrHasHiddenAncestor,
                configuration.focusRequestGeneration != lastFocusRequestGeneration
            else {
                return
            }
            lastFocusRequestGeneration = configuration.focusRequestGeneration
            (outlineView as? SidebarOutlineView)?.requestKeyboardFocus()
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
                configuration.dropInventory.sourceScope == .library,
                configuration.dropInventory.canMutate
            else { return nil }

            if let note = item.node.note,
                let target = NoteMutationTarget(note)
            {
                let payload = SidebarNoteDragItem(target)
                guard !configuration.dropInventory.pendingNoteMoves.contains(payload.id),
                    configuration.dropInventory.notes.contains(where: {
                        NoteMutationTarget($0) == target
                    })
                else { return nil }
                return pasteboardItem(
                    payload,
                    contentType: SidebarNoteDragItem.pasteboardType
                )
            }

            if let path = item.node.folderRelativePath,
                let vaultID = configuration.dropInventory.currentVaultID
            {
                let payload = SidebarFolderDragItem(
                    FolderMutationTarget(
                        vaultID: vaultID,
                        relativePath: path
                    ))
                guard payload.vaultID == configuration.dropInventory.currentVaultID,
                    !configuration.dropInventory.pendingFolderMoves.contains(payload.id),
                    sidebarDropFolderIsMutable(
                        path,
                        inventory: configuration.dropInventory
                    )
                else { return nil }
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
                )
            else {
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
                let payload = sidebarNativeDragPayload(from: info)
            else {
                return false
            }
            guard
                validatedDrop(
                    payload: payload,
                    folderRelativePath: targetFolder
                )
            else { return false }
            commitSidebarNativeDrop(
                payload,
                folderRelativePath: targetFolder,
                onMoveNote: configuration.onMoveNoteDrop,
                onMoveFolder: configuration.onMoveFolderDrop,
                onMoveNotes: configuration.onMoveNotesDrop
            )
            return true
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            shouldShowOutlineCellForItem item: Any
        ) -> Bool {
            true
        }

        // NSOutlineView uses the inherited NSTableView row-action delegate API.
        func tableView(
            _ tableView: NSTableView,
            rowActionsForRow row: Int,
            edge: NSTableView.RowActionEdge
        ) -> [NSTableViewRowAction] {
            guard edge == .trailing,
                let outlineView = tableView as? NSOutlineView,
                self.outlineView === outlineView,
                !(outlineView.selectedRowIndexes.count > 1 && outlineView.selectedRowIndexes.contains(row)),
                configuration.context.canMutateLibrary,
                let item = outlineView.item(atRow: row) as? SidebarOutlineItem,
                let note = item.node.note,
                let target = NoteMutationTarget(note)
            else { return [] }

            let itemID = item.id
            let action = NSTableViewRowAction(
                style: .destructive,
                title: ScholiumL10n.string("Move to Trash…", locale: configuration.locale)
            ) { [weak self, weak outlineView] _, _ in
                guard let self, let outlineView,
                    self.outlineView === outlineView,
                    !outlineView.isHiddenOrHasHiddenAncestor,
                    self.configuration.context.canMutateLibrary,
                    let currentItem = self.itemsByID[itemID],
                    !(outlineView.selectedRowIndexes.count > 1 && outlineView.selectedRowIndexes.contains(outlineView.row(forItem: currentItem))),
                    let currentNote = currentItem.node.note,
                    NoteMutationTarget(currentNote) == target
                else { return }
                // Capture identity, not a row index that sorting/filtering can reuse.
                outlineView.rowActionsVisible = false
                self.configuration.context.requestNoteTrash(target)
            }
            action.image = NSImage(systemSymbolName: "trash", accessibilityDescription: action.title)
            return [action]
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            item is SidebarOutlineItem
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isSynchronizingSelection,
                let outlineView = notification.object as? NSOutlineView
            else { return }
            refreshAvailableRows(in: outlineView)
            let items = selectedItems(in: outlineView)
            configuration.onSelectionChange(Set(items.map(\.id)))
            let extendsSelection = NSApp.currentEvent?.modifierFlags.intersection([.command, .shift]).isEmpty == false
            guard items.count == 1, !extendsSelection, let note = items.first?.node.note else { return }
            configuration.onSelect(note)
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            viewFor tableColumn: NSTableColumn?,
            item: Any
        ) -> NSView? {
            guard let item = item as? SidebarOutlineItem else { return nil }
            let cell =
                outlineView.makeView(
                    withIdentifier: Self.cellIdentifier,
                    owner: self
                ) as? SidebarOutlineHostingCell ?? SidebarOutlineHostingCell()
            cell.identifier = Self.cellIdentifier
            configure(cell: cell, for: item, in: outlineView)
            return cell
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            rowViewForItem item: Any
        ) -> NSTableRowView? {
            guard let item = item as? SidebarOutlineItem else { return nil }
            let row =
                outlineView.makeView(
                    withIdentifier: Self.rowIdentifier,
                    owner: self
                ) as? SidebarOutlineRowView ?? SidebarOutlineRowView()
            row.identifier = Self.rowIdentifier
            row.configure(
                item: item,
                isExpanded: outlineView.isItemExpanded(item),
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
                let item = notification.userInfo?["NSObject"] as? SidebarOutlineItem
            else {
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
