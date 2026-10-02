import AppKit
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Document reading split", .serialized)
@MainActor
struct DocumentReadingSplitTests {
    @Test("Reader and Inspector retain readable native panes at minimum workspace width")
    func nestedShellFitsVisiblePanes() throws {
        let controller = ScholiumWorkspaceSplitView<EmptyView, EmptyView, EmptyView, EmptyView>.Controller(
            initialLibraryVisible: true, initialApparatusVisible: true,
            documentTabs: [], selectedDocumentTabID: nil, selectDocumentTab: { _ in },
            libraryVisibilityDidChange: { _ in }, researchInspectorVisibilityDidChange: { _ in },
            splitControllerDidAttach: { _ in }, splitControllerDidDetach: { _ in },
            readerVisible: true, readerWidth: 340,
            readerWidthDidChange: { _ in }, focusDocument: {}, reader: AnyView(EmptyView()),
            library: EmptyView(), chat: EmptyView(), sidebarContent: .library,
            document: EmptyView(), apparatus: EmptyView()
        )
        let window = makeWindow(controller)
        defer {
            controller.invalidateReadingSplit()
            window.close()
        }
        controller.viewWillAppear()
        window.setContentSize(NSSize(width: 780, height: 600))
        window.layoutIfNeeded()
        let documentSurface = try #require(controller.splitViewItems[1].viewController as? ScholiumSurfaceContainerViewController)
        let readingSplit = try #require(documentSurface.contentViewController as? ScholiumDocumentReadingSplitController)
        #expect(!readingSplit.readerItem.isCollapsed)
        #expect(readingSplit.readerItem.automaticallyAdjustsSafeAreaInsets)
        #expect((readingSplit.readerController as? ScholiumSurfaceContainerViewController)?.contentExtendsUnderToolbar == true)
        #expect(!controller.splitViewItems[2].isCollapsed)
        #expect(readingSplit.documentController.view.frame.width >= 240)
        #expect(readingSplit.readerController.view.frame.width >= 280)
        #expect(controller.splitViewItems[2].viewController.view.frame.width >= 270)
        #expect(readingSplit.splitView.bounds.width.isFinite)
        let width = readingSplit.readerController.view.frame.width
        readingSplit.update(readerVisible: false, readerWidth: Double(width), widthDidChange: { _ in }, focusDocument: {})
        window.layoutIfNeeded()
        readingSplit.update(readerVisible: true, readerWidth: Double(width), widthDidChange: { _ in }, focusDocument: {})
        window.layoutIfNeeded()
        #expect(readingSplit.documentController.view.frame.width >= 240)
        #expect(readingSplit.readerController.view.frame.width >= 280)
    }

    @Test("Reader visibility and divider movement stay within their native window")
    func windowsOwnIndependentSplits() {
        let first = ScholiumDocumentReadingSplitController(
            documentController: NSViewController(), readerController: NSViewController(),
            readerVisible: true, readerWidth: 340,
            widthDidChange: { _ in }, focusDocument: {}
        )
        let second = ScholiumDocumentReadingSplitController(
            documentController: NSViewController(), readerController: NSViewController(),
            readerVisible: false, readerWidth: 420,
            widthDidChange: { _ in }, focusDocument: {}
        )
        let firstWindow = makeWindow(first)
        let secondWindow = makeWindow(second)
        defer {
            first.invalidate()
            second.invalidate()
            firstWindow.close()
            secondWindow.close()
        }
        let firstDocument = first.documentController.view
        let width = first.readerController.view.frame.width
        update(second, visible: true, width: 420) { _ in }
        secondWindow.layoutIfNeeded()
        second.splitView.setPosition(350, ofDividerAt: 0)
        secondWindow.layoutIfNeeded()
        #expect(first.documentController.view === firstDocument)
        #expect(firstDocument.window === firstWindow)
        #expect(first.readerController.view.window === firstWindow)
        #expect(second.readerController.view.window === secondWindow)
        #expect(abs(first.readerController.view.frame.width - width) < 1)
        update(second, visible: false, width: 420) { _ in }
        #expect(!first.readerItem.isCollapsed)
        #expect(second.readerItem.isCollapsed)
    }

    @Test("Repeated reader reveal and collapse retain both native content owners")
    func repeatedVisibilityPreservesHosts() {
        let document = NSViewController()
        let reader = NSViewController()
        var lastWidth: Double?
        let controller = ScholiumDocumentReadingSplitController(
            documentController: document, readerController: reader,
            readerVisible: false, readerWidth: 360,
            widthDidChange: { lastWidth = $0 }, focusDocument: {}
        )
        let window = makeWindow(controller)
        defer {
            controller.invalidate()
            window.close()
        }
        let documentView = document.view
        for _ in 0..<20 {
            update(controller, visible: true, width: lastWidth ?? 360) { lastWidth = $0 }
            window.layoutIfNeeded()
            #expect(!controller.readerItem.isCollapsed)
            #expect(!reader.view.isHidden)
            #expect(reader.view.isAccessibilityHidden() == false)
            #expect(document.view === documentView)
            #expect(documentView.window === window)
            update(controller, visible: false, width: lastWidth ?? 360) { lastWidth = $0 }
            window.layoutIfNeeded()
            #expect(controller.readerItem.isCollapsed)
            #expect(reader.view.isHidden)
            #expect(reader.view.isAccessibilityHidden() == true)
            #expect(document.view === documentView)
        }
        #expect(lastWidth != nil)
        #expect(controller.splitViewItems.count == 2)
        #expect(controller.documentItem.viewController === document)
        #expect(controller.readerItem.viewController === reader)
    }

