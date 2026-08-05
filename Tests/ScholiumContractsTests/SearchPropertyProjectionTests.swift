import Testing
@testable import ScholiumContracts

@Suite("Search property projection")
struct SearchPropertyProjectionTests {
    @Test("projects top-level presence and exact string source ranges")
    func projectsTopLevelStrings() throws {
        let document = NoteDocument(
            relativePath: "Topic.md",
            rawContent: """
            ---
            language: Ancient Greek
            aliases: [Akrasia, "Weakness of Will"]
            count: 3
            nested:
              language: Latin
            ---
            Body
            """
        )

        let projection = SearchPropertyProjection(document: document)
        #expect(projection.entries.map(\.key) == ["aliases", "count", "language", "nested"])

        let language = try #require(projection.entry(forExactKey: "language"))
        #expect(language.valueKind == .string)
        #expect(language.stringMembers.map(\.value) == ["Ancient Greek"])
        let languageRange = try #require(language.stringMembers.first?.sourceRange)
        #expect(source(document.rawContent, in: languageRange) == "Ancient Greek")

        let aliases = try #require(projection.entry(forExactKey: "aliases"))
        #expect(aliases.valueKind == .stringSequence)
        #expect(aliases.stringMembers.map(\.value) == ["Akrasia", "Weakness of Will"])
        #expect(aliases.stringMembers.map { source(document.rawContent, in: $0.sourceRange) }
            == ["Akrasia", "\"Weakness of Will\""])

        #expect(projection.entry(forExactKey: "Language") == nil)
        #expect(projection.entry(forExactKey: "nested")?.stringMembers.isEmpty == true)
        #expect(projection.entry(forExactKey: "nested")?.isEmpty == false)
    }

    @Test("does not coerce scalars or mixed arrays into exact string values")
    func excludesCoercionAndMixedArrays() throws {
        let document = NoteDocument(
            relativePath: "Topic.md",
            rawContent: """
            ---
            enabled: true
            year: 2026
            mixed: [claim, 3]
            empty: null
            blank: ""
            empty_list: []
            empty_map: {}
            ---
            """
        )
        let projection = SearchPropertyProjection(document: document)
        #expect(projection.entry(forExactKey: "enabled")?.valueKind == .scalar)
        #expect(projection.entry(forExactKey: "year")?.stringMembers.isEmpty == true)
        #expect(projection.entry(forExactKey: "mixed")?.valueKind == .sequence)
        #expect(projection.entry(forExactKey: "mixed")?.stringMembers.isEmpty == true)
        #expect(projection.entry(forExactKey: "empty")?.valueKind == .null)
        #expect(projection.entry(forExactKey: "empty")?.isEmpty == true)
        #expect(projection.entry(forExactKey: "blank")?.isEmpty == true)
        #expect(projection.entry(forExactKey: "empty_list")?.isEmpty == true)
        #expect(projection.entry(forExactKey: "empty_map")?.isEmpty == true)
    }

    @Test("fails closed when document validation rejects ambiguous keys")
    func rejectsAmbiguousKeys() {
        let duplicate = NoteDocument(
            relativePath: "Topic.md",
            rawContent: """
            ---
            language: Greek
            language: Latin
            "quoted key": value
            ---
            """
        )
        let projection = SearchPropertyProjection(document: duplicate)
        #expect(projection.entry(forExactKey: "language") == nil)
        #expect(projection.issues == [.invalidYAML])

        let quoted = SearchPropertyProjection(document: NoteDocument(
            relativePath: "Topic.md",
            rawContent: "---\n\"quoted key\": value\n---\n"
        ))
        #expect(quoted.entries.isEmpty)
        #expect(quoted.issues == [.unboundedKey])
    }

    @Test("preserves diacritics while folding case and whitespace")
    func valueNormalization() throws {
        let document = NoteDocument(
            relativePath: "Topic.md",
            rawContent: """
            ---
            concept: "  ÉTHIQUE  "
            ---
            """
        )
        let member = try #require(
            SearchPropertyProjection(document: document)
                .entry(forExactKey: "concept")?.stringMembers.first
        )
        #expect(member.normalizedValue == "éthique")
        #expect(member.normalizedValue != SearchTextNormalization.normalize("ethique"))
    }

    @Test("retains exact UTF-16 ranges through BOM, CRLF, emoji, and RTL values")
    func sourceFidelity() throws {
        let text = "\u{FEFF}---\r\nconcept: \"🧭 قيمة\"\r\n---\r\nBody\r\n"
        let member = try #require(
            SearchPropertyProjection(document: NoteDocument(
                relativePath: "Topic.md",
                rawContent: text
            )).entry(forExactKey: "concept")?.stringMembers.first
        )
        #expect(source(text, in: member.sourceRange) == "\"🧭 قيمة\"")
    }

    private func source(_ text: String, in range: SearchSourceRange) -> String? {
        guard let lower = text.utf16.index(
            text.utf16.startIndex,
            offsetBy: range.utf16LowerBound,
            limitedBy: text.utf16.endIndex
        ), let upper = text.utf16.index(
            text.utf16.startIndex,
            offsetBy: range.utf16UpperBound,
            limitedBy: text.utf16.endIndex
        ), let start = lower.samePosition(in: text),
           let end = upper.samePosition(in: text) else { return nil }
        return String(text[start..<end])
    }
}
