#if DEBUG
import ScholiumContracts
import SwiftUI

/// Deterministic, development-only interface proofs for research workflows
/// that still benefit from a runnable synthetic surface. These views own no
/// vault, Skill, permission, execution, or Research Record authority.
struct ResearchWorkflowPreviewCatalog: View {
    @State private var selection: ResearchWorkflowProof = .actionSheet

    var body: some View {
        NavigationSplitView {
            List(ResearchWorkflowProof.allCases, selection: $selection) { proof in
                Label(proof.title, systemImage: proof.systemImage)
                    .tag(proof)
                    .accessibilityIdentifier("scholium.proofs.navigation.\(proof.rawValue)")
            }
            .navigationTitle("Interface Proofs")
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
            .scholiumSurface(.navigation)
        } detail: {
            ResearchWorkflowProofDetail(proof: selection)
                .id(selection)
        }
        .frame(minWidth: 520, minHeight: 680)
        .accessibilityIdentifier("scholium.proofs.catalog")
    }
}

enum ResearchWorkflowProof: String, CaseIterable, Identifiable {
    case actionSheet
    case researchGuidance
    case writeSetExtension

    var id: String { rawValue }

    var title: String {
        switch self {
        case .actionSheet: "Skill-run Sheet"
        case .researchGuidance: "Research Guidance"
        case .writeSetExtension: "Bounded Write Set"
        }
    }

    var systemImage: String {
        switch self {
        case .actionSheet: "list.bullet.rectangle"
        case .researchGuidance: "slider.horizontal.3"
        case .writeSetExtension: "doc.badge.ellipsis"
        }
    }
}

private struct ResearchWorkflowProofDetail: View {
    let proof: ResearchWorkflowProof

    var body: some View {
        VStack(spacing: 0) {
            ResearchProofHeader(title: proof.title)
            ScholiumStructuralRule()
            proofContent
        }
        .scholiumSurface(.document)
    }

    @ViewBuilder
    private var proofContent: some View {
        switch proof {
        case .actionSheet:
            ResearchActionSheetProof()
        case .researchGuidance:
            ResearchGuidanceSettingsProof()
        case .writeSetExtension:
            ResearchWriteSetExtensionProof()
        }
    }
}

private struct ResearchProofHeader: View {
    let title: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text(title)
                .font(ScholiumInterfaceTypography.apparatusTitle)
            Spacer()
            Text("Synthetic data")
                .font(ScholiumInterfaceTypography.metadata)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
        }
        .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
        .frame(minHeight: ScholiumGrid.Dimension.regionHeaderHeight)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Generic modular Skill-run sheet

enum ResearchActionProofKind: String, CaseIterable, Identifiable {
    case discuss
    case analyze
    case synthesize
    case write
    case critique
    case checkFidelity
    case manuscript

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discuss: "Discuss"
        case .analyze: "Analyze"
        case .synthesize: "Synthesize"
        case .write: "Write"
        case .critique: "Critique"
        case .checkFidelity: "Check Fidelity"
        case .manuscript: "Manuscript"
        }
    }

    var systemImage: String {
        switch self {
        case .discuss: "text.bubble"
        case .analyze: "doc.text.magnifyingglass"
        case .synthesize: "arrow.triangle.merge"
        case .write: "pencil"
        case .critique: "text.magnifyingglass"
        case .checkFidelity: "checkmark.shield"
        case .manuscript: "doc.richtext"
        }
    }

    var target: String {
        switch self {
        case .analyze: "Attention and Salience.md (Analysis)"
        case .synthesize: "Attention and Normative Reasons.md (Topic)"
        case .write, .critique, .manuscript: "Revisable Judgment.md (Work)"
        case .discuss, .checkFidelity: "Current note"
        }
    }

    var candidateWriteScope: String {
        switch self {
        case .analyze: "Current Analysis only"
        case .synthesize: "Current Topic only"
        case .write: "Current Work only"
        case .critique: "Critique output only; Work is read-only"
        case .manuscript: "Separately authorized Work phases only"
        case .discuss, .checkFidelity: "None; current note is read-only"
        }
    }

    var includesRequest: Bool { self != .checkFidelity }
    var includesSource: Bool { self == .analyze }
    var includesChecks: Bool { self == .checkFidelity }
}

struct ResearchActionSheetProof: View {
    let action: ResearchActionProofKind
    @State private var selectedMaterial = "Attention and Salience.md"
    @State private var request = "State the scholarly task in your own words."
    @State private var checksContent = true
    @State private var checksCitations = true

