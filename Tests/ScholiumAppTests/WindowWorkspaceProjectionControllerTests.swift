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

    @Test("One event commits a coherent Location projection")
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
            context: fixture.context(location: .setAside)
        )

        #expect(controller.notes.map(\.relativePath) == ["Set Aside/Aside.md"])
        #expect(Set(controller.documentRevisions.keys) == ["Set Aside/Aside.md"])
        #expect(controller.vaultSnapshotsByID[fixture.vault.id]?.documents.count == 3)
        #expect(controller.catalog?.notes.count == 3)
        #expect(
            controller.relationshipGraph?.generation
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
            context: fixture.context(location: .workspace)
        )
        #expect(openingCommit.snapshotPhase == .opening(
            availableVault: .paperAnalysis
        ))
        #expect(controller.snapshotPhase == openingCommit.snapshotPhase)
        #expect(controller.notes.map(\.relativePath) == ["Active.md"])
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
            context: fixture.context(location: .workspace)
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
            context: fixture.context(location: .workspace)
        )

        let stale = fixture.snapshot(activeSource: "# Stale\n", searchSequence: 4)
        let staleEvent = WorkspaceEvent.snapshot(WorkspaceSnapshotEvent(
            generation: 4,
            snapshot: stale
        ))
        #expect(!controller.canReceive(
            staleEvent,
            runtimeIdentity: fixture.runtimeIdentity
        ))
        #expect(controller.receive(
            staleEvent,
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(location: .workspace)
        ) == nil)
        #expect(controller.notes.first?.rawContent == "# Generation 5\n")

        let foreign = TriptychRuntimeIdentity(
            triptychID: fixture.triptych.id,
            activationID: UUID()
        )
        let newer = fixture.snapshot(activeSource: "# Foreign\n", searchSequence: 6)
        #expect(!controller.canReceive(
            .snapshot(WorkspaceSnapshotEvent(generation: 6, snapshot: newer)),
            runtimeIdentity: foreign
        ))
        #expect(controller.receive(
            .snapshot(WorkspaceSnapshotEvent(generation: 6, snapshot: newer)),
            runtimeIdentity: foreign,
            context: fixture.context(location: .workspace)
        ) == nil)
        #expect(controller.notes.first?.rawContent == "# Generation 5\n")

        let configurationOnly = WorkspaceResearchConfigurationInvalidatedEvent(
            generation: 6,
            snapshot: newer
        )
        #expect(controller.receive(
            .researchConfigurationInvalidated(configurationOnly),
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(location: .workspace)
        ) == nil)
        #expect(controller.notes.first?.rawContent == "# Generation 5\n")

        let sameGeneration = fixture.snapshot(
            activeSource: "# Same Generation\n",
            searchSequence: 6
        )
        #expect(controller.receive(
            .snapshot(WorkspaceSnapshotEvent(generation: 6, snapshot: sameGeneration)),
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(location: .workspace)
        ) == nil)

        let accepted = fixture.snapshot(activeSource: "# Generation 7\n", searchSequence: 7)
        let commit = controller.receive(
            .snapshot(WorkspaceSnapshotEvent(generation: 7, snapshot: accepted)),
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(location: .workspace)
        )
        #expect(commit?.searchGenerationChanged == true)
        #expect(controller.notes.first?.rawContent == "# Generation 7\n")
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
                location: .workspace,
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
                location: .workspace,
                selectedDocumentPath: "Active.md",
                retainedDeletedDocumentPath: "Active.md"
            )
        )

        #expect(commit?.retainedDeletedDocumentPath == "Active.md")
        #expect(controller.notes.map(\.relativePath) == ["Active.md"])
        #expect(controller.documentRevisions["Active.md"] != nil)

        _ = controller.receive(
            .snapshot(WorkspaceSnapshotEvent(generation: 2, snapshot: removed)),
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(
                location: .workspace,
                selectedDocumentPath: "Active.md",
                retainedDeletedDocumentPath: nil
            )
        )
        #expect(controller.notes.isEmpty)
        #expect(controller.documentRevisions.isEmpty)
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
            context: fixture.context(location: .workspace)
        )
        let replacement = fixture.note(
            path: "Active.md",
            source: "---\ntags: [updated]\nauthors:\n  - family: Arendt\npublication_date: \"2024\"\n---\n# After\n",
            lifecycle: .active,
            stableID: fixture.activeNoteID
        )

        let vault = controller.recordCommittedNote(
            replacement,
            visibleVaultID: fixture.vault.id,
            visibleLocationScope: .workspace
        )

        #expect(vault?.id == fixture.vault.id)
        #expect(controller.notes.first?.rawContent.contains("# After") == true)
        #expect(controller.tags == ["updated"])
        #expect(controller.authors == ["Arendt"])
        #expect(controller.documentRevisions["Active.md"] == replacement.fingerprint)
        #expect(controller.vaultSnapshot(
            id: fixture.vault.id
        )?.pathComparisonPolicy == fixture.pathComparisonPolicy)
        #expect(controller.vaultSnapshotsByID[fixture.vault.id]?.documents.first {
            $0.id.relativePath == "Active.md"
        }?.fingerprint == replacement.fingerprint)

        let cachedVault = try #require(controller.vaultSnapshot(id: fixture.vault.id))
        let aside = cachedVault.documents
            .filter { $0.lifecycle == .setAside }
            .map(WindowDocumentLocation.workspace)
        controller.commitVaultSelection(snapshot: cachedVault, notes: aside)
        _ = controller.recordCommittedNote(
            replacement,
            visibleVaultID: fixture.vault.id,
            visibleLocationScope: .setAside
        )
        #expect(controller.notes.map(\.relativePath) == ["Set Aside/Aside.md"])
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
            lifecycle: .active,
            stableID: replacementID
        )
        let movedOriginal = fixture.note(
            path: "Archive/Active.md",
            source: "# Original\n",
            lifecycle: .active,
            stableID: fixture.activeNoteID
        )
        controller.replaceVaultSnapshots([WorkspaceVaultSnapshot(
            slot: .paperAnalysis,
            vault: fixture.vault,
            pathComparisonPolicy: fixture.pathComparisonPolicy,
            documents: [replacementAtOldPath, movedOriginal],
            identityRecovery: NoteIdentityRecoveryState(
                identities: [:],
                ambiguities: [],
                pendingRebindings: [],
                failures: []
            )
        )])

        let resolved = controller.cachedNote(
            vaultID: fixture.vault.id,
            stableNoteID: fixture.activeNoteID,
            relativePath: "Active.md"
        )
        #expect(resolved?.id.relativePath == "Archive/Active.md")
        #expect(resolved?.stableIdentity.resolvedID == fixture.activeNoteID)
        #expect(controller.cachedNote(
            vaultID: fixture.vault.id,
            stableNoteID: UUID(),
            relativePath: "Active.md"
        ) == nil)
        #expect(controller.cachedNote(
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
            context: fixture.context(location: .workspace)
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
            document: document
        )

        _ = controller.recordCommittedNote(
            commit.sourceAheadSnapshot,
            visibleVaultID: fixture.vault.id,
            visibleLocationScope: .workspace
        )

        let visible = try #require(controller.notes.first {
            $0.relativePath == "Untitled.md"
        })
        #expect(visible.rawContent.isEmpty)
        #expect(visible.workspaceSnapshot?.derivedProjectionState == .sourceAhead)
        guard case .stale(let issue)? = controller.derivedRefreshStatus else {
            Issue.record("The source-ahead window overlay claimed current derived state.")
            return
        }
        #expect(issue.affectedVaultIDs == [fixture.vault.id])
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
            context: fixture.context(location: .workspace)
        )
        let folder = try VaultRelativeFolderPath("Arguments/New Folder")

        let vault = controller.recordCommittedFolder(folder, vaultID: fixture.vault.id)
        _ = controller.recordCommittedFolder(folder, vaultID: fixture.vault.id)

        #expect(vault?.id == fixture.vault.id)
        #expect(controller.vaultSnapshot(id: fixture.vault.id)?.folders == [folder])
        #expect(controller.vaultSnapshot(
            id: fixture.vault.id
        )?.pathComparisonPolicy == fixture.pathComparisonPolicy)
        #expect(controller.notes.map(\.relativePath) == ["Active.md"])
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
            context: fixture.context(location: .workspace)
        )
        let source = try #require(controller.cachedNote(
            vaultID: fixture.vault.id,
            relativePath: "Source/Active.md"
        ))
        let destinationID = VaultQualifiedNoteID(
            vaultID: fixture.vault.id,
            relativePath: "Target/Source/Active.md"
        )
        let destinationDocument = NoteDocument(
            relativePath: destinationID.relativePath,
            rawContent: source.document.rawContent
        )
        let commit = FolderMoveCommit(
            vaultID: fixture.vault.id,
            sourceFolder: sourceFolder,
            destinationFolder: try VaultRelativeFolderPath("Target/Source"),
            graphGeneration: 1,
            noteMoves: [FolderNoteMoveCommit(
                stableNoteID: fixture.activeNoteID,
                source: source.id,
                destination: destinationID,
                previousRevision: source.fingerprint,
                committedRevision: destinationDocument.fingerprint,
                committedRawContent: destinationDocument.rawContent
            )],
            rewrites: []
        )

        let projection = controller.recordCommittedFolderMove(
            commit,
            visibleVaultID: fixture.vault.id,
            visibleLocationScope: .workspace
        )

        #expect(projection?.notes.map(\.id) == [destinationID])
        #expect(controller.cachedNote(
            vaultID: fixture.vault.id,
            relativePath: source.id.relativePath
        ) == nil)
        #expect(controller.cachedNote(
            vaultID: fixture.vault.id,
            relativePath: destinationID.relativePath
        )?.derivedProjectionState == .sourceAhead)
        #expect(controller.notes.map(\.relativePath) == [destinationID.relativePath])
        #expect(controller.vaultSnapshot(id: fixture.vault.id)?.folders.map(\.rawValue)
            == ["Target", "Target/Source"])
        #expect(controller.vaultSnapshot(
            id: fixture.vault.id
        )?.pathComparisonPolicy == fixture.pathComparisonPolicy)
        guard case .stale(let issue)? = controller.derivedRefreshStatus else {
            Issue.record("The source-ahead Folder move claimed current derived state.")
            return
        }
        #expect(issue.affectedVaultIDs == [fixture.vault.id])
    }

    @Test("A lifecycle commit relocates exact source and updates the visible category")
    func committedLifecycleMoveUpdatesCategoryProjection() throws {
        let fixture = try Fixture()
        let initial = fixture.snapshot(activeSource: "# Active\n", searchSequence: 1)
        let controller = WindowWorkspaceProjectionController {
            initial.discovery.catalog
        }
        _ = controller.activate(
            snapshot: initial,
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(location: .workspace)
        )
        let source = try #require(
            controller.cachedNote(vaultID: fixture.vault.id, relativePath: "Active.md")
        )
        let destination = VaultQualifiedNoteID(
            vaultID: fixture.vault.id,
            relativePath: "Set Aside/Active.md"
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
            visibleLocationScope: .workspace
        )

        #expect(projection?.note.id == destination)
        #expect(projection?.note.document.rawContent == source.document.rawContent)
        #expect(projection?.note.lifecycle == .setAside)
        #expect(projection?.note.derivedProjectionState == .sourceAhead)
        #expect(controller.notes.isEmpty)
        #expect(controller.cachedNote(
            vaultID: fixture.vault.id,
            relativePath: destination.relativePath
        )?.stableIdentity == source.stableIdentity)
        #expect(controller.vaultSnapshot(
            id: fixture.vault.id
        )?.pathComparisonPolicy == fixture.pathComparisonPolicy)

        let cachedVault = try #require(controller.vaultSnapshot(id: fixture.vault.id))
        controller.commitVaultSelection(
            snapshot: cachedVault,
            notes: cachedVault.documents
                .filter { $0.lifecycle == .setAside }
                .map(WindowDocumentLocation.workspace)
        )
        #expect(controller.notes.map(\.relativePath) == [
            "Set Aside/Active.md",
            "Set Aside/Aside.md",
        ])
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
            context: fixture.context(location: .workspace)
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
            visibleLocationScope: .workspace
        )

        #expect(projection?.note.id == destination)
        #expect(projection?.note.derivedProjectionState == .sourceAhead)
        #expect(controller.notes.map(\.relativePath) == [destination.relativePath])
        #expect(controller.cachedNote(
            vaultID: fixture.vault.id,
            relativePath: "Active.md"
        ) == nil)
        #expect(controller.cachedNote(
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
        #expect(controller.catalog?.notes.first {
            $0.reference.relativePath == "Active.md"
        }?.title == "First")

        probe.resumeNext(with: second.discovery.catalog)
        await waitUntil { !controller.isRefreshingCatalog }

        #expect(probe.callCount == 2)
        #expect(probe.cancelledLoadCount == 0)
        #expect(controller.catalog?.notes.first {
            $0.reference.relativePath == "Active.md"
        }?.title == "Second")
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
            context: fixture.context(location: .workspace)
        )

        controller.scheduleCatalogRefresh()
        await waitUntil { probe.callCount == 1 }
        #expect(controller.isRefreshingCatalog)

        _ = controller.receive(
            .snapshot(WorkspaceSnapshotEvent(
                generation: 1,
                snapshot: eventSnapshot
            )),
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(location: .workspace)
        )
        probe.resumeNext(with: loaded.discovery.catalog)
        await waitUntil { probe.completedCallCount == 1 }

        #expect(!controller.isRefreshingCatalog)
        #expect(controller.searchGeneration?.sequence == 3)
        #expect(controller.catalog?.notes.first {
            $0.reference.relativePath == "Active.md"
        }?.title == "Event New")
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
            location: NoteLocationScope,
            selectedDocumentPath: String? = nil,
            retainedDeletedDocumentPath: String? = nil
        ) -> WindowWorkspaceProjectionContext {
            WindowWorkspaceProjectionContext(
                selectedVaultID: vault.id,
                locationScope: location,
                currentDocumentVaultID: selectedDocumentPath == nil ? nil : vault.id,
                selectedDocumentPath: selectedDocumentPath,
                retainedDeletedDocumentPath: retainedDeletedDocumentPath
            )
        }

        func snapshot(
            activeSource: String?,
            activePath: String = "Active.md",
            folders: [VaultRelativeFolderPath] = [],
            searchSequence: Int,
            phase: WorkspaceSnapshotPhase = .complete
        ) -> WorkspaceSnapshot {
            var documents: [WorkspaceNoteSnapshot] = []
            if let activeSource {
                documents.append(note(
                    path: activePath,
                    source: activeSource,
                    lifecycle: .active,
                    stableID: activeNoteID
                ))
            }
            documents.append(note(
                path: "Set Aside/Aside.md",
                source: "# Aside\n",
                lifecycle: .setAside,
                stableID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            ))
            documents.append(note(
                path: "Trash/Trash.md",
                source: "# Trash\n",
                lifecycle: .trash,
                stableID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
            ))
            let vaultSnapshot = WorkspaceVaultSnapshot(
                slot: .paperAnalysis,
                vault: vault,
                pathComparisonPolicy: pathComparisonPolicy,
                documents: documents,
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
                research: WorkspaceResearchSnapshot(
                    critiques: [],
                    healthIssues: []
                )
            )
        }

        func note(
            path: String,
            source: String,
            lifecycle: WorkspaceDocumentLifecycle,
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
                lifecycle: lifecycle,
                graphCounts: WorkspaceGraphCounts(
                    incoming: 0,
                    outgoing: 0,
                    broken: 0,
                    ambiguous: 0
                )
            )
        }
    }
}
