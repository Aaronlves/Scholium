import Foundation
import ScholiumContracts

/// Small, query-independent Note-level material. Kept separate from paragraph
/// preparation so candidate retrieval need not decode every paragraph or retokenize
/// source fields. Both projections publish with the same document fingerprint.
struct RelatedContentLexicalProjection: Codable, Sendable {
    struct Segment: Codable, Sendable {
        let field: SearchMatchedField
        let text: String
        let index: RelatedContentTextIndex
    }

    let scoringDocument: RelatedContentBM25F.Document
    let segments: [Segment]

    private struct StoredSegment: Codable {
        let field: SearchMatchedField
        let material: RelatedContentBM25F.Document.StoredText
    }

    private enum CodingKeys: String, CodingKey { case scoringDocument, segments }

    init(projection: SearchDocumentProjection) {
        let scoring = RelatedContentBM25F.Document(segments: projection.segments)
        scoringDocument = scoring
        segments = projection.segments.map {
            let shared = scoring.sharingPreparedText($0.normalizedText, index: .init($0.normalizedText))
            return .init(field: $0.field, text: shared.text, index: shared.index)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let scoring = try container.decode(RelatedContentBM25F.Document.self, forKey: .scoringDocument)
        scoringDocument = scoring
        segments = try container.decode([StoredSegment].self, forKey: .segments).map {
            let shared = try $0.material.resolve(in: scoring)
            return .init(field: $0.field, text: shared.text, index: shared.index)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scoringDocument, forKey: .scoringDocument)
        try container.encode(
            segments.map { StoredSegment(field: $0.field, material: scoringDocument.storedText($0.text, index: $0.index)) },
            forKey: .segments)
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    /// Conservative accounting for scoring and matcher material. Shared storage
    /// stays counted twice, preserving the existing cache admission budget.
    var estimatedByteCount: Int {
        128 + scoringDocument.estimatedByteCount
            + segments.reduce(0) {
                $0 + 96 + $1.text.utf8.count + $1.index.estimatedByteCount
            }
    }

    static func decode(_ data: Data?, checksum: String?) throws -> Self {
        guard let data, checksum == RelatedContentSourceProjection.checksum(data) else {
            throw SearchIndexError.corruptDatabase
        }
        let result: Self
        do { result = try JSONDecoder().decode(Self.self, from: data) } catch { throw SearchIndexError.corruptDatabase }
        guard result.scoringDocument.isValid, result.segments.allSatisfy({ $0.index.isValid }) else {
            throw SearchIndexError.corruptDatabase
        }
        return result
    }
}
