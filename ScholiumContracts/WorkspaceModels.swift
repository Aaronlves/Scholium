import Foundation

/// The source-membership policy used by a workspace handle.
///
/// Both modes use the real Core repositories, indexes, and research stores.
/// Snapshot mode freezes only Triptych membership; it does not copy or freeze
/// the bytes in the configured vaults.
public enum WorkspaceConfigurationMode: String, Sendable {
    case live
    case snapshot
}

public enum WorkspaceDocumentLifecycle: String, Codable, Hashable, Sendable {
    case active
    case setAside = "set_aside"
    case trash

    public init(relativePath: String) {
        if relativePath.hasPrefix("Set Aside/") {
            self = .setAside
        } else if relativePath.hasPrefix("Trash/") {
            self = .trash
        } else {
            self = .active
        }
    }
}

public struct WorkspaceFileMetadata: Hashable, Sendable {
    public let byteCount: Int
    public let creationDate: Date?
    public let modificationDate: Date?

    public init(
        byteCount: Int,
        creationDate: Date?,
        modificationDate: Date?
    ) {
        self.byteCount = byteCount
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }
}

public struct WorkspaceGraphCounts: Codable, Hashable, Sendable {
    public let incoming: Int
    public let outgoing: Int
    public let broken: Int
    public let ambiguous: Int

    public init(incoming: Int, outgoing: Int, broken: Int, ambiguous: Int) {
        self.incoming = incoming
        self.outgoing = outgoing
        self.broken = broken
        self.ambiguous = ambiguous
    }
}

/// Freshness of the disposable fields carried beside one authoritative note
/// source. Application-owned Workspace generations publish only `current`.
/// A window may transiently present `sourceAhead` after a proven source commit
/// while the owning Workspace refreshes graph, Search, and other projections.
public enum WorkspaceNoteDerivedProjectionState: String, Codable, Hashable, Sendable {
    case current
    case sourceAhead
}

/// Portable note identity is distinct from the note's current vault-qualified
/// location. A resolved UUID survives a confirmed rename; every other case is
/// explicit so presentation/session code never falls back to treating a path
/// as durable identity.
public enum WorkspaceNoteIdentityState: Hashable, Sendable {
    case resolved(UUID)
    case ambiguous(candidateIDs: [UUID])
    case pending(UUID)
    case unresolved

    public var resolvedID: UUID? {
        guard case .resolved(let id) = self else { return nil }
        return id
    }
}

package struct WorkspaceNoteTitleProjection: Hashable, Sendable {
    package let sourceFingerprint: DocumentFingerprint
    package let resolution: ResearchNoteTitleResolution

    package init(
        document: NoteDocument,
        vaultRole: VaultRole,
        semantic: MarkdownSemanticDocument
    ) {
        sourceFingerprint = document.fingerprint
        resolution = ResearchNoteTitleResolver.resolve(
            document: document,
            vaultRole: vaultRole,
            semantic: semantic
        )
    }
}

/// A source-fidelity-preserving note projection. `document` retains the exact
/// bytes loaded by `VaultRepository`. Application-owned Workspace generations
/// carry `current` derived state. An exact window may transiently overlay a
/// committed source with `sourceAhead`; consumers must not treat its graph
/// counts or other Workspace-wide projections as current until replacement by
/// the matching complete generation.
public struct WorkspaceNoteSnapshot: Hashable, Sendable {
    public let id: VaultQualifiedNoteID
    public let vaultRole: VaultRole
    public let stableIdentity: WorkspaceNoteIdentityState
    public let document: NoteDocument
    public let fileMetadata: WorkspaceFileMetadata
    public let lifecycle: WorkspaceDocumentLifecycle
    public let graphCounts: WorkspaceGraphCounts
    public let derivedProjectionState: WorkspaceNoteDerivedProjectionState
    /// Source-bound heading projection prepared by the workspace catalog for
    /// this exact fingerprint. Presentation consumers must not parse Markdown
    /// again merely to build document navigation.
    public let headings: [HeadingNode]
    package let cachedTitleProjection: WorkspaceNoteTitleProjection?

