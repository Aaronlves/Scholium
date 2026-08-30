import ScholiumContracts
import Combine
import Foundation

enum AttentionPopoverAnchor: String, Equatable, Sendable {
    case sidebar
    case inspector
    case activityStack
}

/// Exact-Workspace adapter for the transient Notifications popover. It observes
/// only the owners whose state appears in the popover and borrows closed
/// refresh/navigation effects from the window composition root. It never
/// searches global windows, broadcasts notifications, or duplicates queue
/// ownership.
@MainActor
final class AttentionPopoverSession: ObservableObject {
    struct Dependencies {
        let dismissalDaysChanges: AnyPublisher<Int, Never>
        let activityChanges: AnyPublisher<[ResearchActivityNotification], Never>
        let refresh: @MainActor () async -> Void
        let resynthesize: @MainActor (AttentionQueueItem) -> Void
        let openAction: @MainActor (ResearchActivityNotification) -> Void
        let endAction: @MainActor (ResearchActivityNotification) -> Void
        let reviewResult: @MainActor (ResearchActivityNotification) -> Void
        let followUp: @MainActor (ResearchActivityNotification) -> Void
        let dismissActivity: @MainActor (ResearchActivityNotification) -> Void
    }

    @Published private(set) var presentedAnchor: AttentionPopoverAnchor?
    @Published private(set) var dismissalDays: Int
    @Published private(set) var activityNotifications:
        [ResearchActivityNotification] = []

    let presentation: AttentionPresentationState
    private let discoveryController: DiscoveryController
    private let workspaceController: WindowWorkspaceController
    private let projectionController: WindowWorkspaceProjectionController
    private let dependencies: Dependencies
    private var observations: Set<AnyCancellable> = []

