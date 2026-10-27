import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Paragraph matching projections")
struct ParagraphSearchMatchingTests {
    @Test("Existential truth retains every successful paragraph and ranking alternative")
    func completeRankingAlternatives() throws {
        let source = "\u{FEFF}# Heading\r\n\r\nAlpha beta.\r\n\r\nGamma delta.\r\n\r\nAlpha missing.\r\n\r\nAlpha beta gamma delta.\r\n"
        let document = stored(source)
        let ast = try parsed("paragraph:((alpha AND beta) OR (gamma AND delta))")
        let evaluation = SearchMatcher.evaluate(ast, document: document, linkMatches: [:])
        #expect(evaluation.truth == .yes)
        let matched = ast.matched(by: evaluation)
        let needles = SearchMatcher.normalizedNeedles(for: ast.expression)
        let ranking = SearchMatcher.paragraphRankingClauses(matched, document: document, normalizedNeedles: needles)
        #expect(ranking.map(\.value.text) == ["alpha", "beta", "gamma", "delta", "alpha", "beta", "gamma", "delta"])
        let witnesses = SearchMatcher.paragraphWitnesses(matched, document: document)
        #expect(witnesses.count == 3)
        let expected = ["Alpha beta.", "Gamma delta.", "Alpha beta gamma delta."]
        for (witness, text) in zip(witnesses, expected) {
            let range = (source as NSString).range(of: text)
            #expect(witness.range.utf16LowerBound == range.location)
            #expect(witness.range.utf16UpperBound == NSMaxRange(range))
        }
        // A partial prepared dictionary preserves the established fallback.
        #expect(SearchMatcher.paragraphRankingClauses(matched, document: document, normalizedNeedles: [:]).map(\.value.text) == ranking.map(\.value.text))
    }

    @Test("Failed alternatives and negated predicates never become ranking contributions")
    func successfulPositiveRankingOnly() throws {
        let document = stored("Alpha beta.\n\nAlpha gamma.\n\nGamma delta.")
        let ast = try parsed("paragraph:((alpha NOT beta) OR (gamma AND delta))")
        let evaluation = SearchMatcher.evaluate(ast, document: document, linkMatches: [:])
        #expect(evaluation.truth == .yes)
        #expect(
            SearchMatcher.paragraphRankingClauses(ast.matched(by: evaluation), document: document).map(\.value.text) == [
                "alpha", "gamma", "delta",
            ])
        let outer = try parsed("NOT paragraph:(alpha AND beta)")
        #expect(SearchMatcher.evaluate(outer, document: document, linkMatches: [:]).truth == .no)
        #expect(SearchMatcher.paragraphRankingClauses(outer, document: document).isEmpty)
    }

    @Test("Known witnesses and absent witnesses retain three-valued incomplete-corpus semantics")
    func incompleteCorpusTruth() throws {
        let document = stored("Alpha beta.", complete: false)
        for (query, expected) in [
            ("paragraph:(alpha AND beta)", SearchTruth.yes),
            ("paragraph:(missing)", .unknown),
            ("NOT paragraph:(missing)", .unknown),
            ("NOT paragraph:(alpha AND beta)", .no),
        ] {
            let ast = try parsed(query)
            #expect(SearchMatcher.evaluate(ast, document: document, linkMatches: [:]).truth == expected)
        }
        let alternative = try parsed("paragraph:(missing) OR body:alpha")
        let evaluation = SearchMatcher.evaluate(alternative, document: document, linkMatches: [:])
        #expect(evaluation.truth == .yes)
        #expect(SearchMatcher.paragraphRankingClauses(alternative.matched(by: evaluation), document: document).isEmpty)
        let complete = stored("Alpha beta.")
        #expect(SearchMatcher.evaluate(try parsed("paragraph:(missing)"), document: complete, linkMatches: [:]).truth == .no)
    }

    @Test("One witness projection retains annotation fields, exact Unicode source and fingerprint")
    func witnessPresentationFidelity() throws {
        let source = "\u{FEFF}# 中文😀\r\n\r\nalpha [[Target]]{{beta}}.\r\n\r\nalpha gamma.\r\n"
        let document = stored(source)
        let ast = try parsed("paragraph:(alpha AND beta)")
        let witnesses = SearchMatcher.paragraphWitnesses(ast, document: document)
        #expect(witnesses.count == 1)
        let fields = SearchMatcher.matchedFields(ast: ast, document: document, paragraphWitnesses: witnesses)
        #expect(fields.contains(.body) && fields.contains(.linkAnnotation))
        let freshness = SearchFreshnessToken.triptych(.init(triptychID: document.vaultID, sequence: 1, sourceManifestHash: "fixture"))
        let hit = NoteSearchResultBuilder.hit(
            candidate: .init(document: document, identityPriority: 10, lexicalRank: 0),
            ast: ast, freshness: freshness, linkMatches: [:])
        #expect(hit.matchedFields == fields)
        #expect(hit.fingerprint == DocumentFingerprint(data: Data(source.utf8)))
        #expect(hit.freshnessToken == freshness)
        let paragraph = (source as NSString).range(of: "alpha [[Target]]{{beta}}.")
        let actual = try #require(hit.paragraphRanges.first)
        #expect(hit.paragraphRanges.count == 1 && actual.utf16LowerBound == paragraph.location && actual.utf16UpperBound == NSMaxRange(paragraph))
        let locator = try #require(hit.sourceRange)
        #expect(locator.utf16LowerBound == paragraph.location && locator.utf16UpperBound == paragraph.location + 5)
        #expect(locator.line == 3 && locator.column == 1)
        #expect(!hit.highlights.isEmpty)
    }

    private func parsed(_ query: String) throws -> SearchQueryAST {
        let parsed = SearchQueryParser.parse(query)
        try #require(parsed.diagnostics.isEmpty)
        return try #require(parsed.ast)
    }

    private func stored(_ source: String, complete: Bool = true) -> StoredSearchDocument {
        let document = NoteDocument(relativePath: "Paragraphs.md", rawContent: source)
        let projection = SearchDocumentProjection(document: document)
        return .init(
            rowID: 1, vaultID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            vaultName: "Synthetic", vaultRole: .topicKnowledge, relativePath: document.relativePath, stableNoteID: nil,
            title: projection.title, normalizedTitle: SearchTextNormalization.normalize(projection.title),
            filenameKey: "paragraphs", pathKey: "paragraphs.md", aliases: projection.aliases,
            calloutRoles: projection.calloutRoles, hasBrokenLink: false, fingerprint: document.fingerprint,
            evidentialLayer: .topicNote, roleOrder: 1, sourceLineStarts: projection.sourceLineStartsUTF16,
            segments: projection.segments, paragraphs: projection.paragraphs, paragraphsAreComplete: complete,
            properties: [], propertyIssues: [])
    }
}
