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
                return ResearchActionItemPresentation(
                    actionID: availability.id,
                    definition: availability.definition,
                    resolvedAvailability: availability,
                    sortOrder: availability.order,
                    activity: nil,
                    isEndingActivity: false,
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
        if primary.repairReason == .resultRequired {
            return String(
                localized: "Waiting for Result",
                table: "Localizable",
                bundle: .module
            )
        }
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
        if let repairReason = primary.repairReason {
            return repairReason.interfaceRepairDescription
        }
        guard primary.state == .needsAttention else { return nil }
        return String(
                localized: "Open the Action status to review recovery.",
                table: "Localizable",
                bundle: .module
            )
    }

    var showsProgress: Bool {
        primary.state == .running && primary.repairReason != .resultRequired
    }
    var showsDirectEnd: Bool {
        (primary.state == .waitingForAgent || primary.state == .running)
            && primary.repairReason != .resultRequired
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
        case .resultRequired:
            String(
                localized: "Agent changes are saved. Resume this Action so the Agent can submit its Research Result.",
                table: "Localizable",
                bundle: .module
            )
        }
    }
}

/// The current Document owns the compact Research Action launch surface. The
/// rail is attached to the Document split item, so native Inspector resizing
/// moves it with the Document instead of transferring it into window chrome.
struct DocumentResearchActionRail: View {
    let presentation: ResearchActionsPresentation
    let freshness: ResearchProjectionFreshness
    let settlementIsRequired: Bool
    let focusRequest: ResearchActionFocusRequest?
    let registerFocusOwner: (ResearchActionID) -> Void
    let select: (ResearchActionItemPresentation) -> Void
    let retryRefresh: () -> Void
    let retryCancellationRecovery: (UUID) -> Void
    let settle: (String?) async throws -> Void

    @State private var presentsSettlement = false
    @State private var settlementRationale = ""
    @State private var settlementError: String?
    @State private var isSettling = false
    @State private var focusRestorationTask: Task<Void, Never>?
    @FocusState private var focusedActionID: ResearchActionID?

