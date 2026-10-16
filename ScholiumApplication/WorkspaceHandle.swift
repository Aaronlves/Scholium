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
    let agentChangeStore: AgentChangeStore
    let documentReviewStore: DocumentReviewStore?
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
    var writingCompletionMemo = WritingCompletionProjectionMemo()
    var lastWritingCompletionMeasurement: WritingCompletionLookupMeasurement?
    var writingCompletionPostSourceReadBarrierForTesting: (@Sendable () async -> Void)?

    func setWritingCompletionPostSourceReadBarrierForTesting(_ barrier: (@Sendable () async -> Void)?) {
        writingCompletionPostSourceReadBarrierForTesting = barrier
    }
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
    public nonisolated let changes: DocumentChangeOperations

    let services: WorkspaceServices
    private let leases: [SecurityScopeLease]
    var currentSnapshot: WorkspaceSnapshot
    var latestRefreshMeasurement: WorkspaceRefreshMeasurement
    var latestRefreshCycleMeasurement: WorkspaceRefreshCycleMeasurement?
    var latestIndexClearResult: SearchIndexClearResult?
    var indexRebuildTask: Task<WorkspaceSnapshot, Error>?
    var nextGraphGeneration = 2
    var refreshCoordinator:
        WorkspaceRefreshCoordinator<
            WorkspaceRefreshPayload,
            WorkspaceSnapshot
        >!
    var derivedStateRequiresRefresh = false
    var isShutDown = false
    private var shutdownTask: Task<Void, Never>?
    #if DEBUG
        private(set) var shutdownJoinCountForTesting = 0
    #endif
    var liveWatcherTask: Task<Void, Never>?
    var citationControlWatcher: WorkspaceFileEventWatcher?
    var citationControlWatcherTask: Task<Void, Never>?
    var citationControlInvalidationTask: Task<Void, Never>?
    var citationControlInvalidationPending = false
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
    var sourceAheadSourceVersions: [VaultQualifiedNoteID: SourceVersion] = [:]
    var pendingLiveEvents: [UUID: VaultWatchEventJournal] = [:]
    var sourceOperationGate = WorkspaceSourceOperationGate()
    var sourceAuthorityToken = UUID()
    var refreshSourceAuthority: WorkspaceRefreshSourceAuthority?
    var managedCreationPreLeaseBarrierForTesting: (@Sendable () async -> Void)?
    var managedCreationPostSourceBarrierForTesting: (@Sendable () async -> Void)?
    var progressiveActivationReconciliationBarrierForTesting: (@Sendable () async -> Void)?
    var hydrationPostReadBarrierForTesting: (@Sendable () async -> Void)?
    var committedMutationRefreshBarrierForTesting: (@Sendable () async -> Void)?

    func setCommittedMutationRefreshBarrierForTesting(_ barrier: (@Sendable () async -> Void)?) {
        committedMutationRefreshBarrierForTesting = barrier
    }
    #if DEBUG
        var liveInventoryPreflightBarrierForTesting: (@Sendable () async -> Void)?
        var capturedSearchManifestBarrierForTesting: (@Sendable () async -> Void)?
        var reviewedSnapshotPublicationBarrierForTesting: (@Sendable () async -> Void)?
        var preparedSourceCatalogBarrierForTesting: (@Sendable (UUID) async -> Void)?

        func setPreparedSourceCatalogBarrierForTesting(_ barrier: (@Sendable (UUID) async -> Void)?) {
            preparedSourceCatalogBarrierForTesting = barrier
        }

        func setReviewedSnapshotPublicationBarrierForTesting(_ barrier: (@Sendable () async -> Void)?) {
            reviewedSnapshotPublicationBarrierForTesting = barrier
        }

        func setCapturedSearchManifestBarrierForTesting(_ barrier: (@Sendable () async -> Void)?) {
            capturedSearchManifestBarrierForTesting = barrier
        }

        func setLiveInventoryPreflightBarrierForTesting(_ barrier: (@Sendable () async -> Void)?) {
            liveInventoryPreflightBarrierForTesting = barrier
        }
    #endif
    var didCompleteActivationReconciliation = false
    var documentReviewIssue: String?
    var openingReviewCandidates: [UUID: WorkspaceNoteSummary] = [:]

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

    func setHydrationPostReadBarrierForTesting(
        _ barrier: (@Sendable () async -> Void)?
    ) {
        hydrationPostReadBarrierForTesting = barrier
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
        agentCollaboration: AgentCollaborationOperations,
        changes: DocumentChangeOperations
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
        self.changes = changes
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
        var citationWatcher: WorkspaceFileEventWatcher?
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

            let openedSearchIndex = try await TriptychSearchIndex.openRecovering(
                applicationSupportURL: applicationSupportURL,
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
                agentChangeStore: agentChangeStore,
                documentReviewStore: try? DocumentReviewStore(
                    applicationSupportURL: applicationSupportURL,
                    triptychID: manifest.id
                ),
                transactionRecoveryStore: transactionRecoveryStore,
                identityRecoveryCoordinator: NoteIdentityRecoveryCoordinator(
                    control: controlStore,
                    windowSessions: windowSessionStore
                )
            )
            let servicesReady = clock.now
            var watcherStreams: [UUID: AsyncStream<VaultWatchEvent>] = [:]
            var citationEvents: AsyncStream<VaultWatchEvent>?
            if mode == .live {
                for (vaultID, pooled) in pooledVaults {
                    watcherStreams[vaultID] = await pooled.events()
                }
                let watcher = WorkspaceFileEventWatcher(rootURL: controlURL, scope: .citationControl)
                citationWatcher = watcher
                citationEvents = try await watcher.start()
            }
            let watchersReady = clock.now
            let usesProgressiveOpening = mode == .live && openingVault != nil
            // Native observation is live before either inventory pass. A
            // progressive open inventories only its first usable vault; the
            // buffered stream and complete background reconcile close edits
            // that race either scan.
            let initialSlots: [WorkspaceVaultSlot]
            if let openingVault, usesProgressiveOpening {
                initialSlots = [openingVault]
            } else {
                initialSlots = WorkspaceVaultSlot.allCases
            }
            let sourceSnapshots = try await prepareInitialSourceSnapshots(
                assignment: assignment, catalogs: services.sourceCatalogs, slots: initialSlots)
            let preOpenInventory: [VaultQualifiedNoteID: DocumentFingerprint]? =
                mode == .live && !usesProgressiveOpening
                ? Dictionary(
                    uniqueKeysWithValues: sourceSnapshots.flatMap { vaultID, snapshot in
                        snapshot.projections.map {
                            (VaultQualifiedNoteID(vaultID: vaultID, relativePath: $0.relativePath), $0.fingerprint)
                        }
                    }) : nil
            let inventoryReady = clock.now
            let initialBuild: WorkspaceSnapshotBuildResult
            if let openingVault, usesProgressiveOpening,
                let vault = assignment.vault(for: openingVault),
                let sourceSnapshot = sourceSnapshots[vault.id]
            {
                initialBuild = try await WorkspaceSnapshotBuilder.buildOpening(
                    assignment: assignment,
                    mode: mode,
                    dependencies: services.snapshotBuilderDependencies,
                    availableVault: openingVault,
                    sourceSnapshot: sourceSnapshot,
                    workspaceGeneration: initialWorkspaceGeneration
                )
            } else {
                initialBuild = try await WorkspaceSnapshotBuilder.build(
                    assignment: assignment,
                    mode: mode,
                    dependencies: services.snapshotBuilderDependencies,
                    sourceSnapshots: sourceSnapshots,
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
            let documentChangeOperations = DocumentChangeOperations(reference: reference)
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
                agentCollaboration: agentCollaborationOperations,
                changes: documentChangeOperations
            )
            await reference.bind(handle)
            if let citationWatcher, let citationEvents {
                await handle.startCitationControlObservation(watcher: citationWatcher, events: citationEvents)
            }
            await handle.initializeDocumentReviewsFromOpeningSnapshot(initialSnapshot)
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
            await citationWatcher?.stop()
            for lease in leases.reversed() where lease.started {
                lease.url.stopAccessingSecurityScopedResource()
            }
            throw error
        }
    }

    /// Before a Handle exists, the pooled catalog owns candidate installation.
    /// Capture only the requested opening Library, or one fully validated
    /// immutable cohort for an immediate complete configuration.
    private static func prepareInitialSourceSnapshots(
        assignment: TriptychAssignment,
        catalogs: [UUID: VaultSourceCatalog],
        slots: [WorkspaceVaultSlot]
    ) async throws -> [UUID: VaultSourceCatalogSnapshot] {
        var snapshots: [UUID: VaultSourceCatalogSnapshot] = [:]
        var pending = slots
        while true {
            for slot in pending {
                guard let vault = assignment.vault(for: slot), let catalog = catalogs[vault.id] else {
                    throw ScholiumApplicationError.incompleteTriptych(assignment.id)
                }
                while true {
                    try Task.checkCancellation()
                    let candidate = try await catalog.prepare(.fullReconcile)
                    if case .installed = try await catalog.install(candidate) {
                        snapshots[vault.id] = try await catalog.snapshot(consumePendingMeasurement: true)
                        break
                    }
                }
            }
            pending = []
            for slot in slots {
                guard let vault = assignment.vault(for: slot), let catalog = catalogs[vault.id],
                    let snapshot = snapshots[vault.id]
                else { throw ScholiumApplicationError.incompleteTriptych(assignment.id) }
                if try await catalog.validate(snapshot) == .superseded { pending.append(slot) }
            }
            if pending.isEmpty { return snapshots }
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
    ) async throws -> DocumentPreviewCatalog {
        try requireActive()
        guard let graph = currentSnapshot.discovery.catalog.graph,
            graph.generation == graphGeneration,
            currentSnapshot.document(id: source)?.fingerprint == sourceFingerprint
        else {
            return DocumentPreviewCatalog(
                graphGeneration: graphGeneration,
                source: source,
                sourceFingerprint: sourceFingerprint,
                links: []
            )
        }
        let targetIDs = Set(
            (graph.outgoing[source] ?? [])
                .sorted { $0.occurrence.span.utf16LowerBound < $1.occurrence.span.utf16LowerBound }
                .prefix(DocumentPreviewCatalogBuilder.maximumLinkCount)
                .compactMap {
                    $0.destination?.note
                })
        var targetDocuments: [VaultQualifiedNoteID: NoteDocument] = [:]
        for id in targetIDs.sorted() {
            try Task.checkCancellation()
            guard let summary = currentSnapshot.document(id: id) else { continue }
            targetDocuments[id] = try await hydrate(summary).document
        }
        guard currentSnapshot.discovery.catalog.graph?.generation == graphGeneration,
            currentSnapshot.document(id: source)?.fingerprint == sourceFingerprint
        else { throw WorkspaceHydrationError.staleSnapshot }
        let targetProfiles = Dictionary(
            uniqueKeysWithValues: targetIDs.compactMap { id in
                currentSnapshot.document(id: id).map { (id, $0.schemaProfile) }
            })
        return DocumentPreviewCatalogBuilder.build(
            source: source, sourceFingerprint: sourceFingerprint,
            graph: graph, documents: targetDocuments, profiles: targetProfiles)

    }

    public func shutdown() async {
        if let shutdownTask {
            #if DEBUG
                shutdownJoinCountForTesting += 1
            #endif
            await shutdownTask.value
            return
        }
        isShutDown = true
        let task = Task { await finishShutdown() }
        shutdownTask = task
        await task.value
    }

    private func finishShutdown() async {
        writingCompletionMemo.clear()
        lastWritingCompletionMeasurement = nil
        writingCompletionPostSourceReadBarrierForTesting = nil
        let sourceCommitRefresh = sourceCommitRefreshTask
        sourceCommitRefreshTask = nil
        pendingSourceCommitRefreshes.removeAll()
        sourceCommitRefresh?.cancel()
        let indexRebuild = indexRebuildTask
        indexRebuildTask = nil
        indexRebuild?.cancel()
        let watcher = liveWatcherTask
        let citationWatcher = citationControlWatcher
        let citationWatcherTask = citationControlWatcherTask
        let citationInvalidation = citationControlInvalidationTask
        citationControlWatcher = nil
        citationControlWatcherTask = nil
        citationControlInvalidationTask = nil
        citationControlInvalidationPending = false
        let openingCompletion = openingCompletionTask
        let refresh = liveIndexRefreshTask?.task
        liveWatcherTask = nil
        openingCompletionTask = nil
        liveIndexRefreshTask = nil
        pendingLiveEvents.removeAll()
        shutDownWorkspaceSourceOperationGate()
        watcher?.cancel()
        citationWatcherTask?.cancel()
        citationInvalidation?.cancel()
        openingCompletion?.cancel()
        openingPresentationSignal.continuation.finish()
        refresh?.cancel()
        // Cancel all producers before the coordinator waits for its current
        // cycle; a producer or explicit rebuild may itself be awaiting it.
        await refreshCoordinator.shutdown()
        _ = try? await indexRebuild?.value
        await citationWatcher?.stop()
        await watcher?.value
        await citationWatcherTask?.value
        await citationInvalidation?.value
        await openingCompletion?.value
        await refresh?.value
        await sourceCommitRefresh?.value
        await services.searchIndex.shutdown()
        await events.finish(finalSnapshot: currentSnapshot)
        await services.indexedAttachmentAccessStore.endAllAccesses()
        for lease in leases.reversed() where lease.started {
            lease.url.stopAccessingSecurityScopedResource()
        }
    }

    func loadDocument(_ id: VaultQualifiedNoteID) async throws -> NoteDocument {
        try requireActive()
        let repository = try repository(vaultID: id.vaultID)
        let document = try await repository.load(relativePath: id.relativePath)
        return try await documentWithCitationSnapshot(document, id: id)
    }

    func hydrate(_ expected: WorkspaceNoteSummary) async throws -> WorkspaceNoteSnapshot {
        try requireActive()
        guard let version = await hydrationSourceVersion(for: expected)
        else { throw WorkspaceHydrationError.staleSnapshot }
        let repository = try repository(vaultID: expected.id.vaultID)
        let loaded = try await repository.loadCatalogSource(
            relativePath: expected.id.relativePath)
        if let barrier = hydrationPostReadBarrierForTesting {
            await barrier()
        }
        try Task.checkCancellation()
        guard loaded.version == version,
            loaded.document.fingerprint == expected.fingerprint,
            loaded.document.relativePath.utf8.elementsEqual(expected.id.relativePath.utf8),
            try await repository.sourceVersionIsCurrent(
                relativePath: expected.id.relativePath, version: version)
        else { throw WorkspaceHydrationError.staleSnapshot }
        let document = try await documentWithCitationSnapshot(
            loaded.document, id: expected.id, expectedNoteID: expected.stableIdentity.resolvedID)
        try requireActive()
        guard await hydrationSourceVersion(for: expected) == version,
            try await repository.sourceVersionIsCurrent(
                relativePath: expected.id.relativePath, version: version)
        else { throw WorkspaceHydrationError.staleSnapshot }
        let current = currentSnapshot.document(id: expected.id)
        let summary =
            current.flatMap {
                Self.sameSourceBinding($0, expected) ? $0 : nil
            } ?? expected
        return WorkspaceNoteSnapshot(summary: summary, document: document)
    }

    private func hydrationSourceVersion(for expected: WorkspaceNoteSummary) async -> SourceVersion? {
        if let record = sourceAheadIdentityRecords[expected.id],
            record.id == expected.stableIdentity.resolvedID,
            record.fingerprint == expected.fingerprint,
            let version = sourceAheadSourceVersions[expected.id],
            version.fingerprint == expected.fingerprint
        {
            return version
        }
        guard let current = currentSnapshot.document(id: expected.id),
            Self.sameSourceBinding(current, expected),
            let catalog = services.sourceCatalogs[expected.id.vaultID]
        else { return nil }
        return await catalog.sourceVersion(
            relativePath: expected.id.relativePath, fingerprint: expected.fingerprint)
    }

    /// Source identity, descriptor version and compact summary share one
    /// acceptance point, independent of the disposable Graph/Search refresh.
    func recordCommittedSource(_ record: NoteIdentityRecord) async throws -> WorkspaceNoteSummary {
        let id = VaultQualifiedNoteID(vaultID: record.vaultID, relativePath: record.relativePath)
        let loaded = try await repository(vaultID: record.vaultID).loadCatalogSource(
            relativePath: record.relativePath)
        guard loaded.document.fingerprint == record.fingerprint,
            try await services.controlStore.identityRecord(
                vaultID: record.vaultID, relativePath: record.relativePath) == record,
            let vault = assignment.vaults.values.first(where: { $0.id == record.vaultID })
        else { throw NoteIdentityRecoveryError.identityUnresolved(record.relativePath) }
        sourceAheadIdentityRecords[id] = record
        sourceAheadSourceVersions[id] = loaded.version
        return WorkspaceNoteSummary(
            id: id, vaultRole: vault.role, stableIdentity: .resolved(record.id),
            document: loaded.document, fileMetadata: loaded.fileMetadata,
            graphCounts: .init(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0),
            derivedProjectionState: .sourceAhead)
    }

    private nonisolated static func sameSourceBinding(
        _ lhs: WorkspaceNoteSummary,
        _ rhs: WorkspaceNoteSummary
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.id.relativePath.utf8.elementsEqual(rhs.id.relativePath.utf8)
            && lhs.fingerprint == rhs.fingerprint
            && lhs.stableIdentity == rhs.stableIdentity
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
