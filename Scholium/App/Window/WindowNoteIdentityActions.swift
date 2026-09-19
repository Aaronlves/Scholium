import Foundation
import ScholiumContracts

/// Note identity recovery: the window's projection of Document's identity
/// state, and the resolution commands a researcher can reach from a document
/// whose identity is ambiguous, pending rebinding, or failed to migrate.
extension WindowModel {
    var noteIdentityByPath: [String: UUID] {
        get { documentController.noteIdentityByPath }
        set { documentController.noteIdentityByPath = newValue }
    }

    var identityAmbiguities: [NoteIdentityAmbiguity] {
        get { documentController.identityAmbiguities }
        set { documentController.identityAmbiguities = newValue }
    }

    var pendingIdentityRebindings: [NoteIdentityPendingRebinding] {
        get { documentController.pendingIdentityRebindings }
        set { documentController.pendingIdentityRebindings = newValue }
    }

    var identityMigrationFailures: [NoteIdentityMigrationFailure] {
        get { documentController.identityMigrationFailures }
        set { documentController.identityMigrationFailures = newValue }
    }

    var isResolvingIdentity: Bool {
        get { documentController.isResolvingIdentity }
        set { documentController.isResolvingIdentity = newValue }
    }

    var identityResolutionError: String? {
        get { documentController.identityResolutionError }
        set { documentController.identityResolutionError = newValue }
    }

    func identityAmbiguity(for path: String) -> NoteIdentityAmbiguity? {
        identityAmbiguities.first { $0.relativePath == path }
    }

    func pendingIdentityRebinding(for path: String) -> NoteIdentityPendingRebinding? {
        pendingIdentityRebindings.first { $0.relativePath == path }
    }

    func identityMigrationFailure(for path: String) -> NoteIdentityMigrationFailure? {
        identityMigrationFailures.first { $0.rebinding.relativePath == path }
    }

    var currentDocumentIdentityAmbiguity: NoteIdentityAmbiguity? {
        guard let path = currentNote?.relativePath else { return nil }
        if let ambiguity = currentDocumentVaultSnapshot?.identityRecovery.ambiguities.first(
            where: { $0.relativePath == path }
        ) {
            return ambiguity
        }
        return identityAmbiguity(for: path)
    }

    var currentDocumentPendingIdentityRebinding: NoteIdentityPendingRebinding? {
        guard let path = currentNote?.relativePath else { return nil }
        if let rebinding = currentDocumentVaultSnapshot?.identityRecovery.pendingRebindings.first(
            where: { $0.relativePath == path }
        ) {
            return rebinding
        }
        return pendingIdentityRebinding(for: path)
    }

    var currentDocumentIdentityMigrationFailure: NoteIdentityMigrationFailure? {
        guard let path = currentNote?.relativePath else { return nil }
        if let failure = currentDocumentVaultSnapshot?.identityRecovery.failures.first(
            where: { $0.rebinding.relativePath == path }
        ) {
            return failure
        }
        return identityMigrationFailure(for: path)
    }

    func requestIdentityResolution(for path: String) {
        let ambiguity =
            currentNote?.relativePath == path
            ? currentDocumentIdentityAmbiguity
            : identityAmbiguity(for: path)
        guard let ambiguity else { return }
        identityResolutionError = nil
        selectedIdentityAmbiguity = ambiguity
    }

    func resolveSelectedIdentity(candidateID: UUID?) async {
        guard let ambiguity = selectedIdentityAmbiguity else { return }
        isResolvingIdentity = true
        identityResolutionError = nil
        defer { isResolvingIdentity = false }
        do {
            let outcome = try await documentController.resolveIdentity(
                ambiguity,
                candidateID: candidateID
            )
            selectedIdentityAmbiguity = nil
            await refreshIdentityState()
            reportCommittedMutationWarnings(outcome)
        } catch {
            identityResolutionError = error.localizedDescription
            try? await refreshLibrarySourceScope()
            if let refreshed = identityAmbiguity(for: ambiguity.relativePath) {
                selectedIdentityAmbiguity = refreshed
            }
        }
    }