    init(
        presentation: AttentionPresentationState,
        discoveryController: DiscoveryController,
        workspaceController: WindowWorkspaceController,
        projectionController: WindowWorkspaceProjectionController,
        dismissalDays: Int,
        dependencies: Dependencies
    ) {
        self.presentation = presentation
        self.discoveryController = discoveryController
        self.workspaceController = workspaceController
        self.projectionController = projectionController
        self.dismissalDays = AttentionPreferences.normalizedDays(dismissalDays)
        self.dependencies = dependencies

        workspaceController.$state
            .map(\.assignment)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &observations)
        projectionController.$state
            .dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &observations)
        dependencies.dismissalDaysChanges
            .map(AttentionPreferences.normalizedDays)
            .removeDuplicates()
            .sink { [weak self] days in
                guard self?.dismissalDays != days else { return }
                self?.dismissalDays = days
            }
            .store(in: &observations)
        dependencies.activityChanges
            .removeDuplicates()
            .sink { [weak self] notifications in
                guard let self else { return }
                activityNotifications = notifications
                if presentedAnchor == .activityStack,
                   !notifications.contains(where: {
                       $0.state.requiresResearcherAttention
                   }) {
                    dismiss()
                }
            }
            .store(in: &observations)
    }

    var isRefreshing: Bool {
        projectionController.isRefreshingCatalog
    }

    var catalogIsAvailable: Bool {
        projectionController.catalog != nil
    }

    var catalogError: String? {
        projectionController.catalogError
    }

    var derivedRefreshStatus: WorkspaceDerivedRefreshStatus? {
        projectionController.derivedRefreshStatus
    }

    func present(
        from anchor: AttentionPopoverAnchor,
        workspaceSlot: WorkspaceVaultSlot? = nil,
        noteScope: VaultQualifiedNoteID?
    ) {
        let resolvedWorkspaceSlot = workspaceSlot ?? noteScope.flatMap { note in
            workspaceController.state.assignment?.vaults.first(where: {
                $0.value.id == note.vaultID
            })?.key
        }
        presentation.present(
            workspaceSlot: resolvedWorkspaceSlot,
            noteScope: noteScope
        )
        presentedAnchor = anchor
    }

    func isPresented(from anchor: AttentionPopoverAnchor) -> Bool {
        presentedAnchor == anchor
    }

    func dismiss(resetFilter: Bool = false) {
        presentedAnchor = nil
        if resetFilter {
            presentation.resetForWorkspaceSwitch()
        }
    }

    func resetForWorkspaceSwitch() {
        dismiss(resetFilter: true)
    }

    func scopedItems(for presentation: AttentionPresentationState) -> [AttentionQueueItem] {
        return (projectionController.catalog?.attention ?? []).filter { item in
            if let workspaceSlot = presentation.workspaceSlot {
                guard let vaultID = workspaceController.state.assignment?
                        .vault(for: workspaceSlot)?.id,
                      item.note.vaultID == vaultID else { return false }
            }
            guard let noteScope = presentation.noteScope else { return true }
            return item.note.vaultID == noteScope.vaultID
                && item.note.relativePath == noteScope.relativePath
        }
    }

    func visibleActivityNotifications(
        for presentation: AttentionPresentationState
    ) -> [ResearchActivityNotification] {
        let noteID: UUID?
        if let noteScope = presentation.noteScope {
            noteID = ResearchActivityNotificationQuery.stableNoteID(
                for: noteScope,
                in: projectionController.catalog?.notes ?? []
            )
            guard noteID != nil else { return [] }
        } else {
            noteID = nil
        }
        return ResearchActivityNotificationQuery.apply(
            notifications: activityNotifications,
            noteID: noteID,
            filter: presentation.filter
        )
    }

    func noteTitle(for item: AttentionQueueItem) -> String {
        if let title = projectionController.catalog?.notes.first(where: {
            $0.reference.vaultID == item.note.vaultID
                && $0.reference.relativePath == item.note.relativePath
        })?.title, !title.isEmpty {
            return title
        }
        return URL(fileURLWithPath: item.note.relativePath)
            .deletingPathExtension().lastPathComponent
    }

    func refresh() async {
        await dependencies.refresh()
    }

    func inspect(_ item: AttentionQueueItem) {
        dismiss()
        let reference = item.synthesisMaterialChanged?.material ?? item.note
        discoveryController.requestOpen(
            reference,
            sourceLocator: item.synthesisMaterialChanged == nil ? item.locator : nil
        )
    }

    func resynthesize(_ item: AttentionQueueItem) {
        dismiss()
        dependencies.resynthesize(item)
    }

    func openAction(_ notification: ResearchActivityNotification) {
        dismiss()
        dependencies.openAction(notification)
    }

    func endAction(_ notification: ResearchActivityNotification) {
        dependencies.endAction(notification)
    }

    func reviewResult(_ notification: ResearchActivityNotification) {
        dismiss()
        dependencies.reviewResult(notification)
    }

    func followUp(_ notification: ResearchActivityNotification) {
        dismiss()
        dependencies.followUp(notification)
    }

    func dismissActivity(_ notification: ResearchActivityNotification) {
        dependencies.dismissActivity(notification)
    }
}

enum ResearchActivityNotificationQuery {
    static func stableNoteID(
        for noteScope: VaultQualifiedNoteID,
        in notes: [WorkspaceCatalogNote]
    ) -> UUID? {
        notes.first(where: {
            $0.reference.vaultID == noteScope.vaultID
                && $0.reference.relativePath == noteScope.relativePath
        })?.reference.stableNoteID.flatMap(UUID.init(uuidString:))
    }

    static func apply(
        notifications: [ResearchActivityNotification],
        noteID: UUID?,
        filter: AttentionQueueFilter
    ) -> [ResearchActivityNotification] {
        guard filter.kind == nil else { return [] }
        let query = normalized(filter.query)
        return notifications.filter { notification in
            if let noteID,
               notification.targetNoteID != noteID,
               !notification.affectedNotes.contains(where: { $0.noteID == noteID }) {
                return false
            }
            guard !query.isEmpty else { return true }
            let searchable = [
                stateTitle(notification.state),
                actionTitle(notification.actionID),
                notification.targetTitle,
                notification.affectedNotes.map(\.title).joined(separator: " "),
            ].joined(separator: " ")
            return normalized(searchable).contains(query)
        }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func stateTitle(_ state: ResearchActivityNotificationState) -> String {
        switch state {
        case .waitingForAgent: "Waiting for Agent"
        case .running: "Running"
        case .needsAttention: "Needs Attention"
        case .resultReady: "Result Ready"
        case .recoveryRequired: "Recovery Required"
        }
    }
}
