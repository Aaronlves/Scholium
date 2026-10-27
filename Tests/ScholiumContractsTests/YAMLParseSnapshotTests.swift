import Foundation
import Testing
import Yams

@testable import ScholiumContracts

@Suite("Source-bound YAML parse snapshots")
struct YAMLParseSnapshotTests {
    private static let corpus = [
        "", "# comment only\n", "{}\n", "null\n", "ordinary scalar\n", "[one, 2, true]\n",
        "summary: plain\nflag: yes\nnumber: 42\nfraction: 3.5\nempty: null\nquoted: 'true'\n",
        "day: 2026-10-27\nstamp: 2026-10-27T08:01:02.125+08:00\nquoted: '2026-10-27'\n",
        "base: &source original\ncopy: *source\nmap: {inside: hidden}\n",
        "base: &defaults {summary: inherited, flag: true}\n<<: *defaults\nsummary: authored\n",
        "text: !!str 42\ninteger: !!int '42'\ncustom: !custom 'literal'\n",
        "=: value\nordinary: kept\n",
        "\"研究 🦉 e\u{301}\": ['[[资料 🦉 e\u{301}]]', '[[资料 🦉 e\u{301}]]']\n",
        "items: [ethics, 42, false, null, {nested: hidden}]\nempty: []\n",
        "summary: |-\n  第一行 🦉\n  second e\u{301}\nnext: untouched\n",
        "summary: >-\n  first\n  second\nnext: untouched\n",
        "summary: \"first\n  second\"\n",
        "duplicate: first\n\"duplicate\": second\n",
        "broken: [unterminated\n", "broken: 'unterminated\n", "copy: *undefined\n",
    ]

    @Test("Metadata and diagnostics match pinned Yams.load for the exact authored envelope", arguments: ["\n", "\r\n", "\r"])
    func metadataParity(newline: String) throws {
        for (index, yaml) in Self.corpus.enumerated() {
            let frontmatter = yaml.replacingOccurrences(of: "\n", with: newline)
            let prefix = "\u{FEFF}---" + newline
            let closing = "---" + newline
            let body = "Body 🦉 e\u{301} [[Target]]{{annotation \"exact\"}} without final newline"
            let source = prefix + frontmatter + closing + body
            let document = NoteDocument(relativePath: "Corpus \(index).md", rawContent: source)
            try #require(document.rawFrontmatter == frontmatter)
            let expected: [String: YAMLValue]
            let warnings: [String]
            do {
                let value = try Yams.load(yaml: frontmatter)
                if let dictionary = value as? [String: Any] {
                    expected = dictionary.mapValues(YAMLValue.convert)
                    warnings = []
                } else if value == nil {
                    expected = [:]
                    warnings = []
                } else {
                    expected = [:]
                    warnings = ["Frontmatter root must be a mapping."]
                }
            } catch {
                expected = [:]
                warnings = [error.localizedDescription]
            }
            #expect(document.parsedFrontmatter == expected, "Corpus \(index)")
            #expect(document.validationWarnings == warnings, "Corpus \(index)")
            #expect(document.sourceBytes == Data(source.utf8))
            #expect(document.fingerprint == DocumentFingerprint(data: Data(source.utf8)))
            #expect(document.body == body)
            #expect(document.frontmatterByteRange == prefix.utf8.count..<(prefix.utf8.count + frontmatter.utf8.count))

            // A fresh compose matches the former independent lexical parse.
            // This checks that metadata construction did not alter the shared
            // tree; the handwritten range fixture below is a separate oracle.
            let snapshot = SearchPropertyProjection(document: document)
            if let root = try? Yams.compose(yaml: frontmatter) {
                let independent = SearchPropertyProjection(
                    root: root, sourceBytes: document.sourceBytes,
                    frontmatterByteRange: document.frontmatterByteRange, frontmatter: frontmatter)
                #expect(snapshot == independent, "Corpus \(index)")
            } else if !warnings.isEmpty {
                #expect(snapshot.entries.isEmpty && snapshot.issues == [.invalidYAML])
            } else {
                #expect(snapshot.entries.isEmpty && snapshot.issues.isEmpty)
            }
            #expect(SearchPropertyProjection(document: document, profile: .topicMarkdown) == snapshot)
        }
    }

