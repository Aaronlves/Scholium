import AppKit
import Foundation
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

    @Test("The workspace coordinator retains, forwards, and restores the native delegate")
    func delegateRetentionAndRestoration() {
        let id = UUID()
        let registry = ScholiumWindowLifecycleRegistry()
        let model = WindowModel(workspaceStore: WorkspaceStore(), nativeWindowID: id)
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

        let expectedDelegate = retainedDelegate.value
        coordinator.detach()
        #expect(window.delegate === expectedDelegate)
    }

    @Test("Workspace readiness requires the exact attached window and split")
    func coordinatorMarksExactNativeBoundaryReady() async {
        let id = UUID()
        let registry = ScholiumWindowLifecycleRegistry()
        let model = WindowModel(workspaceStore: WorkspaceStore(), nativeWindowID: id)
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

@MainActor
private final class TestWindowDelegate: NSObject, NSWindowDelegate {}

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
