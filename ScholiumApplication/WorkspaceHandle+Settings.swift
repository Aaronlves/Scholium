import Foundation
import ScholiumContracts
import ScholiumCore

extension WorkspaceHandle {
    func triptychSettings() async throws -> TriptychSettingsSnapshot {
        try requireActive()
        return try await services.controlStore.settings()
    }

    func triptychSettingsLoadState() async throws -> TriptychSettingsLoadState {
        try requireActive()
        return try await services.controlStore.settingsLoadState()
    }

    func triptychSettingsRecoverySnapshot() async throws -> TriptychSettingsRecoverySnapshot {
        try requireActive()
        return try await services.controlStore.settingsRecoverySnapshot()
    }

    func resetTriptychSettingsToDefaultsOutcome(
        expectedRevision: SettingsRevision?
    ) async throws -> WorkspaceMutationOutcome<TriptychSettingsRecoveryResult> {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer { if ownsMutation { endSourceMutation(mutationLease) } }
        let recovery: TriptychSettingsRecoveryResult
        do {
            recovery = try await services.controlStore.resetSettingsToDefaults(
                expectedRevision: expectedRevision
            )
        } catch {
            if let controlError = error as? TriptychControlError,
                case .controlFileCommitUncertain(let reason) = controlError
            {
                // Default values alone cannot prove that the previous bytes
                // were preserved. Only the control store can prove recovery.
                throw ScholiumApplicationError.operationCommitUncertain(
                    operation: "The Triptych settings recovery",
                    reason: reason
                )
            }
            if let cocoaError = error as? CocoaError,
                cocoaError.code == .fileWriteUnknown
            {
                throw ScholiumApplicationError.operationCommitUncertain(
                    operation: "The Triptych settings recovery",
                    reason: cocoaError.localizedDescription
                )
            }
            throw error
        }
        endSourceMutation(mutationLease)
        ownsMutation = false
        do {
            try await refreshAfterCommittedOperation(
                "The Triptych settings recovery",
                publication: .researchState
            )
            return WorkspaceMutationOutcome(committedValue: recovery)
        } catch let error as ScholiumApplicationError
            where error.durableMutationWasCommitted
        {
            return WorkspaceMutationOutcome(
                committedValue: recovery,
                derivedRefreshWarning: error.refreshFailureReason ?? error.localizedDescription
            )
        }
    }

    func saveTriptychSettings(
        _ settings: TriptychSettings,
        expectedRevision: SettingsRevision
    ) async throws -> TriptychSettingsSnapshot {
        try await saveTriptychSettingsOutcome(
            settings,
            expectedRevision: expectedRevision
        ).committedValue
    }

    func saveTriptychSettingsOutcome(
        _ settings: TriptychSettings,
        expectedRevision: SettingsRevision
    ) async throws -> WorkspaceMutationOutcome<TriptychSettingsSnapshot> {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let snapshot: TriptychSettingsSnapshot
        do {
            snapshot = try await services.controlStore.saveSettings(
                settings,
                expectedRevision: expectedRevision
            )
        } catch {
            let uncertaintyReason: String
            if let controlError = error as? TriptychControlError,
                case .controlFileCommitUncertain(let reason) = controlError
            {
                uncertaintyReason = reason
            } else if let cocoaError = error as? CocoaError,
                cocoaError.code == .fileWriteUnknown
            {
                uncertaintyReason = cocoaError.localizedDescription
            } else {
                throw error
            }
            let state: TriptychSettingsLoadState
            do {
                state = try await services.controlStore.settingsLoadState()
            } catch {
                throw ScholiumApplicationError.operationCommitUncertain(
                    operation: "The Triptych settings",
                    reason: "\(uncertaintyReason) Authoritative reread failed: \(error.localizedDescription)"
                )
            }
            if case .current(let reread) = state, reread.settings == settings {
                snapshot = reread
            } else {
                throw ScholiumApplicationError.operationCommitUncertain(
                    operation: "The Triptych settings",
                    reason: uncertaintyReason
                )
            }
        }
        endSourceMutation(mutationLease)
        ownsMutation = false
        do {
            try await refreshAfterCommittedOperation(
                "The Triptych settings",
                publication: .researchState
            )
            return WorkspaceMutationOutcome(committedValue: snapshot)
        } catch let error as ScholiumApplicationError
            where error.durableMutationWasCommitted
        {
            return WorkspaceMutationOutcome(
                committedValue: snapshot,
                derivedRefreshWarning: error.refreshFailureReason
                    ?? error.localizedDescription
            )
        }
    }
}
