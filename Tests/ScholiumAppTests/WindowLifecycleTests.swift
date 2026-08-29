import AppKit
import Foundation
import ScholiumContracts
import SwiftUI
import Testing
@testable import ScholiumApp

@Suite("Window lifecycle", .serialized)
@MainActor
struct WindowLifecycleTests {
    @Test("Workspace scene identity survives route restoration")
    func workspaceRouteIdentityRoundTrip() throws {
        let windowID = UUID()
        let route = TriptychWindowRoute(
            windowID: windowID,
            triptychID: UUID()
        )

        let restored = try JSONDecoder().decode(
            TriptychWindowRoute.self,
            from: JSONEncoder().encode(route)
        )

        #expect(restored == route)
        #expect(restored.windowID == windowID)
    }

    @Test("Bootstrap scene identity survives route restoration")
    func bootstrapRouteIdentityRoundTrip() throws {
        let windowID = UUID()
        let route = BootstrapWindowRoute(
            windowID: windowID,
            purpose: .missingRegistration,
            targetTriptychID: UUID()
        )

        let restored = try JSONDecoder().decode(
            BootstrapWindowRoute.self,
            from: JSONEncoder().encode(route)
        )

        #expect(restored == route)
        #expect(restored.windowID == windowID)
    }

    @Test("Readiness is resolved for one exact route identity")
    func exactReadinessIsolation() async {
        let registry = ScholiumWindowLifecycleRegistry()
        let firstID = UUID()
        let secondID = UUID()
        registry.register(id: firstID) {}
        registry.register(id: secondID) {}

        let firstWaiter = Task { @MainActor in
            try await registry.waitUntilReady(id: firstID)
        }
        let secondWaiter = Task { @MainActor in
            try await registry.waitUntilReady(id: secondID)
        }

        registry.markReady(id: secondID)
        do {
            try await secondWaiter.value
        } catch {
            Issue.record("The ready route unexpectedly failed: \(error)")
        }

        registry.markFailed(
            id: firstID,
            error: ScholiumWindowLifecycleError.failed("first route failed")
        )
        do {
            try await firstWaiter.value
            Issue.record("A different route incorrectly satisfied the first waiter")
        } catch let error as ScholiumWindowLifecycleError {
            #expect(error == .failed("first route failed"))
        } catch {
            Issue.record("Unexpected readiness error: \(error)")
        }
    }

    @Test("Unregistering a pending route fails its waiters")
    func unregisterFailsPendingWaiters() async {
        let registry = ScholiumWindowLifecycleRegistry()
        let id = UUID()
        registry.register(id: id) {}
        let waiter = Task { @MainActor in
            try await registry.waitUntilReady(id: id)
        }

        await Task.yield()
        registry.unregister(id: id)

        do {
            try await waiter.value
            Issue.record("A detached route remained pending instead of failing")
        } catch let error as ScholiumWindowLifecycleError {
            #expect(error == .unregisteredBeforeReady)
        } catch {
            Issue.record("Unexpected unregister error: \(error)")
        }
    }

    @Test("A route that detached after readiness cannot satisfy a late waiter")
    func detachedReadyRouteFailsLateWaiter() async {
        let registry = ScholiumWindowLifecycleRegistry()
        let id = UUID()
        registry.register(id: id) {}
        registry.markReady(id: id)
        registry.unregister(id: id)

        do {
            try await registry.waitUntilReady(id: id)
            Issue.record("A closed destination incorrectly satisfied a late waiter")
        } catch let error as ScholiumWindowLifecycleError {
            #expect(error == .unregisteredBeforeReady)
        } catch {
            Issue.record("Unexpected late-waiter error: \(error)")
        }
    }

