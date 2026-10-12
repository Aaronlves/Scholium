import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Writing completion index freshness")
struct WritingCompletionFreshnessTests {
    @Test("No matches are confirmed only by a current index, including recovery of the same last-good generation")
    func noMatchRequiresCurrentIndex() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/writing-completion-freshness-tests/\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let analyses = root.appendingPathComponent("analyses")
        let topics = root.appendingPathComponent("topics")
        let works = root.appendingPathComponent("works")
        for directory in [analyses, topics, works] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let source = "# Freshness\n\nA local writing claim.\n"
        let revisedSource = "# Freshness\n\nA revised local writing claim.\n"
        let noteURL = topics.appendingPathComponent("Freshness.md")
        try Data(source.utf8).write(to: noteURL)
        let support = root.appendingPathComponent("state")
        let zotero = ZoteroOperations(requestLoader: { _ in throw WritingFreshnessFixtureFailure.unexpectedZoteroRequest })
        let registrationRuntime = WorkspaceRuntime(
            configuration: .live(.init(applicationSupportURL: support, workspaceRegistryStorageURL: root.appendingPathComponent("registry"))),
            zotero: zotero)
        let assignment: TriptychAssignment
        do {
            let configured = try await registrationRuntime.configureTriptych(
                paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                portableContainerURL: root, triptychName: "Writing freshness fixture")
            assignment = configured.assignment
        } catch {
            await registrationRuntime.shutdown()
            throw error
        }
        await registrationRuntime.shutdown()
        let runtime = WorkspaceRuntime(
            configuration: .snapshot(.init(applicationSupportURL: support, assignments: [assignment])), zotero: zotero)
        do {
            let handle = try await runtime.openWorkspace(id: assignment.id)
            let snapshot = try await handle.snapshot()
            let generation = try #require(snapshot.discovery.searchGeneration)
            let vault = try #require(assignment.vault(for: .topicKnowledge))
            let index = await handle.services.searchIndex
            let workspaceGeneration = try await index.workspaceGeneration()
            let noMatchQuery = "UnmatchedSyntheticCompletion"
            #expect(await index.availability() == .current(generation))
            #expect(try await index.writingCompletionSources(matching: noMatchQuery).isEmpty)
            #expect(try await handle.discovery.writingCompletions(matching: noMatchQuery).isEmpty)

            let note = try #require(snapshot.document(id: .init(vaultID: vault.id, relativePath: "Freshness.md")))
            #expect(snapshot.discovery.catalog.notes.count == 1)
            #expect(note.fingerprint == DocumentFingerprint(content: source))
            // Search compares portable identity and graph metadata as well as
            // exact bytes. Preserve the real opening manifest for recovery.
            let stableNoteID = note.stableIdentity.resolvedID?.uuidString.lowercased()
            let hasBrokenLink = note.graphCounts.broken > 0
            let original = SearchIndexDocument(
                vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                document: NoteDocument(relativePath: "Freshness.md", rawContent: source),
                stableNoteID: stableNoteID, hasBrokenLink: hasBrokenLink)
            let revised = SearchIndexDocument(
                vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                document: NoteDocument(relativePath: "Freshness.md", rawContent: revisedSource),
                stableNoteID: stableNoteID, hasBrokenLink: hasBrokenLink)
            let gate = WritingFreshnessLoadGate()
            // Exercise the real Search writer while the Application still has
            // the identical last-good generation, including a zero-row lookup.
            let pending = Task {
                do {
                    let result = try await index.synchronizeManifest(
                        [.init(document: revised)], workspaceGeneration: workspaceGeneration + 1,
                        loadChanged: { _ in
                            await gate.hold()
                            return revised
                        }, validateManifest: { throw WritingFreshnessFixtureFailure.validationRejected })
                    await gate.writerFinished()
                    return result
                } catch {
                    await gate.writerFinished()
                    throw error
                }
            }
            do {
                try await gate.waitUntilEntered()
                #expect(await index.availability() == .refreshing(lastGood: generation))
                #expect(try await index.generation() == generation)
                #expect(try await index.writingCompletionSources(matching: noMatchQuery).isEmpty)
                await #expect(throws: (any Error).self) {
                    try await handle.discovery.writingCompletions(matching: noMatchQuery)
                }
                await gate.release()
                await #expect(throws: WritingFreshnessFixtureFailure.self) { try await pending.value }
                guard case .stale(let lastGood, _) = await index.availability() else {
                    throw WritingFreshnessFixtureFailure.expectedStaleIndex
                }
                #expect(lastGood == generation)
                #expect(try await index.generation() == generation)
                #expect(try await index.writingCompletionSources(matching: noMatchQuery).isEmpty)
                await #expect(throws: (any Error).self) {
                    try await handle.discovery.writingCompletions(matching: noMatchQuery)
                }
            } catch {
                // A thrown assertion or pre-load writer failure must not leave
                // the fixture writer waiting when its runtime is shut down.
                await gate.release()
                _ = try? await pending.value
                throw error
            }

            // The failed writer rolled back: validating the original manifest
            // restores current availability without replacing Search identity.
            let recovered = try await index.synchronizeManifest(
                [.init(document: original)], workspaceGeneration: workspaceGeneration + 2,
                loadChanged: { _ in original }, validateManifest: {})
            #expect(recovered.disposition == .unchanged)
            #expect(recovered.generation == generation)
            #expect(await index.availability() == .current(generation))
            #expect(try await handle.discovery.writingCompletions(matching: noMatchQuery).isEmpty)
            #expect(try await handle.snapshot().discovery.searchGeneration == generation)
            #expect(try Data(contentsOf: noteURL) == Data(source.utf8))
        } catch {
            await runtime.shutdown()
            throw error
        }
        await runtime.shutdown()
    }
}

private enum WritingFreshnessFixtureFailure: Error {
    case validationRejected, writerFinishedBeforeLoad, expectedStaleIndex, unexpectedZoteroRequest
}

private actor WritingFreshnessLoadGate {
    private var entered = false
    private var released = false
    private var finished = false
    private var arrival: CheckedContinuation<Void, Error>?
    private var held: CheckedContinuation<Void, Never>?

    func hold() async {
        entered = true
        arrival?.resume()
        arrival = nil
        guard !released else { return }
        await withCheckedContinuation { held = $0 }
    }

    func waitUntilEntered() async throws {
        if entered { return }
        guard !finished else { throw WritingFreshnessFixtureFailure.writerFinishedBeforeLoad }
        try await withCheckedThrowingContinuation { arrival = $0 }
    }

    func release() {
        released = true
        held?.resume()
        held = nil
    }

    func writerFinished() {
        finished = true
        if !entered {
            arrival?.resume(throwing: WritingFreshnessFixtureFailure.writerFinishedBeforeLoad)
            arrival = nil
        }
    }
}
