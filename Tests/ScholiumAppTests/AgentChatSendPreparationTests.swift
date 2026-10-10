import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Chat validated input preparation", .serialized)
@MainActor
struct AgentChatSendPreparationTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test("Validated durable input opens a fresh draft during both thread creation and resume", arguments: [false, true])
    func freshDraftDuringThreadPreparation(resumes: Bool) async throws {
        try await withFixture { controller, root in
            if resumes {
                controller.editDraft("Completed seed request")
                controller.send()
                try await wait { !controller.isBusy && controller.selected?.pendingMessageID == nil }
            }
            controller.editDraft("Request awaiting thread preparation")
            try Data().write(to: controller.runtimeHome.appendingPathComponent("hold-thread-preparation"))
            controller.send()
            try await wait { FileManager.default.fileExists(atPath: controller.runtimeHome.appendingPathComponent("pending-thread-preparation").path) }
            let message = try #require(controller.selected?.messages.last { $0.role == .user })
            #expect(controller.selected?.draft == "" && controller.selected?.pendingMessageID == message.id)
            #expect(
                AgentChatMessageDelivery.status(
                    for: message, pendingMessageID: controller.selected?.pendingMessageID,
                    sendingMessageID: controller.executions[controller.selectedID!]?.sendingMessageID) == .sending)
            #expect(
                try String(contentsOf: controller.runtimeHome.appendingPathComponent("pending-thread-preparation"), encoding: .utf8)
                    == (resumes ? "thread/resume" : "thread/start"))
            controller.editDraft("Next question while the submitted request is preparing")
            try Data("success".utf8).write(to: controller.runtimeHome.appendingPathComponent("release-thread-preparation"))
            controller.refreshQuota()
            try await wait { !controller.isBusy && controller.selected?.pendingMessageID == nil }
            #expect(controller.selected?.draft == "Next question while the submitted request is preparing")
            #expect(controller.selected?.messages.filter { $0.id == message.id }.count == 1)
            let requests = try JSONDecoder().decode(
                [MCPJSONValue].self,
                from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("turn-inputs.json")))
            #expect(requests.count == (resumes ? 2 : 1))
            try await controller.flushPersistence()
            let archive = try await AgentChatStorage(root: root.appendingPathComponent(controller.triptychID.uuidString)).load()
            #expect(archive.first { $0.id == controller.selectedID }?.draft == controller.selected?.draft)
        }
    }

    @Test("Known thread setup failure restores untouched input or queues it beside newer text and materials", arguments: [false, true])
    func threadPreparationFailure(edited: Bool) async throws {
        try await withFixture { controller, root in
            let owner = try #require(controller.selectedID)
            let method = try #require(controller.capabilities.methods.first).selection
            let attachment = AgentChatAttachment(
                noteID: UUID(), vaultID: UUID(), relativePath: "Original.md", text: "Original source",
                fingerprint: .init(content: "Original source"))
            let quote = AgentChatReplyQuote(conversationID: owner, messageID: "earlier-reply", text: "Original quotation")
            let file = root.appendingPathComponent("original.txt")
            try Data("Original retained file".utf8).write(to: file)
            let material = try await controller.materialStore.stage(file)
            controller.update {
                $0.draft = "Original request"
                $0.attachments = [attachment]
                $0.localMaterials = [material]
                $0.selectedMethods = [method]
                $0.draftReplyQuotes = [quote]
            }
            try Data().write(to: controller.runtimeHome.appendingPathComponent("hold-thread-preparation"))
            controller.send()
            try await wait { FileManager.default.fileExists(atPath: controller.runtimeHome.appendingPathComponent("pending-thread-preparation").path) }
            let prepared = try #require(controller.selected?.messages.first)
            #expect(
                controller.selected?.draft == "" && controller.selected?.attachments.isEmpty == true
                    && controller.selected?.localMaterials.isEmpty == true && controller.selected?.selectedMethods == nil
                    && controller.selected?.draftReplyQuotes == nil)
            var newerMaterial: AgentChatLocalMaterial?
            let newerAttachment = AgentChatAttachment(
                noteID: UUID(), vaultID: UUID(), relativePath: "Newer.md", text: "Newer source",
                fingerprint: .init(content: "Newer source"))
            let newerQuote = AgentChatReplyQuote(conversationID: owner, messageID: "other-reply", text: "Newer quotation")
            if edited {
                let newerFile = root.appendingPathComponent("newer.txt")
                try Data("Newer retained file".utf8).write(to: newerFile)
                newerMaterial = try await controller.materialStore.stage(newerFile)
                controller.update {
                    $0.draft = "Newer unsent request"
                    $0.attachments = [newerAttachment]
                    $0.localMaterials = [newerMaterial!]
                    $0.draftReplyQuotes = [newerQuote]
                }
            }
            try Data("failure".utf8).write(to: controller.runtimeHome.appendingPathComponent("release-thread-preparation"))
            controller.refreshQuota()
            try await wait { !controller.isBusy }
            #expect(controller.selected?.pendingMessageID == nil && controller.selected?.messages.isEmpty == true)
            #expect(controller.executions[owner]?.recovery == .messageNotSent)
            #expect(controller.selected?.draft == (edited ? "Newer unsent request" : "Original request"))
            #expect(controller.selected?.attachments == [edited ? newerAttachment : attachment])
            #expect(controller.selected?.localMaterials == [edited ? newerMaterial! : material])
            #expect(controller.selected?.draftReplyQuotes == [edited ? newerQuote : quote])
            #expect(controller.selected?.selectedMethods == (edited ? nil : [method]))
            #expect(controller.selected?.queuedMessages == (edited ? [prepared] : []))
            #expect(!FileManager.default.fileExists(atPath: controller.runtimeHome.appendingPathComponent("turn-inputs.json").path))
            try await controller.flushPersistence()
            let retained = try #require(try await AgentChatStorage(root: root.appendingPathComponent(controller.triptychID.uuidString)).load().first)
            #expect(retained.draft == controller.selected?.draft && retained.localMaterials == controller.selected?.localMaterials)
            #expect(retained.queuedMessages == controller.selected?.queuedMessages)
        }
    }

    private func withFixture(_ operation: (AgentChatController, URL) async throws -> Void) async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/send-preparation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        do {
            try #require(await controller.waitUntilLoaded())
            let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
            controller.connect(executable: fixture, home: controller.runtimeHome, helper: fixture)
            try await wait {
                controller.state == .ready && controller.account != nil && controller.capabilities.workspaceReady
                    && controller.capabilities.hasMethods && !controller.capabilities.isRefreshing
            }
            try await operation(controller, root)
            await controller.disconnect()
        } catch {
            await controller.disconnect()
            throw error
        }
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Thread preparation fixture did not reach its expected boundary")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
