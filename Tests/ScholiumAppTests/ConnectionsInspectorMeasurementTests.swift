import Combine
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

/// Opt-in diagnosis over a disposable standard Triptych. No window or renderer
/// is constructed: these distributions describe pure projection CPU work only.
/// Enable with SCHOLIUM_LINKS_MEASURE=1 and SCHOLIUM_LINKS_FIXTURE pointing
/// to a disposable standard Triptych copy under this checkout's .build/.
@Suite("Links Inspector measurement", .serialized)
@MainActor
struct ConnectionsInspectorMeasurementTests {
    @Test(
        "Standard Triptych projection, filtering, disclosure and redundant publication cost",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_LINKS_MEASURE"] == "1")
    )
    func standardTriptychProjection() throws {
        let fixturePath = try #require(ProcessInfo.processInfo.environment["SCHOLIUM_LINKS_FIXTURE"])
        let fixture = URL(fileURLWithPath: fixturePath).standardizedFileURL
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        try #require(fixture.path.hasPrefix(repository.appendingPathComponent(".build/").path))
        let roles: [(String, String, VaultRole)] = [
            ("01-analyses", "Analyses", .sourceCorpus),
            ("02-topics", "Topics", .topicKnowledge),
            ("03-works", "Works", .draftProject),
        ]
        let vaults = roles.enumerated().map { index, entry in
            RegisteredVault(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index + 1)")!,
                name: entry.1, role: entry.2, canonicalPath: fixture.appendingPathComponent(entry.0).path)
        }
        var documents: [UUID: [NoteDocument]] = [:]
        for (index, vault) in vaults.enumerated() {
            let root = fixture.appendingPathComponent(roles[index].0)
            let enumeration = try #require(
                FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]))
            var notes: [NoteDocument] = []
            for case let url as URL in enumeration {
                guard url.pathExtension == "md",
                    try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
                else { continue }
                let path = String(url.path.dropFirst(root.path.count + 1))
                guard WorkspaceLibraryVisibility.includes(path) else { continue }
                let data = try Data(contentsOf: url)
                let source = try #require(String(data: data, encoding: .utf8))
                notes.append(NoteDocument(relativePath: path, rawContent: source))
            }
            documents[vault.id] = notes.sorted { $0.relativePath < $1.relativePath }
        }
        let allNotes = vaults.flatMap { vault in
            (documents[vault.id] ?? []).map {
                (VaultQualifiedNoteID(vaultID: vault.id, relativePath: $0.relativePath), $0)
            }
        }
        try #require(allNotes.count == 500)
        let semantics = Dictionary(
            uniqueKeysWithValues: allNotes.map { ($0.0, MarkdownSemanticDocument(parsing: $0.1)) })
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: allNotes.map { LinkCatalogNote(vaultID: $0.0.vaultID, document: $0.1) },
            documents: semantics, resolutionScope: .workspace)
        let catalog = WorkspaceCatalogBuilder.build(vaults: vaults, documents: documents, graph: graph)
        let current = VaultQualifiedNoteID(vaultID: vaults[1].id, relativePath: "QA Topic.md")
        let edges = graph.incoming[current] ?? []
        try #require(!edges.isEmpty)
        let sourceByID = Dictionary(
            uniqueKeysWithValues: catalog.notes.map {
                (
                    VaultQualifiedNoteID(
                        vaultID: $0.reference.vaultID, relativePath: $0.reference.relativePath), $0
                )
            })
        let expectedAllIDs = edges.sorted { first, second in
            let firstTitle = sourceByID[first.source]?.title ?? first.occurrence.target
            let secondTitle = sourceByID[second.source]?.title ?? second.occurrence.target
            if firstTitle != secondTitle {
                return firstTitle.localizedStandardCompare(secondTitle) == .orderedAscending
            }
            if first.source != second.source { return first.source < second.source }
            return first.occurrence.span.utf16LowerBound < second.occurrence.span.utf16LowerBound
        }.map(occurrenceID)
        let unfiltered = ConnectionsProjection.make(
            graph: graph, catalogNotes: catalog.notes, current: current, direction: .incoming
        ).items
        #expect(unfiltered.map(\.id) == expectedAllIDs)
        let allGroups = InspectorLinkGroup.make(unfiltered)
        #expect(allGroups.flatMap(\.items).map(\.id) == expectedAllIDs)
        let prepared = PreparedConnectionsProjection(graph: graph, catalogNotes: catalog.notes, current: current)
        print(
            "LINKS_MEASURE fixture_notes=\(allNotes.count) graph_edges=\(graph.outgoing.values.reduce(0) { $0 + $1.count })"
                + " graph_diagnostics=\(graph.diagnostics.count) qa_topic_incoming=\(edges.count) qa_topic_groups=\(allGroups.count) samples=31 configuration=debug"
        )

        measure("projection", samples: 31) {
            let items = ConnectionsProjection.make(
                graph: graph, catalogNotes: catalog.notes, current: current, direction: .incoming
            ).items
            return items
        } check: {
            #expect($0.map(\.id) == expectedAllIDs)
        }
        measure("grouping", samples: 31) {
            InspectorLinkGroup.make(unfiltered)
        } check: { result in
            #expect(result.map(\.id) == allGroups.map(\.id))
            #expect(result.map { $0.items.count } == allGroups.map { $0.items.count })
        }
        measure("projection-external", samples: 31) {
            ConnectionsProjection.make(
                graph: graph, catalogNotes: catalog.notes, current: current, direction: .external
            ).items
        } check: {
            #expect($0.isEmpty)
        }
        measure("rows-expanded", samples: 31) {
            InspectorLinkRow.make(
                groups: allGroups, external: [], collapsedGroups: [], freshness: .current,
                emptyAnnouncement: "No Incoming Links"
            )
        } check: { result in
            #expect(result.count == allGroups.count + edges.count)
            #expect(Set(result.map(\.id)).count == result.count)
        }
        measure("prepare-directions", samples: 31) {
            PreparedConnectionsProjection(graph: graph, catalogNotes: catalog.notes, current: current)
        } check: {
            #expect($0.groups(direction: .incoming, query: "").flatMap(\.items).map(\.id) == expectedAllIDs)
            #expect($0.groups(direction: .external, query: "").isEmpty)
        }

        for query in ["", "QA Work", "晨光", "measurement-no-such-link"] {
            let expectedItems = unfiltered.filter { item in
                query.isEmpty
                    || [
                        sourceByID[item.edge.source]?.title ?? item.edge.occurrence.target,
                        item.edge.source.relativePath,
                        item.edge.occurrence.target,
                        item.edge.occurrence.localContext,
                        item.edge.occurrence.annotation?.text ?? "",
                    ].contains { $0.localizedStandardContains(query) }
            }
            let expectedGroups = InspectorLinkGroup.make(expectedItems)
            let collapsed = Set(
                expectedGroups.enumerated().filter { $0.offset.isMultiple(of: 2) }.map { $0.element.id })
            let expectedRows =
                expectedGroups.isEmpty
                ? 1
                : expectedGroups.reduce(0) {
                    $0 + 1 + (collapsed.contains($1.id) ? 0 : $1.items.count)
                }
            measure("pipeline-query=\(query.isEmpty ? "empty" : query)", samples: 31) {
                let items = ConnectionsProjection.make(
                    graph: graph, catalogNotes: catalog.notes, current: current, direction: .incoming
                ).items.filter { $0.matches(query) }
                let groups = InspectorLinkGroup.make(items)
                let rows = InspectorLinkRow.make(
                    groups: groups, external: [], collapsedGroups: collapsed, freshness: .current,
                    emptyAnnouncement: "No Results")
                return (items, groups, rows)
            } check: { result in
                #expect(result.0.map(\.id) == expectedItems.map(\.id))
                #expect(result.1.map(\.id) == expectedGroups.map(\.id))
                #expect(result.2.count == expectedRows)
                #expect(Set(result.2.map(\.id)).count == result.2.count)
            }
            measure("prepared-pipeline-query=\(query.isEmpty ? "empty" : query)", samples: 31) {
                let groups = prepared.groups(direction: .incoming, query: query)
                let rows = InspectorLinkRow.make(
                    groups: groups, external: [], collapsedGroups: collapsed, freshness: .current,
                    emptyAnnouncement: "No Results")
                return (groups, rows)
            } check: { result in
                #expect(result.0.flatMap(\.items).map(\.id) == expectedItems.map(\.id))
                #expect(result.0.map(\.id) == expectedGroups.map(\.id))
                #expect(result.1.count == expectedRows)
                #expect(Set(result.1.map(\.id)).count == result.1.count)
            }
        }

        let session = LinksInspectorSession()
        let key = "measurement:QA Topic:incoming"
        let scrollID = try #require(allGroups.first?.id)
        session.update(key) { $0.scrollID = scrollID }
        var publications = 0
        let observation = session.objectWillChange.sink { publications += 1 }
        defer { observation.cancel() }
        for _ in 0..<1_000 { session.update(key) { $0.scrollID = scrollID } }
        let scrollPublications = publications
        for _ in 0..<1_000 { session.update(key) { $0.query = "" } }
        let queryPublications = publications - scrollPublications
        for _ in 0..<1_000 { session.update(key) { $0.collapsedGroups = [] } }
        let disclosurePublications = publications - scrollPublications - queryPublications
        #expect(session.location(for: key).scrollID == scrollID)
        #expect(
            session.location(for: key).query == "" && session.location(for: key).collapsedGroups.isEmpty)
        let beforeChanges = publications
        session.update(key) { $0.query = "QA Work" }
        session.update(key) { $0.collapsedGroups = [scrollID] }
        session.update(key) { $0.scrollID = nil }
        #expect(session.location(for: key).query == "QA Work")
        #expect(session.location(for: key).collapsedGroups == [scrollID])
        #expect(session.location(for: key).scrollID == nil)
        print(
            "LINKS_MEASURE no_op_each=1000 scroll_publications=\(scrollPublications) query_publications=\(queryPublications)"
                + " disclosure_publications=\(disclosurePublications) meaningful_changes=3 meaningful_publications=\(publications - beforeChanges)"
        )

    }

    private func occurrenceID(_ edge: LinkGraphEdge) -> String {
        [
            edge.source.vaultID.uuidString, edge.source.relativePath,
            String(edge.occurrence.span.utf16LowerBound), String(edge.occurrence.span.utf16UpperBound),
            "incoming",
        ].joined(separator: ":")
    }

    private func measure<Value>(
        _ label: String, samples: Int, operation: () -> Value, check: (Value) -> Void
    ) {
        for _ in 0..<3 { check(operation()) }
        var milliseconds: [Double] = []
        for _ in 0..<samples {
            let start = ContinuousClock.now
            let result = operation()
            let duration = start.duration(to: .now)
            milliseconds.append(
                Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
            )
            check(result)
        }
        let sorted = milliseconds.sorted()
        let format: (Double) -> String = { String(format: "%.4f", $0) }
        print(
            "LINKS_MEASURE stage=\(label) samples=\(samples) median_ms=\(format(sorted[samples / 2]))"
                + " p95_ms=\(format(sorted[Int(ceil(Double(samples) * 0.95)) - 1])) min_ms=\(format(sorted.first!)) max_ms=\(format(sorted.last!))"
        )
    }
}
