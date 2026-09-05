import AppKit
import ScholiumContracts
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
            ScholiumWorkspaceToolbarController.Item.documentInformation,
            in: toolbar
        ))
        #expect(documentInformation.visibilityPriority == .high)
        #expect(documentInformation.label == "Document Information")
        #expect(documentInformation.isBordered)
        #expect(documentInformation.style == .plain)
        #expect(documentInformation.isNavigational)
        #expect(documentInformation.view == nil)
        #expect(!(documentInformation is NSMenuToolbarItem))

        for identifier in [
            ScholiumWorkspaceToolbarController.Item.sidebar,
            ScholiumWorkspaceToolbarController.Item.back,
            ScholiumWorkspaceToolbarController.Item.forward,
            ScholiumWorkspaceToolbarController.Item.documentInformation,
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

        #expect(toolbar.items.allSatisfy {
            $0.itemIdentifier.rawValue != "scholium.toolbar.agentChanges"
        })
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
            showDocumentInformation: {},
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
