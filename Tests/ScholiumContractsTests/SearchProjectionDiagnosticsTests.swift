import CryptoKit
import Foundation
import ScholiumContracts
import Testing

/// Opt-in source-projection diagnostics, separate from startup or release acceptance.
@Suite(
    "Search source projection diagnostics", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_PROJECTION_DIAGNOSTIC"] == "1"))
struct SearchProjectionDiagnosticsTests {
    @Test("Expanded standard Triptych preserves complete projection output")
    func expandedTriptych() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let output = repository.appendingPathComponent(".build/projection-cost")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let paragraph =
            "The researcher examines an argument and its objection. "
            + "研究者保留原文、异议与回应之间的区别。Unicode: café, cafe\u{301}, 🦉. "
            + "Exact source locations remain tied to the current document.\n\n"
        var documents: [NoteDocument] = []
        var first = true
        for slot in ["01-analyses", "02-topics", "03-works"] {
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
                    NoteDocument(
                        relativePath: String(note.path.dropFirst(root.path.count + 1)),
                        rawContent: String(decoding: bytes, as: UTF8.self)))
            }
        }
        #expect(documents.count == 500)
        // Exercise composed/decomposed graphemes, folding expansions, surrogate pairs,
        // whitespace collapse, entities, inline delimiters and repeated exact locations.
        documents.append(
            NoteDocument(
                relativePath: "Unicode.md",
                rawContent:
                    "\u{FEFF}---\r\ntitle: 'Àßİﬃ K'\r\nsummary: 'cafe\u{301} Σςσ'\r\n---\r\n# Émotion\r\n\r\n"
                    + "ＡＢＣ À a\u{300} ß ﬃ İ K Σςσ 🦉 👨‍👩‍👧‍👦 \u{00A0}\t\r\n"
                    + "**cafe\u{301}** &amp; [[Target|Àß]]{{Àß}} repeated repeated\r\n\r\nlast\u{2003}word"))
        let semantic = documents.map { MarkdownSemanticDocument(parsing: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var hashes: [String] = []
        var samples: [Double] = []
        let sampleCount = Int(ProcessInfo.processInfo.environment["SCHOLIUM_PROJECTION_DIAGNOSTIC_SAMPLES"] ?? "3") ?? 3
        for sample in 0..<sampleCount {
            let start = ContinuousClock.now
            let projections = zip(documents, semantic).map { SearchDocumentProjection(document: $0.0, semantic: $0.1) }
            let duration = start.duration(to: .now).components
            samples.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
            if sample == 0 {
                hashes = try projections.map { projection in
                    try autoreleasepool {
                        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(projection)) as? [String: Any])
                        // Set iteration order has no semantic meaning and varies per process.
                        object["calloutRoles"] = projection.calloutRoles.sorted()
                        let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                        return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
                    }
                }
            }
        }
        let label = (ProcessInfo.processInfo.environment["SCHOLIUM_PROJECTION_DIAGNOSTIC_LABEL"] ?? "sample")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let baseline = output.appendingPathComponent("baseline.json")
        if label != "baseline", FileManager.default.fileExists(atPath: baseline.path) {
            let oracle = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: baseline)) as? [String: Any])
            let expected = try #require(oracle["hashes"] as? [String])
            #expect(hashes.count == expected.count)
            let mismatches = zip(hashes, expected).enumerated().compactMap { $0.element.0 == $0.element.1 ? nil : $0.offset }
            #expect(mismatches.isEmpty, "Complete projection mismatch indices: \(mismatches)")
        }
        let report: [String: Any] = [
            "notes": documents.count, "bytes": documents.reduce(0) { $0 + $1.fingerprint.byteCount },
            "projection_ms": samples, "hashes": hashes,
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("\(label).json"))
        print("SOURCE_PROJECTION_DIAGNOSTIC label=\(label) samples_ms=\(samples) full_projection_oracles=\(hashes.count)")
    }
}
