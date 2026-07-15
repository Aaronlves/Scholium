import Foundation

public enum TriptychMutationOperation: String, Codable, Hashable, Sendable {
    case noteMove
    case unclassifiedClassification
    case permanentDeletion
}

public enum TriptychMutationFileRole: String, Codable, Hashable, Sendable {
    case movedNote
    case incomingLinkRewrite
    case classifiedSource
    case classifiedDestination
    case deletedNote
    case associatedCritique
}


public enum TriptychMutationRecoveryState: String, Codable, Hashable, Sendable {
    case restored
    case intendedBytesRemain
    case externallyChanged
    case missing
    case unreadable
}

public struct TriptychMutationRecoveryFile: Codable, Hashable, Sendable, Identifiable {
    public var id: String {
        "\(vaultID?.uuidString ?? "unclassified"):\(path):\(role.rawValue)"
    }

    public let vaultID: UUID?
    public let path: String
    public let alternatePath: String?
    public let role: TriptychMutationFileRole
    public let beforeRevision: DocumentFingerprint?
    public let intendedRevision: DocumentFingerprint?
    public let observedRevision: DocumentFingerprint?
    public let state: TriptychMutationRecoveryState
    public let detail: String

    public init(
        vaultID: UUID?,
        path: String,
        alternatePath: String? = nil,
        role: TriptychMutationFileRole,
        beforeRevision: DocumentFingerprint?,
        intendedRevision: DocumentFingerprint?,
        observedRevision: DocumentFingerprint?,
        state: TriptychMutationRecoveryState,
        detail: String
    ) {
        self.vaultID = vaultID
        self.path = path
        self.alternatePath = alternatePath
        self.role = role
        self.beforeRevision = beforeRevision
        self.intendedRevision = intendedRevision
        self.observedRevision = observedRevision
        self.state = state
        self.detail = detail
    }
}

/// Durable machine-local evidence that a multi-file operation could not be
/// completely rolled back. It never claims cross-filesystem atomicity.
public struct TriptychMutationRecoveryRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let triptychID: UUID
    public let operation: TriptychMutationOperation
    public let createdAt: Date
    public let failure: String
    public let files: [TriptychMutationRecoveryFile]
    public let permanentDeletionBackup: PermanentDeletionRecoveryBackup?

    public init(
        id: UUID = UUID(),
        triptychID: UUID,
        operation: TriptychMutationOperation,
        createdAt: Date = Date(),
        failure: String,
        files: [TriptychMutationRecoveryFile]
    ) {
        self.id = id
        self.triptychID = triptychID
        self.operation = operation
        self.createdAt = createdAt
        self.failure = failure
        self.files = files
        self.permanentDeletionBackup = nil
    }

    public init(
        id: UUID,
        triptychID: UUID,
        createdAt: Date,
        failure: String,
        files: [TriptychMutationRecoveryFile],
        permanentDeletionBackup: PermanentDeletionRecoveryBackup
    ) {
        self.id = id
        self.triptychID = triptychID
        self.operation = .permanentDeletion
        self.createdAt = createdAt
        self.failure = failure
        self.files = files
        self.permanentDeletionBackup = permanentDeletionBackup
    }
}

public struct CoordinatedIncomingLinkRewriteResult: Hashable, Sendable {
    public let note: VaultQualifiedNoteID
    public let previousRevision: DocumentFingerprint
    public let committedRevision: DocumentFingerprint
    public let rewrittenOccurrences: Int

    public init(
        note: VaultQualifiedNoteID,
        previousRevision: DocumentFingerprint,
        committedRevision: DocumentFingerprint,
        rewrittenOccurrences: Int
    ) {
        self.note = note
        self.previousRevision = previousRevision
        self.committedRevision = committedRevision
        self.rewrittenOccurrences = rewrittenOccurrences
    }
}

public struct TriptychMoveCommit: Hashable, Sendable {
    public let movedNote: VaultQualifiedNoteID
    public let destination: VaultQualifiedNoteID
    public let previousRevision: DocumentFingerprint
    public let committedRevision: DocumentFingerprint
    public let graphGeneration: Int
    public let rewrites: [CoordinatedIncomingLinkRewriteResult]

    public init(
        movedNote: VaultQualifiedNoteID,
        destination: VaultQualifiedNoteID,
        previousRevision: DocumentFingerprint,
        committedRevision: DocumentFingerprint,
        graphGeneration: Int,
        rewrites: [CoordinatedIncomingLinkRewriteResult]
    ) {
        self.movedNote = movedNote
        self.destination = destination
        self.previousRevision = previousRevision
        self.committedRevision = committedRevision
        self.graphGeneration = graphGeneration
        self.rewrites = rewrites
    }
}

public struct UnclassifiedClassificationCommit: Hashable, Sendable {
    public let sourceRelativePath: String
    public let destination: VaultQualifiedNoteID
    public let committedRevision: DocumentFingerprint

    public init(
        sourceRelativePath: String,
        destination: VaultQualifiedNoteID,
        committedRevision: DocumentFingerprint
    ) {
        self.sourceRelativePath = sourceRelativePath
        self.destination = destination
        self.committedRevision = committedRevision
    }
}

public enum TriptychTransactionError: LocalizedError, Sendable {
    case invalidPlan(String)
    case preflightFailed(note: VaultQualifiedNoteID?, detail: String)
    case transactionRolledBack(String)
    case recoveryRequired(TriptychMutationRecoveryRecord)
    case recoveryPersistenceFailed(TriptychMutationRecoveryRecord, String)

    public var errorDescription: String? {
        switch self {
        case .invalidPlan(let detail):
            return "The note move plan is invalid: \(detail)"
        case .preflightFailed(let note, let detail):
            if let note {
                return "Scholium did not change any files because \(note.relativePath) failed preflight: \(detail)"
            }
            return "Scholium did not change any files because preflight failed: \(detail)"
        case .transactionRolledBack(let detail):
            return "The operation failed and Scholium restored the affected files: \(detail)"
        case .recoveryRequired(let record):
            return "The operation did not complete and could not be fully restored. Recovery record \(record.id.uuidString) identifies every affected file."
        case .recoveryPersistenceFailed(let record, let detail):
            return "The operation requires recovery, and Scholium could not persist recovery record \(record.id.uuidString): \(detail)"
        }
    }
}
