import ScholiumContracts
import Combine
import Foundation

enum AttentionPopoverAnchor: String, Equatable, Sendable {
    case sidebar
    case inspector
}

enum AttentionQueuePopoverAnchor: Equatable, Sendable {
    case sidebar
    case inspector

    var popoverAnchor: AttentionPopoverAnchor {
        switch self {
        case .sidebar: .sidebar
        case .inspector: .inspector
        }
    }
}

/// One window-level Notifications request either opens the complete queue from
/// a stable anchor or expands the Document's shared notification stack in
/// place when Action activity requires attention.
enum AttentionPresentationRequest: Equatable, Sendable {
    case queue(
        anchor: AttentionQueuePopoverAnchor,
        workspaceSlot: WorkspaceVaultSlot?,
        noteScope: VaultQualifiedNoteID?
    )
    case actionStack
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
        let settlementRequirementChanges:
            AnyPublisher<[WorkspaceSettlementRequirement], Never>
        let refresh: @MainActor () async -> Void
        let resynthesize: @MainActor (AttentionQueueItem) -> Void
        let openAction: @MainActor (ResearchActivityNotification) -> Void
        let endAction: @MainActor (ResearchActivityNotification) -> Void
        let reviewResult: @MainActor (ResearchActivityNotification) -> Void
        let followUp: @MainActor (ResearchActivityNotification) -> Void
        let dismissActivity: @MainActor (ResearchActivityNotification) -> Void
        let reviewChanges: @MainActor (WorkspaceSettlementRequirement) -> Void
    }

    @Published private(set) var presentedAnchor: AttentionPopoverAnchor?
    @Published private(set) var dismissalDays: Int
    @Published private(set) var activityNotifications:
        [ResearchActivityNotification] = []
    @Published private(set) var settlementRequirements:
        [WorkspaceSettlementRequirement] = []

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
            }
            .store(in: &observations)
        dependencies.settlementRequirementChanges
            .removeDuplicates()
            .sink { [weak self] requirements in
                self?.settlementRequirements = requirements
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

    func presentQueue(
        anchor: AttentionQueuePopoverAnchor,
        workspaceSlot: WorkspaceVaultSlot?,
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
        presentedAnchor = anchor.popoverAnchor
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
        guard presentation.notificationFilter.showsActivities else { return [] }
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

    func visibleSettlementRequirements(
        for presentation: AttentionPresentationState,
        locale: Locale = .current
    ) -> [WorkspaceSettlementRequirement] {
        guard presentation.notificationFilter.showsSettlements else { return [] }
        let workspaceVaultID = presentation.workspaceSlot.flatMap {
            workspaceController.state.assignment?.vault(for: $0)?.id
        }
        let query = presentation.filter.query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: locale
            )
        return settlementRequirements.filter { requirement in
            if let workspaceVaultID,
               requirement.note.vaultID != workspaceVaultID {
                return false
            }
            if let noteScope = presentation.noteScope,
               requirement.note != noteScope {
                return false
            }
            guard !query.isEmpty else { return true }
            let searchable = [
                ScholiumL10n.string("Current Revision Not Settled", locale: locale),
                ScholiumL10n.string("Review Changes", locale: locale),
                ScholiumL10n.string("Settle", locale: locale),
                requirement.title,
                requirement.note.relativePath,
            ].joined(separator: " ")
            return searchable.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: locale
            ).contains(query)
        }
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

    func reviewChanges(_ requirement: WorkspaceSettlementRequirement) {
        dismiss()
        dependencies.reviewChanges(requirement)
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
        filter: AttentionQueueFilter,
        locale: Locale = .current
    ) -> [ResearchActivityNotification] {
        let query = normalized(filter.query, locale: locale)
        return notifications.filter { notification in
            if let noteID,
               notification.targetNoteID != noteID,
               !notification.affectedNotes.contains(where: { $0.noteID == noteID }) {
                return false
            }
            guard !query.isEmpty else { return true }
            let searchable = [
                ResearchActivityNotificationCopy.stateTitle(
                    notification.state,
                    locale: locale
                ),
                ResearchActivityNotificationCopy.actionTitle(
                    notification.actionID,
                    locale: locale
                ),
                notification.targetTitle,
                notification.affectedNotes.map(\.title).joined(separator: " "),
            ].joined(separator: " ")
            return normalized(searchable, locale: locale).contains(query)
        }
    }

    private static func normalized(_ value: String, locale: Locale) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
    }
}

enum ResearchActivityNotificationCopy {
    static func actionTitle(
        _ actionID: ResearchActionID,
        locale: Locale = .current
    ) -> String {
        switch actionID {
        case .discuss:
            ScholiumL10n.string("Discuss", locale: locale)
        case .analyze:
            ScholiumL10n.string("Analyze", locale: locale)
        case .synthesize:
            ScholiumL10n.string("Synthesize", locale: locale)
        case .write:
            ScholiumL10n.string("Write", locale: locale)
        case .critique:
            ScholiumL10n.string("Critique", locale: locale)
        case .checkFidelity:
            ScholiumL10n.string("Check Fidelity", locale: locale)
        }
    }

    static func stateTitle(
        _ state: ResearchActivityNotificationState,
        locale: Locale = .current
    ) -> String {
        switch state {
        case .waitingForAgent:
            ScholiumL10n.string("Waiting for Agent", locale: locale)
        case .running:
            ScholiumL10n.string("Running", locale: locale)
        case .needsAttention:
            ScholiumL10n.string("Needs Attention", locale: locale)
        case .resultReady:
            ScholiumL10n.string("Result Ready", locale: locale)
        case .recoveryRequired:
            ScholiumL10n.string("Recovery Required", locale: locale)
        }
    }
}
