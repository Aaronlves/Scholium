import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Coordinated permanent deletion")
struct PermanentDeletionTests {
    @Test("Confirmed deletion purges source, app-owned records, identity, history, and checkpoints")
    func purgesEveryCurrentRecoverySurface() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scholium-PermanentDeletion-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let analyses = root.appendingPathComponent("Analyses", isDirectory: true)
        let topics = root.appendingPathComponent("Topics", isDirectory: true)
        let works = root.appendingPathComponent("Works", isDirectory: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        for directory in [analyses, topics, works, support] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let vaultID = UUID()
        let triptychID = UUID()
        let path = "Trash/Delete Me.md"
        let sourceURL = analyses.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: sourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let source = "# Delete Me\n\nPrivate research.\n"
        try Data(source.utf8).write(to: sourceURL, options: .atomic)
        let fingerprint = DocumentFingerprint(content: source)

        let control = TriptychControlStore(worksVaultURL: works)
        _ = try await control.bootstrap(
            vaultIDs: [
                .paperAnalysis: vaultID,
                .topicKnowledge: UUID(),
                .output: UUID(),
            ],
            preferredTriptychID: triptychID
        )
        let identity = try #require(try await control.identity(
            forVaultID: vaultID,
            relativePath: path,
            fingerprint: fingerprint
        ))
        let reviewStore = HumanReviewStore(
            storageURL: support.appendingPathComponent("Reviews", isDirectory: true)
        )
        _ = try await reviewStore.addComment(
            noteID: identity.id,
            vaultID: vaultID,
            relativePath: path,
            comment: ResearcherComment(
                text: "Delete this private comment too.",
                anchor: testCommentAnchor(fingerprint: fingerprint)
            )
        )
        let dialogueStore = DialogueStore(
            storageURL: support.appendingPathComponent("Dialogue", isDirectory: true)
        )
        let reference = DialogueNoteReference(
            noteID: identity.id,
            vaultID: vaultID,
            vaultName: "Analyses",
            title: "Delete Me",
            relativePath: path,
            fingerprint: fingerprint
        )
        let dialogue = DialogueEntry(
            triptychID: triptychID,
            instruction: "Inspect private research.",
            selectedNotes: [reference],
            includedComments: [],
            preparedInstructions: "Private transport context.",
            checkpointID: UUID()
        )
        _ = try await dialogueStore.save(dialogue)
        let critiqueRegistry = CritiqueRegistry(controlURL: await control.controlURL)
        let checkpointStore = TriptychCheckpointStore(
            triptychID: triptychID,
            applicationSupportURL: support
        )
        let roots = TriptychRoots(
            analyses: analyses,
            topics: topics,
            works: works,
            control: await control.controlURL
        )
        let checkpoint = try await checkpointStore.create(
            name: "Contains Deleted Note",
            kind: .manual,
            roots: roots
        )
        let repository = try VaultRepository(
            vaultURL: analyses,
            identity: VaultIdentity(id: vaultID, canonicalPath: analyses.path, bookmarkData: nil),
            applicationSupportURL: support,
            vaultRole: .sourceCorpus
        )
        _ = try await repository.save(
            relativePath: path,
            changeSet: .body("# Delete Me\n\nPrivate revised research.\n"),
            expectedRevision: fingerprint
        )
        let current = try await repository.load(relativePath: path)
        let recoveryStore = try TriptychMutationRecoveryStore(
            storageURL: support.appendingPathComponent("Transaction Recovery", isDirectory: true)
        )

        let coordinator = NotePermanentDeletionCoordinator(
            triptychID: triptychID,
            repository: repository,
            humanReviewStore: reviewStore,
            dialogueStore: dialogueStore,
            critiqueRegistry: critiqueRegistry,
            checkpointStore: checkpointStore,
            controlStore: control,
            recoveryStore: recoveryStore
        )
        let commit = try await coordinator.delete(
            noteID: identity.id,
            vaultID: vaultID,
            relativePath: path,
            expectedRevision: current.fingerprint,
            checkpointArea: .analyses
        )

        #expect(commit.removedHumanReview)
        #expect(commit.removedDialogueIDs == [dialogue.id])
        #expect(commit.invalidatedCheckpointIDs == [checkpoint.id])
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(await reviewStore.record(noteID: identity.id) == nil)
        #expect(await dialogueStore.entries(noteID: identity.id).isEmpty)
        #expect(await repository.recoveryEntries(relativePath: path).isEmpty)
        #expect(await checkpointStore.checkpoints().isEmpty)
        #expect(try await control.identity(
            forVaultID: vaultID,
            relativePath: path,
            fingerprint: current.fingerprint,
            createIfMissing: false
        ) == nil)
    }

    @Test("Deleting a Work removes its separate current Critique in one committed transaction")
    func deletesAssociatedCritiqueDocument() async throws {
        let fixture = try await WorkFixture()
        defer { fixture.remove() }

        let commit = try await fixture.coordinator().delete(
            noteID: fixture.workIdentity.id,
            vaultID: fixture.vaultID,
            relativePath: fixture.workPath,
            expectedRevision: fixture.workFingerprint,
            checkpointArea: .works
        )

        #expect(commit.removedCritiqueDocumentPath == fixture.critiquePath)
        #expect(commit.removedCritiqueAssociationIDs == [fixture.association.id])
        #expect(commit.removedDialogueIDs == [fixture.dialogue.id, fixture.critiqueDialogue.id]
            .sorted { $0.uuidString < $1.uuidString })
        #expect(!FileManager.default.fileExists(atPath: fixture.workURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.critiqueURL.path))
        #expect(await fixture.repository.recoveryEntries(relativePath: fixture.workPath).isEmpty)
        #expect(await fixture.repository.recoveryEntries(relativePath: fixture.critiquePath).isEmpty)
        #expect(await fixture.critiqueRegistry.association(workNoteID: fixture.workIdentity.id) == nil)
        #expect(await fixture.humanReviewStore.record(noteID: fixture.critiqueIdentity.id) == nil)
        #expect(await fixture.dialogueStore.entries(noteID: fixture.critiqueIdentity.id).isEmpty)
        #expect(try await fixture.control.identityRecord(
            vaultID: fixture.vaultID,
            relativePath: fixture.critiquePath
        ) == nil)
        #expect(await fixture.checkpointStore.checkpoints().isEmpty)
        let pending = try await fixture.recoveryStore.pending()
        #expect(pending.isEmpty)
    }

    @Test(
        "A cleanup failure restores both Markdown files and every purged record",
        arguments: [
            PermanentDeletionFaultPoint.afterCritiqueDeletion,
            .afterSourceDeletion,
            .afterHumanReviewPurge,
            .afterDialoguePurge,
            .afterCritiqueAssociationPurge,
            .afterCheckpointPurge,
            .afterIdentityPurge,
        ]
    )
    func cleanupFailureRollsBackExactly(_ faultPoint: PermanentDeletionFaultPoint) async throws {
        let fixture = try await WorkFixture()
        defer { fixture.remove() }
        let coordinator = fixture.coordinator(
            faultPlan: PermanentDeletionFaultPlan(
                failures: [faultPoint],
                interruptions: []
            )
        )

        await #expect(throws: TriptychTransactionError.self) {
            _ = try await coordinator.delete(
                noteID: fixture.workIdentity.id,
                vaultID: fixture.vaultID,
                relativePath: fixture.workPath,
                expectedRevision: fixture.workFingerprint,
                checkpointArea: .works
            )
        }

        #expect(try String(contentsOf: fixture.workURL, encoding: .utf8) == fixture.workSource)
        #expect(try String(contentsOf: fixture.critiqueURL, encoding: .utf8) == fixture.critiqueSource)
        #expect(await fixture.humanReviewStore.record(noteID: fixture.workIdentity.id) != nil)
        #expect(await fixture.humanReviewStore.record(noteID: fixture.critiqueIdentity.id) != nil)
        #expect(await fixture.dialogueStore.entries(noteID: fixture.workIdentity.id).map(\.id) == [fixture.dialogue.id])
        #expect(await fixture.dialogueStore.entries(noteID: fixture.critiqueIdentity.id).map(\.id) == [fixture.critiqueDialogue.id])
        #expect(await fixture.critiqueRegistry.association(workNoteID: fixture.workIdentity.id)?.id == fixture.association.id)
        #expect(await fixture.checkpointStore.checkpoints().map(\.id) == [fixture.checkpoint.id])
        let pending = try await fixture.recoveryStore.pending()
        #expect(pending.isEmpty)
    }

    @Test("A process interruption leaves a durable journal and the next runtime restores the transaction")
    func interruptionRecoversOnNextRuntime() async throws {
        let fixture = try await WorkFixture()
        defer { fixture.remove() }
        let interrupted = fixture.coordinator(
            faultPlan: PermanentDeletionFaultPlan(
                failures: [],
                interruptions: [.afterSourceDeletion]
            )
        )

        await #expect(throws: TriptychTransactionError.self) {
            _ = try await interrupted.delete(
                noteID: fixture.workIdentity.id,
                vaultID: fixture.vaultID,
                relativePath: fixture.workPath,
                expectedRevision: fixture.workFingerprint,
                checkpointArea: .works
            )
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.workURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.critiqueURL.path))
        #expect(try await fixture.recoveryStore.pending().count == 1)

        try await fixture.reopenedCoordinator().recoverInterruptedTransactions()

        #expect(try String(contentsOf: fixture.workURL, encoding: .utf8) == fixture.workSource)
        #expect(try String(contentsOf: fixture.critiqueURL, encoding: .utf8) == fixture.critiqueSource)
        #expect(await fixture.humanReviewStore.record(noteID: fixture.workIdentity.id) != nil)
        #expect(await fixture.humanReviewStore.record(noteID: fixture.critiqueIdentity.id) != nil)
        #expect(await fixture.dialogueStore.entries(noteID: fixture.workIdentity.id).map(\.id) == [fixture.dialogue.id])
        #expect(await fixture.dialogueStore.entries(noteID: fixture.critiqueIdentity.id).map(\.id) == [fixture.critiqueDialogue.id])
        #expect(await fixture.critiqueRegistry.association(workNoteID: fixture.workIdentity.id)?.id == fixture.association.id)
        #expect(await fixture.checkpointStore.checkpoints().map(\.id) == [fixture.checkpoint.id])
        #expect(try await fixture.recoveryStore.pending().isEmpty)
    }

    @Test("An interruption after the commit decision resumes deletion rather than restoring private copies")
    func commitInterruptionResumesPrivacyCleanup() async throws {
        let fixture = try await WorkFixture()
        defer { fixture.remove() }
        let interrupted = fixture.coordinator(
            faultPlan: PermanentDeletionFaultPlan(
                failures: [],
                interruptions: [.afterCommitDecision]
            )
        )

        await #expect(throws: TriptychTransactionError.self) {
            _ = try await interrupted.delete(
                noteID: fixture.workIdentity.id,
                vaultID: fixture.vaultID,
                relativePath: fixture.workPath,
                expectedRevision: fixture.workFingerprint,
                checkpointArea: .works
            )
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.workURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.critiqueURL.path))
        #expect(try await fixture.recoveryStore.pending().count == 1)

        try await fixture.reopenedCoordinator().recoverInterruptedTransactions()

        #expect(!FileManager.default.fileExists(atPath: fixture.workURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.critiqueURL.path))
        let reopenedRepository = try fixture.reopenedRepository()
        #expect(await reopenedRepository.recoveryEntries(relativePath: fixture.workPath).isEmpty)
        #expect(await reopenedRepository.recoveryEntries(relativePath: fixture.critiquePath).isEmpty)
        #expect(await fixture.checkpointStore.checkpoints().isEmpty)
        #expect(try await fixture.recoveryStore.pending().isEmpty)
    }

    private struct WorkFixture {
        let root: URL
        let analyses: URL
        let topics: URL
        let works: URL
        let support: URL
        let vaultID: UUID
        let triptychID: UUID
        let workPath = "Trash/Work.md"
        let critiquePath = "Critiques/Work Critique.md"
        let workSource = "# Work\n\nResearcher-governed prose.\n"
        let critiqueSource = "# Critique\n\nAgent-authored critique.\n"
        let workURL: URL
        let critiqueURL: URL
        let workFingerprint: DocumentFingerprint
        let workIdentity: NoteIdentityRecord
        let critiqueIdentity: NoteIdentityRecord
        let humanReviewStore: HumanReviewStore
        let dialogueStore: DialogueStore
        let dialogue: DialogueEntry
        let critiqueDialogue: DialogueEntry
        let critiqueRegistry: CritiqueRegistry
        let association: CritiqueAssociation
        let checkpointStore: TriptychCheckpointStore
        let checkpoint: TriptychCheckpoint
        let control: TriptychControlStore
        let repository: VaultRepository
        let recoveryStore: TriptychMutationRecoveryStore

        init() async throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("Scholium-WorkDeletion-\(UUID().uuidString)", isDirectory: true)
            analyses = root.appendingPathComponent("Analyses", isDirectory: true)
            topics = root.appendingPathComponent("Topics", isDirectory: true)
            works = root.appendingPathComponent("Works", isDirectory: true)
            support = root.appendingPathComponent("Support", isDirectory: true)
            for directory in [analyses, topics, works, support] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            vaultID = UUID()
            triptychID = UUID()
            workURL = works.appendingPathComponent(workPath)
            critiqueURL = works.appendingPathComponent(critiquePath)
            try FileManager.default.createDirectory(
                at: workURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: critiqueURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(workSource.utf8).write(to: workURL, options: .atomic)
            try Data(critiqueSource.utf8).write(to: critiqueURL, options: .atomic)
            workFingerprint = DocumentFingerprint(content: workSource)

            control = TriptychControlStore(worksVaultURL: works)
            _ = try await control.bootstrap(
                vaultIDs: [
                    .paperAnalysis: UUID(),
                    .topicKnowledge: UUID(),
                    .output: vaultID,
                ],
                preferredTriptychID: triptychID
            )
            workIdentity = try #require(try await control.identity(
                forVaultID: vaultID,
                relativePath: workPath,
                fingerprint: workFingerprint
            ))
            critiqueIdentity = try #require(try await control.identity(
                forVaultID: vaultID,
                relativePath: critiquePath,
                fingerprint: DocumentFingerprint(content: critiqueSource)
            ))
            humanReviewStore = HumanReviewStore(
                storageURL: support.appendingPathComponent("Reviews", isDirectory: true)
            )
            _ = try await humanReviewStore.addComment(
                noteID: workIdentity.id,
                vaultID: vaultID,
                relativePath: workPath,
                comment: ResearcherComment(
                    text: "Private deletion rollback fixture.",
                    anchor: testCommentAnchor(fingerprint: workFingerprint)
                )
            )
            _ = try await humanReviewStore.addComment(
                noteID: critiqueIdentity.id,
                vaultID: vaultID,
                relativePath: critiquePath,
                comment: ResearcherComment(
                    text: "Critique-local comment.",
                    anchor: testCommentAnchor(
                        fingerprint: DocumentFingerprint(content: critiqueSource)
                    )
                )
            )
            dialogueStore = DialogueStore(
                storageURL: support.appendingPathComponent("Dialogue", isDirectory: true)
            )
            dialogue = DialogueEntry(
                triptychID: triptychID,
                instruction: "Inspect the Work.",
                selectedNotes: [DialogueNoteReference(
                    noteID: workIdentity.id,
                    vaultID: vaultID,
                    vaultName: "Works",
                    title: "Work",
                    relativePath: workPath,
                    fingerprint: workFingerprint
                )],
                includedComments: [],
                preparedInstructions: "",
                checkpointID: UUID()
            )
            _ = try await dialogueStore.save(dialogue)
            critiqueDialogue = DialogueEntry(
                triptychID: triptychID,
                instruction: "Inspect the Critique.",
                selectedNotes: [DialogueNoteReference(
                    noteID: critiqueIdentity.id,
                    vaultID: vaultID,
                    vaultName: "Works",
                    title: "Work Critique",
                    relativePath: critiquePath,
                    fingerprint: DocumentFingerprint(content: critiqueSource)
                )],
                includedComments: [],
                preparedInstructions: "",
                checkpointID: UUID()
            )
            _ = try await dialogueStore.save(critiqueDialogue)
            critiqueRegistry = CritiqueRegistry(controlURL: await control.controlURL)
            association = try await critiqueRegistry.save(CritiqueAssociation(
                workNoteID: workIdentity.id,
                workRelativePath: workPath,
                targetFingerprint: workFingerprint,
                critiqueRelativePath: critiquePath
            ))
            checkpointStore = TriptychCheckpointStore(
                triptychID: triptychID,
                applicationSupportURL: support
            )
            checkpoint = try await checkpointStore.create(
                name: "Work and Critique",
                kind: .manual,
                roots: TriptychRoots(
                    analyses: analyses,
                    topics: topics,
                    works: works,
                    control: await control.controlURL
                )
            )
            repository = try VaultRepository(
                vaultURL: works,
                identity: VaultIdentity(id: vaultID, canonicalPath: works.path, bookmarkData: nil),
                applicationSupportURL: support,
                vaultRole: .draftProject
            )
            recoveryStore = try TriptychMutationRecoveryStore(
                storageURL: support.appendingPathComponent("Transaction Recovery", isDirectory: true)
            )
        }

        func coordinator(
            faultPlan: PermanentDeletionFaultPlan = .none
        ) -> NotePermanentDeletionCoordinator {
            NotePermanentDeletionCoordinator(
                triptychID: triptychID,
                repository: repository,
                humanReviewStore: humanReviewStore,
                dialogueStore: dialogueStore,
                critiqueRegistry: critiqueRegistry,
                checkpointStore: checkpointStore,
                controlStore: control,
                recoveryStore: recoveryStore,
                faultPlan: faultPlan
            )
        }

        func reopenedCoordinator() async throws -> NotePermanentDeletionCoordinator {
            let reopenedControl = TriptychControlStore(worksVaultURL: works)
            return NotePermanentDeletionCoordinator(
                triptychID: triptychID,
                repository: try reopenedRepository(),
                humanReviewStore: HumanReviewStore(
                    storageURL: support.appendingPathComponent("Reviews", isDirectory: true)
                ),
                dialogueStore: DialogueStore(
                    storageURL: support.appendingPathComponent("Dialogue", isDirectory: true)
                ),
                critiqueRegistry: CritiqueRegistry(controlURL: await reopenedControl.controlURL),
                checkpointStore: TriptychCheckpointStore(
                    triptychID: triptychID,
                    applicationSupportURL: support
                ),
                controlStore: reopenedControl,
                recoveryStore: try TriptychMutationRecoveryStore(
                    storageURL: support.appendingPathComponent("Transaction Recovery", isDirectory: true)
                )
            )
        }

        func reopenedRepository() throws -> VaultRepository {
            try VaultRepository(
                vaultURL: works,
                identity: VaultIdentity(id: vaultID, canonicalPath: works.path, bookmarkData: nil),
                applicationSupportURL: support,
                vaultRole: .draftProject
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}

private func testCommentAnchor(
    fingerprint: DocumentFingerprint,
    quotation: String = "source passage"
) -> ResearcherCommentAnchor {
    ResearcherCommentAnchor(
        fingerprint: fingerprint,
        utf8Range: 0..<quotation.utf8.count,
        utf16Range: 0..<quotation.utf16.count,
        line: 1,
        endLine: 1,
        quotation: quotation
    )
}
