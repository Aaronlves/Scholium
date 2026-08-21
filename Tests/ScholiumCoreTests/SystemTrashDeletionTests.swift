import Foundation
import ScholiumContracts
@testable import ScholiumCore
import Testing

@Suite("Coordinated system Trash deletion")
struct SystemTrashDeletionTests {
    @Test("One affected participant deletes the whole finished Record")
    func deletesWholeMultiNoteRecordAndDiscardsDiscussion() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        var trashURLs: [URL] = []
        defer { trashURLs.forEach { try? FileManager.default.removeItem(at: $0) } }

        let preview = try await fixture.coordinator().prepareNote(
            noteID: fixture.firstIdentity.id,
            vaultID: fixture.vaultID,
            relativePath: fixture.firstPath,
            expectedRevision: fixture.firstFingerprint
        )

        #expect(preview.records.map(\.id) == [fixture.sharedRecord.id])
        #expect(preview.records.first?.unaffectedParticipants.map(\.noteID)
            == [fixture.secondIdentity.id])
        #expect(preview.activeDiscussionIDs == [fixture.activeDiscussion.id])

        let commit = try await fixture.coordinator().moveToSystemTrash(preview)
        trashURLs = commit.resultingTrashPaths.map { URL(fileURLWithPath: $0) }

        #expect(!FileManager.default.fileExists(atPath: fixture.firstURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.secondURL.path))
        #expect(await fixture.portableRecordStore.isRecordPermanentlyDeleted(
            id: fixture.sharedRecord.id
        ))
        #expect(try await fixture.portableRecordStore.record(
            id: fixture.unrelatedRecord.id
        ) == fixture.unrelatedRecord)
        #expect(try await fixture.portableRecordStore.activeDiscussions().discussions.isEmpty)
        #expect(try await fixture.portableRecordStore.latestSettlement(
            noteID: fixture.firstIdentity.id
        ) != nil)
        #expect(try await fixture.control.identityRecord(
            vaultID: fixture.vaultID,
            relativePath: fixture.firstPath
        )?.id == fixture.firstIdentity.id)
        #expect(try await fixture.recoveryStore.pending().isEmpty)
    }

    @Test("A source receipt survives cleanup failure and resumes Record deletion")
    func sourceMovedThenRecordCleanupResumesForward() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        var trashURLs: [URL] = []
        defer { trashURLs.forEach { try? FileManager.default.removeItem(at: $0) } }
        let coordinator = fixture.coordinator(faultPlan: SystemTrashDeletionFaultPlan(
            failures: [.afterSourceReceipts],
            interruptions: []
        ))
        let preview = try await coordinator.prepareNote(
            noteID: fixture.firstIdentity.id,
            vaultID: fixture.vaultID,
            relativePath: fixture.firstPath,
            expectedRevision: fixture.firstFingerprint
        )

        await #expect(throws: TriptychTransactionError.self) {
            _ = try await coordinator.moveToSystemTrash(preview)
        }
        let pending = try #require(try await fixture.recoveryStore.pending().first)
        trashURLs = pending.systemTrashDeletionPlan?.sourceReceipts.compactMap {
            $0.resultingTrashPath.map { URL(fileURLWithPath: $0) }
        } ?? []
        #expect(!FileManager.default.fileExists(atPath: fixture.firstURL.path))
        #expect(try await fixture.portableRecordStore.record(
            id: fixture.sharedRecord.id
        ) == fixture.sharedRecord)

        try await fixture.coordinator().recoverInterruptedTransactions()

        #expect(await fixture.portableRecordStore.isRecordPermanentlyDeleted(
            id: fixture.sharedRecord.id
        ))
        #expect(try await fixture.recoveryStore.pending().isEmpty)
    }

    @Test("A crash after plan persistence leaves source intact and recovery owns the gate")
    func durablePlanPrecedesDeletionGate() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        var trashURLs: [URL] = []
        defer { trashURLs.forEach { try? FileManager.default.removeItem(at: $0) } }
        let coordinator = fixture.coordinator(faultPlan: SystemTrashDeletionFaultPlan(
            failures: [],
            interruptions: [.afterPlanPersistence]
        ))
        let preview = try await coordinator.prepareNote(
            noteID: fixture.firstIdentity.id,
            vaultID: fixture.vaultID,
            relativePath: fixture.firstPath,
            expectedRevision: fixture.firstFingerprint
        )

        await #expect(throws: Error.self) {
            _ = try await coordinator.moveToSystemTrash(preview)
        }

        #expect(FileManager.default.fileExists(atPath: fixture.firstURL.path))
        #expect(try await fixture.recoveryStore.pending().count == 1)
        #expect(try await fixture.portableRecordStore.record(
            id: fixture.sharedRecord.id
        ) == fixture.sharedRecord)

        let commits = try await fixture.coordinator().recoverInterruptedTransactions()
        trashURLs = commits.flatMap(\.resultingTrashPaths).map(URL.init(fileURLWithPath:))
        #expect(!FileManager.default.fileExists(atPath: fixture.firstURL.path))
        #expect(await fixture.portableRecordStore.isRecordPermanentlyDeleted(
            id: fixture.sharedRecord.id
        ))
        #expect(try await fixture.recoveryStore.pending().isEmpty)
    }

    @Test("Unknown native Trash outcome never implies Record deletion")
    func unknownOutcomeCanRetainRecordsExplicitly() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        var trashURLs: [URL] = []
        defer { trashURLs.forEach { try? FileManager.default.removeItem(at: $0) } }
        let coordinator = fixture.coordinator(faultPlan: SystemTrashDeletionFaultPlan(
            failures: [],
            interruptions: [.afterSystemTrashMoveBeforeReceipt]
        ))
        let preview = try await coordinator.prepareNote(
            noteID: fixture.firstIdentity.id,
            vaultID: fixture.vaultID,
            relativePath: fixture.firstPath,
            expectedRevision: fixture.firstFingerprint
        )

        await #expect(throws: TriptychTransactionError.self) {
            _ = try await coordinator.moveToSystemTrash(preview)
        }
        let pending = try #require(try await fixture.recoveryStore.pending().first)
        let plan = try #require(pending.systemTrashDeletionPlan)
        trashURLs = plan.sourceReceipts.compactMap {
            $0.resultingTrashPath.map { URL(fileURLWithPath: $0) }
        }
        #expect(plan.sourceReceipts.map(\.progress) == [.outcomeUnknown])
        #expect(try await fixture.portableRecordStore.record(
            id: fixture.sharedRecord.id
        ) == fixture.sharedRecord)

        try await fixture.coordinator().retainRecordsForUnknownOutcome(
            recoveryRecordID: pending.id
        )

        #expect(try await fixture.portableRecordStore.record(
            id: fixture.sharedRecord.id
        ) == fixture.sharedRecord)
        #expect(try await fixture.recoveryStore.pending().isEmpty)
    }

    @Test("A recreated original path records native uncertainty without touching Records")
    func recreatedOriginalPathRetainsRecords() async throws {
        let fixture = try await Fixture(recreateFirstSourceAfterTrash: true)
        defer { fixture.remove() }
        var trashURLs: [URL] = []
        defer { trashURLs.forEach { try? FileManager.default.removeItem(at: $0) } }
        let coordinator = fixture.coordinator()
        let preview = try await coordinator.prepareNote(
            noteID: fixture.firstIdentity.id,
            vaultID: fixture.vaultID,
            relativePath: fixture.firstPath,
            expectedRevision: fixture.firstFingerprint
        )

        await #expect(throws: TriptychTransactionError.self) {
            _ = try await coordinator.moveToSystemTrash(preview)
        }
        let pending = try #require(try await fixture.recoveryStore.pending().first)
        let plan = try #require(pending.systemTrashDeletionPlan)
        let receipt = try #require(plan.sourceReceipts.first)
        #expect(receipt.progress == .outcomeUnknown)
        if let path = receipt.resultingTrashPath {
            trashURLs = [URL(fileURLWithPath: path)]
        }
        #expect(
            try String(contentsOf: fixture.firstURL, encoding: .utf8)
                == "# Recreated source\n"
        )
        #expect(try await fixture.portableRecordStore.record(
            id: fixture.sharedRecord.id
        ) == fixture.sharedRecord)
        #expect(try await fixture.portableRecordStore.activeDiscussion(
            id: fixture.activeDiscussion.id
        ) == fixture.activeDiscussion)

        try await coordinator.retainRecordsForUnknownOutcome(
            recoveryRecordID: pending.id
        )
        #expect(try await fixture.recoveryStore.pending().isEmpty)
        #expect(try await fixture.portableRecordStore.record(
            id: fixture.sharedRecord.id
        ) == fixture.sharedRecord)
    }

    @Test("Folder confirmation covers hidden and non-Markdown descendants")
    func folderManifestChangeFailsClosed() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let coordinator = fixture.coordinator()
        let preview = try await coordinator.prepareFolder(
            vaultID: fixture.vaultID,
            relativePath: fixture.folderPath
        )
        let hiddenURL = fixture.folderURL.appendingPathComponent(".external-state")
        try Data("changed after confirmation".utf8).write(to: hiddenURL, options: .atomic)

        await #expect(throws: VaultRepositoryError.self) {
            _ = try await coordinator.moveToSystemTrash(preview)
        }

        #expect(FileManager.default.fileExists(atPath: fixture.folderURL.path))
        #expect(try await fixture.portableRecordStore.record(
            id: fixture.sharedRecord.id
        ) == fixture.sharedRecord)
        #expect(try await fixture.recoveryStore.pending().isEmpty)
    }

    @Test("A Work and its managed Critique are separate native moves with retained association")
    func managedCritiqueUsesSeparateReceiptAndRetainsPortableRelationship() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let critique = try await fixture.installManagedCritique()
        var trashURLs: [URL] = []
        defer { trashURLs.forEach { try? FileManager.default.removeItem(at: $0) } }
        let coordinator = fixture.coordinator()
        let preview = try await coordinator.prepareNote(
            noteID: fixture.firstIdentity.id,
            vaultID: fixture.vaultID,
            relativePath: fixture.firstPath,
            expectedRevision: fixture.firstFingerprint
        )

        #expect(preview.sources.map(\.relativePath).sorted() == [
            critique.path,
            fixture.firstPath,
        ].sorted())

        let commit = try await coordinator.moveToSystemTrash(preview)
        trashURLs = commit.resultingTrashPaths.map(URL.init(fileURLWithPath:))

        #expect(!FileManager.default.fileExists(atPath: fixture.firstURL.path))
        #expect(!FileManager.default.fileExists(atPath: critique.url.path))
        #expect(await fixture.critiqueRegistry.association(
            workNoteID: fixture.firstIdentity.id
        ) == critique.association)
        #expect(try await fixture.control.identityRecord(
            vaultID: fixture.vaultID,
            relativePath: critique.path
        )?.id == critique.identity.id)
    }

    private struct Fixture {
        let root: URL
        let works: URL
        let support: URL
        let folderPath = "Projects/Cutover"
        let firstPath: String
        let secondPath = "Second.md"
        let firstURL: URL
        let secondURL: URL
        let folderURL: URL
        let firstFingerprint: DocumentFingerprint
        let secondFingerprint: DocumentFingerprint
        let vaultID: UUID
        let triptychID: UUID
        let firstIdentity: NoteIdentityRecord
        let secondIdentity: NoteIdentityRecord
        let control: TriptychControlStore
        let critiqueRegistry: CritiqueRegistry
        let repository: VaultRepository
        let recoveryStore: TriptychMutationRecoveryStore
        let portableRecordStore: PortableResearchRecordStore
        let sharedRecord: PortableResearchRecord
        let unrelatedRecord: PortableResearchRecord
        let activeDiscussion: PortableResearchDiscussion

        init(recreateFirstSourceAfterTrash: Bool = false) async throws {
            firstPath = "Projects/Cutover/First-\(UUID().uuidString).md"
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent(
                    ".build/system-trash-deletion-tests/\(UUID().uuidString)",
                    isDirectory: true
                )
            works = root.appendingPathComponent("Works", isDirectory: true)
            support = root.appendingPathComponent("Support", isDirectory: true)
            try FileManager.default.createDirectory(at: works, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let firstSourceURL = works.appendingPathComponent(firstPath)
            firstURL = firstSourceURL
            secondURL = works.appendingPathComponent(secondPath)
            folderURL = works.appendingPathComponent(folderPath, isDirectory: true)
            try FileManager.default.createDirectory(
                at: firstURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let firstSource = "# First\n\nExact first source.\n"
            let secondSource = "# Second\n\nExact second source.\n"
            try Data(firstSource.utf8).write(to: firstURL, options: .atomic)
            try Data(secondSource.utf8).write(to: secondURL, options: .atomic)
            try Data("non-Markdown inventory".utf8).write(
                to: folderURL.appendingPathComponent("attachment.txt"),
                options: .atomic
            )
            firstFingerprint = DocumentFingerprint(content: firstSource)
            secondFingerprint = DocumentFingerprint(content: secondSource)
            vaultID = UUID()
            triptychID = UUID()

            control = TriptychControlStore(worksVaultURL: works)
            _ = try await control.bootstrap(
                vaultIDs: [
                    .paperAnalysis: UUID(),
                    .topicKnowledge: UUID(),
                    .output: vaultID,
                ],
                preferredTriptychID: triptychID
            )
            firstIdentity = try #require(try await control.identity(
                forVaultID: vaultID,
                relativePath: firstPath,
                fingerprint: firstFingerprint
            ))
            secondIdentity = try #require(try await control.identity(
                forVaultID: vaultID,
                relativePath: secondPath,
                fingerprint: secondFingerprint
            ))
            critiqueRegistry = CritiqueRegistry(controlURL: await control.controlURL)
            repository = try VaultRepository(
                vaultURL: works,
                identity: VaultIdentity(
                    id: vaultID,
                    canonicalPath: works.path,
                    bookmarkData: nil
                ),
                applicationSupportURL: support,
                vaultRole: .draftProject,
                mutationHooks: VaultMutationHooks(didReach: { phase in
                    guard recreateFirstSourceAfterTrash,
                          phase == .systemTrashMoved,
                          !FileManager.default.fileExists(atPath: firstSourceURL.path) else {
                        return
                    }
                    try Data("# Recreated source\n".utf8).write(
                        to: firstSourceURL,
                        options: .atomic
                    )
                })
            )
            recoveryStore = try TriptychMutationRecoveryStore(
                storageURL: support.appendingPathComponent(
                    "Transaction Recovery",
                    isDirectory: true
                )
            )
            portableRecordStore = try PortableResearchRecordStore(
                controlURL: await control.controlURL,
                applicationSupportURL: support,
                triptychID: triptychID
            )
            let firstParticipant = try Self.participant(
                identity: firstIdentity,
                vaultID: vaultID,
                path: firstPath,
                title: "First",
                fingerprint: firstFingerprint
            )
            let secondParticipant = try Self.participant(
                identity: secondIdentity,
                vaultID: vaultID,
                path: secondPath,
                title: "Second",
                fingerprint: secondFingerprint
            )
            let statement = try PortableResearchStatement(
                author: .researcher,
                kind: .discussionTurn,
                attribution: "Researcher",
                text: "Compare these two Notes.",
                createdAt: Date(timeIntervalSince1970: 10)
            )
            sharedRecord = try PortableResearchRecord(
                triptychID: triptychID,
                title: ResearchRecordTitle("Shared interpretation"),
                kind: .discussion,
                action: nil,
                method: nil,
                primaryNoteID: firstIdentity.id,
                participatingNotes: [firstParticipant, secondParticipant],
                statements: [statement],
                fidelityCompletion: .notApplicable,
                startedAt: Date(timeIntervalSince1970: 10),
                finishedAt: Date(timeIntervalSince1970: 20)
            )
            unrelatedRecord = try PortableResearchRecord(
                triptychID: triptychID,
                title: ResearchRecordTitle("Second Note only"),
                kind: .discussion,
                action: nil,
                method: nil,
                primaryNoteID: secondIdentity.id,
                participatingNotes: [secondParticipant],
                statements: [statement],
                fidelityCompletion: .notApplicable,
                startedAt: Date(timeIntervalSince1970: 10),
                finishedAt: Date(timeIntervalSince1970: 20)
            )
            _ = try await portableRecordStore.createFinishedRecord(sharedRecord)
            _ = try await portableRecordStore.createFinishedRecord(unrelatedRecord)
            _ = try await portableRecordStore.settle(
                noteID: firstIdentity.id,
                fingerprint: firstFingerprint,
                rationale: "Stable researcher baseline."
            )
            activeDiscussion = try PortableResearchDiscussion(
                triptychID: triptychID,
                primaryNoteID: firstIdentity.id,
                participatingNotes: [firstParticipant, secondParticipant],
                statements: [statement],
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
            _ = try await portableRecordStore.createActiveDiscussion(activeDiscussion)
        }

        func coordinator(
            faultPlan: SystemTrashDeletionFaultPlan = .none
        ) -> NoteSystemTrashDeletionCoordinator {
            NoteSystemTrashDeletionCoordinator(
                triptychID: triptychID,
                repository: repository,
                critiqueRegistry: critiqueRegistry,
                controlStore: control,
                recoveryStore: recoveryStore,
                portableRecordStore: portableRecordStore,
                faultPlan: faultPlan
            )
        }

        func installManagedCritique() async throws -> ManagedCritique {
            let path = "Critiques/First Critique-\(UUID().uuidString).md"
            let url = works.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let source = "# Critique\n\nExact managed critique.\n"
            try Data(source.utf8).write(to: url, options: .atomic)
            let identity = try #require(try await control.identity(
                forVaultID: vaultID,
                relativePath: path,
                fingerprint: DocumentFingerprint(content: source)
            ))
            let association = try await critiqueRegistry.save(CritiqueAssociation(
                workNoteID: firstIdentity.id,
                workRelativePath: firstPath,
                targetFingerprint: firstFingerprint,
                critiqueRelativePath: path
            ))
            return ManagedCritique(
                path: path,
                url: url,
                identity: identity,
                association: association
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }


        private static func participant(
            identity: NoteIdentityRecord,
            vaultID: UUID,
            path: String,
            title: String,
            fingerprint: DocumentFingerprint
        ) throws -> PortableResearchNoteRevision {
            try PortableResearchNoteRevision(
                noteID: identity.id,
                note: VaultQualifiedNoteID(vaultID: vaultID, relativePath: path),
                role: .work,
                title: title,
                startingRevision: fingerprint,
                endingRevision: fingerprint
            )
        }

        struct ManagedCritique {
            let path: String
            let url: URL
            let identity: NoteIdentityRecord
            let association: CritiqueAssociation
        }
    }
}
