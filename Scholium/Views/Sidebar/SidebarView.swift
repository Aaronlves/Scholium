import ScholiumContracts
import SwiftUI

// MARK: - Sidebar composition

/// Immutable Source List projection and exact window actions supplied by the
/// composition root. Scope, Location, filters, sorting, and disclosure remain
/// owned by `DiscoveryController`; no view retains a parallel Library tree.
struct SidebarContext {
    let triptychName: String
    let attentionCounts: AttentionScopeCounts?
    let attentionError: String?
    let filteredNotes: [WindowDocumentLocation]
    let allNotes: [WindowDocumentLocation]
    let folders: [String]
    let currentVaultID: UUID?
    let disclosureScope: LibraryDisclosureScope?
    let selectedDocumentPath: String?
    let libraryFocusRequestGeneration: UInt64
    let currentVaultRole: VaultRole
    let currentWorkspaceSlot: WorkspaceVaultSlot?
    let noteLifecycleRequest: NoteLifecycleRequest?
    let canCreateNote: Bool
    let lifecycleMutationGeneration: UInt64
    let catalogIsAvailable: Bool
    let graphIsAvailable: Bool
    let tags: [String]
    let authors: [String]
    let years: [Int]
    let propertyKeys: [String]
    let propertyValues: [String: [String]]
    let resolvedIdentityPaths: Set<String>
    let bibliographyController: RecommendedBibliographyController
    let attentionPopoverSession: AttentionPopoverSession?
    let notesAreOrdered: (WindowDocumentLocation, WindowDocumentLocation) -> Bool
    let openAttention: () -> Void
    let retryAttention: () -> Void
    let selectLocationScope: (NoteLocationScope) -> Void
    let openNote: (WindowDocumentLocation, WindowOpenDisposition) -> Void
    let selectWorkspaceVault: (WorkspaceVaultSlot) -> Void
    let prepareLifecycle: (LifecycleLocationItem) -> Void
    let clearPreparedLifecycle: (String) -> Void
    let createUntitledNote: (String?) -> Void
    let createUntitledFolder: (String?) -> Void
    let requestFolderLifecycle: (FolderLifecycleRequest) -> Void
    let moveFolderToTrash: (String) async throws -> Void
    let copyRelativePath: (String) -> Void
    let revealNote: (String) -> Void
    let setAside: (String) async throws -> Void
    let moveToTrash: (String) async throws -> Void
    let deletePermanently: (String) async throws -> Void
    let openRecommendedAnalysis: (VaultQualifiedNoteID) -> Void
    let copyRecommendedBibliographyText: (String) -> Void
    let repairRecommendedBibliographyMethod: () -> Void
    let revealCurrentVault: () -> Void
    let openSettings: () -> Void
    let selectSortOrder: (NoteSortOrder) -> Void
    let showError: (String) -> Void
}

private struct SidebarRemovalFocusPlan: Equatable {
    let originPath: String
    let successorPath: String?
}

