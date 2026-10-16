import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

/// Measures the synchronous source-to-page preparation used by
/// SafeMarkdownReadWebView.Coordinator.loadIfNeeded. It excludes WebKit
/// allocation, navigation, font preparation, native layout and visible paint.
/// Run this opt-in diagnostic alone: its synchronous samples deliberately
/// occupy the main actor used by asynchronous native lifecycle tests.
@MainActor
@Suite("Review page preparation diagnostics", .serialized)
struct ReadPagePreparationPerformanceTests {
    @Test(
        "Measure repeated source parsing against already prepared Review inputs",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_READ_PAGE_PREPARATION"] == "1"))
    func repeatedSourcePreparation() throws {
        for fixture in [
            Fixture(label: "small-crlf-bom", paragraphs: 24, newline: "\r\n", hasBOM: true, bodyBlankLine: true),
            Fixture(label: "large-lf", paragraphs: 1_536, newline: "\n", hasBOM: false, bodyBlankLine: false),
        ] {
            // The actual opening path already owns this immutable, exact
            // document before requesting HTML and constructing the page.
            let prepared = NoteDocument(relativePath: "Synthetic.md", rawContent: fixture.source)
            let frontmatter = try #require(prepared.rawFrontmatter)
            let originalBytes = prepared.sourceBytes
            #expect(prepared.validationWarnings.isEmpty)
            #expect(prepared.rawContent.utf8.elementsEqual(fixture.source.utf8))
            let rendered = SafeMarkdownRenderer.render(prepared).htmlBody
            let inputs = PageInputs(document: prepared)
            #expect(inputs.hasAuthoredBodyBlankLine == fixture.bodyBlankLine)
            let expected = pageHTML(body: rendered, inputs: inputs)
            #expect(expected.contains("data-scholium-protected=\"frontmatter\""))
            #expect(
                expected.contains("class=\"scholium-frontmatter-source scholium-frontmatter-followed-by-blank-line\"")
                    == fixture.bodyBlankLine)
            #expect(expected.contains("段落"))

            var parseTimes: [Double] = []
            var repeatedPageTimes: [Double] = []
            var preparedPageTimes: [Double] = []
            for index in 0..<15 {
                let (parsed, parseTime) = measured {
                    NoteDocument(relativePath: prepared.relativePath, rawContent: fixture.source)
                }
                #expect(parsed.fingerprint == prepared.fingerprint)
                #expect(parsed.sourceBytes == originalBytes)
                #expect(parsed.rawFrontmatter?.utf8.elementsEqual(frontmatter.utf8) == true)
                #expect(PageInputs(document: parsed) == inputs)

                // Alternate order to avoid consistently granting either path
                // the hotter allocator/assets. Each path invokes the actual
                // product documentHTML, with equal source-derived arguments.
                let repeated: (String, Double)
                let retained: (String, Double)
                if index.isMultiple(of: 2) {
                    repeated = measured { pageHTML(reparsing: fixture.source, body: rendered) }
                    retained = measured { pageHTML(body: rendered, inputs: inputs) }
                } else {
                    retained = measured { pageHTML(body: rendered, inputs: inputs) }
                    repeated = measured { pageHTML(reparsing: fixture.source, body: rendered) }
                }
                #expect(repeated.0.utf8.elementsEqual(expected.utf8))
                #expect(retained.0.utf8.elementsEqual(expected.utf8))
                #expect(prepared.sourceBytes == originalBytes)
                guard index >= 3 else { continue }
                parseTimes.append(parseTime)
                repeatedPageTimes.append(repeated.1)
                preparedPageTimes.append(retained.1)
            }
            print(
                "READ_PAGE_PREPARATION fixture=\(fixture.label) source_utf8_bytes=\(originalBytes.count) "
                    + "frontmatter_utf8_bytes=\(frontmatter.utf8.count) html_utf8_bytes=\(expected.utf8.count) warmups=3 samples=12 "
                    + "parse_ms=\(summary(parseTimes)) repeated_parse_and_page_ms=\(summary(repeatedPageTimes)) "
                    + "prepared_inputs_and_page_ms=\(summary(preparedPageTimes)) exact_source=true page_equivalent=true")
        }
    }

