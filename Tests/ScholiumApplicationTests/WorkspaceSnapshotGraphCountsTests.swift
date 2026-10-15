import Foundation
import Testing

@testable import ScholiumApplication
@testable import ScholiumContracts

@Suite("Workspace snapshot Graph summary counts")
struct WorkspaceSnapshotGraphCountsTests {
    @Test("All diagnostic categories, duplicate occurrences and vault-qualified sources retain complete counts")
    func diagnosticClassification() throws {
        let notes = noteIDs(count: 4)
        let unknown = VaultQualifiedNoteID(vaultID: notes[0].vaultID, relativePath: "Outside snapshot.md")
        let codes: [LinkGraphDiagnosticCode] = [.broken, .ambiguous, .missingHeading, .ambiguousHeading, .missingBlock, .ambiguousBlock]
        var diagnostics = codes.enumerated().map { diagnostic($0.element, source: notes[0], ordinal: $0.offset) }
        diagnostics += [diagnostics[0], diagnostics[1], diagnostic(.missingHeading, source: notes[1], ordinal: 8)]
        diagnostics += [diagnostic(.broken, source: notes[2], ordinal: 9), diagnostic(.ambiguousBlock, source: unknown, ordinal: 10)]
        let graph = graph(notes: notes, diagnostics: diagnostics)
        let actual = optimizedCounts(for: notes, graph: graph)
        try expectCompleteOutput(actual, linearCounts(for: notes, graph: graph))
        #expect(notes[0].relativePath == notes[2].relativePath)
        #expect(notes[0].vaultID != notes[2].vaultID)
        #expect(actual[0].broken == 2)
        #expect(actual[0].ambiguous == 4)
        #expect(actual[1].broken == 0 && actual[1].ambiguous == 0)
        #expect(actual[2].broken == 1 && actual[2].ambiguous == 0)
        #expect(actual[3].broken == 0 && actual[3].ambiguous == 0)
        try expectCompleteOutput(optimizedCounts(for: notes, graph: nil), linearCounts(for: notes, graph: nil))
        #expect(WorkspaceSnapshotBuilder.graphDiagnosticCountsBySource(in: nil).isEmpty)
        let emptyGraph = self.graph(notes: [], diagnostics: [])
        try expectCompleteOutput(optimizedCounts(for: notes, graph: emptyGraph), linearCounts(for: notes, graph: emptyGraph))
        try expectCompleteOutput(optimizedCounts(for: [], graph: graph), linearCounts(for: [], graph: graph))
        try expectCompleteOutput(
            optimizedCounts(for: notes, graph: self.graph(notes: notes, diagnostics: [])),
            linearCounts(for: notes, graph: self.graph(notes: notes, diagnostics: [])))
    }

    @Test("Deterministic complete outputs match the old per-Note linear scan")
    func randomizedLinearEquivalence() throws {
        var generator = Generator()
        let codes: [LinkGraphDiagnosticCode] = [.broken, .ambiguous, .missingHeading, .ambiguousHeading, .missingBlock, .ambiguousBlock]
        for _ in 0..<64 {
            let notes = noteIDs(count: 2 + generator.number(62))
            let unknown = VaultQualifiedNoteID(vaultID: notes[0].vaultID, relativePath: "Unlisted.md")
            var diagnostics: [LinkGraphDiagnostic] = []
            for ordinal in 0..<generator.number(256) {
                let source = generator.number(5) == 0 ? unknown : notes[generator.number(notes.count)]
                let value = diagnostic(codes[generator.number(codes.count)], source: source, ordinal: ordinal)
                diagnostics.append(value)
                if generator.number(5) == 0 { diagnostics.append(value) }
            }
            let graph = graph(notes: notes, diagnostics: diagnostics)
            try expectCompleteOutput(optimizedCounts(for: notes, graph: graph), linearCounts(for: notes, graph: graph))
        }
    }

    @Test(
        "Optional paired 5,000-Note summary-count component measurement",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_SNAPSHOT_COUNTS"] == "1"))
    func measureLargeComponent() throws {
        let notes = noteIDs(count: 5_000)
        var diagnostics: [LinkGraphDiagnostic] = []
        for (ordinal, note) in notes.enumerated() {
            for code in [LinkGraphDiagnosticCode.broken, .ambiguous, .missingHeading] {
                let value = diagnostic(code, source: note, ordinal: ordinal)
                diagnostics.append(value)
                if ordinal.isMultiple(of: 11) { diagnostics.append(value) }
            }
        }
        let graph = graph(notes: notes, diagnostics: diagnostics)
        let clock = ContinuousClock()
        let previousStart = clock.now
        let previous = linearCounts(for: notes, graph: graph)
        let previousDuration = previousStart.duration(to: clock.now)
        let optimizedStart = clock.now
        let optimized = optimizedCounts(for: notes, graph: graph)
        let optimizedDuration = optimizedStart.duration(to: clock.now)
        try expectCompleteOutput(optimized, previous)
        let report: [String: Any] = [
            "schema": "scholium-snapshot-summary-count-component-v1",
            "scope": "Single paired in-memory count projection; old algorithm first; excludes source loading, catalog, refresh and UI.",
            "note_count": notes.count,
            "diagnostic_count": diagnostics.count,
            "old_linear_ms": milliseconds(previousDuration),
            "aggregated_ms": milliseconds(optimizedDuration),
            "complete_count_outputs_equal": optimized == previous,
        ]
        let encoded = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        FileHandle.standardOutput.write(Data("SNAPSHOT_COUNTS_COMPONENT ".utf8) + encoded + Data("\n".utf8))
    }
}

private extension WorkspaceSnapshotGraphCountsTests {
    struct Generator {
        private var state: UInt64 = 0x84FA_025D_3B1E_96C7

