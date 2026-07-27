import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Coordinated permanent deletion")
struct PermanentDeletionTests {
    @Test("Confirmed deletion purges source, current records, identity, history, and checkpoints")
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

        #expect(commit.invalidatedCheckpointIDs == [checkpoint.id])
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
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

        let parentRunID = UUID()
        let parentAction = try makeDeletionTestActionSnapshot(
            noteID: fixture.workIdentity.id,
            vaultID: fixture.vaultID,
            relativePath: fixture.workPath,
            fingerprint: fixture.workFingerprint
        )
        _ = try await fixture.localExecutionStore.create(
            try makeDeletionTestLocalExecution(
                triptychID: fixture.triptychID,
                runID: parentRunID,
                action: parentAction
            )
        )
        let revision = try AgentNoteChangeActionRevision(
            actionSnapshot: parentAction
        )
        let requestByParent = try makeDeletionTestAgentRequest(
            triptychID: fixture.triptychID,
            parentRunID: parentRunID,
            revision: revision,
            targetNoteID: UUID(),
            vaultID: fixture.vaultID,
            relativePath: "Unrelated Work.md",
            fingerprint: DocumentFingerprint(content: "# Unrelated Work\n")
        )
        let requestByTarget = try makeDeletionTestAgentRequest(
            triptychID: fixture.triptychID,
            parentRunID: UUID(),
            revision: revision,
            targetNoteID: fixture.workIdentity.id,
            vaultID: fixture.vaultID,
            relativePath: fixture.workPath,
            fingerprint: fixture.workFingerprint
        )
        _ = try await fixture.agentNoteChangeRequestStore.submitValidated(
            requestByParent,
            isCurrent: true
        )
        _ = try await fixture.agentNoteChangeRequestStore.submitValidated(
            requestByTarget,
            isCurrent: true
        )

        let commit = try await fixture.coordinator().delete(
            noteID: fixture.workIdentity.id,
            vaultID: fixture.vaultID,
            relativePath: fixture.workPath,
            expectedRevision: fixture.workFingerprint,
            checkpointArea: .works
        )

