import Foundation

public enum AnalysisSourceType: String, Codable, CaseIterable, Hashable, Sendable {
    case journalArticle = "journal_article"
    case book
    case chapter
    case encyclopediaEntry = "encyclopedia_entry"
    case thesis
    case manuscript
    case report
    case preprint
    case conferencePaper = "conference_paper"
    case presentation
    case webpage
    case review
    case dataset
    case software
    case archivalItem = "archival_item"
    case correspondence
    case audiovisual
    case other

    /// Stable CSL type output for the citation adapter. Mapping is
    /// intentionally one-way and does not import a CSL schema into authored
    /// YAML.
    public var cslType: String {
        switch self {
        case .journalArticle: "article-journal"
        case .book: "book"
        case .chapter: "chapter"
        case .encyclopediaEntry: "entry-encyclopedia"
        case .thesis: "thesis"
        case .manuscript: "manuscript"
        case .report: "report"
        case .preprint: "article"
        case .conferencePaper: "paper-conference"
        case .presentation: "speech"
        case .webpage: "webpage"
        case .review: "review-book"
        case .dataset: "dataset"
        case .software: "software"
        case .archivalItem: "document"
        case .correspondence: "personal_communication"
        case .audiovisual: "motion_picture"
        case .other: "document"
        }
    }
}

public struct AnalysisSourceTypeProfile: Codable, Hashable, Sendable {
    public let sourceType: AnalysisSourceType
    public let applicableFields: [String]
    public let recommendedFieldOrder: [String]
    public let serializationFieldOrder: [String]

    public init(
        sourceType: AnalysisSourceType,
        applicableFields: [String],
        recommendedFieldOrder: [String],
        serializationFieldOrder: [String]
    ) {
        self.sourceType = sourceType
        self.applicableFields = Self.unique(applicableFields)
        self.recommendedFieldOrder = Self.unique(recommendedFieldOrder)
        self.serializationFieldOrder = Self.unique(serializationFieldOrder)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}

public enum AnalysisSourceTypeProfileCatalog {
    public static func profile(for sourceType: AnalysisSourceType) -> AnalysisSourceTypeProfile {
        profiles[sourceType]!
    }

    private static let profiles: [AnalysisSourceType: AnalysisSourceTypeProfile] =
        Dictionary(uniqueKeysWithValues: AnalysisSourceType.allCases.map { sourceType in
            let recommended = recommendedFields(for: sourceType)
            let applicable = unique(recommended + conditionalFields(for: sourceType))
            let serialization = BuiltInNoteMetadataCatalog.analysisCanonicalKeys.filter(applicable.contains)
            return (
                sourceType,
                AnalysisSourceTypeProfile(
                    sourceType: sourceType,
                    applicableFields: applicable,
                    recommendedFieldOrder: recommended,
                    serializationFieldOrder: serialization
                )
            )
        })

    private static func recommendedFields(for type: AnalysisSourceType) -> [String] {
        switch type {
        case .journalArticle:
            ["type", "title", "authors", "container_title", "publication_date", "volume", "issue", "pages"]
        case .book:
            ["type", "title", "authors", "editors", "publication_date", "publisher", "publisher_place"]
        case .chapter, .encyclopediaEntry:
            ["type", "title", "authors", "container_title", "editors", "publication_date", "publisher", "publisher_place", "pages"]
        case .thesis:
            ["type", "title", "authors", "publication_date", "genre", "institution"]
        case .manuscript, .report, .preprint:
            ["type", "title", "authors", "publication_status"]
        case .conferencePaper, .presentation:
            ["type", "title", "authors", "event_title"]
        case .webpage:
            ["type", "title", "authors", "url", "accessed_date"]
        case .review:
            ["type", "title", "authors", "reviewed_authors", "publication_date"]
        case .archivalItem, .correspondence:
            ["type", "title", "authors", "publication_date", "archive", "archive_collection", "archive_location"]
        case .dataset, .software, .audiovisual:
            ["type", "title", "authors", "version", "publication_date"]
        case .other:
            ["type", "title", "authors"]
        }
    }

    private static func conditionalFields(for type: AnalysisSourceType) -> [String] {
        switch type {
        case .journalArticle:
            ["doi", "issn", "url", "accessed_date", "container_title_short", "publication_status", "language", "pmid", "pmcid"]
        case .book:
            ["edition", "translators", "isbn", "series_title", "series_number", "volume", "volume_title", "number_of_volumes", "original_title", "original_authors", "original_publication_date", "original_publisher", "original_publisher_place", "language", "doi", "url"]
        case .chapter, .encyclopediaEntry:
            ["chapter_number", "edition", "volume", "volume_title", "isbn", "translators", "container_authors", "collection_editors", "series_title", "series_number", "language", "doi", "url"]
        case .thesis:
            ["url", "accessed_date", "doi", "language", "publisher_place"]
        case .manuscript, .report, .preprint:
            ["publication_date", "institution", "report_number", "version", "archive", "arxiv_id", "doi", "url", "accessed_date", "language"]
        case .conferencePaper, .presentation:
            ["event_date", "event_place", "container_title", "editors", "pages", "publisher", "publication_date", "doi", "url", "language"]
        case .webpage:
            ["container_title", "publication_date", "publication_status", "language", "version"]
        case .review:
            ["reviewed_title", "container_title", "volume", "issue", "pages", "doi", "url", "accessed_date", "reviewed_authors"]
        case .archivalItem, .correspondence:
            ["archive_place", "call_number", "medium", "language"]
        case .dataset, .software, .audiovisual:
            ["medium", "publisher", "doi", "url", "accessed_date", "language"]
        case .other:
            BuiltInNoteMetadataCatalog.analysisCanonicalKeys
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
