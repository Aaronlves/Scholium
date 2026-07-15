import ScholiumContracts

/// A stable visual section in the structured Properties interface.
///
/// Groups and their ordering are GUI policy only. Property meaning,
/// requiredness, allowed values, aliases, and validation remain in Core.
enum PropertyPresentationGroup: String, CaseIterable, Hashable, Sendable {
    case researchStatus
    case about
    case source
    case progress
    case assessment
    case use
    case history
    case other

    var label: String {
        switch self {
        case .researchStatus: "Research Status"
        case .about: "About"
        case .source: "Source"
        case .progress: "Progress"
        case .assessment: "Assessment"
        case .use: "Use"
        case .history: "History"
        case .other: "Other"
        }
    }

    var order: Int {
        switch self {
        case .researchStatus: 0
        case .about: 1
        case .source: 2
        case .progress: 3
        case .assessment: 4
        case .use: 5
        case .history: 6
        case .other: 7
        }
    }
}

/// The GUI control family used to present one Core property contract.
enum PropertyControlStyle: String, CaseIterable, Hashable, Sendable {
    case textField
    case multilineText
    case numberField
    case dateField
    case toggle
    case tagEditor
    case textListEditor
    case choicePicker
    case researchStatus
}

/// Human-facing metadata for one canonical Core property.
///
/// The descriptor deliberately contains no semantic rules.
struct PropertyPresentation: Hashable, Sendable {
    let key: String
    let label: String
    let help: String?
    let group: PropertyPresentationGroup
    let order: Int
    let controlStyle: PropertyControlStyle
}

enum PropertyPresentationCatalog {
    static let currentProfiles: [SchemaProfileID] = [
        .analysis,
        .topicMarkdown,
        .draftProject,
    ]

    static func presentations(for profile: SchemaProfileID) -> [PropertyPresentation] {
        let presentations: [PropertyPresentation] = switch profile {
        case .analysis, .paperAnalysisV1:
            analysis
        case .topicMarkdown:
            topic
        case .draftProject:
            work
        case .dissertationControlV3:
            dissertationV3
        case .dissertationControlV4:
            dissertationV4
        case .genericMarkdown:
            []
        }
        return presentations.sorted {
            ($0.group.order, $0.order) < ($1.group.order, $1.order)
        }
    }

    /// Resolves a GUI descriptor to its canonical semantic authority.
    static func contract(
        for presentation: PropertyPresentation,
        in profile: SchemaProfileID
    ) -> PropertyContract? {
        guard let contract = PropertyContractCatalog.contract(
            for: presentation.key,
            profile: profile
        ), contract.canonicalKey == presentation.key else {
            return nil
        }
        return contract
    }

    static func presentation(for key: String, in profile: SchemaProfileID) -> PropertyPresentation? {
        presentations(for: profile).first { $0.key == key }
    }

    private static let analysis: [PropertyPresentation] = [
        item("title", "Title", "Title of the analyzed source.", .about, 0, .textField),
        item("authors", "Authors", nil, .about, 1, .textListEditor),
        item("year", "Year", nil, .about, 2, .numberField),
        item("type", "Type", "Publication form, not philosophical role.", .about, 3, .choicePicker),
        item("tags", "Tags", nil, .about, 4, .tagEditor),
        item(
            "research_unit", "Research Unit",
            "Declare the source scope represented by this Analysis and any material limitations.",
            .researchStatus, 0, .researchStatus
        ),
        item("access", "Access", "Extent of source material available for the analysis.", .source, 0, .choicePicker),
        item("text_reliability", "Text Reliability", "Reliability of the text actually consulted.", .source, 1, .choicePicker),
        item("locators", "Locators", "Whether citations can be checked at stable locations.", .source, 2, .choicePicker),
        item("status", "Status", "State of the analysis, not a judgment about the source.", .progress, 0, .choicePicker),
        item(
            "debate_importance", "Debate Importance",
            "Optional whole-number 0–10 assessment within the separately named debate scope; not project relevance, quality, truth, prestige, or citation count.",
            .assessment, 0, .numberField
        ),
        item(
            "debate_importance_scope", "Debate Scope",
            "Debate, domain, tradition, period, or reception context within which Debate Importance was assessed.",
            .assessment, 1, .textField
        ),
    ]

    private static let topic: [PropertyPresentation] = [
        item("title", "Title", "Optional when the filename and first heading already identify the Topic.", .about, 0, .textField),
        item("aliases", "Aliases", "Alternative names used for finding and linking the Topic.", .about, 1, .textListEditor),
        item("tags", "Tags", nil, .about, 2, .tagEditor),
        item("research_unit", "Research Unit", "Optional conceptual or debate boundary plus material limitations.", .researchStatus, 0, .researchStatus),
        item("status", "Status", "Development of the note, not settlement of the Topic.", .progress, 0, .choicePicker),
    ]

    private static let work: [PropertyPresentation] = [
        item("title", "Title", "Title of the Work.", .about, 0, .textField),
        item("authors", "Authors", "Use for co-authored work; omit for an ordinary single-author vault.", .about, 1, .textListEditor),
        item("kind", "Kind", "Optional form of the authored Work.", .about, 2, .choicePicker),
        item("tags", "Tags", nil, .about, 3, .tagEditor),
        item("research_unit", "Research Unit", "Optional project question, argumentative domain, or bounded Work scope plus material limitations.", .researchStatus, 0, .researchStatus),
        item("status", "Status", "Production state, not philosophical quality or acceptance probability.", .progress, 0, .choicePicker),
        item("venue", "Venue", "Journal, publisher, course, event, or other destination.", .use, 0, .textField),
        item("deadline", "Deadline", nil, .use, 1, .dateField),
    ]

