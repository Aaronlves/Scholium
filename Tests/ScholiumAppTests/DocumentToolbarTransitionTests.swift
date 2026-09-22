import AppKit
import Testing
import WebKit
@testable import ScholiumApp

@Suite(.serialized)
@MainActor
struct DocumentToolbarTransitionTests {
    @Test("Document material is confined to live window chrome, never the Paper reading area")
    func materialTracksOnlyActualToolbarOverlap() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.toolbar = NSToolbar(identifier: "DocumentToolbarTransitionTests")
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
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

        let material = try #require(viewport.subviews.compactMap { $0 as? DocumentToolbarTransition }.first)
        let chromeFrame = viewport.convert(material.frame, to: nil)
        #expect(!material.isHidden)
        #expect(chromeFrame.height > 0)
        #expect(abs(chromeFrame.minY - window.contentLayoutRect.maxY) < 0.5)
        #expect(chromeFrame.maxY <= root.convert(root.bounds, to: nil).maxY)
        #expect(material.clipsToBounds)
        #expect(material.hitTest(.zero) == nil)
        #expect(material.isAccessibilityHidden())

        let toolbarPoint = viewport.convert(
            NSPoint(x: material.frame.midX, y: material.frame.midY), to: root
        )
        #expect(viewport.hitTest(toolbarPoint) == nil)
        let bodyPoint = viewport.convert(
            NSPoint(x: viewport.bounds.midX, y: material.frame.maxY + 20), to: root
        )
        let bodyHit = try #require(viewport.hitTest(bodyPoint))
        #expect(bodyHit === web || bodyHit.isDescendant(of: web))

        // Moving between retained reader/editor surfaces keeps their document
        // geometry stable even while neither can receive pointer input.
        viewport.setSurfaceVisibility(.retained)
        viewport.layoutSubtreeIfNeeded()
        #expect(material.frame.height == chromeFrame.height)
        viewport.setSurfaceVisibility(.active)

        // Exercise superview-to-local conversion with a horizontally offset
        // document column; window chrome must still never hit WebKit.
        viewport.frame.origin.x = 80
        #expect(viewport.hitTest(NSPoint(x: toolbarPoint.x + 80, y: toolbarPoint.y)) == nil)
        viewport.frame.origin.x = 0

        // A tab strip or recovery notice can keep the document below chrome.
        // Reuse the same WebKit and remove the effect rather than painting a
        // substitute strip across the prose beneath that fixed content.
        viewport.frame = NSRect(x: 0, y: 0, width: 700, height: window.contentLayoutRect.height - 40)
        viewport.needsLayout = true
        viewport.layoutSubtreeIfNeeded()
        #expect(viewport.toolbarOverlap.isEmpty)
        #expect(material.isHidden)
        #expect(viewport.webView === web)
    }
}
