import AppKit
import ScholiumContracts
import SwiftUI

struct ResearchActionFocusRequest: Equatable {
    let actionID: ResearchActionID
    let token: UUID

    init(actionID: ResearchActionID, token: UUID = UUID()) {
        self.actionID = actionID
        self.token = token
    }
}

/// Immutable projection for the current note's simplified Actions surface.
/// It contains current Action availability and deliberate researcher state,
/// never the removed activity chronology or transport details.
struct ResearchActionsPresentation {
    let items: [ResearchActionItemPresentation]
    let target: ResearchActionNoteSnapshot?
    let isCheckingAvailability: Bool
    let availabilityError: String?
    let cancellationRecoveries: [ResearchActionCancellationRecovery]
    let retryingCancellationRecoveryIDs: Set<UUID>
    let pendingCancellationBarrierCount: Int
    let latestSettlement: SettlementRecord?

    static let empty = Self(
        items: [],
        target: nil,
        isCheckingAvailability: false,
        availabilityError: nil,
        cancellationRecoveries: [],
        retryingCancellationRecoveryIDs: [],
        pendingCancellationBarrierCount: 0,
        latestSettlement: nil
    )

    static func make(
        target: ResearchActionNoteSnapshot?,
        availability: [ResearchActionAvailability],
        isCheckingAvailability: Bool = false,
        availabilityError: String? = nil,
        cancellationRecoveries: [ResearchActionCancellationRecovery] = [],
        retryingCancellationRecoveryIDs: Set<UUID> = [],
        pendingCancellationBarrierCount: Int = 0,
        endingActivityRunIDs: Set<UUID> = [],
        activeDiscussions: [PortableResearchDiscussion] = [],
        settlements: [SettlementRecord] = [],
        activities: [WorkspaceResearchActivity] = []
    ) -> Self {
        guard let target else {
            return Self(
                items: [],
                target: nil,
                isCheckingAvailability: false,
                availabilityError: nil,
                cancellationRecoveries: cancellationRecoveries,
                retryingCancellationRecoveryIDs: retryingCancellationRecoveryIDs,
                pendingCancellationBarrierCount: pendingCancellationBarrierCount,
                latestSettlement: nil
            )
        }
        let hasCancellationBarrier = pendingCancellationBarrierCount > 0
            || !cancellationRecoveries.isEmpty
        let availabilityIsUnconfirmed = isCheckingAvailability || availabilityError != nil
        let hasActiveDiscussion = activeDiscussions.contains {
            $0.primaryNoteID == target.noteID
                && $0.action != nil
                && $0.method != nil
        }
        var items = availability
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.id.rawValue < $1.id.rawValue
            }
            .map { availability in
                let actionActivities = activities.filter {
                    $0.targetNoteID == target.noteID
                        && $0.actionID == availability.id
                }
                return ResearchActionItemPresentation(
                    actionID: availability.id,
                    definition: availability.definition,
                    resolvedAvailability: availability,
                    sortOrder: availability.order,
                    activity: ResearchActionActivityPresentation.make(
                        activities: actionActivities
                    ),
                    isEndingActivity: actionActivities.contains {
                        endingActivityRunIDs.contains($0.runID)
                    },
                    isBlockedByCancellationRecovery:
                        hasCancellationBarrier || availabilityIsUnconfirmed,
                    reopensActiveDiscussion:
                        availability.id == .discuss && hasActiveDiscussion,
                    disabledReason: hasCancellationBarrier
                        ? String(
                            localized: "Resolve the pending Action cancellation before starting another Action.",
                            table: "Localizable",
                            bundle: .module
                        )
                        : availabilityIsUnconfirmed
                            ? availabilityError
                                ?? String(
                                    localized: "Checking this Action…",
                                    table: "Localizable",
                                    bundle: .module
                                )
                            : availability.isEnabled
                                ? nil
                                : availability.repairReasons.first?.interfaceDescription
                                    ?? "Unavailable for this note."
                )
            }
        let resolvedActionIDs = Set(items.map(\.id))
        let fallbackDefinitions = PlatformActionCatalog.definitions.enumerated()
            .filter { !resolvedActionIDs.contains($0.element.id) }
        for (definitionIndex, definition) in fallbackDefinitions {
            let actionActivities = activities.filter {
                $0.targetNoteID == target.noteID
                    && $0.actionID == definition.id
            }
            guard let activity = ResearchActionActivityPresentation.make(
                activities: actionActivities
            ) else { continue }
            items.append(ResearchActionItemPresentation(
                actionID: definition.actionID,
                definition: definition.actionID.interfaceDefinition,
                resolvedAvailability: nil,
                sortOrder: 10_000 + definitionIndex,
                activity: activity,
                isEndingActivity: actionActivities.contains {
                    endingActivityRunIDs.contains($0.runID)
                },
                isBlockedByCancellationRecovery: false,
                reopensActiveDiscussion: false,
                disabledReason: nil
            ))
        }
        items.sort {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.id.rawValue < $1.id.rawValue
        }
        return Self(
            items: items,
            target: target,
            isCheckingAvailability: isCheckingAvailability,
            availabilityError: availabilityError,
            cancellationRecoveries: cancellationRecoveries,
            retryingCancellationRecoveryIDs: retryingCancellationRecoveryIDs,
            pendingCancellationBarrierCount: pendingCancellationBarrierCount,
            latestSettlement: settlements
                .filter { $0.noteID == target.noteID }
                .max { $0.settledAt < $1.settledAt }
        )
    }

}

