import Testing

@testable import ScholiumApplication

@Suite("Codex transport bounded buffers")
struct CodexTransportBufferTests {
    @Test("Independent byte and count budgets preserve FIFO and release capacity on consumption")
    func boundedConsumption() async throws {
        let queue = CodexTransportBuffer<Int>(maximumCount: 2, maximumBytes: 7)
        #expect(queue.offer(1, bytes: 4))
        #expect(!queue.offer(2, bytes: 4))
        #expect(queue.offer(2, bytes: 3))
        #expect(!queue.offer(3, bytes: 0))
        #expect(queue.usage.count == 2)
        #expect(queue.usage.bytes == 7)
        #expect(await queue.next() == 1)
        #expect(queue.offer(3, bytes: 4))
        #expect(queue.usage.count == 2)
        #expect(queue.usage.bytes == 7)
        #expect(await queue.next() == 2)
        #expect(await queue.next() == 3)
        #expect(queue.usage.count == 0)
        #expect(queue.usage.bytes == 0)
        queue.finish()
        #expect(await queue.next() == nil)
    }

    @Test("A full FIFO reserves terminal delivery without replacing accepted events")
    func reservedTerminal() async {
        let queue = CodexTransportBuffer<Int>(maximumCount: 1, maximumBytes: 1)
        #expect(queue.offer(1, bytes: 1))
        queue.offerTerminal(2)
        queue.offerTerminal(99)
        #expect(!queue.offer(3, bytes: 1))
        #expect(await queue.next() == 1)
        #expect(await queue.next() == 2)
        #expect(queue.offer(3, bytes: 1))
        queue.offerTerminal(4)
        queue.finish()
        queue.finish()
        #expect(await queue.next() == 3)
        #expect(await queue.next() == 4)
        #expect(await queue.next() == nil)
        #expect(!queue.offer(5, bytes: 0))
    }

    @Test("Cancellation and finish release an idle consumer", arguments: [false, true])
    func idleConsumerEnds(cancel: Bool) async {
        let queue = CodexTransportBuffer<Int>(maximumCount: 1, maximumBytes: 1)
        let consumer = Task { await queue.next() }
        if cancel { consumer.cancel() } else { queue.finish() }
        #expect(await consumer.value == nil)
        queue.finish()
        #expect(!queue.offer(1, bytes: 1))
    }
}
