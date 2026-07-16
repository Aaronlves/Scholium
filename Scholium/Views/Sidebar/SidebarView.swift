import ScholiumContracts
import SwiftUI

// MARK: - Sidebar View

/// Immutable Library projection and explicit window actions supplied by the
/// `ContentView` composition root. Mutable filter, sort, folder, and lifecycle
/// presentation state remains owned by `DiscoveryController`.
struct SidebarContext {
    let triptychName: String
    let attentionItems: [AttentionQueueItem]?
    let filteredNotes: [WindowDocumentLocation]
    let allNotes: [WindowDocumentLocation]
    let currentVaultID: UUID?
    let activeTab: String?
    let hasCurrentNote: Bool
    let hasVaultConfiguration: Bool
    let currentVaultRole: VaultRole
    let currentWorkspaceSlot: WorkspaceVaultSlot?
    let noteLifecycleRequest: NoteLifecycleRequest?
    let lifecycleMutationGeneration: UInt64
    let catalogIsAvailable: Bool
    let graphIsAvailable: Bool
    let hasUnqualifiedReview: Bool
    let changedSinceReviewCount: Int
    let tags: [String]
    let statuses: [String]
    let authors: [String]
    let years: [Int]
    let propertyKeys: [String]
    let propertyValues: [String: [String]]
    let resolvedIdentityPaths: Set<String>
    let reviewDisplayState: (String) -> HumanReviewDisplayState
    let notesAreOrdered: (WindowDocumentLocation, WindowDocumentLocation) -> Bool
    let presentAttention: () -> Void
    let revealCurrentVault: () -> Void
    let collapseNote: () -> Void
    let selectLocationScope: (NoteLocationScope) -> Void
    let openNote: (String, Bool) -> Void
    let openLifecycleNote: (String, NoteLocationScope) -> Void
    let selectWorkspaceVault: (WorkspaceVaultSlot) -> Void
    let lifecycleItems: (NoteLocationScope) async throws -> [LifecycleLocationItem]
    let prepareLifecycle: (LifecycleLocationItem) -> Void
    let clearPreparedLifecycle: (String) -> Void
    let revealNote: (String) -> Void
    let setAside: (String) async throws -> Void
    let moveToTrash: (String) async throws -> Void
    let deletePermanently: (String) async throws -> Void
    let classify: (String, WorkspaceVaultSlot, String) async throws -> Void
    let selectSortOrder: (NoteSortOrder) -> Void
    let showError: (String) -> Void
}

struct SidebarView: View {
    @ObservedObject private var controller: DiscoveryController
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let context: SidebarContext
    @AppStorage(AttentionPreferences.dismissalLedgerKey)
    private var attentionDismissalLedgerData = Data()

    init(controller: DiscoveryController, context: SidebarContext) {
        self.controller = controller
        self.context = context
    }

    private var lifecycleOverlayScope: NoteLocationScope? {
        controller.library.lifecycleScope
    }

    private var lifecycleOverlayItems: [LifecycleLocationItem] {
        controller.library.lifecycleItems
    }

    private var lifecycleOverlayIsLoading: Bool {
        controller.library.lifecycleIsLoading
    }

    private var lifecycleOverlayError: String? {
        controller.library.lifecycleError
    }

    private var preparedLifecyclePath: String? {
        get { controller.library.preparedLifecyclePath }
        nonmutating set { controller.prepareLifecycle(path: newValue) }
    }

    private var capturedWorkspaceNotes: [WindowDocumentLocation] {
        controller.library.capturedWorkspaceNotes
    }

    private var expandedFolders: Binding<Set<String>> {
        Binding(
            get: { controller.library.expandedFolders },
            set: { controller.setExpandedFolders($0) }
        )
    }

    private var showUnclassified: Binding<Bool> {
        Binding(
            get: { controller.library.showsUnclassified },
            set: { controller.showUnclassified($0) }
        )
    }

    private var visibleAttentionCount: Int? {
        guard let items = context.attentionItems else { return nil }
        return AttentionPreferences.decodeLedger(attentionDismissalLedgerData).visible(items).count
    }

    private var hasVisibleAttention: Bool {
        (visibleAttentionCount ?? 0) > 0
    }

    /// Notes filtered within the selected Triptych vault and location scope.
    private var filteredNotes: [WindowDocumentLocation] {
        context.filteredNotes
    }

    /// Build folder tree from filtered notes
    private var folderTree: [TreeNode] {
        buildTree(from: filteredNotes, notesAreOrdered: context.notesAreOrdered)
    }

