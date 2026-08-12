import Combine
import Foundation
import ScholiumContracts

struct WindowPropertyFilterOptions: Equatable {
    let keys: [String]
    let valuesByKey: [String: [String]]

    init(notes: [WindowDocumentLocation]) {
        var accumulated: [String: Set<String>] = [:]
        for note in notes {
            for (key, values) in note.filterableProperties {
                let usableValues = values.filter { !$0.isEmpty && $0.count <= 80 }
                guard !usableValues.isEmpty else { continue }
                accumulated[key, default: []].formUnion(usableValues)
            }
        }

        keys = accumulated.keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        valuesByKey = accumulated.mapValues { values in
            values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }
}

/// Immutable inputs that select one window's visible projection from the
/// latest Triptych snapshot. Document state is consulted only to preserve a dirty
/// editor whose source disappeared; this controller never owns the buffer.
struct WindowWorkspaceProjectionContext {
    let selectedVaultID: UUID?
    let locationScope: NoteLocationScope
    let currentDocumentVaultID: UUID?
    let selectedDocumentPath: String?
    let retainedDeletedDocumentPath: String?
}

/// One atomic result from accepting a Workspace generation.
struct WindowWorkspaceProjectionCommit {
    let searchGenerationChanged: Bool
    let retainedDeletedDocumentPath: String?
    let snapshotPhase: WorkspaceSnapshotPhase
    let derivedRefreshStatus: WorkspaceDerivedRefreshStatus
}

/// The single per-window owner of immutable Workspace projections and their
/// refresh lifecycle. Application remains authoritative; this controller
/// selects and caches one coherent read model for the exact window.
@MainActor
final class WindowWorkspaceProjectionController: ObservableObject {
    struct CommittedMoveProjection {
        let note: WorkspaceNoteSnapshot
        let vault: RegisteredVault
    }

    struct CommittedFolderMoveProjection {
        let notes: [WorkspaceNoteSnapshot]
        let vault: RegisteredVault
    }

    struct State {
        var catalog: WorkspaceCatalogSnapshot?
        var vaultSnapshotsByID: [UUID: WorkspaceVaultSnapshot] = [:]
        var notes: [WindowDocumentLocation] = []
        var tags: [String] = []
        var authors: [String] = []
        var documentRevisions: [String: DocumentFingerprint] = [:]
        var relationshipGraph: GraphSnapshot?
        var searchGeneration: SearchGenerationID?
        var snapshotPhase: WorkspaceSnapshotPhase?
        var derivedRefreshStatus: WorkspaceDerivedRefreshStatus?
        var propertyFilterOptions = WindowPropertyFilterOptions(notes: [])
        var isRefreshingCatalog = false
        var catalogError: String?
    }

    typealias CatalogLoader = @MainActor () async throws -> WorkspaceCatalogSnapshot
    typealias Sleeper = @MainActor (Duration) async throws -> Void

    @Published private(set) var state = State()

    private let loadCatalog: CatalogLoader
    private let sleep: Sleeper
    private let catalogRefreshDelay: Duration
    private var runtimeIdentity: TriptychRuntimeIdentity?
    private var acceptedGeneration: UInt64?
    private var catalogRevision: UInt64 = 0
    private var catalogRefreshDelayTask: Task<Void, Never>?
    private var catalogNeedsAnotherRefresh = false

    init(
        catalogRefreshDelay: Duration = .milliseconds(500),
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
        loadCatalog: @escaping CatalogLoader
    ) {
        self.catalogRefreshDelay = catalogRefreshDelay
        self.sleep = sleep
        self.loadCatalog = loadCatalog
    }

    deinit {
        catalogRefreshDelayTask?.cancel()
    }

    var catalog: WorkspaceCatalogSnapshot? { state.catalog }
    var vaultSnapshotsByID: [UUID: WorkspaceVaultSnapshot] { state.vaultSnapshotsByID }
    var notes: [WindowDocumentLocation] { state.notes }
    var tags: [String] { state.tags }
    var authors: [String] { state.authors }
    var documentRevisions: [String: DocumentFingerprint] { state.documentRevisions }
    var relationshipGraph: GraphSnapshot? { state.relationshipGraph }
    var searchGeneration: SearchGenerationID? { state.searchGeneration }
    var snapshotPhase: WorkspaceSnapshotPhase? { state.snapshotPhase }
    var derivedRefreshStatus: WorkspaceDerivedRefreshStatus? {
        state.derivedRefreshStatus
    }
    var propertyFilterOptions: WindowPropertyFilterOptions { state.propertyFilterOptions }
    var isRefreshingCatalog: Bool { state.isRefreshingCatalog }
    var catalogError: String? { state.catalogError }

