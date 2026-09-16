import ScholiumContracts
import SwiftUI

// MARK: - Sidebar composition

struct SidebarWorkspaceNoteCounts: Equatable {
    private let values: [WorkspaceVaultSlot: Int]

    init(values: [WorkspaceVaultSlot: Int]) {
        self.values = values
    }

    func count(for slot: WorkspaceVaultSlot) -> Int? {
        values[slot]
    }
}

/// Immutable Source List projection and exact window actions supplied by the
/// composition root. Filters, sorting, and disclosure remain
/// owned by `DiscoveryController`; no view retains a parallel Library tree.
struct SidebarContext {
    let workspaceNoteCounts: SidebarWorkspaceNoteCounts
    /// Window-owned immutable hierarchy. The version changes only with its
    /// ordered Note cohort or Folder inventory, not with document presentation.
    let treeProjection: LibraryTreeProjectionVersion
    let allNotes: [WindowDocumentLocation]
    let folders: [String]
    let pathComparisonPolicy: VaultPathComparisonPolicy?
    let disclosureScope: LibraryDisclosureScope?
    let selectedDocumentPath: String?
    let libraryFocusRequestGeneration: UInt64
    let currentVaultRole: VaultRole
    let currentWorkspaceSlot: WorkspaceVaultSlot?
    let requestedWorkspaceSlot: WorkspaceVaultSlot?
    let canMutateLibrary: Bool
    let filterOptions: SidebarLibraryFilterOptions
    let openNote: (WindowDocumentLocation, WindowOpenDisposition) -> Void
    let canAddNoteToChat: (WindowDocumentLocation) -> Bool
    let addNoteToChat: (WindowDocumentLocation) -> Void
    let selectTriptychWorkspace: (WorkspaceVaultSlot) -> Void
    let createUntitledNote: (String?) -> Void
    let createUntitledFolder: (String?) -> Void
    let pendingNoteMoves: Set<SidebarNoteDragID>
    let pendingFolderMoves: Set<SidebarFolderDragID>
    let requestNoteDrop: (NoteMutationTarget, String) -> Void
    let requestFolderDrop: (FolderMutationTarget, String) -> Void
    let requestNoteBatchMove: ([NoteMutationTarget]) -> Void
    let requestNoteBatchTrash: ([NoteMutationTarget]) -> Void
    let moveNotesDrop: ([NoteMutationTarget], String?) -> Void
    let hasBatchOutcome: Bool
    let showBatchOutcome: () -> Void
    let requestFolderFileOperation: (FolderFileRequest) -> Void
    let requestFolderSystemTrash: (FolderMutationTarget) async throws -> Void
    let copyRelativePath: (String) -> Void
    let revealNote: (String) -> Void
    let requestSystemTrash: (NoteMutationTarget) async throws -> Void
    let selectSortOrder: (NoteSortOrder) -> Void
    let showError: (String) -> Void
}

struct SidebarView: View {
    @ObservedObject private var controller: DiscoveryController
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    let context: SidebarContext

    @State private var requestedRowFocusPath: String?

    init(controller: DiscoveryController, context: SidebarContext) {
        self.controller = controller
        self.context = context
    }

    private var treeProjection: LibraryTreeProjectionVersion {
        context.treeProjection
    }

    private var expandedFolders: Binding<Set<String>> {
        Binding(
            get: { controller.expandedFolders(in: context.disclosureScope) },
            set: { controller.setExpandedFolders($0, in: context.disclosureScope) }
        )
    }

    private var selectedRowIDs: Set<String> {
        controller.librarySelection(in: context.disclosureScope)
    }

    private var selectedBatchTargets: [NoteMutationTarget] {
        let targets = context.allNotes.filter { selectedRowIDs.contains($0.relativePath) }.compactMap(NoteMutationTarget.init)
        return targets.count == selectedRowIDs.count ? targets : []
    }

    private var visibleRowIDs: Set<String> {
        func ids(_ nodes: [TreeNode]) -> Set<String> {
            nodes.reduce(into: Set<String>()) { result, node in
                result.insert(node.id)
                if expandedFolders.wrappedValue.contains(node.id) { result.formUnion(ids(node.children)) }
            }
        }
        return ids(folderTree)
    }

