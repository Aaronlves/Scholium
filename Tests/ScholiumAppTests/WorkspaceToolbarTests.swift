import AppKit
import Combine
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Workspace toolbar")
@MainActor
struct WorkspaceToolbarTests {
    @Test("Notifications retain their native popover when Focus Layout hides the toolbar")
    func notificationsWithHiddenToolbar() async throws {
        let model = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let split = testSplitViewController()
        let window = testWindow()
        window.contentViewController = split
        window.layoutIfNeeded()
        let controller = ScholiumWorkspaceToolbarController(
            appState: model, windowActions: inertWindowActions, splitViewController: split
        )
        controller.install(in: window)
        window.makeKeyAndOrderFront(nil)
        let toolbar = try #require(window.toolbar)
        toolbar.isVisible = false
        var presentedPopover: NSPopover?
        let observation = NotificationCenter.default.publisher(for: NSPopover.willShowNotification)
            .sink { notification in
                guard let popover = notification.object as? NSPopover,
                    popover.contentViewController is AttentionQueueViewController
                else { return }
                popover.animates = false
                presentedPopover = popover
            }
        defer {
            observation.cancel()
            presentedPopover?.close()
            controller.invalidate()
            window.toolbar = nil
            window.close()
        }

        model.attentionPopoverSession.presentQueue(anchor: .toolbar, workspaceSlot: nil, noteScope: nil)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        let popover = try #require(presentedPopover)
        #expect(popover.isShown)
        #expect(popover.contentViewController?.view.window != nil)
        #expect(!toolbar.isVisible)
        #expect(model.attentionPopoverSession.isPresented(from: .toolbar))
        popover.close()
        #expect(!model.attentionPopoverSession.isPresented(from: .toolbar))
        #expect(!toolbar.isVisible)
    }