    public var fingerprint: DocumentFingerprint { document.fingerprint }
    public var validationWarnings: [String] { document.validationWarnings }
    public var capabilities: DocumentCapabilities {
        let identity: DocumentIdentityResolution = switch stableIdentity {
        case .resolved: .resolved
        case .ambiguous: .ambiguous
        case .pending: .pending
        case .unresolved: .unresolved
        }
        return DocumentCapabilities(
            role: vaultRole,
            lifecycle: lifecycle,
            identity: identity,
            isManagedCritique: vaultRole.allowsCritique
                && CritiquePlacement.isManagedCritiquePath(document.relativePath)
        )
    }
    public var schemaProfile: SchemaProfileID {
        WorkflowProfileResolver.resolve(
            vaultRole: vaultRole,
            frontmatter: document.parsedFrontmatter,
            relativePath: document.relativePath
        )
    }

    public init(
        id: VaultQualifiedNoteID,
        vaultRole: VaultRole = .other,
        stableIdentity: WorkspaceNoteIdentityState,
        document: NoteDocument,
        fileMetadata: WorkspaceFileMetadata,
        lifecycle: WorkspaceDocumentLifecycle,
        graphCounts: WorkspaceGraphCounts,
        headings: [HeadingNode] = [],
        derivedProjectionState: WorkspaceNoteDerivedProjectionState = .current
    ) {
        self.init(
            id: id,
            vaultRole: vaultRole,
            stableIdentity: stableIdentity,
            document: document,
            fileMetadata: fileMetadata,
            lifecycle: lifecycle,
            graphCounts: graphCounts,
            headings: headings,
            derivedProjectionState: derivedProjectionState,
            cachedTitleProjection: nil
        )
    }

    package init(
        id: VaultQualifiedNoteID,
        vaultRole: VaultRole = .other,
        stableIdentity: WorkspaceNoteIdentityState,
        document: NoteDocument,
        fileMetadata: WorkspaceFileMetadata,
        lifecycle: WorkspaceDocumentLifecycle,
        graphCounts: WorkspaceGraphCounts,
        headings: [HeadingNode],
        derivedProjectionState: WorkspaceNoteDerivedProjectionState = .current,
        cachedTitleProjection: WorkspaceNoteTitleProjection?
    ) {
        self.id = id
        self.vaultRole = vaultRole
        self.stableIdentity = stableIdentity
        self.document = document
        self.fileMetadata = fileMetadata
        self.lifecycle = lifecycle
        self.graphCounts = graphCounts
        self.headings = headings
        self.derivedProjectionState = derivedProjectionState
        self.cachedTitleProjection = cachedTitleProjection?.sourceFingerprint == document.fingerprint
            ? cachedTitleProjection
            : nil
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.vaultRole == rhs.vaultRole
            && lhs.stableIdentity == rhs.stableIdentity
            && lhs.fingerprint == rhs.fingerprint
            && lhs.fileMetadata == rhs.fileMetadata
            && lhs.lifecycle == rhs.lifecycle
            && lhs.graphCounts == rhs.graphCounts
            && lhs.derivedProjectionState == rhs.derivedProjectionState
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(vaultRole)
        hasher.combine(stableIdentity)
        hasher.combine(fingerprint)
        hasher.combine(fileMetadata)
        hasher.combine(lifecycle)
        hasher.combine(graphCounts)
        hasher.combine(derivedProjectionState)
    }
}

/// The exact result of direct untitled-note creation before disposable
/// Workspace projections necessarily catch up. The source and portable
/// identity state are authoritative; graph counts are intentionally absent.
public struct WorkspaceManagedNoteCommit: Sendable {
    public let id: VaultQualifiedNoteID
    public let vaultRole: VaultRole
    public let stableIdentity: WorkspaceNoteIdentityState
    public let document: NoteDocument

    public init(
        id: VaultQualifiedNoteID,
        vaultRole: VaultRole,
        stableIdentity: WorkspaceNoteIdentityState,
        document: NoteDocument
    ) {
        self.id = id
        self.vaultRole = vaultRole
        self.stableIdentity = stableIdentity
        self.document = document
    }

    /// A bounded window presentation while the matching complete Workspace
    /// generation is pending. Zero graph values are nonauthorizing placeholders
    /// and are explicitly guarded by `sourceAhead`.
    public var sourceAheadSnapshot: WorkspaceNoteSnapshot {
        WorkspaceNoteSnapshot(
            id: id,
            vaultRole: vaultRole,
            stableIdentity: stableIdentity,
            document: document,
            fileMetadata: WorkspaceFileMetadata(
                byteCount: document.sourceBytes.count,
                creationDate: nil,
                modificationDate: nil
            ),
            lifecycle: .active,
            graphCounts: WorkspaceGraphCounts(
                incoming: 0,
                outgoing: 0,
                broken: 0,
                ambiguous: 0
            ),
            headings: [],
            derivedProjectionState: .sourceAhead
        )
    }
}

