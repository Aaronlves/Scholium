import ScholiumContracts
import Foundation

/// Narrow delivery-neutral capability for portable Analysis-to-Zotero
/// relationships. The concrete Workspace handle and control store remain
/// hidden behind the activated runtime reference.
public actor ZoteroBindingOperations: ZoteroBindingUseCases {
    private let reference: WorkspaceHandleReference

    init(reference: WorkspaceHandleReference) {
        self.reference = reference
    }

    public func zoteroBindings() async throws -> AnalysisZoteroBindingsSnapshot {
        try await reference.requireHandle().zoteroBindingsSnapshot()
    }

    public func setZoteroBinding(
        _ binding: AnalysisZoteroBinding,
        expectedRevision: DocumentFingerprint
    ) async throws -> AnalysisZoteroBindingMutationResult {
        try await reference.requireHandle().setPortableZoteroBinding(
            binding,
            expectedRevision: expectedRevision
        )
    }

    public func clearZoteroBinding(
        noteID: UUID,
        expectedRevision: DocumentFingerprint
    ) async throws -> AnalysisZoteroBindingMutationResult {
        try await reference.requireHandle().clearPortableZoteroBinding(
            noteID: noteID,
            expectedRevision: expectedRevision
        )
    }
}

extension WorkspaceHandle {
    func zoteroBindingsSnapshot() async throws -> AnalysisZoteroBindingsSnapshot {
        try requireActive()
        return try await services.controlStore.zoteroBindings()
    }

    func setPortableZoteroBinding(
        _ binding: AnalysisZoteroBinding,
        expectedRevision: DocumentFingerprint
    ) async throws -> AnalysisZoteroBindingMutationResult {
        try await requireAnalysisIdentity(binding.noteID)
        return try await mutatePortableZoteroBinding("The Zotero binding") {
            try await services.controlStore.setZoteroBinding(
                binding,
                expectedRevision: expectedRevision
            )
        }
    }

    func clearPortableZoteroBinding(
        noteID: UUID,
        expectedRevision: DocumentFingerprint
    ) async throws -> AnalysisZoteroBindingMutationResult {
        try await requireAnalysisIdentity(noteID)
        return try await mutatePortableZoteroBinding("The Zotero binding") {
            try await services.controlStore.clearZoteroBinding(
                for: noteID,
                expectedRevision: expectedRevision
            )
        }
    }

    private func requireAnalysisIdentity(_ noteID: UUID) async throws {
        guard let identity = try await services.controlStore.identityRecord(id: noteID),
              services.manifest.vaultIDs[.paperAnalysis] == identity.vaultID else {
            throw ZoteroUseCaseError.invalidAnalysisReference
        }
    }

    private func mutatePortableZoteroBinding(
        _ operation: String,
        mutation: () async throws -> AnalysisZoteroBindingsSnapshot
    ) async throws -> AnalysisZoteroBindingMutationResult {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let snapshot = try await mutation()
        endSourceMutation(mutationLease)
        ownsMutation = false
        do {
            try await refreshAfterCommittedOperation(
                operation,
                publication: .explicit
            )
            return AnalysisZoteroBindingMutationResult(snapshot: snapshot)
        } catch let error as ScholiumApplicationError
            where error.durableMutationWasCommitted {
            return AnalysisZoteroBindingMutationResult(
                snapshot: snapshot,
                derivedRefreshWarning: error.refreshFailureReason
                    ?? error.localizedDescription
            )
        }
    }
}
