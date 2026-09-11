import Combine
import Foundation
import ScholiumContracts

enum AttentionPopoverAnchor: String, Equatable, Sendable {
    case toolbar
    case inspector
}

enum AttentionQueuePopoverAnchor: Equatable, Sendable {
    case toolbar
    case inspector

    var popoverAnchor: AttentionPopoverAnchor {
        switch self {
        case .toolbar: .toolbar
        case .inspector: .inspector
        }
    }
}

/// One window-level Notifications request opens the complete queue from a
/// stable anchor.
enum AttentionPresentationRequest: Equatable, Sendable {
    case queue(
        anchor: AttentionQueuePopoverAnchor,
        workspaceSlot: WorkspaceVaultSlot?,
        noteScope: VaultQualifiedNoteID?
    )
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
        let settlementRequirementChanges: AnyPublisher<[WorkspaceSettlementRequirement], Never>
        let agentChangeChanges: AnyPublisher<[AgentChange]?, Never>
        let agentChangeErrorChanges: AnyPublisher<String?, Never>
        let refresh: @MainActor () async -> Void
        let showAgentChange: @MainActor (UUID) -> Void
    }

    @Published private(set) var presentedAnchor: AttentionPopoverAnchor?
    @Published private(set) var dismissalDays: Int
    @Published private(set) var settlementRequirements: [WorkspaceSettlementRequirement] = []
    @Published private(set) var agentChanges: [AgentChange]?
    @Published private(set) var agentChangesError: String?
    @Published private var refreshInProgress = false

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
        dependencies.settlementRequirementChanges
            .removeDuplicates()
            .sink { [weak self] requirements in
                self?.settlementRequirements = requirements
            }
            .store(in: &observations)
        dependencies.agentChangeChanges
            .removeDuplicates()
            .sink { [weak self] changes in
                self?.agentChanges = changes
            }
            .store(in: &observations)
        dependencies.agentChangeErrorChanges
            .removeDuplicates()
            .sink { [weak self] error in
                self?.agentChangesError = error
            }
            .store(in: &observations)
    }

    var isRefreshing: Bool {
        refreshInProgress || projectionController.isRefreshingCatalog
    }

    var isLoadingInitialContent: Bool {
        (!catalogIsAvailable && catalogError == nil)
            || (agentChanges == nil && agentChangesError == nil)
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
        let resolvedWorkspaceSlot =
            workspaceSlot
            ?? noteScope.flatMap { note in
                workspaceController.state.assignment?.vaults.first(where: {
                    $0.value.id == note.vaultID
                })?.key
            }
        if anchor == .inspector {
            presentation.filter = AttentionQueueFilter()
            presentation.notificationFilter = .all
        }
        presentation.present(
            workspaceSlot: resolvedWorkspaceSlot,
            noteScope: noteScope
        )
        presentedAnchor = anchor.popoverAnchor
    }

    struct NoteSummary {
        let message: String
        let count: Int
    }

    /// A fresh, unfiltered projection, independent of the popover's last search.
    func noteSummary(
        for note: VaultQualifiedNoteID,
        ledger: AttentionDismissalLedger,
        locale: Locale = .current
    ) -> NoteSummary? {
        let scope = AttentionPresentationState()
        scope.present(workspaceSlot: nil, noteScope: note)
        let issues = ledger.visible(scopedItems(for: scope))
        let settlements = visibleSettlementRequirements(for: scope, locale: locale)
        let changes = visibleAgentChanges(for: scope, locale: locale)
        let count = issues.count + settlements.count + changes.count
        let message: String
        if let warning = issues.first(where: { $0.severity == .warning }) {
            message = AttentionIssueCopy.message(for: warning, locale: locale)
        } else if !settlements.isEmpty {
            message = ScholiumL10n.string("Current Revision Not Settled", locale: locale)
        } else if let issue = issues.first {
            message = AttentionIssueCopy.message(for: issue, locale: locale)
        } else if let error = agentChangesError ?? catalogError {
            return NoteSummary(message: error, count: count)
        } else if !changes.isEmpty {
            message = ScholiumL10n.string("Note Notifications", locale: locale)
        } else {
            return nil
        }
        return NoteSummary(message: message, count: count)
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
                guard
                    let vaultID = workspaceController.state.assignment?
                        .vault(for: workspaceSlot)?.id,
                    item.note.vaultID == vaultID
                else { return false }
            }
            guard let noteScope = presentation.noteScope else { return true }
            return item.note.vaultID == noteScope.vaultID
                && item.note.relativePath == noteScope.relativePath
        }
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
                requirement.note.vaultID != workspaceVaultID
            {
                return false
            }
            if let noteScope = presentation.noteScope,
                requirement.note != noteScope
            {
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

    func visibleAgentChanges(
        for presentation: AttentionPresentationState,
        locale: Locale = .current
    ) -> [AgentChange] {
        guard presentation.notificationFilter.showsAgentChanges else { return [] }
        let noteID = presentation.noteScope.flatMap(stableNoteID)
        let query = normalized(presentation.filter.query, locale: locale)
        return (agentChanges ?? []).filter { change in
            if let workspaceSlot = presentation.workspaceSlot,
                change.role != workspaceSlot.vaultRole
            {
                return false
            }
            if presentation.noteScope != nil, change.noteID != noteID {
                return false
            }
            guard !query.isEmpty else { return true }
            let searchable = [
                ScholiumL10n.localized(
                    AgentChangePresentation.operationTitle(for: change.operation),
                    locale: locale
                ),
                ScholiumL10n.localized(
                    AgentChangePresentation.stateTitle(
                        for: change,
                        endingRevisionState: endingRevisionState(for: change)
                    ),
                    locale: locale
                ),
                noteTitle(for: change),
                AgentChangePresentation.path(for: change),
                ScholiumL10n.dynamicString(change.role.displayName),
            ].joined(separator: " ")
            return normalized(searchable, locale: locale).contains(query)
        }
        .sorted(by: AgentChangePresentation.newestFirst)
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

    func noteTitle(for change: AgentChange) -> String {
        if let title = catalogNotes(for: change.noteID).first?.title,
            !title.isEmpty
        {
            return title
        }
        return AgentChangePresentation.displayName(for: change)
    }

    func endingRevisionState(
        for change: AgentChange
    ) -> AgentChangeEndingRevisionState? {
        guard let endingFingerprint = change.afterFingerprint else { return nil }
        let matches = catalogNotes(for: change.noteID)
        guard matches.count == 1 else { return .unavailable }
        return matches[0].fingerprint == endingFingerprint
            ? .current
            : .earlierRevision
    }

    func refresh() async {
        guard !refreshInProgress else { return }
        refreshInProgress = true
        defer { refreshInProgress = false }
        await dependencies.refresh()
    }

    func inspect(_ item: AttentionQueueItem) {
        dismiss()
        discoveryController.requestOpen(
            item.note,
            sourceLocator: item.locator
        )
    }

    func inspect(_ requirement: WorkspaceSettlementRequirement) {
        guard
            let vault = workspaceController.state.assignment?.vaults.values.first(where: {
                $0.id == requirement.note.vaultID
            })
        else { return }
        dismiss()
        discoveryController.requestOpen(
            VaultNoteReference(
                vaultID: requirement.note.vaultID,
                vaultName: vault.name,
                vaultRole: vault.role,
                relativePath: requirement.note.relativePath,
                stableNoteID: requirement.noteID.uuidString
            ),
            sourceLocator: nil
        )
    }

    func inspect(_ change: AgentChange) {
        dismiss()
        dependencies.showAgentChange(change.id)
    }

    private func stableNoteID(_ note: VaultQualifiedNoteID) -> UUID? {
        projectionController.catalog?.notes.first(where: {
            $0.reference.vaultID == note.vaultID
                && $0.reference.relativePath == note.relativePath
        })?.reference.stableNoteID.flatMap(UUID.init(uuidString:))
    }

    private func catalogNotes(for noteID: UUID) -> [WorkspaceCatalogNote] {
        projectionController.catalog?.notes.filter {
            $0.reference.stableNoteID.flatMap(UUID.init(uuidString:)) == noteID
        } ?? []
    }

    private func normalized(_ value: String, locale: Locale) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: locale
            )
    }

}
