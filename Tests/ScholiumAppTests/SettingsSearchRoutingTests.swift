import AppKit
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Settings search routing")
@MainActor
struct SettingsSearchRoutingTests {
    @Test("Repeated Chat links reveal its sole setting once; ordinary navigation clears stale section requests")
    func chatSectionRequests() {
        let fixture = ChatSidebarPreferenceFixture()
        defer { fixture.cleanup() }
        let defaults = fixture.defaults
        SettingsNavigationRequest.reveal(.agentChatSidebar, defaults: defaults)
        let revision = defaults.string(forKey: "scholium.settings.navigationRevision")
        #expect(defaults.string(forKey: "scholium.settings.selectedPane") == ScholiumSettingsDestination.agents.rawValue)
        #expect(defaults.string(forKey: "scholium.settings.agentCategory") == AgentSettingsCategory.connection.rawValue)
        #expect(SettingsNavigationRequest.takeRequestedSection(for: .agents, defaults: defaults) == .agentChatSidebar)
        #expect(defaults.object(forKey: SettingsNavigationRequest.requestedSectionKey) == nil)
        #expect(SettingsNavigationRequest.takeRequestedSection(for: .agents, defaults: defaults) == nil)
        SettingsNavigationRequest.reveal(.agentChatSidebar, defaults: defaults)
        #expect(defaults.string(forKey: "scholium.settings.navigationRevision") != revision)
        #expect(SettingsNavigationRequest.takeRequestedSection(for: .agents, defaults: defaults) == .agentChatSidebar)
        SettingsNavigationRequest.reveal(.agentChatSidebar, defaults: defaults)
        SettingsNavigationRequest.select(.document, defaults: defaults)
        #expect(SettingsNavigationRequest.takeRequestedSection(for: .document, defaults: defaults) == nil)
        SettingsNavigationRequest.reveal(.agentChatSidebar, defaults: defaults)
        #expect(SettingsNavigationRequest.takeRequestedSection(for: .document, defaults: defaults) == nil)
        #expect(SettingsNavigationRequest.takeRequestedSection(for: .agents, defaults: defaults) == nil)
        #expect(!fixture.preferences.isEnabled && defaults.object(forKey: ChatSidebarPreferences.enabledKey) == nil)
    }

    @Test("Every indexed editing location survives contextual navigation with the same pane, segment and anchor")
    func indexedSectionsRoundTripThroughNavigation() {
        let fixture = ChatSidebarPreferenceFixture()
        defer { fixture.cleanup() }
        let defaults = fixture.defaults
        let targets = SettingsSearchTarget.all
        #expect(Set(targets.map(\.id)).count == targets.count, "Search-result identities must be unique")
        for sameID in Dictionary(grouping: targets.map(\.section), by: \.id).values {
            #expect(Set(sameID).count == 1, "An anchor cannot describe two different routes")
        }

        for section in Set(targets.map(\.section)) {
            defaults.removeObject(forKey: "scholium.settings.agentCategory")
            SettingsNavigationRequest.reveal(section, defaults: defaults)
            #expect(defaults.string(forKey: "scholium.settings.selectedPane") == section.destination.rawValue)
            #expect(defaults.string(forKey: SettingsNavigationRequest.requestedSectionKey) == section.id)
            #expect(defaults.string(forKey: "scholium.settings.agentCategory") == section.agentCategory?.rawValue)
            #expect((section.agentCategory != nil) == (section.destination == .agents))
            #expect(SettingsNavigationRequest.takeRequestedSection(for: section.destination, defaults: defaults) == section)
            #expect(SettingsNavigationRequest.takeRequestedSection(for: section.destination, defaults: defaults) == nil)
        }

        defaults.set("unknown-settings-anchor", forKey: SettingsNavigationRequest.requestedSectionKey)
        #expect(SettingsNavigationRequest.takeRequestedSection(for: .agents, defaults: defaults) == nil)
        #expect(defaults.object(forKey: SettingsNavigationRequest.requestedSectionKey) == nil)
    }

