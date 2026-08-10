import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Document navigation history controller")
@MainActor
struct DocumentNavigationHistoryControllerTests {
    @Test("Back and Forward traverse the successful visit sequence")
    func backAndForwardTraverseVisits() throws {
        let controller = DocumentNavigationHistoryController()
        let first = fixtureDocument(path: "Topics/Agency.md")
        let second = fixtureDocument(path: "Topics/Reasons.md")
        let third = fixtureDocument(path: "Topics/Normativity.md")

        controller.record(first)
        controller.record(second)
        controller.record(third)

        #expect(controller.canGoBack)
        #expect(!controller.canGoForward)
        #expect(controller.target(for: .back) == second)
        #expect(controller.commit(.back, to: second))
        #expect(controller.target(for: .back) == first)
        #expect(controller.target(for: .forward) == third)
        #expect(controller.commit(.forward, to: third))
        #expect(!controller.canGoForward)
    }

    @Test("A new visit after Back discards the abandoned Forward branch")
    func newVisitDiscardsForwardBranch() throws {
        let controller = DocumentNavigationHistoryController()
        let first = fixtureDocument(path: "Topics/Agency.md")
        let second = fixtureDocument(path: "Topics/Reasons.md")
        let abandoned = fixtureDocument(path: "Topics/Abandoned.md")
        let replacement = fixtureDocument(path: "Topics/Replacement.md")

        controller.record(first)
        controller.record(second)
        controller.record(abandoned)
        #expect(controller.commit(.back, to: second))

        controller.record(replacement)

        #expect(controller.count == 3)
        #expect(controller.target(for: .back) == second)
        #expect(!controller.canGoForward)
    }

    @Test("Repeated activation of the current document creates no duplicate")
    func repeatedActivationCreatesNoDuplicate() {
        let controller = DocumentNavigationHistoryController()
        let document = fixtureDocument(path: "Topics/Agency.md")

        controller.record(document)
        controller.record(document)

        #expect(controller.count == 1)
        #expect(!controller.canGoBack)
        #expect(!controller.canGoForward)
    }

    private func fixtureDocument(path: String) -> WindowSelectedDocument {
        let vaultID = UUID()
        let noteID = UUID()
        return .workspace(WindowDocumentDescriptor(
            sessionKey: DocumentSessionKey(vaultID: vaultID, noteID: noteID),
            reference: VaultNoteReference(
                vaultID: vaultID,
                vaultName: "Fixture Topics",
                vaultRole: .topicKnowledge,
                relativePath: path,
                stableNoteID: noteID.uuidString.lowercased()
            )
        ))
    }
}
