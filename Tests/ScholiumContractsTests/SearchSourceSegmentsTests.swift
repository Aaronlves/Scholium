import Foundation
import ScholiumContracts
import Testing

@Suite("Shared Search source segments")
struct SearchSourceSegmentsTests {
    @Test("Source-only segments match complete Search fields, attribution and exact offsets", arguments: SchemaProfileID.allCases)
    func completeSegmentEquivalence(profile: SchemaProfileID) throws {
        let sources = [
            "\u{FEFF}---\r\ntitle: 'Café'\r\naliases: [別名, Alias]\r\nsummary: >\r\n  Source summary.\r\nkeywords: [自由, context]\r\nauthors: [Author]\r\nauthor: Coauthor\r\npublication_date: '2026'\r\nunknown: retained\r\n---\r\n# Heading\r\n\r\n**Cafe\u{301}** 😀 &amp; [[目标|行动]]{{annotation *wording*}}.\r\n\r\nSecond paragraph.\r\n",
            "> [!cite] Context\n> Nested paragraph [[Target|label]]{{annotation}}.\n>\n> More text.\n\n- List paragraph.\n\n> Ordinary quote.\n\nReference[^x].\n\n[^x]: Footnote [[Other|label]]{{footnote context}}.\n\n![alt](image.png \"Caption\")\n",
            "---\ntitle: duplicate\ntitle: ambiguous\n---\n\nBody with [[Unclosed]]{{bad annotation\n\n<!-- hidden --> tail `literal` &amp; text.\n",
            "---\ntitle: unfinished\nUnprovable frontmatter\n\nparagraph\n",
            "$$x+y$$\n\n```swift\nlet raw = 1\n```\n\n<span>HTML</span>\n",
            "", "\r\n", "ordinary without final newline",
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for source in sources {
            let document = NoteDocument(relativePath: "Cafe\u{301}.md", rawContent: source)
            let semantic = MarkdownSemanticDocument(parsing: document)
            let segments = SearchDocumentProjection.sourceSegments(document: document, semantic: semantic, profile: profile)
            let complete = SearchDocumentProjection(document: document, profile: profile, semantic: semantic)
            #expect(segments == complete.segments)
            // Swift String equality alone would hide canonical-equivalent
            // Unicode changes. JSON retains every UTF-8 byte and offset value.
            #expect(try encoder.encode(segments) == encoder.encode(complete.segments))
            #expect(document.sourceBytes == Data(source.utf8))
        }
    }
}
