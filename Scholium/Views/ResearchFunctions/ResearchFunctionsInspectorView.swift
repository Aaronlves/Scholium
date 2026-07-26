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
        activeDiscussions: [PortableResearchDiscussion] = [],
        settlements: [SettlementRecord] = []
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
        let items = availability
            .sorted {
                if $0.group != $1.group { return $0.group == .defaultAction }
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.id.rawValue < $1.id.rawValue
            }
            .map { availability in
                ResearchActionItemPresentation(
                    availability: availability,
                    isBlockedByCancellationRecovery:
                        hasCancellationBarrier || availabilityIsUnconfirmed,
                    reopensActiveDiscussion:
                        availability.id == .discuss && hasActiveDiscussion,
                    disabledReason: availability.isEnabled
                        ? hasCancellationBarrier
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
                                : nil
                        : availability.repairReasons.first?.interfaceDescription
                            ?? "Unavailable for this note."
                )
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

    func defaultItems() -> [ResearchActionItemPresentation] {
        items.filter { $0.group == .defaultAction }
    }
}

struct ResearchActionItemPresentation: Identifiable {
    let availability: ResearchActionAvailability
    let isBlockedByCancellationRecovery: Bool
    let reopensActiveDiscussion: Bool
    let disabledReason: String?

    var id: ResearchActionID { availability.id }
    var title: String { availability.buttonName }
    var isEnabled: Bool {
        reopensActiveDiscussion
            || availability.isEnabled && !isBlockedByCancellationRecovery
    }
    var canPresent: Bool {
        reopensActiveDiscussion
            || availability.canPresentInInterface && !isBlockedByCancellationRecovery
    }
    var group: ResearchActionAvailabilityGroup { availability.group }
    var detail: String {
        reopensActiveDiscussion
            ? String(
                localized: "Continue the current Discussion.",
                table: "Localizable",
                bundle: .module
            )
            : disabledReason ?? availability.definition.interfaceSummary
    }
}

struct ResearchFunctionsInspectorView: View {
    @FocusedValue(\.scholiumResearchActionActions) private var focusedResearchActions

    let presentation: ResearchActionsPresentation
    let freshness: ResearchProjectionFreshness
    let focusRequest: ResearchActionFocusRequest?
    let registerFocusOwner: (ResearchActionID) -> Void
    let select: (ResearchActionID) -> Void
    let retryRefresh: () -> Void
    let retryCancellationRecovery: (UUID) -> Void
    let settle: (String?) async throws -> Void

    @State private var presentsSettlement = false
    @State private var settlementRationale = ""
    @State private var settlementError: String?
    @State private var isSettling = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if presentation.pendingCancellationBarrierCount > 0 {
                    pendingCancellationNotice
                    ScholiumStructuralRule()
                        .padding(.vertical, ScholiumMetrics.Apparatus.contentToRuleSpacing)
                }
                ForEach(presentation.cancellationRecoveries) { recovery in
                    cancellationRecoveryNotice(recovery)
                    ScholiumStructuralRule()
                        .padding(.vertical, ScholiumMetrics.Apparatus.contentToRuleSpacing)
                }
                if case .failed(let reason) = freshness {
                    refreshNotice(reason)
                    ScholiumStructuralRule()
                        .padding(.vertical, ScholiumMetrics.Apparatus.contentToRuleSpacing)
                }

                if presentation.isCheckingAvailability && presentation.items.isEmpty {
                    ProgressView("Checking Actions…")
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("scholium.researchActions.loading")
                } else if let error = presentation.availabilityError {
                    availabilityNotice(error)
                }

                actionRows(presentation.defaultItems())

                if !researcherItems.isEmpty {
                    ScholiumStructuralRule()
                        .padding(.vertical, ScholiumMetrics.Apparatus.contentToRuleSpacing)
                    ScholiumApparatusSection("RESEARCHER SKILLS", showsDivider: false) {
                        actionRows(researcherItems)
                    } trailing: {
                        EmptyView()
                    }
                }

                if presentation.target != nil {
                    ScholiumStructuralRule()
                        .padding(.vertical, ScholiumMetrics.Apparatus.contentToRuleSpacing)
                    settlementLauncher
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
    }

