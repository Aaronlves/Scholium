import Foundation
import ScholiumContracts
import Testing

@Suite("Link catalog diagnostics", .serialized)
struct LinkCatalogDiagnosticsTests {
    @Test(
        "Expanded standard Triptych separates link catalog source work",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_LINK_CATALOG_DIAGNOSTIC"] == "1"))
    func expandedLinkCatalogConstruction() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let paragraph =
            "The researcher examines an argument and its objection. "
            + "研究者保留原文、异议与回应之间的区别。Unicode: café, cafe\u{301}, 🦉. "
            + "Exact source locations remain tied to the current document.\n\n"
        var documents: [(NoteDocument, MarkdownSemanticDocument)] = []
        for slot in ["01-analyses", "02-topics", "03-works"] {
            let vault = repositoryRoot.appendingPathComponent("TestVaults/\(slot)")
            let enumerator = try #require(FileManager.default.enumerator(at: vault, includingPropertiesForKeys: nil))
            let notes = enumerator.compactMap { $0 as? URL }
                .filter { $0.pathExtension.lowercased() == "md" }.sorted { $0.path < $1.path }
            for note in notes {
                var bytes = try Data(contentsOf: note)
                let repetitions = max(1, (14_000 - bytes.count) / paragraph.utf8.count)
                bytes.append(contentsOf: ("\n\n# Refresh diagnostic\n\n" + String(repeating: paragraph, count: repetitions)).utf8)
                let document = NoteDocument(relativePath: note.lastPathComponent, rawContent: String(decoding: bytes, as: UTF8.self))
                documents.append((document, MarkdownSemanticDocument(parsing: document)))
            }
        }
        #expect(documents.count == 500)
        let vaultID = UUID()
        let clock = ContinuousClock()
        var propertySamples: [Double] = []
        var anchorSamples: [Double] = []
        var catalogSamples: [Double] = []
        var anchors = 0
        var aliasValues = 0
        for _ in 0..<3 {
            let propertiesStart = clock.now
            aliasValues = documents.reduce(0) { $0 + SearchPropertyProjection(document: $1.0).textValues(forExactKey: "aliases").count }
            propertySamples.append(milliseconds(propertiesStart.duration(to: clock.now)))
            let anchorsStart = clock.now
            let anchorProjections = documents.map { ParagraphAnchorPlanner.anchors(in: $0.0, semantic: $0.1) }
            anchorSamples.append(milliseconds(anchorsStart.duration(to: clock.now)))
            anchors = anchorProjections.reduce(0) { $0 + $1.count }
            let catalogStart = clock.now
            let catalog = documents.map { LinkCatalogNote(vaultID: vaultID, document: $0.0, semantic: $0.1) }
            catalogSamples.append(milliseconds(catalogStart.duration(to: clock.now)))
            #expect(catalog.count == 500)
            for (item, projectedAnchors) in zip(catalog, anchorProjections) {
                let grouped = Dictionary(grouping: projectedAnchors, by: \.id)
                #expect(item.blockAnchors == grouped.compactMapValues { $0.count == 1 ? $0.first?.paragraphSpan : nil })
                #expect(item.ambiguousBlockAnchors == Set(grouped.filter { $0.value.count > 1 }.map(\.key)))
            }
            #expect(catalog.reduce(0) { $0 + $1.aliases.count } == aliasValues)
        }
        let caretDocuments = documents.filter { $0.0.rawContent.contains("^") }.count
        print(
            "LINK_CATALOG_DIAGNOSTIC documents=500 caretDocuments=\(caretDocuments)"
                + " anchors=\(anchors) aliases=\(aliasValues) propertyMilliseconds=\(propertySamples)"
                + " anchorMilliseconds=\(anchorSamples) catalogMilliseconds=\(catalogSamples)"
        )
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }
}
