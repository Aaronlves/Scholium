import Foundation

public struct DocumentLinkPreview: Codable, Hashable, Sendable {
    public let sourceSpan: SourceSpan
    public let target: VaultQualifiedNoteID
    public let targetFingerprint: DocumentFingerprint
    public let title: String
    public let syntax: LinkSyntax
    public let fragment: String?
    public let htmlBody: String

    public init(
        sourceSpan: SourceSpan,
        target: VaultQualifiedNoteID,
        targetFingerprint: DocumentFingerprint,
        title: String,
        syntax: LinkSyntax,
        fragment: String?,
        htmlBody: String
    ) {
        self.sourceSpan = sourceSpan
        self.target = target
        self.targetFingerprint = targetFingerprint
        self.title = title
        self.syntax = syntax
        self.fragment = fragment
        self.htmlBody = htmlBody
    }
}

public struct DocumentPreviewCatalog: Codable, Hashable, Sendable {
    public static let currentContractVersion = 3

    public let contractVersion: Int
    public let graphGeneration: Int
    public let source: VaultQualifiedNoteID
    public let sourceFingerprint: DocumentFingerprint
    public let links: [DocumentLinkPreview]

    public init(
        graphGeneration: Int,
        source: VaultQualifiedNoteID,
        sourceFingerprint: DocumentFingerprint,
        links: [DocumentLinkPreview]
    ) {
        contractVersion = Self.currentContractVersion
        self.graphGeneration = graphGeneration
        self.source = source
        self.sourceFingerprint = sourceFingerprint
        self.links = links
    }
}

/// Builds a bounded, disposable presentation projection from the canonical
/// graph and immutable committed document snapshots. It never resolves links
/// independently and never becomes writable document authority.
public enum DocumentPreviewCatalogBuilder {
    public static let maximumLinkCount = 128
    public static let maximumExcerptCharacters = 1_600

    public static func build(
        source: VaultQualifiedNoteID,
        sourceFingerprint: DocumentFingerprint,
        graph: GraphSnapshot,
        documents: [VaultQualifiedNoteID: NoteDocument],
        profiles: [VaultQualifiedNoteID: SchemaProfileID] = [:],
        metadata: [VaultQualifiedNoteID: NoteMetadataSnapshot] = [:]
    ) -> DocumentPreviewCatalog {
        guard graph.contractVersion == GraphSnapshot.currentContractVersion else {
            return DocumentPreviewCatalog(
                graphGeneration: graph.generation,
                source: source,
                sourceFingerprint: sourceFingerprint,
                links: []
            )
        }

        let links = (graph.outgoing[source] ?? [])
            .sorted { left, right in
                left.occurrence.span.utf16LowerBound < right.occurrence.span.utf16LowerBound
            }
            .prefix(maximumLinkCount)
            .compactMap { edge -> DocumentLinkPreview? in
                guard let destination = edge.destination,
                      let target = documents[destination.note] else { return nil }
                let sourceForPresentation = presentedSource(
                    for: edge.occurrence,
                    destination: destination,
                    in: target
                )
                guard !sourceForPresentation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                let fragment = NoteDocument(
                    relativePath: target.relativePath,
                    rawContent: sourceForPresentation
                )
                let rendered = SafeMarkdownRenderer.render(fragment).htmlBody
                let title = ResearchNoteTitleResolver.resolve(document: target)
                return DocumentLinkPreview(
                    sourceSpan: edge.occurrence.linkSpan,
                    target: destination.note,
                    targetFingerprint: target.fingerprint,
                    title: title,
                    syntax: edge.occurrence.syntax,
                    fragment: destination.fragment,
                    htmlBody: rendered
                )
            }
        return DocumentPreviewCatalog(
            graphGeneration: graph.generation,
            source: source,
            sourceFingerprint: sourceFingerprint,
            links: Array(links)
        )
    }

    private static func presentedSource(
        for occurrence: LinkOccurrence,
        destination: LinkDestination,
        in document: NoteDocument
    ) -> String {
        if occurrence.syntax == .embed {
            return document.body
        }
        if let span = destination.span {
            let source = document.rawContent as NSString
            let start = max(0, min(span.utf16LowerBound, source.length))
            let end = min(source.length, start + maximumExcerptCharacters)
            guard end > start else { return "" }
            return source.substring(with: NSRange(location: start, length: end - start))
        }
        return String(document.body.prefix(maximumExcerptCharacters))
    }
}
