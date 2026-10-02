import AppKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Native pane visibility toolbar", .serialized)
@MainActor
struct PaneVisibilityToolbarTests {
    @Test("The native group projects all three exclusive states with named overflow commands")
    func exclusiveNativeStates() throws {
        let order = ScholiumWorkspaceToolbarController.itemIdentifiers(tabIdentifiers: [])
        let historyIndex = try #require(order.firstIndex(of: ScholiumWorkspaceToolbarController.Item.forward))
        let modeIndex = try #require(order.firstIndex(of: ScholiumWorkspaceToolbarController.Item.documentMode))
        #expect(order[historyIndex..<modeIndex].contains(.flexibleSpace))
        #expect(order.last == ScholiumWorkspaceToolbarController.Item.paneVisibility)
        let first = command("PDF Reader", symbol: "doc.richtext")
        let second = command("Research Inspector", symbol: "sidebar.trailing")
        let group = ScholiumPaneVisibilityToolbarPresentation.group(
            identifier: .init("fixture.panes"), label: "Reading Panes", items: [first, second], target: nil, action: nil)
        defer { ScholiumPaneVisibilityToolbarPresentation.invalidate(group) }
        #expect(group.selectionMode == .selectAny && group.controlRepresentation == .expanded)
        #expect(group.subitems.count == 2 && group.label == "Reading Panes")
        if #available(macOS 27, *) { #expect(group.role == .valueSelection) }
        #expect(group.menuFormRepresentation?.submenu?.items.map(\.title) == ["PDF Reader", "Research Inspector"])

        for selected in [[false, false], [true, false], [false, true]] {
            ScholiumPaneVisibilityToolbarPresentation.refresh(group, selected: selected)
            #expect(group.isSelected(at: 0) == selected[0] && group.isSelected(at: 1) == selected[1])
            #expect(first.menuFormRepresentation?.state == (selected[0] ? .on : .off))
            #expect(second.menuFormRepresentation?.state == (selected[1] ? .on : .off))
        }
        #expect(group.subitems[0].image?.accessibilityDescription == "PDF Reader")
        #expect(group.subitems[1].image?.accessibilityDescription == "Research Inspector")
        second.isEnabled = false
        ScholiumPaneVisibilityToolbarPresentation.refresh(group, selected: [false, true])
        #expect(!group.isSelected(at: 0) && group.isSelected(at: 1))
        #expect(group.subitems[0].isEnabled && !group.subitems[1].isEnabled)
        #expect(first.menuFormRepresentation?.state == .off && second.menuFormRepresentation?.state == .on)
        #expect(group.isEnabled)

        ScholiumPaneVisibilityToolbarPresentation.invalidate(group)
        #expect(!group.isEnabled && group.isHidden)
        #expect(group.target == nil && group.action == nil && group.subitems.isEmpty)
        #expect(group.menuFormRepresentation?.action == nil && group.menuFormRepresentation?.target == nil)
        #expect(group.menuFormRepresentation?.isEnabled != true)
        #expect([first, second].allSatisfy { $0.target == nil && $0.action == nil && !$0.isEnabled })
    }

