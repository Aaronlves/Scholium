import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related passage ranking projection fidelity")
struct RelatedPassageRankingProjectionTests {
    private struct Fixture {
        let path: String
        let source: String
    }

    private struct FrozenMaterial: Encodable {
        let noteScoringDocument: RelatedContentBM25F.Document
        let paragraphs: [RelatedContentSourceProjection.Paragraph]
    }

    @Test("Passage preparation retains scored fields and excludes Search-only identity and metadata", arguments: [false, true])
    func passageFieldBoundary(usesAttribution: Bool) throws {
        let body = usesAttribution ? "retainedbody [[Target|retainedlink]]{{retainedannotation}}." : "retainedbody."
        let source = """
            ---
            title: ignoredtitle
            aliases: [ignoredalias]
            authors: [ignoredauthor]
            publication_date: '1999-12-31'
            summary: retainedsummary
            keywords: [retainedkeyword]
            ---
            # retainedheading

            \(body)
            """
        let document = NoteDocument(relativePath: "Folder/Cafe\u{301}-ignoredfilename.md", rawContent: source)
        let prepared = SearchDocumentProjection.preparePassageRanking(document: document)
        let fields = RelatedContentBM25F.Document(rankingText: prepared.rankingText).fields
        #expect(fields["summary"] == "retainedsummary")
        #expect(fields["keyword"] == "retainedkeyword")
        #expect(fields["heading"] == "retainedheading")
        #expect(fields["body"]?.contains("retainedbody") == true)
        if usesAttribution {
            #expect(fields["link"] == "retainedlink")
            #expect(fields["annotation"] == "retainedannotation")
        } else {
            #expect(fields["link"] == nil && fields["annotation"] == nil)
        }
        let allText = fields.values.joined(separator: " ")
        for excluded in ["ignoredtitle", "ignoredalias", "ignoredauthor", "1999-12-31", "ignoredfilename"] {
            #expect(!allText.contains(excluded))
        }
        let complete = SearchDocumentProjection(document: document)
        #expect(complete.title.utf8.elementsEqual("Cafe\u{301}-ignoredfilename".utf8))
        #expect(complete.aliases == ["ignoredalias"] && complete.authors == ["ignoredauthor"])
        #expect(complete.publicationDate == "1999-12-31")
        #expect(complete.segments.contains { $0.field == .title && $0.text == "ignoredtitle" })
        let old = SearchDocumentProjection.prepareSourceSegments(document: document)
        let expected = try frozenScoringDocument(
            segments: old.segments.filter {
                $0.sourceRange != nil && $0.field != .title && $0.field != .alias
            })
        #expect(try Self.encoder().encode(RelatedContentBM25F.Document(rankingText: prepared.rankingText)) == Self.encoder().encode(expected))
        #expect(document.sourceBytes == Data(source.utf8))
    }

    @Test("Ranking-only snippets match the complete source-segment route")
    func snippetRankingParity() throws {
        let encoder = Self.encoder()
        for fixture in Self.fixtures {
            let document = NoteDocument(relativePath: fixture.path, rawContent: fixture.source)
            let old = SearchDocumentProjection.prepareSourceSegments(document: document)
            let current = SearchDocumentProjection.preparePassageRanking(document: document)
            let segments = old.segments.filter {
                $0.sourceRange != nil && $0.field != .title && $0.field != .alias
            }
            let expected = try frozenScoringDocument(segments: segments)
            let actual = RelatedContentBM25F.Document(rankingText: current.rankingText)
            #expect(try encoder.encode(actual) == encoder.encode(expected))
            #expect(try encoder.encode(current.semantic) == encoder.encode(old.semantic))
            #expect(current.semantic.fingerprint == document.fingerprint)
            #expect(document.sourceBytes == Data(fixture.source.utf8))
        }
    }