struct ResearchActionItemPresentation: Identifiable {
    let actionID: ResearchActionID
    let definition: ResearchActionDefinition
    let resolvedAvailability: ResearchActionAvailability?
    fileprivate let sortOrder: Int
    let activity: ResearchActionActivityPresentation?
    let isEndingActivity: Bool
    let isBlockedByCancellationRecovery: Bool
    let reopensActiveDiscussion: Bool
    let disabledReason: String?

    var id: ResearchActionID { actionID }
    var title: String {
        resolvedAvailability?.buttonName ?? actionID.interfaceFallbackTitle
    }
    var canPresent: Bool {
        activity != nil
            || reopensActiveDiscussion
            || resolvedAvailability?.canPresentInInterface == true
                && !isBlockedByCancellationRecovery
    }
    var detail: String? {
        if reopensActiveDiscussion {
            return String(
                localized: "Continue the current Discussion.",
                table: "Localizable",
                bundle: .module
            )
        }
        return activity?.detail ?? (canPresent ? nil : disabledReason)
    }

}

struct ResearchActionActivityPresentation: Equatable {
    let primary: WorkspaceResearchActivity

    static func make(
        activities: [WorkspaceResearchActivity]
    ) -> ResearchActionActivityPresentation? {
        guard !activities.isEmpty else { return nil }
        let ordered = activities.sorted {
            if priority($0.state) != priority($1.state) {
                return priority($0.state) < priority($1.state)
            }
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.runID.uuidString < $1.runID.uuidString
        }
        guard let primary = ordered.first else { return nil }
        return ResearchActionActivityPresentation(primary: primary)
    }

    var stateTitle: String {
        switch primary.state {
        case .waitingForAgent:
            return String(
                localized: "Waiting for Agent",
                table: "Localizable",
                bundle: .module
            )
        case .running:
            return String(
                localized: "Running",
                table: "Localizable",
                bundle: .module
            )
        case .needsAttention:
            return String(
                localized: "Needs Attention",
                table: "Localizable",
                bundle: .module
            )
        }
    }

    var detail: String? {
        guard primary.state == .needsAttention else { return nil }
        let repair = primary.repairReason?.interfaceRepairDescription
            ?? String(
                localized: "Open the Action status to review recovery.",
                table: "Localizable",
                bundle: .module
            )
        return repair
    }

    var showsProgress: Bool { primary.state == .running }
    var showsDirectEnd: Bool {
        primary.state == .waitingForAgent || primary.state == .running
    }

    private static func priority(_ state: WorkspaceResearchActivityState) -> Int {
        switch state {
        case .needsAttention: 0
        case .running: 1
        case .waitingForAgent: 2
        }
    }
}