    @Test("Toolbar and overflow dispatch mutually exclusive panes and reject a stale disabled selection")
    func windowCommandOwnership() async throws {
        let model = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let noteID = UUID()
        let document = NoteDocument(relativePath: "Synthetic.md", rawContent: "---\nid: \(noteID)\n---\n\nSynthetic Note.\n")
        model.documentController.installOpenedDocument(
            WorkspaceNoteSnapshot(
                id: .init(vaultID: UUID(), relativePath: document.relativePath), vaultRole: .sourceCorpus,
                stableIdentity: .resolved(noteID), document: document,
                fileMetadata: .init(byteCount: document.sourceBytes.count, creationDate: nil, modificationDate: nil),
                graphCounts: .init(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0)), vaultName: "Fixture", vaultRole: .sourceCorpus)
        let split = NSSplitViewController()
        split.addSplitViewItem(NSSplitViewItem(sidebarWithViewController: NSViewController()))
        split.addSplitViewItem(NSSplitViewItem(viewController: NSViewController()))
        split.addSplitViewItem(NSSplitViewItem(inspectorWithViewController: NSViewController()))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640), styleMask: [.titled, .resizable, .closable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = split
        window.layoutIfNeeded()
        let actions = WorkspaceWindowActions(
            toggleFocusLayout: {}, canToggleFocusLayout: { true }, canUseSidebar: { true },
            setLibraryVisible: { _ in }, setResearchInspectorVisible: { model.sidePaneCoordinator.setInspectorVisible($0) },
            activateSidebar: { _ in }, showAttention: { _ in }, showPreferredAttention: {}, canShowAttention: { false })
        let controller = ScholiumWorkspaceToolbarController(appState: model, windowActions: actions, splitViewController: split)
        defer {
            controller.invalidate()
            model.sidePaneCoordinator.shutdown()
            model.pdfReaderController.shutdown()
            window.toolbar = nil
            window.close()
        }
        model.pdfReaderController.setVisible(true)
        controller.install(in: window)
        let toolbar = try #require(window.toolbar)
        let group = try #require(toolbar.items.last as? NSToolbarItemGroup)
        #expect(group.isSelected(at: 0) && !group.isSelected(at: 1))
        #expect(group.subitems.map(\.itemIdentifier) == [ScholiumWorkspaceToolbarController.Item.pdfReader, ScholiumWorkspaceToolbarController.Item.inspector])
        let overflow = try #require(group.menuFormRepresentation?.submenu?.items.last)
        #expect(NSApplication.shared.sendAction(try #require(overflow.action), to: overflow.target, from: overflow))
        try await settleTransition(model)
        #expect(!model.pdfReaderController.isVisible && model.shellState.inspector.isVisible)
        await drainPresentation()
        #expect(!group.isSelected(at: 0) && group.isSelected(at: 1))

        group.setSelected(true, at: 0)
        #expect(NSApplication.shared.sendAction(try #require(group.action), to: group.target, from: group))
        #expect(model.pdfReaderController.isVisible && !model.shellState.inspector.isVisible)
        #expect(group.isSelected(at: 0) && !group.isSelected(at: 1))
        group.setSelected(false, at: 0)
        #expect(NSApplication.shared.sendAction(try #require(group.action), to: group.target, from: group))
        try await settleTransition(model)
        await drainPresentation()
        #expect(!model.pdfReaderController.isVisible && !model.shellState.inspector.isVisible)
        #expect(!group.isSelected(at: 0) && !group.isSelected(at: 1))
        // A queued control event cannot reveal a pane in enforced Focus Layout
        // or leave a false native selection behind.
        model.shellState.recordFocusLayout(true, lockedByFullScreen: true)
        group.setSelected(true, at: 0)
        #expect(NSApplication.shared.sendAction(try #require(group.action), to: group.target, from: group))
        #expect(!model.pdfReaderController.isVisible && !model.shellState.inspector.isVisible)
        #expect(!group.isSelected(at: 0) && !group.isSelected(at: 1))
        let staleAction = try #require(group.action)
        let staleTarget = group.target
        controller.invalidate()
        #expect(group.subitems.isEmpty)
        #expect(NSApplication.shared.sendAction(staleAction, to: staleTarget, from: group))
        #expect(!model.pdfReaderController.isVisible && !model.shellState.inspector.isVisible)
    }

    @Test("Separate Notes align editing commands at the Markdown trailing edge and a single PDF toggle at right")
    func separateToolbarOrder() throws {
        let model = WindowModel(workspaceStore: makeTestWorkspaceStore())
        model.isDetachedDocumentWindow = true
        let controller = DetachedDocumentToolbar(model: model)
        defer {
            controller.invalidate()
            model.pdfReaderController.shutdown()
        }
        let identifiers = controller.toolbarDefaultItemIdentifiers(controller.toolbar)
        #expect(identifiers == [.flexibleSpace, .init("mode"), .init("more"), .space, ScholiumWorkspaceToolbarController.Item.pdfReader])
        let group = try #require(
            controller.toolbar(controller.toolbar, itemForItemIdentifier: identifiers.last!, willBeInsertedIntoToolbar: true) as? NSToolbarItemGroup)
        #expect(group.selectionMode == .selectAny && group.subitems.count == 1)
        #expect(!group.isSelected(at: 0))
        model.pdfReaderController.setVisible(true)
        _ = controller.toolbar(controller.toolbar, itemForItemIdentifier: group.itemIdentifier, willBeInsertedIntoToolbar: true)
        #expect(group.isSelected(at: 0) && group.menuFormRepresentation?.state == .on)
    }

    private func command(_ label: String, symbol: String) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .init(label))
        item.label = label
        item.image = ScholiumNativeToolbarPresentation.symbol(named: symbol)
        item.isEnabled = true
        item.menuFormRepresentation = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        return item
    }

    private func drainPresentation() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func settleTransition(_ model: WindowModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.sidePaneCoordinator.isTransitioning, ContinuousClock.now < deadline { await Task.yield() }
        try #require(!model.sidePaneCoordinator.isTransitioning)
    }

}
