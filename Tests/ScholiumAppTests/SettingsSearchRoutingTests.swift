import Foundation
import Testing

@testable import ScholiumApp

@Suite("Settings search routing")
@MainActor
struct SettingsSearchRoutingTests {
    @Test("Every customizable command title and menu path reveals its shortcut editor")
    func commandSearchRevealsItsEditingLocation() {
        for command in ScholiumHotkeyCommand.customizableCommands {
            for query in [String(localized: command.title), String(localized: command.menuPath)] {
                #expect(
                    SettingsSearchTarget.matches(query).contains {
                        $0.destination == .shortcuts && $0.sectionID == command.rawValue
                    })
            }
        }
    }

    @Test("Task searches reveal the sole editing location in either interface language")
    func taskSearchRevealsItsEditingLocation() {
        let cases: [(String, ScholiumSettingsDestination, String)] = [
            ("AI Continuation", .writing, "writing.continuation"),
            ("Body Font", .document, "appearance.reading"),
            ("正文字体", .document, "appearance.reading"),
            ("段落间距", .document, "appearance.body"),
            ("autocomplete", .writing, "writing.continuation"),
            ("续写模型", .writing, "writing.continuation"),
            ("选段操作", .writing, "writing.selection"),
            ("选区操作", .writing, "writing.selection"),
            ("回车", .agents, "agents.behavior"),
            ("Core Protocol", .agents, "agents.protocol"),
            ("工具授权", .agents, "agents.tools"),
            ("Claude", .agents, "agents.external"),
            ("H3 spacing", .document, "appearance.h3"),
            ("H6 间距", .document, "appearance.h6"),
            ("Zotero capability", .zotero, "zotero.chat"),
            ("Triptych name", .workspace, "workspace.name"),
            ("Source font size", .document, "appearance.source"),
            ("Body Bold Font", .document, "appearance.styles"),
            ("正文斜体字体", .document, "appearance.styles"),
            ("Heading Italic Font", .document, "appearance.styles"),
            ("Writing Continuation", .writing, "writing.continuation"),
            ("Return dismissed items after", .notifications, "notifications.timing"),
            ("Server Address", .agents, "agents.tools"),
            ("Scholium Connection Helper", .agents, "agents.paths"),
            ("Copy Claude Setup Command", .agents, "agents.external"),
        ]
        for (query, destination, section) in cases {
            #expect(
                SettingsSearchTarget.matches(query).contains {
                    $0.destination == destination && $0.sectionID == section
                }, "Query: \(query); target: \(section)")
        }
        #expect(SettingsSearchTarget.matches("no-such-setting-qa").isEmpty)
        #expect(SettingsSearchTarget.matches("  ").isEmpty)
    }

    @Test("Every static visible alias is discoverable in English and Chinese")
    func bilingualAliases() {
        for target in SettingsSearchTarget.all {
            for alias in target.aliases {
                for language in ["en", "zh-Hans"] {
                    var resource = alias
                    resource.locale = Locale(identifier: language)
                    let query = String(localized: resource)
                    #expect(SettingsSearchTarget.matches(query).contains { $0.id == target.id })
                }
            }
        }
    }

    @Test("Search changes and native reattachment retain the original Agent task")
    func searchRestoresBrowsingCategory() {
        var navigation = SettingsSearchNavigation<AgentSettingsCategory>(category: .connection)
        navigation.updateSearch(query: "Core Protocol", matching: .capabilities)
        #expect(navigation.category == .capabilities)
        #expect(navigation.isSearching)
        navigation.updateSearch(query: "Core Protocol", matching: .capabilities)
        navigation.updateSearch(query: "Claude", matching: .externalAccess)
        navigation.updateSearch(query: "unmatched", matching: nil)
        #expect(navigation.categoryBeforeSearch == .connection)
        navigation.updateSearch(query: "  ", matching: nil)
        #expect(navigation.category == .connection)
        #expect(!navigation.isSearching)
        #expect(navigation.categoryBeforeSearch == nil)
    }

    @Test("Temporary Agent task choices during search do not replace browsing history")
    func explicitSearchChoiceRemainsTemporary() {
        var navigation = SettingsSearchNavigation<AgentSettingsCategory>(category: .externalAccess)
        navigation.updateSearch(query: "Codex", matching: AgentSettingsCategory.matchingSearch("Codex"))
        #expect(navigation.category == .connection)
        navigation.category = .capabilities
        navigation.updateSearch(query: "Skills", matching: AgentSettingsCategory.matchingSearch("Skills"))
        navigation.updateSearch(query: "", matching: nil)
        #expect(navigation.category == .externalAccess)
        #expect(!navigation.isSearching)
        navigation.category = .capabilities
        navigation.updateSearch(query: "Claude", matching: AgentSettingsCategory.matchingSearch("Claude"))
        navigation.updateSearch(query: "", matching: nil)
        #expect(navigation.category == .capabilities)
    }
}
