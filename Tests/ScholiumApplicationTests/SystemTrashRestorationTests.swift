import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("System Trash and Finder restoration convergence")
struct SystemTrashRestorationTests {
    @Test("Native observation publishes externally created and restored folders without an explicit refresh", arguments: [false, true])
    func liveFolderTrashAndRestoration(includesNote: Bool) async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/file-operations-fixtures/\(UUID().uuidString)", isDirectory: true)
        let fixture = try await ApplicationFixture.make(registerLiveAccess: true, rootURL: root)
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL,
                    workspaceRegistryStorageURL: fixture.registryStorageURL)))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let stream = await handle.events.events()
        let publications = NativeFolderPublicationObserver()
        let consumer = Task { for await event in stream { await publications.receive(event) } }
        defer { consumer.cancel() }
        do {
            let initial = try await publications.wait { $0.snapshot.phase.isComplete }
            let vaultID = fixture.analysisNoteID.vaultID
            let path = "Live folder-\(UUID().uuidString)"
            let folder = fixture.analysesURL.appendingPathComponent(path, isDirectory: true)
            let nested = folder.appendingPathComponent("Level Two/Level Three", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("# Exact\r\nSource without final newline".utf8)
            let id = VaultQualifiedNoteID(vaultID: vaultID, relativePath: path + "/Level Two/Level Three/Exact.md")
            if includesNote { try bytes.write(to: nested.appendingPathComponent("Exact.md")) }
            // The event stream retains only the newest generation. A citation
            // invalidation can supersede inventoryChanged while carrying the
            // same authoritative inventory; require successful source advance.
            let created = try await publications.wait {
                $0.snapshot.phase.isComplete
                    && $0.generation > initial.generation
                    && $0.snapshot.sourceInventoryRevision > initial.snapshot.sourceInventoryRevision
                    && $0.snapshot.vault(id: vaultID)?.folders.contains { $0.rawValue == path + "/Level Two/Level Three" } == true
                    && (!includesNote || $0.snapshot.document(id: id) != nil)
            }
            let expectedID: UUID?
            if includesNote {
                expectedID = try #require(created.snapshot.document(id: id)?.stableIdentity.resolvedID)
            } else {
                expectedID = nil
            }
            let preview = try await handle.documents.prepareFolderSystemTrash(inVault: vaultID, relativePath: path)
            let commit = try await handle.documents.moveToSystemTrash(preview).committedValue
            let destination = URL(fileURLWithPath: try #require(commit.resultingTrashPaths.first))
            defer { try? FileManager.default.removeItem(at: destination) }
            let deleted = try await publications.wait {
                $0.snapshot.phase.isComplete
                    && $0.generation > created.generation
                    && $0.snapshot.sourceInventoryRevision > created.snapshot.sourceInventoryRevision
                    && $0.snapshot.vault(id: vaultID)?.folders.contains { $0.rawValue == path } == false
                    && (!includesNote || $0.snapshot.document(id: id) == nil)
            }
            // This simulates Finder's external filesystem restoration. Native
            // callbacks, catalog reconciliation and publication all run live.
            try FileManager.default.moveItem(at: destination, to: folder)
            _ = try await publications.wait {
                $0.snapshot.phase.isComplete
                    && $0.generation > deleted.generation
                    && $0.snapshot.sourceInventoryRevision > deleted.snapshot.sourceInventoryRevision
                    && $0.snapshot.vault(id: vaultID)?.folders.contains { $0.rawValue == path + "/Level Two/Level Three" } == true
                    && (!includesNote || $0.snapshot.document(id: id)?.stableIdentity.resolvedID == expectedID)
            }
            if includesNote { #expect(try await handle.documents.load(id).sourceBytes == bytes) }
            #expect(try await handle.research.recoveryRecords().isEmpty)
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    @Test("Empty, non-Markdown and Note folders share complete-manifest Trash and restoration", arguments: [0, 1, 2])
    func folderTrashAndRestoration(contents: Int) async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let path = "Folder-\(UUID().uuidString)"
        let folder = fixture.analysesURL.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("# Exact\r\n\r\nSource without final newline".utf8)
        if contents == 1 { try bytes.write(to: folder.appendingPathComponent("attachment.bin")) }
        if contents == 2 { try bytes.write(to: folder.appendingPathComponent("Exact.md")) }
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let preview = try await handle.documents.prepareFolderSystemTrash(
            inVault: fixture.analysisNoteID.vaultID, relativePath: path)
        #expect(preview.sources.count == 1)
        #expect(preview.sources.first?.notes.count == (contents == 2 ? 1 : 0))
        #expect(preview.sources.first?.expectedDirectoryManifest != nil)
        let expectedID = preview.sources.first?.notes.first?.noteID
        let outcome = try await handle.documents.moveToSystemTrash(preview)
        let trashed = URL(fileURLWithPath: try #require(outcome.committedValue.resultingTrashPaths.first))
        defer { try? FileManager.default.removeItem(at: trashed) }
        #expect(outcome.derivedRefreshWarning == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(try await handle.research.recoveryRecords().isEmpty)
        let after = try await handle.discovery.refresh()
        #expect(after.vault(id: fixture.analysisNoteID.vaultID)?.folders.contains { $0.rawValue == path } == false)
        if contents > 0 {
            #expect(try Data(contentsOf: trashed.appendingPathComponent(contents == 1 ? "attachment.bin" : "Exact.md")) == bytes)
        }
        // Finder's source restoration is an external filesystem observation;
        // no Scholium restore command or mutation receipt is created.
        try FileManager.default.moveItem(at: trashed, to: folder)
        let restored = try await handle.discovery.refresh()
        #expect(restored.vault(id: fixture.analysisNoteID.vaultID)?.folders.contains { $0.rawValue == path } == true)
        if contents == 2 {
            let id = VaultQualifiedNoteID(vaultID: fixture.analysisNoteID.vaultID, relativePath: path + "/Exact.md")
            #expect(restored.document(id: id)?.stableIdentity.resolvedID == expectedID)
            #expect(try await handle.documents.load(id).sourceBytes == bytes)
        }
        await runtime.shutdown()
    }

    @Test("A multi-Note native Trash operation returns per-source receipts and restores stable identities")
    func noteBatchTrashAndRestoration() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let paths = ["First-\(UUID().uuidString).md", "Second-\(UUID().uuidString).md"]
        for path in paths { try Data(("# " + path + "\n").utf8).write(to: fixture.analysesURL.appendingPathComponent(path)) }
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let snapshot = try await handle.snapshot()
        var sources: [SystemTrashDeletionSourceTarget] = []
        var expectedIDs: [String: UUID] = [:]
        for path in paths {
            let id = VaultQualifiedNoteID(vaultID: fixture.analysisNoteID.vaultID, relativePath: path)
            let summary = try #require(snapshot.document(id: id))
            let stableID = try #require(summary.stableIdentity.resolvedID)
            expectedIDs[path] = stableID
            sources += try await handle.documents.prepareSystemTrash(
                NoteMutationTarget(documentID: id, stableNoteID: stableID, revision: summary.fingerprint)
            ).sources
        }
        let preview = SystemTrashDeletionPreview(triptychID: fixture.assignment.id, sources: sources)
        let commit = try await handle.documents.moveToSystemTrash(preview).committedValue
        defer { for path in commit.resultingTrashPaths { try? FileManager.default.removeItem(atPath: path) } }
        #expect(commit.resultingTrashPaths.count == 2)
        for (original, destination) in zip(commit.originalRelativePaths, commit.resultingTrashPaths) {
            try FileManager.default.moveItem(at: URL(fileURLWithPath: destination), to: fixture.analysesURL.appendingPathComponent(original))
        }
        let restored = try await handle.discovery.refresh()
        for path in paths {
            let id = VaultQualifiedNoteID(vaultID: fixture.analysisNoteID.vaultID, relativePath: path)
            #expect(restored.document(id: id)?.stableIdentity.resolvedID == expectedIDs[path])
        }
        #expect(try await handle.research.recoveryRecords().isEmpty)
        await runtime.shutdown()
    }
}

private actor NativeFolderPublicationObserver {
    private var latest: WorkspaceEvent?
    func receive(_ event: WorkspaceEvent) { latest = event }

    func wait(_ predicate: @Sendable (WorkspaceEvent) -> Bool) async throws -> WorkspaceEvent {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline {
            if let latest, predicate(latest) { return latest }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "The native folder inventory did not publish before the bounded deadline."])
    }
}
