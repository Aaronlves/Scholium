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
    case skillInstaller
    case skillSettings
    case changeRequest
    case researchRecord

    var id: String { rawValue }

    var title: String {
        switch self {
        case .actionSheet: "Skill-run Sheet"
        case .skillInstaller: "Skill Installer"
        case .skillSettings: "Skill Settings"
        case .changeRequest: "Agent Change Request"
        case .researchRecord: "Research Record"
        }
    }

    var systemImage: String {
        switch self {
        case .actionSheet: "list.bullet.rectangle"
        case .skillInstaller: "square.and.arrow.down"
        case .skillSettings: "slider.horizontal.3"
        case .changeRequest: "doc.badge.ellipsis"
        case .researchRecord: "books.vertical"
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
        case .skillInstaller:
            ResearchSkillInstallerProof()
        case .skillSettings:
            ResearchSkillSettingsProof()
        case .changeRequest:
            AgentChangeRequestProof()
        case .researchRecord:
            ResearchRecordUtilityProof()
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

// MARK: - Researcher Skill fixtures

private enum ResearchProofRole: String, CaseIterable, Hashable {
    case analysis = "Analysis"
    case topic = "Topic"
    case work = "Work"
}

private struct ResearcherSkillProofFixture: Identifiable {
    let id: String
    let name: String
    let revision: Int
    let isEnabled: Bool
    let showsInActions: Bool
    let applicableRoles: Set<ResearchProofRole>
    let readableRoles: Set<ResearchProofRole>
    let candidateWriteScope: String
    let requiredAuthorization: String

    var applicableRoleDescription: String {
        roleDescription(for: applicableRoles)
    }

    var readableRoleDescription: String {
        roleDescription(for: readableRoles)
    }

    var settingsStatus: String {
        if !isEnabled { return "disabled" }
        return showsInActions ? "enabled" : "enabled and hidden"
    }

    var settingsDescription: String {
        "\(name), revision \(revision), \(settingsStatus)"
    }

    private func roleDescription(for roles: Set<ResearchProofRole>) -> String {
        ResearchProofRole.allCases
            .filter(roles.contains)
            .map(\.rawValue)
            .joined(separator: ", ")
    }
}

private let counterexampleStressTestFixture = ResearcherSkillProofFixture(
    id: "counterexample-stress-test",
    name: "Counterexample Stress Test",
    revision: 4,
    isEnabled: true,
    showsInActions: true,
    applicableRoles: [.topic, .work],
    readableRoles: [.analysis, .topic, .work],
    candidateWriteScope: "None",
    requiredAuthorization: "No Markdown write"
)

private let compareInterpretationsFixture = ResearcherSkillProofFixture(
    id: "compare-interpretations",
    name: "Compare Interpretations",
    revision: 2,
    isEnabled: false,
    showsInActions: false,
    applicableRoles: [.analysis, .topic],
    readableRoles: [.analysis, .topic],
    candidateWriteScope: "None",
    requiredAuthorization: "No Markdown write"
)

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
                LabeledContent("Permission", value: "Ask Me Every Time")
                LabeledContent("Candidate write scope", value: action.candidateWriteScope)
                LabeledContent(
                    "Recovery",
                    value: action.candidateWriteScope.hasPrefix("None")
                        ? "No Target write"
                        : "Exact written Notes"
                )
                LabeledContent("Conflicts", value: "Revalidated before write")
                LabeledContent("Conflict recovery", value: "Retained displaced bytes")
                Text("The Skill can declare requirements, but it cannot hide or expand these fields.")
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
            Button("Copy Only") {}
            Button("Open in Codex") {}
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

// MARK: - Skill installation and settings

private struct ResearchSkillInstallerProof: View {
    @State private var triptychSelected = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                Text("Install Researcher Skill")
                    .font(ScholiumInterfaceTypography.documentTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("Review this local directory before Scholium creates a disabled, Triptych-local snapshot.")
                    .font(ScholiumInterfaceTypography.apparatusResearchContent)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)

                ResearchProofSection(title: "SOURCE") {
                    LabeledContent("Directory", value: counterexampleStressTestFixture.name)
                    LabeledContent("Origin", value: "Local directory chosen by researcher")
                }
                ResearchProofSection(title: "ACCEPTED FILES") {
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        Label("SKILL.md", systemImage: "doc.plaintext")
                        Label("references/evaluation-questions.md", systemImage: "doc.plaintext")
                        Label("evals/strong-objection.md", systemImage: "doc.plaintext")
                    }
                }
                ResearchProofSection(title: "DECLARED USE") {
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        LabeledContent(
                            "Note roles",
                            value: counterexampleStressTestFixture.applicableRoleDescription
                        )
                        LabeledContent("Action placement", value: "Researcher Skills")
                        LabeledContent(
                            "Capabilities",
                            value: "Read \(counterexampleStressTestFixture.readableRoleDescription) focal Notes; return feedback"
                        )
                        LabeledContent(
                            "Requested writes",
                            value: counterexampleStressTestFixture.candidateWriteScope
                        )
                    }
                }
                ResearchProofSection(title: "INSTALL TO") {
                    Toggle("Immediate Results Triptych", isOn: $triptychSelected)
                    Text("Each selected Triptych receives an independent snapshot. Installation does not create hidden synchronization.")
                        .font(ScholiumInterfaceTypography.apparatusResearchContent)
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ResearchProofNotice(
                    title: "Installed Skills Start Disabled",
                    detail: "Review the working Skill and its permissions before enabling its Action.",
                    systemImage: "exclamationmark.triangle",
                    colorRole: .attention
                )
                ResearchSheetButtons(primary: "Install Disabled")
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("scholium.proofs.installer")
    }
}

