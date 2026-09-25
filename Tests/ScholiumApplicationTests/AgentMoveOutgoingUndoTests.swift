import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Agent move outgoing-link recovery")
struct AgentMoveOutgoingUndoTests {
    @Test("Moving a source Note past a same-name target previews and restores exact links")
    func moveAndUndoPreserveOutgoingTarget() async throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/AgentMoveOutgoingUndo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let analyses = root.appendingPathComponent("Analyses")
        let topics = root.appendingPathComponent("Topics")
        let works = root.appendingPathComponent("Works")
        let support = root.appendingPathComponent("Application Support")
        for directory in [
            analyses, topics, works, support,
            topics.appendingPathComponent("Old"), topics.appendingPathComponent("New"),
        ] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let sourceURL = topics.appendingPathComponent("Old/Source.md")
        let movedURL = topics.appendingPathComponent("New/Source.md")
        let oldTargetURL = topics.appendingPathComponent("Old/LocalTarget.md")
        let newTargetURL = topics.appendingPathComponent("New/LocalTarget.md")
        let incomingURL = analyses.appendingPathComponent("Reference.md")
        let sourceBytes = Data("\u{FEFF}# Source\r\n[[LocalTarget]]{{Original relation.}}\r\n".utf8)
        let incomingBytes = Data("# Reference\n[[Old/Source|source]]\n".utf8)
        let oldTargetBytes = Data("# Original target\n".utf8)
        let newTargetBytes = Data("# Same-name neighbor\n".utf8)
        try sourceBytes.write(to: sourceURL)
        try incomingBytes.write(to: incomingURL)
        try oldTargetBytes.write(to: oldTargetURL)
        try newTargetBytes.write(to: newTargetURL)

        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: support,
                    workspaceRegistryStorageURL: root.appendingPathComponent("Registry")
                )))
        let handle = try await runtime.configureTriptych(
            paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
            portableContainerURL: root, triptychName: "Agent Move Undo Fixture"
        )
        defer { Task { await runtime.shutdown() } }
        let original = try await handle.refresh()
        let source = try #require(
            original.vaults.flatMap(\.documents).first {
                $0.id.relativePath == "Old/Source.md"
            })
        let incoming = try #require(
            original.vaults.flatMap(\.documents).first {
                $0.id.relativePath == "Reference.md"
            })
        let sourceID = try #require(source.stableIdentity.resolvedID)
        let incomingID = try #require(incoming.stableIdentity.resolvedID)
        let agent = handle.agentCollaboration

        let preview = try await agent.previewMoveNote(
            noteID: sourceID, expectedFingerprint: source.fingerprint, to: "New/Source.md"
        )
        #expect(preview.blockers.isEmpty)
        #expect(preview.effects.contains { $0.noteID == sourceID && $0.rewrittenOccurrences == 1 })
        #expect(preview.effects.contains { $0.noteID == incomingID && $0.rewrittenOccurrences == 1 })
        let moveComparison = try await agent.previewMoveMutation(
            noteID: sourceID, expectedFingerprint: source.fingerprint,
            to: "New/Source.md", expectedPlanFingerprint: preview.planFingerprint
        )
        #expect(moveComparison.movePreview?.effects.count == 2)

        let moved = try await agent.moveNote(
            noteID: sourceID, expectedFingerprint: source.fingerprint,
            to: "New/Source.md", expectedPlanFingerprint: preview.planFingerprint
        )
        #expect(moved.change.state == .confirmed)
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(try Data(contentsOf: movedURL) == Data("\u{FEFF}# Source\r\n[[Old/LocalTarget]]{{Original relation.}}\r\n".utf8))
        #expect(try Data(contentsOf: incomingURL) == Data("# Reference\n[[New/Source|source]]\n".utf8))
        #expect(try Data(contentsOf: oldTargetURL) == oldTargetBytes)
        #expect(try Data(contentsOf: newTargetURL) == newTargetBytes)

        let undoPreview = try await agent.previewUndoAgentChange(
            id: moved.change.id, expectedAfterFingerprint: try #require(moved.change.afterFingerprint)
        )
        #expect(undoPreview.movePreview?.effects.count == 2)
        #expect(undoPreview.movePreview?.destination.relativePath == "Old/Source.md")
        let undone = try await agent.undoAgentChange(
            id: moved.change.id, expectedAfterFingerprint: try #require(moved.change.afterFingerprint)
        )
        #expect(undone.restoredFingerprint == source.fingerprint)
        #expect(try Data(contentsOf: sourceURL) == sourceBytes)
        #expect(try Data(contentsOf: incomingURL) == incomingBytes)
        #expect(try Data(contentsOf: oldTargetURL) == oldTargetBytes)
        #expect(try Data(contentsOf: newTargetURL) == newTargetBytes)
        #expect(!FileManager.default.fileExists(atPath: movedURL.path))
        let restored = try await handle.refresh()
        #expect(restored.document(id: source.id)?.stableIdentity.resolvedID == sourceID)
        #expect(restored.document(id: incoming.id)?.stableIdentity.resolvedID == incomingID)
        #expect(try await agent.agentChanges().first?.state == .undone)
        await runtime.shutdown()
    }
}