    @Test("An invalidated separate toolbar cannot regain commands through native validation")
    func separateToolbarInvalidation() throws {
        let model = WindowModel(workspaceStore: makeTestWorkspaceStore())
        model.isDetachedDocumentWindow = true
        let controller = DetachedDocumentToolbar(model: model)
        let mode = try #require(
            controller.toolbar(
                controller.toolbar, itemForItemIdentifier: .init("mode"), willBeInsertedIntoToolbar: true
            ) as? ScholiumDocumentModeToolbarItem)
        let more = try #require(
            controller.toolbar(
                controller.toolbar, itemForItemIdentifier: .init("more"), willBeInsertedIntoToolbar: true
            ) as? DocumentNoteActionsToolbarItem)
        let retainedMenuCommand = try #require(more.menu.items.first)
        #expect(mode.action != nil && mode.target != nil)
        #expect(!more.menu.items.isEmpty)
        controller.invalidate()
        controller.invalidate()
        mode.validate()
        more.validate()
        #expect(controller.toolbar.delegate == nil)
        #expect(mode.action == nil && mode.target == nil && !mode.isEnabled)
        #expect(mode.menuFormRepresentation == nil)
        #expect(more.menu.items.isEmpty && more.menu.delegate == nil && !more.isEnabled)
        #expect(!more.validateMenuItem(retainedMenuCommand))
        #expect(
            controller.toolbar(
                controller.toolbar, itemForItemIdentifier: .init("mode"), willBeInsertedIntoToolbar: true
            ) == nil)
    }

    @Test("Sidebar modes switch in place and repeating the visible mode collapses it")
    func sidebarModes() {
        let state = WindowShellState()
        #expect(state.sidebarContent == .library && state.libraryVisible)
        #expect(state.activateSidebar(.chat))
        state.recordLibraryVisibility(true)
        #expect(state.sidebarContent == .chat)
        #expect(!state.activateSidebar(.chat))
        state.recordLibraryVisibility(false)
        #expect(state.activateSidebar(.library))
        state.recordLibraryVisibility(true)
        #expect(!state.activateSidebar(.library))
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
        #expect(window.appearance?.name == NSApplication.shared.effectiveAppearance.name)
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
        let apparatusStart = try #require(
            content.range(
                of: "private var apparatusRegion: some View {"
            ))
        let detailStart = try #require(
            content.range(
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
        #expect(window.toolbarStyle == .unified)
        #expect(!toolbar.allowsDisplayModeCustomization)
        #expect(toolbar.itemIdentifiers == ScholiumWorkspaceToolbarController.itemIdentifiers(tabIdentifiers: []))
        let notifications = try #require(
            item(ScholiumWorkspaceToolbarController.Item.notifications, in: toolbar)
        )
        #expect(notifications.image?.accessibilityDescription != notifications.label)
        let modeIndex = try #require(toolbar.itemIdentifiers.firstIndex(of: ScholiumWorkspaceToolbarController.Item.documentMode))
        #expect(toolbar.itemIdentifiers[modeIndex + 1] == ScholiumWorkspaceToolbarController.Item.noteActions)
        let noteActions = try #require(item(ScholiumWorkspaceToolbarController.Item.noteActions, in: toolbar) as? DocumentNoteActionsToolbarItem)
        #expect(!noteActions.showsIndicator)
        #expect(!noteActions.isEnabled)
        #expect(noteActions.label == "Note Actions")
        #expect(noteActions.visibilityPriority == .standard)
        #expect(noteActions.image?.accessibilityDescription != noteActions.label)
        #expect(noteActions.menuFormRepresentation?.submenu === noteActions.menu)

        #expect(window.titleVisibility == .hidden)

        for identifier in [
            ScholiumWorkspaceToolbarController.Item.back,
            ScholiumWorkspaceToolbarController.Item.forward,
            ScholiumWorkspaceToolbarController.Item.viewChanges,
            ScholiumWorkspaceToolbarController.Item.documentMode,
            ScholiumWorkspaceToolbarController.Item.inspector,
        ] {
            let command = try #require(item(identifier, in: toolbar))
            let expectedTarget: AnyObject = command is ScholiumDocumentModeToolbarItem ? command : controller
            #expect(command.target === expectedTarget)
            #expect(command.action != nil)
            let coreDocumentCommand = [
                ScholiumWorkspaceToolbarController.Item.back,
                ScholiumWorkspaceToolbarController.Item.forward,
                ScholiumWorkspaceToolbarController.Item.documentMode,
                ScholiumWorkspaceToolbarController.Item.inspector,
            ].contains(identifier)
            #expect(command.visibilityPriority == (coreDocumentCommand ? .user : .standard))
            #expect(command.isBordered)
            #expect(command.style == .plain)
            #expect(command.view == nil)
            #expect(command.image?.accessibilityDescription != command.label)
            let overflowCommand = try #require(command.menuFormRepresentation)
            #expect(overflowCommand.target === expectedTarget)
            #expect(overflowCommand.action == command.action)
            #expect(overflowCommand.image != nil)
        }

        let documentMode = try #require(
            item(
                ScholiumWorkspaceToolbarController.Item.documentMode,
                in: toolbar
            ))
        #expect(documentMode.label.hasPrefix("Document Mode,"))
        #expect(documentMode.possibleLabels.count == 3)

        let sidebar = try #require(
            item(
                ScholiumWorkspaceToolbarController.Item.sidebar,
                in: toolbar
            ))
        let selector = try #require(sidebar.view as? ScholiumSidebarModeControl)
        #expect(selector.segmentStyle == .rounded)
        #expect(selector.selectedSegmentBezelColor == nil)
        #expect(selector.trackingMode == .selectOne)
        #expect(selector.segmentCount == 2)
        #expect(selector.image(forSegment: 0) != nil)
        #expect(selector.image(forSegment: 1) != nil)
        #expect(selector.isSelected(forSegment: 0))
        #expect(!selector.isSelected(forSegment: 1))
        #expect(!selector.isEnabled(forSegment: 1))
        #expect(
            selector.segmentToolTipMessages == [
                ScholiumL10n.string("Library"),
                String(localized: "No Triptych Open"),
            ])

        let inspector = try #require(
            item(
                ScholiumWorkspaceToolbarController.Item.inspector,
                in: toolbar
            ))
        let inspectorModes = try #require(
            item(
                ScholiumWorkspaceToolbarController.Item.inspectorModes,
                in: toolbar
            ))
        let modeControl = try #require(inspectorModes.view as? ScholiumTooltippedSegmentedControl)
        #expect(ResearchInspectorMode.allCases == [.links, .related])
        #expect(modeControl.segmentCount == 2)
        #expect(modeControl.segmentDistribution == .fillEqually)
        #expect(
            modeControl.segmentToolTipMessages == [
                ScholiumL10n.localized(ResearchInspectorMode.links.interfaceTitleResource),
                ScholiumL10n.localized(ResearchInspectorMode.related.interfaceTitleResource),
            ])
        #expect(inspectorModes.menuFormRepresentation?.submenu?.items.count == 2)
        #expect(
            inspector.possibleLabels == [
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

        #expect(
            toolbar.items.allSatisfy {
                $0.itemIdentifier.rawValue != "scholium.toolbar.agentChanges"
            })

        // System validation must not re-enable commands merely because their
        // target implements an action. This previously caused state flicker.
        toolbar.validateVisibleItems()
        for identifier in [
            ScholiumWorkspaceToolbarController.Item.back,
            ScholiumWorkspaceToolbarController.Item.forward,
            ScholiumWorkspaceToolbarController.Item.inspector,
            ScholiumWorkspaceToolbarController.Item.documentMode,
            ScholiumWorkspaceToolbarController.Item.viewChanges,
        ] {
            let command = try #require(item(identifier, in: toolbar))
            #expect(!controller.validateToolbarItem(command))
            #expect(!command.isEnabled)
            if let menu = command.menuFormRepresentation { #expect(!controller.validateMenuItem(menu)) }
        }
        controller.invalidate()
        controller.activateSidebar(.chat)
        #expect(model.shellState.sidebarContent == .library)
        #expect(toolbar.delegate == nil)
        for command in toolbar.items {
            #expect(command.action == nil && command.target == nil && !command.isEnabled)
            if let noteActions = command as? DocumentNoteActionsToolbarItem {
                #expect(noteActions.menu.items.isEmpty && noteActions.menu.delegate == nil)
                let overflow = try #require(noteActions.menuFormRepresentation)
                #expect(overflow.submenu === noteActions.menu)
                #expect(overflow.submenu?.items.isEmpty == true)
            } else {
                #expect(command.menuFormRepresentation == nil)
            }
        }
    }

    @Test("Toolbar tabs retain item and command identities as membership and order change")
    func toolbarTabsUpdateIncrementally() async throws {
        let model = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let split = testSplitViewController()
        let window = testWindow()
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1_180, height: 720))
        let controller = ScholiumWorkspaceToolbarController(
            appState: model, windowActions: inertWindowActions,
            splitViewController: split
        )
        controller.install(in: window)
        window.orderFront(nil)
        defer {
            controller.invalidate()
            window.close()
        }

        let toolbar = try #require(window.toolbar)
        let back = try #require(item(ScholiumWorkspaceToolbarController.Item.back, in: toolbar))
        let mode = try #require(item(ScholiumWorkspaceToolbarController.Item.documentMode, in: toolbar))
        let firstDocument = WindowSelectedDocument.unavailable(vaultID: UUID(), relativePath: "First.md")
        let secondDocument = WindowSelectedDocument.unavailable(vaultID: UUID(), relativePath: "Second.md")
        model.documentTabController.activate(
            document: firstDocument, title: "First", toolTip: "First.md", placement: .newTab
        )
        await Task.yield()
        #expect(toolbar.items.compactMap { $0 as? DocumentToolbarTabItem }.isEmpty)
        model.documentTabController.activate(
            document: secondDocument, title: "Second", toolTip: "Second.md", placement: .newTab
        )
        await Task.yield()
        let tabItems = toolbar.items.compactMap { $0 as? DocumentToolbarTabItem }
        #expect(tabItems.count == 1)
        let group = try #require(tabItems.first)
        let firstID = try #require(model.documentTabController.tabs.first?.id)
        let secondID = try #require(model.documentTabController.tabs.last?.id)
        let first = try #require(group.control.control(for: firstID))
        let second = try #require(group.control.control(for: secondID))
        window.layoutIfNeeded()
        group.control.layoutSubtreeIfNeeded()
        #expect(group.control.contextEventMonitor != nil)
        let tabLocation = first.convert(NSPoint(x: first.bounds.midX, y: first.bounds.midY), to: nil)
        func contextEvent(
            _ type: NSEvent.EventType, location: NSPoint, windowNumber: Int,
            modifiers: NSEvent.ModifierFlags = []
        ) throws -> NSEvent {
            try #require(
                NSEvent.mouseEvent(
                    with: type, location: location, modifierFlags: modifiers,
                    timestamp: 0, windowNumber: windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1
                ))
        }
        let rightClick = try contextEvent(.rightMouseDown, location: tabLocation, windowNumber: window.windowNumber)
        let tabMenu = try #require(group.control.contextMenu(for: rightClick))
        #expect(tabMenu.items.map(\.title) == ["Move to Separate Window", "Close Tab"])
        #expect(tabMenu.items.allSatisfy { ($0.representedObject as? UUID) == firstID })
        let controlClick = try contextEvent(
            .leftMouseDown, location: tabLocation, windowNumber: window.windowNumber,
            modifiers: [.control]
        )
        #expect(group.control.contextMenu(for: controlClick) != nil)
        let plainClick = try contextEvent(.leftMouseDown, location: tabLocation, windowNumber: window.windowNumber)
        #expect(group.control.contextMenu(for: plainClick) == nil)
        let outside = try contextEvent(.rightMouseDown, location: .zero, windowNumber: window.windowNumber)
        #expect(group.control.contextMenu(for: outside) == nil)
        #expect(group.visibilityPriority == .high)
        #expect(group.control.orderedTabIDs == [firstID, secondID])
        #expect(group.menuFormRepresentation?.submenu?.items.map(\.title) == ["First", "Second"])
        #expect(group.menuFormRepresentation?.submenu?.items.map(\.state) == [.off, .on])
        let forwardIndex = try #require(toolbar.itemIdentifiers.firstIndex(of: ScholiumWorkspaceToolbarController.Item.forward))
        #expect(toolbar.itemIdentifiers[forwardIndex + 1] == group.itemIdentifier)
        #expect(toolbar.itemIdentifiers[forwardIndex + 2] == ScholiumWorkspaceToolbarController.Item.viewChanges)

        let originalPreferredWidth = first.intrinsicContentSize.width
        let originalGroupWidth = group.control.frame.width
        model.documentTabController.updateDocumentProjection(
            firstDocument,
            title: "A Long English Research Note About the Reading Lifecycle",
            toolTip: "Full long Note title"
        )
        await Task.yield()
        #expect(first.intrinsicContentSize.width == originalPreferredWidth)
        #expect(group.control.frame.width == originalGroupWidth)
        #expect(first.tab.toolTip == "Full long Note title")

        model.documentTabController.moveTab(withID: secondID, to: 0)
        await Task.yield()
        #expect(toolbar.itemIdentifiers[forwardIndex + 1] == group.itemIdentifier)
        #expect(toolbar.items.first { $0.itemIdentifier == group.itemIdentifier } === group)
        #expect(group.control.orderedTabIDs == [secondID, firstID])
        #expect(group.control.control(for: firstID) === first)
        #expect(group.control.control(for: secondID) === second)
        #expect(group.menuFormRepresentation?.submenu?.items.map(\.title) == ["Second", "A Long English Research Note About the Reading Lifecycle"])
        #expect(item(ScholiumWorkspaceToolbarController.Item.back, in: toolbar) === back)
        #expect(item(ScholiumWorkspaceToolbarController.Item.documentMode, in: toolbar) === mode)

        model.documentTabController.removeTabs(withIDs: [firstID])
        await Task.yield()
        #expect(toolbar.items.compactMap { $0 as? DocumentToolbarTabItem }.isEmpty)
        #expect(item(ScholiumWorkspaceToolbarController.Item.back, in: toolbar) === back)
        #expect(item(ScholiumWorkspaceToolbarController.Item.documentMode, in: toolbar) === mode)
        controller.invalidate()
        #expect(group.control.contextEventMonitor == nil)
    }

    @Test("Document tabs remain attached to their own window when another window changes membership")
    func toolbarTabsDoNotSynchronizeAcrossWindows() async throws {
        let firstModel = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let secondModel = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let firstSplit = testSplitViewController()
        let secondSplit = testSplitViewController()
        let firstWindow = testWindow()
        let secondWindow = testWindow()
        firstWindow.contentViewController = firstSplit
        secondWindow.contentViewController = secondSplit
        firstWindow.setContentSize(NSSize(width: 1_180, height: 720))
        secondWindow.setContentSize(NSSize(width: 1_180, height: 720))
        let firstController = ScholiumWorkspaceToolbarController(
            appState: firstModel, windowActions: inertWindowActions,
            splitViewController: firstSplit
        )
        let secondController = ScholiumWorkspaceToolbarController(
            appState: secondModel, windowActions: inertWindowActions,
            splitViewController: secondSplit
        )
        firstController.install(in: firstWindow)
        firstWindow.orderFront(nil)
        defer {
            firstController.invalidate()
            secondController.invalidate()
            firstWindow.close()
            secondWindow.close()
        }

        for title in ["First", "Second"] {
            firstModel.documentTabController.activate(
                document: .unavailable(vaultID: UUID(), relativePath: "\(title).md"),
                title: title, toolTip: title, placement: .newTab
            )
        }
        await Task.yield()
        let firstToolbar = try #require(firstWindow.toolbar)
        let firstGroup = try #require(firstToolbar.items.compactMap { $0 as? DocumentToolbarTabItem }.first)
        let firstOrder = firstGroup.control.orderedTabIDs
        #expect(firstOrder.count == 2)
        #expect(firstGroup.control.window === firstWindow)

        secondController.install(in: secondWindow)
        secondWindow.orderFront(nil)
        await Task.yield()
        let secondToolbar = try #require(secondWindow.toolbar)
        #expect(firstToolbar.identifier != secondToolbar.identifier)
        #expect(secondToolbar.items.compactMap { $0 as? DocumentToolbarTabItem }.isEmpty)
        #expect(firstToolbar.items.first { $0 === firstGroup } === firstGroup)
        #expect(firstGroup.control.window === firstWindow)

        for title in ["Other First", "Other Second"] {
            secondModel.documentTabController.activate(
                document: .unavailable(vaultID: UUID(), relativePath: "\(title).md"),
                title: title, toolTip: title, placement: .newTab
            )
        }
        await Task.yield()
        let secondGroup = try #require(secondToolbar.items.compactMap { $0 as? DocumentToolbarTabItem }.first)
        #expect(secondGroup !== firstGroup)
        #expect(secondGroup.control.window === secondWindow)
        secondModel.documentTabController.removeTabs(withIDs: [try #require(secondModel.documentTabController.tabs.first?.id)])
        await Task.yield()
        #expect(secondToolbar.items.compactMap { $0 as? DocumentToolbarTabItem }.isEmpty)
        #expect(firstToolbar.items.first { $0 === firstGroup } === firstGroup)
        #expect(firstGroup.control.window === firstWindow)
        #expect(firstGroup.control.orderedTabIDs == firstOrder)
        #expect(firstModel.documentTabController.selectedTabID == firstOrder.last)
    }

    @Test("A toolbar tab cannot appear selected before document activation commits")
    func toolbarTabSelectionWaitsForCommit() throws {
        let first = DocumentTabItem(
            document: .unavailable(vaultID: UUID(), relativePath: "First.md"),
            title: "First", toolTip: "First.md"
        )
        let second = DocumentTabItem(
            document: .unavailable(vaultID: UUID(), relativePath: "Second.md"),
            title: "Second", toolTip: "Second.md"
        )
        let projection = DocumentToolbarTabs()
        var requested: UUID?
        projection.select = { requested = $0 }
        projection.update(tabs: [first, second], selectedID: first.id)
        let group = try #require(projection.item(for: DocumentToolbarTabItem.identifier))
        let firstControl = try #require(projection.control(for: first.id))
        let secondControl = try #require(projection.control(for: second.id))
        func tabButton(in view: NSView) -> DocumentToolbarTabButton? {
            if let button = view as? DocumentToolbarTabButton { return button }
            return view.subviews.lazy.compactMap { tabButton(in: $0) }.first
        }
        let firstButton = try #require(tabButton(in: firstControl))
        let secondButton = try #require(tabButton(in: secondControl))
        let firstGlass = try #require(firstControl.subviews.first { $0 is NSGlassEffectView } as? NSGlassEffectView)
        let secondGlass = try #require(secondControl.subviews.first { $0 is NSGlassEffectView } as? NSGlassEffectView)
        let firstContent = try #require(firstGlass.contentView)
        let secondContent = try #require(secondButton.superview)
        let firstClose = try #require(firstContent.subviews.first { $0 is NSButton && $0 !== firstButton })
        let secondClose = try #require(secondContent.subviews.first { $0 is NSButton && $0 !== secondButton })
        #expect(!group.isBordered && group.control.material == .titlebar)
        #expect(group.control.orderedTabIDs == [first.id, second.id])
        #expect(firstControl.superview === secondControl.superview)
        #expect(firstControl.subviews.allSatisfy { !($0 is NSVisualEffectView) })
        #expect(secondControl.subviews.allSatisfy { !($0 is NSVisualEffectView) })
        #expect(!firstGlass.isHidden && secondGlass.isHidden)
        #expect(firstGlass.tintColor == nil)
        #expect(firstContent.subviews.contains { $0 === firstButton })
        #expect(firstContent.subviews.contains { $0 === firstClose })
        #expect(secondContent.subviews.contains { $0 === secondButton })
        #expect(secondContent.subviews.contains { $0 === secondClose })
        #expect(firstButton.state == .on && secondButton.state == .off)
        let overflowMenuBeforeUnchangedUpdate = group.menuFormRepresentation
        projection.update(tabs: [first, second], selectedID: first.id)
        #expect(group.menuFormRepresentation === overflowMenuBeforeUnchangedUpdate)
        #expect(projection.control(for: first.id) === firstControl)
        #expect(projection.control(for: second.id) === secondControl)
        secondButton.performClick(nil)
        #expect(requested == second.id)
        #expect(firstButton.state == .on && secondButton.state == .off)
        #expect(!firstGlass.isHidden && secondGlass.isHidden)
        #expect(firstGlass.contentView === firstContent)
        #expect(secondContent.superview === secondControl)
        let window = testWindow()
        window.contentView?.addSubview(group.control)
        group.control.frame = NSRect(x: 20, y: 20, width: 400, height: DocumentToolbarTabStrip.height)
        defer { window.close() }
        group.control.layoutSubtreeIfNeeded()
        #expect(firstButton.frame.width > 0 && firstClose.frame.width > 0)
        #expect(firstButton.superview === firstGlass.contentView)
        #expect(firstContent.frame.size == firstGlass.bounds.size)
        #expect(firstControl.frame.height == DocumentToolbarTabStrip.contentHeight)
        #expect(abs(firstClose.frame.midY - firstContent.bounds.midY) < 0.5)
        for (control, id) in [(firstControl, first.id), (secondControl, second.id)] {
            let location = control.convert(
                NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil
            )
            let event = try #require(
                NSEvent.mouseEvent(
                    with: .rightMouseDown, location: location, modifierFlags: [],
                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1
                ))
            let menu = try #require(group.control.menu(for: event))
            #expect(menu.items.map(\.title) == ["Move to Separate Window", "Close Tab"])
            #expect(menu.items.allSatisfy { ($0.representedObject as? UUID) == id })
        }
        #expect(window.makeFirstResponder(firstButton))
        projection.update(tabs: [first, second], selectedID: second.id)
        #expect(firstButton.state == .off && secondButton.state == .on)
        #expect(firstGlass.contentView !== firstContent)
        #expect(firstContent.superview === firstControl)
        #expect(secondGlass.contentView === secondContent)
        #expect(secondButton.superview === secondContent && secondClose.superview === secondContent)
        #expect(firstGlass.isHidden && !secondGlass.isHidden)
        #expect(window.firstResponder === firstButton)
        group.control.layoutSubtreeIfNeeded()
        #expect(secondButton.frame.width > 0 && secondClose.frame.width > 0)
        #expect(secondContent.frame.size == secondGlass.bounds.size)
        projection.update(tabs: [first, second], selectedID: first.id)
        group.control.layoutSubtreeIfNeeded()
        #expect(firstGlass.contentView === firstContent)
        #expect(firstButton.superview === firstContent && firstClose.superview === firstContent)
        #expect(firstButton.frame.width > 0 && firstClose.frame.width > 0)
        #expect(window.firstResponder === firstButton)
        #expect(tabButton(in: firstControl) === firstButton)
        #expect(tabButton(in: secondControl) === secondButton)
        #expect(secondButton.accessibilityLabel() == second.title)
        #expect(firstButton.accessibilityValue() as? Int == 1)
        #expect(secondButton.accessibilityCustomActions()?.contains { $0.name == "Close Tab" } == true)
        projection.invalidate()
    }

    @Test("The shared tab well divides available space equally, then favors a crowded selection")
    func toolbarTabStripCompressionAndScroll() throws {
        let tabs = (0..<5).map { index in
            DocumentTabItem(
                document: .unavailable(vaultID: UUID(), relativePath: "\(index).md"),
                title: "A Long Research Document Title \(index)", toolTip: "Full title \(index)"
            )
        }
        let projection = DocumentToolbarTabs()
        let group = try #require(projection.item(for: DocumentToolbarTabItem.identifier))
        let window = testWindow()
        window.contentView?.addSubview(group.control)
        group.control.frame = NSRect(x: 20, y: 20, width: 520, height: DocumentToolbarTabStrip.height)
        defer {
            projection.invalidate()
            window.close()
        }
        let scrollView = try #require(group.control.subviews.first { $0 is NSScrollView } as? NSScrollView)

        projection.update(tabs: Array(tabs.prefix(3)), selectedID: tabs[2].id)
        group.control.layoutSubtreeIfNeeded()
        let threeControls = try tabs.prefix(3).map { tab in
            try #require(projection.control(for: tab.id))
        }
        let visibleThree = scrollView.contentView.documentVisibleRect
        #expect(threeControls.allSatisfy { $0.frame.width >= DocumentToolbarTabControl.minimumWidth })
        #expect(threeControls.allSatisfy { $0.frame.minX >= visibleThree.minX && $0.frame.maxX <= visibleThree.maxX })
        #expect(abs(threeControls[2].frame.width - threeControls[0].frame.width) < 1)
        #expect(abs(threeControls[2].frame.width - threeControls[1].frame.width) < 1)

        let fourTabs = Array(tabs.prefix(4))
        group.control.frame.size.width = 900
        projection.update(tabs: fourTabs, selectedID: tabs[3].id)
        group.control.layoutSubtreeIfNeeded()
        let active = try #require(projection.control(for: tabs[3].id))
        let inactive = try fourTabs.prefix(3).map { try #require(projection.control(for: $0.id)) }
        #expect(inactive.allSatisfy { abs($0.frame.width - active.frame.width) < 1 })

        func widths(at stripWidth: CGFloat, selectedID: UUID) -> [CGFloat] {
            group.control.frame.size.width = stripWidth
            projection.update(tabs: fourTabs, selectedID: selectedID)
            group.control.layoutSubtreeIfNeeded()
            return fourTabs.compactMap { projection.control(for: $0.id)?.frame.width }
        }
        let atEqualBoundary = widths(at: 746, selectedID: tabs[3].id)
        let justCrowded = widths(at: 745, selectedID: tabs[3].id)
        let restoredEqual = widths(at: 746, selectedID: tabs[3].id)
        let fixedOverhead = 746 - atEqualBoundary.reduce(0, +)
        func totalWidthIsConserved(_ values: [CGFloat], stripWidth: CGFloat) -> Bool {
            abs(values.reduce(0, +) + fixedOverhead - stripWidth) < 2
        }
        #expect(atEqualBoundary.count == 4 && justCrowded.count == 4)
        #expect(zip(atEqualBoundary, justCrowded).allSatisfy { abs($0.0 - $0.1) < 2 })
        #expect(zip(atEqualBoundary, restoredEqual).allSatisfy { abs($0.0 - $0.1) < 1 })
        #expect(totalWidthIsConserved(justCrowded, stripWidth: 745))
        #expect(justCrowded.allSatisfy { $0 >= DocumentToolbarTabControl.minimumWidth && $0.isFinite })

        let aboveMinimum = widths(at: 543, selectedID: tabs[3].id)
        let belowInactiveMinimum = widths(at: 541, selectedID: tabs[3].id)
        let allMinimum = widths(at: 474, selectedID: tabs[3].id)
        let justAboveMinimum = widths(at: 475, selectedID: tabs[3].id)
        #expect(zip(aboveMinimum, belowInactiveMinimum).allSatisfy { abs($0.0 - $0.1) < 3 })
        #expect(zip(allMinimum, justAboveMinimum).allSatisfy { abs($0.0 - $0.1) < 2 })
        #expect(totalWidthIsConserved(belowInactiveMinimum, stripWidth: 541))
        #expect(totalWidthIsConserved(allMinimum, stripWidth: 474))
        #expect(justAboveMinimum.allSatisfy { $0 >= DocumentToolbarTabControl.minimumWidth && $0.isFinite })

        let selectedLast = widths(at: 708, selectedID: tabs[3].id)
        let selectedFirst = widths(at: 708, selectedID: tabs[0].id)
        #expect(selectedLast[3] > selectedLast[0])
        #expect(selectedFirst[0] > selectedFirst[3])
        #expect(abs(selectedLast.reduce(0, +) - selectedFirst.reduce(0, +)) < 2)
        #expect(totalWidthIsConserved(selectedFirst, stripWidth: 708))

        group.control.frame.size.width = 600
        projection.update(tabs: fourTabs, selectedID: tabs[3].id)
        group.control.layoutSubtreeIfNeeded()
        #expect(inactive.allSatisfy { abs($0.frame.width - inactive[0].frame.width) < 1 })
        #expect(active.frame.width > inactive[0].frame.width)
        let reorderedFour = [fourTabs[3]] + Array(fourTabs.prefix(3))
        projection.update(tabs: reorderedFour, selectedID: tabs[3].id)
        group.control.layoutSubtreeIfNeeded()
        #expect(group.control.orderedTabIDs == reorderedFour.map(\.id))
        #expect(inactive.allSatisfy { abs($0.frame.width - inactive[0].frame.width) < 1 })
        #expect(active.frame.width > inactive[0].frame.width)

        group.control.frame.size.width = 280
        projection.update(tabs: tabs, selectedID: tabs[4].id)
        group.control.layoutSubtreeIfNeeded()
        let last = try #require(projection.control(for: tabs[4].id))
        #expect(
            tabs.allSatisfy { tab in
                guard let control = projection.control(for: tab.id) else { return false }
                return abs(control.frame.width - DocumentToolbarTabControl.minimumWidth) < 1
            })
        let selectedVisible = scrollView.contentView.documentVisibleRect
        #expect(last.frame.minX >= selectedVisible.minX - 1)
        #expect(last.frame.maxX <= selectedVisible.maxX + 1)

        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        let browsedPosition = scrollView.contentView.documentVisibleRect.minX
        #expect(last.frame.minX > scrollView.contentView.documentVisibleRect.maxX)
        projection.update(tabs: tabs, selectedID: tabs[4].id)
        group.control.layoutSubtreeIfNeeded()
        #expect(abs(scrollView.contentView.documentVisibleRect.minX - browsedPosition) < 1)
        var reordered = tabs
        reordered.swapAt(0, 1)
        projection.update(tabs: reordered, selectedID: tabs[4].id)
        group.control.layoutSubtreeIfNeeded()
        #expect(abs(scrollView.contentView.documentVisibleRect.minX - browsedPosition) < 1)

        projection.update(tabs: reordered, selectedID: reordered[1].id)
        group.control.layoutSubtreeIfNeeded()
        let second = try #require(projection.control(for: reordered[1].id))
        var expanded = reordered
        expanded[0].title = String(repeating: "Long ", count: 20)
        projection.update(tabs: expanded, selectedID: second.tab.id)
        group.control.layoutSubtreeIfNeeded()
        let visibleAfterTitleChange = scrollView.contentView.documentVisibleRect
        #expect(second.frame.minX >= visibleAfterTitleChange.minX - 1)
        #expect(second.frame.maxX <= visibleAfterTitleChange.maxX + 1)
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
        let sidebar = try #require(
            item(
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
            toggleFocusLayout: {},
            canToggleFocusLayout: { false },
            canUseSidebar: { false },
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
        split.addSplitViewItem(
            NSSplitViewItem(
                sidebarWithViewController: NSViewController()
            ))
        split.addSplitViewItem(
            NSSplitViewItem(
                viewController: NSViewController()
            ))
        split.addSplitViewItem(
            NSSplitViewItem(
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
