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
            ScholiumHotkeyPreferences.binding(for: .toggleFocusLayout, data: data)
                == ScholiumHotkeyBinding(key: "l", modifiers: [.control, .command])
        )

        #expect(
            ScholiumHotkeyPreferences.binding(for: .searchResearch, data: data)
                == ScholiumHotkeyBinding(key: "f", modifiers: [.shift, .command])
        )
        #expect(ScholiumHotkeyCommand.searchResearch.title == LocalizedStringResource("Advanced Search"))
        #expect(ScholiumHotkeyCommand.searchResearch.menuPath == LocalizedStringResource("View → Advanced Search"))
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
    @Test("A malformed shortcut entry cannot discard unrelated overrides")
    func individualEntryRecovery() {
        let bytes = Data(
            #"{"overrides":{"showAttention":{"key":"j","modifiers":10},"searchResearch":{"key":99,"modifiers":8}},"disabled":["toggleLibrary"]}"#.utf8)
        #expect(ScholiumHotkeyPreferences.needsRecovery(bytes))
        #expect(ScholiumHotkeyPreferences.binding(for: .showAttention, data: bytes) == ScholiumHotkeyBinding(key: "j", modifiers: [.option, .command]))
        #expect(ScholiumHotkeyPreferences.binding(for: .searchResearch, data: bytes) == nil)
        #expect(ScholiumHotkeyPreferences.binding(for: .toggleLibrary, data: bytes) == nil)
        #expect(ScholiumHotkeyPreferences.needsRecovery(Data("invalid".utf8)))
        #expect(!ScholiumHotkeyPreferences.needsRecovery(Data()))
    }

    @Test("Every fixed menu binding is reserved and cannot be remapped")
    func fixedMenuBindings() {
        for command in ScholiumHotkeyCommand.allCases where !command.isCustomizable {
            guard let binding = command.defaultBinding else { continue }
            #expect(
                ScholiumHotkeyPreferences.validationIssue(
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

    @Test("Command-Plus cannot override the fixed text-size command when saved or loaded")
    func shiftedEqualsRemainsReserved() throws {
        let alias = try #require(ScholiumHotkeyBinding(key: "=", modifiers: [.command, .shift]))
        #expect(ScholiumHotkeyPreferences.validationIssue(for: alias, command: .showAttention, data: Data()) == .systemReserved)
        #expect(ScholiumHotkeyPreferences.data(setting: alias, for: .showAttention, in: Data()).isEmpty)

        let persisted = Data(#"{"overrides":{"showAttention":{"key":"=","modifiers":12}},"disabled":[]}"#.utf8)
        #expect(ScholiumHotkeyPreferences.needsRecovery(persisted))
        #expect(ScholiumHotkeyPreferences.binding(for: .showAttention, data: persisted) == nil)
        #expect(ScholiumHotkeyPreferences.command(for: alias, data: persisted) == .increaseTextSize)
    }

    @Test("Custom shifted-equals aliases conflict in either assignment order", arguments: [false, true])
    func customEqualsAliasesConflict(shiftedFirst: Bool) throws {
        let unshifted = try #require(ScholiumHotkeyBinding(key: "=", modifiers: [.option, .command]))
        let shifted = try #require(ScholiumHotkeyBinding(key: "=", modifiers: [.option, .command, .shift]))
        let first = shiftedFirst ? shifted : unshifted
        let second = shiftedFirst ? unshifted : shifted
        let saved = ScholiumHotkeyPreferences.data(setting: first, for: .showAttention, in: Data())
        #expect(ScholiumHotkeyPreferences.binding(for: .showAttention, data: saved) == first)
        #expect(ScholiumHotkeyPreferences.validationIssue(for: second, command: .showSource, data: saved) == .conflict(.showAttention))
        #expect(ScholiumHotkeyPreferences.data(setting: second, for: .showSource, in: saved) == saved)
        #expect(ScholiumHotkeyPreferences.command(for: shifted, data: saved) == .showAttention)
        #expect(ScholiumHotkeyPreferences.command(for: unshifted, data: saved) == (shiftedFirst ? nil : .showAttention))
    }

    @Test("Persisted custom aliases are isolated without disabling unrelated shortcuts")
    func persistedEqualsAliasesFailClosed() throws {
        let persisted = Data(#"{"overrides":{"showAttention":{"key":"=","modifiers":10},"showSource":{"key":"=","modifiers":14}},"disabled":[]}"#.utf8)
        #expect(ScholiumHotkeyPreferences.needsRecovery(persisted))
        #expect(ScholiumHotkeyPreferences.binding(for: .showAttention, data: persisted) == nil)
        #expect(ScholiumHotkeyPreferences.binding(for: .showSource, data: persisted) == nil)
        #expect(ScholiumHotkeyPreferences.binding(for: .searchResearch, data: persisted) == ScholiumHotkeyCommand.searchResearch.defaultBinding)
        let event = try #require(ScholiumHotkeyBinding(key: "=", modifiers: [.option, .command, .shift]))
        #expect(ScholiumHotkeyPreferences.command(for: event, data: persisted) == nil)
    }

    @Test("Menu routing follows current custom bindings and yields ordinary typing")
    @MainActor
    func menuEventMatching() throws {
        let suite = "ScholiumShortcutTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func event(_ key: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero,
                    modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                    characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: key == "j" ? 38 : 15))
        }
        #expect(
            ScholiumHotkeyEventAdapter.command(for: try event("r", .command), defaults: defaults)
                == .toggleReviewEdit
        )
        #expect(
            ScholiumHotkeyEventAdapter.command(for: try event("r", []), defaults: defaults) == nil
        )
        let custom = ScholiumHotkeyBinding(key: "j", modifiers: [.command, .option])!
        defaults.set(
            ScholiumHotkeyPreferences.data(setting: custom, for: .toggleReviewEdit, in: Data()),
            forKey: ScholiumHotkeyPreferences.defaultsKey)
        #expect(
            ScholiumHotkeyEventAdapter.command(for: try event("r", .command), defaults: defaults) == nil
        )
        #expect(
            ScholiumHotkeyEventAdapter.command(
                for: try event("j", [.command, .option]), defaults: defaults
            ) == .toggleReviewEdit
        )
    }

    @Test("Hardware punctuation events reach document text-size shortcuts")
    @MainActor
    func punctuationMenuEventMatching() throws {
        let suite = "ScholiumShortcutPunctuationTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        func event(
            characters: String,
            charactersIgnoringModifiers: String,
            keyCode: UInt16,
            flags: NSEvent.ModifierFlags
        ) throws -> NSEvent {
            try #require(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero,
                    modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                    characters: characters,
                    charactersIgnoringModifiers: charactersIgnoringModifiers,
                    isARepeat: false, keyCode: keyCode
                )
            )
        }

        #expect(
            ScholiumHotkeyEventAdapter.command(
                for: try event(
                    characters: "-", charactersIgnoringModifiers: "-", keyCode: 27,
                    flags: .command
                ),
                defaults: defaults
            ) == .decreaseTextSize
        )
        #expect(
            ScholiumHotkeyEventAdapter.command(
                for: try event(
                    characters: "+", charactersIgnoringModifiers: "=", keyCode: 24,
                    flags: [.command, .shift]
                ),
                defaults: defaults
            ) == .increaseTextSize
        )
    }

    @Test("Restoring a default never steals a reassigned shortcut")
    func restoringDefaultPreservesOtherCommand() {
        var data = ScholiumHotkeyPreferences.data(setting: nil, for: .toggleReviewEdit, in: Data())
        data = ScholiumHotkeyPreferences.data(
            setting: ScholiumHotkeyCommand.toggleReviewEdit.defaultBinding,
            for: .showAttention, in: data)
        let restored = ScholiumHotkeyPreferences.data(
            setting: ScholiumHotkeyCommand.toggleReviewEdit.defaultBinding,
            for: .toggleReviewEdit, in: data)
        #expect(restored == data)
        #expect(ScholiumHotkeyPreferences.binding(for: .toggleReviewEdit, data: restored) == nil)
        #expect(
            ScholiumHotkeyPreferences.binding(for: .showAttention, data: restored)
                == ScholiumHotkeyCommand.toggleReviewEdit.defaultBinding)
    }

}
