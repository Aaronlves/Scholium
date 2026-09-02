import CryptoKit
import Foundation
import ScholiumContracts

/// Disposable, provider-local projection over strict Research Record files.
/// It never writes Record authority and never shares ranking with Note Search.
public actor ResearchRecordSearchIndex {
    private let triptychID: UUID
    private let store: ResearchRecordStore
    private var sequence = 0
    private var lastManifestHash: String?

    public init(triptychID: UUID, store: ResearchRecordStore) {
        self.triptychID = triptychID
        self.store = store
    }

    public func search(
        requestID: UUID,
        query: String,
        scope: SearchPresentationScope,
        limit: Int,
        offset: Int,
        eligibleNoteIDs: Set<UUID>?
    ) async throws -> RecordSearchResponse {
        let listing = try await store.listing()
        let generation = generation(for: listing.records)
        let parsed = SearchQueryParser.parseRecord(query)
        guard let ast = parsed.ast, parsed.diagnostics.isEmpty else {
            return RecordSearchResponse(
                requestID: requestID,
                scope: scope,
                generation: generation,
                offset: max(0, offset),
                limit: max(0, limit),
                results: [],
                hasMore: false,
                totalResultCount: 0,
                diagnostics: parsed.diagnostics,
                isolatedIssues: listing.issues
            )
        }
        let boundedOffset = max(0, offset)
        let boundedLimit = min(max(1, limit), SearchContract.maximumCLIResults)
        let candidates = listing.records.compactMap { revision in
            candidate(
                revision,
                ast: ast,
                eligibleNoteIDs: eligibleNoteIDs
            )
        }.sorted(by: Candidate.precedes)
        let page = Array(candidates.dropFirst(boundedOffset).prefix(boundedLimit))
        return RecordSearchResponse(
            requestID: requestID,
            scope: scope,
            generation: generation,
            offset: boundedOffset,
            limit: boundedLimit,
            results: page.map(\.result),
            hasMore: boundedOffset + page.count < candidates.count,
            totalResultCount: candidates.count,
            isolatedIssues: listing.issues
        )
    }

    public func currentGeneration() async throws -> RecordSearchGenerationID {
        generation(for: try await store.listing().records)
    }

    private func generation(
        for records: [ResearchRecordRevision]
    ) -> RecordSearchGenerationID {
        let material = records.sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                "\($0.id.uuidString.lowercased())\u{1f}\($0.fingerprint.sha256)\u{1f}\($0.fingerprint.byteCount)"
            }
            .joined(separator: "\u{1e}")
        let manifestHash = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        if lastManifestHash != manifestHash {
            sequence += 1
            lastManifestHash = manifestHash
        }
        return RecordSearchGenerationID(
            triptychID: triptychID,
            sequence: sequence,
            sourceManifestHash: manifestHash,
            recordCount: records.count
        )
    }

    private func candidate(
        _ revision: ResearchRecordRevision,
        ast: RecordSearchQueryAST,
        eligibleNoteIDs: Set<UUID>?
    ) -> Candidate? {
        let record = revision.record
        if let eligibleNoteIDs {
            let referenced = Set(record.steps.flatMap { step in
                step.currentNoteReferences.map(\.noteID)
            })
            guard !referenced.isDisjoint(with: eligibleNoteIDs) else { return nil }
        }
        let question = SearchTextNormalization.lexicalNormalize(record.question)
        let steps = record.steps.map { step in
            (step, SearchTextNormalization.lexicalNormalize(step.currentBodyMarkdown))
        }
        guard ast.clauses.allSatisfy({ clause in
            let matched = matches(clause, question: question, steps: steps)
            return clause.excluded ? !matched : matched
        }) else { return nil }

        let positives = ast.clauses.filter { !$0.excluded }
        let questionMatches = positives.filter {
            $0.field != .step && Self.matches($0.value, in: question)
        }
        let exact = questionMatches.contains {
            switch $0.value {
            case .term(let value), .phrase(let value): question == value
            case .prefix: false
            }
        }
        let prefix = questionMatches.contains {
            if case .prefix(let value) = $0.value {
                return Self.hasTokenPrefix(value, in: question)
            }
            return false
        }
        let matchedStep = steps.first { pair in
            positives.contains { clause in
                clause.field != .question && Self.matches(clause.value, in: pair.1)
            }
        }?.0
        let field: RecordSearchMatchedField = questionMatches.isEmpty ? .step : .question
        let reason: RecordSearchRankReason
        if exact { reason = .exactQuestion }
        else if prefix { reason = .questionPrefix }
        else if !questionMatches.isEmpty { reason = .questionLexical }
        else { reason = .stepLexical }
        let source = field == .question
            ? record.question
            : (matchedStep?.currentBodyMarkdown ?? record.question)
        return Candidate(result: RecordSearchResult(
            recordID: record.id,
            question: record.question,
            lastSubstantiveAt: record.lastSubstantiveAt,
            matchedField: field,
            matchedStepID: field == .step ? matchedStep?.id : nil,
            rankReason: reason,
            snippet: Self.snippet(source),
            fingerprint: revision.fingerprint
        ))
    }

    private func matches(
        _ clause: RecordSearchClause,
        question: String,
        steps: [(ResearchRecordStep, String)]
    ) -> Bool {
        switch clause.field {
        case .question:
            Self.matches(clause.value, in: question)
        case .step:
            steps.contains { Self.matches(clause.value, in: $0.1) }
        case nil:
            Self.matches(clause.value, in: question)
                || steps.contains { Self.matches(clause.value, in: $0.1) }
        }
    }

    private static func matches(_ value: SearchLexicalValue, in corpus: String) -> Bool {
        let needle = SearchTextNormalization.lexicalNormalize(value.text)
        return switch value {
        case .term, .phrase:
            corpus.contains(needle)
        case .prefix:
            hasTokenPrefix(needle, in: corpus)
        }
    }

    private static func hasTokenPrefix(_ prefix: String, in corpus: String) -> Bool {
        corpus.split { !$0.isLetter && !$0.isNumber }.contains {
            $0.hasPrefix(prefix)
        }
    }

    private static func snippet(_ value: String) -> String {
        let collapsed = value.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard collapsed.count > 320 else { return collapsed }
        return String(collapsed.prefix(319)) + "…"
    }

    private struct Candidate {
        let result: RecordSearchResult

        static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
            let lhsRank = rank(lhs.result.rankReason)
            let rhsRank = rank(rhs.result.rankReason)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.result.lastSubstantiveAt != rhs.result.lastSubstantiveAt {
                return lhs.result.lastSubstantiveAt > rhs.result.lastSubstantiveAt
            }
            let questionOrder = lhs.result.question.localizedStandardCompare(
                rhs.result.question
            )
            if questionOrder != .orderedSame { return questionOrder == .orderedAscending }
            return lhs.result.recordID.uuidString < rhs.result.recordID.uuidString
        }

        private static func rank(_ reason: RecordSearchRankReason) -> Int {
            switch reason {
            case .exactQuestion: 0
            case .questionPrefix: 1
            case .questionLexical: 2
            case .stepLexical: 3
            }
        }
    }
}
