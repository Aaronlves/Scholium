import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Document tab controller")
@MainActor
struct DocumentTabControllerTests {
    @Test("The first document creates one selected tab")
    func firstDocumentCreatesSelectedTab() throws {
        let controller = DocumentTabController()
        let document = fixtureDocument(path: "Topics/Agency.md")

        controller.replaceSelectedTab(
            with: document,
            title: "Agency",
            toolTip: "Agency — Topics/Agency.md"
        )

        let tab = try #require(controller.tabs.first)
        #expect(controller.tabs.count == 1)
        #expect(controller.selectedTabID == tab.id)
        #expect(tab.document == document)
    }

    @Test("Appending selects the new tab without replacing its neighbor")
    func appendSelectsNewTab() throws {
        let controller = DocumentTabController()
        let first = fixtureDocument(path: "Topics/Agency.md")
        let second = fixtureDocument(path: "Topics/Reasons.md")
        controller.appendTab(for: first, title: "Agency", toolTip: "Agency")

        let secondID = controller.appendTab(
            for: second,
            title: "Reasons",
            toolTip: "Reasons"
        )

        #expect(controller.tabs.map(\.document) == [first, second])
        #expect(controller.selectedTabID == secondID)
    }

    @Test("Closing a selected middle tab chooses its next neighbor")
    func closeSelectedMiddleChoosesNext() throws {
        let controller = DocumentTabController()
        let first = controller.appendTab(
            for: fixtureDocument(path: "Topics/One.md"),
            title: "One",
            toolTip: "One"
        )
        let middle = controller.appendTab(
            for: fixtureDocument(path: "Topics/Two.md"),
            title: "Two",
            toolTip: "Two"
        )
        let last = controller.appendTab(
            for: fixtureDocument(path: "Topics/Three.md"),
            title: "Three",
            toolTip: "Three"
        )
        controller.selectTab(withID: middle)

        let plan = try #require(controller.closePlan(forTabWithID: middle))
        #expect(plan.selectedTabIDAfterClose == last)
        controller.apply(plan)

        #expect(controller.selectedTabID == last)
        #expect(controller.tabs.map(\.id) == [first, last])
    }

    @Test("Closing the last selected tab chooses its previous neighbor")
    func closeLastChoosesPrevious() throws {
        let controller = DocumentTabController()
        let first = controller.appendTab(
            for: fixtureDocument(path: "Topics/One.md"),
            title: "One",
            toolTip: "One"
        )
        let last = controller.appendTab(
            for: fixtureDocument(path: "Topics/Two.md"),
            title: "Two",
            toolTip: "Two"
        )

        let plan = try #require(controller.closePlan(forTabWithID: last))
        #expect(plan.selectedTabIDAfterClose == first)
        controller.apply(plan)

        #expect(controller.selectedTabID == first)
        #expect(controller.tabs.count == 1)
    }

    @Test("Closing the only tab leaves the document region empty")
    func closeOnlyTabLeavesNoSelection() throws {
        let controller = DocumentTabController()
        let only = controller.appendTab(
            for: fixtureDocument(path: "Topics/Only.md"),
            title: "Only",
            toolTip: "Only"
        )

        let plan = try #require(controller.closePlan(forTabWithID: only))
        #expect(plan.selectedTabIDAfterClose == nil)
        #expect(plan.documentToActivate == nil)
        controller.apply(plan)

        #expect(controller.tabs.isEmpty)
        #expect(controller.selectedTabID == nil)
    }

    @Test("Closing an inactive tab preserves the active tab")
    func closeInactivePreservesSelection() throws {
        let controller = DocumentTabController()
        let inactive = controller.appendTab(
            for: fixtureDocument(path: "Topics/Inactive.md"),
            title: "Inactive",
            toolTip: "Inactive"
        )
        let active = controller.appendTab(
            for: fixtureDocument(path: "Topics/Active.md"),
            title: "Active",
            toolTip: "Active"
        )

        let plan = try #require(controller.closePlan(forTabWithID: inactive))
        #expect(plan.documentToActivate == nil)
        controller.apply(plan)

        #expect(controller.selectedTabID == active)
        #expect(controller.tabs.map(\.id) == [active])
    }

    @Test("A stable rename updates every tab projection for the same note")
    func stableRenameUpdatesMatchingTabs() {
        let controller = DocumentTabController()
        let original = fixtureDocument(path: "Topics/Old.md")
        controller.appendTab(for: original, title: "Old", toolTip: "Old")
        controller.appendTab(for: original, title: "Old", toolTip: "Old")
        let descriptor = original.workspaceDescriptor!
        let renamed = WindowSelectedDocument.workspace(WindowDocumentDescriptor(
            sessionKey: descriptor.sessionKey,
            reference: VaultNoteReference(
                vaultID: descriptor.reference.vaultID,
                vaultName: descriptor.reference.vaultName,
                vaultRole: descriptor.reference.vaultRole,
                relativePath: "Topics/New.md",
                stableNoteID: descriptor.reference.stableNoteID
            )
        ))

        controller.updateDocumentProjection(
            renamed,
            title: "New",
            toolTip: "New — Topics/New.md"
        )

        #expect(controller.tabs.allSatisfy { $0.document == renamed })
        #expect(controller.tabs.allSatisfy { $0.title == "New" })
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
