import Foundation
import ScholiumContracts
import Testing

@Suite("Research Record contracts")
struct ResearchRecordContractsTests {
    @Test("Version-one JSON is strict, lowercase, and round-trippable")
    func strictRoundTrip() throws {
        let recordID = try #require(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
        let triptychID = try #require(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"))
        let stepID = try #require(UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc"))
        let noteID = try #require(UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd"))
        let submitter = try ResearchRecordSubmitter(displayName: "Codex")
        let reference = try ResearchRecordNoteReference(
            noteID: noteID,
            relation: .basis,
            revision: DocumentFingerprint(content: "source")
        )
        let step = try ResearchRecordStep(
            id: stepID,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
            submittedBy: submitter,
            bodyMarkdown: "The distinction now matters because the premise changed.",
            noteReferences: [reference]
        )
        let record = try ResearchRecord(
            id: recordID,
            triptychID: triptychID,
            question: "Can emotions ground reasons?",
            steps: [step]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        let source = try #require(String(data: data, encoding: .utf8))
        #expect(source.contains("\"record_id\":\"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa\""))
        #expect(source.contains("\"byte_count\""))
        #expect(source.contains("\"corrections\":[]"))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(ResearchRecord.self, from: data) == record)
    }

    @Test("Unknown fields and forward revision links fail closed")
    func strictValidation() throws {
        let submitter = try ResearchRecordSubmitter(displayName: "Agent")
        let firstID = UUID()
        let laterID = UUID()
        let invalidFirst = try ResearchRecordStep(
            id: firstID,
            submittedBy: submitter,
            bodyMarkdown: "This incorrectly revises a future step.",
            revisesStepIDs: [laterID]
        )
        let later = try ResearchRecordStep(
            id: laterID,
            submittedBy: submitter,
            bodyMarkdown: "The future step."
        )
        #expect(throws: ResearchRecordContractError.self) {
            try ResearchRecord(
                triptychID: UUID(),
                question: "A question?",
                steps: [invalidFirst, later]
            )
        }

        let valid = try ResearchRecord(
            triptychID: UUID(),
            question: "A question?",
            steps: [try ResearchRecordStep(
                submittedBy: submitter,
                bodyMarkdown: "A reasoned development."
            )]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(valid)) as? [String: Any]
        )
        object["legacy_result"] = "must not be accepted"
        let damaged = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(throws: ResearchRecordContractError.self) {
            try decoder.decode(ResearchRecord.self, from: damaged)
        }
    }

    @Test("Clerical correction preserves original and changes current projection")
    func correctionProjection() throws {
        let submitter = try ResearchRecordSubmitter(displayName: "Codex")
        let step = try ResearchRecordStep(
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
            submittedBy: submitter,
            bodyMarkdown: "The orignal judgment."
        )
        let record = try ResearchRecord(
            triptychID: UUID(),
            question: "What changed?",
            steps: [step]
        )
        let correction = try ResearchRecordCorrection(
            correctedAt: Date(timeIntervalSince1970: 1_700_000_100),
            submittedBy: submitter,
            bodyMarkdown: "The original judgment."
        )
        let corrected = try record.correcting(stepID: step.id, with: correction)

        #expect(corrected.steps[0].bodyMarkdown == "The orignal judgment.")
        #expect(corrected.steps[0].currentBodyMarkdown == "The original judgment.")
        #expect(corrected.lastSubstantiveAt == step.recordedAt)
    }
}
