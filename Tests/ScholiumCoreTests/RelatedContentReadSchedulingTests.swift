import Foundation
import ScholiumContracts
import Synchronization
import Testing

@testable import ScholiumCore

#if DEBUG
    @Suite("Related reads yield without sharing Search transactions", .serialized)
    struct RelatedContentReadSchedulingTests {
        @Test("A paused WAL cursor lets exact Search complete on its independent reader")
        func foregroundSearchDuringRead() async throws {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let index = try fixture.index()
            let gate = ReadGate()
            var pending: Task<RelatedContentResponse, Error>?
            do {
                let generation = try await index.synchronize(fixture.documents).generation
                await index.setRelatedReadBatchBarrierForTesting { await gate.holdOnce() }
                let task = Task { try await index.relatedMaterialSourceCandidates(fixture.request) }
                pending = task
                await gate.waitUntilEntered()
                let request = SearchRequest(query: "uniqueneedle", presentationScope: .triptych, executionScope: .triptych, limit: 100)
                let ast = try #require(SearchQueryParser.parse(request.query).ast)
                let response = try await index.search(request, ast: ast)
                #expect(response.noteResults.map(\.relativePath) == ["Note0.md"])
                #expect(try await index.generation() == generation)
                await gate.release()
                #expect(try await task.value.lexicalCandidates.count == 160)
                await index.shutdown()
            } catch {
                await gate.release()
                pending?.cancel()
                _ = await pending?.result
                await index.shutdown()
                throw error
            }
        }

        @Test("A generation published during a paused read rejects that obsolete snapshot")
        func publicationInvalidatesRead() async throws {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let index = try fixture.index()
            let gate = ReadGate()
            var pending: Task<RelatedContentResponse, Error>?
            do {
                let before = try await index.synchronize(fixture.documents).generation
                await index.setRelatedReadBatchBarrierForTesting { await gate.holdOnce() }
                let task = Task { try await index.relatedMaterialSourceCandidates(fixture.request) }
                pending = task
                await gate.waitUntilEntered()
                var changed = fixture.documents
                changed[0] = fixture.document("Note0.md", "Changed exact source without the old term.")
                let after = try await index.synchronize(changed).generation
                #expect(after != before)
                await gate.release()
                await #expect(throws: CancellationError.self) { try await task.value }
                await index.setRelatedReadBatchBarrierForTesting(nil)
                let current = try await index.relatedMaterialSourceCandidates(fixture.request)
                #expect(!current.lexicalCandidates.contains { $0.note.relativePath == "Note0.md" })
                #expect(current.availability == .current(after))
                await index.shutdown()
            } catch {
                await gate.release()
                pending?.cancel()
                _ = await pending?.result
                await index.shutdown()
                throw error
            }
        }

        @Test("Shutdown drains every borrowed cursor before releasing the index storage")
        func shutdownDrainsRead() async throws {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let index = try fixture.index()
            let gate = ReadGate()
            let closed = ReadCompletion()
            let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            var pending: Task<RelatedContentResponse, Error>?
            do {
                _ = try await index.synchronize(fixture.documents)
                await index.setRelatedReadBatchBarrierForTesting { await gate.holdOnce() }
                await index.setRelatedShutdownObserverForTesting { started.continuation.yield(()) }
                let task = Task { try await index.relatedMaterialSourceCandidates(fixture.request) }
                pending = task
                await gate.waitUntilEntered()
                let shutdown = Task {
                    await index.shutdown()
                    await closed.finish()
                }
                var iterator = started.stream.makeAsyncIterator()
                _ = await iterator.next()
                #expect(await closed.finished == false)
                await gate.release()
                _ = await task.result
                await shutdown.value
                #expect(await closed.finished)
                // A new owner can validate/open this store after all old statements closed.
                let reopened = try fixture.index()
                #expect(try await reopened.generation()?.sequence ?? 0 > 0)
                await reopened.shutdown()
            } catch {
                await gate.release()
                pending?.cancel()
                _ = await pending?.result
                await index.shutdown()
                throw error
            }
        }

        @Test("Cancellation and shutdown drain an opened lexical cursor and its reused payload statement", .timeLimit(.minutes(1)))
        func shutdownDrainsLexicalPayloadRead() async throws {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let index = try fixture.index()
            let request = fixture.request
            let payloadRows = LexicalPayloadReadProgress()
            let gate = ReadGate(holdsThroughCancellation: true)
            let closed = ReadCompletion()
            let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            var pending: Task<RelatedContentResponse, Error>?
            var closing: Task<Void, Never>?
            do {
                let documents = fixture.documents
                // Byte-preservation sentinels for the in-memory loader's exact inputs.
                let sources = documents.map { document in
                    (url: fixture.root.appendingPathComponent(document.relativePath), bytes: document.document.sourceBytes)
                }
                for source in sources { try source.bytes.write(to: source.url) }
                let generation = try await index.synchronize(documents).generation
                await index.setRelatedLexicalPoolObserverForTesting { observation in
                    guard observation.requestID == request.id, case .row = observation.phase else { return }
                    payloadRows.record(observation.candidateCount)
                }
                await index.setRelatedReadBatchBarrierForTesting {
                    // Earlier row-ID checkpoints have no lexical row observations.
                    // Each observed row has already fetched and validated its payload;
                    // the same inner statement has been reset/reused before this pause.
                    if payloadRows.count >= 64 { await gate.holdOnce() }
                }
                await index.setRelatedShutdownObserverForTesting { started.continuation.yield(()) }
                let task = Task { try await index.relatedMaterialSourceCandidates(request) }
                pending = task
                await gate.waitUntilEntered()
                try #require(payloadRows.count == 64)
                task.cancel()
                let shutdown = Task {
                    await index.shutdown()
                    await closed.finish()
                }
                closing = shutdown
                var iterator = started.stream.makeAsyncIterator()
                try #require(await iterator.next() != nil)
                #expect(await closed.finished == false)
                #expect(payloadRows.count == 64)
                // This gate deliberately ignores cancellation so the live outer
                // cursor cannot leave its transaction before the explicit release.
                await gate.release()
                await #expect { try await task.value } throws: { error in
                    if error is CancellationError { return true }
                    guard let error = error as? SearchIndexError, case .sqlite(let message) = error else { return false }
                    return message == "The Search index is closed."
                }
                await shutdown.value
                #expect(await closed.finished)
                for source in sources { try #require(try Data(contentsOf: source.url) == source.bytes) }
                let reopened = try fixture.index()
                do {
                    #expect(try await reopened.generation() == generation)
                    let response = try await reopened.relatedMaterialSourceCandidates(request)
                    #expect(response.requestID == request.id && response.availability == .current(generation))
                    #expect(response.lexicalCandidates.count == 160)
                    await reopened.shutdown()
                } catch {
                    await reopened.shutdown()
                    throw error
                }
            } catch {
                await gate.release()
                pending?.cancel()
                _ = await pending?.result
                await closing?.value
                await index.shutdown()
                throw error
            }
        }

        private struct Fixture {
            let root: URL
            let triptych = UUID()
            let vault = RegisteredVault(name: "Disposable", role: .topicKnowledge, canonicalPath: "/fixtures/related-read-scheduling")
            init() throws {
                root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(".build/related-read-scheduling/\(UUID())")
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            }
            func document(_ path: String, _ source: String) -> SearchIndexDocument {
                .init(
                    vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                    document: .init(relativePath: path, rawContent: source))
            }
            var documents: [SearchIndexDocument] {
                (0..<160).map { document("Note\($0).md", "Orchard geology. \($0 == 0 ? "uniqueneedle" : "ordinary")") }
                    + [document("Seed.md", "Orchard context.")]
            }
            var request: RelatedContentRequest {
                .init(seed: .init(noteID: .init(vaultID: vault.id, relativePath: "Seed.md"), source: "Orchard"), identityLimit: 0, lexicalLimit: 2)
            }
            func index() throws -> TriptychSearchIndex {
                try .init(isolatedDatabaseURL: root.appendingPathComponent("search.sqlite"), triptychID: triptych, vaults: [vault])
            }
            func remove() { try? FileManager.default.removeItem(at: root) }
        }
    }

    private actor ReadCompletion {
        private(set) var finished = false
        func finish() { finished = true }
    }
    private final class LexicalPayloadReadProgress: Sendable {
        private let rows = Mutex(0)
        var count: Int { rows.withLock { $0 } }
        func record(_ count: Int) { rows.withLock { $0 = count } }
    }
    private actor ReadGate {
        let entered = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let resumed = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        var first = true
        private let holdsThroughCancellation: Bool
        private var held: CheckedContinuation<Void, Never>?
        private var released = false
        init(holdsThroughCancellation: Bool = false) {
            self.holdsThroughCancellation = holdsThroughCancellation
        }
        func holdOnce() async {
            guard first else { return }
            first = false
            entered.continuation.yield(())
            if holdsThroughCancellation {
                await withCheckedContinuation { continuation in
                    if released { continuation.resume() } else { held = continuation }
                }
            } else {
                var iterator = resumed.stream.makeAsyncIterator()
                _ = await iterator.next()
            }
        }
        func waitUntilEntered() async {
            var iterator = entered.stream.makeAsyncIterator()
            _ = await iterator.next()
        }
        func release() {
            released = true
            held?.resume()
            held = nil
            resumed.continuation.yield(())
        }
    }
#endif
