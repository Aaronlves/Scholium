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

        controller.activate(
            document: document,
            title: "Agency",
            toolTip: "Agency — Topics/Agency.md",
            placement: .replaceSelected
        )

        let tab = try #require(controller.tabs.first)
        #expect(controller.tabs.count == 1)
        #expect(controller.selectedTabID == tab.id)
        #expect(tab.document == document)
    }

    @Test("New Tab selects a distinct document without replacing its neighbor")
    func newTabSelectsDistinctDocument() throws {
        let controller = DocumentTabController()
        let first = fixtureDocument(path: "Topics/Agency.md")
        let second = fixtureDocument(path: "Topics/Reasons.md")
        _ = try add(first, to: controller)

        controller.activate(
            document: second,
            title: "Reasons",
            toolTip: "Reasons",
            placement: .newTab
        )
        let secondID = try #require(controller.selectedTabID)

        #expect(controller.tabs.map(\.document) == [first, second])
        #expect(controller.selectedTabID == secondID)
    }

    @Test("Repeated New Tab activation selects the existing stable document")
    func repeatedNewTabSelectsExistingDocument() throws {
        let controller = DocumentTabController()
        let document = fixtureDocument(path: "Topics/Agency.md")
        let firstID = try add(document, to: controller)

        controller.activate(
            document: document,
            title: "Updated Agency",
            toolTip: "Updated Agency",
            placement: .newTab
        )

        #expect(controller.tabs.count == 1)
        #expect(controller.tabs.first?.title == "Updated Agency")
        #expect(controller.selectedTabID == firstID)
    }

    @Test("Replacing with an already open target preserves both existing tabs")
    func replaceWithExistingTargetPreservesTabs() throws {
        let controller = DocumentTabController()
        let first = fixtureDocument(path: "Topics/Agency.md")
        let second = fixtureDocument(path: "Topics/Reasons.md")
        let firstID = try add(first, to: controller)
        let secondID = try add(second, to: controller)
        controller.selectTab(withID: firstID)

        controller.activate(
            document: second,
            title: "Reasons",
            toolTip: "Reasons",
            placement: .replaceSelected
        )

        #expect(controller.tabs.map(\.id) == [firstID, secondID])
        #expect(controller.selectedTabID == secondID)
    }

    @Test("The same displayed path with different stable identities may coexist")
    func samePathDifferentStableIdentityMayCoexist() throws {
        let controller = DocumentTabController()
        let vaultID = UUID()
        let first = fixtureDocument(
            path: "Topics/Agency.md",
            vaultID: vaultID,
            noteID: UUID()
        )
        let second = fixtureDocument(
            path: "Topics/Agency.md",
            vaultID: vaultID,
            noteID: UUID()
        )

        _ = try add(first, to: controller)
        _ = try add(second, to: controller)

        #expect(controller.tabs.count == 2)
    }

    @Test("Mixed-vault documents share one ordered collection and neighbor selection")
    func mixedVaultTabs() throws {
        let controller = DocumentTabController()
        let analysis = fixtureDocument(path: "Analysis.md")
        let topic = fixtureDocument(path: "Topic.md")
        let analysisID = try add(analysis, to: controller)
        let topicID = try add(topic, to: controller)
        #expect(controller.tabs.map(\.id) == [analysisID, topicID])
        #expect(controller.selectedTabID == topicID)
        let close = try #require(controller.closePlan(forTabWithID: topicID))
        #expect(close.documentToActivate == analysis)
        controller.apply(close)
        #expect(controller.selectedTabID == analysisID)
    }

    @Test("A close plan cannot overwrite a later selection")
    func staleClosePlan() throws {
        let controller = DocumentTabController()
        let first = try add(fixtureDocument(path: "First.md"), to: controller)
        let second = try add(fixtureDocument(path: "Second.md"), to: controller)
        let plan = try #require(controller.closePlan(forTabWithID: second))
        controller.selectTab(withID: first)
        controller.apply(plan)
        #expect(controller.tabs.count == 2)
        #expect(controller.selectedTabID == first)
    }

    @Test("Closing a selected middle tab chooses its next neighbor")
    func closeSelectedMiddleChoosesNext() throws {
        let controller = DocumentTabController()
        let first = try add(fixtureDocument(path: "Topics/One.md"), to: controller)
        let middle = try add(fixtureDocument(path: "Topics/Two.md"), to: controller)
        let last = try add(fixtureDocument(path: "Topics/Three.md"), to: controller)
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
        let first = try add(fixtureDocument(path: "Topics/One.md"), to: controller)
        let last = try add(fixtureDocument(path: "Topics/Two.md"), to: controller)

        let plan = try #require(controller.closePlan(forTabWithID: last))
        #expect(plan.selectedTabIDAfterClose == first)
        controller.apply(plan)

        #expect(controller.selectedTabID == first)
        #expect(controller.tabs.count == 1)
    }

    @Test("Closing the only tab leaves the document region empty")
    func closeOnlyTabLeavesNoSelection() throws {
        let controller = DocumentTabController()
        let only = try add(fixtureDocument(path: "Topics/Only.md"), to: controller)

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
        let inactive = try add(fixtureDocument(path: "Topics/Inactive.md"), to: controller)
        let active = try add(fixtureDocument(path: "Topics/Active.md"), to: controller)

        let plan = try #require(controller.closePlan(forTabWithID: inactive))
        #expect(plan.documentToActivate == nil)
        controller.apply(plan)

        #expect(controller.selectedTabID == active)
        #expect(controller.tabs.map(\.id) == [active])
    }

    @Test("A proven-missing batch cannot leave a stale selected tab")
    func missingBatchClearsRemovedSelection() throws {
        let controller = DocumentTabController()
        let first = try add(fixtureDocument(path: "Topics/First.md"), to: controller)
        let selected = try add(fixtureDocument(path: "Topics/Deleted.md"), to: controller)
        let surviving = try add(fixtureDocument(path: "Topics/Surviving.md"), to: controller)
        controller.selectTab(withID: selected)

        controller.removeTabs(withIDs: [first, selected])

        #expect(controller.tabs.map(\.id) == [surviving])
        #expect(controller.selectedTabID == nil)
    }

    @Test("A stable rename updates the retained tab projection")
    func stableRenameUpdatesRetainedTab() throws {
        let controller = DocumentTabController()
        let original = fixtureDocument(path: "Topics/Old.md")
        _ = try add(original, to: controller)
        let descriptor = original.workspaceDescriptor!
        let renamed = WindowSelectedDocument.workspace(
            WindowDocumentDescriptor(
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

        #expect(controller.tabs.count == 1)
        #expect(controller.tabs.first?.document == renamed)
        #expect(controller.tabs.first?.title == "New")
    }

    private func add(
        _ document: WindowSelectedDocument,
        to controller: DocumentTabController
    ) throws -> UUID {
        controller.activate(
            document: document,
            title: document.relativePath,
            toolTip: document.relativePath,
            placement: .newTab
        )
        return try #require(
            controller.selectedTabID,
            "Activating a document must select its owned tab."
        )
    }

    private func fixtureDocument(
        path: String,
        vaultID: UUID = UUID(),
        noteID: UUID = UUID()
    ) -> WindowSelectedDocument {
        .workspace(
            WindowDocumentDescriptor(
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