    @Test("Cancelling readiness removes only that waiter")
    func cancellationIsScopedToOneWaiter() async {
        let registry = ScholiumWindowLifecycleRegistry()
        let id = UUID()
        registry.register(id: id) {}
        let cancelledWaiter = Task { @MainActor in
            try await registry.waitUntilReady(id: id)
        }
        let survivingWaiter = Task { @MainActor in
            try await registry.waitUntilReady(id: id)
        }

        await Task.yield()
        cancelledWaiter.cancel()
        do {
            try await cancelledWaiter.value
            Issue.record("A cancelled readiness waiter unexpectedly succeeded")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }

        registry.markReady(id: id)
        do {
            try await survivingWaiter.value
        } catch {
            Issue.record("Cancelling a peer waiter poisoned this route: \(error)")
        }
    }

    @Test("Route readiness has an injectable nonblocking deadline")
    func readinessDeadlineIsBounded() async {
        var policy = ScholiumLifecyclePolicy()
        policy.routeReadiness = .milliseconds(30)
        let registry = ScholiumWindowLifecycleRegistry(policy: policy)
        let id = UUID()
        registry.register(id: id) {}
        let clock = ContinuousClock()
        let started = clock.now

        do {
            try await registry.waitUntilReady(id: id)
            Issue.record("A route without native content incorrectly became ready")
        } catch let error as ScholiumWindowLifecycleError {
            #expect(error == .timedOut(.routeReadiness))
        } catch {
            Issue.record("Unexpected readiness deadline error: \(error)")
        }
        #expect(started.duration(to: clock.now) < .seconds(1))

        // The timed-out waiter was removed; readiness can still be established
        // for a later, independent routing attempt.
        registry.markReady(id: id)
        do {
            try await registry.waitUntilReady(id: id)
        } catch {
            Issue.record("A timed-out waiter poisoned later route readiness: \(error)")
        }
    }

