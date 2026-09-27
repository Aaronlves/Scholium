import Darwin
import Dispatch
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

#if DEBUG
    /// Opt-in live allocator sampling inside the exact short-seed background FTS
    /// loop. Counts and allocation sizes only; the fixture source is never logged.
    @Suite(
        "Related lexical pool peak", .serialized,
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_RELATED_LEXICAL_PEAK"] == "1"))
    struct RelatedContentLexicalPoolPeakMeasurementTests {
        private struct RoleFixture {
            let folder: String
            let vault: RegisteredVault
        }

        private let longSuffix = "\n\n" + (0..<512).map { "conceptualword_\($0)" }.joined(separator: " ") + "\n"

        @Test(
            "Sample live allocator across all 499 background lexical candidates",
            .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_RELATED_LEXICAL_PEAK"] == "1"))
        func actualBackgroundPool() async throws {
            let repository = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let fixture = repository.appendingPathComponent("TestVaults", isDirectory: true)
            for isLong in [false, true] {
                let label = isLong ? "long" : "standard"
                let storage = repository.appendingPathComponent(
                    ".build/memory-stability/lexical-peak/\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: storage) }
                let roles = roles(fixture: fixture)
                let index = try TriptychSearchIndex(
                    databaseURL: storage.appendingPathComponent("search.sqlite"), triptychID: UUID(),
                    vaults: roles.map(\.vault))
                let sourceBytes = try await populate(index: index, roles: roles, fixture: fixture, isLong: isLong)
                #expect(sourceBytes == (isLong ? 4_975_480 : 175_100))
                let seedPath = "QA Autosave A.md"
                let seed = try source(role: roles[0], path: seedPath, fixture: fixture, isLong: isLong)
                let request = RelatedContentRequest(
                    seed: .init(noteID: .init(vaultID: roles[0].vault.id, relativePath: seedPath), source: seed.rawContent))

                let sampler = PoolPeakSampler()
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "scholium.related.lexical.peak"))
                timer.schedule(deadline: .now(), repeating: .milliseconds(1), leeway: .microseconds(100))
                timer.setEventHandler { sampler.sample() }
                timer.resume()
                defer { timer.cancel() }
                await index.setRelatedLexicalPoolObserverForTesting { sampler.observe($0) }
                let beforeRequest = allocatedBytes()
                let response = try await index.relatedMaterialSourceCandidates(request)
                let afterResponse = allocatedBytes()
                await index.setRelatedLexicalPoolObserverForTesting(nil)
                let peak = sampler.snapshot()
                let retention = await index.relatedBackgroundPreparationRetention
                let candidates = response.identityCandidates + response.lexicalCandidates
                #expect(candidates.count == 499)
                #expect(Set(candidates.map(\.note)).count == 499)
                #expect(peak.lastCandidateCount == 499)
                #expect(peak.lastRetainedCount == (isLong ? 0 : 499))
                #expect(
                    isLong
                        ? peak.completePoolEstimatedBytes > RelatedContentBackgroundPreparation.defaultMaximumByteCount
                        : peak.completePoolEstimatedBytes < RelatedContentBackgroundPreparation.defaultMaximumByteCount)
                #expect(peak.sampleCount >= 499)
                #expect(retention.entries == (isLong ? 0 : 1))
                print(
                    "Related lexical peak \(label): sourceNotes=500 sourceBytes=\(sourceBytes) "
                        + "candidateRows=\(candidates.count) beforeRequest=\(beforeRequest) "
                        + "beforeLoop=\(peak.beforeLoopBytes) liveLoopPeak=\(peak.peakBytes) "
                        + "peakCompletedRows=\(peak.peakCandidateCount) peakRetained=\(peak.peakRetainedCount) "
                        + "attemptedEstimateAtPeak=\(peak.peakCompletePoolEstimatedBytes) "
                        + "afterLoop=\(peak.afterLoopBytes) afterResponse=\(afterResponse) "
                        + "completePoolEstimate=\(peak.completePoolEstimatedBytes) "
                        + "storedEntries=\(retention.entries) storedEstimate=\(retention.estimatedBytes) "
                        + "liveSamples=\(peak.sampleCount) rowBoundaryPeak=\(peak.rowBoundaryPeakBytes)")
            }
        }

        private func roles(fixture: URL) -> [RoleFixture] {
            [
                RoleFixture(
                    folder: "01-analyses",
                    vault: .init(
                        name: "Analyses", role: .sourceCorpus,
                        canonicalPath: fixture.appendingPathComponent("01-analyses").path)),
                RoleFixture(
                    folder: "02-topics",
                    vault: .init(
                        name: "Topics", role: .topicKnowledge,
                        canonicalPath: fixture.appendingPathComponent("02-topics").path)),
                RoleFixture(
                    folder: "03-works",
                    vault: .init(
                        name: "Works", role: .draftProject,
                        canonicalPath: fixture.appendingPathComponent("03-works").path)),
            ]
        }

        private func populate(
            index: TriptychSearchIndex, roles: [RoleFixture], fixture: URL, isLong: Bool
        ) async throws -> Int {
            var documents: [SearchIndexDocument] = []
            var sourceBytes = 0
            for role in roles {
                let root = fixture.appendingPathComponent(role.folder, isDirectory: true)
                let enumerator = try #require(
                    FileManager.default.enumerator(
                        at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]))
                let urls = enumerator.compactMap { $0 as? URL }
                    .filter { $0.pathExtension.lowercased() == "md" }.sorted { $0.path < $1.path }
                for url in urls {
                    let path = String(url.path.dropFirst(root.path.count + 1))
                    let note = try source(role: role, path: path, fixture: fixture, isLong: isLong)
                    sourceBytes += note.sourceBytes.count
                    documents.append(
                        .init(
                            vaultID: role.vault.id, vaultName: role.vault.name,
                            vaultRole: role.vault.role, document: note))
                }
            }
            #expect(documents.count == 500)
            _ = try await index.synchronize(documents)
            return sourceBytes
        }

        private func source(
            role: RoleFixture, path: String, fixture: URL, isLong: Bool
        ) throws -> NoteDocument {
            let url = fixture.appendingPathComponent(role.folder, isDirectory: true).appendingPathComponent(path)
            let decoded = try #require(NoteDocument.decodeUTF8PreservingBOM(Data(contentsOf: url)))
            let content =
                isLong && !(role.folder == "01-analyses" && path == "QA Autosave A.md")
                ? decoded + longSuffix : decoded
            return NoteDocument(relativePath: path, rawContent: content)
        }
    }

    private final class PoolPeakSampler: @unchecked Sendable {
        struct Snapshot {
            let beforeLoopBytes: Int
            let afterLoopBytes: Int
            let peakBytes: Int
            let peakCandidateCount: Int
            let peakRetainedCount: Int
            let peakCompletePoolEstimatedBytes: Int
            let lastCandidateCount: Int
            let lastRetainedCount: Int
            let completePoolEstimatedBytes: Int
            let rowBoundaryPeakBytes: Int
            let sampleCount: Int
        }

        private let lock = NSLock()
        private var active = false
        private var currentCandidates = 0
        private var currentRetained = 0
        private var currentCompleteEstimate = 0
        private var beforeLoop = 0
        private var afterLoop = 0
        private var peak = 0
        private var peakCandidates = 0
        private var peakRetained = 0
        private var peakCompleteEstimate = 0
        private var rowBoundaryPeak = 0
        private var endCompleteEstimate = 0
        private var samples = 0

        func observe(_ observation: TriptychSearchIndex.RelatedLexicalPoolObservation) {
            let bytes = allocatedBytes()
            lock.lock()
            defer { lock.unlock() }
            switch observation.phase {
            case .begin:
                beforeLoop = bytes
                currentCompleteEstimate = observation.completePoolEstimatedBytes
                active = true
            case .row:
                currentCandidates = observation.candidateCount
                currentRetained = observation.retainedProjectionCount
                currentCompleteEstimate = observation.completePoolEstimatedBytes
                rowBoundaryPeak = max(rowBoundaryPeak, bytes)
            case .end:
                currentCandidates = observation.candidateCount
                currentRetained = observation.retainedProjectionCount
                currentCompleteEstimate = observation.completePoolEstimatedBytes
                endCompleteEstimate = observation.completePoolEstimatedBytes
                afterLoop = bytes
            }
            if active { record(bytes) }
            if observation.phase == .end { active = false }
        }

        func sample() {
            let bytes = allocatedBytes()
            lock.lock()
            defer { lock.unlock() }
            if active { record(bytes) }
        }

        func snapshot() -> Snapshot {
            lock.lock()
            defer { lock.unlock() }
            return .init(
                beforeLoopBytes: beforeLoop, afterLoopBytes: afterLoop,
                peakBytes: peak, peakCandidateCount: peakCandidates,
                peakRetainedCount: peakRetained, peakCompletePoolEstimatedBytes: peakCompleteEstimate,
                lastCandidateCount: currentCandidates, lastRetainedCount: currentRetained,
                completePoolEstimatedBytes: endCompleteEstimate,
                rowBoundaryPeakBytes: rowBoundaryPeak, sampleCount: samples)
        }

        private func record(_ bytes: Int) {
            samples += 1
            if bytes > peak {
                peak = bytes
                peakCandidates = currentCandidates
                peakRetained = currentRetained
                peakCompleteEstimate = currentCompleteEstimate
            }
        }
    }

    private func allocatedBytes() -> Int {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return Int(statistics.size_in_use)
    }
#endif
