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
        let normalizedDisplayText: String
        let textIndex: RelatedContentTextIndex
        let scoringDocument: RelatedContentBM25F.Document
    }

    let noteScoringDocument: RelatedContentBM25F.Document
    let paragraphs: [Paragraph]

    init(document: NoteDocument) throws {
        try Task.checkCancellation()
        let semantic = MarkdownSemanticDocument(parsing: document)
        try Task.checkCancellation()
        let projection = SearchDocumentProjection(document: document, semantic: semantic)
        noteScoringDocument = .init(segments: projection.segments)
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
            let displayText = ResearchExcerptPresentation.readableText(exact, includingAnnotations: true)
            try Task.checkCancellation()
            let segments = SearchDocumentProjection(document: snippet).segments.filter {
                $0.sourceRange != nil && $0.field != .title && $0.field != .alias
            }
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
                    normalizedDisplayText: SearchTextNormalization.lexicalNormalize(displayText),
                    textIndex: .init(SearchTextNormalization.lexicalNormalize(displayText)),
                    scoringDocument: .init(segments: segments)))
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
        guard let data, let checksum, checksum == Self.checksum(data) else {
            throw SearchIndexError.corruptDatabase
        }
        let value: Self
        do { value = try JSONDecoder().decode(Self.self, from: data) } catch { throw SearchIndexError.corruptDatabase }
        guard value.noteScoringDocument.isValid,
            value.paragraphs.allSatisfy({ paragraph in
                SearchProjectionValidation.valid(paragraphRange: paragraph.range, sourceUTF16Count: sourceUTF16Count)
                    && paragraph.range.utf16UpperBound - paragraph.range.utf16LowerBound <= RelatedContentContract.maximumPassageUTF16Count
                    && paragraph.scoringDocument.isValid
                    && paragraph.textIndex.isValid
            })
        else { throw SearchIndexError.corruptDatabase }
        return value
    }

    /// Accounting budget, not a claim about exact allocator resident memory.
    /// Include retained UTF-8 strings and fixed container/object overhead. No
    /// raw Markdown, segment offset maps, query reasons or results are retained.
    var estimatedByteCount: Int {
        return 128 + noteScoringDocument.estimatedByteCount
            + paragraphs.reduce(0) {
                $0 + 128 + $1.displayText.utf8.count + $1.normalizedDisplayText.utf8.count
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

    /// Immutable protection for one synchronous scan. It owns no projections
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
        var notes = Set<VaultQualifiedNoteID>()
        var byteCount = 0
        for source in sources {
            let candidate = source.candidate
            let document = source.document
            guard let entry = entries[candidate.note],
                entry.fingerprint == document.fingerprint,
                document.fingerprint == candidate.fingerprint,
                entry.role == candidate.vaultRole,
                entry.relativePathUTF8 == Data(document.relativePath.utf8),
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

    mutating func retain(_ documents: [SearchIndexDocument]) {
        let current = Dictionary(
            documents.map {
                (VaultQualifiedNoteID(vaultID: $0.vaultID, relativePath: $0.relativePath), $0.document.fingerprint)
            }, uniquingKeysWith: { first, _ in first })
        for (note, entry) in entries where current[note] != entry.fingerprint {
            invalidate(note: note)
        }
    }

}
