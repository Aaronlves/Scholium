import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Triptych body writing completion")
struct WritingBodyCompletionTests {
    @Test("All three vault bodies complete locally and current source, refresh, deletion and cancellation revoke stale terms")
    func corpusLifecycle() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/writing-body-tests/\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let analyses = root.appendingPathComponent("analyses")
        let topics = root.appendingPathComponent("topics")
        let works = root.appendingPathComponent("works")
        for directory in [analyses, topics, works] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let target = topics.appendingPathComponent("Heading.md")
        let heading = "# Manual Heading Completion Target"
        try Data(heading.utf8).write(to: target)
        try Data("Responsibility concerns reasons.".utf8).write(to: analyses.appendingPathComponent("Paper.md"))
        try Data("控制条件影响判断。".utf8).write(to: works.appendingPathComponent("Draft.md"))
        try Data("---\ntitle: MetadataSecret\n---\n`CodeSecret`\n".utf8).write(to: topics.appendingPathComponent("Excluded.md"))
        try Data("> [!state] Claim\n> Synthetic Callout Vocabulary Target".utf8).write(to: works.appendingPathComponent("Callout.md"))
        try Data(
            "DestinationPublication establishes visibility.\n\n![[Hidden$MathSecret$Destination|Visible picture]]\n\nTrailingVocabulary remains readable.".utf8
        ).write(to: works.appendingPathComponent("Nested.md"))
        // Technical-only matches must not crop a valid Note out of the full corpus.
        for number in 0..<30 {
            try Data("`CrowdedCorpusVocabulary`".utf8).write(to: topics.appendingPathComponent("Technical-\(number).md"))
        }
        try Data("CrowdedCorpusVocabulary concerns a claim.".utf8).write(to: works.appendingPathComponent("Actual.md"))
        let support = root.appendingPathComponent("state")
        let live = WorkspaceRuntime(
            configuration: .live(.init(applicationSupportURL: support, workspaceRegistryStorageURL: root.appendingPathComponent("registry"))))
        let configured = try await live.configureTriptych(
            paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works, portableContainerURL: root, triptychName: "Writing completion fixture")
        let assignment = configured.assignment
        await live.shutdown()
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(applicationSupportURL: support, assignments: [assignment])))
        let handle = try await runtime.openWorkspace(id: assignment.id)
        do {
            let before = try await handle.snapshot()
            let clock = ContinuousClock()
            let start = clock.now
            #expect(try await handle.discovery.writingCompletions(matching: " Manual Heading Completion T").first == "Manual Heading Completion Target")
            print("Writing completion heading query duration: \(start.duration(to: clock.now))")
            let firstMeasurement = try #require(await handle.lastWritingCompletionMeasurement)
            #expect(firstMeasurement.sourceReads > 0 && firstMeasurement.projectionBuilds > 0)
            let warmStart = clock.now
            #expect(try await handle.discovery.writingCompletions(matching: " Manual Heading Completion T").first == "Manual Heading Completion Target")
            let reusedMeasurement = try #require(await handle.lastWritingCompletionMeasurement)
            #expect(reusedMeasurement.sourceReads > 0)
            #expect(reusedMeasurement.projectionBuilds == 0 && reusedMeasurement.projectionReuses > 0)
            print(
                "Writing completion source-checked warm query duration: \(warmStart.duration(to: clock.now)); reads=\(reusedMeasurement.sourceReads) reused=\(reusedMeasurement.projectionReuses) built=\(reusedMeasurement.projectionBuilds)"
            )
            // A longer prefix can admit new FTS source candidates while reusing the prior target.
            #expect(try await handle.discovery.writingCompletions(matching: "Manual Heading Completion Ta").first == "Manual Heading Completion Target")
            let extendedMeasurement = try #require(await handle.lastWritingCompletionMeasurement)
            #expect(extendedMeasurement.sourceReads > 0 && extendedMeasurement.projectionReuses > 0)

            #expect(try await handle.discovery.writingCompletions(matching: "A claim about Responsib").contains("Responsibility"))
            #expect(try await handle.discovery.writingCompletions(matching: "这里的控制").contains("控制条件"))
            #expect(try await handle.discovery.writingCompletions(matching: "Synthetic Callout Vocabulary T").contains("Synthetic Callout Vocabulary Target"))
            #expect(try await handle.discovery.writingCompletions(matching: "CrowdedCorpusVocab").contains("CrowdedCorpusVocabulary"))
            let destinations = try await handle.discovery.writingCompletions(matching: "Dest")
            #expect(destinations.contains("DestinationPublication"))
            #expect(!destinations.contains("Destination"))
            #expect(try await handle.discovery.writingCompletions(matching: "TrailingV").contains("TrailingVocabulary"))
            #expect(try await handle.discovery.writingCompletions(matching: "MetadataS").isEmpty)
            #expect(try await handle.discovery.writingCompletions(matching: "CodeS").isEmpty)
            #expect(try String(contentsOf: target, encoding: .utf8) == heading)
            let after = try await handle.snapshot()
            #expect(after.generatedAt == before.generatedAt)
            #expect(after.discovery.searchGeneration == before.discovery.searchGeneration)
            try Data("# Replacement Heading Completion Target".utf8).write(to: target)
            await #expect(throws: (any Error).self) { try await handle.discovery.writingCompletions(matching: "Manual Heading Completion T") }
            _ = try await handle.discovery.refresh()
            #expect(
                try await handle.discovery.writingCompletions(matching: "Replacement Heading Completion T").first == "Replacement Heading Completion Target")
            try FileManager.default.removeItem(at: target)
            _ = try await handle.discovery.refresh()
            #expect(try await handle.discovery.writingCompletions(matching: "Replacement Heading Completion T").isEmpty)
            let cancelled = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await handle.discovery.writingCompletions(matching: "Responsib")
            }
            await #expect(throws: CancellationError.self) { try await cancelled.value }
        } catch {
            await runtime.shutdown()
            throw error
        }
        await runtime.shutdown()
        #expect(await handle.writingCompletionMemo.entryCount == 0)
        #expect(await handle.writingCompletionMemo.estimatedByteCount == 0)
        await #expect(throws: (any Error).self) { try await handle.discovery.writingCompletions(matching: "Responsib") }
    }
}