    @Test("Timeout and caller cancellation ignore late noncooperative lifecycle completion")
    func deadlineRaceResumesOnce() async {
        let timeoutSleeper = ManualLifecycleSuspension()
        let lateOperation = ManualLifecycleSuspension()
        var acceptedOwnerEffects = 0
        let timedAttempt = Task { @MainActor in
            do {
                try await withScholiumLifecycleDeadline(
                    phase: .contentFlush,
                    timeout: .seconds(30),
                    sleep: { _ in await timeoutSleeper.suspendIgnoringCancellation() }
                ) {
                    await lateOperation.suspendIgnoringCancellation()
                }
                acceptedOwnerEffects += 1
                return DeadlineTestOutcome.succeeded
            } catch let error as ScholiumWindowLifecycleError {
                return error == .timedOut(.contentFlush)
                    ? .timedOut
                    : .unexpected
            } catch {
                return .unexpected
            }
        }
        await timeoutSleeper.waitUntilArmed()
        await lateOperation.waitUntilArmed()
        timeoutSleeper.resume()
        #expect(await timedAttempt.value == .timedOut)
        #expect(acceptedOwnerEffects == 0)

        // The operation deliberately ignores cancellation and arrives after
        // the timeout. It cannot resume the parent again or apply owner state.
        lateOperation.resume()
        for _ in 0..<20 { await Task.yield() }
        #expect(acceptedOwnerEffects == 0)

        let cancellationSleeper = ManualLifecycleSuspension()
        let cancelledOperation = ManualLifecycleSuspension()
        let cancelledAttempt = Task { @MainActor in
            try await withScholiumLifecycleDeadline(
                phase: .presentationSnapshot,
                timeout: .seconds(30),
                sleep: { _ in
                    await cancellationSleeper.suspendIgnoringCancellation()
                }
            ) {
                await cancelledOperation.suspendIgnoringCancellation()
            }
        }
        await cancellationSleeper.waitUntilArmed()
        await cancelledOperation.waitUntilArmed()
        cancelledAttempt.cancel()
        await #expect(throws: CancellationError.self) {
            try await cancelledAttempt.value
        }
        cancellationSleeper.resume()
        cancelledOperation.resume()
        for _ in 0..<20 { await Task.yield() }
    }

    @Test("Application flush visits every registered window")
    func flushAllRegisteredWindows() async {
        let registry = ScholiumWindowLifecycleRegistry()
        var flushed: [UUID] = []
        let firstID = UUID()
        let secondID = UUID()
        registry.register(id: firstID) { flushed.append(firstID) }
        registry.register(id: secondID) { flushed.append(secondID) }

        do {
            try await registry.flushAll()
        } catch {
            Issue.record("Registered flushers unexpectedly failed: \(error)")
        }

        #expect(Set(flushed) == Set([firstID, secondID]))
    }

    @Test("A failed application flush still visits the other windows")
    func flushAllContinuesAfterFailure() async {
        let registry = ScholiumWindowLifecycleRegistry()
        let failingID = UUID()
        let survivingID = UUID()
        var didVisitSurvivingWindow = false
        registry.register(id: failingID) {
            throw ScholiumWindowLifecycleError.failed("save failed")
        }
        registry.register(id: survivingID) {
            didVisitSurvivingWindow = true
        }

        do {
            try await registry.flushAll()
            Issue.record("A failed window flush did not fail termination")
        } catch let error as ScholiumWindowLifecycleError {
            #expect(error == .failed("save failed"))
        } catch {
            Issue.record("Unexpected aggregate flush error: \(error)")
        }
        #expect(didVisitSurvivingWindow)
    }

    @Test("Cancelled application termination preserves successful window flush ownership")
    func cancelledTerminationPreservesFlushOwnership() async {
        let registry = ScholiumWindowLifecycleRegistry()
        let successfulWindow = WindowModel(
            workspaceStore: makeTestWorkspaceStore()
        )
        successfulWindow.documentController.selectUnavailableDocument(
            vaultID: UUID(),
            relativePath: "Still Open.md"
        )
        var successfulFlushCount = 0
        successfulWindow.registerEditorFlush(
            for: "Still Open.md",
            token: UUID(),
            flush: { successfulFlushCount += 1 },
            captureForReconstruction: {}
        )
        let peer = TerminationFailureProbe()
        registry.register(id: UUID()) {
            _ = try await successfulWindow.windowCloseCoordinator.prepare()
        }
        registry.register(id: UUID()) {
            if peer.shouldFail {
                throw ScholiumWindowLifecycleError.failed("peer save failed")
            }
        }

        do {
            try await registry.flushAll()
            Issue.record("A failed peer unexpectedly allowed application termination")
        } catch {
            // Expected: the application remains open.
        }
        #expect(successfulFlushCount == 1)

        peer.shouldFail = false
        do {
            try await registry.flushAll()
        } catch {
            Issue.record("A later termination attempt unexpectedly failed: \(error)")
        }
        #expect(successfulFlushCount == 2)
        successfulWindow.windowCloseCoordinator.finalize()
    }

    @Test("A hanging window flush is bounded and does not starve a healthy peer")
    func hangingFlushIsBoundedAndPeerStillRuns() async {
        var policy = ScholiumLifecyclePolicy()
        policy.contentFlush = .milliseconds(30)
        policy.applicationTermination = .milliseconds(200)
        let registry = ScholiumWindowLifecycleRegistry(policy: policy)
        var didFlushHealthyWindow = false
        registry.register(id: UUID()) {
            await withUnsafeContinuation {
                (_: UnsafeContinuation<Void, Never>) in
            }
        }
        registry.register(id: UUID()) {
            didFlushHealthyWindow = true
        }
        let clock = ContinuousClock()
        let started = clock.now

        do {
            try await registry.flushAll()
            Issue.record("A hanging window incorrectly allowed termination")
        } catch let error as ScholiumWindowLifecycleError {
            #expect(error == .timedOut(.contentFlush))
        } catch {
            Issue.record("Unexpected bounded flush error: \(error)")
        }

        #expect(didFlushHealthyWindow)
        #expect(started.duration(to: clock.now) < .seconds(1))
    }

    @Test("Presentation detach preserves the native close delegate until terminal teardown")
    func delegateRetentionUntilClose() throws {
        let id = UUID()
        let registry = ScholiumWindowLifecycleRegistry()
        let model = WindowModel(
            workspaceStore: makeTestWorkspaceStore(),
            nativeWindowID: id
        )
        let coordinator = WorkspaceWindowCoordinator(
            windowID: id,
            appState: model,
            lifecycleRegistry: registry
        )
        let window = testWindow()
        var priorDelegate: TestWindowDelegate? = TestWindowDelegate()
        let retainedDelegate = WeakReference(priorDelegate)
        window.delegate = priorDelegate

        coordinator.attach(to: window)
        priorDelegate = nil
        #expect(retainedDelegate.value != nil)
        #expect(window.delegate === coordinator)

        let expectedDelegate = try #require(retainedDelegate.value)
        coordinator.detach()
        #expect(window.delegate === coordinator)

        coordinator.windowWillClose(Notification(
            name: NSWindow.willCloseNotification,
            object: window
        ))
        #expect(expectedDelegate.didReceiveWindowWillClose)
    }

    @Test("Changing a window Triptych clears transient notification prompts")
    func triptychReassignmentClearsResearchNotificationState() throws {
        let windowID = UUID()
        let firstTriptychID = UUID()
        let secondTriptychID = UUID()
        let model = WindowModel(
            workspaceStore: makeTestWorkspaceStore(),
            nativeWindowID: windowID
        )
        let notificationCoordinator = ResearchResultNotificationCoordinator(
            systemNotifications: WindowLifecycleNotificationSystem(),
            userDefaults: UserDefaults(
                suiteName: "WindowLifecycleTests.\(UUID())"
            )!,
            applicationIsActive: { true }
        )
        let coordinator = WorkspaceWindowCoordinator(
            windowID: windowID,
            appState: model,
            lifecycleRegistry: ScholiumWindowLifecycleRegistry(),
            researchResultNotificationCoordinator: notificationCoordinator
        )
        coordinator.updateResearchRecordsRouting(triptychID: firstTriptychID)
        model.shellState.presentResearchNotificationPermissionNotice(.enable)

        coordinator.updateResearchRecordsRouting(triptychID: secondTriptychID)

        #expect(model.shellState.researchNotificationPermissionNotice == nil)
    }

    @Test("Native window close releases its Agent permission claim before teardown")
    func nativeCloseReleasesResearchAgentPermissionClaim() throws {
        let windowID = UUID()
        let triptychID = UUID()
        let store = makeTestWorkspaceStore()
        let model = WindowModel(
            workspaceStore: store,
            nativeWindowID: windowID
        )
        let request = try makeTestWriteSetExtensionRecord(
            triptychID: triptychID
        )
        model.researchAgentPermissionWindowController.registerWindowEndpoint(
            activeTriptychID: { triptychID },
            isKeyWindow: { true },
            canPresent: { model.presentationRouter.sheet == nil },
            willPresent: {},
            focus: {}
        )
        store.researchAgentPermissionClaims.receive(
            .writeSetExtension(request),
            intent: .submit
        )
        #expect(model.researchAgentPermissionWindowController.claim?.id == request.id)

        let registry = ScholiumWindowLifecycleRegistry()
        let coordinator = WorkspaceWindowCoordinator(
            windowID: windowID,
            appState: model,
            lifecycleRegistry: registry
        )
        let window = testWindow()
        let priorDelegate = TestWindowDelegate()
        window.delegate = priorDelegate
        coordinator.attach(to: window)

        coordinator.windowWillClose(Notification(
            name: NSWindow.willCloseNotification,
            object: window
        ))

        #expect(model.researchAgentPermissionWindowController.claim == nil)
        #expect(model.presentationRouter.sheet == nil)
        #expect(priorDelegate.didReceiveWindowWillClose)
    }

    @Test("Workspace readiness requires the exact attached window and split")
    func coordinatorMarksExactNativeBoundaryReady() async {
        let id = UUID()
        let registry = ScholiumWindowLifecycleRegistry()
        let model = WindowModel(
            workspaceStore: makeTestWorkspaceStore(),
            nativeWindowID: id
        )
        let coordinator = WorkspaceWindowCoordinator(
            windowID: id,
            appState: model,
            lifecycleRegistry: registry
        )
        let split = TestWorkspaceSplitController()
        let window = testWindow()
        window.contentViewController = split

        coordinator.attach(to: window)
        coordinator.attach(splitController: split)

        do {
            try await registry.waitUntilReady(id: id)
        } catch {
            Issue.record("The exact native window boundary did not become ready: \(error)")
        }
        coordinator.detach()
    }

    @Test("Split state mirrors native collapse and keeps two windows isolated")
    func splitVisibilityMirroringAndIsolation() {
        var firstLibraryChanges: [Bool] = []
        var firstInspectorChanges: [Bool] = []
        let first = makeWorkspaceSplit(
            libraryChanges: { firstLibraryChanges.append($0) },
            inspectorChanges: { firstInspectorChanges.append($0) }
        )
        var secondLibraryChanges: [Bool] = []
        let second = makeWorkspaceSplit(
            libraryChanges: { secondLibraryChanges.append($0) },
            inspectorChanges: { _ in }
        )

        #expect(first.splitViewItems[0].canCollapseFromWindowResize)
        #expect(!first.splitViewItems[1].canCollapse)
        #expect(!first.splitViewItems[1].canCollapseFromWindowResize)
        #expect(!first.splitViewItems[2].canCollapse)

        first.setLibraryVisible(false, animated: false)
        first.setResearchInspectorVisible(true, animated: false)
        #expect(first.libraryIsVisible == false)
        #expect(first.researchInspectorIsVisible)
        #expect(firstLibraryChanges.last == false)
        #expect(firstInspectorChanges.last == true)
        #expect(second.libraryIsVisible)
        #expect(secondLibraryChanges.last == true)

        first.splitViewItems[0].isCollapsed = false
        first.splitViewDidResizeSubviews(Notification(name: NSSplitView.didResizeSubviewsNotification))
        #expect(firstLibraryChanges.last == true)
    }

    @Test("Research Inspector collapse resizes Document inside a fixed workspace frame")
    func researchInspectorCollapseKeepsWorkspaceFrameFixed() throws {
        let controller = makeWorkspaceSplit(
            libraryChanges: { _ in },
            inspectorChanges: { _ in }
        )

        let inspectorItem = try #require(controller.splitViewItems.last)
        #expect(!inspectorItem.canCollapse)
        #expect(
            inspectorItem.collapseBehavior
                == .preferResizingSiblingsWithFixedSplitView
        )
        controller.setResearchInspectorVisible(true, animated: false)
        #expect(!inspectorItem.isCollapsed)
        controller.setResearchInspectorVisible(false, animated: false)
        #expect(inspectorItem.isCollapsed)
        controller.setResearchInspectorVisible(true, animated: false)
        #expect(!inspectorItem.isCollapsed)
    }

    @Test("Workspace split leaves compression priorities to AppKit")
    func workspaceSplitUsesNativeCompressionPriorities() throws {
        let controller = ScholiumWorkspaceSplitView<Text, Text, Text>.Controller(
            initialLibraryVisible: true,
            initialApparatusVisible: true,
            documentTabs: [],
            selectedDocumentTabID: nil,
            selectDocumentTab: { _ in },
            closeDocumentTab: { _ in },
            libraryVisibilityDidChange: { _ in },
            researchInspectorVisibilityDidChange: { _ in },
            splitControllerDidAttach: { _ in },
            splitControllerDidDetach: { _ in },
            library: Text("Library"),
            document: Text("Document"),
            apparatus: Text("Research")
        )
        _ = controller.view
        let documentItem = controller.splitViewItems[1]
        let inspectorItem = try #require(controller.splitViewItems.last)
        #expect(
            documentItem.holdingPriority.rawValue
                == inspectorItem.holdingPriority.rawValue
        )
    }

    @Test("Research Inspector divider resizes one pane while its trailing edge stays fixed")
    func researchInspectorDividerKeepsTrailingEdgeAnchored() throws {
        let controller = ScholiumWorkspaceSplitView<Text, Text, Text>.Controller(
            initialLibraryVisible: true,
            initialApparatusVisible: true,
            documentTabs: [],
            selectedDocumentTabID: nil,
            selectDocumentTab: { _ in },
            closeDocumentTab: { _ in },
            libraryVisibilityDidChange: { _ in },
            researchInspectorVisibilityDidChange: { _ in },
            splitControllerDidAttach: { _ in },
            splitControllerDidDetach: { _ in },
            library: Text("Library"),
            document: Text("Document"),
            apparatus: Text("Research")
        )
        _ = controller.view
        controller.view.frame = NSRect(x: 0, y: 0, width: 1_180, height: 760)
        controller.viewWillAppear()
        controller.view.layoutSubtreeIfNeeded()

        let inspectorItem = try #require(controller.splitViewItems.last)
        let inspectorView = try #require(controller.splitView.arrangedSubviews.last)
        #expect(!inspectorItem.isCollapsed)
        #expect(inspectorView.frame.width > 0)
        #expect(inspectorView.frame.maxX == controller.splitView.bounds.maxX)

        let dividerIndex = controller.splitView.arrangedSubviews.count - 2
        controller.splitView.setPosition(
            controller.splitView.bounds.maxX - 440,
            ofDividerAt: dividerIndex
        )
        controller.view.layoutSubtreeIfNeeded()
        #expect(
            abs(
                inspectorView.frame.width
                    - (440 - controller.splitView.dividerThickness)
            ) < 1
        )
        #expect(inspectorView.frame.maxX == controller.splitView.bounds.maxX)

        controller.splitView.setPosition(
            controller.splitView.bounds.maxX,
            ofDividerAt: dividerIndex
        )
        controller.view.layoutSubtreeIfNeeded()
        #expect(!inspectorItem.isCollapsed)
        #expect(
            inspectorView.frame.width
                >= ScholiumMetrics.Apparatus.minimumReadableWidth
        )
        #expect(inspectorView.frame.maxX == controller.splitView.bounds.maxX)

        controller.setResearchInspectorVisible(false, animated: false)
        #expect(inspectorItem.isCollapsed)
        controller.setResearchInspectorVisible(true, animated: false)
        #expect(!inspectorItem.isCollapsed)

        controller.splitView.setPosition(
            controller.splitView.bounds.maxX - 360,
            ofDividerAt: dividerIndex
        )
        controller.view.layoutSubtreeIfNeeded()
        #expect(!inspectorItem.isCollapsed)
        #expect(
            abs(
                inspectorView.frame.width
                    - (360 - controller.splitView.dividerThickness)
            ) < 1
        )
        #expect(inspectorView.frame.maxX == controller.splitView.bounds.maxX)

        let apparatusContainer = try #require(
            inspectorItem.viewController
                as? ScholiumSurfaceContainerViewController
        )
        #expect(
            apparatusContainer.backgroundView.frame
                == apparatusContainer.view.bounds
        )
    }

    @Test("Native hosting receives the live toolbar safe area")
    func hostingControllerReceivesLiveSafeArea() async {
        let libraryReading = SafeAreaReading()
        let documentReading = SafeAreaReading()
        let inspectorReading = SafeAreaReading()
        let libraryHost = NSHostingController(
            rootView: SafeAreaCaptureView { libraryReading.top = $0 }
        )
        let documentHost = NSHostingController(
            rootView: SafeAreaCaptureView { documentReading.top = $0 }
        )
        let inspectorHost = NSHostingController(
            rootView: SafeAreaCaptureView { inspectorReading.top = $0 }
        )
        let split = NSSplitViewController()
        let libraryItem = NSSplitViewItem(sidebarWithViewController: libraryHost)
        let documentItem = NSSplitViewItem(viewController: documentHost)
        let inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorHost)
        libraryItem.allowsFullHeightLayout = true
        documentItem.allowsFullHeightLayout = true
        split.addSplitViewItem(libraryItem)
        split.addSplitViewItem(documentItem)
        split.addSplitViewItem(inspectorItem)
        let window = testWindow()
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar(identifier: "window-lifecycle-safe-area")
        window.contentViewController = split
        window.orderFront(nil)
        window.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(500))
        window.layoutIfNeeded()

        #expect(window.contentView?.safeAreaInsets.top ?? 0 > 0)
        #expect(split.view.safeAreaInsets.top > 0)
        #expect(libraryReading.top > 0)
        #expect(documentReading.top > 0)
        #expect(inspectorReading.top > 0)
        window.close()
    }

    @Test("Research Records navigation preserves the native window frame")
    func researchRecordsNavigationPreservesWindowFrame() {
        let triptychID = UUID()
        let window = testWindow()
        window.setFrame(
            NSRect(x: 180, y: 180, width: 760, height: 680),
            display: false
        )
        window.toolbar = NSToolbar(identifier: "research-records-frame-regression")
        window.toolbarStyle = .unified
        defer {
            window.toolbar = nil
            window.close()
        }

        let attachment = ResearchRecordsWindowAttachment(
            triptychID: triptychID,
            colorScheme: .light
        )
        attachment.configure(window)
        let collectionFrame = window.frame
        #expect(window.appearance?.name == .aqua)

        attachment.configure(window)
        let detailFrame = window.frame

        attachment.configure(window)
        let returnedCollectionFrame = window.frame

        #expect(detailFrame == collectionFrame)
        #expect(returnedCollectionFrame == collectionFrame)
    }

    @Test("Document tab updates preserve page hosts and selector identities")
    func documentTabAdapterUpdatesIncrementally() {
        let firstID = UUID()
        let secondID = UUID()
        let first = DocumentTabItem(
            id: firstID,
            document: .unavailable(vaultID: UUID(), relativePath: "First.md"),
            title: "First",
            toolTip: "First.md"
        )
        let second = DocumentTabItem(
            id: secondID,
            document: .unavailable(vaultID: UUID(), relativePath: "Second.md"),
            title: "Second",
            toolTip: "Second.md"
        )
        let controller = ScholiumDocumentTabsViewController(
            document: Text("First projection"),
            tabs: [first, second],
            selectedTabID: firstID,
            selectTab: { _ in },
            closeTab: { _ in }
        )
        controller.loadViewIfNeeded()
        let firstHost = controller.testingPageHost(for: firstID)
        let firstItem = controller.testingPageItem(for: firstID)
        let firstSelector = controller.testingSelectorView(for: firstID)
        var renamed = first
        renamed.title = "Renamed"
        renamed.toolTip = "Renamed.md"

        controller.update(
            document: Text("Updated projection"),
            tabs: [renamed, second],
            selectedTabID: firstID,
            selectTab: { _ in },
            closeTab: { _ in }
        )

        #expect(controller.testingPageHost(for: firstID) === firstHost)
        #expect(controller.testingPageItem(for: firstID) === firstItem)
        #expect(controller.testingSelectorView(for: firstID) === firstSelector)
        #expect(controller.testingPageLabel(for: firstID) == "Renamed")
    }

    private func makeWorkspaceSplit(
        libraryChanges: @escaping (Bool) -> Void,
        inspectorChanges: @escaping (Bool) -> Void
    ) -> ScholiumWorkspaceSplitView<Text, Text, Text>.Controller {
        let controller = ScholiumWorkspaceSplitView<Text, Text, Text>.Controller(
            initialLibraryVisible: true,
            initialApparatusVisible: false,
            documentTabs: [],
            selectedDocumentTabID: nil,
            selectDocumentTab: { _ in },
            closeDocumentTab: { _ in },
            libraryVisibilityDidChange: libraryChanges,
            researchInspectorVisibilityDidChange: inspectorChanges,
            splitControllerDidAttach: { _ in },
            splitControllerDidDetach: { _ in },
            library: Text("Library"),
            document: Text("Document"),
            apparatus: Text("Research")
        )
        _ = controller.view
        controller.viewWillAppear()
        return controller
    }

    private func testWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 760),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }
}