/// A location change proven by one resolved portable note identity.
public struct WorkspaceNoteMove: Hashable, Sendable {
    public let stableNoteID: UUID
    public let previousLocation: VaultQualifiedNoteID
    public let location: VaultQualifiedNoteID

    public init(
        stableNoteID: UUID,
        previousLocation: VaultQualifiedNoteID,
        location: VaultQualifiedNoteID
    ) {
        self.stableNoteID = stableNoteID
        self.previousLocation = previousLocation
        self.location = location
    }
}

public struct WorkspaceVaultSnapshot: Sendable {
    public let slot: WorkspaceVaultSlot
    public let vault: RegisteredVault
    public let pathComparisonPolicy: VaultPathComparisonPolicy
    public let documents: [WorkspaceNoteSnapshot]
    public let folders: [VaultRelativeFolderPath]
    public let identityRecovery: NoteIdentityRecoveryState

    public init(
        slot: WorkspaceVaultSlot,
        vault: RegisteredVault,
        pathComparisonPolicy: VaultPathComparisonPolicy,
        documents: [WorkspaceNoteSnapshot],
        folders: [VaultRelativeFolderPath] = [],
        identityRecovery: NoteIdentityRecoveryState
    ) {
        self.slot = slot
        self.vault = vault
        self.pathComparisonPolicy = pathComparisonPolicy
        self.documents = documents
        self.folders = folders
        self.identityRecovery = identityRecovery
    }
}

public struct WorkspaceDiscoverySnapshot: Sendable {
    public let catalog: WorkspaceCatalogSnapshot
    public let searchGeneration: SearchGenerationID?

    public init(
        catalog: WorkspaceCatalogSnapshot,
        searchGeneration: SearchGenerationID?
    ) {
        self.catalog = catalog
        self.searchGeneration = searchGeneration
    }
}

/// Research-record projection for one complete workspace generation. Durable
/// mutations are performed only through `ResearchOperations`; this value is
/// immutable delivery-neutral state for GUI, CLI, and future snapshot readers.
public enum WorkspaceResearchActivityState: String, Hashable, Sendable {
    case waitingForAgent
    case running
    case needsAttention
}

public enum WorkspaceResearchActivityRepairReason: String, Hashable, Sendable {
    case sourceConflict
    case sourceChanged
    case recoveryRequired
    case recordUnavailable
}

public enum WorkspaceNoteReviewStatus: String, Hashable, Sendable {
    case noAgentChangesToReview
    case needsReview
    case noAgentChangesAwaitingReview
}

public struct WorkspaceNoteReviewState: Hashable, Identifiable, Sendable {
    public let noteID: UUID
    public let currentRevision: DocumentFingerprint?
    public let status: WorkspaceNoteReviewStatus
    public let pendingActivities: [PortableResearchNoteActivityReference]
    public let lastReviewedAt: Date?
    public let lastReviewedRevision: DocumentFingerprint?

    public var id: UUID { noteID }

    public init(
        noteID: UUID,
        currentRevision: DocumentFingerprint?,
        status: WorkspaceNoteReviewStatus,
        pendingActivities: [PortableResearchNoteActivityReference] = [],
        lastReviewedAt: Date? = nil,
        lastReviewedRevision: DocumentFingerprint? = nil
    ) {
        self.noteID = noteID
        self.currentRevision = currentRevision
        self.status = status
        self.pendingActivities = pendingActivities
        self.lastReviewedAt = lastReviewedAt
        self.lastReviewedRevision = lastReviewedRevision
    }
}

public struct WorkspaceResearchResultArrival: Hashable, Identifiable, Sendable {
    public let runID: UUID
    public let recordID: UUID
    public let actionID: ResearchActionID
    public let originNoteID: UUID
    public let recordFingerprint: DocumentFingerprint
    public let finishedAt: Date

    public var id: UUID { recordID }

