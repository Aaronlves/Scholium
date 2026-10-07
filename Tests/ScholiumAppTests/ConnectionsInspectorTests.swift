import AppKit
import Combine
import Foundation
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Links Inspector projection", .serialized)
struct ConnectionsInspectorTests {
    @Test("Links publishes only changed navigation context and preserves independent locations")
    @MainActor
    func navigationContextPublications() {
        let session = LinksInspectorSession()
        var publications = 0
        let observation = session.objectWillChange.sink { publications += 1 }
        defer { observation.cancel() }
        let key = "note:incoming"
        session.update(key) { $0.query = "" }
        #expect(publications == 0)
        session.update(key) {
            $0.query = "source"
            $0.scrollID = "first"
            $0.collapsedGroups = ["second"]
        }
        #expect(publications == 1)
        for _ in 0..<10 {
            session.update(key) { $0.query = "source" }
            session.update(key) { $0.scrollID = "first" }
            session.update(key) { $0.collapsedGroups = ["second"] }
        }
        #expect(publications == 1)
        session.update("note:outgoing") { $0.query = "other" }
        #expect(publications == 2)
        #expect(session.location(for: key).query == "source")
        #expect(session.location(for: key).scrollID == "first")
        #expect(session.location(for: key).collapsedGroups == ["second"])
        #expect(session.location(for: "note:outgoing").query == "other")
        session.update(key) { $0.scrollID = nil }
        #expect(publications == 3)
        #expect(session.location(for: key).scrollID == nil)
        session.reset()
        #expect(session.location(for: key) == LinksInspectorSession.Location())
        #expect(session.location(for: "note:outgoing") == LinksInspectorSession.Location())
    }

    @Test("Flat Links rows retain error meaning and distinct authored external occurrences")
    func flatRowsRetainStatesAndExternalLinks() throws {
        let links = SourceResourceReferences.externalLinks(in: "[First](https://example.invalid/source) [Second](https://example.invalid/source)\n")
        try #require(links.count == 2)
        let reason = "Fixture graph refresh failed"
        let rows = InspectorLinkRow.make(
            groups: [], external: links, collapsedGroups: [],
            freshness: .failed(reason), emptyAnnouncement: "No External Links")
        #expect(Set(rows.map(\.id)).count == rows.count)
        try #require(rows.count == 2)
        guard case .freshness(let freshness) = rows[0], case .external(let captured) = rows[1] else {
            Issue.record("A refresh failure must precede the retained authored external links.")
            return
        }
        #expect(freshness.detail == reason)
        #expect(captured == links)
        #expect(captured.map(\.label) == ["First", "Second"])
        #expect(Set(captured.map(\.id)).count == 2)

        let empty = InspectorLinkRow.make(
            groups: [], external: [], collapsedGroups: [],
            freshness: .current, emptyAnnouncement: "No External Links")
        try #require(empty.count == 1)
        guard case .empty = empty[0] else {
            Issue.record("A current empty projection needs its named empty row.")
            return
        }
    }

