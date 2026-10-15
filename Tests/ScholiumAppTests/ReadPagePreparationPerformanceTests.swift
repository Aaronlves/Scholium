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
