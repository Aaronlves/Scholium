import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Recommended Bibliography duplicate discrimination")
struct BibliographyCandidateDiscriminatorTests {
    @Test("Verified identifiers mark but never merge probable duplicates")
    func verifiedIdentifierDuplicate() throws {
        let first = candidate(
            title: "The Sources of Normativity",
            authors: ["Christine Korsgaard"],
            doi: "https://doi.org/10.1000/example",
            metadataVerified: true
        )
        let second = candidate(
            title: "The Sources of Normativity",
            authors: ["Christine Korsgaard"],
            doi: "doi:10.1000/example",
            metadataVerified: true
        )

        let result = BibliographyCandidateDiscriminator.classify([first, second])
        #expect(result.count == 2)
        #expect(result[0].matchState == .unmatched)
        #expect(result[1].matchState == .duplicate)
        #expect(result[1].duplicateOfCandidateID == first.id)
        #expect(result[1].reason == second.reason)
    }

    @Test("Conflicting authors and chapter identities remain ambiguous")
    func conflictingIdentityIsAmbiguous() {
        let chapter = candidate(
            title: "Shared Title",
            authors: ["Chapter Author"],
            isChapter: true,
            containerTitle: "Edited Volume",
            editors: ["Volume Editor"]
        )
        let book = candidate(
            title: "Shared Title",
            authors: ["Different Author"],
            isChapter: false
        )

        let result = BibliographyCandidateDiscriminator.classify([chapter, book])
        #expect(result[1].matchState == .ambiguous)
        #expect(result[1].duplicateOfCandidateID == nil)
    }

    @Test("Complete chapter identity may be recognized without losing volume authorship")
    func completeChapterIdentity() {
        let first = candidate(
            title: "A Chapter",
            authors: ["Chapter Author"],
            isChapter: true,
            containerTitle: "The Volume",
            editors: ["Volume Editor"]
        )
        let second = candidate(
            title: "A Chapter",
            authors: ["Chapter Author"],
            isChapter: true,
            containerTitle: "The Volume",
            editors: ["Volume Editor"]
        )
        let result = BibliographyCandidateDiscriminator.classify([first, second])
        #expect(result[1].matchState == .duplicate)
        #expect(result[1].identity.authors == ["Chapter Author"])
        #expect(result[1].identity.editors == ["Volume Editor"])
    }

    @Test("A later update recognizes prior candidates and preserves dismissal")
    func duplicateAcrossUpdates() {
        let prior = candidate(
            title: "Prior Lead",
            authors: ["Complete Author"],
            doi: "10.1000/prior",
            metadataVerified: true
        ).deriving(matchState: .unmatched, isDismissed: true)
        let repeated = candidate(
            title: "Prior Lead",
            authors: ["Complete Author"],
            doi: "https://doi.org/10.1000/prior",
            metadataVerified: true
        )

        let result = BibliographyCandidateDiscriminator.classify(
            [repeated],
            against: [prior]
        )
        #expect(result[0].matchState == .duplicate)
        #expect(result[0].duplicateOfCandidateID == prior.id)
        #expect(result[0].isDismissed)
    }

    private func candidate(
        title: String,
        authors: [String],
        doi: String? = nil,
        metadataVerified: Bool = false,
        isChapter: Bool = false,
        containerTitle: String? = nil,
        editors: [String] = []
    ) -> RecommendedBibliographyCandidate {
        RecommendedBibliographyCandidate(
            identity: BibliographyCandidateIdentity(
                rawCitation: "\(authors.joined(separator: ", ")), \(title), 2020",
                title: title,
                authors: authors,
                year: 2020,
                doi: doi,
                isChapter: isChapter,
                containerTitle: containerTitle,
                editors: editors
            ),
            reason: "Inspect this reading lead.",
            evidence: BibliographyRecommendationEvidence(
                discussionStatus: .citedInText,
                metadataVerified: metadataVerified
            ),
            requiredNextCheck: "Inspect the complete source."
        )
    }
}
