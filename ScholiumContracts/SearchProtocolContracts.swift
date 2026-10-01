import CryptoKit
import Foundation

/// Stable versions that make a Search generation reproducible and prevent a
/// saved query or derived database from silently acquiring new semantics.
public enum SearchContract {
    public static let maximumNoteResults = 500
    public static let currentVersion = 20
    public static let schemaVersion = 24
    public static let tokenizerPolicyVersion = 2
    public static let rankingPolicyVersion = 5
    public static let maximumInterfaceResults = 100
    public static let maximumQueryUTF16Count = 16_384
    public static let maximumQueryTokenCount = 64
    public static let maximumQueryGroupDepth = 8
    public static let maximumCompletionTerms = 32

}

public struct SearchSourceManifestEntry: Codable, Hashable, Sendable {
    public let vaultID: UUID
    public let relativePath: String
    public let fingerprint: DocumentFingerprint

    public init(
        vaultID: UUID,
        relativePath: String,
        fingerprint: DocumentFingerprint
    ) {
        self.vaultID = vaultID
        self.relativePath = relativePath
        self.fingerprint = fingerprint
    }
}

public enum SearchSourceManifest {
    public static func hash(_ entries: [SearchSourceManifestEntry]) -> String {
        let material = entries.sorted {
            if $0.vaultID != $1.vaultID { return $0.vaultID.uuidString < $1.vaultID.uuidString }
            return $0.relativePath < $1.relativePath
        }.map {
            "\($0.vaultID.uuidString.lowercased())\u{1F}\($0.relativePath)\u{1F}\($0.fingerprint.sha256)\u{1F}\($0.fingerprint.byteCount)"
        }.joined(separator: "\u{1E}")
        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// The sole durable declaration stored by a Saved Search.
public struct SearchDefinition: Codable, Hashable, Sendable {
    public let contractVersion = SearchContract.currentVersion
    public var query: String
    public var presentationScope: SearchPresentationScope

    public init(
        query: String,
        presentationScope: SearchPresentationScope
    ) {
        self.query = query
        self.presentationScope = presentationScope
    }

    private enum CodingKeys: String, CodingKey {
        case contractVersion
        case query
        case presentationScope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .contractVersion) == SearchContract.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .contractVersion, in: container,
                debugDescription: "Unsupported Saved Search format."
            )
        }
        query = try container.decode(String.self, forKey: .query)
        presentationScope = try container.decode(
            SearchPresentationScope.self,
            forKey: .presentationScope
        )
    }
}

/// Exact, nonpersisted editor authority used only by This Note Search.
public struct SearchSourceSnapshot: Codable, Hashable, Sendable {
    public let noteID: VaultQualifiedNoteID
    public let stableNoteID: UUID?
    public let editorSessionID: UUID
    public let source: String
    public let editorRevision: UInt64

    public init(
        noteID: VaultQualifiedNoteID,
        stableNoteID: UUID? = nil,
        editorSessionID: UUID,
        source: String,
        editorRevision: UInt64
    ) {
        self.noteID = noteID
        self.stableNoteID = stableNoteID
        self.editorSessionID = editorSessionID
        self.source = source
        self.editorRevision = editorRevision
    }

    public var fingerprint: DocumentFingerprint {
        DocumentFingerprint(content: source)
    }
}

/// Resolved execution authority. Scope is never inferred from query text.
public enum SearchExecutionScope: Codable, Hashable, Sendable {
    case currentNote(SearchSourceSnapshot)
    case currentVault(UUID)
    case triptych
}

public struct SearchRequest: Codable, Hashable, Sendable {
    public let id: UUID
    public let query: String
    public let presentationScope: SearchPresentationScope
    public let executionScope: SearchExecutionScope
    public let limit: Int
    public let offset: Int?
    /// Optional App-authorized subset of the selected Triptych. This is used
    /// by Scholium MCP's explicit three-role scope; query text never changes
    /// it and the Search owner retains the one canonical ordering.
    public let includedVaultIDs: [UUID]?

    public init(
        id: UUID = UUID(),
        query: String,
        presentationScope: SearchPresentationScope,
        executionScope: SearchExecutionScope,
        limit: Int,
        offset: Int = 0,
        includedVaultIDs: Set<UUID>? = nil
    ) {
        self.id = id
        self.query = query
        self.presentationScope = presentationScope
        self.executionScope = executionScope
        self.limit = limit
        self.offset = offset > 0 ? offset : nil
        self.includedVaultIDs = includedVaultIDs.map {
            $0.sorted { $0.uuidString < $1.uuidString }
        }
    }

