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
            graph: graph, catalog: nil, current: sourceID, direction: .outgoing
        ).items
        let byTarget = Dictionary(grouping: items, by: { $0.edge.occurrence.target })

        #expect(byTarget["Missing"]?.first?.diagnostic?.code == .broken)
        #expect(byTarget["Ambiguous"]?.first?.diagnostic?.code == .ambiguous)
        #expect(byTarget["folder/Target"]?.allSatisfy { $0.diagnostic == nil } == true)
        #expect(byTarget["folder/Target"]?.first?.matches("folder") == true)
        #expect(InspectorLinkGroup.make(items).first { $0.title == "Target" }?.items.count == 2)
    }
}
