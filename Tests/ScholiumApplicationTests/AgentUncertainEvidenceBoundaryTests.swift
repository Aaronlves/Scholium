import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Agent uncertain evidence boundary")
struct AgentUncertainEvidenceBoundaryTests {
    @Test("An Application uncertain outcome preserves prepared exact Agent evidence through reopening")
    func commitUncertainRetainsPreparedEvidence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScholiumAgentUncertainEvidence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let analyses = root.appendingPathComponent("Analyses", isDirectory: true)
        let topics = root.appendingPathComponent("Topics", isDirectory: true)
        let works = root.appendingPathComponent("Works", isDirectory: true)
        let before = Data("\u{FEFF}# Before\r\nExact e\u{301} source.\r\n".utf8)
        let after = Data("\u{FEFF}# Candidate\r\nKeep 中文 e\u{301} 📝 exactly.\r\n".utf8)
        for directory in [support, analyses, topics, works] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let noteURL = analyses.appendingPathComponent("Evidence.md")
        try before.write(to: noteURL)
        try Data("# Topic\n".utf8).write(to: topics.appendingPathComponent("Topic.md"))
        try Data("# Work\n".utf8).write(to: works.appendingPathComponent("Work.md"))
        let configuration = WorkspaceRuntime.Configuration.live(
            .init(
                applicationSupportURL: support,
                workspaceRegistryStorageURL: root.appendingPathComponent("Registry", isDirectory: true)))
        let runtime = WorkspaceRuntime(configuration: configuration)
        do {
            let handle = try await runtime.configureTriptych(
                paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                portableContainerURL: root, triptychName: "Uncertain evidence fixture")
            let snapshot = try await handle.snapshot()
            let note = try #require(snapshot.vaults.flatMap(\.documents).first { $0.id.relativePath == "Evidence.md" })
            let noteID = try #require(note.stableIdentity.resolvedID)
            let services = await handle.services
            let store = services.agentChangeStore
            let prepared = try await store.prepare(
                operation: .update, noteID: noteID, role: note.vaultRole,
                originalRelativePath: note.id.relativePath, finalRelativePath: note.id.relativePath,
                beforeData: before, afterData: after)

            // Core's regression separately proves the postwrite replacement failure.
            // This companion exercises the public Application uncertainty boundary
            // through the existing consequential failure helper without a source write.
            try await handle.finishFailedAgentMutation(
                changeID: prepared.id,
                error: ScholiumApplicationError.operationCommitUncertain(
                    operation: "Save Note", reason: "Synthetic postwrite recovery verification refusal."))

            #expect(try await store.change(id: prepared.id).state == .outcomeUncertain)
            await runtime.shutdown()
            let reopened = WorkspaceRuntime(configuration: configuration)
            do {
                let reopenedHandle = try await reopened.openWorkspace(id: handle.id)
                let reopenedServices = await reopenedHandle.services
                let evidence = try await reopenedServices.agentChangeStore.evidence(id: prepared.id)
                #expect(evidence.change.state == .outcomeUncertain)
                #expect(evidence.change.beforeFingerprint == DocumentFingerprint(data: before))
                #expect(evidence.change.afterFingerprint == DocumentFingerprint(data: after))
                #expect(evidence.beforeData == before)
                #expect(evidence.afterData == after)
                #expect(try Data(contentsOf: noteURL) == before)
                await reopened.shutdown()
            } catch {
                await reopened.shutdown()
                throw error
            }
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }
}
