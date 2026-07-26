import Foundation

public enum VaultRepositoryError: LocalizedError, Sendable {
    case invalidRelativePath(String)
    case outsideVault(String)
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
    case commitUncertain(String)
    case atomicCommitUnsupported(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRelativePath(let path): return "Invalid vault-relative path: \(path)"
        case .outsideVault(let path): return "The path escapes the selected vault: \(path)"
        case .fileDoesNotExist(let path): return "The note no longer exists: \(path)"
        case .fileAlreadyExists(let path): return "A note already exists at: \(path)"
        case .notRegularFile(let path): return "The path is not a regular file: \(path)"
        case .markdownRequired(let path): return "Scholium note operations require a Markdown file: \(path)"
        case .conflict: return "This note changed on disk after editing began. Compare changes or reload before saving."
        case .readbackMismatch:
            return "Scholium could not verify the saved bytes. The previous version remains available for recovery."
        case .invalidFrontmatter(let message): return "Invalid YAML frontmatter: \(message)"
        case .recoveryEntryNotFound(let id): return "Recovery entry not found: \(id.uuidString)"
        case .recoveryPathConflict(let path):
            return "Prewrite recovery already belongs to another note at: \(path)"
        case .recoveryLedgerUnavailable(let reason):
            return "Prewrite recovery is unavailable, so Scholium did not modify the note. Existing recovery evidence remains unchanged. \(reason)"
        case .pathCollision(let existing, let requested):
            return "The requested note path collides with an existing path on this volume: \(requested) (existing: \(existing))"
        case .commitUncertain(let reason):
            return "Scholium could not prove which bytes are canonical after the commit. It preserved recovery evidence and did not report the note as saved. \(reason)"
        case .atomicCommitUnsupported(let reason):
            return "This volume cannot provide Scholium's displaced-byte-preserving commit guarantee. The note remains open and unchanged. \(reason)"
        }
    }
}

public struct PrewriteRecoveryReference: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let relativePath: String
    public let sequence: Int
    public let createdAt: Date
    public let fingerprint: DocumentFingerprint

    public init(
        id: UUID,
        relativePath: String,
        sequence: Int,
        createdAt: Date,
        fingerprint: DocumentFingerprint
    ) {
        self.id = id
        self.relativePath = relativePath
        self.sequence = sequence
        self.createdAt = createdAt
        self.fingerprint = fingerprint
    }
}

/// One machine-local exact revision deliberately pinned by a researcher
/// Settle action. The source bytes remain outside the Triptych; this value is
/// metadata for recovery and never claims that the revision is true or final.
public struct SettledRevisionSnapshot: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let sequence: Int
    public let createdAt: Date
    public let fingerprint: DocumentFingerprint

    public init(
        id: UUID,
        noteID: UUID,
        note: VaultQualifiedNoteID,
        sequence: Int,
        createdAt: Date,
        fingerprint: DocumentFingerprint
    ) {
        self.id = id
        self.noteID = noteID
        self.note = note
        self.sequence = sequence
        self.createdAt = createdAt
        self.fingerprint = fingerprint
    }
}

/// Result of pinning a Settle revision. `wasCreated` lets the application
/// retract only task-owned recovery state if the portable Settle commit fails.
package struct SettledRevisionSnapshotPinOutcome: Hashable, Sendable {
    package let snapshot: SettledRevisionSnapshot
    package let wasCreated: Bool

    package init(snapshot: SettledRevisionSnapshot, wasCreated: Bool) {
        self.snapshot = snapshot
        self.wasCreated = wasCreated
    }
}

public struct SaveResult: Sendable {
    public let document: NoteDocument

    public init(document: NoteDocument) {
        self.document = document
    }
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
