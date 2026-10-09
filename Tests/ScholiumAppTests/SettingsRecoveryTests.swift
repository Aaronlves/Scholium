import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Settings recovery lifecycle")
@MainActor
struct SettingsRecoveryTests {
    private func revision(_ value: String) -> SettingsRevision {
        SettingsRevision(fingerprint: DocumentFingerprint(content: value))
    }

    @Test("Confirmation pins damaged bytes and refuses another Triptych with the same revision")
    func confirmationCannotChangeTargets() async throws {
        let id = UUID()
        let observed = revision("damaged")
        var writes = 0
        let model = WorkspaceSettingsModel(
            snapshot: WorkspaceSettingsSnapshot(activeTriptychID: id, portableSettingsState: .corrupted),
            loadSettingsRecovery: { target in
                #expect(target == id)
                return TriptychSettingsRecoverySnapshot(loadState: .corrupted, revision: observed)
            },
            resetSettings: { target, expected in
                writes += 1
                return WorkspaceSettingsRecoveryCommit(
                    triptychID: target,
                    recovery: TriptychSettingsRecoveryResult(
                        snapshot: TriptychSettingsSnapshot(settings: TriptychSettings(), revision: expected!),
                        preservedSettingsURL: nil),
                    derivedRefreshWarning: nil)
            })
        let request = try await model.prepareSettingsRecovery(triptychID: id)
        #expect(request.triptychID == id)
        #expect(request.revision == observed)
        model.replaceSnapshot(WorkspaceSettingsSnapshot(activeTriptychID: UUID(), settingsRevision: observed))
        await #expect(throws: WorkspaceSettingsMutationError.triptychChanged) {
            try await model.restoreSettingsDefaults(request)
        }
        #expect(writes == 0)
        #expect(!model.isRestoringSettings)
    }

    @Test("Recovery forwards the confirmation's frozen revision after a refresh")
    func recoveryUsesFrozenRevision() async throws {
        let id = UUID()
        let observed = revision("damaged")
        let refreshed = revision("changed elsewhere")
        let committed = revision("defaults")
        var requestedRevision: SettingsRevision?
        let model = WorkspaceSettingsModel(
            snapshot: WorkspaceSettingsSnapshot(activeTriptychID: id, portableSettingsState: .corrupted),
            loadSettingsRecovery: { _ in
                TriptychSettingsRecoverySnapshot(loadState: .corrupted, revision: observed)
            },
            resetSettings: { target, expected in
                requestedRevision = expected
                return WorkspaceSettingsRecoveryCommit(
                    triptychID: target,
                    recovery: TriptychSettingsRecoveryResult(
                        snapshot: TriptychSettingsSnapshot(settings: TriptychSettings(), revision: committed),
                        preservedSettingsURL: nil),
                    derivedRefreshWarning: nil)
            })
        let request = try await model.prepareSettingsRecovery(triptychID: id)
        model.replaceSnapshot(WorkspaceSettingsSnapshot(activeTriptychID: id, settingsRevision: refreshed))
        _ = try await model.restoreSettingsDefaults(request)
        #expect(requestedRevision == observed)
        #expect(model.portableSettingsState == .current(committed))
    }

    @Test("Successful recovery invalidates a refresh that captured damaged state")
    func staleRefreshCannotUndoRecovery() async throws {
        let id = UUID()
        let entered = RecoveryTestSignal()
        let release = RecoveryTestSignal()
        let damaged = WorkspaceSettingsSnapshot(activeTriptychID: id, portableSettingsState: .corrupted)
        let committedRevision = revision("defaults")
        let copy = URL(fileURLWithPath: "/fixture/settings.recovery.json")
        let model = WorkspaceSettingsModel(
            snapshot: damaged,
            loadSnapshot: { _ in
                await entered.signal()
                await release.wait()
                return damaged
            },
            resetSettings: { target, expected in
                #expect(target == id)
                #expect(expected == self.revision("damaged"))
                return WorkspaceSettingsRecoveryCommit(
                    triptychID: target,
                    recovery: TriptychSettingsRecoveryResult(
                        snapshot: TriptychSettingsSnapshot(settings: TriptychSettings(), revision: committedRevision),
                        preservedSettingsURL: copy),
                    derivedRefreshWarning: "refresh unavailable")
            })
        let refresh = Task { await model.refresh() }
        await entered.wait()
        let result = try await model.restoreSettingsDefaults(WorkspaceSettingsRecoveryRequest(triptychID: id, revision: revision("damaged")))
        await release.signal()
        #expect(await refresh.value == false)
        #expect(model.portableSettingsState == .current(committedRevision))
        #expect(!model.isRefreshing)
        #expect(!model.isRestoringSettings)
        #expect(result.recovery.preservedSettingsURL == copy)
        #expect(result.derivedRefreshWarning == "refresh unavailable")
    }

    @Test("An uncertain recovery still throws when its reread shows default settings")
    func uncertainRecoveryRemainsAnErrorAfterDefaultReadback() async throws {
        let id = UUID()
        let saved = revision("defaults")
        let model = WorkspaceSettingsModel(
            snapshot: WorkspaceSettingsSnapshot(activeTriptychID: id, portableSettingsState: .corrupted),
            loadSnapshot: { _ in WorkspaceSettingsSnapshot(activeTriptychID: id, settingsRevision: saved) },
            resetSettings: { _, _ in
                throw ScholiumApplicationError.operationCommitUncertain(operation: "settings recovery", reason: "backup not proven")
            })
        do {
            _ = try await model.restoreSettingsDefaults(WorkspaceSettingsRecoveryRequest(triptychID: id, revision: self.revision("damaged")))
            Issue.record("An uncertain restoration must not return a successful commit.")
        } catch let error as ScholiumApplicationError {
            guard case .operationCommitUncertain(let operation, let reason) = error else {
                Issue.record("Unexpected application error: \(error)")
                return
            }
            #expect(operation == "settings recovery")
            #expect(reason == "backup not proven")
        }
        #expect(model.portableSettingsState == .current(saved))
        #expect(!model.isRestoringSettings)
    }

    @Test("An uncertain recovery refreshes failed read state without repeating its mutation")
    func uncertainRecoveryDoesNotRepeatMutation() async throws {
        let id = UUID()
        var resets = 0
        let model = WorkspaceSettingsModel(
            snapshot: WorkspaceSettingsSnapshot(activeTriptychID: id, settingsRevision: revision("saved")),
            loadSnapshot: { _ in WorkspaceSettingsSnapshot(activeTriptychID: id, portableSettingsState: .readFailed("unreadable")) },
            resetSettings: { _, _ in
                resets += 1
                throw ScholiumApplicationError.operationCommitUncertain(operation: "settings recovery", reason: "backup not proven")
            })
        await #expect(throws: ScholiumApplicationError.self) {
            try await model.restoreSettingsDefaults(WorkspaceSettingsRecoveryRequest(triptychID: id, revision: revision("saved")))
        }
        #expect(model.portableSettingsState == .readFailed("unreadable"))
        #expect(!model.isRestoringSettings)
        #expect(resets == 1)
    }

    @Test("An in-flight recovery keeps its original target without replacing another Triptych's settings")
    func inFlightTriptychSwitchPreservesRecoveryTruth() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let original = revision("damaged")
        let current = revision("second Triptych")
        let committed = revision("first defaults")
        let copy = URL(fileURLWithPath: "/fixture/settings.recovery.json")
        let entered = RecoveryTestSignal()
        let release = RecoveryTestSignal()
        let model = WorkspaceSettingsModel(
            snapshot: WorkspaceSettingsSnapshot(activeTriptychID: firstID, portableSettingsState: .corrupted),
            resetSettings: { target, expected in
                #expect(target == firstID)
                #expect(expected == original)
                await entered.signal()
                await release.wait()
                return WorkspaceSettingsRecoveryCommit(
                    triptychID: target,
                    recovery: TriptychSettingsRecoveryResult(
                        snapshot: TriptychSettingsSnapshot(settings: TriptychSettings(), revision: committed),
                        preservedSettingsURL: copy),
                    derivedRefreshWarning: nil)
            })
        let recovery = Task {
            try await model.restoreSettingsDefaults(WorkspaceSettingsRecoveryRequest(triptychID: firstID, revision: original))
        }
        await entered.wait()
        model.replaceSnapshot(WorkspaceSettingsSnapshot(activeTriptychID: secondID, settingsRevision: current))
        await release.signal()
        let result = try await recovery.value
        #expect(result.triptychID == firstID)
        #expect(result.recovery.preservedSettingsURL == copy)
        #expect(model.snapshot.activeTriptychID == secondID)
        #expect(model.portableSettingsState == .current(current))
        #expect(!model.isRestoringSettings)
    }

    @Test("A recovery of the previous scope cannot invalidate an in-flight Triptych selection")
    func recoveryDoesNotCancelPendingSelection() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let original = WorkspaceSettingsSnapshot(
            activeTriptychID: firstID, settingsRevision: revision("first"))
        let selected = WorkspaceSettingsSnapshot(
            activeTriptychID: secondID, settingsRevision: revision("second"))
        let recoveryEntered = RecoveryTestSignal()
        let releaseRecovery = RecoveryTestSignal()
        let selectionEntered = RecoveryTestSignal()
        let releaseSelection = RecoveryTestSignal()
        let model = WorkspaceSettingsModel(
            snapshot: original,
            loadSnapshot: { target in
                #expect(target == secondID)
                await selectionEntered.signal()
                await releaseSelection.wait()
                return selected
            },
            resetSettings: { target, _ in
                await recoveryEntered.signal()
                await releaseRecovery.wait()
                return WorkspaceSettingsRecoveryCommit(
                    triptychID: target,
                    recovery: TriptychSettingsRecoveryResult(
                        snapshot: TriptychSettingsSnapshot(
                            settings: TriptychSettings(), revision: self.revision("restored first")),
                        preservedSettingsURL: nil),
                    derivedRefreshWarning: nil)
            })
        let request = WorkspaceSettingsRecoveryRequest(triptychID: firstID, revision: revision("first"))
        let recovery = Task { try await model.restoreSettingsDefaults(request) }
        await recoveryEntered.wait()
        let selection = Task { await model.activateTriptych(id: secondID) }
        await selectionEntered.wait()

        await releaseRecovery.signal()
        let commit = try await recovery.value
        #expect(commit.triptychID == firstID)
        #expect(model.selectedTriptychID == secondID)
        #expect(model.snapshot == original)
        #expect(model.isRefreshing)
        await releaseSelection.signal()
        await selection.value
        #expect(model.snapshot == selected)
        #expect(!model.isRefreshing)
    }

    @Test("A pending scope selection refuses the previous scope's recovery confirmation")
    func pendingSelectionRefusesPreviousRecovery() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let selectionEntered = RecoveryTestSignal()
        let releaseSelection = RecoveryTestSignal()
        var resets = 0
        let model = WorkspaceSettingsModel(
            snapshot: WorkspaceSettingsSnapshot(activeTriptychID: firstID, settingsRevision: revision("first")),
            loadSnapshot: { target in
                await selectionEntered.signal()
                await releaseSelection.wait()
                return WorkspaceSettingsSnapshot(activeTriptychID: target, settingsRevision: self.revision("second"))
            },
            resetSettings: { _, _ in
                resets += 1
                throw WorkspaceRegistryError.incompleteWorkspace
            })
        let selection = Task { await model.activateTriptych(id: secondID) }
        await selectionEntered.wait()
        await #expect(throws: WorkspaceSettingsMutationError.triptychChanged) {
            try await model.restoreSettingsDefaults(
                WorkspaceSettingsRecoveryRequest(triptychID: firstID, revision: self.revision("first")))
        }
        #expect(resets == 0)
        await releaseSelection.signal()
        await selection.value
    }
}

private actor RecoveryTestSignal {
    private var permits = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }
    func signal() {
        if waiters.isEmpty { permits += 1 } else { waiters.removeFirst().resume() }
    }
}
