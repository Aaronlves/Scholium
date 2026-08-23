import Foundation
import Testing
@testable import ScholiumContracts

@Suite("Search property projection")
struct SearchPropertyProjectionTests {
    @Test("Indexes only authored YAML allowlist fields with exact source ranges")
    func authoredYAMLAllowlist() throws {
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

        #expect(projection.entries.map(\.key) == ["keywords", "summary"])
        #expect(projection.entry(forExactKey: "title") == nil)
        #expect(projection.entry(forExactKey: "custom") == nil)
        let summary = try #require(projection.entry(forExactKey: "summary"))
        let summaryRange = try #require(summary.stringMembers.first?.sourceRange)
        #expect(sourceText(source, in: summaryRange) == "A navigation summary")
        let keywords = try #require(projection.entry(forExactKey: "keywords"))
        #expect(keywords.stringMembers.map(\.value) == ["Akrasia", "Weakness of Will"])
        #expect(try keywords.stringMembers.map {
            sourceText(source, in: try #require($0.sourceRange))
        } == ["Akrasia", "\"Weakness of Will\""])
    }

    @Test("Managed fields are queryable without claiming Markdown source ranges")
    func managedMetadataHasNoSourceRanges() throws {
        let noteID = UUID()
        let record = NoteMetadataRecord(
            noteID: noteID,
            fields: [
                "type": .string("journal_article"),
                "language": .string("Ancient Greek"),
                "authors": .array([.object([
                    "family": .string("Scanlon"),
                ])]),
            ]
        )
        let metadata = NoteMetadataSnapshot(
            record: record,
            revision: DocumentFingerprint(data: try record.encodedPortableData())
        )
        let projection = SearchPropertyProjection(
            document: NoteDocument(
                relativePath: "Analysis.md",
                rawContent: "---\nsummary: Authored\nlegacy: exact\n---\n# Body\n"
            ),
            profile: .analysis,
            metadata: metadata
        )

        #expect(projection.entries.map(\.key)
            == ["authors", "language", "summary", "type"])
        let language = try #require(projection.entry(forExactKey: "language"))
        #expect(language.keySourceRange == nil)
        #expect(language.stringMembers.first?.value == "Ancient Greek")
        #expect(language.stringMembers.first?.sourceRange == nil)
        #expect(projection.entry(forExactKey: "legacy") == nil)
    }

    @Test("Search indexes resolved custom Metadata but ignores unmanaged record keys")
    func customMetadataRequiresCatalogAuthority() throws {
        let record = NoteMetadataRecord(
            noteID: UUID(),
            fields: [
                "argument_stage": .string("objection"),
                "unmanaged_record_key": .string("must stay hidden"),
            ]
        )
        let metadata = NoteMetadataSnapshot(
            record: record,
            revision: DocumentFingerprint(data: try record.encodedPortableData())
        )
        let catalog = NoteMetadataCatalog(customFieldsByRole: [
            .paperAnalysis: [
                MetadataFieldDefinition(key: "argument_stage", valueKind: .text),
            ],
        ])
        let projection = SearchPropertyProjection(
            document: NoteDocument(relativePath: "Analysis.md", rawContent: "Body\n"),
            profile: .analysis,
            metadata: metadata,
            metadataCatalog: catalog
        )

        #expect(projection.entry(forExactKey: "argument_stage")?.stringMembers
            .map(\.value) == ["objection"])
        #expect(projection.entry(forExactKey: "unmanaged_record_key") == nil)
    }

    @Test("Malformed YAML does not hide independent managed metadata")
    func malformedYAMLIsIndependent() throws {
        let record = NoteMetadataRecord(
            noteID: UUID(),
            fields: ["aliases": .array([.string("Practical agency")])]
        )
        let projection = SearchPropertyProjection(
            document: NoteDocument(
                relativePath: "Topic.md",
                rawContent: "---\nsummary: [unfinished\n---\nBody\n"
            ),
            profile: .topicMarkdown,
            metadata: NoteMetadataSnapshot(
                record: record,
                revision: DocumentFingerprint(data: try record.encodedPortableData())
            )
        )
        #expect(projection.entries.map(\.key) == ["aliases"])
        #expect(projection.issues == [.invalidYAML])
    }

    private func sourceText(_ text: String, in range: SearchSourceRange) -> String? {
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
