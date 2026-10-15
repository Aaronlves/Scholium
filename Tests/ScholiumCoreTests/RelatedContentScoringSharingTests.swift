import CryptoKit
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related-content publication scoring sharing", .serialized)
struct RelatedContentScoringSharingTests {
    /// The pre-cutover lexical constructor and wire shape. It independently
    /// prepares Note scoring instead of accepting the passage projection's value.
    private struct IndependentLexicalProjection: Encodable {
        struct StoredSegment: Encodable {
            let field: SearchMatchedField
            let material: RelatedContentBM25F.Document.StoredText
        }

        let scoringDocument: RelatedContentBM25F.Document
        let segments: [RelatedContentLexicalProjection.Segment]

        init(projection: SearchDocumentProjection) {
            let scoring = RelatedContentBM25F.Document(segments: projection.segments)
            scoringDocument = scoring
            segments = projection.segments.map {
                let shared = scoring.sharingPreparedText($0.normalizedText, index: .init($0.normalizedText))
                return .init(field: $0.field, text: shared.text, index: shared.index)
            }
        }

        private enum CodingKeys: String, CodingKey { case scoringDocument, segments }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(scoringDocument, forKey: .scoringDocument)
            try container.encode(
                segments.map {
                    StoredSegment(field: $0.field, material: scoringDocument.storedText($0.text, index: $0.index))
                }, forKey: .segments)
        }
    }

    @Test(
        "Shared Note scoring preserves independent lexical bytes and complete passage storage",
        arguments: [
            VaultRole.sourceCorpus, .topicKnowledge, .draftProject, .other,
        ])
    func independentStorageParity(role: VaultRole) throws {
        let sources = [
            "\u{FEFF}---\r\ntitle: 'Café'\r\naliases: ['Cafe\u{301}', 自由]\r\nsummary: 'Authored context'\r\nkeywords: [自由, reason]\r\n---\r\n# Heading 😀\r\n\r\nCAFÉ cafe\u{301} [[目标|行动]]{{annotation *wording*}}.\r\n\r\n- Nested paragraph.\r\n\r\n> Quoted [[Nested|label]]{{nested annotation}}.\r\n",
            "> [!cite] Callout title\n> First [external](https://example.test).\n>\n> Second **paragraph**.\n\nFootnote[^a].\n\n[^a]: Note [[目标|行动]]{{context}}.\n\n![alt](image.png \"Image title\")\n",
            "---\ntitle: one\ntitle: two\n---\n\nBody <!-- hidden --> inline `literal` and [[broken]]{{unclosed.\n\n$$x+y$$\n",
            "", "\r\n", "One final paragraph without a newline.",
        ]
        let encoder = Self.canonicalEncoder()
        for text in sources {
            let document = NoteDocument(relativePath: "Cafe\u{301}.md", rawContent: text)
            let prepared = PreparedSearchIndexDocument(source: Self.source(document, role: role), cache: nil)
            let passages = try RelatedContentSourceProjection(prepared: prepared)
            let originalPassageBytes = try encoder.encode(passages)
            let independent = IndependentLexicalProjection(projection: prepared.projection)
            let shared = RelatedContentLexicalProjection(
                projection: prepared.projection, scoringDocument: passages.noteScoringDocument)
            #expect(try encoder.encode(shared) == encoder.encode(independent))
            #expect(try encoder.encode(shared.scoringDocument) == encoder.encode(passages.noteScoringDocument))
            #expect(shared.segments.count == independent.segments.count)
            for (actual, expected) in zip(shared.segments, independent.segments) {
                #expect(actual.field == expected.field)
                #expect(actual.text.utf8.elementsEqual(expected.text.utf8))
                #expect(try encoder.encode(actual.index) == encoder.encode(expected.index))
            }
            let stored = try shared.encoded()
            let decoded = try RelatedContentLexicalProjection.decode(
                stored, checksum: RelatedContentSourceProjection.checksum(stored))
            #expect(try encoder.encode(decoded) == encoder.encode(independent))
            #expect(try encoder.encode(passages) == originalPassageBytes)
            #expect(document.sourceBytes == Data(text.utf8))
            #expect(document.fingerprint == DocumentFingerprint(data: Data(text.utf8)))
        }
    }

    @Test(
        "Opt-in exact stress Note duplicated versus shared scoring component",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_NOTE_SCORING_SHARING"] == "1"))
    func measureActualStressNotes() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let buildRoot = repository.appendingPathComponent(".build", isDirectory: true).resolvingSymlinksInPath()
        let fixture = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCHOLIUM_STRESS_FIXTURE"]
                ?? buildRoot.appendingPathComponent("stress-audit/fixture-5000").path
        ).standardizedFileURL.resolvingSymlinksInPath()
        try #require(fixture.path.hasPrefix(buildRoot.path + "/"))
        let manifest = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("stress-manifest.json"))) as? [String: Any])
        try #require(manifest["synthetic_nonprivate"] as? Bool == true)
        let scenarios = try #require(manifest["scenarios"] as? [String: String])
        let inventory = try #require(manifest["files"] as? [String: [String: Any]])
        let output = buildRoot.appendingPathComponent("index-cache-optimization", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let encoder = Self.canonicalEncoder()
        var records: [[String: Any]] = []
        for scenario in ["long_prose", "dense_links", "nested_callouts"] {
            let path = try #require(scenarios[scenario])
            let file = fixture.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
            try #require(file.path.hasPrefix(fixture.path + "/"))
            let bytes = try Data(contentsOf: file)
            let fingerprint = DocumentFingerprint(data: bytes)
            try #require(fingerprint.sha256 == inventory[path]?["sha256"] as? String)
            try #require(bytes.count == inventory[path]?["bytes"] as? Int)
            let document = NoteDocument(
                relativePath: path.split(separator: "/").dropFirst().joined(separator: "/"),
                rawContent: try #require(NoteDocument.decodeUTF8PreservingBOM(bytes)))
            try #require(document.sourceBytes == bytes)
            let prepared = PreparedSearchIndexDocument(source: Self.source(document, role: .sourceCorpus), cache: nil)
            // Both paths already paid for this first Note scorer and every
            // nested passage. Only the lexical constructor is timed below.
            let passages = try RelatedContentSourceProjection(prepared: prepared)
            let independentPassages = try RelatedContentSourceProjection(prepared: prepared)
            let passageBytes = try encoder.encode(passages)
            let independentPassageBytes = try encoder.encode(independentPassages)
            try #require(passageBytes == independentPassageBytes)
            var beforeSamples: [Double] = []
            var afterSamples: [Double] = []
            var lexicalHash = ""
            var lexicalByteCount = 0
            // Warm both constructors once, then alternate their order to avoid
            // assigning every first/second position to the same implementation.
            for iteration in 0..<4 {
                let before: Measurement
                let after: Measurement
                if iteration.isMultiple(of: 2) {
                    before = try measure(encoder: encoder) { IndependentLexicalProjection(projection: prepared.projection) }
                    after = try measure(encoder: encoder) {
                        RelatedContentLexicalProjection(
                            projection: prepared.projection, scoringDocument: passages.noteScoringDocument)
                    }
                } else {
                    after = try measure(encoder: encoder) {
                        RelatedContentLexicalProjection(
                            projection: prepared.projection, scoringDocument: passages.noteScoringDocument)
                    }
                    before = try measure(encoder: encoder) { IndependentLexicalProjection(projection: prepared.projection) }
                }
                try #require(before.canonicalBytes == after.canonicalBytes)
                if iteration > 0 {
                    beforeSamples.append(before.milliseconds)
                    afterSamples.append(after.milliseconds)
                }
                lexicalHash = Self.hash(after.canonicalBytes)
                lexicalByteCount = after.canonicalBytes.count
            }
            #expect(try encoder.encode(passages) == passageBytes)
            #expect(try Data(contentsOf: file) == bytes)
            #expect(document.fingerprint == fingerprint)
            records.append([
                "scenario": scenario, "source_bytes": bytes.count, "source_sha256": fingerprint.sha256,
                "related_projection_sha256": Self.hash(passageBytes), "related_projection_bytes": passageBytes.count,
                "lexical_projection_sha256": lexicalHash, "lexical_projection_bytes": lexicalByteCount,
                "nested_passages": passages.paragraphs.count, "before_ms": beforeSamples, "after_ms": afterSamples,
                "full_canonical_payload_bytes_equal": true,
            ])
            print("NOTE_SCORING_SHARING scenario=\(scenario) before_ms=\(beforeSamples) after_ms=\(afterSamples)")
        }
        let report: [String: Any] = [
            "boundary":
                "Lexical projection construction after the same prepared Search and RelatedSource projections; before repeats Note BM25, after shares its immutable value. Excludes disk I/O, source parsing, Search preparation, nested passage preparation, serialization and equality checks.",
            "configuration":
                "Same SwiftPM Debug binary; one warmup and three samples per constructor; alternating order; unchanged nonprivate synthetic sources",
            "records": records,
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("note-scoring-sharing-component.json"))
    }

    private struct Measurement {
        let milliseconds: Double
        let canonicalBytes: Data
    }

    private func measure<Value: Encodable>(encoder: JSONEncoder, build: () throws -> Value) throws -> Measurement {
        try autoreleasepool {
            let start = ContinuousClock.now
            let value = try build()
            let duration = start.duration(to: .now).components
            return Measurement(
                milliseconds: Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15,
                canonicalBytes: try encoder.encode(value))
        }
    }

    private static func source(_ document: NoteDocument, role: VaultRole) -> SearchIndexDocument {
        .init(
            vaultID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            vaultName: "Synthetic fixture", vaultRole: role, document: document)
    }

    private static func canonicalEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