private func makeTestWriteSetExtensionRecord(
    triptychID: UUID
) throws -> ResearchWriteSetExtensionRecord {
    let runID = UUID()
    let noteID = UUID()
    let handle = ResearchWriteTargetHandle(runID: runID, noteID: noteID)
    let selector = try ResearchWriteSetTargetSelector(
        role: .work,
        relativePath: "Draft.md",
        operations: [.modifyMarkdown]
    )
    let intent = try ResearchWriteSetExtensionIntent(
        targets: [selector],
        academicReason: "Develop the explicitly selected draft."
    )
    let candidate = try ResearchWriteSetCandidate(
        handle: handle,
        noteID: noteID,
        note: VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Draft.md"),
        role: .work,
        title: "Draft",
        operations: [.modifyMarkdown],
        expectedRevision: DocumentFingerprint(content: "# Draft\n")
    )
    let receivedAt = Date()
    return try ResearchWriteSetExtensionRecord(
        id: UUID(),
        runID: runID,
        triptychID: triptychID,
        intent: intent,
        intentDigest: DocumentFingerprint(content: "extension-intent"),
        candidates: [candidate],
        policy: .askEveryTime,
        policyRevision: DocumentFingerprint(content: "policy"),
        state: .pending,
        receivedAt: receivedAt,
        expiresAt: receivedAt.addingTimeInterval(60)
    )
}

