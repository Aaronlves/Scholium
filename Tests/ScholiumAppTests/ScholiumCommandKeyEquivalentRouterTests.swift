import AppKit
import Testing

@testable import ScholiumApp

@Suite("Command Key Equivalent Router", .serialized)
struct ScholiumCommandKeyEquivalentRouterTests {
    @Test("Registered shortcuts are dispatched through the native menu")
    @MainActor
    func routesRegisteredMenuCommand() throws {
        let suite = "ScholiumCommandRouterTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let menu = RecordingMenu()

        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
                characters: "-", charactersIgnoringModifiers: "-", isARepeat: false, keyCode: 27
            )
        )

        #expect(
            ScholiumCommandKeyEquivalentRouter.route(
                event, menu: menu, defaults: defaults
            )
        )
        #expect(menu.routeCount == 1)
    }

    @Test("Unregistered events remain available to the document input owner")
    @MainActor
    func leavesUnregisteredEventUnclaimed() throws {
        let suite = "ScholiumCommandRouterUnclaimedTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7
            )
        )

        #expect(!ScholiumCommandKeyEquivalentRouter.route(event, menu: NSMenu(), defaults: defaults))
    }

    @MainActor
    private final class RecordingMenu: NSMenu {
        nonisolated(unsafe) var routeCount = 0

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            routeCount += 1
            return true
        }
    }
}
