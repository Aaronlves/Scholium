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

    @Test("Long typed arrays retain each repeated token's exact UTF-16 location", arguments: ["\n", "\r\n", "\r"])
    func typedArrayCoordinates(newline: String) throws {
        for block in [false, true] {
            var fixture = LocatedSource()
            fixture.append("\u{FEFF}---")
            fixture.newline(newline)
            var expected: [String: (key: SearchSourceRange, values: [(String, SearchSourceRange)])] = [:]
            for key in ["keywords", "tags", "aliases"] {
                let keyRange = fixture.append(key)
                fixture.append(block ? ":" : ": [")
                if block { fixture.newline(newline) }
                var members: [(String, SearchSourceRange)] = []
                for index in 0..<128 {
                    if block {
                        fixture.append("  - ")
                    } else if index > 0 {
                        fixture.append(", ")
                    }
                    // Repeated values exercise positional identity rather than
                    // a first textual match. Emoji and decomposed text make
                    // scalar, Character and UTF-16 columns different.
                    let value = index.isMultiple(of: 2) ? "[[合成资料|重复 🦉 e\u{301}]]" : "重复 🦉 e\u{301}"
                    let range = fixture.append("'" + value + "'")
                    members.append((value, range))
                    if block { fixture.newline(newline) }
                }
                if !block {
                    fixture.append("]")
                    fixture.newline(newline)
                }
                expected[key] = (keyRange, members)
            }
            fixture.append("---")
            fixture.newline(newline)
            fixture.append("Exact body e\u{301} 🦉 without final newline")
            let bytes = Data(fixture.text.utf8)
            let document = NoteDocument(relativePath: "Typed arrays.md", rawContent: fixture.text)
            let projection = SearchPropertyProjection(document: document)
            try #require(document.validationWarnings.isEmpty)
            #expect(projection.issues.isEmpty)
            for (key, locations) in expected {
                let entry = try #require(projection.entry(forExactKey: key))
                #expect(entry.keySourceRange == locations.key)
                #expect(entry.valueKind == .stringSequence)
                try #require(entry.stringMembers.count == locations.values.count)
                for (actual, expected) in zip(entry.stringMembers, locations.values) {
                    #expect(actual.value.utf8.elementsEqual(expected.0.utf8))
                    #expect(actual.sourceRange == expected.1)
                    #expect(sourceText(fixture.text, in: expected.1) == "'" + expected.0 + "'")
                }
            }
            #expect(document.sourceBytes == bytes)
            #expect(document.fingerprint == DocumentFingerprint(data: bytes))
        }
    }

    @Test("Quoted and block scalars retain exact locations across Unicode and newline forms", arguments: ["\n", "\r\n", "\r"])
    func quotedAndBlockCoordinates(newline: String) throws {
        var fixture = LocatedSource()
        fixture.append("\u{FEFF}---")
        fixture.newline(newline)
        let quotedKey = fixture.append("\"研究 🦉 e\u{301}\"")
        fixture.append(": [")
        let single = fixture.append("'it''s 🦉 e\u{301}'")
        fixture.append(", ")
        let double = fixture.append(#""\u4E2D \U0001F989 \"quoted\"""#)
        fixture.append(", ")
        let leadingCombining = fixture.append("'\u{301}leading 🦉'")
        fixture.append("]")
        fixture.newline(newline)
        let summaryKey = fixture.append("summary")
        fixture.append(": ")
        let blockStart = fixture.location
        fixture.append("|-")
        fixture.newline(newline)
        fixture.append("  第一行 🦉")
        fixture.newline(newline)
        fixture.append("  e\u{301} 第二行")
        fixture.newline(newline)
        let block = fixture.range(from: blockStart)
        let nextKey = fixture.append("next")
        fixture.append(": ")
        let next = fixture.append("untouched")
        fixture.newline(newline)
        fixture.append("folded: ")
        let quotedStart = fixture.location
        fixture.append("\"first 🦉")
        fixture.newline(newline)
        fixture.append("  second e\u{301}\"")
        let multilineQuoted = fixture.range(from: quotedStart)
        fixture.newline(newline)
        fixture.append("---")
        fixture.newline(newline)
        fixture.append("Body")
        let bytes = Data(fixture.text.utf8)
        let document = NoteDocument(relativePath: "Located scalars.md", rawContent: fixture.text)
        let projection = SearchPropertyProjection(document: document)
        try #require(document.validationWarnings.isEmpty)
        #expect(projection.issues.isEmpty)
        let quoted = try #require(projection.entry(forExactKey: "研究 🦉 e\u{301}"))
        #expect(quoted.keySourceRange == quotedKey)
        #expect(quoted.stringMembers.map(\.value) == ["it's 🦉 e\u{301}", "中 🦉 \"quoted\"", "\u{301}leading 🦉"])
        #expect(quoted.stringMembers.map(\.sourceRange) == [single, double, leadingCombining])
        let summary = try #require(projection.entry(forExactKey: "summary"))
        #expect(summary.keySourceRange == summaryKey)
        #expect(summary.stringMembers.first?.value == "第一行 🦉\ne\u{301} 第二行")
        #expect(summary.stringMembers.first?.sourceRange == block)
        #expect(projection.entry(forExactKey: "next")?.keySourceRange == nextKey)
        #expect(projection.entry(forExactKey: "next")?.stringMembers.first?.sourceRange == next)
        #expect(projection.entry(forExactKey: "folded")?.stringMembers.first?.value == "first 🦉 second e\u{301}")
        #expect(projection.entry(forExactKey: "folded")?.stringMembers.first?.sourceRange == multilineQuoted)
        #expect(document.sourceBytes == bytes)
    }

    @Test("Yams Unicode line marks resolve to exact source lines", arguments: ["\u{85}", "\u{2028}", "\u{2029}"])
    func unicodeYAMLLineMarks(newline: String) throws {
        var fixture = LocatedSource()
        fixture.append("---")
        fixture.newline("\n")
        fixture.append("keywords: ['🦉 e\u{301}']")
        // Yams advances its parser line for these scalars; exact source lines
        // follow the shared CR/LF locator contract, so they occupy a column.
        fixture.append(newline)
        let keyRange = fixture.append("aliases")
        fixture.append(": [")
        let valueRange = fixture.append("'[[资料 🦉]]'")
        fixture.append("]")
        fixture.newline("\n")
        fixture.append("---\nBody")
        let document = NoteDocument(relativePath: "Line marks.md", rawContent: fixture.text)
        let projection = SearchPropertyProjection(document: document)
        try #require(document.validationWarnings.isEmpty)
        #expect(projection.issues.isEmpty)
        let aliases = try #require(projection.entry(forExactKey: "aliases"))
        #expect(aliases.keySourceRange == keyRange)
        #expect(aliases.stringMembers.first?.sourceRange == valueRange)
        #expect(aliases.stringMembers.first?.value == "[[资料 🦉]]")
        #expect(document.sourceBytes == Data(fixture.text.utf8))
    }

    /// Independent fixture construction records positions before inserting
    /// tokens. It neither asks Yams for coordinates nor searches repeated text.
    private struct LocatedSource {
        private(set) var text = ""
        private var offset = 0
        private var line = 1
        private var column = 1

        var location: (offset: Int, line: Int, column: Int) { (offset, line, column) }

        @discardableResult
        mutating func append(_ token: String) -> SearchSourceRange {
            let start = location
            let length = token.utf16.count
            text += token
            offset += length
            column += length
            return range(from: start)
        }

        mutating func newline(_ token: String) {
            text += token
            offset += token.utf16.count
            line += 1
            column = 1
        }

        func range(from start: (offset: Int, line: Int, column: Int)) -> SearchSourceRange {
            SearchSourceRange(
                utf16LowerBound: start.offset, utf16UpperBound: offset,
                line: start.line, column: start.column, endLine: line, endColumn: column)
        }
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
