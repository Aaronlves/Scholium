import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

/// Owning Application-operation timings, not native sheet/paint latency. Receipt
/// history is seeded through its real store; timed Undo uses a fresh, admitted
/// source mutation each time and never replays an already-completed operation.
@Suite(
    "Agent Undo and receipt history performance diagnostics", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_AGENT_UNDO"] == "1"))
struct AgentUndoPerformanceDiagnosticTests {
    @Test("Measure receipt review, distinct Undo and secondary refresh with small and large retained history")
    func retainedHistoryCosts() async throws {
        for receiptCount in [10, 1_000] {
            let fixture = try await ApplicationFixture.make()
            defer { fixture.remove() }
            let sourceURL = fixture.analysesURL.appendingPathComponent("Agency.md")
            let paragraphs = (0..<24).map {
                "Synthetic paragraph \($0). Reasons and agency relate to [[Freedom]] without becoming evidence. 中文 exact source."
            }.joined(separator: "\r\n\r\n")
            let original = "\u{FEFF}---\r\nsummary: Synthetic Undo timing\r\nunknown_field: 'KEEP: 原始'\r\n---\r\n\r\n# Agency\r\n\r\n" + paragraphs + "\r\n"
            let originalData = Data(original.utf8)
            try originalData.write(to: sourceURL)
            let runtime = WorkspaceRuntime(
                configuration: .snapshot(
                    .init(
                        applicationSupportURL: fixture.applicationSupportURL,
                        assignments: [fixture.assignment], defaultWorkspaceID: fixture.assignment.id)))
            do {
                let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
                let note = try #require(try await handle.snapshot().document(id: fixture.analysisNoteID))
                let noteID = try #require(note.stableIdentity.resolvedID)
                let operations = handle.agentCollaboration
                let services = await handle.services
                // Setup is deliberately untimed. These are integrity-valid
                // historical receipts, not a replay of 1,000 source mutations.
                let historicalAfter = Data((original + "\r\nHistorical synthetic change.\r\n").utf8)
                for _ in 0..<receiptCount {
                    let prepared = try await services.agentChangeStore.prepare(
                        operation: .update, noteID: noteID, role: .sourceCorpus,
                        originalRelativePath: fixture.analysisNoteID.relativePath,
                        finalRelativePath: fixture.analysisNoteID.relativePath,
                        beforeData: originalData, afterData: historicalAfter)
                    _ = try await services.agentChangeStore.confirm(
                        id: prepared.id, observedAfterFingerprint: .init(data: historicalAfter))
                }
                #expect(try await operations.agentChanges().count == receiptCount)
                var samples: [String: [Double]] = [:]
                let clock = ContinuousClock()
                var cancelledReadReturns: [Int] = []
                var cancelledReadCancellations = 0
                // Cancel before entering the real public history API. This
                // deliberately records both baseline outcomes without making
                // cancellation support a diagnostic-pass prerequisite.
                for index in 0..<12 {
                    let start = clock.now
                    let request = Task {
                        withUnsafeCurrentTask { $0?.cancel() }
                        return try await operations.agentChanges()
                    }
                    let returnedCount: Int?
                    do {
                        returnedCount = try await request.value.count
                    } catch is CancellationError {
                        returnedCount = nil
                    }
                    let end = clock.now
                    if let returnedCount { #expect(returnedCount == receiptCount) }
                    if index >= 3 {
                        samples["pre_cancelled_history", default: []].append(milliseconds(start.duration(to: end)))
                        if let returnedCount { cancelledReadReturns.append(returnedCount) } else { cancelledReadCancellations += 1 }
                    }
                }
                for index in 0..<12 {
                    let changed = original + "\r\nCurrent synthetic change \(index).\r\n"
                    let update = try await operations.updateNote(
                        noteID: noteID, expectedFingerprint: .init(data: originalData), update: .source(changed))
                    try #require(update.readbackVerified)
                    let reviewStart = clock.now
                    let opened = try await operations.agentChangeReview(id: update.change.id)
                    let reviewEnd = clock.now
                    try #require(opened.change == update.change && opened.isDirectUndoAvailable)
                    let start = clock.now
                    let undone = try await operations.undoAgentChange(
                        id: update.change.id, expectedAfterFingerprint: update.afterFingerprint)
                    let committed = clock.now
                    let discovery = try await handle.discovery.snapshot()
                    let projected = clock.now
                    let history = try await operations.agentChanges()
                    let listed = clock.now
                    let refreshed = try await operations.agentChangeReview(id: update.change.id)
                    let completed = clock.now
                    // Exact source and authoritative result remain the oracle;
                    // all assertions and readback are outside elapsed intervals.
                    #expect(undone.changeID == update.change.id && undone.noteID == noteID)
                    #expect(undone.restoredFingerprint == DocumentFingerprint(data: originalData))
                    #expect(refreshed.change.state == .undone && !refreshed.isDirectUndoAvailable)
                    #expect(history.count == receiptCount + index + 1)
                    #expect(history.first(where: { $0.id == update.change.id })?.state == .undone)
                    #expect(discovery.catalog.notes.count == 3)
                    #expect(try Data(contentsOf: sourceURL) == originalData)
                    if index >= 3 {
                        samples["open_current_receipt", default: []].append(milliseconds(reviewStart.duration(to: reviewEnd)))
                        samples["authoritative_undo", default: []].append(milliseconds(start.duration(to: committed)))
                        samples["catalog_snapshot", default: []].append(milliseconds(committed.duration(to: projected)))
                        samples["history_reload", default: []].append(milliseconds(projected.duration(to: listed)))
                        samples["post_undo_receipt", default: []].append(milliseconds(listed.duration(to: completed)))
                        samples["undo_through_secondary_completion", default: []].append(milliseconds(start.duration(to: completed)))
                    }
                }
                for phase in samples.keys.sorted() {
                    let values = try #require(samples[phase])
                    let sorted = values.sorted()
                    let mean = values.reduce(0, +) / Double(values.count)
                    let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
                    #if DEBUG
                        let configuration = "Debug"
                    #else
                        let configuration = "Release"
                    #endif
                    var record: [String: Any] = [
                        "configuration": configuration, "notes": 3, "initial_receipts": receiptCount,
                        "receipt_growth_per_sample": phase == "pre_cancelled_history" ? 0 : 1,
                        "warmups": 3, "samples": values.count,
                        "source_utf8_bytes": originalData.count, "phase": phase,
                        "median_ms": sorted[sorted.count / 2], "min_ms": sorted[0], "max_ms": sorted[sorted.count - 1],
                        "mean_ms": mean, "sample_stddev_ms": variance.squareRoot(), "raw_ms": values,
                    ]
                    if phase == "pre_cancelled_history" {
                        record["returned_reads"] = cancelledReadReturns.count
                        record["returned_rows"] = cancelledReadReturns
                        record["cancelled_reads"] = cancelledReadCancellations
                    }
                    let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                    print("AgentUndoPerformanceDiagnostic " + String(decoding: data, as: UTF8.self))
                }
                await runtime.shutdown()
            } catch {
                await runtime.shutdown()
                throw error
            }
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
