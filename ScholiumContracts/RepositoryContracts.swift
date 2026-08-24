import Foundation

public enum VaultRepositoryError: LocalizedError, Sendable {
    case invalidRelativePath(String)
    case outsideVault(String)
    case rootUnavailable(String)
    case fileDoesNotExist(String)
    case fileAlreadyExists(String)
    case notRegularFile(String)
    case markdownRequired(String)
    case conflict(expected: DocumentFingerprint, current: DocumentFingerprint)
    case readbackMismatch(expected: DocumentFingerprint, current: DocumentFingerprint)
    case invalidFrontmatter(String)
    case recoveryEntryNotFound(UUID)
    case recoveryPathConflict(String)
    case recoveryLedgerUnavailable(String)
    case pathCollision(existing: String, requested: String)
    case writeFailed(String)
    case commitUncertain(String)
    case recoveryRequired(InterruptedSaveRecovery)
    case atomicCommitUnsupported(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRelativePath(let path): return "Invalid vault-relative path: \(path)"
        case .outsideVault(let path): return "The path escapes the selected vault: \(path)"
        case .rootUnavailable(let path):
            return "The selected vault root is no longer the authorized filesystem object: \(path)"
        case .fileDoesNotExist(let path): return "The note no longer exists: \(path)"
        case .fileAlreadyExists(let path): return "A note already exists at: \(path)"
        case .notRegularFile(let path): return "The path is not a regular file: \(path)"
        case .markdownRequired(let path): return "Scholium note operations require a Markdown file: \(path)"
        case .conflict: return "This note changed on disk after editing began. Compare changes or reload before saving."
        case .readbackMismatch:
            return "Scholium could not verify the saved bytes. The editor buffer and any unresolved save transaction remain available for recovery."
        case .invalidFrontmatter(let message): return "Invalid YAML frontmatter: \(message)"
        case .recoveryEntryNotFound(let id): return "Recovery entry not found: \(id.uuidString)"
        case .recoveryPathConflict(let path):
            return "An interrupted-save transaction already belongs to another note at: \(path)"
        case .recoveryLedgerUnavailable(let reason):
            return "Interrupted-save recovery is unavailable, so Scholium did not modify the note. Existing transaction evidence remains unchanged. \(reason)"
        case .pathCollision(let existing, let requested):
            return "The requested note path collides with an existing path on this volume: \(requested) (existing: \(existing))"
        case .writeFailed(let reason):
            return "Scholium could not save the note. The source remains unchanged and you can retry. \(reason)"
        case .commitUncertain(let reason):
            return "Scholium could not prove which bytes are canonical after the commit. It preserved recovery evidence and did not report the note as saved. \(reason)"
        case .recoveryRequired(let recovery):
            return "The note save remains unresolved. Recovery transaction \(recovery.id.transactionID.uuidString) requires exact source reconciliation before the write can be finalized."
        case .atomicCommitUnsupported(let reason):
            return "This volume cannot provide the coordinated atomic commit required for this operation. The note remains open and unchanged. \(reason)"
        }
    }
}

/// Vault-qualified identity for one retained save transaction. The transaction
/// UUID alone is not sufficient authority because every vault owns an
/// independent machine-local recovery ledger.
public struct InterruptedSaveRecoveryID: Codable, Hashable, Sendable {
    public let vaultID: UUID
    public let transactionID: UUID

    public init(vaultID: UUID, transactionID: UUID) {
        self.vaultID = vaultID
        self.transactionID = transactionID
    }
}

/// Last observed relationship between authoritative source and a retained
/// interrupted-save candidate. This is presentation state only; restore always
/// performs a fresh descriptor-relative revision check in Core.
public enum InterruptedSaveRecoverySourceState: Hashable, Sendable {
    case expectedRevision
    case candidateRevision
    case changed(DocumentFingerprint)
    case missing
    case unavailable(String)

    public var permitsRecovery: Bool {
        switch self {
        case .expectedRevision, .candidateRevision:
            true
        case .changed, .missing, .unavailable:
            false
        }
    }
}