    public var resultOffset: Int { max(0, offset ?? 0) }

    public var hasConsistentScopes: Bool {
        switch (presentationScope, executionScope) {
        case (.thisNote, .currentNote),
            (.currentVault, .currentVault),
            (.triptych, .triptych):
            includedVaultIDs == nil
                || {
                    if case .triptych = executionScope { return true }
                    return false
                }()
        default:
            false
        }
    }
}

/// A bounded lookup for one visible lexical completion token. It carries the
/// same explicit scope boundary as Search but never stores a result or source
/// projection.
public struct SearchCompletionRequest: Codable, Hashable, Sendable {
    public let id: UUID
    public let lookup: SearchCompletionLookup
    public let presentationScope: SearchPresentationScope
    public let executionScope: SearchExecutionScope
    public let limit: Int

    public init(
        id: UUID = UUID(),
        lookup: SearchCompletionLookup,
        presentationScope: SearchPresentationScope,
        executionScope: SearchExecutionScope,
        limit: Int = 32
    ) {
        self.id = id
        self.lookup = lookup
        self.presentationScope = presentationScope
        self.executionScope = executionScope
        self.limit = max(0, min(limit, SearchContract.maximumCompletionTerms))
    }

    public var hasConsistentScopes: Bool {
        switch (presentationScope, executionScope) {
        case (.thisNote, .currentNote),
            (.currentVault, .currentVault),
            (.triptych, .triptych):
            true
        default:
            false
        }
    }
}

public struct SearchCompletionResponse: Codable, Hashable, Sendable {
    public let contractVersion: Int
    public let requestID: UUID
    public let scope: SearchPresentationScope
    public let freshnessToken: SearchFreshnessToken
    public let availability: SearchAvailability
    public let terms: [SearchCompletionTerm]

    public init(
        contractVersion: Int = SearchContract.currentVersion,
        requestID: UUID,
        scope: SearchPresentationScope,
        freshnessToken: SearchFreshnessToken,
        availability: SearchAvailability,
        terms: [SearchCompletionTerm]
    ) {
        self.contractVersion = contractVersion
        self.requestID = requestID
        self.scope = scope
        self.freshnessToken = freshnessToken
        self.availability = availability
        self.terms = terms
    }
}

public struct SearchGenerationID: Codable, Hashable, Sendable {
    public let triptychID: UUID
    public let sequence: Int
    public let schemaVersion: Int
    public let queryContractVersion: Int
    public let tokenizerPolicyVersion: Int
    public let rankingPolicyVersion: Int
    public let sourceManifestHash: String

    public init(
        triptychID: UUID,
        sequence: Int,
        schemaVersion: Int = SearchContract.schemaVersion,
        queryContractVersion: Int = SearchContract.currentVersion,
        tokenizerPolicyVersion: Int = SearchContract.tokenizerPolicyVersion,
        rankingPolicyVersion: Int = SearchContract.rankingPolicyVersion,
        sourceManifestHash: String
    ) {
        self.triptychID = triptychID
        self.sequence = sequence
        self.schemaVersion = schemaVersion
        self.queryContractVersion = queryContractVersion
        self.tokenizerPolicyVersion = tokenizerPolicyVersion
        self.rankingPolicyVersion = rankingPolicyVersion
        self.sourceManifestHash = sourceManifestHash
    }
}

public struct TriptychSearchIndexSyncResult: Codable, Hashable, Sendable {
    public let generation: SearchGenerationID
    public let disposition: SearchIndexSyncDisposition

    public init(
        generation: SearchGenerationID,
        disposition: SearchIndexSyncDisposition
    ) {
        self.generation = generation
        self.disposition = disposition
    }
}

public struct SearchFreshnessToken: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func currentNote(_ snapshot: SearchSourceSnapshot) -> Self {
        Self(
            "note:\(snapshot.editorSessionID.uuidString.lowercased()):\(snapshot.editorRevision):\(snapshot.fingerprint.sha256)"
        )
    }

    public static func triptych(_ generation: SearchGenerationID) -> Self {
        Self(
            "triptych:\(generation.triptychID.uuidString.lowercased()):\(generation.sequence):\(generation.sourceManifestHash)"
        )
    }

}

public struct SearchBuildProgress: Codable, Hashable, Sendable {
    public let completed: Int
    public let total: Int

    public init(completed: Int, total: Int) {
        self.completed = max(0, completed)
        self.total = max(0, total)
    }