    func activate(
        snapshot: WorkspaceSnapshot,
        runtimeIdentity: TriptychRuntimeIdentity,
        generation: UInt64 = 0,
        context: WindowWorkspaceProjectionContext
    ) -> WindowWorkspaceProjectionCommit {
        if self.runtimeIdentity?.triptychID != runtimeIdentity.triptychID {
            state = State()
        }
        self.runtimeIdentity = runtimeIdentity
        acceptedGeneration = generation
        return commit(
            snapshot: snapshot,
            status: snapshot.phase.isComplete
                ? .current(WorkspaceDerivedRefreshEvidence(snapshot: snapshot))
                : .opening(WorkspaceDerivedRefreshEvidence(snapshot: snapshot)),
            context: context
        )
    }

    /// Accepts only the active runtime and an increasing Application event.
    /// Research-configuration invalidation advances ordering without replaying
    /// an unchanged Workspace projection.
    func canReceive(
        _ event: WorkspaceEvent,
        runtimeIdentity: TriptychRuntimeIdentity
    ) -> Bool {
        self.runtimeIdentity == runtimeIdentity
            && (acceptedGeneration.map { event.generation > $0 } ?? true)
    }

    func receive(
        _ event: WorkspaceEvent,
        runtimeIdentity: TriptychRuntimeIdentity,
        context: WindowWorkspaceProjectionContext
    ) -> WindowWorkspaceProjectionCommit? {
        guard canReceive(event, runtimeIdentity: runtimeIdentity) else {
            return nil
        }
        acceptedGeneration = event.generation
        if case .researchConfigurationInvalidated = event {
            return nil
        }
        return commit(
            snapshot: event.snapshot,
            status: event.derivedRefreshStatus,
            context: context
        )
    }

    /// Installs a caller-authenticated snapshot without advancing the
    /// Application event generation, as used by an explicit retry.
    func replaceSnapshot(
        _ snapshot: WorkspaceSnapshot,
        runtimeIdentity: TriptychRuntimeIdentity,
        status: WorkspaceDerivedRefreshStatus,
        context: WindowWorkspaceProjectionContext
    ) -> WindowWorkspaceProjectionCommit? {
        guard self.runtimeIdentity == runtimeIdentity else { return nil }
        return commit(snapshot: snapshot, status: status, context: context)
    }

    func reset() {
        invalidateCatalogLoad()
        runtimeIdentity = nil
        acceptedGeneration = nil
        state = State()
    }

    func vaultSnapshot(id: UUID) -> WorkspaceVaultSnapshot? {
        state.vaultSnapshotsByID[id]
    }

    /// Resolves by stable identity whenever the caller has one. Path lookup is
    /// reserved for identity-unavailable routes; it must never retarget a
    /// stable session after another Note reuses the former path.
    func cachedNote(
        vaultID: UUID,
        stableNoteID: UUID? = nil,
        relativePath: String
    ) -> WorkspaceNoteSnapshot? {
        guard let documents = state.vaultSnapshotsByID[vaultID]?.documents else {
            return nil
        }
        if let stableNoteID {
            return documents.first {
                $0.stableIdentity.resolvedID == stableNoteID
            }
        }
        return documents.first { $0.id.relativePath == relativePath }
    }

    func replaceVaultSnapshots(_ snapshots: [WorkspaceVaultSnapshot]) {
        var next = state
        next.vaultSnapshotsByID = Dictionary(
            uniqueKeysWithValues: snapshots.map { ($0.vault.id, $0) }
        )
        state = next
    }

    func replaceVaultSnapshot(_ snapshot: WorkspaceVaultSnapshot) {
        var next = state
        next.vaultSnapshotsByID[snapshot.vault.id] = snapshot
        state = next
    }

