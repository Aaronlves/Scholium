#if DEBUG
import ScholiumContracts
import SwiftUI

/// Deterministic, development-only interface proofs for D-106. These views
/// render synthetic values and deliberately own no vault, Skill, permission,
/// execution, or Research Record authority.
struct ResearchWorkflowPreviewCatalog: View {
    @State private var selection: ResearchWorkflowProof = .actions

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
    case actions
    case actionSheet
    case skillInstaller
    case skillSettings
    case changeRequest
    case researchRecord
    case stateMatrix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .actions: "Actions"
        case .actionSheet: "Skill-run Sheet"
        case .skillInstaller: "Skill Installer"
        case .skillSettings: "Skill Settings"
        case .changeRequest: "Agent Change Request"
        case .researchRecord: "Research Record"
        case .stateMatrix: "State Matrix"
        }
    }

    var systemImage: String {
        switch self {
        case .actions: "bolt"
        case .actionSheet: "list.bullet.rectangle"
        case .skillInstaller: "square.and.arrow.down"
        case .skillSettings: "slider.horizontal.3"
        case .changeRequest: "doc.badge.ellipsis"
        case .researchRecord: "books.vertical"
        case .stateMatrix: "rectangle.grid.2x2"
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
        case .actions:
            ResearchActionsProof()
        case .actionSheet:
            ResearchActionSheetProof()
        case .skillInstaller:
            ResearchSkillInstallerProof()
        case .skillSettings:
            ResearchSkillSettingsProof()
        case .changeRequest:
            AgentChangeRequestProof()
        case .researchRecord:
            ResearchRecordResponsiveProof()
        case .stateMatrix:
            ResearchWorkflowStateMatrixProof()
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

// MARK: - Actions

private enum ResearchActionsProofRole: String, CaseIterable, Hashable, Identifiable {
    case analysis = "Analysis"
    case topic = "Topic"
    case work = "Work"

    var id: String { rawValue }

    var actions: [ResearchActionProofItem] {
        switch self {
        case .analysis:
            [
                .init(id: "discuss", title: "Discuss", detail: "Continue a passage or whole-note discussion.", symbol: "bubble.left.and.bubble.right"),
                .init(id: "analyze", title: "Analyze", detail: "Analyze or reanalyze the explicitly bound source.", symbol: "doc.text.magnifyingglass"),
                .init(id: "fidelity", title: "Check Fidelity", detail: "Check without modifying Markdown.", symbol: "checkmark.seal"),
            ]
        case .topic:
            [
                .init(id: "discuss", title: "Discuss", detail: "Continue a passage, note, or multi-note discussion.", symbol: "bubble.left.and.bubble.right"),
                .init(id: "synthesize", title: "Synthesize", detail: "Integrate warranted analyses and sources into this Topic.", symbol: "arrow.triangle.merge"),
                .init(id: "fidelity", title: "Check Fidelity", detail: "Check without modifying Markdown.", symbol: "checkmark.seal"),
            ]
        case .work:
            [
                .init(id: "discuss", title: "Discuss", detail: "Discuss without changing this Work.", symbol: "bubble.left.and.bubble.right"),
                .init(id: "write", title: "Write", detail: "Make an explicitly bounded change to this Work.", symbol: "square.and.pencil"),
                .init(id: "critique", title: "Critique", detail: "Return criticism before any separately authorized Write phase.", symbol: "text.magnifyingglass"),
                .init(id: "fidelity", title: "Check Fidelity", detail: "Check without modifying Markdown.", symbol: "checkmark.seal"),
            ]
        }
    }
}

private struct ResearchActionProofItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
}

private struct ResearcherSkillProofFixture: Identifiable {
    let id: String
    let name: String
    let revision: Int
    let symbol: String
    let isEnabled: Bool
    let showsInActions: Bool
    let applicableRoles: Set<ResearchActionsProofRole>
    let readableRoles: Set<ResearchActionsProofRole>
    let candidateWriteScope: String
    let requiredAuthorization: String

    var applicableRoleDescription: String {
        roleDescription(for: applicableRoles)
    }

    var readableRoleDescription: String {
        roleDescription(for: readableRoles)
    }

    var actionItem: ResearchActionProofItem {
        ResearchActionProofItem(
            id: id,
            title: name,
            detail: "Researcher Skill revision \(revision)",
            symbol: symbol
        )
    }

    var settingsStatus: String {
        if !isEnabled { return "disabled" }
        return showsInActions ? "enabled" : "enabled and hidden"
    }

    var settingsDescription: String {
        "\(name), revision \(revision), \(settingsStatus)"
    }

    private func roleDescription(for roles: Set<ResearchActionsProofRole>) -> String {
        ResearchActionsProofRole.allCases
            .filter(roles.contains)
            .map(\.rawValue)
            .joined(separator: ", ")
    }
}

private let counterexampleStressTestFixture = ResearcherSkillProofFixture(
    id: "counterexample-stress-test",
    name: "Counterexample Stress Test",
    revision: 4,
    symbol: "scope",
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
    symbol: "arrow.left.arrow.right",
    isEnabled: false,
    showsInActions: false,
    applicableRoles: [.analysis, .topic],
    readableRoles: [.analysis, .topic],
    candidateWriteScope: "None",
    requiredAuthorization: "No Markdown write"
)

private let researcherSkillProofFixtures = [
    counterexampleStressTestFixture,
    compareInterpretationsFixture,
]

private struct ResearchActionsProof: View {
    @State private var role: ResearchActionsProofRole = .analysis

    private var visibleResearcherSkills: [ResearcherSkillProofFixture] {
        researcherSkillProofFixtures.filter {
            $0.isEnabled && $0.showsInActions && $0.applicableRoles.contains(role)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                Picker("Note role", selection: $role) {
                    ForEach(ResearchActionsProofRole.allCases) { role in
                        Text(role.rawValue).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("scholium.proofs.actions.role")

                ResearchProofSection(title: "DEFAULT ACTIONS") {
                    VStack(spacing: 0) {
                        ForEach(role.actions) { action in
                            ResearchActionProofRow(action: action)
                            if action.id != role.actions.last?.id {
                                ScholiumStructuralRule()
                            }
                        }
                    }
                }

                ResearchProofSection(title: "RESEARCHER SKILLS") {
                    if visibleResearcherSkills.isEmpty {
                        Text("No Researcher Skills for this Note role.")
                            .font(ScholiumInterfaceTypography.apparatusResearchContent)
                            .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(visibleResearcherSkills) { skill in
                                ResearchActionProofRow(action: skill.actionItem)
                                if skill.id != visibleResearcherSkills.last?.id {
                                    ScholiumStructuralRule()
                                }
                            }
                        }
                    }
                }

                Text("Connect remains a separate Inspector area. Research Record remains an independent window.")
                    .font(ScholiumInterfaceTypography.apparatusResearchContent)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

private struct ResearchActionProofRow: View {
    let action: ResearchActionProofItem

    var body: some View {
        Button(action: {}) {
            HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Image(systemName: action.symbol)
                    .frame(width: ScholiumGrid.Dimension.iconTrackWidth)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Text(action.title)
                        .font(ScholiumInterfaceTypography.apparatusActionTitle)
                    Text(action.detail)
                        .font(ScholiumInterfaceTypography.apparatusResearchContent)
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                Image(systemName: "chevron.forward")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ScholiumColorRole.mutedText.color)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
            .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            .frame(maxWidth: .infinity, minHeight: ScholiumGrid.Dimension.researchFunctionTargetHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .accessibilityHint(action.detail)
        .accessibilityIdentifier("scholium.proofs.action.\(action.id)")
    }
}

// MARK: - Generic modular Skill-run sheet

private struct ResearchActionSheetProof: View {
    @State private var selectedMaterial = "Attention and Salience.md"
    @State private var preservesAlternatives = true
    @State private var emphasis = "Dialectical structure"
    @State private var instruction = "Reconstruct the strongest objection before replying."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                ResearchSheetIdentity(
                    action: "Analyze",
                    skill: "Analyze Source, working revision 3",
                    target: "Attention and Salience.md",
                    revision: "f4d77c2a"
                )
                ScholiumStructuralRule()

                ResearchProofSection(title: "SKILL PARAMETERS") {
                    Grid(alignment: .leading, horizontalSpacing: ScholiumGrid.Spacing.sectionSeparation, verticalSpacing: ScholiumGrid.Spacing.nestedContentInset) {
                        GridRow {
                            Text("Source")
                            Button("Nagel, What Is It Like to Be a Bat?.pdf") {}
                                .accessibilityIdentifier("scholium.proofs.run.source")
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
                        GridRow {
                            Text("Emphasis")
                            Picker("Emphasis", selection: $emphasis) {
                                Text("Dialectical structure").tag("Dialectical structure")
                                Text("Conceptual distinctions").tag("Conceptual distinctions")
                            }
                            .labelsHidden()
                        }
                        GridRow {
                            Text("Instruction")
                            TextField(
                                "Optional bounded instruction",
                                text: $instruction,
                                axis: .vertical
                            )
                                .lineLimit(2...4)
                        }
                    }
                    .font(ScholiumInterfaceTypography.apparatusBody)
                    Toggle("Preserve competing interpretations", isOn: $preservesAlternatives)
                        .padding(.top, ScholiumGrid.Spacing.inlineControlGap)
                }

                ScholiumStructuralRule()
                ResearchAuthorityFacts()
                ResearchSheetButtons(primary: "Begin Analyze")
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("scholium.proofs.runSheet")
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
    var body: some View {
        ResearchProofSection(title: "APP-OWNED BOUNDARY") {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                LabeledContent("Permission", value: "Ask Me Every Time")
                LabeledContent("Candidate write scope", value: "Current Analysis only")
                LabeledContent("Checkpoint", value: "Before Agent Work")
                LabeledContent("Conflicts", value: "Revalidated before write")
                LabeledContent("Recovery", value: "Checkpoint and retained prewrite evidence")
                Text("The Skill can declare requirements, but it cannot hide or expand these fields.")
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(ScholiumInterfaceTypography.apparatusResearchContent)
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

                ScholiumInlineStatus(
                    "Installed Skills Start Disabled",
                    detail: "Review the working Skill and its permissions before enabling its Action.",
                    kind: .attention
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
                "Permission and checkpoint",
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
                "Reveal Legacy Data",
                "Checkpoint location",
                "Rebuild derived search index",
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

                ScholiumInlineStatus(
                    "Revalidated Before Decision",
                    detail: "Note identity, revision, Skill revision, Profile, and standing policy remain current.",
                    kind: .confirmed
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

private struct ResearchRecordResponsiveProof: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Independent Triptych Window")
                    .font(ScholiumInterfaceTypography.metadata)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                Spacer()
                Text("Adapts to window width")
                    .font(ScholiumInterfaceTypography.metadata)
                    .foregroundStyle(ScholiumColorRole.mutedText.color)
            }
            .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
            .frame(minHeight: ScholiumGrid.Dimension.regionHeaderHeight)
            ScholiumStructuralRule()

            GeometryReader { geometry in
                Group {
                    if geometry.size.width >= 700 {
                        ResearchRecordTwoColumnProof()
                            .accessibilityIdentifier("scholium.proofs.record.twoColumn")
                    } else {
                        ResearchRecordStackedProof()
                            .accessibilityIdentifier("scholium.proofs.record.stacked")
                    }
                }
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: .topLeading
                )
            }
        }
    }
}

private struct ResearchRecordTwoColumnProof: View {
    var body: some View {
        HStack(spacing: 0) {
            ResearchRecordListProof()
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
            ScholiumStructuralRule(orientation: .vertical)
            ResearchRecordReadingProof()
                .frame(minWidth: 380, maxWidth: .infinity)
        }
    }
}

private struct ResearchRecordStackedProof: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back to Records", systemImage: "chevron.backward") {}
                Spacer()
                Text("This Note")
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
            .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
            .frame(minHeight: ScholiumGrid.Dimension.regionHeaderHeight)
            ScholiumStructuralRule()
            ResearchRecordReadingProof()
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
            VStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
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
            .padding(ScholiumGrid.Spacing.nestedContentInset)
            ScholiumStructuralRule()
            List(researchRecordEntries, selection: $selection) { entry in
                ResearchRecordListRow(entry: entry)
                    .tag(entry.id)
            }
            .listStyle(.sidebar)
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
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title)
                    .font(ScholiumInterfaceTypography.rowTitle)
                    .lineLimit(2)
                Spacer(minLength: ScholiumGrid.Spacing.labelAccessoryGap)
                if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                        .accessibilityLabel("Pinned")
                }
            }
            HStack {
                Text(entry.date)
                Spacer()
                Text(entry.action)
            }
            .font(ScholiumInterfaceTypography.metadata)
            .foregroundStyle(ScholiumColorRole.secondaryText.color)
            Text(entry.skill)
                .font(ScholiumInterfaceTypography.metadata)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
            Text(entry.participants)
                .font(ScholiumInterfaceTypography.metadata)
                .foregroundStyle(ScholiumColorRole.mutedText.color)
        }
        .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
    }
}

private struct ResearchRecordReadingProof: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                Text("Whether salience supplies a reason")
                    .font(ScholiumInterfaceTypography.documentTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("Discussion, 25 July 2026")
                    .font(ScholiumInterfaceTypography.metadata)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)

                ResearchRecordTurn(
                    speaker: "Researcher",
                    context: "Comment on Attention and Salience.md, paragraphs 8–10",
                    prose: "The present distinction seems too quick. If salience changes the practical option-space, why is that not already a reason-giving role?"
                )
                ScholiumStructuralRule()
                ResearchRecordTurn(
                    speaker: "Agent",
                    context: "Response",
                    prose: "One possibility is to distinguish making an option available for deliberation from counting in favor of it. The current note states that distinction, but does not yet defend it against cases where availability itself is normatively structured."
                )
                ScholiumStructuralRule()
                ResearchRecordTurn(
                    speaker: "Agent Feedback",
                    context: "Bounded report",
                    prose: "I used the focal passage and the selected Analysis. I did not establish that the distinction survives the strongest constitutivist reply. I recommend preserving this exchange as an unresolved pressure point."
                )
                ScholiumStructuralRule()
                ResearchRecordTurn(
                    speaker: "Researcher",
                    context: "Reply",
                    prose: "Reanalyze the source distinction before recommending any change to the Topic."
                )

                DisclosureGroup("Record Details") {
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        LabeledContent("Action", value: "Discuss")
                        LabeledContent("Starting revision", value: "f4d77c2a")
                        LabeledContent("Result", value: "No Markdown write")
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

// MARK: - Deterministic state matrix

private enum ResearchWorkflowProofState: String, CaseIterable, Identifiable {
    case empty = "Empty"
    case loading = "Loading"
    case error = "Error"
    case conflict = "Conflict"
    case permissionInvalid = "Permission Invalid"

    var id: String { rawValue }
}

private struct ResearchWorkflowStateMatrixProof: View {
    @State private var state: ResearchWorkflowProofState = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
            Picker("State", selection: $state) {
                ForEach(ResearchWorkflowProofState.allCases) { state in
                    Text(state.rawValue).tag(state)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("scholium.proofs.states.picker")
            ResearchWorkflowStateProof(state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
    }
}

private struct ResearchWorkflowStateProof: View {
    let state: ResearchWorkflowProofState

    var body: some View {
        VStack(spacing: ScholiumGrid.Spacing.nestedContentInset) {
            stateContent
        }
        .frame(maxWidth: 620, minHeight: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var stateContent: some View {
        switch state {
        case .empty:
            ScholiumEmptyState(
                title: "No Researcher Skills",
                detail: "Install a local Skill or continue with the working methods for this Triptych.",
                systemImage: "square.and.arrow.down"
            )
        case .loading:
            ProgressView("Validating Skill files and declared capabilities…")
        case .error:
            ScholiumInlineStatus(
                "Skill Could Not Be Loaded",
                detail: "The current working Skill remains unchanged. Review the validation report or choose another directory.",
                kind: .destructive
            )
            Button("Review Validation Report") {}
        case .conflict:
            ScholiumInlineStatus(
                "Target Changed on Disk",
                detail: "The prepared run has not written anything. Reopen the Note and prepare again from its current revision.",
                kind: .attention
            )
            Button("Reopen Current Revision") {}
        case .permissionInvalid:
            ScholiumInlineStatus(
                "Permission Needs Review",
                detail: "The Skill or Profile changed after approval. No previous approval can authorize this run.",
                kind: .attention
            )
            Button("Review Permissions") {}
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

#Preview("Research Actions") {
    ResearchWorkflowProofDetail(proof: .actions)
        .frame(width: 760, height: 720)
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

#Preview("Research Record Two-column") {
    ResearchWorkflowProofDetail(proof: .researchRecord)
        .frame(width: 960, height: 720)
}

#Preview("Research Record Narrow") {
    ResearchRecordStackedProof()
        .frame(width: 520, height: 680)
}

#Preview("Workflow States") {
    ResearchWorkflowProofDetail(proof: .stateMatrix)
        .frame(width: 760, height: 640)
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
