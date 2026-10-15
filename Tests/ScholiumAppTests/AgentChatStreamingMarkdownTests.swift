import Foundation
import JavaScriptCore
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Chat standalone streaming Markdown runtime")
struct AgentChatStreamingMarkdownTests {
    @Test("The packaged runtime completes partial syntax without executing source")
    func packagedRuntime() async throws {
        let runtime = AgentChatStreamingMarkdown()
        #expect(try await runtime.complete("A **stable phrase") == "A **stable phrase**")
        #expect(try await runtime.complete("A **stable phrase*") == "A **stable phrase**")
        #expect(try await runtime.complete("Use `source") == "Use `source`")
        #expect(try await runtime.complete("[Source](https://exam") == "[Source](streamdown:incomplete-link)")
        let inert = "'); throw new Error('private-source-marker'); //"
        #expect(try await runtime.complete(inert) == inert)
    }

    @Test("Concurrent requests share no speculative state and preserve literal source")
    func independentRequests() async throws {
        let runtime = AgentChatStreamingMarkdown()
        let sources = (0..<32).map { "Reply \($0): **中文😀e\u{301}" }
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask { (index, try await runtime.complete(source)) }
            }
            for try await (index, result) in group {
                #expect(result == sources[index] + "**")
            }
        }
        let literal = "```text\r\n**raw _markers_ [label](pending\r\n```"
        #expect(try await runtime.complete(literal) == literal)
        for literal in ["Cost $25 and $50", "$$\nx_i = y_j ** k\n", "Possible $25 **literal", "\\(x_i ** k", "20~25°C", "- > 25", "<private-tag"] {
            #expect(try await runtime.complete(literal) == literal)
        }
    }

    @Test("Parsed mathematical literals survive while following prose still streams")
    func mathematicalLiterals() async throws {
        let runtime = AgentChatStreamingMarkdown()
        let sources = [
            "$$\nx_i = y_j ** k\n$$\n\nA **stable phrase",
            "$x_i * y_j$ then **stable phrase",
            "\u{feff}中文😀e\u{301}\r\n\r\n$$\r\nx_i ** y_j\r\n$$\r\n\r\nA **stable phrase",
            "SCHOLIUMSTREAMLITERAL is authored. $x_i$ and $y_j$ then **stable phrase",
        ]
        for source in sources {
            let expected = source + "**"
            let completed = try await runtime.complete(source)
            #expect(Array(completed.utf8) == Array(expected.utf8))
        }
        let unfinished = "$x_i$ then $$\ny_j ** k\n"
        #expect(try await runtime.complete(unfinished) == unfinished)
    }

    @Test("Overlapping mathematical and code literals retain exact source coordinates")
    func overlappingLiterals() async throws {
        let runtime = AgentChatStreamingMarkdown()
        for source in [
            "$$\n```text\n$x$\n```\n$$\n\nA **phrase",
            "\u{FEFF}中文😀e\u{301}\r\n\r\n$$\r\n~~~text\r\n$x$\r\n~~~\r\n$$\r\n\r\nA **phrase",
            "$$\n    $x$\n$$\n\nA **phrase",
        ] {
            let completed = try await runtime.complete(source)
            #expect(Array(completed.utf8) == Array((source + "**").utf8))
        }
    }

    @Test("The generated runtime needs no DOM or ambient IO")
    func standaloneBoundary() throws {
        let script = try #require(ScholiumDocumentWebResources.text(named: "chat-streaming-markdown.bundle", extension: "js"))
        let context = try #require(JSContext())
        context.evaluateScript(script)
        #expect(context.exception == nil)
        let absent = context.evaluateScript(
            "[typeof document, typeof window, typeof fetch, typeof XMLHttpRequest, typeof WebSocket, typeof require, typeof process].every(value => value === 'undefined')"
        )
        #expect(absent?.toBool() == true)
        #expect(context.exception == nil)
        let completed = context.objectForKeyedSubscript("scholiumCompleteStreamingMarkdown")?.call(withArguments: ["**local"])
        #expect(completed?.toString() == "**local**")
        #expect(context.exception == nil)
    }

    @Test("Synthetic formatting closes before received whitespace under the native renderer")
    func nativeWhitespaceBoundary() async throws {
        let runtime = AgentChatStreamingMarkdown()
        let cases = [
            ("\u{FEFF}**Cafe\u{301} 中文😀\r\n", "\u{FEFF}**Cafe\u{301} 中文😀**\r\n", "<strong>Cafe\u{301} 中文😀</strong>"),
            ("**phrase ", "**phrase** ", "<strong>phrase</strong>"),
            ("**phrase  \r\n", "**phrase**  \r\n", "<strong>phrase</strong>"),
            ("*phrase\t\n", "*phrase*\t\n", "<em>phrase</em>"),
            ("Use `source ", "Use `source `", "<code dir=\"ltr\">source </code>"),
        ]
        for (source, expected, fragment) in cases {
            let completed = try await runtime.complete(source)
            #expect(Array(completed.utf8) == Array(expected.utf8))
            let html = SafeMarkdownRenderer.render(NoteDocument(relativePath: "Reply.md", rawContent: completed)).htmlBody
            #expect(html.contains(fragment))
        }
        for source in [
            "Use `source\n\n", "    **indented literal \r\n",
            "```text\r\n**literal \t\r\n", "~~~text\n**literal \t\r\n",
            "$$\nx_i ** y_j \t\r\n", "\\[x_i ** y_j \t\r\n",
        ] {
            #expect(try await runtime.complete(source) == source)
        }
        let mathThenProse = "$x_i ** y_j$ then **phrase\r\n"
        #expect(try await runtime.complete(mathThenProse) == "$x_i ** y_j$ then **phrase**\r\n")
        let codeThenProse = "    **indented literal \r\n\r\nA **phrase\r\n"
        #expect(try await runtime.complete(codeThenProse) == "    **indented literal \r\n\r\nA **phrase**\r\n")
    }
}
