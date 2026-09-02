import Foundation

public enum AgentChangeOperation: String, Codable, Hashable, Sendable {
    case create
    case update
    case trash
}

public enum AgentChangeRecoveryState: String, Codable, Hashable, Sendable {
    /// Exact intended evidence exists, but the source operation has not yet
    /// been confirmed by its ordinary owner.
    case prepared
    /// The ordinary owner confirmed source and identity readback.
    case confirmed
    /// The source operation may have crossed its durable boundary; reconcile
    /// exact current state before any retry.
    case outcomeUncertain = "outcome_uncertain"
    /// One eligible update was directly undone against its ending fingerprint.
    case undone
}

/// Machine-local evidence for one MCP mutation. It is not a task, Result,
/// Research Record, review state, permission, or researcher acceptance.
public struct AgentChange: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let triptychID: UUID
    public let operation: AgentChangeOperation
    public let noteID: UUID
    public let role: VaultRole
    public let originalRelativePath: String?
    public let finalRelativePath: String?
    public let beforeFingerprint: DocumentFingerprint?
    public let afterFingerprint: DocumentFingerprint?
    public let state: AgentChangeRecoveryState
    public let createdAt: Date
    public let confirmedAt: Date?
    public let undoneAt: Date?

    public init(
        id: UUID,
        triptychID: UUID,
        operation: AgentChangeOperation,
        noteID: UUID,
        role: VaultRole,
        originalRelativePath: String?,
        finalRelativePath: String?,
        beforeFingerprint: DocumentFingerprint?,
        afterFingerprint: DocumentFingerprint?,
        state: AgentChangeRecoveryState,
        createdAt: Date,
        confirmedAt: Date?,
        undoneAt: Date?
    ) {
        self.id = id
        self.triptychID = triptychID
        self.operation = operation
        self.noteID = noteID
        self.role = role
        self.originalRelativePath = originalRelativePath
        self.finalRelativePath = finalRelativePath
        self.beforeFingerprint = beforeFingerprint
        self.afterFingerprint = afterFingerprint
        self.state = state
        self.createdAt = createdAt
        self.confirmedAt = confirmedAt
        self.undoneAt = undoneAt
    }

    public var isDirectUndoEligible: Bool {
        operation == .update && state == .confirmed
            && beforeFingerprint != nil && afterFingerprint != nil
    }
}

public struct AgentChangeUndoResult: Hashable, Sendable {
    public let changeID: UUID
    public let noteID: UUID
    public let restoredFingerprint: DocumentFingerprint

    public init(
        changeID: UUID,
        noteID: UUID,
        restoredFingerprint: DocumentFingerprint
    ) {
        self.changeID = changeID
        self.noteID = noteID
        self.restoredFingerprint = restoredFingerprint
    }
}

public enum AgentNoteUpdateMode: String, Codable, Hashable, Sendable {
    case body
    case source
}

public struct AgentNoteCreationResult: Sendable {
    public let change: AgentChange
    public let noteID: UUID
    public let role: VaultRole
    public let relativePath: String
    public let fingerprint: DocumentFingerprint

    public init(
        change: AgentChange,
        noteID: UUID,
        role: VaultRole,
        relativePath: String,
        fingerprint: DocumentFingerprint
    ) {
        self.change = change
        self.noteID = noteID
        self.role = role
        self.relativePath = relativePath
        self.fingerprint = fingerprint
    }
}

public struct AgentNoteUpdateResult: Sendable {
    public let change: AgentChange
    public let noteID: UUID
    public let relativePath: String
    public let beforeFingerprint: DocumentFingerprint
    public let afterFingerprint: DocumentFingerprint
    public let readbackVerified: Bool

    public init(
        change: AgentChange,
        noteID: UUID,
        relativePath: String,
        beforeFingerprint: DocumentFingerprint,
        afterFingerprint: DocumentFingerprint,
        readbackVerified: Bool
    ) {
        self.change = change
        self.noteID = noteID
        self.relativePath = relativePath
        self.beforeFingerprint = beforeFingerprint
        self.afterFingerprint = afterFingerprint
        self.readbackVerified = readbackVerified
    }
}

public struct AgentNoteTrashResult: Sendable {
    public let change: AgentChange
    public let noteID: UUID
    public let originalRelativePath: String

    public init(
        change: AgentChange,
        noteID: UUID,
        originalRelativePath: String
    ) {
        self.change = change
        self.noteID = noteID
        self.originalRelativePath = originalRelativePath
    }
}

public protocol AgentCollaborationUseCases: Sendable {
    func createNote(_ request: ManagedNoteCreationRequest) async throws
        -> AgentNoteCreationResult
    func updateNote(
        noteID: UUID,
        expectedFingerprint: DocumentFingerprint,
        mode: AgentNoteUpdateMode,
        content: String
    ) async throws -> AgentNoteUpdateResult
    func trashNote(
        noteID: UUID,
        expectedFingerprint: DocumentFingerprint
    ) async throws -> AgentNoteTrashResult
    func agentChanges() async throws -> [AgentChange]
    func agentChange(id: UUID) async throws -> AgentChange
    func undoAgentChange(
        id: UUID,
        expectedAfterFingerprint: DocumentFingerprint
    ) async throws -> AgentChangeUndoResult
}

public enum AgentCollaborationError: LocalizedError, Hashable, Sendable {
    case noteNotFound(UUID)
    case noteAmbiguous(UUID)
    case staleRevision(expected: DocumentFingerprint, current: DocumentFingerprint)
    case pathOccupied(String)
    case invalidRequest(String)
    case changeConfirmationUncertain(UUID)

    public var errorDescription: String? {
        switch self {
        case .noteNotFound: "The stable Note identity is not present."
        case .noteAmbiguous: "The stable Note identity is ambiguous."
        case .staleRevision: "The Note fingerprint is stale."
        case .pathOccupied: "The requested Note path is occupied."
        case .invalidRequest(let reason): reason
        case .changeConfirmationUncertain:
            "The source operation may have committed, but its Agent Change could not be confirmed."
        }
    }
}

public enum AgentChangeError: LocalizedError, Hashable, Sendable {
    case missing(UUID)
    case invalid(UUID)
    case mismatchedBinding(UUID)
    case sourceTooLarge
    case alreadyFinal(UUID)
    case notConfirmed(UUID)
    case undoUnavailable(UUID)
    case unsafeStore(String)

    public var errorDescription: String? {
        switch self {
        case .missing: "The Agent Change is unavailable."
        case .invalid: "The Agent Change is damaged or has an unsupported schema."
        case .mismatchedBinding: "The Agent Change belongs to another mutation."
        case .sourceTooLarge: "The Agent Change exceeds the supported exact-source size."
        case .alreadyFinal: "The Agent Change is already in a final state."
        case .notConfirmed: "The Agent Change is not confirmed."
        case .undoUnavailable: "Direct Undo is unavailable for this Agent Change."
        case .unsafeStore(let reason): "Agent Changes are unavailable: \(reason)"
        }
    }
}
