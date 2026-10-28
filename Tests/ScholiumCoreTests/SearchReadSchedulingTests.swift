import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

#if DEBUG
    @Suite("Search pages yield with complete source-bound snapshots", .serialized)
    struct SearchReadSchedulingTests {
        @Test("A paused full page lets an exact query finish and then resumes unchanged", .timeLimit(.minutes(1)))
        func foregroundSearchDuringPage() async throws {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let index = try fixture.index()
            let gate = PageGate()
            var pending: Task<SearchResponse, Error>?
            do {
                let documents = fixture.documents
                let generation = try await index.synchronize(documents).generation
                let baseline = try await fixture.search(index)
                try fixture.expectPage(baseline, documents: documents, offset: 0)
                await index.setSearchReadBatchBarrierForTesting { await gate.holdOnce() }
                let task = Task { try await fixture.search(index) }
                pending = task
                try #require(await gate.waitUntilEntered())
                let exact = try await fixture.search(index, query: "uniqueneedle")
                #expect(exact.noteResults.map(\.relativePath) == ["Note000.md"])
                #expect(try await index.generation() == generation)
                await gate.release()
                let resumed = try await task.value
                #expect(resumed.noteResults == baseline.noteResults)
                #expect(resumed.totalResultCount == baseline.totalResultCount)
                #expect(resumed.hasMore == baseline.hasMore)
                await index.shutdown()
            } catch {
                await gate.release()
                pending?.cancel()
                _ = await pending?.result
                await index.shutdown()
                throw error
            }
        }

        @Test("A generation published while a page is paused rejects the obsolete result", .timeLimit(.minutes(1)))
        func publicationInvalidatesPage() async throws {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let index = try fixture.index()
            let gate = PageGate()
            var pending: Task<SearchResponse, Error>?
            do {
                var documents = fixture.documents
                let before = try await index.synchronize(documents).generation
                await index.setSearchReadBatchBarrierForTesting { await gate.holdOnce() }
                let task = Task { try await fixture.search(index) }
                pending = task
                try #require(await gate.waitUntilEntered())
                documents[0] = fixture.document(0, source: "# Note000\n\nChanged source without the previous term.")
                let after = try await index.synchronize(documents).generation
                #expect(after != before)
                await gate.release()
                await #expect(throws: CancellationError.self) { try await task.value }
                await index.setSearchReadBatchBarrierForTesting(nil)
                let current = try await fixture.search(index)
                #expect(current.availability == .current(after))
                #expect(current.totalResultCount == 159)
                #expect(!current.noteResults.contains { $0.relativePath == "Note000.md" })
                await index.shutdown()
            } catch {
                await gate.release()
                pending?.cancel()
                _ = await pending?.result
                await index.shutdown()
                throw error
            }
        }

        @Test("An uncommitted Clear rejects old pages before the committed generation changes", .timeLimit(.minutes(1)))
        func clearInvalidatesPage() async throws {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let index = try fixture.index()
            let gate = PageGate()
            let clearGate = PageGate()
            var pending: Task<SearchResponse, Error>?
            var clearing: Task<SearchIndexClearResult, Error>?
            do {
                let generation = try await index.synchronize(fixture.documents).generation
                await index.setSearchReadBatchBarrierForTesting { await gate.holdOnce() }
                let task = Task { try await fixture.search(index) }
                pending = task
                try #require(await gate.waitUntilEntered())
                await index.setClearObserverForTesting { phase in
                    if case .beforeCommit = phase { await clearGate.holdOnce() }
                }
                let clearTask = Task { try await index.clear() }
                clearing = clearTask
                try #require(await clearGate.waitUntilEntered())
                // A separate reader still sees the pre-Clear committed state.
                // Rejection must therefore check activeClear, not only a new generation.
                let committed = try SearchSQLiteDatabase(path: fixture.root.appendingPathComponent("search.sqlite").path, readOnly: true)
                defer { committed.close() }
                #expect(try committed.scalarText("SELECT sequence FROM search_index_state WHERE singleton = 1;") == String(generation.sequence))
                #expect(try committed.scalarText("SELECT count(*) FROM search_documents;") == "160")
                let duringClear = try await fixture.search(index)
                #expect(duringClear.noteResults.isEmpty && !duringClear.hasMore)
                #expect(duringClear.availability == .unavailable)
                await gate.release()
                await #expect(throws: CancellationError.self) { try await task.value }
                await clearGate.release()
                let cleared = try await clearTask.value
                #expect(cleared.removedDocuments == 160)
                await index.setClearObserverForTesting(nil)
                await index.setSearchReadBatchBarrierForTesting(nil)
                let empty = try await fixture.search(index)
                #expect(empty.noteResults.isEmpty && !empty.hasMore)
                #expect(empty.availability == .unavailable)
                #expect(try await index.generation() == nil)
                await index.shutdown()
            } catch {
                await gate.release()
                await clearGate.release()
                pending?.cancel()
                clearing?.cancel()
                _ = await pending?.result
                _ = await clearing?.result
                await index.shutdown()
                throw error
            }
        }

        @Test("Cancelling a borrowed page leaves its live index available to later queries", .timeLimit(.minutes(1)))
        func cancellationReleasesPage() async throws {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let index = try fixture.index()
            let gate = PageGate(holdsThroughCancellation: true)
            var pending: Task<SearchResponse, Error>?
            do {
                let generation = try await index.synchronize(fixture.documents).generation
                await index.setSearchReadBatchBarrierForTesting { await gate.holdOnce() }
                let task = Task { try await fixture.search(index) }
                pending = task
                try #require(await gate.waitUntilEntered())
                task.cancel()
                await gate.release()
                await #expect(throws: CancellationError.self) { try await task.value }
                await index.setSearchReadBatchBarrierForTesting(nil)
                let exact = try await fixture.search(index, query: "uniqueneedle")
                #expect(exact.noteResults.map(\.relativePath) == ["Note000.md"])
                #expect(exact.availability == .current(generation))
                #expect(try await index.generation() == generation)
                await index.shutdown()
            } catch {
                await gate.release()
                pending?.cancel()
                _ = await pending?.result
                await index.shutdown()
                throw error
            }
        }

        @Test("Cancellation and shutdown wait for the borrowed page before reopening", .timeLimit(.minutes(1)))
        func shutdownDrainsPage() async throws {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let index = try fixture.index()
            let gate = PageGate(holdsThroughCancellation: true)
            let completion = PageCompletion()
            let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            var pending: Task<SearchResponse, Error>?
            var closing: Task<Void, Never>?
            do {
                let documents = fixture.documents
                let generation = try await index.synchronize(documents).generation
                await index.setSearchReadBatchBarrierForTesting { await gate.holdOnce() }
                await index.setRelatedShutdownObserverForTesting { started.continuation.yield(()) }
                let task = Task { try await fixture.search(index) }
                pending = task
                try #require(await gate.waitUntilEntered())
                task.cancel()
                let shutdown = Task {
                    await index.shutdown()
                    await completion.finish()
                }
                closing = shutdown
                var iterator = started.stream.makeAsyncIterator()
                try #require(await iterator.next() != nil)
                #expect(await completion.finished == false)
                await gate.release()
                await #expect { try await task.value } throws: { error in
                    if error is CancellationError { return true }
                    guard let error = error as? SearchIndexError, case .sqlite(let message) = error else { return false }
                    return message == "The Search index is closed."
                }
                await shutdown.value
                #expect(await completion.finished)
                let reopened = try fixture.index()
                do {
                    #expect(try await reopened.generation() == generation)
                    try fixture.expectPage(try await fixture.search(reopened), documents: documents, offset: 0)
                    try fixture.expectPage(try await fixture.search(reopened, offset: 100), documents: documents, offset: 100)
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

        private struct Fixture: Sendable {
            let root: URL
            let triptych = UUID()
            let vault = RegisteredVault(name: "Disposable", role: .topicKnowledge, canonicalPath: "/fixtures/search-read-scheduling")
            init() throws {
                root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(".build/search-read-scheduling/\(UUID())")
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            }
            func document(_ number: Int, source: String? = nil) -> SearchIndexDocument {
                let name = String(format: "Note%03d", number)
                return .init(
                    vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                    document: .init(
                        relativePath: name + ".md",
                        rawContent: source ?? "# \(name)\n\nOrchard geology records \(number == 0 ? "uniqueneedle" : "ordinaryword").\n"))
            }
            var documents: [SearchIndexDocument] { (0..<160).map { document($0) } }
            func search(_ index: TriptychSearchIndex, query: String = "orchard", offset: Int = 0) async throws -> SearchResponse {
                let request = SearchRequest(query: query, presentationScope: .triptych, executionScope: .triptych, limit: 100, offset: offset)
                let ast = try #require(SearchQueryParser.parse(query).ast)
                return try await index.search(request, ast: ast)
            }
            func expectPage(_ response: SearchResponse, documents: [SearchIndexDocument], offset: Int) throws {
                let expected = Array(documents.dropFirst(offset).prefix(100))
                #expect(response.noteResults.map(\.relativePath) == expected.map(\.relativePath))
                #expect(response.totalResultCount == documents.count)
                #expect(response.hasMore == (offset + expected.count < documents.count))
                for (hit, document) in zip(response.noteResults, expected) {
                    #expect(hit.fingerprint == document.document.fingerprint)
                    let range = try #require(hit.sourceRange)
                    let source = document.document.rawContent as NSString
                    try #require(range.utf16LowerBound >= 0 && range.utf16UpperBound >= range.utf16LowerBound && range.utf16UpperBound <= source.length)
                    #expect(source.substring(with: NSRange(location: range.utf16LowerBound, length: range.utf16UpperBound - range.utf16LowerBound)) == "Orchard")
                    try #require(!hit.highlights.isEmpty)
                    let snippet = hit.snippet as NSString
                    for highlight in hit.highlights {
                        try #require(highlight.utf16LowerBound >= 0 && highlight.utf16UpperBound >= highlight.utf16LowerBound
                            && highlight.utf16UpperBound <= snippet.length)
                        #expect(snippet.substring(with: NSRange(
                            location: highlight.utf16LowerBound,
                            length: highlight.utf16UpperBound - highlight.utf16LowerBound)) == "Orchard")
                    }
                }
            }
            func index() throws -> TriptychSearchIndex {
                try .init(isolatedDatabaseURL: root.appendingPathComponent("search.sqlite"), triptychID: triptych, vaults: [vault])
            }
            func remove() { try? FileManager.default.removeItem(at: root) }
        }
    }

    private actor PageCompletion {
        private(set) var finished = false
        func finish() { finished = true }
    }

    private actor PageGate {
        private let entered = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        private let resumed = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        private let holdsThroughCancellation: Bool
        private var first = true
        private var held: CheckedContinuation<Void, Never>?
        private var released = false
        init(holdsThroughCancellation: Bool = false) { self.holdsThroughCancellation = holdsThroughCancellation }
        func holdOnce() async {
            guard first else { return }
            first = false
            entered.continuation.yield(())
            if holdsThroughCancellation {
                await withCheckedContinuation { continuation in
                    if released { continuation.resume() } else { held = continuation }
                }
            } else if !released {
                var iterator = resumed.stream.makeAsyncIterator()
                _ = await iterator.next()
            }
        }
        func waitUntilEntered() async -> Bool {
            var iterator = entered.stream.makeAsyncIterator()
            return await iterator.next() != nil
        }
        func release() {
            released = true
            held?.resume()
            held = nil
            resumed.continuation.yield(())
        }
    }
#endif
