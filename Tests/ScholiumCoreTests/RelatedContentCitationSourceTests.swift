import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Source-owned related content with citation companions")
struct RelatedContentCitationSourceTests {
    @Test("Citation authority never changes recommendation prose, ranking or exact source locators")
    func sourceOnlyParity() throws {
        let vaultID = UUID()
        let decoy = "companiononlyneedle"
        let citationCode =
            #"ITEM CSL_CITATION {"citationItems":[{"id":"http://zotero.org/users/1/items/ABCDEFGH"}]}"#
        let bibliographyCode = "BIBL {} CSL_BIBLIOGRAPHY"
        let companion = ZoteroCitationData(
            fields: [
                .init(id: "one", kind: .citation, code: citationCode, text: decoy),
                .init(id: "two", kind: .citation, code: citationCode, text: decoy),
                .init(id: "bib", kind: .bibliography, code: bibliographyCode, text: decoy),
            ], documentData: decoy,
            acceptedFields: [
                .init(id: "one", code: citationCode), .init(id: "two", code: citationCode),
                .init(id: "bib", code: bibliographyCode),
            ])
        try companion.validate()
        func encoded(_ object: [String: Any]) throws -> String {
            try JSONSerialization.data(withJSONObject: object).base64EncodedString()
        }
        let compactParagraph =
            "[Freedom](cite:one) and [Freedom](cite:two) clarify agency 自由 with 😀 e\u{301}. "
            + "[[Method|research]]{{authored scope}} considers compact inquiry."
        let embeddedCitationPayload = try encoded([
            "id": "one", "kind": "citation", "code": citationCode, "text": decoy,
        ])
        let embeddedLink = "[Freedom](scholium-zotero:1:\(embeddedCitationPayload))"
        let embeddedParagraph = "\(embeddedLink) clarifies agency 自由 with 😀 e\u{301} in embedded inquiry."
        let embeddedBibliographyPayload = try encoded([
            "id": "bib", "kind": "bibliography", "code": bibliographyCode, "text": decoy,
        ])
        let embeddedBibliography = "<!--scholium-zotero-field:1:\(embeddedBibliographyPayload)-->"
        let embeddedStatePayload = try encoded([
            "data": decoy,
            "acceptedFields": [["id": "one", "code": citationCode], ["id": "bib", "code": bibliographyCode]],
        ])
        let embeddedState = "<!--scholium-zotero-document:1:\(embeddedStatePayload)-->"
        let prefix = "\u{FEFF}---\r\nsummary: agency 自由\r\nunknown: 'preserve' # source trivia\r\n---\r\n\r\n"
        let fixtures: [(path: String, source: String, expectedParagraph: String)] = [
            (
                "Compact.md",
                prefix + compactParagraph
                    + "\r\n\r\n<!--cite-bibliography:bib-->\r\n\r\nReader. *Source study*.\r\n\r\n<!--/cite-bibliography-->\r\n",
                compactParagraph
            ),
            (
                "Embedded.md",
                prefix + embeddedParagraph + "\r\n\r\n" + embeddedBibliography
                    + "\r\n\r\nAuthor. *Printed study*.\r\n\r\n<!--/scholium-zotero-field-->\r\n\r\n" + embeddedState + "\r\n",
                embeddedParagraph
            ),
        ]
        let sourceOnly = fixtures.map { NoteDocument(relativePath: $0.path, rawContent: $0.source) }
        let noteIDs = Dictionary(uniqueKeysWithValues: fixtures.map { ($0.path, UUID()) })
        #expect(!fixtures.contains { $0.source.contains(decoy) })
        #expect(ZoteroMarkdownFields(parsing: sourceOnly[1]).canMutate)

        func source(_ document: NoteDocument) -> RelatedContentSource {
            .init(
                candidate: .init(
                    note: .init(vaultID: vaultID, relativePath: document.relativePath),
                    vaultRole: .sourceCorpus, title: document.relativePath, fingerprint: document.fingerprint,
                    reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: []))),
                document: document)
        }
        func request(_ focus: String) -> RelatedContentRequest {
            .init(
                seed: .init(
                    noteID: .init(vaultID: vaultID, relativePath: "Draft.md"), source: focus,
                    focuses: [.init(kind: .selectedPassage, text: focus)]))
        }
        let visibleRequest = request("agency 自由")
        let expected = try TriptychSearchIndex.relatedPassages(visibleRequest, sources: sourceOnly.map(source))
        #expect(expected.count == fixtures.count)
        #expect(Set(expected.map { $0.candidate.note.relativePath }) == Set(fixtures.map(\.path)))
        for passage in expected {
            let fixture = try #require(fixtures.first { $0.path == passage.candidate.note.relativePath })
            #expect(passage.candidate.note.vaultID == vaultID)
            #expect(passage.candidate.fingerprint == DocumentFingerprint(content: fixture.source))
            #expect(passage.source.utf8.elementsEqual(fixture.expectedParagraph.utf8))
            let range = try #require(
                Range(
                    NSRange(
                        location: passage.range.utf16LowerBound,
                        length: passage.range.utf16UpperBound - passage.range.utf16LowerBound), in: fixture.source))
            #expect(String(fixture.source[range]).utf8.elementsEqual(fixture.expectedParagraph.utf8))
            #expect(passage.displayText.contains("agency 自由"))
            #expect(!passage.displayText.contains(decoy))
        }
        #expect(try TriptychSearchIndex.relatedPassages(request(decoy), sources: sourceOnly.map(source)).isEmpty)

        // Five small corpus variants exercise valid compact authority, checked
        // absence, failed loads, unsupported authority and an outdated source binding.
        for variant in 0..<5 {
            let attached = sourceOnly.map { document in
                let noteID = noteIDs[document.relativePath]!
                let snapshot: ZoteroCitationSnapshot
                switch variant {
                case 0: snapshot = .init(noteID: noteID, vaultID: vaultID, status: .absent)
                case 1:
                    snapshot = .init(
                        noteID: noteID, vaultID: vaultID, revision: DocumentFingerprint(content: "companion revision"),
                        sourceFingerprint: document.fingerprint, data: companion, status: .available)
                case 2: snapshot = .init(noteID: noteID, vaultID: vaultID, status: .unresolved)
                case 3: snapshot = .init(noteID: noteID, vaultID: vaultID, status: .unsupported)
                default:
                    snapshot = .init(
                        noteID: noteID, vaultID: vaultID, revision: DocumentFingerprint(content: "companion revision"),
                        sourceFingerprint: DocumentFingerprint(content: document.rawContent + "\n"), data: companion, status: .available)
                }
                return document.withCitationSnapshot(snapshot)
            }
            if variant == 1 {
                #expect(ZoteroMarkdownFields(parsing: attached[0]).canMutate)
                #expect(ZoteroMarkdownFields(parsing: attached[0]).fields.count == companion.fields.count)
            } else {
                #expect(!ZoteroMarkdownFields(parsing: attached[0]).canMutate)
            }
            for (bare, managed) in zip(sourceOnly, attached) {
                #expect(managed.sourceBytes == bare.sourceBytes)
                #expect(managed.fingerprint == bare.fingerprint)
                #expect(SearchDocumentProjection(document: managed) == SearchDocumentProjection(document: bare))
                let actual = try RelatedContentSourceProjection(document: managed)
                let reference = try RelatedContentSourceProjection(document: bare)
                expectEqual(actual.noteScoringDocument, reference.noteScoringDocument)
                #expect(actual.paragraphs.count == reference.paragraphs.count)
                for (actual, reference) in zip(actual.paragraphs, reference.paragraphs) {
                    #expect(actual.range == reference.range)
                    #expect(actual.displayText == reference.displayText)
                    #expect(actual.exactReadableText == reference.exactReadableText)
                    #expect(actual.normalizedDisplayText == reference.normalizedDisplayText)
                    #expect(actual.textIndex.containsCJK == reference.textIndex.containsCJK)
                    #expect(actual.textIndex.hasSameWordCounts(as: reference.textIndex))
                    expectEqual(actual.scoringDocument, reference.scoringDocument)
                }
            }
            #expect(try TriptychSearchIndex.relatedPassages(visibleRequest, sources: attached.map(source)) == expected)
            #expect(try TriptychSearchIndex.relatedPassages(request(decoy), sources: attached.map(source)).isEmpty)
        }
    }

    private func expectEqual(_ actual: RelatedContentBM25F.Document, _ reference: RelatedContentBM25F.Document) {
        #expect(actual.fields == reference.fields)
        #expect(actual.fieldLengths == reference.fieldLengths)
        #expect(Set(actual.textIndexes.keys) == Set(reference.textIndexes.keys))
        for (field, actual) in actual.textIndexes {
            let reference = reference.textIndexes[field]
            #expect(actual.containsCJK == reference?.containsCJK)
            #expect(reference.map { actual.hasSameWordCounts(as: $0) } == true)
        }
    }
}
