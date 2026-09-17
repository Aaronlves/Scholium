import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

/// Independent, synthetic policy regressions. These examples establish ordering
/// and redundancy behavior, not source authority or philosophical truth. Actor
/// candidate recall is measured separately by RelatedContentEvaluationTests.
@Suite("Writing recommendation policy regressions")
struct RelatedContentRecommendationPolicyTests {
    private let vaultID = UUID(uuidString: "CAF63AE8-3F47-471D-BF8D-C23C8D5CE33F")!

    @Test("Near-copy penalties cannot reward a weaker copy at the comparability boundary")
    func monotonicDiversity() {
        let values = (0...100).map { index in
            RelatedContentRecommendationPolicy.diverseScore(
                relevance: Double(index) / 100, strongest: 1,
                roleAlreadyRepresented: true, similarity: 0.9)
        }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test("A skipped duplicate does not consume a Note's first visible paragraph turn")
    func duplicateLeadingParagraphs() throws {
        let sources = (1...6).map {
            source("Note \($0).md", "Freedom autonomy.\n\nFreedom autonomy are considered in distinct example \($0).")
        }
        let results = try evaluate(sources, focus: "freedom autonomy")
        #expect(results.count == 6)
        #expect(Set(results.map { $0.candidate.note }).count == 6)
    }

    @Test("One distinctive concept can outrank three ubiquitous focus words")
    func distinctiveConceptSurvivesGeneralVocabulary() throws {
        let concept = source(
            "Z Concept.md",
            "Supervenience concerns whether one family of properties can differ without a difference in another.")
        let general = (1...12).map {
            source(
                "A General \($0).md",
                "The argument lists a reason and evidence for arranging the office meeting in room \($0).")
        }
        let results = try evaluate([concept] + general, focus: "argument reason evidence supervenience")
        #expect(results.first?.candidate.note.relativePath == "Z Concept.md")
        // Low raw coverage does not make the rare, central term ineligible.
        #expect(results.first?.matches.flatMap(\.terms).contains("supervenience") == true)
    }

    @Test("An explicitly quoted phrase prefers its original order over the same separate words")
    func quotedPhraseOrder() throws {
        // Identical vocabulary, word counts, role, and punctuation. The reverse
        // title sorts first without phrase evidence. Both remain relevant leads.
        let reverse = source("A Reversed.md", "A condition necessary for responsibility requires control.")
        let exact = source("Z Exact.md", "A necessary condition for responsibility requires control.")
        let results = try evaluate([reverse, exact], focus: "\"necessary condition\" responsibility")
        #expect(results.first?.candidate.note.relativePath == "Z Exact.md")
        #expect(Set(results.map { $0.candidate.note.relativePath }) == ["A Reversed.md", "Z Exact.md"])
    }

    @Test("Shared topic retrieves both a negated claim and its opposing assertion without changing their source")
    func negationRemainsVisible() throws {
        let negated = source("Negated.md", "Desire is not sufficient for a reason to act.")
        let affirmative = source("Affirmative.md", "Desire is sufficient for a reason to act.")
        let results = try evaluate([negated, affirmative], focus: "desire sufficient reason")
        #expect(Set(results.map { $0.candidate.note.relativePath }) == ["Negated.md", "Affirmative.md"])
        // Negation is philosophically material. Similarity or deduplication must
        // never collapse opposite assertions into a single apparent source.
        #expect(results.contains { $0.source == negated.document.rawContent })
        #expect(results.contains { $0.source == affirmative.document.rawContent })
    }

    @Test("Exact copies in different Notes leave room for distinct relevant material")
    func exactCopiesDoNotFillTheSidebar() throws {
        let repeated = "Freedom autonomy concern self-government."
        let copies = (1...8).map { source("A Copy \($0).md", repeated) }
        let distinction = source(
            "Z Distinction.md",
            "Freedom and autonomy differ when a person is free from external interference but cannot examine the commitments guiding a decision.")
        let question = source(
            "Z Question.md",
            "Freedom and autonomy raise a further question about whether collective decisions can preserve the agency of each participant.")
        let results = try evaluate(copies + [distinction, question], focus: "freedom autonomy")
        #expect(results.filter { $0.source == repeated }.count == 1)
        #expect(results.contains { $0.candidate.note.relativePath == "Z Distinction.md" })
        #expect(results.contains { $0.candidate.note.relativePath == "Z Question.md" })
        // The surviving passage retains one concrete authoring Note and revision,
        // rather than merging text or inventing a composite source identity.
        let retainedCopy = try #require(results.first { $0.source == repeated })
        #expect(copies.contains { $0.candidate == retainedCopy.candidate })
    }

    @Test("Near copies are demoted behind a distinct relevant passage")
    func nearCopiesLeaveRoomForAnotherIdea() throws {
        let nearCopies = (1...8).map {
            source(
                "A Variant \($0).md",
                "Freedom and autonomy concern a person's capacity to govern decisions, consider alternatives, and act without another person's control. Example number \($0)."
            )
        }
        let distinct = source(
            "Z Distinct.md",
            "Freedom and autonomy can come apart: a person may be free from interference while unable to examine whether a decision reflects their commitments. This distinction asks about the source of an action, rather than merely the range of available alternatives."
        )
        let results = try evaluate(nearCopies + [distinct], focus: "freedom autonomy")
        #expect(results.prefix(3).contains { $0.candidate.note.relativePath == "Z Distinct.md" })
        #expect(results.contains { $0.candidate.note.relativePath.hasPrefix("A Variant") })
    }

    private func source(_ path: String, _ text: String) -> RelatedContentSource {
        let document = NoteDocument(relativePath: path, rawContent: text)
        return .init(
            candidate: .init(
                note: .init(vaultID: vaultID, relativePath: path), vaultRole: .topicKnowledge,
                title: path, fingerprint: document.fingerprint,
                reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: []))),
            document: document)
    }

    private func evaluate(_ sources: [RelatedContentSource], focus: String) throws -> [RelatedContentPassage] {
        let request = RelatedContentRequest(
            seed: .init(
                noteID: .init(vaultID: vaultID, relativePath: "Current.md"), source: focus,
                focuses: [.init(kind: .selectedPassage, text: focus)]))
        let results = try TriptychSearchIndex.relatedPassages(request, sources: sources)
        #expect(try TriptychSearchIndex.relatedPassages(request, sources: sources.reversed()) == results)
        for passage in results {
            let source = try #require(sources.first { $0.candidate.note == passage.candidate.note })
            #expect(passage.candidate.fingerprint == source.document.fingerprint)
            #expect(passage.candidate.vaultRole == source.candidate.vaultRole)
            let range = try #require(
                Range(
                    NSRange(location: passage.range.utf16LowerBound, length: passage.range.utf16UpperBound - passage.range.utf16LowerBound),
                    in: source.document.rawContent))
            #expect(String(source.document.rawContent[range]) == passage.source)
        }
        return results
    }
}