extension WorkspaceResearchActivityRepairReason {
    var interfaceRepairDescription: String {
        switch self {
        case .sourceConflict:
            String(
                localized: "Review the source conflict before continuing.",
                table: "Localizable",
                bundle: .module
            )
        case .sourceChanged:
            String(
                localized: "Copy a new handoff so the Agent can reload current source.",
                table: "Localizable",
                bundle: .module
            )
        case .recoveryRequired:
            String(
                localized: "Open Recovery to inspect the uncertain write result.",
                table: "Localizable",
                bundle: .module
            )
        case .recordUnavailable:
            String(
                localized: "Retry Refresh to recover the completed Research Record.",
                table: "Localizable",
                bundle: .module
            )
        }
    }
}

/// Presentation-only grouping for Scholium's closed Platform Action matrix.
private enum BuiltInActionVisualGroup: Equatable {
    case research
    case review
}

private extension ResearchActionItemPresentation {
    var builtInVisualGroup: BuiltInActionVisualGroup {
        switch definition.executionKind {
        case .discussion, .analysis, .synthesis, .writing:
            .research
        case .critique, .checkFidelity:
            .review
        }
    }
}

private struct ResearchActionVisualSection: Identifiable {
    enum ID: Hashable {
        case research
        case review
    }

    let id: ID
    let title: LocalizedStringResource
    let items: [ResearchActionItemPresentation]
}

struct ResearchActionsInspectorView: View {
    let presentation: ResearchActionsPresentation
    let freshness: ResearchProjectionFreshness
    let focusRequest: ResearchActionFocusRequest?
    let registerFocusOwner: (ResearchActionID) -> Void
    let select: (ResearchActionItemPresentation) -> Void
    let endActivity: (UUID) -> Void
    let retryRefresh: () -> Void
    let retryCancellationRecovery: (UUID) -> Void
    let settle: (String?) async throws -> Void

    @State private var presentsSettlement = false
    @State private var settlementRationale = ""
    @State private var settlementError: String?
    @State private var isSettling = false
    @State private var activityPendingEnd: WorkspaceResearchActivity?

