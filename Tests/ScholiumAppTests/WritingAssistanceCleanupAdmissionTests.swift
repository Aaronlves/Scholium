import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp
@testable import ScholiumApplication

@Suite("Writing assistance cleanup admission", .serialized)
@MainActor
struct WritingAssistanceCleanupAdmissionTests {
    @Test("Cancelled generation permits its replacement to wait for cleanup while active generation remains busy")
    func cancelledRequestAdmission() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/writing-cleanup-tests/\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "scholium-writing-cleanup-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = fixtureChatController(triptychID: UUID(), root: root, methodDefaults: defaults) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        #expect(await controller.waitUntilLoaded())
        #expect(!controller.isWritingAssistanceBusy)
        let turn = AsyncStream<Void>.makeStream()
        let unsubscribe = AsyncStream<Void>.makeStream()
        var heldCleanup: CheckedContinuation<Void, Never>?
        defer {
            heldCleanup?.resume()
            heldCleanup = nil
            turn.continuation.finish()
            unsubscribe.continuation.finish()
        }
        let execution = CodexWritingAssistance(
            request: { method, _ in
                switch method {
                case "config/read": return .object(["config": .object([:])])
                case "thread/start":
                    return .object([
                        "thread": .object(["id": .string("ephemeral"), "ephemeral": .bool(true)]),
                        "model": .string("inexpensive"), "approvalPolicy": .string("never"),
                        "sandbox": .object(["type": .string("readOnly")]),
                        "reasoningEffort": .string("low"), "instructionSources": .array([]),
                    ])
                case "mcpServerStatus/list": return .object(["data": .array([]), "nextCursor": .null])
                case "turn/start":
                    turn.continuation.yield()
                    return .object(["turn": .object(["id": .string("turn"), "status": .string("inProgress")])])
                case "turn/interrupt": return .object([:])
                case "thread/unsubscribe":
                    await withCheckedContinuation { continuation in
                        heldCleanup = continuation
                        unsubscribe.continuation.yield()
                    }
                    return .object([:])
                default: throw CodexConnectionError.invalidMessage
                }
            }, reject: { _ in }, finished: { controller.writingAssistanceExecution = nil })
        controller.writingAssistanceExecution = execution
        let request = CodexWritingAssistanceRequest(before: "A claim needs", after: "", background: [], model: "inexpensive")
        let model = AgentChatModel(
            id: "fixture", model: "inexpensive", name: "Fixture", efforts: ["low"],
            defaultEffort: "low", isDefault: false, inputModalities: ["text"])
        let generation = Task { try await execution.run(request, model: model, cwd: root) }
        defer { generation.cancel() }
        for await _ in turn.stream { break }
        #expect(controller.isWritingAssistanceBusy)
        await #expect(throws: CodexWritingAssistanceError.busy) { try await controller.writingAssistance(request) }
        generation.cancel()
        await #expect(throws: CancellationError.self) { try await generation.value }
        for await _ in unsubscribe.stream { break }
        #expect(execution.isFinishing)
        #expect(!controller.isWritingAssistanceBusy)
        var replacementFinished = false
        let replacement = Task {
            defer { replacementFinished = true }
            // This disconnected test must recheck connection only after cleanup.
            await #expect(throws: CodexWritingAssistanceError.unavailable) { try await controller.writingAssistance(request) }
        }
        await Task.yield()
        #expect(!replacementFinished)
        heldCleanup?.resume()
        heldCleanup = nil
        await replacement.value
        #expect(replacementFinished && !execution.isActive && !controller.isWritingAssistanceBusy)
        await controller.disconnect()
    }
}
