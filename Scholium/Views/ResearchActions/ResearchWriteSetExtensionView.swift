import ScholiumContracts
import SwiftUI

struct ResearchAgentPermissionView: View {
    let claim: ResearchAgentPermissionClaim
    let hasLocallyExpired: Bool
    let isResolving: Bool
    let resolveWriteSet: (
        ResearchWriteSetExtensionState,
        [ResearchWriteTargetHandle]
    ) -> Void
    let resolveContinuation: (Bool) -> Void
    let dismiss: () -> Void

    @ViewBuilder
    var body: some View {
        switch claim {
        case .writeSetExtension(let record):
            ResearchWriteSetExtensionView(
                record: record,
                hasLocallyExpired: hasLocallyExpired,
                isResolving: isResolving,
                resolve: resolveWriteSet,
                dismiss: dismiss
            )
        case .continuation(let record):
            ResearchContinuationPermissionView(
                record: record,
                hasLocallyExpired: hasLocallyExpired,
                isResolving: isResolving,
                resolve: resolveContinuation,
                dismiss: dismiss
            )
        }
    }
}

struct ResearchWriteSetExtensionView: View {
    let record: ResearchWriteSetExtensionRecord
    let hasLocallyExpired: Bool
    let isResolving: Bool
    let resolve: (ResearchWriteSetExtensionState, [ResearchWriteTargetHandle]) -> Void
    let dismiss: () -> Void

    @State private var selectedHandles: Set<ResearchWriteTargetHandle>

