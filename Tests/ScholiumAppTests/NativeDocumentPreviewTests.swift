import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Native document preview projection")
struct NativeDocumentPreviewTests {
    @Test("Edit projects link, footnote and annotation from one checked source")
    func threeSourceLocatedPreviews() throws {
        let source = "Claim[^basis] [[Target|别名]]{{中文 **注释**.}}\n\n[^basis]: A **rendered** footnote.\n"
        let note = NoteDocument(relativePath: "Source.md", rawContent: source)
        let semantic = MarkdownSemanticDocument(parsing: note)
        let link = try #require(semantic.links.first)
        let sourceID = VaultQualifiedNoteID(vaultID: UUID(), relativePath: note.relativePath)
        let target = VaultQualifiedNoteID(vaultID: sourceID.vaultID, relativePath: "Target.md")
        let catalog = DocumentPreviewCatalog(
            graphGeneration: 1, source: sourceID, sourceFingerprint: note.fingerprint,
            links: [
                DocumentLinkPreview(
                    sourceSpan: link.linkSpan, target: target,
                    targetFingerprint: DocumentFingerprint(content: "Target body"),
                    title: "A < B", syntax: .wikilink, fragment: "Claim",
                    htmlBody: "<p>Target body.</p>")
            ])

        let previews = NativeDocumentPreviewBuilder.build(
            source: source, relativePath: note.relativePath, catalog: catalog)
        #expect(previews.count == 3)
        let linkedNote = try #require(previews.first { $0.span == link.linkSpan })
        #expect(linkedNote.html.contains("A &lt; B"))
        #expect(linkedNote.html.contains("scholium-preview-metadata"))
        #expect(linkedNote.html.contains("Target body."))
        let footnote = try #require(previews.first { $0.span == semantic.footnoteReferences[0].span })
        #expect(footnote.title.contains("1"))
        #expect(footnote.bodyHTML.contains("<strong>rendered</strong>"))
        let annotationSpan = try #require(link.annotation?.span)
        let annotation = try #require(previews.first { $0.span == annotationSpan })
        #expect(annotation.metadata == WebKitInterfaceLocalization.current().string("Link Annotation"))
        #expect(annotation.bodyHTML.contains("<strong>注释</strong>"))
    }

    @Test("A stale link catalog is excluded while local footnotes and annotations remain current")
    func staleCatalogDoesNotAuthorizeLinkPreview() throws {
        let source = "[[Target]]{{Current annotation.}}[^one]\n\n[^one]: Current footnote.\n"
        let note = NoteDocument(relativePath: "Source.md", rawContent: source)
        let link = try #require(MarkdownSemanticDocument(parsing: note).links.first)
        let sourceID = VaultQualifiedNoteID(vaultID: UUID(), relativePath: note.relativePath)
        let target = VaultQualifiedNoteID(vaultID: sourceID.vaultID, relativePath: "Target.md")
        let catalog = DocumentPreviewCatalog(
            graphGeneration: 1, source: sourceID,
            sourceFingerprint: DocumentFingerprint(content: "older source"),
            links: [
                DocumentLinkPreview(
                    sourceSpan: link.linkSpan, target: target,
                    targetFingerprint: DocumentFingerprint(content: "Target"),
                    title: "Target", syntax: .wikilink, fragment: nil,
                    htmlBody: "<p>Stale target.</p>")
            ])
        let previews = NativeDocumentPreviewBuilder.build(
            source: source, relativePath: note.relativePath, catalog: catalog)
        #expect(previews.count == 2)
        #expect(!previews.contains { $0.html.contains("Stale target.") })
        #expect(previews.contains { $0.bodyHTML.contains("Current footnote.") })
        #expect(previews.contains { $0.bodyHTML.contains("Current annotation.") })
    }
}
