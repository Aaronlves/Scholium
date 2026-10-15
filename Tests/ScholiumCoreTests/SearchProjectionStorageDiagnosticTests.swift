import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

/// Opt-in measurements over immutable synthetic inputs. No source or path enters the report.
@Suite(
    "Search projection storage diagnostics", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_PROJECTION_STORAGE_DIAGNOSTIC"] == "1"))
struct SearchProjectionStorageDiagnosticTests {
    @Test("Measure lossless source projections and their persisted coordinate material")
    func storageComponents() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let build = repository.appendingPathComponent(".build", isDirectory: true)
        let fixture = build.appendingPathComponent("stress-audit/fixture-complex-508", isDirectory: true)
        let root = build.appendingPathComponent("projection-storage-diagnostic/\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cases: [(String, String)] = [
            ("long_prose", "01-analyses/Stress/Stress Long Prose.md"),
            ("near_source_limit", "01-analyses/Stress/Stress Near Source Limit.md"),
            ("dense_links", "02-topics/Stress/Stress Dense Links.md"),
            ("nested_callouts", "02-topics/Stress/Stress Nested Callouts.md"),
            ("format_matrix", "03-works/Stress/Stress Format Matrix.md"),
            ("source_fidelity", "03-works/Stress/Stress Source Fidelity.md"),
        ]
        let cache = SourceSearchProjectionCache(applicationSupportURL: root, vaultID: UUID(), role: .topicKnowledge)
        var records: [[String: Any]] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for (kind, path) in cases {
            if let selected = ProcessInfo.processInfo.environment["SCHOLIUM_PROJECTION_STORAGE_CASE"], selected != kind { continue }
            let data = try Data(contentsOf: fixture.appendingPathComponent(path))
            let source = try #require(String(data: data, encoding: .utf8))
            let document = NoteDocument(relativePath: path, rawContent: source)
            let projection = SearchDocumentProjection(document: document)
            let segmentOffsets = projection.segments.map(\.offsetMap)
            let paragraphOffsets = projection.paragraphs.flatMap { $0.segments.map(\.offsetMap) }
            let allOffsets = segmentOffsets + paragraphOffsets
            var encodeSamples: [Double] = []
            var decodeSamples: [Double] = []
            var encodedBytes = 0
            for _ in 0..<3 {
                let encodeStart = ContinuousClock.now
                let encoded = try allOffsets.map { try SearchOffsetMapCodec.encode($0) }
                encodeSamples.append(milliseconds(encodeStart.duration(to: .now)))
                let decodeStart = ContinuousClock.now
                let decoded = try encoded.map { try SearchOffsetMapCodec.decode($0) }
                decodeSamples.append(milliseconds(decodeStart.duration(to: .now)))
                #expect(decoded == allOffsets)
                encodedBytes = encoded.reduce(0) { $0 + $1.count }
            }
            let paragraphBytes = try TriptychSearchIndex.encodedParagraphs(projection.paragraphs)
            #expect(try TriptychSearchIndex.decodedStoredParagraphs(from: paragraphBytes) == projection.paragraphs)
            let writeStart = ContinuousClock.now
            cache.store(projection, for: document)
            let writeMS = milliseconds(writeStart.duration(to: .now))
            let readStart = ContinuousClock.now
            let restored = cache.load(for: document)
            let readMS = milliseconds(readStart.duration(to: .now))
            let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]))
            var recordBytes = 0
            var cacheComponents: [String: Int] = [:]
            for case let url as URL in files where url.lastPathComponent == SourceSearchProjectionCache.fileName(path) {
                recordBytes = try #require(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                let bytes = try Data(contentsOf: url)
                let frame = try PropertyListDecoder().decode(SourceSearchProjectionCache.Frame.self, from: bytes)
                let binaryEncoder = PropertyListEncoder()
                binaryEncoder.outputFormat = .binary
                let decodedPayload = try SearchProjectionBlobCodec.decode(frame.payload)
                cacheComponents["payload_bytes"] = decodedPayload.count
                cacheComponents["binary_frame_bytes"] = try binaryEncoder.encode(frame).count
                cacheComponents["lzfse_payload_bytes"] = try (decodedPayload as NSData).compressed(using: .lzfse).length
                cacheComponents["lz4_payload_bytes"] = try (decodedPayload as NSData).compressed(using: .lz4).length
                let fields = try #require(PropertyListSerialization.propertyList(from: decodedPayload, format: nil) as? [String: Any])
                for (name, value) in fields {
                    cacheComponents["independent_field_\(name)_bytes"] = try PropertyListSerialization.data(
                        fromPropertyList: [name: value], format: .binary, options: 0
                    ).count
                }
            }
            if recordBytes > 0 { #expect(restored == projection) } else { #expect(restored == nil) }
            records.append([
                "kind": kind, "source_bytes": data.count, "source_sha256": document.fingerprint.sha256,
                "semantic_projection_sha256": DocumentFingerprint(data: try encoder.encode(projection)).sha256,
                "offset_maps": allOffsets.count, "offset_runs": allOffsets.reduce(0) { $0 + $1.count },
                "offset_storage_bytes": encodedBytes, "paragraph_storage_bytes": paragraphBytes.count,
                "lzfse_paragraph_bytes": try (paragraphBytes as NSData).compressed(using: .lzfse).length,
                "lz4_paragraph_bytes": try (paragraphBytes as NSData).compressed(using: .lz4).length,
                "cache_file_bytes": recordBytes, "cache_stored": recordBytes > 0,
                "cache_components": cacheComponents,
                "offset_encode_ms": encodeSamples, "offset_decode_ms": decodeSamples,
                "cache_write_ms": writeMS, "cache_read_ms": readMS,
            ])
        }
        let report = try JSONSerialization.data(
            withJSONObject: [
                "schema": "scholium-projection-storage-diagnostic-v1", "cases": records,
                "scope": "Debug; three codec samples; one cache write/read; exact semantic and source digests; no OS cache purge or release gate",
            ], options: [.prettyPrinted, .sortedKeys])
        if let path = ProcessInfo.processInfo.environment["SCHOLIUM_PROJECTION_STORAGE_OUTPUT"] {
            let output = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            try #require(output.path.hasPrefix(build.path + "/") && !output.path.hasPrefix(fixture.path + "/"))
            try report.write(to: output, options: .atomic)
        }
        print("PROJECTION_STORAGE_DIAGNOSTIC \(String(decoding: report, as: UTF8.self))")
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let value = duration.components
        return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1_000_000_000_000_000
    }
}
