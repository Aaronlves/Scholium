import Foundation

public enum SystemTrashDeletionSourceProgress: String, Codable, Hashable, Sendable {
    case pending
    case movedToSystemTrash = "moved_to_system_trash"
    /// The process stopped before Scholium durably received Foundation's
    /// resulting URL. Original-path absence alone is not success evidence.
    case outcomeUnknown = "outcome_unknown"
}

public struct SystemTrashDeletionSourceReceipt: Codable, Hashable, Sendable {
    public let targetID: UUID
    public let progress: SystemTrashDeletionSourceProgress
    public let resultingTrashPath: String?

    public init(
        targetID: UUID,
        progress: SystemTrashDeletionSourceProgress,
        resultingTrashPath: String? = nil
    ) {
        self.targetID = targetID
        self.progress = progress
        self.resultingTrashPath = resultingTrashPath
    }
}

/// Durable forward-only evidence for two deliberately non-atomic boundaries:
/// native system-Trash moves first, then irreversible portable Record cleanup.
public struct SystemTrashDeletionPlan: Codable, Hashable, Sendable {
    public let preview: SystemTrashDeletionPreview
    public let sourceReceipts: [SystemTrashDeletionSourceReceipt]
    public let deletedRecordIDs: [UUID]
    public let removedDiscussionIDs: [UUID]

    public init(
        preview: SystemTrashDeletionPreview,
        sourceReceipts: [SystemTrashDeletionSourceReceipt]? = nil,
        deletedRecordIDs: [UUID] = [],
        removedDiscussionIDs: [UUID] = []
    ) {
        self.preview = preview
        self.sourceReceipts = sourceReceipts ?? preview.sources.map {
            SystemTrashDeletionSourceReceipt(targetID: $0.id, progress: .pending)
        }
        self.deletedRecordIDs = deletedRecordIDs.sorted { $0.uuidString < $1.uuidString }
        self.removedDiscussionIDs = removedDiscussionIDs.sorted { $0.uuidString < $1.uuidString }
    }

    public var id: UUID { preview.id }
    public var affectedNoteIDs: Set<UUID> { preview.affectedNoteIDs }
}
