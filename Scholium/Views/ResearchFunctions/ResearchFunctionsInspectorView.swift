import ScholiumContracts
import SwiftUI

/// Immutable, per-window projection for the current note's Functions mode.
/// The view owns only transient focus; Application remains the authority for
/// availability, durable runs, checkpoints, and function presentation.
struct ResearchFunctionsPresentation {
    let items: [ResearchFunctionItemPresentation]
    let activeFunction: ResearchFunctionID?
    let currentActivity: ResearchFunctionActivityPresentation?
    let additionalActionableRunCount: Int

    static let empty = Self(
        items: [],
        activeFunction: nil,
        currentActivity: nil,
        additionalActionableRunCount: 0
    )

    static func make(
        target: ResearchFunctionTarget?,
        availability: [ResearchFunctionID: ResearchFunctionAvailability],
        activeFunction: ResearchFunctionID?,
        runs: [ResearchFunctionRecordProjection]
    ) -> Self {
        guard let target else { return .empty }

        let orderedFunctions: [ResearchFunctionID] = switch target.role {
        case .analysis, .topic:
            [.dialogue, .develop, .fidelity]
        case .work:
            [.critique, .revise, .dialogue, .fidelity, .manuscript]
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
                disabledReason: reason
            )
        }

        let actionable = runs
            .filter { projection in
                switch projection.runState {
                case .prepared, .awaitingFidelity, .unverified, .stale: true
                case .complete, .cancelled: false
                }
            }
            .sorted {
                if $0.snapshot.preparedAt != $1.snapshot.preparedAt {
                    return $0.snapshot.preparedAt > $1.snapshot.preparedAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }

        return Self(
            items: items,
            activeFunction: activeFunction,
            currentActivity: actionable.first.map(ResearchFunctionActivityPresentation.init),
            additionalActionableRunCount: max(0, actionable.count - 1)
        )
    }
}

struct ResearchFunctionItemPresentation: Identifiable {
    let id: ResearchFunctionID
    let isEnabled: Bool
    let disabledReason: String?
}

struct ResearchFunctionActivityPresentation: Identifiable {
    let id: UUID
    let function: ResearchFunctionID
    let state: ResearchFunctionRunState
    let preparedAt: Date

    init(_ projection: ResearchFunctionRecordProjection) {
        id = projection.id
        function = projection.snapshot.request.function
        state = projection.runState
        preparedAt = projection.snapshot.preparedAt
    }

    var stateTitleResource: LocalizedStringResource {
        switch state {
        case .prepared: "Prepared"
        case .awaitingFidelity: "Awaiting Fidelity"
        case .unverified: "Unverified"
        case .stale: "Stale"
        case .complete: "Complete"
        case .cancelled: "Cancelled"
        }
    }
}

struct ResearchFunctionsInspectorView: View {
    @FocusState private var focusedFunction: ResearchFunctionID?
    @State private var originatingFunction: ResearchFunctionID?

    let presentation: ResearchFunctionsPresentation
    let freshness: ResearchProjectionFreshness
    let select: (ResearchFunctionID) -> Void
    let openResearchRecord: () -> Void
    let retryRefresh: () -> Void

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

                ScholiumApparatusSection("RESEARCH FUNCTIONS") {
                    VStack(
                        alignment: .leading,
                        spacing: ScholiumMetrics.Apparatus.rowSpacing
                    ) {
                        if presentation.items.isEmpty {
                            Text("No Research Functions are available for this note.")
                                .font(ScholiumInterfaceTypography.apparatusBody)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(presentation.items) { item in
                                functionLauncher(item)
                            }
                        }
                    }
                }

                if presentation.currentActivity != nil {
                    currentActivitySection
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
    }

    private func functionLauncher(_ item: ResearchFunctionItemPresentation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                originatingFunction = item.id
                focusedFunction = item.id
                select(item.id)
            } label: {
                Label(item.id.interfaceTitleResource, systemImage: item.id.interfaceSymbol)
                    .font(ScholiumInterfaceTypography.apparatusBody.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: ScholiumGrid.Dimension.researchFunctionTargetHeight,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .focusable(interactions: .activate)
            .focused($focusedFunction, equals: item.id)
            .disabled(!item.isEnabled)
            .help(item.disabledReason ?? item.id.interfaceHelp)
            .accessibilityLabel(item.id.interfaceTitleResource)
            .accessibilityHint(item.disabledReason ?? item.id.interfaceHelp)
            .accessibilityValue(
                presentation.activeFunction == item.id
                    ? ScholiumL10n.ResearchFunction.openAccessibilityValue
                    : ScholiumL10n.ResearchFunction.closedAccessibilityValue
            )
            .accessibilityIdentifier(
                "scholium.researchFunction.\(item.id.interfaceIdentifier)"
            )

            if let reason = item.disabledReason {
                Text(reason)
                    .font(ScholiumInterfaceTypography.apparatusMetadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(
                        "scholium.researchFunction.\(item.id.interfaceIdentifier).reason"
                    )
            }
        }
    }

    private var currentActivitySection: some View {
        ScholiumApparatusSection("CURRENT ACTIVITY", showsDivider: false) {
            if let activity = presentation.currentActivity {
                VStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.rowSpacing) {
                    ScholiumApparatusRow(
                        leading: {
                            Image(systemName: activity.function.interfaceSymbol)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        },
                        content: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.function.interfaceTitleResource)
                                    .font(ScholiumInterfaceTypography.apparatusBody)
                                Text(activity.stateTitleResource)
                                    .font(ScholiumInterfaceTypography.apparatusMetadata)
                                    .foregroundStyle(.secondary)
                            }
                        },
                        trailing: {
                            Text(activity.preparedAt, style: .relative)
                                .font(ScholiumInterfaceTypography.apparatusMetadata)
                                .foregroundStyle(.secondary)
                        }
                    )

                    if presentation.additionalActionableRunCount > 0 {
                        Text(
                            "\(presentation.additionalActionableRunCount) more requiring attention"
                        )
                        .font(ScholiumInterfaceTypography.apparatusMetadata)
                        .foregroundStyle(.secondary)
                    }

                    Button("Open Research Record", action: openResearchRecord)
                        .buttonStyle(.link)
                }
            }
        }
        .accessibilityIdentifier("scholium.researchFunctions.currentActivity")
    }
}

extension ResearchFunctionID {
    var interfaceSymbol: String {
        switch self {
        case .dialogue: "text.bubble"
        case .develop: "lightbulb"
        case .review: "checkmark.seal"
        case .fidelity: "checkmark.shield"
        case .critique: "doc.text.magnifyingglass"
        case .revise: "pencil"
        case .manuscript: "doc.text"
        }
    }

    var interfaceIdentifier: String {
        switch self {
        case .dialogue: "dialogue"
        case .develop: "develop"
        case .review: "review"
        case .fidelity: "fidelity"
        case .critique: "critique"
        case .revise: "revise"
        case .manuscript: "manuscript"
        }
    }
}
