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
