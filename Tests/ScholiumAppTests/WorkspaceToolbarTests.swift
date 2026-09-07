import AppKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Workspace toolbar")
@MainActor
struct WorkspaceToolbarTests {
    @Test("Sidebar modes switch in place and repeating the visible mode collapses it")
    func sidebarModes() {
        let state = WindowShellState()
        #expect(state.sidebarContent == .triptych && state.libraryVisible)
        #expect(state.activateSidebar(.chat))
        state.recordLibraryVisibility(true)
        #expect(state.sidebarContent == .chat)
        #expect(!state.activateSidebar(.chat))
        state.recordLibraryVisibility(false)
        #expect(state.activateSidebar(.triptych))
        state.recordLibraryVisibility(true)
        #expect(!state.activateSidebar(.triptych))
        state.recordLibraryVisibility(false)
        #expect(state.activateSidebar(.chat))
    }

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

    @Test("Document Information ignores stale document teardown")
    func documentInformationProjectionIsDocumentScoped() {
        let projection = DocumentInformationProjection()
        let first = DocumentInformationDocumentID(
            vaultID: UUID(),
            relativePath: "First.md"
        )
        let second = DocumentInformationDocumentID(
            vaultID: UUID(),
            relativePath: "Second.md"
        )
        let statistics = DocumentStatistics(
            words: 12,
            charactersWithSpaces: 41,
            charactersWithoutSpaces: 34,
            hanCharacters: 3,
            scope: .selection
        )

        projection.activate(second)
        projection.publish(statistics, for: second)
        projection.publish(.emptyBody, for: first)
        projection.clear(ifCurrent: first)
        #expect(projection.statistics(for: second) == statistics)
        #expect(projection.statistics(for: first) == .emptyBody)

        projection.clear(ifCurrent: second)
        #expect(projection.documentID == nil)
        #expect(projection.statistics == .emptyBody)
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

        let documentInformation = try #require(item(
            ScholiumWorkspaceToolbarController.Item.documentTitle,
            in: toolbar
        ))
        #expect(documentInformation.visibilityPriority == .high)
        let title = try #require(documentInformation.view as? NSTextField)
        #expect(title.stringValue == "Scholium")
        #expect(title.textColor?.usingColorSpace(.deviceRGB) == NSColor.secondaryLabelColor.usingColorSpace(.deviceRGB))
        #expect(window.titleVisibility == .hidden)

        for identifier in [
            ScholiumWorkspaceToolbarController.Item.back,
            ScholiumWorkspaceToolbarController.Item.forward,
            ScholiumWorkspaceToolbarController.Item.settlement,
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

        let settlement = try #require(item(
            ScholiumWorkspaceToolbarController.Item.settlement,
            in: toolbar
        ))
        #expect(settlement.label == "Settlement Unavailable")
        #expect(settlement.isBordered)
        #expect(settlement.style == .plain)
        #expect(settlement.view == nil)
        #expect(settlement.possibleLabels == [
            "Settle", "Settled — Settle Again",
            "Changed since settlement — Settle Again", "Settlement Unavailable",
        ])
        #expect(settlement.menuFormRepresentation?.target === controller)
        #expect(settlement.menuFormRepresentation?.action != nil)

        let sidebar = try #require(item(
            ScholiumWorkspaceToolbarController.Item.sidebar,
            in: toolbar
        ))
        let selector = try #require(sidebar.view as? NSSegmentedControl)
        #expect(selector.segmentStyle == .rounded)
        #expect(selector.selectedSegmentBezelColor == nil)
        #expect(selector.trackingMode == .selectOne)
        #expect(selector.segmentCount == 2)
        #expect(selector.image(forSegment: 0) != nil)
        #expect(selector.image(forSegment: 1) != nil)
        #expect(selector.isSelected(forSegment: 0))
        #expect(!selector.isSelected(forSegment: 1))
        #expect(!selector.isEnabled(forSegment: 1))
        #expect(selector.toolTip(forSegment: 1) == String(localized: "No Triptych Open"))

        let inspector = try #require(item(
            ScholiumWorkspaceToolbarController.Item.inspector,
            in: toolbar
        ))
        let inspectorModes = try #require(item(
            ScholiumWorkspaceToolbarController.Item.inspectorModes,
            in: toolbar
        ))
        let modeControl = try #require(inspectorModes.view as? NSSegmentedControl)
        #expect(ResearchInspectorMode.allCases == [.about, .links, .related])
        #expect(modeControl.segmentCount == 3)
        #expect(modeControl.toolTip(forSegment: 0) == ScholiumL10n.localized(ResearchInspectorMode.about.interfaceTitleResource))
        #expect(modeControl.toolTip(forSegment: 1) == ScholiumL10n.localized(ResearchInspectorMode.links.interfaceTitleResource))
        #expect(inspectorModes.menuFormRepresentation?.submenu?.items.count == 3)
        #expect(inspector.possibleLabels == [
            "Hide Research Inspector",
            "Show Research Inspector",
        ])

        for identifier in [
            ScholiumWorkspaceToolbarController.Item.sidebar,
            ScholiumWorkspaceToolbarController.Item.back,
            ScholiumWorkspaceToolbarController.Item.forward,
        ] {
            #expect((try #require(item(identifier, in: toolbar))).isNavigational == (identifier != ScholiumWorkspaceToolbarController.Item.sidebar))
        }

        #expect(toolbar.items.allSatisfy {
            $0.itemIdentifier.rawValue != "scholium.toolbar.agentChanges"
        })

        // System validation must not re-enable commands merely because their
        // target implements an action. This previously caused state flicker.
        toolbar.validateVisibleItems()
        for identifier in [ScholiumWorkspaceToolbarController.Item.back,
                           ScholiumWorkspaceToolbarController.Item.forward,
                           ScholiumWorkspaceToolbarController.Item.inspector,
                           ScholiumWorkspaceToolbarController.Item.documentMode,
                           ScholiumWorkspaceToolbarController.Item.settlement] {
            let command = try #require(item(identifier, in: toolbar))
            #expect(!controller.validateToolbarItem(command))
            #expect(!command.isEnabled)
            if let menu = command.menuFormRepresentation { #expect(!controller.validateMenuItem(menu)) }
        }
        controller.invalidate()
        controller.activateSidebar(.chat)
        #expect(model.shellState.sidebarContent == .triptych)
        #expect(toolbar.delegate == nil)
        #expect(toolbar.items.allSatisfy { $0.action == nil && $0.menuFormRepresentation == nil })
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
        #expect((sidebar.view as? NSSegmentedControl)?.isSelected(forSegment: 0) == true)

        model.shellState.recordLibraryVisibility(false)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }

        #expect((sidebar.view as? NSSegmentedControl)?.isSelected(forSegment: 0) == false)
        controller.invalidate()
        model.shellState.recordLibraryVisibility(true)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        controller.install(in: window)
        #expect((sidebar.view as? NSSegmentedControl)?.isSelected(forSegment: 0) == false)
        #expect((sidebar.view as? NSSegmentedControl)?.isEnabled == false)
        #expect(toolbar.delegate == nil)
    }

    private var inertWindowActions: WorkspaceWindowActions {
        WorkspaceWindowActions(
            setLibraryVisible: { _ in },
            setResearchInspectorVisible: { _ in },
            activateSidebar: { _ in },
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
