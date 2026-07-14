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
            return "Confirm the note identity before changing, reviewing, commenting on, or restoring \(path)."
        }
    }
}

/// Reconciles note paths with stable identity and migrates every app-owned
/// reference before making identity-dependent actions available again.
///
/// Store migrations are deliberately idempotent. `TriptychControlStore` keeps
/// the rebinding pending until the last step, so an interruption or a failed
/// store write leaves the destination readable but blocked and retryable rather
/// than falsely reporting a complete identity migration.
public actor NoteIdentityRecoveryCoordinator {
    private let control: TriptychControlStore
    private let humanReviews: HumanReviewStore
    private let dialogue: DialogueStore
    private let critiques: CritiqueRegistry
    private let windowSessions: WindowSessionSnapshotStore

    public init(
        control: TriptychControlStore,
        humanReviews: HumanReviewStore,
        dialogue: DialogueStore,
        critiques: CritiqueRegistry,
        windowSessions: WindowSessionSnapshotStore
    ) {
        self.control = control
        self.humanReviews = humanReviews
        self.dialogue = dialogue
        self.critiques = critiques
        self.windowSessions = windowSessions
    }

    public func reconcile(
        vaultID: UUID,
        documents: [(relativePath: String, fingerprint: DocumentFingerprint)],
        repository: VaultRepository,
        canvas: NamedCanvasStore?,
        migrateCritiquePaths: Bool
    ) async throws -> NoteIdentityRecoveryState {
        try await validate(repository: repository, vaultID: vaultID)
        let reconciliation = try await control.reconcileIdentityInventory(
            vaultID: vaultID,
            documents: documents
        )
        let failures = await resumePendingRebindings(
            vaultID: vaultID,
            repository: repository,
            canvas: canvas,
            migrateCritiquePaths: migrateCritiquePaths
        )
        return try await state(
            reconciliation: reconciliation,
            vaultID: vaultID,
            failures: failures
        )
    }

    /// Confirms one explicit candidate, or creates a new identity when
    /// `candidateID` is `nil`. The current file fingerprint is rechecked before
    /// the choice is persisted so a stale sheet cannot resolve changed bytes.
    @discardableResult
    public func resolve(
        _ ambiguity: NoteIdentityAmbiguity,
        candidateID: UUID?,
        repository: VaultRepository,
        canvas: NamedCanvasStore?,
        migrateCritiquePaths: Bool
    ) async throws -> NoteIdentityRecord {
        try await validate(repository: repository, vaultID: ambiguity.vaultID)
        let current = try await repository.load(relativePath: ambiguity.relativePath)
        guard current.fingerprint == ambiguity.fingerprint else {
            throw NoteIdentityRecoveryError.staleResolution(
                expected: ambiguity.fingerprint,
                current: current.fingerprint
            )
        }
        let record = try await control.resolveIdentityAmbiguity(
            vaultID: ambiguity.vaultID,
            relativePath: ambiguity.relativePath,
            fingerprint: ambiguity.fingerprint,
            candidateID: candidateID
        )
        guard candidateID != nil else { return record }
        let failures = await resumePendingRebindings(
            vaultID: ambiguity.vaultID,
            repository: repository,
            canvas: canvas,
            migrateCritiquePaths: migrateCritiquePaths
        )
        if let failure = failures.first(where: { $0.rebinding.noteID == record.id }) {
            throw NoteIdentityMigrationError.incomplete(failure.message)
        }
        return record
    }

    /// Retries every interrupted path migration for one vault. Failures remain
    /// persisted in the control store and therefore continue to block the
    /// destination after restart.
    public func resumePendingRebindings(
        vaultID: UUID,
        repository: VaultRepository,
        canvas: NamedCanvasStore?,
        migrateCritiquePaths: Bool
    ) async -> [NoteIdentityMigrationFailure] {
        let pending: [NoteIdentityPendingRebinding]
        do {
            try await validate(repository: repository, vaultID: vaultID)
            pending = try await control.pendingIdentityRebindings(vaultID: vaultID)
        } catch {
            return []
        }
        var failures: [NoteIdentityMigrationFailure] = []
        for rebinding in pending {
            do {
                try await migrate(
                    rebinding,
                    repository: repository,
                    canvas: canvas,
                    migrateCritiquePaths: migrateCritiquePaths
                )
            } catch {
                failures.append(NoteIdentityMigrationFailure(
                    rebinding: rebinding,
                    message: error.localizedDescription
                ))
            }
        }
        return failures
    }

    private func migrate(
        _ rebinding: NoteIdentityPendingRebinding,
        repository: VaultRepository,
        canvas: NamedCanvasStore?,
        migrateCritiquePaths: Bool
    ) async throws {
        try await validate(repository: repository, vaultID: rebinding.vaultID)
        _ = try await repository.load(relativePath: rebinding.relativePath)

        // Every operation below is idempotent. Completion is persisted only
        // after all stores succeed.
        try await repository.migrateVersionHistory(
            from: rebinding.previousRelativePath,
            to: rebinding.relativePath
        )
        _ = try await humanReviews.migratePathIfPresent(
            noteID: rebinding.noteID,
            vaultID: rebinding.vaultID,
            from: rebinding.previousRelativePath,
            to: rebinding.relativePath
        )
        _ = try await dialogue.migratePathIfPresent(
            noteID: rebinding.noteID,
            vaultID: rebinding.vaultID,
            from: rebinding.previousRelativePath,
            to: rebinding.relativePath
        )
        if migrateCritiquePaths {
            _ = try await critiques.movePath(
                noteID: rebinding.noteID,
                from: rebinding.previousRelativePath,
                to: rebinding.relativePath
            )
        }
        try await windowSessions.migratePath(
            vaultID: rebinding.vaultID,
            from: rebinding.previousRelativePath,
            to: rebinding.relativePath
        )
        if let canvas {
            _ = try await canvas.moveNotePath(
                from: rebinding.previousRelativePath,
                to: rebinding.relativePath
            )
        }
        try await control.completeIdentityRebinding(rebinding)
    }

    private func state(
        reconciliation: NoteIdentityReconciliation,
        vaultID: UUID,
        failures: [NoteIdentityMigrationFailure]
    ) async throws -> NoteIdentityRecoveryState {
        let pending = try await control.pendingIdentityRebindings(vaultID: vaultID)
        let blockedIDs = Set(pending.map(\.noteID))
        var completedByID = Dictionary(uniqueKeysWithValues: reconciliation.rebound.map { ($0.id, $0) })
        for rebinding in reconciliation.pendingRebindings where !blockedIDs.contains(rebinding.noteID) {
            completedByID[rebinding.noteID] = NoteIdentityRebinding(
                id: rebinding.noteID,
                previousRelativePath: rebinding.previousRelativePath,
                relativePath: rebinding.relativePath
            )
        }
        return NoteIdentityRecoveryState(
            identities: reconciliation.identities.filter { !blockedIDs.contains($0.value.id) },
            ambiguities: reconciliation.ambiguities,
            pendingRebindings: pending,
            failures: failures,
            completedRebindings: completedByID.values
                .filter { !blockedIDs.contains($0.id) }
                .sorted { $0.relativePath < $1.relativePath }
        )
    }

    private func validate(repository: VaultRepository, vaultID: UUID) async throws {
        let repositoryVaultID = repository.identity.id
        guard repositoryVaultID == vaultID else {
            throw NoteIdentityRecoveryError.vaultMismatch(
                expected: vaultID,
                current: repositoryVaultID
            )
        }
    }
}

public enum NoteIdentityMigrationError: LocalizedError, Sendable {
    case incomplete(String)

    public var errorDescription: String? {
        switch self {
        case .incomplete(let message):
            return "The note identity was confirmed, but its app-owned records have not finished moving. Identity-dependent actions remain unavailable. \(message)"
        }
    }
}
