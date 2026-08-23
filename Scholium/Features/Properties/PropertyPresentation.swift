import ScholiumContracts

/// The one fixed presentation-group vocabulary shared by Properties,
/// Settings, and About. YAML remains flat; these groups are reading order.
enum PropertyPresentationGroup: String, CaseIterable, Hashable, Sendable {
    case source
    case publication
    case accessAndIdentifiers
    case topicDescription
    case workDescription
    case authoredYAML
    case customMetadata

    var label: String {
        switch self {
        case .source: ScholiumL10n.dynamicString("Source")
        case .publication: ScholiumL10n.dynamicString("Publication")
        case .accessAndIdentifiers: ScholiumL10n.dynamicString("Access & Identifiers")
        case .topicDescription: ScholiumL10n.dynamicString("Topic Description")
        case .workDescription: ScholiumL10n.dynamicString("Work Description")
        case .authoredYAML: ScholiumL10n.dynamicString("Authored YAML")
        case .customMetadata: ScholiumL10n.dynamicString("Custom Metadata")
        }
    }

    var order: Int {
        switch self {
        case .source, .topicDescription, .workDescription: 0
        case .publication: 1
        case .accessAndIdentifiers: 2
        case .customMetadata: 3
        case .authoredYAML: 4
        }
    }
}

