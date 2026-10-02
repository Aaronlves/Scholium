import AppKit
import CoreText
import Foundation
import PDFKit
import Testing

@testable import ScholiumApp

@Suite("Native PDF annotation geometry", .serialized)
@MainActor
struct PDFReaderAnnotationsTests {
    @Test("Multiline and multipage highlights retain separate page-local quadrilaterals")
    func multilineHighlights() throws {
        let document = try fixture()
        let selection = try #require(document.selectionForEntireDocument)
        let prepared = try PDFReaderAnnotations.highlights(for: selection, in: document)
        #expect(prepared.count == 2)
        for (page, annotation) in prepared {
            let points = try #require(annotation.quadrilateralPoints)
            #expect(points.count == 8)
            #expect(
                points.allSatisfy {
                    $0.pointValue.x >= 0 && $0.pointValue.y >= 0
                        && $0.pointValue.x <= annotation.bounds.width
                        && $0.pointValue.y <= annotation.bounds.height
                })
            #expect(page.annotations.isEmpty)
            page.addAnnotation(annotation)
        }
        let reloaded = try #require(PDFDocument(data: document.dataRepresentation()!))
        #expect(reloaded.page(at: 0)?.annotations.first?.quadrilateralPoints?.count == 8)
        #expect(reloaded.page(at: 1)?.annotations.first?.quadrilateralPoints?.count == 8)
        #expect(reloaded.string == document.string)
    }

    @Test("Standard PDF serialization preserves Unicode comments and existing foreign annotations")
    func standardAnnotationsRoundTrip() throws {
        let document = try fixture()
        let page = try #require(document.page(at: 0))
        let link = PDFAnnotation(bounds: NSRect(x: 50, y: 50, width: 100, height: 20), forType: .link, withProperties: nil)
        link.url = URL(string: "https://example.org/synthetic-paper")
        page.addAnnotation(link)
        let comment = try PDFReaderAnnotations.comment(text: "Retained comment 注释 😀", at: NSPoint(x: 611, y: 791), on: page, in: document)
        #expect(page.bounds(for: .cropBox).contains(comment.bounds))
        page.addAnnotation(comment)
        comment.contents = "Edited comment 注释 😀"
        let reloaded = try #require(PDFDocument(data: document.dataRepresentation()!))
        let annotations = try #require(reloaded.page(at: 0)).annotations
        #expect(annotations.count == 2)
        #expect(annotations.contains { $0.url == link.url })
        #expect(annotations.contains { $0.contents == "Edited comment 注释 😀" })
        #expect(comment.value(forAnnotationKey: .name) as? String != nil)
    }

    @Test("Serialized highlights render over known text on cropped pages rotated 90 and 270 degrees")
    func rotatedCroppedHighlightRendering() throws {
        for rotation in [90, 270] {
            let (document, sourceInkBounds) = try rotatedFixture(rotation: rotation)
            let page = try #require(document.page(at: 0))
            let crop = page.bounds(for: .cropBox)
            let thumbnailSize = NSSize(width: crop.height, height: crop.width)
            let before = try thumbnail(page, size: thumbnailSize)
            let selection = try #require(document.selectionForEntireDocument)
            #expect(selection.string?.contains("Rotation alignment") == true)
            let highlights = try PDFReaderAnnotations.highlights(for: selection, in: document)
            #expect(highlights.count == 1)
            for (selectedPage, annotation) in highlights { selectedPage.addAnnotation(annotation) }
            let saved = try #require(PDFDocument(data: document.dataRepresentation()!))
            let savedPage = try #require(saved.page(at: 0))
            #expect(savedPage.rotation == rotation)
            #expect(savedPage.bounds(for: .cropBox) == crop)
            #expect(saved.string == document.string)
            let after = try thumbnail(savedPage, size: thumbnailSize)
            #expect(after.pixelsWide == before.pixelsWide)
            #expect(after.pixelsHigh == before.pixelsHigh)

            // CoreText supplied the source glyph bounds when this independent
            // fixture was drawn. CoreGraphics maps them through the saved PDF's
            // crop and /Rotate, without using selection or annotation geometry.
            let pageReference = try #require(savedPage.pageRef)
            let target = CGRect(x: 0, y: 0, width: CGFloat(after.pixelsWide), height: CGFloat(after.pixelsHigh))
            let transform = pageReference.getDrawingTransform(.cropBox, rect: target, rotate: 0, preserveAspectRatio: true)
            let mapped = sourceInkBounds.applying(transform)
            let expectedInk = NSRect(x: mapped.minX, y: CGFloat(after.pixelsHigh) - mapped.maxY, width: mapped.width, height: mapped.height)
            let allowedHighlight = expectedInk.insetBy(dx: -6, dy: -6)
            var inkPixels = 0
            var highlightPixels = 0
            var outsidePixels = 0
            var highlightBounds = NSRect.null
            for y in 0..<after.pixelsHigh {
                for x in 0..<after.pixelsWide {
                    let original = try #require(before.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    let highlighted = try #require(after.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    let point = NSPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                    if original.redComponent < 0.3, original.greenComponent < 0.3, original.blueComponent < 0.3,
                        expectedInk.insetBy(dx: -1, dy: -1).contains(point)
                    {
                        inkPixels += 1
                    }
                    if highlighted.redComponent > 0.7, highlighted.greenComponent > 0.6, highlighted.blueComponent < 0.75,
                        original.blueComponent - highlighted.blueComponent > 0.15
                    {
                        highlightPixels += 1
                        if !allowedHighlight.contains(point) { outsidePixels += 1 }
                        highlightBounds = highlightBounds.union(NSRect(x: CGFloat(x), y: CGFloat(y), width: 1, height: 1))
                    }
                }
            }
            #expect(inkPixels > 50, "The independently transformed source location must contain rendered text at rotation \(rotation).")
            #expect(highlightPixels > 50, "The saved annotation must render a visible highlight at rotation \(rotation).")
            #expect(outsidePixels * 100 < highlightPixels * 5, "Highlight pixels must remain beside the selected source text at rotation \(rotation).")
            #expect(
                highlightBounds.insetBy(dx: -3, dy: -3).contains(expectedInk), "The rendered highlight must span the selected glyphs at rotation \(rotation).")
        }
    }

    @Test("A selection from a departed PDF cannot create highlights in the current PDF")
    func staleSelection() throws {
        let previous = try fixture()
        let current = try fixture()
        let selection = try #require(previous.selectionForEntireDocument)
        #expect(throws: PDFReaderAnnotationEditingError.self) {
            _ = try PDFReaderAnnotations.highlights(for: selection, in: current)
        }
        #expect(current.page(at: 0)?.annotations.isEmpty == true)
        #expect(previous.page(at: 0)?.annotations.isEmpty == true)
    }

    @Test("Departed, removed, and unsupported annotations cannot authorize editing")
    func staleAnnotation() throws {
        let previous = try fixture()
        let current = try fixture()
        let page = try #require(previous.page(at: 0))
        let comment = try PDFReaderAnnotations.comment(text: "Comment", at: NSPoint(x: 50, y: 50), on: page, in: previous)
        page.addAnnotation(comment)
        #expect(throws: PDFReaderAnnotationEditingError.self) {
            _ = try PDFReaderAnnotations.requireCurrent(comment, in: current)
        }
        #expect(try PDFReaderAnnotations.requireCurrent(comment, in: previous) === page)
        page.removeAnnotation(comment)
        #expect(throws: PDFReaderAnnotationEditingError.self) {
            _ = try PDFReaderAnnotations.requireCurrent(comment, in: previous)
        }
        let link = PDFAnnotation(bounds: NSRect(x: 50, y: 50, width: 100, height: 20), forType: .link, withProperties: nil)
        page.addAnnotation(link)
        #expect(throws: PDFReaderAnnotationEditingError.self) {
            _ = try PDFReaderAnnotations.requireCurrent(link, in: previous)
        }
    }

    @Test("Empty comments and locations outside the current page fail without mutation")
    func invalidComments() throws {
        let document = try fixture()
        let page = try #require(document.page(at: 0))
        for (text, point) in [(" \n", NSPoint(x: 50, y: 50)), ("Comment", NSPoint(x: -10, y: 50)), ("Comment", NSPoint(x: CGFloat.nan, y: 50))] {
            #expect(throws: PDFReaderAnnotationEditingError.self) {
                _ = try PDFReaderAnnotations.comment(text: text, at: point, on: page, in: document)
            }
        }
        #expect(page.annotations.isEmpty)
    }

    private func fixture() throws -> PDFDocument {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        for index in 0..<2 {
            context.beginPDFPage(nil)
            for (offset, text) in ["First line on page \(index + 1)", "Second line on page \(index + 1)"].enumerated() {
                context.textPosition = CGPoint(x: 50, y: 700 - offset * 40)
                let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 16)])
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return try #require(PDFDocument(data: data as Data))
    }

    private func thumbnail(_ page: PDFPage, size: NSSize) throws -> NSBitmapImageRep {
        let image = page.thumbnail(of: size, for: .cropBox)
        let rendered = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return NSBitmapImageRep(cgImage: rendered)
    }

    private func rotatedFixture(rotation: Int) throws -> (PDFDocument, CGRect) {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.textPosition = CGPoint(x: 130, y: 520)
        let font = try #require(NSFont(name: "Helvetica", size: 18))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Rotation alignment", attributes: [.font: font]))
        let inkBounds = CTLineGetImageBounds(line, context)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
        let document = try #require(PDFDocument(data: data as Data))
        let page = try #require(document.page(at: 0))
        page.setBounds(NSRect(x: 80, y: 120, width: 360, height: 540), for: .cropBox)
        page.rotation = rotation
        let normalized = try #require(PDFDocument(data: document.dataRepresentation()!))
        return (normalized, inkBounds)
    }
}
