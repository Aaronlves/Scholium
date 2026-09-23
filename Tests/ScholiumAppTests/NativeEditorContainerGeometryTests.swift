import AppKit
import Testing

@testable import ScholiumApp

@Suite("Native editor toolbar geometry", .serialized)
@MainActor
struct NativeEditorContainerGeometryTests {
    @Test("Native text viewport fills the safe area below the toolbar in both host geometries")
    func contentRespectsSafeArea() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbar = NSToolbar(identifier: "NativeEditorContainerGeometryTests")
        window.toolbarStyle = .unified
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        window.contentView = root
        let session = MarkdownEditorSession()
        let container = NativeEditorContainer(session: session)
        root.addSubview(container)
        defer { window.close() }

        for frame in [root.bounds, NSRect(x: 0, y: 0, width: 700, height: 300)] {
            container.frame = frame
            container.needsLayout = true
            window.layoutIfNeeded()
            container.layoutSubtreeIfNeeded()
            #expect(session.scrollView.frame == container.safeAreaRect)
            #expect(container.subviews.count == 1)
            #expect(container.subviews.first === session.scrollView)
        }
    }
}