    @Test("Native Links rows survive Note replacement, close-like return, and disclosure changes")
    @MainActor
    func nativeLinksCollectionLifecycle() async throws {
        _ = NSApplication.shared
        let vault = RegisteredVault(name: "Synthetic", role: .topicKnowledge, canonicalPath: "/unused/links-fixture")
        let documents =
            [
                NoteDocument(relativePath: "Many.md", rawContent: (0..<4).map { "[[Target\($0)]] [[Target\($0)|Again]]\n" }.joined()),
                NoteDocument(relativePath: "Few.md", rawContent: "[[Target0]]\n"),
                NoteDocument(relativePath: "Empty.md", rawContent: "No links\n"),
            ] + (0..<4).map { NoteDocument(relativePath: "Target\($0).md", rawContent: "Target \($0)\n") }
        let semantics = Dictionary(
            uniqueKeysWithValues: documents.map {
                (VaultQualifiedNoteID(vaultID: vault.id, relativePath: $0.relativePath), MarkdownSemanticDocument(parsing: $0))
            })
        let graph = LinkGraphBuilder.build(
            generation: 1, catalog: documents.map { LinkCatalogNote(vaultID: vault.id, document: $0) },
            documents: semantics, resolutionScope: .sourceVault)
        let catalog = WorkspaceCatalogBuilder.build(vaults: [vault], documents: [vault.id: documents], graph: graph)
        let many = VaultQualifiedNoteID(vaultID: vault.id, relativePath: "Many.md")
        let few = VaultQualifiedNoteID(vaultID: vault.id, relativePath: "Few.md")
        let empty = VaultQualifiedNoteID(vaultID: vault.id, relativePath: "Empty.md")
        let state = LinksLifecycleFixture(current: many)
        let session = LinksInspectorSession()
        session.direction = .outgoing
        let host = NSHostingView(rootView: LinksLifecycleView(state: state, graph: graph, catalog: catalog, session: session))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 600),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        for iteration in 0..<8 {
            for current in [many, few, empty, few, many] {
                state.current = current
                let key = "\(current.vaultID.uuidString):\(current.relativePath):outgoing"
                let groups = InspectorLinkGroup.make(
                    ConnectionsProjection.make(
                        graph: graph, catalogNotes: catalog.notes, current: current, direction: .outgoing
                    ).items)
                let collapsed = iteration.isMultiple(of: 2) ? Set(groups.prefix(1).map(\.id)) : []
                session.update(key) { $0.collapsedGroups = collapsed }
                let expected = groups.isEmpty ? 1 : groups.reduce(0) { $0 + 1 + (collapsed.contains($1.id) ? 0 : $1.items.count) }
                let deadline = ContinuousClock.now.advanced(by: .seconds(3))
                var actual = -1
                repeat {
                    host.layoutSubtreeIfNeeded()
                    if let outline = findOutline(in: host) { actual = outline.numberOfRows }
                    if actual == expected { break }
                    try await Task.sleep(for: .milliseconds(10))
                } while ContinuousClock.now < deadline
                #expect(actual == expected, "\(current.relativePath), iteration \(iteration)")
                try #require(actual == expected)
            }
        }
    }

    @MainActor
    private func findOutline(in view: NSView) -> NSOutlineView? {
        if let outline = view as? NSOutlineView { return outline }
        return view.subviews.lazy.compactMap { findOutline(in: $0) }.first
    }

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
        let repeated = try #require(byTarget["folder/Target"])
        let missing = try #require(byTarget["Missing"]?.first)
        let interleaved = InspectorLinkGroup.make([repeated[0], missing, repeated[1]])
        #expect(interleaved.map(\.title) == ["Target", "Missing"])
        #expect(interleaved[0].items.map(\.id) == repeated.map(\.id))
        #expect(interleaved[1].items.map(\.id) == [missing.id])
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

        let expandedRows = InspectorLinkRow.make(
            groups: groups, external: [], collapsedGroups: [],
            freshness: .current, emptyAnnouncement: "No Outgoing Links")
        let firstGroup = try #require(groups.first)
        let collapsedRows = InspectorLinkRow.make(
            groups: groups, external: [], collapsedGroups: [firstGroup.id],
            freshness: .current, emptyAnnouncement: "No Outgoing Links")
        #expect(expandedRows.count == 4)
        try #require(expandedRows.count == 4)
        #expect(Set(expandedRows.map(\.id)).count == expandedRows.count)
        #expect(collapsedRows.count == 3)
        #expect(collapsedRows.map(\.id) == [expandedRows[0].id, expandedRows[2].id, expandedRows[3].id])
        let capturedOccurrences = expandedRows.compactMap { row -> InspectorLinkItem? in
            if case .occurrence(let item) = row { return item }
            return nil
        }
        #expect(capturedOccurrences.map { $0.edge.occurrence.span } == items.map { $0.edge.occurrence.span })
    }
}

@MainActor
private final class LinksLifecycleFixture: ObservableObject {
    @Published var current: VaultQualifiedNoteID
    init(current: VaultQualifiedNoteID) { self.current = current }
}

private struct LinksLifecycleView: View {
    @ObservedObject var state: LinksLifecycleFixture
    let graph: GraphSnapshot
    let catalog: WorkspaceCatalogSnapshot
    let session: LinksInspectorSession
    let keptPassages = KeptPassagesSession()

    var body: some View {
        ConnectionsInspectorView(
            context: .init(
                graph: graph, catalog: catalog, current: state.current,
                freshness: .current, retryRefresh: {}, openReference: { _, _ in }), session: session,
            keptPassages: keptPassages, keepLink: { _ in }, openKept: { _ in })
    }
}