    public var fraction: Double? {
        guard total > 0 else { return nil }
        return min(1, Double(completed) / Double(total))
    }
}

public enum SearchAvailability: Codable, Hashable, Sendable {
    case unavailable
    case building(SearchBuildProgress)
    case current(SearchGenerationID)
    /// A source-validated subset from the last complete compatible index is
    /// usable while the wider authoritative workspace is still opening.
    case limited(lastGood: SearchGenerationID)
    case refreshing(lastGood: SearchGenerationID)
    case stale(lastGood: SearchGenerationID, reason: String)
    case failed(lastGood: SearchGenerationID?, reason: String)

    public var lastGoodGeneration: SearchGenerationID? {
        switch self {
        case .current(let generation): generation
        case .limited(let generation): generation
        case .refreshing(let generation): generation
        case .stale(let generation, _): generation
        case .failed(let generation, _): generation
        case .unavailable, .building: nil
        }
    }
}

public enum SearchQueryDiagnosticCode: String, Codable, Hashable, Sendable {
    case emptyClause
    case unclosedPhrase
    case invalidEscape
    case invalidPrefix
    case cjkPrefixUnsupported
    case unknownField
    case unsupportedField
    case unsupportedScopeSelector
    case duplicateClause
    case missingCompanion
    case ambiguousIdentity
    case notApplicable
    case missingFieldValue
    case unknownStructuredValue
    case unsupportedSyntax
}

/// App presentation consumes this semantic reason and its literal parameters.
/// The protocol message remains a separate, untranslated diagnostic record.
public enum SearchQueryDiagnosticReason: Codable, Hashable, Sendable {
    case queryTooLong(limit: Int)
    case tooManyTokens(limit: Int)
    case misplacedProvider
    case unexpectedOperator, conditionSeparatorRequired, conditionRequired
    case paragraphRequiresPositiveText, fieldGroupUnsupported, inheritedFieldOverride
    case groupDepthExceeded(limit: Int)
    case unclosedGroup
    case duplicateProvider, providerValueRequired, unknownProvider
    case missingFieldValue(field: String)
    case unsupportedField(field: String)
    case unknownField(field: String)
    case emptyClause, prefixUnsupported, cjkPrefixUnsupported, prefixTooShort
    case structuredValueSyntax
    case unknownStructuredValue(field: SearchStructuredField, value: String)
    case invalidPropertyKey, propertyValueRequired, propertyPrefixUnsupported, emptyPropertyValue
    case linkPrefixUnsupported, emptyLinkIdentity, phrasePrefixUnsupported, unclosedPhrase
    case invalidPhraseEscape, trailingPhraseEscape, partialQuotedValue, invalidPrefixPlacement
    case operatorTextRequiresQuotes, unsupportedPatternSyntax, scopeSelectorInQuery
    case currentNoteRequiresPositiveText, directLinksUnavailableForCurrentNote
    case missingLinkIdentity(identity: String)
    case ambiguousLinkIdentity(identity: String, candidates: [String])
    case linkGraphNotCurrent, openingVaultLexicalOnly, inconsistentScopes, invalidVaultSubset
    case vaultOutsideTriptych, openingVaultUnavailable, noteOutsideTriptych

    public var code: SearchQueryDiagnosticCode {
        switch self {
        case .emptyClause, .emptyPropertyValue, .emptyLinkIdentity: .emptyClause
        case .unclosedPhrase: .unclosedPhrase
        case .invalidPhraseEscape, .trailingPhraseEscape: .invalidEscape
        case .prefixTooShort, .phrasePrefixUnsupported, .invalidPrefixPlacement: .invalidPrefix
        case .cjkPrefixUnsupported: .cjkPrefixUnsupported
        case .unknownField: .unknownField
        case .unsupportedField: .unsupportedField
        case .scopeSelectorInQuery: .unsupportedScopeSelector
        case .duplicateProvider: .duplicateClause
        case .ambiguousLinkIdentity: .ambiguousIdentity
        case .currentNoteRequiresPositiveText, .directLinksUnavailableForCurrentNote,
            .missingLinkIdentity, .linkGraphNotCurrent, .openingVaultLexicalOnly,
            .inconsistentScopes, .invalidVaultSubset, .vaultOutsideTriptych,
            .openingVaultUnavailable, .noteOutsideTriptych:
            .notApplicable
        case .providerValueRequired, .missingFieldValue, .propertyValueRequired: .missingFieldValue
        case .unknownProvider, .unknownStructuredValue: .unknownStructuredValue
        case .queryTooLong, .tooManyTokens, .misplacedProvider, .unexpectedOperator,
            .conditionSeparatorRequired, .conditionRequired, .paragraphRequiresPositiveText,
            .fieldGroupUnsupported, .inheritedFieldOverride, .groupDepthExceeded,
            .unclosedGroup, .prefixUnsupported, .structuredValueSyntax, .invalidPropertyKey,
            .propertyPrefixUnsupported, .linkPrefixUnsupported, .partialQuotedValue,
            .operatorTextRequiresQuotes, .unsupportedPatternSyntax:
            .unsupportedSyntax
        }
    }
}

