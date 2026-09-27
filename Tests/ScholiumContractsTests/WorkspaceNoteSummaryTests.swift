import Foundation
import ScholiumContracts
import Testing

@Suite("Workspace source-free summary semantics")
struct WorkspaceNoteSummaryTests {
    @Test(
        "Canonical display lists remain distinct from Search property text",
        arguments: [
            ("aliases: Scalar\nkeywords: Scalar", [String](), [String](), ["Scalar"], ["Scalar"]),
            ("aliases: [Valid, 7]\nkeywords: [Term, false]", [], [], ["Valid", "7"], ["Term", "false"]),
            ("aliases: []\nkeywords: []", [], [], [], []),
            ("aliases: [' ', Valid]\nkeywords: [\"\\t\", Term]", [], [], [" ", "Valid"], ["\t", "Term"]),
            ("aliases: [First, Second]\nkeywords: [Concept, 观念]", ["First", "Second"], ["Concept", "观念"], ["First", "Second"], ["Concept", "观念"]),
        ])
    func propertyProjectionParity(
        yaml: String,
        canonicalAliases: [String], canonicalKeywords: [String],
        searchAliases: [String], searchKeywords: [String]
    ) {
        let document = NoteDocument(relativePath: "Parity.md", rawContent: "---\n\(yaml)\n---\n# Body\n")
        let summary = WorkspaceNoteSummary(
            id: VaultQualifiedNoteID(vaultID: UUID(), relativePath: document.relativePath),
            vaultRole: .topicKnowledge, stableIdentity: .unresolved,
            document: document,
            fileMetadata: WorkspaceFileMetadata(
                byteCount: document.sourceBytes.count, creationDate: nil, modificationDate: nil),
            graphCounts: WorkspaceGraphCounts(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0)
        )
        #expect(summary.aliases == canonicalAliases)
        #expect(summary.keywords == canonicalKeywords)
        #expect(summary.propertyTextValues["aliases"] ?? [] == searchAliases)
        #expect(summary.propertyTextValues["keywords"] ?? [] == searchKeywords)
        #expect(summary.fingerprint == document.fingerprint)
    }
}
