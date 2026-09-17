import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Reminder settings drafts")
struct AttentionSettingsDraftTests {
    @Test("A draft cannot move to another Triptych with identical settings bytes")
    func rejectsDifferentTriptychWithSameRevision() throws {
        let revision = SettingsRevision(fingerprint: DocumentFingerprint(content: "same-settings"))
        let original = WorkspaceSettingsSnapshot(
            activeTriptychID: UUID(), settingsRevision: revision)
        var draft = try #require(AttentionSettingsDraft(snapshot: original))
        draft.dismissalDays = 14
        let other = WorkspaceSettingsSnapshot(
            activeTriptychID: UUID(), settingsRevision: revision)

        #expect(draft.matches(original))
        #expect(!draft.matches(other))
        #expect(draft.triptychID == original.activeTriptychID)
        #expect(draft.dismissalDays == 14)
        #expect(draft.isDirty)
    }

    @Test("A changed saved revision leaves the edited reminder and saved baseline distinct")
    func retainsDraftAcrossSavedRevisionChange() throws {
        let original = WorkspaceSettingsSnapshot(
            activeTriptychID: UUID(),
            triptychSettings: TriptychSettings(attentionDismissalDays: 7),
            settingsRevision: SettingsRevision(fingerprint: DocumentFingerprint(content: "before")))
        var draft = try #require(AttentionSettingsDraft(snapshot: original))
        draft.dismissalDays = 14
        let changed = WorkspaceSettingsSnapshot(
            activeTriptychID: original.activeTriptychID,
            triptychSettings: TriptychSettings(attentionDismissalDays: 30),
            settingsRevision: SettingsRevision(fingerprint: DocumentFingerprint(content: "after")))

        #expect(!draft.matches(changed))
        #expect(draft.savedSettings == original.triptychSettings)
        #expect(draft.dismissalDays == 14)
        #expect(draft.settingsToSave == TriptychSettings(attentionDismissalDays: 14))
        #expect(draft.revision == original.settingsRevision)
    }

    @Test("A repaired default can be saved even when the effective draft was not edited")
    func invalidPersistedTimingRemainsRepairable() throws {
        let id = UUID()
        let old = SettingsRevision(fingerprint: DocumentFingerprint(content: "invalid timing"))
        let invalid = WorkspaceSettingsSnapshot(
            activeTriptychID: id,
            triptychSettings: TriptychSettings(),
            portableSettingsState: .needsReview(old, reason: "invalid timing"))
        let draft = try #require(AttentionSettingsDraft(snapshot: invalid))
        #expect(draft.needsRepair)
        #expect(!draft.isDirty)
        #expect(draft.matches(invalid))
        #expect(draft.settingsToSave == TriptychSettings())
        let repaired = WorkspaceSettingsSnapshot(
            activeTriptychID: id,
            settingsRevision: SettingsRevision(fingerprint: DocumentFingerprint(content: "repaired timing")))
        #expect(try #require(AttentionSettingsDraft(snapshot: repaired)).needsRepair == false)
        #expect(!draft.matches(repaired))
    }

    @Test("Unreadable settings do not initialize or authorize a reminder draft")
    func unavailableSettingsCannotAuthorizeDraft() throws {
        let triptychID = UUID()
        let original = WorkspaceSettingsSnapshot(
            activeTriptychID: triptychID,
            settingsRevision: SettingsRevision(fingerprint: DocumentFingerprint(content: "saved")))
        let draft = try #require(AttentionSettingsDraft(snapshot: original))
        let unreadable = WorkspaceSettingsSnapshot(
            activeTriptychID: triptychID, portableSettingsState: .corrupted)

        #expect(AttentionSettingsDraft(snapshot: unreadable) == nil)
        #expect(!draft.matches(unreadable))
        #expect(!draft.isDirty)
    }
}
