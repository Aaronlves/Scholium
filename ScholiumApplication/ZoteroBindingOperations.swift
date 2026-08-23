import ScholiumContracts
import Foundation

/// Narrow delivery-neutral capability for researcher-facing Zotero binding,
/// guarded empty-field fill, and clear. Agent binding writes retain their
/// separate Research authorization path; the concrete Workspace owners remain
/// hidden behind the activated runtime reference.
public actor ZoteroBindingOperations: ZoteroBindingUseCases {
    private let reference: WorkspaceHandleReference

    init(reference: WorkspaceHandleReference) {
        self.reference = reference
    }

    public func zoteroBindings() async throws -> AnalysisZoteroBindingsSnapshot {
        try await reference.requireHandle().zoteroBindingsSnapshot()
    }

    public func prepareZoteroLinkAndFill(
        noteID: UUID,
        library: ZoteroLibraryMetadata,
        itemKey: String
    ) async throws -> ZoteroMetadataFillPlan {
        try await reference.requireHandle().preparePortableZoteroLinkAndFill(
            noteID: noteID,
            library: library,
            itemKey: itemKey
        )
    }

    public func commitZoteroLinkAndFill(
        _ plan: ZoteroMetadataFillPlan
    ) async throws -> ZoteroLinkAndFillResult {
        try await reference.requireHandle().commitPortableZoteroLinkAndFill(plan)
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

    func preparePortableZoteroLinkAndFill(
        noteID: UUID,
        library: ZoteroLibraryMetadata,
        itemKey: String
    ) async throws -> ZoteroMetadataFillPlan {
        try requireActive()
        let (identity, document) = try await currentAnalysisIdentity(noteID)
        let source = try await services.zotero.exactItem(
            library: library,
            itemKey: itemKey,
            expectedServerID: nil
        )
        let bindingSnapshot = try await services.controlStore.zoteroBindings()
        let metadataSnapshot = try await services.controlStore.noteMetadata(
            noteID: identity.id
        )
        return try ZoteroMetadataFillPlanner.plan(
            noteID: noteID,
            sourceRevision: document.fingerprint,
            bindingSnapshot: bindingSnapshot,
            metadataSnapshot: metadataSnapshot,
            source: source
        )
    }

    func commitPortableZoteroLinkAndFill(
        _ plan: ZoteroMetadataFillPlan
    ) async throws -> ZoteroLinkAndFillResult {
        try requireActive()
        let source = try await services.zotero.exactItem(
            library: plan.source.library,
            itemKey: plan.source.item.key,
            expectedServerID: plan.source.serverID
        )
        guard source.item == plan.source.item,
              source.library.identity == plan.source.library.identity else {
            throw ZoteroLinkAndFillError.zoteroItemChanged
        }

        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let (_, document) = try await currentAnalysisIdentity(plan.noteID)
        guard document.fingerprint == plan.sourceRevision else {
            throw ZoteroLinkAndFillError.analysisSourceChanged
        }
        let currentBindings = try await services.controlStore.zoteroBindings()
        guard currentBindings.revision == plan.expectedBindingsRevision,
              currentBindings.binding(for: plan.noteID) == plan.currentBinding else {
            throw TriptychControlError.zoteroBindingsRevisionConflict
        }
        let currentMetadata = try await services.controlStore.noteMetadata(
            noteID: plan.noteID
        )
        guard currentMetadata?.revision == plan.expectedMetadataRevision else {
            throw NoteMetadataError.revisionConflict(plan.noteID)
        }

        let bindingChanged = plan.currentBinding != plan.intendedBinding
        let bindingSnapshot: AnalysisZoteroBindingsSnapshot
        if bindingChanged {
            bindingSnapshot = try await services.controlStore.setZoteroBinding(
                plan.intendedBinding,
                expectedRevision: plan.expectedBindingsRevision
            )
        } else {
            bindingSnapshot = currentBindings
        }

        if !plan.fieldsToFill.isEmpty {
            do {
                _ = try await services.controlStore.saveNoteMetadata(
                    noteID: plan.noteID,
                    fields: plan.resultFields,
                    expectedRevision: plan.expectedMetadataRevision
                )
            } catch {
                endSourceMutation(mutationLease)
                ownsMutation = false
                if bindingChanged {
                    _ = try? await refreshAfterCommittedOperation(
                        "The Zotero link",
                        publication: .explicit
                    )
                    throw ZoteroLinkAndFillError.metadataNotFilledAfterBinding(
                        error.localizedDescription
                    )
                }
                throw error
            }
        }
        guard bindingSnapshot.binding(for: plan.noteID) == plan.intendedBinding else {
            throw TriptychControlError.invalidZoteroBindings
        }
        endSourceMutation(mutationLease)
        ownsMutation = false

        let warning: String?
        do {
            try await refreshAfterCommittedOperation(
                "The Zotero Link and Fill operation",
                publication: .explicit
            )
            warning = nil
        } catch let error as ScholiumApplicationError
            where error.durableMutationWasCommitted {
            warning = error.refreshFailureReason ?? error.localizedDescription
        }
        return ZoteroLinkAndFillResult(
            filledKeys: plan.fieldsToFill.map(\.key),
            retainedConflictKeys: plan.retainedConflicts.map(\.key),
            derivedRefreshWarning: warning
        )
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

    private func currentAnalysisIdentity(
        _ noteID: UUID
    ) async throws -> (NoteIdentityRecord, NoteDocument) {
        guard let identity = try await services.controlStore.identityRecord(id: noteID),
              services.manifest.vaultIDs[.paperAnalysis] == identity.vaultID else {
            throw ZoteroUseCaseError.invalidAnalysisReference
        }
        let document = try await repository(vaultID: identity.vaultID).load(
            relativePath: identity.relativePath
        )
        guard document.fingerprint == identity.fingerprint else {
            throw ZoteroLinkAndFillError.analysisSourceChanged
        }
        return (identity, document)
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
