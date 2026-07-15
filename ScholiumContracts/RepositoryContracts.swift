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
    case versionNotFound(UUID)
    case versionHistoryPathConflict(String)
    case versionHistoryUnavailable(String)

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
        case .versionNotFound(let id): return "Version not found: \(id.uuidString)"
        case .versionHistoryPathConflict(let path):
            return "Note History already belongs to another note at: \(path)"
        case .versionHistoryUnavailable(let reason):
            return "Note History is unavailable, so Scholium did not modify the note. The existing history files remain unchanged. \(reason)"
        }
    }
}

public struct VaultVersion: Codable, Hashable, Identifiable, Sendable {
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

public struct SaveResult: Sendable {
    public let document: NoteDocument
    public let snapshot: VaultVersion

    public init(document: NoteDocument, snapshot: VaultVersion) {
        self.document = document
        self.snapshot = snapshot
    }
}

public struct NoteMoveResult: Sendable {
    public let document: NoteDocument
    public let previousRelativePath: String
    public let relativePath: String
    public let snapshot: VaultVersion

    public init(
        document: NoteDocument,
        previousRelativePath: String,
        relativePath: String,
        snapshot: VaultVersion
    ) {
        self.document = document
        self.previousRelativePath = previousRelativePath
        self.relativePath = relativePath
        self.snapshot = snapshot
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
