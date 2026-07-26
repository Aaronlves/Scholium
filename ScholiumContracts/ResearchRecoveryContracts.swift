import Foundation

/// Machine-local retention for distinct revisions pinned by Settle.
/// The limit applies independently to each stable Note identity.
public enum SettledSnapshotRetention: String, Codable, CaseIterable, Hashable, Sendable {
    case keep10 = "keep_10"
    case keep30 = "keep_30"
    case keep50 = "keep_50"
    case neverDelete = "never_delete"

    public static let defaultValue: Self = .keep30

    public var maximumCount: Int? {
        switch self {
        case .keep10: 10
        case .keep30: 30
        case .keep50: 50
        case .neverDelete: nil
        }
    }
}

/// Revision-checked machine-local recovery policy plus current bounded usage.
public struct ResearchRecoveryPolicySnapshot: Hashable, Sendable {
    public let retention: SettledSnapshotRetention
    public let revision: DocumentFingerprint?
    public let settledSnapshotCount: Int
    public let maximumSnapshotsForOneNote: Int

    public init(
        retention: SettledSnapshotRetention,
        revision: DocumentFingerprint?,
        settledSnapshotCount: Int,
        maximumSnapshotsForOneNote: Int
    ) {
        self.retention = retention
        self.revision = revision
        self.settledSnapshotCount = max(0, settledSnapshotCount)
        self.maximumSnapshotsForOneNote = max(0, maximumSnapshotsForOneNote)
    }
}

/// Bounded, short-lived preview used before lowering a retention limit. Only
/// the exact snapshot identities listed here may be removed by the apply step.
public struct ResearchRecoveryPolicyChangePreview: Hashable, Sendable {
    public let triptychID: UUID
    public let retention: SettledSnapshotRetention
    public let expectedPolicyRevision: DocumentFingerprint?
    public let snapshotIDsToRemove: Set<UUID>
    public let affectedNoteCount: Int

    public init(
        triptychID: UUID,
        retention: SettledSnapshotRetention,
        expectedPolicyRevision: DocumentFingerprint?,
        snapshotIDsToRemove: Set<UUID>,
        affectedNoteCount: Int
    ) {
        self.triptychID = triptychID
        self.retention = retention
        self.expectedPolicyRevision = expectedPolicyRevision
        self.snapshotIDsToRemove = snapshotIDsToRemove
        self.affectedNoteCount = max(0, affectedNoteCount)
    }
}

public struct ResearchRecoveryPolicyApplyOutcome: Hashable, Sendable {
    public let snapshot: ResearchRecoveryPolicySnapshot
    public let removedSnapshotCount: Int

    public init(
        snapshot: ResearchRecoveryPolicySnapshot,
        removedSnapshotCount: Int
    ) {
        self.snapshot = snapshot
        self.removedSnapshotCount = max(0, removedSnapshotCount)
    }
}

public enum ResearchRecoveryPolicyError: LocalizedError, Hashable, Sendable {
    case operationInProgress
    case changeTooLarge
    case staleRevision
    case stalePreview
    case corruptStore
    case unsafeStore

    public var errorDescription: String? {
        switch self {
        case .operationInProgress:
            "Another settled-version operation is still finishing. Try again when it completes."
        case .changeTooLarge:
            "This retention change affects too many settled versions to journal safely in one operation."
        case .staleRevision:
            "The Recovery policy changed. Reload it before saving."
        case .stalePreview:
            "The settled snapshots changed. Review the retention change again before removing older versions."
        case .corruptStore:
            "The machine-local Recovery policy is malformed or unreadable."
        case .unsafeStore:
            "The machine-local Recovery policy location is unsafe or changed during saving."
        }
    }
}
