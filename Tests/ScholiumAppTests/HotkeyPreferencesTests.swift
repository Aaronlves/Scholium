import AppKit
import Foundation
import Testing

@testable import ScholiumApp

@Suite("Hotkey Preferences")
struct HotkeyPreferencesTests {
    @Test("Defaults expose only the approved app-specific shortcuts")
    func defaults() {
        let data = ScholiumHotkeyPreferences.defaultData

        #expect(
            ScholiumHotkeyPreferences.binding(for: .searchResearch, data: data)
                == ScholiumHotkeyBinding(key: "f", modifiers: [.shift, .command])
        )
        #expect(
            ScholiumHotkeyPreferences.binding(for: .toggleLibrary, data: data)
                == ScholiumHotkeyBinding(key: "s", modifiers: [.control, .command])
        )
        #expect(
            ScholiumHotkeyPreferences.binding(for: .insertFootnote, data: data)
                == ScholiumHotkeyBinding(key: "n", modifiers: [.option, .command])
        )
        #expect(
            ScholiumHotkeyPreferences.binding(for: .insertInlineFootnote, data: data)
                == ScholiumHotkeyBinding(
                    key: "n",
                    modifiers: [.option, .shift, .command]
                )
        )
    }

    @Test("One command can be changed, cleared, and restored without changing peers")
    func mutationRoundTrip() {
        let custom = ScholiumHotkeyBinding(
            key: "a",
            modifiers: [.option, .shift, .command]
        )!
        var data = ScholiumHotkeyPreferences.data(
            setting: custom,
            for: .showAttention,
            in: ScholiumHotkeyPreferences.defaultData
        )

        #expect(ScholiumHotkeyPreferences.binding(for: .showAttention, data: data) == custom)
        #expect(
            ScholiumHotkeyPreferences.binding(for: .searchResearch, data: data)
                == ScholiumHotkeyCommand.searchResearch.defaultBinding
        )

        data = ScholiumHotkeyPreferences.data(
            setting: nil,
            for: .searchResearch,
            in: data
        )
        #expect(ScholiumHotkeyPreferences.binding(for: .searchResearch, data: data) == nil)

        data = ScholiumHotkeyPreferences.data(
            setting: ScholiumHotkeyCommand.searchResearch.defaultBinding,
            for: .searchResearch,
            in: data
        )
        #expect(
            ScholiumHotkeyPreferences.binding(for: .searchResearch, data: data)
                == ScholiumHotkeyCommand.searchResearch.defaultBinding
        )
    }

    @Test("Validation rejects missing Command, standard macOS shortcuts, and duplicates")
    func validation() {
        let missingCommand = ScholiumHotkeyBinding(key: "j", modifiers: [.option])!
        #expect(
            ScholiumHotkeyPreferences.validationIssue(
                for: missingCommand,
                command: .showAttention,
                data: Data()
            ) == .commandRequired
        )

        let quit = ScholiumHotkeyBinding(key: "q", modifiers: [.command])!
        #expect(
            ScholiumHotkeyPreferences.validationIssue(
                for: quit,
                command: .showAttention,
                data: Data()
            ) == .systemReserved
        )

        let search = ScholiumHotkeyCommand.searchResearch.defaultBinding!
        #expect(
            ScholiumHotkeyPreferences.validationIssue(
                for: search,
                command: .showAttention,
                data: Data()
            ) == .conflict(.searchResearch)
        )
    }

    @Test("Fixed editor shortcuts stay outside the customizable command set")
    func fixedEditorShortcutsRemainReserved() {
        for key in ["b", "i", "k"] {
            let binding = ScholiumHotkeyBinding(key: key, modifiers: [.command])!
            #expect(
                ScholiumHotkeyPreferences.validationIssue(
                    for: binding,
                    command: .showAttention,
                    data: ScholiumHotkeyPreferences.defaultData
                ) == .systemReserved
            )
        }
    }

    @Test("Malformed persisted bindings cannot become active commands")
    func malformedPersistenceFailsClosed() {
        let malformed = Data(#"{"overrides":{"showAttention":{"key":"qq","modifiers":8}},"disabled":[]}"#.utf8)
        #expect(ScholiumHotkeyPreferences.binding(for: .showAttention, data: malformed) == nil)
        let unknownModifiers = Data(#"{"overrides":{"showAttention":{"key":"j","modifiers":24}},"disabled":[]}"#.utf8)
        #expect(ScholiumHotkeyPreferences.binding(for: .showAttention, data: unknownModifiers) == nil)
        #expect(
            ScholiumHotkeyPreferences.binding(for: .searchResearch, data: malformed)
                == ScholiumHotkeyCommand.searchResearch.defaultBinding
        )
    }
    @Test("Every fixed menu binding is reserved and cannot be remapped")
    func fixedMenuBindings() {
        for command in ScholiumHotkeyCommand.allCases where !command.isCustomizable {
            guard let binding = command.defaultBinding else { continue }
            #expect(ScholiumHotkeyPreferences.validationIssue(
                for: binding, command: .showAttention, data: Data()) != nil)
            #expect(ScholiumHotkeyPreferences.data(setting: nil, for: command, in: Data()).isEmpty)
            #expect(ScholiumHotkeyPreferences.binding(for: command, data: Data()) == binding)
        }
        let defaults = ScholiumHotkeyCommand.allCases.compactMap(\.defaultBinding)
        #expect(Set(defaults).count == defaults.count)
    }

    @Test("Invalid writes and conflicting persisted overrides cannot compete with menus")
    func conflictsFailClosed() {
        let reserved = ScholiumHotkeyCommand.italic.defaultBinding!
        #expect(ScholiumHotkeyPreferences.data(setting: reserved, for: .toggleReviewEdit, in: Data()).isEmpty)
        let saved = Data(#"{"overrides":{"toggleReviewEdit":{"key":"i","modifiers":8}},"disabled":[]}"#.utf8)
        #expect(ScholiumHotkeyPreferences.binding(for: .toggleReviewEdit, data: saved) == nil)
        #expect(ScholiumHotkeyPreferences.binding(for: .italic, data: saved) == reserved)
    }

    @Test("Menu routing follows current custom bindings and yields ordinary typing")
    @MainActor
    func menuEventMatching() throws {
        let suite = "ScholiumShortcutTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func event(_ key: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: key == "j" ? 38 : 15))
        }
        #expect(ScholiumHotkeyPreferences.isMenuShortcut(try event("r", .command), defaults: defaults))
        #expect(!ScholiumHotkeyPreferences.isMenuShortcut(try event("r", []), defaults: defaults))
        let custom = ScholiumHotkeyBinding(key: "j", modifiers: [.command, .option])!
        defaults.set(ScholiumHotkeyPreferences.data(setting: custom, for: .toggleReviewEdit, in: Data()),
                     forKey: ScholiumHotkeyPreferences.defaultsKey)
        #expect(!ScholiumHotkeyPreferences.isMenuShortcut(try event("r", .command), defaults: defaults))
        #expect(ScholiumHotkeyPreferences.isMenuShortcut(try event("j", [.command, .option]), defaults: defaults))
    }

    @Test("Restoring a default never steals a reassigned shortcut")
    func restoringDefaultPreservesOtherCommand() {
        var data = ScholiumHotkeyPreferences.data(setting: nil, for: .toggleReviewEdit, in: Data())
        data = ScholiumHotkeyPreferences.data(setting: ScholiumHotkeyCommand.toggleReviewEdit.defaultBinding,
                                               for: .showAttention, in: data)
        let restored = ScholiumHotkeyPreferences.data(setting: ScholiumHotkeyCommand.toggleReviewEdit.defaultBinding,
                                                       for: .toggleReviewEdit, in: data)
        #expect(restored == data)
        #expect(ScholiumHotkeyPreferences.binding(for: .toggleReviewEdit, data: restored) == nil)
        #expect(ScholiumHotkeyPreferences.binding(for: .showAttention, data: restored)
            == ScholiumHotkeyCommand.toggleReviewEdit.defaultBinding)
    }

}
