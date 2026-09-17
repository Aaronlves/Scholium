import AppKit
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Settings pane containment")
@MainActor
struct SettingsPaneContainerTests {
    @Test("Visited content remains attached while hidden content leaves accessibility and resizing")
    func retainedVisibilityAndGeometry() {
        let container = SettingsPaneContainerView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let first = NSButton(title: "First", target: nil, action: nil)
        let second = NSButton(title: "Second", target: nil, action: nil)
        container.show(first)
        container.show(second)
        #expect(first.superview === container)
        #expect(first.isHidden)
        #expect(!second.isHidden)
        #expect(container.accessibilityChildren()?.count == 1)
        #expect(((container.accessibilityChildren()?.first as? NSObject)?.value(forKey: "accessibilityLabel") as? String) == "Second")

        container.setFrameSize(NSSize(width: 800, height: 500))
        container.layoutSubtreeIfNeeded()
        #expect(second.frame.size == container.bounds.size)
        #expect(first.frame.size == NSSize(width: 600, height: 400))
        container.show(first)
        #expect(!first.isHidden)
        #expect(first.frame.size == container.bounds.size)
        #expect(second.isHidden)
        container.removeContents()
        #expect(container.subviews.isEmpty)
        #expect(container.selectedView == nil)
    }

    @Test("Native Settings sidebar and tracking toolbar retain their boundary while the page resizes")
    func fixedNativeNavigation() throws {
        _ = NSApplication.shared
        let controller = SettingsNavigationSplitController(
            title: "Document Appearance",
            sidebar: AnyView(Text("Settings categories")),
            page: AnyView(Text("Disposable settings page")))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 600),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer {
            controller.detachToolbar()
            window.contentViewController = nil
            window.close()
        }
        controller.attachToolbar()
        window.contentView?.layoutSubtreeIfNeeded()
        let toolbar = try #require(window.toolbar)
        #expect(toolbar.delegate === controller)
        #expect(toolbar.isVisible)
        #expect(!toolbar.allowsUserCustomization && !toolbar.autosavesConfiguration)
        #expect(window.toolbarStyle == .unified)
        #expect(window.titleVisibility == .visible)
        #expect(window.title == "Document Appearance")
        let trackingItems = toolbar.items.compactMap { $0 as? NSTrackingSeparatorToolbarItem }
        #expect(trackingItems.count == 1)
        let separator = try #require(trackingItems.first)
        // The system's standard tracking separator associates both titlebar
        // sections with the actual native boundary. Its rendered separator
        // frame is AppKit-owned and has no documented public geometry API.
        #expect(separator.itemIdentifier == .sidebarTrackingSeparator)
        #expect(separator.splitView === controller.splitView)
        #expect(separator.dividerIndex == 0)
        #expect(separator.splitView.window === window)
        #expect(!toolbar.items.contains { $0.itemIdentifier == .toggleSidebar })
        let originalFrame = window.frame
        // A later scene-content transaction must not retire native resizing.
        window.styleMask.remove(.resizable)
        controller.updateTitle("Writing Assistance")
        #expect(window.styleMask.contains(.resizable))
        #expect(window.title == "Writing Assistance")
        #expect(window.toolbar === toolbar)
        #expect(window.frame == originalFrame)

        #expect(controller.splitViewItems.count == 2)
        let navigation = try #require(controller.splitViewItems.first)
        let content = try #require(controller.splitViewItems.last)
        // The public sidebar behavior gives the system ownership of material
        // and adaptation; the test does not depend on AppKit's private view tree.
        #expect(navigation.behavior == .sidebar)
        #expect(navigation.viewController === controller.sidebarController)
        #expect(content.viewController === controller.pageController)
        #expect(!navigation.canCollapse && !navigation.canCollapseFromWindowResize)
        #expect(!content.canCollapse && !content.canCollapseFromWindowResize)
        #expect(controller.splitView.isVertical)
        #expect(controller.splitView.delegate === controller)

        var previousPageWidth: CGFloat?
        for width in [CGFloat(920), CGFloat(780)] {
            window.setContentSize(NSSize(width: width, height: 600))
            window.contentView?.layoutSubtreeIfNeeded()
            controller.splitView.layoutSubtreeIfNeeded()
            let split = controller.splitView
            let sidebarFrame = controller.sidebarController.view.convert(
                controller.sidebarController.view.bounds, to: split)
            let pageFrame = controller.pageController.view.convert(
                controller.pageController.view.bounds, to: split)
            #expect(abs(split.bounds.width - width) < 0.5)
            #expect(abs(sidebarFrame.width - 240) < 0.5)
            #expect(abs(sidebarFrame.minX - split.bounds.minX) < 0.5)
            #expect(!navigation.isCollapsed && !content.isCollapsed)
            #expect(window.toolbar === toolbar && toolbar.isVisible)
            #expect(separator.splitView === split && separator.dividerIndex == 0)
            let gap = pageFrame.minX - sidebarFrame.maxX
            #expect(gap >= 0 && gap <= split.dividerThickness)
            #expect(abs(pageFrame.maxX - split.bounds.maxX) < 0.5)
            if let previousPageWidth {
                #expect(abs(previousPageWidth - pageFrame.width - 140) < 0.5)
            }
            previousPageWidth = pageFrame.width

            let divider = NSRect(
                x: sidebarFrame.maxX, y: split.bounds.minY,
                width: split.dividerThickness, height: split.bounds.height)
            #expect(
                controller.splitView(
                    split, effectiveRect: divider.insetBy(dx: -8, dy: 0),
                    forDrawnRect: divider, ofDividerAt: 0) == .zero)
            #expect(controller.splitView(split, additionalEffectiveRectOfDividerAt: 0) == .zero)
        }
        controller.detachToolbar()
        #expect(window.toolbar == nil)
    }

    @Test("Hiding an editing pane releases its field editor but preserves outside focus")
    func outgoingFieldEditorAndSidebarFocus() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        window.contentView = root
        let sidebar = NSTextField(string: "Sidebar")
        root.addSubview(sidebar)
        let container = SettingsPaneContainerView(frame: NSRect(x: 200, y: 0, width: 600, height: 500))
        root.addSubview(container)
        let first = NSTextField(string: "Unsaved draft")
        let second = NSButton(title: "Second", target: nil, action: nil)
        container.show(first)
        #expect(window.makeFirstResponder(first))
        let oldEditor = window.firstResponder
        container.show(second)
        #expect(window.firstResponder !== oldEditor)
        #expect(first.stringValue == "Unsaved draft")

        #expect(window.makeFirstResponder(sidebar))
        let sidebarEditor = window.firstResponder
        container.show(first)
        #expect(window.firstResponder === sidebarEditor)
        #expect(first.stringValue == "Unsaved draft")
    }
}