    private static let dissertationV3: [PropertyPresentation] = descriptors(
        profile: .dissertationControlV3,
        entries: [
            ("note_type", "Note Type", .about),
            ("project_role", "Project Role", .about),
            ("claim_type", "Claim Type", .about),
            ("status", "Working Status", .progress),
            ("settlement_dimensions", "Settlement Dimensions", .progress),
            ("settlement_degree", "Settlement Degree", .progress),
            ("review_status", "Governance Review", .progress),
            ("confidence", "Working Confidence", .progress),
            ("prose_permission", "Prose Permission", .use),
            ("reopen_condition", "Reopen Condition", .use),
            ("privacy", "Privacy", .use),
            ("last_reviewed", "Last Substantive Review", .history),
            ("version", "Version", .history),
            ("design_decisions", "Design Decisions", .history),
        ]
    )

    private static let dissertationV4: [PropertyPresentation] = descriptors(
        profile: .dissertationControlV4,
        entries: [
            ("title", "Title", .about),
            ("note_type", "Note Type", .about),
            ("project_role", "Project Role", .about),
            ("origin", "Origin", .about),
            ("evidential_layer", "Evidential Layer", .about),
            ("question_kind", "Question Kind", .about),
            ("claim_kind", "Claim Kind", .about),
            ("inference_type", "Inference Type", .about),
            ("inference_force", "Inference Force", .about),
            ("position_kind", "Position Kind", .about),
            ("concept_kind", "Concept Kind", .about),
            ("case_kind", "Case Kind", .about),
            ("evidence_kind", "Evidence Kind", .source),
            ("verification_state", "Verification State", .source),
            ("source_locator", "Source Locator", .source),
            ("predicate", "Predicate", .about),
            ("semantic_direction", "Semantic Direction", .about),
            ("assembly_kind", "Assembly Kind", .about),
            ("chapter_id", "Chapter ID", .about),
            ("workflow_stage", "Workflow Stage", .progress),
            ("draft_target", "Draft Target", .use),
            ("registry_kind", "Registry Kind", .about),
            ("indexed_note_types", "Indexed Note Types", .about),
            ("control_kind", "Control Kind", .about),
            ("status", "Working Status", .progress),
            ("settlement_dimensions", "Settlement Dimensions", .progress),
            ("settlement_degree", "Settlement Degree", .progress),
            ("review_status", "Governance Review", .progress),
            ("confidence", "Working Confidence", .progress),
            ("evidence_state", "Evidence State", .progress),
            ("prose_permission", "Prose Permission", .use),
            ("reopen_condition", "Reopen Condition", .use),
            ("privacy", "Privacy", .use),
            ("provenance", "Provenance", .use),
            ("created_at", "Created", .history),
            ("updated_at", "Updated", .history),
            ("last_reviewed", "Last Substantive Review", .history),
            ("migration_state", "Migration State", .history),
        ]
    )

    private static func descriptors(
        profile: SchemaProfileID,
        entries: [(String, String, PropertyPresentationGroup)]
    ) -> [PropertyPresentation] {
        var groupPositions: [PropertyPresentationGroup: Int] = [:]
        return entries.compactMap { key, label, group in
            guard let contract = PropertyContractCatalog.contract(for: key, profile: profile),
                  contract.canonicalKey == key else { return nil }
            let order = groupPositions[group, default: 0]
            groupPositions[group] = order + 1
            return item(key, label, help(for: key), group, order, control(for: contract.valueKind))
        }
    }

    private static func control(for kind: PropertyValueKind) -> PropertyControlStyle {
        switch kind {
        case .text: .textField
        case .multilineText: .multilineText
        case .number: .numberField
        case .date: .dateField
        case .boolean: .toggle
        case .tags: .tagEditor
        case .textList: .textListEditor
        case .choice: .choicePicker
        case .mapping: .multilineText
        }
    }

    private static func help(for key: String) -> String? {
        switch key {
        case "project_role": "Structural role, not premise, conclusion, target, objection, or reply."
        case "origin": "Whose content or reconstruction the record represents."
        case "evidential_layer": "The represented content's evidential space."
        case "status": "Workflow state, not truth or publication status."
        case "review_status": "Human/agent review condition, separate from Scholium file review."
        case "confidence": "Qualitative only."
        case "evidence_state": "Source-check condition; not a truth verdict."
        case "prose_permission": "Whether and how draft prose may use this record."
        case "reopen_condition": "Condition requiring reconsideration."
        case "provenance": "Origins and authorizations; does not confer authority automatically."
        case "updated_at": "Mechanical edit date; carries no review meaning."
        case "last_reviewed": "Changed only by explicit substantive review."
        default: nil
        }
    }

    private static func item(
        _ key: String,
        _ label: String,
        _ help: String?,
        _ group: PropertyPresentationGroup,
        _ order: Int,
        _ controlStyle: PropertyControlStyle
    ) -> PropertyPresentation {
        PropertyPresentation(
            key: key,
            label: label,
            help: help,
            group: group,
            order: order,
            controlStyle: controlStyle
        )
    }
}
