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
    case portableMetadataAhead
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
    package let title: String

    package init(document: NoteDocument) {
        sourceFingerprint = document.fingerprint
        title = ResearchNoteTitleResolver.resolve(document: document)
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
    public let graphCounts: WorkspaceGraphCounts
    public let derivedProjectionState: WorkspaceNoteDerivedProjectionState
    /// Portable researcher-owned structured metadata joined by stable Note
    /// identity. It is authoritative for managed fields and is never derived
    /// from same-named YAML keys.
    public let metadata: NoteMetadataSnapshot?
    /// Source-bound heading projection prepared by the workspace catalog for
    /// this exact fingerprint. Presentation consumers must not parse Markdown
    /// again merely to build document navigation.
    public let headings: [HeadingNode]
    /// Exact-fingerprint derived semantics prepared by the workspace opening
    /// generation. Package consumers may reuse it but never write from it.
    package let cachedSemanticDocument: MarkdownSemanticDocument?
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
            identity: identity,
            isManagedCritique: vaultRole.allowsCritique
                && CritiquePlacement.isManagedCritiquePath(document.relativePath)
        )
    }
    public var schemaProfile: SchemaProfileID {
        WorkflowProfileResolver.resolve(vaultRole: vaultRole)
    }

    public init(
        id: VaultQualifiedNoteID,
        vaultRole: VaultRole = .other,
        stableIdentity: WorkspaceNoteIdentityState,
        document: NoteDocument,
        fileMetadata: WorkspaceFileMetadata,
        graphCounts: WorkspaceGraphCounts,
        metadata: NoteMetadataSnapshot? = nil,
        headings: [HeadingNode] = [],
        derivedProjectionState: WorkspaceNoteDerivedProjectionState = .current
    ) {
        self.init(
            id: id,
            vaultRole: vaultRole,
            stableIdentity: stableIdentity,
            document: document,
            fileMetadata: fileMetadata,
            graphCounts: graphCounts,
            metadata: metadata,
            headings: headings,
            derivedProjectionState: derivedProjectionState,
            cachedSemanticDocument: nil,
            cachedTitleProjection: nil
        )
    }

    package init(
        id: VaultQualifiedNoteID,
        vaultRole: VaultRole = .other,
        stableIdentity: WorkspaceNoteIdentityState,
        document: NoteDocument,
        fileMetadata: WorkspaceFileMetadata,
        graphCounts: WorkspaceGraphCounts,
        metadata: NoteMetadataSnapshot? = nil,
        headings: [HeadingNode],
        derivedProjectionState: WorkspaceNoteDerivedProjectionState = .current,
        cachedSemanticDocument: MarkdownSemanticDocument? = nil,
        cachedTitleProjection: WorkspaceNoteTitleProjection?
    ) {
        self.id = id
        self.vaultRole = vaultRole
        self.stableIdentity = stableIdentity
        self.document = document
        self.fileMetadata = fileMetadata
        self.graphCounts = graphCounts
        self.metadata = metadata
        self.headings = headings
        self.derivedProjectionState = derivedProjectionState
        self.cachedSemanticDocument = cachedSemanticDocument?.fingerprint == document.fingerprint
            ? cachedSemanticDocument
            : nil
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
            && lhs.graphCounts == rhs.graphCounts
            && lhs.metadata?.revision == rhs.metadata?.revision
            && lhs.derivedProjectionState == rhs.derivedProjectionState
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(vaultRole)
        hasher.combine(stableIdentity)
        hasher.combine(fingerprint)
        hasher.combine(fileMetadata)
        hasher.combine(graphCounts)
        hasher.combine(metadata?.revision)
        hasher.combine(derivedProjectionState)
    }

    /// Immediate window projection after one proven portable metadata commit.
    /// Source bytes remain unchanged; workspace-wide Search and catalog state
    /// catch up in the owning refresh generation.
    public func applyingCommittedMetadata(
        _ metadata: NoteMetadataSnapshot
    ) -> WorkspaceNoteSnapshot {
        WorkspaceNoteSnapshot(
            id: id,
            vaultRole: vaultRole,
            stableIdentity: stableIdentity,
            document: document,
            fileMetadata: fileMetadata,
            graphCounts: graphCounts,
            metadata: metadata,
            headings: headings,
            derivedProjectionState: .portableMetadataAhead,
            cachedSemanticDocument: cachedSemanticDocument,
            cachedTitleProjection: cachedSemanticDocument.map { _ in
                WorkspaceNoteTitleProjection(document: document)
            }
        )
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
    public let metadata: NoteMetadataSnapshot?

    public init(
        id: VaultQualifiedNoteID,
        vaultRole: VaultRole,
        stableIdentity: WorkspaceNoteIdentityState,
        document: NoteDocument,
        metadata: NoteMetadataSnapshot? = nil
    ) {
        self.id = id
        self.vaultRole = vaultRole
        self.stableIdentity = stableIdentity
        self.document = document
        self.metadata = metadata
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
            graphCounts: WorkspaceGraphCounts(
                incoming: 0,
                outgoing: 0,
                broken: 0,
                ambiguous: 0
            ),
            metadata: metadata,
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

public enum WorkspaceSettlementRequirementReason: String, Hashable, Sendable {
    case changedSinceSettlement
}

/// A delivery-neutral reminder that the current saved Note revision is not
/// covered by its latest Settlement. It is derived from current source and the
/// one Settlement marker and is never independently writable.
public struct WorkspaceSettlementRequirement: Hashable, Identifiable, Sendable {
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let title: String
    public let currentRevision: DocumentFingerprint
    public let reason: WorkspaceSettlementRequirementReason
    public let previousSettlement: SettlementRecord?

    public var id: UUID { noteID }

    public init(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        title: String,
        currentRevision: DocumentFingerprint,
        reason: WorkspaceSettlementRequirementReason,
        previousSettlement: SettlementRecord? = nil
    ) {
        self.noteID = noteID
        self.note = note
        self.title = title
        self.currentRevision = currentRevision
        self.reason = reason
        self.previousSettlement = previousSettlement
    }
}

public struct WorkspaceResearchSnapshot: Sendable {
    public let settlements: [SettlementRecord]
    public let critiques: [CritiqueAssociation]
    public let recoveryRecords: [TriptychMutationRecoveryRecord]
    public let settlementRequirements: [WorkspaceSettlementRequirement]
    public let healthIssues: [String]

    public init(
        settlements: [SettlementRecord] = [],
        critiques: [CritiqueAssociation],
        recoveryRecords: [TriptychMutationRecoveryRecord] = [],
        settlementRequirements: [WorkspaceSettlementRequirement] = [],
        healthIssues: [String]
    ) {
        self.settlements = settlements
        self.critiques = critiques
        self.recoveryRecords = recoveryRecords
        self.settlementRequirements = settlementRequirements
        self.healthIssues = healthIssues
    }
}


/// A persisted Critique association together with its version-bound external
/// instructions.
public struct CritiquePreparation: Sendable {
    public let association: CritiqueAssociation
    public let instructions: String

    public init(
        association: CritiqueAssociation,
        instructions: String
    ) {
        self.association = association
        self.instructions = instructions
    }
}

/// The completeness boundary carried by every immutable Triptych projection.
/// An opening snapshot contains one trustworthy, usable vault while the
/// remaining vaults and cross-vault derived state are still loading.
public enum WorkspaceSnapshotPhase: Equatable, Sendable {
    case opening(availableVault: WorkspaceVaultSlot)
    case complete

    public var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }
}

/// A generation-independent projection of one Triptych. `phase` states
/// whether the projection covers the complete Triptych or only the first
/// usable vault during live application opening.
public struct WorkspaceSnapshot: Sendable {
    public let triptych: ScholiumTriptych
    public let mode: WorkspaceConfigurationMode
    public let phase: WorkspaceSnapshotPhase
    public let generatedAt: Date
    public let metadataCatalog: NoteMetadataCatalog
    public let vaults: [WorkspaceVaultSnapshot]
    public let discovery: WorkspaceDiscoverySnapshot
    public let research: WorkspaceResearchSnapshot

    public init(
        triptych: ScholiumTriptych,
        mode: WorkspaceConfigurationMode,
        phase: WorkspaceSnapshotPhase = .complete,
        generatedAt: Date,
        metadataCatalog: NoteMetadataCatalog = .builtIn,
        vaults: [WorkspaceVaultSnapshot],
        discovery: WorkspaceDiscoverySnapshot,
        research: WorkspaceResearchSnapshot
    ) {
        self.triptych = triptych
        self.mode = mode
        self.phase = phase
        self.generatedAt = generatedAt
        self.metadataCatalog = metadataCatalog
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

/// Evidence identifying the derived projection represented by a workspace
/// snapshot. `snapshotPhase` prevents an opening vault projection from being
/// mistaken for a complete cross-vault generation.
public struct WorkspaceDerivedRefreshEvidence: Sendable, Equatable {
    public let snapshotPhase: WorkspaceSnapshotPhase
    public let snapshotGeneratedAt: Date
    public let graphGeneration: Int?
    public let searchGeneration: SearchGenerationID?

    public init(
        snapshotPhase: WorkspaceSnapshotPhase = .complete,
        snapshotGeneratedAt: Date,
        graphGeneration: Int?,
        searchGeneration: SearchGenerationID?
    ) {
        self.snapshotPhase = snapshotPhase
        self.snapshotGeneratedAt = snapshotGeneratedAt
        self.graphGeneration = graphGeneration
        self.searchGeneration = searchGeneration
    }

    public init(snapshot: WorkspaceSnapshot) {
        self.init(
            snapshotPhase: snapshot.phase,
            snapshotGeneratedAt: snapshot.generatedAt,
            graphGeneration: snapshot.discovery.catalog.graph?.generation,
            searchGeneration: snapshot.discovery.searchGeneration
        )
    }
}

/// Diagnostic context for a projection whose freshness can no longer be
/// guaranteed. `lastKnownGood` always describes the explicitly phased snapshot
/// carried by the event; it never describes an unpublished partial rebuild.
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

/// Delivery-neutral freshness of Search, link graph, diagnostic, and other
/// derived workspace state.
///
/// - `opening`: one vault is trustworthy and usable, but cross-vault derived
///   state is deliberately unavailable until a complete snapshot publishes.
/// - `current`: the event's complete snapshot and evidence were rebuilt
///   successfully.
/// - `stale`: a durable mutation or watcher discontinuity may be ahead of the
///   last known good snapshot. The mutation must not be retried merely to make
///   derived state catch up.
/// - `failed`: an attempted rebuild failed. The last explicitly phased good
///   snapshot remains readable while a later refresh retries the projection.
public enum WorkspaceDerivedRefreshStatus: Sendable, Equatable {
    case opening(WorkspaceDerivedRefreshEvidence)
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

public struct WorkspaceResearchStateChangedEvent: Sendable {
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

/// A terminal authority discontinuity for the current Workspace activation.
/// The last complete snapshot remains readable, but no source or derived-state
/// operation may resume until Restore Access installs a replacement runtime.
public struct WorkspaceVaultAccessInvalidatedEvent: Sendable {
    public let generation: UInt64
    public let unavailableVaultPaths: [UUID: String]
    public let snapshot: WorkspaceSnapshot

    public init(
        generation: UInt64,
        unavailableVaultPaths: [UUID: String],
        snapshot: WorkspaceSnapshot
    ) {
        self.generation = generation
        self.unavailableVaultPaths = unavailableVaultPaths
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
/// relevant to its change plus the resulting latest snapshot for resync.
public enum WorkspaceEvent: Sendable {
    case snapshot(WorkspaceSnapshotEvent)
    case sourceCommitted(WorkspaceSourceCommittedEvent)
    case inventoryChanged(WorkspaceInventoryChangedEvent)
    case derivedStateChanged(WorkspaceDerivedStateChangedEvent)
    case researchStateChanged(WorkspaceResearchStateChangedEvent)
    case researchConfigurationInvalidated(
        WorkspaceResearchConfigurationInvalidatedEvent
    )
    case vaultAccessInvalidated(WorkspaceVaultAccessInvalidatedEvent)
    case runtimeReloaded(WorkspaceRuntimeReloadedEvent)

    public var generation: UInt64 {
        switch self {
        case .snapshot(let event): event.generation
        case .sourceCommitted(let event): event.generation
        case .inventoryChanged(let event): event.generation
        case .derivedStateChanged(let event): event.generation
        case .researchStateChanged(let event): event.generation
        case .researchConfigurationInvalidated(let event): event.generation
        case .vaultAccessInvalidated(let event): event.generation
        case .runtimeReloaded(let event): event.generation
        }
    }

    public var snapshot: WorkspaceSnapshot {
        switch self {
        case .snapshot(let event): event.snapshot
        case .sourceCommitted(let event): event.snapshot
        case .inventoryChanged(let event): event.snapshot
        case .derivedStateChanged(let event): event.snapshot
        case .researchStateChanged(let event): event.snapshot
        case .researchConfigurationInvalidated(let event): event.snapshot
        case .vaultAccessInvalidated(let event): event.snapshot
        case .runtimeReloaded(let event): event.snapshot
        }
    }

    /// The freshness represented by this generation. An opening snapshot is
    /// explicitly non-complete; later non-derived cases are emitted only after
    /// a successful complete rebuild and clear the opening/stale/failed state.
    public var derivedRefreshStatus: WorkspaceDerivedRefreshStatus {
        switch self {
        case .derivedStateChanged(let event):
            event.status
        case .vaultAccessInvalidated(let event):
            .stale(WorkspaceDerivedRefreshIssue(
                reason: "A vault root changed identity. Restore access before Scholium reads, refreshes, or changes that vault again.",
                affectedVaultIDs: Set(event.unavailableVaultPaths.keys),
                lastKnownGood: WorkspaceDerivedRefreshEvidence(snapshot: event.snapshot)
            ))
        case .snapshot,
             .sourceCommitted,
             .inventoryChanged,
             .researchStateChanged,
             .researchConfigurationInvalidated,
             .runtimeReloaded:
            snapshot.phase.isComplete
                ? .current(WorkspaceDerivedRefreshEvidence(snapshot: snapshot))
                : .opening(WorkspaceDerivedRefreshEvidence(snapshot: snapshot))
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
    public let portableMetadataRecoveryWarning: String?

    public init(
        committedValue: CommittedValue,
        derivedRefreshWarning: String? = nil,
        identityRecoveryWarning: String? = nil,
        portableMetadataRecoveryWarning: String? = nil
    ) {
        self.committedValue = committedValue
        self.derivedRefreshWarning = derivedRefreshWarning
        self.identityRecoveryWarning = identityRecoveryWarning
        self.portableMetadataRecoveryWarning = portableMetadataRecoveryWarning
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
    case workspaceStillLoading(UUID)
    case workspaceRegistrationInUse(UUID)
    case portableControlRecoveryRequired(controlPath: String, reason: String)
    case noteMetadataRecoveryRequired(
        controlPath: String,
        issue: NoteMetadataRecoveryIssue
    )
    case manifestIdentityMismatch(expected: UUID, actual: UUID)
    case operationCommittedButRefreshFailed(operation: String, reason: String)
    case operationCommitUncertain(operation: String, reason: String)
    case noWorkspaceConfigured
    case critiqueStoreUnavailable(String)
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
        case .workspaceStillLoading(let id):
            "Scholium is still loading the complete Triptych \(id.uuidString). This Note and the currently open vault support bounded text Search; Triptych Search and direct links will become available when loading finishes."
        case .workspaceRegistrationInUse(let id):
            "Scholium cannot remove Triptych registration \(id.uuidString) while that Triptych is open. Close its other windows and try again."
        case .portableControlRecoveryRequired(let controlPath, let reason):
            "The portable control folder at \(controlPath) is incompatible or damaged. Preserve the entire folder before Scholium creates current control state. \(reason)"
        case .noteMetadataRecoveryRequired(let controlPath, let issue):
            "The portable Note metadata record \(issue.fileName) under \(controlPath) requires recovery. Archive only this exact record before reloading the Triptych. \(issue.explanation)"
        case .manifestIdentityMismatch(let expected, let actual):
            "The portable Triptych identity is \(actual.uuidString), not \(expected.uuidString)."
        case .operationCommittedButRefreshFailed(let operation, let reason):
            "\(operation) committed successfully, but the workspace snapshot could not be refreshed: \(reason)"
        case .operationCommitUncertain(let operation, let reason):
            "Scholium could not prove whether \(operation) committed. Reload the authoritative state before trying another mutation: \(reason)"
        case .noWorkspaceConfigured:
            "No Scholium Triptych is configured."
        case .critiqueStoreUnavailable(let reason):
            "Scholium Critique state is unavailable. \(reason)"
        case .runtimeConfigurationUnavailable:
            "This fixed workspace snapshot cannot change Triptych registration or access."
        }
    }
}

/// Application-layer validation failures for research workflows. Core store,
/// repository, change-evidence, and workflow errors pass through unchanged when
/// they already describe the violated invariant precisely.
public enum ResearchOperationError: LocalizedError, Sendable {
    case noteUnavailable(VaultQualifiedNoteID)
    case settlementUnavailable(VaultRole)
    case critiqueUnavailable(VaultRole)
    case critiqueTargetMustBeOrdinaryWork(String)
    case critiqueRegistryUnavailable(String)
    case critiqueTargetChanged
    case critiqueRollbackFailed(requestError: String, rollbackError: String)

    public var errorDescription: String? {
        switch self {
        case .noteUnavailable(let id):
            "The note at \(id.relativePath) is not available in this workspace generation."
        case .settlementUnavailable:
            "Settlement requires a reliably identified Analysis, Topic, or Work."
        case .critiqueUnavailable:
            "Request Critique is available only for ordinary notes in Works."
        case .critiqueTargetMustBeOrdinaryWork(let path):
            "Request Critique requires an ordinary Work, not the managed Critique at \(path)."
        case .critiqueRegistryUnavailable(let reason):
            reason
        case .critiqueTargetChanged:
            "The Work changed while Scholium was preparing the Critique. Review the current Work and request its Critique again."
        case .critiqueRollbackFailed(let requestError, let rollbackError):
            "Scholium could not complete the Critique request and could not restore the prepared Critique source automatically. \(requestError) Recovery also failed: \(rollbackError) Inspect the current Critique and machine-local recovery before continuing."
        }
    }
}