    @Test("Agent search and contextual links choose the same task and preserve the named control identity")
    func agentRoutesShareSegmentAndAnchor() throws {
        let cases: [(String, AgentSettingsCategory, SettingsSection)] = [
            ("Chat Sidebar", .connection, .agentChatSidebar),
            ("Chat state access", .connection, .agentContextState(.chat)),
            ("Core Protocol", .capabilities, .agentCoreProtocol),
            ("Skills", .capabilities, .agentSkills),
            ("Server Address", .capabilities, .agentTools),
            ("Claude", .externalAccess, .agentExternal),
            ("MCP working text", .externalAccess, .agentContextWorkingText(.external)),
        ]
        let fixture = ChatSidebarPreferenceFixture()
        defer { fixture.cleanup() }

        for (query, expectedCategory, expectedSection) in cases {
            let target = try #require(SettingsSearchTarget.matches(query).first { $0.section == expectedSection })
            let category = try #require(target.section.agentCategory)
            #expect(category == expectedCategory)
            var navigation = SettingsSearchNavigation<AgentSettingsCategory>(category: .connection)
            navigation.updateQuery(query)
            navigation.reveal(category)
            #expect(navigation.category == expectedCategory)
            navigation.updateQuery("")
            #expect(navigation.category == .connection)

            SettingsNavigationRequest.reveal(target.section, defaults: fixture.defaults)
            #expect(fixture.defaults.string(forKey: "scholium.settings.agentCategory") == expectedCategory.rawValue)
            #expect(SettingsNavigationRequest.takeRequestedSection(for: .agents, defaults: fixture.defaults) == expectedSection)
        }
    }

    @Test("Search retains native editable plain-text field-editor behavior")
    func nativeSearchInput() throws {
        _ = NSApplication.shared
        let parent = ScholiumSettingsSearchField(text: .constant(""), reveal: { _ in })
        let coordinator = parent.makeCoordinator()
        let field = ScholiumSettingsSearchField.makeSearchField(coordinator: coordinator)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
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
                        $0.destination == .shortcuts && $0.section == .shortcut(command)
                    })
            }
        }
    }

    @Test("Task searches reveal the sole editing location in either interface language")
    func taskSearchRevealsItsEditingLocation() {
        let cases: [(String, ScholiumSettingsDestination, SettingsSection)] = [
            ("AI Continuation", .writing, .writingContinuation),
            ("Body Font", .document, .appearanceReading),
            ("正文字体", .document, .appearanceReading),
            ("段落间距", .document, .appearanceBody),
            ("autocomplete", .writing, .writingContinuation),
            ("续写模型", .writing, .writingModel),
            ("选段操作", .writing, .writingSelection),
            ("选区操作", .writing, .writingSelection),
            ("回车", .agents, .agentBehavior),
            ("Show Chat in Sidebar", .agents, .agentChatSidebar),
            ("Chat Sidebar", .agents, .agentChatSidebar),
            ("关闭聊天", .agents, .agentChatSidebar),
            ("Core Protocol", .agents, .agentCoreProtocol),
            ("工具授权", .agents, .agentTools),
            ("Claude", .agents, .agentExternal),
            ("H3 spacing", .document, .appearanceHeading(.h3)),
            ("H6 间距", .document, .appearanceHeading(.h6)),
            ("Zotero connection", .zotero, .zoteroChat),
            ("Triptych name", .workspace, .workspaceName),
            ("Source font size", .document, .appearanceSource),
            ("Reading line width", .document, .appearanceReading),
            ("Body Bold Font", .document, .appearanceStyles),
            ("正文斜体字体", .document, .appearanceStyles),
            ("Heading Italic Font", .document, .appearanceStyles),
            ("Writing Continuation", .writing, .writingContinuation),
            ("Server Address", .agents, .agentTools),
            ("Scholium Connection Helper", .agents, .agentPaths),
            ("Copy Claude Setup Command", .agents, .agentExternal),
            ("Chat state access", .agents, .agentContextState(.chat)),
            ("聊天状态访问", .agents, .agentContextState(.chat)),
            ("Chat working text", .agents, .agentContextWorkingText(.chat)),
            ("聊天工作文本", .agents, .agentContextWorkingText(.chat)),
            ("MCP state", .agents, .agentContextState(.external)),
            ("外部状态访问", .agents, .agentContextState(.external)),
            ("MCP working text", .agents, .agentContextWorkingText(.external)),
            ("外部工作文本", .agents, .agentContextWorkingText(.external)),
        ]
        for (query, destination, section) in cases {
            #expect(
                SettingsSearchTarget.matches(query).contains {
                    $0.destination == destination && $0.section == section
                }, "Query: \(query); target: \(section.id)")
        }
        #expect(SettingsSearchTarget.matches("no-such-setting-qa").isEmpty)
        #expect(SettingsSearchTarget.matches("  ").isEmpty)
    }

    @Test("Agent context results retain distinct single control destinations")
    func agentContextAccessTargets() {
        let expectedIDs = [
            "agents.context.chat.state", "agents.context.chat.workingText",
            "agents.context.external.state", "agents.context.external.workingText",
        ]
        for id in expectedIDs {
            let targets = SettingsSearchTarget.all.filter { $0.id == id }
            #expect(targets.count == 1)
            #expect(targets.first?.section.id == id)
            #expect(targets.first?.destination == .agents)
        }
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
