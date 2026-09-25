import Foundation
import ScholiumContracts
import Testing

@Suite("Source-located Markdown note links")
struct MarkdownInlineLinkSourceTests {
    @Test("Only valid inline links with local destinations enter the link graph")
    func sourceLocatedLinks() {
        let raw = #"""
            [plain](Topic.md "title") [angle](<Topic Name.md#Heading> 'title')
            [balanced](Topic(1).md#Heading) [escaped](Topic\(2\).md) [section](#Argument)
            [emoji](Topic😀.md)
            [reference][id] [broken](Topic.md "missing)
            [id]: Target.md
            `[code](Hidden.md)` <!-- [comment](Hidden.md) -->
            """#
        let document = NoteDocument(relativePath: "A.md", rawContent: raw)
        let links = MarkdownSemanticDocument(parsing: document).links
        let source = raw as NSString

        #expect(links.map(\.target) == ["Topic.md", "Topic Name.md", "Topic(1).md", "Topic(2).md", "", "Topic😀.md"])
        #expect(links.map(\.fragment) == [nil, "Heading", "Heading", nil, "Argument", nil])
        #expect(
            links.map { source.substring(with: $0.linkSpan.nsRange) } == [
                #"[plain](Topic.md "title")"#,
                #"[angle](<Topic Name.md#Heading> 'title')"#,
                "[balanced](Topic(1).md#Heading)",
                #"[escaped](Topic\(2\).md)"#,
                "[section](#Argument)",
                "[emoji](Topic😀.md)",
            ])
    }
}
