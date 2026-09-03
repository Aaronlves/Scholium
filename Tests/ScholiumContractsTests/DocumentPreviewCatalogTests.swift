import Foundation
import Testing
@testable import ScholiumContracts

@Suite("Document preview catalog")
struct DocumentPreviewCatalogTests {
    @Test("Resolved graph edges produce bounded inert previews while broken links fail closed")
    func resolvedLinksOnly() {
        let vaultID = UUID()
        let sourceID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "A.md")
        let targetID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "B.md")
        let source = NoteDocument(
            relativePath: sourceID.relativePath,
            rawContent: "[[B#Claim]]{{Why this claim matters.}} and [[Missing]]"
        )
        let target = NoteDocument(
            relativePath: targetID.relativePath,
            rawContent: "---\ntitle: Target B\n---\n# Claim\n\n**Rendered** preview.\n"
        )
        let semantic = [
            sourceID: MarkdownSemanticDocument(parsing: source),
            targetID: MarkdownSemanticDocument(parsing: target),
        ]
        let graph = LinkGraphBuilder.build(
            generation: 7,
            catalog: [
                LinkCatalogNote(
                    id: sourceID,
                    title: "A",
                    aliases: [],
                    headings: [],
                    blockAnchors: [:]
                ),
                LinkCatalogNote(vaultID: vaultID, document: target, semantic: semantic[targetID]),
            ],
            documents: semantic
        )
        let preview = DocumentPreviewCatalogBuilder.build(
            source: sourceID,
            sourceFingerprint: source.fingerprint,
            graph: graph,
            documents: [sourceID: source, targetID: target],
            profiles: [targetID: .analysis],
            metadata: [targetID: NoteMetadataSnapshot(
                record: NoteMetadataRecord(
                    noteID: UUID(),
                    fields: ["title": .string("Target B")]
                ),
                revision: DocumentFingerprint(content: "target-metadata")
            )]
        )

        #expect(preview.contractVersion == 3)
        #expect(preview.graphGeneration == 7)
        #expect(preview.links.count == 1)
        #expect(preview.links[0].target == targetID)
        #expect(preview.links[0].title == "B")
        #expect(preview.links[0].syntax == .wikilink)
        #expect(preview.links[0].fragment == "Claim")
        #expect(preview.links[0].htmlBody.contains("<strong>Rendered</strong>"))
        #expect(!preview.links[0].htmlBody.contains("<script"))
    }

    @Test("Embedded notes retain the complete committed body in one read-only projection")
    func embeddedNotesUseCompleteTargetBody() throws {
        let vaultID = UUID()
        let sourceID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "A.md")
        let targetID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "B.md")
        let source = NoteDocument(relativePath: sourceID.relativePath, rawContent: "![[B#Claim]]")
        let trailingMarker = "Complete embedded-note tail"
        let targetBody = "# Target B\n\n## Claim\n\n" + String(repeating: "Full body paragraph.\n\n", count: 120) + trailingMarker
        let target = NoteDocument(
            relativePath: targetID.relativePath,
            rawContent: "---\ntitle: Target B\n---\n" + targetBody
        )
        let semantic = [
            sourceID: MarkdownSemanticDocument(parsing: source),
            targetID: MarkdownSemanticDocument(parsing: target),
        ]
        let graph = LinkGraphBuilder.build(
            generation: 8,
            catalog: [
                LinkCatalogNote(vaultID: vaultID, document: source, semantic: semantic[sourceID]),
                LinkCatalogNote(vaultID: vaultID, document: target, semantic: semantic[targetID]),
            ],
            documents: semantic
        )

        let catalog = DocumentPreviewCatalogBuilder.build(
            source: sourceID,
            sourceFingerprint: source.fingerprint,
            graph: graph,
            documents: [sourceID: source, targetID: target],
            profiles: [targetID: .analysis]
        )

        let embedded = try #require(catalog.links.first)
        #expect(embedded.syntax == .embed)
        #expect(embedded.fragment == "Claim")
        #expect(embedded.htmlBody.contains(trailingMarker))
        #expect(embedded.htmlBody.contains("<h1"))
    }
}
