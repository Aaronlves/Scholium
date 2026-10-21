import CryptoKit
import Dispatch
import Foundation
import ScholiumContracts

/// Query-independent retrieval material only. The current Note must be loaded
/// and fingerprint-checked before this material is used. Exact passage source
/// is always sliced from that current Note; it is never retained here.
struct RelatedContentSourceProjection: Codable, Sendable {
    struct Paragraph: Codable, Sendable {
        let range: SearchSourceRange
        let displayText: String
        let exactReadableText: String
        let normalizedDisplayText: String
        let textIndex: RelatedContentTextIndex
        let scoringDocument: RelatedContentBM25F.Document

        private enum CodingKeys: String, CodingKey { case range, displayText, matchingText, scoringDocument }

        init(
            range: SearchSourceRange, displayText: String, normalizedDisplayText: String,
            textIndex: RelatedContentTextIndex, scoringDocument: RelatedContentBM25F.Document
        ) {
            let shared = scoringDocument.sharingPreparedText(normalizedDisplayText, index: textIndex)
            self.range = range
            self.displayText = displayText.utf8.elementsEqual(shared.text.utf8) ? shared.text : displayText
            let exact = RelatedContentRecommendationPolicy.TextSignature.exact(in: self.displayText)
            exactReadableText = exact.utf8.elementsEqual(self.displayText.utf8) ? self.displayText : exact
            self.normalizedDisplayText = shared.text
            self.textIndex = shared.index
            self.scoringDocument = scoringDocument
        }

        struct Stored: Decodable {
            let range: SearchSourceRange
            let displayText: String?
            let matchingText: RelatedContentBM25F.Document.StoredText
            let scoringDocument: RelatedContentBM25F.Document.Stored
        }

        /// One passage's fields are checked and released before the next is
        /// decoded. Only the endpoint is needed for the enclosing source bound.
        struct Admission: Decodable {
            let sourceUpperBound: Int

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let range = try container.decode(SearchSourceRange.self, forKey: .range)
                _ = try container.decodeIfPresent(String.self, forKey: .displayText)
                let scoring = try container.decode(RelatedContentBM25F.Document.Admission.self, forKey: .scoringDocument)
                let matching = try container.decode(RelatedContentBM25F.Document.StoredText.Admission.self, forKey: .matchingText)
                try matching.validate(in: scoring)
                guard RelatedContentSourceProjection.validRange(range, sourceUTF16Count: Int.max) else {
                    throw SearchIndexError.corruptDatabase
                }
                sourceUpperBound = range.utf16UpperBound
            }
        }

        init(from decoder: any Decoder) throws {
            try self.init(stored: Stored(from: decoder))
        }

