import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Research question interaction", .serialized) @MainActor
struct AgentChatQuestionTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !predicate() {
            try #require(ContinuousClock.now < deadline, "Question fixture did not reach the expected state")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private func controller(_ root: URL, text: String = "hold questions") async throws -> AgentChatController {
        let value = AgentChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await wait { value.isLoaded }
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        value.connect(executable: fixture, home: value.runtimeHome, cli: fixture)
        try await wait { value.account != nil && value.state == .ready }
        value.editDraft(text)
        value.send()
        try await wait { !value.approvals.isEmpty || value.error != nil }
        return value
    }

    @Test("Question replies retain their owner until exact acknowledgement and never archive secret answers")
    func replyConfirmation() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/questions-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try await controller(root)
        let owner = try #require(controller.selectedID)
        let request = try #require(controller.approvals.first)
        #expect(controller.questionCount(in: owner) == 1 && controller.approvalCount(in: owner) == 0)
        #expect(controller.questionAnswers(request.id).isEmpty && request.detail.isEmpty)
        controller.editDraft("Keep my ordinary draft")
        controller.editQuestionAnswers(request.id, values: ["approach": .option("Unlisted choice")])
        controller.answer(request.id, allow: true)
        #expect(controller.approvals.first?.submission == nil)
        let secret = "synthetic-secret-\(UUID())"
        let answers: [String: AgentChatQuestionAnswer] = [
            "approach": .text("Compare these two exact passages.\nKeep this wording."), "private": .text(secret),
        ]
        controller.editQuestionAnswers(request.id, values: answers)
        controller.newConversation()
        let other = try #require(controller.selectedID)
        #expect(controller.questionAnswers(request.id) == answers && controller.approvals.isEmpty)
        try Data().write(to: controller.runtimeHome.appendingPathComponent("hold-question-resolution"))
        controller.answer(request.id, allow: true)
        let responseFile = controller.runtimeHome.appendingPathComponent("question-response.json")
        try await wait { FileManager.default.fileExists(atPath: responseFile.path) }
        #expect(controller.selectedID == other && !controller.needsInput)
        let response = try JSONDecoder().decode(MCPJSONValue.self, from: Data(contentsOf: responseFile))
        #expect(response.objectValue?["result"]?.objectValue?["answers"]?.objectValue?["private"]?.objectValue?["answers"]?.arrayValue == [.string(secret)])
        controller.select(owner)
        #expect(controller.approvals.first?.submission == true && controller.questionAnswers(request.id) == answers)
        #expect(controller.selected?.draft == "Keep my ordinary draft")
        try await controller.flushPersistence()
        let archive = root.appendingPathComponent(controller.triptychID.uuidString).appendingPathComponent("conversations.json")
        let saved = try String(contentsOf: archive, encoding: .utf8)
        #expect(!saved.contains(secret) && saved.contains("Compare these two exact passages."))
        try Data().write(to: controller.runtimeHome.appendingPathComponent("resolve-questions"))
        controller.refreshQuota()
        try await wait { controller.approvals.isEmpty }
        #expect(controller.questionAnswers(request.id).isEmpty)
        #expect(controller.selected?.messages.first { $0.id == "question:\(request.id)" }?.activity?.status == .completed)
        controller.stop()
        try await wait { !controller.isBusy }
        await controller.disconnect()
    }

    @Test("Skip sends no answers; Stop preserves nonsecret drafts without replaying an answer")
    func skipAndStop() async throws {
        for skip in [true, false] {
            let root = repository.appendingPathComponent(".build/agent-chat-tests/question-stop-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let controller = try await controller(root)
            let request = try #require(controller.approvals.first)
            controller.editQuestionAnswers(request.id, values: ["approach": .text("Preserve this incomplete response")])
            if skip {
                controller.answer(request.id, allow: false)
                try await wait { controller.approvals.isEmpty }
                let response = try JSONDecoder().decode(
                    MCPJSONValue.self,
                    from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("question-response.json")))
                #expect(response.objectValue?["result"]?.objectValue?["answers"] == .object([:]))
            }
            controller.stop()
            try await wait { !controller.isBusy }
            let message = try #require(controller.selected?.messages.first { $0.id == "question:\(request.id)" })
            #expect(message.activity?.status == (skip ? .declined : .interrupted))
            #expect(message.activity?.detail.contains("Preserve this incomplete response") == true)
            if !skip { #expect(!FileManager.default.fileExists(atPath: controller.runtimeHome.appendingPathComponent("question-response.json").path)) }
            await controller.disconnect()
        }
    }

    @Test("Malformed question sets are rejected instead of exposing an allow-operation button")
    func malformed() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/question-invalid-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try await controller(root, text: "hold malformed-questions")
        #expect(controller.approvals.isEmpty && controller.error != nil)
        await controller.disconnect()
    }

    @Test("Tool-origin questions retain their identity; declining stops without an assumed default answer")
    func toolQuestions() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/tool-question-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try await controller(root, text: "hold tool-questions")
        let request = try #require(controller.approvals.first)
        #expect(request.toolQuestionContext == "fixture_library · choose_source")
        #expect(request.toolInputDetails?.contains("do-not-archive-this-argument") == true)
        controller.answer(request.id, allow: false)
        try await wait { !controller.isBusy }
        #expect(
            controller.approvals.isEmpty
                && !FileManager.default.fileExists(atPath: controller.runtimeHome.appendingPathComponent("question-response.json").path))
        let record = try #require(controller.selected?.messages.first { $0.id == "question:\(request.id)" })
        #expect(record.activity?.subject == ScholiumL10n.string("Tool Input Request"))
        #expect(record.activity?.detail.contains("fixture_library · choose_source") == true)
        try await controller.flushPersistence()
        let archive = root.appendingPathComponent(controller.triptychID.uuidString).appendingPathComponent("conversations.json")
        #expect(try !String(contentsOf: archive, encoding: .utf8).contains("do-not-archive-this-argument"))
        await controller.disconnect()
    }

    @Test("Secret choice values are omitted from public question history before and after selection")
    func secretChoices() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/secret-choice-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try await controller(root, text: "hold secret-choice-questions")
        let request = try #require(controller.approvals.first)
        controller.editQuestionAnswers(request.id, values: ["private": .option("synthetic-private-option")])
        try await controller.flushPersistence()
        let archive = root.appendingPathComponent(controller.triptychID.uuidString).appendingPathComponent("conversations.json")
        #expect(try !String(contentsOf: archive, encoding: .utf8).contains("synthetic-private-option"))
        await controller.disconnect()
    }
}
