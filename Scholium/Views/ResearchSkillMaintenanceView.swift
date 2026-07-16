import ScholiumContracts
import SwiftUI

/// Stateless Settings presentation for explicit, evaluated whole-package
/// maintenance. It receives no store, package path, or Application handle.
struct ResearchSkillMaintenanceView: View {
    @Binding var instruction: String
    @Binding var proposalSource: String
    @Binding var evaluationEvidenceSource: String
    let currentPackage: ResearchSkillProposedPackage?
    let proposedPackage: ResearchSkillProposedPackage?
    let proposalError: String?
    let preparation: ResearchSkillMaintenancePreparation?
    let appliedOutcome: ResearchSkillMaintenanceApplyOutcome?
    let recoverySnapshots: [ResearchSkillMaintenanceSnapshot]
    let currentPackageRevision: DocumentFingerprint?
    let isWorking: Bool
    let isLoadingCurrentPackage: Bool
    let hasUnsavedSkillDraft: Bool
    let proposalSourceMatchesImport: Bool
    let canRequestEvaluation: Bool
    let canApply: Bool
    let copyProposalRequest: () -> Void
    let importProposal: () -> Void
    let copyEvaluationRequest: () -> Void
    let prepare: () -> Void
    let apply: () -> Void
    let restore: (ResearchSkillMaintenanceSnapshot) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Describe why this Researcher Skill should change. Scholium validates the complete package structure; Apply also requires an attributed external evaluation bound to the exact proposed revision.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $instruction)
                    .frame(minHeight: 68, maxHeight: 100)
                    .padding(5)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }
                    .accessibilityLabel("Maintenance instruction")
                    .accessibilityIdentifier("scholium.researchGuidance.maintenanceInstruction")
                    .disabled(appliedOutcome != nil)

                proposalStep

                if let currentPackage, let proposedPackage {
                    packageComparison(current: currentPackage, proposed: proposedPackage)
                }

                if let preparation {
                    evaluation(preparation)
                    if !canRequestEvaluation {
                        Label(
                            "The maintenance purpose or imported proposal changed after validation. Validate this proposal again before requesting evaluation.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    agentHandoff(preparation)
                }

                if appliedOutcome != nil {
                    Label(
                        "Applied with a restorable snapshot.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("scholium.researchGuidance.maintenanceApplied")
                } else {
                    HStack {
                        Button("Validate Proposal", action: prepare)
                            .disabled(
                                isWorking
                                    || proposedPackage == nil
                                    || currentPackage == nil
                                    || hasUnsavedSkillDraft
                                    || !proposalSourceMatchesImport
                                    || instruction.trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    ).isEmpty
                            )
                            .accessibilityIdentifier("scholium.researchGuidance.maintenanceEvaluate")
                        Spacer()
                        if canApply {
                            Button("Apply", action: apply)
                                .buttonStyle(.borderedProminent)
                                .disabled(isWorking)
                                .accessibilityIdentifier("scholium.researchGuidance.maintenanceApply")
                        }
                    }
                }

                recovery
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Guided Evolution", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
        }
        .accessibilityIdentifier("scholium.researchGuidance.maintenance")
    }

    @ViewBuilder
    private var recovery: some View {
        if !recoverySnapshots.isEmpty {
            GroupBox("Recovery") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Snapshots remain available after Settings closes or Scholium relaunches. Restoring replaces the complete current package only after its revision is rechecked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(recoverySnapshots) { snapshot in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.createdAt, format: .dateTime.year().month().day().hour().minute())
                                Text(snapshot.packageRevision.sha256)
                                    .font(ScholiumTypography.swiftUIMonospaceFont(
                                        size: 10,
                                        relativeTo: .caption
                                    ))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if snapshot.packageRevision == currentPackageRevision {
                                Text("Current")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Restore") { restore(snapshot) }
                                    .disabled(isWorking || hasUnsavedSkillDraft)
                                    .accessibilityIdentifier(
                                        "scholium.researchGuidance.maintenanceRestore.\(snapshot.id.uuidString)"
                                    )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var proposalStep: some View {
        GroupBox("External Proposal") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Copy the complete current package, its revision, and the maintenance purpose to an external agent. Import the returned complete package JSON before structural validation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if hasUnsavedSkillDraft {
                    Label(
                        "Save or discard the unsaved SKILL.md draft before requesting, importing, validating, applying, or restoring a package.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                if isLoadingCurrentPackage {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading the complete current package…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let currentPackage {
                    LabeledContent("Current package revision") {
                        Text(currentPackage.packageRevision.sha256)
                            .font(ScholiumTypography.swiftUIMonospaceFont(
                                size: 10,
                                relativeTo: .caption
                            ))
                            .textSelection(.enabled)
                    }
                    .font(.caption)
                }

                Button("Copy Proposal Request", action: copyProposalRequest)
                    .disabled(
                        isWorking
                            || currentPackage == nil
                            || hasUnsavedSkillDraft
                            || appliedOutcome != nil
                            || instruction.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                    )
                    .accessibilityIdentifier(
                        "scholium.researchGuidance.maintenanceCopyProposalRequest"
                    )

                Text("Returned complete package JSON")
                    .font(.caption.weight(.semibold))
                TextEditor(text: $proposalSource)
                    .font(ScholiumTypography.swiftUIMonospaceFont(
                        size: 11,
                        relativeTo: .caption
                    ))
                    .frame(minHeight: 110, maxHeight: 200)
                    .padding(5)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }
                    .accessibilityLabel("Returned complete Researcher Skill package JSON")
                    .accessibilityIdentifier(
                        "scholium.researchGuidance.maintenanceProposalJSON"
                    )
                    .disabled(appliedOutcome != nil)

                if let proposalError {
                    Label(proposalError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .accessibilityIdentifier(
                            "scholium.researchGuidance.maintenanceProposalError"
                        )
                }

                if proposedPackage != nil, !proposalSourceMatchesImport {
                    Label(
                        "The returned JSON changed after its last import. Import it again before validation or Apply.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                HStack {
                    Button("Import Proposal", action: importProposal)
                        .disabled(
                            isWorking
                                || currentPackage == nil
                                || hasUnsavedSkillDraft
                                || appliedOutcome != nil
                                || proposalSource.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty
                        )
                        .accessibilityIdentifier(
                            "scholium.researchGuidance.maintenanceImportProposal"
                        )
                    Spacer()
                    if let proposedPackage, proposalSourceMatchesImport {
                        Label(
                            "Imported \(proposedPackage.files.count) files",
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.green)
                    }
                }

                if let proposedPackage {
                    LabeledContent("Proposed package revision") {
                        Text(proposedPackage.packageRevision.sha256)
                            .font(ScholiumTypography.swiftUIMonospaceFont(
                                size: 10,
                                relativeTo: .caption
                            ))
                            .textSelection(.enabled)
                    }
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func agentHandoff(
        _ preparation: ResearchSkillMaintenancePreparation
    ) -> some View {
        GroupBox("External Evaluation") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Copy the complete proposal and its revision to an external agent. Paste the agent’s attributed JSON report below, then validate the proposal again. Scholium does not run this philosophical evaluation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Proposed revision") {
                    Text(preparation.proposedPackageRevision.sha256)
                        .font(ScholiumTypography.swiftUIMonospaceFont(
                            size: 10,
                            relativeTo: .caption
                        ))
                        .textSelection(.enabled)
                }
                .font(.caption)
                Button("Copy Evaluation Request", action: copyEvaluationRequest)
                    .disabled(isWorking || !canRequestEvaluation || appliedOutcome != nil)
                    .accessibilityIdentifier(
                        "scholium.researchGuidance.maintenanceCopyHandoff"
                    )
                TextEditor(text: $evaluationEvidenceSource)
                    .font(ScholiumTypography.swiftUIMonospaceFont(
                        size: 11,
                        relativeTo: .caption
                    ))
                    .frame(minHeight: 110, maxHeight: 180)
                    .padding(5)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }
                    .accessibilityLabel("Agent evaluation report JSON")
                    .accessibilityIdentifier(
                        "scholium.researchGuidance.maintenanceEvidence"
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func evaluation(
        _ preparation: ResearchSkillMaintenancePreparation
    ) -> some View {
        let result = preparation.evaluation
        return VStack(alignment: .leading, spacing: 8) {
            Text("Structural Validation")
                .font(.callout.weight(.semibold))
            statusLabel(result.structuralStatus ?? .incomplete)
            ForEach(result.validationIssues, id: \.self) { issue in
                Text(issue)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ForEach(result.cases.filter { $0.id.hasPrefix("core-") }) {
                evaluationCaseRow($0)
            }

            Divider()

            Text("Agent-Reported Evaluation")
                .font(.callout.weight(.semibold))
            statusLabel(result.externalStatus ?? .incomplete)
            if let evaluator = result.evaluator {
                LabeledContent("Reported by", value: evaluator)
                    .font(.caption)
            } else {
                Text("No attributed external evaluation has been supplied. Apply remains unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let method = result.method {
                LabeledContent("Method", value: method)
                    .font(.caption)
            }
            if let revision = result.proposedPackageRevision {
                LabeledContent("Proposal revision") {
                    Text(revision.sha256)
                        .font(ScholiumTypography.swiftUIMonospaceFont(
                            size: 10,
                            relativeTo: .caption
                        ))
                        .textSelection(.enabled)
                }
                .font(.caption)
            }
            if result.proposedPackageRevision != nil,
               result.proposedPackageRevision != preparation.proposedPackageRevision {
                Label(
                    "The reported evaluation is not bound to this proposal revision.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }
            ForEach(result.cases.filter { !$0.id.hasPrefix("core-") }) {
                evaluationCaseRow($0)
            }
        }
        .accessibilityIdentifier("scholium.researchGuidance.maintenanceEvaluation")
    }

    private func evaluationCaseRow(
        _ evaluationCase: ResearchSkillMaintenanceEvaluationCase
    ) -> some View {
        LabeledContent(evaluationCase.id) {
            Label(
                evaluationCase.summary,
                systemImage: evaluationSymbol(evaluationCase.status)
            )
            .foregroundStyle(evaluationColor(evaluationCase.status))
            .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    private func packageComparison(
        current: ResearchSkillProposedPackage,
        proposed: ResearchSkillProposedPackage
    ) -> some View {
        let comparisons = ResearchSkillMaintenanceProposalDraft.comparisons(
            current: current,
            proposed: proposed
        )
        let changed = comparisons.filter { $0.kind != .unchanged }
        return DisclosureGroup("Package Comparison (\(changed.count) changed)") {
            VStack(alignment: .leading, spacing: 8) {
                if changed.isEmpty {
                    Label("No file content changes", systemImage: "equal.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(changed) { comparison in
                        DisclosureGroup {
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: 10) {
                                    sourceColumn(
                                        "Current",
                                        source: comparison.currentSource,
                                        absentLabel: "Not present"
                                    )
                                    sourceColumn(
                                        "Proposed",
                                        source: comparison.proposedSource,
                                        absentLabel: "Removed"
                                    )
                                }
                                VStack(alignment: .leading, spacing: 10) {
                                    sourceColumn(
                                        "Current",
                                        source: comparison.currentSource,
                                        absentLabel: "Not present"
                                    )
                                    sourceColumn(
                                        "Proposed",
                                        source: comparison.proposedSource,
                                        absentLabel: "Removed"
                                    )
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            HStack {
                                Label(
                                    comparison.relativePath,
                                    systemImage: changeSymbol(comparison.kind)
                                )
                                Spacer()
                                Text(changeTitle(comparison.kind))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                }
                let unchangedCount = comparisons.count - changed.count
                if unchangedCount > 0 {
                    Text("\(unchangedCount) unchanged \(unchangedCount == 1 ? "file" : "files")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)
        }
        .accessibilityIdentifier("scholium.researchGuidance.maintenanceDiff")
    }

    private func sourceColumn(
        _ title: String,
        source: String?,
        absentLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
            ScrollView([.horizontal, .vertical]) {
                Text(source ?? absentLabel)
                    .font(ScholiumTypography.swiftUIMonospaceFont(size: 11, relativeTo: .caption))
                    .foregroundStyle(source == nil ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: 100, maxHeight: 180)
            .padding(6)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func evaluationTitle(_ status: ResearchSkillMaintenanceEvaluationStatus) -> String {
        switch status {
        case .passed: "Passed"
        case .failed: "Failed"
        case .incomplete: "Incomplete"
        }
    }

    private func statusLabel(
        _ status: ResearchSkillMaintenanceEvaluationStatus
    ) -> some View {
        Label(evaluationTitle(status), systemImage: evaluationSymbol(status))
            .foregroundStyle(evaluationColor(status))
            .font(.caption.weight(.semibold))
    }

    private func evaluationSymbol(_ status: ResearchSkillMaintenanceEvaluationStatus) -> String {
        switch status {
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .incomplete: "exclamationmark.triangle.fill"
        }
    }

    private func evaluationColor(_ status: ResearchSkillMaintenanceEvaluationStatus) -> Color {
        switch status {
        case .passed: .green
        case .failed: .red
        case .incomplete: .orange
        }
    }

    private func changeSymbol(_ kind: ResearchSkillMaintenanceChangeKind) -> String {
        switch kind {
        case .added: "plus.circle"
        case .modified: "pencil.circle"
        case .removed: "minus.circle"
        case .unchanged: "equal.circle"
        }
    }

    private func changeTitle(_ kind: ResearchSkillMaintenanceChangeKind) -> String {
        switch kind {
        case .added: "Added"
        case .modified: "Modified"
        case .removed: "Removed"
        case .unchanged: "Unchanged"
        }
    }
}
