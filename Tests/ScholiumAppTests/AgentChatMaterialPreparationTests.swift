import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Conversation-owned Chat material preparation", .serialized)
@MainActor
struct AgentChatMaterialPreparationTests {
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Material preparation fixture did not become ready")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Note preparation blocks its draft delivery, permits another conversation and preserves cancelled input")
    func preparationOwnership() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-evolution/material-preparation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await wait { controller.isLoaded }
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: fixture, home: controller.runtimeHome, helper: fixture)
        controller.editDraft("hold active material conversation")
        try await wait { controller.canSend }
        controller.send()
        try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let owner = try #require(controller.selectedID)
        controller.editDraft("Discuss the selected Note")
        #expect(controller.canSend && controller.canQueue)
        let material = AgentChatAttachment(
            noteID: UUID(), vaultID: UUID(), relativePath: "Selected.md", text: "Exact prepared Note text.",
            fingerprint: .init(content: "Exact prepared Note text."), extent: .wholeNote, source: .savedSource)
        var release: CheckedContinuation<Void, Never>?
        defer { release?.resume() }
        let preparing = Task {
            await controller.performMaterialPreparation(in: owner) {
                await withCheckedContinuation { release = $0 }
                try Task.checkCancellation()
                #expect(controller.attachContext([material], to: owner))
            }
        }
        try await wait { release != nil }
        #expect(controller.preparingMaterials == [owner])
        #expect(!controller.canSend && !controller.canQueue)
        let messageCount = controller.selected?.messages.count
        controller.send()
        #expect(!controller.queue() && controller.selected?.messages.count == messageCount)
        #expect(controller.selected?.draft == "Discuss the selected Note")
        controller.newConversation()
        let other = try #require(controller.selectedID)
        let file = root.appendingPathComponent("Other.txt")
        try Data("Other conversation material".utf8).write(to: file)
        await controller.addLocalFiles([file], to: other)
        #expect(controller.selected?.localMaterials.count == 1 && controller.selected?.attachments.isEmpty == true)
        #expect(controller.preparingMaterials == [owner])
        release?.resume()
        release = nil
        #expect(await preparing.value)
        #expect(controller.selectedID == other && controller.selected?.attachments.isEmpty == true)
        controller.select(owner)
        #expect(controller.canQueue && controller.queue())
        #expect(controller.queuedMessages.last?.attachments == [material])
        #expect(controller.queuedMessages.last?.text == "Discuss the selected Note")

        controller.editDraft("Keep this cancelled capture request")
        let cancelled = Task {
            await controller.performMaterialPreparation(in: owner) {
                await withCheckedContinuation { release = $0 }
                try Task.checkCancellation()
                #expect(controller.attachContext([material], to: owner))
            }
        }
        try await wait { release != nil }
        controller.cancelMaterialPreparation(in: owner)
        release?.resume()
        release = nil
        #expect(!(await cancelled.value))
        #expect(controller.preparingMaterials.isEmpty && controller.materialErrors[owner] == nil)
        #expect(controller.selected?.draft == "Keep this cancelled capture request" && controller.selected?.attachments.isEmpty == true)
        #expect(controller.queuedMessages.last?.attachments == [material])
        await controller.disconnect()
    }
}
