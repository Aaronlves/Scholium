import Foundation
import ScholiumContracts

/// Disposable, source-located content for the one native Document preview.
/// Local footnotes and annotations are rebuilt from the checked editor source;
/// destination excerpts are admitted only for the catalog's exact revision.
struct NativeDocumentPreview {
    let span: SourceSpan
    let title: String
    let metadata: String?
    let bodyHTML: String

    var html: String {
        let metadataHTML =
            metadata.map {
                "<p class=\"scholium-preview-metadata\">\(Self.escape($0))</p>"
            } ?? ""
        return """
            <aside class="scholium-preview-popover" role="note" aria-labelledby="scholium-preview-title">
              <h2 id="scholium-preview-title" class="scholium-preview-title">\(Self.escape(title))</h2>
              \(metadataHTML)
              <div class="scholium-preview-body scholium-document">\(bodyHTML)</div>
            </aside>
            """
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

enum NativeDocumentPreviewBuilder {
    static func build(source: String, relativePath: String, catalog: DocumentPreviewCatalog?) -> [NativeDocumentPreview] {
        let document = NoteDocument(relativePath: relativePath, rawContent: source)
        let semantic = MarkdownSemanticDocument(parsing: document)
        let localization = WebKitInterfaceLocalization.current()
        var previews: [NativeDocumentPreview] = []

        if catalog?.source.relativePath == relativePath,
            catalog?.sourceFingerprint == DocumentFingerprint(content: source)
        {
            previews += (catalog?.links ?? []).filter { $0.syntax != .embed }.map { link in
                NativeDocumentPreview(
                    span: link.sourceSpan, title: link.title,
                    metadata: link.fragment, bodyHTML: link.htmlBody)
            }
        }

        let definitions = Dictionary(
            semantic.footnoteDefinitions.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first })
        for reference in semantic.footnoteReferences {
            guard let definition = definitions[reference.identifier] else { continue }
            let title = localization.string("Footnote {ordinal}")
                .replacingOccurrences(of: "{ordinal}", with: String(reference.ordinal))
            previews.append(
                NativeDocumentPreview(
                    span: reference.span, title: title, metadata: nil,
                    bodyHTML: render(definition.content, relativePath: "footnote-preview.md")))
        }

        for link in semantic.links {
            guard let annotation = link.annotation else { continue }
            let title = link.alias ?? (link.target.isEmpty ? link.fragment ?? "Link" : link.target)
            previews.append(
                NativeDocumentPreview(
                    span: annotation.span, title: title,
                    metadata: localization.string("Link Annotation"),
                    bodyHTML: render(annotation.markdown, relativePath: "link-annotation-preview.md")))
        }
        return previews
    }

    private static func render(_ source: String, relativePath: String) -> String {
        SafeMarkdownRenderer.render(NoteDocument(relativePath: relativePath, rawContent: source)).htmlBody
    }
}
