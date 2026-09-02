import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Occurrence-owned Link Graph")
struct LinkGraphTests {
    private let vaultID = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!

    @Test("Every authored occurrence remains a distinct outgoing and incoming edge")
    func occurrenceIdentityAndAnnotations() throws {
        let source = NoteDocument(
            relativePath: "A.md",
            rawContent: "# A\n\n[[B]]{{First **reason**.}}\n\n[[B]]{{Second reason.}}\n"
        )
        let target = NoteDocument(relativePath: "B.md", rawContent: "# B\n")
        let snapshot = build([source, target])
        let sourceID = id(source)
        let targetID = id(target)
        let outgoing = snapshot.outgoing[sourceID] ?? []
        let incoming = snapshot.incoming[targetID] ?? []

        #expect(snapshot.contractVersion == 6)
        #expect(outgoing.count == 2)
        #expect(incoming == outgoing)
        #expect(outgoing.map { $0.occurrence.annotation?.markdown } == [
            "First **reason**.", "Second reason.",
        ])
        #expect(outgoing.map { $0.occurrence.annotation?.text } == [
            "First reason.", "Second reason.",
        ])
        #expect(outgoing[0].occurrence.linkSpan.utf16UpperBound
            < outgoing[0].occurrence.span.utf16UpperBound)
        #expect(outgoing.allSatisfy { !$0.occurrence.localContext.isEmpty })
        #expect(snapshot.diagnostics.isEmpty)
    }

    @Test("Aliases, headings, blocks, and annotations retain one source occurrence")
    func fragmentsAndAliases() throws {
        let source = NoteDocument(
            relativePath: "Source.md",
            rawContent: "[[Target#Claim|heading alias]]{{Why the heading matters.}}\n[[Target#^basis]]\n"
        )
        let target = NoteDocument(
            relativePath: "Target.md",
            rawContent: "# Claim\n\nGrounding paragraph. ^basis\n"
        )
        let snapshot = build([source, target])
        let edges = snapshot.outgoing[id(source)] ?? []

        #expect(edges.count == 2)
        #expect(edges[0].occurrence.alias == "heading alias")
        #expect(edges[0].occurrence.annotation?.markdown == "Why the heading matters.")
        #expect(edges[0].destination?.kind == .heading)
        #expect(edges[0].destination?.fragment == "Claim")
        #expect(edges[0].destination?.span?.start.line == 1)
        #expect(edges[1].destination?.kind == .block)
        #expect(edges[1].destination?.fragment == "^basis")
        #expect(edges[1].destination?.span?.start.line == 3)
    }

    @Test("Ambiguous and broken targets fail closed without inventing destinations")
    func ambiguousAndBrokenTargets() {
        let sourceVault = UUID(uuidString: "10000000-0000-4000-8000-000000000000")!
        let papersVault = UUID(uuidString: "20000000-0000-4000-8000-000000000000")!
        let topicsVault = UUID(uuidString: "30000000-0000-4000-8000-000000000000")!
        let source = NoteDocument(
            relativePath: "Source.md",
            rawContent: "[[Agency]]{{Ambiguous.}}\n[[Missing]]{{Broken.}}\n"
        )
        let paper = NoteDocument(relativePath: "Papers/Agency.md", rawContent: "# Agency\n")
        let topic = NoteDocument(relativePath: "Topics/Agency.md", rawContent: "# Agency\n")
        let sourceID = VaultQualifiedNoteID(vaultID: sourceVault, relativePath: source.relativePath)
        let paperID = VaultQualifiedNoteID(vaultID: papersVault, relativePath: paper.relativePath)
        let topicID = VaultQualifiedNoteID(vaultID: topicsVault, relativePath: topic.relativePath)
        let semantics = [
            sourceID: MarkdownSemanticDocument(parsing: source),
            paperID: MarkdownSemanticDocument(parsing: paper),
            topicID: MarkdownSemanticDocument(parsing: topic),
        ]
        let snapshot = LinkGraphBuilder.build(
            generation: 1,
            catalog: [
                LinkCatalogNote(vaultID: sourceVault, document: source, semantic: semantics[sourceID]),
                LinkCatalogNote(vaultID: papersVault, document: paper, semantic: semantics[paperID]),
                LinkCatalogNote(vaultID: topicsVault, document: topic, semantic: semantics[topicID]),
            ],
            documents: semantics,
            resolutionScope: .workspace
        )
        let edges = snapshot.outgoing[sourceID] ?? []

        #expect(edges.count == 2)
        #expect(edges.allSatisfy { $0.destination == nil })
        #expect(snapshot.incoming.isEmpty)
        #expect(snapshot.diagnostics.map(\.code) == [.ambiguous, .broken])
        #expect(snapshot.diagnostics[0].target == "Agency")
        #expect(snapshot.diagnostics[1].target == "Missing")
    }

    @Test("Embeds are direct edges while external Markdown links remain navigation only")
    func embedsAndExternalLinks() {
        let source = NoteDocument(
            relativePath: "Source.md",
            rawContent: "![[Target]]\n[External](https://example.test)\n"
        )
        let target = NoteDocument(relativePath: "Target.md", rawContent: "# Target\n")
        let snapshot = build([source, target])
        let edges = snapshot.outgoing[id(source)] ?? []

        #expect(edges.count == 1)
        #expect(edges.first?.occurrence.syntax == .embed)
        #expect(edges.first?.destination?.note == id(target))
    }

    @Test("A rebuild from identical source has deterministic projections")
    func deterministicRebuild() throws {
        let source = NoteDocument(
            relativePath: "A.md",
            rawContent: "[[B]]{{One.}} [[B]]{{Two.}} [[Missing]]\n"
        )
        let target = NoteDocument(relativePath: "B.md", rawContent: "# B\n")
        let first = build([source, target], generation: 7)
        let second = build([source, target], generation: 7)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        #expect(first.outgoing == second.outgoing)
        #expect(first.incoming == second.incoming)
        #expect(first.diagnostics == second.diagnostics)
        #expect(try encoder.encode(first.diagnostics) == encoder.encode(second.diagnostics))
    }

    private func id(_ document: NoteDocument) -> VaultQualifiedNoteID {
        VaultQualifiedNoteID(vaultID: vaultID, relativePath: document.relativePath)
    }

    private func build(
        _ documents: [NoteDocument],
        generation: Int = 1
    ) -> GraphSnapshot {
        let semantics = Dictionary(uniqueKeysWithValues: documents.map { document in
            (id(document), MarkdownSemanticDocument(parsing: document))
        })
        return LinkGraphBuilder.build(
            generation: generation,
            catalog: documents.map { document in
                LinkCatalogNote(vaultID: vaultID, document: document, semantic: semantics[id(document)])
            },
            documents: semantics,
            sourceManifestHash: "fixture-manifest"
        )
    }
}
