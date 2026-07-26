import Foundation
import ScholiumContracts
import ScholiumCore
import Testing

@Suite("Agent Note Change request store")
struct AgentNoteChangeRequestStoreTests {
    @Test("Exact replay is idempotent and changed payload reuse fails closed")
    func replayAndPayloadMismatch() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let reopenedStore = try fixture.store()
        let request = try fixture.request()
        let now = Date(timeIntervalSince1970: 1_000.125)
        let first = try await store.submitValidated(
            request,
            isCurrent: true,
            receivedAt: now
        )
        let replay = try await reopenedStore.submitValidated(
            request,
            isCurrent: true,
            receivedAt: now.addingTimeInterval(5)
        )
        #expect(replay == first)

        let changed = try fixture.request(
            requestID: request.id,
            reason: "A different request under the same identifier."
        )
        await #expect(throws: AgentNoteChangeRequestStoreError.self) {
            _ = try await store.submitValidated(
                changed,
                isCurrent: true,
                receivedAt: now
            )
        }
    }

    @Test("One parent has at most one unresolved request")
    func oneUnresolvedRequestPerParent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let first = try fixture.request()
        _ = try await store.submitValidated(first, isCurrent: true)
        let second = try fixture.request(requestID: UUID())
        await #expect(throws: AgentNoteChangeRequestStoreError.self) {
            _ = try await store.submitValidated(second, isCurrent: true)
        }
    }

    @Test("Expiry closes the unresolved slot and a subset decision is idempotent")
    func expirationAndDecision() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let now = Date(timeIntervalSince1970: 2_000)
        let first = try fixture.request()
        _ = try await store.submitValidated(
            first,
            isCurrent: true,
            receivedAt: now,
            validFor: 1
        )
        let expired = try await store.record(
            id: first.id,
            now: now.addingTimeInterval(2)
        )
        #expect(expired.decision.state == .expired)

        let second = try fixture.request(requestID: UUID())
        let pending = try await store.submitValidated(
            second,
            isCurrent: true,
            receivedAt: now.addingTimeInterval(3)
        )
        let allowed = try await store.resolve(
            id: second.id,
            state: .allowedSubset,
            allowedNoteIDs: [second.targets[0].noteID],
            decidedAt: now.addingTimeInterval(4)
        )
        #expect(allowed.decision.state == .allowedSubset)
        #expect(try await store.resolve(
            id: second.id,
            state: .allowedSubset,
            allowedNoteIDs: [second.targets[0].noteID],
            decidedAt: now.addingTimeInterval(5)
        ) == allowed)
        #expect(pending.requestDigest == allowed.requestDigest)
    }

    @Test("A subsecond decision before expiry survives exact store round trip")
    func subsecondDecisionBeforeExpiry() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let reopenedStore = try fixture.store()
        let receivedAt = Date(timeIntervalSinceReferenceDate: 1_000.125)
        let request = try fixture.request()
        let pending = try await store.submitValidated(
            request,
            isCurrent: true,
            receivedAt: receivedAt,
            validFor: 1
        )
        let decidedAt = pending.expiresAt.addingTimeInterval(-0.001)
        let allowed = try await store.resolve(
            id: request.id,
            state: .allowedSubset,
            allowedNoteIDs: [request.targets[0].noteID],
            decidedAt: decidedAt
        )

        #expect(allowed.decision.decidedAt == decidedAt)
        #expect(try await reopenedStore.record(
            id: request.id,
            now: decidedAt
        ) == allowed)
    }

    @Test("Cross-Triptych and initially stale requests fail or terminate narrowly")
    func triptychAndStale() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let crossTriptych = try fixture.request(triptychID: UUID())
        await #expect(throws: AgentNoteChangeRequestStoreError.self) {
            _ = try await store.submitValidated(crossTriptych, isCurrent: true)
        }

        let stale = try fixture.request()
        let recorded = try await store.submitValidated(stale, isCurrent: false)
        #expect(recorded.decision.state == .stale)
        #expect(try await store.pending().isEmpty)
    }

    @Test("Permanent-deletion cleanup purges requested Notes and affected parents")
    func deletionCleanup() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.store()
        let parentRunID = UUID()
        let byParent = try fixture.request(parentRunID: parentRunID)
        _ = try await store.submitValidated(byParent, isCurrent: true)
        #expect(try await store.purgeRequests(
            containing: [],
            parentRunIDs: [parentRunID]
        ) == [byParent.id])
        await #expect(throws: AgentNoteChangeRequestStoreError.self) {
            _ = try await store.record(id: byParent.id)
        }

        let byTarget = try fixture.request(parentRunID: UUID())
        _ = try await store.submitValidated(byTarget, isCurrent: true)
        #expect(try await store.purgeRequests(
            containing: [byTarget.targets[0].noteID],
            parentRunIDs: []
        ) == [byTarget.id])
    }
}

private struct Fixture {
    let root: URL
    let triptychID = UUID()

    init() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        root = repositoryRoot
            .appendingPathComponent(".build/test-fixtures", isDirectory: true)
            .appendingPathComponent(
                "AgentNoteChangeStore-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    func store() throws -> AgentNoteChangeRequestStore {
        try AgentNoteChangeRequestStore(
            applicationSupportURL: root,
            triptychID: triptychID
        )
    }

    func request(
        requestID: UUID = UUID(),
        triptychID requestedTriptychID: UUID? = nil,
        parentRunID: UUID = UUID(
            uuidString: "00000000-0000-4000-8000-000000000040"
        )!,
        reason: String = "Change this additional Work."
    ) throws -> AgentNoteChangeRequest {
        let revision = try AgentNoteChangeActionRevision(
            definition: .write,
            packageID: "scholium-working-write",
            skillRevision: DocumentFingerprint(content: "skill"),
            profileOrigin: .applicationDefault,
            profileRevision: DocumentFingerprint(content: "profile"),
            profileDocumentRevision: nil
        )
        return try AgentNoteChangeRequest(
            requestID: requestID,
            triptychID: requestedTriptychID ?? triptychID,
            parentRunID: parentRunID,
            parentAction: revision,
            requestedAction: revision,
            targets: [try AgentNoteChangeTarget(
                noteID: UUID(uuidString: "00000000-0000-4000-8000-000000000050")!,
                note: VaultQualifiedNoteID(
                    vaultID: UUID(uuidString: "00000000-0000-4000-8000-000000000060")!,
                    relativePath: "Additional Work.md"
                ),
                role: .work,
                expectedFingerprint: DocumentFingerprint(content: "work")
            )],
            operations: [.modifyMarkdown],
            agentReason: reason
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
