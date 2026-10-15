import CryptoKit
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related-content projection work", .serialized)
struct RelatedContentProjectionWorkTests {
    /// The reference deliberately uses complete Search projections for both the
    /// Note and each exact nested passage, as the pre-optimization owner did.
    private struct IndependentProjection: Encodable {
        let noteScoringDocument: RelatedContentBM25F.Document
        let paragraphs: [RelatedContentSourceProjection.Paragraph]

        init(document: NoteDocument) throws {
            let semantic = MarkdownSemanticDocument(parsing: document)
            noteScoringDocument = .init(segments: SearchDocumentProjection(document: document, semantic: semantic).segments)
            paragraphs = semantic.blocks.filter { $0.kind == .paragraph }.compactMap { block in
                guard block.span.utf16Range.count <= RelatedContentContract.maximumPassageUTF16Count,
                    let range = Range(block.span.nsRange, in: document.rawContent)
                else { return nil }
                let snippet = NoteDocument(relativePath: document.relativePath, rawContent: String(document.rawContent[range]))
                let display = ResearchExcerptPresentation.readableText(snippet.rawContent, includingAnnotations: true)
                let normalized = SearchTextNormalization.lexicalNormalize(display)
                let segments = SearchDocumentProjection(document: snippet).segments.filter {
                    $0.sourceRange != nil && $0.field != .title && $0.field != .alias
                }
                return .init(
                    range: .init(
                        utf16LowerBound: block.span.utf16LowerBound, utf16UpperBound: block.span.utf16UpperBound,
                        line: block.span.start.line, column: block.span.start.utf16Column,
                        endLine: block.span.end.line, endColumn: block.span.end.utf16Column),
                    displayText: display, normalizedDisplayText: normalized, textIndex: .init(normalized),
                    scoringDocument: .init(segments: segments))
            }
        }
    }