        init(stored: Stored) throws {
            scoringDocument = try .init(stored: stored.scoringDocument)
            let matching = try stored.matchingText.resolve(in: scoringDocument)
            range = stored.range
            displayText = stored.displayText ?? matching.text
            let exact = RelatedContentRecommendationPolicy.TextSignature.exact(in: displayText)
            exactReadableText = exact.utf8.elementsEqual(displayText.utf8) ? displayText : exact
            normalizedDisplayText = matching.text
            textIndex = matching.index
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(range, forKey: .range)
            if !displayText.utf8.elementsEqual(normalizedDisplayText.utf8) {
                try container.encode(displayText, forKey: .displayText)
            }
            try container.encode(scoringDocument, forKey: .scoringDocument)
            try container.encode(scoringDocument.storedText(normalizedDisplayText, index: textIndex), forKey: .matchingText)
        }
    }

    let noteScoringDocument: RelatedContentBM25F.Document
    let paragraphs: [Paragraph]

    private struct Admission: Decodable {
        let maximumParagraphEnd: Int?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            _ = try container.decode(RelatedContentBM25F.Document.Admission.self, forKey: .noteScoringDocument)
            var paragraphs = try container.nestedUnkeyedContainer(forKey: .paragraphs)
            var maximumEnd: Int?
            while !paragraphs.isAtEnd {
                let paragraph = try paragraphs.decode(Paragraph.Admission.self)
                maximumEnd = max(maximumEnd ?? paragraph.sourceUpperBound, paragraph.sourceUpperBound)
            }
            maximumParagraphEnd = maximumEnd
        }
    }

    private enum CodingKeys: String, CodingKey { case noteScoringDocument, paragraphs }

    init(from decoder: any Decoder) throws {
        // Materialize one passage at a time for queries, releasing each
        // decoded word dictionary before moving to the next passage.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        noteScoringDocument = try container.decode(RelatedContentBM25F.Document.self, forKey: .noteScoringDocument)
        paragraphs = try container.decode([Paragraph].self, forKey: .paragraphs)
    }

    init(document: NoteDocument) throws {
        try Task.checkCancellation()
        let semantic = MarkdownSemanticDocument(parsing: document)
        try Task.checkCancellation()
        let segments = SearchDocumentProjection.sourceSegments(document: document, semantic: semantic)
        try self.init(document: document, semantic: semantic, noteSegments: segments)
    }

    /// Publication already prepared source-bound text and coordinates. Note
    /// scoring shares those segments; Research's nested passage comparison set
    /// still comes from the exact source and its complete semantic traversal.
    init(prepared: PreparedSearchIndexDocument) throws {
        try Task.checkCancellation()
        try self.init(
            document: prepared.source.document, semantic: prepared.source.semantic,
            noteSegments: prepared.projection.segments)
    }

    private init(document: NoteDocument, semantic: MarkdownSemanticDocument, noteSegments: [SearchTextSegment]) throws {
        noteScoringDocument = .init(segments: noteSegments)
        var paragraphs: [Paragraph] = []
        // Deliberately preserve the existing passage comparison set, including
        // nested paragraphs. Search's top-level paragraph query projection has
        // different coverage, attribution and annotation range semantics.
        for block in semantic.blocks where block.kind == .paragraph {
            try Task.checkCancellation()
            guard block.span.utf16Range.count <= RelatedContentContract.maximumPassageUTF16Count,
                let sourceRange = Range(block.span.nsRange, in: document.rawContent)
            else { continue }
            let exact = String(document.rawContent[sourceRange])
            let snippet = NoteDocument(relativePath: document.relativePath, rawContent: exact)
            let preparedSnippet = SearchDocumentProjection.preparePassageRanking(document: snippet)
            let displayText = ResearchExcerptPresentation.readableText(
                document: snippet, semantic: preparedSnippet.semantic, includingAnnotations: true)
            let normalizedDisplayText = SearchTextNormalization.lexicalNormalize(displayText)
            try Task.checkCancellation()
            paragraphs.append(
                .init(
                    range: .init(
                        utf16LowerBound: block.span.utf16LowerBound,
                        utf16UpperBound: block.span.utf16UpperBound,
                        line: block.span.start.line,
                        column: block.span.start.utf16Column,
                        endLine: block.span.end.line,
                        endColumn: block.span.end.utf16Column),
                    displayText: displayText,
                    normalizedDisplayText: normalizedDisplayText,
                    textIndex: .init(normalizedDisplayText),
                    scoringDocument: .init(rankingText: preparedSnippet.rankingText)))
        }
        try Task.checkCancellation()
        self.paragraphs = paragraphs
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func checksum(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func decode(_ data: Data?, checksum: String?, sourceUTF16Count: Int) throws -> Self {
        let value: Self = try decodedStorage(Self.self, data: data, checksum: checksum)
        // Packed words have already been admitted by the query decoder.
        guard value.noteScoringDocument.isValid,
            value.paragraphs.allSatisfy({ validRange($0.range, sourceUTF16Count: sourceUTF16Count) && $0.scoringDocument.isValid })
        else { throw SearchIndexError.corruptDatabase }
        return value
    }

    private static func validRange(_ range: SearchSourceRange, sourceUTF16Count: Int) -> Bool {
        SearchProjectionValidation.valid(paragraphRange: range, sourceUTF16Count: sourceUTF16Count)
            && range.utf16UpperBound - range.utf16LowerBound <= RelatedContentContract.maximumPassageUTF16Count
    }

    private static func decodedStorage<Value: Decodable>(_ type: Value.Type, data: Data?, checksum: String?) throws -> Value {
        guard let data, let checksum, checksum == Self.checksum(data) else { throw SearchIndexError.corruptDatabase }
        do { return try JSONDecoder().decode(type, from: data) } catch { throw SearchIndexError.corruptDatabase }
    }

    /// Opening checks every persisted field without constructing passage
    /// signatures or packed word tables that only a retrieval query consumes.
    static func validate(_ data: Data?, checksum: String?, sourceUTF16Count: Int) throws {
        let value = try decodedStorage(Admission.self, data: data, checksum: checksum)
        // Each range already passed the same predicate with Int.max. Its one
        // remaining condition is upperBound <= this source's exact length.
        // No range means no bound check, preserving empty-payload acceptance.
        guard value.maximumParagraphEnd.map({ $0 <= sourceUTF16Count }) ?? true else {
            throw SearchIndexError.corruptDatabase
        }
    }

    /// Accounting budget, not a claim about exact allocator resident memory.
    /// Include retained UTF-8 strings and fixed container/object overhead. No
    /// raw Markdown, segment offset maps, query reasons or results are retained.
    var estimatedByteCount: Int {
        return 128 + noteScoringDocument.estimatedByteCount
            + paragraphs.reduce(0) {
                $0 + 144 + $1.displayText.utf8.count + $1.normalizedDisplayText.utf8.count
                    + ($1.exactReadableText.utf8.elementsEqual($1.displayText.utf8) ? 0 : $1.exactReadableText.utf8.count)
                    + $1.textIndex.estimatedByteCount
                    + $1.scoringDocument.estimatedByteCount
            }
    }
}

/// A value owned and mutated only by the TriptychSearchIndex actor. It is an
/// in-process disposable memo, never another source or authorization owner.
struct RelatedContentSourceProjectionMemo {
    struct Statistics: Equatable {
        var hits = 0
        var misses = 0
        var evictions = 0
        var oversizeSkips = 0
        var protectedAdmissionSkips = 0
        var rejectedSources = 0
        var preparationNanoseconds: UInt64 = 0
    }

    private struct Entry {
        let fingerprint: DocumentFingerprint
        let role: VaultRole
        let relativePathUTF8: Data
        let projection: RelatedContentSourceProjection
        let byteCount: Int
        var lastAccess: UInt64
    }

    /// Immutable protection for one complete scan, including a batched warmup. It owns no projections
    /// and never changes source eligibility or the result of a cache miss.
    struct ScanProtection: Sendable {
        fileprivate let notes: Set<VaultQualifiedNoteID>
        fileprivate let estimatedByteCount: Int

        static let none = Self(notes: [], estimatedByteCount: 0)
    }

    static let defaultMaximumByteCount = 64 * 1_024 * 1_024
    let maximumByteCount: Int
    private var entries: [VaultQualifiedNoteID: Entry] = [:]
    private var accessClock: UInt64 = 0
    private(set) var estimatedByteCount = 0
    private(set) var statistics = Statistics()
    var entryCount: Int { entries.count }

    init(maximumByteCount: Int = Self.defaultMaximumByteCount) {
        self.maximumByteCount = max(0, maximumByteCount)
    }

    func scanProtection(for sources: [RelatedContentSource]) -> ScanProtection {
        scanProtection(
            for: sources.lazy.compactMap { source -> RelatedContentCandidate? in
                guard source.document.fingerprint == source.candidate.fingerprint,
                    source.document.relativePath.utf8.elementsEqual(source.candidate.note.relativePath.utf8)
                else { return nil }
                return source.candidate
            })
    }

    /// Candidate metadata can protect an already resident revision before its
    /// fresh source is loaded. This never authorizes a projection hit: the
    /// source still passes the exact path/fingerprint checks in `projection`.
    func scanProtection(for candidates: some Sequence<RelatedContentCandidate>) -> ScanProtection {
        var notes = Set<VaultQualifiedNoteID>()
        var byteCount = 0
        for candidate in candidates {
            guard let entry = entries[candidate.note],
                entry.fingerprint == candidate.fingerprint,
                entry.role == candidate.vaultRole,
                entry.relativePathUTF8 == Data(candidate.note.relativePath.utf8),
                notes.insert(candidate.note).inserted
            else { continue }
            byteCount += entry.byteCount
        }
        return .init(notes: notes, estimatedByteCount: byteCount)
    }

    mutating func projection(
        for source: RelatedContentSource,
        protection: ScanProtection = .none,
        prepare: (NoteDocument) throws -> RelatedContentSourceProjection = { try .init(document: $0) }
    ) throws -> RelatedContentSourceProjection? {
        try Task.checkCancellation()
        let candidate = source.candidate
        let document = source.document
        let actualPath = Data(document.relativePath.utf8)
        // String equality canonicalizes Unicode. Bind the actual filesystem
        // relative-path bytes as well as the vault-qualified lookup identity.
        guard document.fingerprint == candidate.fingerprint,
            actualPath == Data(candidate.note.relativePath.utf8)
        else {
            statistics.rejectedSources += 1
            return nil
        }
        accessClock &+= 1
        if var entry = entries[candidate.note],
            entry.fingerprint == document.fingerprint,
            entry.role == candidate.vaultRole,
            entry.relativePathUTF8 == actualPath
        {
            entry.lastAccess = accessClock
            entries[candidate.note] = entry
            statistics.hits += 1
            return entry.projection
        }
        statistics.misses += 1
        // Latest revision only. An older revision is never left resident while
        // a replacement is oversized or preparation is cancelled.
        invalidate(note: candidate.note)
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            statistics.preparationNanoseconds &+= DispatchTime.now().uptimeNanoseconds - start
        }
        let projection = try prepare(document)
        let cost =
            projection.estimatedByteCount + 256 + actualPath.count
            + document.fingerprint.sha256.utf8.count
        guard cost <= maximumByteCount else {
            statistics.oversizeSkips += 1
            return projection
        }
        // A scan larger than the budget must not evict the reusable tail before
        // reaching it. Returning an uncached projection preserves full ranking.
        // Invalidation may leave this snapshot conservative; it never grants a
        // stale hit, and the next request creates a fresh protection snapshot.
        guard protection.estimatedByteCount <= maximumByteCount - cost else {
            statistics.protectedAdmissionSkips += 1
            return projection
        }
        while estimatedByteCount > maximumByteCount - cost {
            guard
                let victim = entries.lazy.filter({ !protection.notes.contains($0.key) }).min(by: { lhs, rhs in
                    if lhs.value.lastAccess != rhs.value.lastAccess {
                        return lhs.value.lastAccess < rhs.value.lastAccess
                    }
                    return lhs.key < rhs.key
                })?.key
            else {
                statistics.protectedAdmissionSkips += 1
                return projection
            }
            invalidate(note: victim)
            statistics.evictions += 1
        }
        entries[candidate.note] = .init(
            fingerprint: document.fingerprint,
            role: candidate.vaultRole,
            relativePathUTF8: actualPath,
            projection: projection,
            byteCount: cost,
            lastAccess: accessClock)
        estimatedByteCount += cost
        return projection
    }

    mutating func invalidate(note: VaultQualifiedNoteID) {
        if let removed = entries.removeValue(forKey: note) {
            estimatedByteCount -= removed.byteCount
        }
    }

    mutating func retainManifest(_ documents: [SearchIndexManifestEntry]) {
        let current = Dictionary(
            documents.map {
                (VaultQualifiedNoteID(vaultID: $0.vaultID, relativePath: $0.relativePath), $0.fingerprint)
            }, uniquingKeysWith: { first, _ in first })
        for (note, entry) in entries where current[note] != entry.fingerprint {
            invalidate(note: note)
        }
    }

}
