import Foundation
import ScholiumContracts
@testable import ScholiumApp
import Testing

@Suite("Research Records window routing")
@MainActor
struct ResearchRecordsWindowCoordinatorTests {
    @Test("Pending and live requests are isolated by Triptych identity")
    func requestRoutingIsTriptychBound() {
        let coordinator = ResearchRecordsWindowCoordinator()
        let firstTriptych = UUID()
        let secondTriptych = UUID()
        let noteID = UUID()
        let initial = ResearchRecordsWindowRequest(
            triptychID: firstTriptych,
            noteID: noteID,
            initialView: .recommendations
        )
        coordinator.submit(initial)

        var received: [ResearchRecordsWindowRequest] = []
        let token = coordinator.registerRecordsWindow(
            triptychID: firstTriptych
        ) { received.append($0) }
        #expect(received == [initial])

        let reapplied = ResearchRecordsWindowRequest(
            triptychID: firstTriptych,
            initialView: .records
        )
        coordinator.submit(reapplied)
        coordinator.submit(ResearchRecordsWindowRequest(
            triptychID: secondTriptych,
            initialView: .recommendations
        ))
        #expect(received == [initial, reapplied])

        coordinator.unregisterRecordsWindow(
            triptychID: firstTriptych,
            token: token
        )
        coordinator.submit(initial)
        var reopened: [ResearchRecordsWindowRequest] = []
        _ = coordinator.registerRecordsWindow(
            triptychID: firstTriptych
        ) { reopened.append($0) }
        #expect(reopened == [initial])
    }

    @Test("Analysis navigation prefers the latest active workspace in the same Triptych")
    func existingWorkspaceNavigationIsExact() {
        let coordinator = ResearchRecordsWindowCoordinator()
        let triptychID = UUID()
        let otherTriptychID = UUID()
        let noteID = UUID()
        let note = VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Analysis.md")
        var openedBy: [String] = []
        let first = coordinator.registerWorkspace(
            triptychID: triptychID,
            windowID: UUID()
        ) { _, _, _ in openedBy.append("first") }
        let second = coordinator.registerWorkspace(
            triptychID: triptychID,
            windowID: UUID()
        ) { _, _, _ in openedBy.append("second") }

        #expect(coordinator.openInExistingWorkspace(
            triptychID: triptychID,
            noteID: noteID,
            note: note
        ))
        #expect(openedBy == ["second"])

        coordinator.workspaceDidActivate(triptychID: triptychID, token: first)
        #expect(coordinator.openInExistingWorkspace(
            triptychID: triptychID,
            noteID: noteID,
            note: note,
            sourceLine: 42
        ))
        #expect(openedBy == ["second", "first"])
        #expect(!coordinator.openInExistingWorkspace(
            triptychID: otherTriptychID,
            noteID: noteID,
            note: note
        ))

        coordinator.unregisterWorkspace(triptychID: triptychID, token: first)
        coordinator.unregisterWorkspace(triptychID: triptychID, token: second)
        #expect(!coordinator.openInExistingWorkspace(
            triptychID: triptychID,
            noteID: noteID,
            note: note
        ))
    }
}
