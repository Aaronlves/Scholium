import Foundation

public enum SystemTrashDeletionSourceKind: String, Codable, Hashable, Sendable {
    case note
    case folder
}

/// One exact Note identity and revision covered by a researcher-confirmed
/// system-Trash operation. Folder deletion carries its complete descendant
/// Markdown inventory here; the folder itself deliberately has no stable ID.
public struct SystemTrashDeletionNoteTarget: Codable, Hashable, Sendable {
    public let noteID: UUID
    public let relativePath: String
    public let expectedRevision: DocumentFingerprint

    public init(noteID: UUID, relativePath: String, expectedRevision: DocumentFingerprint) {
        self.noteID = noteID
        self.relativePath = relativePath
        self.expectedRevision = expectedRevision
    }
}

/// One filesystem item passed to Foundation's native system-Trash API. A Work
/// and its associated Critique remain separately observable filesystem moves.
public struct SystemTrashDeletionSourceTarget: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let vaultID: UUID
    public let relativePath: String
    public let kind: SystemTrashDeletionSourceKind
    public let notes: [SystemTrashDeletionNoteTarget]
    public let expectedDirectoryManifest: DocumentFingerprint?

    public init(
        id: UUID = UUID(),
        vaultID: UUID,
        relativePath: String,
        kind: SystemTrashDeletionSourceKind,
        notes: [SystemTrashDeletionNoteTarget],
        expectedDirectoryManifest: DocumentFingerprint? = nil
    ) {
        self.id = id
        self.vaultID = vaultID
        self.relativePath = relativePath
        self.kind = kind
        self.notes = notes.sorted { $0.relativePath < $1.relativePath }
        self.expectedDirectoryManifest = expectedDirectoryManifest
    }
}

/// Exact researcher-visible consequence prepared before confirmation. It is
/// immutable authority input, not a claim of cross-store atomicity.
public struct SystemTrashDeletionPreview: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let triptychID: UUID
    public let sources: [SystemTrashDeletionSourceTarget]
    public let preparedAt: Date

    public init(
        id: UUID = UUID(),
        triptychID: UUID,
        sources: [SystemTrashDeletionSourceTarget],
        preparedAt: Date = Date()
    ) {
        self.id = id
        self.triptychID = triptychID
        self.sources = sources
        self.preparedAt = preparedAt
    }

    public var affectedNoteIDs: Set<UUID> {
        Set(sources.flatMap(\.notes).map(\.noteID))
    }
}

public struct SystemTrashDeletionCommit: Hashable, Sendable {
    public let planID: UUID
    public let noteIDs: [UUID]
    public let originalRelativePaths: [String]
    /// Machine-local Finder locations returned by the native Trash operation.
    /// They never enter Markdown or portable research state.
    public let resultingTrashPaths: [String]

    public init(
        planID: UUID,
        noteIDs: [UUID],
        originalRelativePaths: [String],
        resultingTrashPaths: [String]
    ) {
        self.planID = planID
        self.noteIDs = noteIDs.sorted { $0.uuidString < $1.uuidString }
        self.originalRelativePaths = originalRelativePaths.sorted()
        self.resultingTrashPaths = resultingTrashPaths.sorted()
    }
}
