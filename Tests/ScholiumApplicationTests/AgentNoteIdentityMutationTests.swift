import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Agent Note mutation identity")
struct AgentNoteIdentityMutationTests {
    @Test(
        "Queued Agent update and Undo refuse another Note with identical bytes at the captured path",
        arguments: [false, true])
    func queuedMutationRejectsReusedPath(undo: Bool) async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try await ApplicationFixture.make(
            rootURL: repositoryRoot.appendingPathComponent(".build/AgentNoteIdentity-\(UUID().uuidString)"))
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(
            configuration: .snapshot(
                .init(applicationSupportURL: fixture.applicationSupportURL, assignments: [fixture.assignment])))
        do {
            try await exerciseQueuedMutation(fixture: fixture, runtime: runtime, undo: undo)
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    private func exerciseQueuedMutation(
        fixture: ApplicationFixture, runtime: WorkspaceRuntime, undo: Bool
    ) async throws {
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let original = try await handle.documents.load(fixture.analysisNoteID)
        let snapshot = try await handle.refresh()
        let originalID = try #require(snapshot.document(id: fixture.analysisNoteID)?.stableIdentity.resolvedID)
        let update = try await handle.agentCollaboration.updateNote(
            noteID: originalID, expectedFingerprint: original.fingerprint,
            update: .source("# Ending revision\n\nIdentical bytes do not make two Notes identical.\n"))
        let ending = try await handle.documents.load(fixture.analysisNoteID)
        #expect(update.change.state == .confirmed)
        #expect(update.afterFingerprint == ending.fingerprint)

        if undo {
            let otherID = try #require(snapshot.vaults.flatMap(\.documents)
                .compactMap(\.stableIdentity.resolvedID).first { $0 != originalID })
            do {
                _ = try await handle.saveDocument(
                    fixture.analysisNoteID, changeSet: .exactContent(original.rawContent),
                    expectedRevision: ending.fingerprint, expectedStableNoteID: otherID,
                    undoAgentChangeID: update.change.id)
                Issue.record("A caller identity conflicting with the Undo receipt must reject before writing.")
            } catch NoteIdentityRecoveryError.targetIdentityChanged(let path) {
                #expect(path == fixture.analysisNoteID.relativePath)
            } catch {
                Issue.record("Expected a conflicting Note identity, received: \(error)")
            }
            #expect(try Data(contentsOf: fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath)) == ending.sourceBytes)
            #expect(try await handle.services.agentChangeStore.change(id: update.change.id).state == .confirmed)
        }

        let holder = try await handle.acquireWorkspaceSourceOperation(.sourceMutation)
        // These are the shared-writer arguments passed by Agent update/Undo
        // after target capture. The preceding update uses the public Agent API;
        // this interleaving exercises its consequential writer directly. Undo
        // also proves the receipt binding when no explicit caller ID is supplied.
        let pending = Task {
            try await handle.saveDocument(
                fixture.analysisNoteID,
                changeSet: undo ? .exactContent(original.rawContent) : .source("# Misattributed update\n"),
                expectedRevision: ending.fingerprint,
                expectedStableNoteID: undo ? nil : originalID,
                undoAgentChangeID: undo ? update.change.id : nil)
        }
        let waiting = await waitUntilQueued(handle)
        #expect(waiting)
        guard waiting else {
            pending.cancel()
            await handle.releaseWorkspaceSourceOperation(holder)
            _ = try? await pending.value
            return
        }

        let movedPath = "MovedAgency.md"
        do {
            let repository = try await handle.repository(vaultID: fixture.analysisNoteID.vaultID)
            let control = await handle.services.controlStore
            _ = try await repository.move(
                relativePath: fixture.analysisNoteID.relativePath, to: movedPath,
                expectedRevision: ending.fingerprint)
            _ = try await control.moveIdentity(
                id: originalID, to: movedPath, fingerprint: ending.fingerprint)
            _ = try await repository.create(
                relativePath: fixture.analysisNoteID.relativePath, content: ending.rawContent)
            let replacement = try #require(try await control.identity(
                forVaultID: fixture.analysisNoteID.vaultID,
                relativePath: fixture.analysisNoteID.relativePath, fingerprint: ending.fingerprint))
            #expect(replacement.id != originalID)
        } catch {
            pending.cancel()
            await handle.releaseWorkspaceSourceOperation(holder)
            _ = try? await pending.value
            throw error
        }
        await handle.releaseWorkspaceSourceOperation(holder)

        do {
            _ = try await pending.value
            Issue.record("The captured Agent mutation must reject the replacement Note before writing.")
        } catch NoteIdentityRecoveryError.identityUnresolved(let path) {
            #expect(path == fixture.analysisNoteID.relativePath)
        } catch NoteIdentityRecoveryError.targetIdentityChanged(let path) {
            #expect(path == fixture.analysisNoteID.relativePath)
        } catch {
            Issue.record("Expected a Note identity rejection, received: \(error)")
        }
        #expect(try Data(contentsOf: fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath)) == ending.sourceBytes)
        #expect(try Data(contentsOf: fixture.analysesURL.appendingPathComponent(movedPath)) == ending.sourceBytes)
        let receipt = try await handle.services.agentChangeStore.change(id: update.change.id)
        #expect(receipt.state == .confirmed, "A rejected Undo must retain its original confirmed receipt.")
        #expect(receipt.undoneAt == nil)

        // Freshly resolving A at its new location remains a valid operation.
        // The replacement B must survive both the refusal and this neighbor.
        if undo {
            let restored = try await handle.agentCollaboration.undoAgentChange(
                id: update.change.id, expectedAfterFingerprint: ending.fingerprint)
            #expect(restored.noteID == originalID && restored.restoredFingerprint == original.fingerprint)
            #expect(try Data(contentsOf: fixture.analysesURL.appendingPathComponent(movedPath)) == original.sourceBytes)
            #expect(try await handle.services.agentChangeStore.change(id: update.change.id).state == .undone)
        } else {
            let freshSource = "# Correctly addressed update\n"
            let fresh = try await handle.agentCollaboration.updateNote(
                noteID: originalID, expectedFingerprint: ending.fingerprint, update: .source(freshSource))
            #expect(fresh.noteID == originalID && fresh.change.state == .confirmed)
            #expect(try Data(contentsOf: fixture.analysesURL.appendingPathComponent(movedPath)) == Data(freshSource.utf8))
        }
        #expect(try Data(contentsOf: fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath)) == ending.sourceBytes)
    }

    private func waitUntilQueued(_ handle: WorkspaceHandle) async -> Bool {
        for _ in 0..<1_000 {
            if await handle.sourceOperationGate.waitingCount == 1 { return true }
            await Task.yield()
        }
        return await handle.sourceOperationGate.waitingCount == 1
    }
}
