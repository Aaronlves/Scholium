import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Stable note identity recovery")
struct NoteIdentityRecoveryTests {
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
        let identity = try #require(try await stores.control.identity(
            forVaultID: fixture.worksID,
            relativePath: "Old.md",
            fingerprint: saved.document.fingerprint
        ))

        _ = try await stores.reviews.addComment(
            noteID: identity.id,
            vaultID: fixture.worksID,
            relativePath: "Old.md",
            comment: ResearcherComment(text: "Keep this distinction.")
        )
        let reference = DialogueNoteReference(
            noteID: identity.id,
            vaultID: fixture.worksID,
            vaultName: "Works",
            title: "Work",
            relativePath: "Old.md",
            fingerprint: saved.document.fingerprint
        )
        let dialogueEntry = DialogueEntry(
            triptychID: UUID(),
            instruction: "Revise.",
            selectedNotes: [reference],
            includedComments: [],
            generatedPrompt: "Historical target: Old.md",
            checkpointID: UUID()
        )
        _ = try await stores.dialogue.save(dialogueEntry)
        _ = try await stores.critiques.recordRequest(
            workNoteID: identity.id,
            workRelativePath: "Old.md",
            targetFingerprint: saved.document.fingerprint,
            critiqueRelativePath: "Critiques/Work.md",
            checkpointID: nil,
            scope: .overall
        )
        try await stores.sessions.save(WindowSessionSnapshot(
            id: stores.sessionID,
            vaultID: fixture.worksID,
            openTabs: ["Old.md"],
            activeTab: "Old.md",
            navigationHistory: ["Old.md"],
            navigationIndex: 0,
            documentModes: ["Old.md": "read"],
            scrollPositions: ["Old.md": 42]
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
            humanReviews: stores.reviews,
            dialogue: stores.dialogue,
            critiques: stores.critiques,
            windowSessions: stores.sessions
        )
        let state = try await coordinator.reconcile(
            vaultID: fixture.worksID,
            documents: [("Folder/New.md", moved.fingerprint)],
            repository: repository,
            migrateCritiquePaths: true
        )

        #expect(state.identities["Folder/New.md"]?.id == identity.id)
        #expect(state.pendingRebindings.isEmpty)
        #expect(state.failures.isEmpty)
        #expect(await stores.reviews.record(noteID: identity.id)?.relativePath == "Folder/New.md")
        let migratedDialogue = try await stores.dialogue.entry(id: dialogueEntry.id)
        #expect(migratedDialogue.selectedNotes[0].relativePath == "Folder/New.md")
        #expect(migratedDialogue.generatedPrompt == "Historical target: Old.md")
        #expect(await stores.critiques.association(workNoteID: identity.id)?.workRelativePath == "Folder/New.md")
        let session = try #require(try await stores.sessions.load(id: stores.sessionID))
        #expect(session.activeTab == "Folder/New.md")
        #expect((await repository.versions(relativePath: "Old.md")).isEmpty)
        #expect((await repository.versions(relativePath: "Folder/New.md")).count == 1)
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
        let analysisIdentity = try #require(try await stores.control.identity(
            forVaultID: fixture.analysesID,
            relativePath: "Shared.md",
            fingerprint: analysisDocument.fingerprint
        ))
        let topicIdentity = try #require(try await stores.control.identity(
            forVaultID: fixture.topicsID,
            relativePath: "Shared.md",
            fingerprint: topicDocument.fingerprint
        ))
        _ = try await stores.reviews.addComment(
            noteID: analysisIdentity.id,
            vaultID: fixture.analysesID,
            relativePath: "Shared.md",
            comment: ResearcherComment(text: "Analysis comment")
        )
        _ = try await stores.reviews.addComment(
            noteID: topicIdentity.id,
            vaultID: fixture.topicsID,
            relativePath: "Shared.md",
            comment: ResearcherComment(text: "Topic comment")
        )
        let references = [
            DialogueNoteReference(
                noteID: analysisIdentity.id,
                vaultID: fixture.analysesID,
                vaultName: "Analyses",
                title: "Shared",
                relativePath: "Shared.md",
                fingerprint: analysisDocument.fingerprint
            ),
            DialogueNoteReference(
                noteID: topicIdentity.id,
                vaultID: fixture.topicsID,
                vaultName: "Topics",
                title: "Shared",
                relativePath: "Shared.md",
                fingerprint: topicDocument.fingerprint
            ),
        ]
        let dialogueEntry = DialogueEntry(
            triptychID: UUID(),
            instruction: "Compare.",
            selectedNotes: references,
            includedComments: [],
            generatedPrompt: "Two Shared.md files",
            checkpointID: UUID()
        )
        _ = try await stores.dialogue.save(dialogueEntry)

        try FileManager.default.moveItem(
            at: fixture.analyses.appendingPathComponent("Shared.md"),
            to: fixture.analyses.appendingPathComponent("Moved.md")
        )
        let moved = try await analysesRepository.load(relativePath: "Moved.md")
        let coordinator = NoteIdentityRecoveryCoordinator(
            control: stores.control,
            humanReviews: stores.reviews,
            dialogue: stores.dialogue,
            critiques: stores.critiques,
            windowSessions: stores.sessions
        )
        let state = try await coordinator.reconcile(
            vaultID: fixture.analysesID,
            documents: [("Moved.md", moved.fingerprint)],
            repository: analysesRepository,
            migrateCritiquePaths: false
        )

        #expect(state.identities["Moved.md"]?.id == analysisIdentity.id)
        #expect(await stores.reviews.record(noteID: analysisIdentity.id)?.relativePath == "Moved.md")
        #expect(await stores.reviews.record(noteID: topicIdentity.id)?.relativePath == "Shared.md")
        let migratedDialogue = try await stores.dialogue.entry(id: dialogueEntry.id)
        #expect(migratedDialogue.selectedNotes.first { $0.vaultID == fixture.analysesID }?.relativePath == "Moved.md")
        #expect(migratedDialogue.selectedNotes.first { $0.vaultID == fixture.topicsID }?.relativePath == "Shared.md")
    }

    @Test("A failed app-state migration remains persisted and blocks identity")
    func incompleteMigrationStaysBlocked() async throws {
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
        let identity = try #require(try await stores.control.identity(
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
        // Simulate an external deletion. Repository permanent deletion now
        // intentionally purges Note History, while this fixture needs the
        // destination's unrelated history to remain and block path migration.
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
            humanReviews: stores.reviews,
            dialogue: stores.dialogue,
            critiques: stores.critiques,
            windowSessions: stores.sessions
        )

        let state = try await coordinator.reconcile(
            vaultID: fixture.worksID,
            documents: [("New.md", moved.fingerprint)],
            repository: repository,
            migrateCritiquePaths: true
        )

        #expect(state.identities["New.md"] == nil)
        #expect(state.pendingRebindings.first?.noteID == identity.id)
        #expect(state.failures.count == 1)
        #expect(try await stores.control.pendingIdentityRebindings(vaultID: fixture.worksID).count == 1)
    }

    private struct Stores {
        let control: TriptychControlStore
        let reviews: HumanReviewStore
        let dialogue: DialogueStore
        let critiques: CritiqueRegistry
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
            let triptychState = support.appendingPathComponent("Triptych", isDirectory: true)
            let sessionID = UUID()
            return Stores(
                control: control,
                reviews: HumanReviewStore(storageURL: triptychState.appendingPathComponent("reviews")),
                dialogue: DialogueStore(storageURL: triptychState.appendingPathComponent("dialogue")),
                critiques: CritiqueRegistry(controlURL: triptychState),
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
