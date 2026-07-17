import Foundation
import ScholiumContracts
import Testing

@Suite("Recommended Bibliography boundary contracts")
struct RecommendedBibliographyContractsTests {
    @Test("Goals are canonical and an empty goal set remains neutral")
    func canonicalGoals() throws {
        let request = RecommendedBibliographyRequest(
            target: target(),
            goals: [.classicWorks, .objections, .classicWorks, .backgroundReading],
            purpose: "  map the objection literature  "
        )
        #expect(request.goals == [.backgroundReading, .objections, .classicWorks])
        #expect(request.purpose == "map the objection literature")
        try request.validate()

        let neutral = RecommendedBibliographyRequest(target: target(), purpose: "  ")
        #expect(neutral.goals.isEmpty)
        #expect(neutral.purpose == nil)
    }

    @Test("Zero recommendations is a valid completion")
    func zeroRecommendations() throws {
        let submission = RecommendedBibliographyCompletionSubmission(
            requestID: UUID(),
            confirmationToken: UUID(),
            targetFingerprint: target().fingerprint,
            sourceScope: "Paper bibliography and in-text citations",
            candidates: []
        )
        try submission.validate()
        #expect(try JSONDecoder().decode(
            RecommendedBibliographyCompletionSubmission.self,
            from: JSONEncoder().encode(submission)
        ) == submission)
    }

    @Test("Candidates preserve evidence layers and reject app-owned match state")
    func candidateEvidenceLayers() throws {
        let candidate = RecommendedBibliographyCandidate(
            identity: BibliographyCandidateIdentity(
                rawCitation: "A. Author, Chapter Title, 2020",
                title: "Chapter Title",
                authors: ["A. Author"],
                year: 2020,
                doi: "10.1000/example",
                isChapter: true,
                containerTitle: "An Edited Volume",
                editors: ["V. Editor"],
                edition: "First",
                translators: ["T. Translator"]
            ),
            goals: [.objections, .replies],
            reason: "The analyzed paper treats this chapter as the central objection.",
            possibleUse: "Inspect the objection before relying on the paper's reply.",
            uncertainty: "The chapter itself has not been inspected.",
            evidence: BibliographyRecommendationEvidence(
                discussionStatus: .substantivelyDiscussed,
                sourceLocators: ["pp. 14–17"],
                authorialFraming: .central,
                metadataVerified: true,
                sourceInspected: false,
                verificationProvenance: "Publisher metadata"
            ),
            requiredNextCheck: "Read the complete chapter in its edited volume."
        )
        _ = try candidate.validatedForSubmission()
        #expect(candidate.evidence.discussionStatus == .substantivelyDiscussed)
        #expect(candidate.evidence.metadataVerified)
        #expect(!candidate.evidence.sourceInspected)
        #expect(candidate.identity.containerTitle == "An Edited Volume")
        #expect(candidate.identity.editors == ["V. Editor"])

        #expect(throws: RecommendedBibliographyError.self) {
            _ = try candidate.deriving(
                matchState: .matchedZotero,
                matchedZoteroItemKey: "ABCD1234"
            ).validatedForSubmission()
        }
    }

    @Test("Malformed candidate and completion identities are rejected")
    func malformedCandidate() {
        let evidence = BibliographyRecommendationEvidence(
            discussionStatus: .referenceListOnly
        )
        #expect(throws: RecommendedBibliographyError.self) {
            _ = try RecommendedBibliographyCandidate(
                identity: BibliographyCandidateIdentity(rawCitation: ""),
                reason: "A reason",
                evidence: evidence,
                requiredNextCheck: "Check identity"
            ).validatedForSubmission()
        }
        #expect(throws: RecommendedBibliographyError.self) {
            try RecommendedBibliographyCompletionSubmission(
                requestID: UUID(),
                confirmationToken: UUID(),
                targetFingerprint: target().fingerprint,
                sourceScope: " ",
                candidates: []
            ).validate()
        }
    }

    @Test("Legacy candidate identities default newly added bibliographic distinctions")
    func legacyIdentityDefaults() throws {
        let data = Data(#"{"rawCitation":"A. Author, A Work, 2020","authors":["A. Author"],"year":2020}"#.utf8)
        let identity = try JSONDecoder().decode(BibliographyCandidateIdentity.self, from: data)

        #expect(identity.rawCitation == "A. Author, A Work, 2020")
        #expect(identity.authors == ["A. Author"])
        #expect(identity.editors.isEmpty)
        #expect(identity.translators.isEmpty)
        #expect(identity.containerTitle == nil)
        #expect(identity.edition == nil)
    }

    @Test("Legacy method snapshots decode without embedded resource sources")
    func legacyMethodSnapshotDefaultsRenderedResources() throws {
        let snapshot = RecommendedBibliographyMethodSnapshot(
            packageID: "scholium-source-analyzer",
            origin: .bundled,
            version: "1.1.0-template",
            packageRevision: DocumentFingerprint(content: "package"),
            loadedResources: [ResearchFunctionResourceSnapshot(
                relativePath: "SKILL.md",
                revision: DocumentFingerprint(content: "skill")
            )],
            renderedResources: [RecommendedBibliographyMethodResourceSnapshot(
                relativePath: "SKILL.md",
                revision: DocumentFingerprint(content: "skill"),
                source: "Skill source"
            )]
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot))
                as? [String: Any]
        )
        object.removeValue(forKey: "renderedResources")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(
            RecommendedBibliographyMethodSnapshot.self,
            from: legacy
        )

        #expect(decoded.loadedResources == snapshot.loadedResources)
        #expect(decoded.renderedResources.isEmpty)
    }

    private func target() -> RecommendedBibliographyTarget {
        RecommendedBibliographyTarget(
            noteID: UUID(),
            note: VaultQualifiedNoteID(
                vaultID: UUID(),
                relativePath: "Analyses/Source.md"
            ),
            fingerprint: DocumentFingerprint(content: "analysis"),
            title: "Source Analysis"
        )
    }
}
