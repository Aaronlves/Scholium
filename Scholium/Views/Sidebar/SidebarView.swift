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
    let disclosureScope: LibraryDisclosureScope?
    let selectedDocumentPath: String?
    let libraryFocusRequestGeneration: UInt64
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
    let bibliographyController: RecommendedBibliographyController
    let attentionQueueContext: AttentionQueueContext
    let reviewDisplayState: (String) -> HumanReviewDisplayState
    let notesAreOrdered: (WindowDocumentLocation, WindowDocumentLocation) -> Bool
    let selectLocationScope: (NoteLocationScope) -> Void
    let openNote: (WindowDocumentLocation, WindowOpenDisposition) -> Void
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
    let openRecommendedAnalysis: (VaultQualifiedNoteID) -> Void
    let openRecommendedZoteroItem: (String) async -> Void
    let copyRecommendedBibliographyText: (String) -> Void
    let repairRecommendedBibliographyMethod: () -> Void
    let revealCurrentVault: () -> Void
    let setSidebarVisible: (Bool) -> Void
    let openSettings: () -> Void
    let selectSortOrder: (NoteSortOrder) -> Void
    let showError: (String) -> Void
}

private struct LifecycleDestinationFocusPlan: Equatable {
    let originPath: String
    let successorPath: String?
}

struct SidebarView: View {
    @ObservedObject private var controller: DiscoveryController
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    let context: SidebarContext
    @AppStorage(AttentionPreferences.dismissalLedgerKey)
    private var attentionDismissalLedgerData = Data()
    @FocusState private var libraryFocused: Bool
    @FocusState private var lifecycleBackFocused: Bool
    @State private var requestedLifecyclePutBackFocusPath: String?
    @State private var pendingLifecycleFocusPlan: LifecycleDestinationFocusPlan?

    init(controller: DiscoveryController, context: SidebarContext) {
        self.controller = controller
        self.context = context
    }

    private var lifecycleDestinationScope: NoteLocationScope? {
        controller.library.lifecycleScope
    }

    private var lifecycleDestinationItems: [LifecycleLocationItem] {
        controller.library.lifecycleItems
    }

    private var lifecycleDestinationIsLoading: Bool {
        controller.library.lifecycleIsLoading
    }

