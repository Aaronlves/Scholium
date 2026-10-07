import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Stable note identity recovery")
struct NoteIdentityRecoveryTests {
    @Test("An unsupported window layout cannot block a confirmed move or repeated recovery")
    func unsupportedWindowDoesNotBlockMoveRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let stores = try await fixture.makeStores()
        let repository = try fixture.repository(vaultID: fixture.worksID, root: fixture.works)
        let exactSource = "\u{FEFF}---\r\ncustom: 'unchanged'\r\n---\r\n# Work\r\n[[Other]]"
        let original = try await repository.create(relativePath: "Old.md", content: exactSource)
        let identity = try #require(
            try await stores.control.identity(
                forVaultID: fixture.worksID, relativePath: "Old.md", fingerprint: original.fingerprint))
        let session = WindowSessionSnapshot(
            id: stores.sessionID,
            selectedWorkspace: .output,
            openDocuments: [.init(vaultID: fixture.worksID, relativePath: "Old.md")],
            selectedDocument: .init(vaultID: fixture.worksID, relativePath: "Old.md"),
            workspaceSessions: [
                .init(
                    workspace: .output,
                    vaultID: fixture.worksID,
                    documentPresentations: ["Old.md": .init(scrollFraction: 0.42)])
            ])
        try await stores.sessions.save(session)
        let unsupported = WindowSessionSnapshot(openDocuments: session.openDocuments)
        var incomplete = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(unsupported)) as? [String: Any])
        incomplete.removeValue(forKey: "documentMode")
        let unsupportedBytes = try JSONSerialization.data(withJSONObject: incomplete, options: [.sortedKeys])
        let unsupportedURL = fixture.support.appendingPathComponent("Window Sessions")
            .appendingPathComponent(unsupported.id.uuidString + ".json")
        try unsupportedBytes.write(to: unsupportedURL)
        let ledger = try PrewriteRecoveryLedger(storageURL: await repository.storageURL)
        let candidate = Data((exactSource + "\r\nCandidate").utf8)
        let transaction = try ledger.beginMutation(
            relativePath: "Old.md", expected: Data(exactSource.utf8), candidate: candidate)
        try ledger.retainMutation(transaction, reason: "Synthetic interrupted save")

        // The filesystem move and stable identity commit already succeeded.
        // Recovery must finish app-owned records without touching source again.
        try FileManager.default.moveItem(
            at: fixture.works.appendingPathComponent("Old.md"),
            to: fixture.works.appendingPathComponent("New.md"))
        _ = try await stores.control.moveIdentity(
            id: identity.id, vaultID: fixture.worksID,
            from: "Old.md", to: "New.md", fingerprint: original.fingerprint)
        let coordinator = NoteIdentityRecoveryCoordinator(control: stores.control, windowSessions: stores.sessions)
        let failures = await coordinator.resumePendingRebindings(vaultID: fixture.worksID, repository: repository)
        #expect(failures.isEmpty)
        #expect(try await stores.control.pendingIdentityRebindings(vaultID: fixture.worksID).isEmpty)
        #expect(try await stores.control.identityRecord(id: identity.id)?.relativePath == "New.md")
        let migrated = try #require(try await stores.sessions.load(id: session.id))
        #expect(migrated == session.migratingPath(vaultID: fixture.worksID, from: "Old.md", to: "New.md"))
        let recovery = try #require(try await repository.interruptedSaveRecoveries().first)
        #expect(recovery.id.transactionID == transaction.id)
        #expect(recovery.relativePath == "New.md")
        #expect(try await repository.interruptedSaveRecoveryContent(recovery).exactSource == String(decoding: candidate, as: UTF8.self))
        #expect(try Data(contentsOf: unsupportedURL) == unsupportedBytes)

        let repeated = await coordinator.resumePendingRebindings(vaultID: fixture.worksID, repository: repository)
        #expect(repeated.isEmpty)
        #expect(try await stores.sessions.load(id: session.id) == migrated)
        #expect(try Data(contentsOf: fixture.works.appendingPathComponent("New.md")) == Data(exactSource.utf8))
        #expect(!FileManager.default.fileExists(atPath: fixture.works.appendingPathComponent("Old.md").path))
        #expect(try Data(contentsOf: unsupportedURL) == unsupportedBytes)
    }

    @Test("Corrupt current window data retains progress and retries only record migration")
    func corruptWindowRecoveryRetainsProgress() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let stores = try await fixture.makeStores()
        let repository = try fixture.repository(vaultID: fixture.worksID, root: fixture.works)
        let original = try await repository.create(relativePath: "Old.md", content: "unchanged\n[[Other]]")
        let identity = try #require(
            try await stores.control.identity(
                forVaultID: fixture.worksID, relativePath: "Old.md", fingerprint: original.fingerprint))
        let session = WindowSessionSnapshot(
            id: stores.sessionID,
            openDocuments: [.init(vaultID: fixture.worksID, relativePath: "Old.md")],
            selectedDocument: .init(vaultID: fixture.worksID, relativePath: "Old.md"))
        try await stores.sessions.save(session)
        let sessionURL = fixture.support.appendingPathComponent("Window Sessions")
            .appendingPathComponent(session.id.uuidString + ".json")
        let supportedBytes = try Data(contentsOf: sessionURL)
        let corruptBytes = Data("{ malformed current window data".utf8)
        try corruptBytes.write(to: sessionURL)
        let ledger = try PrewriteRecoveryLedger(storageURL: await repository.storageURL)
        let candidate = Data("recovery candidate".utf8)
        let transaction = try ledger.beginMutation(
            relativePath: "Old.md", expected: Data(original.rawContent.utf8), candidate: candidate)
        try ledger.retainMutation(transaction, reason: "Synthetic interrupted save")
        try FileManager.default.moveItem(
            at: fixture.works.appendingPathComponent("Old.md"),
            to: fixture.works.appendingPathComponent("New.md"))
        _ = try await stores.control.moveIdentity(
            id: identity.id, vaultID: fixture.worksID,
            from: "Old.md", to: "New.md", fingerprint: original.fingerprint)
        let coordinator = NoteIdentityRecoveryCoordinator(control: stores.control, windowSessions: stores.sessions)

        for _ in 0..<2 {
            let failures = await coordinator.resumePendingRebindings(vaultID: fixture.worksID, repository: repository)
            #expect(failures.count == 1)
            #expect(failures.first?.rebinding.noteID == identity.id)
            #expect(try await stores.control.pendingIdentityRebindings(vaultID: fixture.worksID).count == 1)
            #expect(try Data(contentsOf: sessionURL) == corruptBytes)
            #expect(try await repository.interruptedSaveRecoveries().first?.relativePath == "New.md")
            #expect(try await repository.load(relativePath: "New.md").fingerprint == original.fingerprint)
        }
        // Repair only the test-owned malformed window record, then resume the
        // pending migration, including its already-completed recovery step.
        try supportedBytes.write(to: sessionURL)
        let failures = await coordinator.resumePendingRebindings(vaultID: fixture.worksID, repository: repository)
        #expect(failures.isEmpty)
        #expect(try await stores.control.pendingIdentityRebindings(vaultID: fixture.worksID).isEmpty)
        #expect(
            try await stores.sessions.load(id: session.id)
                == session.migratingPath(
                    vaultID: fixture.worksID, from: "Old.md", to: "New.md"))
        let recovery = try #require(try await repository.interruptedSaveRecoveries().first)
        #expect(recovery.id.transactionID == transaction.id)
        #expect(try await repository.interruptedSaveRecoveryContent(recovery).exactSource == "recovery candidate")
        #expect(try Data(contentsOf: fixture.works.appendingPathComponent("New.md")) == Data(original.rawContent.utf8))
        #expect(!FileManager.default.fileExists(atPath: fixture.works.appendingPathComponent("Old.md").path))
    }

    @Test("A unique external rename migrates every app-owned path reference")
    func uniqueExternalRenameMigration() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let stores = try await fixture.makeStores()
        let repository = try fixture.repository(vaultID: fixture.worksID, root: fixture.works)
        let original = try await repository.create(relativePath: "Old.md", content: "# Work\n")
        let saved = try await repository.save(
            relativePath: "Old.md",
            changeSet: .body("# Revised Work\n"),
            expectedRevision: original.fingerprint
        )
        let identity = try #require(
            try await stores.control.identity(
                forVaultID: fixture.worksID,
                relativePath: "Old.md",
                fingerprint: saved.document.fingerprint
            ))

        try await stores.sessions.save(
            WindowSessionSnapshot(
                id: stores.sessionID,
                selectedWorkspace: .output,
                openDocuments: [
                    VaultQualifiedNoteID(
                        vaultID: fixture.worksID,
                        relativePath: "Old.md"
                    )
                ],
                selectedDocument: VaultQualifiedNoteID(
                    vaultID: fixture.worksID,
                    relativePath: "Old.md"
                ),
                workspaceSessions: [
                    WindowWorkspaceSessionSnapshot(
                        workspace: .output,
                        vaultID: fixture.worksID,

                        documentPresentations: [
                            "Old.md": WindowDocumentPresentationSnapshot(scrollFraction: 0.42)
                        ]
                    )
                ]
            ))
        try FileManager.default.createDirectory(
            at: fixture.works.appendingPathComponent("Folder", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(
            at: fixture.works.appendingPathComponent("Old.md"),
            to: fixture.works.appendingPathComponent("Folder/New.md")
        )
        let moved = try await repository.load(relativePath: "Folder/New.md")
        let coordinator = NoteIdentityRecoveryCoordinator(
            control: stores.control,
            windowSessions: stores.sessions
        )
        let state = try await coordinator.reconcile(
            vaultID: fixture.worksID,
            documents: [("Folder/New.md", moved.fingerprint)],
            repository: repository
        )

        #expect(state.identities["Folder/New.md"]?.id == identity.id)
        #expect(state.pendingRebindings.isEmpty)
        #expect(state.failures.isEmpty)
        let session = try #require(try await stores.sessions.load(id: stores.sessionID))
        #expect(
            session.selectedDocument?.relativePath
                == "Folder/New.md"
        )
    }

    @Test("Same names and bytes in two vaults migrate only the confirmed vault")
    func migrationIsVaultQualified() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let stores = try await fixture.makeStores()
        let analysesRepository = try fixture.repository(vaultID: fixture.analysesID, root: fixture.analyses)
        let topicsRepository = try fixture.repository(vaultID: fixture.topicsID, root: fixture.topics)
        let analysisDocument = try await analysesRepository.create(relativePath: "Shared.md", content: "same")
        let topicDocument = try await topicsRepository.create(relativePath: "Shared.md", content: "same")
        let analysisIdentity = try #require(
            try await stores.control.identity(
                forVaultID: fixture.analysesID,
                relativePath: "Shared.md",
                fingerprint: analysisDocument.fingerprint
            ))
        let topicIdentity = try #require(
            try await stores.control.identity(
                forVaultID: fixture.topicsID,
                relativePath: "Shared.md",
                fingerprint: topicDocument.fingerprint
            ))
        try FileManager.default.moveItem(
            at: fixture.analyses.appendingPathComponent("Shared.md"),
            to: fixture.analyses.appendingPathComponent("Moved.md")
        )
        let moved = try await analysesRepository.load(relativePath: "Moved.md")
        let coordinator = NoteIdentityRecoveryCoordinator(
            control: stores.control,
            windowSessions: stores.sessions
        )
        let state = try await coordinator.reconcile(
            vaultID: fixture.analysesID,
            documents: [("Moved.md", moved.fingerprint)],
            repository: analysesRepository
        )

        #expect(state.identities["Moved.md"]?.id == analysisIdentity.id)
        #expect(
            try await stores.control.identityRecord(
                vaultID: fixture.topicsID,
                relativePath: "Shared.md"
            )?.id == topicIdentity.id)
    }

    @Test("Completed saves do not leave history that blocks an external move")
    func completedSavesDoNotBlockExternalMove() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let stores = try await fixture.makeStores()
        let repository = try fixture.repository(vaultID: fixture.worksID, root: fixture.works)
        let old = try await repository.create(relativePath: "Old.md", content: "old")
        let oldSaved = try await repository.save(
            relativePath: "Old.md",
            changeSet: .body("same"),
            expectedRevision: old.fingerprint
        )
        let identity = try #require(
            try await stores.control.identity(
                forVaultID: fixture.worksID,
                relativePath: "Old.md",
                fingerprint: oldSaved.document.fingerprint
            ))
        let destination = try await repository.create(relativePath: "New.md", content: "destination")
        _ = try await repository.save(
            relativePath: "New.md",
            changeSet: .body("destination history"),
            expectedRevision: destination.fingerprint
        )
        // Simulate an external replacement at a path that previously completed
        // an unrelated save. Completed transactions leave no recovery history,
        // so identity migration has no stale per-path owner to reconcile.
        try FileManager.default.removeItem(
            at: fixture.works.appendingPathComponent("New.md")
        )
        try FileManager.default.moveItem(
            at: fixture.works.appendingPathComponent("Old.md"),
            to: fixture.works.appendingPathComponent("New.md")
        )
        let moved = try await repository.load(relativePath: "New.md")
        let coordinator = NoteIdentityRecoveryCoordinator(
            control: stores.control,
            windowSessions: stores.sessions
        )

        let state = try await coordinator.reconcile(
            vaultID: fixture.worksID,
            documents: [("New.md", moved.fingerprint)],
            repository: repository
        )

        #expect(state.identities["New.md"]?.id == identity.id)
        #expect(state.pendingRebindings.isEmpty)
        #expect(state.failures.isEmpty)
        #expect(try await stores.control.pendingIdentityRebindings(vaultID: fixture.worksID).isEmpty)
        #expect(try await repository.interruptedSaveRecoveries().isEmpty)
    }

    private struct Stores {
        let control: TriptychControlStore
        let sessions: WindowSessionSnapshotStore
        let sessionID: UUID
    }

    private struct Fixture {
        let root: URL
        let analyses: URL
        let topics: URL
        let works: URL
        let support: URL
        let analysesID = UUID()
        let topicsID = UUID()
        let worksID = UUID()

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("Scholium-Identity-Recovery-\(UUID().uuidString)", isDirectory: true)
            analyses = root.appendingPathComponent("Analyses", isDirectory: true)
            topics = root.appendingPathComponent("Topics", isDirectory: true)
            works = root.appendingPathComponent("Works", isDirectory: true)
            support = root.appendingPathComponent("Application Support", isDirectory: true)
            for directory in [analyses, topics, works, support] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }

        func makeStores() async throws -> Stores {
            let control = TriptychControlStore(worksVaultURL: works)
            _ = try await control.bootstrap(vaultIDs: [
                .paperAnalysis: analysesID,
                .topicKnowledge: topicsID,
                .output: worksID,
            ])
            let sessionID = UUID()
            return Stores(
                control: control,
                sessions: WindowSessionSnapshotStore(applicationSupportURL: support),
                sessionID: sessionID
            )
        }

        func repository(vaultID: UUID, root: URL) throws -> VaultRepository {
            try VaultRepository(
                vaultURL: root,
                identity: VaultIdentity(id: vaultID, canonicalPath: root.path, bookmarkData: nil),
                applicationSupportURL: support
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