private enum ResearchGuidanceProofCategory: String, CaseIterable, Identifiable {
    case methods = "Methods"
    case researcherSkills = "Researcher Skills"
    case permissions = "Permissions"
    case sources = "Sources & Integrations"
    case recovery = "Recovery & Technical"

    var id: String { rawValue }
}

private struct ResearchSkillSettingsProof: View {
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
                ResearchSkillSettingsDetail(category: category)
                    .padding(ScholiumGrid.Spacing.regionContentInset)
                    .frame(maxWidth: 680, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .scholiumSurface(.document)
        }
    }
}

private struct ResearchSkillSettingsDetail: View {
    let category: ResearchGuidanceProofCategory
    @State private var buttonName = counterexampleStressTestFixture.name
    @State private var selectedTriptych = "Dissertation"
    @State private var appliesToAnalysis = counterexampleStressTestFixture.applicableRoles
        .contains(.analysis)
    @State private var appliesToTopic = counterexampleStressTestFixture.applicableRoles
        .contains(.topic)
    @State private var appliesToWork = counterexampleStressTestFixture.applicableRoles
        .contains(.work)
    @State private var showsInActions = counterexampleStressTestFixture.showsInActions
    @State private var actionOrder = 4
    @State private var standingPolicy = "Inherit Triptych Policy"

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
            ResearchProofSection(title: "WORKING METHOD SKILLS") {
                Text("Editable for this Triptych. A working method may be changed, disabled, replaced, or restored from its bundled reference.")
                    .font(ScholiumInterfaceTypography.apparatusResearchContent)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach([
                        ("Discuss", "Enabled"),
                        ("Analyze", "Enabled"),
                        ("Synthesize", "Enabled"),
                        ("Write", "Enabled"),
                        ("Critique", "Enabled"),
                        ("Content Fidelity", "Enabled"),
                        ("Manuscript", "Disabled and hidden"),
                    ], id: \.0) { name, status in
                        ResearchWorkingMethodProofRow(name: name, status: status)
                        ScholiumStructuralRule()
                    }
                }
            }
            ResearchSkillGroup(title: "SYSTEM SKILLS", detail: "Read-only application mechanisms", rows: [
                "Identity and revision",
                "Permission and recovery",
                "Conflict and completion validation",
            ], actionTitle: nil)
            ResearchSkillGroup(title: "BUNDLED REFERENCES", detail: "Compare, restore, or reinstall explicitly", rows: [
                "Scholium Analyze reference",
                "Scholium Synthesize reference",
            ], actionTitle: "Compare")
        case .researcherSkills:
            ResearchSkillGroup(title: "INSTALLED", detail: "Local, editable, and versioned", rows: [
                counterexampleStressTestFixture.settingsDescription,
                compareInterpretationsFixture.settingsDescription,
            ])
            ResearchProofSection(title: "APPLICABILITY") {
                Picker("Triptych", selection: $selectedTriptych) {
                    Text("Dissertation").tag("Dissertation")
                    Text("Article Project").tag("Article Project")
                }
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Text("Note roles")
                        .font(ScholiumInterfaceTypography.apparatusBody)
                    Toggle("Analysis", isOn: $appliesToAnalysis)
                    Toggle("Topic", isOn: $appliesToTopic)
                    Toggle("Work", isOn: $appliesToWork)
                }
            }
            ResearchProofSection(title: "ACTION PLACEMENT") {
                TextField("Button name", text: $buttonName)
                Toggle("Show in Actions", isOn: $showsInActions)
                Stepper("Order in Actions: \(actionOrder)", value: $actionOrder, in: 1 ... 12)
            }
            ResearchProofSection(title: "PROFILE MODULES") {
                ResearchSettingsValueRow(label: "Passage anchor", value: "Optional")
                ResearchSettingsValueRow(label: "Material selector", value: "Required")
                ResearchSettingsValueRow(label: "Bounded instruction", value: "1,200 characters")
                Button("Add Declarative Module…") {}
            }
            ResearchProofSection(title: "DECLARED PERMISSIONS") {
                ResearchSettingsValueRow(
                    label: "Readable roles",
                    value: counterexampleStressTestFixture.readableRoleDescription
                )
                ResearchSettingsValueRow(
                    label: "Candidate write scope",
                    value: counterexampleStressTestFixture.candidateWriteScope
                )
                ResearchSettingsValueRow(
                    label: "Required authorization",
                    value: counterexampleStressTestFixture.requiredAuthorization
                )
            }
            Button("Install from Local Directory…") {}
        case .permissions:
            ResearchSkillGroup(title: "TRIPTYCH POLICY", detail: "Ask Me Every Time", rows: [
                "Discuss inherits Triptych policy",
                "Write asks only for new Notes or an expanded phase",
            ], actionTitle: nil)
            ResearchProofSection(title: "SKILL OVERRIDE") {
                Picker("Standing policy", selection: $standingPolicy) {
                    Text("Inherit Triptych Policy").tag("Inherit Triptych Policy")
                    Text("Ask Me Every Time").tag("Ask Me Every Time")
                    Text("Ask Me Only for Works").tag("Ask Me Only for Works")
                    Text("Triptych-wide").tag("Triptych-wide")
                }
                Text("A Skill declares what it needs. This separate standing policy only decides when Scholium asks the researcher.")
                    .font(ScholiumInterfaceTypography.apparatusResearchContent)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .sources:
            ResearchSkillGroup(title: "ANALYZE SOURCES", detail: "Explicit source identity", rows: [
                "Zotero local attachment route",
                "Researcher-selected local file route",
            ], actionTitle: nil)
        case .recovery:
            ResearchSkillGroup(title: "RECOVERY", detail: "Machine-local operational state", rows: [
                "Reveal Skills Folder",
                "Settled version policy",
                "Skill recovery snapshots",
            ], actionTitle: nil)
        }
    }
}

