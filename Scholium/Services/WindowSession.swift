import Foundation
import Combine
import ScholiumCore

@MainActor
final class WindowSession: ObservableObject, Identifiable {
    let id: UUID
    @Published var snapshot: WindowSessionSnapshot

    init(snapshot: WindowSessionSnapshot = WindowSessionSnapshot()) {
        id = snapshot.id
        self.snapshot = snapshot
    }
}

struct VaultRefreshGeneration: Codable, Hashable, Sendable {
    let vaultID: UUID
    let sequence: UInt64
    let sourceEventSequence: UInt64
    let startedAt: Date
    let completedAt: Date?
}

enum DerivedRefreshState: Codable, Hashable, Sendable {
    case idle
    case refreshing(VaultRefreshGeneration)
    case current(
        generation: VaultRefreshGeneration,
        searchGeneration: IndexGeneration,
        indexWasRecovered: Bool
    )
    case stale(generation: VaultRefreshGeneration, message: String)
    case failed(generation: VaultRefreshGeneration, message: String)
}

struct WorkspaceCommit: Hashable, Sendable {
    let originSessionID: UUID
    let vaultID: UUID
    let relativePath: String
    let revision: DocumentFingerprint
}

struct WorkspaceVaultChange: Sendable {
    let vaultID: UUID
    let event: VaultWatchEvent
    let generation: VaultRefreshGeneration
    let derivedState: DerivedRefreshState
}

@MainActor
private struct WorkspaceEditorFlushRegistration {
    let token: UUID
    let triptychID: UUID
    let windowID: UUID
    let relativePath: String
    let flush: @MainActor () async throws -> Void
}

struct VaultRuntimeUpdate: Sendable {
    let event: VaultWatchEvent
    let generation: VaultRefreshGeneration
    let derivedState: DerivedRefreshState
    let requiresWorkspaceGraphRefresh: Bool
}

private enum WorkspaceGraphApplyOutcome: Equatable, Sendable {
    case applied
    case superseded
}

/// Shared durable services for one Triptych. These actors all point at one
/// canonical persistence location and must not be recreated independently by
/// each window, because concurrent actor instances could otherwise overwrite
/// one another with stale in-memory snapshots.
struct SharedTriptychRuntime {
    let manifest: TriptychManifest
    let controlStore: TriptychControlStore
    let researchSkillStore: ResearchSkillStore
    let humanReviewStore: HumanReviewStore
    let dialogueStore: DialogueStore
    let critiqueRegistry: CritiqueRegistry
    let checkpointStore: TriptychCheckpointStore
    let transactionRecoveryStore: TriptychMutationRecoveryStore
    let identityRecoveryCoordinator: NoteIdentityRecoveryCoordinator
}

/// The read-only boundary exposed to a window after a Triptych has been
/// activated. The value contains references to shared actors and repositories;
/// it does not own their lifetime. Security-scoped access is held by
/// `WorkspaceStore` for the lifetime of the shared runtime rather than being
/// started and stopped by individual windows.
struct WorkspaceAccess {
    let assignment: TriptychAssignment
    let triptychRuntime: SharedTriptychRuntime
    let runtimes: [WorkspaceVaultSlot: SharedVaultRuntime]
    let roots: TriptychRoots
    let repositories: [WorkspaceVaultSlot: VaultRepository]
    let graph: GraphSnapshot?
    let refreshStates: [UUID: DerivedRefreshState]
    let refreshGenerations: [UUID: VaultRefreshGeneration]
}

struct TriptychRuntimeReload {
    let triptychID: UUID
    let runtime: SharedTriptychRuntime
}

