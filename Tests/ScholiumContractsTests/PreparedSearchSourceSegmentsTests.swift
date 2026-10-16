import Foundation
import ScholiumContracts
import Testing

@Suite("Prepared Search source segment fidelity")
struct PreparedSearchSourceSegmentsTests {
    @Test("A shared exact body tree matches independent semantic and Search parses", arguments: SchemaProfileID.allCases)
    func sharedBodyParity(profile: SchemaProfileID) throws {
        let fixtures: [(name: String, source: String)] = [
            (
                "rich-crlf",
                "\u{FEFF}---\r\ntitle: 'Café'\r\nsummary: >-\r\n  Exact source summary.\r\nkeywords: [自由, evidence]\r\nunknown: preserved\r\n---\r\n# Heading 😀\r\n\r\nPlain **Cafe\u{301}** 👩‍🔬 &amp; [[目标#一节|行动]]{{annotation *wording*}}.\r\n"
            ),
            (
                "nested",
                "- First list paragraph.\n\n  Continued [[Target|label]]{{list context}}.\n\n> [!unknown-kind] Callout title\n> First paragraph.\n>\n> Second **paragraph** and [[Nested]].\n\nReference[^a] and ^[inline 自由].\n\n[^a]: Footnote paragraph.\n\n  Continued nested footnote [[Other|label]]{{context}}.\n"
            ),
            (
                "reference-context",
                "See [visible][ref] and ![alt][image].\n\n[ref]: Local.md#section \"Reference title\"\n[image]: image.png \"Caption\"\n\nOutside paragraph.\n"
            ),
            (
                "directives",
                "@Example(name: \"context\") {\n  Body [[Target|label]]{{annotation}}.\n\n  Second paragraph.\n}\n\nFollowing text.\n"
            ),
            (
                "multiline-annotation",
                "😀 [[One|*literal*]]{{First line\nsecond [[Nested|label]] and *reason*.}}.\n\n[[Broken]]{{unfinished\n"
            ),
            (
                "literals-and-math",
                "<!-- hidden [[A]] --> %% hidden [[B]] %% visible `[[literal]]` and ==highlight==.\n\n<span data-note=\"[[Hidden]]\">inline HTML</span> ![authored alt](image.png \"Image title\").\n\n$x + y$\n\n$$\nx + y\n$$\n\n```swift\nlet raw = \"[[literal]]\"\n```\n\n$$\nUnclosed display math.\n"
            ),
            ("duplicate-yaml", "---\ntitle: one\ntitle: two\n---\n\nUnchanged body.\n"),
            ("unclosed-yaml", "---\nsummary: [unfinished\n\nUnprovable body boundary 😀.\n"),
            ("empty-body", "---\nsummary: metadata only\n---\n"),
            ("no-final-newline", "À cafe\u{301} ß ﬃ İ K Σςσ ＡＢＣ 👨‍👩‍👧‍👦\u{00A0}\t自由"),
            ("empty", ""), ("blank-crlf", "\r\n"),
        ]
        for fixture in fixtures {
            let document = NoteDocument(relativePath: "\(fixture.name)-Cafe\u{301}.md", rawContent: fixture.source)
            try expectParity(document, profile: profile)
            // Related reinterprets exact nested slices as standalone documents.
            // Do not accidentally validate reuse of whole-Note AST nodes here.
            let standalone = MarkdownSemanticDocument(parsing: document)
            for block in standalone.blocks where block.kind == .paragraph {
                let range = try #require(Range(block.span.nsRange, in: document.rawContent))
                let snippet = NoteDocument(
                    relativePath: document.relativePath, rawContent: String(document.rawContent[range]))
                try expectParity(snippet, profile: profile)
            }
        }
    }

    private func expectParity(_ document: NoteDocument, profile: SchemaProfileID) throws {
        let originalBytes = document.sourceBytes
        let independentSemantic = MarkdownSemanticDocument(parsing: document)
        let independentSegments = SearchDocumentProjection.sourceSegments(
            document: document, semantic: independentSemantic, profile: profile)
        let shared = SearchDocumentProjection.prepareSourceSegments(document: document, profile: profile)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Complete encoded equality catches Unicode byte changes hidden by
        // Swift String equality, source ranges, diagnostics and ranking fields.
        #expect(try encoder.encode(shared.semantic) == encoder.encode(independentSemantic))
        #expect(try encoder.encode(shared.segments) == encoder.encode(independentSegments))
        #expect(shared.semantic.fingerprint == document.fingerprint)
        #expect(document.sourceBytes == originalBytes && originalBytes == Data(document.rawContent.utf8))
        for block in shared.semantic.blocks {
            let range = try #require(Range(block.span.nsRange, in: document.rawContent))
            try #require(block.span.utf8LowerBound >= 0 && block.span.utf8UpperBound <= originalBytes.count)
            #expect(Data(document.rawContent[range].utf8) == originalBytes.subdata(in: block.span.utf8Range))
        }
    }
}