    @Test("Closing a focused reader hands focus to the retained document")
    func hideReturnsDocumentFocus() {
        let document = NSViewController()
        document.view = FocusableReadingTestView()
        let reader = NSViewController()
        reader.view = FocusableReadingTestView()
        var window: NSWindow!
        var focusRequests = 0
        let focusDocument = {
            focusRequests += 1
            _ = window.makeFirstResponder(document.view)
        }
        let controller = ScholiumDocumentReadingSplitController(
            documentController: document, readerController: reader,
            readerVisible: true, readerWidth: 340,
            widthDidChange: { _ in }, focusDocument: focusDocument
        )
        window = makeWindow(controller)
        defer {
            controller.invalidate()
            window.close()
        }
        #expect(window.makeFirstResponder(reader.view))
        controller.update(
            readerVisible: false, readerWidth: 340,
            widthDidChange: { _ in }, focusDocument: focusDocument
        )
        #expect(focusRequests == 1)
        #expect(window.firstResponder === document.view)
        #expect(reader.view.isHidden)
        #expect(reader.view.isAccessibilityHidden() == true)
        controller.update(
            readerVisible: false, readerWidth: 340,
            widthDidChange: { _ in }, focusDocument: focusDocument
        )
        #expect(focusRequests == 1)
    }

    @Test("Native resize remains authoritative until an explicit reopen")
    func widthOffersDoNotReassertOnContentUpdates() {
        var savedWidth = 360.0
        let controller = ScholiumDocumentReadingSplitController(
            documentController: NSViewController(), readerController: NSViewController(),
            readerVisible: true, readerWidth: savedWidth,
            widthDidChange: { savedWidth = $0 }, focusDocument: {}
        )
        let window = makeWindow(controller)
        defer {
            controller.invalidate()
            window.close()
        }
        controller.splitView.setPosition(460, ofDividerAt: 0)
        window.layoutIfNeeded()
        let nativeWidth = controller.readerController.view.frame.width
        #expect(nativeWidth >= 280)
        #expect(abs(savedWidth - Double(nativeWidth)) < 1)

        // A stale projection must not undo the researcher's divider movement.
        update(controller, visible: true, width: 360) { savedWidth = $0 }
        window.layoutIfNeeded()
        #expect(abs(controller.readerController.view.frame.width - nativeWidth) < 1)
        update(controller, visible: false, width: savedWidth) { savedWidth = $0 }
        let retainedWidth = savedWidth
        window.setContentSize(NSSize(width: 680, height: 600))
        window.layoutIfNeeded()
        #expect(savedWidth == retainedWidth)
        update(controller, visible: true, width: retainedWidth) { savedWidth = $0 }
        window.layoutIfNeeded()
        #expect(!controller.readerItem.isCollapsed)
        #expect(controller.readerController.view.frame.width >= 280)
        #expect(controller.documentController.view.frame.width >= 240)
        #expect(!controller.readerItem.canCollapseFromWindowResize)
    }

    @Test("Detached native teardown stops width publication and stale updates")
    func teardownStopsCallbacks() {
        var widths: [Double] = []
        let controller = ScholiumDocumentReadingSplitController(
            documentController: NSViewController(), readerController: NSViewController(),
            readerVisible: true, readerWidth: 360,
            widthDidChange: { widths.append($0) }, focusDocument: {}
        )
        let window = makeWindow(controller)
        defer { window.close() }
        controller.invalidate()
        let count = widths.count
        update(controller, visible: false, width: 360) { widths.append($0) }
        controller.splitView.setPosition(450, ofDividerAt: 0)
        window.layoutIfNeeded()
        #expect(widths.count == count)
        #expect(!controller.readerItem.isCollapsed)
    }

    private func update(
        _ controller: ScholiumDocumentReadingSplitController,
        visible: Bool, width: Double, widthDidChange: @escaping (Double) -> Void
    ) {
        controller.update(
            readerVisible: visible, readerWidth: width,
            widthDidChange: widthDidChange, focusDocument: {}
        )
    }

    private func makeWindow(_ controller: NSViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.layoutIfNeeded()
        return window
    }
}

@MainActor
private final class FocusableReadingTestView: NSView {
    override var acceptsFirstResponder: Bool { true }
}
