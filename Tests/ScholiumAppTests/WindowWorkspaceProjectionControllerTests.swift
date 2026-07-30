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
        #expect(commit.retainedDeletedEditorPath == nil)
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
        #expect(controller.receive(
            .snapshot(WorkspaceSnapshotEvent(generation: 4, snapshot: stale)),
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(location: .workspace)
        ) == nil)
        #expect(controller.notes.first?.rawContent == "# Generation 5\n")

        let foreign = TriptychRuntimeIdentity(
            triptychID: fixture.triptych.id,
            activationID: UUID()
        )
        let newer = fixture.snapshot(activeSource: "# Foreign\n", searchSequence: 6)
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
                editingDocumentPath: "Active.md"
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
                editingDocumentPath: "Active.md"
            )
        )

        #expect(commit?.retainedDeletedEditorPath == "Active.md")
        #expect(controller.notes.map(\.relativePath) == ["Active.md"])
        #expect(controller.documentRevisions["Active.md"] != nil)

        _ = controller.receive(
            .snapshot(WorkspaceSnapshotEvent(generation: 2, snapshot: removed)),
            runtimeIdentity: fixture.runtimeIdentity,
            context: fixture.context(
                location: .workspace,
                selectedDocumentPath: "Active.md",
                editingDocumentPath: nil
            )
        )
        #expect(controller.notes.isEmpty)
        #expect(controller.documentRevisions.isEmpty)
    }

    @Test("A committed note updates cache, visible source, tags, and revision atomically")
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
            source: "---\ntags: [updated]\n---\n# After\n",
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
        #expect(controller.documentRevisions["Active.md"] == replacement.fingerprint)
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
            editingDocumentPath: String? = nil
        ) -> WindowWorkspaceProjectionContext {
            WindowWorkspaceProjectionContext(
                selectedVaultID: vault.id,
                locationScope: location,
                currentDocumentVaultID: selectedDocumentPath == nil ? nil : vault.id,
                selectedDocumentPath: selectedDocumentPath,
                editingDocumentPath: editingDocumentPath
            )
        }

        func snapshot(
            activeSource: String?,
            searchSequence: Int
        ) -> WorkspaceSnapshot {
            var documents: [WorkspaceNoteSnapshot] = []
            if let activeSource {
                documents.append(note(
                    path: "Active.md",
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
                documents: documents,
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
                generatedAt: Date(),
                vaults: [vaultSnapshot],
                discovery: WorkspaceDiscoverySnapshot(
                    catalog: catalog,
                    searchGeneration: SearchGenerationID(
                        triptychID: triptych.id,
                        sequence: searchSequence,
                        sourceManifestHash: "manifest-\(searchSequence)"
                    )
                ),
                research: WorkspaceResearchSnapshot(
                    critiques: [],
                    checkpointListing: TriptychCheckpointListing(
                        checkpoints: [],
                        unreadableEntries: []
                    ),
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
