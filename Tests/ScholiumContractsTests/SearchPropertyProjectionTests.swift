import Foundation
import Testing

@testable import ScholiumContracts

@Suite("Search property projection")
struct SearchPropertyProjectionTests {
    @Test("Indexes custom YAML fields without a managed catalog and preserves exact ranges")
    func arbitraryAuthoredYAML() throws {
        let source = """
            ---
            summary: A navigation summary
            keywords: [Akrasia, "Weakness of Will"]
            title: Retired YAML title
            custom: keep exact but ignore
            ---
            Body
            """
        let projection = SearchPropertyProjection(
            document: NoteDocument(relativePath: "Topic.md", rawContent: source),
            profile: .topicMarkdown
        )

        #expect(projection.entries.map(\.key) == ["custom", "keywords", "summary", "title"])
        #expect(projection.entry(forExactKey: "title")?.stringMembers.first?.value == "Retired YAML title")
        #expect(projection.entry(forExactKey: "custom")?.stringMembers.first?.value == "keep exact but ignore")
        let summary = try #require(projection.entry(forExactKey: "summary"))
        let summaryRange = try #require(summary.stringMembers.first?.sourceRange)
        #expect(sourceText(source, in: summaryRange) == "A navigation summary")
        let keywords = try #require(projection.entry(forExactKey: "keywords"))
        #expect(keywords.stringMembers.map(\.value) == ["Akrasia", "Weakness of Will"])
        #expect(
            try keywords.stringMembers.map {
                sourceText(source, in: try #require($0.sourceRange))
            } == ["Akrasia", "\"Weakness of Will\""])
    }

    @Test("Quoted Unicode keys and direct mixed-list members retain their own scalar tokens")
    func arbitraryKeysAndScalars() throws {
        let source =
            "\u{FEFF}---\r\n\"研究 问题\": \"行动理由\"\r\nyear: 1962\r\nflag: true\r\nitems: [ethics, 42, false, null, {nested: hidden}]\r\npunctuation: a,b]c\r\nempty: null\r\n---\r\nBody"
        let document = NoteDocument(relativePath: "Mixed.md", rawContent: source)
        let projection = SearchPropertyProjection(document: document)
        let key = try #require(projection.entry(forExactKey: "研究 问题"))
        #expect(sourceText(source, in: try #require(key.keySourceRange)) == "\"研究 问题\"")
        #expect(key.stringMembers.first?.value == "行动理由")
        #expect(projection.entry(forExactKey: "year")?.valueKind == .scalar)
        #expect(projection.entry(forExactKey: "year")?.stringMembers.first?.value == "1962")
        #expect(projection.entry(forExactKey: "flag")?.stringMembers.first?.value == "true")
        let members = try #require(projection.entry(forExactKey: "items")).stringMembers
        #expect(members.map(\.value) == ["ethics", "42", "false"])
        #expect(try members.map { sourceText(source, in: try #require($0.sourceRange)) } == ["ethics", "42", "false"])
        #expect(projection.entry(forExactKey: "punctuation")?.stringMembers.first?.value == "a,b]c")
        #expect(projection.entry(forExactKey: "empty")?.isEmpty == true)
        #expect(document.sourceBytes == Data(source.utf8))
    }

    @Test("Block scalar ranges include the full authored token and exclude neighboring fields")
    func blockScalarSpans() throws {
        for newline in ["\n", "\r\n"] {
            for indicator in ["|", "|-", "|+", ">", ">-", "|2-"] {
                let source = ["---", "summary: \(indicator)", "  第一行 😀", "  second line", "next: untouched", "---", "Body"].joined(separator: newline)
                let document = NoteDocument(relativePath: "Block.md", rawContent: source)
                let projection = SearchPropertyProjection(document: document)
                let member = try #require(projection.entry(forExactKey: "summary")?.stringMembers.first)
                let span = try #require(member.sourceRange)
                #expect(sourceText(source, in: span) == [indicator, "  第一行 😀", "  second line", ""].joined(separator: newline))
                #expect(span.line == 2)
                #expect(span.endLine == 5)
                #expect(projection.entry(forExactKey: "next")?.stringMembers.first?.value == "untouched")
                #expect(document.sourceBytes == Data(source.utf8))
            }
        }
    }

    @Test("Duplicate decoded keys and unsupported aliases never invent a field value")
    func duplicateAndAliasBoundaries() throws {
        let source = "---\ncustom: first\n\"custom\": second\nbase: &source original\ncopy: *source\nmap: {inside: hidden}\n---\nBody"
        let projection = SearchPropertyProjection(document: NoteDocument(relativePath: "Duplicate.md", rawContent: source))
        #expect(projection.entry(forExactKey: "custom") == nil)
        #expect(projection.issues == [.invalidYAML])
        let aliases = SearchPropertyProjection(
            document: NoteDocument(
                relativePath: "Aliases.md",
                rawContent: "---\nbase: &source original\ncopy: *source\nmap: {inside: hidden}\n---\nBody"))
        #expect(aliases.entry(forExactKey: "copy")?.stringMembers.isEmpty == true)
        #expect(aliases.entry(forExactKey: "map")?.valueKind == .mapping)
        #expect(aliases.entry(forExactKey: "inside") == nil)
    }

    private func sourceText(_ text: String, in range: SearchSourceRange) -> String? {
        guard
            let lower = text.utf16.index(
                text.utf16.startIndex,
                offsetBy: range.utf16LowerBound,
                limitedBy: text.utf16.endIndex
            ),
            let upper = text.utf16.index(
                text.utf16.startIndex,
                offsetBy: range.utf16UpperBound,
                limitedBy: text.utf16.endIndex
            ), let start = lower.samePosition(in: text),
            let end = upper.samePosition(in: text)
        else { return nil }
        return String(text[start..<end])
    }
}
