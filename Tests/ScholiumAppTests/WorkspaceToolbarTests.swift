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

    @Test("Records uses Triptych scope when no Document is selected")
    func recordsUsesTriptychScopeWithoutDocument() {
        let presentation = ScholiumWorkspaceResearchRecordsToolbarState.resolve(
            hasTriptych: true,
            hasCurrentNote: false,
            currentNoteIsAvailable: false
        )

        #expect(presentation.scope == .triptych)
        #expect(presentation.title == "Triptych Records")
        #expect(presentation.isEnabled)
    }

    @Test("Records uses an available This Note scope independently of Edit mode")
    func recordsUsesResolvedCurrentNoteScope() {
        let presentation = ScholiumWorkspaceResearchRecordsToolbarState.resolve(
            hasTriptych: true,
            hasCurrentNote: true,
            currentNoteIsAvailable: true
        )

        #expect(presentation.scope == .note)
        #expect(presentation.title == "This Note Records")
        #expect(presentation.isEnabled)
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
        let headingButton = try #require(heading.view?.subviews.first as? NSButton)
        #expect(heading.visibilityPriority == .high)
        #expect(heading.label == "Heading Outline")
        #expect(!heading.isBordered)
        #expect(heading.isNavigational)
        #expect(headingButton.isBordered)
        #expect(headingButton.showsBorderOnlyWhileMouseInside)
        #expect(headingButton.imagePosition == .imageOnly)
        #expect(headingButton.accessibilityRole() == .popUpButton)
        #expect(headingButton.target === controller)
        #expect(headingButton.action != nil)

        for identifier in [
            ScholiumWorkspaceToolbarController.Item.sidebar,
            ScholiumWorkspaceToolbarController.Item.back,
            ScholiumWorkspaceToolbarController.Item.forward,
            ScholiumWorkspaceToolbarController.Item.search,
            ScholiumWorkspaceToolbarController.Item.documentMode,
            ScholiumWorkspaceToolbarController.Item.researchRecords,
            ScholiumWorkspaceToolbarController.Item.inspector,
        ] {
            let command = try #require(item(identifier, in: toolbar))
            let button = try #require(command.view?.subviews.first as? NSButton)
            #expect(button.target === controller)
            #expect(button.action != nil)
            #expect(command.visibilityPriority == (
                identifier == ScholiumWorkspaceToolbarController.Item.sidebar
                    || identifier == ScholiumWorkspaceToolbarController.Item.inspector
                    ? .user
                    : .high
            ))
            #expect(!command.isBordered)
            #expect(button.isBordered)
            #expect(button.showsBorderOnlyWhileMouseInside)
            #expect(button.imagePosition == .imageOnly)
            let overflowCommand = try #require(command.menuFormRepresentation)
            #expect(overflowCommand.target === controller)
            #expect(overflowCommand.action == button.action)
            #expect(overflowCommand.image != nil)
        }

        for identifier in [
            ScholiumWorkspaceToolbarController.Item.sidebar,
            ScholiumWorkspaceToolbarController.Item.back,
            ScholiumWorkspaceToolbarController.Item.forward,
        ] {
            #expect(!(try #require(item(identifier, in: toolbar))).isNavigational)
        }
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
        let sidebarButton = try #require(sidebar.view?.subviews.first as? NSButton)
        #expect(sidebarButton.accessibilityLabel() == "Hide Sidebar")
        #expect(sidebarButton.accessibilityValue() as? String == "Shown")

        model.shellState.recordLibraryVisibility(false)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }

        #expect(sidebarButton.accessibilityLabel() == "Show Sidebar")
        #expect(sidebarButton.accessibilityValue() as? String == "Hidden")
    }

    private var inertWindowActions: WorkspaceWindowActions {
        WorkspaceWindowActions(
            setLibraryVisible: { _ in },
            setResearchInspectorVisible: { _ in },
            showNoteResearchRecords: {},
            showTriptychResearchRecords: {},
            showAttention: { _, _ in },
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
