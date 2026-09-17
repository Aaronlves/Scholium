import Foundation
import Testing

@testable import ScholiumApp

@Suite("Settings search routing")
@MainActor
struct SettingsSearchRoutingTests {
    @Test("Every customizable command title and menu path reveals Keyboard Shortcuts")
    func commandSearchRevealsItsEditingLocation() {
        for command in ScholiumHotkeyCommand.customizableCommands {
            for query in [String(localized: command.title), String(localized: command.menuPath)] {
                #expect(SettingsInteractionCategory.matchingSearch(query) == .keyboardShortcuts)
            }
        }
        #expect(SettingsInteractionCategory.matchingSearch("回车") == .chat)
        #expect(SettingsInteractionCategory.matchingSearch("选段操作") == .selectionActions)
        for query in ["Writing Assistance", "AI continuation", "Continuation Model", "autocomplete", "续写模型", "写作辅助", "补全"] {
            #expect(SettingsInteractionCategory.matchingSearch(query) == .writingAssistance)
        }
    }

    @Test("Search changes and native reattachment retain the original child category")
    func searchRestoresBrowsingCategory() {
        var navigation = SettingsSearchNavigation<SettingsInteractionCategory>(category: .chat)
        let commandQuery = String(localized: ScholiumHotkeyCommand.insertFootnote.title)
        navigation.updateSearch(query: commandQuery, matching: SettingsInteractionCategory.matchingSearch(commandQuery))
        #expect(navigation.category == .keyboardShortcuts)
        #expect(navigation.isSearching)

        // Reattaching a retained native pane reconciles the same query again.
        navigation.updateSearch(query: commandQuery, matching: SettingsInteractionCategory.matchingSearch(commandQuery))
        navigation.updateSearch(query: "selection actions", matching: .selectionActions)
        navigation.updateSearch(query: "unmatched", matching: nil)
        #expect(navigation.categoryBeforeSearch == .chat)

        navigation.updateSearch(query: "  ", matching: nil)
        #expect(navigation.category == .chat)
        #expect(!navigation.isSearching)
        #expect(navigation.categoryBeforeSearch == nil)
    }

    @Test("Temporary child choices during search do not replace browsing history")
    func explicitSearchChoiceRemainsTemporary() {
        var navigation = SettingsSearchNavigation<SettingsIntegrationCategory>(category: .zotero)
        navigation.updateSearch(query: "Codex", matching: SettingsIntegrationCategory.matchingSearch("Codex"))
        #expect(navigation.category == .agents)
        #expect(navigation.isSearching)
        navigation.category = .zotero
        navigation.updateSearch(query: "Claude", matching: SettingsIntegrationCategory.matchingSearch("Claude"))
        navigation.updateSearch(query: "", matching: nil)
        #expect(navigation.category == .zotero)
        #expect(!navigation.isSearching)

        // A later search starts from the next ordinary browsing selection.
        navigation.category = .agents
        navigation.updateSearch(query: "Zotero", matching: SettingsIntegrationCategory.matchingSearch("Zotero"))
        navigation.updateSearch(query: "", matching: nil)
        #expect(navigation.category == .agents)
    }
}
