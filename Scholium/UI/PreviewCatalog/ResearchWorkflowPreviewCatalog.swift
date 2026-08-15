#if DEBUG
import ScholiumContracts
import ScholiumResearchRecordsFeature
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
    case resultReview
    case researchGuidance
    case writeSetExtension

    var id: String { rawValue }

    var title: String {
        switch self {
        case .actionSheet: "Skill-run Sheet"
        case .resultReview: "Agent Result Review"
        case .researchGuidance: "Research Guidance"
        case .writeSetExtension: "Bounded Write Set"
        }
    }

    var systemImage: String {
        switch self {
        case .actionSheet: "list.bullet.rectangle"
        case .resultReview: "checkmark.message"
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
        case .resultReview:
            ResearchResultReviewProof()
        case .researchGuidance:
            ResearchGuidanceSettingsProof()
        case .writeSetExtension:
            ResearchWriteSetExtensionProof()
        }
    }
}

// MARK: - Agent result review

private struct ResearchResultReviewProof: View {
    private let fixture: ResearchResultReviewProofFixture
    private let model: ResearchRecordBrowserModel

    init() {
        let fixture = try! ResearchResultReviewProofFixture()
        let model = ResearchRecordBrowserModel()
        model.prepareForOpen(
            triptychID: fixture.record.triptychID,
            records: [fixture.record],
            request: ResearchRecordsWindowRequest(
                triptychID: fixture.record.triptychID,
                purpose: .reviewResult,
                recordID: fixture.record.id,
                expectedFinalizedResultFingerprint: fixture.resultFingerprint
            )
        )
        self.fixture = fixture
        self.model = model
    }

    var body: some View {
        ResearchRecordBrowserView(
            model: model,
            loadIssues: [],
            context: ResearchRecordBrowserContext(
                setRecommendationDisposition: { _, _, _ in fixture.record },
                setRecommendationNote: { _, _, _ in fixture.record },
                saveResponse: { _, _, _, _, _ in fixture.record },
                reloadRecord: { _ in fixture.record },
                changeState: { _ in fixture.changeState },
                comparison: { _, noteID in
                    guard let comparison = fixture.comparisons[noteID] else {
                        throw ExactSourceComparisonError.exactRevisionUnavailable(
                            fixture.resultFingerprint
                        )
                    }
                    return comparison
                },
                undoChanges: { _, noteIDs, _ in
                    ResearchRecordChangesUndoResult(
                        record: fixture.record,
                        documents: noteIDs.map {
                            ResearchRecordChangeUndoDocumentResult(
                                noteID: $0,
                                status: .restored,
                                observedRevision: fixture.startingRevisions[$0]
                            )
                        }
                    )
                },
                startMethodImprovement: { _ in throw CancellationError() },
                deletePermanently: { _ in },
                openNote: { _, _, _ in }
            )
        )
        .accessibilityIdentifier("scholium.proofs.resultReview")
    }
}

private struct ResearchResultReviewProofFixture {
    let record: PortableResearchRecord
    let resultFingerprint: DocumentFingerprint
    let changeState: ResearchRecordChangeState
    let comparisons: [UUID: ExactSourceComparison]
    let startingRevisions: [UUID: DocumentFingerprint]

