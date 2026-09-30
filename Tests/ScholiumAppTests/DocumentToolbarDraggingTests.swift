import AppKit
import Testing

@testable import ScholiumApp

@Suite("Native Document tab dragging", .serialized)
@MainActor
struct DocumentToolbarDraggingTests {
    @Test("Drop location, acceptance and cancellation determine detachment", arguments: DropCase.allCases)
    func dropBoundary(scenario: DropCase) throws {
        let fixture = TabDragFixture()
        defer { fixture.close() }
        let item = try #require(fixture.owner.prepareDraggingItem(from: fixture.controls[0]))
        let board = try #require(item.item as? NSPasteboardItem)
        #expect(board.types == [DocumentToolbarTabItem.pasteboardType])
        #expect(board.string(forType: DocumentToolbarTabItem.pasteboardType) == fixture.tabs[0].id.uuidString)
        let stripFrame = fixture.screenFrame
        let body = NSPoint(x: stripFrame.midX, y: stripFrame.minY - 120)
        #expect(fixture.window.frame.contains(body))
        var point = body
        var operation: NSDragOperation = []
        switch scenario {
        case .inside: point = NSPoint(x: stripFrame.midX, y: stripFrame.midY)
        case .body: break
        case .outsideWindow: point = NSPoint(x: fixture.window.frame.maxX + 40, y: stripFrame.midY)
        case .accepted: operation = .move
        case .cancelled: fixture.owner.cancelDrag()
        case .hidden: fixture.strip.isHidden = true
        case .invalidPoint: point.x = .infinity
        case .removed:
            fixture.owner.update(tabs: Array(fixture.tabs.dropFirst()), selectedID: fixture.tabs[1].id)
        }
        let detaches = scenario == .body || scenario == .outsideWindow
        let preview = fixture.owner.draggingPreviewComponents(at: point, window: fixture.window)
        if scenario != .removed {
            #expect(preview?.count == (detaches || scenario == .accepted ? 2 : 1))
            #expect(preview?.first?.frame == NSRect(origin: .zero, size: fixture.controls[0].bounds.size))
        } else {
            #expect(preview == nil)
        }
        #expect(
            fixture.owner.shouldAnimateDragReturn(at: point, operation: operation, window: fixture.window)
                == (!detaches && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        )
        fixture.owner.finishDrag(at: point, operation: operation, window: fixture.window)
        #expect(fixture.detachedIDs == (detaches ? [fixture.tabs[0].id] : []))
        // Late native completion must not transfer the same Note twice.
        fixture.owner.finishDrag(at: point, operation: operation, window: fixture.window)
        #expect(fixture.detachedIDs.count == (detaches ? 1 : 0))
        #expect(fixture.owner.draggingPreviewComponents(at: point, window: fixture.window) == nil)
    }

    @Test("Whole-strip gaps and end space retain insertion destinations", arguments: [true, false])
    func stripDropFallback(atEnd: Bool) throws {
        let fixture = TabDragFixture()
        defer { fixture.close() }
        let sourceIndex = atEnd ? 0 : 2
        _ = try #require(fixture.owner.prepareDraggingItem(from: fixture.controls[sourceIndex]))
        let point: NSPoint
        if atEnd {
            point = fixture.strip.convert(NSPoint(x: fixture.strip.bounds.maxX - 2, y: fixture.strip.bounds.midY), to: nil)
        } else {
            let first = fixture.controls[0].convert(fixture.controls[0].bounds, to: nil)
            let second = fixture.controls[1].convert(fixture.controls[1].bounds, to: nil)
            point = NSPoint(x: (first.maxX + second.minX) / 2, y: first.midY)
        }
        let info = TabDraggingInfo(source: fixture.controls[sourceIndex], window: fixture.window, point: point)
        defer { info.draggingPasteboard.releaseGlobally() }
        #expect(fixture.strip.draggingEntered(info) == .move)
        #expect(fixture.strip.prepareForDragOperation(info))
        #expect(fixture.strip.performDragOperation(info))
        #expect(fixture.reorderedIDs == [fixture.tabs[sourceIndex].id])
        #expect(fixture.reorderedIndices == [atEnd ? 2 : 1])
        fixture.owner.finishDrag(at: fixture.window.convertPoint(toScreen: point), operation: .move, window: fixture.window)
        #expect(fixture.detachedIDs.isEmpty)
    }

