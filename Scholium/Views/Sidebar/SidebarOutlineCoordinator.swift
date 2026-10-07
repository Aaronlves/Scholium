import AppKit
import ScholiumContracts
import SwiftUI

extension SidebarOutlineSourceList {
    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDelegate, NSMenuDelegate {
        private final class MenuAction: NSObject {
            let perform: () -> Bool
            init(perform: @escaping () -> Bool) { self.perform = perform }
        }
        static let columnIdentifier = NSUserInterfaceItemIdentifier(
            "ScholiumSidebarOutlineColumn"
        )
        private static let cellIdentifier = NSUserInterfaceItemIdentifier(
            "ScholiumSidebarOutlineCell"
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
        private var isPreparingContextSelection = false
        private var interactionGeneration: UInt64 = 0
        private var contextualMenu: NSMenu?
        private var contextualMenuNotes: [String: WindowDocumentLocation] = [:]
        private var lastRevealGeneration: UInt64?
        private var lastFocusRequestGeneration: UInt64
        private var lastRequestedFocusPath: String?
        private var lastRequestedFocusGeneration: UInt64?

        init(configuration: SidebarOutlineSourceList) {
            self.configuration = configuration
            lastFocusRequestGeneration = configuration.focusRequestGeneration
        }

        func attach(outlineView: NSOutlineView, scrollView: NSScrollView) {
            invalidateInteractions()
            self.outlineView = outlineView
            self.scrollView = scrollView
            lastProjectionRevision = nil
            lastSynchronizedExpandedFolderIDs = nil
            lastFocusRequestGeneration = configuration.focusRequestGeneration
            (outlineView as? SidebarOutlineView)?.chatAccessibilityAction = { [weak self, weak outlineView] in
                guard let self, let outlineView, self.outlineView === outlineView,
                    !outlineView.isHiddenOrHasHiddenAncestor, outlineView.selectedRowIndexes.count == 1,
                    let item = outlineView.item(atRow: outlineView.selectedRow) as? SidebarOutlineItem,
                    let note = item.node.note, self.configuration.context.canAddNoteToChat(note)
                else { return nil }
                let selectedID = item.id
                let generation = self.interactionGeneration
                return NSAccessibilityCustomAction(name: ScholiumL10n.string("Add to Chat", locale: self.configuration.locale)) {
                    [weak self, weak outlineView] in
                    guard let self, let outlineView, self.outlineView === outlineView,
                        !outlineView.isHiddenOrHasHiddenAncestor,
                        self.interactionGeneration == generation,
                        outlineView.selectedRowIndexes.count == 1,
                        self.selectedItemID(in: outlineView) == selectedID,
                        self.itemsByID[selectedID]?.node.note == note,
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
                nativeOutline.primaryClickHandler = { [weak self, weak outlineView] row, modifiers in
                    guard let self, let outlineView, self.outlineView === outlineView else { return false }
                    return self.openPrimaryClickedRow(row, modifiers: modifiers)
                }
                nativeOutline.target = nativeOutline
                nativeOutline.action = #selector(SidebarOutlineView.activateClickedRow)
                nativeOutline.lifecycleDidBecomeUnavailable = { [weak self] in self?.invalidateInteractions() }
                nativeOutline.lifecycleDidBecomeAvailable = { [weak self, weak outlineView] in
                    guard let self, let outlineView, self.outlineView === outlineView,
                        !outlineView.isHiddenOrHasHiddenAncestor
                    else { return }
                    self.refreshAvailableRows(in: outlineView)
                    self.handleRevealRequest(in: outlineView)
                    self.handleFocusRequest(in: outlineView)
                    self.handleSourceListFocus(in: outlineView)
                }
            }
            (scrollView as? SidebarOutlineScrollView)?.rootMenuProvider = { [weak self] in
                self?.makeSelectionMenu(for: -1)
            }
        }

        func detach(from scrollView: NSScrollView) {
            guard self.scrollView === scrollView else { return }
            invalidateInteractions()
            (scrollView as? SidebarOutlineScrollView)?.rootMenuProvider = nil
            if let nativeOutline = outlineView as? SidebarOutlineView {
                nativeOutline.chatAccessibilityAction = nil
                nativeOutline.selectionMenuProvider = nil
                nativeOutline.selectionAccessibilityActions = nil
                nativeOutline.trashSelection = nil
                nativeOutline.openSelection = nil
                nativeOutline.dragSelectionIsValid = nil
                nativeOutline.primaryClickHandler = nil
                nativeOutline.target = nil
                nativeOutline.action = nil
                nativeOutline.lifecycleDidBecomeUnavailable = nil
                nativeOutline.lifecycleDidBecomeAvailable = nil
            }
            outlineView?.delegate = nil
            outlineView?.dataSource = nil
            self.outlineView = nil
            self.scrollView = nil
        }

        func apply(configuration: SidebarOutlineSourceList) {
            if self.configuration.disclosureScope != configuration.disclosureScope {
                invalidateInteractions()
                lastRevealGeneration = nil
                lastProjectionRevision = nil
                lastSynchronizedExpandedFolderIDs = nil
            }
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
                let needsInitialProjection = lastProjectionRevision == nil
                let newStructure = sidebarOutlineStructure(from: configuration.roots)
                reconcile(configuration.roots)
                if contextualMenuNotes.contains(where: { itemsByID[$0.key]?.node.note != $0.value }) {
                    invalidateInteractions()
                }
                if needsInitialProjection || structure != newStructure {
                    invalidateInteractions()
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

        private func invalidateInteractions() {
            interactionGeneration &+= 1
            let menu = contextualMenu
            contextualMenu = nil
            contextualMenuNotes = [:]
            menu?.cancelTrackingWithoutAnimation()
            menu?.delegate = nil
            lastRevealGeneration = nil
            lastRequestedFocusPath = nil
            lastRequestedFocusGeneration = nil
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
            guard let outlineView, !outlineView.isHiddenOrHasHiddenAncestor else { return nil }
            isPreparingContextSelection = true
            defer { isPreparingContextSelection = false }
            let menu: NSMenu
            var menuNotes: [String: WindowDocumentLocation] = [:]
            if row >= 0, let item = outlineView.item(atRow: row) as? SidebarOutlineItem {
                if !outlineView.selectedRowIndexes.contains(row) {
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
                menu = makeItemMenu(for: item, surface: .contextMenu)
                for selected in selectedItems(in: outlineView) {
                    if let note = selected.node.note { menuNotes[selected.id] = note }
                }
            } else {
                outlineView.deselectAll(nil)
                menu = makeRootMenu()
            }
            (outlineView as? SidebarOutlineView)?.requestKeyboardFocus()
            contextualMenu?.cancelTrackingWithoutAnimation()
            contextualMenu?.delegate = nil
            contextualMenu = menu
            contextualMenuNotes = menuNotes
            menu.delegate = self
            return menu
        }

        private func makeItemMenu(
            for item: SidebarOutlineItem,
            surface: SidebarNoteCommandSurface
        ) -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.setAccessibilityIdentifier(
                item.node.isFolder ? "scholium.folderRow.\(item.id)" : "scholium.noteRow.\(item.id)"
            )
            menu.setAccessibilityLabel(item.node.note?.title ?? item.node.note?.displayName ?? item.node.name)
            guard let outlineView else { return menu }
            if outlineView.selectedRowIndexes.count > 1,
                outlineView.selectedRowIndexes.contains(outlineView.row(forItem: item))
            {
                appendBatchActions(to: menu)
            } else if let note = item.node.note {
                for (index, group) in sidebarNoteCommandGroups().enumerated() {
                    if index > 0 { menu.addItem(.separator()) }
                    for command in group.commands {
                        appendAction(
                            to: menu,
                            titleKey: surface == .contextMenu ? command.contextMenuTitleKey : command.accessibilityTitleKey,
                            enabled: configuration.context.canPerform(command, note: note),
                            item: item
                        ) { [weak self, weak item] in
                            guard let self, let item, item.node.note == note,
                                self.configuration.context.canPerform(command, note: note)
                            else { return false }
                            self.configuration.context.perform(command, note: note)
                            return true
                        }
                    }
                }
            } else {
                appendFolderActions(to: menu, item: item)
            }
            return menu
        }

        private func appendAction(
            to menu: NSMenu,
            titleKey: String.LocalizationValue,
            enabled: Bool = true,
            item: SidebarOutlineItem? = nil,
            perform: @escaping () -> Bool
        ) {
            let generation = interactionGeneration
            let scope = configuration.disclosureScope
            let itemID = item?.id
            let action = MenuAction { [weak self, weak item] in
                guard let self, let outlineView = self.outlineView,
                    !outlineView.isHiddenOrHasHiddenAncestor,
                    self.interactionGeneration == generation,
                    self.configuration.disclosureScope == scope
                else { return false }
                if let itemID {
                    guard let item, self.itemsByID[itemID] === item,
                        outlineView.row(forItem: item) >= 0
                    else { return false }
                }
                return perform()
            }
            let menuItem = NSMenuItem(
                title: ScholiumL10n.string(titleKey, locale: configuration.locale),
                action: #selector(performMenuAction), keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = action
            menuItem.isEnabled = enabled
            menu.addItem(menuItem)
        }

        @objc private func performMenuAction(_ sender: NSMenuItem) {
            guard sender.isEnabled else { return }
            _ = (sender.representedObject as? MenuAction)?.perform()
        }

        func menuDidClose(_ menu: NSMenu) {
            if contextualMenu === menu {
                contextualMenu = nil
                contextualMenuNotes = [:]
                menu.delegate = nil
            }
        }

        private func appendBatchActions(to menu: NSMenu) {
            let targets = selectedNoteTargets()
            appendAction(to: menu, titleKey: "Move Notes…", enabled: targets != nil) { [weak self] in
                guard let self, let targets, self.selectedNoteTargets() == targets else { return false }
                self.configuration.onBatchMove(targets)
                return true
            }
            appendAction(to: menu, titleKey: "Move to Trash…", enabled: targets != nil) { [weak self] in
                guard let self, let targets, self.selectedNoteTargets() == targets else { return false }
                self.configuration.onBatchTrash(targets)
                return true
            }
        }

        private func appendFolderActions(to menu: NSMenu, item: SidebarOutlineItem) {
            if let path = item.node.folderRelativePath {
                if configuration.context.canMutateLibrary {
                    appendAction(to: menu, titleKey: "New Note", item: item) { [weak self] in
                        guard let self, self.configuration.context.canMutateLibrary else { return false }
                        self.configuration.context.createUntitledNote(path)
                        return true
                    }
                    appendAction(to: menu, titleKey: "New Folder", item: item) { [weak self] in
                        guard let self, self.configuration.context.canMutateLibrary else { return false }
                        self.configuration.context.createUntitledFolder(path)
                        return true
                    }
                    menu.addItem(.separator())
                    if let vaultID = configuration.context.currentVaultID {
                        let target = FolderMutationTarget(vaultID: vaultID, relativePath: path)
                        let actions: [(String.LocalizationValue, Bool)] = [
                            ("Rename Folder…", true), ("Move Folder…", false),
                        ]
                        for (title, isRename) in actions {
                            appendAction(to: menu, titleKey: title, item: item) { [weak self] in
                                guard let self, self.configuration.context.canMutateLibrary,
                                    self.configuration.context.currentVaultID == target.vaultID
                                else { return false }
                                self.configuration.context.requestFolderFileOperation(
                                    isRename ? .rename(target) : .move(target)
                                )
                                return true
                            }
                        }
                    }
                }
                appendFolderDisclosure(to: menu, item: item)
                menu.addItem(.separator())
                appendAction(to: menu, titleKey: "Reveal in Finder", item: item) { [weak self] in
                    self?.configuration.context.revealNote(path)
                    return self != nil
                }
                appendAction(to: menu, titleKey: "Copy Relative Path", item: item) { [weak self] in
                    self?.configuration.context.copyRelativePath(path)
                    return self != nil
                }
                if configuration.context.canMutateLibrary, let vaultID = configuration.context.currentVaultID {
                    let target = FolderMutationTarget(vaultID: vaultID, relativePath: path)
                    menu.addItem(.separator())
                    appendAction(to: menu, titleKey: "Move Folder and Notes to Trash…", item: item) { [weak self] in
                        guard let self, self.configuration.context.canMutateLibrary,
                            self.configuration.context.currentVaultID == target.vaultID
                        else { return false }
                        self.configuration.context.requestFolderTrash(target)
                        return true
                    }
                }
            } else {
                appendFolderDisclosure(to: menu, item: item)
            }
        }

        private func appendFolderDisclosure(to menu: NSMenu, item: SidebarOutlineItem) {
            guard !item.children.isEmpty else { return }
            let folderIDs = item.node.folderIDs
            let expanded = folderIDs.isSubset(of: configuration.expandedFolderIDs)
            appendAction(to: menu, titleKey: expanded ? "Collapse All" : "Expand All", item: item) { [weak self] in
                guard let self else { return false }
                var disclosure = self.configuration.expandedFolders
                if expanded { disclosure.subtract(folderIDs) } else { disclosure.formUnion(folderIDs) }
                self.configuration.expandedFolders = disclosure
                return true
            }
        }

        private func accessibilityActions(
            in menu: NSMenu,
            representedItemIsCurrent: @escaping () -> Bool = { true }
        ) -> [NSAccessibilityCustomAction] {
            menu.items.compactMap { menuItem in
                guard menuItem.isEnabled, let action = menuItem.representedObject as? MenuAction else { return nil }
                return NSAccessibilityCustomAction(name: menuItem.title) {
                    guard representedItemIsCurrent() else { return false }
                    return action.perform()
                }
            }
        }

        private func selectionAccessibilityActions() -> [NSAccessibilityCustomAction] {
            guard let outlineView, outlineView.selectedRowIndexes.count > 1,
                selectedNoteTargets() != nil
            else { return [] }
            let menu = NSMenu()
            appendBatchActions(to: menu)
            return accessibilityActions(in: menu)
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

        private func openPrimaryClickedRow(_ row: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
            guard let outlineView, !outlineView.isHiddenOrHasHiddenAncestor,
                modifiers.intersection([.command, .shift, .control]).isEmpty,
                row >= 0, outlineView.selectedRowIndexes == IndexSet(integer: row),
                let item = outlineView.item(atRow: row) as? SidebarOutlineItem,
                itemsByID[item.id] === item, let note = item.node.note
            else { return false }
            configuration.onSelect(note)
            return true
        }

        private func dragSelectionIsValid(_ rows: IndexSet) -> Bool {
            guard let outlineView, !outlineView.isHiddenOrHasHiddenAncestor, !rows.isEmpty else { return false }
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
            outlineView.enumerateAvailableRowViews { [weak self] _, row in
                guard let self,
                    row >= 0,
                    let item = outlineView.item(atRow: row) as? SidebarOutlineItem
                else {
                    return
                }
                guard
                    let cell = outlineView.view(
                        atColumn: 0,
                        row: row,
                        makeIfNecessary: false
                    ) as? SidebarOutlineCell
                else { return }
                self.configure(
                    cell: cell,
                    for: item,
                    in: outlineView
                )
            }
        }

        private func configure(
            cell: SidebarOutlineCell,
            for item: SidebarOutlineItem,
            in outlineView: NSOutlineView
        ) {
            cell.configure(
                item: item,
                isExpanded: outlineView.isItemExpanded(item),
                nativeStrings: configuration.nativeStrings,
                presentation: SidebarSourceListRowPresentation(
                    effectiveRowSizeStyle: outlineView.effectiveRowSizeStyle
                )
            )
            cell.titleLabel.actionProvider = { [weak self, weak cell, weak item, weak outlineView] in
                guard let self, let cell, let item, let outlineView,
                    self.outlineView === outlineView, !outlineView.isHiddenOrHasHiddenAncestor,
                    (cell.objectValue as? SidebarOutlineItem) === item,
                    self.itemsByID[item.id] === item, outlineView.row(forItem: item) >= 0
                else { return [] }
                let generation = cell.representationGeneration
                return self.accessibilityActions(
                    in: self.makeItemMenu(for: item, surface: .accessibility),
                    representedItemIsCurrent: { [weak cell, weak item] in
                        guard let cell, let item else { return false }
                        return cell.representationGeneration == generation
                            && (cell.objectValue as? SidebarOutlineItem) === item
                    }
                )
            }
        }

        private func handleRevealRequest(in outlineView: NSOutlineView) {
            guard !outlineView.isHiddenOrHasHiddenAncestor,
                let request = configuration.revealRequest,
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
            let generation = interactionGeneration

            DispatchQueue.main.async { [weak self, weak outlineView] in
                guard let self,
                    let outlineView,
                    self.outlineView === outlineView,
                    !outlineView.isHiddenOrHasHiddenAncestor,
                    self.interactionGeneration == generation,
                    self.itemsByID[item.id] === item,
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
                lastRequestedFocusGeneration = nil
                return
            }
            guard !outlineView.isHiddenOrHasHiddenAncestor,
                path != lastRequestedFocusPath || configuration.focusRequestGeneration != lastRequestedFocusGeneration,
                let item = itemsByID[path]
            else { return }
            expandAncestors(of: item, in: outlineView)
            let row = outlineView.row(forItem: item)
            guard row >= 0 else { return }
            guard (outlineView as? SidebarOutlineView)?.requestKeyboardFocus() == true else { return }
            lastRequestedFocusPath = path
            lastRequestedFocusGeneration = configuration.focusRequestGeneration
            isSynchronizingSelection = true
            outlineView.selectRowIndexes(
                IndexSet(integer: row),
                byExtendingSelection: false
            )
            isSynchronizingSelection = false
            outlineView.scrollRowToVisible(row)
            let scope = configuration.disclosureScope
            let generation = configuration.focusRequestGeneration
            let interactionGeneration = self.interactionGeneration
            DispatchQueue.main.async { [weak self, weak outlineView] in
                guard let self,
                    let outlineView,
                    self.outlineView === outlineView,
                    !outlineView.isHiddenOrHasHiddenAncestor,
                    self.interactionGeneration == interactionGeneration,
                    self.itemsByID[item.id] === item,
                    outlineView.row(forItem: item) >= 0,
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
            if (outlineView as? SidebarOutlineView)?.requestKeyboardFocus() == true {
                lastFocusRequestGeneration = configuration.focusRequestGeneration
            }
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

        private func makeRootMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            appendAction(to: menu, titleKey: "New Note", enabled: configuration.context.canMutateLibrary) { [weak self] in
                guard let self, self.configuration.context.canMutateLibrary else { return false }
                self.configuration.context.createUntitledNote(nil)
                return true
            }
            menu.items.last?.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)
            appendAction(to: menu, titleKey: "New Folder", enabled: configuration.context.canMutateLibrary) { [weak self] in
                guard let self, self.configuration.context.canMutateLibrary else { return false }
                self.configuration.context.createUntitledFolder(nil)
                return true
            }
            menu.items.last?.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)
            return menu
        }

        @MainActor
        private struct DropTarget {
            let item: SidebarOutlineItem?
            let childIndex: Int

            var folderRelativePath: String? { item?.node.folderRelativePath }
        }

        private func dropTarget(
            in outlineView: NSOutlineView,
            item: Any?,
            childIndex: Int
        ) -> DropTarget? {
            guard self.outlineView === outlineView,
                !outlineView.isHiddenOrHasHiddenAncestor
            else { return nil }

            guard let item else {
                guard
                    childIndex == NSOutlineViewDropOnItemIndex
                        || (0...roots.count).contains(childIndex)
                else { return nil }
                // The native outline owns root insertion gaps, including the
                // end gap when the pointer is below the last row. Order is
                // derived by the Library, so this expresses only root placement.
                return DropTarget(
                    item: nil,
                    childIndex: childIndex == NSOutlineViewDropOnItemIndex ? roots.count : childIndex
                )
            }
            guard let item = item as? SidebarOutlineItem,
                itemsByID[item.id] === item,
                outlineView.row(forItem: item) >= 0,
                item.node.isFolder, item.node.folderRelativePath != nil,
                childIndex == NSOutlineViewDropOnItemIndex
                    || (0...item.children.count).contains(childIndex)
            else { return nil }
            // Folder contents are sorted; advertise the containing Folder,
            // rather than promising an insertion order the model does not own.
            return DropTarget(item: item, childIndex: NSOutlineViewDropOnItemIndex)
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
                let target = dropTarget(in: outlineView, item: item, childIndex: index),
                validatedDrop(
                    payload: payload,
                    folderRelativePath: target.folderRelativePath
                )
            else {
                return []
            }
            outlineView.setDropItem(
                target.item,
                dropChildIndex: target.childIndex
            )
            return .move
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: NSDraggingInfo,
            item: Any?,
            childIndex index: Int
        ) -> Bool {
            guard let target = dropTarget(in: outlineView, item: item, childIndex: index),
                let payload = sidebarNativeDragPayload(from: info)
            else {
                return false
            }
            guard
                validatedDrop(
                    payload: payload,
                    folderRelativePath: target.folderRelativePath
                )
            else { return false }
            commitSidebarNativeDrop(
                payload,
                folderRelativePath: target.folderRelativePath,
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
                let outlineView = notification.object as? NSOutlineView,
                self.outlineView === outlineView,
                !outlineView.isHiddenOrHasHiddenAncestor
            else { return }
            refreshAvailableRows(in: outlineView)
            let items = selectedItems(in: outlineView)
            configuration.onSelectionChange(Set(items.map(\.id)))
            let extendsSelection = NSApp.currentEvent?.modifierFlags.intersection([.command, .shift]).isEmpty == false
            guard items.count == 1, !extendsSelection, !isPreparingContextSelection,
                (outlineView as? SidebarOutlineView)?.isHandlingPrimaryMouseDown != true,
                NSApp.currentEvent?.type != .rightMouseDown,
                NSApp.currentEvent?.modifierFlags.contains(.control) != true,
                let note = items.first?.node.note
            else { return }
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
                ) as? SidebarOutlineCell ?? SidebarOutlineCell()
            cell.identifier = Self.cellIdentifier
            configure(cell: cell, for: item, in: outlineView)
            return cell
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            updateExpansion(from: notification, expanded: true)
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            updateExpansion(from: notification, expanded: false)
        }

        private func updateExpansion(from notification: Notification, expanded: Bool) {
            guard !isSynchronizingExpansion,
                let outlineView = notification.object as? NSOutlineView,
                self.outlineView === outlineView,
                !outlineView.isHiddenOrHasHiddenAncestor,
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