    private func reconcileLibrarySelection() {
        controller.setLibrarySelection(selectedRowIDs.intersection(visibleRowIDs), in: context.disclosureScope)
    }

    private var folderTree: [TreeNode] {
        treeProjection.value.roots
    }

    var body: some View {
        VStack(spacing: 0) {
            ScholiumTriptychWorkspaceNavigator(
                selectedSlot: context.requestedWorkspaceSlot ?? context.currentWorkspaceSlot,
                noteCounts: context.workspaceNoteCounts,
                usesAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
                select: context.selectTriptychWorkspace
            )
            .padding(.horizontal, ScholiumSidebarLayout.edgeInset)
            .padding(.top, ScholiumSidebarLayout.edgeInset)

            libraryHeader
                .padding(.top, ScholiumSidebarLayout.sectionSpacing)
                .padding(.bottom, ScholiumSidebarLayout.controlGap)

            ScholiumLibraryTransition(slot: context.currentWorkspaceSlot) {
                sourceRegion
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: treeProjection.revision) { _, _ in reconcileLibrarySelection() }
        .onChange(of: context.disclosureScope) { _, _ in reconcileLibrarySelection() }
        .onChange(of: expandedFolders.wrappedValue) { _, _ in reconcileLibrarySelection() }
        .onChange(of: context.selectedDocumentPath) { _, path in
            guard selectedRowIDs.count <= 1 else { return }
            controller.setLibrarySelection(Set(path.map { [$0] } ?? []).intersection(visibleRowIDs), in: context.disclosureScope)
        }
        .overlay(alignment: .topLeading) {
            if PerformanceProbe.shared.measuresWarmLibraryLaunch,
                sourceListUsesOutlineView,
                !context.allNotes.isEmpty
            {
                PerformanceReadyBoundary(
                    generation: "\(treeProjection.revision):\(context.allNotes.count)"
                ) {
                    PerformanceProbe.shared.markLibraryReady(
                        noteCount: context.allNotes.count
                    )
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: Library source region

    @ViewBuilder
    private var sourceRegion: some View {
        if sourceListUsesOutlineView {
            VStack(spacing: 0) {
                if activeLibraryMenuFilterCount > 0 {
                    activeFilterStatus
                        .padding(.horizontal, ScholiumSidebarLayout.textInset)
                        .padding(.bottom, ScholiumGrid.Spacing.inlineControlGap)
                }

                SidebarOutlineSourceList(
                    roots: folderTree,
                    projectionRevision: treeProjection.revision,
                    locale: locale,
                    expandedFolders: expandedFolders,
                    expandedFolderIDs: expandedFolders.wrappedValue,
                    usesAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
                    selectedDocumentPath: context.selectedDocumentPath,
                    context: treeContext,
                    dropInventory: dropInventory,
                    revealRequest: controller.libraryRevealRequest,
                    disclosureScope: context.disclosureScope,
                    focusRequestGeneration: context.libraryFocusRequestGeneration,
                    requestedFocusPath: requestedRowFocusPath,
                    onConsumeRevealRequest: controller.consumeLibraryRevealRequest,
                    onFocusRequestHandled: { requestedRowFocusPath = nil },
                    onSelect: { context.openNote($0, .replaceCurrent) },
                    onMoveNoteDrop: { item, targetFolder in
                        performNoteDrop([item], into: targetFolder)
                    },
                    onMoveFolderDrop: { item, targetFolder in
                        performFolderDrop([item], into: targetFolder)
                    },
                    selectedRowIDs: selectedRowIDs,
                    onSelectionChange: { controller.setLibrarySelection($0, in: context.disclosureScope) },
                    onBatchMove: context.requestNoteBatchMove,
                    onBatchTrash: context.requestNoteBatchTrash,
                    onMoveNotesDrop: { performNoteDrop($0, into: $1) }
                )
                .accessibilityIdentifier("scholium.noteList")
            }
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if activeLibraryMenuFilterCount > 0 {
                        activeFilterStatus
                            .padding(.horizontal, ScholiumSidebarLayout.textInset)
                            .padding(.bottom, ScholiumGrid.Spacing.inlineControlGap)
                    }

                    sourceStateContent
                }
                .padding(.bottom, ScholiumSidebarLayout.textInset)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .contentShape(Rectangle())
            .contextMenu { rootCreationActions }
            .accessibilityIdentifier("scholium.noteList")
        }
    }

    private var sourceListUsesOutlineView: Bool {
        !controller.library.sourceIsLoading
            && controller.library.sourceError == nil
            && !folderTree.isEmpty
    }

    private var libraryHeader: some View {
        ScholiumSidebarHeader {
            Text("Library")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, ScholiumSidebarLayout.rowInset)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            ScholiumSidebarHeaderActions {
                libraryFilterMenu

                Menu {
                    rootCreationActions
                } label: {
                    ScholiumSidebarHeaderIcon(systemImage: ScholiumSidebarAction.add.symbol)
                }
                .scholiumSidebarHeaderControl()
                .disabled(!context.canMutateLibrary)
                .help("Create New")
                .accessibilityLabel("Create New")
                .accessibilityIdentifier("scholium.libraryCreate")
            }
        }
        .background {
            SidebarLibraryHeaderDropDestination(
                dropInventory: dropInventory,
                onMoveNoteDrop: { item, targetFolder in
                    performNoteDrop([item], into: targetFolder)
                },
                onMoveFolderDrop: { item, targetFolder in
                    performFolderDrop([item], into: targetFolder)
                },
                onMoveNotesDrop: { performNoteDrop($0, into: $1) }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.libraryHeader")
    }

    private var expandableFolderIDs: Set<String> {
        treeProjection.value.expandableFolderIDs
    }

    private var visibleExpandedFolderIDs: Set<String> {
        treeProjection.value.visibleExpandedFolderIDs(
            expandedFolders: expandedFolders.wrappedValue
        )
    }

    private func expandAllFolders() {
        expandedFolders.wrappedValue = expandableFolderIDs
    }

    private func collapseAllFolders() {
        expandedFolders.wrappedValue = []
    }

    @ViewBuilder
    private var rootCreationActions: some View {
        Button {
            context.createUntitledNote(nil)
        } label: {
            Label("New Note", systemImage: ScholiumSidebarAction.newNote.symbol)
        }
        .disabled(!context.canMutateLibrary)
        .accessibilityIdentifier("scholium.newNote")

        Button {
            context.createUntitledFolder(nil)
        } label: {
            Label("New Folder", systemImage: ScholiumSidebarAction.newFolder.symbol)
        }
        .disabled(!context.canMutateLibrary)
        .accessibilityIdentifier("scholium.newFolder")
    }

    private var activeFilterStatus: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text(
                activeLibraryMenuFilterCount == 1
                    ? "1 filter applied"
                    : "\(activeLibraryMenuFilterCount) filters applied"
            )
            .font(ScholiumTypography.interface(.small, emphasis: .medium))
            .scholiumForeground(.secondaryText)
            Spacer(minLength: 0)
            Button(action: clearAllFilters) {
                Text("Clear")
                    .scholiumContentControlInk(
                        resting: .secondaryText,
                        emphasized: .accent
                    )
            }
            .buttonStyle(.borderless)
            .scholiumActivationPointer()
            .scholiumContentControlPointerFeedback(
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
        }
        .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.libraryFilterStatus")
    }

    @ViewBuilder
    private var sourceStateContent: some View {
        if controller.library.sourceIsLoading {
            ScholiumSidebarState(Text("Loading Library…"), indicator: .progress)
                .accessibilityIdentifier("scholium.libraryLoading")
        } else if let error = controller.library.sourceError {
            ScholiumSidebarState(
                Text("Could Not Open Library"), detail: Text(error),
                indicator: .symbol("exclamationmark.triangle", role: .attention)
            ) {
                Button {
                    context.selectTriptychWorkspace(controller.library.workspaceSlot)
                } label: {
                    Text("Retry")
                        .scholiumContentControlInk(
                            resting: .secondaryText,
                            emphasized: .accent
                        )
                }
                .buttonStyle(.borderless)
                .scholiumActivationPointer()
                .scholiumContentControlPointerFeedback(
                    in: RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialControlCornerRadius,
                        style: .continuous
                    )
                )
            }
            .accessibilityIdentifier("scholium.libraryError")
        } else if folderTree.isEmpty {
            ScholiumSidebarState(
                activeLibraryMenuFilterCount > 0 ? Text("No Matching Notes") : Text("No Notes"),
                detail: activeLibraryMenuFilterCount > 0
                    ? Text("No notes match the current filters.") : Text("Create a Note to begin."),
                indicator: .symbol(activeLibraryMenuFilterCount > 0 ? "magnifyingglass" : "doc.text")
            )
            .accessibilityIdentifier("scholium.libraryEmpty")
        }
    }

    private var treeContext: SidebarTreeContext {
        SidebarTreeContext(
            currentVaultID: context.disclosureScope?.vaultID,
            currentVaultRole: context.currentVaultRole,
            selectedRowIDs: selectedRowIDs,
            selectedBatchTargets: selectedBatchTargets,
            requestNoteBatchMove: context.requestNoteBatchMove,
            requestNoteBatchTrash: context.requestNoteBatchTrash,
            openNote: context.openNote,
            canAddNoteToChat: context.canAddNoteToChat,
            addNoteToChat: context.addNoteToChat,
            requestFileOperation: { controller.requestFileOperation($0) },
            canMutateLibrary: context.canMutateLibrary,
            createUntitledNote: context.createUntitledNote,
            createUntitledFolder: context.createUntitledFolder,
            requestFolderFileOperation: context.requestFolderFileOperation,
            requestFolderSystemTrash: context.requestFolderSystemTrash,
            copyRelativePath: context.copyRelativePath,
            revealNote: context.revealNote,
            requestSystemTrash: context.requestSystemTrash,
            showError: context.showError
        )
    }

    private var dropInventory: SidebarTreeDropInventory {
        SidebarTreeDropInventory(
            currentVaultID: context.disclosureScope?.vaultID,
            sourceScope: controller.library.sourceScope,
            currentVaultRole: context.currentVaultRole,
            canMutate: context.canMutateLibrary,
            notes: context.allNotes,
            folderRelativePaths: Set(context.folders),
            pathComparisonPolicy: context.pathComparisonPolicy,
            pendingNoteMoves: context.pendingNoteMoves,
            pendingFolderMoves: context.pendingFolderMoves
        )
    }

    private func performNoteDrop(
        _ items: [SidebarNoteDragItem],
        into folderRelativePath: String?
    ) {
        guard let destinations = sidebarValidatedNotesDropDestinations(
            items: items,
            folderRelativePath: folderRelativePath,
            inventory: dropInventory
        ) else { return }
        if items.count > 1 {
            context.moveNotesDrop(items.map(\.mutationTarget), folderRelativePath)
        } else if let item = items.first, let destination = destinations.first {
            context.requestNoteDrop(item.mutationTarget, destination)
        }
    }

    private func performFolderDrop(
        _ items: [SidebarFolderDragItem],
        into folderRelativePath: String?
    ) {
        guard items.count == 1, let item = items.first,
            let destination = sidebarValidatedFolderDropDestination(
                item: item,
                folderRelativePath: folderRelativePath,
                inventory: dropInventory
            )
        else { return }
        context.requestFolderDrop(item.mutationTarget, destination)
    }

    // MARK: Library filters

    private var libraryFilterMenu: some View {
        SidebarLibraryFilterMenu(
            filters: controller.library.filters,
            sortOrder: controller.library.sortOrder,
            options: context.filterOptions,
            canChangeFolderDisclosure: !expandableFolderIDs.isEmpty,
            shouldCollapseFolders: !visibleExpandedFolderIDs.isEmpty,
            toggleAllFolders: {
                if visibleExpandedFolderIDs.isEmpty {
                    expandAllFolders()
                } else {
                    collapseAllFolders()
                }
            },
            replaceFilters: controller.replaceFilters,
            selectSortOrder: context.selectSortOrder,
            clearFilters: clearAllFilters,
            canMutateSelection: context.canMutateLibrary && !selectedBatchTargets.isEmpty,
            moveSelection: { context.requestNoteBatchMove(selectedBatchTargets) },
            trashSelection: { context.requestNoteBatchTrash(selectedBatchTargets) },
            showBatchOutcome: context.hasBatchOutcome ? context.showBatchOutcome : nil
        )
    }

    private var activeLibraryMenuFilterCount: Int {
        sidebarActiveLibraryFilterCount(controller.library.filters)
    }

    private func clearAllFilters() {
        controller.replaceFilters(DiscoveryFilterState())
    }
}
