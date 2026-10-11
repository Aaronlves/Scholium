import Foundation

public enum SystemTrashDeletionSourceProgress: String, Codable, Hashable, Sendable {
    case pending
    case movedToSystemTrash = "moved_to_system_trash"
    /// Durably written before native dispatch and retained until exact native
    /// completion is proved. Source presence or absence cannot authorize replay.
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

/// Durable forward-only evidence for native system-Trash requests. Unsupported
/// staging-era records remain unreadable and cannot authorize a native request.
public struct SystemTrashDeletionPlan: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let preview: SystemTrashDeletionPreview
    public let sourceReceipts: [SystemTrashDeletionSourceReceipt]

    public init(
        preview: SystemTrashDeletionPreview,
        sourceReceipts: [SystemTrashDeletionSourceReceipt]? = nil
    ) {
        schemaVersion = 2
        self.preview = preview
        self.sourceReceipts =
            sourceReceipts
            ?? preview.sources.map {
                SystemTrashDeletionSourceReceipt(targetID: $0.id, progress: .pending)
            }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, preview, sourceReceipts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == 2 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: container,
                debugDescription: "Unsupported native Trash request-receipt format.")
        }
        schemaVersion = version
        preview = try container.decode(SystemTrashDeletionPreview.self, forKey: .preview)
        sourceReceipts = try container.decode([SystemTrashDeletionSourceReceipt].self, forKey: .sourceReceipts)
    }

    public var id: UUID { preview.id }
    public var affectedNoteIDs: Set<UUID> { preview.affectedNoteIDs }
}
