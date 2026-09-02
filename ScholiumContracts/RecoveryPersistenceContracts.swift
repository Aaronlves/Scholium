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

/// Durable forward-only evidence for native system-Trash moves followed by
/// cleanup of portable application state that cannot outlive the source.
public struct SystemTrashDeletionPlan: Codable, Hashable, Sendable {
    public let preview: SystemTrashDeletionPreview
    public let sourceReceipts: [SystemTrashDeletionSourceReceipt]

    public init(
        preview: SystemTrashDeletionPreview,
        sourceReceipts: [SystemTrashDeletionSourceReceipt]? = nil
    ) {
        self.preview = preview
        self.sourceReceipts = sourceReceipts ?? preview.sources.map {
            SystemTrashDeletionSourceReceipt(targetID: $0.id, progress: .pending)
        }
    }

    public var id: UUID { preview.id }
    public var affectedNoteIDs: Set<UUID> { preview.affectedNoteIDs }
}
