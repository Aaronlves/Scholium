import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

struct ResearchLinkQueryTests {
    @Test("A late filter witness leads the preview while the authored occurrence stays bound")
    func lateFilter() throws {
        let source =
            "The authored [[Target|anchor]] comes first. "
            + String(repeating: "Background remains available. ", count: 20)
            + "This is not evidence of agreement. Its qualification matters."
        let occurrence = try #require(links(source).first)
        let ordinary = ResearchLinkPassage(occurrence: occurrence)
        let filtered = ResearchLinkPassage(occurrence: occurrence, query: "evidence")
        let preview = ResearchCompactExcerpt(text: filtered.text, matches: filtered.focus)

        #expect(filtered.authoredFocus == ordinary.focus)
        #expect(filtered.focus != filtered.authoredFocus)
        #expect(preview.text.contains("not evidence of agreement"))
        #expect(preview.text.hasPrefix("…"))
        #expect(try strings(filtered.highlights, in: filtered.text) == ["evidence"])
        #expect(try strings(preview.matches, in: preview.text) == ["evidence"])
        #expect(filtered.text == ordinary.text)
        #expect(ResearchLinkPassage(occurrence: occurrence, query: " ").focus == ordinary.focus)
    }

    @Test("Repeated labels remain separate authored occurrences under the same filter")
    func repeatedLabels() throws {
        let occurrences = links("[[Target|Same]] is not equivalent to the later [[Target|Same]]. Same words recur.")
        try #require(occurrences.count == 2)
        let first = ResearchLinkPassage(occurrence: occurrences[0], query: "same")
        let second = ResearchLinkPassage(occurrence: occurrences[1], query: "same")

        #expect(first.authoredFocus != second.authoredFocus)
        #expect(first.focus == second.focus)
        #expect(first.highlights.count == 3)
        #expect(try strings(first.highlights, in: first.text) == ["Same", "Same", "Same"])
        #expect(ResearchLinkPassage(occurrence: occurrences[0]).highlights.isEmpty)
        #expect(ResearchLinkPassage(occurrence: occurrences[1]).highlights.isEmpty)
        #expect(occurrences[0].linkSpan != occurrences[1].linkSpan)
    }

    @Test("Localized filter ranges preserve exact EN and ZH wording and Unicode offsets", arguments: ["cafe", "不是证据"])
    func localizedRanges(query: String) throws {
        let source =
            "👩🏽‍🔬 [[Target|出处]] " + String(repeating: "背景。", count: 80)
            + "cafe\u{301} 不是证据；仍须论证。CAFE\u{301} is not proof."
        let occurrence = try #require(links(source).first)
        let passage = ResearchLinkPassage(occurrence: occurrence, query: query)
        let preview = ResearchCompactExcerpt(text: passage.text, matches: passage.focus)

        #expect(passage.text.localizedStandardContains(query))
        #expect(!passage.highlights.isEmpty)
        #expect(preview.text.localizedStandardContains(query))
        let highlighted = try strings(passage.highlights, in: passage.text)
        let expected = query == "cafe" ? ["cafe\u{301}", "CAFE\u{301}"] : ["不是证据"]
        #expect(highlighted == expected)
        #expect(passage.text == ResearchExcerptPresentation.readableText(occurrence.localContext))
    }

    @Test("Canonically equivalent labels stay visually ambiguous until Find highlights its actual matches")
    func equivalentLabels() throws {
        let occurrences = links("[[A|café]] then [[B|cafe\u{301}]].")
        try #require(occurrences.count == 2)
        let first = ResearchLinkPassage(occurrence: occurrences[0])
        let second = ResearchLinkPassage(occurrence: occurrences[1])
        #expect(first.authoredFocus != second.authoredFocus)
        #expect(first.highlights.isEmpty && second.highlights.isEmpty)
        for occurrence in occurrences {
            let filtered = ResearchLinkPassage(occurrence: occurrence, query: "cafe")
            let highlights = try strings(filtered.highlights, in: filtered.text)
            #expect(highlights.map { Array($0.utf8) } == [Array("café".utf8), Array("cafe\u{301}".utf8)])
        }
    }

    @Test("A title or hidden-target match admits the row without inventing a body highlight")
    func titleOnly() throws {
        let vaultID = UUID()
        let source = NoteDocument(relativePath: "Source.md", rawContent: "The source links to [[Target|visible alias]].")
        let target = NoteDocument(relativePath: "Target.md", rawContent: "# Unique title\n\nUnrelated body.")
        let documents = [source, target]
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: documents.map { LinkCatalogNote(vaultID: vaultID, document: $0) },
            documents: Dictionary(
                uniqueKeysWithValues: documents.map {
                    (VaultQualifiedNoteID(vaultID: vaultID, relativePath: $0.relativePath), MarkdownSemanticDocument(parsing: $0))
                }), resolutionScope: .sourceVault)
        let peer = WorkspaceCatalogNote(
            reference: .init(vaultID: vaultID, vaultName: "Topics", vaultRole: .topicKnowledge, relativePath: target.relativePath),
            title: "Unique title", fingerprint: target.fingerprint, validationWarnings: [])
        let item = try #require(
            ConnectionsProjection.make(
                graph: graph, catalogNotes: [peer], current: .init(vaultID: vaultID, relativePath: source.relativePath), direction: .outgoing
            ).items.first)
        let unfiltered = ResearchLinkPassage(occurrence: item.edge.occurrence)
        for query in ["Unique title", "Target"] {
            #expect(item.matches(query))
            let filtered = ResearchLinkPassage(occurrence: item.edge.occurrence, query: query)
            #expect(filtered.highlights.isEmpty)
            #expect(filtered.focus == unfiltered.authoredFocus)
            #expect(filtered.text == unfiltered.text)
        }
    }

    @Test("An annotation-only match gets its own compact witness without a fake body match")
    func annotationOnly() throws {
        let source =
            "Before [[Target|anchor]]{{"
            + String(repeating: "Authored annotation context. ", count: 20)
            + "This is not corroboration; 不是佐证。}} after."
        let occurrence = try #require(links(source).first)
        let annotation = try #require(occurrence.annotation?.text)
        let body = ResearchLinkPassage(occurrence: occurrence, query: "corroboration")
        let ranges = ResearchLinkPassage.queryMatches(in: annotation, query: "corroboration")
        let preview = ResearchCompactExcerpt(text: annotation, matches: ranges)

        #expect(body.highlights.isEmpty)
        #expect(body.focus == body.authoredFocus)
        #expect(preview.text.contains("not corroboration"))
        #expect(preview.text.hasPrefix("…"))
        #expect(try strings(preview.matches, in: preview.text) == ["corroboration"])
        #expect(!body.text.contains("corroboration"))
    }

    private func links(_ source: String) -> [LinkOccurrence] {
        MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "Source.md", rawContent: source)).links
    }

    private func strings(_ ranges: [Range<Int>], in text: String) throws -> [String] {
        try ranges.map {
            String(text[try #require(Range(NSRange(location: $0.lowerBound, length: $0.count), in: text))])
        }
    }
}
