import Foundation

public enum SearchProviderSelection: String, Codable, CaseIterable, Hashable, Sendable {
    case all
    case notes
    case records

    public var providers: Set<SearchProvider> {
        switch self {
        case .all: [.note, .record]
        case .notes: [.note]
        case .records: [.record]
        }
    }
}

public enum RecordSearchField: String, Codable, CaseIterable, Hashable, Sendable {
    case question
    case step
}

public struct RecordSearchClause: Codable, Hashable, Sendable {
    public let field: RecordSearchField?
    public let value: SearchLexicalValue
    public let excluded: Bool
    public let sourceRange: Range<Int>

    public init(
        field: RecordSearchField?,
        value: SearchLexicalValue,
        excluded: Bool,
        sourceRange: Range<Int>
    ) {
        self.field = field
        self.value = value
        self.excluded = excluded
        self.sourceRange = sourceRange
    }
}

public struct RecordSearchQueryAST: Codable, Hashable, Sendable {
    public let providerWasExplicit: Bool
    public let clauses: [RecordSearchClause]

    public init(providerWasExplicit: Bool, clauses: [RecordSearchClause]) {
        self.providerWasExplicit = providerWasExplicit
        self.clauses = clauses
    }
}

public struct RecordSearchQueryParseResult: Codable, Hashable, Sendable {
    public let providerWasExplicit: Bool
    public let ast: RecordSearchQueryAST?
    public let diagnostics: [SearchQueryDiagnostic]

    public init(
        providerWasExplicit: Bool,
        ast: RecordSearchQueryAST?,
        diagnostics: [SearchQueryDiagnostic]
    ) {
        self.providerWasExplicit = providerWasExplicit
        self.ast = ast
        self.diagnostics = diagnostics
    }
}

public enum RecordSearchMatchedField: String, Codable, Hashable, Sendable {
    case question
    case step
}

public enum RecordSearchRankReason: String, Codable, Hashable, Sendable {
    case exactQuestion = "exact_question"
    case questionPrefix = "question_prefix"
    case questionLexical = "question_lexical"
    case stepLexical = "step_lexical"
}

public struct RecordSearchResult: Codable, Hashable, Identifiable, Sendable {
    public let recordID: UUID
    public let question: String
    public let lastSubstantiveAt: Date
    public let matchedField: RecordSearchMatchedField
    public let matchedStepID: UUID?
    public let rankReason: RecordSearchRankReason
    public let snippet: String
    public let fingerprint: DocumentFingerprint

    public var id: UUID { recordID }

    public init(
        recordID: UUID,
        question: String,
        lastSubstantiveAt: Date,
        matchedField: RecordSearchMatchedField,
        matchedStepID: UUID?,
        rankReason: RecordSearchRankReason,
        snippet: String,
        fingerprint: DocumentFingerprint
    ) {
        self.recordID = recordID
        self.question = question
        self.lastSubstantiveAt = lastSubstantiveAt
        self.matchedField = matchedField
        self.matchedStepID = matchedStepID
        self.rankReason = rankReason
        self.snippet = snippet
        self.fingerprint = fingerprint
    }
}

public struct RecordSearchGenerationID: Codable, Hashable, Sendable {
    public let triptychID: UUID
    public let sequence: Int
    public let sourceManifestHash: String
    public let recordCount: Int

    public init(
        triptychID: UUID,
        sequence: Int,
        sourceManifestHash: String,
        recordCount: Int
    ) {
        self.triptychID = triptychID
        self.sequence = sequence
        self.sourceManifestHash = sourceManifestHash
        self.recordCount = recordCount
    }
}

public struct RecordSearchResponse: Hashable, Sendable {
    public let requestID: UUID
    public let scope: SearchPresentationScope
    public let generation: RecordSearchGenerationID
    public let offset: Int
    public let limit: Int
    public let results: [RecordSearchResult]
    public let hasMore: Bool
    public let totalResultCount: Int
    public let diagnostics: [SearchQueryDiagnostic]
    public let isolatedIssues: [ResearchRecordStoreIssue]

    public init(
        requestID: UUID,
        scope: SearchPresentationScope,
        generation: RecordSearchGenerationID,
        offset: Int,
        limit: Int,
        results: [RecordSearchResult],
        hasMore: Bool,
        totalResultCount: Int,
        diagnostics: [SearchQueryDiagnostic] = [],
        isolatedIssues: [ResearchRecordStoreIssue] = []
    ) {
        self.requestID = requestID
        self.scope = scope
        self.generation = generation
        self.offset = offset
        self.limit = limit
        self.results = results
        self.hasMore = hasMore
        self.totalResultCount = totalResultCount
        self.diagnostics = diagnostics
        self.isolatedIssues = isolatedIssues
    }
}

public struct UnifiedSearchRequest: Hashable, Sendable {
    public let id: UUID
    public let query: String
    public let providerSelection: SearchProviderSelection
    public let presentationScope: SearchPresentationScope
    public let executionScope: SearchExecutionScope
    public let noteLimit: Int
    public let noteOffset: Int
    public let recordLimit: Int
    public let recordOffset: Int
    public let includedVaultIDs: Set<UUID>?

    public init(
        id: UUID = UUID(),
        query: String,
        providerSelection: SearchProviderSelection = .all,
        presentationScope: SearchPresentationScope,
        executionScope: SearchExecutionScope,
        noteLimit: Int,
        noteOffset: Int = 0,
        recordLimit: Int,
        recordOffset: Int = 0,
        includedVaultIDs: Set<UUID>? = nil
    ) {
        self.id = id
        self.query = query
        self.providerSelection = providerSelection
        self.presentationScope = presentationScope
        self.executionScope = executionScope
        self.noteLimit = noteLimit
        self.noteOffset = max(0, noteOffset)
        self.recordLimit = recordLimit
        self.recordOffset = max(0, recordOffset)
        self.includedVaultIDs = includedVaultIDs
    }
}

public struct UnifiedSearchResponse: Hashable, Sendable {
    public let requestID: UUID
    public let providerSelection: SearchProviderSelection
    public let notes: SearchResponse?
    public let records: RecordSearchResponse?

    public init(
        requestID: UUID,
        providerSelection: SearchProviderSelection,
        notes: SearchResponse?,
        records: RecordSearchResponse?
    ) {
        self.requestID = requestID
        self.providerSelection = providerSelection
        self.notes = notes
        self.records = records
    }
}
