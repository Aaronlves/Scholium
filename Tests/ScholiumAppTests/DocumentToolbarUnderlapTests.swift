import AppKit
import Testing
import WebKit
@testable import ScholiumApp

@Suite(.serialized)
@MainActor
struct DocumentToolbarUnderlapTests {
    @Test("WebKit may scroll behind native toolbar without owning its input")
    func underlapRoutesToolbarInputToWindow() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.toolbar = NSToolbar(identifier: "DocumentToolbarUnderlapTests")
        window.toolbarStyle = .unified
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        window.contentView = root
        let web = WKWebView(frame: root.bounds)
        let viewport = DocumentWebViewContainer(webView: web)
        viewport.frame = root.bounds
        viewport.toolbarUnderlapEnabled = true
        root.addSubview(viewport)
        defer { window.close() }
        window.layoutIfNeeded()
        viewport.layoutSubtreeIfNeeded()

        #expect(viewport.subviews.count == 1)
        #expect(viewport.subviews.first === web)
        let overlap = viewport.toolbarOverlap
        #expect(overlap.height > 0)
        let toolbarPoint = viewport.convert(
            NSPoint(x: overlap.midX, y: overlap.midY), to: root
        )
        #expect(viewport.hitTest(toolbarPoint) == nil)
        let bodyPoint = viewport.convert(
            NSPoint(x: viewport.bounds.midX, y: overlap.maxY + 20), to: root
        )
        let bodyHit = try #require(viewport.hitTest(bodyPoint))
        #expect(bodyHit === web || bodyHit.isDescendant(of: web))

        viewport.setSurfaceVisibility(.retained)
        viewport.layoutSubtreeIfNeeded()
        #expect(viewport.toolbarOverlap.height == overlap.height)
        viewport.setSurfaceVisibility(.active)

        viewport.frame.origin.x = 80
        #expect(viewport.hitTest(NSPoint(x: toolbarPoint.x + 80, y: toolbarPoint.y)) == nil)
        viewport.frame.origin.x = 0
        viewport.frame = NSRect(
            x: 0, y: 0, width: 700, height: window.contentLayoutRect.height - 40
        )
        viewport.needsLayout = true
        viewport.layoutSubtreeIfNeeded()
        #expect(viewport.toolbarOverlap.isEmpty)
        #expect(viewport.webView === web)
    }
}
