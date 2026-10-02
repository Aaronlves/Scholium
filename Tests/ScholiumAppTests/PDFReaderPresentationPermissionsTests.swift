import AppKit
import PDFKit
import Testing

@testable import ScholiumApp

@Suite("PDF form presentation permissions", .serialized)
@MainActor
struct PDFReaderPresentationPermissionsTests {
    @Test("Presentation locks widgets while serialized flags and values retain their originals")
    func widgetPermissionsRoundTrip() throws {
        let document = try fixture()
        let page = try #require(document.page(at: 0))
        let editable = widget(name: "Editable", flags: 4096, value: "Retained value 注释 😀")
        let readOnly = widget(name: "Read only", flags: 4097, value: "Original locked value")
        page.addAnnotation(editable)
        page.addAnnotation(readOnly)
        let protection = PDFReaderPresentationPermissions(document: document)
        defer { protection.invalidate() }

        #expect(editable.isReadOnly)
        #expect(readOnly.isReadOnly)
        #expect(!editable.isActivatableTextField)
        let data = try #require(
            protection.withOriginalPermissions {
                #expect(!editable.isReadOnly)
                #expect(readOnly.isReadOnly)
                #expect(flags(editable) == 4096)
                #expect(flags(readOnly) == 4097)
                return document.dataRepresentation()
            })
        #expect(editable.isReadOnly)
        #expect(readOnly.isReadOnly)
        let reloaded = try #require(PDFDocument(data: data))
        let annotations = try #require(reloaded.page(at: 0)).annotations
        let savedEditable = try #require(annotations.first { $0.fieldName == "Editable" })
        let savedReadOnly = try #require(annotations.first { $0.fieldName == "Read only" })
        #expect(!savedEditable.isReadOnly)
        #expect(savedReadOnly.isReadOnly)
        #expect(flags(savedEditable) == 4096)
        #expect(flags(savedReadOnly) == 4097)
        #expect(savedEditable.widgetStringValue == "Retained value 注释 😀")
        #expect(savedReadOnly.widgetStringValue == "Original locked value")
        #expect(savedEditable.widgetDefaultStringValue == "Default Editable")
    }

    @Test("Nested serialization and throwing callbacks always reapply protection")
    func serializationScope() throws {
        let document = try fixture()
        let annotation = widget(name: "Editable", flags: 0, value: "Original")
        try #require(document.page(at: 0)).addAnnotation(annotation)
        let protection = PDFReaderPresentationPermissions(document: document)
        defer { protection.invalidate() }
        protection.withOriginalPermissions {
            #expect(!annotation.isReadOnly)
            protection.withOriginalPermissions { #expect(!annotation.isReadOnly) }
            #expect(!annotation.isReadOnly)
        }
        #expect(annotation.isReadOnly)
        #expect(throws: SyntheticError.self) {
            try protection.withOriginalPermissions {
                #expect(!annotation.isReadOnly)
                throw SyntheticError.serialization
            }
        }
        #expect(annotation.isReadOnly)
        #expect(annotation.widgetStringValue == "Original")
    }

    @Test("Invalidation restores flag presence and values without changing unrelated annotations")
    func invalidationRestoresOriginals() throws {
        let document = try fixture()
        let page = try #require(document.page(at: 0))
        let annotation = widget(name: "No flags", flags: 0, value: "Unchanged")
        annotation.removeValue(forAnnotationKey: .widgetFieldFlags)
        let comment = PDFAnnotation(bounds: NSRect(x: 20, y: 20, width: 24, height: 24), forType: .text, withProperties: nil)
        comment.contents = "Unrelated comment"
        page.addAnnotation(annotation)
        page.addAnnotation(comment)
        #expect(flags(annotation) == nil)
        let protection = PDFReaderPresentationPermissions(document: document)
        #expect(annotation.isReadOnly)
        protection.withOriginalPermissions {
            #expect(flags(annotation) == nil)
            #expect(!annotation.isReadOnly)
        }
        #expect(annotation.isReadOnly)
        protection.invalidate()
        protection.invalidate()
        #expect(!annotation.isReadOnly)
        #expect(flags(annotation) == nil)
        #expect(annotation.widgetStringValue == "Unchanged")
        #expect(annotation.widgetDefaultStringValue == "Default No flags")
        #expect(comment.contents == "Unrelated comment")
        protection.withOriginalPermissions { #expect(!annotation.isReadOnly) }
        #expect(!annotation.isReadOnly)
    }

    @Test("Related widgets retain inherited field permissions and values after serialization")
    func inheritedPermissionsRoundTrip() throws {
        let document = try inheritedFieldFixture()
        let originalData = try #require(document.dataRepresentation())
        let baseline = try #require(PDFDocument(data: originalData))
        let originalWidgets = try #require(baseline.page(at: 0)).annotations
        let originalFlags = originalWidgets.map(flags)
        let originalParentFlags = originalWidgets.map(parentFlags)
        let annotations = try #require(document.page(at: 0)).annotations
        #expect(annotations.count == 2)
        #expect(annotations.allSatisfy { !$0.isReadOnly })
        let protection = PDFReaderPresentationPermissions(document: document)
        defer { protection.invalidate() }
        #expect(annotations.allSatisfy { $0.isReadOnly })
        let data = try #require(protection.withOriginalPermissions { document.dataRepresentation() })
        let reloaded = try #require(PDFDocument(data: data))
        let savedWidgets = try #require(reloaded.page(at: 0)).annotations
        #expect(savedWidgets.map(flags) == originalFlags)
        #expect(savedWidgets.map(parentFlags) == originalParentFlags)
        #expect(savedWidgets.map(\.widgetStringValue) == originalWidgets.map(\.widgetStringValue))
        #expect(savedWidgets.allSatisfy { !$0.isReadOnly })
        #expect(annotations.allSatisfy { $0.isReadOnly })
    }

    private enum SyntheticError: Error { case serialization }

    private func flags(_ annotation: PDFAnnotation) -> Int? {
        (annotation.annotationKeyValues[PDFAnnotationKey.widgetFieldFlags.rawValue] as? NSNumber)?.intValue
    }

    private func parentFlags(_ annotation: PDFAnnotation) -> Int? {
        let parent = annotation.value(forAnnotationKey: .parent) as? [AnyHashable: Any]
        return (parent?[PDFAnnotationKey.widgetFieldFlags.rawValue] as? NSNumber)?.intValue
    }

    private func widget(name: String, flags: Int, value: String) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: NSRect(x: 50, y: 650, width: 250, height: 35), forType: .widget, withProperties: nil)
        annotation.widgetFieldType = .text
        annotation.fieldName = name
        annotation.widgetStringValue = value
        annotation.widgetDefaultStringValue = "Default \(name)"
        annotation.setValue(NSNumber(value: flags), forAnnotationKey: .widgetFieldFlags)
        return annotation
    }

    private func fixture() throws -> PDFDocument {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return try #require(PDFDocument(data: data as Data))
    }

    private func inheritedFieldFixture() throws -> PDFDocument {
        // Two page widgets share an AcroForm field. /Ff and /V exist only on
        // their parent, so protection must not save a new child permission.
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R /AcroForm 5 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /Helv 7 0 R >> >> /Contents 4 0 R /Annots [8 0 R 9 0 R] >>",
            "<< /Length 0 >>\nstream\n\nendstream",
            "<< /Fields [6 0 R] /DA (/Helv 12 Tf 0 g) /DR << /Font << /Helv 7 0 R >> >> >>",
            "<< /FT /Tx /T (Related field) /V (Retained parent value) /DV (Default parent value) /Ff 4096 /Kids [8 0 R 9 0 R] >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Type /Annot /Subtype /Widget /Rect [50 650 300 685] /Parent 6 0 R /P 3 0 R /F 4 >>",
            "<< /Type /Annot /Subtype /Widget /Rect [50 550 300 585] /Parent 6 0 R /P 3 0 R /F 4 >>",
        ]
        var data = Data("%PDF-1.7\n".utf8)
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(data.count)
            data.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
        }
        let crossReference = data.count
        data.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
        for offset in offsets { data.append(Data(String(format: "%010d 00000 n \n", offset).utf8)) }
        data.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(crossReference)\n%%EOF\n".utf8))
        return try #require(PDFDocument(data: data))
    }
}
