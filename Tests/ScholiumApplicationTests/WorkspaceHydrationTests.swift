import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Workspace demand hydration")
struct WorkspaceHydrationTests {
    @Test("Folder link rewrites authorize a later incoming-Note mutation before complete publication")
    func folderRewritesAdvanceOutsideIdentities() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let old = fixture.analysesURL.appendingPathComponent("Old", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("# Descendant\n".utf8).write(to: old.appendingPathComponent("Descendant.md"))
        try Data("# Incoming\n\n[[Old/Descendant]]\n".utf8).write(to: fixture.analysesURL.appendingPathComponent("Incoming.md"))
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let gate = HydrationReadGate()
        await handle.setCommittedMutationRefreshBarrierForTesting { await gate.hold() }
        defer {
            Task {
                await handle.setCommittedMutationRefreshBarrierForTesting(nil)
                await gate.release()
                await runtime.shutdown()
            }
        }
        let first = try await handle.documents.moveFolder(
            inVault: fixture.analysisNoteID.vaultID, from: "Old", to: "Filed")
        await gate.waitUntilEntered()
        #expect(first.identityRecoveryWarning == nil)
        let second = try await handle.documents.moveFolder(
            inVault: fixture.analysisNoteID.vaultID, from: "Filed", to: "Other")
        #expect(second.identityRecoveryWarning == nil)
        let incoming = try #require(second.committedSourceSummaries.first { $0.id.relativePath == "Incoming.md" })
        #expect(try await handle.documents.hydrate(incoming).document.rawContent == "# Incoming\n\n[[Other/Descendant]]\n")
        let moved = try await handle.documents.move(
            NoteMutationTarget(documentID: incoming.id, stableNoteID: #require(incoming.stableIdentity.resolvedID), revision: incoming.fingerprint),
            to: "Other/Incoming.md")
        #expect(moved.identityRecoveryWarning == nil)
        let target = try #require(moved.committedSourceSummaries.first { $0.id == moved.committedValue.destination })
        let preview = try await handle.documents.prepareSystemTrash(
            NoteMutationTarget(documentID: target.id, stableNoteID: #require(target.stableIdentity.resolvedID), revision: target.fingerprint))
        #expect(preview.sources.first?.relativePath == target.id.relativePath)
        await handle.setCommittedMutationRefreshBarrierForTesting(nil)
        await gate.release()
        await runtime.shutdown()
    }

    @Test("Repeated moves hydrate each exact committed source while complete derived publication is suspended")
    func consecutiveSourceAheadMoves() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let sourceBytes = Data("# Agency\n\n[[LocalTarget]]\n".utf8)
        let old = fixture.analysesURL.appendingPathComponent("Old", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try sourceBytes.write(to: old.appendingPathComponent("Agency.md"))
        try Data("# Original target\n".utf8).write(to: old.appendingPathComponent("LocalTarget.md"))
        let filed = fixture.analysesURL.appendingPathComponent("Filed", isDirectory: true)
        try FileManager.default.createDirectory(at: filed, withIntermediateDirectories: true)
        try Data("# Different target\n".utf8).write(to: filed.appendingPathComponent("LocalTarget.md"))
        try Data("# Incoming\n\n[[Old/Agency]]\n".utf8).write(to: fixture.analysesURL.appendingPathComponent("Incoming.md"))
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let gate = HydrationReadGate()
        await handle.setCommittedMutationRefreshBarrierForTesting { await gate.hold() }
        defer {
            Task {
                await handle.setCommittedMutationRefreshBarrierForTesting(nil)
                await gate.release()
                await runtime.shutdown()
            }
        }
        let originalID = VaultQualifiedNoteID(vaultID: fixture.analysisNoteID.vaultID, relativePath: "Old/Agency.md")
        let original = try #require(await handle.snapshot().document(id: originalID))
        let stableID = try #require(original.stableIdentity.resolvedID)
        let first = try await handle.documents.move(
            NoteMutationTarget(documentID: original.id, stableNoteID: stableID, revision: original.fingerprint),
            to: "Filed/Agency.md")
        await gate.waitUntilEntered()
        #expect(first.identityRecoveryWarning == nil)
        #expect(first.committedValue.committedRevision != original.fingerprint)
        let moved = try #require(first.committedSourceSummaries.first { $0.id == first.committedValue.destination })
        let hydrated = try await handle.documents.hydrate(moved)
        #expect(hydrated.document.rawContent == "# Agency\n\n[[Old/LocalTarget]]\n")
        let second = try await handle.documents.move(
            NoteMutationTarget(documentID: moved.id, stableNoteID: stableID, revision: moved.fingerprint),
            to: "Other/Agency.md")
        #expect(second.identityRecoveryWarning == nil)
        var next = try #require(second.committedSourceSummaries.first { $0.id == second.committedValue.destination })
        #expect(try await handle.documents.hydrate(next).document.fingerprint == next.fingerprint)
        #expect(try await handle.snapshot().document(id: next.id) == nil)

        for destination in ["Old/Agency.md", "Other/Agency.md"] {
            let repeated = try await handle.documents.move(
                NoteMutationTarget(documentID: next.id, stableNoteID: stableID, revision: next.fingerprint),
                to: destination)
            #expect(repeated.identityRecoveryWarning == nil)
            next = try #require(repeated.committedSourceSummaries.first { $0.id == repeated.committedValue.destination })
            #expect(try await handle.documents.hydrate(next).document.fingerprint == next.fingerprint)
        }

        let incoming = try #require(second.committedSourceSummaries.first { $0.id.relativePath == "Incoming.md" })
        #expect(try await handle.documents.hydrate(incoming).document.rawContent.contains("[[Other/Agency]]"))
        let incomingID = try #require(incoming.stableIdentity.resolvedID)
        let incomingMove = try await handle.documents.move(
            NoteMutationTarget(documentID: incoming.id, stableNoteID: incomingID, revision: incoming.fingerprint),
            to: "Other/Incoming.md")
        #expect(incomingMove.identityRecoveryWarning == nil)
        let currentIncoming = try #require(
            incomingMove.committedSourceSummaries.first {
                $0.id == incomingMove.committedValue.destination
            })
        #expect(try await handle.documents.hydrate(currentIncoming).document.fingerprint == currentIncoming.fingerprint)
        await handle.setCommittedMutationRefreshBarrierForTesting(nil)
        await gate.release()
        let rebuilt = try await handle.discovery.refresh()
        #expect(rebuilt.document(id: next.id)?.stableIdentity.resolvedID == stableID)
        #expect(rebuilt.document(id: incomingMove.committedValue.destination)?.stableIdentity.resolvedID == incomingID)
        await runtime.shutdown()
    }

    @Test("A source-ahead move rejects identical bytes recreated at its committed path")
    func sourceAheadReplacementDoesNotBorrowIdentity() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let gate = HydrationReadGate()
        await handle.setCommittedMutationRefreshBarrierForTesting { await gate.hold() }
        defer {
            Task {
                await handle.setCommittedMutationRefreshBarrierForTesting(nil)
                await gate.release()
                await runtime.shutdown()
            }
        }
        let source = try #require(await handle.snapshot().document(id: fixture.analysisNoteID))
        let moved = try await handle.documents.move(
            NoteMutationTarget(documentID: source.id, stableNoteID: #require(source.stableIdentity.resolvedID), revision: source.fingerprint),
            to: "Filed/Agency.md")
        await gate.waitUntilEntered()
        let summary = try #require(moved.committedSourceSummaries.first { $0.id == moved.committedValue.destination })
        let path = fixture.analysesURL.appendingPathComponent(summary.id.relativePath)
        let bytes = try Data(contentsOf: path)
        try FileManager.default.moveItem(at: path, to: path.deletingLastPathComponent().appendingPathComponent("External original.md"))
        try bytes.write(to: path)
        await #expect(throws: WorkspaceHydrationError.self) { try await handle.documents.hydrate(summary) }
        await #expect(throws: (any Error).self) {
            try await handle.documents.move(
                NoteMutationTarget(documentID: summary.id, stableNoteID: #require(summary.stableIdentity.resolvedID), revision: summary.fingerprint),
                to: "Other/Agency.md")
        }
        #expect(try Data(contentsOf: path) == bytes)
        await handle.setCommittedMutationRefreshBarrierForTesting(nil)
        await gate.release()
        await runtime.shutdown()
    }

    @Test("Hydration preserves BOM, CRLF, malformed YAML, Unicode, and missing final newline")
    func exactBytesAndReadOnlyIdentity() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let relativePath = "E\u{301}tude.md"
        let bytes =
            Data([0xEF, 0xBB, 0xBF])
            + Data("---\r\ntitle: Étude\r\ninvalid: [\r\n---\r\n# Étude\r\nExact 😀 source".utf8)
        try bytes.write(to: fixture.analysesURL.appendingPathComponent(relativePath))
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let vault = try #require(try await handle.snapshot().vault(id: fixture.analysisNoteID.vaultID))
        let summary = try #require(
            vault.documents.first {
                $0.id.relativePath.utf8.elementsEqual(relativePath.utf8)
            })
        let services = await handle.services
        #if DEBUG
            let decodes = await services.controlStore.identitySnapshotDecodeCountForTesting
        #endif
        let hydrated = try await handle.documents.hydrate(summary)
        #if DEBUG
            #expect(await services.controlStore.identitySnapshotDecodeCountForTesting == decodes + 1)
        #endif
        #expect(hydrated.document.sourceBytes == bytes)
        #expect(hydrated.summary.validationWarnings == hydrated.document.validationWarnings)
        #expect(!hydrated.summary.validationWarnings.isEmpty)
        #expect(hydrated.document.relativePath.utf8.elementsEqual(relativePath.utf8))
        await runtime.shutdown()
    }