    init(
        record: ResearchWriteSetExtensionRecord,
        hasLocallyExpired: Bool,
        isResolving: Bool,
        resolve: @escaping (
            ResearchWriteSetExtensionState,
            [ResearchWriteTargetHandle]
        ) -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.record = record
        self.hasLocallyExpired = hasLocallyExpired
        self.isResolving = isResolving
        self.resolve = resolve
        self.dismiss = dismiss
        _selectedHandles = State(initialValue: Set(record.candidates.map(\.handle)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text("Allow Additional Notes for This Research Run?")
                    .font(ScholiumTypography.scholarly(.title))
                    .accessibilityAddTraits(.isHeader)
                Text("Select the requested Note targets this Run may create or modify.")
                    .font(ScholiumTypography.scholarly(.body))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScholiumStructuralRule()
            if record.isUnresolved && !hasLocallyExpired {
                requestContent
                ScholiumStructuralRule()
                decisionButtons
            } else {
                Label(
                    hasLocallyExpired ? "This Request Expired" : "This Request Is Resolved",
                    systemImage: hasLocallyExpired
                        ? "clock.badge.exclamationmark"
                        : "checkmark.shield"
                )
                .font(ScholiumTypography.interface(.sectionTitle))
                Spacer()
                HStack {
                    Spacer()
                    Button("Done", action: dismiss)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 420, idealHeight: 520)
        .scholiumSurface(.denseEvidence)
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchWriteSetExtension.sheet")
        .interactiveDismissDisabled(isResolving)
    }

    private var requestContent: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            Text("ACADEMIC REASON")
                .font(ScholiumTypography.interface(.small, emphasis: .strong))
                .scholiumForeground(.secondaryText)
            Text(record.intent.academicReason)
                .font(ScholiumTypography.scholarly(.body))
                .textSelection(.enabled)

            Text("REQUESTED NOTES")
                .font(ScholiumTypography.interface(.small, emphasis: .strong))
                .scholiumForeground(.secondaryText)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(record.candidates) { candidate in
                        Toggle(isOn: selectionBinding(candidate.handle)) {
                            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment) {
                                Text(candidate.title).font(ScholiumTypography.interface(.sectionTitle))
                                Text("\(roleTitle(candidate.role))  \(candidate.note.relativePath)")
                                    .font(ScholiumTypography.interface(.small))
                                    .scholiumForeground(.secondaryText)
                                Text(operationTitles(candidate.operations))
                                    .font(ScholiumTypography.interface(.small))
                                    .scholiumForeground(.secondaryText)
                                if !candidate.propertyKeys.isEmpty {
                                    Text("Properties: \(propertyPlanDescription(candidate))")
                                        .font(ScholiumTypography.exact(.small))
                                        .scholiumForeground(.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .toggleStyle(.checkbox)
                        .frame(minHeight: ScholiumGrid.Dimension.researchFunctionTargetHeight)
                        .accessibilityHint("Selects this exact target and operation for this Run.")
                        ScholiumStructuralRule()
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var decisionButtons: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Button("Cancel Request", role: .destructive) {
                resolve(.cancelled, [])
            }
            .disabled(isResolving)
            Spacer()
            if isResolving {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Revalidating bounded write request")
            }
            Button("Continue Without Changes") {
                resolve(.continueWithoutChanges, [])
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isResolving)
            Button("Allow Selected Notes") {
                resolve(.allowedSubset, canonicalSelection)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isResolving || selectedHandles.isEmpty)
        }
    }

    private var canonicalSelection: [ResearchWriteTargetHandle] {
        selectedHandles.sorted { $0.rawValue < $1.rawValue }
    }

    private func selectionBinding(
        _ handle: ResearchWriteTargetHandle
    ) -> Binding<Bool> {
        Binding(
            get: { selectedHandles.contains(handle) },
            set: { selected in
                if selected { selectedHandles.insert(handle) }
                else { selectedHandles.remove(handle) }
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

    private func operationTitles(
        _ operations: [ResearchDocumentWriteOperation]
    ) -> String {
        operations.map {
            switch $0 {
            case .createNote: String(localized: "Create Note")
            case .modifyMarkdown: String(localized: "Modify Markdown")
            case .modifyProperties: String(localized: "Modify Properties")
            }
        }.joined(separator: ", ")
    }

    private func propertyPlanDescription(
        _ candidate: ResearchWriteSetCandidate
    ) -> String {
        candidate.propertyWritePlans.map {
            "\($0.key) (\($0.valueKind.rawValue))"
        }.joined(separator: ", ")
    }
}

private struct ResearchContinuationPermissionView: View {
    let record: ResearchContinuationRequestRecord
    let hasLocallyExpired: Bool
    let isResolving: Bool
    let resolve: (Bool) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text("Allow the Next Research Action?")
                    .font(ScholiumTypography.scholarly(.title))
                    .accessibilityAddTraits(.isHeader)
                Text("This starts a new independent Run with current permissions for the selected Action and target.")
                    .font(ScholiumTypography.scholarly(.body))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScholiumStructuralRule()
            if record.state == .pending && !hasLocallyExpired {
                requestContent
                ScholiumStructuralRule()
                decisionButtons
            } else {
                Label(
                    hasLocallyExpired ? "This Request Expired" : "This Request Is Resolved",
                    systemImage: hasLocallyExpired
                        ? "clock.badge.exclamationmark"
                        : "checkmark.shield"
                )
                .font(ScholiumTypography.interface(.sectionTitle))
                Spacer()
                HStack {
                    Spacer()
                    Button("Done", action: dismiss)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
        .frame(minWidth: 560, idealWidth: 660, minHeight: 460, idealHeight: 580)
        .scholiumSurface(.denseEvidence)
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchContinuationPermission.sheet")
        .interactiveDismissDisabled(record.state == .pending || isResolving)
    }

    private var requestContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
                permissionValue("NEXT ACTION", actionTitle(record.request.nextActionID))
                permissionValue(
                    "TARGET",
                    "\(roleTitle(record.request.targetRole))  \(record.request.targetRelativePath)"
                )
                permissionValue("ACADEMIC PURPOSE", record.request.academicPurpose)

                Text("BOUNDED HANDOFF")
                    .font(ScholiumTypography.interface(.small, emphasis: .strong))
                    .scholiumForeground(.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    ForEach(Array(record.request.handoff.enumerated()), id: \.offset) {
                        index, item in
                        VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.fieldDetailSpacing) {
                            Text("\(index + 1). \(epistemicStatusTitle(item.epistemicStatus))")
                                .font(ScholiumTypography.interface(.sectionTitle))
                            Text(item.content)
                                .font(ScholiumTypography.scholarly(.body))
                                .textSelection(.enabled)
                            Text("Next use: \(item.nextUse)")
                                .font(ScholiumTypography.interface(.small))
                                .scholiumForeground(.secondaryText)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if index + 1 < record.request.handoff.count {
                            ScholiumStructuralRule()
                        }
                    }
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var decisionButtons: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Button("Decline") { resolve(false) }
                .keyboardShortcut(.cancelAction)
                .disabled(isResolving)
            Spacer()
            if isResolving {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Revalidating next Action request")
            }
            Button("Allow Next Action") { resolve(true) }
                .keyboardShortcut(.defaultAction)
                .disabled(isResolving)
        }
    }

    private func permissionValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.fieldDetailSpacing) {
            Text(label)
                .font(ScholiumTypography.interface(.small, emphasis: .strong))
                .scholiumForeground(.secondaryText)
                .accessibilityAddTraits(.isHeader)
            Text(value)
                .font(ScholiumTypography.scholarly(.body))
                .textSelection(.enabled)
        }
    }

    private func roleTitle(_ role: ResearchActionTargetRole) -> String {
        switch role {
        case .analysis: String(localized: "Analysis")
        case .topic: String(localized: "Topic")
        case .work: String(localized: "Work")
        }
    }

    private func epistemicStatusTitle(
        _ status: ResearchContinuationEpistemicStatus
    ) -> String {
        switch status {
        case .sourceConclusion: String(localized: "Source Conclusion")
        case .agentReconstruction: String(localized: "Agent Reconstruction")
        case .hypothesisToVerify: String(localized: "Hypothesis to Verify")
        case .unresolvedQuestion: String(localized: "Unresolved Question")
        }
    }
}
