import Foundation
import ScholiumContracts
import Testing

@Suite("Agent Discussion reply contracts")
struct ResearchAgentDiscussionContractsTests {
    @Test("Reply requests and receipts round-trip with strict fields")
    func roundTrip() throws {
        let run = try #require(
            ResearchRunLocator(rawValue: "discussionreplycontract1")
        )
        let statementID = UUID(uuidString: "00000000-0000-4000-8000-000000000901")!
        let request = try ResearchAgentDiscussionReplyRequest(
            statementID: statementID,
            attribution: "External Agent",
            text: "The second premise needs a narrower reconstruction."
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["schema_version"] as? Int
            == ResearchAgentDiscussionReplyRequest.currentSchemaVersion)
        #expect(object["statement_id"] as? String == statementID.uuidString)

        let decoded = try JSONDecoder().decode(
            ResearchAgentDiscussionReplyRequest.self,
            from: data
        )
        #expect(decoded == request)

        var unknown = object
        unknown["unexpected"] = true
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(
                ResearchAgentDiscussionReplyRequest.self,
                from: JSONSerialization.data(withJSONObject: unknown)
            )
        }

        let receipt = try ResearchAgentDiscussionReplyReceipt(
            run: run,
            discussionID: UUID(uuidString: "00000000-0000-4000-8000-000000000904")!,
            statementID: statementID,
            state: .alreadyRecorded,
            message: "The Agent Discussion reply was already recorded."
        )
        let receiptData = try encoder.encode(receipt)
        let decodedReceipt = try JSONDecoder().decode(
            ResearchAgentDiscussionReplyReceipt.self,
            from: receiptData
        )
        #expect(decodedReceipt == receipt)
    }

    @Test("Reply request validation rejects unsupported schema and unsafe text")
    func validation() throws {
        #expect(throws: (any Error).self) {
            _ = try ResearchAgentDiscussionReplyRequest(
                statementID: UUID(),
                attribution: "Agent",
                text: "/Users/researcher/private.pdf"
            )
        }

        let request = try ResearchAgentDiscussionReplyRequest(
            statementID: UUID(),
            attribution: "Agent",
            text: "A bounded reply."
        )
        let encoder = JSONEncoder()
        var object = try #require(
            JSONSerialization.jsonObject(
                with: encoder.encode(request)
            ) as? [String: Any]
        )
        object["schema_version"] = ResearchAgentDiscussionReplyRequest
            .currentSchemaVersion - 1
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(
                ResearchAgentDiscussionReplyRequest.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
    }
}