    @Test(
        "Separate large Review document, semantic and renderer work with complete output equivalence",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_READ_RENDERER"] == "1"))
    func largeSourceRendererPreparation() throws {
        let fixture = Fixture(label: "large-lf", paragraphs: 1_536, newline: "\n", hasBOM: false, bodyBlankLine: false)
        let originalBytes = Data(fixture.source.utf8)
        let prepared = NoteDocument(relativePath: "Synthetic.md", rawContent: fixture.source)
        let semantic = MarkdownSemanticDocument(parsing: prepared)
        try #require(prepared.sourceBytes == originalBytes)
        try #require(semantic.fingerprint == prepared.fingerprint)
        var expected: RenderedMarkdownDocument?
        var timings: [String: [Double]] = [:]
        let warmups = 1
        let samples = 3
        for iteration in 0..<(warmups + samples) {
            let (document, documentMS) = measured {
                NoteDocument(relativePath: prepared.relativePath, rawContent: fixture.source)
            }
            let (parsed, semanticMS) = measured { MarkdownSemanticDocument(parsing: prepared) }
            let reused: (RenderedMarkdownDocument, Double)
            let fresh: (RenderedMarkdownDocument, Double)
            // Alternate renderer order; both consume the same exact NoteDocument.
            // Fresh rendering includes its own semantic parse, but not construction
            // of the NoteDocument, which is measured separately above.
            if iteration.isMultiple(of: 2) {
                reused = measured { SafeMarkdownRenderer.render(prepared, semantic: semantic) }
                fresh = measured { SafeMarkdownRenderer.render(prepared) }
            } else {
                fresh = measured { SafeMarkdownRenderer.render(prepared) }
                reused = measured { SafeMarkdownRenderer.render(prepared, semantic: semantic) }
            }

            // No output normalization, nonce stripping or assertions enter timers.
            // Generated replacement nonces must be consumed by the renderer: this
            // fixture's complete final HTML and object identities are deterministic.
            let reference = expected ?? reused.0
            #expect(document.sourceBytes == originalBytes)
            #expect(document.fingerprint == prepared.fingerprint)
            #expect(parsed == semantic)
            for rendered in [reused.0, fresh.0] {
                #expect(rendered.htmlBody.utf8.elementsEqual(reference.htmlBody.utf8))
                #expect(rendered.semanticDocument == reference.semanticDocument)
                #expect(rendered.objects == reference.objects)
                for (actual, original) in zip(rendered.objects, reference.objects) {
                    #expect(actual.copyText.utf8.elementsEqual(original.copyText.utf8))
                    #expect(actual.html.utf8.elementsEqual(original.html.utf8))
                }
                #expect(!rendered.htmlBody.contains("SCHOLIUMINLINETOKEN"))
                #expect(!rendered.htmlBody.contains("data-scholium-block-token"))
            }
            #expect(prepared.sourceBytes == originalBytes)
            expected = reference
            guard iteration >= warmups else { continue }
            for (stage, duration) in [
                ("note_document", documentMS), ("semantic_parse", semanticMS),
                ("renderer_prepared_semantic", reused.1), ("renderer_fresh_semantic", fresh.1),
            ] {
                timings[stage, default: []].append(duration)
            }
        }
        let reference = try #require(expected)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let semanticDigest = DocumentFingerprint(data: try encoder.encode(semantic)).sha256
        let objectMaterial = reference.objects.map { object in
            ["id": object.id, "kind": object.kind.rawValue, "copy_text": object.copyText, "html": object.html]
        }
        let objectDigest = DocumentFingerprint(
            data: try JSONSerialization.data(withJSONObject: objectMaterial, options: [.sortedKeys])).sha256
        let summaries = timings.mapValues { values in
            let sorted = values.sorted()
            return ["min": sorted[0], "median": sorted[1], "max": sorted[2]]
        }
        let record: [String: Any] = [
            "schema": "scholium-read-renderer-diagnostic-v1", "fixture": fixture.label,
            "source_utf8_bytes": originalBytes.count, "source_sha256": prepared.fingerprint.sha256,
            "paragraph_groups": 1_536, "html_utf8_bytes": reference.htmlBody.utf8.count,
            "html_sha256": DocumentFingerprint(content: reference.htmlBody).sha256,
            "semantic_sha256": semanticDigest, "rendered_objects_sha256": objectDigest,
            "rendered_objects": reference.objects.count, "semantic_blocks": semantic.blocks.count,
            "warmups": warmups, "samples": samples, "stage_ms": summaries, "stage_samples_ms": timings,
            "scope": "SwiftPM Debug pure construction and rendering; fresh renderer includes semantic parsing, excludes NoteDocument construction; no I/O, WebKit, layout, XCTest transport or paint",
            "complete_output_equivalent": true, "exact_source": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print("READ_RENDERER_DIAGNOSTIC \(String(decoding: data, as: UTF8.self))")
    }

    private struct PageInputs: Equatable {
        let frontmatter: String?
        let hasAuthoredBodyBlankLine: Bool

        init(document: NoteDocument) {
            frontmatter = document.rawFrontmatter
            hasAuthoredBodyBlankLine =
                !document.body.isEmpty
                && document.body.prefix { !$0.isNewline }.allSatisfy(\.isWhitespace)
        }
    }

    private func pageHTML(reparsing source: String, body: String) -> String {
        // Mirrors the sourceDocument construction and derived inputs inside
        // loadIfNeeded, rather than timing a substitute YAML implementation.
        let document = NoteDocument(relativePath: "Synthetic.md", rawContent: source)
        return pageHTML(body: body, inputs: PageInputs(document: document))
    }

    private func pageHTML(body: String, inputs: PageInputs) -> String {
        SafeMarkdownReadWebView.Coordinator.documentHTML(
            body: body,
            frontmatter: inputs.frontmatter,
            frontmatterHasAuthoredBodyBlankLine: inputs.hasAuthoredBodyBlankLine,
            documentTitle: "Synthetic Review Fixture",
            includesMathRuntime: false
        )
    }

    private func measured<Value>(_ action: () -> Value) -> (Value, Double) {
        let start = ContinuousClock.now
        let value = action()
        let components = start.duration(to: .now).components
        return (value, Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000)
    }

    private func summary(_ values: [Double]) -> String {
        let sorted = values.sorted()
        let median = (sorted[5] + sorted[6]) / 2
        let p95 = sorted[Int((Double(sorted.count) * 0.95).rounded(.up)) - 1]
        return String(format: "[p50:%.3f,p95:%.3f,max:%.3f]", median, p95, sorted.last ?? 0)
    }

    private struct Fixture {
        let label: String
        let source: String
        let bodyBlankLine: Bool

        init(label: String, paragraphs: Int, newline: String, hasBOM: Bool, bodyBlankLine: Bool) {
            self.label = label
            self.bodyBlankLine = bodyBlankLine
            let header = """
                ---
                title: 'Synthetic: reading lifecycle'
                aliases:
                  - 'An exact é 🦉 fixture'
                  - 阅读界面
                tags: [synthetic, review, performance]
                date: 2026-10-15
                count: 12
                enabled: true
                summary: |
                  This is disposable diagnostic content.
                  It makes no academic source claim.
                unknown_property: {nested: [one, two, three]}
                # Authored comments remain part of the source.
                ---
                """
            let paragraphs = (0..<paragraphs).map { index in
                let text = """
                    ## Section \(index) · 段落

                    Paragraph \(index) combines English prose, 中文句子, decomposed é and 🦉. \
                    A **synthetic claim** has an [authored link](Other.md), `exact code`, \
                    and no external source authority. Reading remains independent of source editing.

                    > A bounded quotation-shaped fixture; it is not attributed to a real source.
                    """
                if index.isMultiple(of: 16) {
                    return text + "\n\n| Column | Value |\n| --- | --- |\n| Exact | preserved |\n\n```text\nsource é 🦉\n```"
                }
                return text
            }.joined(separator: "\n\n")
            let source = header + (bodyBlankLine ? "\n\n" : "\n") + paragraphs + "\n"
            self.source = (hasBOM ? "\u{FEFF}" : "") + source.replacingOccurrences(of: "\n", with: newline)
        }
    }
}