    var body: some View {
        VStack(spacing: 0) {
            brandHeader
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 9)

            workspaceVaultPicker
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            Button {
                context.presentAttention()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "tray.full")
                        .foregroundStyle(hasVisibleAttention ? Color.orange : Color.secondary)
                    Text("Attention")
                        .font(ScholiumInterfaceTypography.compactEmphasis)
                    Spacer()
                    if let count = visibleAttentionCount {
                        Text(count.formatted())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(count > 0 ? Color.orange : Color.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 9)
            .help("Review derived warnings and recoverable research issues")
            .accessibilityValue(
                visibleAttentionCount.map { "\($0) items" } ?? "Loading"
            )

            Divider().opacity(0.15)

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    libraryHeader

                    filtersSection

                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(displayedFolderTree) { node in
                                TreeNodeView(
                                    node: node,
                                    expandedFolders: expandedFolders,
                                    activeTab: context.activeTab,
                                    context: treeContext,
                                    onSelect: { context.openNote($0, false) }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollContentBackground(.hidden)
                    .accessibilityIdentifier("scholium.noteList")
                }
                .opacity(lifecycleOverlayScope == nil ? 1 : 0.48)
                .allowsHitTesting(lifecycleOverlayScope == nil)

                if let scope = lifecycleOverlayScope {
                    SidebarLifecycleCard(
                        scope: scope,
                        items: lifecycleOverlayItems,
                        isLoading: lifecycleOverlayIsLoading,
                        errorMessage: lifecycleOverlayError,
                        onReload: { await reloadLifecycleOverlay(scope) },
                        onOpen: { item in
                            context.openLifecycleNote(item.note.relativePath, scope)
                        },
                        onPutBack: preparePutBack,
                        onReveal: context.revealNote,
                        onMoveToTrash: moveLifecycleItemToTrash,
                        onDeletePermanently: deleteLifecycleItemPermanently,
                        onClose: closeLifecycleOverlay
                    )
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(
                        reduceMotion
                            ? .identity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
                }
            }

            Divider()
                .opacity(0.5)

            unclassifiedNavigation

            Divider()
                .padding(.horizontal, 12)

            lifecycleNavigation
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.2),
            value: lifecycleOverlayScope
        )
        .accessibilityIdentifier("scholium.sidebar")
        .background {
            if context.catalogIsAvailable, !context.allNotes.isEmpty {
                PerformanceReadyBoundary(
                    generation: "\(context.currentVaultID?.uuidString ?? "none"):\(context.allNotes.count)"
                ) {
                    PerformanceProbe.shared.markLibraryReady(noteCount: context.allNotes.count)
                }
                .frame(width: 0, height: 0)
            }
        }
        .onAppear { captureWorkspaceSnapshotIfNeeded() }
        .onChange(of: context.allNotes.map(\.relativePath)) { _, _ in
            captureWorkspaceSnapshotIfNeeded()
        }
        .task(id: lifecycleOverlayReloadID) {
            guard let scope = lifecycleOverlayScope else { return }
            await reloadLifecycleOverlay(scope)
        }
        .onChange(of: context.noteLifecycleRequest) { _, request in
            guard request == nil, let path = preparedLifecyclePath else { return }
            context.clearPreparedLifecycle(path)
            preparedLifecyclePath = nil
            if let scope = lifecycleOverlayScope {
                Task { await reloadLifecycleOverlay(scope) }
            }
        }
        .sheet(isPresented: showUnclassified, onDismiss: restoreWorkspaceAfterTransientScope) {
            UnclassifiedClassificationSheet(
                locationScope: controller.library.locationScope,
                notes: context.allNotes,
                classify: context.classify,
                showError: context.showError
            )
        }
    }

    // MARK: - Header and Search

    private var brandHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scholium")
                    .font(ScholiumInterfaceTypography.identity)
                Text("Triptych — \(context.triptychName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 0) {
                Menu {
                    Button {
                        openSettings()
                    } label: {
                        Label("Manage Triptychs…", systemImage: "folder.badge.gearshape")
                    }
                    Button {
                        context.revealCurrentVault()
                    } label: {
                        Label("Reveal Current Vault in Finder", systemImage: "folder")
                    }
                    .disabled(!context.hasVaultConfiguration)
                } label: {
                    Label("Triptych management", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .frame(
                            width: ScholiumMetrics.Triptych.headerControlSize,
                            height: ScholiumMetrics.Triptych.headerControlSize
                        )
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(
                    width: ScholiumMetrics.Triptych.headerControlSize,
                    height: ScholiumMetrics.Triptych.headerControlSize
                )
                .accessibilityLabel("Triptych management")
                .accessibilityIdentifier("scholium.triptychManagement")

                if context.hasCurrentNote {
                    Divider()
                        .frame(height: 16)

                    Button {
                        context.collapseNote()
                    } label: {
                        Image(systemName: "chevron.left.2")
                            .frame(
                                width: ScholiumMetrics.Triptych.headerControlSize,
                                height: ScholiumMetrics.Triptych.headerControlSize
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Collapse Note")
                    .accessibilityLabel("Collapse Note")
                    .accessibilityHint("Retracts the document into the Triptych Interface")
                    .accessibilityIdentifier("scholium.collapseNote")
                }
            }
            .padding(2)
            .glassEffect(.regular.interactive(), in: Capsule())
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.20),
                value: context.hasCurrentNote
            )
        }
    }