/// One shared file/search runtime per registered vault. Windows subscribe to
/// its single FSEvents stream instead of replacing each other's native watcher.
actor SharedVaultRuntime {
    private struct EventSubscriber {
        let token: UUID
        let continuation: AsyncStream<VaultWatchEvent>.Continuation
    }

    private struct UpdateSubscriber {
        let token: UUID
        let continuation: AsyncStream<VaultRuntimeUpdate>.Continuation
    }

    nonisolated let vaultService: VaultService
    nonisolated let searchEngine: SearchEngine
    nonisolated let repository: VaultRepository
    nonisolated let registeredVault: RegisteredVault
    nonisolated let rootURL: URL

    private let applicationSupportURL: URL
    private var watcherTask: Task<Void, Never>?
    private var eventSubscribers: [UUID: EventSubscriber] = [:]
    private var updateSubscribers: [UUID: UpdateSubscriber] = [:]
    private var openWaiters: [CheckedContinuation<(notes: [Note], config: VaultConfig), any Error>] = []
    private var opening = false
    private var opened = false
    private var eventJournal = VaultWatchEventJournal(capacity: 256)
    private var notes: [Note] = []
    private var config: VaultConfig?
    private var refreshSequence: UInt64 = 0
    private var latestSourceEventSequence: UInt64 = 0
    private var derivedState: DerivedRefreshState = .idle
    private var graphRevisions: [String: DocumentFingerprint] = [:]
    private var graphSnapshot: GraphSnapshot?
    private var workspaceGraphApplications = GraphGenerationLedger<UUID>()
    private var workspaceGraphPublications = GraphGenerationLedger<UUID>()

    init(
        repository: VaultRepository,
        registeredVault: RegisteredVault,
        rootURL: URL,
        applicationSupportURL: URL
    ) {
        self.repository = repository
        self.registeredVault = registeredVault
        self.rootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        self.applicationSupportURL = applicationSupportURL
        vaultService = VaultService()
        searchEngine = SearchEngine()
    }

    func openVault(at url: URL, role: VaultRole) async throws -> (notes: [Note], config: VaultConfig) {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.path == rootURL.path,
              role == registeredVault.role else {
            throw WorkspaceRegistryError.vaultIdentityMismatch(
                registeredVault.id,
                rootURL.path,
                canonical.path
            )
        }
        if opened, let config { return (notes, config) }
        if opening {
            return try await withCheckedThrowingContinuation { continuation in
                openWaiters.append(continuation)
            }
        }

        opening = true
        do {
            eventJournal = VaultWatchEventJournal(capacity: eventJournal.capacity)
            let prepared = try await vaultService.prepareForObservation(at: canonical, role: role)
            await startWatcherIfNeeded()
            var inventory = try await vaultService.openVault(at: canonical, role: role).notes

            // The watcher is already live. Always perform at least one post-scan
            // inventory and repeat a bounded number of times if changes arrived
            // during reconciliation. Any remaining activity becomes a subsequent
            // full-reconciliation signal rather than a partial publication.
            var needsPostOpenReconciliation = false
            for pass in 0..<3 {
                if eventJournal.rootChanged {
                    throw WorkspaceRegistryError.vaultAccessUnavailable(rootURL.path)
                }
                inventory = try await vaultService.rescan()
                let queued = eventJournal.drain()
                if queued?.rootChanged == true {
                    throw WorkspaceRegistryError.vaultAccessUnavailable(rootURL.path)
                }
                guard queued == nil else {
                    if pass == 2 { needsPostOpenReconciliation = true }
                    continue
                }
                break
            }
            if needsPostOpenReconciliation {
                eventJournal.append(.reconciliationRequired(sequence: eventJournal.highestSequence))
            }

            notes = inventory.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
            config = prepared
            opened = true
            let initialEvent = VaultWatchEvent.reconciliationRequired(
                sequence: max(latestSourceEventSequence, eventJournal.highestSequence)
            )
            await publishInventory(event: initialEvent)
            for _ in 0..<3 {
                guard let pending = eventJournal.drain() else { break }
                if pending.rootChanged {
                    throw WorkspaceRegistryError.vaultAccessUnavailable(rootURL.path)
                }
                await publishInventory(event: .reconciliationRequired(sequence: pending.sequence))
            }
            opening = false
            if let pending = eventJournal.drain() {
                await handleWatchEvent(.reconciliationRequired(sequence: pending.sequence))
            }
            let result = (notes, prepared)
            let waiters = openWaiters
            openWaiters.removeAll()
            waiters.forEach { $0.resume(returning: result) }
            return result
        } catch {
            opening = false
            opened = false
            watcherTask?.cancel()
            watcherTask = nil
            await vaultService.stopWatching()
            let generation = completing(beginGeneration(sourceEventSequence: latestSourceEventSequence))
            derivedState = .failed(
                generation: generation,
                message: "The vault inventory could not be opened."
            )
            publish(
                event: .reconciliationRequired(sequence: latestSourceEventSequence),
                generation: generation
            )
            let waiters = openWaiters
            openWaiters.removeAll()
            waiters.forEach { $0.resume(throwing: error) }
            throw error
        }
    }

    func events(subscriberID: UUID) -> AsyncStream<VaultWatchEvent> {
        AsyncStream { continuation in
            let token = UUID()
            eventSubscribers[subscriberID]?.continuation.finish()
            eventSubscribers[subscriberID] = EventSubscriber(token: token, continuation: continuation)
            // A late subscriber cannot safely reconstruct prior batches. A
            // complete-reconciliation signal is sufficient and never implies
            // that the last FSEvent was a complete inventory.
            if opened {
                continuation.yield(.reconciliationRequired(sequence: latestSourceEventSequence))
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeEventSubscriber(subscriberID, token: token) }
            }
        }
    }

    func updates(subscriberID: UUID) -> AsyncStream<VaultRuntimeUpdate> {
        AsyncStream { continuation in
            let token = UUID()
            updateSubscribers[subscriberID]?.continuation.finish()
            updateSubscribers[subscriberID] = UpdateSubscriber(token: token, continuation: continuation)
            if opened, let generation = currentGeneration {
                continuation.yield(VaultRuntimeUpdate(
                    event: .reconciliationRequired(sequence: latestSourceEventSequence),
                    generation: generation,
                    derivedState: derivedState,
                    requiresWorkspaceGraphRefresh: true
                ))
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeUpdateSubscriber(subscriberID, token: token) }
            }
        }
    }

    func currentNotes() -> [Note] { notes }

    func currentConfig() -> VaultConfig? { config }

    func currentDerivedState() -> DerivedRefreshState { derivedState }

    func currentGraph() -> GraphSnapshot? { graphSnapshot }

    func currentWorkspaceGraphGeneration(for triptychID: UUID) -> Int? {
        workspaceGraphPublications.latest(for: triptychID)
    }

    func currentSearchIndex() async -> SQLiteSearchIndex? {
        await searchEngine.index()
    }

    func reconcileAfterExternalChange() async {
        await handleWatchEvent(.reconciliationRequired(sequence: latestSourceEventSequence))
    }

    func shutdown() async {
        watcherTask?.cancel()
        watcherTask = nil
        await vaultService.stopWatching()
        eventSubscribers.values.forEach { $0.continuation.finish() }
        updateSubscribers.values.forEach { $0.continuation.finish() }
        eventSubscribers.removeAll()
        updateSubscribers.removeAll()
        opened = false
    }

    func graphDocuments() -> [NoteDocument] {
        notes.map { NoteDocument(relativePath: $0.relativePath, rawContent: $0.rawContent) }
    }

    /// Applies the complete Triptych graph to this vault's graph cache and
    /// lexical rows. This is how a target added in another vault clears a
    /// broken-link bit without changing the source note's fingerprint.
    fileprivate func applyWorkspaceGraph(
        _ graph: GraphSnapshot,
        triptychID: UUID
    ) async throws -> WorkspaceGraphApplyOutcome {
        guard workspaceGraphApplications.accept(graph.generation, for: triptychID) else {
            return .superseded
        }
        let generation = beginGeneration(sourceEventSequence: latestSourceEventSequence)
        derivedState = .refreshing(generation)
        let revisions = Dictionary(uniqueKeysWithValues: graphDocuments().map {
            ($0.relativePath, $0.fingerprint)
        })
        let brokenPaths = Set(graph.diagnostics.compactMap {
            $0.code == .broken && $0.source.vaultID == registeredVault.id
                ? $0.source.relativePath
                : nil
        })
        do {
            let index = try await searchEngine.synchronize(
                notes: notes,
                vault: registeredVault,
                applicationSupportURL: applicationSupportURL,
                brokenLinkPaths: brokenPaths
            )
            guard !Task.isCancelled,
                  workspaceGraphApplications.isCurrent(graph.generation, for: triptychID) else {
                return .superseded
            }
            publishGraph(graph, revisions: revisions)
            _ = workspaceGraphPublications.accept(graph.generation, for: triptychID)
            let finished = completing(generation)
            derivedState = .current(
                generation: finished,
                searchGeneration: index.generation,
                indexWasRecovered: index.disposition == .recoveredAndRebuilt
            )
            publish(
                event: .reconciliationRequired(sequence: latestSourceEventSequence),
                generation: finished,
                notifyEventSubscribers: false,
                requiresWorkspaceGraphRefresh: false
            )
            return .applied
        } catch {
            guard !Task.isCancelled,
                  workspaceGraphApplications.isCurrent(graph.generation, for: triptychID) else {
                return .superseded
            }
            let finished = completing(generation)
            derivedState = .failed(
                generation: finished,
                message: "Triptych graph refresh failed for \(registeredVault.name)."
            )
            publish(
                event: .reconciliationRequired(sequence: latestSourceEventSequence),
                generation: finished,
                notifyEventSubscribers: false,
                requiresWorkspaceGraphRefresh: false
            )
            throw error
        }
    }

    func cachedGraph(for revisions: [String: DocumentFingerprint]) -> GraphSnapshot? {
        guard graphRevisions == revisions else { return nil }
        return graphSnapshot
    }

    func publishGraph(_ snapshot: GraphSnapshot, revisions: [String: DocumentFingerprint]) {
        graphRevisions = revisions
        graphSnapshot = snapshot
    }

    private func startWatcherIfNeeded() async {
        guard watcherTask == nil else { return }
        let stream = await vaultService.watchVault()
        watcherTask = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { break }
                await self?.handleWatchEvent(event)
            }
        }
    }

    private func handleWatchEvent(_ event: VaultWatchEvent) async {
        if opening || !opened {
            eventJournal.append(event)
            return
        }
        let sequenceReset = latestSourceEventSequence > 0
            && event.sequence > 0
            && event.sequence < latestSourceEventSequence
        latestSourceEventSequence = max(latestSourceEventSequence, event.sequence)
        if event.rootChanged {
            let generation = beginGeneration(sourceEventSequence: event.sequence)
            let finished = completing(generation)
            derivedState = .failed(
                generation: finished,
                message: "The vault root moved or became unavailable."
            )
            publish(event: event, generation: finished)
            return
        }
        let effective = sequenceReset
            ? .reconciliationRequired(sequence: latestSourceEventSequence)
            : event
        await publishInventory(event: effective)
    }

    private func publishInventory(event: VaultWatchEvent) async {
        let generation = beginGeneration(sourceEventSequence: event.sequence)
        derivedState = .refreshing(generation)
        do {
            if opened, generation.sequence > 1 {
                notes = try await vaultService.rescan().sorted {
                    $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
                }
            }
            let documents = notes.map {
                NoteDocument(relativePath: $0.relativePath, rawContent: $0.rawContent)
            }
            let revisions = Dictionary(uniqueKeysWithValues: documents.map {
                ($0.relativePath, $0.fingerprint)
            })
            let graph: GraphSnapshot
            if let cached = cachedGraph(for: revisions) {
                graph = cached
            } else {
                graph = Self.buildGraph(
                    generation: Int(clamping: generation.sequence),
                    vaultID: registeredVault.id,
                    documents: documents
                )
                publishGraph(graph, revisions: revisions)
            }
            let brokenPaths = Set(graph.diagnostics.compactMap {
                $0.code == .broken ? $0.source.relativePath : nil
            })
            let index = try await searchEngine.synchronize(
                notes: notes,
                vault: registeredVault,
                applicationSupportURL: applicationSupportURL,
                brokenLinkPaths: brokenPaths
            )
            let finished = completing(generation)
            derivedState = .current(
                generation: finished,
                searchGeneration: index.generation,
                indexWasRecovered: index.disposition == .recoveredAndRebuilt
            )
            publish(event: event, generation: finished)
        } catch {
            let finished = completing(generation)
            // Never include note bytes or query text in this persisted-visible
            // state. The subsystem and vault identity are enough to recover.
            derivedState = .failed(
                generation: finished,
                message: "Search or graph refresh failed for \(registeredVault.name)."
            )
            publish(event: .reconciliationRequired(sequence: event.sequence), generation: finished)
        }
    }

    private var currentGeneration: VaultRefreshGeneration? {
        switch derivedState {
        case .idle: nil
        case .refreshing(let generation): generation
        case .current(let generation, _, _): generation
        case .stale(let generation, _): generation
        case .failed(let generation, _): generation
        }
    }

    private func beginGeneration(sourceEventSequence: UInt64) -> VaultRefreshGeneration {
        refreshSequence += 1
        return VaultRefreshGeneration(
            vaultID: registeredVault.id,
            sequence: refreshSequence,
            sourceEventSequence: sourceEventSequence,
            startedAt: Date(),
            completedAt: nil
        )
    }

    private func completing(_ generation: VaultRefreshGeneration) -> VaultRefreshGeneration {
        VaultRefreshGeneration(
            vaultID: generation.vaultID,
            sequence: generation.sequence,
            sourceEventSequence: generation.sourceEventSequence,
            startedAt: generation.startedAt,
            completedAt: Date()
        )
    }

    private func publish(
        event: VaultWatchEvent,
        generation: VaultRefreshGeneration,
        notifyEventSubscribers: Bool = true,
        requiresWorkspaceGraphRefresh: Bool = true
    ) {
        if notifyEventSubscribers {
            for subscriber in eventSubscribers.values { subscriber.continuation.yield(event) }
        }
        let update = VaultRuntimeUpdate(
            event: event,
            generation: generation,
            derivedState: derivedState,
            requiresWorkspaceGraphRefresh: requiresWorkspaceGraphRefresh
        )
        for subscriber in updateSubscribers.values { subscriber.continuation.yield(update) }
    }

    private func removeEventSubscriber(_ id: UUID, token: UUID) {
        guard eventSubscribers[id]?.token == token else { return }
        eventSubscribers[id] = nil
    }

    private func removeUpdateSubscriber(_ id: UUID, token: UUID) {
        guard updateSubscribers[id]?.token == token else { return }
        updateSubscribers[id] = nil
    }

    private nonisolated static func buildGraph(
        generation: Int,
        vaultID: UUID,
        documents: [NoteDocument]
    ) -> GraphSnapshot {
        let semantics = Dictionary(uniqueKeysWithValues: documents.map { document in
            let id = VaultQualifiedNoteID(vaultID: vaultID, relativePath: document.relativePath)
            return (id, MarkdownSemanticDocument(parsing: document))
        })
        let catalog = documents.map { document in
            let id = VaultQualifiedNoteID(vaultID: vaultID, relativePath: document.relativePath)
            return LinkCatalogNote(vaultID: vaultID, document: document, semantic: semantics[id])
        }
        return LinkGraphBuilder.build(
            generation: generation,
            catalog: catalog,
            documents: semantics
        )
    }
}

