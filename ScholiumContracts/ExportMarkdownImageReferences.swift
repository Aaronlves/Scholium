import Foundation
import Markdown

/// The image destinations that the export renderer may encounter in one exact
/// Note source. Both attachment preparation and export validation consume this
/// projection so a reference-style image cannot disappear between the two.
public enum ExportMarkdownImageReferences {
    public enum Reference: Hashable, Sendable {
        case local(SourceResourceReferences.File)
        case remote(String)
        case unavailable(String)
    }

    public static func references(in document: NoteDocument) -> [Reference] {
        // The export service shows malformed frontmatter as escaped source,
        // without interpreting any Markdown inside it.
        guard document.frontmatterState != .malformed else { return [] }
        var references: [Reference] = []
        collect(in: document, depth: 0, into: &references)
        var seen: Set<Reference> = []
        return references.filter { seen.insert($0).inserted }
    }

    private static func collect(
        in document: NoteDocument,
        depth: Int,
        into references: inout [Reference]
    ) {
        guard depth < 12 else {
            references.append(.unavailable("Nested rendering limit reached."))
            return
        }
        var walker = ImageWalker(noteRelativePath: document.relativePath)
        walker.visit(Document(parsing: document.body))
        references.append(contentsOf: walker.references)

        let semantic = MarkdownSemanticDocument(parsing: document)
        for definition in semantic.footnoteDefinitions where definition.ordinal != nil {
            collect(
                in: NoteDocument(
                    relativePath: document.relativePath,
                    rawContent: definition.content
                ),
                depth: depth + 1,
                into: &references
            )
        }
        for callout in semantic.callouts {
            collect(
                in: NoteDocument(
                    relativePath: document.relativePath,
                    rawContent: callout.bodySource
                ),
                depth: depth + 1,
                into: &references
            )
        }
        for annotation in semantic.links.compactMap(\.annotation) {
            collect(
                in: NoteDocument(
                    relativePath: document.relativePath,
                    rawContent: annotation.markdown
                ),
                depth: depth + 1,
                into: &references
            )
        }
    }
}

private struct ImageWalker: MarkupWalker {
    let noteRelativePath: String
    var references: [ExportMarkdownImageReferences.Reference] = []

    mutating func visitImage(_ image: Markdown.Image) {
        guard let source = image.source, !source.isEmpty else {
            references.append(.unavailable("an unresolved Markdown image"))
            return
        }
        if source.hasPrefix("//") {
            references.append(.remote(source))
            return
        }
        if let scheme = URLComponents(string: source)?.scheme?.lowercased() {
            references.append(
                scheme == "http" || scheme == "https"
                    ? .remote(source) : .unavailable(source)
            )
            return
        }
        if let file = SourceResourceReferences.file(
            destination: source,
            noteRelativePath: noteRelativePath,
            isImage: true
        ) {
            references.append(.local(file))
        } else {
            references.append(.unavailable(source))
        }
    }
}
