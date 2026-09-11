import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Paragraph retrieval")
struct RelatedPassageTests {
    @Test("Ranks exact paragraphs, keeps two from one Note, excludes neighbors and presents no link syntax")
    func paragraphs() throws {
        let vault = UUID()
        let source =
            "\u{FEFF}# A title with freedom\r\n\r\nUnrelated introductory material.\r\n\r\n**Freedom** and autonomy are distinct. [[Other|行动自由]] is a link.\r\n\r\nFreedom can conflict with autonomy in this synthetic example.\r\n\r\nFreedom can conflict with autonomy in this synthetic example.\r\n\r\nFreedom is incidental here.\r\n\r\nA wholly unrelated conclusion.\r\n"
        let document = NoteDocument(relativePath: "Source.md", rawContent: source)
        let candidate = RelatedContentCandidate(
            note: .init(vaultID: vault, relativePath: "Source.md"), vaultRole: .sourceCorpus,
            title: "Source", fingerprint: document.fingerprint,
            reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: [])))
        let seed = RelatedContentSeedSnapshot(
            noteID: .init(vaultID: vault, relativePath: "Draft.md"), source: "# Unsaved\n\nfreedom autonomy",
            focuses: [.init(kind: .selectedPassage, text: "freedom autonomy")])
        let passages = try TriptychSearchIndex.relatedPassages(.init(seed: seed), sources: [.init(candidate: candidate, document: document)])
        #expect(passages.count == 2)
        #expect(Set(passages.map(\.id)).count == 2)
        #expect(passages.allSatisfy { $0.candidate.note == candidate.note })
        for passage in passages {
            let range = try #require(
                Range(
                    NSRange(
                        location: passage.range.utf16LowerBound,
                        length: passage.range.utf16UpperBound - passage.range.utf16LowerBound), in: source))
            #expect(String(source[range]) == passage.source)
            #expect(!passage.displayText.contains("[[") && !passage.displayText.contains("**"))
            #expect(!passage.displayText.contains("Unrelated") && !passage.displayText.contains("conclusion"))
            #expect(passage.range.line == 1 + source[..<range.lowerBound].utf8.filter { $0 == 10 }.count)
        }
        #expect(passages.contains { $0.displayText.contains("行动自由") })
        let drifted = NoteDocument(relativePath: "Source.md", rawContent: source + "changed")
        #expect(try TriptychSearchIndex.relatedPassages(.init(seed: seed), sources: [.init(candidate: candidate, document: drifted)]).isEmpty)
    }

    @Test("A title or another paragraph matching does not make a nonmatching paragraph a result")
    func noNoteFallback() throws {
        let vault = UUID()
        let doc = NoteDocument(relativePath: "freedom.md", rawContent: "# freedom\n\nAn unrelated paragraph.\n\n```\nfreedom\n```\n")
        let candidate = RelatedContentCandidate(
            note: .init(vaultID: vault, relativePath: doc.relativePath), vaultRole: .sourceCorpus,
            title: "freedom", fingerprint: doc.fingerprint, reason: .identityMention(.init(mentions: [])))
        let seed = RelatedContentSeedSnapshot(
            noteID: .init(vaultID: vault, relativePath: "Draft.md"), source: "freedom",
            focuses: [.init(kind: .selectedPassage, text: "freedom")])
        #expect(try TriptychSearchIndex.relatedPassages(.init(seed: seed), sources: [.init(candidate: candidate, document: doc)]).isEmpty)
    }
}
