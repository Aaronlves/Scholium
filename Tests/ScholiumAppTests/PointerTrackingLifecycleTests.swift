import AppKit
import Testing

@testable import ScholiumApp

@Suite("Content pointer tracking lifecycle")
@MainActor
struct PointerTrackingLifecycleTests {
    @Test("Layout updates retain one tracking identity")
    func stableTrackingArea() throws {
        let view = ScholiumPointerTrackingView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        view.updateTrackingAreas()
        let original = try #require(view.trackingAreas.first)
        for _ in 0..<20 { view.updateTrackingAreas() }
        #expect(view.trackingAreas.count == 1)
        #expect(view.trackingAreas.first === original)
        view.invalidate()
    }

    @Test("Current pointer position clears every previously crossed row")
    func crossingRows() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var hovering = [false, false, false]
        let rows = (0..<3).map { index in
            let view = ScholiumPointerTrackingView(frame: NSRect(x: 0, y: index * 50, width: 200, height: 40))
            window.contentView!.addSubview(view)
            view.stateDidChange = { inside, _ in hovering[index] = inside }
            #expect(view.visibleRect == view.bounds)
            return view
        }
        for index in 0..<3 {
            let point = rows[index].convert(NSPoint(x: 20, y: 10), to: nil)
            rows.forEach { $0.synchronizePointer(locationInWindow: point) }
            #expect(hovering.enumerated().allSatisfy { $0.element == ($0.offset == index) }, "row \(index): \(hovering)")
        }
        rows.forEach { $0.synchronizePointer(locationInWindow: nil) }
        #expect(hovering == [false, false, false])
        rows.forEach { $0.invalidate() }
    }

    @Test("Offscreen and hidden portions never retain hover")
    func clippingAndVisibility() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let viewport = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        viewport.clipsToBounds = true
        window.contentView!.addSubview(viewport)
        let row = ScholiumPointerTrackingView(frame: NSRect(x: 0, y: 20, width: 100, height: 40))
        viewport.addSubview(row)
        var hovering = false
        row.stateDidChange = { inside, _ in hovering = inside }
        row.synchronizePointer(locationInWindow: row.convert(NSPoint(x: 10, y: 10), to: nil))
        #expect(hovering)
        row.synchronizePointer(locationInWindow: row.convert(NSPoint(x: 10, y: 30), to: nil))
        #expect(!hovering)
        row.isHidden = true
        row.synchronizePointer(locationInWindow: row.convert(NSPoint(x: 10, y: 10), to: nil))
        #expect(!hovering)
        row.invalidate()
    }

    @Test("Native clip movement transfers hover beneath a stationary pointer")
    func stationaryPointerDuringScroll() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
        scroll.documentView = document
        window.contentView!.addSubview(scroll)
        let rows = [40, 120].map { y in
            let row = ScholiumPointerTrackingView(frame: NSRect(x: 0, y: y, width: 200, height: 40))
            document.addSubview(row)
            return row
        }
        var hovering = [false, false]
        for (index, row) in rows.enumerated() {
            row.stateDidChange = { inside, _ in hovering[index] = inside }
        }
        let stationaryPoint = scroll.contentView.convert(NSPoint(x: 20, y: 60), to: nil)
        rows.forEach { $0.synchronizePointer(locationInWindow: stationaryPoint) }
        #expect(hovering == [true, false])
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 80))
        scroll.reflectScrolledClipView(scroll.contentView)
        rows.forEach { $0.synchronizePointer(locationInWindow: stationaryPoint) }
        #expect(hovering == [false, true])
        rows.forEach { $0.invalidate() }
    }

    @Test("Detach publishes a reset instead of leaving SwiftUI's old hover behind")
    func detachClearsPublishedState() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = ScholiumPointerTrackingView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        window.contentView!.addSubview(view)
        var hovering = false
        view.stateDidChange = { inside, _ in hovering = inside }
        view.synchronizePointer(locationInWindow: NSPoint(x: 20, y: 10))
        #expect(hovering)
        view.removeFromSuperview()
        #expect(!hovering)
        view.invalidate()
    }
}
