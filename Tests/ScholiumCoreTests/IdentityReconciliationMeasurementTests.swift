import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

/// Synthetic portable records only. Setup, state restoration and correctness
/// checks are excluded from each timed reconciliation; no source files or
/// repositories, watchers, application runtime or native windows are created.
@Suite(
    "Identity reconciliation measurement", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_IDENTITY_RECONCILIATION"] == "1"))
struct IdentityReconciliationMeasurementTests {
    private let warmups = 3
    private let samples = 20

    @Test("Measure unchanged and single-edit inventories with recovery controls", arguments: [2_000, 10_000])
    func reconciliation(noteCount: Int) async throws {
        let fixture = try Fixture(noteCount: noteCount)
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        _ = try await store.bootstrap(vaultIDs: [
            .paperAnalysis: fixture.peerVaultIDs[0],
            .topicKnowledge: fixture.peerVaultIDs[1],
            .output: fixture.vaultID,
        ])

        for scenario in [Scenario.unchanged, .edited] {
            let documents = fixture.documents(for: scenario)
            var milliseconds: [Double] = []
            for iteration in 0..<(warmups + samples) {
                try fixture.reset()
                let start = ContinuousClock.now
                let result = try await store.reconcileIdentityInventory(vaultID: fixture.vaultID, documents: documents)
                let elapsed = start.duration(to: .now)
                if iteration >= warmups {
                    milliseconds.append(
                        Double(elapsed.components.seconds) * 1_000
                            + Double(elapsed.components.attoseconds) / 1e15)
                }
                try fixture.check(result, scenario: scenario)
            }
            let sorted = milliseconds.sorted()
            let report: [String: Any] = [
                "schema": "scholium-identity-reconciliation-measurement-v1",
                "scenario": scenario.rawValue,
                "target_note_count": noteCount,
                "portable_record_count": fixture.records.count,
                "fixture_sha256": DocumentFingerprint(data: fixture.seed).sha256,
                "warmups": warmups,
                "samples": samples,
                "durations_ms": milliseconds,
                "median_ms": (sorted[samples / 2 - 1] + sorted[samples / 2]) / 2,
                "p95_ms": sorted[Int(ceil(Double(samples) * 0.95)) - 1],
                "minimum_ms": sorted.first ?? 0,
                "maximum_ms": sorted.last ?? 0,
                "boundary": "store reconcile including decode, validation and any exact commit/readback",
                "correctness": "identity, fingerprint, portable readback and cross-vault preservation checked per sample",
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            print("IDENTITY_RECONCILIATION_MEASURE " + String(decoding: data, as: UTF8.self))
        }

        // These controls establish meaning rather than latency. Reset each
        // scenario, then repeat it to check durable identity and recovery state.
        for scenario in [Scenario.renamed, .copied, .ambiguous] {
            try fixture.reset()
            let documents = fixture.documents(for: scenario)
            let first = try await store.reconcileIdentityInventory(vaultID: fixture.vaultID, documents: documents)
            try fixture.check(first, scenario: scenario)
            let committed = try Data(contentsOf: fixture.identityURL)
            let repeated = try await store.reconcileIdentityInventory(vaultID: fixture.vaultID, documents: documents)
            #expect(repeated.identities == first.identities)
            #expect(repeated.ambiguities == first.ambiguities)
            #expect(repeated.pendingRebindings == first.pendingRebindings)
            #expect(repeated.rebound.isEmpty)
            #expect(try Data(contentsOf: fixture.identityURL) == committed)
        }
        print("IDENTITY_RECONCILIATION_CONTROLS target_notes=\(noteCount) rename=checked copy=checked ambiguity=checked")
    }

    private enum Scenario: String {
        case unchanged = "exact-unchanged"
        case edited = "one-fingerprint-edit"
        case renamed, copied, ambiguous
    }

    // This fixture envelope seeds the existing private portable-file shape;
    // only the production store interprets or changes it during measurement.
    private struct Payload: Codable {
        var records: [NoteIdentityRecord]
        var pendingRebindings: [NoteIdentityPendingRebinding]
        var unresolvedAmbiguities: [StoredAmbiguity]
    }

    private struct StoredAmbiguity: Codable {
        let vaultID: UUID
        let relativePath: String
        let fingerprint: DocumentFingerprint
        let candidateIDs: [UUID]
        let detectedAt: Date
    }

    private struct Fixture {
        let root: URL
        let works: URL
        let identityURL: URL
        let vaultID: UUID
        let peerVaultIDs: [UUID]
        let records: [NoteIdentityRecord]
        let targets: [NoteIdentityRecord]
        let seed: Data
        let selected: NoteIdentityRecord
        let editedFingerprint = DocumentFingerprint(content: "Synthetic edited revision\n")
        let destination = "000 Destination.md"

        init(noteCount: Int) throws {
            let repository = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            root = repository.appendingPathComponent(".build/identity-reconciliation-measurement/\(UUID().uuidString)")
            works = root.appendingPathComponent("Works")
            identityURL = root.appendingPathComponent(".scholium/identities.json")
            let targetVaultID = try Self.id(1)
            vaultID = targetVaultID
            let peers = try [Self.id(2), Self.id(3)]
            peerVaultIDs = peers
            let date = Date(timeIntervalSince1970: 10)
            let sharedFingerprint = DocumentFingerprint(content: "Synthetic ambiguous revision\n")
            let targetRecords = try (0..<noteCount).map { index in
                NoteIdentityRecord(
                    id: try Self.id(index + 100), vaultID: targetVaultID,
                    relativePath: String(format: "Folder/Note-%05d.md", index),
                    fingerprint: index >= noteCount - 2 ? sharedFingerprint : DocumentFingerprint(content: "Synthetic revision \(index)\n"),
                    createdAt: date, updatedAt: date,
                    citationCompanionRequired: index == 0 ? true : nil)
            }
            targets = targetRecords
            let selectedRecord = targetRecords[noteCount / 2]
            selected = selectedRecord
            // Opposite record and document orders exercise the complete lookup
            // distribution without relying on randomized fixture admission.
            var all = Array(targetRecords.reversed())
            for (index, peer) in peers.enumerated() {
                all.insert(
                    NoteIdentityRecord(
                        id: try Self.id(index + 20), vaultID: peer,
                        relativePath: selectedRecord.relativePath, fingerprint: selectedRecord.fingerprint,
                        createdAt: date, updatedAt: date),
                    at: 0)
            }
            records = all
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            seed = try encoder.encode(Payload(records: all, pendingRebindings: [], unresolvedAmbiguities: []))
            do {
                try FileManager.default.createDirectory(at: works, withIntermediateDirectories: true)
            } catch {
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }

        func documents(for scenario: Scenario) -> [(relativePath: String, fingerprint: DocumentFingerprint)] {
            var documents = targets.map { (relativePath: $0.relativePath, fingerprint: $0.fingerprint) }
            switch scenario {
            case .unchanged: break
            case .edited:
                documents[targets.count / 2].fingerprint = editedFingerprint
            case .renamed:
                documents[targets.count / 2].relativePath = destination
            case .copied:
                documents.append((destination, selected.fingerprint))
            case .ambiguous:
                documents.removeLast(2)
                documents.append((destination, targets[targets.count - 1].fingerprint))
            }
            return documents
        }

        func reset() throws {
            try seed.write(to: identityURL, options: .atomic)
        }

        func check(_ result: NoteIdentityReconciliation, scenario: Scenario) throws {
            let data = try Data(contentsOf: identityURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let persisted = try decoder.decode(Payload.self, from: data)
            let byID = Dictionary(uniqueKeysWithValues: persisted.records.map { ($0.id, $0) })
            #expect(persisted.records.count == records.count + (scenario == .copied ? 1 : 0))
            for original in records {
                var expected = original
                if original.id == selected.id {
                    if scenario == .edited { expected.fingerprint = editedFingerprint }
                    if scenario == .renamed { expected.relativePath = destination }
                }
                var actual = try #require(byID[original.id])
                if original.id == selected.id, scenario == .edited || scenario == .renamed {
                    #expect(actual.updatedAt >= original.updatedAt)
                    actual.updatedAt = original.updatedAt
                }
                #expect(actual == expected)
            }
            let documents = documents(for: scenario)
            let resolvedPaths = Set(documents.map(\.relativePath)).subtracting(scenario == .ambiguous ? [destination] : [])
            #expect(Set(result.identities.keys) == resolvedPaths)
            for document in documents where resolvedPaths.contains(document.relativePath) {
                let record = try #require(result.identities[document.relativePath])
                #expect(record == byID[record.id])
                #expect(record.vaultID == vaultID)
                #expect(record.relativePath.utf8.elementsEqual(document.relativePath.utf8))
                #expect(record.fingerprint == document.fingerprint)
            }
            #expect(persisted.pendingRebindings == result.pendingRebindings)
            if scenario == .renamed {
                #expect(result.rebound == [.init(id: selected.id, previousRelativePath: selected.relativePath, relativePath: destination)])
                let pending = try #require(result.pendingRebindings.first)
                #expect(result.pendingRebindings.count == 1)
                #expect(pending.noteID == selected.id && pending.vaultID == vaultID)
                #expect(pending.previousRelativePath == selected.relativePath && pending.relativePath == destination)
                #expect(pending.fingerprint == selected.fingerprint)
            } else {
                #expect(result.rebound.isEmpty)
                #expect(result.pendingRebindings.isEmpty)
            }
            if scenario == .ambiguous {
                let ambiguity = try #require(result.ambiguities.first)
                #expect(result.ambiguities.count == 1)
                #expect(ambiguity.vaultID == vaultID && ambiguity.relativePath == destination)
                #expect(ambiguity.fingerprint == targets[targets.count - 1].fingerprint)
                let candidateIDs = Set(targets.suffix(2).map(\.id))
                #expect(Set(ambiguity.candidates.map(\.id)) == candidateIDs)
                let stored = try #require(persisted.unresolvedAmbiguities.first)
                #expect(persisted.unresolvedAmbiguities.count == 1)
                #expect(stored.vaultID == vaultID && stored.relativePath == destination)
                #expect(stored.fingerprint == ambiguity.fingerprint)
                #expect(Set(stored.candidateIDs) == candidateIDs)
            } else {
                #expect(result.ambiguities.isEmpty)
                #expect(persisted.unresolvedAmbiguities.isEmpty)
            }
            if scenario == .copied {
                let copied = try #require(result.identities[destination])
                #expect(!Set(records.map(\.id)).contains(copied.id))
                #expect(result.identities[selected.relativePath]?.id == selected.id)
            }
            if scenario == .unchanged { #expect(data == seed) }
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }

        private static func id(_ value: Int) throws -> UUID {
            try #require(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", UInt64(value))))
        }
    }
}
