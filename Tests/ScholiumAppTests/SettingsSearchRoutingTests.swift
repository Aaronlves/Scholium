import AppKit
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Settings search routing")
@MainActor
struct SettingsSearchRoutingTests {
    @Test("Search retains native editable plain-text field-editor behavior")
    func nativeSearchInput() throws {
        _ = NSApplication.shared
        let parent = ScholiumSettingsSearchField(text: .constant(""), reveal: { _ in })
        let coordinator = parent.makeCoordinator()
        let field = ScholiumSettingsSearchField.makeSearchField(coordinator: coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = field
        defer {
            ScholiumSettingsSearchField.dismantleNSView(field, coordinator: coordinator)
            window.contentView = nil
            window.close()
        }
        #expect(field.isEditable && field.isSelectable)
        #expect(field.isBezeled && field.bezelStyle == .roundedBezel)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        #expect(editor.isFieldEditor && !editor.isRichText)
        #expect(editor.delegate === field)
    }

    @Test("Native results require a choice, reset it when the query changes, and expose accessible activation")
    func nativeResultSelectionAndActivation() throws {
        let results = SettingsSearchResultsController()
        let targets = Array(SettingsSearchTarget.all.prefix(3))
        var chosen: [String] = []
        results.choose = { chosen.append($0.id) }
        results.update(targets)
        results.activateSelection()
        #expect(chosen.isEmpty)
        results.moveSelection(by: 1)
        #expect(results.selectedTarget?.id == targets[0].id)
        results.moveSelection(by: 100)
        #expect(results.selectedTarget?.id == targets[2].id)
        #expect(results.table.accessibilityPerformConfirm())
        #expect(chosen == [targets[2].id])

        results.update([targets[1]])
        #expect(results.selectedTarget == nil)
        let cell = try #require(results.tableView(results.table, viewFor: nil, row: 0))
        #expect(cell.accessibilityPerformPress())
        #expect(chosen == [targets[2].id, targets[1].id])
        results.update([targets[0]])
        #expect(!cell.accessibilityPerformPress())
        #expect(results.selectedTarget == nil)
        results.update([])
        results.moveSelection(by: 1)
        results.activateSelection()
        #expect(results.selectedTarget == nil)
        #expect(!results.table.accessibilityPerformConfirm())
        let empty = try #require(results.tableView(results.table, viewFor: nil, row: 0))
        #expect(empty.accessibilityRole() == .staticText)
        #expect(!empty.accessibilityPerformPress())
        #expect(chosen.count == 2)
    }

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
            ("续写模型", .writing, "writing.model"),
            ("选段操作", .writing, "writing.selection"),
            ("选区操作", .writing, "writing.selection"),
            ("回车", .agents, "agents.behavior"),
            ("Core Protocol", .agents, "agents.protocol"),
            ("工具授权", .agents, "agents.tools"),
            ("Claude", .agents, "agents.external"),
            ("H3 spacing", .document, "appearance.h3"),
            ("H6 间距", .document, "appearance.h6"),
            ("Zotero connection", .zotero, "zotero.chat"),
            ("Triptych name", .workspace, "workspace.name"),
            ("Source font size", .document, "appearance.source"),
            ("Reading line width", .document, "appearance.reading"),
            ("Body Bold Font", .document, "appearance.styles"),
            ("正文斜体字体", .document, "appearance.styles"),
            ("Heading Italic Font", .document, "appearance.styles"),
            ("Writing Continuation", .writing, "writing.continuation"),
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
        navigation.updateQuery("Core Protocol")
        #expect(navigation.category == .connection)
        navigation.reveal(.capabilities)
        #expect(navigation.category == .capabilities)
        #expect(navigation.isSearching)
        navigation.updateQuery("Core Protocol")
        navigation.updateQuery("Claude")
        #expect(navigation.category == .capabilities)
        navigation.reveal(.externalAccess)
        navigation.updateQuery("unmatched")
        #expect(navigation.category == .externalAccess)
        #expect(navigation.categoryBeforeSearch == .connection)
        navigation.updateQuery("  ")
        #expect(navigation.category == .connection)
        #expect(!navigation.isSearching)
        #expect(navigation.categoryBeforeSearch == nil)
    }

    @Test("Temporary Agent task choices during search do not replace browsing history")
    func explicitSearchChoiceRemainsTemporary() {
        var navigation = SettingsSearchNavigation<AgentSettingsCategory>(category: .externalAccess)
        navigation.updateQuery("Codex")
        #expect(navigation.category == .externalAccess)
        navigation.reveal(.connection)
        #expect(navigation.category == .connection)
        navigation.category = .capabilities
        navigation.updateQuery("Skills")
        navigation.updateQuery("")
        #expect(navigation.category == .externalAccess)
        #expect(!navigation.isSearching)
        navigation.category = .capabilities
        navigation.updateQuery("Claude")
        navigation.updateQuery("")
        #expect(navigation.category == .capabilities)
    }
}
