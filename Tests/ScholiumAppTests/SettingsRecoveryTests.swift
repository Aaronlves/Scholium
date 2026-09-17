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

    @Test("Confirmation pins damaged bytes and refuses a different Triptych")
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
        model.replaceSnapshot(WorkspaceSettingsSnapshot(activeTriptychID: UUID()))
        await #expect(throws: WorkspaceSettingsMutationError.triptychChanged) {
            try await model.restoreSettingsDefaults(request)
        }
        #expect(writes == 0)
        #expect(!model.isRestoringSettings)
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
            loadSnapshot: {
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
        #expect(model.hasWritableTriptychSettings)
        #expect(!model.isRefreshing)
        #expect(!model.isRestoringSettings)
        #expect(result.recovery.preservedSettingsURL == copy)
        #expect(result.derivedRefreshWarning == "refresh unavailable")
    }

    @Test("Default readback does not clear an uncertain recovery outcome")
    func defaultReadbackCannotProveRecoveryPreservation() async throws {
        let id = UUID()
        let saved = revision("defaults")
        let model = WorkspaceSettingsModel(
            snapshot: WorkspaceSettingsSnapshot(activeTriptychID: id, portableSettingsState: .corrupted),
            loadSnapshot: { WorkspaceSettingsSnapshot(activeTriptychID: id, settingsRevision: saved) },
            resetSettings: { _, _ in
                throw ScholiumApplicationError.operationCommitUncertain(operation: "settings recovery", reason: "backup not proven")
            })
        await #expect(throws: ScholiumApplicationError.self) {
            try await model.restoreSettingsDefaults(WorkspaceSettingsRecoveryRequest(triptychID: id, revision: self.revision("damaged")))
        }
        #expect(model.requiresSettingsReconciliation(for: id))
        #expect(await model.refresh())
        #expect(model.requiresSettingsReconciliation(for: id))
        #expect(!model.isRestoringSettings)
    }

    @Test("A damaged dismissal entry keeps valid peers and the local repair route")
    func dismissalLedgerIsolatesBadEntry() throws {
        let bytes = Data(#"{"dismissedUntilByItemID":{"good":5000,"bad":"unreadable"}}"#.utf8)
        let recovered = AttentionPreferences.decodeLedger(bytes)
        #expect(recovered.dismissedUntilByItemID == ["good": Date(timeIntervalSinceReferenceDate: 5000)])
        #expect(AttentionPreferences.ledgerNeedsRecovery(bytes))
        #expect(!AttentionPreferences.ledgerNeedsRecovery(Data()))
        #expect(!AttentionPreferences.ledgerNeedsRecovery(AttentionPreferences.encodeLedger(AttentionDismissalLedger())))
        #expect(AttentionPreferences.ledgerNeedsRecovery(Data("broken".utf8)))
    }

    @Test("Read failure does not clear the uncertain-write barrier")
    func failedReadKeepsReconciliationBarrier() async throws {
        let id = UUID()
        struct Failure: Error {}
        let model = WorkspaceSettingsModel(
            snapshot: WorkspaceSettingsSnapshot(activeTriptychID: id, settingsRevision: revision("saved")),
            loadSnapshot: { WorkspaceSettingsSnapshot(activeTriptychID: id, portableSettingsState: .readFailed("unreadable")) },
            loadPortableSettings: { _ in throw Failure() },
            saveSettings: { _, _, _ in
                throw ScholiumApplicationError.operationCommitUncertain(operation: "settings", reason: "unknown")
            })
        await #expect(throws: WorkspaceSettingsMutationError.reconciliationRequired) {
            try await model.saveTriptychSettings(TriptychSettings())
        }
        #expect(await model.refresh())
        #expect(model.requiresSettingsReconciliation(for: id))
        #expect(!model.hasWritableTriptychSettings)
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