struct SidebarView: View {
    @ObservedObject private var controller: DiscoveryController
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.locale) private var locale
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    let context: SidebarContext

    @FocusState private var locationPickerFocused: Bool
    @FocusState private var attentionAlertFocused: Bool
    @FocusState private var sourceListFocused: Bool
    @State private var preparedLifecyclePath: String?
    @State private var pendingRemovalFocusPlan: SidebarRemovalFocusPlan?
    @State private var requestedRowFocusPath: String?
    @State private var pinnedRootFolderIDs: Set<String> = []

    init(controller: DiscoveryController, context: SidebarContext) {
        self.controller = controller
        self.context = context
    }

    private var expandedFolders: Binding<Set<String>> {
        Binding(
            get: { controller.expandedFolders(in: context.disclosureScope) },
            set: { controller.setExpandedFolders($0, in: context.disclosureScope) }
        )
    }

    private var folderTree: [TreeNode] {
        if controller.library.locationScope != .workspace {
            return context.filteredNotes.map {
                TreeNode(
                    id: $0.relativePath,
                    name: $0.displayName,
                    isFolder: false,
                    note: $0,
                    folderRelativePath: nil,
                    children: [],
                    depth: 0
                )
            }
        }
        return buildTree(
            from: context.filteredNotes,
            folderRelativePaths: context.folders,
            notesAreOrdered: context.notesAreOrdered
        )
    }

    private var displayedAttentionCount: Int? {
        guard let slot = context.currentWorkspaceSlot else { return 0 }
        return context.attentionCounts?.count(for: slot)
    }

    private var attentionAlertState: SidebarAttentionAlertState? {
        if let displayedAttentionCount {
            return displayedAttentionCount > 0
                ? .active(count: displayedAttentionCount)
                : nil
        }
        return context.attentionError == nil ? .checking : .unavailable
    }

    /// The Source List is projected once into top-level sections plus a flat
    /// sequence of currently visible descendants. Sticky handoff, keyboard
    /// order, lifecycle focus recovery, and accessibility therefore consume
    /// the same ordering instead of recursively composing nested view trees.
    private var sourceSections: [SidebarSourceSection] {
        sidebarSourceSections(
            from: folderTree,
            expandedFolders: expandedFolders.wrappedValue
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            brandHeader
            scopeIndex
                .padding(.horizontal, ScholiumMetrics.Library.contentInset)
                .padding(.top, ScholiumMetrics.Library.scopeTopSpacing)
            Group {
                if let attentionAlertState {
                    SidebarAttentionAlert(
                        state: attentionAlertState,
                        open: context.openAttention,
                        retry: context.retryAttention
                    )
                    .scholiumAttentionPopover(
                        anchor: .sidebar,
                        session: context.attentionPopoverSession
                    )
                    .focused($attentionAlertFocused)
                    .padding(.horizontal, ScholiumMetrics.Library.contentInset)
                    .padding(.top, ScholiumMetrics.Library.sectionSpacing)
                    .transition(.opacity)
                }
            }
            .animation(
                ScholiumMotion.sidebarAttentionPresentation(reduceMotion: reduceMotion),
                value: attentionAlertState
            )

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    locationHeader
                        .padding(.horizontal, ScholiumMetrics.Library.contentInset)
                        .padding(.top, ScholiumMetrics.Library.sectionSpacing)
                        .padding(.bottom, ScholiumGrid.Spacing.labelAccessoryGap)

                    if controller.library.locationScope == .workspace,
                       activeLibraryMenuFilterCount > 0 {
                        activeFilterStatus
                            .padding(.horizontal, ScholiumMetrics.Library.contentInset)
                            .padding(.bottom, ScholiumGrid.Spacing.inlineControlGap)
                    }

                    sourceContent
                }
                .padding(.bottom, ScholiumMetrics.Library.contentInset)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .coordinateSpace(name: SidebarRootHeaderOffsetPreference.coordinateSpace)
            .scrollContentBackground(.hidden)
            .focused($sourceListFocused)
            .onPreferenceChange(SidebarRootHeaderOffsetPreference.self) { offsets in
                pinnedRootFolderIDs = Set(offsets.compactMap { id, minY in
                    let rowHeight = ScholiumMetrics.Library.hierarchyRowHeight
                    return minY <= 0.5 && minY > -rowHeight ? id : nil
                })
            }
            .accessibilityIdentifier("scholium.noteList")

            recommendedBibliographyUtility
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ScholiumColorRole.navigationSurfaceBackground.color)
        .onChange(of: attentionAlertState) { oldState, newState in
            guard oldState != nil, newState == nil, attentionAlertFocused else { return }
            locationPickerFocused = true
        }
        .onChange(of: context.libraryFocusRequestGeneration) { _, _ in
            sourceListFocused = true
        }
        .onChange(of: context.noteLifecycleRequest) { _, request in
            guard request == nil, let path = preparedLifecyclePath else { return }
            context.clearPreparedLifecycle(path)
            preparedLifecyclePath = nil
        }
        .onChange(of: context.lifecycleMutationGeneration) { _, _ in
            restoreFocusAfterRemoval()
        }
        .onChange(of: context.allNotes.map(\.relativePath)) { _, _ in
            restoreFocusAfterRemoval()
        }
    }

    // MARK: Fixed identity and navigation

    /// Triptych-wide agent recommendations are a sibling of Library
    /// navigation, never the tail of the active Scope/Location Source List.
    /// The intrinsic-height band stays fixed while the source region scrolls.
    private var recommendedBibliographyUtility: some View {
        SidebarRecommendedBibliographySection(
            controller: context.bibliographyController,
            openAnalysis: context.openRecommendedAnalysis,
            copyText: context.copyRecommendedBibliographyText,
            repairMethod: context.repairRecommendedBibliographyMethod
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScholiumColorRole.navigationSurfaceBackground.color)
        .overlay(alignment: .top) {
            ScholiumStructuralRule()
        }
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Text("Scholium")
                .font(ScholiumInterfaceTypography.identity)
                .foregroundStyle(ScholiumColorRole.primaryText.color)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("scholium.wordmark")

            Menu {
                Button(action: context.openSettings) {
                    Label("Manage Triptychs…", systemImage: "folder.badge.gearshape")
                }
                Button(action: context.revealCurrentVault) {
                    Label("Reveal Current Vault in Finder", systemImage: "folder")
                }
            } label: {
                Text(verbatim: context.triptychName)
                    .font(ScholiumInterfaceTypography.editorialLabel)
                    .tracking(0.7)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minHeight: ScholiumMetrics.Accessibility.minimumCustomTarget)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)
            .help("Triptych management")
            .accessibilityLabel("Triptych: \(context.triptychName)")
            .accessibilityIdentifier("scholium.triptychManagement")
        }
        .padding(.horizontal, ScholiumMetrics.Library.contentInset)
        .padding(.top, ScholiumGrid.Spacing.sectionSeparation)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scopeIndex: some View {
        HStack(spacing: 0) {
            ForEach(WorkspaceVaultSlot.allCases) { slot in
                Button {
                    guard !isCurrent(slot) else { return }
                    context.selectWorkspaceVault(slot)
                } label: {
                    Text(ScholiumL10n.dynamicString(slot.displayName))
                        .font(.system(size: 12, weight: isCurrent(slot) ? .semibold : .regular))
                        .foregroundStyle(ScholiumColorRole.primaryText.color)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
                        .overlay(alignment: .bottom) {
                            ScholiumEditorialIndexUnderline(
                                isSelected: isCurrent(slot),
                                width: ScholiumMetrics.Library.scopeIndicatorWidth,
                                height: ScholiumMetrics.Library.scopeIndicatorHeight
                            )
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isCurrent(slot) ? .isSelected : [])
                .accessibilityIdentifier("scholium.vault.\(slot.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Triptych Scope")
        .onKeyPress(.leftArrow) {
            moveScope(readingDirectionDelta: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            moveScope(readingDirectionDelta: 1)
            return .handled
        }
    }

    private func isCurrent(_ slot: WorkspaceVaultSlot) -> Bool {
        context.currentWorkspaceSlot == slot
    }

    private func moveScope(readingDirectionDelta delta: Int) {
        guard let current = context.currentWorkspaceSlot,
              let index = WorkspaceVaultSlot.allCases.firstIndex(of: current) else { return }
        let visualDelta = layoutDirection == .rightToLeft ? -delta : delta
        let target = min(
            max(index + visualDelta, WorkspaceVaultSlot.allCases.startIndex),
            WorkspaceVaultSlot.allCases.index(before: WorkspaceVaultSlot.allCases.endIndex)
        )
        guard target != index else { return }
        context.selectWorkspaceVault(WorkspaceVaultSlot.allCases[target])
    }

    // MARK: Location and source region

    private var locationHeader: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ScholiumLibraryLocationPicker(selection: locationSelection)
            .focused($locationPickerFocused)

            Spacer(minLength: 0)

            if controller.library.locationScope == .workspace {
                libraryFilterMenu
                Button {
                    context.createUntitledNote(nil)
                } label: {
                    Label("New Note", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .frame(
                            width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                            height: ScholiumMetrics.Accessibility.preferredCustomTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!context.canCreateNote)
                .help("New Note")
                .accessibilityIdentifier("scholium.newNote")
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget
        )
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
                .font(ScholiumInterfaceTypography.metadata)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
            Spacer(minLength: 0)
            Button("Clear", action: clearAllFilters)
                .buttonStyle(.link)
        }
        .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.libraryFilterStatus")
    }

    @ViewBuilder
    private var sourceContent: some View {
        if controller.library.locationIsLoading {
            ScholiumLibrarySourceState {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    ProgressView().controlSize(.small)
                    Text("Loading \(locationName(canonicalPickerLocation))…")
                        .font(ScholiumInterfaceTypography.metadata)
                }
            }
            .accessibilityIdentifier("scholium.libraryLoading")
        } else if let error = controller.library.locationError {
            ScholiumLibrarySourceState {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    Label {
                        Text(locationErrorTitle)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                        .font(ScholiumInterfaceTypography.rowTitle)
                    Text(error)
                        .font(ScholiumInterfaceTypography.metadata)
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Retry") { context.selectLocationScope(canonicalPickerLocation) }
                }
            }
            .accessibilityIdentifier("scholium.libraryError")
        } else if folderTree.isEmpty {
            ScholiumLibrarySourceState {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Text(emptyLocationTitle)
                        .font(ScholiumInterfaceTypography.rowTitle)
                    Text(emptyLocationDetail)
                        .font(ScholiumInterfaceTypography.metadata)
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("scholium.libraryEmpty")
        } else {
            ForEach(sourceSections) { section in
                if let root = section.header {
                    Section {
                        ForEach(section.rows) { row in
                            SidebarTreeNodeRow(
                                node: row,
                                expandedFolders: expandedFolders,
                                selectedDocumentPath: context.selectedDocumentPath,
                                context: treeContext,
                                isPinnedRoot: false,
                                requestedFocusPath: requestedRowFocusPath,
                                onFocusRequestHandled: { requestedRowFocusPath = nil },
                                onSelect: { context.openNote($0, .replaceCurrent) },
                                onPutBack: preparePutBack,
                                onWillRemove: prepareRemovalFocus,
                                onMutationFailed: { requestedRowFocusPath = $0.relativePath }
                            )
                        }
                    } header: {
                        treeRow(root, isPinnedRoot: pinnedRootFolderIDs.contains(root.id))
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: SidebarRootHeaderOffsetPreference.self,
                                        value: [
                                            root.id: proxy.frame(
                                                in: .named(SidebarRootHeaderOffsetPreference.coordinateSpace)
                                            ).minY,
                                        ]
                                    )
                                }
                            )
                            .background(ScholiumColorRole.navigationSurfaceBackground.color)
                    }
                } else {
                    ForEach(section.rows) { row in
                        treeRow(row, isPinnedRoot: false)
                    }
                }
            }
        }
    }

    private func treeRow(_ node: TreeNode, isPinnedRoot: Bool) -> some View {
        SidebarTreeNodeRow(
            node: node,
            expandedFolders: expandedFolders,
            selectedDocumentPath: context.selectedDocumentPath,
            context: treeContext,
            isPinnedRoot: isPinnedRoot,
            requestedFocusPath: requestedRowFocusPath,
            onFocusRequestHandled: { requestedRowFocusPath = nil },
            onSelect: { context.openNote($0, .replaceCurrent) },
            onPutBack: preparePutBack,
            onWillRemove: prepareRemovalFocus,
            onMutationFailed: { requestedRowFocusPath = $0.relativePath }
        )
    }

    private var treeContext: SidebarTreeContext {
        SidebarTreeContext(
            currentVaultID: context.currentVaultID,
            currentVaultRole: context.currentVaultRole,
            locationScope: controller.library.locationScope,
            resolvedIdentityPaths: context.resolvedIdentityPaths,
            openNote: context.openNote,
            requestLifecycle: { controller.requestLifecycle($0) },
            canCreateNote: context.canCreateNote,
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

    private var emptyLocationTitle: String {
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
        sourceSections.flatMap(\.rows).compactMap { $0.note?.relativePath }
    }

    private func prepareRemovalFocus(_ note: WindowDocumentLocation) {
        let paths = visibleNotePaths
        guard let index = paths.firstIndex(of: note.relativePath) else {
            pendingRemovalFocusPlan = SidebarRemovalFocusPlan(
                originPath: note.relativePath,
                successorPath: nil
            )
            return
        }
        let successor: String? = if paths.indices.contains(index + 1) {
            paths[index + 1]
        } else if index > paths.startIndex {
            paths[index - 1]
        } else {
            nil
        }
        pendingRemovalFocusPlan = SidebarRemovalFocusPlan(
            originPath: note.relativePath,
            successorPath: successor
        )
    }

    private func restoreFocusAfterRemoval() {
        guard let plan = pendingRemovalFocusPlan else { return }
        let remaining = Set(context.allNotes.map(\.relativePath))
        guard !remaining.contains(plan.originPath) else { return }
        pendingRemovalFocusPlan = nil
        if let successor = plan.successorPath, remaining.contains(successor) {
            requestedRowFocusPath = successor
        } else if let first = visibleNotePaths.first {
            requestedRowFocusPath = first
        } else {
            locationPickerFocused = true
        }
    }

    private func preparePutBack(_ note: WindowDocumentLocation) {
        prepareRemovalFocus(note)
        guard let snapshot = note.workspaceSnapshot,
              let noteID = snapshot.stableIdentity.resolvedID else {
            context.showError("This note cannot be put back until its identity is resolved.")
            requestedRowFocusPath = note.relativePath
            return
        }
        let item = LifecycleLocationItem(
            note: note,
            revision: snapshot.fingerprint,
            noteID: noteID
        )
        context.prepareLifecycle(item)
        preparedLifecyclePath = note.relativePath
        controller.requestLifecycle(.putBack(note.relativePath))
    }

    // MARK: Library filters

    private var libraryFilterMenu: some View {
        Menu {
            Section("Integrity") {
                Toggle("Needs Attention", isOn: filterBinding(\.needsAttention))
                    .disabled(!context.catalogIsAvailable)
                Toggle("Explicit Connections", isOn: filterBinding(\.hasExplicitConnections))
                    .disabled(!context.graphIsAvailable)
                Toggle("Malformed Metadata", isOn: filterBinding(\.hasMalformedMetadata))
                    .disabled(!context.catalogIsAvailable)
            }
            Section("Metadata") {
                Menu("Tag") {
                    Button("All Tags") { updateFilters { $0.tag = nil } }
                    Divider()
                    ForEach(context.tags, id: \.self) { tag in
                        filterChoice(tag, selected: controller.library.filters.tag == tag) {
                            updateFilters { $0.tag = tag }
                        }
                    }
                }
                .disabled(context.tags.isEmpty)
                if !context.authors.isEmpty {
                    Menu("Author") {
                        Button("Any Author") { updateFilters { $0.author = nil } }
                        Divider()
                        ForEach(context.authors, id: \.self) { author in
                            filterChoice(author, selected: controller.library.filters.author == author) {
                                updateFilters { $0.author = author }
                            }
                        }
                    }
                }
                if !context.years.isEmpty {
                    Menu("Year") {
                        Button("Any Year") { updateFilters { $0.year = nil } }
                        Divider()
                        ForEach(context.years, id: \.self) { year in
                            let title = year.formatted(.number.grouping(.never))
                            filterChoice(title, selected: controller.library.filters.year == year) {
                                updateFilters { $0.year = year }
                            }
                        }
                    }
                }
            }
            if !context.propertyKeys.isEmpty {
                Section("Properties") {
                    Button("Any Property") {
                        updateFilters {
                            $0.propertyKey = nil
                            $0.propertyValue = nil
                        }
                    }
                    ForEach(context.propertyKeys, id: \.self) { key in
                        Menu(propertyLabel(key)) {
                            ForEach(context.propertyValues[key] ?? [], id: \.self) { value in
                                filterChoice(
                                    value,
                                    selected: controller.library.filters.propertyKey == key
                                        && controller.library.filters.propertyValue == value
                                ) {
                                    updateFilters {
                                        $0.propertyKey = key
                                        $0.propertyValue = value
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Section("Order") {
                Menu("Sort") {
                    ForEach(NoteSortOrder.allCases) { order in
                        filterChoice(order.title, selected: controller.library.sortOrder == order) {
                            context.selectSortOrder(order)
                        }
                        .disabled(order == .debateImportanceDescending && !hasScopedDebateImportanceFilter)
                    }
                }
            }
            if activeLibraryMenuFilterCount > 0 {
                Section("Actions") {
                    Button("Clear All Filters", action: clearAllFilters)
                }
            }
        } label: {
            Label(
                "Filter",
                systemImage: activeLibraryMenuFilterCount == 0
                    ? "line.3.horizontal.decrease"
                    : "line.3.horizontal.decrease.circle.fill"
            )
            .labelStyle(.iconOnly)
            .frame(
                width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                height: ScholiumMetrics.Accessibility.preferredCustomTarget
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(activeLibraryMenuFilterCount == 0
            ? "Filter and sort Library notes"
            : "\(activeLibraryMenuFilterCount) Library filters active")
        .accessibilityLabel("Library filters")
        .accessibilityValue(activeLibraryMenuFilterCount == 0
            ? "No filters active"
            : "\(activeLibraryMenuFilterCount) filters active")
        .accessibilityIdentifier("scholium.libraryFilters")
    }

    @ViewBuilder
    private func filterChoice(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
    }

    private var activeLibraryMenuFilterCount: Int {
        let filters = controller.library.filters
        return [
            filters.needsAttention,
            filters.hasExplicitConnections,
            filters.hasMalformedMetadata,
            filters.tag != nil,
            filters.author != nil,
            filters.year != nil,
            filters.propertyKey != nil && filters.propertyValue != nil,
        ].count(where: { $0 })
    }

    private var hasScopedDebateImportanceFilter: Bool {
        controller.library.filters.propertyKey == "debate_importance_scope"
            && controller.library.filters.propertyValue?
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func filterBinding<Value>(
        _ keyPath: WritableKeyPath<DiscoveryFilterState, Value>
    ) -> Binding<Value> {
        Binding(
            get: { controller.library.filters[keyPath: keyPath] },
            set: { value in updateFilters { $0[keyPath: keyPath] = value } }
        )
    }

    private func updateFilters(_ update: (inout DiscoveryFilterState) -> Void) {
        var filters = controller.library.filters
        update(&filters)
        controller.replaceFilters(filters)
    }

    private func clearAllFilters() {
        controller.replaceFilters(DiscoveryFilterState())
        if controller.library.sortOrder == .debateImportanceDescending {
            context.selectSortOrder(.modifiedNewest)
        }
    }

    private func propertyLabel(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - Sticky root measurement

private struct SidebarRootHeaderOffsetPreference: PreferenceKey {
    static let coordinateSpace = "scholium.librarySourceScroll"
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Tree model

struct TreeNode: Identifiable {
    let id: String
    let name: String
    let isFolder: Bool
    let note: WindowDocumentLocation?
    let folderRelativePath: String?
    let children: [TreeNode]
    let depth: Int

    var folderIDs: Set<String> {
        guard isFolder else { return [] }
        return children.reduce(into: Set([id])) { $0.formUnion($1.folderIDs) }
    }
}

/// One top-level Source List block. Real root Folders become sticky Section
/// headers; root Notes remain ordinary rows. Descendants are already flattened
/// in visual, keyboard, and accessibility order.
struct SidebarSourceSection: Identifiable {
    let id: String
    let header: TreeNode?
    let rows: [TreeNode]
}

func sidebarSourceSections(
    from roots: [TreeNode],
    expandedFolders: Set<String>
) -> [SidebarSourceSection] {
    roots.map { root in
        guard root.isFolder else {
            return SidebarSourceSection(
                id: "row:\(root.id)",
                header: nil,
                rows: [root]
            )
        }
        return SidebarSourceSection(
            id: "section:\(root.id)",
            header: root,
            rows: expandedFolders.contains(root.id)
                ? flattenedVisibleDescendants(
                    of: root,
                    expandedFolders: expandedFolders
                )
                : []
        )
    }
}

private func flattenedVisibleDescendants(
    of folder: TreeNode,
    expandedFolders: Set<String>
) -> [TreeNode] {
    folder.children.flatMap { child in
        guard child.isFolder, expandedFolders.contains(child.id) else {
            return [child]
        }
        return [child] + flattenedVisibleDescendants(
            of: child,
            expandedFolders: expandedFolders
        )
    }
}

func buildTree(
    from notes: [WindowDocumentLocation],
    folderRelativePaths folders: [String] = [],
    notesAreOrdered: (WindowDocumentLocation, WindowDocumentLocation) -> Bool
) -> [TreeNode] {
    var roots: [TreeNode] = []
    var folderMap: [String: [WindowDocumentLocation]] = [:]
    var actualFolderPaths: [String: String] = [:]
    var ambiguousFolderPaths: Set<String> = []

    func registerFolder(actualPath: String) {
        let visiblePath = stripKBRootFolder(actualPath)
        guard !visiblePath.isEmpty else { return }
        let visibleParts = visiblePath.split(separator: "/").map(String.init)
        let actualParts = actualPath.split(separator: "/").map(String.init)
        guard actualParts.count >= visibleParts.count else { return }
        let hiddenPrefixCount = actualParts.count - visibleParts.count
        for count in 1...visibleParts.count {
            let visibleAncestor = visibleParts.prefix(count).joined(separator: "/")
            let actualAncestor = actualParts.prefix(hiddenPrefixCount + count).joined(separator: "/")
            folderMap[visibleAncestor, default: []] = folderMap[visibleAncestor, default: []]
            if let existing = actualFolderPaths[visibleAncestor], existing != actualAncestor {
                ambiguousFolderPaths.insert(visibleAncestor)
            } else {
                actualFolderPaths[visibleAncestor] = actualAncestor
            }
        }
    }

    folders.forEach { registerFolder(actualPath: $0) }
    for note in notes {
        let parts = stripKBRoot(note.relativePath).split(separator: "/").map(String.init)
        if parts.count <= 1 {
            roots.append(TreeNode(
                id: note.relativePath,
                name: note.displayName,
                isFolder: false,
                note: note,
                folderRelativePath: nil,
                children: [],
                depth: 0
            ))
        } else {
            let folderPath = parts.dropLast().joined(separator: "/")
            folderMap[folderPath, default: []].append(note)
            registerFolder(actualPath: note.relativePath.split(separator: "/").dropLast().joined(separator: "/"))
        }
    }

    func buildNode(path: String, depth: Int) -> TreeNode {
        var children = (folderMap[path] ?? []).map {
            TreeNode(
                id: $0.relativePath,
                name: $0.displayName,
                isFolder: false,
                note: $0,
                folderRelativePath: nil,
                children: [],
                depth: depth + 1
            )
        }
        let prefix = path + "/"
        let subfolders = Set(folderMap.keys.compactMap { candidate -> String? in
            guard candidate.hasPrefix(prefix), candidate != path else { return nil }
            return candidate.split(separator: "/").prefix(depth + 2).joined(separator: "/")
        })
        children.append(contentsOf: subfolders.sorted().map { buildNode(path: $0, depth: depth + 1) })
        children.sort { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            if let left = lhs.note, let right = rhs.note { return notesAreOrdered(left, right) }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return TreeNode(
            id: path,
            name: path.split(separator: "/").last.map(String.init) ?? path,
            isFolder: true,
            note: nil,
            folderRelativePath: ambiguousFolderPaths.contains(path) ? nil : actualFolderPaths[path],
            children: children,
            depth: depth
        )
    }

    let topFolders = Set(folderMap.keys.compactMap { $0.split(separator: "/").first.map(String.init) })
    roots.append(contentsOf: topFolders.sorted().map { buildNode(path: $0, depth: 0) })
    return roots.sorted { lhs, rhs in
        if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
        if let left = lhs.note, let right = rhs.note { return notesAreOrdered(left, right) }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

func stripKBRoot(_ path: String) -> String {
    for prefix in ["papers/", "topics/", "output/"] where path.hasPrefix(prefix) {
        return String(path.dropFirst(prefix.count))
    }
    return path
}

func stripKBRootFolder(_ path: String) -> String {
    for root in ["papers", "topics", "output"] {
        if path == root { return "" }
        let prefix = root + "/"
        if path.hasPrefix(prefix) { return String(path.dropFirst(prefix.count)) }
    }
    return path
}

// MARK: - Tree rows

private struct SidebarTreeContext {
    let currentVaultID: UUID?
    let currentVaultRole: VaultRole
    let locationScope: NoteLocationScope
    let resolvedIdentityPaths: Set<String>
    let openNote: (WindowDocumentLocation, WindowOpenDisposition) -> Void
    let requestLifecycle: (NoteLifecycleRequest) -> Void
    let canCreateNote: Bool
    let createUntitledNote: (String?) -> Void
    let createUntitledFolder: (String?) -> Void
    let requestFolderLifecycle: (FolderLifecycleRequest) -> Void
    let moveFolderToTrash: (String) async throws -> Void
    let copyRelativePath: (String) -> Void
    let revealNote: (String) -> Void
    let setAside: (String) async throws -> Void
    let moveToTrash: (String) async throws -> Void
    let deletePermanently: (String) async throws -> Void
    let showError: (String) -> Void
}

private struct SidebarTreeNodeRow: View {
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    let node: TreeNode
    @Binding var expandedFolders: Set<String>
    let selectedDocumentPath: String?
    let context: SidebarTreeContext
    let isPinnedRoot: Bool
    let requestedFocusPath: String?
    let onFocusRequestHandled: () -> Void
    let onSelect: (WindowDocumentLocation) -> Void
    let onPutBack: (WindowDocumentLocation) -> Void
    let onWillRemove: (WindowDocumentLocation) -> Void
    let onMutationFailed: (WindowDocumentLocation) -> Void

    @FocusState private var rowFocused: Bool
    @State private var pendingDestructiveAction: DestructiveAction?
    @State private var pendingFolderTrashPath: String?

    private enum DestructiveAction: String, Identifiable {
        case setAside = "Set Aside"
        case trash = "Move to Trash"
        case delete = "Delete Permanently"
        var id: String { rawValue }
    }

    private var isExpanded: Bool { expandedFolders.contains(node.id) }

    var body: some View {
        Group {
            if node.isFolder { folderRow }
            else if let note = node.note { noteRow(note) }
        }
        .onChange(of: requestedFocusPath) { _, path in
            guard path == node.note?.relativePath else { return }
            rowFocused = true
            onFocusRequestHandled()
        }
    }

    private var folderRow: some View {
        Button(action: toggleFolder) {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Group {
                    if node.children.isEmpty {
                        Image(systemName: "folder")
                    } else {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(
                                ScholiumMotion.disclosure(reduceMotion: reduceMotion),
                                value: isExpanded
                            )
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .frame(width: ScholiumMetrics.Library.leadingSlotWidth)
                .accessibilityHidden(true)

                Text(node.name)
                    .font(ScholiumInterfaceTypography.libraryFolderTitle)
                    .foregroundStyle(ScholiumColorRole.primaryText.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.leading, rowLeadingInset)
            .padding(.trailing, ScholiumMetrics.Library.rowHorizontalInset)
            .frame(
                maxWidth: .infinity,
                minHeight: ScholiumMetrics.Library.hierarchyRowHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ScholiumColorRole.separator.color)
                    .frame(height: 1)
                    .opacity(isPinnedRoot ? 1 : 0)
                    .animation(
                        ScholiumMotion.disclosure(reduceMotion: reduceMotion),
                        value: isPinnedRoot
                    )
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(SidebarNavigationButtonStyle(isSelected: false))
        .help(node.name)
        .accessibilityLabel(node.name)
        .accessibilityValue(node.children.isEmpty ? "Empty folder" : isExpanded ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("scholium.folderRow.\(node.id)")
        .contextMenu { folderContextMenu }
        .accessibilityActions { folderAccessibilityActions }
        .confirmationDialog(
            "Move Folder to Trash?",
            isPresented: Binding(
                get: { pendingFolderTrashPath != nil },
                set: { if !$0 { pendingFolderTrashPath = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move Folder and Notes to Trash", role: .destructive) {
                guard let path = pendingFolderTrashPath else { return }
                pendingFolderTrashPath = nil
                performFolderTrash(path)
            }
            Button("Cancel", role: .cancel) { pendingFolderTrashPath = nil }
        }
    }

    private func noteRow(_ note: WindowDocumentLocation) -> some View {
        HStack(spacing: 0) {
            Button { onSelect(note) } label: {
                NoteCardRow(
                    note: note,
                    isActive: selectedDocumentPath == note.relativePath,
                    vaultRole: context.currentVaultRole,
                    depth: node.depth
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(SidebarNavigationButtonStyle(
                isSelected: selectedDocumentPath == note.relativePath
            ))
            .focused($rowFocused)
            .frame(minWidth: 0, maxWidth: .infinity)
            .accessibilityLabel(note.title ?? note.displayName)
            .accessibilityIdentifier("scholium.noteRow.\(note.relativePath)")

            if context.locationScope == .setAside || context.locationScope == .trash {
                Button { onPutBack(note) } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(
                            width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                            height: ScholiumMetrics.Accessibility.preferredCustomTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Put Back…")
                .accessibilityLabel("Put Back \(note.title ?? note.displayName)")
                .accessibilityIdentifier("scholium.lifecyclePutBack.\(encodedPath(note.relativePath))")
            }
        }
        .frame(minHeight: ScholiumMetrics.Library.hierarchyRowHeight)
        .contextMenu { noteContextMenu(note) }
        .accessibilityActions { noteAccessibilityActions(note) }
        .confirmationDialog(
            pendingDestructiveAction?.rawValue ?? "Confirm",
            isPresented: Binding(
                get: { pendingDestructiveAction != nil },
                set: { if !$0 { pendingDestructiveAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = pendingDestructiveAction {
                Button(action.rawValue, role: action == .setAside ? nil : .destructive) {
                    perform(action, note: note)
                }
            }
            Button("Cancel", role: .cancel) { pendingDestructiveAction = nil }
        } message: {
            Text(destructiveMessage(for: pendingDestructiveAction, note: note))
        }
    }

    private var rowLeadingInset: CGFloat {
        ScholiumMetrics.Library.rowHorizontalInset
            + CGFloat(node.depth) * ScholiumMetrics.Library.hierarchyIndent
    }

    private func toggleFolder() {
        if isExpanded { expandedFolders.remove(node.id) }
        else { expandedFolders.insert(node.id) }
    }

    @ViewBuilder
    private var folderContextMenu: some View {
        if let path = node.folderRelativePath {
            if canMutateFolder(path) {
                Button("New Note") { context.createUntitledNote(path) }
                Button("New Folder") { context.createUntitledFolder(path) }
                if let target = folderTarget(path) {
                    Button("Rename Folder…") { context.requestFolderLifecycle(.rename(target)) }
                    Button("Move Folder…") { context.requestFolderLifecycle(.move(target)) }
                }
            }
            if !node.children.isEmpty {
                Button(subtreeIsExpanded ? "Collapse All" : "Expand All", action: toggleEntireSubtree)
            }
            Divider()
            Button("Copy Relative Path") { context.copyRelativePath(path) }
            Button("Reveal in Finder") { context.revealNote(path) }
            if canMutateFolder(path) {
                Divider()
                Button("Move Folder and Notes to Trash…", role: .destructive) {
                    pendingFolderTrashPath = path
                }
            }
        } else if !node.children.isEmpty {
            Button(subtreeIsExpanded ? "Collapse All" : "Expand All", action: toggleEntireSubtree)
        }
    }

    @ViewBuilder
    private var folderAccessibilityActions: some View {
        if let path = node.folderRelativePath {
            if canMutateFolder(path) {
                Button("New Note") { context.createUntitledNote(path) }
                Button("New Folder") { context.createUntitledFolder(path) }
                if let target = folderTarget(path) {
                    Button("Rename Folder") { context.requestFolderLifecycle(.rename(target)) }
                    Button("Move Folder") { context.requestFolderLifecycle(.move(target)) }
                }
                Button("Move Folder and Notes to Trash") { pendingFolderTrashPath = path }
            }
            Button("Copy Relative Path") { context.copyRelativePath(path) }
            Button("Reveal in Finder") { context.revealNote(path) }
        }
        if !node.children.isEmpty {
            Button(subtreeIsExpanded ? "Collapse All" : "Expand All", action: toggleEntireSubtree)
        }
    }

    @ViewBuilder
    private func noteContextMenu(_ note: WindowDocumentLocation) -> some View {
        Button("Open in New Tab") { context.openNote(note, .newTab) }
        Divider()
        if context.locationScope == .workspace {
            let target = NoteLifecycleTarget(note)
            if !CritiquePlacement.isManagedCritiquePath(note.relativePath) {
                Button("Duplicate…") {
                    guard let target else { return }
                    context.requestLifecycle(.duplicate(target))
                }
                .disabled(!hasResolvedIdentity(note) || target == nil)
            }
            Button("Move or Rename…") {
                guard let target else { return }
                context.requestLifecycle(.move(target))
            }
            .disabled(!hasResolvedIdentity(note) || target == nil)
            Divider()
            Button("Set Aside…") { pendingDestructiveAction = .setAside }
                .disabled(!hasResolvedIdentity(note))
            Button("Move to Trash…") { pendingDestructiveAction = .trash }
                .disabled(!hasResolvedIdentity(note))
        } else {
            Button("Put Back…") { onPutBack(note) }
            if context.locationScope == .setAside {
                Button("Move to Trash…") { pendingDestructiveAction = .trash }
            } else {
                Button("Delete Permanently…", role: .destructive) {
                    pendingDestructiveAction = .delete
                }
            }
        }
        Divider()
        Button("Copy Relative Path") { context.copyRelativePath(note.relativePath) }
        Button("Reveal in Finder") { context.revealNote(note.relativePath) }
    }

    @ViewBuilder
    private func noteAccessibilityActions(_ note: WindowDocumentLocation) -> some View {
        Button("Open in New Tab") { context.openNote(note, .newTab) }
        if context.locationScope == .setAside || context.locationScope == .trash {
            Button("Put Back") { onPutBack(note) }
        }
        Button("Copy Relative Path") { context.copyRelativePath(note.relativePath) }
        Button("Reveal in Finder") { context.revealNote(note.relativePath) }
    }

    private var subtreeFolderIDs: Set<String> { node.folderIDs }
    private var subtreeIsExpanded: Bool { subtreeFolderIDs.isSubset(of: expandedFolders) }

    private func toggleEntireSubtree() {
        if subtreeIsExpanded { expandedFolders.subtract(subtreeFolderIDs) }
        else { expandedFolders.formUnion(subtreeFolderIDs) }
    }

    private func canMutateFolder(_ path: String) -> Bool {
        guard context.locationScope == .workspace, context.canCreateNote else { return false }
        let candidate = "\(path)/Untitled.md"
        return !context.currentVaultRole.allowsCritique
            || !CritiquePlacement.isManagedCritiquePath(candidate)
    }

    private func folderTarget(_ path: String) -> FolderLifecycleTarget? {
        guard let vaultID = context.currentVaultID else { return nil }
        return FolderLifecycleTarget(vaultID: vaultID, relativePath: path)
    }

    private func performFolderTrash(_ path: String) {
        Task {
            do { try await context.moveFolderToTrash(path) }
            catch { context.showError("Could not move this folder to Trash. \(error.localizedDescription)") }
        }
    }

    private func hasResolvedIdentity(_ note: WindowDocumentLocation) -> Bool {
        context.resolvedIdentityPaths.contains(note.relativePath)
    }

    private func destructiveMessage(
        for action: DestructiveAction?,
        note: WindowDocumentLocation
    ) -> String {
        let title = note.title ?? note.displayName
        return switch action {
        case .setAside: "Move ‘\(title)’ out of the active Workspace?"
        case .trash: "Move ‘\(title)’ to Trash?"
        case .delete: "Permanently delete ‘\(title)’? This cannot be undone."
        case nil: ""
        }
    }

    private func perform(_ action: DestructiveAction, note: WindowDocumentLocation) {
        pendingDestructiveAction = nil
        onWillRemove(note)
        Task {
            do {
                switch action {
                case .setAside: try await context.setAside(note.relativePath)
                case .trash: try await context.moveToTrash(note.relativePath)
                case .delete: try await context.deletePermanently(note.relativePath)
                }
            } catch {
                onMutationFailed(note)
                context.showError("Could not \(action.rawValue.lowercased()): \(error.localizedDescription)")
            }
        }
    }

    private func encodedPath(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? path
    }
}

private struct SidebarNavigationButtonStyle: ButtonStyle {
    @Environment(\.controlActiveState) private var controlActiveState
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isSelected {
                    ScholiumColorRole.raisedSurfaceBackground.color
                        .opacity(controlActiveState == .inactive ? 0.56 : 0.82)
                } else if configuration.isPressed {
                    ScholiumColorRole.raisedSurfaceBackground.color.opacity(0.36)
                }
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(ScholiumColorRole.accent.color)
                        .frame(width: ScholiumMetrics.Library.selectionBoundaryWidth)
                        .accessibilityHidden(true)
                }
            }
    }
}

struct NoteCardRow: View {
    let note: WindowDocumentLocation
    let isActive: Bool
    let vaultRole: VaultRole
    var depth: Int = 0

    var body: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Image(systemName: "doc.text")
                .font(.caption)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .frame(width: ScholiumMetrics.Library.leadingSlotWidth)
                .accessibilityHidden(true)
            Text(note.title ?? note.displayName)
                .font(
                    isActive
                        ? ScholiumInterfaceTypography.librarySelectedNoteTitle
                        : ScholiumInterfaceTypography.libraryNoteTitle
                )
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(ScholiumColorRole.primaryText.color)
            Spacer(minLength: 0)
        }
        .padding(.leading, ScholiumMetrics.Library.rowHorizontalInset
            + CGFloat(depth) * ScholiumMetrics.Library.hierarchyIndent)
        .padding(.trailing, ScholiumMetrics.Library.rowHorizontalInset)
        .frame(
            maxWidth: .infinity,
            minHeight: ScholiumMetrics.Library.hierarchyRowHeight,
            alignment: .leading
        )
        .help(note.title ?? note.displayName)
    }
}
