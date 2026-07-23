import ScholiumContracts

/// A stable visual section in the structured Properties interface.
///
/// Groups and their ordering are GUI policy only. Property meaning,
/// requiredness, allowed values, aliases, and validation remain in Core.
enum PropertyPresentationGroup: String, CaseIterable, Hashable, Sendable {
    case researchUnit
    case about
    case source
    case progress
    case assessment
    case use
    case history
    case other

    var label: String {
        switch self {
        case .researchUnit: ScholiumL10n.dynamicString("Research Unit")
        case .about: ScholiumL10n.dynamicString("About")
        case .source: ScholiumL10n.dynamicString("Source")
        case .progress: ScholiumL10n.dynamicString("Progress")
        case .assessment: ScholiumL10n.dynamicString("Assessment")
        case .use: ScholiumL10n.dynamicString("Use")
        case .history: ScholiumL10n.dynamicString("History")
        case .other: ScholiumL10n.dynamicString("Other")
        }
    }

    var order: Int {
        switch self {
        case .researchUnit: 0
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
    case researchUnit
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
        case .analysis:
            analysis
        case .topicMarkdown:
            topic
        case .draftProject:
            work
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
            "Record represented completion and any material limitations; this does not judge analytical adequacy.",
            .researchUnit, 0, .researchUnit
        ),
        item("access", "Access", "Extent of source material available for the analysis.", .source, 0, .choicePicker),
        item("text_reliability", "Text Reliability", "Reliability of the text actually consulted.", .source, 1, .choicePicker),
        item("locators", "Locators", "Whether citations can be checked at stable locations.", .source, 2, .choicePicker),
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
        item("aliases", "Aliases", "Alternative names used for finding and linking the Topic.", .about, 0, .textListEditor),
        item("tags", "Tags", nil, .about, 1, .tagEditor),
        item("research_unit", "Research Unit", "Optional conceptual or debate scope plus material limitations.", .researchUnit, 0, .researchUnit),
    ]

    private static let work: [PropertyPresentation] = [
        item("authors", "Authors", "Use for co-authored work; omit for an ordinary single-author vault.", .about, 0, .textListEditor),
        item("kind", "Kind", "Optional form of the authored Work.", .about, 1, .choicePicker),
        item("tags", "Tags", nil, .about, 2, .tagEditor),
        item("research_unit", "Research Unit", "Optional Research Scope plus material limitations.", .researchUnit, 0, .researchUnit),
        item("venue", "Venue", "Journal, publisher, course, event, or other destination.", .use, 0, .textField),
    ]

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
            label: ScholiumL10n.dynamicString(label),
            help: help.map(ScholiumL10n.dynamicString),
            group: group,
            order: order,
            controlStyle: controlStyle
        )
    }
}
