import Darwin
import Foundation
import ScholiumContracts
import Testing

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_SOURCE_RETENTION"] == "1"))
struct SourceProjectionRetentionMeasurementTests {
    @Test func measureLayers() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let addition =
            "\n\n"
            + (0..<2).map { p in
                (0..<256).map { "conceptualword\(p)_\($0)" }.joined(separator: " ") + "."
            }.joined(separator: "\n\n") + "\n"
        for sample in 0..<3 {
            try autoreleasepool {
                let baseline = bytes()
                var documents: [NoteDocument] = []
                for vault in ["01-analyses", "02-topics", "03-works"] {
                    let base = root.appendingPathComponent("TestVaults/" + vault)
                    let enumerator = try #require(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil))
                    for case let url as URL in enumerator where url.pathExtension == "md" {
                        var source = try #require(NoteDocument.decodeUTF8PreservingBOM(Data(contentsOf: url)))
                        if url.lastPathComponent != "QA Autosave A.md" { source += addition }
                        documents.append(.init(relativePath: String(url.path.dropFirst(base.path.count + 1)), rawContent: source))
                    }
                }
                #expect(documents.count == 500)
                let sourceBytes = bytes() - baseline
                let semantics = documents.map(MarkdownSemanticDocument.init(parsing:))
                let semanticBytes = bytes() - baseline - sourceBytes
                let projections = zip(documents, semantics).map { SearchDocumentProjection(document: $0, semantic: $1) }
                let projectionBytes = bytes() - baseline - sourceBytes - semanticBytes
                withExtendedLifetime((documents, semantics, projections)) {
                    print("Source retained sample=\(sample) documents=\(sourceBytes) semantics=\(semanticBytes) search=\(projectionBytes)")
                }
            }
        }
    }

    private func bytes() -> Int {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return Int(statistics.size_in_use)
    }
}
