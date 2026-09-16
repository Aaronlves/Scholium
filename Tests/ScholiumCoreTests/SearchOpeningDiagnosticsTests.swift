import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

/// Opt-in measurements of the existing complete generated-index validation.
/// This is diagnostic evidence, not a release gate or native presentation test.
@Suite(
    "Search index opening diagnostics", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_SEARCH_OPEN_DIAGNOSTIC"] == "1"))
struct SearchOpeningDiagnosticsTests {
    @Test("Measure repeated index opening over the expanded standard Triptych")
    func expandedTriptychOpening() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let output = repository.appendingPathComponent(".build/search-opening-diagnostics")
        let state = output.appendingPathComponent("state")
        let label = (ProcessInfo.processInfo.environment["SCHOLIUM_SEARCH_OPEN_DIAGNOSTIC_LABEL"] ?? "sample")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        if label == "baseline", FileManager.default.fileExists(atPath: state.path) {
            try FileManager.default.removeItem(at: state)
        }
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        let triptychID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111110"))
        let roles: [VaultRole] = [.sourceCorpus, .topicKnowledge, .draftProject]
        let slots = ["01-analyses", "02-topics", "03-works"]
        let vaults = try slots.enumerated().map { number, slot in
            RegisteredVault(
                id: try #require(UUID(uuidString: "11111111-1111-1111-1111-11111111111\(number + 1)")),
                name: slot, role: roles[number], canonicalPath: state.appendingPathComponent(slot).path)
        }
        let databaseURL = state.appendingPathComponent("search.sqlite")
        let paragraph =
            "The researcher examines an argument and its objection. "
            + "研究者保留原文、异议与回应之间的区别。Unicode: café, cafe\u{301}, 🦉. "
            + "Exact source locations remain tied to the current document.\n\n"
        var documents: [(RegisteredVault, NoteDocument)] = []
        var first = true
        for (slot, vault) in zip(slots, vaults) {
            let root = repository.appendingPathComponent("TestVaults/\(slot)")
            let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            let notes = enumerator.compactMap { $0 as? URL }
                .filter { $0.pathExtension.lowercased() == "md" }.sorted { $0.path < $1.path }
            for note in notes {
                var bytes = try Data(contentsOf: note)
                let repetitions = max(1, (14_000 - bytes.count) / paragraph.utf8.count)
                var appendix = "\n\n# Refresh diagnostic\n\n" + String(repeating: paragraph, count: repetitions)
                if first {
                    appendix += "refreshdiagnosticneedle\n"
                    first = false
                }
                bytes.append(contentsOf: appendix.utf8)
                documents.append(
                    (
                        vault,
                        NoteDocument(
                            relativePath: String(note.path.dropFirst(root.path.count + 1)),
                            rawContent: String(decoding: bytes, as: UTF8.self))
                    ))
            }
        }
        #expect(documents.count == 500)
        if !FileManager.default.fileExists(atPath: databaseURL.path) {
            let indexed = documents.map { vault, document in
                SearchIndexDocument(vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role, document: document)
            }
            let index = try TriptychSearchIndex(databaseURL: databaseURL, triptychID: triptychID, vaults: vaults)
            _ = try await index.synchronize(indexed)
        }
        var samples: [Double] = []
        for _ in 0..<3 {
            let start = ContinuousClock.now
            let opened = try TriptychSearchIndex.openRecovering(databaseURL: databaseURL, triptychID: triptychID, vaults: vaults)
            let duration = start.duration(to: .now).components
            samples.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
            #expect(!opened.recoveredCorruption)
            let result = try await opened.index.testSearch(
                SearchRequest(query: "refreshdiagnosticneedle", presentationScope: .triptych, executionScope: .triptych, limit: 10))
            #expect(result.noteResults.count == 1)
            #expect(result.noteResults.first?.fingerprint == documents.first?.1.fingerprint)
        }
        let report: [String: Any] = [
            "notes": documents.count,
            "bytes": documents.reduce(0) { $0 + $1.1.fingerprint.byteCount }, "index_open_ms": samples,
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("\(label).json"))
        print("SEARCH_OPEN_DIAGNOSTIC label=\(label) index_open_ms=\(samples) notes=500")
        if ProcessInfo.processInfo.environment["SCHOLIUM_SEARCH_OPEN_DIAGNOSTIC_CLEANUP"] == "1" {
            try FileManager.default.removeItem(at: state)
        }
    }
}
