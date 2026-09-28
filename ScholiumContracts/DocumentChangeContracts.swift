import Foundation

/// The first observed source is never represented by invented empty bytes.
public enum DocumentChangeBaselineState: String, Codable, Hashable, Sendable {
    case known
    case newDocument
    case unavailable
}

public struct DocumentChangeSummary: Hashable, Identifiable, Sendable {
    public var id: UUID { noteID }
    public let noteID: UUID
    public let vaultID: UUID
    public let role: VaultRole
    public let relativePath: String
    public let startingRevision: DocumentFingerprint?
    public let endingRevision: DocumentFingerprint
    public let savedAt: Date?
    public let baselineState: DocumentChangeBaselineState

    public init(
        noteID: UUID, vaultID: UUID, role: VaultRole, relativePath: String,
        startingRevision: DocumentFingerprint?, endingRevision: DocumentFingerprint,
        savedAt: Date?, baselineState: DocumentChangeBaselineState
    ) {
        self.noteID = noteID
        self.vaultID = vaultID
        self.role = role
        self.relativePath = relativePath
        self.startingRevision = startingRevision
        self.endingRevision = endingRevision
        self.savedAt = savedAt
        self.baselineState = baselineState
    }
}

/// Opaque identity for the exact saved source displayed by Changes. Only the
/// machine-local review store can resolve it; it grants no source write.
public struct DocumentChangeCapture: Hashable, Sendable {
    public let id: UUID
    public let noteID: UUID
    public let baselineID: UUID
    public let endingRevision: DocumentFingerprint

    public init(
        id: UUID, noteID: UUID, baselineID: UUID,
        endingRevision: DocumentFingerprint
    ) {
        self.id = id
        self.noteID = noteID
        self.baselineID = baselineID
        self.endingRevision = endingRevision
    }
}

public struct DocumentChangeReview: Sendable {
    public let summary: DocumentChangeSummary
    public let capture: DocumentChangeCapture
    public let comparison: ExactSourceComparison?
    public let startingSource: String?
    public let endingSource: String

    public init(
        summary: DocumentChangeSummary, capture: DocumentChangeCapture,
        comparison: ExactSourceComparison?, startingSource: String?, endingSource: String
    ) {
        self.summary = summary
        self.capture = capture
        self.comparison = comparison
        self.startingSource = startingSource
        self.endingSource = endingSource
    }
}

public struct ReviewedDocumentChange: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let noteID: UUID
    public let vaultID: UUID
    public let role: VaultRole
    public let relativePath: String
    public let startingRevision: DocumentFingerprint?
    public let endingRevision: DocumentFingerprint
    public let reviewedAt: Date
    public let wasNewDocument: Bool

    public init(
        id: UUID, noteID: UUID, vaultID: UUID, role: VaultRole,
        relativePath: String, startingRevision: DocumentFingerprint?,
        endingRevision: DocumentFingerprint, reviewedAt: Date,
        wasNewDocument: Bool
    ) {
        self.id = id
        self.noteID = noteID
        self.vaultID = vaultID
        self.role = role
        self.relativePath = relativePath
        self.startingRevision = startingRevision
        self.endingRevision = endingRevision
        self.reviewedAt = reviewedAt
        self.wasNewDocument = wasNewDocument
    }
}

public struct ReviewedDocumentChangeDetail: Sendable {
    public let batch: ReviewedDocumentChange
    public let comparison: ExactSourceComparison?
    public let startingSource: String?
    public let endingSource: String

    public init(
        batch: ReviewedDocumentChange, comparison: ExactSourceComparison?,
        startingSource: String?, endingSource: String
    ) {
        self.batch = batch
        self.comparison = comparison
        self.startingSource = startingSource
        self.endingSource = endingSource
    }
}

public enum DocumentChangeRetention: String, Codable, CaseIterable, Hashable, Sendable {
    case days30
    case days90
    case days365
    case forever

    public var days: Int? {
        switch self {
        case .days30: 30
        case .days90: 90
        case .days365: 365
        case .forever: nil
        }
    }
}

public struct DocumentChangeHistoryUsage: Hashable, Sendable {
    public let count: Int
    /// Approximate serialized bytes occupied by reviewed batch objects.
    public let byteCount: Int
    /// Remaining machine-local review-record bytes plus exact MCP receipt file
    /// bytes. They can remain after reviewed history is cleared.
    public let protectedByteCount: Int

    public init(count: Int, byteCount: Int, protectedByteCount: Int = 0) {
        self.count = count
        self.byteCount = byteCount
        self.protectedByteCount = protectedByteCount
    }
}

public enum DocumentChangeError: LocalizedError, Sendable {
    case unavailable(String)
    case noteUnavailable(UUID)
    case baselineUnavailable(UUID)
    case noPendingChanges(UUID)
    case staleCapture(UUID)
    case missingCapture(UUID)
    case missingHistory(UUID)
    case invalidRecord(UUID)
    case historyChangedCleanupPending(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "Changes storage is unavailable: \(reason)"
        case .noteUnavailable: "The Note identity or saved source is unavailable."
        case .baselineUnavailable: "The starting source is unavailable; no comparison was invented."
        case .noPendingChanges: "The saved Note has no pending Changes."
        case .staleCapture: "A newer comparison was reviewed. Reopen this Note's Changes."
        case .missingCapture: "The displayed comparison is no longer retained. Reopen it."
        case .missingHistory: "This reviewed batch is unavailable."
        case .invalidRecord: "A Changes record is damaged or has an unsupported schema."
        case .historyChangedCleanupPending(let reason):
            "Reviewed history changed, but receipt cleanup needs retry: \(reason)"
        }
    }
}

public protocol DocumentChangeUseCases: Sendable {
    func pendingChanges() async throws -> [DocumentChangeSummary]
    func changeReview(noteID: UUID) async throws -> DocumentChangeReview
    func markReviewed(capture: DocumentChangeCapture) async throws -> ReviewedDocumentChange
    func reviewedHistory() async throws -> [ReviewedDocumentChange]
    func reviewedChange(id: UUID) async throws -> ReviewedDocumentChangeDetail
    func deleteReviewedHistory(ids: [UUID]) async throws
    func clearReviewedHistory() async throws
    func retention() async throws -> DocumentChangeRetention
    func setRetention(_ retention: DocumentChangeRetention) async throws
    func historyUsage() async throws -> DocumentChangeHistoryUsage
}
