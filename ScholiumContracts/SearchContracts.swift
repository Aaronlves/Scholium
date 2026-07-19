import Foundation

public struct SearchQuery: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum SearchScope: Codable, Hashable, Sendable {
    case currentNote(VaultQualifiedNoteID)
    case currentVault(UUID)
    case workspace
    case roles(Set<VaultRole>)
}

public struct SearchFilter: Codable, Hashable, Sendable {
    public var vault: String?
    public var role: VaultRole?
    public var relativePath: String?
    public var status: String?
    public var review: String?
    public var callout: String?
    public var hasBrokenLink: Bool?

    public init(
        vault: String? = nil,
        role: VaultRole? = nil,
        relativePath: String? = nil,
        status: String? = nil,
        review: String? = nil,
        callout: String? = nil,
        hasBrokenLink: Bool? = nil
    ) {
        self.vault = vault
        self.role = role
        self.relativePath = relativePath
        self.status = status
        self.review = review
        self.callout = callout
        self.hasBrokenLink = hasBrokenLink
    }
}

public enum SearchMatchedField: String, Codable, Hashable, Sendable {
    case title, alias, heading, author, year, tag, status, body, callout, footnote, metadata, path
}

public enum SearchResultClassification: String, Codable, Hashable, Sendable {
    case retrievalLead = "retrieval_lead"
}

public struct SearchHighlight: Codable, Hashable, Sendable {
    public let utf16LowerBound: Int
    public let utf16UpperBound: Int

    public init(utf16LowerBound: Int, utf16UpperBound: Int) {
        self.utf16LowerBound = utf16LowerBound
        self.utf16UpperBound = utf16UpperBound
    }
}

public struct SearchHit: Codable, Hashable, Sendable {
    public let vaultID: UUID
    public let vaultName: String
    public let vaultRole: VaultRole
    public let relativePath: String
    public let stableNoteID: String?
    public let title: String
    public let matchedField: SearchMatchedField
    public let context: String?
    public let sourceLine: Int
    public let snippet: String
    public let highlights: [SearchHighlight]
    public let score: Double
    public let fingerprint: DocumentFingerprint
    public let indexGeneration: Int
    public let evidentialLayer: EvidentialLayer
    public let classification: SearchResultClassification

    public init(
        vaultID: UUID,
        vaultName: String,
        vaultRole: VaultRole,
        relativePath: String,
        stableNoteID: String?,
        title: String,
        matchedField: SearchMatchedField,
        context: String?,
        sourceLine: Int,
        snippet: String,
        highlights: [SearchHighlight],
        score: Double,
        fingerprint: DocumentFingerprint,
        indexGeneration: Int,
        evidentialLayer: EvidentialLayer,
        classification: SearchResultClassification
    ) {
        self.vaultID = vaultID
        self.vaultName = vaultName
        self.vaultRole = vaultRole
        self.relativePath = relativePath
        self.stableNoteID = stableNoteID
        self.title = title
        self.matchedField = matchedField
        self.context = context
        self.sourceLine = sourceLine
        self.snippet = snippet
        self.highlights = highlights
        self.score = score
        self.fingerprint = fingerprint
        self.indexGeneration = indexGeneration
        self.evidentialLayer = evidentialLayer
        self.classification = classification
    }
}

public struct IndexGeneration: Codable, Hashable, Sendable {
    public static let contractVersion = 2
    public let vaultID: UUID
    public let sequence: Int
    public let contractVersion: Int
    public let fingerprints: [String: DocumentFingerprint]

    public init(
        vaultID: UUID,
        sequence: Int,
        contractVersion: Int,
        fingerprints: [String: DocumentFingerprint]
    ) {
        self.vaultID = vaultID
        self.sequence = sequence
        self.contractVersion = contractVersion
        self.fingerprints = fingerprints
    }
}

public struct SearchIndexDocument: Sendable {
    public let vaultID: UUID
    public let vaultName: String
    public let vaultRole: VaultRole
    public let relativePath: String
    public let stableNoteID: String?
    public let title: String
    public let aliases: [String]
    public let authors: [String]
    public let year: String?
    public let tags: [String]
    public let status: String?
    public let review: String?
    public let document: NoteDocument
    public let semantic: MarkdownSemanticDocument
    public let evidentialLayer: EvidentialLayer
    public let hasBrokenLink: Bool

    public init(
        vaultID: UUID,
        vaultName: String,
        vaultRole: VaultRole,
        document: NoteDocument,
        semantic: MarkdownSemanticDocument? = nil,
        review: String? = nil,
        hasBrokenLink: Bool = false
    ) {
        self.vaultID = vaultID
        self.vaultName = vaultName
        self.vaultRole = vaultRole
        self.document = document
        self.semantic = semantic ?? MarkdownSemanticDocument(parsing: document)
        relativePath = document.relativePath
        stableNoteID = ["note_id", "paper_id", "topic_id", "output_id"]
            .compactMap { document.parsedFrontmatter[$0]?.searchStrings.first }
            .first
        title = document.parsedFrontmatter["title"]?.searchStrings.first
            ?? (document.relativePath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
        aliases = document.parsedFrontmatter["aliases"]?.searchStrings
            ?? document.parsedFrontmatter["alias"]?.searchStrings
            ?? []
        authors = document.parsedFrontmatter["authors"]?.searchStrings
            ?? document.parsedFrontmatter["author"]?.searchStrings
            ?? []
        year = document.parsedFrontmatter["year"]?.displayScalar
        tags = document.parsedFrontmatter["tags"]?.searchStrings ?? []
        status = document.parsedFrontmatter["status"]?.displayScalar
        self.review = review
        self.hasBrokenLink = hasBrokenLink
        evidentialLayer = switch vaultRole {
        case .sourceCorpus: .paperAnalysis
        case .topicKnowledge: .topicNote
        case .draftProject: .draftProse
        case .other: .topicNote
        }
    }
}

public enum SearchIndexMutation: Sendable {
    case upsert(SearchIndexDocument)
    case delete(relativePath: String)
}

public enum SearchIndexSyncDisposition: String, Codable, Hashable, Sendable {
    case unchanged
    case incrementallyUpdated
    case rebuilt
    case recoveredAndRebuilt
}

public struct SearchIndexSyncResult: Codable, Hashable, Sendable {
    public let generation: IndexGeneration
    public let disposition: SearchIndexSyncDisposition

    public init(generation: IndexGeneration, disposition: SearchIndexSyncDisposition) {
        self.generation = generation
        self.disposition = disposition
    }
}

public enum SearchIndexError: LocalizedError, Sendable {
    case sqlite(String)
    case corruptDatabase
    case incompatibleSchema
    case invalidQuery(String)
    case invalidDocuments(String)

    public var errorDescription: String? {
        switch self {
        case .sqlite(let message): "The search index failed: \(message)"
        case .corruptDatabase: "The generated search index is corrupt and must be rebuilt."
        case .incompatibleSchema: "The generated search index uses an incompatible schema and must be rebuilt."
        case .invalidQuery(let message): "The search query is invalid: \(message)"
        case .invalidDocuments(let message): "The search index input is invalid: \(message)"
        }
    }
}


public extension YAMLValue {
    var searchStrings: [String] {
        switch self {
        case .string(let value): [value]
        case .integer(let value): [String(value)]
        case .double(let value): [String(value)]
        case .boolean(let value): [value ? "true" : "false"]
        case .array(let values): values.flatMap(\.searchStrings)
        case .object(let values): values.keys.sorted().flatMap { values[$0]?.searchStrings ?? [] }
        case .null: []
        }
    }
}