private enum DeadlineTestOutcome: Equatable, Sendable {
    case succeeded
    case timedOut
    case unexpected
}

@MainActor
private final class TerminationFailureProbe {
    var shouldFail = true
}

@MainActor
private final class ManualLifecycleSuspension {
    private var continuation: UnsafeContinuation<Void, Never>?

    func suspendIgnoringCancellation() async {
        await withUnsafeContinuation { continuation = $0 }
    }

    func waitUntilArmed() async {
        for _ in 0..<1_000 {
            if continuation != nil { return }
            await Task.yield()
        }
        Issue.record("The controllable lifecycle suspension did not arm.")
    }

    func resume() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

@MainActor
private final class WindowLifecycleNotificationSystem:
    ResearchResultSystemNotificationServing
{
    var responseHandler: (@MainActor (ResearchResultReviewDestination) -> Void)?

    func authorizationState() async -> ResearchResultNotificationAuthorizationState {
        .denied
    }

    func requestAuthorization() async throws -> Bool { false }

    func deliver(_ request: ResearchResultSystemNotificationRequest) async throws {}

    func removeNotification(identifier: String) {}

    func openNotificationSettings() {}
}

@MainActor
private final class TestWindowDelegate: NSObject, NSWindowDelegate {
    private(set) var didReceiveWindowWillClose = false

