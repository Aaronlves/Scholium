import ScholiumContracts
import Foundation
import ScholiumCore
import OSLog

enum WorkspaceAccessConfiguration: Sendable {
    case live(
        portableControlAccessRegistry: PortableControlAccessRegistry
    )
    case snapshot
}

struct WorkspaceServices: Sendable {
    let manifest: TriptychManifest
    let repositories: [UUID: VaultRepository]
    let sourceCatalogs: [UUID: VaultSourceCatalog]
    let searchIndex: TriptychSearchIndex
    let controlStore: TriptychControlStore
    let researchSkillStore: ResearchSkillTransactionCoordinator
    let researchSkillMaintenanceStore: ResearchSkillMaintenanceStore
    let researchPermissionPolicyStore: ResearchPermissionPolicyStore
    let agentNoteChangeRequestStore: AgentNoteChangeRequestStore
    let researchRecoveryPolicyStore: ResearchRecoveryPolicyStore
    let researchSourceAccessStore: ResearchSourceAccessStore
    let recommendedBibliographyStore: RecommendedBibliographyStore
    let zotero: ZoteroOperations
    let portableResearchRecordStore: PortableResearchRecordStore
    let localResearchExecutionStore: LocalResearchExecutionStore
    let critiqueRegistry: CritiqueRegistry
    let checkpointStore: TriptychCheckpointStore
    let transactionRecoveryStore: TriptychMutationRecoveryStore
    let identityRecoveryCoordinator: NoteIdentityRecoveryCoordinator
    let roots: TriptychRoots
}

struct WorkspaceWatcherReadinessEvidence: Equatable, Sendable {
    let watchedVaultIDs: Set<UUID>
    let activationReconciliationCompleted: Bool
}

private struct SecurityScopeLease: Sendable {
    let url: URL
    let started: Bool
}

private struct OwnedRefreshTask: Sendable {
    let token: UUID
    let task: Task<Void, Never>
}

private enum DocumentSaveCompletion: Equatable {
    /// Return only after the matching derived workspace generation publishes.
    case sourceAndDerived
    /// Return after the authoritative repository commit and refresh in the
    /// Workspace-owned background queue.
    case sourceOnly
}

enum RefreshPublication: Sendable {
    case sourceCommitted(VaultQualifiedNoteID, WorkspaceSourceCommitKind)
    case explicit
    case liveInventory
    case researchRecords
    case runtimeReloaded
}

enum DerivedRefreshFailureDisposition: Sendable {
    case staleAfterCommittedMutation(affectedVaultIDs: Set<UUID>)
    case failed(affectedVaultIDs: Set<UUID>)

    func status(
        for error: Error,
        lastKnownGood snapshot: WorkspaceSnapshot
    ) -> WorkspaceDerivedRefreshStatus {
        let evidence = WorkspaceDerivedRefreshEvidence(snapshot: snapshot)
        switch self {
        case .staleAfterCommittedMutation(let affectedVaultIDs):
            return .stale(WorkspaceDerivedRefreshIssue(
                reason: "The authoritative mutation committed, but derived workspace refresh failed: \(error.localizedDescription)",
                affectedVaultIDs: affectedVaultIDs,
                lastKnownGood: evidence
            ))
        case .failed(let affectedVaultIDs):
            return .failed(WorkspaceDerivedRefreshIssue(
                reason: "Derived workspace refresh failed: \(error.localizedDescription)",
                affectedVaultIDs: affectedVaultIDs,
                lastKnownGood: evidence
            ))
        }
    }
}

struct VaultSourceCatalogDelta: Sendable {
    var upserts: Set<String> = []
    var deletions: Set<String> = []
    var refreshFolders = false

    mutating func merge(_ other: Self) {
        for path in other.deletions {
            upserts.remove(path)
            deletions.insert(path)
        }
        for path in other.upserts {
            deletions.remove(path)
            upserts.insert(path)
        }
        refreshFolders = refreshFolders || other.refreshFolders
    }
}

enum SourceCatalogPreparation: Sendable {
    case none
    case delta([UUID: VaultSourceCatalogDelta])
    case fullReconcile

    static func inferred(from publication: RefreshPublication) -> Self {
        switch publication {
        case .sourceCommitted(let id, _):
            .delta([id.vaultID: VaultSourceCatalogDelta(
                upserts: [id.relativePath]
            )])
        case .liveInventory, .researchRecords:
            .none
        case .explicit, .runtimeReloaded:
            .fullReconcile
        }
    }

    static func merged(_ preparations: [Self]) -> Self {
        guard !preparations.contains(where: {
            if case .fullReconcile = $0 { true } else { false }
        }) else { return .fullReconcile }
        var merged: [UUID: VaultSourceCatalogDelta] = [:]
        for preparation in preparations {
            guard case .delta(let changes) = preparation else { continue }
            for (vaultID, change) in changes {
                merged[vaultID, default: VaultSourceCatalogDelta()].merge(change)
            }
        }
        return merged.isEmpty ? .none : .delta(merged)
    }
}

private enum WorkspaceRefreshCycleError: LocalizedError {
    case graphGenerationExhausted

    var errorDescription: String? {
        "Workspace graph generation IDs were exhausted."
    }
}

private struct WorkspaceSourceInventoryInput: Sendable {
    let order: Int
    let vaultID: UUID
    let catalog: VaultSourceCatalog
}

private struct WorkspaceSourceInventorySnapshot: Sendable {
    let order: Int
    let vaultID: UUID
    let snapshot: VaultSourceCatalogSnapshot
}

private struct WorkspaceRefreshPayload: Sendable {
    let publication: RefreshPublication
    let failureDisposition: DerivedRefreshFailureDisposition
    let sourceCatalogPreparation: SourceCatalogPreparation

    static func merged(_ payloads: [Self]) throws -> Self {
        guard let first = payloads.first else { throw CancellationError() }
        guard payloads.count > 1 else { return first }
        var affectedVaultIDs: Set<UUID> = []
        var includesCommittedMutation = false
        for payload in payloads {
            switch payload.failureDisposition {
            case .staleAfterCommittedMutation(let affected):
                includesCommittedMutation = true
                affectedVaultIDs.formUnion(affected)
            case .failed(let affected):
                affectedVaultIDs.formUnion(affected)
            }
        }
        return Self(
            publication: mergedPublication(payloads.map(\.publication)),
            failureDisposition: includesCommittedMutation
                ? .staleAfterCommittedMutation(affectedVaultIDs: affectedVaultIDs)
                : .failed(affectedVaultIDs: affectedVaultIDs),
            sourceCatalogPreparation: .merged(
                payloads.map(\.sourceCatalogPreparation)
            )
        )
    }

    private static func mergedPublication(
        _ publications: [RefreshPublication]
    ) -> RefreshPublication {
        if publications.allSatisfy({
            if case .researchRecords = $0 { true } else { false }
        }) { return .researchRecords }
        if publications.allSatisfy({
            if case .liveInventory = $0 { true } else { false }
        }) { return .liveInventory }
        if publications.allSatisfy({
            if case .runtimeReloaded = $0 { true } else { false }
        }) { return .runtimeReloaded }
        if publications.allSatisfy({
            if case .explicit = $0 { true } else { false }
        }) { return .explicit }
        if case .sourceCommitted(let firstID, let firstKind) = publications[0],
           publications.dropFirst().allSatisfy({ publication in
               guard case .sourceCommitted(let id, let kind) = publication else {
                   return false
               }
               return id == firstID && kind == firstKind
           }) {
            return .sourceCommitted(firstID, firstKind)
        }
        // One event generation cannot publish several source identities or
        // heterogeneous semantic causes. A complete inventory event carries
        // every changed note from the merged snapshot instead.
        return .explicit
    }
}