private final class VaultSecurityScopeLease: @unchecked Sendable {
    let url: URL
    private let started: Bool

    init(url: URL, started: Bool) {
        self.url = url
        self.started = started
    }

    deinit {
        if started { url.stopAccessingSecurityScopedResource() }
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    let applicationSupportURL: URL
    /// These services are inert pre-activation adapters for window code that
    /// needs a concrete service type before a vault is selected. All active
    /// work is routed to the corresponding `SharedVaultRuntime` below.
    let unconfiguredVaultService = VaultService()
    let unconfiguredSearchEngine = SearchEngine()
    let cssSnippetStore: CSSSnippetStore
    let zoteroBridge: ZoteroBridge
    let identityRegistry: VaultIdentityRegistry
    let portableControlAccessRegistry: PortableControlAccessRegistry
    let workspaceRegistry: WorkspaceRegistry
    let savedSearchStore: SavedSearchStore
    let windowSessionStore: WindowSessionSnapshotStore
    @Published private(set) var latestCommit: WorkspaceCommit?
    @Published private(set) var latestVaultChange: WorkspaceVaultChange?
    @Published private(set) var vaultRefreshStates: [UUID: DerivedRefreshState] = [:]
    @Published private(set) var vaultRefreshGenerations: [UUID: VaultRefreshGeneration] = [:]
    @Published private(set) var triptychGraphs: [UUID: GraphSnapshot] = [:]
    @Published private(set) var latestTriptychRuntimeReload: TriptychRuntimeReload?
    private var vaultRuntimes: [UUID: SharedVaultRuntime] = [:]
    private var vaultRuntimePaths: [UUID: String] = [:]
    private var triptychRuntimes: [UUID: SharedTriptychRuntime] = [:]
    private var vaultWatcherTasks: [UUID: Task<Void, Never>] = [:]
    private var triptychGraphTasks: [UUID: Task<Void, Never>] = [:]
    private var triptychGraphBuildTokens: [UUID: UUID] = [:]
    private var triptychActivationTasks: [UUID: Task<[WorkspaceVaultSlot: SharedVaultRuntime], Error>] = [:]
    private var triptychActivationTokens: [UUID: UUID] = [:]
    private var triptychGraphSequences = GraphGenerationLedger<UUID>()
    private var vaultTriptychIDs: [UUID: Set<UUID>] = [:]
    private var activeTriptychVaultIDs: [UUID: [WorkspaceVaultSlot: UUID]] = [:]
    private var securityScopeLeases: [UUID: VaultSecurityScopeLease] = [:]
    private var portableControlScopeLeases: [String: VaultSecurityScopeLease] = [:]
    private var editorFlushRegistrations: [UUID: WorkspaceEditorFlushRegistration] = [:]

    init() {
        if let isolated = ProcessInfo.processInfo.environment["SCHOLIUM_HOME"], !isolated.isEmpty {
            applicationSupportURL = URL(
                fileURLWithPath: (isolated as NSString).expandingTildeInPath,
                isDirectory: true
            ).appendingPathComponent("ApplicationSupport", isDirectory: true)
        } else {
            applicationSupportURL = (try? ScholiumPaths.sharedApplicationSupportURL())
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("Scholium", isDirectory: true)
        }
        cssSnippetStore = CSSSnippetStore(applicationSupportURL: applicationSupportURL)
        zoteroBridge = ZoteroBridge(applicationSupportURL: applicationSupportURL)
        identityRegistry = VaultIdentityRegistry(applicationSupportURL: applicationSupportURL)
        portableControlAccessRegistry = PortableControlAccessRegistry(
            applicationSupportURL: applicationSupportURL
        )
        let workspaceURL = applicationSupportURL.appendingPathComponent("Workspace", isDirectory: true)
        workspaceRegistry = WorkspaceRegistry(storageURL: workspaceURL)
        savedSearchStore = SavedSearchStore(workspaceStorageURL: workspaceURL)
        windowSessionStore = WindowSessionSnapshotStore(applicationSupportURL: applicationSupportURL)
    }

    func publishCommit(_ commit: WorkspaceCommit) {
        latestCommit = commit
    }

    func registerEditorFlush(
        token: UUID,
        triptychID: UUID,
        windowID: UUID,
        relativePath: String,
        flush: @escaping @MainActor () async throws -> Void
    ) {
        editorFlushRegistrations[token] = WorkspaceEditorFlushRegistration(
            token: token,
            triptychID: triptychID,
            windowID: windowID,
            relativePath: relativePath,
            flush: flush
        )
    }

    func unregisterEditorFlush(token: UUID) {
        editorFlushRegistrations[token] = nil
    }

    /// Returns the complete shared runtime boundary for one active Triptych.
    /// Callers may read through the returned references, but may not create
    /// replacement repositories, indexes, watchers, or security-scope leases.
    func access(for assignment: TriptychAssignment) async throws -> WorkspaceAccess {
        guard let registeredWorks = assignment.vault(for: .output) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        _ = try await accessPortableControlContainer(for: registeredWorks)
        let runtimes = try await activateTriptych(assignment)
        guard let worksRuntime = runtimes[.output],
              let analyses = runtimes[.paperAnalysis]?.rootURL,
              let topics = runtimes[.topicKnowledge]?.rootURL,
              let works = runtimes[.output]?.rootURL else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let vaultIDs = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.compactMap { slot in
            assignment.vault(for: slot).map { (slot, $0.id) }
        })
        let triptychRuntime = try await triptychRuntime(
            triptychID: assignment.id,
            worksVaultURL: worksRuntime.rootURL,
            vaultIDs: vaultIDs
        )
        let roots = TriptychRoots(
            analyses: analyses,
            topics: topics,
            works: works,
            control: await triptychRuntime.controlStore.controlURL
        )
        return WorkspaceAccess(
            assignment: assignment,
            triptychRuntime: triptychRuntime,
            runtimes: runtimes,
            roots: roots,
            repositories: Dictionary(uniqueKeysWithValues: runtimes.map { ($0.key, $0.value.repository) }),
            graph: triptychGraphs[assignment.id],
            refreshStates: vaultRefreshStates,
            refreshGenerations: vaultRefreshGenerations
        )
    }

