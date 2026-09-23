import AppKit
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Native title popover sizing", .serialized)
struct NativeTitlePopoverSizingTests {
    @Test("Focus Layout popover anchor remains inside either native coordinate orientation")
    func focusAnchorStaysVisible() {
        let safe = NSRect(x: 10, y: 20, width: 500, height: 400)
        for flipped in [true, false] {
            let anchor = DocumentTitleToolbarItem.fallbackAnchor(in: safe, isFlipped: flipped)
            #expect(safe.contains(anchor))
            #expect(anchor.height > 0 && anchor.width > 0)
            #expect(flipped ? anchor.minY == safe.minY : anchor.maxY == safe.maxY)
        }
    }

    @Test("The initial popover has a measurable body before presentation")
    func initialContentSize() {
        _ = NSApplication.shared
        let controller = DocumentTitlePopoverController(
            name: "Synthetic title", location: "Topics/Synthetic.md",
            rename: { _, requested in requested }, latestName: { "Synthetic title" }, dismiss: {})
        let popover = NSPopover()
        controller.prepareForPresentation(in: popover)
        #expect(popover.contentViewController === controller)
        #expect(controller.preferredContentSize.width > 0)
        #expect(controller.preferredContentSize.height > 0)
        #expect(popover.contentSize.width > 0, "Popover body width: \(popover.contentSize.width); view: \(controller.view.frame.size)")
        #expect(popover.contentSize.height > 0, "Popover body height: \(popover.contentSize.height); view: \(controller.view.frame.size)")
    }
}
