import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Agent Change store", .serialized)
struct AgentChangeStoreTests {
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
        #expect(try await store.beforeDataForUndo(
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
            root = repositoryRoot
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
