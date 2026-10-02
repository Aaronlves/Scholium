import AppKit
import Foundation
import PDFKit

enum PDFReaderAnnotationEditingError: LocalizedError {
    case commentingRestricted
    case selectionUnavailable
    case annotationUnavailable
    case emptyComment

    var errorDescription: String? {
        switch self {
        case .commentingRestricted:
            String(localized: "This PDF does not permit annotations.", table: "Localizable", bundle: .module)
        case .selectionUnavailable:
            String(localized: "Select text in the current PDF to highlight it.", table: "Localizable", bundle: .module)
        case .annotationUnavailable:
            String(localized: "This annotation is no longer available in the current PDF.", table: "Localizable", bundle: .module)
        case .emptyComment:
            String(localized: "Enter a comment before saving it.", table: "Localizable", bundle: .module)
        }
    }
}

/// PDFKit geometry, derived passage text, and mutation only. The reader session owns revision checks,
/// durable saving, and admission of an edit into its current document.
@MainActor
enum PDFReaderAnnotations {
    static func highlights(
        for selection: PDFSelection,
        in document: PDFDocument,
        color: NSColor = .yellow
    ) throws -> [(page: PDFPage, annotation: PDFAnnotation)] {
        try requireCommenting(in: document)
        guard selection.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
            !selection.pages.isEmpty,
            selection.pages.allSatisfy({ $0.document === document })
        else { throw PDFReaderAnnotationEditingError.selectionUnavailable }

        // One standard markup annotation per page, with a separate quadrilateral
        // for every selected line. A multiline bounding rectangle alone would
        // also paint unselected whitespace and neighboring text.
        let lines = selection.selectionsByLine()
        let prepared = selection.pages.compactMap { page -> (PDFPage, PDFAnnotation)? in
            let crop = page.bounds(for: .cropBox)
            let rectangles = lines.filter { $0.pages.contains(where: { $0 === page }) }
                .map { $0.bounds(for: page).intersection(crop) }
                .filter { !$0.isNull && !$0.isEmpty && finite($0) }
            guard let first = rectangles.first else { return nil }
            let bounds = rectangles.dropFirst().reduce(first) { $0.union($1) }
            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            annotation.color = color
            annotation.quadrilateralPoints = rectangles.flatMap { rectangle in
                let local = rectangle.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
                return [
                    NSValue(point: NSPoint(x: local.minX, y: local.maxY)),
                    NSValue(point: NSPoint(x: local.maxX, y: local.maxY)),
                    NSValue(point: NSPoint(x: local.minX, y: local.minY)),
                    NSValue(point: NSPoint(x: local.maxX, y: local.minY)),
                ]
            }
            identify(annotation)
            return (page, annotation)
        }
        guard !prepared.isEmpty else { throw PDFReaderAnnotationEditingError.selectionUnavailable }
        return prepared
    }

