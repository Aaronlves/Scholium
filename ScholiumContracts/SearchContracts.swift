import Foundation

public enum SearchMatchedField: String, Codable, Hashable, Sendable {
    case title, alias, heading, author, year, tag, body, callout, footnote, path
    case brokenLink = "broken_link"
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
    public let resultID: String
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
    public let matchedFields: [SearchMatchedField]
    public let rankReason: SearchRankReason
    public let sourceRange: SearchSourceRange?
    public let freshnessToken: SearchFreshnessToken
    public let fingerprint: DocumentFingerprint
    public let evidentialLayer: EvidentialLayer
    public let classification: SearchResultClassification

    public init(
        resultID: String? = nil,
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
        matchedFields: [SearchMatchedField]? = nil,
        rankReason: SearchRankReason = .lexicalRelevance,
        sourceRange: SearchSourceRange? = nil,
        freshnessToken: SearchFreshnessToken,
        fingerprint: DocumentFingerprint,
        evidentialLayer: EvidentialLayer,
        classification: SearchResultClassification
    ) {
        self.resultID = resultID
            ?? "\(vaultID.uuidString.lowercased()):\(relativePath):\(sourceLine):\(matchedField.rawValue)"
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
        self.matchedFields = matchedFields ?? [matchedField]
        self.rankReason = rankReason
        self.sourceRange = sourceRange
        self.freshnessToken = freshnessToken
        self.fingerprint = fingerprint
        self.evidentialLayer = evidentialLayer
        self.classification = classification
    }

    public var noteReference: VaultQualifiedNoteID {
        VaultQualifiedNoteID(vaultID: vaultID, relativePath: relativePath)
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
    public let document: NoteDocument
    public let semantic: MarkdownSemanticDocument
    public let evidentialLayer: EvidentialLayer
    public let hasBrokenLink: Bool
    public let projection: SearchDocumentProjection

    public init(
        vaultID: UUID,
        vaultName: String,
        vaultRole: VaultRole,
        document: NoteDocument,
        semantic: MarkdownSemanticDocument? = nil,
        hasBrokenLink: Bool = false
    ) {
        self.init(
            vaultID: vaultID,
            vaultName: vaultName,
            vaultRole: vaultRole,
            document: document,
            resolvedSemantic: semantic ?? MarkdownSemanticDocument(
                parsing: document
            ),
            sourceProjection: nil,
            hasBrokenLink: hasBrokenLink
        )
    }

    package init(
        vaultID: UUID,
        vaultName: String,
        vaultRole: VaultRole,
        document: NoteDocument,
        semantic: MarkdownSemanticDocument,
        cachedSourceProjection: SearchDocumentProjection,
        hasBrokenLink: Bool = false
    ) {
        self.init(
            vaultID: vaultID,
            vaultName: vaultName,
            vaultRole: vaultRole,
            document: document,
            resolvedSemantic: semantic,
            sourceProjection: cachedSourceProjection,
            hasBrokenLink: hasBrokenLink
        )
    }

    private init(
        vaultID: UUID,
        vaultName: String,
        vaultRole: VaultRole,
        document: NoteDocument,
        resolvedSemantic: MarkdownSemanticDocument,
        sourceProjection cachedSourceProjection: SearchDocumentProjection?,
        hasBrokenLink: Bool
    ) {
        self.vaultID = vaultID
        self.vaultName = vaultName
        self.vaultRole = vaultRole
        self.document = document
        self.semantic = resolvedSemantic
        relativePath = document.relativePath
        stableNoteID = ["note_id", "paper_id", "topic_id", "output_id"]
            .compactMap { document.parsedFrontmatter[$0]?.searchStrings.first }
            .first
        title = ResearchNoteTitleResolver.resolve(
            document: document,
            vaultRole: vaultRole,
            semantic: self.semantic
        ).title
        aliases = document.parsedFrontmatter["aliases"]?.searchStrings
            ?? document.parsedFrontmatter["alias"]?.searchStrings
            ?? []
        authors = document.parsedFrontmatter["authors"]?.searchStrings
            ?? document.parsedFrontmatter["author"]?.searchStrings
            ?? []
        year = document.parsedFrontmatter["year"]?.displayScalar
        tags = document.parsedFrontmatter["tags"]?.searchStrings ?? []
        self.hasBrokenLink = hasBrokenLink
        let sourceProjection = cachedSourceProjection ?? SearchDocumentProjection(
            document: document,
            profile: WorkflowProfileResolver.resolve(
                vaultRole: vaultRole,
                frontmatter: document.parsedFrontmatter,
                relativePath: document.relativePath
            ),
            semantic: self.semantic
        )
        projection = sourceProjection.applyingDynamicState(
            hasBrokenLink: hasBrokenLink
        )
        evidentialLayer = switch vaultRole {
        case .sourceCorpus: .paperAnalysis
        case .topicKnowledge: .topicNote
        case .draftProject: .draftProse
        case .other: .topicNote
        }
    }
}

public enum SearchIndexSyncDisposition: String, Codable, Hashable, Sendable {
    case unchanged
    case incrementallyUpdated
    case rebuilt
    case recoveredAndRebuilt
}

public enum SearchIndexError: LocalizedError, Sendable {
    case sqlite(String)
    case corruptDatabase
    case incompatibleSchema
    case invalidDocuments(String)

    public var errorDescription: String? {
        switch self {
        case .sqlite(let message): "The search index failed: \(message)"
        case .corruptDatabase: "The generated search index is corrupt and must be rebuilt."
        case .incompatibleSchema: "The generated search index uses an incompatible schema and must be rebuilt."
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
