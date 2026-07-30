import ScholiumContracts
import SwiftUI

struct AgentNoteChangeRequestView: View {
    let record: AgentNoteChangeRequestRecord
    let targets: [AgentNoteChangeDisplayTarget]
    let identity: AgentNoteChangePresentationIdentity?
    let identityLoadFailed: Bool
    let hasLocallyExpired: Bool
    let isResolving: Bool
    let resolve: (AgentNoteChangeDecisionState, [UUID]) -> Void
    let dismiss: () -> Void

    @State private var selectedNoteIDs: Set<UUID>

    init(
        record: AgentNoteChangeRequestRecord,
        targets: [AgentNoteChangeDisplayTarget],
        identity: AgentNoteChangePresentationIdentity?,
        identityLoadFailed: Bool,
        hasLocallyExpired: Bool,
        isResolving: Bool,
        resolve: @escaping (AgentNoteChangeDecisionState, [UUID]) -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.record = record
        self.targets = targets
        self.identity = identity
        self.identityLoadFailed = identityLoadFailed
        self.hasLocallyExpired = hasLocallyExpired
        self.isResolving = isResolving
        self.resolve = resolve
        self.dismiss = dismiss
        _selectedNoteIDs = State(initialValue: Set(targets.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
            header
            ScholiumStructuralRule()
            if record.isUnresolved && !hasLocallyExpired {
                requestContent
                ScholiumStructuralRule()
                decisionButtons
            } else {
                terminalContent
                HStack {
                    Spacer()
                    Button("Done", action: dismiss)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isResolving)
                }
            }
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 420, idealHeight: 520)
        .scholiumSurface(.denseEvidence)
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.agentNoteChange.sheet")
        .interactiveDismissDisabled(isResolving)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Text("The Agent Wants to Change Additional Notes")
                .font(ScholiumInterfaceTypography.documentTitle)
                .accessibilityAddTraits(.isHeader)
            Text("The current run remains frozen. Allowing Notes records a one-time decision for a separate phase; it does not widen the current run.")
                .font(ScholiumInterfaceTypography.apparatusResearchContent)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var requestContent: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text("AGENT REASON")
                    .font(ScholiumInterfaceTypography.apparatusLabel)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                Text(record.request.agentReason)
                    .font(ScholiumInterfaceTypography.apparatusResearchContent)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            requestAuthority

            Text("REQUESTED NOTES")
                .font(ScholiumInterfaceTypography.apparatusLabel)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(targets) { target in
                        Toggle(isOn: selectionBinding(for: target.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.title)
                                    .font(.body.weight(.semibold))
                                Text("\(roleTitle(target.role))  \(target.relativePath)")
                                    .font(.caption)
                                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                                Text(revisionDescription(for: target))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .toggleStyle(.checkbox)
                        .frame(minHeight: ScholiumGrid.Dimension.researchFunctionTargetHeight)
                        .accessibilityLabel("\(target.title), \(roleTitle(target.role))")
                        .accessibilityHint("Selects this Note for one authorized child phase.")
                        .accessibilityIdentifier(
                            "scholium.agentNoteChange.note.\(target.id.uuidString.lowercased())"
                        )
                        ScholiumStructuralRule()
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Label(
                "Scholium will save and revalidate the current Notes, Skill, Profile, policy, lifecycle, identities, and revisions before recording this decision.",
                systemImage: "checkmark.shield"
            )
            .font(.caption)
            .foregroundStyle(ScholiumColorRole.secondaryText.color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("scholium.agentNoteChange.revalidation")
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var decisionButtons: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Button("Cancel the Run", role: .destructive) {
                resolve(.cancelled, [])
            }
            .disabled(isResolving)

            Spacer()

            if isResolving {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Revalidating request")
            }

            Button("Continue Without Changes") {
                resolve(.continueWithoutChanges, [])
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isResolving)

            Button("Allow These Notes Once") {
                resolve(.allowedSubset, canonicalSelection)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(
                isResolving
                    || selectedNoteIDs.isEmpty
                    || identity == nil
            )
        }
    }

    private var requestAuthority: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Text("REQUESTED AUTHORITY")
                .font(ScholiumInterfaceTypography.apparatusLabel)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
            LabeledContent("Action", value: identityName(\.actionName))
            LabeledContent("Changes", value: operationTitles)
            LabeledContent(
                "Working Method",
                value: identityName(\.skillName)
            )
            LabeledContent(
                "Package ID",
                value: record.request.requestedAction.packageID
            )
            LabeledContent(
                "Skill revision",
                value: fingerprintPrefix(
                    record.request.requestedAction.skillRevision
                )
            )
            LabeledContent(
                "Profile revision",
                value: fingerprintPrefix(
                    record.request.requestedAction.profileRevision
                )
            )
            if identityLoadFailed {
                Label(
                    "Current Action details are unavailable. Scholium will not allow this request.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
        }
        .font(ScholiumInterfaceTypography.apparatusResearchContent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.agentNoteChange.authority")
    }

    private var terminalContent: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            Label(terminalTitle, systemImage: terminalSymbol)
                .font(.headline)
            Text(terminalDetail)
                .font(ScholiumInterfaceTypography.apparatusResearchContent)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scholium.agentNoteChange.terminal")
    }

    private var terminalTitle: String {
        if hasLocallyExpired {
            return String(localized: "This Request Expired")
        }
        return switch record.decision.state {
        case .stale: String(localized: "This Request Is No Longer Current")
        case .expired: String(localized: "This Request Expired")
        default: String(localized: "This Request Is Resolved")
        }
    }

    private var terminalDetail: String {
        if hasLocallyExpired {
            return String(localized: "The request was not decided before its bounded lifetime ended. Silence did not grant permission.")
        }
        return switch record.decision.state {
        case .stale:
            String(localized: "A Note, revision, Skill, Profile, policy subject, lifecycle state, or parent run changed. Scholium recorded no new authority.")
        case .expired:
            String(localized: "The request was not decided before its bounded lifetime ended. Silence did not grant permission.")
        default:
            String(localized: "Scholium has already recorded a decision for this exact request.")
        }
    }

    private var terminalSymbol: String {
        hasLocallyExpired || record.decision.state == .expired
            ? "clock.badge.exclamationmark"
            : "arrow.triangle.2.circlepath"
    }

    private var canonicalSelection: [UUID] {
        selectedNoteIDs.sorted { $0.uuidString < $1.uuidString }
    }

    private func selectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedNoteIDs.contains(id) },
            set: { selected in
                if selected {
                    selectedNoteIDs.insert(id)
                } else {
                    selectedNoteIDs.remove(id)
                }
            }
        )
    }

