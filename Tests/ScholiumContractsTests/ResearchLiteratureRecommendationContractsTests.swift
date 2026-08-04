import Foundation
import ScholiumContracts
import Testing

@Suite("Research literature recommendation contracts")
struct ResearchLiteratureRecommendationContractsTests {
    @Test("Agent submissions contain scholarly content but no Application state")
    func submissionIsStrictAndBounded() throws {
        let submission = try ResearchLiteratureRecommendationSubmission(
            rawCitation: "A. Author, A Relevant Work (2020)",
            title: "A Relevant Work",
            authors: ["A. Author"],
            year: 2020,
            doi: "10.1000/relevant",
            zoteroItemKey: "abcd1234",
            sourceLocators: ["p. 42"],
            reason: "The analyzed source discusses this work as its strongest rival.",
            uncertainty: "The edition was not independently checked."
        )
        #expect(submission.zoteroItemKey == "ABCD1234")
        let data = try recommendationJSONEncoder().encode(submission)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(Set(object.keys) == [
            "rawCitation", "title", "authors", "year", "doi",
            "zoteroItemKey", "sourceLocators", "reason", "uncertainty",
        ])
        for forbidden in ["id", "status", "handled", "match", "score", "category"] {
            #expect(object[forbidden] == nil)
        }

        var unknown = object
        unknown["handled"] = true
        #expect(throws: ResearchLiteratureRecommendationError.self) {
            _ = try recommendationJSONDecoder().decode(
                ResearchLiteratureRecommendationSubmission.self,
                from: JSONSerialization.data(withJSONObject: unknown)
            )
        }
        #expect(throws: ResearchLiteratureRecommendationError.self) {
            _ = try ResearchLiteratureRecommendationSubmission(
                rawCitation: "Citation",
                reason: String(repeating: "x", count: 64 * 1_024 + 1)
            )
        }
        #expect(throws: ResearchLiteratureRecommendationError.self) {
            _ = try ResearchLiteratureRecommendationSubmission(
                rawCitation: "Citation",
                reason: "Unsafe\u{0000}reason"
            )
        }
        #expect(throws: ResearchLiteratureRecommendationError.self) {
            _ = try ResearchLiteratureRecommendationSubmission(
                rawCitation: "Citation",
                sourceLocators: ["/Users/researcher/private/Source.pdf"],
                reason: "Follow the cited passage."
            )
        }
        #expect(throws: ResearchLiteratureRecommendationError.self) {
            _ = try ResearchLiteratureRecommendationSubmission(
                rawCitation: "Citation",
                reason: "Transient locator: file:///Users/researcher/Source.pdf"
            )
        }
        let embeddedPathJSON = """
        {
          "rawCitation": "Citation",
          "sourceLocators": ["prefix=/Users/researcher/private/./Source.pdf"],
          "reason": "Follow the cited passage."
        }
        """
        #expect(throws: ResearchLiteratureRecommendationError.self) {
            _ = try recommendationJSONDecoder().decode(
                ResearchLiteratureRecommendationSubmission.self,
                from: Data(embeddedPathJSON.utf8)
            )
        }
        for unsafeLocator in [
            "prefix=%2FUsers%2Fresearcher%2FSource.pdf",
            "prefix=%25252FUsers%25252Fresearcher%25252FSource.pdf",
            "prefix=／Users／researcher／Source.pdf",
            "prefix=C:\\Users\\researcher\\Source.pdf",
            "prefix=\\\\server\\share\\Source.pdf",
            "opaque-/Users/researcher/./Source.pdf",
            "nothttp:/Users/researcher/./Source.pdf",
        ] {
            #expect(throws: ResearchLiteratureRecommendationError.self) {
                _ = try ResearchLiteratureRecommendationSubmission(
                    rawCitation: "Citation",
                    sourceLocators: [unsafeLocator],
                    reason: "Follow the cited passage."
                )
            }
        }
        #expect(try ResearchLiteratureRecommendationSubmission(
            rawCitation: "Citation",
            doi: "https://doi.org/10.1000/relevant",
            reason: "Compare https://example.org/research/path with the cited work."
        ).doi == "https://doi.org/10.1000/relevant")
    }

    @Test("Application identity and researcher disposition are deterministic and strict")
    func identityAndDisposition() throws {
        let runID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        #expect(
            ResearchLiteratureRecommendation.stableID(runID: runID, ordinal: 0)
                == ResearchLiteratureRecommendation.stableID(
                    runID: runID,
                    ordinal: 0
                )
        )
        #expect(
            ResearchLiteratureRecommendation.stableID(runID: runID, ordinal: 0)
                != ResearchLiteratureRecommendation.stableID(
                    runID: runID,
                    ordinal: 1
                )
        )

        let disposition = try PortableResearchRecommendationDisposition(
            status: .unprocessed,
            updatedAt: Date(timeIntervalSince1970: 100),
            researcherNote: "  Follow up with the author.  "
        )
        #expect(disposition.researcherNote == "Follow up with the author.")
        let cleared = try PortableResearchRecommendationDisposition(
            status: .handled,
            updatedAt: Date(timeIntervalSince1970: 200),
            researcherNote: "   "
        )
        #expect(cleared.researcherNote == nil)
        #expect(throws: ResearchLiteratureRecommendationError.self) {
            _ = try PortableResearchRecommendationDisposition(
                status: .handled,
                updatedAt: Date(timeIntervalSince1970: 200),
                researcherNote: "private=/Users/researcher/Notes.txt"
            )
        }
        #expect(throws: ResearchLiteratureRecommendationError.self) {
            _ = try PortableResearchRecommendationDisposition(
                status: .handled,
                updatedAt: Date(timeIntervalSince1970: 200),
                researcherNote: "unsafe\u{0000}note"
            )
        }

        var object = try #require(
            JSONSerialization.jsonObject(
                with: recommendationJSONEncoder().encode(disposition)
            ) as? [String: Any]
        )
        object["accepted"] = true
        #expect(throws: ResearchLiteratureRecommendationError.self) {
            _ = try recommendationJSONDecoder().decode(
                PortableResearchRecommendationDisposition.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
    }

    @Test("Completion JSON distinguishes an omitted array from an explicit empty array")
    func completionArrayPresenceIsExplicit() throws {
        let omitted = ResearchActionCompletionSubmission(
            runID: UUID(),
            confirmationToken: UUID(),
            finalMaterialFingerprints: [:],
            actuallyUsedMaterialNoteIDs: [],
            summary: "Completed",
            didModifyTarget: false,
            fidelityOutcomes: [],
            literatureRecommendations: nil,
            childRunIDs: [],
            submittedAt: Date(timeIntervalSince1970: 100)
        )
        let explicit = ResearchActionCompletionSubmission(
            runID: omitted.runID,
            confirmationToken: omitted.confirmationToken,
            finalMaterialFingerprints: [:],
            actuallyUsedMaterialNoteIDs: [],
            summary: "Completed",
            didModifyTarget: false,
            fidelityOutcomes: [],
            literatureRecommendations: [],
            childRunIDs: [],
            submittedAt: omitted.submittedAt
        )
        let omittedObject = try #require(
            JSONSerialization.jsonObject(
                with: recommendationJSONEncoder().encode(omitted)
            ) as? [String: Any]
        )
        let explicitObject = try #require(
            JSONSerialization.jsonObject(
                with: recommendationJSONEncoder().encode(explicit)
            ) as? [String: Any]
        )
        #expect(omittedObject["literatureRecommendations"] == nil)
        #expect((explicitObject["literatureRecommendations"] as? [Any])?.isEmpty == true)

        var nullObject = explicitObject
        nullObject["literatureRecommendations"] = NSNull()
        #expect(throws: (any Error).self) {
            _ = try recommendationJSONDecoder().decode(
                ResearchActionCompletionSubmission.self,
                from: JSONSerialization.data(withJSONObject: nullObject)
            )
        }
    }
}

private func recommendationJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}

private func recommendationJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}