    /// Before a complete Triptych checkpoint, commit every open editor in
    /// every window for that Triptych. A conflict in any window aborts the
    /// checkpoint so its files and generated prompt cannot omit visible work.
    func flushEditors(in triptychID: UUID) async throws {
        let registrations = editorFlushRegistrations.values
            .filter { $0.triptychID == triptychID }
            .sorted {
                if $0.windowID != $1.windowID {
                    return $0.windowID.uuidString < $1.windowID.uuidString
                }
                return $0.relativePath < $1.relativePath
            }
        for registration in registrations {
            try await registration.flush()
        }
    }

    func vaultRuntime(
        vault: RegisteredVault,
        identity: VaultIdentity,
        url: URL
    ) throws -> SharedVaultRuntime {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        guard vault.id == identity.id,
              vault.canonicalPath == canonical.path,
              identity.canonicalPath == canonical.path else {
            throw WorkspaceRegistryError.vaultIdentityMismatch(
                vault.id,
                vault.canonicalPath,
                canonical.path
            )
        }
        if let existing = vaultRuntimes[vault.id] {
            guard vaultRuntimePaths[vault.id] == canonical.path else {
                throw WorkspaceRegistryError.vaultIdentityMismatch(
                    vault.id,
                    vaultRuntimePaths[vault.id] ?? "unavailable",
                    canonical.path
                )
            }
            return existing
        }
        let repository = try VaultRepository(
            vaultURL: canonical,
            identity: identity,
            applicationSupportURL: applicationSupportURL,
            vaultRole: vault.role
        )
        let runtime = SharedVaultRuntime(
            repository: repository,
            registeredVault: vault,
            rootURL: canonical,
            applicationSupportURL: applicationSupportURL
        )
        vaultRuntimes[vault.id] = runtime
        vaultRuntimePaths[vault.id] = canonical.path
        observeVaultRuntime(runtime, vaultID: vault.id)
        return runtime
    }

