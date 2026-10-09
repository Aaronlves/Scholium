import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Chat material catalog ordering") @MainActor
struct AgentChatCatalogRegressionTests {
    @Test("Complete material results preserve ties, match tiers and all material routes")
    func orderingAndAdmission() throws {
        let fixture = ChatMaterialCatalogFixture.self
        let notes = [
            fixture.note(0, title: "Note 9", path: "Z-first.md"),
            fixture.note(1, title: "Needle extended", path: "Prefix.md"),
            fixture.note(2, title: "A Needle passage", path: "Archive/自由/reference.md"),
            fixture.note(3, title: "Needle", path: "Exact.md"),
            fixture.note(4, title: "Note 9", path: "A-second.md"),
            fixture.note(5, title: "Note 10", path: "自由/Note-10.md"),
            fixture.note(6, title: "Needle missing", path: "Missing.md", stableID: nil),
            fixture.note(7, title: "Needle invalid", path: "Invalid.md", stableID: "not-a-uuid"),
        ]
        let paths = ["Archive/自由/reference.md", "Exact.md", "Prefix.md", "Z-first.md", "A-second.md", "自由/Note-10.md"]
        let expected = paths.map(fixture.materialID) + fixture.actionIDs
        let candidates = AgentChatNoteCatalog(notes: notes).materialCandidates
        #expect(candidates.map(\.id) == expected)
        try fixture.expectActions(in: candidates)
        #expect(AgentChatComposerCatalog.matching(candidates, query: "  ").map(\.id) == expected)
        #expect(AgentChatComposerCatalog.matching(candidates, query: "material:").map(\.id) == expected)
        #expect(
            AgentChatComposerCatalog.matching(candidates, query: " NEEDLE ").map(\.id)
                == ["Exact.md", "Prefix.md", "Archive/自由/reference.md"].map(fixture.materialID))
        #expect(
            AgentChatComposerCatalog.matching(candidates, query: "自由").map(\.id)
                == ["自由/Note-10.md", "Archive/自由/reference.md"].map(fixture.materialID))
        #expect(
            AgentChatComposerCatalog.matching(candidates, query: "Archive/自由/reference.md").map(\.id)
                == [fixture.materialID("Archive/自由/reference.md")])
        #expect(AgentChatComposerCatalog.matching(candidates, query: "absentfixtureterm").isEmpty)
    }
}

