import ScholiumContracts
import Foundation
import ScholiumCore
import OSLog

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
    let researchConfigurationStore: ResearchConfigurationStore
    let researchAgentSessions: ResearchAgentSessionAuthority?
    let researchSourceAccessStore: ResearchSourceAccessStore
    let indexedAttachmentAccessStore: IndexedAttachmentAccessStore
    let zotero: ZoteroOperations
    let portableResearchRecordStore: PortableResearchRecordStore
    let localResearchExecutionStore: LocalResearchExecutionStore
    let agentChangeEvidenceStore: AgentChangeEvidenceStore
    let critiqueRegistry: CritiqueRegistry
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

private struct OwnedRefreshTask: Sendable {
    let token: UUID
    let task: Task<Void, Never>
}

private struct RetainedCreatedDocument: Sendable {
    let document: NoteDocument
    let identityRecoveryWarning: String
}

enum CreatedDocumentIdentityRollbackError: LocalizedError, Sendable {
    case sourceRolledBack(path: String, identityFailure: String)
    case sourcePresenceUncertain(
        path: String,
        identityFailure: String,
        rollbackFailure: String,
        observationFailure: String
    )

    var errorDescription: String? {
        switch self {
        case .sourceRolledBack(let path, let identityFailure):
            "Scholium removed the newly created source at \(path) after portable identity setup failed. No new Note remains. Identity: \(identityFailure)"
        case .sourcePresenceUncertain(
            let path,
            let identityFailure,
            let rollbackFailure,
            let observationFailure
        ):
            "Scholium could not determine whether the newly created note at \(path) remains after stable identity setup and rollback both failed. Do not repeat creation until the vault has been refreshed and inspected. Identity: \(identityFailure) Rollback: \(rollbackFailure) Observation: \(observationFailure)"
        }
    }
}

enum ManagedCreationFinalVerificationError: LocalizedError, Sendable {
    case sourceAndIdentityNotJointlyProven(String)

    var errorDescription: String? {
        switch self {
        case .sourceAndIdentityNotJointlyProven(let path):
            "Scholium created \(path) but could not jointly prove its final source and reserved portable identity. Recovery must reconcile the creation before it can be reported as complete."
        }
    }
}

private enum DocumentSaveCompletion: Equatable {
    /// Return only after the matching derived workspace generation publishes.
    case sourceAndDerived
    /// Return after the authoritative repository commit and refresh in the
    /// Workspace-owned background queue.
    case sourceOnly
}

struct ResearchDocumentSaveTransaction: Sendable {
    let runID: UUID
    let operationID: UUID
    let target: ResearchWriteTargetHandle
    let noteID: UUID
    let role: ResearchActionTargetRole
}

enum ResearchDocumentSaveOutcome: Sendable {
    case committed(WorkspaceMutationOutcome<SaveResult>)
    case notWritten(VaultSaveNotWrittenReason)
    case recoveryRequired(TriptychMutationRecoveryRecord)
}

private enum DocumentSaveOperationOutcome: Sendable {
    case committed(WorkspaceMutationOutcome<SaveResult>)
    case notWritten(VaultSaveNotWrittenReason)
    case recoveryRequired(TriptychMutationRecoveryRecord)
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

/// Builds the complete descendant identity plan from the last complete
/// Workspace generation plus durable identities committed ahead of it. Folder
/// paths have no identity of their own, so a second Folder move must follow
/// each Note identity to its current path instead of reusing stale descendants
/// from the earlier generation.
func sourceAuthorizedFolderNoteMoves(
    vaultID: UUID,
    sourceFolder: VaultRelativeFolderPath,
    destinationFolder: VaultRelativeFolderPath,
    snapshotDocuments: [WorkspaceNoteSnapshot],
    sourceAheadIdentityRecords: [VaultQualifiedNoteID: NoteIdentityRecord]
) throws -> [FolderNoteMovePlan] {
    let sourcePrefix = sourceFolder.rawValue + "/"
    let destinationPrefix = destinationFolder.rawValue + "/"
    let sourceAhead = try sourceAheadIdentityRecords.map { location, record in
        guard location.vaultID == record.vaultID,
              location.relativePath == record.relativePath else {
            throw TriptychTransactionError.invalidPlan(
                "A source-ahead identity record does not match its current location."
            )
        }
        return record
    }.filter { $0.vaultID == vaultID }
    let sourceAheadIDs = Set(sourceAhead.map(\.id))
    let sourceAheadPaths = Set(sourceAhead.map(\.relativePath))

    var authorizationByID: [UUID: (path: String, revision: DocumentFingerprint)] = [:]
    for note in snapshotDocuments where note.id.vaultID == vaultID {
        if sourceAheadPaths.contains(note.id.relativePath) { continue }
        guard let stableNoteID = note.stableIdentity.resolvedID else {
            if note.id.relativePath.hasPrefix(sourcePrefix) {
                throw NoteIdentityRecoveryError.identityUnresolved(
                    note.id.relativePath
                )
            }
            continue
        }
        guard !sourceAheadIDs.contains(stableNoteID) else { continue }
        authorizationByID[stableNoteID] = (
            path: note.id.relativePath,
            revision: note.fingerprint
        )
    }
    for record in sourceAhead {
        authorizationByID[record.id] = (
            path: record.relativePath,
            revision: record.fingerprint
        )
    }

    let descendants: [FolderNoteMovePlan] = authorizationByID.compactMap {
        stableNoteID, source -> FolderNoteMovePlan? in
        guard source.path.hasPrefix(sourcePrefix) else { return nil }
        let suffix = source.path.dropFirst(sourcePrefix.count)
        return FolderNoteMovePlan(
            stableNoteID: stableNoteID,
            source: VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: source.path
            ),
            destination: VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: destinationPrefix + suffix
            ),
            expectedRevision: source.revision
        )
    }.sorted { $0.source < $1.source }
    guard Set(descendants.map(\.source)).count == descendants.count else {
        throw TriptychTransactionError.invalidPlan(
            "Several stable Note identities claim the same Folder descendant."
        )
    }
    return descendants
}