private struct ResearchWorkingMethodProofRow: View {
    let name: String
    let status: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text(name)
                Text(status)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
            Spacer()
            Menu("Manage") {
                Button("Edit Method") {}
                Button(status == "Enabled" ? "Disable" : "Enable") {}
                Button("Replace…") {}
                Divider()
                Button("Restore Bundled Reference") {}
            }
            .menuStyle(.borderlessButton)
        }
        .font(ScholiumInterfaceTypography.apparatusBody)
        .frame(minHeight: ScholiumGrid.Dimension.researchFunctionTargetHeight)
    }
}

private struct ResearchSettingsValueRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label, value: value)
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

// MARK: - Agent change request

private struct AgentChangeRequestNote: Identifiable {
    let id: String
    let title: String
    var isSelected: Bool
}

private struct AgentChangeRequestProof: View {
    @State private var notes = [
        AgentChangeRequestNote(id: "topic-attention", title: "Topic: Attention", isSelected: true),
        AgentChangeRequestNote(id: "topic-normative-reasons", title: "Topic: Normative Reasons", isSelected: false),
        AgentChangeRequestNote(id: "work-chapter-three", title: "Work: Chapter Three", isSelected: true),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                Text("The Agent Wants to Change Additional Notes")
                    .font(ScholiumInterfaceTypography.documentTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("The current Analyze run remains frozen. An allowed selection would begin a separate authorized phase.")
                    .font(ScholiumInterfaceTypography.apparatusResearchContent)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)

                ResearchProofSection(title: "REQUEST") {
                    LabeledContent("Parent run", value: "Analyze Attention and Salience")
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
                    detail: "Note identity, revision, Skill revision, Profile, and standing policy remain current.",
                    systemImage: "checkmark.circle",
                    colorRole: .confirmed
                )

                ViewThatFits(in: .horizontal) {
                    HStack {
                        Spacer()
                        changeRequestButtons
                    }
                    VStack(alignment: .trailing) {
                        changeRequestButtons
                    }
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("scholium.proofs.changeRequest")
    }

    private var changeRequestButtons: some View {
        Group {
            Button("Cancel the Run", role: .destructive) {}
            Button("Continue Without Changes") {}
            Button("Allow These Notes Once") {}
                .keyboardShortcut(.defaultAction)
                .disabled(!notes.contains(where: \.isSelected))
        }
    }
}

// MARK: - Research Record

private struct ResearchRecordEntry: Identifiable {
    let id: String
    let title: String
    let date: String
    let skill: String
    let action: String
    let participants: String
    let isPinned: Bool
}

private let researchRecordEntries = [
    ResearchRecordEntry(
        id: "objection",
        title: "Whether salience supplies a reason",
        date: "25 Jul 2026, 14:32",
        skill: "Discuss, revision 2",
        action: "Discuss",
        participants: "Researcher, Agent",
        isPinned: true
    ),
    ResearchRecordEntry(
        id: "source",
        title: "Analyze What Is It Like to Be a Bat?",
        date: "24 Jul 2026, 18:05",
        skill: "Analyze Source, revision 3",
        action: "Analyze",
        participants: "Agent",
        isPinned: false
    ),
    ResearchRecordEntry(
        id: "synthesis",
        title: "Synthesize attention into normative reasons",
        date: "23 Jul 2026, 10:18",
        skill: "Synthesize, revision 4",
        action: "Synthesize",
        participants: "Researcher, Agent",
        isPinned: false
    ),
]

private struct ResearchRecordUtilityProof: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Independent Triptych Window")
                    .font(ScholiumInterfaceTypography.metadata)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                Spacer()
                Text("Fixed 760 × 680 utility window")
                    .font(ScholiumInterfaceTypography.metadata)
                    .foregroundStyle(ScholiumColorRole.mutedText.color)
            }
            .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
            .frame(minHeight: ScholiumGrid.Dimension.regionHeaderHeight)
            ScholiumStructuralRule()

            ResearchRecordTwoColumnProof()
                .accessibilityIdentifier("scholium.proofs.record.fixedUtility")
        }
    }
}

