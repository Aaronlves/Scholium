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
/// composition root. Scope, Location, filters, sorting, and disclosure remain
/// owned by `DiscoveryController`; no view retains a parallel Library tree.
struct SidebarContext {
    let triptychName: String
    let attentionTotal: Int?
    let workspaceNoteCounts: SidebarWorkspaceNoteCounts
    let attentionError: String?
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
    let canMutateLibrary: Bool
    let lifecycleMutationGeneration: UInt64
    let filterOptions: SidebarLibraryFilterOptions
    let attentionPopoverSession: AttentionPopoverSession?
    let openAttention: () -> Void
    let retryAttention: () -> Void
    let selectLocationScope: (NoteLocationScope) -> Void
    let openNote: (WindowDocumentLocation, WindowOpenDisposition) -> Void
    let selectTriptychWorkspace: (WorkspaceVaultSlot) -> Void
    let createUntitledNote: (String?) -> Void
    let createUntitledFolder: (String?) -> Void
    let moveNote: (NoteLifecycleTarget, String) async throws -> Void
    let moveFolder: (FolderLifecycleTarget, String) async throws -> Void
    let requestFolderLifecycle: (FolderLifecycleRequest) -> Void
    let moveFolderToTrash: (FolderLifecycleTarget) async throws -> Void
    let copyRelativePath: (String) -> Void
    let revealNote: (String) -> Void
    let setAside: (NoteLifecycleTarget) async throws -> Void
    let moveToTrash: (NoteLifecycleTarget) async throws -> Void
    let putBack: (NoteLifecycleTarget) async throws -> Void
    let deletePermanently: (NoteLifecycleTarget) async throws -> Void
    let revealCurrentVault: () -> Void
    let openSettings: () -> Void
    let selectSortOrder: (NoteSortOrder) -> Void
    let showError: (String) -> Void
}

struct SidebarView: View {
    @ObservedObject private var controller: DiscoveryController
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    let context: SidebarContext

    @FocusState private var locationPickerFocused: Bool
    @FocusState private var sourceListFocused: Bool
    @State private var pendingRemovalFocusPlans: [SidebarRemovalFocusPlan] = []
    @State private var requestedRowFocusPath: String?
    @State private var putBackDocumentsInProgress: Set<VaultQualifiedNoteID> = []
    @State private var noteDragMovesInProgress: Set<SidebarNoteDragID> = []
    @State private var folderDragMovesInProgress: Set<SidebarFolderDragID> = []
    @State private var sourceRevealProgress: CGFloat = 1
    @State private var sourceRevealTask: Task<Void, Never>?

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

    private var folderTree: [TreeNode] {
        treeProjection.value.roots
    }

    private var triptychAttentionState: SidebarTriptychAttentionState {
        if let total = context.attentionTotal {
            return total > 0 ? .active(count: total) : .zero
        }
        return context.attentionError == nil ? .checking : .unavailable
    }

    var body: some View {
        VStack(spacing: 0) {
            brandHeader
            ScholiumTriptychWorkspaceNavigator(
                selectedSlot: context.currentWorkspaceSlot,
                noteCounts: context.workspaceNoteCounts,
                select: context.selectTriptychWorkspace
            )
                .padding(.horizontal, ScholiumMetrics.Library.contentInset)
                .padding(.top, ScholiumMetrics.Library.workspaceNavigatorTopSpacing)

            locationHeader
                .padding(.top, ScholiumMetrics.Library.sectionSpacing)
                .padding(.bottom, ScholiumGrid.Spacing.labelAccessoryGap)

            sourceRegion
                .modifier(SidebarWorkspaceSourceReveal(
                    progress: sourceRevealProgress
                ))
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ScholiumColorRole.navigationSurfaceBackground.color)
        .onChange(of: context.currentWorkspaceSlot) { oldSlot, newSlot in
            guard oldSlot != nil, newSlot != nil, oldSlot != newSlot else { return }
            revealSourceRegion()
        }
        .onChange(of: reduceMotion) { _, shouldReduceMotion in
            guard shouldReduceMotion else { return }
            finishSourceRevealWithoutAnimation()
        }
        .onChange(of: context.libraryFocusRequestGeneration) { _, _ in
            sourceListFocused = true
        }
        .onChange(of: context.lifecycleMutationGeneration) { _, _ in
            restoreFocusAfterRemoval()
        }
        .onChange(of: context.allNotes.map(\.relativePath)) { _, _ in
            restoreFocusAfterRemoval()
        }
        .onDisappear {
            sourceRevealTask?.cancel()
        }
    }

