import Foundation

public enum SearchMatchedField: String, Codable, Hashable, Sendable {
    case title, alias, heading, summary, author, body, callout, footnote, path
    case tag = "keyword"
    case publicationDate = "publication_date"
    case brokenLink = "broken_link"
    case linkAnnotation = "link_annotation"
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
    public let keySourceRange: SearchSourceRange?
    public let valueSourceRanges: [SearchSourceRange]

    public init(
        key: String,
        mode: SearchPropertyMatchMode,
        normalizedValue: String?,
        valueKind: SearchPropertyProjection.ValueKind,
        isEmpty: Bool,
        keySourceRange: SearchSourceRange?,
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

public struct SearchLinkOccurrence: Codable, Hashable, Sendable {
    public let sourceNote: VaultQualifiedNoteID
    public let span: SourceSpan
    public let linkSpan: SourceSpan
    public let annotationSpan: SourceSpan?

    public init(sourceNote: VaultQualifiedNoteID, occurrence: LinkOccurrence) {
        self.sourceNote = sourceNote
        span = occurrence.span
        linkSpan = occurrence.linkSpan
        annotationSpan = occurrence.annotation?.span
    }
}

public struct SearchLinkMatch: Codable, Hashable, Sendable {
    public let direction: SearchLinkDirection
    public let anchorIdentity: String
    public let targetNote: VaultQualifiedNoteID
    public let occurrences: [SearchLinkOccurrence]

    public init(
        direction: SearchLinkDirection,
        anchorIdentity: String,
        targetNote: VaultQualifiedNoteID,
        occurrences: [SearchLinkOccurrence]
    ) {
        self.direction = direction
        self.anchorIdentity = anchorIdentity
        self.targetNote = targetNote
        self.occurrences = occurrences
    }
}

public struct SearchStructuredMatch: Codable, Hashable, Sendable {
    public let field: SearchStructuredField
    public let value: String
    public let excluded: Bool

    public init(
        field: SearchStructuredField,
        value: String,
        excluded: Bool
    ) {
        self.field = field
        self.value = value
        self.excluded = excluded
    }
}

public enum NoteSearchMatchReason: Codable, Hashable, Sendable {
    case lexical
    case structured(SearchStructuredMatch)
    case property(SearchPropertyMatch)
    case link(SearchLinkMatch)
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

public enum SearchResult: Codable, Hashable, Identifiable, Sendable {
    case note(NoteSearchResult)

    public var id: String {
        switch self { case .note(let result): result.resultID }
    }

    public var provider: SearchProvider {
        .note
    }

    public var freshnessToken: SearchFreshnessToken {
        switch self { case .note(let result): result.freshnessToken }
    }

    public var fingerprint: DocumentFingerprint {
        switch self { case .note(let result): result.fingerprint }
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
    public let publicationDate: String?
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
        stableNoteID: String? = nil,
        metadata: NoteMetadataSnapshot? = nil,
        metadataCatalog: NoteMetadataCatalog = .builtIn,
        semantic: MarkdownSemanticDocument? = nil,
        hasBrokenLink: Bool = false
    ) {
        self.init(
            vaultID: vaultID,
            vaultName: vaultName,
            vaultRole: vaultRole,
            document: document,
            stableNoteID: stableNoteID,
            metadata: metadata,
            metadataCatalog: metadataCatalog,
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
        stableNoteID: String? = nil,
        metadata: NoteMetadataSnapshot? = nil,
        metadataCatalog: NoteMetadataCatalog,
        semantic: MarkdownSemanticDocument,
        cachedSourceProjection: SearchDocumentProjection,
        hasBrokenLink: Bool = false
    ) {
        self.init(
            vaultID: vaultID,
            vaultName: vaultName,
            vaultRole: vaultRole,
            document: document,
            stableNoteID: stableNoteID,
            metadata: metadata,
            metadataCatalog: metadataCatalog,
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
        stableNoteID: String?,
        metadata: NoteMetadataSnapshot?,
        metadataCatalog: NoteMetadataCatalog,
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
        self.stableNoteID = stableNoteID
        let profile = WorkflowProfileResolver.resolve(vaultRole: vaultRole)
        title = ResearchNoteTitleResolver.resolve(
            document: document,
            vaultRole: vaultRole,
            metadata: metadata,
            semantic: self.semantic
        ).title
        aliases = profile == .topicMarkdown
            ? metadata?.record.fields["aliases"]?.canonicalStringList ?? []
            : []
        authors = profile == .analysis
            ? metadata?.record.fields["authors"]
                .flatMap(PropertyContractCatalog.creatorNames(from:))?
                .map(\.displayName) ?? []
            : []
        publicationDate = profile == .analysis
            ? metadata?.record.fields["publication_date"]?.canonicalSearchText
            : nil
        tags = PropertyContractCatalog.contract(for: "keywords", profile: profile) == nil
            ? []
            : document.parsedFrontmatter["keywords"]?.canonicalStringList ?? []
        self.hasBrokenLink = hasBrokenLink
        let sourceProjection = (cachedSourceProjection ?? SearchDocumentProjection(
            document: document,
            profile: profile,
            semantic: self.semantic
        )).applyingNoteMetadata(
            metadata,
            profile: profile,
            source: document.rawContent
        )
        projection = sourceProjection.applyingDynamicState(
            hasBrokenLink: hasBrokenLink
        )
        propertyProjection = SearchPropertyProjection(
            document: document,
            profile: profile,
            metadata: metadata,
            metadataCatalog: metadataCatalog
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

    var canonicalStringList: [String]? {
        guard case .array(let values) = self, !values.isEmpty else { return nil }
        let strings = values.compactMap { value -> String? in
            guard case .string(let string) = value,
                  !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  string.unicodeScalars.allSatisfy({
                      !CharacterSet.controlCharacters.contains($0)
                  }) else { return nil }
            return string
        }
        return strings.count == values.count ? strings : nil
    }

    var canonicalSearchText: String? {
        guard case .string(let value) = self,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.unicodeScalars.allSatisfy({ scalar in
                  scalar != "\n" && scalar != "\r"
                      && !CharacterSet.controlCharacters.contains(scalar)
              }) else { return nil }
        return value
    }
}