    private var lifecycleDestinationError: String? {
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
            get: { controller.expandedFolders(in: context.disclosureScope) },
            set: { controller.setExpandedFolders($0, in: context.disclosureScope) }
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
            triptychIdentity

            workspaceVaultPicker
                .padding(.horizontal, ScholiumMetrics.Library.contentInset)
                .padding(.top, ScholiumMetrics.Library.scopeTopSpacing)

            attentionNavigation
                .padding(.horizontal, ScholiumMetrics.Library.contentInset)
                .padding(.top, ScholiumMetrics.Library.sectionSpacing)

            libraryHeader
                .padding(.horizontal, ScholiumMetrics.Library.contentInset)
                .padding(.top, ScholiumMetrics.Library.sectionSpacing)

            ZStack(alignment: .topLeading) {
                Group {
                    if controller.library.showsAttentionQueue {
                        AttentionQueueView(
                            controller: controller,
                            context: context.attentionQueueContext
                        )
                        .accessibilityIdentifier("scholium.libraryAttentionQueue")
                    } else {
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(displayedFolderTree) { node in
                                    TreeNodeView(
                                        node: node,
                                        expandedFolders: expandedFolders,
                                        selectedDocumentPath: context.selectedDocumentPath,
                                        context: treeContext,
                                        onSelect: { context.openNote($0, .replaceCurrent) }
                                    )
                                }
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, ScholiumMetrics.Library.contentInset)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        }
                        .scrollContentBackground(.hidden)
                        .focusable()
                        .focusEffectDisabled()
                        .focused($libraryFocused)
                        .accessibilityIdentifier("scholium.noteList")
                    }
                }
                .opacity(lifecycleDestinationScope == nil ? 1 : 0)
                .allowsHitTesting(lifecycleDestinationScope == nil)
                .accessibilityHidden(lifecycleDestinationScope != nil)
                .overlay(alignment: .topLeading) {
                    if let scope = lifecycleDestinationScope {
                        SidebarLifecycleDestinationView(
                            scope: scope,
                            items: lifecycleDestinationItems,
                            isLoading: lifecycleDestinationIsLoading,
                            errorMessage: lifecycleDestinationError,
                            requestedPutBackFocusPath: requestedLifecyclePutBackFocusPath,
                            onFocusRequestHandled: {
                                requestedLifecyclePutBackFocusPath = nil
                            },
                            onRequestPutBackFocus: {
                                requestedLifecyclePutBackFocusPath = $0
                            },
                            onReload: { await reloadLifecycleDestination(scope) },
                            onOpen: { item in
                                context.openLifecycleNote(item.note.relativePath, scope)
                            },
                            onPutBack: preparePutBack,
                            onReveal: context.revealNote,
                            onMoveToTrash: moveLifecycleItemToTrash,
                            onDeletePermanently: deleteLifecycleItemPermanently
                        )
                        .padding(.horizontal, ScholiumMetrics.Library.contentInset)
                        .transition(.opacity)
                    }
                }
            }
            .padding(.top, ScholiumGrid.Spacing.labelAccessoryGap)
            .frame(maxHeight: .infinity)
            .background(ScholiumColorRole.surfaceBackground.color)

            sidebarBottomRegion
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .animation(
            ScholiumMotion.disclosure(reduceMotion: reduceMotion),
            value: lifecycleDestinationScope
        )
        .onChange(of: context.libraryFocusRequestGeneration) { _, _ in
            libraryFocused = true
        }
        .onChange(of: lifecycleDestinationScope) { _, scope in
            guard scope != nil else { return }
            lifecycleBackFocused = true
        }
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
        .task(id: lifecycleDestinationReloadID) {
            guard let scope = lifecycleDestinationScope else { return }
            await reloadLifecycleDestination(scope)
        }
        .onChange(of: context.noteLifecycleRequest) { _, request in
            guard request == nil, let path = preparedLifecyclePath else { return }
            context.clearPreparedLifecycle(path)
            preparedLifecyclePath = nil
            if let scope = lifecycleDestinationScope {
                Task {
                    await reloadLifecycleDestination(scope)
                    restoreLifecycleFocusAfterMutation()
                }
            }
        }
        .onExitCommand {
            guard lifecycleDestinationScope != nil else { return }
            closeLifecycleDestination()
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

    // MARK: - Search

    private var triptychIdentity: some View {
        Menu {
            Button(action: context.openSettings) {
                Label("Manage Triptychs…", systemImage: "folder.badge.gearshape")
            }
            Button(action: context.revealCurrentVault) {
                Label("Reveal Current Vault in Finder", systemImage: "folder")
            }
        } label: {
            Text("Scholium")
                .font(ScholiumInterfaceTypography.identity)
                .padding(.trailing, 13)
                .foregroundStyle(ScholiumColorRole.primaryText.color)
                .fixedSize()
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .overlay(alignment: .trailing) {
            Text("⌄")
                .font(.caption.weight(.medium))
                .foregroundStyle(ScholiumColorRole.primaryText.color)
                .allowsHitTesting(false)
        }
        .fixedSize()
        .padding(.horizontal, ScholiumMetrics.Library.contentInset)
        .frame(
            maxWidth: .infinity,
            minHeight: ScholiumMetrics.Workspace.regionHeaderHeight,
            maxHeight: ScholiumMetrics.Workspace.regionHeaderHeight,
            alignment: .leading
        )
        .help("Triptych management")
        .accessibilityLabel("Triptych management — \(context.triptychName)")
        .accessibilityIdentifier("scholium.triptychManagement")
    }

    @ViewBuilder
    private var sidebarBottomRegion: some View {
        VStack(spacing: 0) {
            ScholiumStructuralRule()
                .padding(.horizontal, ScholiumMetrics.Library.contentInset)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)

            SidebarRecommendedBibliographySection(
                controller: context.bibliographyController,
                openAnalysis: context.openRecommendedAnalysis,
                openZoteroItem: context.openRecommendedZoteroItem,
                copyText: context.copyRecommendedBibliographyText,
                repairMethod: context.repairRecommendedBibliographyMethod
            )
            .padding(.horizontal, ScholiumMetrics.Library.contentInset)
            .padding(.bottom, ScholiumGrid.Spacing.inlineControlGap)

            ScholiumStructuralRule()
                .padding(.horizontal, ScholiumMetrics.Library.contentInset)
            lifecycleNavigation
        }
        .scholiumSurface(.navigation)
    }

    private var libraryHeader: some View {
        ZStack(alignment: .leading) {
            ordinaryLibraryHeader
                .opacity(lifecycleDestinationScope == nil ? 1 : 0)
                .allowsHitTesting(lifecycleDestinationScope == nil)
                .accessibilityHidden(lifecycleDestinationScope != nil)

            lifecycleDestinationHeader
                .opacity(lifecycleDestinationScope == nil ? 0 : 1)
                .allowsHitTesting(lifecycleDestinationScope != nil)
                .accessibilityHidden(lifecycleDestinationScope == nil)
        }
        .frame(height: ScholiumMetrics.Accessibility.preferredCustomTarget)
        .animation(
            ScholiumMotion.disclosure(reduceMotion: reduceMotion),
            value: lifecycleDestinationScope
        )
    }

    private var ordinaryLibraryHeader: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Button {
                context.selectLocationScope(.workspace)
            } label: {
                Text("LIBRARY")
                    .font(ScholiumInterfaceTypography.editorialLabel)
                    .tracking(0.7)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(
                controller.library.locationScope == .workspace ? .isSelected : []
            )
            .accessibilityIdentifier("scholium.libraryHeading")

            Spacer()

            libraryFilterMenu

            Button {
                controller.requestLifecycle(.create)
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
            .help("New Note")
            .accessibilityIdentifier("scholium.newNote")
        }
        .frame(maxWidth: .infinity)
    }

    private var lifecycleDestinationHeader: some View {
        let scope = lifecycleDestinationScope ?? .setAside
        let heading = lifecycleDestinationHeading(scope)

        return HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Button(action: closeLifecycleDestination) {
                Image(systemName: "chevron.backward")
                    .frame(
                        width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                        height: ScholiumMetrics.Accessibility.preferredCustomTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($lifecycleBackFocused)
            .help("Back to Library")
            .accessibilityLabel("Back to Library")
            .accessibilityIdentifier("scholium.lifecycleBack")

            HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text(lifecycleDestinationVisualTitle(scope))
                    .font(ScholiumInterfaceTypography.editorialLabel)
                    .tracking(0.7)

                if lifecycleDestinationShowsCount {
                    Text(localizedNoteCount(lifecycleDestinationItems.count))
                        .font(ScholiumInterfaceTypography.metadata.monospacedDigit())
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                }
            }
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(heading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(lifecycleHeadingIdentifier(scope))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var attentionNavigation: some View {
        Button {
            if lifecycleDestinationScope != nil {
                controller.showAttentionQueue(true)
            } else {
                controller.showAttentionQueue(!controller.library.showsAttentionQueue)
            }
        } label: {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Image(systemName: "tray.full")
                    .foregroundStyle(hasVisibleAttention ? Color.orange : Color.secondary)
                    .frame(width: ScholiumMetrics.Library.navigationIconWidth)
                Text("ATTENTION")
                    .font(ScholiumInterfaceTypography.editorialLabel)
                    .tracking(0.7)
                Spacer()
                if let count = visibleAttentionCount {
                    Text(count.formatted())
                        .font(ScholiumInterfaceTypography.metadata.monospacedDigit())
                        .foregroundStyle(count > 0 ? Color.orange : Color.secondary)
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(controller.library.showsAttentionQueue ? .isSelected : [])
        .help("Review derived warnings and recoverable research issues")
        .accessibilityValue(visibleAttentionCount.map { "\($0) items" } ?? "Loading")
        .accessibilityIdentifier("scholium.location.attention")
    }

    private var lifecycleNavigation: some View {
        HStack(spacing: 0) {
            locationButton(.setAside, symbol: "archivebox")
                .frame(maxWidth: .infinity)
            locationButton(.trash, symbol: "trash")
                .frame(maxWidth: .infinity)
            ScholiumInkIconControl(
                title: "Settings",
                systemImage: "gearshape",
                identifier: "scholium.location.settings",
                action: context.openSettings
            )
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ScholiumMetrics.Library.contentInset)
        .frame(height: ScholiumMetrics.Workspace.libraryFooterHeight)
    }

    private func locationButton(_ scope: NoteLocationScope, symbol: String) -> some View {
        let isActive = lifecycleDestinationScope == scope
        return ScholiumInkIconControl(
            title: lifecycleDestinationName(scope),
            systemImage: isActive ? "\(symbol).fill" : symbol,
            identifier: scope == .setAside
                ? "scholium.location.setAside"
                : "scholium.location.trash",
            isActive: isActive,
            action: { openLifecycleDestination(scope) }
        )
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var displayedFolderTree: [TreeNode] {
        if lifecycleDestinationScope != nil, !capturedWorkspaceNotes.isEmpty {
            return buildTree(
                from: capturedWorkspaceNotes,
                notesAreOrdered: context.notesAreOrdered
            )
        }
        return folderTree
    }

    private var lifecycleDestinationReloadID: String {
        "\(lifecycleDestinationScope?.rawValue ?? "closed"):\(context.lifecycleMutationGeneration)"
    }

    private func captureWorkspaceSnapshotIfNeeded() {
        guard controller.library.locationScope == .workspace else { return }
        controller.captureWorkspaceNotes(filteredNotes)
    }

    private func openLifecycleDestination(_ scope: NoteLocationScope) {
        guard scope == .setAside || scope == .trash else { return }
        if lifecycleDestinationScope == scope {
            closeLifecycleDestination()
            return
        }
        captureWorkspaceSnapshotIfNeeded()
        controller.presentLifecycleListing(scope)
    }

    private func closeLifecycleDestination() {
        pendingLifecycleFocusPlan = nil
        requestedLifecyclePutBackFocusPath = nil
        controller.dismissLifecycleListing()
        if controller.library.locationScope != .workspace {
            restoreWorkspaceAfterTransientScope()
        }
    }

    private func reloadLifecycleDestination(_ scope: NoteLocationScope) async {
        let request = controller.beginLifecycleListing(scope)
        do {
            let items = try await context.lifecycleItems(scope)
            guard lifecycleDestinationScope == scope, !Task.isCancelled else { return }
            controller.receiveLifecycleItems(items, for: request)
        } catch {
            guard lifecycleDestinationScope == scope, !Task.isCancelled else { return }
            controller.failLifecycleListing(error.localizedDescription, for: request)
        }
    }

    private func preparePutBack(_ item: LifecycleLocationItem) {
        pendingLifecycleFocusPlan = lifecycleFocusPlan(removing: item)
        context.prepareLifecycle(item)
        preparedLifecyclePath = item.note.relativePath
        controller.requestLifecycle(.putBack(item.note.relativePath))
    }

    private var lifecycleDestinationShowsCount: Bool {
        !lifecycleDestinationIsLoading && lifecycleDestinationError == nil
    }

    private func lifecycleDestinationName(_ scope: NoteLocationScope) -> String {
        switch scope {
        case .setAside: ScholiumL10n.string("Set Aside", locale: locale)
        case .trash: ScholiumL10n.string("Trash", locale: locale)
        case .workspace: ScholiumL10n.string("Library", locale: locale)
        case .unclassified: ScholiumL10n.string("Unclassified", locale: locale)
        }
    }

    private func lifecycleDestinationVisualTitle(_ scope: NoteLocationScope) -> String {
        switch scope {
        case .setAside: ScholiumL10n.string("SET ASIDE", locale: locale)
        case .trash: ScholiumL10n.string("TRASH", locale: locale)
        case .workspace: ScholiumL10n.string("LIBRARY", locale: locale)
        case .unclassified: ScholiumL10n.string("Unclassified", locale: locale)
        }
    }

    private func lifecycleHeadingIdentifier(_ scope: NoteLocationScope) -> String {
        scope == .trash
            ? "scholium.lifecycleHeading.trash"
            : "scholium.lifecycleHeading.setAside"
    }

    private func lifecycleDestinationHeading(_ scope: NoteLocationScope) -> String {
        let name = lifecycleDestinationName(scope)
        guard lifecycleDestinationShowsCount else { return name }
        return "\(name), \(localizedNoteCount(lifecycleDestinationItems.count))"
    }

    private func localizedNoteCount(_ count: Int) -> String {
        if count == 1 {
            return ScholiumL10n.string("1 note", locale: locale)
        }
        return String(
            format: ScholiumL10n.string("%lld notes", locale: locale),
            locale: locale,
            arguments: [Int64(count)]
        )
    }

    private func lifecycleFocusPlan(
        removing item: LifecycleLocationItem
    ) -> LifecycleDestinationFocusPlan {
        guard let index = lifecycleDestinationItems.firstIndex(where: { $0.id == item.id }) else {
            return LifecycleDestinationFocusPlan(
                originPath: item.note.relativePath,
                successorPath: nil
            )
        }
        let successor: LifecycleLocationItem? = if lifecycleDestinationItems.indices.contains(index + 1) {
            lifecycleDestinationItems[index + 1]
        } else if index > lifecycleDestinationItems.startIndex {
            lifecycleDestinationItems[index - 1]
        } else {
            nil
        }
        return LifecycleDestinationFocusPlan(
            originPath: item.note.relativePath,
            successorPath: successor?.note.relativePath
        )
    }

    private func restoreLifecycleFocusAfterMutation() {
        guard let plan = pendingLifecycleFocusPlan else { return }
        pendingLifecycleFocusPlan = nil

        if lifecycleDestinationItems.contains(where: { $0.note.relativePath == plan.originPath }) {
            requestedLifecyclePutBackFocusPath = plan.originPath
        } else if let successorPath = plan.successorPath,
                  lifecycleDestinationItems.contains(where: { $0.note.relativePath == successorPath }) {
            requestedLifecyclePutBackFocusPath = successorPath
        } else if let firstPath = lifecycleDestinationItems.first?.note.relativePath {
            requestedLifecyclePutBackFocusPath = firstPath
        } else {
            lifecycleBackFocused = true
        }
    }

    private func restoreWorkspaceAfterTransientScope() {
        context.selectLocationScope(.workspace)
    }

    // MARK: - Knowledge Base Picker

    private var workspaceVaultPicker: some View {
        HStack(spacing: 2) {
            ForEach(WorkspaceVaultSlot.allCases) { slot in
                Button {
                    guard !isCurrent(slot) else { return }
                    context.selectWorkspaceVault(slot)
                } label: {
                    Text(ScholiumL10n.dynamicString(slot.displayName))
                        .font(.callout)
                        .foregroundStyle(ScholiumColorRole.primaryText.color)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    isCurrent(slot)
                        ? ScholiumColorRole.surfaceBackground.color
                        : Color.clear,
                    in: RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialControlCornerRadius,
                        style: .continuous
                    )
                )
                .accessibilityAddTraits(isCurrent(slot) ? .isSelected : [])
                .accessibilityLabel(ScholiumL10n.dynamicString(slot.displayName))
                .accessibilityIdentifier("scholium.vault.\(slot.rawValue)")
            }
        }
        .padding(2)
        .background(
            ScholiumColorRole.raisedSurfaceBackground.color.opacity(0.35),
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                style: .continuous
            )
        )
    }

    private func isCurrent(_ slot: WorkspaceVaultSlot) -> Bool {
        context.currentWorkspaceSlot == slot
    }

    private var currentWorkspaceSlot: WorkspaceVaultSlot? {
        context.currentWorkspaceSlot
    }

    // MARK: - Filter Menu

    private var libraryFilterMenu: some View {
        Menu {
            Section("Review") {
                Menu("Review State") {
                    if context.currentVaultRole.allowsHumanReview {
                        Toggle("Unreviewed", isOn: filterBinding(\.isReviewed))
                        if context.hasUnqualifiedReview {
                            Toggle("Unqualified", isOn: filterBinding(\.isUnqualified))
                        }
                    }
                    Toggle("Changed Since Review", isOn: filterBinding(\.isChangedSinceReview))
                        .accessibilityIdentifier("scholium.researchFilter.changedSinceReview")
                }
            }

            Section("Integrity") {
                Menu("Integrity Checks") {
                    Toggle("Needs Attention", isOn: filterBinding(\.needsAttention))
                        .disabled(!context.catalogIsAvailable)
                        .accessibilityIdentifier("scholium.researchFilter.needsAttention")
                    Toggle("Explicit Connections", isOn: filterBinding(\.hasExplicitConnections))
                        .disabled(!context.graphIsAvailable)
                        .accessibilityIdentifier("scholium.researchFilter.explicitConnections")
                    Toggle("Malformed Metadata", isOn: filterBinding(\.hasMalformedMetadata))
                        .disabled(!context.catalogIsAvailable)
                        .accessibilityIdentifier("scholium.researchFilter.malformedMetadata")
                }
            }

            Section("Metadata") {
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
            }

            if !context.propertyKeys.isEmpty {
                Section("Properties") {
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
            }

            Section("Order") {
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
            }

            Section("Actions") {
                if activeResearchFilterCount > 0 {
                    Button("Clear Review and Integrity Filters", action: clearResearchFilters)
                }
                if activeMetadataFilterCount > 0 {
                    Button("Clear Metadata Filters", action: clearMetadataFilters)
                }
                if activeLibraryMenuFilterCount > 0 {
                    Button("Clear All Filters") {
                        clearResearchFilters()
                        updateFilters { $0.tag = nil }
                        clearMetadataFilters()
                    }
                }

                Button("Classify Imported Notes…") {
                    captureWorkspaceSnapshotIfNeeded()
                    controller.showUnclassified(true)
                    context.selectLocationScope(.unclassified)
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
        .fixedSize()
        .help(libraryFilterHelp)
        .accessibilityLabel("Library filters")
        .accessibilityValue(libraryFilterAccessibilityValue)
        .accessibilityIdentifier("scholium.libraryFilters")
    }

    private var activeLibraryMenuFilterCount: Int {
        activeResearchFilterCount
            + activeMetadataFilterCount
            + (controller.library.filters.tag == nil ? 0 : 1)
    }

    private var activeResearchFilterCount: Int {
        let filters = controller.library.filters
        return [
            filters.isReviewed,
            filters.isUnqualified,
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
            $0.isReviewed = false
            $0.isUnqualified = false
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
        pendingLifecycleFocusPlan = lifecycleFocusPlan(removing: item)
        Task {
            do {
                context.prepareLifecycle(item)
                defer { context.clearPreparedLifecycle(item.note.relativePath) }
                try await context.moveToTrash(item.note.relativePath)
                await reloadLifecycleDestination(.setAside)
                restoreLifecycleFocusAfterMutation()
            } catch {
                restoreLifecycleFocusAfterMutation()
                context.showError(
                    "Could not move this note to Trash. \(error.localizedDescription)"
                )
            }
        }
    }

    private func deleteLifecycleItemPermanently(_ item: LifecycleLocationItem) {
        pendingLifecycleFocusPlan = lifecycleFocusPlan(removing: item)
        Task {
            do {
                context.prepareLifecycle(item)
                defer { context.clearPreparedLifecycle(item.note.relativePath) }
                try await context.deletePermanently(item.note.relativePath)
                await reloadLifecycleDestination(.trash)
                restoreLifecycleFocusAfterMutation()
            } catch {
                restoreLifecycleFocusAfterMutation()
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

struct SidebarLifecycleDestinationView: View {
    @Environment(\.locale) private var locale
    let scope: NoteLocationScope
    let items: [LifecycleLocationItem]
    let isLoading: Bool
    let errorMessage: String?
    let requestedPutBackFocusPath: String?
    let onFocusRequestHandled: () -> Void
    let onRequestPutBackFocus: (String) -> Void
    let onReload: () async -> Void
    let onOpen: (LifecycleLocationItem) -> Void
    let onPutBack: (LifecycleLocationItem) -> Void
    let onReveal: (String) -> Void
    let onMoveToTrash: (LifecycleLocationItem) -> Void
    let onDeletePermanently: (LifecycleLocationItem) -> Void

    @State private var pendingPermanentDeletion: LifecycleLocationItem?

    var body: some View {
        Group {
            if isLoading {
                loadingState
            } else if let errorMessage {
                errorState(errorMessage)
            } else if items.isEmpty {
                emptyState
            } else {
                lifecycleList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ScholiumColorRole.surfaceBackground.color)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(destinationIdentifier)
        .confirmationDialog(
            "Delete Permanently?",
            isPresented: Binding(
                get: { pendingPermanentDeletion != nil },
                set: { isPresented in
                    guard !isPresented, let item = pendingPermanentDeletion else { return }
                    pendingPermanentDeletion = nil
                    onRequestPutBackFocus(item.note.relativePath)
                }
            ),
            titleVisibility: .visible
        ) {
            if let item = pendingPermanentDeletion {
                Button("Delete Permanently", role: .destructive) {
                    deletePermanently(item)
                }
            }
            Button("Cancel", role: .cancel) {
                guard let item = pendingPermanentDeletion else { return }
                pendingPermanentDeletion = nil
                onRequestPutBackFocus(item.note.relativePath)
            }
        } message: {
            Text("This cannot be undone. Scholium removes the note, its Review and comments, Dialogue records, Critique association, stable identity, Research Record, and every Triptych checkpoint containing it.")
        }
    }

    private var lifecycleList: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    SidebarLifecycleDestinationRow(
                        scope: scope,
                        item: item,
                        requestedPutBackFocusPath: requestedPutBackFocusPath,
                        onFocusRequestHandled: onFocusRequestHandled,
                        onOpen: { onOpen(item) },
                        onPutBack: { onPutBack(item) },
                        onReveal: { onReveal(item.note.relativePath) },
                        onMoveToTrash: { onMoveToTrash(item) },
                        onRequestPermanentDeletion: {
                            pendingPermanentDeletion = item
                        }
                    )
                    if item.id != items.last?.id {
                        ScholiumStructuralRule()
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }

    private var loadingState: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(openingLabel)
            Spacer(minLength: 0)
        }
        .padding(.top, ScholiumGrid.Spacing.inlineControlGap)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Image(systemName: scope == .trash ? "trash" : "archivebox")
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .accessibilityHidden(true)
            Text(emptyTitle)
                .font(ScholiumInterfaceTypography.rowTitle)
            Text(emptyDetail)
                .font(ScholiumInterfaceTypography.metadata)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, ScholiumGrid.Spacing.sectionSeparation)
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Label(errorTitle, systemImage: "exclamationmark.triangle")
                .font(ScholiumInterfaceTypography.rowTitle)
            Text(message)
                .font(ScholiumInterfaceTypography.metadata)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry") { Task { await onReload() } }
                .accessibilityIdentifier("scholium.lifecycleRetry")
        }
        .padding(.top, ScholiumGrid.Spacing.sectionSeparation)
    }

    private var destinationIdentifier: String {
        scope == .trash
            ? "scholium.lifecycleDestination.trash"
            : "scholium.lifecycleDestination.setAside"
    }

    private var openingLabel: String {
        scope == .trash
            ? ScholiumL10n.string("Opening Trash…", locale: locale)
            : ScholiumL10n.string("Opening Set Aside…", locale: locale)
    }

    private var emptyTitle: String {
        scope == .trash
            ? ScholiumL10n.string("No Notes in Trash", locale: locale)
            : ScholiumL10n.string("No Set Aside Notes", locale: locale)
    }

    private var emptyDetail: String {
        scope == .trash
            ? ScholiumL10n.string(
                "Notes moved to Trash appear here until you put them back or delete them permanently.",
                locale: locale
            )
            : ScholiumL10n.string(
                "Notes you set aside appear here until you put them back.",
                locale: locale
            )
    }

    private var errorTitle: String {
        scope == .trash
            ? ScholiumL10n.string("Could Not Open Trash", locale: locale)
            : ScholiumL10n.string("Could Not Open Set Aside", locale: locale)
    }

    private func deletePermanently(_ item: LifecycleLocationItem) {
        pendingPermanentDeletion = nil
        onDeletePermanently(item)
    }
}

private struct SidebarLifecycleDestinationRow: View {
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    let scope: NoteLocationScope
    let item: LifecycleLocationItem
    let requestedPutBackFocusPath: String?
    let onFocusRequestHandled: () -> Void
    let onOpen: () -> Void
    let onPutBack: () -> Void
    let onReveal: () -> Void
    let onMoveToTrash: () -> Void
    let onRequestPermanentDeletion: () -> Void

    @State private var isHovering = false
    @FocusState private var putBackHasKeyboardFocus: Bool
    @AccessibilityFocusState private var putBackHasAccessibilityFocus: Bool

    var body: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Button(action: onOpen) {
                Text(verbatim: noteTitle)
                    .font(ScholiumInterfaceTypography.libraryHierarchy)
                    .foregroundStyle(ScholiumColorRole.primaryText.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(noteTitle)
            .accessibilityHint(openHint)

            Button(action: onPutBack) {
                Image(systemName: "arrow.uturn.backward")
                    .frame(
                        width: ScholiumMetrics.Accessibility.minimumCustomTarget,
                        height: ScholiumMetrics.Accessibility.minimumCustomTarget
                    )
                    .contentShape(Rectangle())
                    .opacity(putBackGlyphIsVisible ? 1 : 0)
                    .animation(
                        ScholiumMotion.disclosure(reduceMotion: reduceMotion),
                        value: putBackGlyphIsVisible
                    )
            }
            .buttonStyle(.plain)
            .focused($putBackHasKeyboardFocus)
            .accessibilityFocused($putBackHasAccessibilityFocus)
            .help("Put Back…")
            .accessibilityLabel(putBackAccessibilityLabel)
            .accessibilityIdentifier(putBackIdentifier)
        }
        .frame(height: ScholiumMetrics.Library.hierarchyRowHeight)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(action: onPutBack) {
                Label("Put Back…", systemImage: "arrow.uturn.backward")
            }
            if scope == .setAside {
                Button(action: onMoveToTrash) {
                    Label("Move to Trash…", systemImage: "trash")
                }
            } else {
                Button(role: .destructive, action: onRequestPermanentDeletion) {
                    Label("Delete Permanently…", systemImage: "trash.slash")
                }
            }
            Divider()
            Button(action: onReveal) {
                Label("Reveal in Finder", systemImage: "folder")
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: requestedPutBackFocusPath) { _, requestedPath in
            guard requestedPath == item.note.relativePath else { return }
            putBackHasKeyboardFocus = true
            onFocusRequestHandled()
        }
    }

    private var noteTitle: String {
        item.note.title ?? item.note.displayName
    }

    private var putBackGlyphIsVisible: Bool {
        isHovering || putBackHasKeyboardFocus || putBackHasAccessibilityFocus
    }

    private var openHint: String {
        let destination = scope == .trash
            ? ScholiumL10n.string("Trash", locale: locale)
            : ScholiumL10n.string("Set Aside", locale: locale)
        return String(
            format: ScholiumL10n.string("Open note in %@", locale: locale),
            locale: locale,
            arguments: [destination]
        )
    }

    private var putBackAccessibilityLabel: String {
        String(
            format: ScholiumL10n.string("Put Back %@", locale: locale),
            locale: locale,
            arguments: [noteTitle]
        )
    }

    private var putBackIdentifier: String {
        let encodedPath = item.note.relativePath.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        ) ?? item.note.relativePath
        return "scholium.lifecyclePutBack.\(encodedPath)"
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
        .scholiumSurface(.denseEvidence)
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
                Text(ScholiumL10n.dynamicString(slot.displayName)).tag(slot)
            }
        }
        .labelsHidden()
        .frame(width: 130)
    }

    private var classifyButton: some View {
        Button("Classify") { performClassification() }
            .buttonStyle(.borderedProminent)
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
    let openNote: (WindowDocumentLocation, WindowOpenDisposition) -> Void
    let requestLifecycle: (NoteLifecycleRequest) -> Void
    let revealNote: (String) -> Void
    let setAside: (String) async throws -> Void
    let moveToTrash: (String) async throws -> Void
    let deletePermanently: (String) async throws -> Void
    let showError: (String) -> Void
}

private struct TreeNodeView: View {
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    let node: TreeNode
    @Binding var expandedFolders: Set<String>
    let selectedDocumentPath: String?
    let context: SidebarTreeContext
    let onSelect: (WindowDocumentLocation) -> Void

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
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 12)
                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                        Text(node.name)
                            .font(ScholiumInterfaceTypography.libraryHierarchy)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.leading, CGFloat(node.depth * 12 + 8))
                    .padding(.trailing, 8)
                    .frame(height: ScholiumMetrics.Library.hierarchyRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("scholium.folderRow.\(node.id)")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

                // Children
                if isExpanded {
                    ForEach(node.children) { child in
                        TreeNodeView(
                            node: child,
                            expandedFolders: $expandedFolders,
                            selectedDocumentPath: selectedDocumentPath,
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
                onSelect(note)
            } label: {
                NoteCardRow(
                    note: note,
                    isActive: selectedDocumentPath == note.relativePath,
                    vaultRole: context.currentVaultRole,
                    reviewDisplayState: context.reviewDisplayState(note.relativePath)
                )
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
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
                        context.openNote(note, .newTab)
                    } label: {
                        Label("Open in New Tab", systemImage: "plus.square")
                    }
                    Divider()
                    if context.locationScope == .workspace {
                        let lifecycleTarget = NoteLifecycleTarget(note)
                        if !CritiquePlacement.isManagedCritiquePath(note.relativePath) {
                            Button {
                                guard let lifecycleTarget else { return }
                                context.requestLifecycle(.duplicate(lifecycleTarget))
                            } label: {
                                Label("Duplicate…", systemImage: "plus.square.on.square")
                            }
                            .disabled(!hasResolvedIdentity(note) || lifecycleTarget == nil)
                        }
                        Button {
                            guard let lifecycleTarget else { return }
                            context.requestLifecycle(.move(lifecycleTarget))
                        } label: {
                            Label("Move or Rename…", systemImage: "folder")
                        }
                        .disabled(!hasResolvedIdentity(note) || lifecycleTarget == nil)
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
        case .delete: "Permanently delete ‘\(note.title ?? note.displayName)’? This removes its comments, Human Review, Dialogue records, Critique association, stable identity, Research Record, and every Triptych checkpoint containing it. This cannot be undone."
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

    var body: some View {
        HStack(spacing: 6) {
            if vaultRole.allowsHumanReview {
                Image(systemName: reviewBadgeSymbol)
                    .font(.system(size: 10))
                    .foregroundStyle(reviewBadgeColor)
                    .help(reviewBadgeLabel)
                    .accessibilityLabel(reviewBadgeLabel)
            } else if let status = note.status,
                      !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(ScholiumColorRole.information.color)
                    .help(status.capitalized)
                    .accessibilityLabel(status.capitalized)
            }

            Text(note.title ?? note.displayName)
                .font(ScholiumInterfaceTypography.libraryNoteTitle)
                .fontWeight(isActive ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: ScholiumMetrics.Library.hierarchyRowHeight)
        .background(
            isActive ? ScholiumColorRole.raisedSurfaceBackground.color : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(ScholiumColorRole.accent.color)
                    .frame(width: 3)
                    .padding(.vertical, 5)
                    .accessibilityHidden(true)
            }
        }
        .focusEffectDisabled()
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .help(note.title ?? note.displayName)
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
        case .notReviewed: ScholiumColorRole.mutedText.color.opacity(0.4)
        case .reviewed: ScholiumColorRole.secondaryText.color
        case .qualified: ScholiumColorRole.confirmed.color
        case .unqualified: ScholiumColorRole.destructive.color
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
