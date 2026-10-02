import AppKit
import CoreText
import Foundation
import PDFKit
import Testing

@testable import ScholiumApp

@Suite("PDF annotation reading", .serialized)
@MainActor
struct PDFReaderAnnotationPresentationTests {
    @Test("Highlights on one page identify their distinct current passages without storing prose")
    func distinctPassages() throws {
        let document = try fixture()
        let first = try highlight("First target passage", in: document)
        let second = try highlight("Second target passage", in: document)
        let page = try #require(document.page(at: 0))
        first.contents = "A comment about the first passage"
        let contents = first.contents

        #expect(PDFReaderAnnotations.selectedPassage(for: first, on: page) == "First target passage")
        #expect(PDFReaderAnnotations.selectedPassage(for: second, on: page) == "Second target passage")
        #expect(first.contents == contents)
        #expect(second.contents == nil)
        #expect(page.annotations.count == 2)

        let serialized = try #require(document.dataRepresentation())
        let saved = try #require(PDFDocument(data: serialized))
        let savedPage = try #require(saved.page(at: 0))
        #expect(PDFReaderAnnotations.selectedPassage(for: savedPage.annotations[0], on: savedPage) == "First target passage")
        #expect(PDFReaderAnnotations.selectedPassage(for: savedPage.annotations[1], on: savedPage) == "Second target passage")
    }

