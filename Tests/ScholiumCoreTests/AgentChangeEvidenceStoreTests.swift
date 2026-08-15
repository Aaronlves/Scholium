import Foundation
import ScholiumContracts
@testable import ScholiumCore
import Testing

@Suite("Agent change evidence")
struct AgentChangeEvidenceStoreTests {
    @Test("One Run-bound record preserves exact starting and ending bytes")
    func preservesExactRunBoundBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runID = UUID()
        let noteID = UUID()
        let starting = Data("\u{feff}---\r\ntitle: Exact\r\n---\r\nBefore.\r\n".utf8)
        let ending = Data("\u{feff}---\r\ntitle: Exact\r\n---\r\nAfter.\r\n".utf8)
        let startingRevision = DocumentFingerprint(data: starting)
        let endingRevision = DocumentFingerprint(data: ending)
        let store = try AgentChangeEvidenceStore(
            applicationSupportURL: fixture.support,
            triptychID: fixture.triptychID
        )

        let captured = try await store.captureStartingRevision(
            runID: runID,
            noteID: noteID,
            data: starting,
            expectedRevision: startingRevision
        )
        let replay = try await store.captureStartingRevision(
            id: captured.id,
            runID: runID,
            noteID: noteID,
            data: starting,
            expectedRevision: startingRevision
        )
        #expect(replay == captured)

        let completed = try await store.recordEndingRevision(
            id: captured.id,
            runID: runID,
            noteID: noteID,
            data: ending,
            expectedRevision: endingRevision
        )
        #expect(completed.endingRevision == endingRevision)
        #expect(try await store.startingData(
            id: captured.id,
            runID: runID,
            noteID: noteID,
            expectedRevision: startingRevision
        ) == starting)
        #expect(try await store.endingData(
            id: captured.id,
            runID: runID,
            noteID: noteID,
            expectedRevision: endingRevision
        ) == ending)

        let reopened = try AgentChangeEvidenceStore(
            applicationSupportURL: fixture.support,
            triptychID: fixture.triptychID
        )
        #expect(try await reopened.evidence(id: captured.id) == completed)
    }

    @Test("Evidence rejects another Run and supports privacy deletion by Note")
    func rejectsMismatchedBindingAndRemovesByNote() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try AgentChangeEvidenceStore(
            applicationSupportURL: fixture.support,
            triptychID: fixture.triptychID
        )
        let runID = UUID()
        let noteID = UUID()
        let data = Data("Exact source.\n".utf8)
        let revision = DocumentFingerprint(data: data)
        let evidence = try await store.captureStartingRevision(
            runID: runID,
            noteID: noteID,
            data: data,
            expectedRevision: revision
        )

        await #expect(throws: AgentChangeEvidenceError.self) {
            _ = try await store.startingData(
                id: evidence.id,
                runID: UUID(),
                noteID: noteID,
                expectedRevision: revision
            )
        }
        #expect(try await store.removeEvidence(noteID: noteID) == 1)
        await #expect(throws: AgentChangeEvidenceError.self) {
            _ = try await store.evidence(id: evidence.id)
        }
    }

    private struct Fixture {
        let root: URL
        let support: URL
        let triptychID = UUID()

        init() throws {
            root = URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            ).appendingPathComponent(
                ".build/agent-change-evidence-tests/\(UUID().uuidString)",
                isDirectory: true
            )
            support = root.appendingPathComponent("Support", isDirectory: true)
            try FileManager.default.createDirectory(
                at: support,
                withIntermediateDirectories: true
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
