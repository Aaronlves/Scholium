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
            rawContent: "+[[B#Claim]] and [[Missing]]"
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
                LinkCatalogNote(id: sourceID, title: "A", aliases: [], noteType: nil, headings: [], blockAnchors: [:]),
                LinkCatalogNote(vaultID: vaultID, document: target, semantic: semantic[targetID]),
            ],
            documents: semantic
        )
        let preview = DocumentPreviewCatalogBuilder.build(
            source: sourceID,
            sourceFingerprint: source.fingerprint,
            graph: graph,
            documents: [sourceID: source, targetID: target],
            profiles: [targetID: .analysis]
        )

        #expect(preview.contractVersion == 1)
        #expect(preview.graphGeneration == 7)
        #expect(preview.links.count == 1)
        #expect(preview.links[0].target == targetID)
        #expect(preview.links[0].title == "Target B")
        #expect(preview.links[0].relationship == .supportsTarget)
        #expect(preview.links[0].fragment == "Claim")
        #expect(preview.links[0].htmlBody.contains("<strong>Rendered</strong>"))
        #expect(!preview.links[0].htmlBody.contains("<script"))
    }
}
