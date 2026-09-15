import Combine
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Child Agent metadata inspection") @MainActor
struct AgentChatChildMetadataTests {
    @Test("A verified name requires only metadata and does not enable execution controls")
    func nameWithoutHistory() async throws {
        let fixture = RequestFixture()
        let child = controller(fixture)
        defer { child.cancel() }
        let metadata = try await child.readMetadata()
        #expect(metadata.name == "Research reviewer")
        #expect(metadata.id == "child" && metadata.parentID == "parent")
        #expect(fixture.calls.count == 1)
        #expect(fixture.calls.first?.method == "thread/read")
        #expect(fixture.calls.first?.params == ["threadId": .string("child")])
        #expect(child.snapshot == nil && child.observedAt == nil && child.work == nil)
        #expect(!child.canStop && child.error == nil)
    }

    @Test("Closed inspections reject metadata before making a request")
    func closedBeforeRead() async {
        let fixture = RequestFixture()
        let child = controller(fixture)
        child.cancel()
        await #expect(throws: CancellationError.self) { try await child.readMetadata() }
        #expect(fixture.calls.isEmpty)
    }

    @Test("Closing during metadata verification rejects the returned observation")
    func closedDuringRead() async {
        let fixture = RequestFixture()
        let child = controller(fixture)
        fixture.beforeReply = { child.cancel() }
        await #expect(throws: CancellationError.self) { try await child.readMetadata() }
        #expect(fixture.calls.count == 1)
        #expect(child.snapshot == nil && child.observedAt == nil && !child.canStop)
    }

    @Test("Disconnected inspections reject metadata before or after a request", arguments: [true, false])
    func disconnected(_ beforeRead: Bool) async {
        let fixture = RequestFixture()
        let connection = PassthroughSubject<Bool, Never>()
        let child = controller(fixture, connection: connection.eraseToAnyPublisher())
        defer { child.cancel() }
        if beforeRead { connection.send(false) } else { fixture.beforeReply = { connection.send(false) } }
        do {
            _ = try await child.readMetadata()
            Issue.record("A disconnected inspection returned metadata")
        } catch CodexConnectionError.disconnected {
        } catch {
            Issue.record("Unexpected metadata error: \(error)")
        }
        #expect(fixture.calls.count == (beforeRead ? 0 : 1))
        #expect(child.isDisconnected && child.snapshot == nil && child.observedAt == nil && !child.canStop)
    }

    @Test("A cancelled caller cannot receive a late metadata response")
    func cancelledDuringRead() async {
        let fixture = RequestFixture()
        let child = controller(fixture)
        defer { child.cancel() }
        let task = Task { try await child.readMetadata() }
        fixture.beforeReply = { task.cancel() }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.calls.count == 1)
        #expect(child.snapshot == nil && child.observedAt == nil && !child.canStop)
    }

    private func controller(
        _ fixture: RequestFixture, connection: AnyPublisher<Bool, Never> = Just(true).eraseToAnyPublisher()
    ) -> AgentChatChildController {
        AgentChatChildController(
            childID: "child", parentID: "parent", parentTitle: "Parent", connection: connection
        ) { method, params in
            await fixture.read(method, params: params)
        }
    }

    @MainActor private final class RequestFixture {
        struct Call {
            let method: String
            let params: [String: MCPJSONValue]
        }
        var calls: [Call] = []
        var beforeReply: (() -> Void)?

        func read(_ method: String, params: [String: MCPJSONValue]) -> MCPJSONValue {
            calls.append(.init(method: method, params: params))
            beforeReply?()
            return .object([
                "thread": .object([
                    "id": .string("child"), "parentThreadId": .string("parent"),
                    "agentNickname": .string("Research reviewer"),
                    "status": .object(["type": .string("active"), "activeFlags": .array([])]),
                    "historyMode": .string("paginated"),
                ])
            ])
        }
    }
}