    private var libraryHeader: some View {
        HStack(spacing: 8) {
            Button {
                context.selectLocationScope(.workspace)
            } label: {
                Label("Library", systemImage: "books.vertical")
                    .font(ScholiumInterfaceTypography.compactEmphasis)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(
                controller.library.locationScope == .workspace ? .isSelected : []
            )

            Spacer()

            Text("\(filteredNotes.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                controller.requestLifecycle(.create)
            } label: {
                Label("New Note", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("New Note")
            .accessibilityIdentifier("scholium.newNote")
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
    }

    private var unclassifiedNavigation: some View {
        Button {
            captureWorkspaceSnapshotIfNeeded()
            controller.showUnclassified(true)
            context.selectLocationScope(.unclassified)
        } label: {
            Label("Unclassified", systemImage: "tray.and.arrow.down")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .help("Classify imported Markdown")
        .accessibilityIdentifier("scholium.location.unclassified")
    }

    private var lifecycleNavigation: some View {
        VStack(spacing: 1) {
            locationButton(.setAside, symbol: "archivebox")
            locationButton(.trash, symbol: "trash")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    private func locationButton(_ scope: NoteLocationScope, symbol: String) -> some View {
        Button {
            openLifecycleOverlay(scope)
        } label: {
            Label(scope.rawValue, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(
            lifecycleOverlayScope == scope ? .regular.interactive() : .identity,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .accessibilityAddTraits(lifecycleOverlayScope == scope ? .isSelected : [])
        .accessibilityIdentifier(
            scope == .setAside ? "scholium.location.setAside" : "scholium.location.trash"
        )
    }

    private var displayedFolderTree: [TreeNode] {
        if lifecycleOverlayScope != nil, !capturedWorkspaceNotes.isEmpty {
            return buildTree(
                from: capturedWorkspaceNotes,
                notesAreOrdered: context.notesAreOrdered
            )
        }
        return folderTree
    }

    private var lifecycleOverlayReloadID: String {
        "\(lifecycleOverlayScope?.rawValue ?? "closed"):\(context.lifecycleMutationGeneration)"
    }

    private func captureWorkspaceSnapshotIfNeeded() {
        guard controller.library.locationScope == .workspace else { return }
        controller.captureWorkspaceNotes(filteredNotes)
    }

    private func openLifecycleOverlay(_ scope: NoteLocationScope) {
        guard scope == .setAside || scope == .trash else { return }
        if lifecycleOverlayScope == scope {
            closeLifecycleOverlay()
            return
        }
        captureWorkspaceSnapshotIfNeeded()
        controller.presentLifecycleListing(scope)
    }

    private func closeLifecycleOverlay() {
        controller.dismissLifecycleListing()
        if controller.library.locationScope != .workspace {
            restoreWorkspaceAfterTransientScope()
        }
    }

    private func reloadLifecycleOverlay(_ scope: NoteLocationScope) async {
        let request = controller.beginLifecycleListing(scope)
        do {
            let items = try await context.lifecycleItems(scope)
            guard lifecycleOverlayScope == scope, !Task.isCancelled else { return }
            controller.receiveLifecycleItems(items, for: request)
        } catch {
            guard lifecycleOverlayScope == scope, !Task.isCancelled else { return }
            controller.failLifecycleListing(error.localizedDescription, for: request)
        }
    }

    private func preparePutBack(_ item: LifecycleLocationItem) {
        context.prepareLifecycle(item)
        preparedLifecyclePath = item.note.relativePath
        controller.requestLifecycle(.putBack(item.note.relativePath))
    }

    private func restoreWorkspaceAfterTransientScope() {
        context.selectLocationScope(.workspace)
    }

    // MARK: - Knowledge Base Picker

    private var workspaceVaultPicker: some View {
        Picker("Triptych", selection: currentWorkspaceSlotBinding) {
            ForEach(WorkspaceVaultSlot.allCases) { slot in
                Text(slot.displayName).tag(slot)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .accessibilityLabel("Triptych vault")
    }

    private var currentWorkspaceSlotBinding: Binding<WorkspaceVaultSlot> {
        Binding(
            get: { currentWorkspaceSlot ?? .paperAnalysis },
            set: { slot in
                guard !isCurrent(slot) else { return }
                context.selectWorkspaceVault(slot)
            }
        )
    }

    private func isCurrent(_ slot: WorkspaceVaultSlot) -> Bool {
        context.currentWorkspaceSlot == slot
    }

    private var currentWorkspaceSlot: WorkspaceVaultSlot? {
        context.currentWorkspaceSlot
    }

    // MARK: - Filters Section

    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if context.currentVaultRole.allowsHumanReview {
                    Toggle(isOn: filterBinding(\.isReviewed)) {
                        Text("Unreviewed")
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                }

                Spacer()

                Text("\(filteredNotes.count) notes")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if context.currentVaultRole.allowsHumanReview,
               context.hasUnqualifiedReview {
                Toggle(isOn: filterBinding(\.isUnqualified)) {
                    Label("Unqualified", systemImage: "xmark.seal")
                        .font(.caption)
                        .foregroundStyle(
                            controller.library.filters.isUnqualified ? .red : .primary
                        )
                }
                .toggleStyle(.checkbox)
            }

            Menu {
                Menu("Research State") {
                    Toggle("Changed since review", isOn: filterBinding(\.isChangedSinceReview))
                        .accessibilityIdentifier("scholium.researchFilter.changedSinceReview")
                    Toggle("Needs attention", isOn: filterBinding(\.needsAttention))
                        .disabled(!context.catalogIsAvailable)
                        .accessibilityIdentifier("scholium.researchFilter.needsAttention")
                    Toggle("Explicit connections", isOn: filterBinding(\.hasExplicitConnections))
                        .disabled(!context.graphIsAvailable)
                        .accessibilityIdentifier("scholium.researchFilter.explicitConnections")
                    Toggle("Malformed metadata", isOn: filterBinding(\.hasMalformedMetadata))
                        .disabled(!context.catalogIsAvailable)
                        .accessibilityIdentifier("scholium.researchFilter.malformedMetadata")

                    if activeResearchFilterCount > 0 {
                        Divider()
                        Button("Clear Research Filters", action: clearResearchFilters)
                    }
                }

                Menu("Tag") {
                    Button {
                        updateFilters { $0.tag = nil }
                    } label: {
                        if controller.library.filters.tag == nil {
                            Label("All Tags", systemImage: "checkmark")
                        } else {
                            Text("All Tags")
                        }
                    }
                    Divider()
                    ForEach(context.tags, id: \.self) { tag in
                        Button {
                            updateFilters { $0.tag = tag }
                        } label: {
                            if controller.library.filters.tag == tag {
                                Label(tag, systemImage: "checkmark")
                            } else {
                                Text(tag)
                            }
                        }
                    }
                }
                .disabled(context.tags.isEmpty)

                Menu("Status") {
                    Button("Any Status") { updateFilters { $0.status = nil } }
                    Divider()
                    ForEach(context.statuses, id: \.self) { status in
                        Button {
                            updateFilters { $0.status = status }
                        } label: {
                            if controller.library.filters.status == status {
                                Label(status.capitalized, systemImage: "checkmark")
                            } else {
                                Text(status.capitalized)
                            }
                        }
                    }
                }

                if !context.authors.isEmpty {
                    Menu("Author") {
                        Button("Any Author") { updateFilters { $0.author = nil } }
                        Divider()
                        ForEach(context.authors, id: \.self) { author in
                            Button {
                                updateFilters { $0.author = author }
                            } label: {
                                if controller.library.filters.author == author {
                                    Label(author, systemImage: "checkmark")
                                } else {
                                    Text(author)
                                }
                            }
                        }
                    }
                }

                if !context.years.isEmpty {
                    Menu("Year") {
                        Button("Any Year") { updateFilters { $0.year = nil } }
                        Divider()
                        ForEach(context.years, id: \.self) { year in
                            Button {
                                updateFilters { $0.year = year }
                            } label: {
                                if controller.library.filters.year == year {
                                    Label(year.formatted(.number.grouping(.never)), systemImage: "checkmark")
                                } else {
                                    Text(year.formatted(.number.grouping(.never)))
                                }
                            }
                        }
                    }
                }

                if !context.propertyKeys.isEmpty {
                    Button("Any Property") {
                        updateFilters {
                            $0.propertyKey = nil
                            $0.propertyValue = nil
                        }
                        if controller.library.sortOrder == .debateImportanceDescending {
                            context.selectSortOrder(.modifiedNewest)
                        }
                    }
                    ForEach(context.propertyKeys, id: \.self) { key in
                        Menu(propertyLabel(key)) {
                            ForEach(context.propertyValues[key] ?? [], id: \.self) { value in
                                Button {
                                    updateFilters {
                                        $0.propertyKey = key
                                        $0.propertyValue = value
                                    }
                                    if key != "debate_importance_scope",
                                       controller.library.sortOrder == .debateImportanceDescending {
                                        context.selectSortOrder(.modifiedNewest)
                                    }
                                } label: {
                                    if controller.library.filters.propertyKey == key,
                                       controller.library.filters.propertyValue == value {
                                        Label(value, systemImage: "checkmark")
                                    } else {
                                        Text(value)
                                    }
                                }
                            }
                        }
                    }
                }

                if activeMetadataFilterCount > 0 {
                    Divider()
                    Button("Clear Metadata Filters", action: clearMetadataFilters)
                }

                Menu("Sort") {
                    ForEach(NoteSortOrder.allCases) { order in
                        Button {
                            context.selectSortOrder(order)
                        } label: {
                            if controller.library.sortOrder == order {
                                Label(order.title, systemImage: "checkmark")
                            } else {
                                Text(order.title)
                            }
                        }
                        .disabled(
                            order == .debateImportanceDescending
                                && !hasScopedDebateImportanceFilter
                        )
                    }
                    if !hasScopedDebateImportanceFilter {
                        Divider()
                        Text("Select one Debate Scope before comparing importance")
                    }
                }

                if activeLibraryMenuFilterCount > 0 {
                    Divider()
                    Button("Clear Library Filters") {
                        clearResearchFilters()
                        updateFilters { $0.tag = nil }
                        clearMetadataFilters()
                    }
                }
            } label: {
                Label(
                    "Filter",
                    systemImage: activeLibraryMenuFilterCount == 0
                        ? "line.3.horizontal.decrease"
                        : "line.3.horizontal.decrease.circle.fill"
                )
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .controlSize(.small)
            .help(libraryFilterHelp)
            .accessibilityLabel("Library filters")
            .accessibilityValue(libraryFilterAccessibilityValue)
            .accessibilityIdentifier("scholium.libraryFilters")

            if context.changedSinceReviewCount > 0 {
                Label("\(context.changedSinceReviewCount) changed since review", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var activeLibraryMenuFilterCount: Int {
        activeResearchFilterCount
            + activeMetadataFilterCount
            + (controller.library.filters.tag == nil ? 0 : 1)
    }

    private var activeResearchFilterCount: Int {
        let filters = controller.library.filters
        return [
            filters.isChangedSinceReview,
            filters.needsAttention,
            filters.hasExplicitConnections,
            filters.hasMalformedMetadata,
        ].count(where: { $0 })
    }

    private var activeMetadataFilterCount: Int {
        let filters = controller.library.filters
        return [
            filters.status != nil,
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
            set: { value in
                updateFilters { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func updateFilters(_ update: (inout DiscoveryFilterState) -> Void) {
        var filters = controller.library.filters
        update(&filters)
        controller.replaceFilters(filters)
    }

    private func clearResearchFilters() {
        updateFilters {
            $0.isChangedSinceReview = false
            $0.needsAttention = false
            $0.hasExplicitConnections = false
            $0.hasMalformedMetadata = false
        }
    }

    private func clearMetadataFilters() {
        updateFilters {
            $0.status = nil
            $0.author = nil
            $0.year = nil
            $0.propertyKey = nil
            $0.propertyValue = nil
        }
        if controller.library.sortOrder == .debateImportanceDescending {
            context.selectSortOrder(.modifiedNewest)
        }
    }

    private var treeContext: SidebarTreeContext {
        SidebarTreeContext(
            currentVaultRole: context.currentVaultRole,
            locationScope: controller.library.locationScope,
            resolvedIdentityPaths: context.resolvedIdentityPaths,
            reviewDisplayState: context.reviewDisplayState,
            openNote: context.openNote,
            requestLifecycle: { controller.requestLifecycle($0) },
            revealNote: context.revealNote,
            setAside: context.setAside,
            moveToTrash: context.moveToTrash,
            deletePermanently: context.deletePermanently,
            showError: context.showError
        )
    }

    private func moveLifecycleItemToTrash(_ item: LifecycleLocationItem) {
        Task {
            do {
                context.prepareLifecycle(item)
                defer { context.clearPreparedLifecycle(item.note.relativePath) }
                try await context.moveToTrash(item.note.relativePath)
                await reloadLifecycleOverlay(.setAside)
            } catch {
                context.showError(
                    "Could not move this note to Trash. \(error.localizedDescription)"
                )
            }
        }
    }

    private func deleteLifecycleItemPermanently(_ item: LifecycleLocationItem) {
        Task {
            do {
                context.prepareLifecycle(item)
                defer { context.clearPreparedLifecycle(item.note.relativePath) }
                try await context.deletePermanently(item.note.relativePath)
                await reloadLifecycleOverlay(.trash)
            } catch {
                context.showError(
                    "Could not permanently delete this note. \(error.localizedDescription)"
                )
            }
        }
    }

    private var libraryFilterHelp: String {
        activeLibraryMenuFilterCount == 0
            ? "Filter and sort Library notes"
            : "\(activeLibraryMenuFilterCount) Library filters active"
    }

    private var libraryFilterAccessibilityValue: String {
        let filters = activeLibraryMenuFilterCount == 0
            ? "No filters active"
            : "\(activeLibraryMenuFilterCount) filters active"
        return "\(filters), sorted by \(controller.library.sortOrder.title)"
    }

    private func propertyLabel(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

private struct SidebarLifecycleCard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let scope: NoteLocationScope
    let items: [LifecycleLocationItem]
    let isLoading: Bool
    let errorMessage: String?
    let onReload: () async -> Void
    let onOpen: (LifecycleLocationItem) -> Void
    let onPutBack: (LifecycleLocationItem) -> Void
    let onReveal: (String) -> Void
    let onMoveToTrash: (LifecycleLocationItem) -> Void
    let onDeletePermanently: (LifecycleLocationItem) -> Void
    let onClose: () -> Void

    @State private var pendingPermanentDeletion: LifecycleLocationItem?

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onClose) {
                Capsule()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: 34, height: 4)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Collapse \(scope.rawValue)")
            .accessibilityLabel("Collapse \(scope.rawValue)")

            HStack {
                Text(scope.rawValue)
                    .font(ScholiumInterfaceTypography.compactEmphasis)
                Spacer()
                if !isLoading {
                    Text(items.count.formatted())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            Group {
                if isLoading {
                    ProgressView("Opening \(scope.rawValue)…")
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Could Not Open \(scope.rawValue)", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") { Task { await onReload() } }
                    }
                    .frame(minHeight: 150)
                } else if items.isEmpty {
                    ContentUnavailableView(
                        scope.rawValue,
                        systemImage: scope == .trash ? "trash" : "archivebox",
                        description: Text("No notes are currently in \(scope.rawValue).")
                    )
                    .frame(minHeight: 150)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(items) { item in
                                let note = item.note
                                Button {
                                    onOpen(item)
                                } label: {
                                    Text(note.title ?? note.displayName)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        onPutBack(item)
                                    } label: {
                                        Label("Put Back…", systemImage: "arrow.uturn.backward")
                                    }
                                    if scope == .setAside {
                                        Button {
                                            moveToTrash(item)
                                        } label: {
                                            Label("Move to Trash…", systemImage: "trash")
                                        }
                                    } else {
                                        Button(role: .destructive) {
                                            pendingPermanentDeletion = item
                                        } label: {
                                            Label("Delete Permanently…", systemImage: "trash.slash")
                                        }
                                    }
                                    Divider()
                                    Button {
                                        onReveal(note.relativePath)
                                    } label: {
                                        Label("Reveal in Finder", systemImage: "folder")
                                    }
                                }
                                .accessibilityLabel(note.title ?? note.displayName)
                                .accessibilityHint("Open note in \(scope.rawValue)")

                                if item.id != items.last?.id {
                                    Divider().padding(.leading, 12)
                                }
                            }
                        }
                    }
                }
            }
        }
        .background {
            if reduceTransparency {
                Rectangle()
                    .fill(Color(nsColor: .controlBackgroundColor))
            } else {
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    Rectangle()
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.84))
                }
            }
        }
        .frame(minHeight: 170, idealHeight: 280, maxHeight: 360)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            scope == .setAside ? "scholium.lifecycleCard.setAside" : "scholium.lifecycleCard.trash"
        )
        .confirmationDialog(
            "Delete Permanently?",
            isPresented: Binding(
                get: { pendingPermanentDeletion != nil },
                set: { if !$0 { pendingPermanentDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = pendingPermanentDeletion {
                Button("Delete Permanently", role: .destructive) {
                    deletePermanently(item)
                }
            }
            Button("Cancel", role: .cancel) { pendingPermanentDeletion = nil }
        } message: {
            Text("This cannot be undone. Scholium removes the note, its Review and comments, Dialogue records, Critique association, stable identity, Note History, and every Triptych checkpoint containing it.")
        }
    }

    private func moveToTrash(_ item: LifecycleLocationItem) {
        onMoveToTrash(item)
    }

    private func deletePermanently(_ item: LifecycleLocationItem) {
        pendingPermanentDeletion = nil
        onDeletePermanently(item)
    }
}

private struct UnclassifiedClassificationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let locationScope: NoteLocationScope
    let notes: [WindowDocumentLocation]
    let classify: (String, WorkspaceVaultSlot, String) async throws -> Void
    let showError: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unclassified")
                        .font(.title2.weight(.semibold))
                    Text("Choose a Triptych destination for each imported note.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)

            Divider()

            if locationScope != .unclassified {
                ProgressView("Opening Unclassified…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if notes.isEmpty {
                ContentUnavailableView(
                    "No Unclassified Notes",
                    systemImage: "tray.and.arrow.down",
                    description: Text("Imported Markdown appears here until you choose Analyses, Topics, or Works.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(notes) { note in
                            UnclassifiedClassificationRow(
                                note: note,
                                classify: classify,
                                showError: showError
                            )
                            if note.id != notes.last?.id {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(minWidth: 0, idealWidth: 600, minHeight: 300, idealHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("scholium.unclassifiedPanel")
    }
}

private struct UnclassifiedClassificationRow: View {
    let note: WindowDocumentLocation
    let classify: (String, WorkspaceVaultSlot, String) async throws -> Void
    let showError: (String) -> Void

    @State private var destinationSlot: WorkspaceVaultSlot = .paperAnalysis
    @State private var isClassifying = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                noteSummary
                destinationPicker
                classifyButton
            }

            VStack(alignment: .leading, spacing: 8) {
                noteSummary
                HStack(spacing: 10) {
                    destinationPicker
                    classifyButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private var noteSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title ?? note.displayName)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Text(note.relativePath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var destinationPicker: some View {
        Picker("Destination", selection: $destinationSlot) {
            ForEach(WorkspaceVaultSlot.allCases) { slot in
                Text(slot.displayName).tag(slot)
            }
        }
        .labelsHidden()
        .frame(width: 130)
    }

    private var classifyButton: some View {
        Button("Classify") { performClassification() }
            .buttonStyle(.glass)
            .disabled(isClassifying)
    }

    private func performClassification() {
        isClassifying = true
        Task {
            do {
                try await classify(
                    note.relativePath,
                    destinationSlot,
                    note.relativePath
                )
            } catch {
                isClassifying = false
                showError("Could not classify this note. \(error.localizedDescription)")
            }
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(result.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text("Line \(result.sourceLine)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(highlightedSnippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Text(result.matchField.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(result.displayName), match on line \(result.sourceLine)")
        .accessibilityHint("Open the exact source line")
    }

    private var highlightedSnippet: AttributedString {
        var attributed = AttributedString(result.snippet)
        let ns = result.snippet as NSString
        for highlight in result.highlights {
            let range = NSRange(
                location: highlight.utf16LowerBound,
                length: highlight.utf16UpperBound - highlight.utf16LowerBound
            )
            guard range.location >= 0, NSMaxRange(range) <= ns.length,
                  let stringRange = Range(range, in: result.snippet),
                  let attributedRange = Range(stringRange, in: attributed) else { continue }
            attributed[attributedRange].backgroundColor = .accentColor.opacity(0.18)
            attributed[attributedRange].foregroundColor = .primary
        }
        return attributed
    }
}

// MARK: - Tree Node Model

struct TreeNode: Identifiable {
    let id: String       // full path
    let name: String     // display name
    let isFolder: Bool
    let note: WindowDocumentLocation?      // nil for folders
    let children: [TreeNode]
    let depth: Int
}

/// Build a folder tree from flat note list
func buildTree(
    from notes: [WindowDocumentLocation],
    notesAreOrdered: (WindowDocumentLocation, WindowDocumentLocation) -> Bool
) -> [TreeNode] {
    var roots: [TreeNode] = []
    var folderMap: [String: [WindowDocumentLocation]] = [:]

    for note in notes {
        // Strip KB root prefix (e.g., "papers/", "topics/", "output/")
        let stripped = stripKBRoot(note.relativePath)
        let parts = stripped.split(separator: "/").map(String.init)
        if parts.count == 0 || (parts.count == 1 && parts[0].isEmpty) {
            roots.append(TreeNode(id: note.relativePath, name: note.displayName, isFolder: false, note: note, children: [], depth: 0))
        } else if parts.count == 1 {
            roots.append(TreeNode(id: note.relativePath, name: note.displayName, isFolder: false, note: note, children: [], depth: 0))
        } else {
            let folderPath = parts.dropLast().joined(separator: "/")
            folderMap[folderPath, default: []].append(note)
        }
    }

    // Build folder nodes
    func buildNode(path: String, depth: Int) -> TreeNode {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        var children: [TreeNode] = []

        // Add files directly in this folder
        if let files = folderMap[path] {
            for note in files {
                children.append(TreeNode(id: note.relativePath, name: note.displayName, isFolder: false, note: note, children: [], depth: depth + 1))
            }
        }

        // Add subfolders
        let prefix = path + "/"
        let subfolders = Set(folderMap.keys.filter { $0.hasPrefix(prefix) && $0 != path }.map { $0.split(separator: "/").prefix(depth + 2).joined(separator: "/") })
        for sub in subfolders.sorted() {
            children.append(buildNode(path: sub, depth: depth + 1))
        }

        return TreeNode(id: path, name: name, isFolder: true, note: nil, children: children.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            if let left = a.note, let right = b.note { return notesAreOrdered(left, right) }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }, depth: depth)
    }

    // Collect top-level folders
    let topFolders = Set(folderMap.keys.map { $0.split(separator: "/").first.map(String.init) ?? $0 })
    for folder in topFolders.sorted() {
        if !roots.contains(where: { $0.id == folder }) {
            roots.append(buildNode(path: folder, depth: 0))
        }
    }

    return roots.sorted { a, b in
        if a.isFolder != b.isFolder { return a.isFolder }
        if let left = a.note, let right = b.note { return notesAreOrdered(left, right) }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}

/// Strip the KB root prefix from a path (e.g., "papers/ethics/note.md" → "ethics/note.md")
func stripKBRoot(_ path: String) -> String {
    let kbPrefixes = ["papers/", "topics/", "output/"]
    for prefix in kbPrefixes {
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
    }
    return path
}

// MARK: - Tree Node View

private struct SidebarTreeContext {
    let currentVaultRole: VaultRole
    let locationScope: NoteLocationScope
    let resolvedIdentityPaths: Set<String>
    let reviewDisplayState: (String) -> HumanReviewDisplayState
    let openNote: (String, Bool) -> Void
    let requestLifecycle: (NoteLifecycleRequest) -> Void
    let revealNote: (String) -> Void
    let setAside: (String) async throws -> Void
    let moveToTrash: (String) async throws -> Void
    let deletePermanently: (String) async throws -> Void
    let showError: (String) -> Void
}

private struct TreeNodeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let node: TreeNode
    @Binding var expandedFolders: Set<String>
    let activeTab: String?
    let context: SidebarTreeContext
    let onSelect: (String) -> Void

    @State private var pendingDestructiveAction: DestructiveAction?

    private enum DestructiveAction: String, Identifiable {
        case setAside = "Set Aside"
        case trash = "Move to Trash"
        case delete = "Delete Permanently"
        var id: String { rawValue }
    }

    private var isExpanded: Bool { expandedFolders.contains(node.id) }

    var body: some View {
        if node.isFolder {
            // Folder row
            VStack(spacing: 0) {
                Button(action: toggleFolder) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 12)
                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text(node.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.leading, CGFloat(node.depth * 12 + 8))
                    .padding(.trailing, 8)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("scholium.folderRow.\(node.id)")

                // Children
                if isExpanded {
                    ForEach(node.children) { child in
                        TreeNodeView(
                            node: child,
                            expandedFolders: $expandedFolders,
                            activeTab: activeTab,
                            context: context,
                            onSelect: onSelect
                        )
                            .transition(
                                reduceMotion
                                    ? .identity
                                    : .opacity.combined(with: .move(edge: .top))
                            )
                    }
                }
            }
        } else if let note = node.note {
            // Note file row
            Button {
                onSelect(note.relativePath)
            } label: {
                NoteCardRow(
                    note: note,
                    isActive: activeTab == note.relativePath,
                    vaultRole: context.currentVaultRole,
                    reviewDisplayState: context.reviewDisplayState(note.relativePath)
                )
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(note.title ?? note.displayName)
                .accessibilityIdentifier("scholium.noteRow.\(note.relativePath)")
                .accessibilityValue(
                    CritiquePlacement.isManagedCritiquePath(note.relativePath)
                        ? "Agent-authored Critique"
                        : context.currentVaultRole.allowsCritique
                        ? "Work"
                        : context.reviewDisplayState(note.relativePath).badgeLabel
                )
                .contextMenu {
                    Button {
                        context.openNote(note.relativePath, true)
                    } label: {
                        Label("Open in New Tab", systemImage: "plus.square")
                    }
                    Divider()
                    if context.locationScope == .workspace {
                        if !CritiquePlacement.isManagedCritiquePath(note.relativePath) {
                            Button {
                                context.requestLifecycle(.duplicate(note.relativePath))
                            } label: {
                                Label("Duplicate…", systemImage: "plus.square.on.square")
                            }
                            .disabled(!hasResolvedIdentity(note))
                        }
                        Button {
                            context.requestLifecycle(.move(note.relativePath))
                        } label: {
                            Label("Move or Rename…", systemImage: "folder")
                        }
                        .disabled(!hasResolvedIdentity(note))
                        Divider()
                        Button {
                            pendingDestructiveAction = .setAside
                        } label: {
                            Label("Set Aside…", systemImage: "archivebox")
                        }
                        .disabled(!hasResolvedIdentity(note))
                        Button {
                            pendingDestructiveAction = .trash
                        } label: {
                            Label("Move to Trash…", systemImage: "trash")
                        }
                        .disabled(!hasResolvedIdentity(note))
                    } else if context.locationScope == .unclassified {
                        Button {
                            context.requestLifecycle(.classify(note.relativePath))
                        } label: {
                            Label("Classify…", systemImage: "tray.and.arrow.down")
                        }
                    } else {
                        Button {
                            context.requestLifecycle(.putBack(note.relativePath))
                        } label: {
                            Label("Put Back…", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(!hasResolvedIdentity(note))
                        if context.locationScope == .setAside {
                            Button {
                                pendingDestructiveAction = .trash
                            } label: {
                                Label("Move to Trash…", systemImage: "trash")
                            }
                            .disabled(!hasResolvedIdentity(note))
                        } else {
                            Button(role: .destructive) {
                                pendingDestructiveAction = .delete
                            } label: {
                                Label("Delete Permanently…", systemImage: "trash.slash")
                            }
                            .disabled(!hasResolvedIdentity(note))
                        }
                    }
                    Divider()
                    Button {
                        context.revealNote(note.relativePath)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                }
                .padding(.leading, CGFloat(node.depth * 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
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
    }

    private func toggleFolder() {
        let update = {
            if isExpanded {
                expandedFolders.remove(node.id)
            } else {
                expandedFolders.insert(node.id)
            }
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(.easeInOut(duration: 0.16), update)
        }
    }

    private func destructiveMessage(for action: DestructiveAction?, note: WindowDocumentLocation) -> String {
        switch action {
        case .setAside: "Move ‘\(note.title ?? note.displayName)’ out of the active Workspace?"
        case .trash: "Move ‘\(note.title ?? note.displayName)’ to Trash?"
        case .delete: "Permanently delete ‘\(note.title ?? note.displayName)’? This removes its comments, Human Review, Dialogue records, Critique association, stable identity, Note History, and every Triptych checkpoint containing it. This cannot be undone."
        case nil: ""
        }
    }

    private func hasResolvedIdentity(_ note: WindowDocumentLocation) -> Bool {
        context.locationScope == .unclassified
            || context.resolvedIdentityPaths.contains(note.relativePath)
    }

    private func perform(_ action: DestructiveAction, note: WindowDocumentLocation) {
        pendingDestructiveAction = nil
        Task {
            do {
                switch action {
                case .setAside: try await context.setAside(note.relativePath)
                case .trash: try await context.moveToTrash(note.relativePath)
                case .delete: try await context.deletePermanently(note.relativePath)
                }
            } catch {
                context.showError(
                    "Could not \(action.rawValue.lowercased()): \(error.localizedDescription)"
                )
            }
        }
    }
}

// MARK: - Note Card Row

struct NoteCardRow: View {
    let note: WindowDocumentLocation
    let isActive: Bool
    let vaultRole: VaultRole
    let reviewDisplayState: HumanReviewDisplayState

    private var modifiedString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: note.fileModifiedAt, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(note.title ?? note.displayName)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if vaultRole.allowsHumanReview {
                        Image(systemName: reviewBadgeSymbol)
                            .font(.system(size: 10))
                            .foregroundStyle(reviewBadgeColor)
                            .help(reviewBadgeLabel)
                            .accessibilityLabel(reviewBadgeLabel)
                    }
                }
                Text(secondaryMetadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if let status = note.status {
                Text(status.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.14) : Color.clear)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var reviewBadgeSymbol: String {
        reviewDisplayState.badgeSymbol
    }

    private var reviewBadgeColor: Color {
        reviewDisplayState.badgeColor
    }

    private var reviewBadgeLabel: String {
        reviewDisplayState.badgeLabel
    }

    private var secondaryMetadata: String {
        switch vaultRole {
        case .sourceCorpus:
            let author = note.authors.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            let year = note.year.map { $0.formatted(.number.grouping(.never)) }
            let sourceMetadata = [author, year].compactMap { $0 }.filter { !$0.isEmpty }
            return sourceMetadata.isEmpty ? modifiedString : sourceMetadata.joined(separator: ", ")
        case .topicKnowledge:
            return modifiedString
        case .dissertationControl, .draftProject:
            let kind = ["kind", "note_type", "document_type"].compactMap {
                note.property(at: $0)?.scalarString?.trimmingCharacters(in: .whitespacesAndNewlines)
            }.first { !$0.isEmpty }
            let lifecycle = note.status.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
            }
            let workMetadata = [kind, lifecycle].compactMap { $0 }.filter { !$0.isEmpty }
            return workMetadata.isEmpty ? modifiedString : workMetadata.joined(separator: ", ")
        case .other:
            return modifiedString
        }
    }

}

private extension HumanReviewDisplayState {
    var badgeSymbol: String {
        switch self {
        case .notReviewed: "circle"
        case .reviewed: "checkmark.circle.fill"
        case .qualified: "checkmark.seal.fill"
        case .unqualified: "xmark.seal.fill"
        }
    }

    var badgeColor: Color {
        switch self {
        case .notReviewed: .secondary.opacity(0.4)
        case .reviewed: .secondary
        case .qualified: .green
        case .unqualified: .red
        }
    }

    var badgeLabel: String {
        switch self {
        case .notReviewed: "Not reviewed"
        case .reviewed: "Reviewed"
        case .qualified: "Qualified"
        case .unqualified: "Unqualified"
        }
    }
}