    @Test(
        "Complete passage material preserves frozen encoding, readable text, indexes and exact ranges",
        arguments: [VaultRole.sourceCorpus, .topicKnowledge, .draftProject, .other])
    func completeMaterialParity(role: VaultRole) throws {
        let encoder = Self.encoder()
        let vaultID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        for fixture in Self.fixtures {
            let document = NoteDocument(relativePath: fixture.path, rawContent: fixture.source)
            let source = SearchIndexDocument(
                vaultID: vaultID, vaultName: "Synthetic parity", vaultRole: role, document: document)
            let prepared = PreparedSearchIndexDocument(source: source, cache: nil)
            let expected = try frozenMaterial(prepared)
            let expectedBytes = try encoder.encode(expected)
            let production = try RelatedContentSourceProjection(prepared: prepared)
            let standalone = try RelatedContentSourceProjection(document: document)
            #expect(try encoder.encode(production) == expectedBytes)
            #expect(try encoder.encode(standalone) == expectedBytes)
            try expectParagraphs(production.paragraphs, equalTo: expected.paragraphs, encoder: encoder)
            try expectParagraphs(standalone.paragraphs, equalTo: expected.paragraphs, encoder: encoder)
            // The same exact snippet source, path and semantic fingerprint own
            // every preparation; no derived text can replace those identities.
            #expect(prepared.source.document.sourceBytes == Data(fixture.source.utf8))
            #expect(prepared.source.document.relativePath.utf8.elementsEqual(fixture.path.utf8))
            #expect(prepared.source.semantic.fingerprint == document.fingerprint)
            for paragraph in production.paragraphs {
                let range = try #require(
                    Range(
                        NSRange(
                            location: paragraph.range.utf16LowerBound,
                            length: paragraph.range.utf16UpperBound - paragraph.range.utf16LowerBound),
                        in: document.rawContent))
                #expect(!document.rawContent[range].isEmpty)
            }
        }
    }

    /// Freeze the old route: each admitted nested paragraph is sliced from
    /// exact source and independently prepares full Search segments, including
    /// coordinates and attribution, before the original passage filter.
    private func frozenMaterial(_ prepared: PreparedSearchIndexDocument) throws -> FrozenMaterial {
        let document = prepared.source.document
        var paragraphs: [RelatedContentSourceProjection.Paragraph] = []
        for block in prepared.source.semantic.blocks where block.kind == .paragraph {
            guard block.span.utf16Range.count <= RelatedContentContract.maximumPassageUTF16Count,
                let range = Range(block.span.nsRange, in: document.rawContent)
            else { continue }
            let snippet = NoteDocument(
                relativePath: document.relativePath, rawContent: String(document.rawContent[range]))
            let old = SearchDocumentProjection.prepareSourceSegments(document: snippet)
            let display = ResearchExcerptPresentation.readableText(
                document: snippet, semantic: old.semantic, includingAnnotations: true)
            let normalized = SearchTextNormalization.lexicalNormalize(display)
            let segments = old.segments.filter {
                $0.sourceRange != nil && $0.field != .title && $0.field != .alias
            }
            paragraphs.append(
                .init(
                    range: .init(
                        utf16LowerBound: block.span.utf16LowerBound,
                        utf16UpperBound: block.span.utf16UpperBound,
                        line: block.span.start.line, column: block.span.start.utf16Column,
                        endLine: block.span.end.line, endColumn: block.span.end.utf16Column),
                    displayText: display, normalizedDisplayText: normalized,
                    textIndex: .init(normalized),
                    scoringDocument: try frozenScoringDocument(segments: segments)))
        }
        return FrozenMaterial(
            noteScoringDocument: try frozenScoringDocument(segments: prepared.projection.segments),
            paragraphs: paragraphs)
    }

    /// Independent pre-change BM25 input aggregation. Keep newlines, segment
    /// order, field lengths and tokenizer indexes outside the new initializer.
    private func frozenScoringDocument(segments: [SearchTextSegment]) throws -> RelatedContentBM25F.Document {
        var result: [String: String] = [:]
        for segment in segments {
            for (field, text) in segment.relatedRankingText {
                result[field, default: ""] += "\n" + text
            }
        }
        let fields = result.mapValues(SearchTextNormalization.lexicalNormalize)
        let indexes = fields.mapValues(RelatedContentTextIndex.init)
        let lengths = fields.mapValues { text in
            Double(
                text.split { !$0.isLetter && !$0.isNumber }.reduce(0) { total, word in
                    let ascii = word.utf8.allSatisfy {
                        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                    }
                    return total + (ascii ? 1 : SearchTokenization.queryTokens(for: String(word)).count)
                })
        }
        return try .init(
            stored: .init(
                fields: fields, fieldLengths: lengths, textIndexes: indexes.mapValues(\.stored)))
    }

    private func expectParagraphs(
        _ actual: [RelatedContentSourceProjection.Paragraph],
        equalTo expected: [RelatedContentSourceProjection.Paragraph], encoder: JSONEncoder
    ) throws {
        try #require(actual.count == expected.count)
        for (actual, expected) in zip(actual, expected) {
            #expect(actual.range == expected.range)
            #expect(actual.displayText.utf8.elementsEqual(expected.displayText.utf8))
            #expect(actual.normalizedDisplayText.utf8.elementsEqual(expected.normalizedDisplayText.utf8))
            #expect(actual.exactReadableText.utf8.elementsEqual(expected.exactReadableText.utf8))
            #expect(try encoder.encode(actual.textIndex) == encoder.encode(expected.textIndex))
            #expect(try encoder.encode(actual.scoringDocument) == encoder.encode(expected.scoringDocument))
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var fixtures: [Fixture] {
        let oversized = "A" + String(repeating: "\u{301}", count: 80)
        return [
            .init(
                path: "Cafe\u{301}.md",
                source:
                    "\u{FEFF}---\r\ntitle: 'Authored Café'\r\naliases: ['別名', 'Cafe\u{301}']\r\n"
                    + "summary: 'A distinct authored summary'\r\nkeywords: [自由, reason]\r\n"
                    + "unknown: retained\r\n---\r\n# Heading 🦉\r\n\r\n"
                    + "Repeated 研究 CAFÉ é e\u{301} ß ﬃ İ Σςσ ＡＢＣ 👩‍🔬.\r\n\r\n"
                    + "Second paragraph with \(oversized) and exact source.\r\n"),
            .init(
                path: "Fragments.md",
                source:
                    "Before **CAFÉ cafe\u{301}** *ß ﬃ* `literal` &amp; 研究.\n\n"
                    + "\u{301} \u{301} \u{301}\n\nWord \u{301}word é e\u{301} end.\n"),
            .init(
                path: "Links.md",
                source:
                    "Body [[Target|CAFÉ]]{{Authored *cafe\u{301}* reason}} after.\n\n"
                    + "[External **label**](https://example.test) and ![[Embedded|visible]] remain local prose.\n\n"
                    + "[[Nested|link]]{{Context [[Other|中文]] and **É**.}}\n"),
            .init(
                path: "Nested.md",
                source:
                    "> Quoted **É** paragraph.\n>\n> Another quoted paragraph.\n\n"
                    + "- First list paragraph.\n\n  Continued list paragraph cafe\u{301}.\n\n"
                    + "  - Nested list paragraph 研究.\n\n"
                    + "> [!cite] Authored title\n> First callout **paragraph**.\n>\n> Second callout paragraph.\n"),
            .init(
                path: "Attributed-nested.md",
                source:
                    "> [!cite] Visible callout\n> First [[Quoted|行动]]{{Quoted annotation}}.\n>\n"
                    + "> Second paragraph with [external](https://example.test).\n\n"
                    + "Body uses a footnote[^a].\n\n"
                    + "[^a]: Footnote [[Target|É]]{{Nested annotation}} and **cafe\u{301}**.\n"),
            .init(
                path: "Malformed.md",
                source:
                    "---\ntitle: one\ntitle: two\n---\n\nBody <!-- hidden --> [[broken]]{{unclosed.\n\n"
                    + "$$x+y$$\n\nFinal paragraph without a newline"),
            .init(path: "Empty.md", source: "\u{FEFF}\r\n"),
        ]
    }
}