private struct ResearchRecordTwoColumnProof: View {
    var body: some View {
        HStack(spacing: 0) {
            ResearchRecordListProof()
                .frame(minWidth: 224, idealWidth: 244, maxWidth: 268)
            ScholiumStructuralRule(orientation: .vertical)
            ResearchRecordReadingProof()
                .frame(minWidth: 380, maxWidth: .infinity)
        }
    }
}

private struct ResearchRecordListProof: View {
    @State private var searchText = ""
    @State private var scope = "This Note"
    @State private var selection = "objection"
    @State private var showsFilters = true
    @State private var dateFilter = "Any Date"
    @State private var skillFilter = "Any Skill"
    @State private var actionFilter = "Any Action"
    @State private var participantFilter = "Any Participant"

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                TextField("Search records", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("Scope", selection: $scope) {
                    Text("This Note").tag("This Note")
                    Text("Triptych").tag("Triptych")
                }
                .pickerStyle(.segmented)
                DisclosureGroup("Filters", isExpanded: $showsFilters) {
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                        ResearchRecordFilterPicker(
                            title: "Date",
                            selection: $dateFilter,
                            values: ["Any Date", "Today", "Past Week"]
                        )
                        ResearchRecordFilterPicker(
                            title: "Skill",
                            selection: $skillFilter,
                            values: ["Any Skill", "Discuss", "Analyze Source", "Synthesize"]
                        )
                        ResearchRecordFilterPicker(
                            title: "Action",
                            selection: $actionFilter,
                            values: ["Any Action", "Discuss", "Analyze", "Synthesize"]
                        )
                        ResearchRecordFilterPicker(
                            title: "Participant",
                            selection: $participantFilter,
                            values: ["Any Participant", "Researcher", "Agent"]
                        )
                    }
                    .padding(.top, ScholiumGrid.Spacing.labelAccessoryGap)
                }
            }
            .controlSize(.small)
            .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
            .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            ScholiumStructuralRule()
            List(researchRecordEntries, selection: $selection) { entry in
                ResearchRecordListRow(entry: entry)
                    .tag(entry.id)
                    .listRowInsets(
                        EdgeInsets(
                            top: ScholiumGrid.Spacing.opticalAlignmentAdjustment,
                            leading: ScholiumGrid.Spacing.inlineControlGap,
                            bottom: ScholiumGrid.Spacing.opticalAlignmentAdjustment,
                            trailing: ScholiumGrid.Spacing.inlineControlGap
                        )
                    )
            }
            .listStyle(.plain)
        }
        .scholiumSurface(.navigation)
    }
}

