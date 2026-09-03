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

    @Test("Malformed persisted bindings cannot become active commands")
    func malformedPersistenceFailsClosed() {
        let malformed = Data(#"{"overrides":{"showAttention":{"key":"qq","modifiers":8}},"disabled":[]}"#.utf8)
        #expect(ScholiumHotkeyPreferences.binding(for: .showAttention, data: malformed) == nil)
        #expect(
            ScholiumHotkeyPreferences.binding(for: .searchResearch, data: malformed)
                == ScholiumHotkeyCommand.searchResearch.defaultBinding
        )
    }
}