    @Test("One document snapshot retains independently recorded token locations and exact bytes", arguments: ["\n", "\r\n", "\r"])
    func exactCoordinates(newline: String) throws {
        var source = LocatedSource()
        source.append("\u{FEFF}---")
        source.newline(newline)
        let keywordsKey = source.append("keywords")
        source.append(": [")
        let repeated = "[[资料 🦉 e\u{301}]]"
        let first = source.append("'" + repeated + "'")
        source.append(", ")
        let second = source.append("'" + repeated + "'")
        source.append(", ")
        let escaped = source.append(#""\u4E2D \U0001F989""#)
        source.append("]")
        source.newline(newline)
        let summaryKey = source.append("summary")
        source.append(": ")
        let summaryStart = source.location
        source.append("|-")
        source.newline(newline)
        source.append("  第一行 🦉")
        source.newline(newline)
        source.append("  second e\u{301}")
        source.newline(newline)
        let summaryRange = source.range(from: summaryStart)
        let flagKey = source.append("flag")
        source.append(": ")
        let flag = source.append("'true'")
        source.newline(newline)
        source.append("---")
        source.newline(newline)
        let body = "[[Target]]{{annotation 🦉 e\u{301}}} without final newline"
        source.append(body)
        let document = NoteDocument(relativePath: "Exact.md", rawContent: source.text)
        let projection = SearchPropertyProjection(document: document)
        #expect(document.validationWarnings.isEmpty && projection.issues.isEmpty)
        let keywords = try #require(projection.entry(forExactKey: "keywords"))
        #expect(keywords.keySourceRange == keywordsKey)
        #expect(keywords.valueKind == .stringSequence)
        #expect(keywords.stringMembers.map(\.value) == [repeated, repeated, "中 🦉"])
        #expect(keywords.stringMembers.map(\.sourceRange) == [first, second, escaped])
        let summary = try #require(projection.entry(forExactKey: "summary"))
        #expect(summary.keySourceRange == summaryKey)
        #expect(summary.stringMembers.first?.value == "第一行 🦉\nsecond e\u{301}")
        #expect(summary.stringMembers.first?.sourceRange == summaryRange)
        #expect(projection.entry(forExactKey: "flag")?.keySourceRange == flagKey)
        #expect(projection.entry(forExactKey: "flag")?.valueKind == .string)
        #expect(projection.entry(forExactKey: "flag")?.stringMembers.first?.sourceRange == flag)
        #expect(document.parsedFrontmatter["flag"] == .string("true"))
        #expect(document.body == body && document.sourceBytes == Data(source.text.utf8))
        #expect(SearchPropertyProjection(document: document.withCitationSnapshot(nil)) == projection)

        let changedSource = source.text.replacingOccurrences(of: "资料", with: "新资料")
        let changed = NoteDocument(relativePath: document.relativePath, rawContent: changedSource)
        #expect(changed.fingerprint != document.fingerprint)
        #expect(
            SearchPropertyProjection(document: changed).textValues(forExactKey: "keywords") == [
                "[[新资料 🦉 e\u{301}]]", "[[新资料 🦉 e\u{301}]]", "中 🦉",
            ])
        #expect(projection.textValues(forExactKey: "keywords") == [repeated, repeated, "中 🦉"])
    }

    @Test("Absent, unclosed, empty and nonmapping YAML preserve their distinct projection states")
    func envelopeBoundaries() {
        let cases: [(String, [SearchPropertyProjection.Issue])] = [
            ("# Body\n\n---\nLater divider", []),
            ("\u{FEFF}---\r\nsummary: unclosed", [.invalidYAML]),
            ("---\n---\nBody", []),
            ("---\n# comment only\n---\nBody", []),
            ("---\n{}\n---\nBody", []),
            ("---\nnull\n---\nBody", [.nonMappingRoot]),
            ("---\n[one, two]\n---\nBody", [.nonMappingRoot]),
            ("---\nscalar\n---\nBody", [.nonMappingRoot]),
            ("---\na: 1\n'a': 2\n---\nBody", [.invalidYAML]),
        ]
        for (source, issues) in cases {
            let document = NoteDocument(relativePath: "Boundary.md", rawContent: source)
            let projection = SearchPropertyProjection(document: document)
            #expect(projection.entries.isEmpty && projection.issues == issues)
            #expect(document.sourceBytes == Data(source.utf8))
        }
    }

    @Test("Metadata construction cannot change a lexical special-key tag")
    func specialValueKey() {
        let source = "---\n=: value\nordinary: kept\n---\nBody"
        let document = NoteDocument(relativePath: "Special key.md", rawContent: source)
        #expect(document.parsedFrontmatter["="] == .string("value"))
        let projection = SearchPropertyProjection(document: document)
        #expect(projection.entry(forExactKey: "=") == nil)
        #expect(projection.issues == [.unboundedKey])
        #expect(projection.textValues(forExactKey: "ordinary") == ["kept"])
        #expect(document.sourceBytes == Data(source.utf8))
    }

    private struct LocatedSource {
        private(set) var text = ""
        private var offset = 0
        private var line = 1
        private var column = 1
        var location: (offset: Int, line: Int, column: Int) { (offset, line, column) }

        @discardableResult
        mutating func append(_ token: String) -> SearchSourceRange {
            let start = location
            text += token
            offset += token.utf16.count
            column += token.utf16.count
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
}
