import Foundation
import ScholiumContracts
import Testing

@Suite("Source-bound rendered objects")
struct RenderedMarkdownObjectTests {
    private func render(_ source: String) -> RenderedMarkdownDocument {
        SafeMarkdownRenderer.render(NoteDocument(relativePath: "Reply.md", rawContent: source))
    }

    @Test("Separate tables and raw HTML cannot shift the following code's actions")
    func independentObjects() throws {
        let first = "| A | B |\n|---|---|\n| one | two |"
        let second = "| C | D |\n|---|---|\n| three | four |"
        let source = first + "\n\n" + second + "\n\n<div>HTML example</div>\n\n```swift\nprint(42)\n```"
        let rendered = render(source)
        #expect(rendered.objects.map(\.kind) == [.table, .table, .code, .code])
        #expect(rendered.objects.map(\.copyText) == [first, second, "<div>HTML example</div>\n", "print(42)\n"])
        #expect(Set(rendered.objects.map(\.id)).count == 4)
        for object in rendered.objects {
            #expect(rendered.htmlBody.components(separatedBy: "data-scholium-object=\"" + object.id + "\"").count == 2)
            #expect(!object.html.contains("data-scholium-object"), "Preview content has no second action layer")
        }
        #expect(rendered.objects[0].html.contains("<td dir=\"auto\">one</td>"))
        #expect(!rendered.objects[0].html.contains("three"))
        #expect(rendered.objects[2].html.contains("&lt;div&gt;HTML example&lt;/div&gt;"))
    }

    @Test("Unchanged objects survive appended prose; changed content replaces identity")
    func stableIdentity() throws {
        let source = "```text\nfirst\n```\n\n```text\nsecond\n```"
        let first = render(source)
        #expect(render(source + "\n\nMore prose.").objects == first.objects)
        let changed = render(source.replacingOccurrences(of: "second", with: "replacement"))
        #expect(changed.objects.first?.id == first.objects.first?.id)
        #expect(changed.objects.last?.id != first.objects.last?.id)
        #expect(render(source).objects == first.objects)
    }

    @Test("Code payload uses AST content with original line endings and no synthetic EOF newline")
    func exactCode() throws {
        for (source, expected) in [
            ("```mermaid\r\nflowchart LR\r\n  A --> B\r\n\r\n```", "flowchart LR\r\n  A --> B\r\n\r\n"),
            ("  ```swift title\r\n  let a = 1\r\n    let b = 2\r\n  ```", "let a = 1\r\n  let b = 2\r\n"),
            ("> ```swift\r\n> let a = 1\r\n> ```", "let a = 1\r\n"),
            ("```text\r\none\ntwo\r\n```", "one\ntwo\r\n"),
            ("```text\nlast", "last"),
            ("    first\r\n    second", "first\r\nsecond"),
            ("    ```\r\n    literal\n    ```", "```\r\nliteral\n```"),
            ("```text\n\n```", "\n"),
        ] {
            let object = try #require(render(source).objects.first)
            #expect(object.copyText == expected, "Source: \(source.debugDescription)")
        }
    }

    @Test("Nested containers bind each rendered object independently of collection order")
    func nestedObjects() throws {
        let source =
            "```text\nouter\n```\n\n> [!note] Context\n> ```mermaid\n> flowchart LR\n> A --> B\n> ```\n\nFootnote.[^one]\n\n[^one]: Detail.\n\n    ```text\n    footnote code\n    ```"
        let rendered = render(source)
        #expect(rendered.objects.count == 3)
        #expect(Set(rendered.objects.map(\.copyText)) == ["outer\n", "flowchart LR\nA --> B\n", "footnote code\n"])
        for object in rendered.objects {
            #expect(rendered.htmlBody.contains("data-scholium-object=\"" + object.id + "\""))
        }
    }

    @Test("Table copies original Markdown while its preview preserves inline semantics")
    func tableSource() throws {
        let source = "| Claim | Link |\r\n|---|---|\r\n| **A** \\| B | [[Target]] |"
        let object = try #require(render(source).objects.first)
        #expect(object.copyText == source)
        #expect(object.html.contains("<strong>A</strong>"))
        #expect(object.html.contains("wiki-link"))
        #expect(!object.copyText.contains("SCHOLIUMINLINETOKEN"))
    }
}