    /// Commits one fully staged Library destination in a single state write.
    func commitVaultSelection(
        snapshot: WorkspaceVaultSnapshot,
        notes: [WindowDocumentLocation]
    ) {
        var next = state
        next.vaultSnapshotsByID[snapshot.vault.id] = snapshot
        installVisibleNotes(notes, in: &next)
        next.relationshipGraph = next.catalog?.graph
        state = next
    }

    func replaceVisibleNotes(_ notes: [WindowDocumentLocation]) {
        var next = state
        installVisibleNotes(notes, in: &next)
        state = next
    }

    func refreshVisibleNoteSnapshots(
        _ snapshotsByPath: [String: WorkspaceNoteSnapshot]
    ) {
        var next = state
        let refreshed = next.notes.map { location in
            snapshotsByPath[location.relativePath]
                .map(WindowDocumentLocation.workspace) ?? location
        }
        installVisibleNotes(refreshed, in: &next)
        state = next
    }

    /// Updates the cached vault and visible Location as one projection commit.
    /// Returns the vault metadata needed by the Document controller projection.
    func recordCommittedNote(
        _ note: WorkspaceNoteSnapshot,
        visibleVaultID: UUID?,
        visibleLocationScope: NoteLocationScope?
    ) -> RegisteredVault? {
        guard let vaultSnapshot = state.vaultSnapshotsByID[note.id.vaultID] else {
            return nil
        }
        var next = state
        var documents = vaultSnapshot.documents
        if let noteID = note.stableIdentity.resolvedID,
           let index = documents.firstIndex(where: {
               $0.stableIdentity.resolvedID == noteID
           }) {
            documents[index] = note
        } else if let index = documents.firstIndex(where: { $0.id == note.id }) {
            documents[index] = note
        } else {
            documents.append(note)
        }
        next.vaultSnapshotsByID[note.id.vaultID] = WorkspaceVaultSnapshot(
            slot: vaultSnapshot.slot,
            vault: vaultSnapshot.vault,
            pathComparisonPolicy: vaultSnapshot.pathComparisonPolicy,
            documents: documents,
            folders: vaultSnapshot.folders,
            identityRecovery: vaultSnapshot.identityRecovery
        )
        let visibleLifecycle = visibleLocationScope?.documentLifecycle
        if visibleVaultID == note.id.vaultID,
           visibleLifecycle == note.lifecycle {
            let visible = WindowDocumentLocation.workspace(note)
            var notes = next.notes
            if let index = notes.firstIndex(where: {
                $0.relativePath == note.id.relativePath
            }) {
                notes[index] = visible
            } else {
                notes.append(visible)
            }
            installVisibleNotes(notes, in: &next)
            next.documentRevisions[note.id.relativePath] = note.fingerprint
        }
        if note.derivedProjectionState == .sourceAhead {
            markDerivedStateStale(
                reason: "The new note is committed while derived workspace state refreshes.",
                affectedVaultIDs: [note.id.vaultID],
                state: &next
            )
        }
        state = next
        return vaultSnapshot.vault
    }

    /// Installs a durable empty-folder claim without waiting for the complete
    /// Workspace generation that will refresh disposable folder inventory.
    func recordCommittedFolder(
        _ folder: VaultRelativeFolderPath,
        vaultID: UUID
    ) -> RegisteredVault? {
        guard let vaultSnapshot = state.vaultSnapshotsByID[vaultID] else {
            return nil
        }
        var next = state
        var folders = vaultSnapshot.folders
        if !folders.contains(folder) {
            folders.append(folder)
            folders.sort {
                $0.rawValue.localizedStandardCompare($1.rawValue) == .orderedAscending
            }
        }
        next.vaultSnapshotsByID[vaultID] = WorkspaceVaultSnapshot(
            slot: vaultSnapshot.slot,
            vault: vaultSnapshot.vault,
            pathComparisonPolicy: vaultSnapshot.pathComparisonPolicy,
            documents: vaultSnapshot.documents,
            folders: folders,
            identityRecovery: vaultSnapshot.identityRecovery
        )
        markDerivedStateStale(
            reason: "The new folder is committed while derived workspace state refreshes.",
            affectedVaultIDs: [vaultID],
            state: &next
        )
        state = next
        return vaultSnapshot.vault
    }

