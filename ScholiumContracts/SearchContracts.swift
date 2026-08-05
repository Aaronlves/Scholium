import Foundation

public enum SearchMatchedField: String, Codable, Hashable, Sendable {
    case title, alias, heading, summary, author, year, tag, body, callout, footnote, path
    case brokenLink = "broken_link"
}

public enum RecordSearchMatchedField: String, Codable, Hashable, Sendable {
    case context
    case action
    case skill
    case participant
    case researcherStatement = "researcher_statement"
    case agentStatement = "agent_statement"
    case material
    case sourceReference = "source_reference"
}

public enum SearchResultClassification: String, Codable, Hashable, Sendable {
    case retrievalLead = "retrieval_lead"
}

public enum SearchPropertyMatchMode: String, Codable, Hashable, Sendable {
    case presence
    case exactStringValue = "exact_string_value"
}

public struct SearchPropertyMatch: Codable, Hashable, Sendable {
    public let key: String
    public let mode: SearchPropertyMatchMode
    public let normalizedValue: String?
    public let valueKind: SearchPropertyProjection.ValueKind
    public let isEmpty: Bool
    public let keySourceRange: SearchSourceRange
    public let valueSourceRanges: [SearchSourceRange]

    public init(
        key: String,
        mode: SearchPropertyMatchMode,
        normalizedValue: String?,
        valueKind: SearchPropertyProjection.ValueKind,
        isEmpty: Bool,
        keySourceRange: SearchSourceRange,
        valueSourceRanges: [SearchSourceRange] = []
    ) {
        self.key = key
        self.mode = mode
        self.normalizedValue = normalizedValue
        self.valueKind = valueKind
        self.isEmpty = isEmpty
        self.keySourceRange = keySourceRange
        self.valueSourceRanges = valueSourceRanges
    }
}

public struct SearchRelationshipMatch: Codable, Hashable, Sendable {
    public let relation: SearchRelation
    public let direction: SearchRelationDirection
    public let symmetric: Bool
    public let anchorIdentity: String
    public let targetNote: VaultQualifiedNoteID
    public let occurrences: [RelationshipSourceOccurrence]

    public init(
        relation: SearchRelation,
        direction: SearchRelationDirection,
        anchorIdentity: String,
        targetNote: VaultQualifiedNoteID,
        occurrences: [RelationshipSourceOccurrence]
    ) {
        self.relation = relation
        self.direction = direction
        symmetric = relation.isSymmetric
        self.anchorIdentity = anchorIdentity
        self.targetNote = targetNote
        self.occurrences = occurrences
    }
}

public enum NoteSearchMatchReason: Codable, Hashable, Sendable {
    case lexical
    case property(SearchPropertyMatch)
    case relationship(SearchRelationshipMatch)
}

public struct SearchHighlight: Codable, Hashable, Sendable {
    public let utf16LowerBound: Int
    public let utf16UpperBound: Int

    public init(utf16LowerBound: Int, utf16UpperBound: Int) {
        self.utf16LowerBound = utf16LowerBound
        self.utf16UpperBound = utf16UpperBound
    }
}

public struct NoteSearchResult: Codable, Hashable, Sendable {
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
    public let primaryMatchReason: NoteSearchMatchReason
    public let additionalMatchReasons: [NoteSearchMatchReason]
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
        primaryMatchReason: NoteSearchMatchReason = .lexical,
        additionalMatchReasons: [NoteSearchMatchReason] = [],
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
        self.primaryMatchReason = primaryMatchReason
        self.additionalMatchReasons = additionalMatchReasons
        self.sourceRange = sourceRange
        self.freshnessToken = freshnessToken
        self.fingerprint = fingerprint
        self.evidentialLayer = evidentialLayer
        self.classification = classification
    }

    public var noteReference: VaultQualifiedNoteID {
        VaultQualifiedNoteID(vaultID: vaultID, relativePath: relativePath)
    }

    /// A nonempty, deterministic sequence. The primary ranking reason comes
    /// first; further satisfied structured AND clauses follow query order.
    public var matchReasons: [NoteSearchMatchReason] {
        [primaryMatchReason] + additionalMatchReasons
    }
}

public struct RecordSearchResult: Codable, Hashable, Sendable {
    public let resultID: String
    public let recordID: UUID
    public let statementID: UUID?
    public let statementAuthor: PortableResearchStatementAuthor?
    public let matchedField: RecordSearchMatchedField
    public let additionalMatchedFields: [RecordSearchMatchedField]
    public let matchedReason: String
    public let context: String
    public let actionID: String?
    public let methodName: String?
    public let sourceDisplayName: String?
    public let finishedAt: Date
    public let pinned: Bool
    public let participatingNotes: [VaultQualifiedNoteID]
    public let snippet: String
    public let highlights: [SearchHighlight]
    public let sourceRange: SearchSourceRange?
    public let freshnessToken: SearchFreshnessToken
    public let fingerprint: DocumentFingerprint
    public let classification: SearchResultClassification

    public init(
        resultID: String? = nil,
        recordID: UUID,
        statementID: UUID? = nil,
        statementAuthor: PortableResearchStatementAuthor? = nil,
        matchedField: RecordSearchMatchedField,
        additionalMatchedFields: [RecordSearchMatchedField] = [],
        matchedReason: String,
        context: String,
        actionID: String? = nil,
        methodName: String? = nil,
        sourceDisplayName: String? = nil,
        finishedAt: Date,
        pinned: Bool,
        participatingNotes: [VaultQualifiedNoteID],
        snippet: String,
        highlights: [SearchHighlight] = [],
        sourceRange: SearchSourceRange? = nil,
        freshnessToken: SearchFreshnessToken,
        fingerprint: DocumentFingerprint,
        classification: SearchResultClassification = .retrievalLead
    ) {
        self.resultID = resultID
            ?? "record:\(recordID.uuidString.lowercased()):\(statementID?.uuidString.lowercased() ?? matchedField.rawValue)"
        self.recordID = recordID
        self.statementID = statementID
        self.statementAuthor = statementAuthor
        self.matchedField = matchedField
        self.additionalMatchedFields = additionalMatchedFields
        self.matchedReason = matchedReason
        self.context = context
        self.actionID = actionID
        self.methodName = methodName
        self.sourceDisplayName = sourceDisplayName
        self.finishedAt = finishedAt
        self.pinned = pinned
        self.participatingNotes = participatingNotes
        self.snippet = snippet
        self.highlights = highlights
        self.sourceRange = sourceRange
        self.freshnessToken = freshnessToken
        self.fingerprint = fingerprint
        self.classification = classification
    }

    /// A nonempty typed summary of all fields satisfied by this one Record.
    public var matchedFields: [RecordSearchMatchedField] {
        [matchedField] + additionalMatchedFields
    }
}

public enum SearchResult: Codable, Hashable, Identifiable, Sendable {
    case note(NoteSearchResult)
    case record(RecordSearchResult)

    public var id: String {
        switch self {
        case .note(let result): result.resultID
        case .record(let result): result.resultID
        }
    }

    public var provider: SearchProvider {
        switch self {
        case .note: .note
        case .record: .record
        }
    }

    public var freshnessToken: SearchFreshnessToken {
        switch self {
        case .note(let result): result.freshnessToken
        case .record(let result): result.freshnessToken
        }
    }

    public var fingerprint: DocumentFingerprint {
        switch self {
        case .note(let result): result.fingerprint
        case .record(let result): result.fingerprint
        }
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
    public let propertyProjection: SearchPropertyProjection

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
        propertyProjection = SearchPropertyProjection(document: document)
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