    var body: some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: ScholiumMetrics.Apparatus.sectionSpacing
            ) {
                if presentation.pendingCancellationBarrierCount > 0 {
                    pendingCancellationNotice
                }
                ForEach(presentation.cancellationRecoveries) { recovery in
                    cancellationRecoveryNotice(recovery)
                }
                if case .failed(let reason) = freshness {
                    refreshNotice(reason)
                }

                if presentation.isCheckingAvailability && presentation.items.isEmpty {
                    ScholiumApparatusStateView(
                        "Checking Actions…",
                        systemImage: "arrow.triangle.2.circlepath",
                        showsProgress: true
                    )
                        .accessibilityIdentifier("scholium.researchActions.loading")
                } else if let error = presentation.availabilityError {
                    availabilityNotice(error)
                }

                ForEach(actionSections) { section in
                    ScholiumApparatusSection(section.title) {
                        actionRows(section.items)
                    }
                }

                if presentation.target != nil {
                    ScholiumApparatusSection("JUDGMENT") {
                        settlementLauncher
                    }
                }
            }
            .padding(.horizontal, ScholiumMetrics.Apparatus.contentInset)
            .padding(.top, ScholiumMetrics.Apparatus.firstSectionSpacing)
            .padding(.bottom, ScholiumMetrics.Apparatus.bottomInset)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("scholium.researchActions")
        .confirmationDialog(
            "End this Action?",
            isPresented: Binding(
                get: { activityPendingEnd != nil },
                set: { if !$0 { activityPendingEnd = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Keep Action", role: .cancel) {
                activityPendingEnd = nil
            }
            Button("End Action", role: .destructive) {
                guard let runID = activityPendingEnd?.runID else { return }
                activityPendingEnd = nil
                endActivity(runID)
            }
        } message: {
            Text("Scholium will revoke Agent access and end this unfinished Run. Confirmed changes, conflicts, and recovery records remain available.")
        }
    }

    @ViewBuilder
    private func actionRows(_ rows: [ResearchActionItemPresentation]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { item in
                actionRow(item)
            }
        }
    }

    private func actionRow(_ item: ResearchActionItemPresentation) -> some View {
        HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            ResearchActionRowButton(
                title: item.title,
                systemImage: item.definition.interfaceSymbol,
                detail: item.detail,
                trailingState: item.activity?.stateTitle,
                showsProgress: item.activity?.showsProgress == true,
                showsChevron: item.activity?.showsDirectEnd != true,
                localizesTitle: false,
                focusRequestToken: focusRequest?.actionID == item.id
                    ? focusRequest?.token
                    : nil
            ) { shouldRestoreKeyboardFocus in
                if shouldRestoreKeyboardFocus {
                    registerFocusOwner(item.id)
                }
                select(item)
            }
            .disabled(!item.canPresent)
            if item.activity?.showsDirectEnd == true {
                Button(item.isEndingActivity ? "Ending…" : "End Action") {
                    activityPendingEnd = item.activity?.primary
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
                .disabled(item.isEndingActivity)
                .accessibilityHint("Revokes Agent access while preserving confirmed changes and recovery facts.")
            }
        }
        .accessibilityIdentifier("scholium.researchAction.\(item.id.rawValue)")
    }

    private func refreshNotice(_ reason: String) -> some View {
        ScholiumApparatusStateView(
            "Action availability may be incomplete.",
            detail: reason,
            systemImage: "exclamationmark.triangle",
            density: .block
        ) {
            Button("Retry", action: retryRefresh)
                .controlSize(.small)
        }
    }

    private func availabilityNotice(_ reason: String) -> some View {
        ScholiumApparatusStateView(
            "Actions could not be resolved.",
            detail: reason,
            systemImage: "exclamationmark.triangle",
            density: .block
        ) {
            Button("Retry", action: retryRefresh)
                .controlSize(.small)
        }
        .accessibilityIdentifier("scholium.researchActions.error")
    }

    private func cancellationRecoveryNotice(
        _ recovery: ResearchActionCancellationRecovery
    ) -> some View {
        let isRetrying = presentation.retryingCancellationRecoveryIDs.contains(recovery.runID)
        return ScholiumApparatusStateView(
            "A prepared Action still needs cancellation.",
            detail: recovery.errorMessage,
            systemImage: "exclamationmark.arrow.triangle.2.circlepath",
            showsProgress: isRetrying,
            density: .block
        ) {
            Button(
                isRetrying
                    ? "Retrying Cancellation…"
                    : "Retry Cancellation",
                action: { retryCancellationRecovery(recovery.runID) }
            )
            .controlSize(.small)
            .disabled(isRetrying)
        }
        .accessibilityIdentifier(
            "scholium.researchActions.cancellationRecovery.\(recovery.runID.uuidString.lowercased())"
        )
    }

    private var pendingCancellationNotice: some View {
        ScholiumApparatusStateView(
            "Waiting for interrupted Action cleanup…",
            systemImage: "arrow.triangle.2.circlepath",
            showsProgress: true
        )
        .accessibilityIdentifier("scholium.researchActions.pendingCancellation")
    }

    private var settlementLauncher: some View {
        let isCurrent = presentation.latestSettlement?.fingerprint
            == presentation.target?.fingerprint
        return ResearchActionRowButton(
            title: isCurrent ? "Settled" : "Settle",
            systemImage: "checkmark.circle",
            detail: nil,
            showsChevron: true
        ) { _ in
            presentsSettlement = true
        }
        .disabled(presentation.target == nil)
        .popover(isPresented: $presentsSettlement) {
            settlementPopover
        }
        .accessibilityIdentifier("scholium.researchAction.settle")
    }

    private var settlementPopover: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.sectionContentSpacing) {
            Text(presentation.latestSettlement == nil ? "Settle" : "Settle Again")
                .font(ScholiumTypography.interface(.sectionTitle))
            Text("Record this saved revision as sufficiently stable for current research.")
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Optional rationale", text: $settlementRationale, axis: .vertical)
                .lineLimit(2...4)
            if let settlementError {
                Text(settlementError)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.attention)
            }
            HStack {
                Button("Cancel") {
                    settlementRationale = ""
                    settlementError = nil
                    presentsSettlement = false
                }
                Spacer()
                Button("Settle") {
                    isSettling = true
                    settlementError = nil
                    Task {
                        do {
                            try await settle(settlementRationale)
                            settlementRationale = ""
                            isSettling = false
                            presentsSettlement = false
                        } catch {
                            settlementError = error.localizedDescription
                            isSettling = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSettling || presentation.target == nil)
            }
        }
        .padding(ScholiumGrid.Spacing.sectionSeparation)
        .frame(width: 300)
    }

    private var researchItems: [ResearchActionItemPresentation] {
        presentation.items.filter { $0.builtInVisualGroup == .research }
    }

    private var reviewItems: [ResearchActionItemPresentation] {
        presentation.items.filter { $0.builtInVisualGroup == .review }
    }

    private var actionSections: [ResearchActionVisualSection] {
        [
            ResearchActionVisualSection(
                id: .research,
                title: "RESEARCH",
                items: researchItems
            ),
            ResearchActionVisualSection(
                id: .review,
                title: "REVIEW",
                items: reviewItems
            ),
        ].filter { !$0.items.isEmpty }
    }
}