        #expect(commit.removedCritiqueDocumentPath == fixture.critiquePath)
        #expect(commit.removedCritiqueAssociationIDs == [fixture.association.id])
        #expect(!FileManager.default.fileExists(atPath: fixture.workURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.critiqueURL.path))
        #expect(await fixture.repository.recoveryEntries(relativePath: fixture.workPath).isEmpty)
        #expect(await fixture.repository.recoveryEntries(relativePath: fixture.critiquePath).isEmpty)
        #expect(await fixture.critiqueRegistry.association(workNoteID: fixture.workIdentity.id) == nil)
        #expect(try await fixture.control.identityRecord(
            vaultID: fixture.vaultID,
            relativePath: fixture.critiquePath
        ) == nil)
        #expect(await fixture.checkpointStore.checkpoints().isEmpty)
        #expect(try await fixture.portableRecordStore.settlementListing().settlements.isEmpty)
        #expect(try await fixture.localExecutionStore.recordIfPresent(
            id: parentRunID
        ) == nil)
        await #expect(throws: AgentNoteChangeRequestStoreError.self) {
            _ = try await fixture.agentNoteChangeRequestStore.record(
                id: requestByParent.id
            )
        }
        await #expect(throws: AgentNoteChangeRequestStoreError.self) {
            _ = try await fixture.agentNoteChangeRequestStore.record(
                id: requestByTarget.id
            )
        }
        let pending = try await fixture.recoveryStore.pending()
        #expect(pending.isEmpty)
    }

    @Test(
        "A cleanup failure restores both Markdown files and every purged record",
        arguments: [
            PermanentDeletionFaultPoint.afterCritiqueDeletion,
            .afterSourceDeletion,
            .afterSettlementPurge,
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
        #expect(await fixture.critiqueRegistry.association(workNoteID: fixture.workIdentity.id)?.id == fixture.association.id)
        #expect(await fixture.checkpointStore.checkpoints().map(\.id) == [fixture.checkpoint.id])
        #expect(try await fixture.portableRecordStore.latestSettlement(
            noteID: fixture.workIdentity.id
        ) == fixture.workSettlement)
        #expect(try await fixture.portableRecordStore.latestSettlement(
            noteID: fixture.critiqueIdentity.id
        ) == fixture.critiqueSettlement)
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
        #expect(await fixture.critiqueRegistry.association(workNoteID: fixture.workIdentity.id)?.id == fixture.association.id)
        #expect(await fixture.checkpointStore.checkpoints().map(\.id) == [fixture.checkpoint.id])
        #expect(try await fixture.portableRecordStore.latestSettlement(
            noteID: fixture.workIdentity.id
        ) == fixture.workSettlement)
        #expect(try await fixture.portableRecordStore.latestSettlement(
            noteID: fixture.critiqueIdentity.id
        ) == fixture.critiqueSettlement)
        #expect(try await fixture.recoveryStore.pending().isEmpty)
    }

    @Test("Rollback preserves a newer Settle created after deletion capture")
    func interruptedDeletionPreservesConcurrentSettlement() async throws {
        let fixture = try await WorkFixture()
        defer { fixture.remove() }
        let interrupted = fixture.coordinator(
            faultPlan: PermanentDeletionFaultPlan(
                failures: [],
                interruptions: [.afterSettlementPurge]
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
        let concurrent = try await fixture.portableRecordStore.settle(
            noteID: fixture.workIdentity.id,
            fingerprint: DocumentFingerprint(content: "newer-settlement"),
            rationale: "Recorded from another window while deletion was interrupted."
        )

        try await fixture.reopenedCoordinator().recoverInterruptedTransactions()

        #expect(try await fixture.portableRecordStore.latestSettlement(
            noteID: fixture.workIdentity.id
        ) == concurrent)
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
        #expect(try await fixture.portableRecordStore.settlementListing().settlements.isEmpty)
        #expect(try await fixture.recoveryStore.pending().isEmpty)
    }

    @Test("Committed deletion removes a first Settle created after capture")
    func committedDeletionPurgesLateFirstSettlement() async throws {
        let fixture = try await WorkFixture()
        defer { fixture.remove() }
        try await fixture.portableRecordStore.purgeSettlement(
            noteID: fixture.workIdentity.id
        )
        try await fixture.portableRecordStore.purgeSettlement(
            noteID: fixture.critiqueIdentity.id
        )
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
        _ = try await fixture.portableRecordStore.settle(
            noteID: fixture.workIdentity.id,
            fingerprint: DocumentFingerprint(content: "late-work"),
            rationale: nil
        )
        _ = try await fixture.portableRecordStore.settle(
            noteID: fixture.critiqueIdentity.id,
            fingerprint: DocumentFingerprint(content: "late-critique"),
            rationale: nil
        )

        try await fixture.reopenedCoordinator().recoverInterruptedTransactions()

        #expect(try await fixture.portableRecordStore.latestSettlement(
            noteID: fixture.workIdentity.id
        ) == nil)
        #expect(try await fixture.portableRecordStore.latestSettlement(
            noteID: fixture.critiqueIdentity.id
        ) == nil)
        #expect(try await fixture.recoveryStore.pending().isEmpty)
    }

    @Test("Malformed unrelated portable data blocks deletion before Markdown changes")
    func malformedPortableDataFailsClosedBeforeDeletion() async throws {
        let fixture = try await WorkFixture()
        defer { fixture.remove() }
        let malformedURL = fixture.portableRecordStore.storageURL
            .appendingPathComponent("active", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString.lowercased()).json")
        try FileManager.default.createDirectory(
            at: malformedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{not valid portable data".utf8).write(to: malformedURL, options: .atomic)

        await #expect(throws: ResearchRecordStoreError.self) {
            _ = try await fixture.coordinator().delete(
                noteID: fixture.workIdentity.id,
                vaultID: fixture.vaultID,
                relativePath: fixture.workPath,
                expectedRevision: fixture.workFingerprint,
                checkpointArea: .works
            )
        }

        #expect(try Data(contentsOf: fixture.workURL) == Data(fixture.workSource.utf8))
        #expect(try Data(contentsOf: fixture.critiqueURL) == Data(fixture.critiqueSource.utf8))
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
        let critiqueRegistry: CritiqueRegistry
        let association: CritiqueAssociation
        let checkpointStore: TriptychCheckpointStore
        let checkpoint: TriptychCheckpoint
        let control: TriptychControlStore
        let repository: VaultRepository
        let recoveryStore: TriptychMutationRecoveryStore
        let portableRecordStore: PortableResearchRecordStore
        let localExecutionStore: LocalResearchExecutionStore
        let agentNoteChangeRequestStore: AgentNoteChangeRequestStore
        let workSettlement: SettlementRecord
        let critiqueSettlement: SettlementRecord

        init() async throws {
            root = URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            )
                .appendingPathComponent(
                    ".build/session11-permanent-deletion-tests/\(UUID().uuidString)",
                    isDirectory: true
                )
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
            portableRecordStore = try PortableResearchRecordStore(
                controlURL: await control.controlURL,
                applicationSupportURL: support,
                triptychID: triptychID
            )
            localExecutionStore = try LocalResearchExecutionStore(
                applicationSupportURL: support,
                triptychID: triptychID
            )
            agentNoteChangeRequestStore = try AgentNoteChangeRequestStore(
                applicationSupportURL: support,
                triptychID: triptychID
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
            workSettlement = try await portableRecordStore.settle(
                noteID: workIdentity.id,
                fingerprint: workFingerprint,
                rationale: "Current Work basis.",
                settledAt: Date(timeIntervalSince1970: 10)
            )
            critiqueSettlement = try await portableRecordStore.settle(
                noteID: critiqueIdentity.id,
                fingerprint: DocumentFingerprint(content: critiqueSource),
                rationale: nil,
                settledAt: Date(timeIntervalSince1970: 11)
            )
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
                critiqueRegistry: critiqueRegistry,
                checkpointStore: checkpointStore,
                controlStore: control,
                recoveryStore: recoveryStore,
                portableRecordStore: portableRecordStore,
                localExecutionStore: localExecutionStore,
                agentNoteChangeRequestStore: agentNoteChangeRequestStore,
                faultPlan: faultPlan
            )
        }

        func reopenedCoordinator() async throws -> NotePermanentDeletionCoordinator {
            let reopenedControl = TriptychControlStore(worksVaultURL: works)
            return NotePermanentDeletionCoordinator(
                triptychID: triptychID,
                repository: try reopenedRepository(),
                critiqueRegistry: CritiqueRegistry(controlURL: await reopenedControl.controlURL),
                checkpointStore: TriptychCheckpointStore(
                    triptychID: triptychID,
                    applicationSupportURL: support
                ),
                controlStore: reopenedControl,
                recoveryStore: try TriptychMutationRecoveryStore(
                    storageURL: support.appendingPathComponent("Transaction Recovery", isDirectory: true)
                ),
                portableRecordStore: try PortableResearchRecordStore(
                    controlURL: await reopenedControl.controlURL,
                    applicationSupportURL: support,
                    triptychID: triptychID
                ),
                localExecutionStore: try LocalResearchExecutionStore(
                    applicationSupportURL: support,
                    triptychID: triptychID
                ),
                agentNoteChangeRequestStore: try AgentNoteChangeRequestStore(
                    applicationSupportURL: support,
                    triptychID: triptychID
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

private func makeDeletionTestActionSnapshot(
    noteID: UUID,
    vaultID: UUID,
    relativePath: String,
    fingerprint: DocumentFingerprint
) throws -> ResearchActionSnapshot {
    let definition = ResearchActionDefinition.write
    let target = ResearchActionNoteSnapshot(
        noteID: noteID,
        note: VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: relativePath
        ),
        role: .work,
        lifecycle: .active,
        fingerprint: fingerprint,
        title: "Work"
    )
    let profile = try ResearchActionProfile(
        definition: definition,
        buttonName: "Write",
        order: 100,
        applicableRoles: [.work],
        showInActions: true,
        modules: [],
        sourceRequirement: .none,
        capabilities: try ResearchActionCapabilityDeclaration(
            readableRoles: [.work],
            candidateWritableRoles: [.work],
            candidateWriteOperations: [.modifyMarkdown]
        ),
        feedbackRequirement: .requested
    )
    return try ResearchActionSnapshot(
        definition: definition,
        target: target,
        method: try ResearchActionMethodSnapshot(
            packageID: "scholium-working-write",
            origin: .triptych,
            version: "working",
            packageRevision: DocumentFingerprint(content: "package"),
            loadedResources: [ResearchActionResourceSnapshot(
                relativePath: "SKILL.md",
                revision: DocumentFingerprint(content: "method")
            )]
        ),
        resolvedProfile: try ResearchActionResolvedProfileSnapshot(
            origin: .applicationDefault,
            profile: profile,
            profileRevision: profile.contentRevision(),
            profileDocumentRevision: nil
        ),
        parameters: try ResearchActionParameterModel(profile: profile),
        authority: try ResearchAuthorityEnvelope(
            readableNotes: [target],
            writableNotes: [target],
            writeOperations: [.modifyMarkdown],
            editablePropertyKeys: []
        )
    )
}

private func makeDeletionTestLocalExecution(
    triptychID: UUID,
    runID: UUID,
    action: ResearchActionSnapshot
) throws -> LocalResearchExecutionRecord {
    let target = ResearchFunctionTarget(
        noteID: action.target.noteID,
        note: action.target.note,
        role: .work,
        lifecycle: .active,
        fingerprint: action.target.fingerprint,
        title: action.target.title
    )
    let snapshot = ResearchFunctionSnapshot(
        runID: runID,
        request: ResearchFunctionRequest(
            function: .revise,
            target: target,
            writeScope: .currentNote,
            authorizedWriteTargets: [target]
        ),
        actionSnapshot: action,
        recordKind: .functionEnvelope,
        recordID: runID,
        confirmationToken: UUID(),
        preparedAt: Date(timeIntervalSince1970: 10)
    )
    return try LocalResearchExecutionRecord(
        triptychID: triptychID,
        snapshot: snapshot,
        preparedInstructions: "Local protected instructions."
    )
}

private func makeDeletionTestAgentRequest(
    triptychID: UUID,
    parentRunID: UUID,
    revision: AgentNoteChangeActionRevision,
    targetNoteID: UUID,
    vaultID: UUID,
    relativePath: String,
    fingerprint: DocumentFingerprint
) throws -> AgentNoteChangeRequest {
    try AgentNoteChangeRequest(
        triptychID: triptychID,
        parentRunID: parentRunID,
        parentAction: revision,
        requestedAction: revision,
        targets: [try AgentNoteChangeTarget(
            noteID: targetNoteID,
            note: VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: relativePath
            ),
            role: .work,
            expectedFingerprint: fingerprint
        )],
        operations: [.modifyMarkdown],
        agentReason: "Request one independently authorized Work change."
    )
}
