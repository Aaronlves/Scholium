import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Related Material connection explanations")
struct RelatedMaterialGraphExplanationTests {
    private let english = Locale(identifier: "en")
    private let chinese = Locale(identifier: "zh-Hans")
    private let vault = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private func note(_ path: String) -> VaultQualifiedNoteID {
        .init(vaultID: vault, relativePath: path)
    }

    private func step(
        from start: VaultQualifiedNoteID, to end: VaultQualifiedNoteID,
        traversal: RelatedContentGraphTraversal
    ) -> RelatedContentGraphStep {
        let source = traversal == .outgoing ? start : end
        let destination = traversal == .outgoing ? end : start
        let span = SourceSpan(
            utf8LowerBound: 0, utf8UpperBound: 5, utf16LowerBound: 0, utf16UpperBound: 5,
            start: .init(line: 1, utf8Column: 1, utf16Column: 1),
            end: .init(line: 1, utf8Column: 6, utf16Column: 6))
        let occurrence = LinkOccurrence(
            syntax: .wikilink, target: destination.relativePath, alias: nil, fragment: nil,
            localContext: "Authored occurrence context must not become a generated explanation.",
            isExternal: false, span: span)
        return .init(source: source, destination: destination, occurrence: occurrence, traversal: traversal)
    }

    private func candidate(_ paths: [RelatedContentGraphPath]? = nil, proximity: Double = 0.9317) -> RelatedContentCandidate {
        .init(
            note: note("Candidate.md"), vaultRole: .topicKnowledge,
            title: "Candidate", fingerprint: .init(content: "Fixture paragraph."),
            reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: [])),
            graphContext: paths.map { .init(paths: $0, proximity: proximity) })
    }

    @Test("No graph context preserves the original passage action hint")
    func noGraphContext() {
        #expect(RelatedMaterialGraphExplanation.string(for: candidate(), locale: english) == nil)
        #expect(RelatedMaterialGraphExplanation.passageHint(for: candidate(), locale: english) == "Show this passage")
        #expect(RelatedMaterialGraphExplanation.string(for: candidate([]), locale: english) == nil)
    }

    @Test("Direct connection direction follows the authored occurrence, including reverse traversal")
    func directDirections() {
        let seed = note("Seed.md")
        let target = note("Candidate.md")
        for (direction, expectedEnglish, expectedChinese) in [
            (RelatedContentGraphTraversal.outgoing, "Direct outgoing connection.", "直接传出连接。"),
            (.incoming, "Direct incoming connection.", "直接传入连接。"),
        ] {
            let value = candidate([.init(steps: [step(from: seed, to: target, traversal: direction)])])
            #expect(RelatedMaterialGraphExplanation.string(for: value, locale: english) == expectedEnglish)
            #expect(RelatedMaterialGraphExplanation.string(for: value, locale: chinese) == expectedChinese)
        }
    }

    @Test("Two-step explanations retain compact Unicode identity and both traversal directions in each locale")
    func twoHopIdentityAndDirections() {
        let seed = note("Seed.md")
        let middle = note("Private directory/CUI's 控制😀.md")
        let target = note("Candidate.md")
        for (first, second, englishDirections, chineseDirections) in [
            (
                RelatedContentGraphTraversal.outgoing, RelatedContentGraphTraversal.outgoing,
                "outgoing link, then outgoing link", "先沿传出连接，再沿传出连接"
            ),
            (.outgoing, .incoming, "outgoing link, then incoming link", "先沿传出连接，再沿传入连接"),
            (.incoming, .outgoing, "incoming link, then outgoing link", "先沿传入连接，再沿传出连接"),
            (.incoming, .incoming, "incoming link, then incoming link", "先沿传入连接，再沿传入连接"),
        ] {
            let value = candidate([
                .init(steps: [
                    step(from: seed, to: middle, traversal: first),
                    step(from: middle, to: target, traversal: second),
                ])
            ])
            #expect(
                RelatedMaterialGraphExplanation.string(for: value, locale: english)
                    == "Connected via CUI's 控制😀: \(englishDirections).")
            #expect(
                RelatedMaterialGraphExplanation.string(for: value, locale: chinese)
                    == "经由“CUI's 控制😀”连接：\(chineseDirections)。")
        }
    }

    @Test("Repeated occurrences do not repeat their explanation or expose internal proximity")
    func deduplicatesExplanation() {
        let outgoing = RelatedContentGraphPath(steps: [step(from: note("Seed.md"), to: note("Candidate.md"), traversal: .outgoing)])
        let incoming = RelatedContentGraphPath(steps: [step(from: note("Seed.md"), to: note("Candidate.md"), traversal: .incoming)])
        let value = candidate([outgoing, outgoing, incoming])
        #expect(
            RelatedMaterialGraphExplanation.string(for: value, locale: english)
                == "Direct outgoing connection. Direct incoming connection.")
        #expect(
            RelatedMaterialGraphExplanation.string(for: value, locale: english)
                == RelatedMaterialGraphExplanation.string(for: candidate([outgoing, incoming], proximity: 0.1), locale: english))
        #expect(
            RelatedMaterialGraphExplanation.passageHint(for: value, locale: english)
                == "Show this passage\nDirect outgoing connection. Direct incoming connection.")
    }

    @Test("Invalid discontinuous, wrong-destination or overlong walks cannot manufacture an explanation")
    func invalidPaths() {
        let a = step(from: note("Seed.md"), to: note("Middle.md"), traversal: .outgoing)
        let b = step(from: note("Unrelated.md"), to: note("Candidate.md"), traversal: .incoming)
        let c = step(from: note("Middle.md"), to: note("Candidate.md"), traversal: .outgoing)
        for steps in [[], [a], [a, b], [a, c, c]] {
            #expect(RelatedMaterialGraphExplanation.string(for: candidate([.init(steps: steps)]), locale: english) == nil)
        }
    }
}
