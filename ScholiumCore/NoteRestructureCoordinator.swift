import Foundation
import ScholiumContracts

/// Cross-file edits use the existing checked source writers and durable recovery store.
/// A forward record is durable before the first save, including exact rollback candidates.
public actor NoteRestructureCoordinator {
    private let triptychID: UUID
    private let repositories: [UUID: VaultRepository]
    private let recoveryStore: TriptychMutationRecoveryStore
    private let afterWrite: (@Sendable (Int) async throws -> Void)?
    private let beforeRollbackWrite: (@Sendable (Int) async throws -> Void)?

    public init(triptychID: UUID, repositories: [UUID: VaultRepository], recoveryStore: TriptychMutationRecoveryStore) {
        self.triptychID = triptychID
        self.repositories = repositories
        self.recoveryStore = recoveryStore
        self.afterWrite = nil
        self.beforeRollbackWrite = nil
    }

    init(
        triptychID: UUID, repositories: [UUID: VaultRepository], recoveryStore: TriptychMutationRecoveryStore,
        afterWrite: @escaping @Sendable (Int) async throws -> Void, beforeRollbackWrite: (@Sendable (Int) async throws -> Void)? = nil
    ) {
        self.triptychID = triptychID
        self.repositories = repositories
        self.recoveryStore = recoveryStore
        self.afterWrite = afterWrite
        self.beforeRollbackWrite = beforeRollbackWrite
    }

    public func validate(_ preview: NoteRestructurePreview) async throws {
        try await validateInventory(preview, completed: [])
        for edit in preview.edits {
            let repository = try repository(edit.note)
            if let revision = edit.expectedRevision {
                _ = try await repository.preflightExisting(relativePath: edit.note.relativePath, expectedRevision: revision)
            } else {
                try await repository.preflightNewFile(relativePath: edit.note.relativePath)
            }
        }
    }

    public func commit(
        _ preview: NoteRestructurePreview, trashSource: (@Sendable () async throws -> Void)? = nil,
        finishCreation: (@Sendable (NoteDocument) async throws -> Void)? = nil
    ) async throws -> NoteRestructureCommit {
        guard !preview.edits.isEmpty, Set(preview.edits.map(\.note)).count == preview.edits.count,
            preview.edits.allSatisfy({ $0.before != nil || $0.after != nil }),
            preview.edits.filter({ $0.after == nil }).count <= 1,
            preview.edits.allSatisfy({
                $0.after != nil || ($0.note == preview.request.source.documentID && preview.request.operation == .merge && trashSource != nil)
            })
        else { throw NoteRestructureError.unavailable("The reorganization plan is invalid.") }
        try await validate(preview)
        try Task.checkCancellation()
        let record = await recoveryRecord(preview.edits, failure: "Note reorganization is pending.")
        try await recoveryStore.record(record)
        var documents: [VaultQualifiedNoteID: NoteDocument] = [:]
        var completed: Set<VaultQualifiedNoteID> = []
        do {
            for (index, edit) in preview.edits.enumerated() {
                try Task.checkCancellation()
                if edit.note == preview.request.source.documentID {
                    try await validateInventory(preview, completed: completed)
                }
                let repository = try repository(edit.note)
                if let after = edit.after {
                    let document: NoteDocument
                    if let revision = edit.expectedRevision {
                        document = try await repository.save(relativePath: edit.note.relativePath, changeSet: .exactContent(after), expectedRevision: revision)
                            .document
                    } else {
                        document = try await repository.create(relativePath: edit.note.relativePath, content: after)
                    }
                    documents[edit.note] = document
                } else {
                    try await trashSource?()
                }
                completed.insert(edit.note)
                try await afterWrite?(index)
            }
            // Confirm all intended bytes still exist before declaring the coordinated operation complete.
            for edit in preview.edits where edit.after != nil {
                _ = try await repository(edit.note).preflightExisting(relativePath: edit.note.relativePath, expectedRevision: edit.intendedRevision!)
            }
            for edit in preview.edits where edit.after == nil {
                try await repository(edit.note).preflightNewFile(relativePath: edit.note.relativePath)
            }
            try await validateInventory(preview, completed: completed)
        } catch {
            do {
                try await rollback(record)
            } catch {
                let current = await recoveryRecord(preview.edits, id: record.id, failure: error.localizedDescription)
                do { try await recoveryStore.record(current) } catch {
                    throw TriptychTransactionError.recoveryPersistenceFailed(current, error.localizedDescription)
                }
                throw TriptychTransactionError.recoveryRequired(current)
            }
            throw TriptychTransactionError.transactionRolledBack(error.localizedDescription)
        }
        // Portable identity may already have committed when its callback reports uncertainty.
        // Once identity work starts, retain all source and the journal for reconciliation.
        if preview.edits.contains(where: { $0.note == preview.destination && $0.before == nil }),
            let destination = documents[preview.destination]
        {
            do { try await finishCreation?(destination) } catch { throw TriptychTransactionError.recoveryRequired(record) }
        }
        // A journal deletion error must retain committed source, never roll back a completed merge.
        do { try await recoveryStore.resolve(record) } catch { throw TriptychTransactionError.recoveryRequired(record) }
        return NoteRestructureCommit(destination: preview.destination, documents: documents, removedNotes: preview.edits.filter { $0.after == nil }.map(\.note))
    }

    /// Failure rollback restores only files still holding the exact planned revision.
    /// A completed system-Trash step is never reversed or reconstructed as a new file.
    private func rollback(_ record: TriptychMutationRecoveryRecord) async throws {
        guard record.triptychID == triptychID, record.operation == .noteRestructure,
            let edits = record.restructureEdits
        else { throw NoteRestructureError.unavailable("The reorganization recovery evidence is unavailable.") }
        // Preflight the complete rollback before touching any source. External edits stay authoritative.
        for edit in edits {
            let repository = try repository(edit.note)
            let current = try? await repository.load(relativePath: edit.note.relativePath)
            if edit.after == nil {
                guard current?.fingerprint == edit.expectedRevision else {
                    throw NoteRestructureError.unavailable(
                        "The merged source has moved to system Trash or changed. Inspect the retained transaction before resolving it.")
                }
            } else if edit.before == nil, current == nil {
                try await repository.preflightNewFile(relativePath: edit.note.relativePath)
            } else {
                guard let current, current.fingerprint == edit.expectedRevision || current.fingerprint == edit.intendedRevision else {
                    throw NoteRestructureError.unavailable("An affected note changed after reorganization. Recovery will not overwrite that revision.")
                }
            }
        }
        for (index, edit) in edits.reversed().filter({ $0.after != nil }).enumerated() {
            try await beforeRollbackWrite?(index)
            let repository = try repository(edit.note)
            let current = try? await repository.load(relativePath: edit.note.relativePath)
            if let current, current.fingerprint == edit.intendedRevision {
                if let before = edit.before {
                    _ = try await repository.save(relativePath: edit.note.relativePath, changeSet: .exactContent(before), expectedRevision: current.fingerprint)
                } else {
                    try await repository.removeCreatedFileForRollback(relativePath: edit.note.relativePath, createdRevision: current.fingerprint)
                }
            } else if let current, current.fingerprint == edit.expectedRevision {
                continue
            } else if current == nil && edit.before == nil {
                try await repository.preflightNewFile(relativePath: edit.note.relativePath)
            } else {
                throw NoteRestructureError.unavailable("An affected file changed during rollback. Its exact recovery evidence remains available.")
            }
        }
        for edit in edits {
            let repository = try repository(edit.note)
            if let before = edit.expectedRevision {
                _ = try await repository.preflightExisting(relativePath: edit.note.relativePath, expectedRevision: before)
            } else {
                try await repository.preflightNewFile(relativePath: edit.note.relativePath)
            }
        }
        try await recoveryStore.resolve(record)
    }

    private func repository(_ note: VaultQualifiedNoteID) throws -> VaultRepository {
        guard let repository = repositories[note.vaultID] else { throw NoteRestructureError.unavailable("An affected vault is unavailable.") }
        return repository
    }

    private func validateInventory(_ preview: NoteRestructurePreview, completed: Set<VaultQualifiedNoteID>) async throws {
        var expected = preview.observedRevisions
        for edit in preview.edits where completed.contains(edit.note) { expected[edit.note] = edit.intendedRevision }
        var observed: Set<VaultQualifiedNoteID> = []
        for (vaultID, repository) in repositories {
            for path in try await repository.markdownRelativePaths() {
                observed.insert(VaultQualifiedNoteID(vaultID: vaultID, relativePath: path))
            }
        }
        guard observed == Set(expected.keys) else {
            throw NoteRestructureError.unavailable("The workspace note inventory changed during reorganization. Review a fresh plan.")
        }
        for (note, revision) in expected {
            _ = try await repository(note).preflightExisting(relativePath: note.relativePath, expectedRevision: revision)
        }
    }

    private func recoveryRecord(_ edits: [NoteRestructureFileEdit], id: UUID = UUID(), failure: String) async -> TriptychMutationRecoveryRecord {
        var files: [TriptychMutationRecoveryFile] = []
        for edit in edits {
            let observed = try? await repository(edit.note).load(relativePath: edit.note.relativePath).fingerprint
            let state: TriptychMutationRecoveryState =
                observed == edit.expectedRevision
                ? .restored : observed == edit.intendedRevision ? .intendedBytesRemain : observed == nil ? .missing : .externallyChanged
            files.append(
                TriptychMutationRecoveryFile(
                    vaultID: edit.note.vaultID, path: edit.note.relativePath,
                    role: edit.after == nil ? .trashedNote : edit.before == nil ? .createdNote : .savedNote, beforeRevision: edit.expectedRevision,
                    intendedRevision: edit.intendedRevision, observedRevision: observed, state: state,
                    detail: "Exact original and intended source remain in this machine-local reorganization record."))
        }
        return TriptychMutationRecoveryRecord(
            id: id, triptychID: triptychID, operation: .noteRestructure, failure: failure, files: files, restructureEdits: edits)
    }
}