    @Test("Foreign sources, cancellation and stale insertion gaps cannot reorder")
    func invalidDropSources() throws {
        let fixture = TabDragFixture()
        let foreign = TabDragFixture()
        defer {
            fixture.close()
            foreign.close()
        }
        _ = try #require(fixture.owner.prepareDraggingItem(from: fixture.controls[0]))
        let point = fixture.strip.convert(NSPoint(x: 100, y: fixture.strip.bounds.midY), to: nil)
        let info = TabDraggingInfo(source: foreign.controls[0], window: fixture.window, point: point)
        defer { info.draggingPasteboard.releaseGlobally() }
        // Even a matching payload cannot substitute for this owner's source.
        info.draggingPasteboard.setString(fixture.tabs[0].id.uuidString, forType: DocumentToolbarTabItem.pasteboardType)
        #expect(fixture.strip.draggingEntered(info).isEmpty)
        #expect(!fixture.strip.performDragOperation(info))
        info.draggingSource = fixture.controls[0]
        #expect(fixture.strip.draggingEntered(info) == .move)
        fixture.owner.cancelDrag()
        #expect(!fixture.strip.performDragOperation(info))
        #expect(fixture.reorderedIDs.isEmpty)
        #expect(fixture.detachedIDs.isEmpty)
    }

    @Test("Preview returns to its original image and follows live strip geometry")
    func previewReentryAndGeometry() throws {
        let fixture = TabDragFixture()
        defer { fixture.close() }
        _ = try #require(fixture.owner.prepareDraggingItem(from: fixture.controls[0]))
        let outside = NSPoint(x: fixture.screenFrame.midX, y: fixture.screenFrame.minY - 60)
        #expect(fixture.owner.draggingPreviewComponents(at: outside, window: fixture.window)?.count == 2)
        fixture.strip.frame.origin.y -= 60
        fixture.strip.layoutSubtreeIfNeeded()
        #expect(fixture.owner.draggingPreviewComponents(at: outside, window: fixture.window)?.count == 1)
        #expect(fixture.owner.draggingPreviewComponents(at: outside, window: nil)?.count == 1)
        fixture.owner.finishDrag(at: outside, operation: [], window: fixture.window)
        #expect(fixture.detachedIDs.isEmpty)
    }