enum PropertyControlStyle: String, CaseIterable, Hashable, Sendable {
    case textField
    case multilineText
    case numberField
    case dateField
    case toggle
    case tagEditor
    case textListEditor
    case choicePicker
    case creatorListEditor
}

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

    static func presentations(
        for profile: SchemaProfileID,
        catalog: NoteMetadataCatalog
    ) -> [PropertyPresentation] {
        let contracts = catalog.contracts(for: profile)
            + PropertyContractCatalog.contracts(for: profile)
        return contracts.enumerated().map { index, contract in
            PropertyPresentation(
                key: contract.canonicalKey,
                label: label(
                    for: contract.canonicalKey,
                    profile: profile,
                    catalog: catalog
                ),
                help: help(
                    for: contract.canonicalKey,
                    profile: profile,
                    catalog: catalog
                ),
                group: group(for: contract.canonicalKey, profile: profile),
                order: index,
                controlStyle: controlStyle(for: contract)
            )
        }.sorted {
            ($0.group.order, $0.order) < ($1.group.order, $1.order)
        }
    }

    static func managedPresentations(
        for profile: SchemaProfileID,
        catalog: NoteMetadataCatalog
    ) -> [PropertyPresentation] {
        let managedKeys = Set(
            catalog.contracts(for: profile).map(\.canonicalKey)
        )
        return presentations(for: profile, catalog: catalog).filter {
            managedKeys.contains($0.key)
        }
    }

    static func contract(
        for presentation: PropertyPresentation,
        in profile: SchemaProfileID,
        catalog: NoteMetadataCatalog
    ) -> PropertyContract? {
        guard let contract = catalog.contract(
            for: presentation.key,
            profile: profile
        ) ?? PropertyContractCatalog.contract(
            for: presentation.key,
            profile: profile
        ), contract.canonicalKey == presentation.key else { return nil }
        return contract
    }

    static func presentation(
        for key: String,
        in profile: SchemaProfileID,
        catalog: NoteMetadataCatalog
    ) -> PropertyPresentation? {
        presentations(for: profile, catalog: catalog).first { $0.key == key }
    }

    static func orderedGroups(for profile: SchemaProfileID) -> [PropertyPresentationGroup] {
        switch profile {
        case .analysis:
            [.source, .publication, .accessAndIdentifiers, .customMetadata, .authoredYAML]
        case .topicMarkdown:
            [.topicDescription, .customMetadata, .authoredYAML]
        case .draftProject:
            [.workDescription, .customMetadata, .authoredYAML]
        case .genericMarkdown:
            [.customMetadata]
        }
    }

    static func choiceDisplayName(for value: String, fieldKey: String) -> String {
        if fieldKey == "type", let sourceType = AnalysisSourceType(rawValue: value) {
            return sourceType.propertyDisplayName
        }
        return ScholiumL10n.dynamicString(
            value.replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.capitalized }
                .joined(separator: " ")
        )
    }

    private static let analysisSourceKeys: Set<String> = [
        "type", "title", "short_title", "original_title", "reviewed_title",
        "genre", "medium", "version", "language", "authors", "editors",
        "translators", "collection_editors", "container_authors",
        "original_authors", "reviewed_authors",
    ]

    private static let analysisAccessKeys: Set<String> = [
        "accessed_date", "doi", "isbn", "issn", "url", "pmid", "pmcid",
        "arxiv_id", "archive", "archive_collection", "archive_location",
        "archive_place", "call_number",
    ]

    private static func group(
        for key: String,
        profile: SchemaProfileID
    ) -> PropertyPresentationGroup {
        if key == "summary" || key == "keywords" { return .authoredYAML }
        switch profile {
        case .analysis:
            if analysisSourceKeys.contains(key) { return .source }
            if analysisAccessKeys.contains(key) { return .accessAndIdentifiers }
            return BuiltInNoteMetadataCatalog.contract(for: key, profile: profile) == nil
                ? .customMetadata
                : .publication
        case .topicMarkdown:
            return BuiltInNoteMetadataCatalog.contract(for: key, profile: profile) == nil
                ? .customMetadata
                : .topicDescription
        case .draftProject:
            return BuiltInNoteMetadataCatalog.contract(for: key, profile: profile) == nil
                ? .customMetadata
                : .workDescription
        case .genericMarkdown:
            return .customMetadata
        }
    }

    private static func controlStyle(for contract: PropertyContract) -> PropertyControlStyle {
        switch contract.valueKind {
        case .text: .textField
        case .multilineText: .multilineText
        case .number: .numberField
        case .date: .dateField
        case .boolean: .toggle
        case .tags: .tagEditor
        case .textList: .textListEditor
        case .choice: .choicePicker
        case .creatorList: .creatorListEditor
        case .mapping: .multilineText
        }
    }

    private static func label(
        for key: String,
        profile: SchemaProfileID,
        catalog: NoteMetadataCatalog
    ) -> String {
        let fixed: [String: String] = [
            "type": "Source Type", "title": "Title", "short_title": "Short Title",
            "original_title": "Original Title", "reviewed_title": "Reviewed Title",
            "genre": "Genre", "medium": "Medium", "version": "Version",
            "language": "Language", "authors": "Source Authors", "editors": "Editors",
            "translators": "Translators", "collection_editors": "Collection Editors",
            "container_authors": "Container Authors", "original_authors": "Original Authors",
            "reviewed_authors": "Reviewed Authors", "publication_date": "Publication Date",
            "publication_status": "Publication Status",
            "original_publication_date": "Original Publication Date",
            "accessed_date": "Accessed Date", "event_date": "Event Date",
            "container_title": "Publication / Container", "container_title_short": "Short Container Title",
            "series_title": "Series Title", "series_number": "Series Number",
            "volume": "Volume", "volume_title": "Volume Title", "issue": "Issue",
            "pages": "Pages", "chapter_number": "Chapter Number", "edition": "Edition",
            "number_of_volumes": "Number of Volumes", "publisher": "Publisher",
            "publisher_place": "Publisher Place", "original_publisher": "Original Publisher",
            "original_publisher_place": "Original Publisher Place", "institution": "Institution",
            "report_number": "Report Number", "event_title": "Event Title",
            "event_place": "Event Place", "doi": "DOI", "isbn": "ISBN", "issn": "ISSN",
            "url": "URL", "pmid": "PMID", "pmcid": "PMCID", "arxiv_id": "arXiv ID",
            "archive": "Archive", "archive_collection": "Archive Collection",
            "archive_location": "Archive Location", "archive_place": "Archive Place",
            "call_number": "Call Number", "keywords": "Keywords", "summary": "Note Summary",
            "aliases": "Aliases", "work_type": "Work Type", "coauthors": "Co-authors",
        ]
        return ScholiumL10n.dynamicString(
            fixed[key]
                ?? catalog.customField(for: key, profile: profile)?.label
                ?? MetadataFieldDefinition.defaultLabel(for: key)
        )
    }

    private static func help(
        for key: String,
        profile: SchemaProfileID,
        catalog: NoteMetadataCatalog
    ) -> String? {
        let text: String? = switch key {
        case "title": "Title of the analyzed source."
        case "type": "Broad source type used to select applicable bibliographic fields."
        case "publication_date": "Publication date as authored text; publication status belongs in Publication Status."
        case "publication_status": "Publication state such as forthcoming, in press, retracted, or withdrawn."
        case "authors": "Ordered structured names of the analyzed source's authors."
        case "summary": "Short navigation description of this Note; open the current Note and sources before relying on it."
        case "aliases": "Alternative names used for finding and linking this Topic."
        case "keywords": "Short researcher-defined retrieval terms stored in authored YAML."
        default: nil
        }
        return (text ?? catalog.customField(for: key, profile: profile)?.description)
            .map(ScholiumL10n.dynamicString)
    }
}

extension AnalysisSourceType {
    var propertyDisplayName: String {
        let label = rawValue.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
        return ScholiumL10n.dynamicString(label)
    }
}
