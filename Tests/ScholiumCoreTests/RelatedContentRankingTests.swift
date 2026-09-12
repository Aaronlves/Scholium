import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related content field ranking")
struct RelatedContentRankingTests {
    private func projection(_ source: String) -> SearchDocumentProjection {
        SearchDocumentProjection(document: NoteDocument(relativePath: "Fixture.md", rawContent: source))
    }

    @Test("YAML-only matches never manufacture a useful paragraph")
    func propertyMaterial() throws {
        let vault = UUID()
        let document = NoteDocument(
            relativePath: "Property.md",
            rawContent:
                "\u{FEFF}---\r\nsummary: >-\r\n  needle freedom\r\nkeywords: [needle, freedom]\r\nunknown: secret\r\n---\r\n\r\nUnrelated prose.\r\n")
        let candidate = RelatedContentCandidate(
            note: .init(vaultID: vault, relativePath: document.relativePath),
            vaultRole: .sourceCorpus, title: "Property", fingerprint: document.fingerprint,
            reason: .lexicalOverlap(.init(matchedFields: [.summary], seedMatches: [])))
        let request = RelatedContentRequest(
            seed: .init(
                noteID: .init(vaultID: vault, relativePath: "Draft.md"),
                source: "needle freedom", focuses: [.init(kind: .selectedPassage, text: "needle freedom")]))
        let result = try TriptychSearchIndex.relatedPassages(request, sources: [.init(candidate: candidate, document: document)])
        #expect(result.isEmpty)
    }

    @Test("YAML ranks Notes but only relevant authored paragraphs are returned")
    func noteContextAndParagraphSelection() throws {
        let vault = UUID()
        func source(_ name: String, _ text: String) -> RelatedContentSource {
            let document = NoteDocument(relativePath: name, rawContent: text)
            let candidate = RelatedContentCandidate(
                note: .init(vaultID: vault, relativePath: name),
                vaultRole: .sourceCorpus, title: name, fingerprint: document.fingerprint,
                reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: [])))
            return .init(candidate: candidate, document: document)
        }
        let sources = [
            source("A Plain.md", "needle freedom first discussion.\n\nneedle freedom second discussion."),
            source(
                "Z Focused.md",
                "---\nsummary: needle freedom\nkeywords: [needle, freedom]\n---\n\nUnrelated introduction.\n\nneedle freedom first discussion.\n\nneedle freedom second discussion."
            ),
            source("Metadata Only.md", "---\nsummary: needle freedom\n---\n\nUnrelated introduction."),
        ]
        let request = RelatedContentRequest(
            seed: .init(
                noteID: .init(vaultID: vault, relativePath: "Draft.md"),
                source: "needle freedom", focuses: [.init(kind: .selectedPassage, text: "needle freedom")]))
        let result = try TriptychSearchIndex.relatedPassages(request, sources: sources)
        #expect(result.count == 4)
        #expect(result.map(\.candidate.note.relativePath) == ["Z Focused.md", "A Plain.md", "Z Focused.md", "A Plain.md"])
        #expect(result.allSatisfy { !$0.source.contains("summary:") && !$0.source.contains("Unrelated") })
        #expect(try TriptychSearchIndex.relatedPassages(request, sources: sources.reversed()) == result)
        for passage in result {
            let original = try #require(sources.first { $0.candidate.note == passage.candidate.note })
            let range = try #require(
                Range(
                    NSRange(
                        location: passage.range.utf16LowerBound,
                        length: passage.range.utf16UpperBound - passage.range.utf16LowerBound), in: original.document.rawContent))
            #expect(String(original.document.rawContent[range]) == passage.source)
        }
    }

    @Test("Authored annotation, link label and content YAML outrank plain body")
    func fieldPreference() throws {
        let sources = ["needle", "---\nsummary: needle\n---\n", "[[Target|needle]]", "[[Target]]{{needle}}"]
        let scores = try RelatedContentBM25F.scores(documents: sources.map { .init(segments: projection($0).segments) }, terms: ["needle"])
        #expect(scores[0] < scores[1])
        #expect(scores[1] < scores[2])
        #expect(scores[2] < scores[3])
    }

    @Test("Unrelated body length does not dilute a matching annotation")
    func independentLengths() throws {
        let short = projection("[[Target]]{{needle}}")
        let long = projection("[[Target]]{{needle}}\n\n" + String(repeating: "unrelated text ", count: 300))
        let scores = try RelatedContentBM25F.scores(documents: [short, long].map { .init(segments: $0.segments) }, terms: ["needle"])
        #expect(abs(scores[0] - scores[1]) < 0.000001)
    }

    @Test("Source attribution excludes link destinations and duplicate annotation prose")
    func ownership() throws {
        let p = projection("> [!note]\n> [[HiddenTarget|visible]]{{uniqueannotation}} ordinary\n")
        let fields = RelatedContentBM25F.Document(segments: p.segments).fields
        #expect(fields["annotation"]?.contains("uniqueannotation") == true)
        #expect(fields["link"]?.contains("visible") == true)
        #expect(fields["body"]?.contains("uniqueannotation") != true)
        #expect(fields["body"]?.contains("visible") != true)
        #expect(fields.values.allSatisfy { !$0.contains("hiddentarget") })
    }

    @Test("Dates and unknown YAML do not contribute to default topic ranking")
    func nonTopicProperties() throws {
        let p = projection("---\nauthor: needle\npublication_date: needle\nstatus: needle\n---\nordinary")
        let scores = try RelatedContentBM25F.scores(documents: [.init(segments: p.segments)], terms: ["needle"])
        #expect(scores == [0])
    }

    @Test("Paragraph ranking follows fields and preserves exact CRLF source")
    func passageOrder() throws {
        let vault = UUID()
        let document = NoteDocument(
            relativePath: "Fixture.md",
            rawContent:
                "needle ordinary.\r\n\r\n[[Target|needle]] ordinary.\r\n\r\n[[Target]]{{needle}} ordinary.\r\n")
        let candidate = RelatedContentCandidate(
            note: .init(vaultID: vault, relativePath: document.relativePath),
            vaultRole: .sourceCorpus, title: "Fixture", fingerprint: document.fingerprint,
            reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: [])))
        let request = RelatedContentRequest(
            seed: .init(
                noteID: .init(vaultID: vault, relativePath: "Seed.md"),
                source: "needle", focuses: [.init(kind: .selectedPassage, text: "needle")]))
        let result = try TriptychSearchIndex.relatedPassages(request, sources: [.init(candidate: candidate, document: document)])
        #expect(result.count == 2)
        #expect(result.first?.source.contains("{{needle}}") == true)
        #expect(result.last?.source.contains("|needle]]") == true)
        for passage in result {
            let range = try #require(
                Range(
                    NSRange(
                        location: passage.range.utf16LowerBound,
                        length: passage.range.utf16UpperBound - passage.range.utf16LowerBound), in: document.rawContent))
            #expect(String(document.rawContent[range]) == passage.source)
        }
    }

    @Test("Chinese annotation retains preference without appended index tokens")
    func chinese() throws {
        let sources = ["行动自由", "[[目标]]{{行动自由}}"]
        let scores = try RelatedContentBM25F.scores(documents: sources.map { .init(segments: projection($0).segments) }, terms: ["行动", "自由"])
        #expect(scores.allSatisfy { $0.isFinite && $0 > 0 })
        #expect(scores[1] > scores[0])
    }
}
