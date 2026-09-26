import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Related-content source preparation batches")
struct RelatedContentPreparationBatchTests {
    @Test("Fresh source preparation preserves retrieval across several batches")
    func freshSources() async throws {
        try await verifyPreparation(candidateCount: 40)
    }

    @Test("Large Notes flush the source byte bound before the count bound")
    func largeSources() async throws {
        try await verifyPreparation(candidateCount: 4, paragraphRepetitions: 7_500)
    }

    @Test(
        "Measure fresh source retention across 500 synthetic Notes",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_RELATED_BATCHES"] == "1"))
    func sourceRetentionMeasurement() async throws {
        try await verifyPreparation(candidateCount: 499)
    }

    private func verifyPreparation(candidateCount: Int, paragraphRepetitions: Int = 120) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/related-preparation-batches/\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let analyses = root.appendingPathComponent("analyses")
        let topics = root.appendingPathComponent("topics")
        let works = root.appendingPathComponent("works")
        for directory in [analyses, topics, works] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let seed = "Orchard geology examines sediment, roots and evidence."
        try Data(seed.utf8).write(to: works.appendingPathComponent("Draft.md"))
        var sourceByteCount = 0
        var maximumSourceByteCount = 0
        for number in 0..<candidateCount {
            let text =
                "Orchard geology records sample \(number), sediment and roots.\n\n"
                + String(repeating: "Evidence from orchard geology describes the sediment and roots in a regional context. ", count: paragraphRepetitions)
                + "\n"
            let bytes = Data(text.utf8)
            sourceByteCount += bytes.count
            maximumSourceByteCount = max(maximumSourceByteCount, bytes.count)
            try bytes.write(to: analyses.appendingPathComponent("Context-\(number).md"))
        }
        let support = root.appendingPathComponent("state")
        let live = WorkspaceRuntime(
            configuration: .live(.init(applicationSupportURL: support, workspaceRegistryStorageURL: root.appendingPathComponent("registry"))))
        let configured = try await live.configureTriptych(
            paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
            portableContainerURL: root, triptychName: "Preparation batches fixture")
        let assignment = configured.assignment
        await live.shutdown()
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(applicationSupportURL: support, assignments: [assignment])))
        do {
            let handle = try await runtime.openWorkspace(id: assignment.id)
            let vault = try #require(assignment.vault(for: .output)?.id)
            let request = RelatedContentRequest(
                seed: .init(noteID: .init(vaultID: vault, relativePath: "Draft.md"), source: seed))
            let cold = try await handle.discovery.relatedContent(request)
            #expect(!cold.passages.isEmpty)
            #expect(await handle.lastRelatedContentMeasurement?.sourceCount == candidateCount)
            let before = try await handle.snapshot()
            let measured = try #require(await handle.prepareRelatedContent(request))
            #expect(measured.sourceCount == candidateCount)
            #expect(measured.peakBufferedSourceCount <= 16)
            #expect(measured.peakBufferedSourceBytes < sourceByteCount)
            #expect(measured.peakBufferedSourceBytes < 1_024 * 1_024 + maximumSourceByteCount)
            print(
                "Fresh-source preparation: candidates=\(candidateCount) totalSourceBytes=\(sourceByteCount) "
                    + "peakBufferedSources=\(measured.peakBufferedSourceCount) peakBufferedSourceBytes=\(measured.peakBufferedSourceBytes)")
            #expect(try await handle.discovery.relatedContent(request) == cold)
            let after = try await handle.snapshot()
            #expect(after.generatedAt == before.generatedAt)
            #expect(after.discovery.searchGeneration == before.discovery.searchGeneration)
        } catch {
            await runtime.shutdown()
            throw error
        }
        await runtime.shutdown()
    }
}