    public init(
        runID: UUID,
        recordID: UUID,
        actionID: ResearchActionID,
        originNoteID: UUID,
        recordFingerprint: DocumentFingerprint,
        finishedAt: Date
    ) {
        self.runID = runID
        self.recordID = recordID
        self.actionID = actionID
        self.originNoteID = originNoteID
        self.recordFingerprint = recordFingerprint
        self.finishedAt = finishedAt
    }
}

/// A privacy-bounded projection over machine-local execution and portable
/// Record truth. It contains no handoff secret, checkpoint identity, source
/// bytes, or tool trace and is never a durable workflow owner.
public struct WorkspaceResearchActivity: Hashable, Identifiable, Sendable {
    public let runID: UUID
    public let actionID: ResearchActionID
    public let targetNoteID: UUID
    public let state: WorkspaceResearchActivityState
    public let recordID: UUID?
    public let recordFingerprint: DocumentFingerprint?
    public let repairReason: WorkspaceResearchActivityRepairReason?
    public let updatedAt: Date

    public var id: UUID { runID }

    public init(
        runID: UUID,
        actionID: ResearchActionID,
        targetNoteID: UUID,
        state: WorkspaceResearchActivityState,
        recordID: UUID? = nil,
        recordFingerprint: DocumentFingerprint? = nil,
        repairReason: WorkspaceResearchActivityRepairReason? = nil,
        updatedAt: Date
    ) {
        self.runID = runID
        self.actionID = actionID
        self.targetNoteID = targetNoteID
        self.state = state
        self.recordID = recordID
        self.recordFingerprint = recordFingerprint
        self.repairReason = repairReason
        self.updatedAt = updatedAt
    }
}

public struct WorkspaceResearchSnapshot: Sendable {
    public let settlements: [SettlementRecord]
    public let activeDiscussions: [PortableResearchDiscussion]
    public let finishedResearchRecords: [PortableResearchRecord]
    /// Exact fingerprints of the authoritative portable JSON bytes read for
    /// this snapshot. Missing entries are never reconstructed by re-encoding.
    public let finishedResearchRecordFingerprints: [UUID: DocumentFingerprint]
    /// Stable hash of the valid Record UUID + exact-byte fingerprint set.
    public let finishedResearchRecordSourceManifestHash: String
    /// False when any portable Record file failed exact reading or validation;
    /// Search must not present the remaining subset as a complete corpus.
    public let finishedResearchRecordProjectionIsComplete: Bool
    public let critiques: [CritiqueAssociation]
    public let checkpointListing: TriptychCheckpointListing
    public let recoveryRecords: [TriptychMutationRecoveryRecord]
    public let activities: [WorkspaceResearchActivity]
    public let noteReviews: [PortableResearchNoteReview]
    public let noteReviewStates: [WorkspaceNoteReviewState]
    public let resultArrivals: [WorkspaceResearchResultArrival]
    public let healthIssues: [String]

    public init(
        settlements: [SettlementRecord] = [],
        activeDiscussions: [PortableResearchDiscussion] = [],
        finishedResearchRecords: [PortableResearchRecord] = [],
        finishedResearchRecordFingerprints: [UUID: DocumentFingerprint] = [:],
        finishedResearchRecordSourceManifestHash: String = "",
        finishedResearchRecordProjectionIsComplete: Bool = true,
        critiques: [CritiqueAssociation],
        checkpointListing: TriptychCheckpointListing,
        recoveryRecords: [TriptychMutationRecoveryRecord] = [],
        activities: [WorkspaceResearchActivity] = [],
        noteReviews: [PortableResearchNoteReview] = [],
        noteReviewStates: [WorkspaceNoteReviewState] = [],
        resultArrivals: [WorkspaceResearchResultArrival] = [],
        healthIssues: [String]
    ) {
        self.settlements = settlements
        self.activeDiscussions = activeDiscussions
        self.finishedResearchRecords = finishedResearchRecords
        self.finishedResearchRecordFingerprints = finishedResearchRecordFingerprints
        self.finishedResearchRecordSourceManifestHash = finishedResearchRecordSourceManifestHash
        self.finishedResearchRecordProjectionIsComplete =
            finishedResearchRecordProjectionIsComplete
        self.critiques = critiques
        self.checkpointListing = checkpointListing
        self.recoveryRecords = recoveryRecords
        self.activities = activities
        self.noteReviews = noteReviews
        self.noteReviewStates = noteReviewStates
        self.resultArrivals = resultArrivals
        self.healthIssues = healthIssues
    }
}