/// Per-Triptych application boundary shared by every consumer of a runtime.
/// The actor borrows the runtime's identity-pooled vault authorities and owns
/// only the Triptych-level composition, snapshots, and publication lifetime.
public actor WorkspaceHandle: WorkspaceSourceOperationGateOwner {
    private nonisolated static let refreshLogger = Logger(
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
    public nonisolated let zoteroBindings: ZoteroBindingOperations

    let services: WorkspaceServices
    let researchContinuationDependencies:
        WorkspaceResearchContinuationDependencies
    let researchWorkspaceDependencies:
        WorkspaceResearchOperationsDependencies
    let researchBoundedWriteDependencies:
        WorkspaceResearchBoundedWriteDependencies
    let researchAgentDiscussionDependencies:
        WorkspaceResearchAgentDiscussionDependencies
    let researchMethodImprovementDependencies:
        WorkspaceResearchMethodImprovementDependencies
    let researchAgentConnectionDependencies:
        WorkspaceResearchAgentConnectionDependencies
    let researchAgentResultDependencies:
        WorkspaceResearchAgentResultDependencies
    let researchActionResolverDependencies:
        WorkspaceResearchActionResolverDependencies
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
    private var openingCompletionTask: Task<Void, Never>?
    private let openingPresentationSignal = AsyncStream<Void>.makeStream(
        bufferingPolicy: .bufferingNewest(1)
    )
    private var liveIndexRefreshTask: OwnedRefreshTask?
    private var sourceCommitRefreshTask: Task<Void, Never>?
    private var pendingSourceCommitRefreshes: [WorkspaceRefreshPayload] = []
    /// Exact identity records from durable source moves whose complete
    /// Workspace generation has not arrived yet. This is a bounded authority
    /// bridge for a second revision-checked operation, not a derived cache.
    private var sourceAheadIdentityRecords: [VaultQualifiedNoteID: NoteIdentityRecord] = [:]
    private var pendingLiveEvents: [UUID: VaultWatchEventJournal] = [:]
    var sourceOperationGate = WorkspaceSourceOperationGate()
    private var managedCreationPreLeaseBarrierForTesting:
        (@Sendable () async -> Void)?
    private var managedCreationPostSourceBarrierForTesting:
        (@Sendable () async -> Void)?
    var researchCreationRecoveryObservationBarrierForTesting:
        (@Sendable () async -> Void)?
    private var researchDocumentSavePreflightBarrierForTesting:
        (@Sendable () async -> Void)?
    var researchFunctionControlledObservationBarrierForTesting:
        (@Sendable () async -> Void)?
    private var progressiveActivationReconciliationBarrierForTesting:
        (@Sendable () async -> Void)?
    private var researchStateRepairBarrierForTesting:
        (@Sendable () async throws -> Void)?
    var agentStartPostBindingBarrierForTesting:
        (@Sendable () async throws -> Void)?
    private var didCompleteActivationReconciliation = false

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

    func setResearchCreationRecoveryObservationBarrierForTesting(
        _ barrier: (@Sendable () async -> Void)?
    ) {
        researchCreationRecoveryObservationBarrierForTesting = barrier
    }

    func setResearchDocumentSavePreflightBarrierForTesting(
        _ barrier: (@Sendable () async -> Void)?
    ) {
        researchDocumentSavePreflightBarrierForTesting = barrier
    }

    func setResearchFunctionControlledObservationBarrierForTesting(
        _ barrier: (@Sendable () async -> Void)?
    ) {
        researchFunctionControlledObservationBarrierForTesting = barrier
    }

    func setProgressiveActivationReconciliationBarrierForTesting(
        _ barrier: (@Sendable () async -> Void)?
    ) {
        progressiveActivationReconciliationBarrierForTesting = barrier
    }

    func setResearchStateRepairBarrierForTesting(
        _ barrier: (@Sendable () async throws -> Void)?
    ) {
        researchStateRepairBarrierForTesting = barrier
    }

    func setAgentStartPostBindingBarrierForTesting(
        _ barrier: (@Sendable () async throws -> Void)?
    ) {
        agentStartPostBindingBarrierForTesting = barrier
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
        researchFunctionCoordinator: ResearchFunctionCoordinator,
        documents: DocumentOperations,
        discovery: DiscoveryOperations,
        research: ResearchOperations,
        zoteroBindings: ZoteroBindingOperations
    ) {
        id = assignment.id
        runtimeIdentity = TriptychRuntimeIdentity(
            triptychID: assignment.id,
            activationID: UUID()
        )
        self.assignment = assignment
        self.mode = mode
        self.services = services
        self.researchContinuationDependencies = services.researchContinuationDependencies
        self.researchWorkspaceDependencies = services.researchWorkspaceDependencies
        self.researchBoundedWriteDependencies = services.researchBoundedWriteDependencies
        self.researchAgentDiscussionDependencies = services.researchAgentDiscussionDependencies
        self.researchMethodImprovementDependencies = services.researchMethodImprovementDependencies
        self.researchAgentConnectionDependencies = services.researchAgentConnectionDependencies
        self.researchAgentResultDependencies = services.researchAgentResultDependencies
        self.researchActionResolverDependencies = services.researchActionResolverDependencies
        self.researchFunctionCoordinator = researchFunctionCoordinator
        self.leases = leases
        currentSnapshot = initialSnapshot
        latestRefreshMeasurement = initialRefreshMeasurement
        self.documents = documents
        self.discovery = discovery
        self.research = research
        self.zoteroBindings = zoteroBindings
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
        researchAgentSessions: ResearchAgentSessionAuthority?,
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
                  let worksURL = resolvedURLs[.output] else {
                throw ScholiumApplicationError.incompleteTriptych(assignment.id)
            }

            if case .live = access {
                let portable = try resolvePortableControlAccess(
                    worksVault: worksVault,
                    access: assignment.triptych.portableControlAccess
                )
                leases.append(portable)
            }

            let triptychStorage = applicationSupportURL
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

            let researchConfigurationStore = ResearchConfigurationStore(
                controlURL: controlURL,
                triptychID: assignment.id,
                machineStorageURL: triptychStorage
                    .appendingPathComponent("research-guidance", isDirectory: true)
            )
            do {
                try await researchConfigurationStore.bootstrapDefaults()
            } catch let error as ResearchConfigurationStoreError {
                switch error {
                case .invalidDocument:
                    throw ScholiumApplicationError.portableControlRecoveryRequired(
                        controlPath: controlURL.path,
                        reason: error.localizedDescription
                    )
                default:
                    throw error
                }
            }

            let vaultIDs = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map {
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
                     .invalidZoteroBindings, .invalidIdentities:
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

            let portableResearchRecordStore = try PortableResearchRecordStore(
                controlURL: controlURL,
                applicationSupportURL: applicationSupportURL,
                triptychID: manifest.id
            )
            let localResearchExecutionStore = try LocalResearchExecutionStore(
                applicationSupportURL: applicationSupportURL,
                triptychID: manifest.id
            )
            let agentChangeEvidenceStore = try AgentChangeEvidenceStore(
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
            let services = WorkspaceServices(
                manifest: manifest,
                repositories: repositories,
                sourceCatalogs: Dictionary(uniqueKeysWithValues: pooledVaults.map {
                    ($0.key, $0.value.sourceCatalog)
                }),
                searchIndex: openedSearchIndex.index,
                controlStore: controlStore,
                researchConfigurationStore: researchConfigurationStore,
                researchAgentSessions: researchAgentSessions,
                researchSourceAccessStore: ResearchSourceAccessStore(
                    applicationSupportURL: applicationSupportURL,
                    triptychID: manifest.id
                ),
                indexedAttachmentAccessStore: try IndexedAttachmentAccessStore(
                    applicationSupportURL: applicationSupportURL,
                    triptychID: manifest.id
                ),
                zotero: zotero,
                portableResearchRecordStore: portableResearchRecordStore,
                localResearchExecutionStore: localResearchExecutionStore,
                agentChangeEvidenceStore: agentChangeEvidenceStore,
                critiqueRegistry: critiqueRegistry,
                transactionRecoveryStore: transactionRecoveryStore,
                identityRecoveryCoordinator: NoteIdentityRecoveryCoordinator(
                    control: controlStore,
                    critiques: critiqueRegistry,
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
            let preOpenInventory = mode == .live && !usesProgressiveOpening
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
            let repairedInitialBuild = try await WorkspaceResearchStateReconciler
                .repairBeforePublication(
                    build: initialBuild,
                    triptychID: assignment.id,
                    dependencies: services.researchStateReconcilerDependencies
                )
            let snapshotReady = clock.now
            let initialSnapshot = repairedInitialBuild.snapshot
            logRefresh(repairedInitialBuild.measurement, publicationDuration: nil)
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
                    controlStore: services.controlStore,
                    researchConfigurationStore: services.researchConfigurationStore,
                    sourceAccessStore: services.researchSourceAccessStore,
                    portableResearchRecordStore: services.portableResearchRecordStore,
                    localExecutionStore: services.localResearchExecutionStore,
                    agentChangeEvidenceStore: services.agentChangeEvidenceStore,
                    zotero: services.zotero
                )
            )
            let researchOperations = ResearchOperations(
                reference: reference,
                functionCoordinator: researchFunctionCoordinator,
                recoveryRecordsURL: services.transactionRecoveryStore.storageURL
            )
            let zoteroBindingOperations = ZoteroBindingOperations(
                reference: reference
            )
            let handle = WorkspaceHandle(
                assignment: assignment,
                mode: mode,
                services: services,
                leases: leases,
                initialSnapshot: initialSnapshot,
                initialRefreshMeasurement: repairedInitialBuild.measurement,
                initialWorkspaceGeneration: initialWorkspaceGeneration,
                reference: reference,
                researchFunctionCoordinator: researchFunctionCoordinator,
                documents: documentOperations,
                discovery: discoveryOperations,
                research: researchOperations,
                zoteroBindings: zoteroBindingOperations
            )
            await reference.bind(handle)
            if case .live = access {
                let activationInventory: [
                    VaultQualifiedNoteID: DocumentFingerprint
                ]
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

    func importMarkdown(
        at sourceURL: URL,
        intoVault vaultID: UUID
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> {
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
        var committedDocument = document
        var identityRecoveryWarning: String?
        do {
            guard try await services.controlStore.identity(
                forVaultID: vaultID,
                relativePath: document.relativePath,
                fingerprint: document.fingerprint
            ) != nil else {
                throw NoteIdentityRecoveryError.identityUnresolved(document.relativePath)
            }
        } catch let identityError {
            guard let retained = try await retainedCreatedDocumentAfterIdentityFailure(
                repository: repository,
                document: document,
                identityError: identityError
            ) else {
                throw identityError
            }
            committedDocument = retained.document
            identityRecoveryWarning = retained.identityRecoveryWarning
        }
        endSourceMutation(mutationLease)
        ownsMutation = false
        return await finishCreatedDocumentMutation(
            id: id,
            document: committedDocument,
            identityRecoveryWarning: identityRecoveryWarning
        )
    }

    func importImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedImageAttachment {
        try requireActive()
        let secured = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if secured { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let mutationLease = try await beginSourceMutation()
        defer { endSourceMutation(mutationLease) }

        let repository = try repository(vaultID: note.vaultID)
        _ = try await repository.load(relativePath: note.relativePath)
        let fileStore = VaultAttachmentStore(vaultURL: await repository.vaultURL)
        let attachmentID = UUID()
        let preparedFile = try await fileStore.prepareImage(
            at: sourceURL,
            attachmentID: attachmentID,
            noteRelativePath: note.relativePath,
            management: .importIntoAttachments
        )
        return try await registerPreparedImageFile(
            preparedFile,
            attachmentID: attachmentID,
            vaultID: note.vaultID,
            fileStore: fileStore,
            indexedSourceURL: nil
        )
    }

    func indexImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedImageAttachment {
        try requireActive()
        let secured = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if secured { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let mutationLease = try await beginSourceMutation()
        defer { endSourceMutation(mutationLease) }

        let repository = try repository(vaultID: note.vaultID)
        _ = try await repository.load(relativePath: note.relativePath)
        let fileStore = VaultAttachmentStore(vaultURL: await repository.vaultURL)
        let attachmentID = UUID()
        let preparedFile = try await fileStore.prepareImage(
            at: sourceURL,
            attachmentID: attachmentID,
            noteRelativePath: note.relativePath,
            management: .indexAbsolutePath
        )
        return try await registerPreparedImageFile(
            preparedFile,
            attachmentID: attachmentID,
            vaultID: note.vaultID,
            fileStore: fileStore,
            indexedSourceURL: sourceURL
        )
    }

    func importPastedImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedImageAttachment {
        try requireActive()
        let secured = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if secured { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let mutationLease = try await beginSourceMutation()
        defer { endSourceMutation(mutationLease) }

        let repository = try repository(vaultID: note.vaultID)
        _ = try await repository.load(relativePath: note.relativePath)
        let fileStore = VaultAttachmentStore(vaultURL: await repository.vaultURL)
        let attachmentID = UUID()
        let preparedFile = try await fileStore.prepareImage(
            at: sourceURL,
            attachmentID: attachmentID,
            noteRelativePath: note.relativePath,
            management: .importIntoAttachments
        )
        return try await registerPreparedImageFile(
            preparedFile,
            attachmentID: attachmentID,
            vaultID: note.vaultID,
            fileStore: fileStore,
            indexedSourceURL: nil
        )
    }

    func importPastedImageAttachment(
        data: Data,
        preferredFilename: String,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedImageAttachment {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        defer { endSourceMutation(mutationLease) }

        let repository = try repository(vaultID: note.vaultID)
        _ = try await repository.load(relativePath: note.relativePath)
        let fileStore = VaultAttachmentStore(vaultURL: await repository.vaultURL)
        let attachmentID = UUID()
        let preparedFile = try await fileStore.preparePastedImage(
            data: data,
            preferredFilename: preferredFilename,
            attachmentID: attachmentID,
            noteRelativePath: note.relativePath
        )
        return try await registerPreparedImageFile(
            preparedFile,
            attachmentID: attachmentID,
            vaultID: note.vaultID,
            fileStore: fileStore,
            indexedSourceURL: nil
        )
    }

    private func registerPreparedImageFile(
        _ preparedFile: PreparedVaultImageFile,
        attachmentID: UUID,
        vaultID: UUID,
        fileStore: VaultAttachmentStore,
        indexedSourceURL: URL?
    ) async throws -> PreparedImageAttachment {
        let registration: (record: PortableAttachmentRecord, created: Bool)
        do {
            registration = try await services.controlStore.registerAttachment(
                vaultID: vaultID,
                location: preparedFile.location,
                preferredID: attachmentID
            )
        } catch {
            if let fingerprint = preparedFile.copiedFileFingerprint,
               let copiedRelativePath = preparedFile.copiedRelativePath {
                if let imageError = error as? ImageAttachmentError,
                   case .catalogCommitUncertain = imageError {
                    throw error
                }
                do {
                    try await fileStore.removeCopiedImageIfExact(
                        relativePath: copiedRelativePath,
                        expectedFingerprint: fingerprint
                    )
                } catch let cleanupError {
                    throw ImageAttachmentError.preparationCleanupFailed(
                        operation: error.localizedDescription,
                        cleanup: cleanupError.localizedDescription
                    )
                }
            }
            throw error
        }

        var createdLocalAccessRecord = false
        if case .absolutePath(let path) = registration.record.location {
            guard let indexedSourceURL else {
                throw IndexedAttachmentAccessError.bookmarkUnavailable(path)
            }
            do {
                createdLocalAccessRecord = try await services
                    .indexedAttachmentAccessStore.register(
                        attachmentID: registration.record.id,
                        selectedURL: indexedSourceURL,
                        expectedAbsolutePath: path
                    )
            } catch {
                if registration.created {
                    do {
                        try await services.controlStore.removeAttachment(
                            registration.record
                        )
                    } catch let cleanupError {
                        throw ImageAttachmentError.preparationCleanupFailed(
                            operation: error.localizedDescription,
                            cleanup: cleanupError.localizedDescription
                        )
                    }
                }
                throw error
            }
        }
        return PreparedImageAttachment(
            record: registration.record,
            markdownDestination: preparedFile.markdownDestination,
            altText: preparedFile.altText,
            copiedFileFingerprint: preparedFile.copiedFileFingerprint,
            createdCatalogRecord: registration.created,
            createdLocalAccessRecord: createdLocalAccessRecord
        )
    }

    func rollbackImageAttachment(
        _ preparation: PreparedImageAttachment
    ) async throws {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        defer { endSourceMutation(mutationLease) }

        if preparation.createdCatalogRecord {
            // Keep Finder bytes when catalog cleanup is uncertain: a remaining
            // portable record must never be made to point at a missing file.
            try await services.controlStore.removeAttachment(preparation.record)
        }
        if preparation.createdLocalAccessRecord {
            try await services.indexedAttachmentAccessStore.removeIfPresent(
                attachmentID: preparation.record.id
            )
        }
        if let fingerprint = preparation.copiedFileFingerprint {
            guard case .vaultRelative(let relativePath) = preparation.record.location else {
                throw ImageAttachmentError.cleanupRefused(
                    preparation.record.location.path
                )
            }
            let repository = try repository(vaultID: preparation.record.vaultID)
            let fileStore = VaultAttachmentStore(vaultURL: await repository.vaultURL)
            try await fileStore.removeCopiedImageIfExact(
                relativePath: relativePath,
                expectedFingerprint: fingerprint
            )
        }
    }

    func unavailableIndexedImagePaths(
        in markdownSource: String
    ) async throws -> [String] {
        let referencedPaths = IndexedImageReferences.absolutePaths(
            in: markdownSource
        )
        guard !referencedPaths.isEmpty else { return [] }
        let records = try await services.controlStore.attachmentRecords()
        var unavailable: [String] = []
        for record in records {
            guard case .absolutePath(let path) = record.location,
                  referencedPaths.contains(path) else { continue }
            if try await services.indexedAttachmentAccessStore.isAvailable(
                attachmentID: record.id,
                expectedAbsolutePath: path
            ) == false {
                unavailable.append(path)
            }
        }
        return unavailable.sorted()
    }

    func createDocument(
        _ id: VaultQualifiedNoteID,
        content: String
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> {
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
        var committedDocument = document
        var identityRecoveryWarning: String?
        do {
            guard try await services.controlStore.identity(
                forVaultID: id.vaultID,
                relativePath: id.relativePath,
                fingerprint: document.fingerprint
            ) != nil else {
                throw NoteIdentityRecoveryError.identityUnresolved(id.relativePath)
            }
        } catch let identityError {
            guard let retained = try await retainedCreatedDocumentAfterIdentityFailure(
                repository: repository,
                document: document,
                identityError: identityError
            ) else {
                throw identityError
            }
            committedDocument = retained.document
            identityRecoveryWarning = retained.identityRecoveryWarning
        }
        endSourceMutation(mutationLease)
        ownsMutation = false
        return await finishCreatedDocumentMutation(
            id: id,
            document: committedDocument,
            identityRecoveryWarning: identityRecoveryWarning
        )
    }

    /// The sole managed creator for GUI, researcher CLI, and authenticated
    /// Agent delivery. It snapshots one valid Settings revision, composes one
    /// complete candidate, atomically claims the path, and then commits the
    /// portable stable identity before publishing a source-ahead result.
    func createManagedNote(
        _ request: ManagedNoteCreationRequest
    ) async throws -> WorkspaceMutationOutcome<WorkspaceManagedNoteCommit> {
        try requireActive()
        guard let slot = services.manifest.vaultIDs.first(where: {
            $0.value == request.vaultID
        })?.key else {
            throw ScholiumApplicationError.vaultNotInWorkspace(request.vaultID)
        }
        if let barrier = managedCreationPreLeaseBarrierForTesting {
            await barrier()
        }
        // Settings mutation and source creation share this lease. Reading the
        // revision after acquisition closes the reentrant gap between the
        // frozen Agent authorization and the no-replace filesystem claim.
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let settingsSnapshot = try await services.controlStore.settings()
        let reservedIdentity: UUID
        switch request.authority {
        case .researcher:
            reservedIdentity = UUID()
        case .authenticatedAgent(let expectedRevision, let identity):
            guard expectedRevision == settingsSnapshot.revision else {
                throw DocumentCreationError.settingsRevisionChanged
            }
            reservedIdentity = identity
        }
        let initialSource = try managedCreationSource(
            request: request,
            slot: slot,
            settings: settingsSnapshot.settings
        )
        let repository = try repository(vaultID: request.vaultID)
        let registeredVault = try vault(id: request.vaultID)

        var ordinal = 1
        while true {
            try Task.checkCancellation()
            let relativePath: String = switch request.destination {
            case .exact(let path):
                path
            case .untitled(let folderRelativePath):
                if let folderRelativePath, !folderRelativePath.isEmpty {
                    "\(folderRelativePath)/\(ordinal == 1 ? "Untitled.md" : "Untitled \(ordinal).md")"
                } else {
                    ordinal == 1 ? "Untitled.md" : "Untitled \(ordinal).md"
                }
            }
            let id = VaultQualifiedNoteID(
                vaultID: request.vaultID,
                relativePath: relativePath
            )
            if registeredVault.role.allowsCritique,
               CritiquePlacement.isManagedCritiquePath(relativePath) {
                throw CritiquePlacementError.directCreationRequiresRequestCritique
            }
            if try await services.controlStore.identityRecord(
                vaultID: request.vaultID,
                relativePath: relativePath
            ) != nil {
                switch request.destination {
                case .exact:
                    throw DocumentCreationError.portableIdentityAlreadyExists
                case .untitled:
                    ordinal += 1
                    continue
                }
            }
            do {
                let document = try await repository.create(
                    relativePath: relativePath,
                    content: initialSource
                )
                if let barrier = managedCreationPostSourceBarrierForTesting {
                    await barrier()
                }
                var committedDocument = document
                var stableIdentity = WorkspaceNoteIdentityState.unresolved
                var createdIdentityRecord: NoteIdentityRecord?
                var identityRecoveryWarning: String?
                do {
                    guard let identity = try await services.controlStore.identity(
                        forVaultID: request.vaultID,
                        relativePath: relativePath,
                        fingerprint: document.fingerprint,
                        preferredID: reservedIdentity
                    ) else {
                        throw NoteIdentityRecoveryError.identityUnresolved(relativePath)
                    }
                    if identity.id != reservedIdentity {
                        throw DocumentCreationError.reservedIdentityMismatch
                    }
                    stableIdentity = .resolved(identity.id)
                    createdIdentityRecord = identity
                } catch let identityError {
                    let retained: RetainedCreatedDocument
                    do {
                        guard let result = try await retainedCreatedDocumentAfterIdentityFailure(
                            repository: repository,
                            document: document,
                            identityError: identityError
                        ) else {
                            throw identityError
                        }
                        retained = result
                    } catch let rollbackError as CreatedDocumentIdentityRollbackError {
                        if case .researcher = request.authority,
                           case .sourcePresenceUncertain = rollbackError {
                            let record = try await recordManagedCreationRecovery(
                                vaultID: request.vaultID,
                                relativePath: relativePath,
                                reservedIdentityID: reservedIdentity,
                                intendedRevision: document.fingerprint,
                                repository: repository,
                                failure: rollbackError.localizedDescription
                            )
                            throw TriptychTransactionError.recoveryRequired(record)
                        }
                        throw rollbackError
                    }
                    committedDocument = retained.document
                    identityRecoveryWarning = retained.identityRecoveryWarning
                    if case .researcher = request.authority {
                        let record = try await recordManagedCreationRecovery(
                            vaultID: request.vaultID,
                            relativePath: relativePath,
                            reservedIdentityID: reservedIdentity,
                            intendedRevision: document.fingerprint,
                            repository: repository,
                            failure: retained.identityRecoveryWarning
                        )
                        throw TriptychTransactionError.recoveryRequired(record)
                    }
                }

                if identityRecoveryWarning == nil {
                    do {
                        let finalDocument = try await repository.load(
                            relativePath: relativePath
                        )
                        let finalIdentity = try await services.controlStore
                            .identityRecord(
                                vaultID: request.vaultID,
                                relativePath: relativePath
                            )
                        guard finalDocument.fingerprint == document.fingerprint,
                              finalIdentity?.id == reservedIdentity,
                              finalIdentity?.fingerprint == document.fingerprint else {
                            throw ManagedCreationFinalVerificationError
                                .sourceAndIdentityNotJointlyProven(relativePath)
                        }
                        committedDocument = finalDocument
                        stableIdentity = .resolved(reservedIdentity)
                        createdIdentityRecord = finalIdentity
                    } catch {
                        let verification = ManagedCreationFinalVerificationError
                            .sourceAndIdentityNotJointlyProven(relativePath)
                        if case .researcher = request.authority {
                            let record = try await recordManagedCreationRecovery(
                                vaultID: request.vaultID,
                                relativePath: relativePath,
                                reservedIdentityID: reservedIdentity,
                                intendedRevision: document.fingerprint,
                                repository: repository,
                                failure: verification.localizedDescription
                            )
                            throw TriptychTransactionError.recoveryRequired(record)
                        }
                        throw verification
                    }
                }

                sourceAheadIdentityRecords[id] = createdIdentityRecord
                // Queue the only complete derived rebuild before releasing the
                // source lease. A matching watcher event therefore remains
                // behind this owned task instead of starting a duplicate cycle.
                scheduleSourceCommitRefresh(id: id, kind: .creation)
                endSourceMutation(mutationLease)
                ownsMutation = false
                return WorkspaceMutationOutcome(
                    committedValue: WorkspaceManagedNoteCommit(
                        id: id,
                        vaultRole: registeredVault.role,
                        stableIdentity: stableIdentity,
                        document: committedDocument
                    ),
                    identityRecoveryWarning: identityRecoveryWarning
                )
            } catch let error as VaultRepositoryError {
                switch error {
                case .fileAlreadyExists, .pathCollision:
                    guard case .untitled = request.destination else { throw error }
                    ordinal += 1
                default:
                    throw error
                }
            }
        }
    }

    func managedCreationSource(
        request: ManagedNoteCreationRequest,
        slot: WorkspaceVaultSlot,
        settings: TriptychSettings
    ) throws -> String {
        let seed = settings.properties[slot]?.newNoteYAML
        let seedKeys = try TriptychSettingsValidator.seedKeys(in: seed, role: slot)
        let dynamic: String
        if let metadata = request.analysisMetadata {
            guard slot == .paperAnalysis else {
                throw DocumentCreationError.analysisMetadataRoleMismatch
            }
            let profile = AnalysisSourceTypeProfileCatalog.profile(
                for: metadata.sourceType
            )
            let applicable = Set(profile.applicableFields)
            var values: [String: YAMLValue] = [
                "type": .string(metadata.sourceType.rawValue),
            ]
            for input in metadata.properties {
                guard applicable.contains(input.key),
                      PropertyContractCatalog.contract(
                        for: input.key,
                        profile: .analysis
                      ) != nil else {
                    throw DocumentCreationError.inapplicableAnalysisProperty(
                        input.key,
                        metadata.sourceType
                    )
                }
                guard !seedKeys.contains(input.key) else {
                    throw DocumentCreationError.analysisSeedCollision(input.key)
                }
                values[input.key] = input.value
            }
            let issues = PropertyContractCatalog.validate(
                frontmatter: values,
                profile: .analysis
            )
            guard issues.isEmpty,
                  metadata.properties.allSatisfy({
                      Self.isNonemptyManagedValue($0.value)
                  }) else {
                throw DocumentCreationError.invalidMetadata(issues)
            }
            if case .authenticatedAgent = request.authority {
                let required = Set(
                    settings.analysisAgentCreation.requiredFields(
                        for: metadata.sourceType
                    )
                )
                let supplied = Set(metadata.properties.map(\.key))
                let missing = required.subtracting(supplied).sorted()
                guard missing.isEmpty else {
                    throw DocumentCreationError.missingRequiredAgentFields(missing)
                }
            }
            let order = ["type"] + profile.serializationFieldOrder.filter {
                values[$0] != nil && $0 != "type"
            }
            dynamic = try FrontmatterPatchPlanner.serializeTopLevelMapping(
                try order.map { key in
                    guard let value = values[key] else {
                        throw DocumentCreationError.invalidMetadata([])
                    }
                    return (key, try Self.frontmatterEditValue(value))
                }
            )
        } else {
            if slot == .paperAnalysis,
               case .authenticatedAgent = request.authority {
                throw DocumentCreationError.missingAgentAnalysisMetadata
            }
            dynamic = ""
        }

        let frontmatter = dynamic + (seed ?? "")
        let source = frontmatter.isEmpty
            ? request.body
            : "---\n" + frontmatter + "---\n" + request.body
        let document = NoteDocument(relativePath: "Managed Creation.md", rawContent: source)
        guard document.frontmatterState != .malformed else {
            throw DocumentCreationError.invalidMetadata(
                PropertyContractCatalog.validate(
                    document,
                    profile: Self.schemaProfile(for: slot)
                )
            )
        }
        let issues = PropertyContractCatalog.validate(
            document,
            profile: Self.schemaProfile(for: slot)
        )
        guard issues.isEmpty else {
            throw DocumentCreationError.invalidMetadata(issues)
        }
        return source
    }

    private func recordManagedCreationRecovery(
        vaultID: UUID,
        relativePath: String,
        reservedIdentityID: UUID,
        intendedRevision: DocumentFingerprint,
        repository: VaultRepository,
        failure: String
    ) async throws -> TriptychMutationRecoveryRecord {
        let observed: DocumentFingerprint?
        let state: TriptychMutationRecoveryState
        let sourceDetail: String
        do {
            let document = try await repository.load(relativePath: relativePath)
            observed = document.fingerprint
            state = document.fingerprint == intendedRevision
                ? .intendedBytesRemain
                : .externallyChanged
            sourceDetail = "The managed path currently has revision \(document.fingerprint.sha256)."
        } catch VaultRepositoryError.fileDoesNotExist {
            observed = nil
            state = .missing
            sourceDetail = "The managed path is currently absent."
        } catch {
            observed = nil
            state = .unreadable
            sourceDetail = "The managed path could not be read: \(error.localizedDescription)"
        }
        let identityDetail: String
        do {
            if let identity = try await services.controlStore.identityRecord(
                vaultID: vaultID,
                relativePath: relativePath
            ) {
                identityDetail = " Portable identity \(identity.id.uuidString) remains at revision \(identity.fingerprint.sha256)."
            } else {
                identityDetail = " No portable identity is currently assigned to the path."
            }
        } catch {
            identityDetail = " Portable identity state is unreadable: \(error.localizedDescription)"
        }
        let record = TriptychMutationRecoveryRecord(
            triptychID: id,
            operation: .noteCreation,
            failure: failure,
            files: [TriptychMutationRecoveryFile(
                vaultID: vaultID,
                path: relativePath,
                role: .createdNote,
                beforeRevision: nil,
                intendedRevision: intendedRevision,
                observedRevision: observed,
                state: state,
                detail: sourceDetail + identityDetail
            )],
            managedCreation: ManagedCreationRecoveryReference(
                target: VaultQualifiedNoteID(
                    vaultID: vaultID,
                    relativePath: relativePath
                ),
                reservedIdentityID: reservedIdentityID
            )
        )
        do {
            try await services.transactionRecoveryStore.record(record)
        } catch {
            throw TriptychTransactionError.recoveryPersistenceFailed(
                record,
                error.localizedDescription
            )
        }
        return record
    }

    private static func schemaProfile(for slot: WorkspaceVaultSlot) -> SchemaProfileID {
        switch slot {
        case .paperAnalysis: .analysis
        case .topicKnowledge: .topicMarkdown
        case .output: .draftProject
        }
    }

    static func isNonemptyManagedValue(_ value: YAMLValue) -> Bool {
        switch value {
        case .string(let value):
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .integer, .double, .boolean:
            true
        case .array(let values):
            !values.isEmpty && values.allSatisfy(isNonemptyManagedValue)
        case .object(let values):
            !values.isEmpty && values.values.allSatisfy(isNonemptyManagedValue)
        case .null:
            false
        }
    }

    static func frontmatterEditValue(
        _ value: YAMLValue
    ) throws -> FrontmatterEditValue {
        switch value {
        case .string(let value): .string(value)
        case .integer(let value): .integer(value)
        case .double(let value): .double(value)
        case .boolean(let value): .boolean(value)
        case .array(let values):
            .sequence(try values.map(frontmatterEditValue))
        case .object(let values):
            .mapping(try values.mapValues(frontmatterEditValue))
        case .null:
            throw DocumentCreationError.invalidMetadata([])
        }
    }

    /// Claims one default directory name. The returned path is a location, not
    /// a new portable identity or research record.
    func createUntitledFolder(
        inVault vaultID: UUID,
        parentRelativePath: String?
    ) async throws -> WorkspaceMutationOutcome<VaultRelativeFolderPath> {
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
                scheduleCommittedMutationRefresh(WorkspaceRefreshPayload(
                    publication: .explicit,
                    failureDisposition: .staleAfterCommittedMutation(
                        affectedVaultIDs: [vaultID]
                    ),
                    sourceCatalogPreparation: Self.catalogPreparation(
                        refreshFolderVaultIDs: [vaultID]
                    )
                ))
                endSourceMutation(mutationLease)
                ownsMutation = false
                return WorkspaceMutationOutcome(committedValue: folder)
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
    ) async throws -> WorkspaceMutationOutcome<FolderMoveCommit> {
        try await coordinatedMoveFolder(
            inVault: vaultID,
            from: sourceRelativePath,
            to: destinationRelativePath
        )
    }

    func duplicateDocument(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> {
        try await duplicateDocument(
            id,
            to: destinationRelativePath,
            expectedRevision: expectedRevision,
            expectedStableNoteID: nil
        )
    }

    func duplicateDocument(
        _ target: NoteMutationTarget,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> {
        try await duplicateDocument(
            target.documentID,
            to: destinationRelativePath,
            expectedRevision: target.revision,
            expectedStableNoteID: target.stableNoteID
        )
    }

    private func duplicateDocument(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint,
        expectedStableNoteID: UUID?
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> {
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
        try requireExpectedIdentity(
            expectedStableNoteID,
            resolved: identity.id,
            relativePath: id.relativePath
        )
        let document = try await repository.duplicate(
            relativePath: id.relativePath,
            to: destinationRelativePath,
            expectedRevision: expectedRevision
        )
        var committedDocument = document
        var identityRecoveryWarning: String?
        do {
            _ = try await services.controlStore.duplicateIdentity(
                from: identity.id,
                to: destinationRelativePath,
                fingerprint: document.fingerprint
            )
        } catch let identityError {
            guard let retained = try await retainedCreatedDocumentAfterIdentityFailure(
                repository: repository,
                document: document,
                identityError: identityError
            ) else {
                throw identityError
            }
            committedDocument = retained.document
            identityRecoveryWarning = retained.identityRecoveryWarning
        }
        endSourceMutation(mutationLease)
        ownsMutation = false
        return await finishCreatedDocumentMutation(
            id: VaultQualifiedNoteID(
                vaultID: id.vaultID,
                relativePath: destinationRelativePath
            ),
            document: committedDocument,
            identityRecoveryWarning: identityRecoveryWarning
        )
    }

    /// Creation and duplication first commit a no-replace source and then
    /// establish portable identity. If identity setup fails, rollback is
    /// revision checked. A failed rollback is never ignored: this helper
    /// distinguishes a proven retained source from unreadable presence so the
    /// managed researcher creator can persist one recovery duty, while older
    /// import and duplication callers keep their existing warning boundary.
    private func retainedCreatedDocumentAfterIdentityFailure(
        repository: VaultRepository,
        document: NoteDocument,
        identityError: any Error
    ) async throws -> RetainedCreatedDocument? {
        do {
            try await repository.removeCreatedFileForRollback(
                relativePath: document.relativePath,
                createdRevision: document.fingerprint
            )
        } catch {
            let rollbackError = error
            do {
                let retained = try await repository.load(
                    relativePath: document.relativePath
                )
                return RetainedCreatedDocument(
                    document: retained,
                    identityRecoveryWarning: "The source remains at \(document.relativePath) because stable identity setup failed and exact rollback was refused. Do not create or import it again; recover its identity instead. Identity: \(identityError.localizedDescription) Rollback: \(rollbackError.localizedDescription)"
                )
            } catch VaultRepositoryError.fileDoesNotExist {
                // The delete may have committed before its own verification
                // failed. A direct read now proves there is no retained source.
                throw CreatedDocumentIdentityRollbackError.sourceRolledBack(
                    path: document.relativePath,
                    identityFailure: identityError.localizedDescription
                )
            } catch {
                throw CreatedDocumentIdentityRollbackError.sourcePresenceUncertain(
                    path: document.relativePath,
                    identityFailure: identityError.localizedDescription,
                    rollbackFailure: rollbackError.localizedDescription,
                    observationFailure: error.localizedDescription
                )
            }
        }
        throw CreatedDocumentIdentityRollbackError.sourceRolledBack(
            path: document.relativePath,
            identityFailure: identityError.localizedDescription
        )
    }

    private func finishCreatedDocumentMutation(
        id: VaultQualifiedNoteID,
        document: NoteDocument,
        identityRecoveryWarning: String?
    ) async -> WorkspaceMutationOutcome<NoteDocument> {
        var identityRecoveryWarning = identityRecoveryWarning
        let derivedRefreshWarning: String?
        do {
            let refreshed = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [id.vaultID]
                ),
                sourceCatalogPreparation: Self.catalogPreparation(
                    upserts: [id],
                    refreshFolderVaultIDs: [id.vaultID]
                )
            )
            if identityRecoveryWarning != nil,
               refreshed.document(id: id)?.stableIdentity.resolvedID != nil {
                identityRecoveryWarning = nil
            }
            derivedRefreshWarning = nil
        } catch {
            derivedRefreshWarning = error.localizedDescription
        }
        return WorkspaceMutationOutcome(
            committedValue: document,
            derivedRefreshWarning: derivedRefreshWarning,
            identityRecoveryWarning: identityRecoveryWarning
        )
    }

    func saveDocument(
        _ id: VaultQualifiedNoteID,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<SaveResult> {
        switch try await performDocumentSave(
            id,
            changeSet: changeSet,
            expectedRevision: expectedRevision,
            completion: .sourceAndDerived,
            researchWrite: nil
        ) {
        case .committed(let outcome):
            return outcome
        case .notWritten(let reason):
            throw documentSaveError(reason, expectedRevision: expectedRevision)
        case .recoveryRequired(let record):
            throw TriptychTransactionError.recoveryRequired(record)
        }
    }

    func commitDocument(
        _ id: VaultQualifiedNoteID,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint
    ) async throws -> SaveResult {
        switch try await performDocumentSave(
            id,
            changeSet: changeSet,
            expectedRevision: expectedRevision,
            completion: .sourceOnly,
            researchWrite: nil
        ) {
        case .committed(let outcome):
            return outcome.committedValue
        case .notWritten(let reason):
            throw documentSaveError(reason, expectedRevision: expectedRevision)
        case .recoveryRequired(let record):
            throw TriptychTransactionError.recoveryRequired(record)
        }
    }

    func saveResearchDocument(
        _ id: VaultQualifiedNoteID,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint,
        transaction: ResearchDocumentSaveTransaction
    ) async throws -> ResearchDocumentSaveOutcome {
        switch try await performDocumentSave(
            id,
            changeSet: changeSet,
            expectedRevision: expectedRevision,
            completion: .sourceAndDerived,
            researchWrite: transaction
        ) {
        case .committed(let outcome): .committed(outcome)
        case .notWritten(let reason): .notWritten(reason)
        case .recoveryRequired(let record): .recoveryRequired(record)
        }
    }

    private func performDocumentSave(
        _ id: VaultQualifiedNoteID,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint,
        completion: DocumentSaveCompletion,
        researchWrite: ResearchDocumentSaveTransaction?
    ) async throws -> DocumentSaveOperationOutcome {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let repository = try repository(vaultID: id.vaultID)
        if let researchWrite {
            if let barrier = researchDocumentSavePreflightBarrierForTesting {
                await barrier()
            }
            guard Self.vaultRole(for: researchWrite.role)
                    == (try vault(id: id.vaultID).role),
                  let identity = try await services.controlStore.identityRecord(
                    vaultID: id.vaultID,
                    relativePath: id.relativePath
                  ), identity.id == researchWrite.noteID else {
                return .notWritten(.targetIdentityChanged)
            }
        }
        let save = try await repository.saveOutcome(
            relativePath: id.relativePath,
            changeSet: changeSet,
            expectedRevision: expectedRevision
        )
        switch save {
        case .notWritten(let reason):
            return .notWritten(reason)
        case .recoveryRequired(let sourceRecovery):
            let record = try await recordUncertainNoteSave(
                id: id,
                expectedRevision: expectedRevision,
                intendedRevision: sourceRecovery.candidateRevision,
                repository: repository,
                sourceRecovery: sourceRecovery,
                researchWrite: researchWrite,
                failure: sourceRecovery.retainedReason,
                detail: "The coordinated save could not prove the canonical result. The exact source transaction remains machine-local for reconciliation."
            )
            return .recoveryRequired(record)
        case .committed(let result):
            if completion == .sourceOnly {
                // Queue before releasing the mutation lease so the matching
                // watcher event cannot start a competing refresh first.
                scheduleSourceCommitRefresh(id: id, kind: .save)
            }
            endSourceMutation(mutationLease)
            ownsMutation = false
            var derivedRefreshWarning: String?
            if completion == .sourceAndDerived {
                do {
                    _ = try await refresh(
                        publication: .sourceCommitted(id, .save),
                        failureDisposition: .staleAfterCommittedMutation(
                            affectedVaultIDs: [id.vaultID]
                        )
                    )
                    derivedRefreshWarning = nil
                } catch {
                    derivedRefreshWarning = error.localizedDescription
                }
            }
            return .committed(WorkspaceMutationOutcome(
                committedValue: result,
                derivedRefreshWarning: derivedRefreshWarning
            ))
        }
    }

    private func recordUncertainNoteSave(
        id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        intendedRevision: DocumentFingerprint?,
        repository: VaultRepository,
        sourceRecovery: InterruptedSaveRecovery? = nil,
        researchWrite: ResearchDocumentSaveTransaction? = nil,
        failure: String,
        detail: String
    ) async throws -> TriptychMutationRecoveryRecord {
        guard researchWrite == nil || sourceRecovery != nil else {
            throw TriptychTransactionError.invalidPlan(
                "An Agent write recovery record requires its exact source transaction."
            )
        }
        let observed = try? await repository.load(relativePath: id.relativePath).fingerprint
        let state: TriptychMutationRecoveryState
        if let observed {
            if observed == expectedRevision {
                state = .restored
            } else if observed == intendedRevision {
                state = .intendedBytesRemain
            } else {
                state = .externallyChanged
            }
        } else {
            state = .unreadable
        }
        let record = TriptychMutationRecoveryRecord(
            triptychID: self.id,
            operation: .noteSave,
            failure: failure,
            files: [TriptychMutationRecoveryFile(
                vaultID: id.vaultID,
                path: id.relativePath,
                role: .savedNote,
                beforeRevision: expectedRevision,
                intendedRevision: intendedRevision,
                observedRevision: observed,
                state: state,
                detail: detail
            )],
            researchWrite: researchWrite.map {
                ResearchWriteRecoveryReference(
                    runID: $0.runID,
                    operationID: $0.operationID,
                    target: $0.target,
                    sourceRecoveryID: sourceRecovery!.id
                )
            }
        )
        do {
            try await services.transactionRecoveryStore.record(record)
        } catch {
            throw TriptychTransactionError.recoveryPersistenceFailed(
                record,
                error.localizedDescription
            )
        }
        return record
    }

    private func documentSaveError(
        _ reason: VaultSaveNotWrittenReason,
        expectedRevision: DocumentFingerprint
    ) -> VaultRepositoryError {
        switch reason {
        case .conflict(let current):
            .conflict(expected: expectedRevision, current: current)
        case .targetIdentityChanged:
            .notRegularFile("The Note path no longer belongs to the authorized portable identity.")
        case .invalidFrontmatter(let message):
            .invalidFrontmatter(message)
        case .atomicCommitUnsupported(let message):
            .atomicCommitUnsupported(message)
        }
    }

    private static func vaultRole(
        for role: ResearchActionTargetRole
    ) -> VaultRole {
        switch role {
        case .analysis: .sourceCorpus
        case .topic: .topicKnowledge
        case .work: .draftProject
        }
    }

    func moveDocument(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit> {
        try await coordinatedMoveDocument(
            id,
            to: destinationRelativePath,
            expectedRevision: expectedRevision,
            validatesCritiquePlacement: true
        )
    }

    func moveDocument(
        _ target: NoteMutationTarget,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit> {
        try await coordinatedMoveDocument(
            target.documentID,
            to: destinationRelativePath,
            expectedRevision: target.revision,
            expectedStableNoteID: target.stableNoteID,
            validatesCritiquePlacement: true
        )
    }

    func prepareSystemTrash(
        _ target: NoteMutationTarget
    ) async throws -> SystemTrashDeletionPreview {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        defer { endSourceMutation(mutationLease) }
        let identity = try await resolvedIdentity(
            for: target.documentID,
            expectedRevision: target.revision
        )
        try requireExpectedIdentity(
            target.stableNoteID,
            resolved: identity.id,
            relativePath: target.relativePath
        )
        return try await systemTrashCoordinator(vaultID: target.documentID.vaultID)
            .prepareNote(
                noteID: identity.id,
                vaultID: target.documentID.vaultID,
                relativePath: target.relativePath,
                expectedRevision: target.revision
            )
    }

    func prepareFolderSystemTrash(
        inVault vaultID: UUID,
        relativePath: String
    ) async throws -> SystemTrashDeletionPreview {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        defer { endSourceMutation(mutationLease) }
        return try await systemTrashCoordinator(vaultID: vaultID).prepareFolder(
            vaultID: vaultID,
            relativePath: relativePath
        )
    }

    func moveToSystemTrash(
        _ preview: SystemTrashDeletionPreview
    ) async throws -> WorkspaceMutationOutcome<SystemTrashDeletionCommit> {
        try requireActive()
        guard let vaultID = preview.sources.first?.vaultID,
              preview.sources.allSatisfy({ $0.vaultID == vaultID }) else {
            throw TriptychTransactionError.invalidPlan(
                "A system-Trash plan must belong to exactly one vault."
            )
        }
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer { if ownsMutation { endSourceMutation(mutationLease) } }
        let commit: SystemTrashDeletionCommit
        do {
            commit = try await systemTrashCoordinator(vaultID: vaultID)
                .moveToSystemTrash(preview)
        } catch {
            endSourceMutation(mutationLease)
            ownsMutation = false
            _ = try? await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [vaultID]
                )
            )
            throw error
        }
        endSourceMutation(mutationLease)
        ownsMutation = false
        let deletedIDs = preview.sources.flatMap(\.notes).map {
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: $0.relativePath)
        }
        let derivedRefreshWarning: String?
        do {
            _ = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [vaultID]
                ),
                sourceCatalogPreparation: Self.catalogPreparation(
                    deletions: deletedIDs,
                    refreshFolderVaultIDs: [vaultID]
                )
            )
            derivedRefreshWarning = nil
        } catch {
            derivedRefreshWarning = error.localizedDescription
        }
        return WorkspaceMutationOutcome(
            committedValue: commit,
            derivedRefreshWarning: derivedRefreshWarning
        )
    }

    private func systemTrashCoordinator(
        vaultID: UUID
    ) throws -> NoteSystemTrashDeletionCoordinator {
        let repository = try repository(vaultID: vaultID)
        return NoteSystemTrashDeletionCoordinator(
            triptychID: services.manifest.id,
            repository: repository,
            critiqueRegistry: services.critiqueRegistry,
            controlStore: services.controlStore,
            recoveryStore: services.transactionRecoveryStore,
            portableRecordStore: services.portableResearchRecordStore,
            localExecutionStore: services.localResearchExecutionStore,
            agentChangeEvidenceStore: services.agentChangeEvidenceStore
        )
    }

    func interruptedSaveRecoveries() async throws -> [InterruptedSaveRecovery] {
        try requireActive()
        var recoveries: [InterruptedSaveRecovery] = []
        for vault in orderedVaults() {
            let repository = try repository(vaultID: vault.id)
            recoveries.append(contentsOf: try await repository.interruptedSaveRecoveries())
        }
        return recoveries.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            if $0.id.vaultID != $1.id.vaultID {
                return $0.id.vaultID.uuidString < $1.id.vaultID.uuidString
            }
            return $0.id.transactionID.uuidString < $1.id.transactionID.uuidString
        }
    }

    func interruptedSaveRecoveryContent(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> InterruptedSaveRecoveryContent {
        try requireActive()
        return try await repository(vaultID: recovery.id.vaultID)
            .interruptedSaveRecoveryContent(recovery)
    }

    func prepareInterruptedSaveRecoveryLocation(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> URL {
        try requireActive()
        return try await repository(vaultID: recovery.id.vaultID)
            .prepareInterruptedSaveRecoveryLocation(recovery)
    }

    func restoreInterruptedSaveRecovery(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> WorkspaceMutationOutcome<InterruptedSaveRecoveryRestoreCommit> {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let repository = try repository(vaultID: recovery.id.vaultID)
        let commit: InterruptedSaveRecoveryRestoreCommit
        do {
            commit = try await repository.restoreInterruptedSaveRecovery(recovery)
        } catch let error as VaultRepositoryError {
            let sourceRecovery: InterruptedSaveRecovery
            let failure: String
            switch error {
            case .commitUncertain:
                sourceRecovery = recovery
                failure = error.localizedDescription
            case .recoveryRequired(let retained):
                sourceRecovery = retained
                failure = retained.retainedReason
            default:
                throw error
            }
            let record = try await recordUncertainNoteSave(
                id: VaultQualifiedNoteID(
                    vaultID: recovery.id.vaultID,
                    relativePath: recovery.relativePath
                ),
                expectedRevision: sourceRecovery.expectedRevision,
                intendedRevision: sourceRecovery.candidateRevision,
                repository: repository,
                sourceRecovery: sourceRecovery,
                failure: failure,
                detail: "Interrupted-save recovery could not prove both canonical and displaced bytes. The candidate and every available source revision remain machine-local for inspection."
            )
            throw TriptychTransactionError.recoveryRequired(record)
        }
        endSourceMutation(mutationLease)
        ownsMutation = false

        var derivedRefreshWarning: String?
        if commit.didReplaceSource {
            do {
                _ = try await refresh(
                    publication: .sourceCommitted(
                        VaultQualifiedNoteID(
                            vaultID: recovery.id.vaultID,
                            relativePath: recovery.relativePath
                        ),
                        .save
                    ),
                    failureDisposition: .staleAfterCommittedMutation(
                        affectedVaultIDs: [recovery.id.vaultID]
                    )
                )
            } catch {
                derivedRefreshWarning = error.localizedDescription
            }
        }
        return WorkspaceMutationOutcome(
            committedValue: commit,
            derivedRefreshWarning: derivedRefreshWarning
        )
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
            let coordinator = NoteSystemTrashDeletionCoordinator(
                triptychID: services.manifest.id,
                repository: repository,
                critiqueRegistry: services.critiqueRegistry,
                controlStore: services.controlStore,
                recoveryStore: services.transactionRecoveryStore,
                portableRecordStore: services.portableResearchRecordStore,
                localExecutionStore: services.localResearchExecutionStore,
                agentChangeEvidenceStore: services.agentChangeEvidenceStore
            )
            do {
                try await coordinator.recoverInterruptedTransactions()
            } catch {
                issues.append("Vault \(vaultID.uuidString): \(error.localizedDescription)")
            }
        }
        return issues
    }

    func retainRecordsForUnknownSystemTrashOutcome(
        recoveryRecordID: UUID,
        vaultID: UUID
    ) async throws {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        defer { endSourceMutation(mutationLease) }
        try await systemTrashCoordinator(vaultID: vaultID)
            .retainRecordsForUnknownOutcome(
                recoveryRecordID: recoveryRecordID
            )
    }

    func refresh() async throws -> WorkspaceSnapshot {
        let snapshot = try await refresh(publication: .explicit)
        if snapshot.phase.isComplete {
            startLiveIndexRefreshIfNeeded()
        }
        return snapshot
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
            if mode == .live,
               !currentSnapshot.phase.isComplete,
               !didCompleteActivationReconciliation {
                await progressiveActivationReconciliationBarrierForTesting?()
                try Task.checkCancellation()
                try requireActive()
                // Observation already owns all three Vault streams. Complete
                // one full post-observation reconciliation before the first
                // complete snapshot can be built or published, closing the
                // initial-open blind interval as one completion boundary.
                try await prepareSourceCatalogs(.fullReconcile)
                didCompleteActivationReconciliation = true
            } else {
                try await prepareSourceCatalogs(payload.sourceCatalogPreparation)
            }
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
                dependencies: services.snapshotBuilderDependencies,
                graphGeneration: graphGeneration,
                workspaceGeneration: workspaceGeneration
            )
            try await researchStateRepairBarrierForTesting?()
            let repairedBuild = try await WorkspaceResearchStateReconciler
                .repairBeforePublication(
                    build: build,
                    triptychID: assignment.id,
                    dependencies: services.researchStateReconcilerDependencies
                )
            snapshot = repairedBuild.snapshot
            measurement = repairedBuild.measurement
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
        sourceAheadIdentityRecords.removeAll(keepingCapacity: true)
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
            if previous.phase != snapshot.phase {
                await events.publishDerivedStateChanged(snapshot: snapshot)
                return
            }
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
        preOpenInventory: [VaultQualifiedNoteID: DocumentFingerprint],
        completesOpeningInBackground: Bool
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
        if completesOpeningInBackground {
            let presentationEvents = openingPresentationSignal.stream
            openingCompletionTask = Task(priority: .utility) { [weak self] in
                await Self.waitForOpeningPresentationOrFallback(presentationEvents)
                guard !Task.isCancelled, let self else { return }
                await self.completeLiveOpening()
            }
            return
        }
        await reconcileLiveActivation(preOpenInventory: preOpenInventory)
    }

    private nonisolated static func waitForOpeningPresentationOrFallback(
        _ events: AsyncStream<Void>
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in events { return }
            }
            group.addTask {
                // A Library-only window must still converge when no Document
                // is selected or its renderer fails before becoming visible.
                try? await Task.sleep(for: .seconds(2))
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func completeLiveOpening() async {
        defer { openingCompletionTask = nil }
        guard !isShutDown, !Task.isCancelled else { return }
        do {
            if !currentSnapshot.phase.isComplete {
                _ = try await refresh(
                    publication: .liveInventory,
                    failureDisposition: .failed(
                        affectedVaultIDs: Set(assignment.vaults.values.map(\.id))
                    ),
                    sourceCatalogPreparation: .fullReconcile
                )
            }
            startLiveIndexRefreshIfNeeded()
        } catch {
            // `refresh` already published a typed failure while retaining the
            // usable opening vault. Explicit Retry performs a full reconcile.
        }
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

    func beginSourceMutation() async throws -> WorkspaceSourceOperationLease {
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

    /// Research Method, Profile, Skill, and standing-policy writes share the
    /// Agent decision gate so an exact-current check and its non-authorizing
    /// durable decision cannot be separated by an in-App configuration edit.
    func beginResearchConfigurationMutation() async throws -> WorkspaceSourceOperationLease {
        try await beginSourceMutation()
    }

    func beginResearchControlledSourceObservation() async throws
        -> WorkspaceSourceOperationLease
    {
        try await beginSourceMutation()
    }

    func endSourceMutation(_ lease: WorkspaceSourceOperationLease) {
        releaseWorkspaceSourceOperation(lease)
        startLiveIndexRefreshIfNeeded()
    }

    func endResearchConfigurationMutation(_ lease: WorkspaceSourceOperationLease) {
        endSourceMutation(lease)
        let snapshot = currentSnapshot
        let events = events
        Task {
            await events.publishResearchConfigurationInvalidated(snapshot: snapshot)
        }
    }

    func endResearchControlledSourceObservation(
        _ lease: WorkspaceSourceOperationLease
    ) {
        endSourceMutation(lease)
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
              currentSnapshot.phase.isComplete,
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
        scheduleCommittedMutationRefresh(WorkspaceRefreshPayload(
            publication: .sourceCommitted(id, kind),
            failureDisposition: .staleAfterCommittedMutation(
                affectedVaultIDs: [id.vaultID]
            ),
            sourceCatalogPreparation: .inferred(
                from: .sourceCommitted(id, kind)
            )
        ))
    }

    /// Retains disposable projection work after a proven source mutation so
    /// filesystem completion never waits for graph, Search, or research-state
    /// assembly. Callers enqueue while holding the source lease; the owned
    /// refresh task can therefore begin only after that lease is released.
    private func scheduleCommittedMutationRefresh(
        _ payload: WorkspaceRefreshPayload
    ) {
        pendingSourceCommitRefreshes.append(payload)
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

    /// Waits for the Workspace-owned projection task that follows an already
    /// committed source mutation. If that disposable task failed, one explicit
    /// refresh may repair it; the caller receives a typed committed-but-stale
    /// outcome and must never repeat the source creation.
    func awaitCommittedSourceProjection(
        id: VaultQualifiedNoteID,
        stableIdentity: UUID,
        fingerprint: DocumentFingerprint
    ) async throws -> WorkspaceNoteSnapshot {
        if let sourceCommitRefreshTask {
            await sourceCommitRefreshTask.value
        }
        if let note = currentSnapshot.document(id: id),
           note.stableIdentity.resolvedID == stableIdentity,
           note.fingerprint == fingerprint {
            return note
        }
        do {
            _ = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [id.vaultID]
                )
            )
        } catch {
            throw ScholiumApplicationError.operationCommittedButRefreshFailed(
                operation: "Agent Analysis creation",
                reason: error.localizedDescription
            )
        }
        guard let note = currentSnapshot.document(id: id),
              note.stableIdentity.resolvedID == stableIdentity,
              note.fingerprint == fingerprint else {
            throw ScholiumApplicationError.operationCommittedButRefreshFailed(
                operation: "Agent Analysis creation",
                reason: "The complete Workspace projection does not yet contain the committed Note identity and revision."
            )
        }
        return note
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
        (liveWatcherTask == nil ? 0 : 1)
            + (openingCompletionTask == nil ? 0 : 1)
            + (liveIndexRefreshTask == nil ? 0 : 1)
    }

    var activationReconciliationCompleted: Bool {
        didCompleteActivationReconciliation
    }

    var watcherReadinessEvidence: WorkspaceWatcherReadinessEvidence? {
        guard liveWatcherTask != nil,
              currentSnapshot.phase.isComplete,
              didCompleteActivationReconciliation else { return nil }
        return WorkspaceWatcherReadinessEvidence(
            watchedVaultIDs: Set(assignment.vaults.values.map(\.id)),
            activationReconciliationCompleted: true
        )
    }

    func search(_ request: SearchRequest) async throws -> SearchResponse {
        try requireActive()
        guard currentSnapshot.phase.isComplete else {
            throw ScholiumApplicationError.workspaceStillLoading(id)
        }
        if let diagnostic = searchScopeDiagnostic(request) {
            return await searchDiagnosticResponse(
                request: request,
                parsed: SearchQueryParseResult(
                    ast: nil,
                    diagnostics: [diagnostic]
                )
            )
        }

        let parsed = SearchQueryParser.parse(request.query)
        guard let ast = parsed.ast, parsed.diagnostics.isEmpty else {
            return await searchDiagnosticResponse(request: request, parsed: parsed)
        }
        switch ast.provider {
        case .note:
            if case .currentNote = request.executionScope,
               ast.clauses.contains(where: { clause in
                   switch clause {
                   case .property, .relation: true
                   case .lexical, .structured, .record: false
                   }
               }) {
                return await searchDiagnosticResponse(
                    request: request,
                    parsed: SearchQueryParseResult(
                        provider: .note,
                        providerWasExplicit: ast.providerWasExplicit,
                        ast: ast,
                        diagnostics: [SearchQueryDiagnostic(
                            code: .notApplicable,
                            message: "Property and direct relation clauses are not applicable to This Note occurrence Search.",
                            utf16LowerBound: 0,
                            utf16UpperBound: request.query.utf16.count
                        )]
                    )
                )
            }
            let relation = NoteRelationSearchResolver.resolve(
                ast: ast,
                scope: request.executionScope,
                catalog: currentSnapshot.discovery.catalog,
                searchGeneration: currentSnapshot.discovery.searchGeneration
            )
            if let diagnostic = relation.diagnostic {
                return await searchDiagnosticResponse(
                    request: request,
                    parsed: SearchQueryParseResult(
                        provider: .note,
                        providerWasExplicit: ast.providerWasExplicit,
                        ast: ast,
                        diagnostics: [diagnostic]
                    )
                )
            }
            return try await services.searchIndex.search(
                request,
                ast: ast,
                relationshipMatches: relation.matches
            )

        case .record:
            return try searchRecords(request, ast: ast)
        }
    }

    /// Rebuilds the Record query projection from the current immutable
    /// snapshot. `search(_:)` has already validated the resolved scope before
    /// parsing or dispatching to this provider.
    func searchRecords(
        _ request: SearchRequest,
        ast: SearchQueryAST
    ) throws -> SearchResponse {
        try requireActive()
        precondition(ast.provider == .record)
        let index = ResearchRecordSearchIndex(
            triptychID: assignment.id,
            research: currentSnapshot.research,
            catalog: currentSnapshot.discovery.catalog
        )
        let execution = try index.search(
            ast: ast,
            scope: request.executionScope,
            limit: request.limit,
            offset: request.resultOffset,
            sort: request.resolvedRecordSort,
            topLevelOnly: request.recordSort != nil
        )
        return SearchResponse(
            requestID: request.id,
            scope: request.presentationScope,
            explanation: ast.explanation(scope: request.presentationScope),
            freshnessToken: .record(execution.generation),
            availability: .record(execution.availability),
            results: execution.results.map(SearchResult.record),
            hasMore: execution.hasMore,
            totalResultCount: execution.totalResultCount,
            diagnostics: execution.diagnostics
        )
    }

    private func searchScopeDiagnostic(
        _ request: SearchRequest
    ) -> SearchQueryDiagnostic? {
        guard request.hasConsistentScopes else {
            return SearchQueryDiagnostic(
                code: .notApplicable,
                message: "Search presentation and execution scopes do not match.",
                utf16LowerBound: 0,
                utf16UpperBound: 0
            )
        }
        let authorizedVaultIDs = Set(assignment.vaults.values.map(\.id))
        switch request.executionScope {
        case .triptych:
            return nil
        case .currentVault(let vaultID):
            guard authorizedVaultIDs.contains(vaultID) else {
                return SearchQueryDiagnostic(
                    code: .notApplicable,
                    message: "The selected Search vault is not part of this Triptych.",
                    utf16LowerBound: 0,
                    utf16UpperBound: 0
                )
            }
        case .currentNote(let source):
            guard authorizedVaultIDs.contains(source.noteID.vaultID),
                  currentSnapshot.discovery.catalog.notes.contains(where: {
                      $0.reference.vaultID == source.noteID.vaultID
                          && $0.reference.relativePath == source.noteID.relativePath
                  }) else {
                return SearchQueryDiagnostic(
                    code: .notApplicable,
                    message: "The selected Search Note is not part of this Triptych.",
                    utf16LowerBound: 0,
                    utf16UpperBound: 0
                )
            }
        }
        return nil
    }

    private func searchDiagnosticResponse(
        request: SearchRequest,
        parsed: SearchQueryParseResult
    ) async -> SearchResponse {
        let availability: SearchProviderAvailability
        let freshness: SearchFreshnessToken
        switch parsed.provider {
        case .note:
            let noteAvailability = await services.searchIndex.availability()
            availability = .note(noteAvailability)
            switch request.executionScope {
            case .currentNote(let source):
                freshness = .currentNote(source)
            case .currentVault, .triptych:
                if let generation = noteAvailability.lastGoodGeneration {
                    freshness = .triptych(generation)
                } else {
                    freshness = SearchFreshnessToken(
                        "triptych:\(id.uuidString.lowercased()):unavailable"
                    )
                }
            }
        case .record:
            let generation = RecordSearchGenerationID(
                triptychID: id,
                sourceManifestHash:
                    currentSnapshot.research.finishedResearchRecordSourceManifestHash
            )
            if currentSnapshot.research.finishedResearchRecordProjectionIsComplete {
                availability = .record(.current(generation))
            } else {
                availability = .record(.failed(
                    lastGood: nil,
                    reason: "The portable Research Record corpus is incomplete."
                ))
            }
            freshness = .record(generation)
        }
        return SearchResponse(
            requestID: request.id,
            scope: request.presentationScope,
            explanation: parsed.explanation(scope: request.presentationScope),
            freshnessToken: freshness,
            availability: availability,
            results: [],
            hasMore: false,
            diagnostics: parsed.diagnostics
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

    func triptychSettings() async throws -> TriptychSettingsSnapshot {
        try requireActive()
        return try await services.controlStore.settings()
    }

    func triptychSettingsLoadState() async throws -> TriptychSettingsLoadState {
        try requireActive()
        return try await services.controlStore.settingsLoadState()
    }

    func saveTriptychSettings(
        _ settings: TriptychSettings,
        expectedRevision: SettingsRevision
    ) async throws -> TriptychSettingsSnapshot {
        try await saveTriptychSettingsOutcome(
            settings,
            expectedRevision: expectedRevision
        ).committedValue
    }

    func saveTriptychSettingsOutcome(
        _ settings: TriptychSettings,
        expectedRevision: SettingsRevision
    ) async throws -> WorkspaceMutationOutcome<TriptychSettingsSnapshot> {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let snapshot: TriptychSettingsSnapshot
        do {
            snapshot = try await services.controlStore.saveSettings(
                settings,
                expectedRevision: expectedRevision
            )
        } catch {
            let uncertaintyReason: String
            if let controlError = error as? TriptychControlError,
               case .controlFileCommitUncertain(let reason) = controlError {
                uncertaintyReason = reason
            } else if let cocoaError = error as? CocoaError,
                      cocoaError.code == .fileWriteUnknown {
                uncertaintyReason = cocoaError.localizedDescription
            } else {
                throw error
            }
            let state: TriptychSettingsLoadState
            do {
                state = try await services.controlStore.settingsLoadState()
            } catch {
                throw ScholiumApplicationError.operationCommitUncertain(
                    operation: "The Triptych settings",
                    reason: "\(uncertaintyReason) Authoritative reread failed: \(error.localizedDescription)"
                )
            }
            if case .current(let reread) = state, reread.settings == settings {
                snapshot = reread
            } else {
                throw ScholiumApplicationError.operationCommitUncertain(
                    operation: "The Triptych settings",
                    reason: uncertaintyReason
                )
            }
        }
        endSourceMutation(mutationLease)
        ownsMutation = false
        do {
            try await refreshAfterCommittedOperation(
                "The Triptych settings",
                publication: .researchRecords
            )
            return WorkspaceMutationOutcome(committedValue: snapshot)
        } catch let error as ScholiumApplicationError
            where error.durableMutationWasCommitted {
            return WorkspaceMutationOutcome(
                committedValue: snapshot,
                derivedRefreshWarning: error.refreshFailureReason
                    ?? error.localizedDescription
            )
        }
    }


    private func coordinatedMoveDocument(
        _ source: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint,
        expectedStableNoteID: UUID? = nil,
        validatesCritiquePlacement: Bool
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit> {
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
        try requireExpectedIdentity(
            expectedStableNoteID,
            resolved: identity.id,
            relativePath: source.relativePath
        )
        let registeredVault = try vault(id: source.vaultID)
        if validatesCritiquePlacement, registeredVault.role.allowsCritique {
            try CritiquePlacement.validateOrdinaryMove(
                from: source.relativePath,
                to: destinationRelativePath
            )
        }

        let repositories = services.repositories
        let plan = try await workspaceMovePlan(moving: source, to: destination)

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
        var movedIdentityRecord: NoteIdentityRecord?
        do {
            movedIdentityRecord = try await services.controlStore.moveIdentity(
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

        sourceAheadIdentityRecords[source] = nil
        if identityFailure == nil, let movedIdentityRecord {
            sourceAheadIdentityRecords[destination] = movedIdentityRecord
        } else {
            sourceAheadIdentityRecords[destination] = nil
        }

        let refreshPayload = WorkspaceRefreshPayload(
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
        // The source rename, incoming-link rewrites, and identity rebind are
        // already durable at this point. Graph, Search, and the complete
        // Workspace snapshot are disposable projections, so every kind of
        // Note move resumes them in the owned background refresh instead of
        // holding the interaction open. The exact window installs the
        // committed source-ahead relocation before this operation returns.
        scheduleCommittedMutationRefresh(refreshPayload)
        endSourceMutation(mutationLease)
        ownsMutation = false
        return WorkspaceMutationOutcome(
            committedValue: commit,
            identityRecoveryWarning: identityFailure?.localizedDescription
        )
    }

    private func coordinatedMoveFolder(
        inVault vaultID: UUID,
        from sourceRelativePath: String,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<FolderMoveCommit> {
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
        let noteMoves = try sourceAuthorizedFolderNoteMoves(
            vaultID: vaultID,
            sourceFolder: sourceFolder,
            destinationFolder: destinationFolder,
            snapshotDocuments: vaultSnapshot.documents,
            sourceAheadIdentityRecords: sourceAheadIdentityRecords
        )

        let repositories = services.repositories
        let plan = try await workspaceFolderMovePlan(
            vaultID: vaultID,
            sourceFolder: sourceFolder,
            destinationFolder: destinationFolder,
            noteMoves: noteMoves
        )

        let coordinator = TriptychFolderMoveCoordinator(
            triptychID: services.manifest.id,
            repositories: repositories,
            recoveryStore: services.transactionRecoveryStore
        )
        let commit = try await coordinator.move(plan)

        var identityFailure: Error?
        var movedIdentityRecords: [NoteIdentityRecord] = []
        do {
            movedIdentityRecords = try await services.controlStore.moveIdentities(
                commit.noteMoves
            )
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

        for move in commit.noteMoves {
            sourceAheadIdentityRecords[move.source] = nil
            sourceAheadIdentityRecords[move.destination] = nil
        }
        if identityFailure == nil {
            for record in movedIdentityRecords {
                sourceAheadIdentityRecords[VaultQualifiedNoteID(
                    vaultID: record.vaultID,
                    relativePath: record.relativePath
                )] = record
            }
        }

        let affectedVaultIDs = Set(plan.rewrites.map { $0.source.vaultID })
            .union([vaultID])
        let refreshPayload = WorkspaceRefreshPayload(
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
        // The directory rename, exact link rewrites, and portable identity
        // rebind are durable. Queue the one complete derived generation while
        // the source lease is still held so matching watcher events cannot
        // start a competing rebuild; the exact window installs the returned
        // committed sources immediately.
        scheduleCommittedMutationRefresh(refreshPayload)
        endSourceMutation(mutationLease)
        ownsMutation = false
        return WorkspaceMutationOutcome(
            committedValue: commit,
            identityRecoveryWarning: identityFailure?.localizedDescription
        )
    }

    private func workspaceFolderMovePlan(
        vaultID: UUID,
        sourceFolder: VaultRelativeFolderPath,
        destinationFolder: VaultRelativeFolderPath,
        noteMoves: [FolderNoteMovePlan]
    ) async throws -> FolderIncomingLinkRewritePlan {
        let snapshotCanAuthorizeFastPlan = !derivedStateRequiresRefresh
            && pendingSourceCommitRefreshes.isEmpty
            && sourceCommitRefreshTask == nil
            && pendingLiveEvents.isEmpty
            && liveIndexRefreshTask == nil
            && sourceAheadIdentityRecords.isEmpty
        if snapshotCanAuthorizeFastPlan,
           let graph = currentSnapshot.discovery.catalog.graph {
            let activeSnapshots = currentSnapshot.vaults.flatMap(\.documents)
            let documents = Dictionary(uniqueKeysWithValues: activeSnapshots.map {
                ($0.id, $0.document)
            })
            var catalogNotesByID: [VaultQualifiedNoteID: WorkspaceCatalogNote] = [:]
            for note in currentSnapshot.discovery.catalog.notes {
                let id = VaultQualifiedNoteID(
                    vaultID: note.reference.vaultID,
                    relativePath: note.reference.relativePath
                )
                catalogNotesByID[id] = note
            }
            var catalog: [LinkCatalogNote] = []
            var snapshotIsCoherent = noteMoves.allSatisfy { move in
                documents[move.source]?.fingerprint == move.expectedRevision
            }
            for note in activeSnapshots {
                guard let cached = catalogNotesByID[note.id],
                      cached.fingerprint == note.fingerprint else {
                    snapshotIsCoherent = false
                    break
                }
                catalog.append(LinkCatalogNote(
                    id: note.id,
                    title: cached.title,
                    aliases: cached.aliases,
                    headings: note.headings
                ))
            }
            let sourceManifestHash = SearchSourceManifest.hash(documents.map {
                id, document in
                SearchSourceManifestEntry(
                    vaultID: id.vaultID,
                    relativePath: id.relativePath,
                    fingerprint: document.fingerprint
                )
            })
            if snapshotIsCoherent,
               catalog.count == documents.count,
               graph.sourceManifestHash == sourceManifestHash,
               let plan = IncomingLinkRewriter.folderPlanUsingValidatedSnapshot(
                    documents: documents,
                    catalog: catalog,
                    graph: graph,
                    vaultID: vaultID,
                    sourceFolder: sourceFolder,
                    destinationFolder: destinationFolder,
                    noteMoves: noteMoves
               ) {
                return plan
            }
        }

        // A pending, source-ahead, or structurally stale generation cannot
        // authorize link edits. Preserve the complete filesystem fallback and
        // its exact preflight rather than weakening source coordination.
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
        let snapshotCanAuthorizeFastPlan = !derivedStateRequiresRefresh
            && pendingSourceCommitRefreshes.isEmpty
            && sourceCommitRefreshTask == nil
            && pendingLiveEvents.isEmpty
            && liveIndexRefreshTask == nil
            && sourceAheadIdentityRecords.isEmpty
        if snapshotCanAuthorizeFastPlan,
           let graph = currentSnapshot.discovery.catalog.graph {
            let activeSnapshots = currentSnapshot.vaults.flatMap(\.documents)
            let documents = Dictionary(uniqueKeysWithValues: activeSnapshots.map {
                ($0.id, $0.document)
            })
            var catalogNotesByID: [VaultQualifiedNoteID: WorkspaceCatalogNote] = [:]
            for note in currentSnapshot.discovery.catalog.notes {
                let id = VaultQualifiedNoteID(
                    vaultID: note.reference.vaultID,
                    relativePath: note.reference.relativePath
                )
                catalogNotesByID[id] = note
            }
            var catalog: [LinkCatalogNote] = []
            var snapshotIsCoherent = documents[source] != nil
            for note in activeSnapshots {
                guard let cached = catalogNotesByID[note.id],
                      cached.fingerprint == note.fingerprint else {
                    snapshotIsCoherent = false
                    break
                }
                catalog.append(LinkCatalogNote(
                    id: note.id,
                    title: cached.title,
                    aliases: cached.aliases,
                    headings: note.headings
                ))
            }
            if snapshotIsCoherent,
               let plan = IncomingLinkRewriter.planUsingValidatedSnapshot(
                   documents: documents,
                   catalog: catalog,
                   graph: graph,
                   moving: source,
                   to: destination
               ) {
                return plan
            }
        }

        // A source-ahead, known-stale, pending-refresh, or otherwise
        // mixed-generation snapshot cannot authorize link edits. Fall back to
        // the complete filesystem read and graph re-derivation rather than
        // weakening exact-source validation.
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

    private func requireExpectedIdentity(
        _ expected: UUID?,
        resolved current: UUID,
        relativePath: String
    ) throws {
        guard let expected else { return }
        guard expected == current else {
            throw NoteIdentityRecoveryError.targetIdentityChanged(relativePath)
        }
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
        guard let record = try await services.controlStore.identityRecord(
                  vaultID: id.vaultID,
                  relativePath: id.relativePath
              ), record.fingerprint == expectedRevision else {
            throw NoteIdentityRecoveryError.identityUnresolved(id.relativePath)
        }
        if let note = currentSnapshot.document(id: id),
           note.fingerprint == expectedRevision,
           note.stableIdentity.resolvedID == record.id {
            return record
        }
        guard let sourceAhead = sourceAheadIdentityRecords[id],
              sourceAhead.id == record.id,
              sourceAhead.fingerprint == record.fingerprint else {
            throw NoteIdentityRecoveryError.identityUnresolved(id.relativePath)
        }
        return record
    }

    func resolveIdentity(
        _ ambiguity: NoteIdentityAmbiguity,
        candidateID: UUID?
    ) async throws -> WorkspaceMutationOutcome<NoteIdentityRecord> {
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
        let derivedRefreshWarning: String?
        do {
            _ = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [ambiguity.vaultID]
                )
            )
            derivedRefreshWarning = nil
        } catch {
            derivedRefreshWarning = error.localizedDescription
        }
        return WorkspaceMutationOutcome(
            committedValue: record,
            derivedRefreshWarning: derivedRefreshWarning
        )
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

    func requireCompleteWorkspace() throws {
        try requireActive()
        guard currentSnapshot.phase.isComplete else {
            throw ScholiumApplicationError.workspaceStillLoading(id)
        }
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