private struct ResearchRecordFilterPicker: View {
    let title: String
    @Binding var selection: String
    let values: [String]

    var body: some View {
        LabeledContent(title) {
            Picker(title, selection: $selection) {
                ForEach(values, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .font(ScholiumInterfaceTypography.apparatusBody)
    }
}

private struct ResearchRecordListRow: View {
    let entry: ResearchRecordEntry

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment
        ) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(entry.action): \(entry.title)")
                    .font(ScholiumInterfaceTypography.rowTitle)
                    .lineLimit(1)
                Spacer(minLength: ScholiumGrid.Spacing.labelAccessoryGap)
                if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                        .accessibilityLabel("Pinned")
                }
            }
            HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text(entry.date)
                Spacer()
                Text(entry.skill)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(ScholiumInterfaceTypography.metadata)
            .foregroundStyle(ScholiumColorRole.secondaryText.color)
            Text(entry.participants)
                .font(ScholiumInterfaceTypography.metadata)
                .foregroundStyle(ScholiumColorRole.mutedText.color)
        }
    }
}

private struct ResearchRecordReadingProof: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                Text("Analyze What Is It Like to Be a Bat?")
                    .font(ScholiumInterfaceTypography.documentTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("Analyze, 25 July 2026")
                    .font(ScholiumInterfaceTypography.metadata)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)

                ResearchRecordTurn(
                    speaker: "Agent Feedback",
                    context: "Bounded report",
                    prose: "The source boundary and reconstruction were recorded, but the required final check could not inspect one locator-backed passage. The limitation remains explicit."
                )
                ScholiumStructuralRule()
                Label(
                    "Fidelity could not be completed for this recorded revision.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(ScholiumInterfaceTypography.apparatusBody)

                DisclosureGroup("Record Details") {
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        LabeledContent("Action", value: "Analyze")
                        LabeledContent("Agent-reported Materials used", value: "None")
                        LabeledContent("Starting revision", value: "f4d77c2a")
                    }
                    .font(ScholiumInterfaceTypography.apparatusBody)
                    .padding(.top, ScholiumGrid.Spacing.inlineControlGap)
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scholiumSurface(.document)
    }
}

private struct ResearchRecordTurn: View {
    let speaker: String
    let context: String
    let prose: String

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            HStack(alignment: .firstTextBaseline) {
                Text(speaker)
                    .font(ScholiumInterfaceTypography.sectionTitle)
                Spacer()
                Text(context)
                    .font(ScholiumInterfaceTypography.metadata)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .multilineTextAlignment(.trailing)
            }
            Text(prose)
                .font(ScholiumTypography.swiftUIReadingFont(size: 13, relativeTo: .body))
                .lineSpacing(ScholiumGrid.Spacing.labelAccessoryGap)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
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

#Preview("Skill Installer") {
    ResearchWorkflowProofDetail(proof: .skillInstaller)
        .frame(width: 760, height: 720)
}

#Preview("Skill Settings") {
    ResearchWorkflowProofDetail(proof: .skillSettings)
        .frame(width: 900, height: 720)
}

#Preview("Agent Change Request") {
    ResearchWorkflowProofDetail(proof: .changeRequest)
        .frame(width: 760, height: 720)
}

#Preview("Research Record Fixed Utility") {
    ResearchWorkflowProofDetail(proof: .researchRecord)
        .frame(width: 760, height: 680)
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
    ResearchWorkflowProofDetail(proof: .changeRequest)
        .dynamicTypeSize(.accessibility2)
        .frame(width: 900, height: 760)
}
#endif