    func retryIdentityRecovery() async {
        do {
            try await refreshLibrarySourceScope()
        } catch {
            identityResolutionError = error.localizedDescription
        }
    }

    func refreshIdentityState() async {
        identityRefreshGeneration &+= 1
        let refreshGeneration = identityRefreshGeneration
        guard let vault = currentRegisteredVault else {
            noteIdentityByPath = [:]
            identityAmbiguities = []
            pendingIdentityRebindings = []
            identityMigrationFailures = []
            return
        }
        let sourceScope = noteSourceScope
        guard refreshGeneration == identityRefreshGeneration,
            currentRegisteredVault?.id == vault.id,
            noteSourceScope == sourceScope
        else { return }
        let recovery: NoteIdentityRecoveryState
        let vaultSnapshot: WorkspaceVaultSnapshot
        do {
            guard
                let snapshot = try await documentController.workspaceSnapshot(
                    vaultID: vault.id
                )
            else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            vaultSnapshot = snapshot
            recovery = snapshot.identityRecovery
        } catch {
            guard refreshGeneration == identityRefreshGeneration,
                currentRegisteredVault?.id == vault.id,
                noteSourceScope == sourceScope
            else { return }
            noteIdentityByPath = [:]
            identityResolutionError = error.localizedDescription
            return
        }
        guard refreshGeneration == identityRefreshGeneration,
            currentRegisteredVault?.id == vault.id,
            noteSourceScope == sourceScope
        else { return }
        installIdentityState(
            recovery,
            vault: vault,
            sourceScope: sourceScope,
            refreshGeneration: refreshGeneration,
            visibleSnapshots: vaultSnapshot.documents
        )
    }

    /// Applies identity state carried by the exact accepted Workspace
    /// generation. Publication callers must not ask Application to return the
    /// same snapshot again before Document restoration can continue.
    func refreshIdentityState(from vaultSnapshot: WorkspaceVaultSnapshot) {
        identityRefreshGeneration &+= 1
        let refreshGeneration = identityRefreshGeneration
        guard let vault = currentRegisteredVault,
            vault.id == vaultSnapshot.vault.id
        else { return }
        let sourceScope = noteSourceScope
        installIdentityState(
            vaultSnapshot.identityRecovery,
            vault: vault,
            sourceScope: sourceScope,
            refreshGeneration: refreshGeneration,
            visibleSnapshots: nil
        )
    }

    private func installIdentityState(
        _ recovery: NoteIdentityRecoveryState,
        vault: RegisteredVault,
        sourceScope: LibrarySourceScope,
        refreshGeneration: UInt64,
        visibleSnapshots: [WorkspaceNoteSnapshot]?
    ) {
        guard refreshGeneration == identityRefreshGeneration,
            currentRegisteredVault?.id == vault.id,
            noteSourceScope == sourceScope
        else { return }
        let identities = recovery.identities

        for rebinding in recovery.completedRebindings {
            migrateInMemoryPath(
                from: rebinding.previousRelativePath,
                to: rebinding.relativePath,
                noteID: rebinding.id,
                identityResolved: true,
                vaultID: vault.id
            )
        }
        noteIdentityByPath = identities.mapValues(\.id)
        identityAmbiguities = recovery.ambiguities
        pendingIdentityRebindings = recovery.pendingRebindings
        identityMigrationFailures = recovery.failures
        if let selectedIdentityAmbiguity,
            !identityAmbiguities.contains(where: { $0.id == selectedIdentityAmbiguity.id })
        {
            self.selectedIdentityAmbiguity = nil
        }
        if let visibleSnapshots {
            let snapshots = Dictionary(
                uniqueKeysWithValues: visibleSnapshots.map { ($0.id.relativePath, $0) }
            )
            workspaceProjectionController.refreshVisibleNoteSnapshots(snapshots)
        }
        refreshSelectedDocumentProjection()
    }
}
