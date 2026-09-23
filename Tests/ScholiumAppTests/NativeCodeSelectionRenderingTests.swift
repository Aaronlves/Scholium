import AppKit
import Testing

@testable import ScholiumApp
@testable import ScholiumEditor

@MainActor
@Suite("Code block selection compositing", .serialized)
struct NativeCodeSelectionRenderingTests {
    @Test("Code glyph fragments cannot cover the native highlight with their opaque box")
    func codeBoxStaysBelowSelection() throws {
        _ = NSApplication.shared
        let source = Data("before\r\n\r\n```swift\nlet value = 1\nreturn value\n```\r\n\r\nafter".utf8)
        let session = nativeSelectionTestSession(source)
        let editor = session.nativeEditor
        editor.viewMode = .reading
        editor.setSelectedRange(NSRange(location: 0, length: (editor.rawSource as NSString).length))
        let layout = try #require(editor.textLayoutManager)
        layout.ensureLayout(for: layout.documentRange)
        var body: DecoratedTextLayoutFragment?
        layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: []) { fragment in
            if let decorated = fragment as? DecoratedTextLayoutFragment,
                decorated.drawsFillsBelowSelection,
                decorated.textLineFragments.contains(where: { $0.attributedString.string.contains("let value") })
            {
                body = decorated
                return false
            }
            return true
        }
        let fragment = try #require(body)
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 128, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        let point = CGPoint(x: fragment.layoutFragmentFrame.minX, y: 0)
        fragment.drawBackgroundFills(at: point, in: context)
        // Bitmap row orientation differs from the CGContext's coordinates;
        // locate an actual filled margin pixel rather than guessing its row.
        let sampleY = try #require(
            (0..<64).first {
                (bitmap.colorAt(x: 2, y: $0)?.alphaComponent ?? 0) > 0.9
            })
        let background = try #require(bitmap.colorAt(x: 2, y: sampleY)?.usingColorSpace(.deviceRGB))
        // Simulate the intervening native selection pass. Its color comes from
        // AppKit; the assertion concerns later opaque overpainting, not a custom
        // implementation of selection geometry or its platform presentation.
        context.setFillColor(NSColor.selectedTextBackgroundColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 64))
        let selected = try #require(bitmap.colorAt(x: 2, y: sampleY)?.usingColorSpace(.deviceRGB))
        fragment.draw(at: point, in: context)
        let rendered = try #require(bitmap.colorAt(x: 2, y: sampleY)?.usingColorSpace(.deviceRGB))
        #expect(background.alphaComponent > 0.9)
        #expect(
            abs(background.redComponent - selected.redComponent)
                + abs(background.greenComponent - selected.greenComponent)
                + abs(background.blueComponent - selected.blueComponent) > 0.01)
        #expect(abs(rendered.redComponent - selected.redComponent) < 0.01)
        #expect(abs(rendered.greenComponent - selected.greenComponent) < 0.01)
        #expect(abs(rendered.blueComponent - selected.blueComponent) < 0.01)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let copied = editor.writeSelection(to: pasteboard, types: editor.writablePasteboardTypes)
        #expect(copied)
        let copiedText = pasteboard.string(forType: .string)
        #expect(copiedText == editor.rawSource)
        #expect(try editor.exactUTF8ForSaving() == source)
    }
}
