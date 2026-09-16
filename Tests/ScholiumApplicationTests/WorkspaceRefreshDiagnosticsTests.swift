import CryptoKit
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Workspace refresh diagnostics", .serialized)
struct WorkspaceRefreshDiagnosticsTests {
    @Test(
        "Expanded standard Triptych measures cold, reopened, and unchanged refreshes",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_REFRESH_DIAGNOSTIC"] == "1")
    )
    func expandedTriptychRefresh() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let outputRoot = repositoryRoot.appendingPathComponent(".build/refresh-optimization")
        let root = outputRoot.appendingPathComponent(UUID().uuidString.lowercased())
        let fixtureRoot = root.appendingPathComponent("fixture")
        let stateRoot = root.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent("TestVaults"), to: fixtureRoot
        )

        let slots = ["01-analyses", "02-topics", "03-works"]
        var sourceOracle: [URL: Data] = [:]
        let paragraph =
            "The researcher examines an argument and its objection. "
            + "研究者保留原文、异议与回应之间的区别。Unicode: café, cafe\u{301}, 🦉. "
            + "Exact source locations remain tied to the current document.\n\n"
        var expectedNeedlePath: String?
        for slot in slots {
            let vaultURL = fixtureRoot.appendingPathComponent(slot)
            let enumerator = try #require(
                FileManager.default.enumerator(
                    at: vaultURL, includingPropertiesForKeys: nil
                ))
            let notes = enumerator.compactMap { $0 as? URL }
                .filter { $0.pathExtension.lowercased() == "md" }
                .sorted { $0.path < $1.path }
            for note in notes {
                var bytes = try Data(contentsOf: note)
                let repetitions = max(1, (14_000 - bytes.count) / paragraph.utf8.count)
                var appendix =
                    "\n\n# Refresh diagnostic\n\n"
                    + String(repeating: paragraph, count: repetitions)
                if expectedNeedlePath == nil {
                    appendix += "refreshdiagnosticneedle\n"
                    expectedNeedlePath = String(note.path.dropFirst(vaultURL.path.count + 1))
                }
                bytes.append(contentsOf: appendix.utf8)
                try bytes.write(to: note)
                sourceOracle[note] = bytes
            }
        }
        #expect(sourceOracle.count == 500)
        let applicationSupportURL = stateRoot.appendingPathComponent("Application Support")
        let registryStorageURL = stateRoot.appendingPathComponent("Registry")
        let configuration = WorkspaceRuntime.Configuration.live(
            .init(
                applicationSupportURL: applicationSupportURL,
                workspaceRegistryStorageURL: registryStorageURL
            ))
        let setup = WorkspaceRuntime(configuration: configuration)
        let clock = ContinuousClock()
        let coldStart = clock.now
        let configured: WorkspaceHandle
        do {
            configured = try await setup.configureTriptych(
                paperAnalysisURL: fixtureRoot.appendingPathComponent(slots[0]),
                topicKnowledgeURL: fixtureRoot.appendingPathComponent(slots[1]),
                outputURL: fixtureRoot.appendingPathComponent(slots[2]),
                portableContainerURL: fixtureRoot,
                triptychName: "Refresh Diagnostic"
            )
        } catch {
            await setup.shutdown()
            throw error
        }
        let coldElapsed = coldStart.duration(to: clock.now)
        let assignment = configured.assignment
        let coldMeasurement = await configured.latestRefreshMeasurement
        await setup.shutdown()
        var samples: [[String: Any]] = []
        for iteration in 0..<3 {
            let runtime = WorkspaceRuntime(configuration: configuration)
            do {
                let openStart = clock.now
                let handle = try await runtime.openWorkspace(
                    id: assignment.id, openingVault: .paperAnalysis
                )
                let usableElapsed = openStart.duration(to: clock.now)
                let stream = await handle.events.events()
                var events = stream.makeAsyncIterator()
                let opening = try #require(await events.next())
                try #require(!opening.snapshot.phase.isComplete)
                let completionStart = clock.now
                await handle.openingPresentationDidComplete()
                _ = try await completeSnapshot(in: stream)
                let completionElapsed = completionStart.duration(to: clock.now)
                await handle.awaitOpeningCompletionForTesting()
                let refreshed = await handle.latestRefreshMeasurement
                #expect(refreshed.projectedDocuments == 0)
                #expect(refreshed.restoredSearchProjections == 500)
                let response = try await handle.discovery.search(
                    SearchRequest(
                        query: "refreshdiagnosticneedle",
                        presentationScope: .triptych, executionScope: .triptych, limit: 20
                    ))
                #expect(response.results.count == 1)
                switch try #require(response.results.first) {
                case .note(let result):
                    #expect(result.relativePath == expectedNeedlePath)
                }
                let cycle = try #require(await handle.latestRefreshCycleMeasurement)
                #expect(cycle.workspaceGeneration == refreshed.workspaceGeneration)
                #expect(cycle.totalDuration >= cycle.sourcePreparationDuration + cycle.buildDuration)
                samples.append([
                    "iteration": iteration,
                    "usable_open_ms": milliseconds(usableElapsed),
                    "completion_after_presentation_ms": milliseconds(completionElapsed),
                    "source_preparation_ms": milliseconds(cycle.sourcePreparationDuration),
                    "build_ms": milliseconds(cycle.buildDuration),
                    "cycle_ms": milliseconds(cycle.totalDuration),
                    "search_ms": milliseconds(refreshed.searchDuration),
                    "identity_ms": milliseconds(refreshed.identityProjectionDuration),
                    "link_catalog_ms": milliseconds(refreshed.linkCatalogProjectionDuration),
                    "read_files": refreshed.readFiles,
                    "projected_documents": refreshed.projectedDocuments,
                    "restored_search_projections": refreshed.restoredSearchProjections,
                    "cache_read_work_ms": milliseconds(refreshed.cacheReadDuration),
                    "cache_write_work_ms": milliseconds(refreshed.cacheWriteDuration),
                ])
                let unchangedStart = clock.now
                _ = try await handle.discovery.refresh()
                let unchangedElapsed = unchangedStart.duration(to: clock.now)
                let unchanged = await handle.latestRefreshMeasurement
                #expect(unchanged.readFiles == 0)
                #expect(unchanged.parsedDocuments == 0)
                #expect(unchanged.projectedDocuments == 0)
                samples[samples.count - 1]["unchanged_refresh_ms"] = milliseconds(unchangedElapsed)
                samples[samples.count - 1]["unchanged_identity_ms"] = milliseconds(unchanged.identityProjectionDuration)
                samples[samples.count - 1]["unchanged_link_catalog_ms"] = milliseconds(unchanged.linkCatalogProjectionDuration)
                await runtime.shutdown()
            } catch {
                await runtime.shutdown()
                throw error
            }
        }
        for (url, expected) in sourceOracle {
            #expect(try Data(contentsOf: url) == expected)
        }
        let label = ProcessInfo.processInfo.environment["SCHOLIUM_REFRESH_DIAGNOSTIC_LABEL"] ?? "sample"
        let safeLabel = label.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let report: [String: Any] = [
            "fixture": "standard-500-expanded-mixed-script",
            "fixture_sha256": fixtureHash(sourceOracle, fixtureRoot: fixtureRoot),
            "source_bytes": sourceOracle.values.reduce(0) { $0 + $1.count },
            "configuration": "SwiftPM Debug; presentation wait excluded",
            "cold_configuration_ms": milliseconds(coldElapsed),
            "cold_search_ms": milliseconds(coldMeasurement.searchDuration),
            "cold_cache_read_work_ms": milliseconds(coldMeasurement.cacheReadDuration),
            "cold_cache_write_work_ms": milliseconds(coldMeasurement.cacheWriteDuration),
            "samples": samples,
        ]
        let reportURL = outputRoot.appendingPathComponent("application-\(safeLabel).json")
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: reportURL)
        print("Refresh diagnostic: 500 source-faithful notes; cold/reopened/unchanged samples recorded at \(reportURL.path)")
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }

    private enum DiagnosticError: Error {
        case refreshFailed
        case streamFinished
        case timedOut
    }

    private func completeSnapshot(in stream: AsyncStream<WorkspaceEvent>) async throws -> WorkspaceSnapshot {
        try await withThrowingTaskGroup(of: WorkspaceSnapshot.self) { group in
            group.addTask {
                for await event in stream {
                    if event.snapshot.phase.isComplete { return event.snapshot }
                    if case .failed = event.derivedRefreshStatus { throw DiagnosticError.refreshFailed }
                }
                throw DiagnosticError.streamFinished
            }
            group.addTask {
                try await Task.sleep(for: .seconds(60))
                throw DiagnosticError.timedOut
            }
            defer { group.cancelAll() }
            let result = try await group.next()
            return try #require(result)
        }
    }

    private func fixtureHash(_ sources: [URL: Data], fixtureRoot: URL) -> String {
        var hash = SHA256()
        for (url, data) in sources.sorted(by: { $0.key.path < $1.key.path }) {
            hash.update(data: Data(url.path.dropFirst(fixtureRoot.path.count + 1).utf8))
            hash.update(data: Data([0]))
            hash.update(data: data)
            hash.update(data: Data([0]))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