        mutating func number(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 32) % UInt64(bound))
        }
    }

    func noteIDs(count: Int) -> [VaultQualifiedNoteID] {
        let vaults = [
            UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
            UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!,
        ]
        let half = (count + 1) / 2
        return (0..<count).map { index in
            VaultQualifiedNoteID(vaultID: vaults[index / half], relativePath: "Shared/e\u{301}😀 \(index % half).md")
        }
    }

    func diagnostic(_ code: LinkGraphDiagnosticCode, source: VaultQualifiedNoteID, ordinal: Int) -> LinkGraphDiagnostic {
        .init(code: code, source: source, target: "Target \(ordinal)", message: "Synthetic diagnostic", span: span(ordinal))
    }

    func span(_ lower: Int) -> SourceSpan {
        .init(
            utf8LowerBound: lower, utf8UpperBound: lower + 1,
            utf16LowerBound: lower, utf16UpperBound: lower + 1,
            start: .init(line: 1, utf8Column: lower + 1, utf16Column: lower + 1),
            end: .init(line: 1, utf8Column: lower + 2, utf16Column: lower + 2))
    }

    func graph(notes: [VaultQualifiedNoteID], diagnostics: [LinkGraphDiagnostic]) -> GraphSnapshot {
        var outgoing: [VaultQualifiedNoteID: [LinkGraphEdge]] = [:]
        var incoming: [VaultQualifiedNoteID: [LinkGraphEdge]] = [:]
        for (ordinal, source) in notes.enumerated() where !ordinal.isMultiple(of: 3) {
            let destination = notes[(ordinal + 1) % notes.count]
            let edge = LinkGraphEdge(
                source: source,
                occurrence: .init(syntax: .wikilink, target: destination.relativePath, alias: nil, fragment: nil, isExternal: false, span: span(ordinal)),
                destination: .init(note: destination, kind: .note, fragment: nil, span: nil))
            outgoing[source, default: []].append(edge)
            incoming[destination, default: []].append(edge)
            if ordinal.isMultiple(of: 11) {
                outgoing[source, default: []].append(edge)
                incoming[destination, default: []].append(edge)
            }
        }
        return GraphSnapshot(
            contractVersion: GraphSnapshot.currentContractVersion, generation: 1,
            sourceManifestHash: "synthetic-component-input", outgoing: outgoing, incoming: incoming, diagnostics: diagnostics)
    }

    func optimizedCounts(for notes: [VaultQualifiedNoteID], graph: GraphSnapshot?) -> [WorkspaceGraphCounts] {
        let counts = WorkspaceSnapshotBuilder.graphDiagnosticCountsBySource(in: graph)
        return notes.map { note in
            WorkspaceGraphCounts(
                incoming: graph?.incoming[note]?.count ?? 0,
                outgoing: graph?.outgoing[note]?.count ?? 0,
                broken: counts[note]?.broken ?? 0,
                ambiguous: counts[note]?.ambiguous ?? 0)
        }
    }

    /// Independent reference from the previous complete-snapshot assembly.
    /// Do not derive classification or grouping from the optimized helper.
    func linearCounts(for notes: [VaultQualifiedNoteID], graph: GraphSnapshot?) -> [WorkspaceGraphCounts] {
        notes.map { note in
            let diagnostics = (graph?.diagnostics ?? []).filter { $0.source == note }
            return WorkspaceGraphCounts(
                incoming: graph?.incoming[note]?.count ?? 0,
                outgoing: graph?.outgoing[note]?.count ?? 0,
                broken: diagnostics.count { $0.code == .broken },
                ambiguous: diagnostics.count { $0.code == .ambiguous || $0.code == .ambiguousHeading || $0.code == .ambiguousBlock })
        }
    }

    func expectCompleteOutput(_ actual: [WorkspaceGraphCounts], _ expected: [WorkspaceGraphCounts]) throws {
        #expect(actual == expected)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(actual) == encoder.encode(expected))
    }

    func milliseconds(_ duration: Duration) -> Double {
        let value = duration.components
        return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1e15
    }
}
