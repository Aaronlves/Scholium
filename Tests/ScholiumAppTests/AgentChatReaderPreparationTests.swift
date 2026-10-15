import Foundation
import Testing
@testable import ScholiumApp

@Suite("Chat cold reader admission")
@MainActor
struct AgentChatReaderPreparationTests {
    @MainActor final class Results {
        var values: [AgentChatReaderPreparation.Reader: Bool] = [:]
    }

    @Test("Measured completion releases bounded work and scrolling pauses pending startup")
    func scrollingAndCompletion() async throws {
        let queue = AgentChatReaderPreparation()
        let presentation = UUID()
        queue.begin(presentation)
        let readers = (0..<8).map { reader(presentation, "reply-\($0)") }
        let results = Results()
        let tasks = readers.map { key in Task { results.values[key] = await queue.acquire(key) != nil } }
        defer { queue.end(); tasks.forEach { $0.cancel() } }
        try await settle { results.values.count == 2 }
        #expect(results.values.values.allSatisfy { $0 })
        queue.setScrolling(true)
        readers.filter { results.values[$0] == true }.forEach(queue.complete)
        await nativeTurn()
        #expect(results.values.count == 2)
        queue.setScrolling(false)
        try await settle { results.values.count == 4 }
        // Completion is keyed by each granted reader, regardless of enqueue order.
        results.values.keys.forEach(queue.complete)
        try await settle { results.values.count == 6 }
        results.values.keys.forEach(queue.complete)
        try await settle { results.values.count == 8 }
        #expect(results.values.values.allSatisfy { $0 })
    }

    @Test("Cancellation and a departed presentation cannot consume or release a successor's slots")
    func cancellationAndRootReplacement() async throws {
        let queue = AgentChatReaderPreparation()
        let old = UUID()
        queue.begin(old)
        queue.setScrolling(true)
        let cancelled = Task { await queue.acquire(reader(old, "cancelled")) != nil }
        await nativeTurn()
        cancelled.cancel()
        #expect(await cancelled.value == false)
        let departed = Task { await queue.acquire(reader(old, "departed")) != nil }
        await nativeTurn()
        let current = UUID()
        queue.begin(current)
        #expect(await departed.value == false)
        let first = reader(current, "same-name")
        let second = reader(current, "other")
        let third = reader(current, "waiting")
        let results = Results()
        let tasks = [first, second, third].map { key in Task { results.values[key] = await queue.acquire(key) != nil } }
        defer { queue.end(); tasks.forEach { $0.cancel() } }
        try await settle { results.values.count == 2 }
        queue.complete(reader(old, "same-name"))
        await nativeTurn()
        #expect(results.values.count == 2)
        let granted = try #require(results.values.keys.first)
        queue.remove(granted)
        try await settle { results.values.count == 3 }
    }

    @Test("Replacing an admitted reader releases its old slot before a late unmount")
    func replacementDuringPreparation() async throws {
        let session = AgentChatReadingSession()
        let presentation = UUID()
        session.beginPresentation(presentation)
        let old = reader(presentation, "replaced")
        let other = reader(presentation, "other")
        session.mountReplyReader(old.id, presentationID: presentation, instance: old.instance, hydrated: false)
        session.mountReplyReader(other.id, presentationID: presentation, instance: other.instance, hydrated: false)
        let results = Results()
        let tasks = [old, other].map { key in Task { results.values[key] = await session.readerPreparation.acquire(key) != nil } }
        defer { session.endPresentation(presentation); tasks.forEach { $0.cancel() } }
        try await settle { results.values.count == 2 }
        let successor = reader(presentation, old.id)
        session.mountReplyReader(successor.id, presentationID: presentation, instance: successor.instance, hydrated: false)
        let successorTask = Task { await session.readerPreparation.acquire(successor) }
        #expect(await successorTask.value != nil)
        session.unmountReplyReader(old.id, presentationID: presentation, instance: old.instance)
        #expect(session.ownsReplyReader(successor.id, presentationID: presentation, instance: successor.instance))
        #expect(!session.areReadersHydrated([successor.id]))
        session.updateReplyHydration(old.id, presentationID: presentation, instance: old.instance, hydrated: true, layoutApplied: true)
        #expect(!session.areReadersHydrated([successor.id]))
        session.updateReplyHydration(successor.id, presentationID: presentation, instance: successor.instance, hydrated: true, layoutApplied: true)
        #expect(session.areReadersHydrated([successor.id]))
    }

    @Test("A cancelled unstarted acquisition cannot release its source successor")
    func inheritedAcquisition() async throws {
        let queue = AgentChatReaderPreparation()
        let presentation = UUID()
        queue.begin(presentation)
        defer { queue.end() }
        let key = reader(presentation, "same-native-reader")
        let old = try #require(await queue.acquire(key))
        let inherited = try #require(await queue.acquire(key))
        let other = try #require(await queue.acquire(reader(presentation, "other")))
        let results = Results()
        let waitingKey = reader(presentation, "waiting")
        let waiting = Task { results.values[waitingKey] = await queue.acquire(waitingKey) != nil }
        defer { waiting.cancel() }
        await nativeTurn()
        queue.releaseUnstarted(old)
        await nativeTurn()
        #expect(results.values.isEmpty)
        queue.releaseUnstarted(inherited)
        try await settle { results.values[waitingKey] == true }
        queue.releaseUnstarted(other)
    }

    @Test("Resetting a failed readiness receipt cannot release its newly acquired startup slot")
    func failedReceiptReset() async throws {
        let session = AgentChatReadingSession()
        let presentation = UUID()
        session.beginPresentation(presentation)
        let readiness = AgentChatReadReply.Readiness()
        readiness.mount(in: session, readerID: "failed-retry", presentationID: presentation)
        readiness.failure = "Disposable renderer failure"
        _ = try #require(await readiness.prepare())
        _ = try #require(await session.readerPreparation.acquire(reader(presentation, "other")))
        defer { readiness.unmount(); session.endPresentation(presentation) }
        readiness.reset()
        #expect(!session.areReadersHydrated(["failed-retry"]))
        let results = Results()
        let waitingKey = reader(presentation, "waiting")
        let waiting = Task { results.values[waitingKey] = await session.readerPreparation.acquire(waitingKey) != nil }
        defer { waiting.cancel() }
        for _ in 0..<10 { await nativeTurn() }
        #expect(results.values.isEmpty, "Intermediate reset fields cannot acknowledge the new page as failed or ready")
        readiness.ready = true
        readiness.hasMeasuredLayout = true
        try await settle { results.values[waitingKey] == true }
    }

    private func reader(_ presentation: UUID, _ id: String) -> AgentChatReaderPreparation.Reader {
        .init(presentationID: presentation, id: id, instance: UUID())
    }
    private func nativeTurn() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }
    private func settle(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate(), ContinuousClock.now < deadline { await nativeTurn() }
        try #require(predicate())
    }
}