/// A persisted Critique association together with the version-bound external
/// instructions and the automatic checkpoint created before source mutation.
public struct CritiquePreparation: Sendable {
    public let association: CritiqueAssociation
    public let instructions: String
    public let checkpoint: TriptychCheckpoint?

    public init(
        association: CritiqueAssociation,
        instructions: String,
        checkpoint: TriptychCheckpoint?
    ) {
        self.association = association
        self.instructions = instructions
        self.checkpoint = checkpoint
    }
}

/// A complete, generation-independent projection of one Triptych.
public struct WorkspaceSnapshot: Sendable {
    public let triptych: ScholiumTriptych
    public let mode: WorkspaceConfigurationMode
    public let generatedAt: Date
    public let vaults: [WorkspaceVaultSnapshot]
    public let discovery: WorkspaceDiscoverySnapshot
    public let research: WorkspaceResearchSnapshot

    public init(
        triptych: ScholiumTriptych,
        mode: WorkspaceConfigurationMode,
        generatedAt: Date,
        vaults: [WorkspaceVaultSnapshot],
        discovery: WorkspaceDiscoverySnapshot,
        research: WorkspaceResearchSnapshot
    ) {
        self.triptych = triptych
        self.mode = mode
        self.generatedAt = generatedAt
        self.vaults = vaults
        self.discovery = discovery
        self.research = research
    }

    public func vault(id: UUID) -> WorkspaceVaultSnapshot? {
        vaults.first { $0.vault.id == id }
    }

    public func document(id: VaultQualifiedNoteID) -> WorkspaceNoteSnapshot? {
        vault(id: id.vaultID)?.documents.first { $0.id == id }
    }
}

public struct WorkspaceSnapshotEvent: Sendable {
    public let generation: UInt64
    public let snapshot: WorkspaceSnapshot

    public init(generation: UInt64, snapshot: WorkspaceSnapshot) {
        self.generation = generation
        self.snapshot = snapshot
    }
}

public enum WorkspaceSourceCommitKind: Equatable, Sendable {
    case creation
    case save
    case checkpointRestore(checkpointID: UUID)
}

public struct WorkspaceSourceCommittedEvent: Sendable {
    public let generation: UInt64
    public let note: WorkspaceNoteSnapshot
    public let kind: WorkspaceSourceCommitKind
    public let snapshot: WorkspaceSnapshot

    public init(
        generation: UInt64,
        note: WorkspaceNoteSnapshot,
        kind: WorkspaceSourceCommitKind,
        snapshot: WorkspaceSnapshot
    ) {
        self.generation = generation
        self.note = note
        self.kind = kind
        self.snapshot = snapshot
    }
}

public struct WorkspaceInventoryChangedEvent: Sendable {
    public let generation: UInt64
    public let added: Set<VaultQualifiedNoteID>
    public let removed: Set<VaultQualifiedNoteID>
    public let changed: Set<VaultQualifiedNoteID>
    public let moved: [WorkspaceNoteMove]
    public let snapshot: WorkspaceSnapshot

    public init(
        generation: UInt64,
        added: Set<VaultQualifiedNoteID>,
        removed: Set<VaultQualifiedNoteID>,
        changed: Set<VaultQualifiedNoteID>,
        moved: [WorkspaceNoteMove] = [],
        snapshot: WorkspaceSnapshot
    ) {
        self.generation = generation
        self.added = added
        self.removed = removed
        self.changed = changed
        self.moved = moved
        self.snapshot = snapshot
    }
}

/// Evidence identifying the complete derived projection represented by a
/// workspace snapshot. Consumers can compare the graph and Triptych lexical
/// generations without reaching into an index implementation.
public struct WorkspaceDerivedRefreshEvidence: Sendable, Equatable {
    public let snapshotGeneratedAt: Date
    public let graphGeneration: Int?
    public let searchGeneration: SearchGenerationID?

    public init(
        snapshotGeneratedAt: Date,
        graphGeneration: Int?,
        searchGeneration: SearchGenerationID?
    ) {
        self.snapshotGeneratedAt = snapshotGeneratedAt
        self.graphGeneration = graphGeneration
        self.searchGeneration = searchGeneration
    }

    public init(snapshot: WorkspaceSnapshot) {
        self.init(
            snapshotGeneratedAt: snapshot.generatedAt,
            graphGeneration: snapshot.discovery.catalog.graph?.generation,
            searchGeneration: snapshot.discovery.searchGeneration
        )
    }
}

