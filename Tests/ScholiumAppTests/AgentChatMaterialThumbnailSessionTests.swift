import AppKit
import Foundation
import Testing

@testable import ScholiumApp

@Suite("Chat material thumbnail lifetime", .serialized)
@MainActor
struct AgentChatMaterialThumbnailSessionTests {
    @Test("Closing during file preparation prevents a native thumbnail request and permits retry")
    func cancelBeforeRequest() async throws {
        var preparedURL: CheckedContinuation<URL, Never>?
        var generated = 0
        let image = NSImage(size: NSSize(width: 1, height: 1))
        let session = AgentChatMaterialThumbnailSession(
            generate: { _ in
                generated += 1
                return image
            }, cancel: { _ in Issue.record("No native request was created") })
        let first = Task {
            try await session.load {
                await withCheckedContinuation { preparedURL = $0 }
            }
        }
        defer { preparedURL?.resume(returning: URL(fileURLWithPath: "/synthetic/image.png")) }
        try await wait { preparedURL != nil }
        session.cancel()
        preparedURL?.resume(returning: URL(fileURLWithPath: "/synthetic/image.png"))
        preparedURL = nil
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(generated == 0)
        let retried = try await session.load { URL(fileURLWithPath: "/synthetic/retry.png") }
        #expect(retried === image)
        #expect(generated == 1)
    }

    @Test("Native cancellation revokes late results without cancelling or clearing the replacement request")
    func cancelAndReplaceRequest() async throws {
        let gate = ThumbnailGate()
        let session = AgentChatMaterialThumbnailSession(generate: gate.generate, cancel: gate.cancel)
        defer {
            session.cancel()
            gate.finishAll()
        }
        let first = Task { try await session.load { URL(fileURLWithPath: "/synthetic/first.png") } }
        try await wait { gate.requests.count == 1 }
        session.cancel()
        #expect(gate.cancelled == [ObjectIdentifier(gate.requests[0])])

        let second = Task { try await session.load { URL(fileURLWithPath: "/synthetic/second.png") } }
        try await wait { gate.requests.count == 2 }
        let cancelledEntry = Task { try await session.load { URL(fileURLWithPath: "/synthetic/cancelled.png") } }
        cancelledEntry.cancel()
        await #expect(throws: CancellationError.self) { try await cancelledEntry.value }
        #expect(gate.requests.count == 2)
        #expect(gate.cancelled.count == 1, "An already cancelled entry cannot revoke the replacement request")
        gate.finish(0)
        await #expect(throws: CancellationError.self) { try await first.value }
        session.cancel()
        #expect(gate.cancelled == gate.requests.map(ObjectIdentifier.init))
        gate.finish(1)
        await #expect(throws: CancellationError.self) { try await second.value }

        let third = Task { try await session.load { URL(fileURLWithPath: "/synthetic/third.png") } }
        try await wait { gate.requests.count == 3 }
        gate.finish(2)
        #expect(try await third.value === gate.image)
        session.cancel()
        #expect(gate.cancelled.count == 2)
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate() {
            try #require(ContinuousClock.now < deadline, "The controlled thumbnail operation did not reach its barrier")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @MainActor
    private final class ThumbnailGate {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        var requests: [AgentChatMaterialThumbnailSession.Request] = []
        var cancelled: [ObjectIdentifier] = []
        private var pending: [Int: CheckedContinuation<NSImage, Never>] = [:]

        func generate(_ request: AgentChatMaterialThumbnailSession.Request) async -> NSImage {
            let index = requests.count
            requests.append(request)
            return await withCheckedContinuation { pending[index] = $0 }
        }

        func cancel(_ request: AgentChatMaterialThumbnailSession.Request) {
            cancelled.append(ObjectIdentifier(request))
        }

        func finish(_ index: Int) { pending.removeValue(forKey: index)?.resume(returning: image) }
        func finishAll() {
            for index in Array(pending.keys) { finish(index) }
        }
    }
}
