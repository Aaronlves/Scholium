import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Links Inspector projection")
struct ConnectionsInspectorTests {
    @Test("Link group count has an accessible localized phrase")
    func localizedLinkCount() {
        #expect(ScholiumL10n.string("1 link", locale: Locale(identifier: "zh-Hans")) == "1 处链接")
        #expect(ScholiumL10n.string("\(2) links", locale: Locale(identifier: "zh-Hans")) == "2 处链接")
        #expect(ScholiumL10n.string("Missing target note", locale: Locale(identifier: "zh-Hans")) == "目标笔记缺失")
    }

    @Test("Outgoing occurrences retain distinct broken and ambiguous reasons")
    func outgoingDiagnosticsAndCounts() throws {
        let vaultID = UUID()
        let source = NoteDocument(
            relativePath: "Source.md",
            rawContent: "[[Missing]]\n[[Ambiguous]]\n[[folder/Target|Alias]] [[folder/Target|Again]]\n"
        )
        let notes = [
            source,
            NoteDocument(relativePath: "One/Ambiguous.md", rawContent: "One\n"),
            NoteDocument(relativePath: "Two/Ambiguous.md", rawContent: "Two\n"),
            NoteDocument(relativePath: "folder/Target.md", rawContent: "Target\n"),
        ]
        let semantics = Dictionary(
            uniqueKeysWithValues: notes.map { note in
                (VaultQualifiedNoteID(vaultID: vaultID, relativePath: note.relativePath), MarkdownSemanticDocument(parsing: note))
            })
        let catalog = notes.map { LinkCatalogNote(vaultID: vaultID, document: $0) }
        let graph = LinkGraphBuilder.build(
            generation: 1, catalog: catalog, documents: semantics,
            resolutionScope: .sourceVault
        )
        let sourceID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: source.relativePath)
        let items = ConnectionsProjection.make(
            graph: graph, catalogNotes: nil, current: sourceID, direction: .outgoing
        ).items
        let byTarget = Dictionary(grouping: items, by: { $0.edge.occurrence.target })

        #expect(byTarget["Missing"]?.first?.diagnostic?.code == .broken)
        #expect(byTarget["Ambiguous"]?.first?.diagnostic?.code == .ambiguous)
        #expect(byTarget["folder/Target"]?.allSatisfy { $0.diagnostic == nil } == true)
        #expect(byTarget["folder/Target"]?.first?.matches("folder") == true)
        #expect(InspectorLinkGroup.make(items).first { $0.title == "Target" }?.items.count == 2)
    }

    @Test("Same-title link groups expose exact identities and quiet directory context")
    func duplicateTitlesHaveDistinctIdentity() throws {
        let vaultID = UUID()
        let current = NoteDocument(
            relativePath: "Current.md",
            rawContent: "[[One/Target]]\n[[Two/Target]]\n"
        )
        let first = NoteDocument(relativePath: "One/Target.md", rawContent: "First target\n")
        let second = NoteDocument(relativePath: "Two/Target.md", rawContent: "Second target\n")
        let documents = [current, first, second]
        let semanticDocuments = Dictionary(
            uniqueKeysWithValues: documents.map { note in
                (
                    VaultQualifiedNoteID(vaultID: vaultID, relativePath: note.relativePath),
                    MarkdownSemanticDocument(parsing: note)
                )
            }
        )
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: documents.map { LinkCatalogNote(vaultID: vaultID, document: $0) },
            documents: semanticDocuments,
            resolutionScope: .sourceVault
        )
        let catalogNotes = [first, second].map { note in
            WorkspaceCatalogNote(
                reference: VaultNoteReference(
                    vaultID: vaultID,
                    vaultName: "Topics",
                    vaultRole: .topicKnowledge,
                    relativePath: note.relativePath
                ),
                title: "Target",
                fingerprint: note.fingerprint,
                validationWarnings: []
            )
        }
        let currentID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: current.relativePath)
        let items = ConnectionsProjection.make(
            graph: graph,
            catalogNotes: catalogNotes,
            current: currentID,
            direction: .outgoing
        ).items

        let groups = InspectorLinkGroup.make(items)
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.title == "Target" })
        #expect(groups.compactMap(\.relativePath).sorted() == ["One/Target.md", "Two/Target.md"])
        #expect(groups.compactMap(\.directoryContext).sorted() == ["Topics / One", "Topics / Two"])
    }
}