    var body: some View {
        researchActionGroup
        .fixedSize(horizontal: true, vertical: false)
        .onChange(of: focusRequest) { _, request in
            guard let request else { return }
            focusRestorationTask?.cancel()
            focusedActionID = nil
            focusRestorationTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                focusedActionID = request.actionID
            }
        }
        .onDisappear {
            focusRestorationTask?.cancel()
            focusRestorationTask = nil
        }
    }

    private var researchActionGroup: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment) {
            ForEach(presentation.items) { item in
                actionButton(item)
            }

            if presentation.target != nil {
                settlementButton
            }

            recoveryControls
        }
        .padding(ScholiumGrid.Spacing.labelAccessoryGap)
        .scholiumEditorialSurface(.floatingControl, in: railShape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Research Actions")
        .accessibilityIdentifier("scholium.documentActionRail.actions")
    }

    private var railShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: ScholiumShape.inlineStatusCornerRadius,
            style: .continuous
        )
    }

    private func actionButton(_ item: ResearchActionItemPresentation) -> some View {
        Button {
            registerFocusOwner(item.id)
            select(item)
        } label: {
            railIcon(
                systemImage: item.definition.interfaceSymbol,
                showsProgress: item.activity?.showsProgress == true
            )
        }
        .buttonStyle(
            ScholiumContentControlButtonStyle(
                isFocused: focusedActionID == item.id,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
        )
        .scholiumActivationFocus($focusedActionID, equals: item.id)
        .disabled(!item.canPresent)
        .help(item.detail ?? String(localized: "Open \(item.title)"))
        .accessibilityLabel(Text(verbatim: item.title))
        .accessibilityValue(Text(verbatim: item.activity?.stateTitle ?? ""))
        .accessibilityHint(Text(verbatim: item.detail ?? ""))
        .accessibilityIdentifier("scholium.researchAction.\(item.id.rawValue)")
    }

    private var settlementButton: some View {
        let isCurrent = presentation.latestSettlement?.fingerprint
            == presentation.target?.fingerprint
            && !settlementIsRequired
        return Button {
            presentsSettlement = true
        } label: {
            railIcon(systemImage: isCurrent ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .buttonStyle(railButtonStyle())
        .disabled(presentation.target == nil)
        .help(isCurrent ? "Settle this Note again" : "Settle this Note")
        .accessibilityLabel(isCurrent ? "Settled" : "Settle")
        .popover(isPresented: $presentsSettlement) {
            settlementPopover
        }
        .accessibilityIdentifier("scholium.researchAction.settle")
    }

    @ViewBuilder
    private var recoveryControls: some View {
        if presentation.pendingCancellationBarrierCount > 0 {
            railStatus(
                "Cleaning Up Action…",
                systemImage: "arrow.triangle.2.circlepath",
                showsProgress: true
            )
            .accessibilityIdentifier("scholium.researchActions.pendingCancellation")
        }

        ForEach(presentation.cancellationRecoveries) { recovery in
            let isRetrying = presentation.retryingCancellationRecoveryIDs
                .contains(recovery.runID)
            Button {
                retryCancellationRecovery(recovery.runID)
            } label: {
                railIcon(
                    systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                    showsProgress: isRetrying
                )
            }
            .buttonStyle(railButtonStyle())
            .disabled(isRetrying)
            .help(recovery.errorMessage)
            .accessibilityLabel(isRetrying ? "Retrying Action Cleanup" : "Retry Action Cleanup")
            .accessibilityHint(Text(verbatim: recovery.errorMessage))
            .accessibilityIdentifier(
                "scholium.researchActions.cancellationRecovery.\(recovery.runID.uuidString.lowercased())"
            )
        }

        if presentation.isCheckingAvailability && presentation.items.isEmpty {
            railStatus(
                "Checking Actions…",
                systemImage: "arrow.triangle.2.circlepath",
                showsProgress: true
            )
            .accessibilityIdentifier("scholium.researchActions.loading")
        } else if let reason = presentation.availabilityError {
            retryButton(title: "Retry Actions", detail: reason)
                .accessibilityIdentifier("scholium.researchActions.error")
        } else if case .failed(let reason) = freshness {
            retryButton(title: "Retry Actions", detail: reason)
                .accessibilityIdentifier("scholium.researchActions.refresh")
        }
    }

    private func retryButton(title: LocalizedStringResource, detail: String) -> some View {
        Button(action: retryRefresh) {
            railIcon(systemImage: "arrow.clockwise")
        }
        .buttonStyle(railButtonStyle())
        .help(detail)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(verbatim: detail))
    }

    private func railButtonStyle() -> ScholiumContentControlButtonStyle<RoundedRectangle> {
        ScholiumContentControlButtonStyle(
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                style: .continuous
            )
        )
    }

    private func railIcon(
        systemImage: String,
        showsProgress: Bool = false,
        restingRole: ScholiumColorRole = .secondaryText,
        emphasizedRole: ScholiumColorRole = .primaryText
    ) -> some View {
        Group {
            if showsProgress {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: systemImage)
                    .font(ScholiumTypography.interface(.body, emphasis: .medium))
                .scholiumContentControlInk(
                    resting: restingRole,
                    emphasized: emphasizedRole
                )
                .accessibilityHidden(true)
            }
        }
        .frame(
            width: ScholiumMetrics.Apparatus.actionRowMinimumHeight,
            height: ScholiumMetrics.Apparatus.actionRowMinimumHeight,
            alignment: .center
        )
        .contentShape(railShape)
    }

    private func railStatus(
        _ title: LocalizedStringResource,
        systemImage: String,
        showsProgress: Bool
    ) -> some View {
        railIcon(
            systemImage: systemImage,
            showsProgress: showsProgress
        )
        .accessibilityLabel(Text(title))
        .accessibilityElement(children: .combine)
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
        }
    }
}