    // MARK: Fixed identity and navigation

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Text("Scholium")
                .font(ScholiumTypography.Brand.wordmark)
                .scholiumForeground(.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("scholium.wordmark")

            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                triptychMenu
                Spacer(minLength: 0)
                SidebarTriptychAttentionEntry(
                    state: triptychAttentionState,
                    open: context.openAttention,
                    retry: context.retryAttention
                )
                .scholiumAttentionPopover(
                    anchor: .sidebar,
                    session: context.attentionPopoverSession
                )
            }
        }
        .padding(.horizontal, ScholiumMetrics.Library.contentInset)
        .padding(.top, ScholiumGrid.Spacing.sectionSeparation)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var triptychMenu: some View {
        Menu {
            Button(action: context.openSettings) {
                Label("Manage Triptychs…", systemImage: "folder.badge.gearshape")
            }
            Button(action: context.revealCurrentVault) {
                Label("Reveal Current Vault in Finder", systemImage: "folder")
            }
        } label: {
            Text(verbatim: context.triptychName)
                .font(ScholiumTypography.interface(.small, emphasis: .strong))
                .tracking(0.7)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minHeight: ScholiumMetrics.Accessibility.minimumCustomTarget)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .tint(ScholiumColorRole.primaryText.color)
        .fixedSize(horizontal: false, vertical: true)
        .help("Triptych management")
        .accessibilityLabel("Triptych: \(context.triptychName)")
        .accessibilityIdentifier("scholium.triptychManagement")
    }

    private func revealSourceRegion() {
        sourceRevealTask?.cancel()
        guard let animation = ScholiumMotion.triptychWorkspaceSourceReveal(
            reduceMotion: reduceMotion
        ) else {
            finishSourceRevealWithoutAnimation()
            return
        }
        withTransaction(Transaction(animation: nil)) {
            sourceRevealProgress = 0
        }
        sourceRevealTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(animation) {
                sourceRevealProgress = 1
            }
        }
    }

    private func finishSourceRevealWithoutAnimation() {
        sourceRevealTask?.cancel()
        withTransaction(Transaction(animation: nil)) {
            sourceRevealProgress = 1
        }
    }

    // MARK: Location and source region

    @ViewBuilder
    private var sourceRegion: some View {
        if sourceListUsesOutlineView {
            VStack(spacing: 0) {
                if controller.library.locationScope == .workspace,
                   activeLibraryMenuFilterCount > 0 {
                    activeFilterStatus
                        .padding(.horizontal, ScholiumMetrics.Library.contentInset)
                        .padding(.bottom, ScholiumGrid.Spacing.inlineControlGap)
                }

                SidebarOutlineSourceList(
                    roots: folderTree,
                    projectionRevision: treeProjection.revision,
                    locale: locale,
                    expandedFolders: expandedFolders,
                    expandedFolderIDs: expandedFolders.wrappedValue,
                    rowHeight: sidebarOutlineRowHeight(
                        usesAccessibilitySize: dynamicTypeSize.isAccessibilitySize
                    ),
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
                    putBackDocumentsInProgress: putBackDocumentsInProgress,
                    onMoveNoteDrop: { item, targetFolder in
                        performNoteDrop([item], into: targetFolder)
                    },
                    onMoveFolderDrop: { item, targetFolder in
                        performFolderDrop([item], into: targetFolder)
                    },
                    onPutBack: performPutBack,
                    onWillRemove: prepareRemovalFocus,
                    onMutationFailed: restoreRemovalFocusAfterFailure
                )
                .focused($sourceListFocused)
                .accessibilityIdentifier("scholium.noteList")
            }
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if controller.library.locationScope == .workspace,
                       activeLibraryMenuFilterCount > 0 {
                        activeFilterStatus
                            .padding(.horizontal, ScholiumMetrics.Library.contentInset)
                            .padding(.bottom, ScholiumGrid.Spacing.inlineControlGap)
                    }

                    sourceStateContent
                }
                .padding(.bottom, ScholiumMetrics.Library.contentInset)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .contentShape(Rectangle())
            .contextMenu {
                if controller.library.locationScope == .workspace {
                    rootCreationActions
                }
            }
            .focused($sourceListFocused)
            .accessibilityIdentifier("scholium.noteList")
        }
    }

    private var sourceListUsesOutlineView: Bool {
        !controller.library.locationIsLoading
            && controller.library.locationError == nil
            && !folderTree.isEmpty
    }

    private var locationHeader: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ScholiumLibraryLocationPicker(
                selection: locationSelection,
                focus: $locationPickerFocused
            )

            Spacer(minLength: 0)

            if controller.library.locationScope == .workspace {
                libraryFilterMenu
            }

            libraryDisclosureButton

            if controller.library.locationScope == .workspace {
                ScholiumEditorialIconControl(systemImage: "plus") { label in
                    Menu {
                        rootCreationActions
                    } label: {
                        label
                    }
                }
                .disabled(!context.canMutateLibrary)
                .help("Create New")
                .accessibilityLabel("Create New")
                .accessibilityIdentifier("scholium.libraryCreate")
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget
        )
        .padding(.horizontal, ScholiumMetrics.Library.contentInset)
        .background {
            SidebarLocationHeaderDropDestination(
                dropInventory: dropInventory,
                onMoveNoteDrop: { item, targetFolder in
                    performNoteDrop([item], into: targetFolder)
                },
                onMoveFolderDrop: { item, targetFolder in
                    performFolderDrop([item], into: targetFolder)
                }
            )
        }
    }

    private var libraryDisclosureButton: some View {
        let shouldCollapse = !visibleExpandedFolderIDs.isEmpty
        let title: LocalizedStringKey = shouldCollapse
            ? "Collapse All Folders"
            : "Expand All Folders"
        let symbol = shouldCollapse
            ? "rectangle.compress.vertical"
            : "rectangle.expand.vertical"

        return ScholiumEditorialIconControl(systemImage: symbol) { label in
            Button {
                if shouldCollapse {
                    collapseAllFolders()
                } else {
                    expandAllFolders()
                }
            } label: {
                label
            }
        }
        .disabled(expandableFolderIDs.isEmpty)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier("scholium.libraryDisclosureToggle")
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
            Label("New Note", systemImage: "doc.badge.plus")
        }
        .disabled(!context.canMutateLibrary)
        .accessibilityIdentifier("scholium.newNote")

        Button {
            context.createUntitledFolder(nil)
        } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
        }
        .disabled(!context.canMutateLibrary)
        .accessibilityIdentifier("scholium.newFolder")
    }

    private var locationSelection: Binding<NoteLocationScope> {
        Binding(
            get: { canonicalPickerLocation },
            set: { context.selectLocationScope($0) }
        )
    }

    private var canonicalPickerLocation: NoteLocationScope {
        controller.library.locationScope
    }

    private var activeFilterStatus: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text(activeLibraryMenuFilterCount == 1
                ? "1 filter applied"
                : "\(activeLibraryMenuFilterCount) filters applied")
                .font(ScholiumTypography.interface(.small, emphasis: .medium))
                .scholiumForeground(.secondaryText)
            Spacer(minLength: 0)
            Button("Clear", action: clearAllFilters)
                .buttonStyle(.link)
        }
        .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.libraryFilterStatus")
    }

    @ViewBuilder
    private var sourceStateContent: some View {
        if controller.library.locationIsLoading {
            ScholiumLibrarySourceState {
                ScholiumContentStateView(
                    title: Text("Loading \(locationName(canonicalPickerLocation))…"),
                    indicator: .progress,
                    placement: .leading,
                    density: .compact
                )
            }
            .accessibilityIdentifier("scholium.libraryLoading")
        } else if let error = controller.library.locationError {
            ScholiumLibrarySourceState {
                ScholiumContentStateView(
                    locationErrorTitle,
                    detail: Text(error),
                    indicator: .symbol("exclamationmark.triangle", role: .attention),
                    placement: .leading,
                    density: .compact
                ) {
                    Button("Retry") { context.selectLocationScope(canonicalPickerLocation) }
                }
            }
            .accessibilityIdentifier("scholium.libraryError")
        } else if folderTree.isEmpty {
            ScholiumLibrarySourceState {
                ScholiumContentStateView(
                    emptyLocationTitle,
                    detail: Text(emptyLocationDetail),
                    indicator: .symbol("doc.text"),
                    placement: .leading,
                    density: .compact
                )
            }
            .accessibilityIdentifier("scholium.libraryEmpty")
        } else {
            EmptyView()
        }
    }

    private var treeContext: SidebarTreeContext {
        SidebarTreeContext(
            currentVaultID: context.disclosureScope?.vaultID,
            currentVaultRole: context.currentVaultRole,
            locationScope: controller.library.locationScope,
            openNote: context.openNote,
            requestLifecycle: { controller.requestLifecycle($0) },
            canMutateLibrary: context.canMutateLibrary,
            createUntitledNote: context.createUntitledNote,
            createUntitledFolder: context.createUntitledFolder,
            requestFolderLifecycle: context.requestFolderLifecycle,
            moveFolderToTrash: context.moveFolderToTrash,
            copyRelativePath: context.copyRelativePath,
            revealNote: context.revealNote,
            setAside: context.setAside,
            moveToTrash: context.moveToTrash,
            deletePermanently: context.deletePermanently,
            showError: context.showError
        )
    }

    private var dropInventory: SidebarTreeDropInventory {
        SidebarTreeDropInventory(
            currentVaultID: context.disclosureScope?.vaultID,
            locationScope: controller.library.locationScope,
            currentVaultRole: context.currentVaultRole,
            canMutate: context.canMutateLibrary,
            notes: context.allNotes,
            folderRelativePaths: Set(context.folders),
            pathComparisonPolicy: context.pathComparisonPolicy,
            pendingNoteMoves: noteDragMovesInProgress,
            pendingFolderMoves: folderDragMovesInProgress
        )
    }

    private func performNoteDrop(
        _ items: [SidebarNoteDragItem],
        into folderRelativePath: String?
    ) {
        guard items.count == 1, let item = items.first else {
            context.showError("Move one note at a time.")
            return
        }
        guard let destination = sidebarValidatedNoteDropDestination(
            item: item,
            folderRelativePath: folderRelativePath,
            inventory: dropInventory
        ) else { return }
        let target = item.lifecycleTarget
        noteDragMovesInProgress.insert(item.id)
        Task { @MainActor in
            defer { noteDragMovesInProgress.remove(item.id) }
            do {
                try await context.moveNote(target, destination)
            } catch {
                context.showError("Could not move this note. \(error.localizedDescription)")
            }
        }
    }

    private func performFolderDrop(
        _ items: [SidebarFolderDragItem],
        into folderRelativePath: String?
    ) {
        guard items.count == 1, let item = items.first else {
            context.showError("Move one folder at a time.")
            return
        }
        guard let destination = sidebarValidatedFolderDropDestination(
            item: item,
            folderRelativePath: folderRelativePath,
            inventory: dropInventory
        ) else { return }
        let target = item.lifecycleTarget
        folderDragMovesInProgress.insert(item.id)
        Task { @MainActor in
            defer { folderDragMovesInProgress.remove(item.id) }
            do {
                try await context.moveFolder(target, destination)
            } catch {
                context.showError("Could not move this folder. \(error.localizedDescription)")
            }
        }
    }

    private func locationName(_ location: NoteLocationScope) -> String {
        switch location {
        case .workspace: ScholiumL10n.string("Library", locale: locale)
        case .setAside: ScholiumL10n.string("Set Aside", locale: locale)
        case .trash: ScholiumL10n.string("Trash", locale: locale)
        }
    }

    private var locationErrorTitle: LocalizedStringResource {
        switch canonicalPickerLocation {
        case .workspace: "Could Not Open Library"
        case .setAside: "Could Not Open Set Aside"
        case .trash: "Could Not Open Trash"
        }
    }

    private var emptyLocationTitle: LocalizedStringResource {
        switch controller.library.locationScope {
        case .workspace: "No Notes"
        case .setAside: "No Set Aside Notes"
        case .trash: "No Notes in Trash"
        }
    }

    private var emptyLocationDetail: String {
        switch controller.library.locationScope {
        case .workspace: "Create a Note or choose another Scope."
        case .setAside: "Notes you set aside appear here until you put them back."
        case .trash: "Notes moved to Trash appear here until you put them back or delete them permanently."
        }
    }

    // MARK: Lifecycle focus

    private var visibleNotePaths: [String] {
        treeProjection.value.visibleNotePaths(
            expandedFolders: expandedFolders.wrappedValue
        )
    }

    private func prepareRemovalFocus(_ note: WindowDocumentLocation) {
        guard let originDocumentID = note.workspaceSnapshot?.id else { return }
        let plan = sidebarRemovalFocusPlan(
            originDocumentID: originDocumentID,
            originPath: note.relativePath,
            disclosureScope: context.disclosureScope,
            visibleNotePaths: visibleNotePaths
        )
        pendingRemovalFocusPlans.removeAll {
            $0.originDocumentID == originDocumentID
        }
        pendingRemovalFocusPlans.append(plan)
    }

    private func restoreFocusAfterRemoval() {
        guard !pendingRemovalFocusPlans.isEmpty else { return }
        let remainingDocumentIDs = Set(context.allNotes.compactMap {
            $0.workspaceSnapshot?.id
        })
        let reconciliation = sidebarRemovalFocusAfterCompletions(
            plans: pendingRemovalFocusPlans,
            disclosureScope: context.disclosureScope,
            remainingDocumentIDs: remainingDocumentIDs,
            remainingVisibleNotePaths: visibleNotePaths
        )
        pendingRemovalFocusPlans = reconciliation.pendingPlans
        applyRemovalFocusDestination(reconciliation.destination)
    }

    private func performPutBack(_ note: WindowDocumentLocation) {
        guard let target = NoteLifecycleTarget(note) else {
            context.showError("This note cannot be put back until its identity is resolved.")
            requestedRowFocusPath = note.relativePath
            return
        }
        guard !putBackDocumentsInProgress.contains(target.documentID) else { return }
        prepareRemovalFocus(note)
        putBackDocumentsInProgress.insert(target.documentID)
        Task { @MainActor in
            defer {
                putBackDocumentsInProgress.remove(target.documentID)
            }
            do {
                try await context.putBack(target)
            } catch {
                restoreRemovalFocusAfterFailure(note)
                context.showError(
                    "Could not put this note back. \(error.localizedDescription)"
                )
            }
        }
    }

    private func restoreRemovalFocusAfterFailure(
        _ note: WindowDocumentLocation
    ) {
        guard let originDocumentID = note.workspaceSnapshot?.id else { return }
        let reconciliation = sidebarRemovalFocusAfterFailure(
            plans: pendingRemovalFocusPlans,
            originDocumentID: originDocumentID,
            originPath: note.relativePath,
            disclosureScope: context.disclosureScope
        )
        pendingRemovalFocusPlans = reconciliation.pendingPlans
        applyRemovalFocusDestination(reconciliation.destination)
    }

    private func applyRemovalFocusDestination(
        _ destination: SidebarRemovalFocusDestination?
    ) {
        switch destination {
        case .row(let path): requestedRowFocusPath = path
        case .locationPicker: locationPickerFocused = true
        case nil: break
        }
    }

    // MARK: Library filters

    private var libraryFilterMenu: some View {
        SidebarLibraryFilterMenu(
            filters: controller.library.filters,
            sortOrder: controller.library.sortOrder,
            options: context.filterOptions,
            replaceFilters: controller.replaceFilters,
            selectSortOrder: context.selectSortOrder,
            clearFilters: clearAllFilters
        )
    }

    private var activeLibraryMenuFilterCount: Int {
        sidebarActiveLibraryFilterCount(controller.library.filters)
    }

    private func clearAllFilters() {
        controller.replaceFilters(DiscoveryFilterState())
        if controller.library.sortOrder == .debateImportanceDescending {
            context.selectSortOrder(.modifiedNewest)
        }
    }
}

private struct SidebarWorkspaceSourceReveal: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(Double(progress))
            .offset(
                y: -(1 - progress) * ScholiumMotion.triptychWorkspaceSourceOffset
            )
    }
}
