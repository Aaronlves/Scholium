import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Kept passage snapshots", .serialized) @MainActor
struct KeptPassagesTests {
    @Test("Repeated Keeps are idempotent; a new revision is a separate immutable snapshot")
    func identityAndRevision() throws {
        let (document, items) = try links("Before [[Target|同名]]{{A qualification.}} after.\n")
        let item = try #require(items.first)
        let entry = try KeptPassage(item: item, document: document)
        let kept = KeptPassagesSession()
        kept.retain(entry)
        kept.retain(entry)
        #expect(kept.contains(item))
        #expect(kept.entries == [entry])
        let (changed, changedItems) = try links(document.rawContent + "Another paragraph.\n", vaultID: item.edge.source.vaultID)
        let next = try KeptPassage(item: #require(changedItems.first), document: changed)
        #expect(next.id != entry.id)
        kept.retain(next)
        #expect(kept.entries == [entry, next])
        kept.remove(entry.id)
        #expect(kept.entries == [next])
    }

    @Test("Links retain exact multiline context, annotations and each original occurrence anchor")
    func exactLinkCapture() throws {
        let source = "\u{FEFF}# Header\r\n\r\n👩🏽‍🔬 cafe\u{301} [[Target|同名]]{{第一行\r\n第二行。}} and [[Target|同名]].\r\n\r\nAfter.\r\n"
        let (document, items) = try links(source)
        try #require(items.count == 2)
        let first = try KeptPassage(item: items[0], document: document)
        let second = try KeptPassage(item: items[1], document: document)
        #expect(first.id != second.id)
        #expect(first.text.utf8.elementsEqual(items[0].edge.occurrence.localContext.utf8))
        #expect(first.text.contains("{{第一行\r\n第二行。}}"))
        #expect(first.displayText.contains("第一行"))
        #expect(first.linkOccurrence?.annotation?.markdown.contains("第二行") == true)
        #expect(first.sourceRange.utf16LowerBound == items[0].edge.occurrence.linkSpan.utf16LowerBound)
        #expect(second.sourceRange.utf16LowerBound == items[1].edge.occurrence.linkSpan.utf16LowerBound)
        for entry in [first, second] {
            let captured = try #require(
                Range(NSRange(location: entry.range.utf16LowerBound, length: entry.range.utf16UpperBound - entry.range.utf16LowerBound), in: source))
            #expect(source[captured].utf8.elementsEqual(entry.text.utf8))
            #expect(entry.fingerprint == document.fingerprint)
        }
        #expect(document.rawContent.utf8.elementsEqual(source.utf8))
    }