/// Diagnostic context for a projection whose freshness can no longer be
/// guaranteed. `lastKnownGood` always describes the snapshot carried by the
/// event; it never describes a partially rebuilt index.
public struct WorkspaceDerivedRefreshIssue: Sendable, Equatable {
    public let reason: String
    public let affectedVaultIDs: Set<UUID>
    public let lastKnownGood: WorkspaceDerivedRefreshEvidence

    public init(
        reason: String,
        affectedVaultIDs: Set<UUID> = [],
        lastKnownGood: WorkspaceDerivedRefreshEvidence
    ) {
        self.reason = reason
        self.affectedVaultIDs = affectedVaultIDs
        self.lastKnownGood = lastKnownGood
    }
}

/// Delivery-neutral freshness of search, relationship, diagnostic, and other
/// derived workspace state.
///
/// - `current`: the event's complete snapshot and evidence were rebuilt
///   successfully.
/// - `stale`: a durable mutation or watcher discontinuity may be ahead of the
///   last known good snapshot. The mutation must not be retried merely to make
///   derived state catch up.
/// - `failed`: an attempted rebuild failed. The complete last known good
///   snapshot remains readable while a later refresh retries the projection.
public enum WorkspaceDerivedRefreshStatus: Sendable, Equatable {
    case current(WorkspaceDerivedRefreshEvidence)
    case stale(WorkspaceDerivedRefreshIssue)
    case failed(WorkspaceDerivedRefreshIssue)
}

public struct WorkspaceDerivedStateChangedEvent: Sendable {
    public let generation: UInt64
    public let status: WorkspaceDerivedRefreshStatus
    public let discovery: WorkspaceDiscoverySnapshot
    public let snapshot: WorkspaceSnapshot

    public init(
        generation: UInt64,
        status: WorkspaceDerivedRefreshStatus,
        discovery: WorkspaceDiscoverySnapshot,
        snapshot: WorkspaceSnapshot
    ) {
        self.generation = generation
        self.status = status
        self.discovery = discovery
        self.snapshot = snapshot
    }
}

public struct WorkspaceResearchRecordsChangedEvent: Sendable {
    public let generation: UInt64
    public let research: WorkspaceResearchSnapshot
    public let snapshot: WorkspaceSnapshot

    public init(
        generation: UInt64,
        research: WorkspaceResearchSnapshot,
        snapshot: WorkspaceSnapshot
    ) {
        self.generation = generation
        self.research = research
        self.snapshot = snapshot
    }
}

/// Invalidates projections that resolve mutable Research Guidance state.
/// The event deliberately does not claim that an attempted configuration
/// mutation committed: consumers reread the exact current Method, Skill,
/// Profile, and permission state after the mutation gate closes.
public struct WorkspaceResearchConfigurationInvalidatedEvent: Sendable {
    public let generation: UInt64
    public let snapshot: WorkspaceSnapshot

    public init(generation: UInt64, snapshot: WorkspaceSnapshot) {
        self.generation = generation
        self.snapshot = snapshot
    }
}

public struct WorkspaceRuntimeReloadedEvent: Sendable {
    public let generation: UInt64
    public let runtimeIdentity: TriptychRuntimeIdentity
    public let snapshot: WorkspaceSnapshot

    public init(
        generation: UInt64,
        runtimeIdentity: TriptychRuntimeIdentity,
        snapshot: WorkspaceSnapshot
    ) {
        self.generation = generation
        self.runtimeIdentity = runtimeIdentity
        self.snapshot = snapshot
    }
}

public struct TriptychRuntimeIdentity: Codable, Hashable, Sendable {
    public let triptychID: UUID
    public let activationID: UUID

    public init(triptychID: UUID, activationID: UUID) {
        self.triptychID = triptychID
        self.activationID = activationID
    }
}

/// Closed application event vocabulary. Each case carries only the projection
/// relevant to its change plus the resulting complete snapshot for resync.
public enum WorkspaceEvent: Sendable {
    case snapshot(WorkspaceSnapshotEvent)
    case sourceCommitted(WorkspaceSourceCommittedEvent)
    case inventoryChanged(WorkspaceInventoryChangedEvent)
    case derivedStateChanged(WorkspaceDerivedStateChangedEvent)
    case researchRecordsChanged(WorkspaceResearchRecordsChangedEvent)
    case researchConfigurationInvalidated(
        WorkspaceResearchConfigurationInvalidatedEvent
    )
    case runtimeReloaded(WorkspaceRuntimeReloadedEvent)

