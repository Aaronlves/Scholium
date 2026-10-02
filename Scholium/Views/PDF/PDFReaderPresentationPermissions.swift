import PDFKit

/// Locks native form widgets for reading without changing their saved permissions.
/// One instance belongs to one loaded document session, before PDFView receives it.
@MainActor
final class PDFReaderPresentationPermissions {
    private struct Widget {
        let annotation: PDFAnnotation
        let isReadOnly: Bool
        let fieldFlags: Any?

        func restore() {
            annotation.isReadOnly = isReadOnly
            if let fieldFlags {
                annotation.setValue(fieldFlags, forAnnotationKey: .widgetFieldFlags)
            } else {
                // Setting readOnly can introduce /Ff. Preserve its absence too.
                annotation.removeValue(forAnnotationKey: .widgetFieldFlags)
            }
        }
    }

    private var widgets: [Widget]
    private var serializationDepth = 0
    private var isActive = true

    init(document: PDFDocument) {
        // Capture every widget before changing any: a form can have related fields.
        widgets = (0..<document.pageCount).flatMap { index in
            (document.page(at: index)?.annotations ?? []).compactMap { annotation -> Widget? in
                guard PDFReaderAnnotations.hasType(annotation, .widget) else { return nil }
                return Widget(
                    annotation: annotation,
                    isReadOnly: annotation.isReadOnly,
                    fieldFlags: annotation.annotationKeyValues[PDFAnnotationKey.widgetFieldFlags.rawValue]
                )
            }
        }
        applyProtection()
    }

    /// The synchronous main-actor boundary admits no user event or task suspension
    /// while PDFKit serializes the original permissions. Never await inside it.
    func withOriginalPermissions<Result>(_ body: () throws -> Result) rethrows -> Result {
        guard isActive else { return try body() }
        if serializationDepth == 0 { restoreOriginalPermissions() }
        serializationDepth += 1
        defer {
            serializationDepth -= 1
            if isActive, serializationDepth == 0 { applyProtection() }
        }
        return try body()
    }

    /// Restore the document before its view/session is released. Safe to repeat.
    func invalidate() {
        guard isActive else { return }
        isActive = false
        restoreOriginalPermissions()
        widgets.removeAll()
    }

    private func restoreOriginalPermissions() {
        for widget in widgets { widget.restore() }
    }

    private func applyProtection() {
        for widget in widgets { widget.annotation.isReadOnly = true }
    }
}
