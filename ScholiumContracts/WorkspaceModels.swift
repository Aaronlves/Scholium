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

/// A source-fidelity-preserving note projection for one complete generation.
/// `document` retains the exact bytes loaded by `VaultRepository`; the other
/// fields are explicitly derived projections over that source revision.
public struct WorkspaceNoteSnapshot: Hashable, Sendable {
    public let id: VaultQualifiedNoteID
    public let vaultRole: VaultRole
    public let stableIdentity: WorkspaceNoteIdentityState
    public let document: NoteDocument
    public let fileMetadata: WorkspaceFileMetadata
    public let lifecycle: WorkspaceDocumentLifecycle
    public let graphCounts: WorkspaceGraphCounts
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
        graphCounts: WorkspaceGraphCounts
    ) {
        self.init(
            id: id,
            vaultRole: vaultRole,
            stableIdentity: stableIdentity,
            document: document,
            fileMetadata: fileMetadata,
            lifecycle: lifecycle,
            graphCounts: graphCounts,
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
        cachedTitleProjection: WorkspaceNoteTitleProjection?
    ) {
        self.id = id
        self.vaultRole = vaultRole
        self.stableIdentity = stableIdentity
        self.document = document
        self.fileMetadata = fileMetadata
        self.lifecycle = lifecycle
        self.graphCounts = graphCounts
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
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(vaultRole)
        hasher.combine(stableIdentity)
        hasher.combine(fingerprint)
        hasher.combine(fileMetadata)
        hasher.combine(lifecycle)
        hasher.combine(graphCounts)
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
    public let documents: [WorkspaceNoteSnapshot]
    public let folders: [VaultRelativeFolderPath]
    public let identityRecovery: NoteIdentityRecoveryState

    public init(
        slot: WorkspaceVaultSlot,
        vault: RegisteredVault,
        documents: [WorkspaceNoteSnapshot],
        folders: [VaultRelativeFolderPath] = [],
        identityRecovery: NoteIdentityRecoveryState
    ) {
        self.slot = slot
        self.vault = vault
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
public struct WorkspaceResearchSnapshot: Sendable {
    /// Compatibility-only archive. New product behavior never creates or
    /// projects Human Review records as current research state.
    public let legacyHumanReviews: [HumanReviewRecord]
    public let activityEvents: [ResearchActivityEvent]
    public let settlements: [SettlementRecord]
    public let annotations: [AnnotationRecord]
    public let commentExchanges: [CommentExchange]
    public let pendingResearchStates: [PendingResearchState]
    public let activityGrants: [ResearchActivityGrant]
    public let dialogues: [DialogueEntry]
    public let critiques: [CritiqueAssociation]
    public let functionRuns: [ResearchFunctionRecordProjection]
    public let checkpointListing: TriptychCheckpointListing
    public let recoveryRecords: [TriptychMutationRecoveryRecord]
    public let healthIssues: [String]

    public init(
        legacyHumanReviews: [HumanReviewRecord] = [],
        activityEvents: [ResearchActivityEvent] = [],
        settlements: [SettlementRecord] = [],
        annotations: [AnnotationRecord] = [],
        commentExchanges: [CommentExchange] = [],
        pendingResearchStates: [PendingResearchState] = [],
        activityGrants: [ResearchActivityGrant] = [],
        dialogues: [DialogueEntry],
        critiques: [CritiqueAssociation],
        functionRuns: [ResearchFunctionRecordProjection] = [],
        checkpointListing: TriptychCheckpointListing,
        recoveryRecords: [TriptychMutationRecoveryRecord] = [],
        healthIssues: [String]
    ) {
        self.legacyHumanReviews = legacyHumanReviews
        self.activityEvents = activityEvents
        self.settlements = settlements
        self.annotations = annotations
        self.commentExchanges = commentExchanges
        self.pendingResearchStates = pendingResearchStates
        self.activityGrants = activityGrants
        self.dialogues = dialogues
        self.critiques = critiques
        self.functionRuns = functionRuns
        self.checkpointListing = checkpointListing
        self.recoveryRecords = recoveryRecords
        self.healthIssues = healthIssues
    }
}

/// A saved Dialogue request together with the exact instructions prepared for
/// external transport and the automatic recovery checkpoint that precedes it.
public struct DialoguePreparation: Sendable {
    public let entry: DialogueEntry
    public let instructions: String
    public let checkpoint: TriptychCheckpoint?

    public init(
        entry: DialogueEntry,
        instructions: String,
        checkpoint: TriptychCheckpoint?
    ) {
        self.entry = entry
        self.instructions = instructions
        self.checkpoint = checkpoint
    }
}

/// A persisted Critique association together with the version-bound external
/// instructions and the automatic checkpoint created before source mutation.
public struct CritiquePreparation: Sendable {
    public let association: CritiqueAssociation
    public let instructions: String
    public let checkpoint: TriptychCheckpoint

    public init(
        association: CritiqueAssociation,
        instructions: String,
        checkpoint: TriptychCheckpoint
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
    case runtimeReloaded(WorkspaceRuntimeReloadedEvent)

    public var generation: UInt64 {
        switch self {
        case .snapshot(let event): event.generation
        case .sourceCommitted(let event): event.generation
        case .inventoryChanged(let event): event.generation
        case .derivedStateChanged(let event): event.generation
        case .researchRecordsChanged(let event): event.generation
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
             .runtimeReloaded:
            .current(WorkspaceDerivedRefreshEvidence(snapshot: snapshot))
        }
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
    case committedButRefreshFailed(DocumentFingerprint, String)
    case operationCommittedButRefreshFailed(operation: String, reason: String)
    case noWorkspaceConfigured
    case researchStoreUnavailable(String)
    case runtimeConfigurationUnavailable

    /// `true` means the authoritative mutation is already durable and the
    /// caller must not retry it. Only disposable derived state failed to catch
    /// up; request or await a refresh instead.
    public var durableMutationWasCommitted: Bool {
        switch self {
        case .committedButRefreshFailed, .operationCommittedButRefreshFailed:
            true
        default:
            false
        }
    }

    /// A direct retry would repeat an already committed mutation. This
    /// spelling is intentionally explicit for GUI and CLI error handling.
    public var mustNotRetryMutation: Bool { durableMutationWasCommitted }

    public var committedDocumentRevision: DocumentFingerprint? {
        guard case .committedButRefreshFailed(let revision, _) = self else {
            return nil
        }
        return revision
    }

    public var refreshFailureReason: String? {
        switch self {
        case .committedButRefreshFailed(_, let reason),
             .operationCommittedButRefreshFailed(_, let reason):
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
        case .committedButRefreshFailed(let fingerprint, let reason):
            "The source commit succeeded at revision \(fingerprint.sha256), but derived workspace refresh failed: \(reason)"
        case .operationCommittedButRefreshFailed(let operation, let reason):
            "\(operation) committed successfully, but the workspace snapshot could not be refreshed: \(reason)"
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
    case dialogueContextChanged(String)
    case invalidDialogueResponseContract([String])
    case critiqueRegistryUnavailable(String)
    case critiqueTargetChanged
    case critiqueRollbackFailed(requestError: String, rollbackError: String)

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
        case .dialogueContextChanged(let title):
            "\(title) changed, moved, or lost its stable identity while Discuss was being prepared. Reload the current note list and review the source again."
        case .invalidDialogueResponseContract(let issues):
            "The selected Discuss response contract is unavailable. \(issues.joined(separator: " "))"
        case .critiqueRegistryUnavailable(let reason):
            reason
        case .critiqueTargetChanged:
            "The Work changed while Scholium was creating Before Agent Work. Review the current Work and request its Critique again."
        case .critiqueRollbackFailed(let requestError, let rollbackError):
            "Scholium could not complete the Critique request and could not restore the prepared Critique source automatically. \(requestError) Recovery also failed: \(rollbackError) Use Before Agent Work before continuing."
        }
    }
}
