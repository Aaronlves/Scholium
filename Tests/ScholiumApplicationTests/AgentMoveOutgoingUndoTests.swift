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

    @Test(
        "Undo refuses a redirected unchanged link, including a move with no source rewrites",
        arguments: [false, true])
    func undoRejectsRedirectedUnchangedLink(withRewrites: Bool) async throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/AgentMoveUnchangedLink-\(UUID().uuidString)")
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
        let neighborURL = topics.appendingPathComponent("Old/StableTarget.md")
        let stableTargetURL = topics.appendingPathComponent("New/StableTarget.md")
        let incomingURL = analyses.appendingPathComponent("Reference.md")
        let source =
            "\u{FEFF}# Source\r\n" + (withRewrites ? "[[LocalTarget]]\r\n" : "")
            + "[[StableTarget]]\r\n[[MissingTarget]]\r\n"
        let originalBytes = Data(source.utf8)
        let stableTargetBytes = Data("# Stable target\n".utf8)
        let incomingBytes = Data("# Reference\n[[Old/Source|source]]\n".utf8)
        try originalBytes.write(to: sourceURL)
        try stableTargetBytes.write(to: stableTargetURL)
        if withRewrites {
            try Data("# Original local target\n".utf8).write(to: topics.appendingPathComponent("Old/LocalTarget.md"))
            try Data("# Same-name neighbor\n".utf8).write(to: topics.appendingPathComponent("New/LocalTarget.md"))
            try incomingBytes.write(to: incomingURL)
        }
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: support, workspaceRegistryStorageURL: root.appendingPathComponent("Registry"))))
        do {
            let handle = try await runtime.configureTriptych(
                paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                portableContainerURL: root, triptychName: "Unchanged Link Undo Fixture")
            let initial = try await handle.refresh()
            let note = try #require(initial.vaults.flatMap(\.documents).first { $0.id.relativePath == "Old/Source.md" })
            let noteID = try #require(note.stableIdentity.resolvedID)
            let agent = handle.agentCollaboration
            let plan = try await agent.previewMoveNote(
                noteID: noteID, expectedFingerprint: note.fingerprint, to: "New/Source.md")
            #expect(plan.blockers.isEmpty)
            #expect(plan.effects.first { $0.noteID == noteID }?.rewrittenOccurrences == (withRewrites ? 1 : 0))
            #expect(plan.effects.count == (withRewrites ? 2 : 1))
            let moved = try await agent.moveNote(
                noteID: noteID, expectedFingerprint: note.fingerprint, to: "New/Source.md",
                expectedPlanFingerprint: plan.planFingerprint)
            let movedBytes = try Data(contentsOf: movedURL)
            let movedIncomingBytes = withRewrites ? try Data(contentsOf: incomingURL) : nil
            let neighborBytes = Data("# Newly created original-folder neighbor\n".utf8)
            try neighborBytes.write(to: neighborURL)
            _ = try await handle.refresh()

            let review = try await agent.agentChangeReview(id: moved.change.id)
            #expect(review.endingRevisionState == .current)
            #expect(!review.isDirectUndoAvailable)
            let unavailableReason = try #require(review.undoUnavailableReason)
            #expect(unavailableReason.contains("resolve differently") || unavailableReason.contains("link scope changed"))
            do {
                _ = try await agent.previewUndoAgentChange(
                    id: moved.change.id, expectedAfterFingerprint: moved.commit.committedRevision)
                Issue.record("Undo preview admitted an unchanged link whose restored resolution changed.")
            } catch AgentCollaborationError.invalidRequest(let reason) {
                #expect(reason == unavailableReason)
            }
            do {
                _ = try await agent.undoAgentChange(
                    id: moved.change.id, expectedAfterFingerprint: moved.commit.committedRevision)
                Issue.record("Undo silently redirected an unchanged original link.")
            } catch AgentCollaborationError.invalidRequest(let reason) {
                #expect(reason == unavailableReason)
            }
            #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
            #expect(try Data(contentsOf: movedURL) == movedBytes)
            #expect(try Data(contentsOf: neighborURL) == neighborBytes)
            #expect(try Data(contentsOf: stableTargetURL) == stableTargetBytes)
            if withRewrites { #expect(try Data(contentsOf: incomingURL) == movedIncomingBytes) }
            #expect(try await agent.agentChanges().first { $0.id == moved.change.id } == moved.change)
            #expect(try await handle.research.recoveryRecords().isEmpty)
            #expect(try await handle.refresh().document(id: moved.commit.destination)?.stableIdentity.resolvedID == noteID)

            // Once the conflicting neighbor is gone, the same receipt and
            // unchanged ending revision still authorize its exact inverse.
            try FileManager.default.removeItem(at: neighborURL)
            _ = try await handle.refresh()
            let available = try await agent.agentChangeReview(id: moved.change.id)
            #expect(available.isDirectUndoAvailable)
            #expect(available.undoUnavailableReason == nil)
            _ = try await agent.previewUndoAgentChange(
                id: moved.change.id, expectedAfterFingerprint: moved.commit.committedRevision)
            let undone = try await agent.undoAgentChange(
                id: moved.change.id, expectedAfterFingerprint: moved.commit.committedRevision)
            #expect(undone.restoredFingerprint == note.fingerprint)
            #expect(try Data(contentsOf: sourceURL) == originalBytes)
            #expect(!FileManager.default.fileExists(atPath: movedURL.path))
            if withRewrites { #expect(try Data(contentsOf: incomingURL) == incomingBytes) }
            #expect(try Data(contentsOf: stableTargetURL) == stableTargetBytes)
            #expect(try await agent.agentChanges().first { $0.id == moved.change.id }?.state == .undone)
            #expect(try await handle.refresh().document(id: note.id)?.stableIdentity.resolvedID == noteID)
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }
}
