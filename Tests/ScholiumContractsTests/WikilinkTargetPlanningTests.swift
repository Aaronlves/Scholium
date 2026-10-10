import Foundation
import ScholiumContracts
import Testing

@Suite("Source-compatible Wikilink target planning")
struct WikilinkTargetPlanningTests {
    private let topics = UUID(uuidString: "10000000-0000-4000-8000-000000000000")!
    private let analyses = UUID(uuidString: "20000000-0000-4000-8000-000000000000")!
    private let works = UUID(uuidString: "30000000-0000-4000-8000-000000000000")!

    @Test("Every offered spelling survives source parsing and navigation to the selected identity")
    func sourceRoundTrip() throws {
        let source = id(topics, "Folder/Draft.md")
        let catalog = [
            LinkCatalogNote(id: source),
            LinkCatalogNote(id: id(topics, "Foo.md")),
            LinkCatalogNote(id: id(topics, "Folder/Foo.md")),
            LinkCatalogNote(id: id(topics, "Other/Foo.md")),
            LinkCatalogNote(id: id(analyses, "Research/Foo.md"), aliases: ["Distinct Analysis"]),
            LinkCatalogNote(id: id(analyses, "A#draft.md"), aliases: ["Safe Analysis"]),
            LinkCatalogNote(id: id(topics, "Foo.md.md")),
            LinkCatalogNote(id: id(topics, "中文/价值.md")),
            LinkCatalogNote(id: id(topics, "Literal%23.md")),
        ]
        let resolver = LinkResolutionCatalog(catalog: catalog)
        for destination in catalog.map(\.id).filter({ $0 != source }) {
            guard case .available(let target) = resolver.wikilinkTarget(for: destination, from: source) else {
                Issue.record("A safely addressable Note was unavailable: \(destination.relativePath)")
                continue
            }
            let written = NoteDocument(relativePath: source.relativePath, rawContent: "[[\(target)]]")
            let semantics = MarkdownSemanticDocument(parsing: written)
            let snapshot = LinkGraphBuilder.build(
                generation: 1, catalog: catalog, documents: [source: semantics], resolutionScope: .workspace)
            #expect(snapshot.outgoing[source]?.count == 1)
            #expect(snapshot.outgoing[source]?.first?.destination?.note == destination)
            #expect(snapshot.diagnostics.isEmpty)
        }
        #expect(resolver.wikilinkTarget(for: id(topics, "Folder/Foo.md"), from: source) == .available("Folder/Foo"))
        #expect(resolver.wikilinkTarget(for: id(analyses, "Research/Foo.md"), from: source) == .available("Distinct Analysis"))
    }

    @Test("Shadowed and unsupported targets stay distinct and never receive an unsafe spelling")
    func unavailableTargets() {
        let source = id(topics, "Folder/Draft.md")
        let shadowed = id(analyses, "Research/Foo.md")
        let unsafePaths = ["A#draft.md", "A|B.md", "A[B].md", "A\\B.md", "A\nB.md"]
        let catalog =
            [
                LinkCatalogNote(id: source),
                LinkCatalogNote(id: id(topics, "Folder/Foo.md")),
                LinkCatalogNote(id: shadowed),
                LinkCatalogNote(id: id(works, "Research/Foo.md")),
            ] + unsafePaths.map { LinkCatalogNote(id: id(analyses, $0)) }
        let resolver = LinkResolutionCatalog(catalog: catalog)
        #expect(resolver.wikilinkTarget(for: shadowed, from: source) == .ambiguous)
        for path in unsafePaths {
            #expect(resolver.wikilinkTarget(for: id(analyses, path), from: source) == .unsupportedSyntax)
        }
        #expect(resolver.wikilinkTarget(for: id(analyses, "Deleted.md"), from: source) == .missingNote)
    }

    private func id(_ vault: UUID, _ path: String) -> VaultQualifiedNoteID {
        VaultQualifiedNoteID(vaultID: vault, relativePath: path)
    }
}