    /// Relocates every exact source and real directory from one durable Folder
    /// transaction. Graph, Search, and research projections intentionally stay
    /// stale until the matching complete Workspace generation arrives.
    func recordCommittedFolderMove(
        _ commit: FolderMoveCommit,
        visibleVaultID: UUID?,
        visibleLocationScope: NoteLocationScope?
    ) -> CommittedFolderMoveProjection? {
        guard let vaultSnapshot = state.vaultSnapshotsByID[commit.vaultID] else {
            return nil
        }

        var documents = vaultSnapshot.documents
        var projectedNotes: [WorkspaceNoteSnapshot] = []
        for move in commit.noteMoves {
            if let current = documents.first(where: {
                $0.id == move.destination
                    && $0.fingerprint == move.committedRevision
                    && $0.stableIdentity.resolvedID == move.stableNoteID
            }) {
                projectedNotes.append(current)
                continue
            }
            guard let sourceIndex = documents.firstIndex(where: {
                $0.id == move.source
                    && $0.fingerprint == move.previousRevision
                    && $0.stableIdentity.resolvedID == move.stableNoteID
            }) else { return nil }
            let source = documents[sourceIndex]
            let document = NoteDocument(
                relativePath: move.destination.relativePath,
                rawContent: move.committedRawContent
            )
            guard document.fingerprint == move.committedRevision else { return nil }
            let destination = WorkspaceNoteSnapshot(
                id: move.destination,
                vaultRole: source.vaultRole,
                stableIdentity: .resolved(move.stableNoteID),
                document: document,
                fileMetadata: WorkspaceFileMetadata(
                    byteCount: document.sourceBytes.count,
                    creationDate: source.fileMetadata.creationDate,
                    modificationDate: source.fileMetadata.modificationDate
                ),
                lifecycle: WorkspaceDocumentLifecycle(
                    relativePath: move.destination.relativePath
                ),
                graphCounts: source.graphCounts,
                headings: source.headings,
                derivedProjectionState: .sourceAhead,
                cachedTitleProjection: source.cachedTitleProjection
            )
            documents[sourceIndex] = destination
            projectedNotes.append(destination)
        }

        let source = commit.sourceFolder.rawValue
        let sourcePrefix = source + "/"
        let destination = commit.destinationFolder.rawValue
        var folders = vaultSnapshot.folders.map { folder in
            guard folder.rawValue == source || folder.rawValue.hasPrefix(sourcePrefix)
            else { return folder }
            let suffix = folder.rawValue.dropFirst(source.count)
            return (try? VaultRelativeFolderPath(destination + suffix)) ?? folder
        }
        if !folders.contains(commit.destinationFolder) {
            folders.append(commit.destinationFolder)
        }
        folders.sort {
            $0.rawValue.localizedStandardCompare($1.rawValue) == .orderedAscending
        }

        var next = state
        next.vaultSnapshotsByID[commit.vaultID] = WorkspaceVaultSnapshot(
            slot: vaultSnapshot.slot,
            vault: vaultSnapshot.vault,
            pathComparisonPolicy: vaultSnapshot.pathComparisonPolicy,
            documents: documents,
            folders: folders,
            identityRecovery: vaultSnapshot.identityRecovery
        )
        if visibleVaultID == commit.vaultID,
           let visibleLocationScope {
            let lifecycle = visibleLocationScope.documentLifecycle
            installVisibleNotes(
                documents
                    .filter { $0.lifecycle == lifecycle }
                    .map(WindowDocumentLocation.workspace),
                in: &next
            )
        }
        markDerivedStateStale(
            reason: "The folder location is committed while derived workspace state refreshes.",
            affectedVaultIDs: [commit.vaultID],
            state: &next
        )
        state = next
        return CommittedFolderMoveProjection(
            notes: projectedNotes,
            vault: vaultSnapshot.vault
        )
    }

