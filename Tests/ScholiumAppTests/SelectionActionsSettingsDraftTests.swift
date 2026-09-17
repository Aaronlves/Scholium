import Foundation
import Testing

@testable import ScholiumApp

@Suite("Selection Actions Settings draft")
@MainActor
struct SelectionActionsSettingsDraftTests {
    private func withPreferences(_ body: (SelectionActionPreferences) throws -> Void) throws {
        let suite = "scholium.selection-draft.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(SelectionActionPreferences(defaults: defaults))
    }

    @Test("External preference changes retain a dirty draft and cannot be overwritten")
    func externalChangeRequiresExplicitReload() throws {
        try withPreferences { preferences in
            let draft = SelectionActionsSettingsDraft(preferences: preferences)
            draft.actions[0].prompt = "Unsaved local instruction"
            var external = preferences.actions
            external[0].prompt = "Saved external instruction"
            try preferences.save(external)
            draft.synchronize(with: preferences.actions)
            #expect(draft.hasExternalChange)
            #expect(draft.actions[0].prompt == "Unsaved local instruction")
            draft.save()
            #expect(preferences.actions == external)
            #expect(draft.hasExternalChange)
            draft.reload(preferences.actions)
            #expect(draft.actions == external)
            #expect(!draft.hasExternalChange)
            draft.actions[0].prompt = "Reviewed replacement instruction"
            draft.save()
            #expect(preferences.actions[0].prompt == "Reviewed replacement instruction")
            #expect(draft.editingActionID == nil)
        }
    }

    @Test("Cancelling one inline action preserves other unapplied changes")
    func cancelIsScopedToEditedAction() throws {
        try withPreferences { preferences in
            let draft = SelectionActionsSettingsDraft(preferences: preferences)
            let saved = preferences.actions
            draft.actions[1].prompt = "Another unapplied instruction"
            draft.beginEditing(draft.actions[0])
            draft.actions[0].prompt = "Cancelled edit"
            draft.cancelEditing()
            #expect(draft.actions[0] == saved[0])
            #expect(draft.actions[1].prompt == "Another unapplied instruction")
            #expect(preferences.actions == saved)
            let addition = SelectionActionDefinition(name: "", prompt: "")
            draft.actions.append(addition)
            draft.beginEditing(addition, isNew: true)
            draft.cancelEditing()
            #expect(!draft.actions.contains { $0.id == addition.id })
            #expect(draft.actions[1].prompt == "Another unapplied instruction")
            #expect(preferences.actions == saved)
        }
    }
}