    @Test("Source-only preparation preserves complete nested passage material byte for byte")
    func independentPassageMaterial() throws {
        let cases = [
            "\u{FEFF}---\r\ntitle: 'Café'\r\nsummary: 'source-only summary'\r\nkeywords: [自由, test]\r\n---\r\n# Heading\r\n\r\nPlain **Cafe\u{301}** 😀 &amp; [[目标|行动]]{{annotation *wording*}}.\r\n\r\n- Nested paragraph.\r\n\r\n> Quoted [[Nested|label]]{{nested annotation}}.\r\n",
            "> [!cite] Callout title\n> First [external](https://example.test).\n>\n> Second **paragraph**.\n\nFootnote[^a].\n\n[^a]: Nested note [[目标|行动]]{{context}}.\n\n![alt](image.png \"Image title\")\n",
            "---\ntitle: unfinished\n---\n\nBody <!-- hidden --> inline `literal` and [[broken]]{{unclosed.\n\n$$x+y$$\n\n```swift\nlet source = 1\n```\n",
            "---\ntitle: one\ntitle: two\n---\n\nDuplicate YAML remains unchanged.\n",
            "", "\r\n", "A single paragraph without final newline.",
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for source in cases {
            let document = NoteDocument(relativePath: "Cafe\u{301}.md", rawContent: source)
            let actual = try RelatedContentSourceProjection(document: document)
            let reference = try IndependentProjection(document: document)
            #expect(try encoder.encode(actual) == encoder.encode(reference))
            #expect(actual.paragraphs.count == reference.paragraphs.count)
            for (paragraph, expected) in zip(actual.paragraphs, reference.paragraphs) {
                #expect(paragraph.exactReadableText.utf8.elementsEqual(expected.exactReadableText.utf8))
                #expect(try encoder.encode(paragraph.textIndex) == encoder.encode(expected.textIndex))
            }
            #expect(document.sourceBytes == Data(source.utf8))
        }
    }

    @Test(
        "Opt-in actual stress source passage projection measurement",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_RELATED_SEGMENTS"] == "1"))
    func measureActualStressSources() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let buildRoot = repository.appendingPathComponent(".build", isDirectory: true).resolvingSymlinksInPath()
        let fixture = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCHOLIUM_STRESS_FIXTURE"]
                ?? buildRoot.appendingPathComponent("stress-audit/fixture-5000").path
        ).standardizedFileURL.resolvingSymlinksInPath()
        try #require(fixture.path.hasPrefix(buildRoot.path + "/"))
        let label = ProcessInfo.processInfo.environment["SCHOLIUM_RELATED_SEGMENTS_LABEL"] ?? "optimized"
        try #require(["baseline", "optimized"].contains(label))
        let manifest = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("stress-manifest.json"))) as? [String: Any])
        try #require(manifest["synthetic_nonprivate"] as? Bool == true)
        let scenarios = try #require(manifest["scenarios"] as? [String: String])
        let inventory = try #require(manifest["files"] as? [String: [String: Any]])
        let output = buildRoot.appendingPathComponent("stress-audit/index-segments-component", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var records: [[String: Any]] = []
        for scenario in ["long_prose", "dense_links", "nested_callouts"] {
            let path = try #require(scenarios[scenario])
            let file = fixture.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
            try #require(file.path.hasPrefix(fixture.path + "/"))
            let bytes = try Data(contentsOf: file)
            let fingerprint = DocumentFingerprint(data: bytes)
            #expect(fingerprint.sha256 == inventory[path]?["sha256"] as? String)
            #expect(bytes.count == inventory[path]?["bytes"] as? Int)
            let text = try #require(NoteDocument.decodeUTF8PreservingBOM(bytes))
            let document = NoteDocument(relativePath: path.split(separator: "/").dropFirst().joined(separator: "/"), rawContent: text)
            try #require(document.sourceBytes == bytes)
            let source = SearchIndexDocument(
                vaultID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                vaultName: "Synthetic fixture", vaultRole: .sourceCorpus, document: document)
            let prepared = PreparedSearchIndexDocument(source: source, cache: nil)
            let fullHash: String = try autoreleasepool {
                var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(prepared.projection)) as? [String: Any])
                object["calloutRoles"] = prepared.projection.calloutRoles.sorted()
                return Self.hash(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            }
            var samples: [Double] = []
            var relatedHash = ""
            var passageCount = 0
            // First iteration warms the exact production path. All I/O,
            // preparation, encoding and oracle work is outside the samples.
            for sample in 0..<4 {
                try autoreleasepool {
                    let start = ContinuousClock.now
                    let related = try RelatedContentSourceProjection(prepared: prepared)
                    let elapsed = start.duration(to: .now).components
                    if sample > 0 {
                        samples.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
                    }
                    if sample == 0 {
                        relatedHash = Self.hash(try encoder.encode(related))
                        passageCount = related.paragraphs.count
                    }
                    withExtendedLifetime(related) {}
                }
            }
            #expect(try Data(contentsOf: file) == bytes)
            records.append([
                "scenario": scenario, "source_bytes": bytes.count, "source_sha256": fingerprint.sha256,
                "search_projection_sha256": fullHash, "related_projection_sha256": relatedHash,
                "nested_passages": passageCount, "projection_ms": samples,
            ])
            print("RELATED_SEGMENTS_COMPONENT scenario=\(scenario) samples_ms=\(samples) passages=\(passageCount)")
        }
        let report: [String: Any] = [
            "boundary": "RelatedContentSourceProjection(prepared:); excludes disk I/O, source semantic/Search preparation, encoding and equality checks",
            "configuration": "SwiftPM Debug; one warmup and three samples per unchanged synthetic source",
            "records": records,
        ]
        if label != "baseline" {
            let baseline = try #require(
                JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("baseline.json"))) as? [String: Any])
            let prior = try #require(baseline["records"] as? [[String: Any]])
            #expect(prior.count == records.count)
            for (before, after) in zip(prior, records) {
                for key in ["scenario", "source_bytes", "source_sha256", "search_projection_sha256", "related_projection_sha256", "nested_passages"] {
                    let oldValue = try #require(before[key] as? NSObject)
                    let newValue = try #require(after[key] as? NSObject)
                    #expect(oldValue == newValue)
                }
            }
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("\(label).json"))
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
