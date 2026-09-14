import Foundation
import ScholiumContracts
import ScholiumCore

extension WorkspaceHandle {
    func prepareNoteRestructure(_ request: NoteRestructureRequest) async throws -> NoteRestructurePreview {
        let lease = try await beginSourceMutation()
        defer { endSourceMutation(lease) }
        try await validateRestructureTargets(request)
        let context = try await freshMovePlanningContext()
        let preview = try NoteRestructurePlanner.prepare(request, documents: context.documents, graph: context.graph)
        try await NoteRestructureCoordinator(triptychID: id, repositories: services.repositories, recoveryStore: services.transactionRecoveryStore).validate(
            preview)
        if case .newNote = request.destination {
            guard try await services.controlStore.identityRecord(vaultID: preview.destination.vaultID, relativePath: preview.destination.relativePath) == nil
            else {
                throw DocumentCreationError.portableIdentityAlreadyExists
            }
        }
        return preview
    }

    func commitNoteRestructure(_ preview: NoteRestructurePreview) async throws -> WorkspaceMutationOutcome<NoteRestructureCommit> {
        let lease = try await beginSourceMutation()
        var ownsLease = true
        defer { if ownsLease { endSourceMutation(lease) } }
        try await validateRestructureTargets(preview.request)
        let context = try await freshMovePlanningContext()
        let rechecked = try NoteRestructurePlanner.prepare(preview.request, documents: context.documents, graph: context.graph)
        guard preview == rechecked else {
            throw NoteRestructureError.unavailable(
                "The source, destination, or incoming links changed while the operation was open. Review a fresh reorganization plan.")
        }
        let trashAction: (@Sendable () async throws -> Void)?
        if preview.request.operation == .merge {
            let target = preview.request.source
            let coordinator = try systemTrashCoordinator(vaultID: target.documentID.vaultID)
            let trash = try await coordinator.prepareNote(
                noteID: target.stableNoteID, vaultID: target.documentID.vaultID, relativePath: target.relativePath, expectedRevision: target.revision)
            trashAction = { _ = try await coordinator.moveToSystemTrash(trash) }
        } else {
            trashAction = nil
        }
        let destination = preview.destination
        let controlStore = services.controlStore
        let finishCreation: @Sendable (NoteDocument) async throws -> Void = { document in
            guard
                let identity = try await controlStore.identity(
                    forVaultID: destination.vaultID, relativePath: destination.relativePath, fingerprint: document.fingerprint, preferredID: preview.request.id),
                identity.id == preview.request.id
            else {
                throw NoteIdentityRecoveryError.identityUnresolved(destination.relativePath)
            }
        }
        let coordinator = NoteRestructureCoordinator(triptychID: id, repositories: services.repositories, recoveryStore: services.transactionRecoveryStore)
        let commit: NoteRestructureCommit
        do {
            commit = try await coordinator.commit(preview, trashSource: trashAction, finishCreation: finishCreation)
        } catch {
            endSourceMutation(lease)
            ownsLease = false
            _ = try? await refresh(publication: .explicit, failureDisposition: .staleAfterCommittedMutation(affectedVaultIDs: Set(services.repositories.keys)))
            throw error
        }
        endSourceMutation(lease)
        ownsLease = false
        var warning: String?
        do {
            _ = try await refresh(
                publication: .explicit, failureDisposition: .staleAfterCommittedMutation(affectedVaultIDs: Set(services.repositories.keys)),
                sourceCatalogPreparation: Self.catalogPreparation(
                    upserts: Array(commit.documents.keys), deletions: commit.removedNotes, refreshFolderVaultIDs: [destination.vaultID]))
        } catch { warning = error.localizedDescription }
        return WorkspaceMutationOutcome(committedValue: commit, derivedRefreshWarning: warning)
    }

    private func validateRestructureTargets(_ request: NoteRestructureRequest) async throws {
        guard try await services.transactionRecoveryStore.pending().isEmpty else {
            throw NoteRestructureError.unavailable("Resolve the pending source recovery before reorganizing notes.")
        }
        var targets = [request.source]
        if case .existing(let destination) = request.destination { targets.append(destination) }
        if case .newNote(let path) = request.destination,
            try await services.controlStore.identityRecord(vaultID: request.source.documentID.vaultID, relativePath: path) != nil
        {
            throw DocumentCreationError.portableIdentityAlreadyExists
        }
        for target in targets {
            let identity = try await resolvedIdentity(for: target.documentID, expectedRevision: target.revision)
            guard identity.id == target.stableNoteID else {
                throw NoteRestructureError.unavailable("A note's identity changed. Open its current location before reorganizing it.")
            }
        }
    }
}
