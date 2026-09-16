import AppKit
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