/// Read-only metadata for exact candidate bytes retained after an interrupted
/// save. Every field is carried back to Core when content is loaded, revealed,
/// or restored so a stale or substituted manifest cannot change the action's
/// target silently.
public struct InterruptedSaveRecovery: Hashable, Identifiable, Sendable {
    public let id: InterruptedSaveRecoveryID
    public let relativePath: String
    public let expectedRevision: DocumentFingerprint
    public let candidateRevision: DocumentFingerprint
    public let createdAt: Date
    public let retainedReason: String
    public let sourceState: InterruptedSaveRecoverySourceState

    public init(
        id: InterruptedSaveRecoveryID,
        relativePath: String,
        expectedRevision: DocumentFingerprint,
        candidateRevision: DocumentFingerprint,
        createdAt: Date,
        retainedReason: String,
        sourceState: InterruptedSaveRecoverySourceState
    ) {
        self.id = id
        self.relativePath = relativePath
        self.expectedRevision = expectedRevision
        self.candidateRevision = candidateRevision
        self.createdAt = createdAt
        self.retainedReason = retainedReason
        self.sourceState = sourceState
    }
}

public struct InterruptedSaveRecoveryContent: Hashable, Sendable {
    public let recoveryID: InterruptedSaveRecoveryID
    public let exactSource: String
    public let fingerprint: DocumentFingerprint

    public init(
        recoveryID: InterruptedSaveRecoveryID,
        exactSource: String,
        fingerprint: DocumentFingerprint
    ) {
        self.recoveryID = recoveryID
        self.exactSource = exactSource
        self.fingerprint = fingerprint
    }
}

/// A successful recovery commit after exact canonical source readback.
public struct InterruptedSaveRecoveryRestoreCommit: Sendable {
    public let document: NoteDocument
    public let didReplaceSource: Bool

    public init(
        document: NoteDocument,
        didReplaceSource: Bool
    ) {
        self.document = document
        self.didReplaceSource = didReplaceSource
    }
}

/// One machine-local exact revision deliberately pinned by a researcher
/// Settle action. The source bytes remain outside the Triptych; this value is
/// metadata for recovery and never claims that the revision is true or final.
/// Result of one source replacement proven by exact canonical readback.
public struct SaveResult: Sendable {
    public let document: NoteDocument

    public init(document: NoteDocument) {
        self.document = document
    }
}

/// Result of pinning a Settle revision. `wasCreated` lets the application
/// retract only task-owned recovery state if the portable Settle commit fails.
/// The repository owns the distinction between a proven commit and a write
/// whose canonical result remains unknown. Application must not infer this
/// distinction from an arbitrary error after the transaction has started.
public enum VaultSaveOutcome: Sendable {
    case committed(SaveResult)
    case notWritten(VaultSaveNotWrittenReason)
    case recoveryRequired(InterruptedSaveRecovery)
}

public enum VaultSaveNotWrittenReason: Hashable, Sendable {
    case conflict(DocumentFingerprint)
    case targetIdentityChanged
    case invalidFrontmatter(String)
    case atomicCommitUnsupported(String)
}

public struct NoteMoveResult: Sendable {
    public let document: NoteDocument
    public let previousRelativePath: String
    public let relativePath: String

    public init(
        document: NoteDocument,
        previousRelativePath: String,
        relativePath: String
    ) {
        self.document = document
        self.previousRelativePath = previousRelativePath
        self.relativePath = relativePath
    }
}

public struct FolderRepositoryMoveResult: Sendable {
    public let sourceFolder: VaultRelativeFolderPath
    public let destinationFolder: VaultRelativeFolderPath
    public let documents: [NoteDocument]

    public init(
        sourceFolder: VaultRelativeFolderPath,
        destinationFolder: VaultRelativeFolderPath,
        documents: [NoteDocument]
    ) {
        self.sourceFolder = sourceFolder
        self.destinationFolder = destinationFolder
        self.documents = documents
    }
}

public struct NoteDeletionResult: Sendable {
    public let relativePath: String
    public let fingerprint: DocumentFingerprint

    public init(relativePath: String, fingerprint: DocumentFingerprint) {
        self.relativePath = relativePath
        self.fingerprint = fingerprint
    }
}