    /// Relocates one already-cached exact source after an ordinary or category
    /// move. The authoritative filesystem transaction has completed; this
    /// source-ahead projection keeps the exact window responsive until the
    /// matching complete Workspace event replaces it.
    func recordCommittedNoteMove(
        _ commit: TriptychMoveCommit,
        stableIdentity: WorkspaceNoteIdentityState,
        visibleVaultID: UUID?,
        visibleLocationScope: NoteLocationScope?
    ) -> CommittedMoveProjection? {
        guard let vaultSnapshot = state.vaultSnapshotsByID[commit.movedNote.vaultID]
        else { return nil }

        if let destination = vaultSnapshot.documents.first(where: {
            $0.id == commit.destination
                && $0.fingerprint == commit.committedRevision
        }) {
            return CommittedMoveProjection(
                note: destination,
                vault: vaultSnapshot.vault
            )
        }

        guard let sourceIndex = vaultSnapshot.documents.firstIndex(where: {
            $0.id == commit.movedNote
        }) else { return nil }
        let source = vaultSnapshot.documents[sourceIndex]
        guard source.fingerprint == commit.previousRevision else { return nil }

        let relocatedDocument = NoteDocument(
            relativePath: commit.destination.relativePath,
            rawContent: source.document.rawContent
        )
        guard relocatedDocument.fingerprint == commit.committedRevision else {
            return nil
        }
        let destination = WorkspaceNoteSnapshot(
            id: commit.destination,
            vaultRole: source.vaultRole,
            stableIdentity: stableIdentity,
            document: relocatedDocument,
            fileMetadata: source.fileMetadata,
            lifecycle: WorkspaceDocumentLifecycle(
                relativePath: commit.destination.relativePath
            ),
            graphCounts: source.graphCounts,
            headings: source.headings,
            derivedProjectionState: .sourceAhead,
            cachedTitleProjection: source.cachedTitleProjection
        )

        var next = state
        var documents = vaultSnapshot.documents
        documents[sourceIndex] = destination
        next.vaultSnapshotsByID[commit.movedNote.vaultID] = WorkspaceVaultSnapshot(
            slot: vaultSnapshot.slot,
            vault: vaultSnapshot.vault,
            pathComparisonPolicy: vaultSnapshot.pathComparisonPolicy,
            documents: documents,
            folders: vaultSnapshot.folders,
            identityRecovery: vaultSnapshot.identityRecovery
        )

        if visibleVaultID == commit.movedNote.vaultID,
           let visibleLocationScope {
            let visibleLifecycle = visibleLocationScope.documentLifecycle
            installVisibleNotes(
                documents
                    .filter { $0.lifecycle == visibleLifecycle }
                    .map(WindowDocumentLocation.workspace),
                in: &next
            )
        }
        markDerivedStateStale(
            reason: "The note location is committed while derived workspace state refreshes.",
            affectedVaultIDs: [commit.movedNote.vaultID],
            state: &next
        )
        state = next
        return CommittedMoveProjection(
            note: destination,
            vault: vaultSnapshot.vault
        )
    }

    func replaceCatalog(_ catalog: WorkspaceCatalogSnapshot) {
        invalidateCatalogLoad()
        var next = state
        next.catalog = catalog
        next.relationshipGraph = catalog.graph
        next.catalogError = nil
        next.isRefreshingCatalog = false
        state = next
    }

    func reportCatalogError(_ message: String?) {
        var next = state
        next.catalogError = message
        state = next
    }

    func refreshCatalog() async {
        guard !state.isRefreshingCatalog else {
            catalogNeedsAnotherRefresh = true
            return
        }
        catalogRefreshDelayTask?.cancel()
        catalogRefreshDelayTask = nil
        catalogNeedsAnotherRefresh = false
        let revision = catalogRevision
        var loading = state
        loading.isRefreshingCatalog = true
        loading.catalogError = nil
        state = loading

        do {
            let catalog = try await loadCatalog()
            guard catalogRevision == revision else { return }
            var complete = state
            complete.catalog = catalog
            complete.relationshipGraph = catalog.graph
            complete.catalogError = nil
            complete.isRefreshingCatalog = false
            state = complete
        } catch {
            guard catalogRevision == revision else { return }
            var failed = state
            failed.catalogError = error.localizedDescription
            failed.isRefreshingCatalog = false
            state = failed
        }
        if catalogNeedsAnotherRefresh {
            scheduleCatalogRefresh()
        }
    }

