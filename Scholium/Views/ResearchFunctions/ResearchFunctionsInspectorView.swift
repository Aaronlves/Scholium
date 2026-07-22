import ScholiumContracts
import SwiftUI

/// Immutable, per-window projection for the current note's Actions mode.
/// The view owns only transient focus; Application remains the authority for
/// availability, durable runs, checkpoints, and function presentation.
struct ResearchFunctionsPresentation {
    let items: [ResearchFunctionItemPresentation]
    let activeFunction: ResearchFunctionID?
    let target: ResearchFunctionTarget?
    let activityEvents: [ResearchActivityEvent]
    let pendingStates: [PendingResearchState]
    let latestSettlement: SettlementRecord?

    static let empty = Self(
        items: [],
        activeFunction: nil,
        target: nil,
        activityEvents: [],
        pendingStates: [],
        latestSettlement: nil
    )

    static func make(
        target: ResearchFunctionTarget?,
        availability: [ResearchFunctionID: ResearchFunctionAvailability],
        activeFunction: ResearchFunctionID?,
        runs: [ResearchFunctionRecordProjection],
        activityEvents: [ResearchActivityEvent] = [],
        pendingStates: [PendingResearchState] = [],
        settlements: [SettlementRecord] = [],
        critique: CritiqueAssociation? = nil
    ) -> Self {
        guard let target else { return .empty }

        let targetPendingStates = pendingStates.filter { $0.noteID == target.noteID }

        // Discuss is the read-only branch behind Work with Agent. Develop
        // and Revise remain distinct permissioned methods but are not
        // Inspector launchers. The selected role determines the write method
        // only after the researcher chooses Write in the secondary surface.
        let orderedFunctions: [ResearchFunctionID] = switch target.role {
        case .analysis, .topic:
            [.discuss, .fidelity]
        case .work:
            [.discuss, .critique, .fidelity, .manuscript]
        }

        let items = orderedFunctions.map { function in
            let result = availability[function]
            let reason: String?
            if result == nil {
                reason = ScholiumL10n.string("Checking availability…")
            } else if result?.isEnabled == true {
                reason = nil
            } else {
                reason = result?.repairReasons.first?.interfaceDescription
                    ?? ScholiumL10n.string("Unavailable for this note.")
            }
            return ResearchFunctionItemPresentation(
                id: function,
                isEnabled: result?.isEnabled == true,
                disabledReason: reason,
                statusSummary: statusSummary(
                    for: function,
                    target: target,
                    runs: runs,
                    pendingStates: targetPendingStates,
                    critique: critique
                )
            )
        }

        return Self(
            items: items,
            activeFunction: activeFunction,
            target: target,
            activityEvents: activityEvents
                .filter { $0.note.noteID == target.noteID }
                .sorted { lhs, rhs in
                    if lhs.occurredAt != rhs.occurredAt {
                        return lhs.occurredAt < rhs.occurredAt
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                },
            pendingStates: targetPendingStates
                .sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt {
                        return lhs.createdAt < rhs.createdAt
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                },
            latestSettlement: settlements
                .filter { $0.noteID == target.noteID }
                .max { $0.settledAt < $1.settledAt }
        )
    }

    private static func statusSummary(
        for function: ResearchFunctionID,
        target: ResearchFunctionTarget,
        runs: [ResearchFunctionRecordProjection],
        pendingStates: [PendingResearchState],
        critique: CritiqueAssociation?
    ) -> String? {
        switch function {
        case .discuss:
            return "Read-only until you explicitly choose Write."
        case .fidelity:
            return fidelityStatus(
                target: target,
                runs: runs,
                pendingStates: pendingStates
            )
        case .critique:
            return critiqueStatus(critique)
        case .manuscript:
            return "Uses its own declared manuscript boundary."
        case .develop, .revise:
            return nil
        }
    }

    private static func fidelityStatus(
        target: ResearchFunctionTarget,
        runs: [ResearchFunctionRecordProjection],
        pendingStates: [PendingResearchState]
    ) -> String {
        let revision = String(target.fingerprint.sha256.prefix(8))
        if pendingStates.contains(where: {
            $0.kind == .awaitingFidelity
                && ($0.fingerprint == nil || $0.fingerprint == target.fingerprint)
        }) {
            return "Read-only. Awaiting a check for revision \(revision)."
        }

        let latest = runs
            .filter { run in
                guard run.snapshot.request.function == .fidelity,
                      let completion = run.completion,
                      completion.state == .complete else { return false }
                if let results = completion.fidelityTargetResults {
                    return results.contains {
                        $0.target.noteID == target.noteID
                            && $0.target.fingerprint == target.fingerprint
                    }
                }
                return run.snapshot.request.target.noteID == target.noteID
                    && completion.targetFingerprint == target.fingerprint
            }
            .max { lhs, rhs in
                (lhs.completion?.completedAt ?? lhs.snapshot.preparedAt)
                    < (rhs.completion?.completedAt ?? rhs.snapshot.preparedAt)
            }
        guard let completion = latest?.completion else {
            return "Read-only. Current revision \(revision) has no Fidelity result."
        }
        let outcomes = completion.fidelityTargetResults?
            .first(where: { $0.target.noteID == target.noteID })?.outcomes
            ?? completion.fidelityOutcomes
        let issueCount = outcomes.filter { $0.state == .issuesFound }.count
        let unavailableCount = outcomes.filter { $0.state == .unavailable }.count
        let result: String
        if issueCount > 0 {
            result = issueCount == 1 ? "1 check found issues" : "\(issueCount) checks found issues"
        } else if unavailableCount > 0 {
            result = unavailableCount == 1
                ? "1 check was unavailable"
                : "\(unavailableCount) checks were unavailable"
        } else {
            result = "No unresolved finding"
        }
        return "Read-only. \(result) on \(completion.completedAt.formatted(date: .abbreviated, time: .omitted)) for revision \(revision)."
    }

    private static func critiqueStatus(_ critique: CritiqueAssociation?) -> String {
        guard let round = critique?.rounds.max(by: {
            $0.requestedAt < $1.requestedAt
        }) else {
            return "Read-only. No Critique has been recorded."
        }
        let dispositions = Dictionary(
            round.findingDispositions.map { ($0.findingID, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let unresolved = round.actionableFindings.filter {
            dispositions[$0.id]?.satisfiesRoundCompletion != true
        }.count
        if unresolved > 0 {
            let findings = unresolved == 1 ? "1 finding awaits" : "\(unresolved) findings await"
            return "Read-only. \(findings) disposition from the latest Critique."
        }
        return "Read-only. The latest Critique has no finding awaiting disposition."
    }
}

struct ResearchFunctionItemPresentation: Identifiable {
    let id: ResearchFunctionID
    let isEnabled: Bool
    let disabledReason: String?
    let statusSummary: String?
}

private enum ResearchActivityHUDItem: Identifiable {
    case event(ResearchActivityEvent)
    case pending(PendingResearchState)

    var id: UUID {
        switch self {
        case .event(let event): event.id
        case .pending(let state): state.id
        }
    }

    var symbolName: String {
        switch self {
        case .event(let event): event.kind.activitySymbol
        case .pending(let state): state.kind.activitySymbol
        }
    }

    var detail: String {
        switch self {
        case .event(let event): event.activityDetail
        case .pending(let state): state.kind.detail
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .event(let event): event.activityAccessibilityLabel
        case .pending(let state): state.kind.accessibilityLabel
        }
    }

    var actionHint: String {
        switch self {
        case .event: "Open Research Record"
        case .pending(let state): state.kind.actionHint
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .event(let event):
            "scholium.researchActivity.\(event.kind.rawValue)"
        case .pending(let state):
            "scholium.researchActivity.pending.\(state.kind.rawValue)"
        }
    }

    var isPending: Bool {
        if case .pending = self { return true }
        return false
    }
}

extension ResearchFunctionItemPresentation {
    var actionTitleResource: LocalizedStringResource {
        switch id {
        case .discuss: "Work with Agent"
        case .fidelity: "Fidelity"
        case .critique: "Critique"
        case .manuscript: "Manuscript"
        case .develop, .revise: id.interfaceTitleResource
        }
    }

    var actionSummary: String {
        switch id {
        case .discuss: "Discuss the current note, or choose a bounded write."
        case .fidelity: "Read-only checks for the current saved revision."
        case .critique: "Assess this Work without editing it."
        case .manuscript: "Coordinate manuscript work without creating research-activity events."
        case .develop, .revise: id.interfaceHelp
        }
    }

}

struct ResearchFunctionsInspectorView: View {
    @FocusState private var focusedFunction: ResearchFunctionID?
    @FocusState private var focusedActivityID: UUID?
    @State private var originatingFunction: ResearchFunctionID?
    @State private var presentsSettlement = false
    @State private var settlementRationale = ""
    @State private var settlementError: String?
    @State private var isSettling = false
    @State private var presentsWorkChoice = false
    @State private var activityCursorID: UUID?

    let presentation: ResearchFunctionsPresentation
    let freshness: ResearchProjectionFreshness
    let select: (ResearchFunctionID) -> Void
    let openResearchRecord: () -> Void
    let openComment: (UUID) -> Void
    let retryRefresh: () -> Void
    let settle: (String?) async throws -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(
                alignment: .leading,
                spacing: ScholiumMetrics.Apparatus.sectionSpacing
            ) {
                ResearchProjectionFreshnessBanner(
                    freshness: freshness,
                    retry: retryRefresh
                )

                researchActivitySection

                ScholiumApparatusSection("ACTIONS") {
                    VStack(
                        alignment: .leading,
                        spacing: 0
                    ) {
                        if presentation.items.isEmpty {
                            Text("No Actions are available for this note.")
                                .font(ScholiumInterfaceTypography.apparatusBody)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(Array(presentation.items.enumerated()), id: \.element.id) { index, item in
                                functionLauncher(item)
                                if index < presentation.items.count - 1 {
                                    ScholiumStructuralRule()
                                }
                            }
                        }
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
        .task(id: presentation.activeFunction) {
            if presentation.activeFunction != nil {
                focusedFunction = nil
                return
            }
            guard let originatingFunction else { return }
            self.originatingFunction = nil
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedFunction = originatingFunction
        }
        .confirmationDialog(
            "Work with Agent",
            isPresented: $presentsWorkChoice,
            titleVisibility: .visible
        ) {
            Button("Discuss") {
                beginWork(.discuss)
            }
            if let writeFunction {
                Button("Write") {
                    beginWork(writeFunction)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(workChoiceDescription)
        }
    }

    private func functionLauncher(_ item: ResearchFunctionItemPresentation) -> some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumMetrics.Apparatus.actionCopySpacing
        ) {
            Text(item.actionTitleResource)
                .font(ScholiumInterfaceTypography.apparatusActionTitle)
                .fixedSize(horizontal: false, vertical: true)

            Text(item.actionSummary)
                .font(ScholiumInterfaceTypography.apparatusBody)
                .foregroundStyle(.secondary)
                .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)

            if let statusSummary = item.statusSummary {
                Text(statusSummary)
                    .font(ScholiumInterfaceTypography.apparatusMetadata)
                    .foregroundStyle(ScholiumColorRole.mutedText.color)
                    .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let reason = item.disabledReason {
                Text(reason)
                    .font(ScholiumInterfaceTypography.apparatusMetadata)
                    .foregroundStyle(ScholiumColorRole.mutedText.color)
                    .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(
                        "scholium.researchFunction.\(item.id.interfaceIdentifier).reason"
                    )
            }

            HStack {
                Spacer(minLength: 0)
                Button("Open") {
                    if item.id == .discuss {
                        presentsWorkChoice = true
                    } else {
                        beginWork(item.id)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .focusable(interactions: .activate)
                .focused($focusedFunction, equals: item.id)
                .disabled(!item.isEnabled)
                .help(item.disabledReason ?? item.id.interfaceHelp)
                .accessibilityLabel(item.actionTitleResource)
                .accessibilityHint(Text(item.disabledReason ?? item.actionSummary))
                .accessibilityValue(
                    presentation.activeFunction == item.id
                        ? ScholiumL10n.ResearchFunction.openAccessibilityValue
                        : ScholiumL10n.ResearchFunction.closedAccessibilityValue
                )
                .accessibilityIdentifier("scholium.researchFunction.\(item.id.interfaceIdentifier)")
            }
            .padding(.top, ScholiumMetrics.Apparatus.actionFooterSpacing)
        }
        .padding(.vertical, ScholiumMetrics.Apparatus.actionRowVerticalInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var writeFunction: ResearchFunctionID? {
        switch presentation.target?.role {
        case .analysis, .topic: .develop
        case .work: .revise
        case nil: nil
        }
    }

    private var workChoiceDescription: String {
        guard let target = presentation.target else { return "Choose the next activity." }
        switch target.role {
        case .analysis, .topic:
            return "Discuss reads the note. Write opens a bounded development activity."
        case .work:
            return "Discuss reads the note. Write opens a bounded revision activity."
        }
    }

    private func beginWork(_ function: ResearchFunctionID) {
        originatingFunction = .discuss
        focusedFunction = .discuss
        select(function)
    }

    private var researchActivitySection: some View {
        ScholiumApparatusSection("RESEARCH ACTIVITY", showsDivider: false) {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.rowSpacing) {
                    if activityItems.isEmpty {
                        Text("No recorded activity yet.")
                            .font(ScholiumInterfaceTypography.apparatusMetadata)
                            .foregroundStyle(.secondary)
                            .frame(
                                minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget,
                                alignment: .leading
                            )
                    } else {
                        HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                            Text(activitySummary)
                                .font(ScholiumInterfaceTypography.apparatusMetadata)
                                .foregroundStyle(ScholiumColorRole.mutedText.color)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if activityItems.count > 1 {
                                activityNavigationButton(
                                    systemImage: "chevron.left",
                                    label: "Previous research activity",
                                    step: -1,
                                    proxy: proxy
                                )
                                activityNavigationButton(
                                    systemImage: "chevron.right",
                                    label: "Next research activity",
                                    step: 1,
                                    proxy: proxy
                                )
                            }
                        }

                        ScrollView(.horizontal) {
                            HStack(spacing: 0) {
                                ForEach(Array(activityItems.enumerated()), id: \.element.id) { index, item in
                                    activityNode(item)
                                        .id(item.id)
                                    if index < activityItems.count - 1 {
                                        Rectangle()
                                            .fill(ScholiumColorRole.mutedText.color.opacity(0.36))
                                            .frame(width: 16, height: 1)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                            .padding(.trailing, ScholiumGrid.Spacing.sectionSeparation)
                        }
                        .scrollIndicators(.hidden)
                        .frame(height: ScholiumMetrics.Accessibility.preferredCustomTarget)
                        .onMoveCommand { direction in
                            switch direction {
                            case .left:
                                moveActivity(step: -1, using: proxy)
                            case .right:
                                moveActivity(step: 1, using: proxy)
                            default:
                                break
                            }
                        }
                        .onChange(of: focusedActivityID) { _, id in
                            if let id { activityCursorID = id }
                        }
                    }

                    ScholiumStructuralRule()

                    HStack(spacing: ScholiumMetrics.Apparatus.iconToTextSpacing) {
                        Button("Open Research Record", action: openResearchRecord)
                            .buttonStyle(.link)
                            .font(ScholiumInterfaceTypography.apparatusMetadata)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        settlementControl
                    }
                }
                .padding(ScholiumMetrics.Apparatus.activityHUDInset)
                .background(ScholiumColorRole.raisedSurfaceBackground.color)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ScholiumMetrics.Apparatus.activityHUDCornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ScholiumMetrics.Apparatus.activityHUDCornerRadius,
                        style: .continuous
                    )
                    .stroke(ScholiumColorRole.separator.color.opacity(0.42), lineWidth: 0.75)
                }
                .onAppear { showLatestActivity(using: proxy) }
                .onChange(of: activityItems.map(\.id)) { _, _ in
                    showLatestActivity(using: proxy)
                }
            }
        }
        .popover(isPresented: $presentsSettlement) {
            settlementPopover
        }
        .accessibilityIdentifier("scholium.researchFunctions.researchActivity")
    }

    private func activityNode(_ item: ResearchActivityHUDItem) -> some View {
        Button {
            activate(item)
        } label: {
            Image(systemName: item.symbolName)
                .font(.system(size: 12, weight: .medium))
                .frame(
                    width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                    height: ScholiumMetrics.Accessibility.preferredCustomTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .focusable(interactions: .activate)
        .focused($focusedActivityID, equals: item.id)
        .foregroundStyle(item.isPending
            ? ScholiumColorRole.accent.color
            : ScholiumColorRole.secondaryText.color)
        .help(item.detail)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityHint(item.actionHint)
        .accessibilityIdentifier(item.accessibilityIdentifier)
    }

    private var activityItems: [ResearchActivityHUDItem] {
        presentation.activityEvents.map(ResearchActivityHUDItem.event)
            + presentation.pendingStates.map(ResearchActivityHUDItem.pending)
    }

    private var activitySummary: String {
        guard let last = presentation.activityEvents.last else {
            return presentation.pendingStates.isEmpty ? "No history" : "Current state"
        }
        return "Latest \(last.occurredAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private func activityNavigationButton(
        systemImage: String,
        label: String,
        step: Int,
        proxy: ScrollViewProxy
    ) -> some View {
        Button {
            moveActivity(step: step, using: proxy)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(activityItems.count < 2)
        .accessibilityLabel(label)
    }

    private func showLatestActivity(using proxy: ScrollViewProxy) {
        guard let lastID = activityItems.last?.id else {
            activityCursorID = nil
            return
        }
        activityCursorID = lastID
        proxy.scrollTo(lastID, anchor: .trailing)
    }

    private func moveActivity(step: Int, using proxy: ScrollViewProxy) {
        let items = activityItems
        guard !items.isEmpty else { return }
        let currentIndex = activityCursorID.flatMap { id in
            items.firstIndex(where: { $0.id == id })
        } ?? (items.count - 1)
        let nextIndex = min(items.count - 1, max(0, currentIndex + step))
        let nextID = items[nextIndex].id
        activityCursorID = nextID
        focusedActivityID = nextID
        proxy.scrollTo(nextID, anchor: step < 0 ? .leading : .trailing)
    }

    private func activate(_ item: ResearchActivityHUDItem) {
        switch item {
        case .event:
            openResearchRecord()
        case .pending(let state):
            switch state.kind {
            case .responseReady:
                if state.route == .discuss {
                    openResearchRecord()
                } else if let exchangeID = state.activityID {
                    openComment(exchangeID)
                } else {
                    openResearchRecord()
                }
            case .awaitingFidelity:
                select(.fidelity)
            case .changedSinceSettled:
                presentsSettlement = true
            }
        }
    }

    @ViewBuilder
    private var settlementControl: some View {
        let isCurrent = presentation.latestSettlement?.fingerprint
            == presentation.target?.fingerprint
        Button(isCurrent ? "Settled" : settlementActionTitle) {
            presentsSettlement = true
        }
        .buttonStyle(.bordered)
        .disabled(isCurrent || presentation.target == nil)
        .help(isCurrent
            ? "This saved revision is settled."
            : "Record that this saved revision is sufficiently stable for current research.")
    }

    private var settlementActionTitle: String {
        presentation.latestSettlement == nil ? "Settle" : "Settle Again"
    }

    private var settlementPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(settlementActionTitle)
                .font(.headline)
            Text("Record this saved revision as sufficiently stable for current research.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if presentation.pendingStates.contains(where: { $0.kind == .responseReady }) {
                Text("An agent response is ready for your review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if presentation.pendingStates.contains(where: { $0.kind == .awaitingFidelity }) {
                Text("Fidelity is still awaiting a check for this revision.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("Optional rationale", text: $settlementRationale, axis: .vertical)
                .lineLimit(2...4)
            if let settlementError {
                Text(settlementError)
                    .font(.caption)
                    .foregroundStyle(ScholiumColorRole.attention.color)
                    .fixedSize(horizontal: false, vertical: true)
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

    var interfaceIdentifier: String {
        switch self {
        case .discuss: "discuss"
        case .develop: "develop"
        case .fidelity: "fidelity"
        case .critique: "critique"
        case .revise: "revise"
        case .manuscript: "manuscript"
        }
    }
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

    var activityAccessibilityLabel: String {
        "\(kind.activityTitle). \(activityDetail)"
    }
}

extension PendingResearchStateKind {
    var activitySymbol: String {
        switch self {
        case .responseReady: "bubble.left"
        case .awaitingFidelity: "checkmark.shield"
        case .changedSinceSettled: "arrow.triangle.2.circlepath"
        }
    }

    var detail: String {
        switch self {
        case .responseReady: "An agent response is ready for your review."
        case .awaitingFidelity: "Fidelity is awaiting a check for this revision."
        case .changedSinceSettled: "This revision changed after it was settled."
        }
    }

    var accessibilityLabel: String { detail }

    var actionHint: String {
        switch self {
        case .responseReady: "Open Work with Agent"
        case .awaitingFidelity: "Open Fidelity"
        case .changedSinceSettled: "Open Settle"
        }
    }
}