    static func comment(
        text: String,
        at point: NSPoint,
        on page: PDFPage,
        in document: PDFDocument
    ) throws -> PDFAnnotation {
        try requireCommenting(in: document)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PDFReaderAnnotationEditingError.emptyComment
        }
        let crop = page.bounds(for: .cropBox)
        guard page.document === document,
            point.x.isFinite, point.y.isFinite,
            crop.contains(point), finite(crop), crop.width > 0, crop.height > 0
        else { throw PDFReaderAnnotationEditingError.annotationUnavailable }
        let size = min(24, crop.width, crop.height)
        let bounds = NSRect(
            x: min(max(point.x - size / 2, crop.minX), crop.maxX - size),
            y: min(max(point.y - size / 2, crop.minY), crop.maxY - size),
            width: size, height: size
        )
        let annotation = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
        annotation.iconType = .comment
        annotation.color = .yellow
        annotation.contents = text
        identify(annotation)
        return annotation
    }

    static func hasType(_ annotation: PDFAnnotation, _ type: PDFAnnotationSubtype) -> Bool {
        annotation.value(forAnnotationKey: .subtype) as? String == type.rawValue
    }

    static func isEditable(_ annotation: PDFAnnotation) -> Bool {
        hasType(annotation, .highlight) || hasType(annotation, .text)
    }

    static func requireReadable(_ annotation: PDFAnnotation, in document: PDFDocument) throws -> PDFPage {
        guard isEditable(annotation),
            let page = annotation.page, page.document === document,
            page.annotations.contains(where: { $0 === annotation })
        else { throw PDFReaderAnnotationEditingError.annotationUnavailable }
        return page
    }

    static func requireCurrent(_ annotation: PDFAnnotation, in document: PDFDocument) throws -> PDFPage {
        try requireCommenting(in: document)
        return try requireReadable(annotation, in: document)
    }

    /// A label is a projection of the current PDF, never annotation contents or
    /// a stored excerpt. Separate quads exclude text between marked passages;
    /// checking glyph centers also excludes corners of a slanted quad's box.
    static func selectedPassage(for annotation: PDFAnnotation, on page: PDFPage) -> String {
        guard hasType(annotation, .highlight), annotation.page === page else { return "" }
        var seen = IndexSet()
        var passages: [String] = []
        for points in quadrilaterals(for: annotation) {
            let path = CGMutablePath()
            path.addLines(between: [points[0], points[1], points[3], points[2]])
            path.closeSubpath()
            guard let selection = page.selection(for: path.boundingBoxOfPath) else { continue }
            var selected = IndexSet()
            for rangeIndex in 0..<selection.numberOfTextRanges(on: page) {
                let range = selection.range(at: rangeIndex, on: page)
                guard range.location != NSNotFound, range.location <= page.numberOfCharacters,
                    range.length <= page.numberOfCharacters - range.location
                else { continue }
                for index in range.location..<NSMaxRange(range) where !seen.contains(index) {
                    // PDFKit's characterBounds index can diverge from its text
                    // ranges after inserted line separators. Keep text and
                    // geometry in the same PDFSelection range coordinate space.
                    if let glyph = page.selection(for: NSRange(location: index, length: 1)) {
                        let bounds = glyph.bounds(for: page)
                        if finite(bounds), !bounds.isEmpty,
                            path.contains(CGPoint(x: bounds.midX, y: bounds.midY))
                        {
                            selected.insert(index)
                        }
                    }
                }
            }
            // PDFKit can insert whitespace without a glyph rectangle. Retain
            // those exact separators between selected glyphs, without pulling
            // unselected writing into a disconnected selection.
            let ranges = selected.rangeView.map { NSRange($0) }
            var joined: [NSRange] = []
            for range in ranges {
                if let previous = joined.last {
                    let gap = NSRange(location: NSMaxRange(previous), length: range.location - NSMaxRange(previous))
                    if let text = page.selection(for: gap)?.string, text.allSatisfy(\.isWhitespace) {
                        joined[joined.count - 1] = NSRange(location: previous.location, length: NSMaxRange(range) - previous.location)
                        continue
                    }
                }
                joined.append(range)
            }
            for range in joined {
                if let text = page.selection(for: range)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    passages.append(text)
                }
            }
            seen.formUnion(selected)
        }
        return passages.joined(separator: "\n")
    }

    static func navigationBounds(for annotation: PDFAnnotation, on page: PDFPage) -> NSRect {
        let quads = quadrilaterals(for: annotation)
        let bounds: NSRect
        if hasType(annotation, .highlight), !quads.isEmpty {
            let path = CGMutablePath()
            path.addLines(between: quads.flatMap { $0 })
            bounds = path.boundingBoxOfPath
        } else {
            bounds = annotation.bounds
        }
        guard finite(bounds), !bounds.isEmpty else { return .null }
        return bounds.intersection(page.bounds(for: .cropBox))
    }

    private static func quadrilaterals(for annotation: PDFAnnotation) -> [[NSPoint]] {
        // The convenience getter can synthesize a bounds-sized quad when the
        // PDF dictionary contains no /QuadPoints. That is not marked-text proof.
        guard annotation.value(forAnnotationKey: .quadPoints) != nil,
            let values = annotation.quadrilateralPoints, !values.isEmpty, values.count.isMultiple(of: 4),
            finite(annotation.bounds)
        else { return [] }
        return stride(from: 0, to: values.count, by: 4).compactMap { offset in
            let points = values[offset..<(offset + 4)].map {
                NSPoint(x: $0.pointValue.x + annotation.bounds.minX, y: $0.pointValue.y + annotation.bounds.minY)
            }
            guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
            return points
        }
    }

    private static func requireCommenting(in document: PDFDocument) throws {
        guard !document.isLocked, document.allowsCommenting else {
            throw PDFReaderAnnotationEditingError.commentingRestricted
        }
    }

    private static func identify(_ annotation: PDFAnnotation) {
        annotation.setValue("scholium-\(UUID().uuidString.lowercased())", forAnnotationKey: .name)
        annotation.modificationDate = Date()
    }

    private static func finite(_ rectangle: NSRect) -> Bool {
        rectangle.origin.x.isFinite && rectangle.origin.y.isFinite
            && rectangle.size.width.isFinite && rectangle.size.height.isFinite
    }
}