    func scheduleCatalogRefresh() {
        catalogNeedsAnotherRefresh = true
        catalogRefreshDelayTask?.cancel()
        let sleep = self.sleep
        let delay = catalogRefreshDelay
        catalogRefreshDelayTask = Task { @MainActor [weak self] in
            try? await sleep(delay)
            guard !Task.isCancelled, let self else { return }
            // From this point the task represents acquired load work, not a
            // replaceable debounce wait. A later request may queue one more
            // refresh, but must not cancel this in-flight read.
            self.catalogRefreshDelayTask = nil
            await self.refreshCatalog()
        }
    }

    private func commit(
        snapshot: WorkspaceSnapshot,
        status: WorkspaceDerivedRefreshStatus,
        context: WindowWorkspaceProjectionContext
    ) -> WindowWorkspaceProjectionCommit {
        invalidateCatalogLoad()
        let previousSearchGeneration = state.searchGeneration
        var next = state
        next.catalog = snapshot.discovery.catalog
        next.vaultSnapshotsByID = Dictionary(
            uniqueKeysWithValues: snapshot.vaults.map { ($0.vault.id, $0) }
        )
        next.relationshipGraph = snapshot.discovery.catalog.graph
        next.searchGeneration = snapshot.discovery.searchGeneration
        next.snapshotPhase = snapshot.phase
        next.derivedRefreshStatus = status
        next.catalogError = switch status {
        case .opening, .current: nil
        case .stale(let issue), .failed(let issue): issue.reason
        }
        next.isRefreshingCatalog = false

        var retainedDeletedDocumentPath: String?
        if let vaultID = context.selectedVaultID,
           let vault = snapshot.vault(id: vaultID) {
            let lifecycle = context.locationScope.documentLifecycle
            var notes = vault.documents
                .filter { $0.lifecycle == lifecycle }
                .map(WindowDocumentLocation.workspace)
            if context.locationScope == .workspace,
               context.currentDocumentVaultID == vaultID,
               let selectedPath = context.selectedDocumentPath,
               context.retainedDeletedDocumentPath == selectedPath,
               !notes.contains(where: { $0.relativePath == selectedPath }),
               let retained = state.notes.first(where: {
                   $0.relativePath == selectedPath
                }) {
                notes.append(retained)
                retainedDeletedDocumentPath = selectedPath
            }
            installVisibleNotes(notes, in: &next)
        }
        state = next
        return WindowWorkspaceProjectionCommit(
            searchGenerationChanged: previousSearchGeneration != nil
                && previousSearchGeneration != snapshot.discovery.searchGeneration,
            retainedDeletedDocumentPath: retainedDeletedDocumentPath,
            snapshotPhase: snapshot.phase,
            derivedRefreshStatus: status
        )
    }

    private func installVisibleNotes(
        _ notes: [WindowDocumentLocation],
        in state: inout State
    ) {
        state.notes = notes
        state.tags = notes.orderedTags
        state.authors = Set(notes.flatMap(\.authors)).sorted()
        state.documentRevisions = Dictionary(uniqueKeysWithValues: notes.map {
            ($0.relativePath, $0.document.fingerprint)
        })
        state.propertyFilterOptions = WindowPropertyFilterOptions(notes: notes)
    }

    private func markDerivedStateStale(
        reason: String,
        affectedVaultIDs: Set<UUID>,
        state: inout State
    ) {
        let lastKnownGood: WorkspaceDerivedRefreshEvidence? = switch state.derivedRefreshStatus {
        case .opening(let evidence), .current(let evidence): evidence
        case .stale(let issue), .failed(let issue): issue.lastKnownGood
        case nil: nil
        }
        guard let lastKnownGood else { return }
        state.derivedRefreshStatus = .stale(WorkspaceDerivedRefreshIssue(
            reason: reason,
            affectedVaultIDs: affectedVaultIDs,
            lastKnownGood: lastKnownGood
        ))
    }

    private func invalidateCatalogLoad() {
        catalogRevision &+= 1
        catalogRefreshDelayTask?.cancel()
        catalogRefreshDelayTask = nil
        catalogNeedsAnotherRefresh = false
    }
}
