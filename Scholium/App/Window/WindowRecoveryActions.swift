import Foundation
import ScholiumContracts

/// Recovery surfaces: interrupted saves and unfinished Triptych mutations a
/// researcher can inspect, resolve or restore from the window.
extension WindowModel {
    func refreshTransactionRecoveryRecords() async {
        do {
            transactionRecoveryRecords = try await researchController.recoveryRecords()
            transactionRecoveryError = nil
        } catch {
            transactionRecoveryRecords = []
            transactionRecoveryError = "Scholium could not read the durable recovery records. Their file remains unchanged. \(error.localizedDescription)"
        }
        do {
            interruptedSaveRecoveries =
                try await researchController
                .loadInterruptedSaveRecoveries()
            interruptedSaveRecoveryError = nil
        } catch {
            interruptedSaveRecoveries = []
            interruptedSaveRecoveryError = String(
                localized: "Scholium could not verify the interrupted save candidates. Their exact bytes remain unchanged. \(error.localizedDescription)",
                table: "Localizable",
                bundle: .module
            )
        }
    }

    func markTransactionRecoveryResolved(_ id: UUID) async throws {
        try await researchController.resolveRecoveryRecord(id)
        await refreshTransactionRecoveryRecords()
    }

    func revealTransactionRecoveryRecordsInFinder() {
        guard let url = researchController.recoveryRecordsURL else { return }
        workspaceStore.revealInFinder(url)
    }

    func interruptedSaveRecoveryContent(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> InterruptedSaveRecoveryContent {
        try await researchController.interruptedSaveRecoveryContent(recovery)
    }

    func revealInterruptedSaveRecoveryInFinder(
        _ recovery: InterruptedSaveRecovery
    ) async throws {
        let url =
            try await researchController
            .prepareInterruptedSaveRecoveryLocation(recovery)
        workspaceStore.revealInFinder(url)
    }

    @discardableResult
    func restoreInterruptedSaveRecovery(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> InterruptedSaveRecoveryRestoreCommit {
        guard let assignment = workspaceAssignment else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        // A recovery write may target a Note open in any window. Flush first so
        // unsaved researcher text either commits and causes Core's exact
        // revision check to refuse the restore, or remains available on a flush
        // failure. Recovery never writes around a retained dirty buffer.
        try await editorFlushCoordinator.flushAllEditors(in: assignment.id)
        let outcome = try await researchController.restoreInterruptedSaveRecovery(recovery)
        await refreshTransactionRecoveryRecords()
        await refreshWindowProjection()

        var warnings: [String] = []
        if let derived = outcome.derivedRefreshWarning {
            warnings.append(
                String(
                    localized:
                        "The candidate was restored, but Library, Search, or another derived view may be stale. Use Refresh instead of repeating recovery. \(derived)",
                    table: "Localizable",
                    bundle: .module
                ))
        }
        if !warnings.isEmpty {
            reportOperationIssue(warnings.joined(separator: " "), kind: .warning)
        }
        return outcome.committedValue
    }

    func migrateAppOwnedState(
        sourcePath: String,
        destinationPath: String,
        noteID: UUID,
        identityResolved: Bool,
        vaultID: UUID
    ) {
        // Source movement is already durable. Portable identity is projected
        // as resolved only when Application also proved its migration; a
        // post-commit recovery warning must keep identity-dependent actions
        // unavailable without discarding the retained editor session.
        migrateInMemoryPath(
            from: sourcePath,
            to: destinationPath,
            noteID: noteID,
            identityResolved: identityResolved,
            vaultID: vaultID
        )
    }
}