    public var generation: UInt64 {
        switch self {
        case .snapshot(let event): event.generation
        case .sourceCommitted(let event): event.generation
        case .inventoryChanged(let event): event.generation
        case .derivedStateChanged(let event): event.generation
        case .researchRecordsChanged(let event): event.generation
        case .researchConfigurationInvalidated(let event): event.generation
        case .runtimeReloaded(let event): event.generation
        }
    }

    public var snapshot: WorkspaceSnapshot {
        switch self {
        case .snapshot(let event): event.snapshot
        case .sourceCommitted(let event): event.snapshot
        case .inventoryChanged(let event): event.snapshot
        case .derivedStateChanged(let event): event.snapshot
        case .researchRecordsChanged(let event): event.snapshot
        case .researchConfigurationInvalidated(let event): event.snapshot
        case .runtimeReloaded(let event): event.snapshot
        }
    }

    /// The freshness represented by this complete generation. Non-derived
    /// cases are emitted only after a successful workspace rebuild, so they
    /// also clear an earlier stale/failed status without requiring a second
    /// event that could obscure the primary source or inventory change.
    public var derivedRefreshStatus: WorkspaceDerivedRefreshStatus {
        switch self {
        case .derivedStateChanged(let event):
            event.status
        case .snapshot,
             .sourceCommitted,
             .inventoryChanged,
             .researchRecordsChanged,
             .researchConfigurationInvalidated,
             .runtimeReloaded:
            .current(WorkspaceDerivedRefreshEvidence(snapshot: snapshot))
        }
    }
}

/// The result of a Workspace mutation whose authoritative operation is proven
/// durable before this value is returned. Post-commit warnings describe only
/// work that must be recovered or refreshed without repeating the mutation.
/// A thrown error therefore never substitutes for a known committed value.
public struct WorkspaceMutationOutcome<CommittedValue: Sendable>: Sendable {
    public let committedValue: CommittedValue
    public let derivedRefreshWarning: String?
    public let identityRecoveryWarning: String?
    public let cleanupWarnings: [SaveCleanupWarning]

    public init(
        committedValue: CommittedValue,
        derivedRefreshWarning: String? = nil,
        identityRecoveryWarning: String? = nil,
        cleanupWarnings: [SaveCleanupWarning] = []
    ) {
        self.committedValue = committedValue
        self.derivedRefreshWarning = derivedRefreshWarning
        self.identityRecoveryWarning = identityRecoveryWarning
        self.cleanupWarnings = cleanupWarnings
    }
}

public enum ScholiumApplicationError: LocalizedError, Sendable {
    case runtimeShutDown
    case workspaceShutDown(UUID)
    case workspaceNotFound(UUID)
    case workspaceSelectorNotFound(String)
    case ambiguousWorkspaceSelector(String)
    case incompleteTriptych(UUID)
    case vaultNotInWorkspace(UUID)
    case manifestIdentityMismatch(expected: UUID, actual: UUID)
    case operationCommittedButRefreshFailed(operation: String, reason: String)
    case operationCommitUncertain(operation: String, reason: String)
    case noWorkspaceConfigured
    case researchStoreUnavailable(String)
    case runtimeConfigurationUnavailable

    /// `true` means the authoritative mutation is already durable and the
    /// caller must not retry it. Only disposable derived state failed to catch
    /// up; request or await a refresh instead.
    public var durableMutationWasCommitted: Bool {
        switch self {
        case .operationCommittedButRefreshFailed:
            true
        default:
            false
        }
    }

    /// A direct retry would either repeat an already committed mutation or
    /// act before a commit-uncertain replacement has been reconciled. This
    /// spelling is intentionally explicit for GUI and CLI error handling.
    public var mustNotRetryMutation: Bool { mutationRequiresReconciliation }

    /// `true` means retry is unsafe until the authoritative owner is reread.
    /// The first case is committed; the second deliberately makes no claim
    /// about whether the replacement crossed its durable boundary.
    public var mutationRequiresReconciliation: Bool {
        switch self {
        case .operationCommittedButRefreshFailed, .operationCommitUncertain:
            true
        default:
            false
        }
    }

