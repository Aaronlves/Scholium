import Foundation
import ScholiumContracts
import Testing

@Suite("Recommended Bibliography boundary contracts")
struct RecommendedBibliographyContractsTests {
    @Test("Goals are canonical and an empty goal set remains neutral")
    func canonicalGoals() throws {
        let request = RecommendedBibliographyRequest(
            scope: scope(),
            goals: [.classicWorks, .objections, .classicWorks, .backgroundReading],
            purpose: "  map the objection literature  "
        )
        #expect(request.goals == [.backgroundReading, .objections, .classicWorks])
        #expect(request.purpose == "map the objection literature")
        try request.validate()

        let neutral = RecommendedBibliographyRequest(scope: scope(), purpose: "  ")
        #expect(neutral.goals.isEmpty)
        #expect(neutral.purpose == nil)
    }

    @Test("Zero recommendations is a valid completion")
    func zeroRecommendations() throws {
        let submission = RecommendedBibliographyCompletionSubmission(
            requestID: UUID(),
            confirmationToken: UUID(),
            sourceRevisions: scope().sourceRevisions,
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
                sourceRevisions: scope().sourceRevisions,
                sourceScope: " ",
                candidates: []
            ).validate()
        }
    }

    @Test("Incomplete candidate identity arrays fail closed")
    func incompleteIdentityFailsClosed() {
        let data = Data(#"{"rawCitation":"A. Author, A Work, 2020","authors":["A. Author"],"year":2020}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BibliographyCandidateIdentity.self, from: data)
        }
    }

    @Test("Method snapshots require embedded resource sources")
    func methodSnapshotRequiresRenderedResources() throws {
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
        let incomplete = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                RecommendedBibliographyMethodSnapshot.self,
                from: incomplete
            )
        }
    }

    @Test("Retired Analysis-target fields fail closed")
    func retiredTargetFieldsFailClosed() throws {
        let request = RecommendedBibliographyRequest(scope: scope())
        var requestObject = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request))
                as? [String: Any]
        )
        requestObject["target"] = ["legacy": true]
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                RecommendedBibliographyRequest.self,
                from: JSONSerialization.data(withJSONObject: requestObject)
            )
        }

        let completion = RecommendedBibliographyCompletionSubmission(
            requestID: UUID(),
            confirmationToken: UUID(),
            sourceRevisions: scope().sourceRevisions,
            sourceScope: "Selected Notes",
            candidates: []
        )
        var completionObject = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(completion))
                as? [String: Any]
        )
        completionObject["targetFingerprint"] = [
            "sha256": String(repeating: "0", count: 64),
            "byteCount": 0,
        ]
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                RecommendedBibliographyCompletionSubmission.self,
                from: JSONSerialization.data(withJSONObject: completionObject)
            )
        }
    }

    private func scope() -> RecommendedBibliographyScope {
        RecommendedBibliographyScope(
            triptychID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            selectedNotes: [RecommendedBibliographySourceNote(
            noteID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            note: VaultQualifiedNoteID(
                vaultID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
                relativePath: "Analyses/Source.md"
            ),
            role: .sourceCorpus,
            fingerprint: DocumentFingerprint(content: "analysis"),
            title: "Source Analysis"
        )])
    }
}