    @Test("Graph context from an older revision cannot become a newly verified Links snapshot")
    func rejectsStaleLinkCapture() throws {
        let (document, items) = try links("Before [[Target]] after.\n")
        let item = try #require(items.first)
        let changed = NoteDocument(relativePath: document.relativePath, rawContent: "Different prefix.\n" + document.rawContent)
        #expect(throws: KeptPassageError.self) { try KeptPassage(item: item, document: changed) }
        let currentSource = WorkspaceCatalogNote(
            reference: try #require(item.source).reference, title: "Source", fingerprint: changed.fingerprint, validationWarnings: [])
        let staleEdgeWithNewCatalog = InspectorLinkItem(
            edge: item.edge, peer: item.peer, source: currentSource, direction: item.direction, diagnostic: item.diagnostic)
        #expect(throws: KeptPassageError.self) { try KeptPassage(item: staleEdgeWithNewCatalog, document: changed) }
    }

    @Test("Reset and removal invalidate pending captures without changing another window")
    func cancellationAndIsolation() throws {
        let (document, items) = try links("Before [[Target]] after.\n")
        let entry = try KeptPassage(item: #require(items.first), document: document)
        let first = ResearchController()
        let second = ResearchController()
        second.keptPassages.retain(entry)
        let resetCapture = try #require(first.keptPassages.beginCapture(id: entry.id))
        first.reset()
        first.keptPassages.finish(resetCapture, entry: entry)
        #expect(first.keptPassages.entries.isEmpty)
        #expect(second.keptPassages.entries == [entry])
        let removedCapture = try #require(first.keptPassages.beginCapture(id: entry.id))
        first.keptPassages.remove(entry.id)
        first.keptPassages.finish(removedCapture, entry: entry)
        #expect(first.keptPassages.entries.isEmpty)
        first.keptPassages.retain(entry)
        first.unbind()
        #expect(first.keptPassages.entries.isEmpty)
        #expect(second.keptPassages.entries == [entry])
    }

    @Test("Pane switches and discovery resets preserve window-local comparison disclosure")
    func comparisonDisclosureOwnership() throws {
        let (document, items) = try links("Before [[Target]] after.\n")
        let entry = try KeptPassage(item: #require(items.first), document: document)
        let first = ResearchController()
        let second = ResearchController()
        first.keptPassages.retain(entry)
        second.keptPassages.retain(entry)
        first.keptPassages.setContextExpanded(true, for: entry.id)
        first.keptPassages.isExpanded = false

        first.selectInspectorMode(.related)
        first.relatedMaterials.reset()
        first.showResearchInspector(false)
        first.selectInspectorMode(.links)
        first.linksInspector.reset()
        first.showResearchInspector(true)

        #expect(first.keptPassages.entries == [entry])
        #expect(!first.keptPassages.isExpanded)
        #expect(first.keptPassages.isContextExpanded(entry.id))
        #expect(second.keptPassages.isExpanded)
        #expect(!second.keptPassages.isContextExpanded(entry.id))
    }

    @Test("A new Keep reveals its passage while repeated Keeps preserve existing comparison state")
    func keepRevealsNewPassage() throws {
        let (document, items) = try links("First [[Target]]. Second [[Target]].\n")
        let first = try KeptPassage(item: #require(items.first), document: document)
        let second = try KeptPassage(item: #require(items.last), document: document)
        let kept = KeptPassagesSession()
        kept.retain(first)
        kept.isExpanded = false
        kept.setContextExpanded(true, for: first.id)
        kept.retain(first)
        #expect(!kept.isExpanded)
        #expect(kept.isContextExpanded(first.id))

        kept.retain(second)
        #expect(kept.isExpanded)
        #expect(!kept.isContextExpanded(second.id))
        #expect(kept.isContextExpanded(first.id))
        #expect(kept.entries == [first, second])
    }

    @Test("Removal and reset release reading state; stale controls cannot recreate it")
    func comparisonDisclosureLifetime() throws {
        let (document, items) = try links("Before [[Target]] after.\n")
        let entry = try KeptPassage(item: #require(items.first), document: document)
        let kept = KeptPassagesSession()
        kept.retain(entry)
        kept.setContextExpanded(true, for: entry.id)
        kept.remove(entry.id)
        kept.setContextExpanded(true, for: entry.id)
        kept.retain(entry)
        #expect(!kept.isContextExpanded(entry.id))

        kept.isExpanded = false
        kept.setContextExpanded(true, for: entry.id)
        kept.reset()
        #expect(kept.entries.isEmpty)
        #expect(kept.isExpanded)
        kept.setContextExpanded(true, for: entry.id)
        kept.retain(entry)
        #expect(!kept.isContextExpanded(entry.id))
    }

    @Test("Duplicate source titles show vault and directory without regrouping snapshots")
    func duplicateSourceIdentity() throws {
        let (document, items) = try links("First [[Target]]. Second [[Target]].\n")
        let first = try KeptPassage(item: #require(items.first), document: document)
        let second = try KeptPassage(item: #require(items.last), document: document)
        let kept = KeptPassagesSession()
        kept.retain(first)
        kept.retain(second)
        #expect(kept.directoryContext(for: first) == nil)

        let (otherDocument, otherItems) = try links(
            "A different [[Target]].\n", vaultName: "Other vault", relativePath: "Arguments/Source.md"
        )
        let other = try KeptPassage(item: #require(otherItems.first), document: otherDocument)
        #expect(other.title == first.title)
        kept.retain(other)
        #expect(kept.directoryContext(for: first) == "Synthetic")
        #expect(kept.directoryContext(for: other) == "Other vault / Arguments")
        #expect(kept.entries == [first, second, other])
        kept.remove(other.id)
        #expect(kept.directoryContext(for: first) == nil)
    }

    private func links(
        _ source: String, vaultID: UUID = UUID(), vaultName: String = "Synthetic", relativePath: String = "Source.md"
    ) throws -> (NoteDocument, [InspectorLinkItem]) {
        let vault = RegisteredVault(id: vaultID, name: vaultName, role: .topicKnowledge, canonicalPath: "/unused/kept-fixture")
        let document = NoteDocument(relativePath: relativePath, rawContent: source)
        let target = NoteDocument(relativePath: "Target.md", rawContent: "Target.\n")
        let documents = [document, target]
        let semantics = Dictionary(
            uniqueKeysWithValues: documents.map {
                (VaultQualifiedNoteID(vaultID: vault.id, relativePath: $0.relativePath), MarkdownSemanticDocument(parsing: $0))
            })
        let graph = LinkGraphBuilder.build(
            generation: 1, catalog: documents.map { LinkCatalogNote(vaultID: vault.id, document: $0) },
            documents: semantics, resolutionScope: .sourceVault)
        let catalog = WorkspaceCatalogBuilder.build(vaults: [vault], documents: [vault.id: documents], graph: graph)
        return (
            document,
            ConnectionsProjection.make(
                graph: graph, catalogNotes: catalog.notes, current: .init(vaultID: vault.id, relativePath: document.relativePath), direction: .outgoing
            ).items
        )
    }
}
