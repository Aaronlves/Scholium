import Foundation
import OSLog
import ScholiumContracts
import ScholiumCore

enum WorkspaceAccessConfiguration: Sendable {
    case live
    case snapshot
}

struct WorkspaceServices: Sendable {
    let manifest: TriptychManifest
    let repositories: [UUID: VaultRepository]
    let sourceCatalogs: [UUID: VaultSourceCatalog]
    let searchIndex: TriptychSearchIndex
    let controlStore: TriptychControlStore
    let indexedAttachmentAccessStore: IndexedAttachmentAccessStore
    let zotero: ZoteroOperations
    let settlementStore: SettlementStore
    let agentChangeStore: AgentChangeStore
    let transactionRecoveryStore: TriptychMutationRecoveryStore
    let identityRecoveryCoordinator: NoteIdentityRecoveryCoordinator
}

struct WorkspaceWatcherReadinessEvidence: Equatable, Sendable {
    let watchedVaultIDs: Set<UUID>
    let activationReconciliationCompleted: Bool
}

private struct SecurityScopeLease: Sendable {
    let url: URL
    let started: Bool
}

/// Per-Triptych application boundary shared by every consumer of a runtime.
/// The actor borrows the runtime's identity-pooled vault authorities and owns
/// only the Triptych-level composition, snapshots, and publication lifetime.
public actor WorkspaceHandle: WorkspaceSourceOperationGateOwner {
    // These module-internal members are shared only by WorkspaceHandle
    // extensions. They remain one actor-isolated state owner, not secondary
    // runtime or transaction owners.
    var lastRelatedContentMeasurement: RelatedContentRetrievalMeasurement?
    nonisolated static let refreshLogger = Logger(
        subsystem: "com.scholium.app",
        category: "WorkspaceRefresh"
    )
    private nonisolated static let openLogger = Logger(
        subsystem: "com.scholium.app",
        category: "WorkspaceOpen"
    )
    public nonisolated let id: UUID
    public nonisolated let runtimeIdentity: TriptychRuntimeIdentity
    public nonisolated let assignment: TriptychAssignment
    public nonisolated let mode: WorkspaceConfigurationMode
    public nonisolated let events: WorkspaceEventSource
    public nonisolated let documents: DocumentOperations
    public nonisolated let discovery: DiscoveryOperations
    public nonisolated let research: ResearchOperations
    public nonisolated let agentCollaboration: AgentCollaborationOperations

    let services: WorkspaceServices
    private let leases: [SecurityScopeLease]
    var currentSnapshot: WorkspaceSnapshot
    var latestRefreshMeasurement: WorkspaceRefreshMeasurement
    var latestRefreshCycleMeasurement: WorkspaceRefreshCycleMeasurement?
    var nextGraphGeneration = 2
    var refreshCoordinator:
        WorkspaceRefreshCoordinator<
            WorkspaceRefreshPayload,
            WorkspaceSnapshot
        >!
    var derivedStateRequiresRefresh = false
    var isShutDown = false
    var liveWatcherTask: Task<Void, Never>?
    var openingCompletionTask: Task<Void, Never>?
    let openingPresentationSignal = AsyncStream<Void>.makeStream(
        bufferingPolicy: .bufferingNewest(1)
    )
    var liveIndexRefreshTask: OwnedRefreshTask?
    var sourceCommitRefreshTask: Task<Void, Never>?
    var pendingSourceCommitRefreshes: [WorkspaceRefreshPayload] = []
    /// A root-discontinuity projection from the process-owned pooled vaults.
    /// It is cleared only by replacing this complete Workspace activation.
    var unavailableRootVaultIDs: Set<UUID> = []
    /// Exact identity records from durable source moves whose complete
    /// Workspace generation has not arrived yet. This is a bounded authority
    /// bridge for a second revision-checked operation, not a derived cache.
    var sourceAheadIdentityRecords: [VaultQualifiedNoteID: NoteIdentityRecord] = [:]
    var pendingLiveEvents: [UUID: VaultWatchEventJournal] = [:]
    var sourceOperationGate = WorkspaceSourceOperationGate()
    var managedCreationPreLeaseBarrierForTesting: (@Sendable () async -> Void)?
    var managedCreationPostSourceBarrierForTesting: (@Sendable () async -> Void)?
    var progressiveActivationReconciliationBarrierForTesting: (@Sendable () async -> Void)?
    var didCompleteActivationReconciliation = false

    func setManagedCreationPreLeaseBarrierForTesting(
        _ barrier: (@Sendable () async -> Void)?
    ) {
        managedCreationPreLeaseBarrierForTesting = barrier
    }

    func setManagedCreationPostSourceBarrierForTesting(
        _ barrier: (@Sendable () async -> Void)?
    ) {
        managedCreationPostSourceBarrierForTesting = barrier
    }

    func setProgressiveActivationReconciliationBarrierForTesting(
        _ barrier: (@Sendable () async -> Void)?
    ) {
        progressiveActivationReconciliationBarrierForTesting = barrier
    }

    private init(
        assignment: TriptychAssignment,
        mode: WorkspaceConfigurationMode,
        services: WorkspaceServices,
        leases: [SecurityScopeLease],
        initialSnapshot: WorkspaceSnapshot,
        initialRefreshMeasurement: WorkspaceRefreshMeasurement,
        initialWorkspaceGeneration: UInt64,
        reference: WorkspaceHandleReference,
        documents: DocumentOperations,
        discovery: DiscoveryOperations,
        research: ResearchOperations,
        agentCollaboration: AgentCollaborationOperations
    ) {
        id = assignment.id
        runtimeIdentity = TriptychRuntimeIdentity(
            triptychID: assignment.id,
            activationID: UUID()
        )
        self.assignment = assignment
        self.mode = mode
        self.services = services
        self.leases = leases
        currentSnapshot = initialSnapshot
        latestRefreshMeasurement = initialRefreshMeasurement
        self.documents = documents
        self.discovery = discovery
        self.research = research
        self.agentCollaboration = agentCollaboration
        events = WorkspaceEventSource(initialSnapshot: initialSnapshot)
        refreshCoordinator = WorkspaceRefreshCoordinator(
            startingAfter: initialWorkspaceGeneration
        ) {
            requestID, payloads in
            let handle = try await reference.requireHandle()
            return try await handle.performRefreshCycle(
                requestID: requestID,
                payloads: payloads
            )
        }
    }

    static func open(
        assignment: TriptychAssignment,
        mode: WorkspaceConfigurationMode,
        applicationSupportURL: URL,
        windowSessionStore: WindowSessionSnapshotStore,
        vaultPool: WorkspaceVaultPool,
        zotero: ZoteroOperations,
        access: WorkspaceAccessConfiguration,
        openingVault: WorkspaceVaultSlot? = nil
    ) async throws -> WorkspaceHandle {
        let clock = ContinuousClock()
        let totalStart = clock.now
        try Task.checkCancellation()
        guard Set(assignment.vaults.keys) == Set(WorkspaceVaultSlot.allCases) else {
            throw ScholiumApplicationError.incompleteTriptych(assignment.id)
        }

        var leases: [SecurityScopeLease] = []
        do {
            var repositories: [UUID: VaultRepository] = [:]
            var resolvedURLs: [WorkspaceVaultSlot: URL] = [:]
            var pooledVaults: [UUID: PooledWorkspaceVault] = [:]

            for slot in WorkspaceVaultSlot.allCases {
                try Task.checkCancellation()
                guard let vault = assignment.vault(for: slot) else {
                    throw ScholiumApplicationError.incompleteTriptych(assignment.id)
                }
                let pooled = try await vaultPool.vault(for: vault)
                repositories[vault.id] = pooled.repository
                pooledVaults[vault.id] = pooled
                resolvedURLs[slot] = pooled.rootURL
            }
            let vaultsReady = clock.now

            guard let worksVault = assignment.vault(for: .output),
                let worksURL = resolvedURLs[.output]
            else {
                throw ScholiumApplicationError.incompleteTriptych(assignment.id)
            }

            if case .live = access {
                let portable = try resolvePortableControlAccess(
                    worksVault: worksVault,
                    access: assignment.triptych.portableControlAccess
                )
                leases.append(portable)
            }

            let triptychStorage =
                applicationSupportURL
                .appendingPathComponent("Triptychs", isDirectory: true)
                .appendingPathComponent(assignment.id.uuidString, isDirectory: true)
            let controlStore = try TriptychControlStore(
                worksVaultURL: worksURL,
                coordinationURL: triptychStorage
            )
            let controlURL = await controlStore.controlURL
            let manifestURL = controlURL.appendingPathComponent("manifest.json")
            let manifestExists = FileManager.default.fileExists(atPath: manifestURL.path)
            if manifestExists {
                let existing: TriptychManifest
                do {
                    existing = try await controlStore.manifest()
                } catch let error as TriptychControlError {
                    throw ScholiumApplicationError.portableControlRecoveryRequired(
                        controlPath: controlURL.path,
                        reason: error.localizedDescription
                    )
                } catch {
                    throw error
                }
                guard existing.id == assignment.id else {
                    throw ScholiumApplicationError.manifestIdentityMismatch(
                        expected: assignment.id,
                        actual: existing.id
                    )
                }
            }

            let vaultIDs = Dictionary(
                uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map {
                    ($0, assignment.triptych.vaultID(for: $0))
                })
            let manifest: TriptychManifest
            do {
                manifest = try await controlStore.bootstrap(
                    vaultIDs: vaultIDs,
                    preferredTriptychID: assignment.id
                )
            } catch let error as TriptychControlError {
                switch error {
                case .invalidManifest, .settingsMissing, .settingsOldSchema,
                    .settingsFutureSchema, .settingsCorrupted,
                    .invalidIdentities,
                    .invalidAttachmentCatalog:
                    throw ScholiumApplicationError.portableControlRecoveryRequired(
                        controlPath: controlURL.path,
                        reason: error.localizedDescription
                    )
                default:
                    throw error
                }
            }
            guard manifest.id == assignment.id else {
                throw ScholiumApplicationError.manifestIdentityMismatch(
                    expected: assignment.id,
                    actual: manifest.id
                )
            }

            let openedSearchIndex = try TriptychSearchIndex.openRecovering(
                databaseURL: TriptychSearchIndex.databaseURL(
                    applicationSupportURL: applicationSupportURL,
                    triptychID: manifest.id
                ),
                triptychID: manifest.id,
                vaults: Array(assignment.vaults.values)
            )
            let priorWorkspaceGeneration = try await openedSearchIndex.index
                .workspaceGeneration()
            guard priorWorkspaceGeneration < UInt64(Int.max) else {
                throw SearchIndexError.invalidDocuments(
                    "Search workspace generation IDs were exhausted."
                )
            }
            let initialWorkspaceGeneration = priorWorkspaceGeneration + 1

            let settlementStore = try SettlementStore(
                controlURL: controlURL,
                applicationSupportURL: applicationSupportURL,
                triptychID: manifest.id
            )
            let agentChangeStore = try AgentChangeStore(
                applicationSupportURL: applicationSupportURL,
                triptychID: manifest.id
            )
            let transactionRecoveryStore = try TriptychMutationRecoveryStore(
                storageURL: triptychStorage.appendingPathComponent(
                    "transactions",
                    isDirectory: true
                )
            )
            let services = WorkspaceServices(
                manifest: manifest,
                repositories: repositories,
                sourceCatalogs: Dictionary(
                    uniqueKeysWithValues: pooledVaults.map {
                        ($0.key, $0.value.sourceCatalog)
                    }),
                searchIndex: openedSearchIndex.index,
                controlStore: controlStore,
                indexedAttachmentAccessStore: try IndexedAttachmentAccessStore(
                    applicationSupportURL: applicationSupportURL,
                    triptychID: manifest.id
                ),
                zotero: zotero,
                settlementStore: settlementStore,
                agentChangeStore: agentChangeStore,
                transactionRecoveryStore: transactionRecoveryStore,
                identityRecoveryCoordinator: NoteIdentityRecoveryCoordinator(
                    control: controlStore,
                    windowSessions: windowSessionStore
                )
            )
            let servicesReady = clock.now
            var watcherStreams: [UUID: AsyncStream<VaultWatchEvent>] = [:]
            if mode == .live {
                for (vaultID, pooled) in pooledVaults {
                    watcherStreams[vaultID] = await pooled.events()
                }
            }
            let watchersReady = clock.now
            let usesProgressiveOpening = mode == .live && openingVault != nil
            // Native observation is live before either inventory pass. A
            // progressive open inventories only its first usable vault; the
            // buffered stream and complete background reconcile close edits
            // that race either scan.
            let preOpenInventory =
                mode == .live && !usesProgressiveOpening
                ? try await sourceInventory(
                    assignment: assignment,
                    sourceCatalogs: services.sourceCatalogs
                )
                : nil
            let inventoryReady = clock.now
            let initialBuild: WorkspaceSnapshotBuildResult
            if let openingVault, usesProgressiveOpening {
                initialBuild = try await WorkspaceSnapshotBuilder.buildOpening(
                    assignment: assignment,
                    mode: mode,
                    dependencies: services.snapshotBuilderDependencies,
                    availableVault: openingVault,
                    workspaceGeneration: initialWorkspaceGeneration
                )
            } else {
                initialBuild = try await WorkspaceSnapshotBuilder.build(
                    assignment: assignment,
                    mode: mode,
                    dependencies: services.snapshotBuilderDependencies,
                    graphGeneration: 1,
                    workspaceGeneration: initialWorkspaceGeneration
                )
            }
            let snapshotReady = clock.now
            let initialSnapshot = initialBuild.snapshot
            logRefresh(initialBuild.measurement, publicationDuration: nil)
            try Task.checkCancellation()
            let reference = WorkspaceHandleReference(workspaceID: assignment.id)
            let documentOperations = DocumentOperations(reference: reference)
            let discoveryOperations = DiscoveryOperations(reference: reference)
            let researchOperations = ResearchOperations(
                reference: reference,
                recoveryRecordsURL: services.transactionRecoveryStore.storageURL
            )
            let agentCollaborationOperations = AgentCollaborationOperations(
                reference: reference
            )
            let handle = WorkspaceHandle(
                assignment: assignment,
                mode: mode,
                services: services,
                leases: leases,
                initialSnapshot: initialSnapshot,
                initialRefreshMeasurement: initialBuild.measurement,
                initialWorkspaceGeneration: initialWorkspaceGeneration,
                reference: reference,
                documents: documentOperations,
                discovery: discoveryOperations,
                research: researchOperations,
                agentCollaboration: agentCollaborationOperations
            )
            await reference.bind(handle)
            if case .live = access {
                let activationInventory: [VaultQualifiedNoteID: DocumentFingerprint]
                if let preOpenInventory {
                    activationInventory = preOpenInventory
                } else {
                    activationInventory = await handle.sourceRevisions(
                        in: initialSnapshot
                    )
                }
                await handle.startLiveTasks(
                    streams: watcherStreams,
                    preOpenInventory: activationInventory,
                    completesOpeningInBackground: usesProgressiveOpening
                )
            }
            let completed = clock.now
            Self.logOpen(
                vaults: totalStart.duration(to: vaultsReady),
                services: vaultsReady.duration(to: servicesReady),
                watchers: servicesReady.duration(to: watchersReady),
                inventory: watchersReady.duration(to: inventoryReady),
                snapshot: inventoryReady.duration(to: snapshotReady),
                finalization: snapshotReady.duration(to: completed),
                total: totalStart.duration(to: completed)
            )
            return handle
        } catch {
            for lease in leases.reversed() where lease.started {
                lease.url.stopAccessingSecurityScopedResource()
            }
            throw error
        }
    }

    private nonisolated static func logOpen(
        vaults: Duration,
        services: Duration,
        watchers: Duration,
        inventory: Duration,
        snapshot: Duration,
        finalization: Duration,
        total: Duration
    ) {
        openLogger.info(
            "handle vaults=\(String(describing: vaults), privacy: .public) services=\(String(describing: services), privacy: .public) watchers=\(String(describing: watchers), privacy: .public) inventory=\(String(describing: inventory), privacy: .public) snapshot=\(String(describing: snapshot), privacy: .public) finalization=\(String(describing: finalization), privacy: .public) total=\(String(describing: total), privacy: .public)"
        )
    }

    public func snapshot() throws -> WorkspaceSnapshot {
        try requireActive()
        return currentSnapshot
    }

    func documentPreviewCatalog(
        source: VaultQualifiedNoteID,
        sourceFingerprint: DocumentFingerprint,
        graphGeneration: Int
    ) throws -> DocumentPreviewCatalog {
        try requireActive()
        guard let graph = currentSnapshot.discovery.catalog.graph,
            graph.generation == graphGeneration,
            let sourceDocument = currentSnapshot.document(id: source)?.document,
            sourceDocument.fingerprint == sourceFingerprint
        else {
            return DocumentPreviewCatalog(
                graphGeneration: graphGeneration,
                source: source,
                sourceFingerprint: sourceFingerprint,
                links: []
            )
        }
        let targetIDs = Set(
            (graph.outgoing[source] ?? []).compactMap {
                $0.destination?.note
            })
        let targetDocuments = Dictionary(
            uniqueKeysWithValues: targetIDs.compactMap { id in
                currentSnapshot.document(id: id).map { (id, $0.document) }
            })
        let targetProfiles = Dictionary(
            uniqueKeysWithValues: targetIDs.compactMap { id in
                currentSnapshot.document(id: id).map { (id, $0.schemaProfile) }
            })
        return DocumentPreviewCatalogBuilder.build(
            source: source, sourceFingerprint: sourceFingerprint,
            graph: graph, documents: targetDocuments, profiles: targetProfiles)

    }

    public func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true
        let sourceCommitRefresh = sourceCommitRefreshTask
        sourceCommitRefreshTask = nil
        pendingSourceCommitRefreshes.removeAll()
        sourceCommitRefresh?.cancel()
        await refreshCoordinator.shutdown()
        let watcher = liveWatcherTask
        let openingCompletion = openingCompletionTask
        let refresh = liveIndexRefreshTask?.task
        liveWatcherTask = nil
        openingCompletionTask = nil
        liveIndexRefreshTask = nil
        pendingLiveEvents.removeAll()
        shutDownWorkspaceSourceOperationGate()
        watcher?.cancel()
        openingCompletion?.cancel()
        openingPresentationSignal.continuation.finish()
        refresh?.cancel()
        await watcher?.value
        await openingCompletion?.value
        await refresh?.value
        await sourceCommitRefresh?.value
        await events.finish(finalSnapshot: currentSnapshot)
        await services.indexedAttachmentAccessStore.endAllAccesses()
        for lease in leases.reversed() where lease.started {
            lease.url.stopAccessingSecurityScopedResource()
        }
    }

    func loadDocument(_ id: VaultQualifiedNoteID) async throws -> NoteDocument {
        try requireActive()
        let repository = try repository(vaultID: id.vaultID)
        return try await repository.load(relativePath: id.relativePath)
    }

    /// Releases the deferred complete-Triptych reconcile after the opening
    /// Vault's first Document has crossed its native visible-layout boundary.
    /// The signal is idempotent and carries no document identity or source.
    public func openingPresentationDidComplete() {
        openingPresentationSignal.continuation.yield()
        openingPresentationSignal.continuation.finish()
    }

    func awaitOpeningCompletionForTesting() async {
        await openingCompletionTask?.value
    }

    func orderedVaults() -> [RegisteredVault] {
        WorkspaceVaultSlot.allCases.compactMap { assignment.vault(for: $0) }
    }

    func vault(id: UUID) throws -> RegisteredVault {
        guard let vault = assignment.vaults.values.first(where: { $0.id == id }) else {
            throw ScholiumApplicationError.vaultNotInWorkspace(id)
        }
        return vault
    }

    func repository(vaultID: UUID) throws -> VaultRepository {
        if unavailableRootVaultIDs.contains(vaultID) {
            throw WorkspaceRegistryError.vaultAccessUnavailable(
                try vault(id: vaultID).canonicalPath
            )
        }
        guard let repository = services.repositories[vaultID] else {
            throw ScholiumApplicationError.vaultNotInWorkspace(vaultID)
        }
        return repository
    }

    func requireActive() throws {
        if isShutDown { throw ScholiumApplicationError.workspaceShutDown(id) }
    }

    func requireRootAuthoritiesAvailable() throws {
        guard
            let vaultID = WorkspaceVaultSlot.allCases.compactMap({ slot in
                assignment.vault(for: slot)?.id
            }).first(where: unavailableRootVaultIDs.contains)
        else {
            return
        }
        throw WorkspaceRegistryError.vaultAccessUnavailable(
            try vault(id: vaultID).canonicalPath
        )
    }

    func unavailableRootPaths() -> [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: unavailableRootVaultIDs.compactMap { vaultID in
                assignment.vaults.values.first(where: { $0.id == vaultID }).map {
                    (vaultID, $0.canonicalPath)
                }
            })
    }

    private static func resolvePortableControlAccess(
        worksVault: RegisteredVault,
        access: PortableControlAccess?
    ) throws -> SecurityScopeLease {
        let worksURL = URL(
            fileURLWithPath: worksVault.canonicalPath,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL
        let expectedContainer = worksURL.deletingLastPathComponent()
        guard let access,
            access.canonicalContainerPath == expectedContainer.path
        else {
            throw WorkspaceRegistryError.portableControlAccessUnavailable(
                expectedContainer.path
            )
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
            throw WorkspaceRegistryError.portableControlAccessUnavailable(
                expectedContainer.path
            )
        }
        let canonical = resolved.resolvingSymlinksInPath().standardizedFileURL
        guard !stale,
            canonical.path == expectedContainer.path,
            resolved.startAccessingSecurityScopedResource()
        else {
            throw WorkspaceRegistryError.portableControlAccessUnavailable(
                expectedContainer.path
            )
        }
        return SecurityScopeLease(url: resolved, started: true)
    }
}
