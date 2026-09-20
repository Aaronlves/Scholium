import AppKit
import Combine
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Notifications native presentation", .serialized)
@MainActor
struct AttentionQueuePresentationTests {
    @Test("Native Notifications gives the list first responder and keeps the search field native")
    func nativeFocus() async throws {
        _ = NSApplication.shared
        let store = makeTestWorkspaceStore()
        let workspaceController = WindowWorkspaceController(
            workspaceStore: store,
            requestedTriptychID: nil
        )
        let discoveryController = DiscoveryController()
        let projectionController = WindowWorkspaceProjectionController {
            throw DiscoverySearchExecutionError.workspaceUnavailable
        }
        let agentChanges = PassthroughSubject<[AgentChange]?, Never>()
        let agentChangeErrors = PassthroughSubject<String?, Never>()
        let vault = RegisteredVault(
            name: "Topics",
            role: .topicKnowledge,
            canonicalPath: "/fixtures/Topics"
        )
        let reference = VaultNoteReference(
            vaultID: vault.id,
            vaultName: vault.name,
            vaultRole: vault.role,
            relativePath: "Reasons.md"
        )
        let issue = AttentionQueueItem(
            kind: .possibleOrphan,
            severity: .information,
            note: reference,
            message: "No incoming or outgoing links"
        )
        projectionController.replaceCatalog(
            WorkspaceCatalogBuilder.build(
                vaults: [vault],
                documents: [vault.id: [NoteDocument(relativePath: "Reasons.md", rawContent: "# Reasons\n")]],
                additionalAttention: [issue]
            )
        )
        let session = AttentionPopoverSession(
            presentation: AttentionPresentationState(),
            discoveryController: discoveryController,
            workspaceController: workspaceController,
            projectionController: projectionController,
            dependencies: .init(
                settlementRequirementChanges: Just([]).eraseToAnyPublisher(),
                agentChangeChanges: agentChanges.eraseToAnyPublisher(),
                agentChangeErrorChanges: agentChangeErrors.eraseToAnyPublisher(),
                refresh: {},
                showAgentChange: { _ in }
            )
        )
        agentChanges.send([])
        agentChangeErrors.send(nil)
        session.presentQueue(anchor: .toolbar, workspaceSlot: nil, noteScope: nil)

        let controller = AttentionQueueViewController(
            presentation: session.presentation,
            session: session
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer {
            window.contentView = nil
            window.close()
        }

        window.makeKeyAndOrderFront(nil)
        controller.focusInitialContentIfNeeded()

        try await wait {
            find(NSTableView.self, in: controller.view)?.numberOfRows == 0
                && window.firstResponder === find(NSTableView.self, in: controller.view)
        }
        let table = try #require(find(NSTableView.self, in: controller.view))
        let search = try #require(find(NSSearchField.self, in: controller.view))
        #expect(table.accessibilityIdentifier() == "scholium.attentionList")
        #expect(table.allowsMultipleSelection == false)
        #expect(search.accessibilityIdentifier() == "scholium.attentionSearch")
        #expect(search.searchMenuTemplate?.items.count == 3)
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(predicate())
    }
}