    @Test("Detachment caption renders readable text in the source appearance", arguments: [false, true], [false, true])
    func previewAppearance(dark: Bool, highContrast: Bool) throws {
        let fixture = TabDragFixture()
        defer { fixture.close() }
        let light: NSAppearance.Name = highContrast ? .accessibilityHighContrastAqua : .aqua
        let darkAppearance: NSAppearance.Name = highContrast ? .accessibilityHighContrastDarkAqua : .darkAqua
        let appearance = try #require(NSAppearance(named: dark ? darkAppearance : light))
        fixture.window.appearance = appearance
        let sourceAppearance = fixture.strip.effectiveAppearance
        _ = try #require(fixture.owner.prepareDraggingItem(from: fixture.controls[0]))
        let outside = NSPoint(x: fixture.screenFrame.midX, y: fixture.screenFrame.minY - 60)
        let components = try #require(fixture.owner.draggingPreviewComponents(at: outside, window: fixture.window))
        let caption = try #require(components.last?.contents as? NSImage)
        #expect(components.last?.frame.maxY ?? 0 < 0)
        // A native drag image can render after the source's appearance changes.
        // Its cached caption must keep the source appearance and contain ink.
        fixture.window.appearance = NSAppearance(named: dark ? light : darkAppearance)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: Int(caption.size.width), height: Int(caption.size.height),
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        caption.draw(in: NSRect(origin: .zero, size: caption.size))
        NSGraphicsContext.restoreGraphicsState()
        let rendered = try #require(context.makeImage())
        let bitmap = NSBitmapImageRep(cgImage: rendered)
        var expectedBackground: NSColor?
        var oppositeBackground: NSColor?
        sourceAppearance.performAsCurrentDrawingAppearance {
            expectedBackground = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)
        }
        fixture.strip.effectiveAppearance.performAsCurrentDrawingAppearance {
            oppositeBackground = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)
        }
        let expected = try #require(expectedBackground)
        let opposite = try #require(oppositeBackground)
        let corner = try #require(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB))
        #expect(corner.alphaComponent > 0.98)
        // Material colors need not round-trip as identical RGB channels. The
        // rendered caption must match the source theme rather than its opposite.
        func distance(to color: NSColor) -> CGFloat {
            abs(corner.redComponent - color.redComponent)
                + abs(corner.greenComponent - color.greenComponent)
                + abs(corner.blueComponent - color.blueComponent)
        }
        #expect(distance(to: expected) < distance(to: opposite))
        var inkPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(color.redComponent - corner.redComponent) > 0.25 {
                    inkPixels += 1
                }
            }
        }
        #expect(inkPixels > 20, "The native caption must render visible glyphs, not only its background.")
    }

    enum DropCase: String, CaseIterable, Sendable {
        case inside, body, outsideWindow, accepted, cancelled, hidden, invalidPoint, removed
    }
}

@MainActor
private final class TabDragFixture {
    let owner = DocumentToolbarTabs()
    let window: NSWindow
    let tabs: [DocumentTabItem]
    let strip: DocumentToolbarTabStrip
    let controls: [DocumentToolbarTabControl]
    var detachedIDs: [UUID] = []
    var reorderedIDs: [UUID] = []
    var reorderedIndices: [Int] = []

    init() {
        _ = NSApplication.shared
        window = NSWindow(
            contentRect: NSRect(x: 120, y: 200, width: 880, height: 620),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        tabs = (0..<3).map { index in
            DocumentTabItem(document: .unavailable(vaultID: UUID(), relativePath: "\(index).md"), title: "Tab \(index)", toolTip: "\(index).md")
        }
        owner.update(tabs: tabs, selectedID: tabs[0].id)
        strip = owner.item(for: DocumentToolbarTabItem.identifier)!.control
        let projection = owner
        controls = tabs.map { projection.control(for: $0.id)! }
        window.contentView?.addSubview(strip)
        strip.frame = NSRect(x: 80, y: 540, width: 640, height: DocumentToolbarTabStrip.height)
        strip.layoutSubtreeIfNeeded()
        owner.detach = { [weak self] id, _ in self?.detachedIDs.append(id) }
        owner.reorder = { [weak self] id, index in
            self?.reorderedIDs.append(id)
            self?.reorderedIndices.append(index)
        }
    }

    var screenFrame: NSRect { window.convertToScreen(strip.convert(strip.bounds, to: nil)) }

    func close() {
        owner.invalidate()
        window.contentView = nil
        window.close()
    }
}

@MainActor
private final class TabDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any?
    var draggingDestinationWindow: NSWindow?
    var draggingLocation: NSPoint
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggedImageLocation: NSPoint { .zero }
    nonisolated var draggedImage: NSImage? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    init(source: DocumentToolbarTabControl, window: NSWindow, point: NSPoint) {
        draggingSource = source
        draggingDestinationWindow = window
        draggingLocation = point
        super.init()
        draggingPasteboard.setString(source.tab.id.uuidString, forType: DocumentToolbarTabItem.pasteboardType)
    }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(
        options: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
}