private extension ResearchActionID {
    var interfaceDefinition: ResearchActionDefinition {
        switch self {
        case .discuss: .discuss
        case .analyze: .analyze
        case .synthesize: .synthesize
        case .write: .write
        case .critique: .critique
        case .checkFidelity: .checkFidelity
        default: .discuss
        }
    }

    var interfaceFallbackTitle: String {
        switch self {
        case .discuss:
            String(localized: "Discuss", table: "Localizable", bundle: .module)
        case .analyze:
            String(localized: "Analyze", table: "Localizable", bundle: .module)
        case .synthesize:
            String(localized: "Synthesize", table: "Localizable", bundle: .module)
        case .write:
            String(localized: "Write", table: "Localizable", bundle: .module)
        case .critique:
            String(localized: "Critique", table: "Localizable", bundle: .module)
        case .checkFidelity:
            String(localized: "Check Fidelity", table: "Localizable", bundle: .module)
        default:
            String(localized: "Research Action", table: "Localizable", bundle: .module)
        }
    }
}

private struct ResearchActionRowButton: View {
    let title: String
    let systemImage: String
    let detail: String?
    let trailingState: String?
    let showsProgress: Bool
    let showsChevron: Bool
    let localizesTitle: Bool
    let focusRequestToken: UUID?
    let action: (_ shouldRestoreKeyboardFocus: Bool) -> Void

    @State private var focusRestorationTask: Task<Void, Never>?
    @FocusState private var hasKeyboardFocus: Bool

    init(
        title: String,
        systemImage: String,
        detail: String? = nil,
        trailingState: String? = nil,
        showsProgress: Bool = false,
        showsChevron: Bool = true,
        localizesTitle: Bool = true,
        focusRequestToken: UUID? = nil,
        action: @escaping (_ shouldRestoreKeyboardFocus: Bool) -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.trailingState = trailingState
        self.showsProgress = showsProgress
        self.showsChevron = showsChevron
        self.localizesTitle = localizesTitle
        self.focusRequestToken = focusRequestToken
        self.action = action
    }

    var body: some View {
        Button {
            focusRestorationTask?.cancel()
            action(hasKeyboardFocus)
        } label: {
            ScholiumApparatusActionRowContent(
                title: titleText,
                systemImage: systemImage,
                detail: detailText,
                trailingState: trailingState.map { Text(verbatim: $0) },
                showsProgress: showsProgress,
                showsChevron: showsChevron
            )
        }
        .buttonStyle(ScholiumQuietRowButtonStyle(
            isFocused: hasKeyboardFocus,
            minimumHeight: ScholiumMetrics.Apparatus.actionRowMinimumHeight,
            verticalInset: ScholiumMetrics.Apparatus.actionRowVerticalInset
        ))
        .accessibilityValue(Text(verbatim: trailingState ?? ""))
        .scholiumActivationFocus($hasKeyboardFocus)
        .onChange(of: focusRequestToken) { _, token in
            guard token != nil else { return }
            focusRestorationTask?.cancel()
            hasKeyboardFocus = false
            focusRestorationTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                hasKeyboardFocus = true
            }
        }
        .onDisappear {
            focusRestorationTask?.cancel()
            focusRestorationTask = nil
        }
    }

    private var titleText: Text {
        localizesTitle
            ? Text(LocalizedStringKey(title))
            : Text(verbatim: title)
    }

    private var detailText: Text? {
        guard let detail, !detail.isEmpty else { return nil }
        return localizesTitle
            ? Text(LocalizedStringKey(detail))
            : Text(verbatim: detail)
    }
}
