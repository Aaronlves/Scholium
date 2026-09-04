import AppKit
import Testing

@testable import ScholiumApp

@Suite("Workspace toolbar")
@MainActor
struct WorkspaceToolbarTests {
    @Test("Window appearance keeps native toolbar chrome aligned with the selected scheme")
    func nativeToolbarAppearanceFollowsWindowChoice() {
        let window = testWindow()
        defer { window.close() }

        ScholiumWindowAppearance.apply(.light, to: window)
        #expect(window.appearance?.name == .aqua)

        ScholiumWindowAppearance.apply(.dark, to: window)
        #expect(window.appearance?.name == .darkAqua)

        ScholiumWindowAppearance.apply(.system, to: window)
        #expect(window.appearance == nil)
    }

    @Test("The explicit Apparatus boundary does not invoke Inspector auto-discovery")
    func apparatusBoundaryHasOneGeometryOwner() {
        #expect(
            ScholiumWorkspaceToolbarController.Item.apparatusDivider
                != .inspectorTrackingSeparator
        )
    }

    @Test("A visible Inspector without a Document has an explicit content state")
    func inspectorHasNoDocumentState() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ContentView.swift"
            ),
            encoding: .utf8
        )
        let apparatusStart = try #require(content.range(
            of: "private var apparatusRegion: some View {"
        ))
        let detailStart = try #require(content.range(
            of: "private var detailContent: some View {",
            range: apparatusStart.upperBound..<content.endIndex
        ))
        let apparatus = content[apparatusStart.lowerBound..<detailStart.lowerBound]

        #expect(apparatus.contains("scholium.noDocumentInspectorState"))
        #expect(!apparatus.contains("Color.clear"))
    }

    @Test("The native toolbar owns command identity, overflow, and navigation")
    func nativeToolbarOwnsLayout() throws {
        let model = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let split = testSplitViewController()
        let window = testWindow()
        window.contentViewController = split
        window.toolbarStyle = .unified
        window.layoutIfNeeded()
        defer {
            window.toolbar = nil
            window.close()
        }

        let controller = ScholiumWorkspaceToolbarController(
            appState: model,
            windowActions: inertWindowActions,
            splitViewController: split
        )
        controller.install(in: window)

        let toolbar = try #require(window.toolbar)
        #expect(toolbar.itemIdentifiers == ScholiumWorkspaceToolbarController.itemIdentifiers)

        let heading = try #require(item(
            ScholiumWorkspaceToolbarController.Item.headingOutline,
            in: toolbar
        ))
        #expect(heading.visibilityPriority == .high)
        #expect(heading.label == "Heading Outline")
        #expect(heading.isBordered)
        #expect(heading.style == .plain)
        #expect(heading.isNavigational)
        #expect(heading.view == nil)
        #expect((heading as? NSMenuToolbarItem)?.menu != nil)

        for identifier in [
            ScholiumWorkspaceToolbarController.Item.sidebar,
            ScholiumWorkspaceToolbarController.Item.back,
            ScholiumWorkspaceToolbarController.Item.forward,
            ScholiumWorkspaceToolbarController.Item.documentMode,
            ScholiumWorkspaceToolbarController.Item.inspector,
        ] {
            let command = try #require(item(identifier, in: toolbar))
            #expect(command.target === controller)
            #expect(command.action != nil)
            #expect(command.visibilityPriority == (
                identifier == ScholiumWorkspaceToolbarController.Item.sidebar
                    || identifier == ScholiumWorkspaceToolbarController.Item.inspector
                    ? .user
                    : .high
            ))
            #expect(command.isBordered)
            #expect(command.style == .plain)
            #expect(command.view == nil)
            let overflowCommand = try #require(command.menuFormRepresentation)
            #expect(overflowCommand.target === controller)
            #expect(overflowCommand.action == command.action)
            #expect(overflowCommand.image != nil)
        }

        let documentMode = try #require(item(
            ScholiumWorkspaceToolbarController.Item.documentMode,
            in: toolbar
        ))
        #expect(documentMode.label.hasPrefix("Document Mode,"))
        #expect(documentMode.possibleLabels.count == 3)

        let sidebar = try #require(item(
            ScholiumWorkspaceToolbarController.Item.sidebar,
            in: toolbar
        ))
        #expect(sidebar.possibleLabels == ["Hide Sidebar", "Show Sidebar"])

        let inspector = try #require(item(
            ScholiumWorkspaceToolbarController.Item.inspector,
            in: toolbar
        ))
        #expect(inspector.possibleLabels == [
            "Hide Research Inspector",
            "Show Research Inspector",
        ])

        for identifier in [
            ScholiumWorkspaceToolbarController.Item.sidebar,
            ScholiumWorkspaceToolbarController.Item.back,
            ScholiumWorkspaceToolbarController.Item.forward,
        ] {
            #expect(!(try #require(item(identifier, in: toolbar))).isNavigational)
        }

        let agentChanges = try #require(item(
            ScholiumWorkspaceToolbarController.Item.agentChanges,
            in: toolbar
        ))
        #expect(agentChanges.isHidden)
    }

    @Test("Peripheral controls mirror their current accessible visibility state")
    func peripheralControlsMirrorVisibility() async throws {
        let model = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let split = testSplitViewController()
        let window = testWindow()
        window.contentViewController = split
        window.layoutIfNeeded()
        defer {
            window.toolbar = nil
            window.close()
        }

        let controller = ScholiumWorkspaceToolbarController(
            appState: model,
            windowActions: inertWindowActions,
            splitViewController: split
        )
        controller.install(in: window)

        let toolbar = try #require(window.toolbar)
        let sidebar = try #require(item(
            ScholiumWorkspaceToolbarController.Item.sidebar,
            in: toolbar
        ))
        #expect(sidebar.label == "Hide Sidebar")

        model.shellState.recordLibraryVisibility(false)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }

        #expect(sidebar.label == "Show Sidebar")
    }

    private var inertWindowActions: WorkspaceWindowActions {
        WorkspaceWindowActions(
            setLibraryVisible: { _ in },
            setResearchInspectorVisible: { _ in },
            showResearchRecords: {},
            showAttention: { _ in },
            showPreferredAttention: {},
            canShowAttention: { false }
        )
    }

    private func item(
        _ identifier: NSToolbarItem.Identifier,
        in toolbar: NSToolbar
    ) -> NSToolbarItem? {
        toolbar.items.first { $0.itemIdentifier == identifier }
    }

    private func testSplitViewController() -> NSSplitViewController {
        let split = NSSplitViewController()
        split.addSplitViewItem(NSSplitViewItem(
            sidebarWithViewController: NSViewController()
        ))
        split.addSplitViewItem(NSSplitViewItem(
            viewController: NSViewController()
        ))
        split.addSplitViewItem(NSSplitViewItem(
            inspectorWithViewController: NSViewController()
        ))
        return split
    }

    private func testWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }
}