    @ViewBuilder
    private func actionRows(_ rows: [ResearchActionItemPresentation]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                actionRow(item)
                if index < rows.count - 1 { ScholiumStructuralRule() }
            }
        }
    }

    private func actionRow(_ item: ResearchActionItemPresentation) -> some View {
        ResearchActionRowButton(
            title: item.title,
            systemImage: item.availability.definition.interfaceSymbol,
            detail: item.detail,
            localizesTitle: item.availability.profile.origin == .applicationDefault,
            focusRequestToken: focusRequest?.actionID == item.id
                ? focusRequest?.token
                : nil
        ) {
            registerFocusOwner(item.id)
            if let focusedResearchActions {
                focusedResearchActions.open(item.id)
            } else {
                select(item.id)
            }
        }
        .disabled(!item.canPresent)
        .help(item.canPresent ? item.detail : item.disabledReason ?? item.detail)
        .accessibilityIdentifier("scholium.researchAction.\(item.id.rawValue)")
    }

    private func refreshNotice(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Action availability may be incomplete.", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
            Text(reason)
                .font(.caption)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
            Button("Retry", action: retryRefresh)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func availabilityNotice(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Actions could not be resolved.", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
            Text(reason)
                .font(.caption)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
            Button("Retry", action: retryRefresh)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("scholium.researchActions.error")
    }

    private func cancellationRecoveryNotice(
        _ recovery: ResearchActionCancellationRecovery
    ) -> some View {
        let isRetrying = presentation.retryingCancellationRecoveryIDs.contains(recovery.runID)
        return VStack(alignment: .leading, spacing: 8) {
            Label(
                "A prepared Action still needs cancellation.",
                systemImage: "exclamationmark.arrow.triangle.2.circlepath"
            )
            .font(.callout.weight(.semibold))
            Text(recovery.errorMessage)
                .font(.caption)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
            Button(
                isRetrying
                    ? "Retrying Cancellation…"
                    : "Retry Cancellation",
                action: { retryCancellationRecovery(recovery.runID) }
            )
            .disabled(isRetrying)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier(
            "scholium.researchActions.cancellationRecovery.\(recovery.runID.uuidString.lowercased())"
        )
    }

    private var pendingCancellationNotice: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Waiting for interrupted Action cleanup…")
                .font(.callout)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scholium.researchActions.pendingCancellation")
    }

    private var settlementLauncher: some View {
        let isCurrent = presentation.latestSettlement?.fingerprint
            == presentation.target?.fingerprint
        return ResearchActionRowButton(
            title: isCurrent ? "Settled" : "Settle",
            systemImage: "checkmark.circle",
            detail: isCurrent
                ? "This saved revision is settled."
                : "Record that this saved revision is sufficiently stable for current research.",
            showsChevron: true
        ) {
            presentsSettlement = true
        }
        .disabled(presentation.target == nil)
        .popover(isPresented: $presentsSettlement) {
            settlementPopover
        }
        .accessibilityIdentifier("scholium.researchAction.settle")
    }

    private var settlementPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(presentation.latestSettlement == nil ? "Settle" : "Settle Again")
                .font(.headline)
            Text("Record this saved revision as sufficiently stable for current research.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Optional rationale", text: $settlementRationale, axis: .vertical)
                .lineLimit(2...4)
            if let settlementError {
                Text(settlementError)
                    .font(.caption)
                    .foregroundStyle(ScholiumColorRole.attention.color)
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
        .padding(16)
        .frame(width: 300)
    }

    private var researcherItems: [ResearchActionItemPresentation] {
        presentation.items.filter { $0.group == .researcherSkill }
    }
}

private struct ResearchActionRowButton: View {
    let title: String
    let systemImage: String
    let detail: String?
    let showsChevron: Bool
    let localizesTitle: Bool
    let focusRequestToken: UUID?
    let action: () -> Void

    @State private var isHovering = false
    @State private var focusRestorationTask: Task<Void, Never>?
    @FocusState private var hasKeyboardFocus: Bool

    init(
        title: String,
        systemImage: String,
        detail: String? = nil,
        showsChevron: Bool = true,
        localizesTitle: Bool = true,
        focusRequestToken: UUID? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.showsChevron = showsChevron
        self.localizesTitle = localizesTitle
        self.focusRequestToken = focusRequestToken
        self.action = action
    }

    var body: some View {
        Button {
            focusRestorationTask?.cancel()
            hasKeyboardFocus = true
            action()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: ScholiumMetrics.Apparatus.iconToTextSpacing) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .frame(width: ScholiumMetrics.Apparatus.iconColumnWidth)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.actionCopySpacing) {
                    Group {
                        if localizesTitle {
                            Text(LocalizedStringKey(title))
                        } else {
                            Text(verbatim: title)
                        }
                    }
                    .font(ScholiumInterfaceTypography.apparatusActionTitle)
                    .foregroundStyle(ScholiumColorRole.primaryText.color)
                    if let detail, !detail.isEmpty {
                        Text(LocalizedStringKey(detail))
                            .font(ScholiumInterfaceTypography.apparatusResearchContent)
                            .foregroundStyle(ScholiumColorRole.secondaryText.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if showsChevron {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ScholiumColorRole.mutedText.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
            .padding(.vertical, ScholiumMetrics.Apparatus.actionRowVerticalInset)
            .frame(
                maxWidth: .infinity,
                minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget,
                alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                isHovering ? ScholiumColorRole.raisedSurfaceBackground.color : Color.clear,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($hasKeyboardFocus)
        .onHover { isHovering = $0 }
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
}

extension ResearchFunctionID {
    var interfaceSymbol: String {
        switch self {
        case .discuss: "text.bubble"
        case .develop: "lightbulb"
        case .fidelity: "checkmark.shield"
        case .critique: "doc.text.magnifyingglass"
        case .revise: "pencil"
        case .manuscript: "doc.text"
        }
    }

    var interfaceIdentifier: String { rawValue }
}

extension ResearchActivityEventKind {
    var activitySymbol: String {
        switch self {
        case .created: "plus"
        case .commented: "bubble.left"
        case .discussed: "bubble.left.and.bubble.right"
        case .developed: "arrow.triangle.branch"
        case .fidelityChecked: "checkmark.shield"
        case .settled: "checkmark.circle"
        case .critiqued: "doc.text.magnifyingglass"
        case .revised: "pencil.line"
        case .critiqueAddressed: "checkmark.seal"
        }
    }

    var activityTitle: String {
        switch self {
        case .created: "Created"
        case .commented: "Commented"
        case .discussed: "Discussed"
        case .developed: "Developed"
        case .fidelityChecked: "Fidelity Checked"
        case .settled: "Settled"
        case .critiqued: "Critiqued"
        case .revised: "Revised"
        case .critiqueAddressed: "Critique Addressed"
        }
    }
}

extension ResearchActivityEvent {
    var activityDetail: String {
        var lines = [
            occurredAt.formatted(date: .abbreviated, time: .omitted),
            "Origin note: \(origin.title)",
        ]
        if confirmedModifiedNoteCount > 0 {
            lines.append("This activity modified \(confirmedModifiedNoteCount) notes.")
        }
        if unmodifiedNoteCount > 0 {
            lines.append("\(unmodifiedNoteCount) notes were not modified.")
        }
        return lines.joined(separator: "\n")
    }
}