    private func roleTitle(_ role: ResearchActionTargetRole) -> String {
        switch role {
        case .analysis: String(localized: "Analysis")
        case .topic: String(localized: "Topic")
        case .work: String(localized: "Work")
        }
    }

    private func identityName(
        _ keyPath: KeyPath<AgentNoteChangePresentationIdentity, String>
    ) -> String {
        if let identity {
            return identity[keyPath: keyPath]
        }
        return identityLoadFailed
            ? String(localized: "Unavailable")
            : String(localized: "Loading…")
    }

    private var operationTitles: String {
        record.request.operations.map { operation in
            switch operation {
            case .modifyMarkdown: String(localized: "Modify Markdown")
            case .modifyProperties: String(localized: "Modify Properties")
            }
        }.joined(separator: ", ")
    }

    private func revisionDescription(
        for target: AgentNoteChangeDisplayTarget
    ) -> String {
        let expected = fingerprintPrefix(target.expectedFingerprint)
        guard let current = target.currentFingerprint else {
            return String(
                format: String(localized: "Expected revision %@; current Note unavailable"),
                expected
            )
        }
        if current == target.expectedFingerprint {
            return String(
                format: String(localized: "Expected revision %@; current revision matches"),
                expected
            )
        }
        return String(
            format: String(localized: "Expected revision %@; current revision changed"),
            expected
        )
    }

    private func fingerprintPrefix(_ fingerprint: DocumentFingerprint) -> String {
        String(fingerprint.sha256.prefix(12)) + "…"
    }
}