    init(action: ResearchActionProofKind = .analyze) {
        self.action = action
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                ResearchSheetIdentity(
                    action: action.title,
                    skill: "\(action.title), working revision 3",
                    target: action.target,
                    revision: "f4d77c2a"
                )
                ScholiumStructuralRule()

                ResearchProofSection(title: "SKILL PARAMETERS") {
                    Grid(alignment: .leading, horizontalSpacing: ScholiumGrid.Spacing.sectionSeparation, verticalSpacing: ScholiumGrid.Spacing.nestedContentInset) {
                        if action.includesRequest {
                            GridRow {
                                Text("Request")
                                TextField("Describe the task", text: $request, axis: .vertical)
                                    .lineLimit(2...4)
                            }
                        }
                        GridRow {
                            Text("Passage")
                            Button("Use current selection, paragraphs 4–7") {}
                        }
                        GridRow {
                            Text("Material")
                            Picker("Material", selection: $selectedMaterial) {
                                Text("Attention and Salience.md").tag("Attention and Salience.md")
                                Text("Normative Reasons.md").tag("Normative Reasons.md")
                            }
                            .labelsHidden()
                        }
                        if action.includesSource {
                            GridRow {
                                Text("Source")
                                Button("Nagel, What Is It Like to Be a Bat?.pdf") {}
                                    .accessibilityIdentifier("scholium.proofs.run.source")
                            }
                        }
                        if action.includesChecks {
                            GridRow(alignment: .top) {
                                Text("Checks")
                                VStack(alignment: .leading, spacing: 6) {
                                    Toggle("Content", isOn: $checksContent)
                                    Toggle("Citations", isOn: $checksCitations)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    .font(ScholiumInterfaceTypography.apparatusBody)
                }

                ScholiumStructuralRule()
                ResearchAuthorityFacts(action: action)
                ResearchActionProofFooter()
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("scholium.proofs.runSheet")
        .scholiumSurface(.denseEvidence)
    }
}

private struct ResearchSheetIdentity: View {
    let action: String
    let skill: String
    let target: String
    let revision: String

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text(action)
                .font(ScholiumInterfaceTypography.documentTitle)
                .accessibilityAddTraits(.isHeader)
            Text(skill)
                .font(ScholiumInterfaceTypography.apparatusResearchContent)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
            LabeledContent("Target", value: target)
            LabeledContent("Starting revision", value: revision)
                .monospacedDigit()
        }
    }
}

private struct ResearchAuthorityFacts: View {
    let action: ResearchActionProofKind

    var body: some View {
        ResearchProofSection(title: "APP-OWNED BOUNDARY") {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                LabeledContent("Collaboration policy", value: "Ask Me Every Time")
                LabeledContent("Candidate write scope", value: action.candidateWriteScope)
                LabeledContent(
                    "Recovery",
                    value: action.candidateWriteScope.hasPrefix("None")
                        ? "No Target write"
                        : "Exact written Notes"
                )
                LabeledContent("Conflicts", value: "Revalidated before write")
                LabeledContent("Conflict recovery", value: "Retained displaced bytes")
                Text("The Method may guide scholarly work, but it cannot hide or expand these app-owned facts.")
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(ScholiumInterfaceTypography.apparatusResearchContent)
        }
    }
}

private struct ResearchActionProofFooter: View {
    var body: some View {
        HStack(spacing: 10) {
            Button("Cancel") {}
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Copy Handoff") {}
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct ResearchSheetButtons: View {
    let primary: String

    var body: some View {
        HStack {
            Spacer()
            Button("Cancel") {}
                .keyboardShortcut(.cancelAction)
            Button(primary) {}
                .keyboardShortcut(.defaultAction)
        }
        .accessibilityIdentifier("scholium.proofs.sheet.actions")
    }
}

// MARK: - Research Guidance

private enum ResearchGuidanceProofCategory: String, CaseIterable, Identifiable {
    case methods = "Methods"
    case profilesPractices = "Profiles & Practices"
    case collaboration = "Collaboration"
    case sources = "Sources & Integrations"
    case recovery = "Recovery & Technical"

    var id: String { rawValue }
}

private struct ResearchGuidanceSettingsProof: View {
    @State private var category: ResearchGuidanceProofCategory = .methods

    var body: some View {
        HStack(spacing: 0) {
            List(ResearchGuidanceProofCategory.allCases, selection: $category) { item in
                Text(item.rawValue)
                    .tag(item)
                    .accessibilityIdentifier("scholium.proofs.settings.\(item.id)")
            }
            .frame(minWidth: 210, idealWidth: 230)
            .scholiumSurface(.navigation)

            ScholiumStructuralRule(orientation: .vertical)

            ScrollView {
                ResearchGuidanceSettingsDetail(category: category)
                    .padding(ScholiumGrid.Spacing.regionContentInset)
                    .frame(maxWidth: 680, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .scholiumSurface(.document)
        }
    }
}

private struct ResearchGuidanceSettingsDetail: View {
    let category: ResearchGuidanceProofCategory
    @State private var collaborationPolicy = "Ask Me Every Time"

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
            Text(category.rawValue)
                .font(ScholiumInterfaceTypography.documentTitle)
                .accessibilityAddTraits(.isHeader)
            settingsContent
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch category {
        case .methods:
            ResearchProofSection(title: "RESEARCH SKILLS") {
                        Text("Each Platform Action routes to one current primary Markdown Method. Exact Wikilinks select Practices; an optional local folder is ordinary Agent-readable storage, not a package.")
                    .font(ScholiumInterfaceTypography.apparatusResearchContent)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 0) {
                            ForEach([
                                ("Discuss", "Argument Mapping, Counterexample Testing"),
                                ("Analyze", "Source Analysis, Conceptual Analysis"),
                                ("Synthesize", "Dialectical Mapping"),
                                ("Write", "Objection Development, Reply Construction"),
                                ("Critique", "Argument Mapping, Counterexample Testing"),
                                ("Check Fidelity", "Interpretive Triangulation"),
                                ("Manuscript", "Thesis Stabilization, Terminological Audit"),
                            ], id: \.0) { name, practices in
                        ResearchWorkingMethodProofRow(name: name, practices: practices)
                        ScholiumStructuralRule()
                    }
                }
            }
            ResearchProofSection(title: "BOUNDARY") {
                Text("Method and Practice prose can guide scholarly work. It cannot change Platform Actions, Sessions, collaboration policy, bounded writes, exact revisions, conflicts, or recovery.")
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .profilesPractices:
                   ResearchSkillGroup(title: "ACADEMIC PROFILES", detail: "Flat researcher-facing fields", rows: [
                       "Analyze: source and passage inputs; evidence Result fields",
                       "Critique: target and standard inputs; objection Result fields",
                   ], actionTitle: "Enable")
            ResearchSkillGroup(title: "PHILOSOPHICAL PRACTICES", detail: "Exact Markdown linked from primary Methods", rows: [
                "Argument Mapping.md",
                "Counterexample Testing.md",
                "Interpretive Triangulation.md",
            ], actionTitle: "Edit")
            Text("A Practice keeps one replaceable previous edit. It guides research but never grants authority.")
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .fixedSize(horizontal: false, vertical: true)
        case .collaboration:
            ResearchProofSection(title: "TRIPTYCH COLLABORATION") {
                Picker("Collaboration policy", selection: $collaborationPolicy) {
                    Text("Ask Me Every Time").tag("Ask Me Every Time")
                    Text("Ask Me Only for Works").tag("Ask Me Only for Works")
                    Text("Full Triptych Access").tag("Full Triptych Access")
                }
                Text("The policy only controls when Scholium asks to extend one Run's bounded write set. It is not attached to a Skill or Agent and never grants blanket writes.")
                    .font(ScholiumInterfaceTypography.apparatusResearchContent)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .sources:
            ResearchSkillGroup(title: "SOURCE ROUTES", detail: "Explicit source identity", rows: [
                "Zotero local attachment route",
                "Researcher-selected local file route",
            ], actionTitle: nil)
            ResearchSkillGroup(title: "CITATION STYLE", detail: "Triptych-owned configuration", rows: [
                "APA 7",
            ], actionTitle: "Select")
            ResearchSkillGroup(title: "AGENT & CLI", detail: "Local authenticated handoff", rows: [
                "Pairing and Session are short-lived and restart-invalidated",
                "CLI uses the same Application owner as the app",
            ], actionTitle: nil)
        case .recovery:
            ResearchSkillGroup(title: "RECOVERY", detail: "Machine-local operational state", rows: [
                "Settled Note version retention",
                "One previous primary Method edit",
                "One previous Practice edit",
            ], actionTitle: nil)
        }
    }
}

private struct ResearchWorkingMethodProofRow: View {
    let name: String
    let practices: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text(name)
                Text("Practices: \(practices)")
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
            Spacer()
            Menu("Manage") {
                Button("Edit Primary Markdown") {}
                Button("Register Markdown…") {}
                Button("Register Skill Folder…") {}
                Divider()
                Button("Restore Previous Edit") {}
                Button("Restore Scholium Default…") {}
            }
            .menuStyle(.borderlessButton)
        }
        .font(ScholiumInterfaceTypography.apparatusBody)
        .frame(minHeight: ScholiumGrid.Dimension.researchFunctionTargetHeight)
    }
}

private struct ResearchSkillGroup: View {
    let title: String
    let detail: String
    let rows: [String]
    var actionTitle: String? = "Edit"

    var body: some View {
        ResearchProofSection(title: title) {
            Text(detail)
                .font(ScholiumInterfaceTypography.apparatusResearchContent)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
            VStack(spacing: 0) {
                ForEach(rows, id: \.self) { row in
                    HStack {
                        Text(row)
                        Spacer()
                        if let actionTitle {
                            Button(actionTitle) {}
                                .buttonStyle(.borderless)
                        }
                    }
                    .font(ScholiumInterfaceTypography.apparatusBody)
                    .frame(minHeight: ScholiumGrid.Dimension.researchFunctionTargetHeight)
                    ScholiumStructuralRule()
                }
            }
        }
    }
}

// MARK: - Bounded write-set extension

private struct ResearchWriteSetExtensionNote: Identifiable {
    let id: String
    let title: String
    var isSelected: Bool
}

private struct ResearchWriteSetExtensionProof: View {
    @State private var notes = [
        ResearchWriteSetExtensionNote(id: "topic-attention", title: "Topic: Attention", isSelected: true),
        ResearchWriteSetExtensionNote(id: "topic-normative-reasons", title: "Topic: Normative Reasons", isSelected: false),
        ResearchWriteSetExtensionNote(id: "work-chapter-three", title: "Work: Chapter Three", isSelected: true),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                Text("Allow Additional Notes for This Research Run?")
                    .font(ScholiumInterfaceTypography.documentTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("One decision may add any selected subset to this Run. Each later write remains independently revision checked and recoverable.")
                    .font(ScholiumInterfaceTypography.apparatusResearchContent)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)

                ResearchProofSection(title: "REQUEST") {
                    LabeledContent("Current Run", value: "Analyze Attention and Salience")
                    LabeledContent("Reason", value: "Two claims now bear directly on the current Topic and one Work section.")
                }

                ResearchProofSection(title: "REQUESTED NOTES") {
                    VStack(spacing: 0) {
                        ForEach($notes) { $note in
                            Toggle(note.title, isOn: $note.isSelected)
                            .frame(minHeight: ScholiumGrid.Dimension.researchFunctionTargetHeight)
                            .accessibilityIdentifier("scholium.proofs.request.note.\(note.id)")
                            ScholiumStructuralRule()
                        }
                    }
                }

                ResearchProofNotice(
                    title: "Revalidated Before Decision",
                    detail: "Note identity, role, operation, current revision, and Triptych collaboration policy remain current.",
                    systemImage: "checkmark.circle",
                    colorRole: .confirmed
                )

                ViewThatFits(in: .horizontal) {
                    HStack {
                        Spacer()
                        writeSetExtensionButtons
                    }
                    VStack(alignment: .trailing) {
                        writeSetExtensionButtons
                    }
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("scholium.proofs.writeSetExtension")
    }

    private var writeSetExtensionButtons: some View {
        Group {
            Button("Cancel Request", role: .destructive) {}
            Button("Continue Without Changes") {}
            Button("Allow Selected Notes") {}
                .keyboardShortcut(.defaultAction)
                .disabled(!notes.contains(where: \.isSelected))
        }
    }
}

private struct ResearchProofSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text(title)
                .scholiumApparatusHeadingStyle()
                .accessibilityAddTraits(.isHeader)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ResearchProofNotice: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let systemImage: String
    let colorRole: ScholiumColorRole

    var body: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: ScholiumGrid.Spacing.inlineControlGap
        ) {
            Image(systemName: systemImage)
                .foregroundStyle(colorRole.color)
                .accessibilityHidden(true)
            VStack(
                alignment: .leading,
                spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment
            ) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Modular Skill-run Sheet") {
    ResearchWorkflowProofDetail(proof: .actionSheet)
        .frame(width: 760, height: 720)
}

#Preview("Research Guidance") {
    ResearchWorkflowProofDetail(proof: .researchGuidance)
        .frame(width: 900, height: 720)
}

#Preview("Bounded Write Set") {
    ResearchWorkflowProofDetail(proof: .writeSetExtension)
        .frame(width: 760, height: 720)
}

#Preview("Workflow Dark") {
    ResearchWorkflowPreviewCatalog()
        .preferredColorScheme(.dark)
}

#Preview("Workflow Increased Contrast") {
    ResearchWorkflowPreviewCatalog()
        .environment(
            \.scholiumVisualEnvironmentOverride,
            .init(increasedContrast: true)
        )
}

#Preview("Workflow Reduced Transparency") {
    ResearchWorkflowPreviewCatalog()
        .environment(
            \.scholiumVisualEnvironmentOverride,
            .init(reduceTransparency: true)
        )
}

#Preview("Workflow Reduced Motion") {
    ResearchWorkflowPreviewCatalog()
        .environment(
            \.scholiumVisualEnvironmentOverride,
            .init(reduceMotion: true)
        )
}

#Preview("Workflow 200% Legibility") {
    ResearchWorkflowProofDetail(proof: .writeSetExtension)
        .dynamicTypeSize(.accessibility2)
        .frame(width: 900, height: 760)
}
#endif
