import Foundation
import ScholiumContracts

/// Captured after editor flush, before a destination or Trash confirmation.
/// Execution advances a revision only from an exact earlier commit receipt.
struct LibraryNoteBatchRequest: Identifiable, Sendable {
    let id: UUID
    let assignmentID: UUID
    let vaultID: UUID
    let targets: [NoteMutationTarget]

    init(id: UUID = UUID(), assignmentID: UUID, vaultID: UUID, targets: [NoteMutationTarget]) {
        self.id = id
        self.assignmentID = assignmentID
        self.vaultID = vaultID
        self.targets = targets
    }
}

enum LibraryNoteBatchOperation: Sendable, Equatable {
    case move(folderRelativePath: String)
    case systemTrash
}

enum LibraryNoteBatchItemStatus: Sendable, Equatable {
    case succeeded
    case failed(String)
    case unattempted
    case cancelled
    case outcomeUnknown(String)
}

struct LibraryNoteBatchItemResult: Identifiable, Sendable {
    var id: UUID { target.stableNoteID }
    let target: NoteMutationTarget
    let destinationRelativePath: String?
    let status: LibraryNoteBatchItemStatus
}

struct LibraryNoteBatchOutcome: Identifiable, Sendable {
    var id: UUID { request.id }
    let request: LibraryNoteBatchRequest
    let operation: LibraryNoteBatchOperation
    let items: [LibraryNoteBatchItemResult]
    let recoveryRequired: Bool
    let warnings: [String]

    var succeededCount: Int { items.filter { $0.status == .succeeded }.count }
    var isComplete: Bool { succeededCount == items.count && !recoveryRequired }
    /// Retry is a new preparation and confirmation, never reuse of stale authority.
    var retryTargets: [NoteMutationTarget] {
        guard !recoveryRequired else { return [] }
        return items.compactMap { item in
            switch item.status {
            case .failed, .unattempted, .cancelled: item.target
            case .succeeded, .outcomeUnknown: nil
            }
        }
    }
}
