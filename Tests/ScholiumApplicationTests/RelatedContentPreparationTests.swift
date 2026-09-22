import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Related-content background preparation")
struct RelatedContentPreparationTests {
    @Test("Preparation publishes nothing, preserves cold results and never authorizes stale source")
    func exactSourceAndScope() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/two-layer-retrieval/application-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let analyses = root.appendingPathComponent("analyses")
        let topics = root.appendingPathComponent("topics")
        let works = root.appendingPathComponent("works")
        for directory in [analyses, topics, works] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let seed = "Agency freedom background.\n\nquantum measurement"
        let target = topics.appendingPathComponent("Quantum.md")
        try Data(seed.utf8).write(to: works.appendingPathComponent("Draft.md"))
        for number in 0..<25 {
            try Data("Agency freedom background.".utf8).write(to: analyses.appendingPathComponent("Context-\(number).md"))
        }
        try Data("Quantum measurement concerns a different topic.".utf8).write(to: target)
        let support = root.appendingPathComponent("state")
        let live = WorkspaceRuntime(
            configuration: .live(.init(applicationSupportURL: support, workspaceRegistryStorageURL: root.appendingPathComponent("registry"))))
        let configured = try await live.configureTriptych(
            paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
            portableContainerURL: root, triptychName: "Preparation fixture")
        let assignment = configured.assignment
        await live.shutdown()
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(applicationSupportURL: support, assignments: [assignment])))
        let handle = try await runtime.openWorkspace(id: assignment.id)
        do {
            let vault = try #require(assignment.vault(for: .output)?.id)
            let request = RelatedContentRequest(
                seed: .init(
                    noteID: .init(vaultID: vault, relativePath: "Draft.md"), source: seed,
                    focuses: [.init(kind: .selectedPassage, text: "quantum measurement")]))
            let cold = try await handle.discovery.relatedContent(request)
            #expect(cold.passages.map(\.candidate.note.relativePath) == ["Quantum.md"])
            let before = try await handle.snapshot()
            let measurement = await handle.lastRelatedContentMeasurement?.requestID
            try await handle.discovery.prepareRelatedContent(request)
            let after = try await handle.snapshot()
            #expect(after.generatedAt == before.generatedAt)
            #expect(after.discovery.searchGeneration == before.discovery.searchGeneration)
            #expect(after.discovery.catalog.notes == before.discovery.catalog.notes)
            #expect(await handle.lastRelatedContentMeasurement?.requestID == measurement)
            #expect(try await handle.discovery.relatedContent(request) == cold)
            // The Note's broad background must not force unrelated source I/O
            // for a narrow current-line query, even when all 25 Notes are warm.
            #expect(await handle.lastRelatedContentMeasurement?.sourceCount == 1)

            // A source change that has not reached the disposable index must be
            // caught even after preparation has populated every derived cache.
            try Data("New unrelated source bytes.".utf8).write(to: target)
            let staleSource = try await handle.discovery.relatedContent(request)
            #expect(staleSource.omittedSourceCount > 0)
            #expect(!staleSource.passages.contains { $0.candidate.note.relativePath == "Quantum.md" })
            _ = try await handle.discovery.refresh()
            #expect(try await handle.discovery.relatedContent(request).passages.isEmpty)
            await #expect(throws: (any Error).self) {
                try await handle.discovery.prepareRelatedContent(
                    .init(
                        seed: .init(
                            noteID: .init(vaultID: UUID(), relativePath: "Private.md"), source: seed)))
            }
            let cancelled = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try await handle.discovery.prepareRelatedContent(request)
            }
            await #expect(throws: CancellationError.self) { try await cancelled.value }
        } catch {
            await runtime.shutdown()
            throw error
        }
        await runtime.shutdown()
        await #expect(throws: (any Error).self) {
            try await handle.discovery.prepareRelatedContent(
                .init(
                    seed: .init(
                        noteID: .init(vaultID: UUID(), relativePath: "Departed.md"), source: seed)))
        }
    }
}
