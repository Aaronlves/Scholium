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

/// One finished portable Research Record selected by direct Note
/// participation. Its exact portable-byte fingerprint prevents stale deletion.
public struct SystemTrashDeletionRecordParticipant: Codable, Hashable, Identifiable, Sendable {
    public let noteID: UUID
    public let title: String
    public let relativePath: String

    public var id: UUID { noteID }

    public init(noteID: UUID, title: String, relativePath: String) {
        self.noteID = noteID
        self.title = title
        self.relativePath = relativePath
    }
}

public struct SystemTrashDeletionRecordTarget: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let fingerprint: DocumentFingerprint
    public let participantNoteIDs: [UUID]
    public let unaffectedParticipants: [SystemTrashDeletionRecordParticipant]

    public init(
        id: UUID,
        title: String,
        fingerprint: DocumentFingerprint,
        participantNoteIDs: [UUID],
        unaffectedParticipants: [SystemTrashDeletionRecordParticipant]
    ) {
        self.id = id
        self.title = title
        self.fingerprint = fingerprint
        self.participantNoteIDs = participantNoteIDs.sorted { $0.uuidString < $1.uuidString }
        self.unaffectedParticipants = unaffectedParticipants.sorted {
            $0.noteID.uuidString < $1.noteID.uuidString
        }
    }
}

/// Exact researcher-visible consequence prepared before confirmation. It is
/// immutable authority input, not a claim of cross-store atomicity.
public struct SystemTrashDeletionPreview: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let triptychID: UUID
    public let sources: [SystemTrashDeletionSourceTarget]
    public let records: [SystemTrashDeletionRecordTarget]
    public let activeDiscussionIDs: [UUID]
    public let preparedAt: Date

    public init(
        id: UUID = UUID(),
        triptychID: UUID,
        sources: [SystemTrashDeletionSourceTarget],
        records: [SystemTrashDeletionRecordTarget],
        activeDiscussionIDs: [UUID],
        preparedAt: Date = Date()
    ) {
        self.id = id
        self.triptychID = triptychID
        self.sources = sources
        self.records = records.sorted { $0.id.uuidString < $1.id.uuidString }
        self.activeDiscussionIDs = activeDiscussionIDs.sorted { $0.uuidString < $1.uuidString }
        self.preparedAt = preparedAt
    }

    public var affectedNoteIDs: Set<UUID> {
        Set(sources.flatMap(\.notes).map(\.noteID))
    }
}

public struct SystemTrashDeletionCommit: Hashable, Sendable {
    public let planID: UUID
    public let noteIDs: [UUID]
    public let deletedRecordIDs: [UUID]
    public let removedDiscussionIDs: [UUID]
    public let originalRelativePaths: [String]
    /// Machine-local Finder locations returned by the native Trash operation.
    /// They never enter Markdown or a portable Research Record.
    public let resultingTrashPaths: [String]

    public init(
        planID: UUID,
        noteIDs: [UUID],
        deletedRecordIDs: [UUID],
        removedDiscussionIDs: [UUID],
        originalRelativePaths: [String],
        resultingTrashPaths: [String]
    ) {
        self.planID = planID
        self.noteIDs = noteIDs.sorted { $0.uuidString < $1.uuidString }
        self.deletedRecordIDs = deletedRecordIDs.sorted { $0.uuidString < $1.uuidString }
        self.removedDiscussionIDs = removedDiscussionIDs.sorted { $0.uuidString < $1.uuidString }
        self.originalRelativePaths = originalRelativePaths.sorted()
        self.resultingTrashPaths = resultingTrashPaths.sorted()
    }
}

/// One opaque machine-local execution file that System Trash cannot safely
/// scope because it lacks a valid stable authority envelope. The fingerprint
/// binds explicit recovery to the exact bytes the researcher reviewed.
public struct LocalResearchExecutionRecoveryItem: Codable, Hashable, Identifiable, Sendable {
    public let fileName: String
    public let fingerprint: DocumentFingerprint

    public var id: String { fileName }

    public init(fileName: String, fingerprint: DocumentFingerprint) {
        self.fileName = fileName
        self.fingerprint = fingerprint
    }
}

/// Exact recovery preview shown before opaque local execution bytes are moved
/// into Scholium's protected unsupported-data archive.
public struct LocalResearchExecutionRecoveryPreview: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let triptychID: UUID
    /// `nil` means the envelope itself is unreadable, so the preview covers the
    /// complete store-wide opaque set. A nonempty value binds recovery to the
    /// selected Notes whose valid envelopes contain unreadable live payloads.
    public let affectedNoteIDs: [UUID]?
    public let items: [LocalResearchExecutionRecoveryItem]

    public init(
        id: UUID = UUID(),
        triptychID: UUID,
        affectedNoteIDs: Set<UUID>? = nil,
        items: [LocalResearchExecutionRecoveryItem]
    ) {
        self.id = id
        self.triptychID = triptychID
        self.affectedNoteIDs = affectedNoteIDs?.sorted {
            $0.uuidString < $1.uuidString
        }
        self.items = items.sorted { $0.fileName < $1.fileName }
    }
}

public struct LocalResearchExecutionArchiveCommit: Hashable, Sendable {
    public let previewID: UUID
    public let archivedFileNames: [String]

    public init(previewID: UUID, archivedFileNames: [String]) {
        self.previewID = previewID
        self.archivedFileNames = archivedFileNames.sorted()
    }
}

public enum SystemTrashPreparationError: LocalizedError, Sendable {
    case localExecutionRecoveryRequired(LocalResearchExecutionRecoveryPreview)

    public var errorDescription: String? {
        switch self {
        case .localExecutionRecoveryRequired(let preview):
            "System Trash requires recovery for unreadable local Research Action storage (file count: \(preview.items.count))."
        }
    }
}
