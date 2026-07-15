import Foundation

public struct NoteIdentityMigrationFailure: Hashable, Identifiable, Sendable {
    public var id: String { rebinding.id }
    public let rebinding: NoteIdentityPendingRebinding
    public let message: String

    public init(rebinding: NoteIdentityPendingRebinding, message: String) {
        self.rebinding = rebinding
        self.message = message
    }
}

public struct NoteIdentityRecoveryState: Sendable {
    /// Only identities whose app-owned path references have converged.
    public let identities: [String: NoteIdentityRecord]
    public let ambiguities: [NoteIdentityAmbiguity]
    public let pendingRebindings: [NoteIdentityPendingRebinding]
    public let failures: [NoteIdentityMigrationFailure]
    public let completedRebindings: [NoteIdentityRebinding]

    public init(
        identities: [String: NoteIdentityRecord],
        ambiguities: [NoteIdentityAmbiguity],
        pendingRebindings: [NoteIdentityPendingRebinding],
        failures: [NoteIdentityMigrationFailure],
        completedRebindings: [NoteIdentityRebinding] = []
    ) {
        self.identities = identities
        self.ambiguities = ambiguities
        self.pendingRebindings = pendingRebindings
        self.failures = failures
        self.completedRebindings = completedRebindings
    }
}

public enum NoteIdentityRecoveryError: LocalizedError, Sendable {
    case vaultMismatch(expected: UUID, current: UUID)
    case staleResolution(expected: DocumentFingerprint, current: DocumentFingerprint)
    case identityUnresolved(String)

    public var errorDescription: String? {
        switch self {
        case .vaultMismatch(let expected, let current):
            return "Identity recovery belongs to vault \(expected.uuidString), not \(current.uuidString)."
        case .staleResolution:
            return "The note changed after the identity choices were shown. Review the refreshed choices before confirming its identity."
        case .identityUnresolved(let path):
            return "Confirm the note identity before changing, reviewing, commenting on, or putting back \(path)."
        }
    }
}

/// Reconciles note paths with stable identity and migrates every app-owned
/// reference before making identity-dependent actions available again.
///
/// Store migrations are deliberately idempotent. `TriptychControlStore` keeps
/// the rebinding pending until the last step, so an interruption or a failed
/// store write leaves the destination readable but blocked and retryable rather

public enum NoteIdentityMigrationError: LocalizedError, Sendable {
    case incomplete(String)

    public var errorDescription: String? {
        switch self {
        case .incomplete(let message):
            return "The note identity was confirmed, but its app-owned records have not finished moving. Identity-dependent actions remain unavailable. \(message)"
        }
    }
}
