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

/// Immutable inputs that select one window's visible projection from a complete
/// Triptych snapshot. Document state is consulted only to preserve a dirty
/// editor whose source disappeared; this controller never owns the buffer.
struct WindowWorkspaceProjectionContext {
    let selectedVaultID: UUID?
    let locationScope: NoteLocationScope
    let currentDocumentVaultID: UUID?
    let selectedDocumentPath: String?
    let editingDocumentPath: String?
}

/// One atomic result from accepting a complete Workspace generation.
struct WindowWorkspaceProjectionCommit {
    let searchGenerationChanged: Bool
    let retainedDeletedEditorPath: String?
    let derivedRefreshStatus: WorkspaceDerivedRefreshStatus
}

/// The single per-window owner of immutable Workspace projections and their
/// refresh lifecycle. Application remains authoritative; this controller
/// selects and caches one coherent read model for the exact window.
@MainActor
final class WindowWorkspaceProjectionController: ObservableObject {
    struct State {
        var catalog: WorkspaceCatalogSnapshot?
        var vaultSnapshotsByID: [UUID: WorkspaceVaultSnapshot] = [:]
        var notes: [WindowDocumentLocation] = []
        var tags: [String] = []
        var documentRevisions: [String: DocumentFingerprint] = [:]
        var relationshipGraph: GraphSnapshot?
        var searchGeneration: SearchGenerationID?
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
    var documentRevisions: [String: DocumentFingerprint] { state.documentRevisions }
    var relationshipGraph: GraphSnapshot? { state.relationshipGraph }
    var searchGeneration: SearchGenerationID? { state.searchGeneration }
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
            status: .current(WorkspaceDerivedRefreshEvidence(snapshot: snapshot)),
            context: context
        )
    }

    /// Accepts only the active runtime and an increasing Application event.
    /// Research-configuration invalidation advances ordering without replaying
    /// an unchanged Workspace projection.
    func receive(
        _ event: WorkspaceEvent,
        runtimeIdentity: TriptychRuntimeIdentity,
        context: WindowWorkspaceProjectionContext
    ) -> WindowWorkspaceProjectionCommit? {
        guard self.runtimeIdentity == runtimeIdentity,
              acceptedGeneration.map({ event.generation > $0 }) ?? true else {
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

    /// Installs a caller-authenticated complete snapshot without advancing the
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

    func cachedNote(
        vaultID: UUID,
        stableNoteID: UUID? = nil,
        relativePath: String
    ) -> WorkspaceNoteSnapshot? {
        state.vaultSnapshotsByID[vaultID]?.documents.first { note in
            stableNoteID.map { $0 == note.stableIdentity.resolvedID } == true
                || note.id.relativePath == relativePath
        }
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

    func recordPreparedRevision(_ revision: DocumentFingerprint, at path: String) {
        var next = state
        next.documentRevisions[path] = revision
        state = next
    }

    func clearPreparedRevision(at path: String) {
        var next = state
        next.documentRevisions[path] = nil
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
            documents: documents,
            folders: vaultSnapshot.folders,
            identityRecovery: vaultSnapshot.identityRecovery
        )
        let visibleLifecycle: WorkspaceDocumentLifecycle? = switch visibleLocationScope {
        case .workspace: .active
        case .setAside: .setAside
        case .trash: .trash
        case nil: nil
        }
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
        state = next
        return vaultSnapshot.vault
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
        next.derivedRefreshStatus = status
        next.catalogError = switch status {
        case .current: nil
        case .stale(let issue), .failed(let issue): issue.reason
        }
        next.isRefreshingCatalog = false

        var retainedDeletedEditorPath: String?
        if let vaultID = context.selectedVaultID,
           let vault = snapshot.vault(id: vaultID) {
            let lifecycle: WorkspaceDocumentLifecycle = switch context.locationScope {
            case .workspace: .active
            case .setAside: .setAside
            case .trash: .trash
            }
            var notes = vault.documents
                .filter { $0.lifecycle == lifecycle }
                .map(WindowDocumentLocation.workspace)
            if context.locationScope == .workspace,
               context.currentDocumentVaultID == vaultID,
               let selectedPath = context.selectedDocumentPath,
               context.editingDocumentPath == selectedPath,
               !notes.contains(where: { $0.relativePath == selectedPath }),
               let retained = state.notes.first(where: {
                   $0.relativePath == selectedPath
               }) {
                notes.append(retained)
                retainedDeletedEditorPath = selectedPath
            }
            installVisibleNotes(notes, in: &next)
        }
        state = next
        return WindowWorkspaceProjectionCommit(
            searchGenerationChanged: previousSearchGeneration != nil
                && previousSearchGeneration != snapshot.discovery.searchGeneration,
            retainedDeletedEditorPath: retainedDeletedEditorPath,
            derivedRefreshStatus: status
        )
    }

    private func installVisibleNotes(
        _ notes: [WindowDocumentLocation],
        in state: inout State
    ) {
        state.notes = notes
        state.tags = notes.orderedTags
        state.documentRevisions = Dictionary(uniqueKeysWithValues: notes.map {
            ($0.relativePath, DocumentFingerprint(content: $0.rawContent))
        })
        state.propertyFilterOptions = WindowPropertyFilterOptions(notes: notes)
    }

    private func invalidateCatalogLoad() {
        catalogRevision &+= 1
        catalogRefreshDelayTask?.cancel()
        catalogRefreshDelayTask = nil
        catalogNeedsAnotherRefresh = false
    }
}