    public var refreshFailureReason: String? {
        switch self {
        case .operationCommittedButRefreshFailed(_, let reason):
            reason
        default:
            nil
        }
    }

    public var errorDescription: String? {
        switch self {
        case .runtimeShutDown:
            "The Scholium application runtime has shut down."
        case .workspaceShutDown(let id):
            "The Scholium workspace \(id.uuidString) has shut down."
        case .workspaceNotFound(let id):
            "No Scholium Triptych matches \(id.uuidString)."
        case .workspaceSelectorNotFound(let selector):
            "No Scholium Triptych matches '\(selector)'."
        case .ambiguousWorkspaceSelector(let selector):
            "More than one Scholium Triptych is named '\(selector)'. Use its UUID."
        case .incompleteTriptych(let id):
            "The Scholium Triptych \(id.uuidString) does not contain all three vaults."
        case .vaultNotInWorkspace(let id):
            "Vault \(id.uuidString) is not part of this Scholium Triptych."
        case .manifestIdentityMismatch(let expected, let actual):
            "The portable Triptych identity is \(actual.uuidString), not \(expected.uuidString)."
        case .operationCommittedButRefreshFailed(let operation, let reason):
            "\(operation) committed successfully, but the workspace snapshot could not be refreshed: \(reason)"
        case .operationCommitUncertain(let operation, let reason):
            "Scholium could not prove whether \(operation) committed. Reload the authoritative state before trying another mutation: \(reason)"
        case .noWorkspaceConfigured:
            "No Scholium Triptych is configured."
        case .researchStoreUnavailable(let reason):
            "Scholium research records are unavailable. \(reason)"
        case .runtimeConfigurationUnavailable:
            "This fixed workspace snapshot cannot change Triptych registration or access."
        }
    }
}

/// Application-layer validation failures for research workflows. Core store,
/// repository, checkpoint, and workflow errors pass through unchanged when
/// they already describe the violated invariant precisely.
public enum ResearchOperationError: LocalizedError, Sendable {
    case noteUnavailable(VaultQualifiedNoteID)
    case commentUnavailable(VaultRole)
    case critiqueUnavailable(VaultRole)
    case critiqueTargetMustBeOrdinaryWork(String)
    case staleCommentRevision
    case discussionContextChanged
    case dialogueContextChanged(String)
    case invalidDialogueResponseContract([String])
    case critiqueRegistryUnavailable(String)
    case critiqueTargetChanged
    case critiqueRollbackFailed(requestError: String, rollbackError: String)
    case settleRollbackFailed(settleError: String, recoveryError: String)

    public var errorDescription: String? {
        switch self {
        case .noteUnavailable(let id):
            "The note at \(id.relativePath) is not available in this workspace generation."
        case .commentUnavailable:
            "Comments require a reliably identified Analysis, Topic, or Work."
        case .critiqueUnavailable:
            "Request Critique is available only for ordinary notes in Works."
        case .critiqueTargetMustBeOrdinaryWork(let path):
            "Request Critique requires an ordinary Work, not the managed Critique at \(path)."
        case .staleCommentRevision:
            "The note changed before the Comment could be attached. Reload the current source and select the passage again."
        case .discussionContextChanged:
            "The active Discussion has a different focal-note boundary. Finish it before starting a Discussion with new focal notes."
        case .dialogueContextChanged(let title):
            "\(title) changed, moved, or lost its stable identity while Discuss was being prepared. Reload the current note list and review the source again."
        case .invalidDialogueResponseContract(let issues):
            "The selected Discuss response contract is unavailable. \(issues.joined(separator: " "))"
        case .critiqueRegistryUnavailable(let reason):
            reason
        case .critiqueTargetChanged:
            "The Work changed while Scholium was preparing the Critique. Review the current Work and request its Critique again."
        case .critiqueRollbackFailed(let requestError, let rollbackError):
            "Scholium could not complete the Critique request and could not restore the prepared Critique source automatically. \(requestError) Recovery also failed: \(rollbackError) Inspect the current Critique and machine-local recovery before continuing."
        case .settleRollbackFailed(let settleError, let recoveryError):
            "Scholium could not record Settle and could not remove its newly pinned recovery version. \(settleError) Recovery cleanup also failed: \(recoveryError) Inspect Recovery & Technical before settling again."
        }
    }
}
