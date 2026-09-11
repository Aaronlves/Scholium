import AppKit
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@MainActor
struct ResearchSearchFieldTests {
    @Test("Advanced Search cannot offer its own launch action")
    func advancedMenuHasNoRecursiveEntry() {
        let quick = field(openAdvanced: {})
        let advanced = field(openAdvanced: nil)
        let quickMenu = ResearchSearchField.Coordinator(quick).makeSearchMenu()
        let advancedMenu = ResearchSearchField.Coordinator(advanced).makeSearchMenu()
        #expect(quickMenu.items.contains { $0.action == #selector(ResearchSearchField.Coordinator.advancedSearch(_:)) })
        #expect(!advancedMenu.items.contains { $0.action == #selector(ResearchSearchField.Coordinator.advancedSearch(_:)) })
        #expect(advancedMenu.items.filter { $0.submenu != nil }.count == 1)
    }

    @Test("Search filter menus expose current scope and preserve the query")
    func filtersPreserveQuery() throws {
        var query = "aurora-fixture"
        var scope: SearchPresentationScope = .triptych
        let field = ResearchSearchField(
            text: Binding(get: { query }, set: { query = $0 }),
            placeholder: "Search", scope: Binding(get: { scope }, set: { scope = $0 }),
            openAdvanced: {},
            isActive: true, focusRequestID: nil, replacementID: 0, beganEditing: {}, endedEditing: {}, command: { _ in false })
        let coordinator = ResearchSearchField.Coordinator(field)
        let menu = coordinator.makeSearchMenu()
        let thisVault = try #require(menu.items.first?.submenu?.items[1])
        coordinator.selectScope(thisVault)
        #expect(scope == .currentVault)
        #expect(coordinator.validateMenuItem(thisVault))
        #expect(thisVault.state == .on)
        #expect(query == "aurora-fixture")
        coordinator.clearFilters(NSMenuItem())
        #expect(scope == .triptych)
        #expect(query == "aurora-fixture")
    }

    private func field(openAdvanced: (() -> Void)?) -> ResearchSearchField {
        ResearchSearchField(
            text: .constant(""), placeholder: "Search",
            scope: .constant(.triptych), openAdvanced: openAdvanced,
            isActive: false, focusRequestID: nil, replacementID: 0, beganEditing: {}, endedEditing: {}, command: { _ in false })
    }
}
