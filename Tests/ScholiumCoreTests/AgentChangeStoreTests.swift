import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Agent Change store", .serialized)
struct AgentChangeStoreTests {

    @Test("Move evidence requires complete readback, survives reopening and rejects unknown nested authority")
    func moveEvidenceLifecycle() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }
        let store = try AgentChangeStore(applicationSupportURL: fixture.root, triptychID: fixture.triptychID)
        let primaryID = UUID()
        let linkedID = UUID()
        let vault = UUID()
        let linkedVault = UUID()
        let source = Data("\u{feff}Exact unchanged primary\r\n".utf8)
        let before = Data("---\nsummary: 'keep'\n---\n[[Old|label]]{{Authored comment.}}\n".utf8)
        let after = Data("---\nsummary: 'keep'\n---\n[[New|label]]{{Authored comment.}}\n".utf8)
        let primary = AgentNoteMoveEffect(
            noteID: primaryID, role: .sourceCorpus,
            source: .init(vaultID: vault, relativePath: "Old.md"), destination: .init(vaultID: vault, relativePath: "New.md"),
            beforeFingerprint: .init(data: source), afterFingerprint: .init(data: source), rewrittenOccurrences: 0)
        let linked = AgentNoteMoveEffect(
            noteID: linkedID, role: .topicKnowledge,
            source: .init(vaultID: linkedVault, relativePath: "Link.md"), destination: .init(vaultID: linkedVault, relativePath: "Link.md"),
            beforeFingerprint: .init(data: before), afterFingerprint: .init(data: after), rewrittenOccurrences: 1)
        let move = AgentMoveEvidence(primary: primary, linkedSources: [.init(effect: linked, beforeData: before, afterData: after)])
        // A second affected file cannot occupy the move's final path, even in a self-consistent payload.
        let collision = AgentNoteMoveEffect(
            noteID: linkedID, role: .sourceCorpus,
            source: primary.destination, destination: primary.destination,
            beforeFingerprint: .init(data: before), afterFingerprint: .init(data: after), rewrittenOccurrences: 1)
        await #expect(throws: AgentChangeError.self) {
            try await store.prepare(
                operation: .move, noteID: primaryID, role: .sourceCorpus,
                originalRelativePath: "Old.md", finalRelativePath: "New.md", beforeData: source, afterData: source,
                move: .init(primary: primary, linkedSources: [.init(effect: collision, beforeData: before, afterData: after)]))
        }
        let prepared = try await store.prepare(
            operation: .move, noteID: primaryID, role: .sourceCorpus,
            originalRelativePath: "Old.md", finalRelativePath: "New.md", beforeData: source, afterData: source, move: move)
        await #expect(throws: AgentChangeError.self) { try await store.confirm(id: prepared.id, observedAfterFingerprint: primary.afterFingerprint) }
        _ = try await store.confirm(
            id: prepared.id, observedAfterFingerprint: primary.afterFingerprint,
            observedMoveFingerprints: [primaryID: primary.afterFingerprint, linkedID: linked.afterFingerprint])
        let reopened = try AgentChangeStore(applicationSupportURL: fixture.root, triptychID: fixture.triptychID)
        let evidence = try await reopened.evidence(id: prepared.id)
        #expect(evidence.move == move && evidence.beforeData == source && evidence.afterData == source)
        #expect(evidence.change.moveEffects?.count == 2 && evidence.change.isDirectUndoEligible)
        await #expect(throws: AgentChangeError.self) { try await reopened.markUndone(id: prepared.id, restoredFingerprint: primary.beforeFingerprint) }
        _ = try await reopened.markUndone(
            id: prepared.id, restoredFingerprint: primary.beforeFingerprint,
            restoredMoveFingerprints: [primaryID: primary.beforeFingerprint, linkedID: linked.beforeFingerprint])
        #expect(try await reopened.change(id: prepared.id).state == .undone)
        let file = fixture.root.appendingPathComponent(
            "Triptychs/\(fixture.triptychID.uuidString)/agent-changes-v1/\(prepared.id.uuidString.lowercased()).json")
        var payload = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var moveObject = try #require(payload["move"] as? [String: Any])
        var primaryObject = try #require(moveObject["primary"] as? [String: Any])
        primaryObject["future_authority"] = true
        moveObject["primary"] = primaryObject
        payload["move"] = moveObject
        let unsupported = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try unsupported.write(to: file)
        await #expect(throws: AgentChangeError.self) { try await reopened.evidence(id: prepared.id) }
        #expect(try Data(contentsOf: file) == unsupported)
    }

    @Test("Exact evidence survives confirmation, restart, and direct Undo state")
    func exactEvidenceLifecycle() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }
        let store = try AgentChangeStore(
            applicationSupportURL: fixture.root,
            triptychID: fixture.triptychID
        )
        let before = Data(
            [0xEF, 0xBB, 0xBF] + Array("---\r\nsummary: null\r\n---\r\nBefore\r\n".utf8)
        )
        let after = Data(
            [0xEF, 0xBB, 0xBF] + Array("---\r\nsummary: null\r\n---\r\nAfter\r\n".utf8)
        )
        let id = UUID()
        let noteID = UUID()
        let prepared = try await store.prepare(
            id: id,
            operation: .update,
            noteID: noteID,
            role: .topicKnowledge,
            originalRelativePath: "Nested/Exact.md",
            finalRelativePath: "Nested/Exact.md",
            beforeData: before,
            afterData: after
        )
        #expect(prepared.state == .prepared)
        #expect(prepared.beforeFingerprint == DocumentFingerprint(data: before))
        #expect(prepared.afterFingerprint == DocumentFingerprint(data: after))

        let confirmed = try await store.confirm(
            id: id,
            observedAfterFingerprint: DocumentFingerprint(data: after)
        )
        #expect(confirmed.state == .confirmed)
        let evidence = try await store.evidence(id: id)
        #expect(evidence.change.id == id)
        #expect(evidence.change.noteID == noteID)
        #expect(evidence.beforeData == before)
        #expect(evidence.afterData == after)
        let comparison = try evidence.exactUpdateComparison()
        #expect(comparison.startingRevision == DocumentFingerprint(data: before))
        #expect(comparison.endingRevision == DocumentFingerprint(data: after))
        #expect(
            try await store.beforeDataForUndo(
                id: id,
                expectedAfterFingerprint: DocumentFingerprint(data: after)
            ) == before)

        let reopened = try AgentChangeStore(
            applicationSupportURL: fixture.root,
            triptychID: fixture.triptychID
        )
        #expect(try await reopened.change(id: id).state == .confirmed)
        let reopenedEvidence = try await reopened.evidence(id: id)
        #expect(reopenedEvidence.beforeData == before)
        #expect(reopenedEvidence.afterData == after)
        let reopenedComparison = try reopenedEvidence.exactUpdateComparison()
        #expect(reopenedComparison.startingRevision == DocumentFingerprint(data: before))
        #expect(reopenedComparison.endingRevision == DocumentFingerprint(data: after))
        let undone = try await reopened.markUndone(
            id: id,
            restoredFingerprint: DocumentFingerprint(data: before)
        )
        #expect(undone.state == .undone)
        #expect(try await reopened.change(id: id).state == .undone)
    }

    @Test("Unknown persisted fields fail closed without rewriting evidence")
    func unknownFieldsFailClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }
        let store = try AgentChangeStore(
            applicationSupportURL: fixture.root,
            triptychID: fixture.triptychID
        )
        let id = UUID()
        _ = try await store.prepare(
            id: id,
            operation: .create,
            noteID: UUID(),
            role: .draftProject,
            originalRelativePath: nil,
            finalRelativePath: "Draft.md",
            beforeData: nil,
            afterData: Data("Body".utf8)
        )
        let url = fixture.changeDirectory.appendingPathComponent(
            "\(id.uuidString.lowercased()).json"
        )
        let original = try Data(contentsOf: url)
        var object = try #require(
            JSONSerialization.jsonObject(with: original) as? [String: Any]
        )
        object["unsupported"] = true
        let damaged = try JSONSerialization.data(withJSONObject: object)
        try damaged.write(to: url, options: .atomic)

        do {
            _ = try await store.change(id: id)
            Issue.record("The store accepted an unsupported persisted field.")
        } catch let error as AgentChangeError {
            guard case .invalid = error else {
                Issue.record("Unexpected Agent Change error: \(error)")
                return
            }
        }
        #expect(try Data(contentsOf: url) == damaged)
    }

    private struct Fixture {
        let root: URL
        let triptychID = UUID()

        init() throws {
            let repositoryRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            root =
                repositoryRoot
                .appendingPathComponent(".build/core-unit-state", isDirectory: true)
                .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
        }

        var changeDirectory: URL {
            root.appendingPathComponent("Triptychs", isDirectory: true)
                .appendingPathComponent(triptychID.uuidString, isDirectory: true)
                .appendingPathComponent("agent-changes-v1", isDirectory: true)
        }

        func dispose() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
