import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Window Workspace projection ownership")
struct WindowWorkspaceProjectionControllerTests {
    @MainActor
    private final class CatalogLoadProbe {
        private(set) var callCount = 0
        private(set) var completedCallCount = 0
        private(set) var cancelledLoadCount = 0
        private var continuations: [CheckedContinuation<WorkspaceCatalogSnapshot, Never>] = []

        func load() async -> WorkspaceCatalogSnapshot {
            callCount += 1
            let catalog = await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
            if Task.isCancelled {
                cancelledLoadCount += 1
            }
            completedCallCount += 1
            return catalog
        }

        func resumeNext(with catalog: WorkspaceCatalogSnapshot) {
            continuations.removeFirst().resume(returning: catalog)
        }
    }

    @Test("One event commits a coherent Library projection")
    func eventCommitsOneCoherentProjection() throws {
        let fixture = try Fixture()
        let snapshot = fixture.snapshot(
            activeSource: "# Active\n",
            searchSequence: 1
        )
        let controller = WindowWorkspaceProjectionController {
            snapshot.discovery.catalog
        }

        let commit = controller.activate(
            snapshot: snapshot,
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(sourceScope: .library)
        )

        #expect(
            Set(controller.notes.map(\.relativePath)) == [
                "Active.md",
                "Archive/Aside.md",
                "Old/Removed.md",
            ])
        #expect(
            Set(controller.documentRevisions.keys) == [
                "Active.md",
                "Archive/Aside.md",
                "Old/Removed.md",
            ])
        #expect(controller.vaultSnapshotsByID[fixture.vault.id]?.documents.count == 3)
        #expect(controller.catalog?.notes.count == 3)
        #expect(
            controller.linkGraph?.generation
                == snapshot.discovery.catalog.graph?.generation
        )
        #expect(controller.searchGeneration?.sequence == 1)
        #expect(controller.derivedRefreshStatus != nil)
        #expect(!commit.searchGenerationChanged)
        #expect(commit.retainedDeletedDocumentPath == nil)
    }

    @Test("Opening phase keeps the available Library and advances to complete")
    func openingPhaseProjection() throws {
        let fixture = try Fixture()
        let opening = fixture.snapshot(
            activeSource: "# Available\n",
            searchSequence: 1,
            phase: .opening(availableVault: .paperAnalysis)
        )
        let controller = WindowWorkspaceProjectionController {
            opening.discovery.catalog
        }

        let openingCommit = controller.activate(
            snapshot: opening,
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(sourceScope: .library)
        )
        #expect(
            openingCommit.snapshotPhase
                == .opening(
                    availableVault: .paperAnalysis
                ))
        #expect(controller.snapshotPhase == openingCommit.snapshotPhase)
        #expect(
            Set(controller.notes.map(\.relativePath)) == [
                "Active.md", "Archive/Aside.md", "Old/Removed.md",
            ])
        guard case .opening? = controller.derivedRefreshStatus else {
            Issue.record("The usable-vault projection was presented as complete.")
            return
        }

        let complete = fixture.snapshot(
            activeSource: "# Available\n",
            searchSequence: 2
        )
        let completeCommit = controller.receive(
            .snapshot(WorkspaceSnapshotEvent(generation: 1, snapshot: complete)),
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(sourceScope: .library)
        )
        #expect(completeCommit?.snapshotPhase == .complete)
        #expect(controller.snapshotPhase == .complete)
        guard case .current? = controller.derivedRefreshStatus else {
            Issue.record("The complete projection did not clear opening state.")
            return
        }
    }

    @Test("Runtime and generation gates reject stale projection events")
    func runtimeAndGenerationGate() throws {
        let fixture = try Fixture()
        let initial = fixture.snapshot(activeSource: "# Generation 5\n", searchSequence: 5)
        let controller = WindowWorkspaceProjectionController {
            initial.discovery.catalog
        }
        _ = controller.activate(
            snapshot: initial,
            runtimeIdentity: fixture.runtimeIdentity,
            generation: 5,
            context: fixture.context(sourceScope: .library)
        )

        let stale = fixture.snapshot(activeSource: "# Stale\n", searchSequence: 4)
        let staleEvent = WorkspaceEvent.snapshot(
            WorkspaceSnapshotEvent(
                generation: 4,
                snapshot: stale
            ))
        #expect(
            !controller.canReceive(
                staleEvent,
                runtimeIdentity: fixture.runtimeIdentity
            ))
        #expect(
            controller.receive(
                staleEvent,
                runtimeIdentity: fixture.runtimeIdentity,
                context: fixture.context(sourceScope: .library)
            ) == nil)
        #expect(controller.notes.first?.workspaceSnapshot?.fingerprint == DocumentFingerprint(content: "# Generation 5\n"))

        let foreign = TriptychRuntimeIdentity(
            triptychID: fixture.triptych.id,
            activationID: UUID()
        )
        let newer = fixture.snapshot(activeSource: "# Foreign\n", searchSequence: 6)
        #expect(
            !controller.canReceive(
                .snapshot(WorkspaceSnapshotEvent(generation: 6, snapshot: newer)),
                runtimeIdentity: foreign
            ))
        #expect(
            controller.receive(
                .snapshot(WorkspaceSnapshotEvent(generation: 6, snapshot: newer)),
                runtimeIdentity: foreign,
                context: fixture.context(sourceScope: .library)
            ) == nil)
        #expect(controller.notes.first?.workspaceSnapshot?.fingerprint == DocumentFingerprint(content: "# Generation 5\n"))

        let configurationOnly = WorkspaceResearchConfigurationInvalidatedEvent(
            generation: 6,
            snapshot: initial
        )
        #expect(
            controller.receive(
                .researchConfigurationInvalidated(configurationOnly),
                runtimeIdentity: fixture.runtimeIdentity,
                context: fixture.context(sourceScope: .library)
            ) == nil)
        #expect(controller.notes.first?.workspaceSnapshot?.fingerprint == DocumentFingerprint(content: "# Generation 5\n"))

        let sameGeneration = fixture.snapshot(
            activeSource: "# Same Generation\n",
            searchSequence: 6
        )
        #expect(
            controller.receive(
                .snapshot(WorkspaceSnapshotEvent(generation: 6, snapshot: sameGeneration)),
                runtimeIdentity: fixture.runtimeIdentity,
                context: fixture.context(sourceScope: .library)
            ) == nil)

        let accepted = fixture.snapshot(activeSource: "# Generation 7\n", searchSequence: 7)
        let commit = controller.receive(
            .snapshot(WorkspaceSnapshotEvent(generation: 7, snapshot: accepted)),
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(sourceScope: .library)
        )
        #expect(commit?.searchGenerationChanged == true)
        #expect(controller.notes.first?.workspaceSnapshot?.fingerprint == DocumentFingerprint(content: "# Generation 7\n"))
    }

    @Test("A dirty deleted editor remains visible until conflict recovery")
    func dirtyDeletedEditorIsRetained() throws {
        let fixture = try Fixture()
        let initial = fixture.snapshot(activeSource: "# Retained\n", searchSequence: 1)
        let controller = WindowWorkspaceProjectionController {
            initial.discovery.catalog
        }
        _ = controller.activate(
            snapshot: initial,
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(
                sourceScope: .library,
                selectedDocumentPath: "Active.md",
                retainedDeletedDocumentPath: "Active.md"
            )
        )

        let removed = fixture.snapshot(
            activeSource: nil,
            searchSequence: 2
        )
        let commit = controller.receive(
            .snapshot(WorkspaceSnapshotEvent(generation: 1, snapshot: removed)),
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(
                sourceScope: .library,
                selectedDocumentPath: "Active.md",
                retainedDeletedDocumentPath: "Active.md"
            )
        )

        #expect(commit?.retainedDeletedDocumentPath == "Active.md")
        #expect(
            Set(controller.notes.map(\.relativePath)) == [
                "Active.md", "Archive/Aside.md", "Old/Removed.md",
            ])
        #expect(controller.documentRevisions["Active.md"] != nil)

        _ = controller.receive(
            .snapshot(WorkspaceSnapshotEvent(generation: 2, snapshot: removed)),
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(
                sourceScope: .library,
                selectedDocumentPath: "Active.md",
                retainedDeletedDocumentPath: nil
            )
        )
        #expect(
            Set(controller.notes.map(\.relativePath)) == [
                "Archive/Aside.md", "Old/Removed.md",
            ])
        #expect(
            Set(controller.documentRevisions.keys) == [
                "Archive/Aside.md", "Old/Removed.md",
            ])
    }

    @Test("A committed note updates cache and Library filter projections atomically")
    func committedNoteUpdatesOneState() throws {
        let fixture = try Fixture()
        let initial = fixture.snapshot(activeSource: "# Before\n", searchSequence: 1)
        let controller = WindowWorkspaceProjectionController {
            initial.discovery.catalog
        }
        _ = controller.activate(
            snapshot: initial,
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(sourceScope: .library)
        )
        let replacement = fixture.note(
            path: "Active.md",
            source: "---\nkeywords: [updated]\ntags: [ignored]\nauthors: [Arendt]\n---\n# After\n",
            stableID: fixture.activeNoteID
        )

        let vault = controller.recordCommittedNote(
            replacement.summary,
            visibleVaultID: fixture.vault.id,
            visibleSourceScope: .library
        )

        #expect(vault?.id == fixture.vault.id)
        #expect(controller.notes.first?.workspaceSnapshot?.fingerprint == replacement.fingerprint)
        #expect(controller.tags == ["updated"])
        #expect(controller.authors == ["Arendt"])
        #expect(controller.documentRevisions["Active.md"] == replacement.fingerprint)
        #expect(
            controller.vaultSnapshot(
                id: fixture.vault.id
            )?.pathComparisonPolicy == fixture.pathComparisonPolicy)
        #expect(
            controller.vaultSnapshotsByID[fixture.vault.id]?.documents.first {
                $0.id.relativePath == "Active.md"
            }?.fingerprint == replacement.fingerprint)
    }

    @Test("Stable identity lookup never falls back to a reused path")
    func stableIdentityLookupRejectsReusedPath() throws {
        let fixture = try Fixture()
        let baseline = fixture.snapshot(activeSource: "# Original\n", searchSequence: 1)
        let controller = WindowWorkspaceProjectionController {
            baseline.discovery.catalog
        }
        let replacementID = UUID()
        let replacementAtOldPath = fixture.note(
            path: "Active.md",
            source: "# Replacement\n",
            stableID: replacementID
        )
        let movedOriginal = fixture.note(
            path: "Archive/Active.md",
            source: "# Original\n",
            stableID: fixture.activeNoteID
        )
        controller.replaceVaultSnapshots([
            WorkspaceVaultSnapshot(
                slot: .paperAnalysis,
                vault: fixture.vault,
                pathComparisonPolicy: fixture.pathComparisonPolicy,
                documents: [replacementAtOldPath.summary, movedOriginal.summary],
                identityRecovery: NoteIdentityRecoveryState(
                    identities: [:],
                    ambiguities: [],
                    pendingRebindings: [],
                    failures: []
                )
            )
        ])

        let resolved = controller.cachedNote(
            vaultID: fixture.vault.id,
            stableNoteID: fixture.activeNoteID,
            relativePath: "Active.md"
        )
        #expect(resolved?.id.relativePath == "Archive/Active.md")
        #expect(resolved?.stableIdentity.resolvedID == fixture.activeNoteID)
        #expect(
            controller.cachedNote(
                vaultID: fixture.vault.id,
                stableNoteID: UUID(),
                relativePath: "Active.md"
            ) == nil)
        #expect(
            controller.cachedNote(
                vaultID: fixture.vault.id,
                relativePath: "Active.md"
            )?.stableIdentity.resolvedID == replacementID)
    }

    @Test("A committed untitled source is visible while derived state remains explicitly stale")
    func committedUntitledSourceDoesNotClaimCurrentDerivedState() throws {
        let fixture = try Fixture()
        let initial = fixture.snapshot(activeSource: "# Before\n", searchSequence: 1)
        let controller = WindowWorkspaceProjectionController {
            initial.discovery.catalog
        }
        _ = controller.activate(
            snapshot: initial,
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(sourceScope: .library)
        )
        let document = NoteDocument(relativePath: "Untitled.md", rawContent: "")
        let noteID = UUID()
        let commit = WorkspaceManagedNoteCommit(
            id: VaultQualifiedNoteID(
                vaultID: fixture.vault.id,
                relativePath: document.relativePath
            ),
            vaultRole: fixture.vault.role,
            stableIdentity: .resolved(noteID),
            document: document,
            baseSourceInventoryRevision: initial.sourceInventoryRevision
        )

        _ = controller.recordCommittedNoteCreation(
            commit,
            visibleVaultID: fixture.vault.id,
            visibleSourceScope: .library
        )

        let visible = try #require(
            controller.notes.first {
                $0.relativePath == "Untitled.md"
            })
        #expect(visible.workspaceSnapshot?.fingerprint == document.fingerprint)
        #expect(visible.hydratedSnapshot == nil)
        #expect(visible.workspaceSnapshot?.derivedProjectionState == .sourceAhead)
        guard case .stale(let issue)? = controller.derivedRefreshStatus else {
            Issue.record("The source-ahead window overlay claimed current derived state.")
            return
        }
        #expect(issue.affectedVaultIDs == [fixture.vault.id])
    }

    @Test(
        "Older and equal inventory metadata events preserve a committed creation until a fresh inventory includes it",
        arguments: [1, 2])
    func creationSurvivesMetadataReplay(windowSourceRevision: Int) throws {
        let fixture = try Fixture()
        let initial = fixture.snapshot(activeSource: "# Before\n", searchSequence: windowSourceRevision)
        let older = fixture.snapshot(activeSource: "# Before\n", searchSequence: 1)
        // The producer's base may already be newer than the window. Accepting
        // that pre-creation inventory still cannot erase the returned commit.
        let creationBase = fixture.snapshot(activeSource: "# Before\n", searchSequence: 2)
        let controller = WindowWorkspaceProjectionController { initial.discovery.catalog }
        let context = fixture.context(sourceScope: .library)
        _ = controller.activate(snapshot: initial, runtimeIdentity: fixture.runtimeIdentity, context: context)
        let created = fixture.note(path: "Untitled.md", source: "---\nkeywords: [created]\n---\n", stableID: UUID())
        let noteID = try #require(created.stableIdentity.resolvedID)
        let commit = WorkspaceManagedNoteCommit(
            id: created.id, vaultRole: fixture.vault.role, stableIdentity: created.stableIdentity,
            document: created.document, baseSourceInventoryRevision: creationBase.sourceInventoryRevision)
        _ = controller.recordCommittedNoteCreation(commit, visibleVaultID: fixture.vault.id, visibleSourceScope: .library)
        let events: [WorkspaceEvent] = [
            .citationAuthorityInvalidated(
                .init(generation: 1, snapshot: older, derivedRefreshStatus: .current(.init(snapshot: older)))),
            .citationAuthorityInvalidated(
                .init(generation: 2, snapshot: creationBase, derivedRefreshStatus: .current(.init(snapshot: creationBase)))),
            .derivedStateChanged(
                .init(
                    generation: 3,
                    status: .failed(.init(reason: "Synthetic metadata refresh failure.", lastKnownGood: .init(snapshot: creationBase))),
                    discovery: creationBase.discovery, snapshot: creationBase)),
        ]
        for event in events {
            _ = controller.receive(event, runtimeIdentity: fixture.runtimeIdentity, context: context)
            let cached = try #require(controller.cachedNote(vaultID: fixture.vault.id, stableNoteID: noteID, relativePath: "Untitled.md"))
            #expect(cached.id == created.id)
            #expect(cached.fingerprint == created.fingerprint)
            #expect(cached.derivedProjectionState == .sourceAhead)
            #expect(controller.notes.contains { $0.summary.id == created.id && $0.summary.fingerprint == created.fingerprint })
            #expect(
                controller.cachedNote(vaultID: fixture.vault.id, stableNoteID: fixture.activeNoteID, relativePath: "Active.md")?.fingerprint
                    == DocumentFingerprint(content: "# Before\n"))
            if case .citationAuthorityInvalidated = event {
                guard case .stale? = controller.derivedRefreshStatus else {
                    Issue.record("The pre-creation citation inventory claimed current derived state for the new Note.")
                    return
                }
            }
        }
        guard case .failed? = controller.derivedRefreshStatus else {
            Issue.record("Preserving the source inventory erased the failed-refresh status.")
            return
        }
        let fresh = fixture.snapshot(activeSource: "# Before\n", additionalNotes: [created], searchSequence: 3)
        _ = controller.receive(
            .snapshot(.init(generation: 4, snapshot: fresh)), runtimeIdentity: fixture.runtimeIdentity, context: context)
        #expect(controller.cachedNote(vaultID: fixture.vault.id, stableNoteID: noteID, relativePath: "Untitled.md") == created.summary)
        guard case .current? = controller.derivedRefreshStatus else {
            Issue.record("The complete inventory containing the creation retained a source-ahead overlay.")
            return
        }
    }

    @Test("A fresh inventory arriving before the creation return keeps its current Note projection")
    func freshCreationInventoryWinsCommitReturnRace() throws {
        let fixture = try Fixture()
        let initial = fixture.snapshot(activeSource: "# Before\n", searchSequence: 1)
        let created = fixture.note(path: "Untitled.md", source: "# Created\n", stableID: UUID())
        let fresh = fixture.snapshot(activeSource: "# Before\n", additionalNotes: [created], searchSequence: 2)
        let controller = WindowWorkspaceProjectionController { initial.discovery.catalog }
        let context = fixture.context(sourceScope: .library)
        _ = controller.activate(snapshot: initial, runtimeIdentity: fixture.runtimeIdentity, context: context)
        _ = controller.receive(
            .snapshot(.init(generation: 1, snapshot: fresh)), runtimeIdentity: fixture.runtimeIdentity, context: context)
        let commit = WorkspaceManagedNoteCommit(
            id: created.id, vaultRole: fixture.vault.role, stableIdentity: created.stableIdentity,
            document: created.document, baseSourceInventoryRevision: initial.sourceInventoryRevision)
        let vault = controller.recordCommittedNoteCreation(commit, visibleVaultID: fixture.vault.id, visibleSourceScope: .library)
        #expect(vault?.id == fixture.vault.id)
        let cached = try #require(
            controller.cachedNote(
                vaultID: fixture.vault.id, stableNoteID: created.stableIdentity.resolvedID, relativePath: "Untitled.md"))
        #expect(cached == created.summary)
        #expect(cached.derivedProjectionState == .current)
        #expect(controller.notes.filter { $0.summary.id == created.id }.count == 1)
        guard case .current? = controller.derivedRefreshStatus else {
            Issue.record("The late mutation return downgraded a complete current creation inventory.")
            return
        }
    }

    @Test(
        "A late unresolved creation can use a fresh inventory only when its exact source is still present",
        arguments: [false, true])
    func unresolvedCreationRequiresExactFreshSource(freshSourceChanged: Bool) throws {
        let fixture = try Fixture()
        let initial = fixture.snapshot(activeSource: "# Before\n", searchSequence: 1)
        let committedDocument = NoteDocument(relativePath: "Untitled.md", rawContent: "\u{FEFF}Created 中文 😀 e\u{301}。\r\n")
        let freshDocument = NoteDocument(
            relativePath: committedDocument.relativePath,
            rawContent: freshSourceChanged ? "\u{FEFF}Externally replaced 中文。\r\n" : committedDocument.rawContent)
        let freshNote = WorkspaceNoteSnapshot(
            id: VaultQualifiedNoteID(vaultID: fixture.vault.id, relativePath: freshDocument.relativePath),
            vaultRole: fixture.vault.role,
            stableIdentity: .unresolved,
            document: freshDocument,
            fileMetadata: WorkspaceFileMetadata(
                byteCount: freshDocument.sourceBytes.count, creationDate: nil, modificationDate: nil),
            graphCounts: WorkspaceGraphCounts(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0))
        let fresh = fixture.snapshot(activeSource: "# Before\n", additionalNotes: [freshNote], searchSequence: 2)
        let controller = WindowWorkspaceProjectionController { initial.discovery.catalog }
        let context = fixture.context(sourceScope: .library)
        _ = controller.activate(snapshot: initial, runtimeIdentity: fixture.runtimeIdentity, context: context)
        _ = controller.receive(
            .snapshot(.init(generation: 1, snapshot: fresh)), runtimeIdentity: fixture.runtimeIdentity, context: context)
        let commit = WorkspaceManagedNoteCommit(
            id: freshNote.id, vaultRole: fixture.vault.role, stableIdentity: .unresolved,
            document: committedDocument, baseSourceInventoryRevision: initial.sourceInventoryRevision)

        let vault = controller.recordCommittedNoteCreation(commit, visibleVaultID: fixture.vault.id, visibleSourceScope: .library)

        if freshSourceChanged {
            #expect(vault == nil)
            #expect(freshDocument.sourceBytes != committedDocument.sourceBytes)
        } else {
            #expect(vault?.id == fixture.vault.id)
            #expect(freshDocument.sourceBytes == committedDocument.sourceBytes)
        }
        let cached = try #require(controller.cachedNote(vaultID: fixture.vault.id, relativePath: "Untitled.md"))
        #expect(cached == freshNote.summary)
        #expect(cached.stableIdentity == .unresolved)
        #expect(cached.fingerprint == freshDocument.fingerprint)
        #expect(cached.derivedProjectionState == .current)
        let listed = try #require(controller.notes.first { $0.summary.id == freshNote.id })
        #expect(listed.summary == freshNote.summary)
        #expect(controller.notes.filter { $0.summary.id == freshNote.id }.count == 1)
        guard case .current? = controller.derivedRefreshStatus else {
            Issue.record("The late unresolved commit replaced the fresh inventory with unavailable source bytes.")
            return
        }
    }

    @Test("A committed Folder claim is installed without replacing Note projections")
    func committedFolderUpdatesCachedInventory() throws {
        let fixture = try Fixture()
        let initial = fixture.snapshot(activeSource: "# Active\n", searchSequence: 1)
        let controller = WindowWorkspaceProjectionController {
            initial.discovery.catalog
        }
        _ = controller.activate(
            snapshot: initial,
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(sourceScope: .library)
        )
        let folder = try VaultRelativeFolderPath("Arguments/New Folder")

        let vault = controller.recordCommittedFolder(folder, vaultID: fixture.vault.id)
        _ = controller.recordCommittedFolder(folder, vaultID: fixture.vault.id)

        #expect(vault?.id == fixture.vault.id)
        #expect(controller.vaultSnapshot(id: fixture.vault.id)?.folders == [folder])
        #expect(
            controller.vaultSnapshot(
                id: fixture.vault.id
            )?.pathComparisonPolicy == fixture.pathComparisonPolicy)
        #expect(
            Set(controller.notes.map(\.relativePath)) == [
                "Active.md", "Archive/Aside.md", "Old/Removed.md",
            ])
        guard case .stale(let issue)? = controller.derivedRefreshStatus else {
            Issue.record("The source-ahead Folder claim was not marked stale.")
            return
        }
        #expect(issue.affectedVaultIDs == [fixture.vault.id])
    }

    @Test("A committed Folder move relocates exact sources and directory inventory")
    func committedFolderMoveUpdatesCachedHierarchy() throws {
        let fixture = try Fixture()
        let sourceFolder = try VaultRelativeFolderPath("Source")
        let targetFolder = try VaultRelativeFolderPath("Target")
        let initial = fixture.snapshot(
            activeSource: "# Active\n",
            activePath: "Source/Active.md",
            folders: [sourceFolder, targetFolder],
            searchSequence: 1
        )
        let controller = WindowWorkspaceProjectionController {
            initial.discovery.catalog
        }
        _ = controller.activate(
            snapshot: initial,
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(sourceScope: .library)
        )
        let source = try #require(
            controller.cachedNote(
                vaultID: fixture.vault.id,
                relativePath: "Source/Active.md"
            ))
        let destinationID = VaultQualifiedNoteID(
            vaultID: fixture.vault.id,
            relativePath: "Target/Source/Active.md"
        )
        let destinationDocument = NoteDocument(
            relativePath: destinationID.relativePath,
            rawContent: "# Active\n"
        )
        let commit = FolderMoveCommit(
            vaultID: fixture.vault.id,
            sourceFolder: sourceFolder,
            destinationFolder: try VaultRelativeFolderPath("Target/Source"),
            graphGeneration: 1,
            noteMoves: [
                FolderNoteMoveCommit(
                    stableNoteID: fixture.activeNoteID,
                    source: source.id,
                    destination: destinationID,
                    previousRevision: source.fingerprint,
                    committedRevision: destinationDocument.fingerprint,
                    committedRawContent: destinationDocument.rawContent
                )
            ],
            rewrites: []
        )

        let projection = controller.recordCommittedFolderMove(
            commit,
            visibleVaultID: fixture.vault.id,
            visibleSourceScope: .library
        )

        #expect(projection?.notes.map(\.id).contains(destinationID) == true)
        #expect(
            controller.cachedNote(
                vaultID: fixture.vault.id,
                relativePath: source.id.relativePath
            ) == nil)
        #expect(
            controller.cachedNote(
                vaultID: fixture.vault.id,
                relativePath: destinationID.relativePath
            )?.derivedProjectionState == .sourceAhead)
        #expect(
            Set(controller.notes.map(\.relativePath)) == [
                destinationID.relativePath, "Archive/Aside.md", "Old/Removed.md",
            ])
        #expect(
            controller.vaultSnapshot(id: fixture.vault.id)?.folders.map(\.rawValue)
                == ["Target", "Target/Source"])
        #expect(
            controller.vaultSnapshot(
                id: fixture.vault.id
            )?.pathComparisonPolicy == fixture.pathComparisonPolicy)
        guard case .stale(let issue)? = controller.derivedRefreshStatus else {
            Issue.record("The source-ahead Folder move claimed current derived state.")
            return
        }
        #expect(issue.affectedVaultIDs == [fixture.vault.id])
    }

    @Test("An ordinary move relocates the selected source before derived refresh")
    func committedOrdinaryMoveUpdatesActiveProjection() throws {
        let fixture = try Fixture()
        let initial = fixture.snapshot(activeSource: "# Active\n", searchSequence: 1)
        let controller = WindowWorkspaceProjectionController {
            initial.discovery.catalog
        }
        _ = controller.activate(
            snapshot: initial,
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(sourceScope: .library)
        )
        let source = try #require(
            controller.cachedNote(vaultID: fixture.vault.id, relativePath: "Active.md")
        )
        let destination = VaultQualifiedNoteID(
            vaultID: fixture.vault.id,
            relativePath: "Arguments/Active.md"
        )
        let commit = TriptychMoveCommit(
            movedNote: source.id,
            destination: destination,
            previousRevision: source.fingerprint,
            committedRevision: source.fingerprint,
            graphGeneration: 1,
            rewrites: []
        )

        let projection = controller.recordCommittedNoteMove(
            commit,
            stableIdentity: source.stableIdentity,
            visibleVaultID: fixture.vault.id,
            visibleSourceScope: .library
        )

        #expect(projection?.note.id == destination)
        #expect(projection?.note.derivedProjectionState == .sourceAhead)
        #expect(
            Set(controller.notes.map(\.relativePath)) == [
                destination.relativePath, "Archive/Aside.md", "Old/Removed.md",
            ])
        #expect(
            controller.cachedNote(
                vaultID: fixture.vault.id,
                relativePath: "Active.md"
            ) == nil)
        #expect(
            controller.cachedNote(
                vaultID: fixture.vault.id,
                relativePath: destination.relativePath
            )?.stableIdentity == source.stableIdentity)
        guard case .stale(let issue)? = controller.derivedRefreshStatus else {
            Issue.record("The ordinary source-ahead move claimed current derived state.")
            return
        }
        #expect(issue.affectedVaultIDs == [fixture.vault.id])
    }

    @Test("Catalog refresh coalesces without cancelling an acquired load")
    func catalogRefreshCoalescesWithoutCancellingLoad() async throws {
        let fixture = try Fixture()
        let first = fixture.snapshot(activeSource: "# First\n", searchSequence: 1)
        let second = fixture.snapshot(activeSource: "# Second\n", searchSequence: 2)
        let probe = CatalogLoadProbe()
        let controller = WindowWorkspaceProjectionController(
            catalogRefreshDelay: .zero,
            sleep: { _ in },
            loadCatalog: { await probe.load() }
        )

        controller.scheduleCatalogRefresh()
        await waitUntil { probe.callCount == 1 }
        #expect(controller.isRefreshingCatalog)

        controller.scheduleCatalogRefresh()
        await Task.yield()
        probe.resumeNext(with: first.discovery.catalog)
        await waitUntil { probe.callCount == 2 }

        #expect(probe.cancelledLoadCount == 0)
        let firstActive = controller.catalog?.notes.first {
            $0.reference.relativePath == "Active.md"
        }
        #expect(firstActive?.title == "Active")
        #expect(firstActive?.fingerprint == DocumentFingerprint(content: "# First\n"))

        probe.resumeNext(with: second.discovery.catalog)
        await waitUntil { !controller.isRefreshingCatalog }

        #expect(probe.callCount == 2)
        #expect(probe.cancelledLoadCount == 0)
        let secondActive = controller.catalog?.notes.first {
            $0.reference.relativePath == "Active.md"
        }
        #expect(secondActive?.title == "Active")
        #expect(secondActive?.fingerprint == DocumentFingerprint(content: "# Second\n"))
    }

    @Test("A late catalog load cannot overwrite a newer Workspace event")
    func lateCatalogLoadCannotOverwriteWorkspaceEvent() async throws {
        let fixture = try Fixture()
        let initial = fixture.snapshot(activeSource: "# Initial\n", searchSequence: 1)
        let loaded = fixture.snapshot(activeSource: "# Loaded Old\n", searchSequence: 2)
        let eventSnapshot = fixture.snapshot(activeSource: "# Event New\n", searchSequence: 3)
        let probe = CatalogLoadProbe()
        let controller = WindowWorkspaceProjectionController(
            catalogRefreshDelay: .zero,
            sleep: { _ in },
            loadCatalog: { await probe.load() }
        )
        _ = controller.activate(
            snapshot: initial,
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(sourceScope: .library)
        )

        controller.scheduleCatalogRefresh()
        await waitUntil { probe.callCount == 1 }
        #expect(controller.isRefreshingCatalog)

        _ = controller.receive(
            .snapshot(
                WorkspaceSnapshotEvent(
                    generation: 1,
                    snapshot: eventSnapshot
                )),
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(sourceScope: .library)
        )
        probe.resumeNext(with: loaded.discovery.catalog)
        await waitUntil { probe.completedCallCount == 1 }

        #expect(!controller.isRefreshingCatalog)
        #expect(controller.searchGeneration?.sequence == 3)
        let eventActive = controller.catalog?.notes.first {
            $0.reference.relativePath == "Active.md"
        }
        #expect(eventActive?.title == "Active")
        #expect(eventActive?.fingerprint == DocumentFingerprint(content: "# Event New\n"))
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }

    private struct Fixture {
        let vault: RegisteredVault
        let triptych: ScholiumTriptych
        let runtimeIdentity: TriptychRuntimeIdentity
        let activeNoteID = UUID()
        let pathComparisonPolicy = VaultPathComparisonPolicy(
            caseSensitive: true,
            normalizationSensitive: true
        )

        init() throws {
            let analysesID = UUID()
            let topicsID = UUID()
            let worksID = UUID()
            vault = RegisteredVault(
                id: analysesID,
                name: "Analyses",
                role: .sourceCorpus,
                canonicalPath: "/fixtures/Analyses"
            )
            triptych = ScholiumTriptych(
                name: "Projection Fixture",
                paperAnalysisVaultID: analysesID,
                topicKnowledgeVaultID: topicsID,
                outputVaultID: worksID
            )
            runtimeIdentity = TriptychRuntimeIdentity(
                triptychID: triptych.id,
                activationID: UUID()
            )
        }

        func context(
            sourceScope: LibrarySourceScope,
            selectedDocumentPath: String? = nil,
            retainedDeletedDocumentPath: String? = nil
        ) -> WindowWorkspaceProjectionContext {
            WindowWorkspaceProjectionContext(
                selectedVaultID: vault.id,
                sourceScope: sourceScope,
                currentDocumentVaultID: selectedDocumentPath == nil ? nil : vault.id,
                selectedDocumentPath: selectedDocumentPath,
                retainedDeletedDocumentPath: retainedDeletedDocumentPath
            )
        }

        func snapshot(
            activeSource: String?,
            activePath: String = "Active.md",
            folders: [VaultRelativeFolderPath] = [],
            additionalNotes: [WorkspaceNoteSnapshot] = [],
            searchSequence: Int,
            phase: WorkspaceSnapshotPhase = .complete
        ) -> WorkspaceSnapshot {
            var documents: [WorkspaceNoteSnapshot] = []
            if let activeSource {
                documents.append(
                    note(
                        path: activePath,
                        source: activeSource,
                        stableID: activeNoteID
                    ))
            }
            documents.append(
                note(
                    path: "Archive/Aside.md",
                    source: "# Aside\n",
                    stableID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
                ))
            documents.append(
                note(
                    path: "Old/Removed.md",
                    source: "# Removed\n",
                    stableID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
                ))
            documents.append(contentsOf: additionalNotes)
            let vaultSnapshot = WorkspaceVaultSnapshot(
                slot: .paperAnalysis,
                vault: vault,
                pathComparisonPolicy: pathComparisonPolicy,
                documents: documents.map(\.summary),
                folders: folders,
                identityRecovery: NoteIdentityRecoveryState(
                    identities: [:],
                    ambiguities: [],
                    pendingRebindings: [],
                    failures: []
                )
            )
            let catalog = WorkspaceCatalogBuilder.build(
                vaults: [vault],
                documents: [vault.id: documents.map(\.document)]
            )
            return WorkspaceSnapshot(
                triptych: triptych,
                mode: .live,
                phase: phase,
                generatedAt: Date(),
                vaults: [vaultSnapshot],
                discovery: WorkspaceDiscoverySnapshot(
                    catalog: catalog,
                    searchGeneration: phase.isComplete
                        ? SearchGenerationID(
                            triptychID: triptych.id,
                            sequence: searchSequence,
                            sourceManifestHash: "manifest-\(searchSequence)"
                        )
                        : nil
                ),
                research: WorkspaceResearchSnapshot(healthIssues: []),
                sourceInventoryRevision: UInt64(searchSequence)
            )
        }

        func note(
            path: String,
            source: String,
            stableID: UUID
        ) -> WorkspaceNoteSnapshot {
            let document = NoteDocument(relativePath: path, rawContent: source)
            return WorkspaceNoteSnapshot(
                id: VaultQualifiedNoteID(vaultID: vault.id, relativePath: path),
                vaultRole: vault.role,
                stableIdentity: .resolved(stableID),
                document: document,
                fileMetadata: WorkspaceFileMetadata(
                    byteCount: document.sourceBytes.count,
                    creationDate: nil,
                    modificationDate: nil
                ),
                graphCounts: WorkspaceGraphCounts(
                    incoming: 0,
                    outgoing: 0,
                    broken: 0,
                    ambiguous: 0
                ),
            )
        }
    }
}