public struct SearchQueryDiagnostic: Error, Codable, Hashable, Sendable {
    public let reason: SearchQueryDiagnosticReason
    public var code: SearchQueryDiagnosticCode { reason.code }
    public let message: String
    public let utf16LowerBound: Int
    public let utf16UpperBound: Int

    public init(
        reason: SearchQueryDiagnosticReason,
        message: String,
        utf16LowerBound: Int,
        utf16UpperBound: Int
    ) {
        self.reason = reason
        self.message = message
        self.utf16LowerBound = utf16LowerBound
        self.utf16UpperBound = utf16UpperBound
    }

    private enum CodingKeys: String, CodingKey {
        case reason, code, message, utf16LowerBound, utf16UpperBound
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        reason = try values.decode(SearchQueryDiagnosticReason.self, forKey: .reason)
        guard try values.decode(SearchQueryDiagnosticCode.self, forKey: .code) == reason.code else {
            throw DecodingError.dataCorruptedError(
                forKey: .code, in: values, debugDescription: "Search diagnostic code does not match its reason.")
        }
        message = try values.decode(String.self, forKey: .message)
        utf16LowerBound = try values.decode(Int.self, forKey: .utf16LowerBound)
        utf16UpperBound = try values.decode(Int.self, forKey: .utf16UpperBound)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(reason, forKey: .reason)
        try values.encode(code, forKey: .code)
        try values.encode(message, forKey: .message)
        try values.encode(utf16LowerBound, forKey: .utf16LowerBound)
        try values.encode(utf16UpperBound, forKey: .utf16UpperBound)
    }
}

public enum SearchRankReason: String, Codable, Hashable, Sendable {
    case exactTitle = "exact_title"
    case exactAlias = "exact_alias"
    case exactFilename = "exact_filename"
    case exactPath = "exact_path"
    case lexicalRelevance = "lexical_relevance"
    case structuredFilter = "structured_filter"
}

public struct SearchSourceRange: Codable, Hashable, Sendable {
    public let utf16LowerBound: Int
    public let utf16UpperBound: Int
    public let line: Int
    public let column: Int
    public let endLine: Int
    public let endColumn: Int

    public init(
        utf16LowerBound: Int,
        utf16UpperBound: Int,
        line: Int,
        column: Int,
        endLine: Int,
        endColumn: Int
    ) {
        self.utf16LowerBound = utf16LowerBound
        self.utf16UpperBound = utf16UpperBound
        self.line = line
        self.column = column
        self.endLine = endLine
        self.endColumn = endColumn
    }
}

public struct SearchResponse: Codable, Hashable, Sendable {
    public let contractVersion: Int
    public let requestID: UUID
    public let scope: SearchPresentationScope
    public let explanation: SearchExplanation
    public let freshnessToken: SearchFreshnessToken
    public let availability: SearchAvailability
    public let results: [SearchResult]
    public let hasMore: Bool
    public let totalResultCount: Int?
    public let indeterminateDocumentCount: Int
    public let diagnostics: [SearchQueryDiagnostic]

    public init(
        contractVersion: Int = SearchContract.currentVersion,
        requestID: UUID,
        scope: SearchPresentationScope,
        explanation: SearchExplanation,
        freshnessToken: SearchFreshnessToken,
        availability: SearchAvailability,
        results: [SearchResult],
        hasMore: Bool,
        totalResultCount: Int? = nil,
        indeterminateDocumentCount: Int = 0,
        diagnostics: [SearchQueryDiagnostic] = []
    ) {
        self.contractVersion = contractVersion
        self.requestID = requestID
        self.scope = scope
        self.explanation = explanation
        self.freshnessToken = freshnessToken
        self.availability = availability
        self.results = results
        self.hasMore = hasMore
        self.totalResultCount = totalResultCount
        self.indeterminateDocumentCount = indeterminateDocumentCount
        self.diagnostics = diagnostics
    }

    public var provider: SearchProvider { .note }
}