/// Per-Triptych application boundary shared by every consumer of a runtime.
/// The actor borrows the runtime's identity-pooled vault authorities and owns
/// only the Triptych-level composition, snapshots, and publication lifetime.
public actor WorkspaceHandle: WorkspaceSourceOperationGateOwner {
    private nonisolated static let refreshLogger = Logger(
        subsystem: "com.scholium.app",
        category: "WorkspaceRefresh"
    )
    public nonisolated let id: UUID
    public nonisolated let runtimeIdentity: TriptychRuntimeIdentity
    public nonisolated let assignment: TriptychAssignment
    public nonisolated let mode: WorkspaceConfigurationMode
    public nonisolated let events: WorkspaceEventSource
    public nonisolated let documents: DocumentOperations
    public nonisolated let discovery: DiscoveryOperations
    public nonisolated let research: ResearchOperations

    let services: WorkspaceServices
    let researchFunctionCoordinator: ResearchFunctionCoordinator
    private let leases: [SecurityScopeLease]
    var currentSnapshot: WorkspaceSnapshot
    private(set) var latestRefreshMeasurement: WorkspaceRefreshMeasurement
    private var nextGraphGeneration = 2
    private var refreshCoordinator: WorkspaceRefreshCoordinator<
        WorkspaceRefreshPayload,
        WorkspaceSnapshot
    >!
    private var derivedStateRequiresRefresh = false
    private var isShutDown = false
    private var liveWatcherTask: Task<Void, Never>?
    private var liveIndexRefreshTask: OwnedRefreshTask?
    private var sourceCommitRefreshTask: Task<Void, Never>?
    private var pendingSourceCommitRefreshes: [WorkspaceRefreshPayload] = []
    private var pendingLiveEvents: [UUID: VaultWatchEventJournal] = [:]
    private var researchRecoveryMutationIsActive = false
    var sourceOperationGate = WorkspaceSourceOperationGate()
    private var didCompleteActivationReconciliation = false

    func beginResearchRecoveryMutation() throws {
        guard !researchRecoveryMutationIsActive else {
            throw ResearchRecoveryPolicyError.operationInProgress
        }
        researchRecoveryMutationIsActive = true
    }

    func endResearchRecoveryMutation() {
        researchRecoveryMutationIsActive = false
    }
    /// Plaintext activity keys live only for this open WorkspaceHandle. The
    /// durable grant store keeps a digest, so reopening never reconstructs a
    /// credential from persisted state.
    var activeResearchActivityKeys: [UUID: String] = [:]
    /// Plaintext Agent coordination keys are likewise process-local. Local
    /// Execution v2 persists only their digest and expiry.
    var activeAgentCoordinationKeys: [UUID: String] = [:]

    private init(
        assignment: TriptychAssignment,
        mode: WorkspaceConfigurationMode,
        services: WorkspaceServices,
        leases: [SecurityScopeLease],
        initialSnapshot: WorkspaceSnapshot,
        initialRefreshMeasurement: WorkspaceRefreshMeasurement,
        initialWorkspaceGeneration: UInt64,
        reference: WorkspaceHandleReference,
        researchFunctionCoordinator: ResearchFunctionCoordinator,
        documents: DocumentOperations,
        discovery: DiscoveryOperations,
        research: ResearchOperations
    ) {
        id = assignment.id
        runtimeIdentity = TriptychRuntimeIdentity(
            triptychID: assignment.id,
            activationID: UUID()
        )
        self.assignment = assignment
        self.mode = mode
        self.services = services
        self.researchFunctionCoordinator = researchFunctionCoordinator
        self.leases = leases
        currentSnapshot = initialSnapshot
        latestRefreshMeasurement = initialRefreshMeasurement
        self.documents = documents
        self.discovery = discovery
        self.research = research
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
        access: WorkspaceAccessConfiguration
    ) async throws -> WorkspaceHandle {
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

            guard let worksVault = assignment.vault(for: .output),
                  let worksURL = resolvedURLs[.output],
                  let analysesURL = resolvedURLs[.paperAnalysis],
                  let topicsURL = resolvedURLs[.topicKnowledge] else {
                throw ScholiumApplicationError.incompleteTriptych(assignment.id)
            }

            if case .live(let portableRegistry) = access {
                let portable = try await resolvePortableControlAccess(
                    worksVault: worksVault,
                    registry: portableRegistry
                )
                leases.append(portable)
            }

            let controlStore = TriptychControlStore(worksVaultURL: worksURL)
            let controlURL = await controlStore.controlURL
            let triptychStorage = applicationSupportURL
                .appendingPathComponent("Triptychs", isDirectory: true)
                .appendingPathComponent(assignment.id.uuidString, isDirectory: true)
            let manifestURL = controlURL.appendingPathComponent("manifest.json")
            let manifestExists = FileManager.default.fileExists(atPath: manifestURL.path)
            if manifestExists {
                let existing = try await controlStore.manifest()
                guard existing.id == assignment.id else {
                    throw ScholiumApplicationError.manifestIdentityMismatch(
                        expected: assignment.id,
                        actual: existing.id
                    )
                }
            }

            let workingMethodRecoveryStore = ResearchWorkingMethodRecoveryStore(
                snapshotRootURL: triptychStorage
                    .appendingPathComponent("research-guidance", isDirectory: true)
                    .appendingPathComponent(
                        "skill-snapshots",
                        isDirectory: true
                    )
            )
            let researchSkillStore = ResearchSkillTransactionCoordinator(
                controlURL: controlURL,
                workingMethodRecoveryStore: workingMethodRecoveryStore
            )
            if !manifestExists {
                // Working Methods are installed before the manifest becomes
                // the durable new-Triptych marker. A failed or interrupted
                // bootstrap can therefore retry exact partial task-owned
                // packages without mutating an established Triptych.
                _ = try await researchSkillStore
                    .installDefaultWorkingMethods()
            }

            let vaultIDs = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map {
                ($0, assignment.triptych.vaultID(for: $0))
            })
            let manifest = try await controlStore.bootstrap(
                vaultIDs: vaultIDs,
                preferredTriptychID: assignment.id
            )
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

            let portableResearchRecordStore = try PortableResearchRecordStore(
                controlURL: controlURL,
                applicationSupportURL: applicationSupportURL,
                triptychID: manifest.id
            )
            let localResearchExecutionStore = try LocalResearchExecutionStore(
                applicationSupportURL: applicationSupportURL,
                triptychID: manifest.id
            )
            let critiqueRegistry = CritiqueRegistry(controlURL: controlURL)
            let transactionRecoveryStore = try TriptychMutationRecoveryStore(
                storageURL: triptychStorage.appendingPathComponent(
                    "transactions",
                    isDirectory: true
                )
            )
            let researchSkillMaintenanceStore = ResearchSkillMaintenanceStore(
                skillStore: researchSkillStore,
                snapshotRootURL: triptychStorage
                    .appendingPathComponent("research-guidance", isDirectory: true)
                    .appendingPathComponent("skill-snapshots", isDirectory: true)
            )
            let services = WorkspaceServices(
                manifest: manifest,
                repositories: repositories,
                sourceCatalogs: Dictionary(uniqueKeysWithValues: pooledVaults.map {
                    ($0.key, $0.value.sourceCatalog)
                }),
                searchIndex: openedSearchIndex.index,
                controlStore: controlStore,
                researchSkillStore: researchSkillStore,
                researchSkillMaintenanceStore: researchSkillMaintenanceStore,
                researchPermissionPolicyStore: ResearchPermissionPolicyStore(
                    applicationSupportURL: applicationSupportURL,
                    triptychID: manifest.id
                ),
                agentNoteChangeRequestStore: try AgentNoteChangeRequestStore(
                    applicationSupportURL: applicationSupportURL,
                    triptychID: manifest.id
                ),
                researchRecoveryPolicyStore: try ResearchRecoveryPolicyStore(
                    applicationSupportURL: applicationSupportURL,
                    triptychID: manifest.id
                ),
                researchSourceAccessStore: ResearchSourceAccessStore(
                    applicationSupportURL: applicationSupportURL,
                    triptychID: manifest.id
                ),
                recommendedBibliographyStore: RecommendedBibliographyStore(
                    controlURL: controlURL
                ),
                zotero: zotero,
                portableResearchRecordStore: portableResearchRecordStore,
                localResearchExecutionStore: localResearchExecutionStore,
                critiqueRegistry: critiqueRegistry,
                checkpointStore: TriptychCheckpointStore(
                    triptychID: manifest.id,
                    applicationSupportURL: applicationSupportURL
                ),
                transactionRecoveryStore: transactionRecoveryStore,
                identityRecoveryCoordinator: NoteIdentityRecoveryCoordinator(
                    control: controlStore,
                    critiques: critiqueRegistry,
                    windowSessions: windowSessionStore
                ),
                roots: TriptychRoots(
                    analyses: analysesURL,
                    topics: topicsURL,
                    works: worksURL,
                    control: controlURL
                )
            )
            var watcherStreams: [UUID: AsyncStream<VaultWatchEvent>] = [:]
            if mode == .live {
                for (vaultID, pooled) in pooledVaults {
                    watcherStreams[vaultID] = await pooled.events()
                }
            }
            // Native observation is live before either inventory pass. The
            // buffered stream plus the post-publication reconciliation closes
            // edits that race either scan.
            let preOpenInventory = mode == .live
                ? try await sourceInventory(
                    assignment: assignment,
                    sourceCatalogs: services.sourceCatalogs
                )
                : nil
            let initialBuild = try await WorkspaceSnapshotBuilder.build(
                assignment: assignment,
                mode: mode,
                services: services,
                graphGeneration: 1,
                workspaceGeneration: initialWorkspaceGeneration
            )
            let initialSnapshot = initialBuild.snapshot
            logRefresh(initialBuild.measurement, publicationDuration: nil)
            try Task.checkCancellation()
            let reference = WorkspaceHandleReference(workspaceID: assignment.id)
            let documentOperations = DocumentOperations(reference: reference)
            let discoveryOperations = DiscoveryOperations(reference: reference)
            let researchFunctionCoordinator = ResearchFunctionCoordinator(
                workspaceID: assignment.id,
                dependencies: ResearchFunctionCoordinatorDependencies(
                    repositories: services.repositories,
                    vaults: Dictionary(uniqueKeysWithValues: assignment.vaults.values.map {
                        ($0.id, $0)
                    }),
                    roots: services.roots,
                    controlStore: services.controlStore,
                    researchSkillStore: services.researchSkillStore,
                    sourceAccessStore: services.researchSourceAccessStore,
                    agentNoteChangeRequestStore: services.agentNoteChangeRequestStore,
                    portableResearchRecordStore: services.portableResearchRecordStore,
                    localExecutionStore: services.localResearchExecutionStore,
                    critiqueRegistry: services.critiqueRegistry,
                    checkpointStore: services.checkpointStore,
                    zotero: services.zotero
                )
            )
            let researchOperations = ResearchOperations(
                reference: reference,
                functionCoordinator: researchFunctionCoordinator,
                skillsURL: services.researchSkillStore.skillsURL,
                recoveryRecordsURL: services.transactionRecoveryStore.storageURL
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
                researchFunctionCoordinator: researchFunctionCoordinator,
                documents: documentOperations,
                discovery: discoveryOperations,
                research: researchOperations
            )
            await reference.bind(handle)
            if case .live = access {
                await handle.startLiveTasks(
                    streams: watcherStreams,
                    preOpenInventory: preOpenInventory ?? [:]
                )
            }
            return handle
        } catch {
            for lease in leases.reversed() where lease.started {
                lease.url.stopAccessingSecurityScopedResource()
            }
            throw error
        }
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
              sourceDocument.fingerprint == sourceFingerprint else {
            return DocumentPreviewCatalog(
                graphGeneration: graphGeneration,
                source: source,
                sourceFingerprint: sourceFingerprint,
                links: []
            )
        }
        let targetIDs = Set((graph.outgoing[source] ?? []).compactMap {
            $0.destination?.note
        })
        let targetDocuments = Dictionary(uniqueKeysWithValues: targetIDs.compactMap { id in
            currentSnapshot.document(id: id).map { (id, $0.document) }
        })
        let targetProfiles = Dictionary(uniqueKeysWithValues: targetIDs.compactMap { id in
            currentSnapshot.document(id: id).map { (id, $0.schemaProfile) }
        })
        return DocumentPreviewCatalogBuilder.build(
            source: source,
            sourceFingerprint: sourceFingerprint,
            graph: graph,
            documents: targetDocuments,
            profiles: targetProfiles
        )
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
        let refresh = liveIndexRefreshTask?.task
        liveWatcherTask = nil
        liveIndexRefreshTask = nil
        pendingLiveEvents.removeAll()
        shutDownWorkspaceSourceOperationGate()
        watcher?.cancel()
        refresh?.cancel()
        await watcher?.value
        await refresh?.value
        await sourceCommitRefresh?.value
        await events.finish(finalSnapshot: currentSnapshot)
        for lease in leases.reversed() where lease.started {
            lease.url.stopAccessingSecurityScopedResource()
        }
    }

    func loadDocument(_ id: VaultQualifiedNoteID) async throws -> NoteDocument {
        try requireActive()
        let repository = try repository(vaultID: id.vaultID)
        return try await repository.load(relativePath: id.relativePath)
    }

    func importMarkdown(
        at sourceURL: URL,
        intoVault vaultID: UUID
    ) async throws -> NoteDocument {
        try requireActive()
        let secured = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if secured { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let resolved = sourceURL.resolvingSymlinksInPath().standardizedFileURL
        let values = try resolved.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              resolved.pathExtension.caseInsensitiveCompare("md") == .orderedSame else {
            throw DocumentImportError.unsupportedSource(sourceURL.path)
        }
        let sourceData = try Data(contentsOf: resolved, options: [.mappedIfSafe])
        guard NoteDocument.decodeUTF8PreservingBOM(sourceData) != nil else {
            throw DocumentImportError.unsupportedSource(sourceURL.path)
        }

        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let repository = try repository(vaultID: vaultID)
        let document = try await repository.importMarkdown(
            preferredFilename: resolved.lastPathComponent,
            sourceData: sourceData
        )
        let id = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: document.relativePath
        )
        do {
            guard try await services.controlStore.identity(
                forVaultID: vaultID,
                relativePath: document.relativePath,
                fingerprint: document.fingerprint
            ) != nil else {
                throw NoteIdentityRecoveryError.identityUnresolved(document.relativePath)
            }
        } catch {
            try? await repository.removeCreatedFileForRollback(
                relativePath: document.relativePath,
                createdRevision: document.fingerprint
            )
            throw error
        }
        endSourceMutation(mutationLease)
        ownsMutation = false
        do {
            _ = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [vaultID]
                ),
                sourceCatalogPreparation: Self.catalogPreparation(
                    upserts: [id],
                    refreshFolderVaultIDs: [vaultID]
                )
            )
        } catch {
            throw ScholiumApplicationError.committedButRefreshFailed(
                document.fingerprint,
                error.localizedDescription
            )
        }
        return document
    }

    func createDocument(
        _ id: VaultQualifiedNoteID,
        content: String
    ) async throws -> NoteDocument {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let repository = try repository(vaultID: id.vaultID)
        let registeredVault = try vault(id: id.vaultID)
        if registeredVault.role.allowsCritique,
           CritiquePlacement.isManagedCritiquePath(id.relativePath) {
            throw CritiquePlacementError.directCreationRequiresRequestCritique
        }

        let document = try await repository.create(
            relativePath: id.relativePath,
            content: content
        )
        do {
            guard try await services.controlStore.identity(
                forVaultID: id.vaultID,
                relativePath: id.relativePath,
                fingerprint: document.fingerprint
            ) != nil else {
                throw NoteIdentityRecoveryError.identityUnresolved(id.relativePath)
            }
        } catch {
            try? await repository.removeCreatedFileForRollback(
                relativePath: id.relativePath,
                createdRevision: document.fingerprint
            )
            throw error
        }
        endSourceMutation(mutationLease)
        ownsMutation = false
        do {
            _ = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [id.vaultID]
                ),
                sourceCatalogPreparation: Self.catalogPreparation(
                    upserts: [id],
                    refreshFolderVaultIDs: [id.vaultID]
                )
            )
        } catch {
            throw ScholiumApplicationError.committedButRefreshFailed(
                document.fingerprint,
                error.localizedDescription
            )
        }
        return document
    }

    func createDocument(_ request: DocumentCreationRequest) async throws -> NoteDocument {
        try requireActive()
        let registeredVault = try vault(id: request.id.vaultID)
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let frontmatter: [String: YAMLValue] = [:]
        let profile: SchemaProfileID = switch registeredVault.role {
        case .sourceCorpus: .analysis
        case .topicKnowledge: .topicMarkdown
        case .draftProject: .draftProject
        case .other: .genericMarkdown
        }
        let issues = PropertyContractCatalog.validate(
            frontmatter: frontmatter,
            profile: profile,
            context: .creation
        )
        guard issues.isEmpty else { throw DocumentCreationError.invalidMetadata(issues) }

        let content = title.isEmpty ? "" : "# \(title)\n"
        return try await createDocument(request.id, content: content)
    }

    /// Claims the first available default note name through the repository's
    /// atomic no-replace create. A collision can race any earlier inventory, so
    /// only the authoritative create result decides whether to advance.
    func createUntitledNote(
        inVault vaultID: UUID,
        folderRelativePath: String?
    ) async throws -> NoteDocument {
        var ordinal = 1
        while true {
            try Task.checkCancellation()
            let filename = ordinal == 1 ? "Untitled.md" : "Untitled \(ordinal).md"
            let relativePath = if let folderRelativePath, !folderRelativePath.isEmpty {
                "\(folderRelativePath)/\(filename)"
            } else {
                filename
            }
            do {
                return try await createDocument(DocumentCreationRequest(
                    id: VaultQualifiedNoteID(
                        vaultID: vaultID,
                        relativePath: relativePath
                    ),
                    title: ""
                ))
            } catch VaultRepositoryError.fileAlreadyExists {
                ordinal += 1
            } catch VaultRepositoryError.pathCollision {
                ordinal += 1
            }
        }
    }

    /// Claims one default directory name. The returned path is a location, not
    /// a new portable identity or research record.
    func createUntitledFolder(
        inVault vaultID: UUID,
        parentRelativePath: String?
    ) async throws -> VaultRelativeFolderPath {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let registeredVault = try vault(id: vaultID)
        if let parentRelativePath,
           registeredVault.role.allowsCritique,
           CritiquePlacement.isManagedCritiquePath(
               parentRelativePath + "/placeholder.md"
           ) {
            throw CritiquePlacementError.directCreationRequiresRequestCritique
        }
        let repository = try repository(vaultID: vaultID)
        var ordinal = 1
        while true {
            try Task.checkCancellation()
            let name = ordinal == 1 ? "Untitled Folder" : "Untitled Folder \(ordinal)"
            let relativePath = if let parentRelativePath, !parentRelativePath.isEmpty {
                parentRelativePath + "/" + name
            } else {
                name
            }
            do {
                let folder = try await repository.createFolder(relativePath: relativePath)
                endSourceMutation(mutationLease)
                ownsMutation = false
                do {
                    _ = try await refreshFolderInventory(vaultID: vaultID)
                } catch {
                    throw ScholiumApplicationError.operationCommittedButRefreshFailed(
                        operation: "Folder creation at \(folder.rawValue)",
                        reason: error.localizedDescription
                    )
                }
                return folder
            } catch VaultRepositoryError.fileAlreadyExists {
                ordinal += 1
            } catch VaultRepositoryError.pathCollision {
                ordinal += 1
            }
        }
    }

    func moveFolder(
        inVault vaultID: UUID,
        from sourceRelativePath: String,
        to destinationRelativePath: String
    ) async throws -> FolderMoveCommit {
        try await coordinatedMoveFolder(
            inVault: vaultID,
            from: sourceRelativePath,
            to: destinationRelativePath,
            movesToLifecycle: false
        )
    }

    func moveFolderToTrash(
        inVault vaultID: UUID,
        relativePath: String
    ) async throws -> FolderMoveCommit {
        try await coordinatedMoveFolder(
            inVault: vaultID,
            from: relativePath,
            to: "Trash/" + relativePath,
            movesToLifecycle: true
        )
    }

    func duplicateDocument(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> NoteDocument {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let repository = try repository(vaultID: id.vaultID)
        let registeredVault = try vault(id: id.vaultID)
        if registeredVault.role.allowsCritique,
           CritiquePlacement.isManagedCritiquePath(id.relativePath) {
            throw CritiquePlacementError.duplicateNotSupported
        }
        if registeredVault.role.allowsCritique,
           CritiquePlacement.isManagedCritiquePath(destinationRelativePath) {
            throw CritiquePlacementError.directCreationRequiresRequestCritique
        }
        let identity = try await resolvedIdentity(
            for: id,
            expectedRevision: expectedRevision
        )
        let document = try await repository.duplicate(
            relativePath: id.relativePath,
            to: destinationRelativePath,
            expectedRevision: expectedRevision
        )
        do {
            _ = try await services.controlStore.duplicateIdentity(
                from: identity.id,
                to: destinationRelativePath,
                fingerprint: document.fingerprint
            )
        } catch {
            try? await repository.removeCreatedFileForRollback(
                relativePath: destinationRelativePath,
                createdRevision: document.fingerprint
            )
            throw error
        }
        endSourceMutation(mutationLease)
        ownsMutation = false
        do {
            _ = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [id.vaultID]
                ),
                sourceCatalogPreparation: Self.catalogPreparation(
                    upserts: [VaultQualifiedNoteID(
                        vaultID: id.vaultID,
                        relativePath: destinationRelativePath
                    )],
                    refreshFolderVaultIDs: [id.vaultID]
                )
            )
        } catch {
            throw ScholiumApplicationError.committedButRefreshFailed(
                document.fingerprint,
                error.localizedDescription
            )
        }
        return document
    }

    func saveDocument(
        _ id: VaultQualifiedNoteID,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint
    ) async throws -> SaveResult {
        try await performDocumentSave(
            id,
            changeSet: changeSet,
            expectedRevision: expectedRevision,
            completion: .sourceAndDerived
        )
    }

    func commitDocument(
        _ id: VaultQualifiedNoteID,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint
    ) async throws -> SaveResult {
        try await performDocumentSave(
            id,
            changeSet: changeSet,
            expectedRevision: expectedRevision,
            completion: .sourceOnly
        )
    }

    private func performDocumentSave(
        _ id: VaultQualifiedNoteID,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint,
        completion: DocumentSaveCompletion
    ) async throws -> SaveResult {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let repository = try repository(vaultID: id.vaultID)
        let result: SaveResult
        do {
            result = try await repository.save(
                relativePath: id.relativePath,
                changeSet: changeSet,
                expectedRevision: expectedRevision
            )
        } catch let error as VaultRepositoryError {
            guard case .commitUncertain = error else { throw error }
            let observed = try? await repository.load(relativePath: id.relativePath).fingerprint
            let state: TriptychMutationRecoveryState
            if let observed {
                state = observed == expectedRevision ? .restored : .externallyChanged
            } else {
                state = .unreadable
            }
            let record = TriptychMutationRecoveryRecord(
                triptychID: self.id,
                operation: .noteSave,
                failure: error.localizedDescription,
                files: [TriptychMutationRecoveryFile(
                    vaultID: id.vaultID,
                    path: id.relativePath,
                    role: .savedNote,
                    beforeRevision: expectedRevision,
                    intendedRevision: nil,
                    observedRevision: observed,
                    state: state,
                    detail: "The coordinated save could not prove both canonical and displaced bytes. Recovery evidence remains machine-local."
                )]
            )
            do {
                try await services.transactionRecoveryStore.record(record)
            } catch {
                throw TriptychTransactionError.recoveryPersistenceFailed(
                    record,
                    error.localizedDescription
                )
            }
            throw TriptychTransactionError.recoveryRequired(record)
        }
        if completion == .sourceOnly {
            // Queue before releasing the mutation lease so the matching
            // watcher event cannot start a competing refresh first.
            scheduleSourceCommitRefresh(id: id, kind: .save)
        }
        endSourceMutation(mutationLease)
        ownsMutation = false
        if completion == .sourceAndDerived {
            do {
                _ = try await refresh(
                    publication: .sourceCommitted(id, .save),
                    failureDisposition: .staleAfterCommittedMutation(
                        affectedVaultIDs: [id.vaultID]
                    )
                )
            } catch {
                throw ScholiumApplicationError.committedButRefreshFailed(
                    result.document.fingerprint,
                    error.localizedDescription
                )
            }
        }
        return result
    }

    func moveDocument(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychMoveCommit {
        try await coordinatedMoveDocument(
            id,
            to: destinationRelativePath,
            expectedRevision: expectedRevision,
            validatesCritiquePlacement: true
        )
    }

    func setAsideDocument(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychMoveCommit {
        let destination = id.relativePath.hasPrefix("Set Aside/")
            ? id.relativePath
            : "Set Aside/" + id.relativePath
        return try await coordinatedMoveDocument(
            id,
            to: destination,
            expectedRevision: expectedRevision,
            validatesCritiquePlacement: false
        )
    }

    func moveDocumentToTrash(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychMoveCommit {
        let destination: String
        if id.relativePath.hasPrefix("Set Aside/") {
            destination = "Trash/" + id.relativePath.dropFirst("Set Aside/".count)
        } else if id.relativePath.hasPrefix("Trash/") {
            destination = id.relativePath
        } else {
            destination = "Trash/" + id.relativePath
        }
        return try await coordinatedMoveDocument(
            id,
            to: destination,
            expectedRevision: expectedRevision,
            validatesCritiquePlacement: false
        )
    }

    func putBackDocument(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychMoveCommit {
        let destination: String?
        if id.relativePath.hasPrefix("Set Aside/") {
            destination = String(id.relativePath.dropFirst("Set Aside/".count))
        } else if id.relativePath.hasPrefix("Trash/") {
            destination = String(id.relativePath.dropFirst("Trash/".count))
        } else {
            destination = nil
        }
        guard let destination, !destination.isEmpty else {
            throw VaultRepositoryError.invalidRelativePath(id.relativePath)
        }
        return try await coordinatedMoveDocument(
            id,
            to: destination,
            expectedRevision: expectedRevision,
            validatesCritiquePlacement: true
        )
    }

    func deleteDocumentPermanently(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> PermanentDeletionCommit {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        guard id.relativePath.hasPrefix("Trash/") else {
            throw VaultRepositoryError.invalidRelativePath(id.relativePath)
        }
        let identity = try await resolvedIdentity(
            for: id,
            expectedRevision: expectedRevision
        )
        let repository = try repository(vaultID: id.vaultID)
        let coordinator = NotePermanentDeletionCoordinator(
            triptychID: services.manifest.id,
            repository: repository,
            critiqueRegistry: services.critiqueRegistry,
            checkpointStore: services.checkpointStore,
            controlStore: services.controlStore,
            recoveryStore: services.transactionRecoveryStore,
            sourceAccessStore: services.researchSourceAccessStore,
            portableRecordStore: services.portableResearchRecordStore,
            localExecutionStore: services.localResearchExecutionStore,
            agentNoteChangeRequestStore: services.agentNoteChangeRequestStore
        )
        let commit = try await coordinator.delete(
            noteID: identity.id,
            vaultID: id.vaultID,
            relativePath: id.relativePath,
            expectedRevision: expectedRevision,
            checkpointArea: try checkpointArea(vaultID: id.vaultID)
        )
        endSourceMutation(mutationLease)
        ownsMutation = false
        do {
            _ = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [id.vaultID]
                ),
                sourceCatalogPreparation: Self.catalogPreparation(
                    deletions: [id],
                    refreshFolderVaultIDs: [id.vaultID]
                )
            )
        } catch {
            throw ScholiumApplicationError.committedButRefreshFailed(
                commit.fingerprint,
                error.localizedDescription
            )
        }
        return commit
    }

    func recoverInterruptedDocumentTransactions() async -> [String] {
        guard !isShutDown else {
            return [ScholiumApplicationError.workspaceShutDown(id).localizedDescription]
        }
        let mutationLease: WorkspaceSourceOperationLease
        do {
            mutationLease = try await beginSourceMutation()
        } catch {
            return [error.localizedDescription]
        }
        defer { endSourceMutation(mutationLease) }
        var issues: [String] = []
        for (vaultID, repository) in services.repositories.sorted(by: {
            $0.key.uuidString < $1.key.uuidString
        }) {
            let coordinator = NotePermanentDeletionCoordinator(
                triptychID: services.manifest.id,
                repository: repository,
                critiqueRegistry: services.critiqueRegistry,
                checkpointStore: services.checkpointStore,
                controlStore: services.controlStore,
                recoveryStore: services.transactionRecoveryStore,
                sourceAccessStore: services.researchSourceAccessStore,
                portableRecordStore: services.portableResearchRecordStore,
                localExecutionStore: services.localResearchExecutionStore,
                agentNoteChangeRequestStore: services.agentNoteChangeRequestStore
            )
            do {
                try await coordinator.recoverInterruptedTransactions()
            } catch {
                issues.append("Vault \(vaultID.uuidString): \(error.localizedDescription)")
            }
        }
        return issues
    }

    func refresh() async throws -> WorkspaceSnapshot {
        try await refresh(publication: .explicit)
    }

    /// Refreshes disposable projections after a durable non-document
    /// operation. Failure is reported as an explicit committed outcome so a
    /// delivery surface can refresh later without repeating the mutation.
    func refreshAfterCommittedOperation(
        _ operation: String,
        publication: RefreshPublication,
        affectedVaultIDs: Set<UUID> = []
    ) async throws {
        do {
            _ = try await refresh(
                publication: publication,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: affectedVaultIDs
                )
            )
        } catch {
            throw ScholiumApplicationError.operationCommittedButRefreshFailed(
                operation: operation,
                reason: error.localizedDescription
            )
        }
    }

    func refresh(
        publication: RefreshPublication,
        failureDisposition: DerivedRefreshFailureDisposition = .failed(
            affectedVaultIDs: []
        ),
        sourceCatalogPreparation: SourceCatalogPreparation? = nil
    ) async throws -> WorkspaceSnapshot {
        try requireActive()
        return try await refreshCoordinator.request(WorkspaceRefreshPayload(
            publication: publication,
            failureDisposition: failureDisposition,
            sourceCatalogPreparation: sourceCatalogPreparation
                ?? .inferred(from: publication)
        ))
    }

    private func performRefreshCycle(
        requestID: RefreshRequestID,
        payloads: [WorkspaceRefreshPayload]
    ) async throws -> WorkspaceSnapshot {
        let refreshLease = try await beginRefreshCycle()
        defer { endRefreshCycle(refreshLease) }
        let payload = try WorkspaceRefreshPayload.merged(payloads)
        let snapshot: WorkspaceSnapshot
        let measurement: WorkspaceRefreshMeasurement
        do {
            try await prepareSourceCatalogs(payload.sourceCatalogPreparation)
            guard nextGraphGeneration < Int.max else {
                throw WorkspaceRefreshCycleError.graphGenerationExhausted
            }
            let indexedWorkspaceGeneration = try await services.searchIndex
                .workspaceGeneration()
            guard indexedWorkspaceGeneration < UInt64(Int.max) else {
                throw SearchIndexError.invalidDocuments(
                    "Search workspace generation IDs were exhausted."
                )
            }
            let workspaceGeneration = max(
                requestID.rawValue,
                indexedWorkspaceGeneration + 1
            )
            let graphGeneration = nextGraphGeneration
            nextGraphGeneration += 1
            let build = try await WorkspaceSnapshotBuilder.build(
                assignment: assignment,
                mode: mode,
                services: services,
                graphGeneration: graphGeneration,
                workspaceGeneration: workspaceGeneration
            )
            snapshot = build.snapshot
            measurement = build.measurement
            latestRefreshMeasurement = measurement
        } catch {
            for catalog in services.sourceCatalogs.values {
                await catalog.discardPendingMeasurement()
            }
            if !Task.isCancelled, !isShutDown {
                derivedStateRequiresRefresh = true
                await events.publishDerivedStateChanged(
                    snapshot: currentSnapshot,
                    status: payload.failureDisposition.status(
                        for: error,
                        lastKnownGood: currentSnapshot
                    )
                )
            }
            throw error
        }
        try requireActive()
        let previous = currentSnapshot
        currentSnapshot = snapshot
        let confirmsEarlierFailure = derivedStateRequiresRefresh
        derivedStateRequiresRefresh = false
        let publicationStart = ContinuousClock().now
        await publish(
            payload.publication,
            previous: previous,
            snapshot: snapshot,
            confirmsEarlierFailure: confirmsEarlierFailure
        )
        Self.logRefresh(
            measurement,
            publicationDuration: publicationStart.duration(to: ContinuousClock().now)
        )
        return snapshot
    }

    private nonisolated static func logRefresh(
        _ measurement: WorkspaceRefreshMeasurement,
        publicationDuration: Duration?
    ) {
        refreshLogger.info(
            "generation=\(measurement.workspaceGeneration, privacy: .public) files=\(measurement.enumeratedFiles, privacy: .public) reads=\(measurement.readFiles, privacy: .public) parses=\(measurement.parsedDocuments, privacy: .public) projections=\(measurement.projectedDocuments, privacy: .public) sourceBytes=\(measurement.snapshotSourceBytes, privacy: .public) enumerate=\(String(describing: measurement.enumerationDuration), privacy: .public) read=\(String(describing: measurement.readDuration), privacy: .public) parse=\(String(describing: measurement.parseDuration), privacy: .public) project=\(String(describing: measurement.projectionDuration), privacy: .public) identity=\(String(describing: measurement.identityProjectionDuration), privacy: .public) graph=\(String(describing: measurement.graphDuration), privacy: .public) research=\(String(describing: measurement.researchStateDuration), privacy: .public) searchProjection=\(String(describing: measurement.searchDocumentProjectionDuration), privacy: .public) search=\(String(describing: measurement.searchDuration), privacy: .public) assemble=\(String(describing: measurement.snapshotAssemblyDuration), privacy: .public) publish=\(String(describing: publicationDuration), privacy: .public) total=\(String(describing: measurement.totalDuration), privacy: .public)"
        )
    }

    private func prepareSourceCatalogs(
        _ preparation: SourceCatalogPreparation
    ) async throws {
        // Snapshot/CLI runtimes have no native watcher. Every publication must
        // therefore stat-reconcile all three catalogs so an external addition,
        // deletion, or unreadable source in another vault cannot be hidden by
        // an otherwise precise local mutation. Unchanged notes are not read or
        // reparsed because SourceVersion remains the cache gate.
        if mode == .snapshot {
            for catalog in services.sourceCatalogs.values {
                try await catalog.reconcile()
            }
            return
        }
        switch preparation {
        case .fullReconcile:
            for catalog in services.sourceCatalogs.values {
                try await catalog.reconcile()
            }
        case .none:
            break
        case .delta(let changes):
            for (vaultID, change) in changes {
                guard let catalog = services.sourceCatalogs[vaultID] else {
                    throw ScholiumApplicationError.vaultNotInWorkspace(vaultID)
                }
                try await catalog.apply(
                    upserts: change.upserts,
                    deletions: change.deletions,
                    refreshFolders: change.refreshFolders
                )
            }
        }
    }

    private static func catalogPreparation(
        upserts: [VaultQualifiedNoteID] = [],
        deletions: [VaultQualifiedNoteID] = [],
        refreshFolderVaultIDs: Set<UUID> = []
    ) -> SourceCatalogPreparation {
        var changes: [UUID: VaultSourceCatalogDelta] = [:]
        for id in deletions {
            changes[id.vaultID, default: VaultSourceCatalogDelta()]
                .deletions.insert(id.relativePath)
        }
        for id in upserts {
            var change = changes[id.vaultID, default: VaultSourceCatalogDelta()]
            change.deletions.remove(id.relativePath)
            change.upserts.insert(id.relativePath)
            changes[id.vaultID] = change
        }
        for vaultID in refreshFolderVaultIDs {
            changes[vaultID, default: VaultSourceCatalogDelta()]
                .refreshFolders = true
        }
        return changes.isEmpty ? .none : .delta(changes)
    }

    private func publish(
        _ publication: RefreshPublication,
        previous: WorkspaceSnapshot,
        snapshot: WorkspaceSnapshot,
        confirmsEarlierFailure: Bool
    ) async {
        let changes = inventoryChanges(from: previous, to: snapshot)
        switch publication {
        case .sourceCommitted(let id, let kind):
            guard let note = snapshot.document(id: id) else {
                await events.publishDerivedStateChanged(snapshot: snapshot)
                return
            }
            await events.publishSourceCommitted(
                snapshot: snapshot,
                note: note,
                kind: kind
            )
        case .explicit:
            if changes.hasChanges {
                await events.publishInventoryChanged(
                    snapshot: snapshot,
                    added: changes.added,
                    removed: changes.removed,
                    changed: changes.changed,
                    moved: changes.moved
                )
            } else {
                await events.publishDerivedStateChanged(snapshot: snapshot)
            }
        case .liveInventory:
            guard changes.hasChanges else {
                if confirmsEarlierFailure {
                    await events.publishDerivedStateChanged(snapshot: snapshot)
                }
                return
            }
            await events.publishInventoryChanged(
                snapshot: snapshot,
                added: changes.added,
                removed: changes.removed,
                changed: changes.changed,
                moved: changes.moved
            )
        case .researchRecords:
            await events.publishResearchRecordsChanged(snapshot: snapshot)
        case .runtimeReloaded:
            await events.publishRuntimeReloaded(
                runtimeIdentity: runtimeIdentity,
                snapshot: snapshot
            )
        }
    }

    /// Publishes the one typed handoff from this activation to a fully opened
    /// replacement. Subscribers can adopt the replacement identity and its
    /// complete snapshot before this handle finishes its stream.
    func announceRuntimeReplacement(
        runtimeIdentity: TriptychRuntimeIdentity,
        snapshot: WorkspaceSnapshot
    ) async {
        await events.publishRuntimeReloaded(
            runtimeIdentity: runtimeIdentity,
            snapshot: snapshot
        )
    }

    private func inventoryChanges(
        from previous: WorkspaceSnapshot,
        to current: WorkspaceSnapshot
    ) -> (
        added: Set<VaultQualifiedNoteID>,
        removed: Set<VaultQualifiedNoteID>,
        changed: Set<VaultQualifiedNoteID>,
        moved: [WorkspaceNoteMove],
        hasChanges: Bool
    ) {
        let old = sourceRevisions(in: previous)
        let new = sourceRevisions(in: current)
        let oldIDs = Set(old.keys)
        let newIDs = Set(new.keys)
        let previousLocations = resolvedIdentityLocations(in: previous)
        let currentLocations = resolvedIdentityLocations(in: current)
        let moved = Set(previousLocations.keys).intersection(currentLocations.keys)
            .compactMap { stableID -> WorkspaceNoteMove? in
                guard let oldLocation = previousLocations[stableID],
                      let newLocation = currentLocations[stableID],
                      oldLocation != newLocation else { return nil }
                return WorkspaceNoteMove(
                    stableNoteID: stableID,
                    previousLocation: oldLocation,
                    location: newLocation
                )
            }
            .sorted { left, right in
                if left.previousLocation.vaultID != right.previousLocation.vaultID {
                    return left.previousLocation.vaultID.uuidString
                        < right.previousLocation.vaultID.uuidString
                }
                return left.previousLocation.relativePath < right.previousLocation.relativePath
            }
        let movedFrom = Set(moved.map(\.previousLocation))
        let movedTo = Set(moved.map(\.location))
        let added = newIDs.subtracting(oldIDs).subtracting(movedTo)
        let removed = oldIDs.subtracting(newIDs).subtracting(movedFrom)
        let changed = oldIDs.intersection(newIDs).filter { old[$0] != new[$0] }
        return (
            added,
            removed,
            Set(changed),
            moved,
            !added.isEmpty || !removed.isEmpty || !changed.isEmpty || !moved.isEmpty
        )
    }

    private func resolvedIdentityLocations(
        in snapshot: WorkspaceSnapshot
    ) -> [UUID: VaultQualifiedNoteID] {
        Dictionary(
            snapshot.vaults.flatMap(\.documents).compactMap { note in
                note.stableIdentity.resolvedID.map { ($0, note.id) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func sourceRevisions(
        in snapshot: WorkspaceSnapshot
    ) -> [VaultQualifiedNoteID: DocumentFingerprint] {
        Dictionary(
            uniqueKeysWithValues: snapshot.vaults.flatMap { vault in
                vault.documents.map { ($0.id, $0.fingerprint) }
            }
        )
    }

    private func startLiveTasks(
        streams: [UUID: AsyncStream<VaultWatchEvent>],
        preOpenInventory: [VaultQualifiedNoteID: DocumentFingerprint]
    ) async {
        guard mode == .live, !isShutDown, liveWatcherTask == nil else { return }
        liveWatcherTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                for (vaultID, stream) in streams {
                    group.addTask { [weak self] in
                        for await event in stream {
                            guard !Task.isCancelled, let self else { return }
                            await self.receiveLiveEvent(event, vaultID: vaultID)
                        }
                    }
                }
                await group.waitForAll()
            }
        }
        await reconcileLiveActivation(preOpenInventory: preOpenInventory)
    }

    /// Closes the interval between the pre-open inventory and watcher
    /// ownership. The comparison against both the pre-open signature and the
    /// published initial snapshot catches a source that changed during scan,
    /// including an intermediate revision that was captured by that scan.
    private func reconcileLiveActivation(
        preOpenInventory: [VaultQualifiedNoteID: DocumentFingerprint]
    ) async {
        defer { didCompleteActivationReconciliation = true }
        guard !isShutDown else { return }
        var attemptedRefresh = false
        do {
            let observed = try await Self.sourceInventory(
                assignment: assignment,
                sourceCatalogs: services.sourceCatalogs
            )
            let published = sourceRevisions(in: currentSnapshot)
            let changedDuringActivation = observed != preOpenInventory
            let publishedRevisionIsStale = observed != published
            guard changedDuringActivation || publishedRevisionIsStale else { return }
            if publishedRevisionIsStale {
                attemptedRefresh = true
                _ = try await refresh(
                    publication: .liveInventory,
                    failureDisposition: .failed(
                        affectedVaultIDs: Set(assignment.vaults.values.map(\.id))
                    )
                )
            }
        } catch {
            guard !attemptedRefresh, !Task.isCancelled, !isShutDown else { return }
            // Native observation is already owned. A concurrent filesystem
            // event remains buffered and triggers a complete retry, while the
            // delivery surfaces retain the initial last-known-good snapshot.
            derivedStateRequiresRefresh = true
            await events.publishDerivedStateChanged(
                snapshot: currentSnapshot,
                status: DerivedRefreshFailureDisposition.failed(
                    affectedVaultIDs: Set(assignment.vaults.values.map(\.id))
                ).status(for: error, lastKnownGood: currentSnapshot)
            )
        }
    }

    private func receiveLiveEvent(_ event: VaultWatchEvent, vaultID: UUID) {
        guard !isShutDown else { return }
        var journal = pendingLiveEvents[vaultID] ?? VaultWatchEventJournal(capacity: 256)
        journal.append(event)
        pendingLiveEvents[vaultID] = journal
        startLiveIndexRefreshIfNeeded()
    }

    private func beginSourceMutation() async throws -> WorkspaceSourceOperationLease {
        try requireActive()
        do {
            let lease = try await acquireWorkspaceSourceOperation(.sourceMutation)
            do {
                try Task.checkCancellation()
                try requireActive()
                return lease
            } catch {
                releaseWorkspaceSourceOperation(lease)
                throw error
            }
        } catch WorkspaceSourceOperationGateError.shutDown {
            throw ScholiumApplicationError.workspaceShutDown(id)
        }
    }

    /// Agent change-request validation reads source-bound identities and local
    /// executions that permanent deletion may remove. Borrowing the same gate
    /// keeps those checks and their store write on one side of every source
    /// mutation instead of leaving an orphaned private request across actor
    /// reentrancy.
    func beginAgentNoteChangeCoordination() async throws -> WorkspaceSourceOperationLease {
        try await beginSourceMutation()
    }

    /// Research Method, Profile, Skill, and standing-policy writes share the
    /// Agent decision gate so an exact-current check and its non-authorizing
    /// durable decision cannot be separated by an in-App configuration edit.
    func beginResearchConfigurationMutation() async throws -> WorkspaceSourceOperationLease {
        try await beginSourceMutation()
    }

    private func endSourceMutation(_ lease: WorkspaceSourceOperationLease) {
        releaseWorkspaceSourceOperation(lease)
        startLiveIndexRefreshIfNeeded()
    }

    func endAgentNoteChangeCoordination(_ lease: WorkspaceSourceOperationLease) {
        endSourceMutation(lease)
    }

    func endResearchConfigurationMutation(_ lease: WorkspaceSourceOperationLease) {
        endSourceMutation(lease)
        let snapshot = currentSnapshot
        let events = events
        Task {
            await events.publishResearchConfigurationInvalidated(snapshot: snapshot)
        }
    }

    private func beginRefreshCycle() async throws -> WorkspaceSourceOperationLease {
        try requireActive()
        do {
            let lease = try await acquireWorkspaceSourceOperation(.refreshCycle)
            do {
                try Task.checkCancellation()
                try requireActive()
                return lease
            } catch {
                releaseWorkspaceSourceOperation(lease)
                throw error
            }
        } catch WorkspaceSourceOperationGateError.shutDown {
            throw ScholiumApplicationError.workspaceShutDown(id)
        }
    }

    private func endRefreshCycle(_ lease: WorkspaceSourceOperationLease) {
        releaseWorkspaceSourceOperation(lease)
    }

    private func startLiveIndexRefreshIfNeeded() {
        guard !isShutDown,
              !sourceOperationGate.sourceMutationIsActive,
              !pendingLiveEvents.isEmpty,
              sourceCommitRefreshTask == nil,
              liveIndexRefreshTask == nil else { return }

        let token = UUID()
        let task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.runLiveIndexRefresh(token: token)
        }
        liveIndexRefreshTask = OwnedRefreshTask(token: token, task: task)
    }

    /// Commits and derived state intentionally have different completion
    /// semantics. The source caller receives the revision-checked repository
    /// result immediately; this actor retains and coalesces the disposable
    /// refresh work until publication or a typed stale-state event.
    private func scheduleSourceCommitRefresh(
        id: VaultQualifiedNoteID,
        kind: WorkspaceSourceCommitKind
    ) {
        pendingSourceCommitRefreshes.append(WorkspaceRefreshPayload(
            publication: .sourceCommitted(id, kind),
            failureDisposition: .staleAfterCommittedMutation(
                affectedVaultIDs: [id.vaultID]
            ),
            sourceCatalogPreparation: .inferred(
                from: .sourceCommitted(id, kind)
            )
        ))
        guard !isShutDown, sourceCommitRefreshTask == nil else { return }
        sourceCommitRefreshTask = Task(priority: .utility) { [weak self] in
            await self?.runSourceCommitRefreshes()
        }
    }

    private func runSourceCommitRefreshes() async {
        defer {
            sourceCommitRefreshTask = nil
            startLiveIndexRefreshIfNeeded()
        }
        while !isShutDown, !Task.isCancelled,
              !pendingSourceCommitRefreshes.isEmpty {
            let queued = pendingSourceCommitRefreshes
            pendingSourceCommitRefreshes.removeAll(keepingCapacity: true)
            do {
                let payload = try WorkspaceRefreshPayload.merged(queued)
                _ = try await refreshCoordinator.request(payload)
            } catch is CancellationError {
                return
            } catch {
                // `performRefreshCycle` already published the typed stale
                // state while retaining its last known-good snapshot. A
                // derived failure never turns the committed save into a
                // retryable source mutation.
            }
        }
    }

    private func runLiveIndexRefresh(token: UUID) async {
        while !isShutDown, !pendingLiveEvents.isEmpty {
            guard !sourceOperationGate.sourceMutationIsActive else { break }
            let pending = pendingLiveEvents
            pendingLiveEvents.removeAll()
            var changedVaultIDs: Set<UUID> = []
            var rootChangedVaultIDs: Set<UUID> = []
            for (vaultID, var journal) in pending {
                guard let event = journal.drain() else { continue }
                if event.rootChanged {
                    rootChangedVaultIDs.insert(vaultID)
                } else {
                    changedVaultIDs.insert(vaultID)
                }
            }
            // A root discontinuity invalidates the authority path itself. Do
            // not let an unrelated vault event clear that stale status by
            // rebuilding against a missing or relocated root.
            if !rootChangedVaultIDs.isEmpty {
                let evidence = WorkspaceDerivedRefreshEvidence(snapshot: currentSnapshot)
                derivedStateRequiresRefresh = true
                await events.publishDerivedStateChanged(
                    snapshot: currentSnapshot,
                    status: .stale(WorkspaceDerivedRefreshIssue(
                        reason: "Native observation reported that a vault root changed. The last complete derived snapshot remains available until access is restored and a refresh succeeds.",
                        affectedVaultIDs: rootChangedVaultIDs,
                        lastKnownGood: evidence
                    ))
                )
                continue
            }
            guard !changedVaultIDs.isEmpty else { continue }
            do {
                if !derivedStateRequiresRefresh {
                    // FSEvents may coalesce harmless startup activity from
                    // several roots with one real source change. Scope the
                    // refresh outcome to vaults whose authoritative Markdown
                    // inventory actually differs from the published snapshot.
                    // An unreadable source still counts as changed so the
                    // subsequent full rebuild publishes a typed, vault-local
                    // failure instead of silently discarding the event.
                    changedVaultIDs = await sourceInventoryChanges(
                        vaultIDs: changedVaultIDs
                    )
                    guard !changedVaultIDs.isEmpty else { continue }
                }
                guard !sourceOperationGate.sourceMutationIsActive else {
                    for vaultID in changedVaultIDs {
                        var journal = pendingLiveEvents[vaultID]
                            ?? VaultWatchEventJournal(capacity: 256)
                        journal.append(.reconciliationRequired(sequence: 0))
                        pendingLiveEvents[vaultID] = journal
                    }
                    break
                }
                _ = try await refresh(
                    publication: .liveInventory,
                    failureDisposition: .failed(
                        affectedVaultIDs: changedVaultIDs
                    )
                )
            } catch {
                // `refresh` already published one failed generation using the
                // complete last known good snapshot. Retain it for the next
                // native event or explicit refresh; never masquerade an
                // unchanged index as a successful rebuild.
            }
        }
        if liveIndexRefreshTask?.token == token {
            liveIndexRefreshTask = nil
            startLiveIndexRefreshIfNeeded()
        }
    }

    private func sourceInventoryChanges(vaultIDs: Set<UUID>) async -> Set<UUID> {
        let published = sourceRevisions(in: currentSnapshot)
        var changed: Set<UUID> = []
        for vaultID in vaultIDs {
            do {
                guard let catalog = services.sourceCatalogs[vaultID] else {
                    throw ScholiumApplicationError.vaultNotInWorkspace(vaultID)
                }
                let source = try await catalog.snapshot(refreshFolders: false)
                let publishedForVault = published.filter {
                    $0.key.vaultID == vaultID
                }
                guard source.documents.count == publishedForVault.count else {
                    changed.insert(vaultID)
                    continue
                }
                for document in source.documents {
                    let id = VaultQualifiedNoteID(
                        vaultID: vaultID,
                        relativePath: document.relativePath
                    )
                    if publishedForVault[id] != document.fingerprint {
                        changed.insert(vaultID)
                        break
                    }
                }
            } catch {
                guard !Task.isCancelled else { return [] }
                changed.insert(vaultID)
            }
        }
        return changed
    }

    private static func sourceInventory(
        assignment: TriptychAssignment,
        sourceCatalogs: [UUID: VaultSourceCatalog]
    ) async throws -> [VaultQualifiedNoteID: DocumentFingerprint] {
        var inputs: [WorkspaceSourceInventoryInput] = []
        for (order, slot) in WorkspaceVaultSlot.allCases.enumerated() {
            try Task.checkCancellation()
            guard let vault = assignment.vault(for: slot),
                  let catalog = sourceCatalogs[vault.id] else {
                throw ScholiumApplicationError.incompleteTriptych(assignment.id)
            }
            inputs.append(WorkspaceSourceInventoryInput(
                order: order,
                vaultID: vault.id,
                catalog: catalog
            ))
        }
        let sources = try await withThrowingTaskGroup(
            of: WorkspaceSourceInventorySnapshot.self
        ) { group in
            for input in inputs {
                group.addTask {
                    try Task.checkCancellation()
                    return WorkspaceSourceInventorySnapshot(
                        order: input.order,
                        vaultID: input.vaultID,
                        snapshot: try await input.catalog.snapshot()
                    )
                }
            }
            var loaded: [WorkspaceSourceInventorySnapshot] = []
            for try await source in group {
                loaded.append(source)
            }
            return loaded.sorted { $0.order < $1.order }
        }
        var observed: [VaultQualifiedNoteID: DocumentFingerprint] = [:]
        for source in sources {
            for document in source.snapshot.documents {
                try Task.checkCancellation()
                observed[VaultQualifiedNoteID(
                    vaultID: source.vaultID,
                    relativePath: document.relativePath
                )] =
                    document.fingerprint
            }
        }
        return observed
    }

    // Internal evidence for lifecycle tests; capabilities do not expose tasks.
    var ownedBackgroundTaskCount: Int {
        (liveWatcherTask == nil ? 0 : 1) + (liveIndexRefreshTask == nil ? 0 : 1)
    }

    var activationReconciliationCompleted: Bool {
        didCompleteActivationReconciliation
    }

    var watcherReadinessEvidence: WorkspaceWatcherReadinessEvidence? {
        guard liveWatcherTask != nil, didCompleteActivationReconciliation else { return nil }
        return WorkspaceWatcherReadinessEvidence(
            watchedVaultIDs: Set(assignment.vaults.values.map(\.id)),
            activationReconciliationCompleted: true
        )
    }

    func search(_ request: SearchRequest) async throws -> SearchResponse {
        try requireActive()
        return try await services.searchIndex.search(request)
    }

    func related(
        query: String,
        scope: SearchExecutionScope,
        searchGeneration: SearchGenerationID?,
        excluding: Set<VaultQualifiedNoteID>,
        limit: Int
    ) throws -> RelatedSearchResponse {
        try requireActive()
        let parsed = SearchQueryParser.parse(query)
        guard parsed.diagnostics.isEmpty,
              parsed.ast?.relatedIdentityNeedle != nil else {
            return RelatedSearchResponse(availability: .notApplicable)
        }
        guard let searchGeneration else {
            return RelatedSearchResponse(availability: .notApplicable)
        }
        guard currentSnapshot.discovery.searchGeneration == searchGeneration else {
            return RelatedSearchResponse(availability: .refreshing)
        }
        guard let graph = currentSnapshot.discovery.catalog.graph else {
            return RelatedSearchResponse(availability: .refreshing)
        }
        guard graph.sourceManifestHash == searchGeneration.sourceManifestHash else {
            return RelatedSearchResponse(
                availability: .stale(
                    reason: "Related connections were derived from an older source manifest."
                )
            )
        }
        return RelatedSearchResponse(
            availability: .current,
            items: currentSnapshot.discovery.catalog.relatedSearchResults(
            for: query,
            scope: scope,
            searchGeneration: currentSnapshot.discovery.searchGeneration,
            excluding: excluding,
            limit: limit
            )
        )
    }

    func researchSnapshot() throws -> WorkspaceResearchSnapshot {
        try requireActive()
        return currentSnapshot.research
    }

    func critique(workNoteID: UUID) async throws -> CritiqueAssociation? {
        try requireActive()
        return await services.critiqueRegistry.association(workNoteID: workNoteID)
    }

    func triptychSettings() async throws -> TriptychSettings {
        try requireActive()
        return try await services.controlStore.settings()
    }

    func saveTriptychSettings(_ settings: TriptychSettings) async throws {
        try requireActive()
        try await services.controlStore.saveSettings(settings)
        try await refreshAfterCommittedOperation(
            "The Triptych settings",
            publication: .researchRecords
        )
    }

    func skills() async throws -> [ResearchSkillPackage] {
        try requireActive()
        return try await services.researchSkillStore.skills()
    }

    func skillCatalog() async throws -> ResearchSkillCatalog {
        try requireActive()
        return try await services.researchSkillStore.catalog()
    }

    func skillPackage(id: String) async throws -> ResearchSkillPackage {
        try requireActive()
        return try await services.researchSkillStore.package(id: id)
    }

    func createSkill(id: String, source: String) async throws -> ResearchSkillPackage {
        try requireActive()
        let mutationLease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationLease) }
        return try await services.researchSkillStore.create(id: id, source: source)
    }

    func duplicateBundledSkill(
        id: String,
        as newID: String
    ) async throws -> ResearchSkillPackage {
        try requireActive()
        let mutationLease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationLease) }
        return try await services.researchSkillStore.duplicateBundled(id: id, as: newID)
    }

    func saveSkill(
        id: String,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchSkillPackage {
        try requireActive()
        let mutationLease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationLease) }
        return try await services.researchSkillStore.save(
            id: id,
            source: source,
            expectedRevision: expectedRevision
        )
    }

    func renameSkill(
        id: String,
        to newID: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchSkillPackage {
        try requireActive()
        let mutationLease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationLease) }
        return try await services.researchSkillStore.rename(
            id: id,
            to: newID,
            expectedRevision: expectedRevision
        )
    }

    func deleteSkill(id: String, expectedRevision: DocumentFingerprint) async throws {
        try requireActive()
        let mutationLease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationLease) }
        try await services.researchSkillStore.delete(
            id: id,
            expectedRevision: expectedRevision
        )
    }

    func skillResourcePaths(id: String) async throws -> [String] {
        try requireActive()
        return try await services.researchSkillStore.resourcePaths(id: id)
    }

    func skillResource(id: String, relativePath: String) async throws -> String {
        try requireActive()
        return try await services.researchSkillStore.resource(
            id: id,
            relativePath: relativePath
        )
    }

    func skillInstructionAssembly(
        mode: ResearchSkillMode,
        requestedSkillIDs: [String],
        mixedPhases: [ResearchSkillAssemblyPhase]
    ) async throws -> String {
        try requireActive()
        return try await services.researchSkillStore.instructionAssembly(
            mode: mode,
            requestedSkillIDs: requestedSkillIDs,
            mixedPhases: mixedPhases
        )
    }

    func resolveWorkflow(
        _ contract: ResearchWorkflowContract
    ) async throws -> ResolvedResearchWorkflowEnvelope {
        try requireActive()
        return try await ResearchWorkflowAssembler.resolve(
            contract,
            store: services.researchSkillStore
        )
    }

    private func coordinatedMoveDocument(
        _ source: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint,
        validatesCritiquePlacement: Bool
    ) async throws -> TriptychMoveCommit {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let destination = VaultQualifiedNoteID(
            vaultID: source.vaultID,
            relativePath: destinationRelativePath
        )
        let identity = try await resolvedIdentity(
            for: source,
            expectedRevision: expectedRevision
        )
        let registeredVault = try vault(id: source.vaultID)
        if validatesCritiquePlacement, registeredVault.role.allowsCritique {
            try CritiquePlacement.validateOrdinaryMove(
                from: source.relativePath,
                to: destinationRelativePath
            )
        }

        let sourceIsActive = !Self.isLifecyclePath(source.relativePath)
        let destinationIsActive = !Self.isLifecyclePath(destinationRelativePath)
        let plan: IncomingLinkRewritePlan
        let repositories: [UUID: VaultRepository]
        if sourceIsActive, destinationIsActive {
            repositories = services.repositories
            plan = try await workspaceMovePlan(moving: source, to: destination)
        } else {
            repositories = [source.vaultID: try repository(vaultID: source.vaultID)]
            plan = IncomingLinkRewritePlan(
                movedNote: source,
                destination: destination,
                graphGeneration: currentSnapshot.discovery.catalog.graph?.generation ?? 0,
                rewrites: []
            )
        }

        let coordinator = TriptychMoveCoordinator(
            triptychID: services.manifest.id,
            repositories: repositories,
            recoveryStore: services.transactionRecoveryStore
        )
        let commit = try await coordinator.move(
            plan,
            expectedRevision: expectedRevision
        )

        var identityFailure: Error?
        do {
            _ = try await services.controlStore.moveIdentity(
                id: identity.id,
                vaultID: source.vaultID,
                from: source.relativePath,
                to: destinationRelativePath,
                fingerprint: commit.committedRevision
            )
            let failures = await services.identityRecoveryCoordinator.resumePendingRebindings(
                vaultID: source.vaultID,
                repository: try repository(vaultID: source.vaultID),
                migrateCritiquePaths: assignment.vault(for: .output)?.id == source.vaultID
            )
            if let failure = failures.first(where: { $0.rebinding.noteID == identity.id }) {
                identityFailure = NoteIdentityMigrationError.incomplete(failure.message)
            }
        } catch {
            identityFailure = error
        }

        endSourceMutation(mutationLease)
        ownsMutation = false
        do {
            _ = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: Set(repositories.keys)
                ),
                sourceCatalogPreparation: Self.catalogPreparation(
                    upserts: [commit.destination] + commit.rewrites.map(\.note),
                    deletions: [commit.movedNote],
                    refreshFolderVaultIDs: [source.vaultID]
                )
            )
        } catch {
            throw ScholiumApplicationError.committedButRefreshFailed(
                commit.committedRevision,
                error.localizedDescription
            )
        }
        if let identityFailure { throw identityFailure }
        return commit
    }

    private func coordinatedMoveFolder(
        inVault vaultID: UUID,
        from sourceRelativePath: String,
        to destinationRelativePath: String,
        movesToLifecycle: Bool
    ) async throws -> FolderMoveCommit {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let sourceFolder: VaultRelativeFolderPath
        let destinationFolder: VaultRelativeFolderPath
        do {
            sourceFolder = try VaultRelativeFolderPath(sourceRelativePath)
            destinationFolder = try VaultRelativeFolderPath(destinationRelativePath)
        } catch {
            throw VaultRepositoryError.invalidRelativePath(
                sourceRelativePath + " → " + destinationRelativePath
            )
        }
        guard WorkspaceDocumentLifecycle(
            relativePath: sourceFolder.rawValue + "/placeholder.md"
        ) == .active else {
            throw VaultRepositoryError.invalidRelativePath(sourceFolder.rawValue)
        }
        let destinationLifecycle = WorkspaceDocumentLifecycle(
            relativePath: destinationFolder.rawValue + "/placeholder.md"
        )
        guard movesToLifecycle ? destinationLifecycle == .trash : destinationLifecycle == .active else {
            throw VaultRepositoryError.invalidRelativePath(destinationFolder.rawValue)
        }

        let registeredVault = try vault(id: vaultID)
        let sourceIsManagedCritiqueFolder = CritiquePlacement.isManagedCritiquePath(
            sourceFolder.rawValue + "/placeholder.md"
        )
        let destinationIsManagedCritiqueFolder = CritiquePlacement.isManagedCritiquePath(
            destinationFolder.rawValue + "/placeholder.md"
        )
        if registeredVault.role.allowsCritique,
           sourceIsManagedCritiqueFolder || destinationIsManagedCritiqueFolder {
            throw CritiquePlacementError.crossesCritiqueBoundary(
                source: sourceFolder.rawValue,
                destination: destinationFolder.rawValue
            )
        }
        guard let vaultSnapshot = currentSnapshot.vault(id: vaultID) else {
            throw ScholiumApplicationError.vaultNotInWorkspace(vaultID)
        }
        let sourcePrefix = sourceFolder.rawValue + "/"
        let destinationPrefix = destinationFolder.rawValue + "/"
        let descendants = vaultSnapshot.documents
            .filter { $0.id.relativePath.hasPrefix(sourcePrefix) }
            .sorted { $0.id.relativePath < $1.id.relativePath }
        var noteMoves: [FolderNoteMovePlan] = []
        for note in descendants {
            guard case .resolved(let stableNoteID) = note.stableIdentity else {
                throw NoteIdentityRecoveryError.identityUnresolved(note.id.relativePath)
            }
            let suffix = note.id.relativePath.dropFirst(sourcePrefix.count)
            noteMoves.append(FolderNoteMovePlan(
                stableNoteID: stableNoteID,
                source: note.id,
                destination: VaultQualifiedNoteID(
                    vaultID: vaultID,
                    relativePath: destinationPrefix + suffix
                ),
                expectedRevision: note.fingerprint
            ))
        }

        let plan: FolderIncomingLinkRewritePlan
        let repositories: [UUID: VaultRepository]
        if !movesToLifecycle {
            repositories = services.repositories
            plan = try await workspaceFolderMovePlan(
                vaultID: vaultID,
                sourceFolder: sourceFolder,
                destinationFolder: destinationFolder,
                noteMoves: noteMoves
            )
        } else {
            repositories = [vaultID: try repository(vaultID: vaultID)]
            plan = FolderIncomingLinkRewritePlan(
                vaultID: vaultID,
                sourceFolder: sourceFolder,
                destinationFolder: destinationFolder,
                graphGeneration: currentSnapshot.discovery.catalog.graph?.generation ?? 0,
                noteMoves: noteMoves,
                rewrites: []
            )
        }

        let coordinator = TriptychFolderMoveCoordinator(
            triptychID: services.manifest.id,
            repositories: repositories,
            recoveryStore: services.transactionRecoveryStore
        )
        let commit = try await coordinator.move(plan)

        var identityFailure: Error?
        do {
            _ = try await services.controlStore.moveIdentities(commit.noteMoves)
            let failures = await services.identityRecoveryCoordinator.resumePendingRebindings(
                vaultID: vaultID,
                repository: try repository(vaultID: vaultID),
                migrateCritiquePaths: assignment.vault(for: .output)?.id == vaultID
            )
            let movedIDs = Set(commit.noteMoves.map(\.stableNoteID))
            if let failure = failures.first(where: {
                movedIDs.contains($0.rebinding.noteID)
            }) {
                identityFailure = NoteIdentityMigrationError.incomplete(failure.message)
            }
        } catch {
            identityFailure = error
        }

        let affectedVaultIDs = Set(plan.rewrites.map { $0.source.vaultID })
            .union([vaultID])
        endSourceMutation(mutationLease)
        ownsMutation = false
        do {
            if commit.noteMoves.isEmpty, plan.rewrites.isEmpty {
                _ = try await refreshFolderInventory(vaultID: vaultID)
            } else {
                _ = try await refresh(
                    publication: .explicit,
                    failureDisposition: .staleAfterCommittedMutation(
                        affectedVaultIDs: affectedVaultIDs
                    ),
                    sourceCatalogPreparation: Self.catalogPreparation(
                        upserts: commit.noteMoves.map(\.destination)
                            + commit.rewrites.map(\.note),
                        deletions: commit.noteMoves.map(\.source),
                        refreshFolderVaultIDs: [vaultID]
                    )
                )
            }
        } catch {
            throw ScholiumApplicationError.operationCommittedButRefreshFailed(
                operation: "Folder move from \(sourceFolder.rawValue) to \(destinationFolder.rawValue)",
                reason: error.localizedDescription
            )
        }
        if let identityFailure { throw identityFailure }
        return commit
    }

    /// Serially republishes directory classifications after an empty-folder
    /// mutation. Unchanged source versions avoid Markdown reads and parses;
    /// the correctness-first pipeline may still reassemble the in-memory graph
    /// and synchronize an unchanged Search manifest.
    private func refreshFolderInventory(vaultID: UUID) async throws
        -> WorkspaceSnapshot
    {
        try await refresh(
            publication: .explicit,
            failureDisposition: .staleAfterCommittedMutation(
                affectedVaultIDs: [vaultID]
            ),
            sourceCatalogPreparation: Self.catalogPreparation(
                refreshFolderVaultIDs: [vaultID]
            )
        )
    }

    private func workspaceFolderMovePlan(
        vaultID: UUID,
        sourceFolder: VaultRelativeFolderPath,
        destinationFolder: VaultRelativeFolderPath,
        noteMoves: [FolderNoteMovePlan]
    ) async throws -> FolderIncomingLinkRewritePlan {
        var documents: [VaultQualifiedNoteID: NoteDocument] = [:]
        for registeredVault in orderedVaults() {
            let repository = try repository(vaultID: registeredVault.id)
            for path in try await repository.markdownRelativePaths() {
                let document = try await repository.load(relativePath: path)
                documents[VaultQualifiedNoteID(
                    vaultID: registeredVault.id,
                    relativePath: path
                )] = document
            }
        }
        for move in noteMoves {
            guard let current = documents[move.source],
                  current.fingerprint == move.expectedRevision else {
                throw VaultRepositoryError.conflict(
                    expected: move.expectedRevision,
                    current: documents[move.source]?.fingerprint ?? move.expectedRevision
                )
            }
        }
        let semantics = documents.mapValues(MarkdownSemanticDocument.init(parsing:))
        let vaultRoles = Dictionary(uniqueKeysWithValues: orderedVaults().map {
            ($0.id, $0.role)
        })
        let catalog = documents.map { id, document in
            let role = vaultRoles[id.vaultID] ?? .other
            return LinkCatalogNote(
                vaultID: id.vaultID,
                document: document,
                profile: WorkflowProfileResolver.resolve(
                    vaultRole: role,
                    frontmatter: document.parsedFrontmatter,
                    relativePath: document.relativePath
                ),
                semantic: semantics[id]
            )
        }
        let graph = LinkGraphBuilder.build(
            generation: (currentSnapshot.discovery.catalog.graph?.generation ?? 0) + 1,
            catalog: catalog,
            documents: semantics,
            resolutionScope: .workspace
        )
        return IncomingLinkRewriter.folderPlan(
            documents: documents,
            graph: graph,
            vaultID: vaultID,
            sourceFolder: sourceFolder,
            destinationFolder: destinationFolder,
            noteMoves: noteMoves
        )
    }

    private func workspaceMovePlan(
        moving source: VaultQualifiedNoteID,
        to destination: VaultQualifiedNoteID
    ) async throws -> IncomingLinkRewritePlan {
        var documents: [VaultQualifiedNoteID: NoteDocument] = [:]
        for registeredVault in orderedVaults() {
            let repository = try repository(vaultID: registeredVault.id)
            for path in try await repository.markdownRelativePaths() {
                let document = try await repository.load(relativePath: path)
                documents[VaultQualifiedNoteID(
                    vaultID: registeredVault.id,
                    relativePath: path
                )] = document
            }
        }
        let semantics = documents.mapValues(MarkdownSemanticDocument.init(parsing:))
        let vaultRoles = Dictionary(uniqueKeysWithValues: orderedVaults().map {
            ($0.id, $0.role)
        })
        let catalog = documents.map { id, document in
            let role = vaultRoles[id.vaultID] ?? .other
            return LinkCatalogNote(
                vaultID: id.vaultID,
                document: document,
                profile: WorkflowProfileResolver.resolve(
                    vaultRole: role,
                    frontmatter: document.parsedFrontmatter,
                    relativePath: document.relativePath
                ),
                semantic: semantics[id]
            )
        }
        let graph = LinkGraphBuilder.build(
            generation: (currentSnapshot.discovery.catalog.graph?.generation ?? 0) + 1,
            catalog: catalog,
            documents: semantics,
            resolutionScope: .workspace
        )
        return IncomingLinkRewriter.plan(
            documents: documents,
            graph: graph,
            moving: source,
            to: destination
        )
    }

    func resolvedIdentity(
        for id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> NoteIdentityRecord {
        let repository = try repository(vaultID: id.vaultID)
        let current = try await repository.load(relativePath: id.relativePath)
        guard current.fingerprint == expectedRevision else {
            throw VaultRepositoryError.conflict(
                expected: expectedRevision,
                current: current.fingerprint
            )
        }
        guard let note = currentSnapshot.document(id: id),
              note.fingerprint == expectedRevision,
              case .resolved(let stableID) = note.stableIdentity,
              let record = try await services.controlStore.identityRecord(
                vaultID: id.vaultID,
                relativePath: id.relativePath
              ),
              record.id == stableID else {
            throw NoteIdentityRecoveryError.identityUnresolved(id.relativePath)
        }
        return record
    }

    func resolveIdentity(
        _ ambiguity: NoteIdentityAmbiguity,
        candidateID: UUID?
    ) async throws -> NoteIdentityRecord {
        try requireActive()
        let repository = try repository(vaultID: ambiguity.vaultID)
        guard let slot = WorkspaceVaultSlot.allCases.first(where: {
            assignment.vault(for: $0)?.id == ambiguity.vaultID
        }) else {
            throw ScholiumApplicationError.vaultNotInWorkspace(ambiguity.vaultID)
        }
        let record = try await services.identityRecoveryCoordinator.resolve(
            ambiguity,
            candidateID: candidateID,
            repository: repository,
            migrateCritiquePaths: slot == .output
        )
        do {
            _ = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [ambiguity.vaultID]
                )
            )
        } catch {
            throw ScholiumApplicationError.operationCommittedButRefreshFailed(
                operation: "The note-identity resolution",
                reason: error.localizedDescription
            )
        }
        return record
    }

    func checkpointArea(vaultID: UUID) throws -> TriptychCheckpointArea {
        guard let slot = WorkspaceVaultSlot.allCases.first(where: {
            assignment.vault(for: $0)?.id == vaultID
        }) else {
            throw ScholiumApplicationError.vaultNotInWorkspace(vaultID)
        }
        switch slot {
        case .paperAnalysis: return .analyses
        case .topicKnowledge: return .topics
        case .output: return .works
        }
    }

    private static func isLifecyclePath(_ path: String) -> Bool {
        path.hasPrefix("Set Aside/") || path.hasPrefix("Trash/")
    }

    private func orderedVaults() -> [RegisteredVault] {
        WorkspaceVaultSlot.allCases.compactMap { assignment.vault(for: $0) }
    }

    func vault(id: UUID) throws -> RegisteredVault {
        guard let vault = assignment.vaults.values.first(where: { $0.id == id }) else {
            throw ScholiumApplicationError.vaultNotInWorkspace(id)
        }
        return vault
    }

    func repository(vaultID: UUID) throws -> VaultRepository {
        guard let repository = services.repositories[vaultID] else {
            throw ScholiumApplicationError.vaultNotInWorkspace(vaultID)
        }
        return repository
    }

    func requireActive() throws {
        if isShutDown { throw ScholiumApplicationError.workspaceShutDown(id) }
    }

    private static func resolvePortableControlAccess(
        worksVault: RegisteredVault,
        registry: PortableControlAccessRegistry
    ) async throws -> SecurityScopeLease {
        let worksURL = URL(
            fileURLWithPath: worksVault.canonicalPath,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL
        let expectedContainer = worksURL.deletingLastPathComponent()
        guard let access = await registry.access(forWorksURL: worksURL),
              access.canonicalContainerPath == expectedContainer.path else {
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
              resolved.startAccessingSecurityScopedResource() else {
            throw WorkspaceRegistryError.portableControlAccessUnavailable(
                expectedContainer.path
            )
        }
        return SecurityScopeLease(url: resolved, started: true)
    }
}
