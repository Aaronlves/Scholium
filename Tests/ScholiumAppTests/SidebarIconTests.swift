import AppKit
import Testing
@testable import ScholiumApp

@Suite("Sidebar symbol availability") @MainActor
struct SidebarIconTests {
    @Test("Every shared sidebar symbol resolves on the supported native runtime")
    func nativeSymbols() {
        let names = ScholiumSidebarAction.allCases.map(\.symbol)
            + ScholiumSidebarItem.allCases.map(\.symbol)
            + [ScholiumSidebarHeaderIcon.filterSymbol(isActive: false),
               ScholiumSidebarHeaderIcon.filterSymbol(isActive: true),
               AgentChatListPresentation.unreadSymbol,
               AgentChatListPresentation.importantSymbol,
               AgentChatListPresentation.readActionSymbol(isUnread: false),
               AgentChatListPresentation.readActionSymbol(isUnread: true),
               AgentChatListPresentation.importanceActionSymbol(isImportant: false),
               AgentChatListPresentation.importanceActionSymbol(isImportant: true)]
        for name in Set(names) {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                    "Unavailable sidebar symbol: \(name)")
        }
    }
}