    init() throws {
        let triptychID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let recordID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let topicID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let workID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        let topicStarting = Data((1...18).map { "Line \($0): inherited context" }.joined(separator: "\n").utf8)
        let topicEnding = Data((1...18).map {
            $0 == 9 ? "Line 9: Agent clarified the normative target" : "Line \($0): inherited context"
        }.joined(separator: "\n").utf8)
        let workStarting = Data("# Practical option-space\n\nExisting objection.\n\nExisting reply.\n".utf8)
        let workEnding = Data("# Practical option-space\n\nExisting objection.\n\nRevised reply with a narrower evidential claim.\n".utf8)

        let topicStartRevision = DocumentFingerprint(data: topicStarting)
        let topicEndRevision = DocumentFingerprint(data: topicEnding)
        let workStartRevision = DocumentFingerprint(data: workStarting)
        let workEndRevision = DocumentFingerprint(data: workEnding)
        let topic = try PortableResearchNoteRevision(
            noteID: topicID,
            note: VaultQualifiedNoteID(
                vaultID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
                relativePath: "Topics/情感适切性与实践理由.md"
            ),
            role: .topic,
            title: "情感适切性与实践理由",
            startingRevision: topicStartRevision,
            endingRevision: topicEndRevision
        )
        let work = try PortableResearchNoteRevision(
            noteID: workID,
            note: VaultQualifiedNoteID(
                vaultID: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
                relativePath: "Works/Practical Option-Space.md"
            ),
            role: .work,
            title: "Practical Option-Space",
            startingRevision: workStartRevision,
            endingRevision: workEndRevision
        )
        let method = try JSONDecoder().decode(
            PortableResearchMethodReference.self,
            from: Data(
                """
                {"registration_key":"10000000-0000-0000-0000-000000000001","display_name":"Argument Reconstruction","practice_names":["Source Fidelity"],"profile_revision":{"sha256":"\(topicStartRevision.sha256)","byteCount":\(topicStartRevision.byteCount)}}
                """.utf8
            )
        )
        let finishedAt = Date(timeIntervalSince1970: 1_800_000_000)
        record = try PortableResearchRecord(
            id: recordID,
            triptychID: triptychID,
            title: ResearchRecordTitle("Clarify fittingness and practical authority"),
            kind: .action,
            action: ResearchActionRecordIdentity(actionID: .synthesize),
            method: method,
            primaryNoteID: topicID,
            participatingNotes: [topic, work],
            statements: [
                try PortableResearchStatement(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    author: .agent,
                    kind: .agentFeedback,
                    attribution: "Agent",
                    text: "The revision separates salience from authority and narrows the objection without treating the cited material as direct support.",
                    createdAt: finishedAt
                )
            ],
            resultDisposition: .completed,
            fidelityCompletion: .notRequired,
            confirmedChanges: [
                try PortableResearchConfirmedChange(
                    noteID: topicID,
                    actor: .agent,
                    startingRevision: topicStartRevision,
                    endingRevision: topicEndRevision
                ),
                try PortableResearchConfirmedChange(
                    noteID: workID,
                    actor: .agent,
                    startingRevision: workStartRevision,
                    endingRevision: workEndRevision
                )
            ],
            startedAt: finishedAt.addingTimeInterval(-420),
            finishedAt: finishedAt
        )
        resultFingerprint = try record.finalizedResultFingerprint()
        changeState = ResearchRecordChangeState(
            recordID: recordID,
            finalizedResultFingerprint: resultFingerprint,
            documents: [
                ResearchRecordChangeCurrentState(
                    noteID: topicID,
                    currentRelativePath: topic.note.relativePath,
                    status: .agentEndingRevision,
                    observedRevision: topicEndRevision
                ),
                ResearchRecordChangeCurrentState(
                    noteID: workID,
                    currentRelativePath: work.note.relativePath,
                    status: .agentEndingRevision,
                    observedRevision: workEndRevision
                )
            ]
        )
        comparisons = [
            topicID: try ExactSourceComparisonBuilder.build(
                startingData: topicStarting,
                endingData: topicEnding,
                startingRevision: topicStartRevision,
                endingRevision: topicEndRevision
            ),
            workID: try ExactSourceComparisonBuilder.build(
                startingData: workStarting,
                endingData: workEnding,
                startingRevision: workStartRevision,
                endingRevision: workEndRevision
            )
        ]
        startingRevisions = [
            topicID: topicStartRevision,
            workID: workStartRevision
        ]
    }
}

private struct ResearchProofHeader: View {
    let title: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text(title)
                .font(ScholiumTypography.scholarly(.sectionTitle))
            Spacer()
            Text("Synthetic data")
                .font(ScholiumTypography.interface(.small, emphasis: .medium))
                .scholiumForeground(.secondaryText)
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
                    .font(ScholiumTypography.interface(.compact))
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
                .font(ScholiumTypography.scholarly(.title))
                .accessibilityAddTraits(.isHeader)
            Text(skill)
                .font(ScholiumTypography.scholarly(.body))
                .scholiumForeground(.secondaryText)
            LabeledContent("Target", value: target)
            LabeledContent("Starting revision", value: revision)
                .font(ScholiumTypography.exact(.body))
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
                LabeledContent("Conflict recovery", value: "Retained candidate source")
                Text("The Method may guide scholarly work, but it cannot hide or expand these app-owned facts.")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                .font(ScholiumTypography.scholarly(.title))
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
                    .font(ScholiumTypography.scholarly(.body))
                    .scholiumForeground(.secondaryText)
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
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
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
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        case .collaboration:
            ResearchProofSection(title: "TRIPTYCH COLLABORATION") {
                Picker("Collaboration policy", selection: $collaborationPolicy) {
                    Text("Ask Me Every Time").tag("Ask Me Every Time")
                    Text("Ask Me Only for Works").tag("Ask Me Only for Works")
                    Text("Full Triptych Access").tag("Full Triptych Access")
                }
                Text("The policy only controls when Scholium asks to extend one Run's bounded write set. It is not attached to a Skill or Agent and never grants blanket writes.")
                    .font(ScholiumTypography.scholarly(.body))
                    .scholiumForeground(.secondaryText)
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
                    .font(ScholiumTypography.interface(.rowTitle))
                Text("Practices: \(practices)")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
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
        .font(ScholiumTypography.interface(.compact))
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
                .font(ScholiumTypography.scholarly(.body))
                .scholiumForeground(.secondaryText)
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
                    .font(ScholiumTypography.interface(.compact))
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
                    .font(ScholiumTypography.scholarly(.title))
                    .accessibilityAddTraits(.isHeader)
                Text("Select the requested Note targets this Run may create or modify.")
                    .font(ScholiumTypography.scholarly(.body))
                    .scholiumForeground(.secondaryText)
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
