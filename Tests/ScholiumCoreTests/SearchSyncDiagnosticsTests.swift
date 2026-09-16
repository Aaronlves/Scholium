import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

/// Opt-in diagnostic evidence; these measurements do not establish a release gate.
@Suite(
    "Search synchronization diagnostics", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_SEARCH_SYNC_DIAGNOSTIC"] == "1"))
struct SearchSyncDiagnosticsTests {
    @Test("Compare exact paragraph serialization with the existing lossless offset codec")
    func paragraphStorageSerialization() throws {
        let paragraph = String(
            repeating: "Evidence, inference, objection, and source authority. 哲学概念需要精确分析。 ", count: 4)
        let body = (0..<45).map { "Paragraph \($0): \(paragraph)" }.joined(separator: "\n\n")
        let projection = SearchDocumentProjection(
            document: NoteDocument(relativePath: "Codec.md", rawContent: body))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for sample in 0..<5 {
            let verboseStart = ContinuousClock.now
            let verbose = try encoder.encode(projection.paragraphs)
            let verboseMS = milliseconds(verboseStart.duration(to: .now))
            let compactStart = ContinuousClock.now
            let compact = try TriptychSearchIndex.encodedParagraphs(projection.paragraphs)
            let compactMS = milliseconds(compactStart.duration(to: .now))
            let verboseDecodeStart = ContinuousClock.now
            let original = try JSONDecoder().decode([SearchParagraphProjection].self, from: verbose)
            let verboseDecodeMS = milliseconds(verboseDecodeStart.duration(to: .now))
            let compactDecodeStart = ContinuousClock.now
            let decoded = try TriptychSearchIndex.decodedStoredParagraphs(
                from: String(decoding: compact, as: UTF8.self))
            let compactDecodeMS = milliseconds(compactDecodeStart.duration(to: .now))
            #expect(original == projection.paragraphs)
            #expect(decoded == projection.paragraphs)
            print(
                "PARAGRAPH_STORAGE_DIAGNOSTIC sample=\(sample) verbose_bytes=\(verbose.count) compact_bytes=\(compact.count) verbose_encode_ms=\(verboseMS) compact_encode_ms=\(compactMS) verbose_decode_ms=\(verboseDecodeMS) compact_decode_ms=\(compactDecodeMS)"
            )
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let value = duration.components
        return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1e15
    }

    @Test(
        "Record cold, reopened, repeated, and one-note publication over 433 long mixed-script Notes")
    func longNoteSynchronization() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(
            ".build/search-sync-diagnostics/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let vaults = [
            RegisteredVault(
                name: "Analyses", role: .sourceCorpus,
                canonicalPath: root.appendingPathComponent("analyses").path),
            RegisteredVault(
                name: "Topics", role: .topicKnowledge,
                canonicalPath: root.appendingPathComponent("topics").path),
            RegisteredVault(
                name: "Works", role: .draftProject, canonicalPath: root.appendingPathComponent("works").path
            ),
        ]
        let paragraph = String(
            repeating: "Evidence, inference, objection, and source authority. 哲学概念需要精确分析。 ", count: 4)
        let body = (0..<45).map { "Paragraph \($0): \(paragraph)" }.joined(separator: "\n\n")
        var documents = (0..<433).map { number in
            let vault = vaults[number % 3]
            return SearchIndexDocument(
                vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                document: NoteDocument(
                    relativePath: "Note-\(number).md",
                    rawContent:
                        "---\nkeywords: [fixture, cluster-\(number % 7)]\nstatus: draft\n---\n# Note \(number)\n\n\(body)"
                ))
        }
        let totalBytes = documents.reduce(0) { $0 + $1.document.fingerprint.byteCount }
        let totalSegments = documents.reduce(0) { $0 + $1.projection.segments.count }
        print(
            "SEARCH_SYNC_DIAGNOSTIC fixture notes=\(documents.count) bytes=\(totalBytes) segments=\(totalSegments)"
        )
        for sample in 0..<3 {
            let triptychID = UUID()
            let url = root.appendingPathComponent("sample-\(sample).sqlite")
            let cold = try TriptychSearchIndex(databaseURL: url, triptychID: triptychID, vaults: vaults)
            _ = try await cold.synchronize(documents)
            await report(cold, scenario: "cold", sample: sample)
            let reopened = try TriptychSearchIndex(
                databaseURL: url, triptychID: triptychID, vaults: vaults)
            let unchanged = try await reopened.synchronize(documents)
            #expect(unchanged.disposition == .unchanged)
            await report(reopened, scenario: "reopened", sample: sample)
            _ = try await reopened.synchronize(documents)
            await report(reopened, scenario: "repeated", sample: sample)
            let original = documents[0]
            documents[0] = SearchIndexDocument(
                vaultID: original.vaultID, vaultName: original.vaultName,
                vaultRole: original.vaultRole,
                document: NoteDocument(
                    relativePath: original.relativePath,
                    rawContent: original.document.rawContent + "\n\nChanged revision \(sample)."))
            let changed = try await reopened.synchronize(documents)
            #expect(changed.disposition == .incrementallyUpdated)
            await report(reopened, scenario: "one_note", sample: sample)
            documents[0] = original
        }
    }

    private func report(_ index: TriptychSearchIndex, scenario: String, sample: Int) async {
        guard let timing = await index.lastSynchronizationTimings else { return }
        print(
            "SEARCH_SYNC_DIAGNOSTIC sample=\(sample) scenario=\(scenario) preparation_ms=\(timing.preparationMilliseconds) publication_ms=\(timing.publicationMilliseconds) changed=\(timing.changedCount) hash_misses=\(timing.hashMissCount)"
        )
    }
}
