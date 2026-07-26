import Foundation
import ScholiumContracts
import Testing

@Suite("Agent Note Change contracts")
struct AgentNoteChangeContractsTests {
    @Test("Canonical requests round-trip with a deterministic payload digest")
    func requestRoundTripAndDigest() throws {
        let first = try note(index: 1)
        let second = try note(index: 2)
        let request = try makeRequest(targets: [second, first])
        let reordered = try makeRequest(
            requestID: request.id,
            targets: [first, second]
        )

        #expect(request == reordered)
        #expect(try request.payloadDigest() == reordered.payloadDigest())
        let data = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(
            AgentNoteChangeRequest.self,
            from: data
        ) == request)
    }

    @Test("The request digest distinguishes changed intent under one ID")
    func changedIntentChangesDigest() throws {
        let id = UUID()
        let first = try makeRequest(requestID: id, reason: "Revise this note.")
        let changed = try makeRequest(
            requestID: id,
            reason: "Revise this note and replace its argument."
        )
        #expect(first.id == changed.id)
        #expect(try first.payloadDigest() != changed.payloadDigest())
    }

    @Test("Requests reject duplicated operations, mixed roles, and empty reasons")
    func requestValidation() throws {
        #expect(throws: AgentNoteChangeContractError.self) {
            _ = try makeRequest(
                operations: [.modifyMarkdown, .modifyMarkdown]
            )
        }
        #expect(throws: AgentNoteChangeContractError.self) {
            _ = try makeRequest(
                targets: [try note(index: 1), try note(index: 2, role: .topic)]
            )
        }
        #expect(throws: AgentNoteChangeContractError.self) {
            _ = try makeRequest(reason: "  \n")
        }
    }

    @Test("Decisions bind one digest and only an allowed subset carries Notes")
    func decisionValidation() throws {
        let request = try makeRequest(targets: [try note(index: 1), try note(index: 2)])
        let receivedAt = Date(timeIntervalSince1970: 1_000)
        let pending = try AgentNoteChangeRequestRecord(
            request: request,
            receivedAt: receivedAt,
            validFor: 60
        )
        #expect(pending.decision.state == .pending)
        #expect(pending.decision.decidedAt == nil)

        let allowed = try pending.resolving(
            state: .allowedSubset,
            allowedNoteIDs: [request.targets[0].noteID],
            at: receivedAt.addingTimeInterval(1)
        )
        #expect(allowed.decision.state == .allowedSubset)
        #expect(allowed.decision.allowedNoteIDs == [request.targets[0].noteID])
        #expect(throws: AgentNoteChangeContractError.self) {
            _ = try pending.resolving(
                state: .continueWithoutChanges,
                allowedNoteIDs: [request.targets[0].noteID],
                at: receivedAt.addingTimeInterval(1)
            )
        }
    }

    @Test("Expired state is terminal and unknown fields or versions fail closed")
    func expirationAndStrictDecoding() throws {
        let request = try makeRequest()
        let receivedAt = Date(timeIntervalSince1970: 2_000)
        let record = try AgentNoteChangeRequestRecord(
            request: request,
            receivedAt: receivedAt,
            validFor: 1
        )
        let expired = try record.expiringIfNeeded(
            at: receivedAt.addingTimeInterval(2)
        )
        #expect(expired.decision.state == .expired)

        var object = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(request)
            ) as? [String: Any]
        )
        object["schema_version"] = 99
        #expect(throws: AgentNoteChangeContractError.self) {
            _ = try JSONDecoder().decode(
                AgentNoteChangeRequest.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
        object["schema_version"] = 1
        object["unexpected"] = true
        #expect(throws: AgentNoteChangeContractError.self) {
            _ = try JSONDecoder().decode(
                AgentNoteChangeRequest.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
        object.removeValue(forKey: "unexpected")
        var parent = try #require(object["parent_action"] as? [String: Any])
        var definition = try #require(parent["definition"] as? [String: Any])
        definition["unexpected"] = true
        parent["definition"] = definition
        object["parent_action"] = parent
        #expect(throws: AgentNoteChangeContractError.self) {
            _ = try JSONDecoder().decode(
                AgentNoteChangeRequest.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        var targetObject = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(request)
            ) as? [String: Any]
        )
        var targets = try #require(targetObject["targets"] as? [[String: Any]])
        targets[0]["title"] = "Agent-supplied display title"
        targetObject["targets"] = targets
        #expect(throws: AgentNoteChangeContractError.self) {
            _ = try JSONDecoder().decode(
                AgentNoteChangeRequest.self,
                from: JSONSerialization.data(withJSONObject: targetObject)
            )
        }
    }

    @Test("Persisted decisions reject impossible receive and expiry timelines")
    func persistedDecisionTimelineValidation() throws {
        let request = try makeRequest()
        let receivedAt = Date(timeIntervalSinceReferenceDate: 4_000)
        let pending = try AgentNoteChangeRequestRecord(
            request: request,
            receivedAt: receivedAt,
            validFor: 60
        )
        let allowed = try pending.resolving(
            state: .allowedSubset,
            allowedNoteIDs: [request.targets[0].noteID],
            at: receivedAt.addingTimeInterval(1)
        )
        let expired = try pending.expiringIfNeeded(
            at: receivedAt.addingTimeInterval(61)
        )

        for (record, impossibleDate) in [
            (allowed, receivedAt.addingTimeInterval(-1)),
            (allowed, pending.expiresAt),
            (expired, pending.expiresAt.addingTimeInterval(-1)),
        ] {
            var object = try #require(
                JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(record)
                ) as? [String: Any]
            )
            var decision = try #require(object["decision"] as? [String: Any])
            decision["decided_at"] = impossibleDate.timeIntervalSinceReferenceDate
            object["decision"] = decision
            #expect(throws: AgentNoteChangeContractError.self) {
                _ = try JSONDecoder().decode(
                    AgentNoteChangeRequestRecord.self,
                    from: JSONSerialization.data(withJSONObject: object)
                )
            }
        }
    }

    private func makeRequest(
        requestID: UUID = UUID(),
        targets: [AgentNoteChangeTarget]? = nil,
        operations: [ResearchActionCandidateWriteOperation] = [.modifyMarkdown],
        reason: String = "Develop the alternative argument in these Notes."
    ) throws -> AgentNoteChangeRequest {
        let revision = try actionRevision()
        return try AgentNoteChangeRequest(
            requestID: requestID,
            triptychID: UUID(uuidString: "00000000-0000-4000-8000-000000000010")!,
            parentRunID: UUID(uuidString: "00000000-0000-4000-8000-000000000020")!,
            parentAction: revision,
            requestedAction: revision,
            targets: targets ?? [try note(index: 1)],
            operations: operations,
            agentReason: reason
        )
    }

    private func actionRevision() throws -> AgentNoteChangeActionRevision {
        try AgentNoteChangeActionRevision(
            definition: .write,
            packageID: "scholium-working-write",
            skillRevision: DocumentFingerprint(content: "skill"),
            profileOrigin: .applicationDefault,
            profileRevision: DocumentFingerprint(content: "profile"),
            profileDocumentRevision: nil
        )
    }

    private func note(
        index: Int,
        role: ResearchActionTargetRole = .work
    ) throws -> AgentNoteChangeTarget {
        let noteID = UUID(
            uuidString: String(format: "00000000-0000-4000-8000-%012d", index)
        )!
        return try AgentNoteChangeTarget(
            noteID: noteID,
            note: VaultQualifiedNoteID(
                vaultID: UUID(uuidString: "00000000-0000-4000-8000-000000000030")!,
                relativePath: "Alternative \(index).md"
            ),
            role: role,
            expectedFingerprint: DocumentFingerprint(content: "note-\(index)")
        )
    }
}
