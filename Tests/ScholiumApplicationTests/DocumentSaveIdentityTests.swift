import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Researcher save identity")
struct DocumentSaveIdentityTests {
    @Test("A queued researcher save refuses a replacement Note with identical bytes", arguments: [false, true])
    func queuedSaveRejectsReusedPath(waitForDerived: Bool) async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try await ApplicationFixture.make(
            rootURL: repositoryRoot.appendingPathComponent(".build/DocumentSaveIdentity-\(UUID().uuidString)"))
        let runtime = WorkspaceRuntime(
            configuration: .snapshot(
                .init(applicationSupportURL: fixture.applicationSupportURL, assignments: [fixture.assignment])))
        do {
            try await exerciseQueuedSave(fixture: fixture, runtime: runtime, waitForDerived: waitForDerived)
            await runtime.shutdown()
            fixture.remove()
        } catch {
            await runtime.shutdown()
            fixture.remove()
            throw error
        }
    }

    private func exerciseQueuedSave(
        fixture: ApplicationFixture, runtime: WorkspaceRuntime, waitForDerived: Bool
    ) async throws {
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let original = try await handle.documents.load(fixture.analysisNoteID)
        let snapshot = try await handle.refresh()
        let originalID = try #require(snapshot.document(id: fixture.analysisNoteID)?.stableIdentity.resolvedID)
        let target = NoteMutationTarget(documentID: fixture.analysisNoteID, stableNoteID: originalID, revision: original.fingerprint)
        let holder = try await handle.acquireWorkspaceSourceOperation(.sourceMutation)
        let pending = Task {
            if waitForDerived {
                _ = try await handle.documents.save(
                    target, changeSet: .source("# Misattributed researcher edit\n"))
            } else {
                _ = try await handle.documents.commit(
                    target, changeSet: .source("# Misattributed researcher edit\n"))
            }
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
                expectedRevision: original.fingerprint)
            _ = try await control.moveIdentity(id: originalID, to: movedPath, fingerprint: original.fingerprint)
            _ = try await repository.create(relativePath: fixture.analysisNoteID.relativePath, content: original.rawContent)
            let replacement = try #require(
                try await control.identity(
                    forVaultID: fixture.analysisNoteID.vaultID,
                    relativePath: fixture.analysisNoteID.relativePath, fingerprint: original.fingerprint))
            #expect(replacement.id != originalID)
        } catch {
            pending.cancel()
            await handle.releaseWorkspaceSourceOperation(holder)
            _ = try? await pending.value
            throw error
        }
        await handle.releaseWorkspaceSourceOperation(holder)

        do {
            try await pending.value
            Issue.record("The captured researcher save overwrote a replacement Note.")
        } catch NoteIdentityRecoveryError.identityUnresolved(let path) {
            #expect(path == fixture.analysisNoteID.relativePath)
        } catch NoteIdentityRecoveryError.targetIdentityChanged(let path) {
            #expect(path == fixture.analysisNoteID.relativePath)
        } catch {
            Issue.record("Expected a Note identity rejection, received: \(error)")
        }
        let originalURL = fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath)
        let movedURL = fixture.analysesURL.appendingPathComponent(movedPath)
        #expect(try Data(contentsOf: originalURL) == original.sourceBytes)
        #expect(try Data(contentsOf: movedURL) == original.sourceBytes)

        // Freshly addressed source at the moved identity remains writable.
        let freshSource = "# Correctly addressed researcher edit\n"
        let movedID = VaultQualifiedNoteID(vaultID: fixture.analysisNoteID.vaultID, relativePath: movedPath)
        _ = try await handle.refresh()
        _ = try await handle.documents.commit(
            NoteMutationTarget(documentID: movedID, stableNoteID: originalID, revision: original.fingerprint),
            changeSet: .source(freshSource))
        #expect(try Data(contentsOf: movedURL) == Data(freshSource.utf8))
        #expect(try Data(contentsOf: originalURL) == original.sourceBytes)
    }

    @Test("Repeated source commits retain identity while derived refresh is unavailable")
    func repeatedCommitsBeforeDerivedRefresh() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try await ApplicationFixture.make(
            rootURL: repositoryRoot.appendingPathComponent(".build/DocumentSaveIdentity-\(UUID().uuidString)"))
        let runtime = WorkspaceRuntime(
            configuration: .snapshot(
                .init(applicationSupportURL: fixture.applicationSupportURL, assignments: [fixture.assignment])))
        do {
            let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            let original = try await handle.documents.load(fixture.analysisNoteID)
            let target = try await capturedSaveTarget(handle, fixture.analysisNoteID, revision: original.fingerprint)
            let invalidURL = fixture.topicsURL.appendingPathComponent("Invalid UTF-8.md")
            try Data([0xFF]).write(to: invalidURL)
            var revision = original.fingerprint
            for source in ["# First exact save\r\n", "\u{FEFF}# Second exact save\r\n"] {
                let saved = try await handle.documents.commit(
                    NoteMutationTarget(documentID: target.documentID, stableNoteID: target.stableNoteID, revision: revision),
                    changeSet: .source(source))
                revision = saved.document.fingerprint
                await handle.sourceCommitRefreshTask?.value
                #expect(try await handle.snapshot().document(id: target.documentID)?.fingerprint == original.fingerprint)
                #expect(try await handle.documents.load(target.documentID).sourceBytes == Data(source.utf8))
            }
            try FileManager.default.removeItem(at: invalidURL)
            let finalSource = "# Saved with current derived state\n"
            let saved = try await handle.documents.save(
                NoteMutationTarget(documentID: target.documentID, stableNoteID: target.stableNoteID, revision: revision),
                changeSet: .source(finalSource))
            #expect(saved.derivedRefreshWarning == nil)
            #expect(try await handle.snapshot().document(id: target.documentID)?.fingerprint == saved.committedValue.document.fingerprint)
            #expect(try await handle.documents.load(target.documentID).sourceBytes == Data(finalSource.utf8))
            await runtime.shutdown()
            fixture.remove()
        } catch {
            await runtime.shutdown()
            fixture.remove()
            throw error
        }
    }

    private func waitUntilQueued(_ handle: WorkspaceHandle) async -> Bool {
        for _ in 0..<1_000 {
            if await handle.sourceOperationGate.waitingCount == 1 { return true }
            await Task.yield()
        }
        return await handle.sourceOperationGate.waitingCount == 1
    }
}