/// Compute-bound helper diagnostics, separate from native completion latency.
@Suite(
    "Large Chat material catalog CPU diagnostics", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_CHAT_CATALOG"] == "1"))
@MainActor
struct AgentChatCatalogPerformanceTests {
    private enum Pipeline: String, CaseIterable {
        case rebuildAndMatch = "rebuild_and_match"
        case preparedMatch = "prepared_match"
    }

    @Test("Measure complete 2000 and 10000 Note material catalogs with independent ordered results")
    func largeCatalogs() throws {
        let fixture = ChatMaterialCatalogFixture.self
        var scenarios: [[String: Any]] = []
        for count in [2_000, 10_000] {
            let inputOrdinals = (0..<count).map { ($0 * 31) % count }
            let notes = inputOrdinals.map { ordinal in
                let title =
                    ordinal == 2 ? "Note 1" : "Note \(ordinal)" + ([41, 53].contains(ordinal) ? " 自由" : "")
                return fixture.note(
                    ordinal, title: title, path: fixture.path(ordinal),
                    stableID: ordinal == 7 ? nil : (ordinal == 37 ? "not-a-uuid" : fixture.stableID(ordinal)))
            }
            #expect(notes.count == count)
            // The numeric title order is declared by this fixture. The two
            // equal titles retain their known input order; no production sort
            // or matcher generates the oracle.
            let orderedOrdinals =
                [0] + inputOrdinals.filter { $0 == 1 || $0 == 2 }
                + (3..<count).filter { $0 != 7 && $0 != 37 }
            let allIDs = orderedOrdinals.map { fixture.materialID(fixture.path($0)) } + fixture.actionIDs
            let queries: [(name: String, text: String, expected: [String])] = [
                ("empty", "", allIDs),
                ("title", " note 123 ", ([123] + Array(1230..<1240)).map { fixture.materialID(fixture.path($0)) }),
                ("path", "bucket/target.md", [17, 21, 29].map { fixture.materialID(fixture.path($0)) }),
                ("cjk", "自由", [67, 41, 53, 83].map { fixture.materialID(fixture.path($0)) }),
            ]
            let cache = AgentChatNoteCatalogCache()
            let prepared = cache.catalog(notes: notes).materialCandidates
            try fixture.expectOrdered(prepared, IDs: allIDs)
            try fixture.expectActions(in: prepared)
            #expect(!prepared.contains { ["Corpus/Note-7.md", "Corpus/Note-37.md"].contains($0.detail) })
            try fixture.expectOrdered(AgentChatNoteCatalog(notes: notes).materialCandidates, IDs: allIDs)
            var coldMilliseconds: [Double] = []
            for _ in 0..<31 {
                let started = ContinuousClock.now
                let catalog = AgentChatNoteCatalog(notes: notes)
                let elapsed = started.duration(to: .now).components
                coldMilliseconds.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
                try fixture.expectOrdered(catalog.materialCandidates, IDs: allIDs)
            }
            let coldSorted = coldMilliseconds.sorted()
            scenarios.append([
                "notes": count, "valid_notes": count - 2, "query": "none",
                "pipeline": "cold_catalog", "warmups": 1, "samples": 31, "result_count": allIDs.count,
                "ordered_result_sha256": DocumentFingerprint(content: allIDs.joined(separator: "\n")).sha256,
                "median_ms": coldSorted[15], "p95_ms": coldSorted[29], "sample_ms": coldMilliseconds,
            ])
            print(
                "CHAT_CATALOG_DIAGNOSTIC notes=\(count) query=none pipeline=cold_catalog "
                    + "samples=31 median_ms=\(String(format: "%.3f", coldSorted[15])) p95_ms=\(String(format: "%.3f", coldSorted[29]))")
            for query in queries {
                for pipeline in Pipeline.allCases {
                    func evaluate() -> [AgentChatComposerCandidate] {
                        switch pipeline {
                        case .rebuildAndMatch:
                            return AgentChatComposerCatalog.matching(
                                AgentChatNoteCatalog(notes: notes).materialCandidates, query: query.text)
                        case .preparedMatch:
                            return AgentChatComposerCatalog.matching(cache.catalog(notes: notes).materialCandidates, query: query.text)
                        }
                    }
                    // One warmup and all result checks remain outside retained timings.
                    try fixture.expectOrdered(evaluate(), IDs: query.expected)
                    var milliseconds: [Double] = []
                    for _ in 0..<31 {
                        let started = ContinuousClock.now
                        let result = evaluate()
                        let elapsed = started.duration(to: .now).components
                        milliseconds.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
                        try fixture.expectOrdered(result, IDs: query.expected)
                    }
                    let sorted = milliseconds.sorted()
                    let median = sorted[15]
                    let p95 = sorted[29]  // Nearest rank ceil(0.95 * 31), using zero-based storage.
                    scenarios.append([
                        "notes": count, "valid_notes": count - 2, "query": query.name,
                        "pipeline": pipeline.rawValue, "warmups": 1, "samples": 31,
                        "result_count": query.expected.count,
                        "ordered_result_sha256": DocumentFingerprint(content: query.expected.joined(separator: "\n")).sha256,
                        "median_ms": median, "p95_ms": p95, "sample_ms": milliseconds,
                    ])
                    print(
                        "CHAT_CATALOG_DIAGNOSTIC notes=\(count) query=\(query.name) pipeline=\(pipeline.rawValue) "
                            + "samples=31 median_ms=\(String(format: "%.3f", median)) p95_ms=\(String(format: "%.3f", p95))")
                }
            }
            // A repaint resolves many App receipts against the same catalog.
            // Half deliberately hit its tail; the rest span the input order.
            let validNotes = notes.filter { !["Corpus/Note-7.md", "Corpus/Note-37.md"].contains($0.reference.relativePath) }
            let activityNotes =
                Array(validNotes.suffix(16))
                + (0..<16).map { validNotes[$0 * (validNotes.count - 1) / 15] }
            let expectedTargets = activityNotes.map { note in
                AgentChatActivityNoteTarget(
                    noteID: UUID(uuidString: note.reference.stableNoteID!)!,
                    vaultID: fixture.vaultID, title: note.title)
            }
            let activities = zip(activityNotes, expectedTargets).map { note, target in
                AgentChatActivity(
                    kind: .read, status: .completed, source: .scholium,
                    files: [.init(path: note.reference.relativePath, noteID: target.noteID, effect: .read)])
            }
            #expect(activities.count == 32)
            func activityTargets() -> [AgentChatActivityNoteTarget?] {
                activities.map { AgentChatActivityProjection.noteTarget($0, catalog: cache.catalog(notes: notes)) }
            }
            let expectedOptionalTargets = expectedTargets.map(Optional.some)
            try #require(activityTargets() == expectedOptionalTargets)
            var activityMilliseconds: [Double] = []
            for _ in 0..<31 {
                let started = ContinuousClock.now
                let targets = activityTargets()
                let elapsed = started.duration(to: .now).components
                activityMilliseconds.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
                try #require(targets == expectedOptionalTargets)
            }
            let sortedActivity = activityMilliseconds.sorted()
            let activityMedian = sortedActivity[15]
            let activityP95 = sortedActivity[29]
            let targetRecords = expectedTargets.map { "\($0.noteID.uuidString):\($0.vaultID.uuidString):\($0.title)" }
            scenarios.append([
                "notes": count, "valid_notes": count - 2, "query": "activity_batch",
                "pipeline": "activity_note_targets", "warmups": 1, "samples": 31,
                "activity_count": activities.count, "result_count": expectedTargets.count,
                "ordered_result_sha256": DocumentFingerprint(content: targetRecords.joined(separator: "\n")).sha256,
                "median_ms": activityMedian, "p95_ms": activityP95, "sample_ms": activityMilliseconds,
            ])
            print(
                "CHAT_CATALOG_DIAGNOSTIC notes=\(count) query=activity_batch pipeline=activity_note_targets "
                    + "activities=32 samples=31 median_ms=\(String(format: "%.3f", activityMedian)) "
                    + "p95_ms=\(String(format: "%.3f", activityP95))")
        }
        #if DEBUG
            let configuration = "debug"
        #else
            let configuration = "release"
        #endif
        let process = ProcessInfo.processInfo
        let report: [String: Any] = [
            "schema_version": 1, "fixture_version": 1, "build_configuration": configuration,
            "os_version": process.operatingSystemVersionString, "processor_count": process.processorCount,
            "measurement":
                "Compute-bound helper elapsed time only; excludes fixture creation, assertions, serialization and native completion presentation. One warmup and 31 retained samples per pipeline and query; no product gate.",
            "pipeline_semantics":
                "cold_catalog constructs the new complete Note catalog; rebuild_and_match includes a fresh catalog and matching; prepared_match includes warm cache validation for the same immutable input and matching; activity_note_targets resolves 32 App receipts through the same warm catalog cache. Baseline prepared_match used an already constructed candidate array and baseline activity_note_targets used 32 linear scans.",
            "oracle":
                "Complete ordered candidate IDs derive independently from declared fixture ordinals, equal-title input order and exact/prefix/substring tiers. Invalid portable IDs are absent and all three material routes remain in the unfiltered catalog. Activity batches preserve exact declared Note UUID, vault UUID and title.",
            "scenarios": scenarios,
        ]
        let label = process.environment["SCHOLIUM_CHAT_CATALOG_MEASUREMENT_LABEL"] ?? "diagnostic"
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        try #require(!label.isEmpty && label.allSatisfy { allowed.contains($0) })
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = repository.appendingPathComponent(".build/chat-catalog-performance", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("\(label).json"), options: .atomic)
    }
}

@MainActor
private enum ChatMaterialCatalogFixture {
    static let vaultID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let fingerprint = DocumentFingerprint(content: "Synthetic public fixture source")
    static let actionIDs = ["material:file", "material:note-picker", "material:selection"]

    static func stableID(_ ordinal: Int) -> String {
        "22222222-2222-2222-2222-" + String(format: "%012x", ordinal + 1)
    }

    static func materialID(_ path: String) -> String { "material:note:\(vaultID.uuidString):\(path)" }

    static func path(_ ordinal: Int) -> String {
        switch ordinal {
        case 17: "bucket/target.md"
        case 21: "bucket/target.md.extra.md"
        case 29: "archive/bucket/target.md"
        case 67: "自由/Note-67.md"
        case 83: "Archive/自由/Note-83.md"
        default: "Corpus/Note-\(ordinal).md"
        }
    }

    static func note(_ ordinal: Int, title: String, path: String, stableID: String? = "default") -> WorkspaceCatalogNote {
        .init(
            reference: .init(
                vaultID: vaultID, vaultName: "Topics", vaultRole: .topicKnowledge, relativePath: path,
                stableNoteID: stableID == "default" ? Self.stableID(ordinal) : stableID),
            title: title, fingerprint: fingerprint, validationWarnings: [])
    }

    static func expectOrdered(_ candidates: [AgentChatComposerCandidate], IDs: [String]) throws {
        // Bound a failed 10000-row assertion to its consequential boolean.
        let orderedIDsMatch = candidates.map(\.id) == IDs
        try #require(orderedIDsMatch)
    }

    static func expectActions(in candidates: [AgentChatComposerCandidate]) throws {
        try #require(candidates.count >= 3)
        let actions = Array(candidates.suffix(3))
        #expect(actions.map(\.id) == actionIDs)
        if case .file = actions[0].action {} else { Issue.record("The file route lost its action.") }
        if case .notePicker = actions[1].action {} else { Issue.record("The Note picker lost its action.") }
        if case .selection = actions[2].action {} else { Issue.record("The selection route lost its action.") }
    }
}
