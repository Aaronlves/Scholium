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

    init(projection: SearchDocumentProjection) {
        scoringDocument = .init(segments: projection.segments)
        segments = projection.segments.map {
            .init(field: $0.field, text: $0.normalizedText, index: .init($0.normalizedText))
        }
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    /// Conservative accounting for both the Note scoring fields and the
    /// independently allocated matcher segments. Shared storage is counted twice.
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