    @Test("Separate quadrilaterals exclude intervening unmarked text from one highlight")
    func disconnectedPassages() throws {
        let document = try fixture()
        let selection = try #require(document.findString("First target passage", withOptions: []).first)
        selection.add(try #require(document.findString("Second target passage", withOptions: []).first))
        let prepared = try PDFReaderAnnotations.highlights(for: selection, in: document)
        let (page, annotation) = try #require(prepared.first)
        page.addAnnotation(annotation)
        #expect(annotation.quadrilateralPoints?.count == 8)
        let passage = PDFReaderAnnotations.selectedPassage(for: annotation, on: page)
        #expect(passage == "First target passage\nSecond target passage")
        #expect(!passage.contains("Intervening"))
    }

    @Test("Slanted quadrilaterals do not identify text in their unmarked bounding-box corners")
    func slantedQuad() throws {
        let document = try fixture(lines: [
            ("A inside", NSPoint(x: 95, y: 690)),
            ("Not marked", NSPoint(x: 300, y: 690)),
            ("B inside", NSPoint(x: 285, y: 600)),
        ])
        let page = try #require(document.page(at: 0))
        let annotation = PDFAnnotation(bounds: NSRect(x: 60, y: 590, width: 340, height: 120), forType: .highlight, withProperties: nil)
        annotation.quadrilateralPoints = [
            NSValue(point: NSPoint(x: 0, y: 120)), NSValue(point: NSPoint(x: 140, y: 120)),
            NSValue(point: NSPoint(x: 200, y: 0)), NSValue(point: NSPoint(x: 340, y: 0)),
        ]
        page.addAnnotation(annotation)
        let passage = PDFReaderAnnotations.selectedPassage(for: annotation, on: page)
        #expect(passage.contains("A inside"))
        #expect(passage.contains("B inside"))
        #expect(!passage.contains("Not marked"))
    }

    @Test("Highlight navigation uses exact page-local quadrilaterals, including cropped rotated pages")
    func preciseNavigation() throws {
        let document = try fixture()
        let page = try #require(document.page(at: 0))
        page.setBounds(NSRect(x: 20, y: 100, width: 500, height: 650), for: .cropBox)
        page.rotation = 270
        let selection = try #require(document.findString("Second target passage", withOptions: []).first)
        let exact = selection.bounds(for: page)
        let annotation = PDFAnnotation(bounds: page.bounds(for: .cropBox), forType: .highlight, withProperties: nil)
        let local = exact.offsetBy(dx: -annotation.bounds.minX, dy: -annotation.bounds.minY)
        annotation.quadrilateralPoints = [
            NSValue(point: NSPoint(x: local.minX, y: local.maxY)), NSValue(point: NSPoint(x: local.maxX, y: local.maxY)),
            NSValue(point: NSPoint(x: local.minX, y: local.minY)), NSValue(point: NSPoint(x: local.maxX, y: local.minY)),
        ]
        page.addAnnotation(annotation)
        #expect(PDFReaderAnnotations.navigationBounds(for: annotation, on: page) == exact)
        #expect(PDFReaderAnnotations.selectedPassage(for: annotation, on: page) == "Second target passage")
    }

    @Test("Reading existing comments does not grant mutation permission")
    func restrictedComments() throws {
        let source = try fixture()
        let page = try #require(source.page(at: 0))
        let contents = String(repeating: "Complete comment 注释 😀\n", count: 80)
        let comment = try PDFReaderAnnotations.comment(text: contents, at: NSPoint(x: 60, y: 600), on: page, in: source)
        page.addAnnotation(comment)
        let data = try #require(
            source.dataRepresentation(options: [
                PDFDocumentWriteOption.ownerPasswordOption: "synthetic-owner",
                PDFDocumentWriteOption.userPasswordOption: "synthetic-reader",
                PDFDocumentWriteOption.accessPermissionsOption: NSNumber(value: PDFAccessPermissions.allowsContentCopying.rawValue),
            ]))
        let restricted = try #require(PDFDocument(data: data))
        #expect(restricted.unlock(withPassword: "synthetic-reader"))
        #expect(!restricted.allowsCommenting)
        let restrictedPage = try #require(restricted.page(at: 0))
        let retained = try #require(restrictedPage.annotations.first)
        #expect(try PDFReaderAnnotations.requireReadable(retained, in: restricted) === restrictedPage)
        #expect(retained.contents == contents)
        #expect(throws: PDFReaderAnnotationEditingError.self) {
            _ = try PDFReaderAnnotations.requireCurrent(retained, in: restricted)
        }
        #expect(restrictedPage.annotations.count == 1)
        #expect(retained.contents == contents)
    }

    @Test("Missing highlight geometry never substitutes annotation comments or unmarked page text")
    func unavailablePassage() throws {
        let document = try fixture()
        let page = try #require(document.page(at: 0))
        let annotation = PDFAnnotation(bounds: page.bounds(for: .cropBox), forType: .highlight, withProperties: nil)
        // PDFKit's factory inserts a full-bounds /QuadPoints value. Remove it
        // explicitly to model an imported annotation with missing geometry.
        annotation.removeValue(forAnnotationKey: .quadPoints)
        #expect(annotation.value(forAnnotationKey: .quadPoints) == nil)
        annotation.contents = "Authored comment, not highlighted source"
        page.addAnnotation(annotation)
        #expect(PDFReaderAnnotations.selectedPassage(for: annotation, on: page).isEmpty)
        annotation.quadrilateralPoints = []
        #expect(PDFReaderAnnotations.selectedPassage(for: annotation, on: page).isEmpty)
        let other = try fixture()
        #expect(throws: PDFReaderAnnotationEditingError.self) {
            _ = try PDFReaderAnnotations.requireReadable(annotation, in: other)
        }
        page.removeAnnotation(annotation)
        #expect(throws: PDFReaderAnnotationEditingError.self) {
            _ = try PDFReaderAnnotations.requireReadable(annotation, in: document)
        }
    }

    private func highlight(_ text: String, in document: PDFDocument) throws -> PDFAnnotation {
        let selection = try #require(document.findString(text, withOptions: []).first)
        let (page, annotation) = try #require(PDFReaderAnnotations.highlights(for: selection, in: document).first)
        page.addAnnotation(annotation)
        return annotation
    }

    private func fixture(lines: [(String, NSPoint)]? = nil) throws -> PDFDocument {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        let values =
            lines ?? [
                ("First target passage", NSPoint(x: 50, y: 700)),
                ("Intervening text must stay out", NSPoint(x: 50, y: 660)),
                ("Second target passage", NSPoint(x: 50, y: 620)),
            ]
        let font = try #require(NSFont(name: "Helvetica", size: 16))
        for (text, point) in values {
            context.textPosition = point
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font])), context)
        }
        context.endPDFPage()
        context.closePDF()
        return try #require(PDFDocument(data: data as Data))
    }
}