    func windowWillClose(_ notification: Notification) {
        didReceiveWindowWillClose = true
    }
}

private final class WeakReference<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}

@MainActor
private final class SafeAreaReading {
    var top: CGFloat = 0
}

private struct SafeAreaCaptureView: View {
    let record: @MainActor (CGFloat) -> Void

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { record(geometry.safeAreaInsets.top) }
                .onChange(of: geometry.safeAreaInsets.top) { _, top in
                    record(top)
                }
        }
    }
}

@MainActor
private final class TestWorkspaceSplitController:
    NSSplitViewController,
    ScholiumWorkspaceSplitControlling
{
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        _ = view
        let library = NSSplitViewItem(sidebarWithViewController: NSViewController())
        let document = NSSplitViewItem(viewController: NSViewController())
        let inspector = NSSplitViewItem(inspectorWithViewController: NSViewController())
        library.canCollapse = true
        document.canCollapse = false
        document.canCollapseFromWindowResize = false
        addSplitViewItem(library)
        addSplitViewItem(document)
        addSplitViewItem(inspector)
    }

    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TestWorkspaceSplitController is code-only")
    }

    var nativeSplitViewController: NSSplitViewController { self }

    var libraryIsVisible: Bool { !splitViewItems[0].isCollapsed }

    var researchInspectorIsVisible: Bool { !splitViewItems[2].isCollapsed }

    func setLibraryVisible(_ visible: Bool, animated: Bool) {
        splitViewItems[0].isCollapsed = !visible
    }

    func setResearchInspectorVisible(_ visible: Bool, animated: Bool) {
        splitViewItems[2].isCollapsed = !visible
    }
}