    @Test("A same-source graph publication during the read returns current metadata")
    func sameSourceDerivedPublication() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        defer { Task { await runtime.shutdown() } }
        let original = try #require(await handle.snapshot().document(id: fixture.analysisNoteID))
        let gate = HydrationReadGate()
        await handle.setHydrationPostReadBarrierForTesting { await gate.hold() }
        let pending = Task { try await handle.documents.hydrate(original) }
        await gate.waitUntilEntered()

        try Data("# New incoming source\n\n[[Agency]]\n".utf8).write(
            to: fixture.analysesURL.appendingPathComponent("Incoming.md"))
        let refreshed = try await handle.discovery.refresh()
        let current = try #require(refreshed.document(id: fixture.analysisNoteID))
        #expect(current.fingerprint == original.fingerprint)
        #expect(current.graphCounts.incoming > original.graphCounts.incoming)
        await gate.release()
        let hydrated = try await pending.value
        #expect(hydrated.summary == current)
        #expect(hydrated.document.fingerprint == original.fingerprint)
        await handle.setHydrationPostReadBarrierForTesting(nil)
        await runtime.shutdown()
    }

    @Test("A changed source or closed runtime cannot publish a suspended read")
    func staleReadAndShutdown() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let original = try #require(await handle.snapshot().document(id: fixture.analysisNoteID))
        let gate = HydrationReadGate()
        await handle.setHydrationPostReadBarrierForTesting { await gate.hold() }
        let pending = Task { try await handle.documents.hydrate(original) }
        await gate.waitUntilEntered()
        try Data("# Agency\n\nExternal changed bytes.\n".utf8).write(
            to: fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath),
            options: .atomic)
        await gate.release()
        await #expect(throws: WorkspaceHydrationError.self) { try await pending.value }
        await handle.setHydrationPostReadBarrierForTesting(nil)

        let fresh = try await handle.discovery.refresh()
        let next = try #require(fresh.document(id: fixture.analysisNoteID))
        let closeGate = HydrationReadGate()
        await handle.setHydrationPostReadBarrierForTesting { await closeGate.hold() }
        let closingRead = Task { try await handle.documents.hydrate(next) }
        await closeGate.waitUntilEntered()
        await runtime.shutdown()
        await closeGate.release()
        await #expect(throws: ScholiumApplicationError.self) { try await closingRead.value }
    }
    @Test("Preview hydration shares one identity decode and rejects replacement between targets")
    func previewIdentityInventoryIsOperationLocal() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        try Data("# Agency\n\n[[Freedom]] and [[Chapter]]\n".utf8)
            .write(to: fixture.analysesURL.appendingPathComponent("Agency.md"))
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL)
        let handle: WorkspaceHandle
        do { handle = try await runtime.openWorkspace(id: fixture.assignment.id) } catch {
            await runtime.shutdown()
            throw error
        }
        let gate = HydrationReadGate()
        var pending: Task<DocumentPreviewCatalog, Error>?
        do {
            let snapshot = try await handle.snapshot()
            let graph = try #require(snapshot.discovery.catalog.graph)
            let source = try #require(snapshot.document(id: fixture.analysisNoteID))
            let services = await handle.services
            #if DEBUG
                let decodes = await services.controlStore.identitySnapshotDecodeCountForTesting
            #endif
            let unlinked = try #require(snapshot.vaults.flatMap(\.documents).first { $0.id.relativePath == "Chapter.md" })
            #expect(
                try await handle.documents.documentPreviewCatalog(
                    source: unlinked.id, sourceFingerprint: unlinked.fingerprint, graphGeneration: graph.generation
                ).links.isEmpty)
            #if DEBUG
                #expect(await services.controlStore.identitySnapshotDecodeCountForTesting == decodes)
            #endif
            let catalog = try await handle.documents.documentPreviewCatalog(
                source: source.id, sourceFingerprint: source.fingerprint, graphGeneration: graph.generation)
            try #require(catalog.links.count == 2)
            #expect(Set(catalog.links.map(\.title)) == ["Freedom", "Chapter"])
            #if DEBUG
                #expect(await services.controlStore.identitySnapshotDecodeCountForTesting == decodes + 1)
            #endif
            let identitiesURL = fixture.rootURL.appendingPathComponent(".scholium/identities.json")
            let original = try Data(contentsOf: identitiesURL)
            await handle.setHydrationPostReadBarrierForTesting { await gate.holdSecondRead() }
            pending = Task {
                try await handle.documents.documentPreviewCatalog(
                    source: source.id, sourceFingerprint: source.fingerprint, graphGeneration: graph.generation)
            }
            try await gate.waitUntilEntered(timeout: .seconds(10))
            // The first target has completed; identical bytes at a replaced
            // identity file must not admit the remaining target from that batch.
            try original.write(to: identitiesURL, options: .atomic)
            await gate.release()
            let operation = try #require(pending)
            await #expect(throws: (any Error).self) { try await operation.value }
            pending = nil
            await handle.setHydrationPostReadBarrierForTesting(nil)
            await runtime.shutdown()
        } catch {
            await handle.setHydrationPostReadBarrierForTesting(nil)
            await gate.release()
            pending?.cancel()
            _ = try? await pending?.value
            await runtime.shutdown()
            throw error
        }
    }
}

private actor HydrationReadGate {
    private var readCount = 0
    private var entered = false
    private var released = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func holdSecondRead() async {
        readCount += 1
        if readCount == 2 { await hold() }
    }

    func hold() async {
        guard !released else { return }
        entered = true
        arrival?.resume()
        arrival = nil
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func waitUntilEntered(timeout: Duration) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !entered && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(entered, "Preview hydration did not reach its second target.")
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