    private func observeVaultRuntime(_ runtime: SharedVaultRuntime, vaultID: UUID) {
        guard vaultWatcherTasks[vaultID] == nil else { return }
        let subscriberID = UUID()
        vaultWatcherTasks[vaultID] = Task { [weak self] in
            let updates = await runtime.updates(subscriberID: subscriberID)
            for await update in updates {
                guard !Task.isCancelled, let self else { return }
                self.vaultRefreshStates[vaultID] = update.derivedState
                self.vaultRefreshGenerations[vaultID] = update.generation
                self.latestVaultChange = WorkspaceVaultChange(
                    vaultID: vaultID,
                    event: update.event,
                    generation: update.generation,
                    derivedState: update.derivedState
                )
                if update.requiresWorkspaceGraphRefresh {
                    await self.scheduleGraphRefreshes(containing: vaultID)
                }
            }
        }
    }

    /// Activates all three independently located vaults in one Triptych. Each
    /// runtime, watcher, repository, graph cache, and SQLite authority is reused
    /// by every window until the application releases the WorkspaceStore.
    @discardableResult
    func activateTriptych(
        _ assignment: TriptychAssignment
    ) async throws -> [WorkspaceVaultSlot: SharedVaultRuntime] {
        let signature = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.compactMap { slot in
            assignment.vault(for: slot).map { (slot, $0.id) }
        })
        guard signature.count == WorkspaceVaultSlot.allCases.count else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        if let existing = triptychActivationTasks[assignment.id] {
            return try await existing.value
        }
        let activationToken = UUID()
        let activationTask = Task { @MainActor in
            try await self.performActivateTriptych(
                assignment,
                signature: signature
            )
        }
        triptychActivationTasks[assignment.id] = activationTask
        triptychActivationTokens[assignment.id] = activationToken
        do {
            let result = try await activationTask.value
            if triptychActivationTokens[assignment.id] == activationToken {
                triptychActivationTasks[assignment.id] = nil
                triptychActivationTokens[assignment.id] = nil
            }
            return result
        } catch {
            if triptychActivationTokens[assignment.id] == activationToken {
                triptychActivationTasks[assignment.id] = nil
                triptychActivationTokens[assignment.id] = nil
            }
            throw error
        }
    }

    private func performActivateTriptych(
        _ assignment: TriptychAssignment,
        signature: [WorkspaceVaultSlot: UUID]
    ) async throws -> [WorkspaceVaultSlot: SharedVaultRuntime] {
        let assignmentChanged = activeTriptychVaultIDs[assignment.id] != signature
        if assignmentChanged {
            let oldIDs = activeTriptychVaultIDs[assignment.id].map { Array($0.values) } ?? []
            for oldID in oldIDs {
                vaultTriptychIDs[oldID]?.remove(assignment.id)
            }
            triptychGraphTasks[assignment.id]?.cancel()
            triptychGraphs[assignment.id] = nil
            activeTriptychVaultIDs[assignment.id] = signature
        }
        var result: [WorkspaceVaultSlot: SharedVaultRuntime] = [:]
        for slot in WorkspaceVaultSlot.allCases {
            guard let vault = assignment.vault(for: slot),
                  let identity = await identityRegistry.identity(id: vault.id) else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            let url = try accessURL(for: vault, identity: identity)
            let runtime = try vaultRuntime(vault: vault, identity: identity, url: url)
            vaultTriptychIDs[vault.id, default: []].insert(assignment.id)
            _ = try await runtime.openVault(at: url, role: vault.role)
            result[slot] = runtime
        }
        if assignmentChanged || triptychGraphs[assignment.id] == nil {
            try await ensureTriptychGraph(assignment, runtimes: result)
        }
        await deactivateUnregisteredVaultRuntimes()
        return result
    }

    /// A vault's initial inventory publication and the Triptych graph
    /// publication are both asynchronous. A window may become visible as
    /// soon as its note inventory is available, so activation must close that
    /// gap before returning a shared runtime boundary. A watcher-triggered
    /// graph build can supersede the first attempt; retry the complete build
    /// while keeping the latest graph generation authoritative.
    private func ensureTriptychGraph(
        _ assignment: TriptychAssignment,
        runtimes: [WorkspaceVaultSlot: SharedVaultRuntime]
    ) async throws {
        triptychGraphTasks[assignment.id]?.cancel()
        // Initial runtime updates can race the first graph publication. Do
        // not treat a superseded build as a durable activation failure: wait
        // for the competing task to observe cancellation, then publish a new
        // complete generation. The bounded foreground retry avoids exposing a
        // partially activated workspace in the usual case; a slow graph then
        // continues as recoverable background derived work.
        for _ in 0..<12 {
            let token = UUID()
            triptychGraphBuildTokens[assignment.id] = token
            try await rebuildTriptychGraph(assignment, runtimes: runtimes, token: token)
            if triptychGraphs[assignment.id] != nil {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        // Graph readiness is derived state, not a prerequisite for opening the
        // research workspace. Continue publication in the shared store so a
        // slow index never becomes a modal activation error.
        triptychGraphTasks[assignment.id]?.cancel()
        triptychGraphTasks[assignment.id] = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<40 {
                guard !Task.isCancelled else { return }
                let token = UUID()
                self.triptychGraphBuildTokens[assignment.id] = token
                do {
                    try await self.rebuildTriptychGraph(
                        assignment,
                        runtimes: runtimes,
                        token: token
                    )
                    if self.triptychGraphs[assignment.id] != nil { return }
                } catch {
                    // Per-vault refresh state retains the recoverable failure.
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Returns only complete, activated per-vault indexes. A missing or failed
    /// runtime is an explicit error, never an empty contribution to federation.
    func searchIndexes(
        for assignment: TriptychAssignment
    ) async throws -> [(vault: RegisteredVault, index: SQLiteSearchIndex)] {
        guard let workspaceGraph = triptychGraphs[assignment.id] else {
            throw SearchIndexError.sqlite("The Triptych graph is not ready.")
        }
        var indexes: [(vault: RegisteredVault, index: SQLiteSearchIndex)] = []
        for slot in WorkspaceVaultSlot.allCases {
            guard let vault = assignment.vault(for: slot),
                  let runtime = vaultRuntimes[vault.id],
                  let index = await runtime.currentSearchIndex() else {
                throw SearchIndexError.sqlite(
                      "The \(slot.displayName) index is not ready."
                  )
            }
            switch await runtime.currentDerivedState() {
            case .current:
                break
            case .failed:
                throw SearchIndexError.sqlite(
                    "The \(slot.displayName) index needs recovery."
                )
            case .idle, .refreshing, .stale:
                throw SearchIndexError.sqlite(
                    "The \(slot.displayName) index is refreshing."
                )
            }
            guard await runtime.currentWorkspaceGraphGeneration(for: assignment.id)
                    == workspaceGraph.generation else {
                throw SearchIndexError.sqlite(
                    "The \(slot.displayName) graph and index are refreshing."
                )
            }
            if case .stale = vaultRefreshStates[vault.id] {
                throw SearchIndexError.sqlite(
                    "The \(slot.displayName) index is refreshing."
                )
            }
            if case .failed = vaultRefreshStates[vault.id] {
                throw SearchIndexError.sqlite(
                    "The \(slot.displayName) index needs recovery."
                )
            }
            indexes.append((vault, index))
        }
        return indexes
    }

    func triptychDocuments(
        for assignment: TriptychAssignment
    ) async throws -> [(vault: RegisteredVault, documents: [NoteDocument])] {
        let runtimes = try await activateTriptych(assignment)
        var result: [(vault: RegisteredVault, documents: [NoteDocument])] = []
        for slot in WorkspaceVaultSlot.allCases {
            guard let vault = assignment.vault(for: slot),
                  let runtime = runtimes[slot] else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            result.append((vault, await runtime.graphDocuments()))
        }
        return result
    }

    func triptychGraph(for assignment: TriptychAssignment) async throws -> GraphSnapshot {
        _ = try await activateTriptych(assignment)
        guard let graph = triptychGraphs[assignment.id] else {
            throw SearchIndexError.sqlite("The Triptych graph is not ready.")
        }
        return graph
    }

    func federatedSearch(
        _ query: SearchQuery,
        in assignment: TriptychAssignment,
        limit: Int = 50
    ) async throws -> [SearchHit] {
        _ = try await activateTriptych(assignment)
        let indexes = try await searchIndexes(for: assignment)
        return try await FederatedSearchEngine.search(
            query,
            indexes: indexes,
            limit: limit
        )
    }

    /// A complete checkpoint restore invalidates every vault in the Triptych,
    /// including vaults not selected in any window. Each runtime republishes a
    /// complete generation to all subscribed sessions.
    func reconcileTriptychAfterRestore(_ assignment: TriptychAssignment) async throws {
        let runtimes = try await activateTriptych(assignment)
        for slot in WorkspaceVaultSlot.allCases {
            await runtimes[slot]?.reconcileAfterExternalChange()
        }
        triptychGraphTasks[assignment.id]?.cancel()
        let token = UUID()
        triptychGraphBuildTokens[assignment.id] = token
        try await rebuildTriptychGraph(assignment, runtimes: runtimes, token: token)
    }

    private func scheduleGraphRefreshes(containing vaultID: UUID) async {
        for triptychID in vaultTriptychIDs[vaultID, default: []] {
            // Initial activation publishes a reconciliation update before the
            // shared Triptych graph has been committed. The activation path is
            // the sole owner of that first build; a watcher-triggered task at
            // this point would cancel it and leave windows without a graph.
            guard triptychGraphs[triptychID] != nil else {
                continue
            }
            // Close the reentrancy window before loading the assignment. A
            // federated query must not observe the just-refreshed local index
            // as Triptych-current while the workspace graph is still old.
            if let generation = vaultRefreshGenerations[vaultID] {
                vaultRefreshStates[vaultID] = .stale(
                    generation: generation,
                    message: "Triptych connections are refreshing."
                )
            }
            if let assignment = await workspaceRegistry.triptych(id: triptychID) {
                for vault in assignment.vaults.values {
                    if let generation = vaultRefreshGenerations[vault.id] {
                        vaultRefreshStates[vault.id] = .stale(
                            generation: generation,
                            message: "Triptych connections are refreshing."
                        )
                    }
                }
            }
            triptychGraphTasks[triptychID]?.cancel()
            let token = UUID()
            triptychGraphBuildTokens[triptychID] = token
            triptychGraphTasks[triptychID] = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled, let self,
                      let assignment = await self.workspaceRegistry.triptych(id: triptychID) else { return }
                do {
                    var runtimes: [WorkspaceVaultSlot: SharedVaultRuntime] = [:]
                    for slot in WorkspaceVaultSlot.allCases {
                        guard let vault = assignment.vault(for: slot),
                              let runtime = self.vaultRuntimes[vault.id] else { return }
                        runtimes[slot] = runtime
                    }
                    try await self.rebuildTriptychGraph(
                        assignment,
                        runtimes: runtimes,
                        token: token
                    )
                } catch {
                    // Per-vault refresh states retain the durable failure. The
                    // graph remains at its last complete generation.
                }
            }
        }
    }

    private func rebuildTriptychGraph(
        _ assignment: TriptychAssignment,
        runtimes: [WorkspaceVaultSlot: SharedVaultRuntime],
        token: UUID
    ) async throws {
        var documentsByID: [VaultQualifiedNoteID: MarkdownSemanticDocument] = [:]
        var catalog: [LinkCatalogNote] = []
        for slot in WorkspaceVaultSlot.allCases {
            guard let vault = assignment.vault(for: slot),
                  let runtime = runtimes[slot] else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            for document in await runtime.graphDocuments() {
                let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
                let semantic = MarkdownSemanticDocument(parsing: document)
                documentsByID[id] = semantic
                catalog.append(LinkCatalogNote(vaultID: vault.id, document: document, semantic: semantic))
            }
        }
        guard triptychGraphBuildTokens[assignment.id] == token,
              !Task.isCancelled else {
            return
        }
        // Reserve before the first asynchronous apply. Cancellation consumes
        // this number, so a replacement build always supersedes every vault
        // touched by the canceled build instead of reusing its generation.
        let next = triptychGraphSequences.reserveNext(for: assignment.id)
        let graph = LinkGraphBuilder.build(
            generation: next,
            catalog: catalog,
            documents: documentsByID,
            resolutionScope: .workspace
        )
        for slot in WorkspaceVaultSlot.allCases {
            guard triptychGraphBuildTokens[assignment.id] == token,
                  !Task.isCancelled else {
                return
            }
            guard let runtime = runtimes[slot] else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            let outcome = try await runtime.applyWorkspaceGraph(
                graph,
                triptychID: assignment.id
            )
            guard outcome == .applied else {
                return
            }
        }
        guard triptychGraphBuildTokens[assignment.id] == token,
              !Task.isCancelled else {
            return
        }
        triptychGraphs[assignment.id] = graph
    }

    private func accessURL(
        for vault: RegisteredVault,
        identity: VaultIdentity
    ) throws -> URL {
        if let lease = securityScopeLeases[vault.id] { return lease.url }
        let canonical = URL(fileURLWithPath: vault.canonicalPath, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        guard identity.canonicalPath == canonical.path else {
            throw WorkspaceRegistryError.vaultIdentityMismatch(
                vault.id,
                identity.canonicalPath,
                canonical.path
            )
        }
        guard let bookmark = identity.bookmarkData else { return canonical }
        var stale = false
        let resolved: URL
        do {
            resolved = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            throw WorkspaceRegistryError.vaultAccessUnavailable(vault.canonicalPath)
        }
        let resolvedCanonical = resolved.resolvingSymlinksInPath().standardizedFileURL
        guard !stale,
              resolvedCanonical.path == canonical.path,
              resolved.startAccessingSecurityScopedResource() else {
            throw WorkspaceRegistryError.vaultAccessUnavailable(vault.canonicalPath)
        }
        securityScopeLeases[vault.id] = VaultSecurityScopeLease(url: resolved, started: true)
        return resolved
    }

    private func accessPortableControlContainer(
        for worksVault: RegisteredVault
    ) async throws -> URL {
        let worksURL = URL(
            fileURLWithPath: worksVault.canonicalPath,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL
        let expectedContainer = worksURL.deletingLastPathComponent()
        if let lease = portableControlScopeLeases[expectedContainer.path] {
            return lease.url
        }
        guard let access = await portableControlAccessRegistry.access(forWorksURL: worksURL),
              access.canonicalContainerPath == expectedContainer.path else {
            throw WorkspaceRegistryError.portableControlAccessUnavailable(expectedContainer.path)
        }
        var stale = false
        let resolved: URL
        do {
            resolved = try URL(
                resolvingBookmarkData: access.bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            throw WorkspaceRegistryError.portableControlAccessUnavailable(expectedContainer.path)
        }
        let canonical = resolved.resolvingSymlinksInPath().standardizedFileURL
        guard !stale,
              canonical.path == expectedContainer.path,
              resolved.startAccessingSecurityScopedResource() else {
            throw WorkspaceRegistryError.portableControlAccessUnavailable(expectedContainer.path)
        }
        portableControlScopeLeases[expectedContainer.path] = VaultSecurityScopeLease(
            url: resolved,
            started: true
        )
        return resolved
    }

    private func deactivateUnregisteredVaultRuntimes() async {
        let registeredIDs = Set(await workspaceRegistry.allVaults().map(\.id))
        for vaultID in Set(vaultRuntimes.keys).subtracting(registeredIDs) {
            vaultWatcherTasks[vaultID]?.cancel()
            vaultWatcherTasks[vaultID] = nil
            if let runtime = vaultRuntimes.removeValue(forKey: vaultID) {
                await runtime.shutdown()
            }
            vaultRuntimePaths[vaultID] = nil
            securityScopeLeases[vaultID] = nil
            vaultRefreshStates[vaultID] = nil
            vaultRefreshGenerations[vaultID] = nil
            vaultTriptychIDs[vaultID] = nil
        }
    }

    func triptychRuntime(
        triptychID: UUID,
        worksVaultURL: URL,
        vaultIDs: [WorkspaceVaultSlot: UUID]
    ) async throws -> SharedTriptychRuntime {
        if let existing = triptychRuntimes[triptychID],
           existing.manifest.vaultIDs == vaultIDs {
            return existing
        }

        let controlStore = TriptychControlStore(worksVaultURL: worksVaultURL)
        let manifest = try await controlStore.bootstrap(
            vaultIDs: vaultIDs,
            preferredTriptychID: triptychID
        )
        let triptychStorage = applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(manifest.id.uuidString, isDirectory: true)
        let humanReviewStore = HumanReviewStore(
            storageURL: triptychStorage.appendingPathComponent("human-review", isDirectory: true)
        )
        let dialogueStore = DialogueStore(
            storageURL: triptychStorage.appendingPathComponent("dialogue", isDirectory: true)
        )
        let critiqueRegistry = CritiqueRegistry(controlURL: await controlStore.controlURL)
        let runtime = SharedTriptychRuntime(
            manifest: manifest,
            controlStore: controlStore,
            researchSkillStore: ResearchSkillStore(controlURL: await controlStore.controlURL),
            humanReviewStore: humanReviewStore,
            dialogueStore: dialogueStore,
            critiqueRegistry: critiqueRegistry,
            checkpointStore: TriptychCheckpointStore(
                triptychID: manifest.id,
                applicationSupportURL: applicationSupportURL
            ),
            transactionRecoveryStore: try TriptychMutationRecoveryStore(
                storageURL: triptychStorage.appendingPathComponent("transactions", isDirectory: true)
            ),
            identityRecoveryCoordinator: NoteIdentityRecoveryCoordinator(
                control: controlStore,
                humanReviews: humanReviewStore,
                dialogue: dialogueStore,
                critiques: critiqueRegistry,
                windowSessions: windowSessionStore
            )
        )
        triptychRuntimes[triptychID] = runtime
        triptychRuntimes[manifest.id] = runtime
        return runtime
    }

    /// Reopens portable Triptych control state after checkpoint restoration.
    /// Every window receives the new shared actor set instead of continuing to
    /// write from stale in-memory settings or Critique associations.
    func reloadTriptychRuntime(
        assignment: TriptychAssignment,
        worksVaultURL: URL
    ) async throws -> SharedTriptychRuntime {
        let vaultIDs = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.compactMap { slot in
            assignment.vault(for: slot).map { (slot, $0.id) }
        })
        guard vaultIDs.count == WorkspaceVaultSlot.allCases.count else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        for key in Array(triptychRuntimes.keys) {
            if key == assignment.id || triptychRuntimes[key]?.manifest.id == assignment.id {
                triptychRuntimes[key] = nil
            }
        }
        let runtime = try await triptychRuntime(
            triptychID: assignment.id,
            worksVaultURL: worksVaultURL,
            vaultIDs: vaultIDs
        )
        latestTriptychRuntimeReload = TriptychRuntimeReload(
            triptychID: assignment.id,
            runtime: runtime
        )
        return runtime
    }
}
