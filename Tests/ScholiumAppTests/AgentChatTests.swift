import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("In-app Agent collaboration", .serialized)
@MainActor
struct AgentChatTests {
    @Test("Organization persists; only archived idle conversations can be permanently deleted")
    func organizationLifecycle() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let triptych = UUID()
        let controller = AgentChatController(triptychID: triptych, root: root, toolHandler: success)
        try await connect(controller)
        controller.editDraft("phased activity")
        controller.send()
        let id = try #require(controller.selectedID)
        controller.setArchived(id, archived: true)
        controller.deleteConversation(id)
        #expect(controller.selected?.isAvailable == true)
        try await eventually { !controller.isBusy && controller.selected?.lastRunStatus == .completed }
        #expect(controller.selected?.unreadAt != nil)
        controller.setUnread(id, unread: false)
        #expect(controller.selected?.unreadAt == nil)
        controller.editDraft("Retain this draft")
        let messages = controller.selected?.messages
        let order = controller.selected?.updatedAt
        controller.setUnread(id, unread: true)
        controller.setImportant(id, important: true)
        controller.deleteConversation(id)
        #expect(controller.selected?.id == id)
        controller.setArchived(id, archived: true)
        #expect(!controller.canSend && !controller.canCompact)
        #expect(controller.selected?.updatedAt == order)
        await controller.disconnect()
        let restored = AgentChatController(triptychID: triptych, root: root, toolHandler: success)
        try await eventually { restored.isLoaded }
        restored.select(id)
        #expect(restored.selected?.archivedAt != nil)
        #expect(restored.selected?.importantAt != nil && restored.selected?.unreadAt != nil)
        #expect(restored.selected?.messages == messages && restored.selected?.draft == "Retain this draft")
        restored.setArchived(id, archived: false)
        #expect(restored.selected?.isAvailable == true)
        restored.setImportant(id, important: false)
        #expect(restored.selected?.importantAt == nil)
        restored.setArchived(id, archived: true)
        restored.deleteConversation(id)
        #expect(restored.selectedID == nil && !restored.conversations.contains { $0.id == id })
        await restored.disconnect()
        let reopened = AgentChatController(triptychID: triptych, root: root, toolHandler: success)
        try await eventually { reopened.isLoaded }
        #expect(!reopened.conversations.contains { $0.id == id })
        await reopened.disconnect()
    }

    @Test("A missing runtime thread preserves local reading and draft without blaming the connection")
    func missingRuntimeHistory() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root, toolHandler: success)
        try await connect(controller)
        controller.editDraft("phased activity")
        controller.send()
        try await eventually { !controller.isBusy && controller.selected?.lastRunStatus == .completed }
        let id = try #require(controller.selectedID)
        let messages = controller.selected?.messages
        let thread = controller.selected?.threadID
        controller.editDraft("keep my question")
        let marker = controller.runtimeHome.appendingPathComponent("missing-thread-history")
        try Data().write(to: marker)
        controller.select(id)
        try await eventually { !controller.isRefreshingHistory }
        #expect(controller.historyUnavailable && controller.error == nil)
        #expect(controller.connectionState == .ready && !controller.canSend && !controller.canBranch && !controller.canCompact)
        #expect(controller.selected?.messages == messages && controller.selected?.draft == "keep my question")
        #expect(controller.selected?.threadID == thread)
        try FileManager.default.removeItem(at: marker)
        controller.retryHistory()
        try await eventually { !controller.isRefreshingHistory }
        #expect(!controller.historyUnavailable && controller.canSend && controller.error == nil)
        #expect(controller.selected?.draft == "keep my question")
        await controller.disconnect()
    }

    @Test("Turn elapsed time follows runtime identity through completion and archive restoration")
    func timedTurnRestoration() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let triptych = UUID()
        let controller = AgentChatController(triptychID: triptych, root: root, toolHandler: success)
        try await connect(controller)
        controller.editDraft("timed activity")
        controller.send()
        try await eventually { !controller.isBusy && controller.selected?.lastRunStatus == .completed }
        let id = try #require(controller.selectedID)
        let record = try #require(controller.selected?.turns.values.first)
        #expect(record.status == .completed && record.timing.completedSeconds == 38)
        controller.select(id)
        try await eventually { !controller.isRefreshingHistory }
        #expect(controller.selected?.turns.values.first == record)
        await controller.disconnect()
        let restored = AgentChatController(triptychID: triptych, root: root, toolHandler: success)
        try await eventually { restored.isLoaded }
        #expect(restored.selected?.turns.values.first == record)
        await restored.disconnect()
    }

    @Test("Reply quotes are delivered as Agent content, retained on history refresh and cleared only from the sent draft")
    func quoteDelivery() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root, toolHandler: success)
        try await connect(controller)
        controller.editDraft("phased activity")
        controller.send()
        try await eventually { !controller.isBusy && controller.selected?.lastRunStatus == .completed }
        let owner = try #require(controller.selectedID)
        let finalReply = controller.selected?.messages.last { $0.role == .assistant && $0.phase == .finalAnswer }
        let reply = try #require(finalReply)
        #expect(controller.quoteReply(reply.id, selection: nil, in: owner))
        controller.editDraft("Discuss this reply.")
        controller.send()
        try await eventually { !controller.isBusy && controller.selected?.draft.isEmpty == true }
        let request = try JSONDecoder().decode(
            MCPJSONValue.self,
            from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-turn.json")))
        let input = try #require(request.objectValue?["input"]?.arrayValue?.first?.objectValue?["text"]?.stringValue)
        #expect(input.contains("Quoted Agent reply selected by the researcher"))
        #expect(input.contains(reply.id))
        #expect(controller.selected?.draftReplyQuotes == nil)
        let sent = try #require(controller.selected?.messages.last(where: { $0.role == .user }))
        #expect(sent.replyQuotes?.first?.text == reply.text && sent.text == "Discuss this reply.")
        controller.select(owner)
        try await eventually { !controller.isRefreshingHistory }
        #expect(controller.selected?.messages.first(where: { $0.id == sent.id })?.replyQuotes == sent.replyQuotes)
        await controller.disconnect()
    }

    @Test("Malformed restored history leaves every retained message unchanged")
    func atomicHistoryReconciliation() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root, toolHandler: success)
        try await connect(controller)
        controller.editDraft("phased activity")
        controller.send()
        try await eventually { !controller.isBusy && controller.selected?.lastRunStatus == .completed }
        let id = try #require(controller.selectedID)
        let messages = controller.selected?.messages
        controller.editDraft("keep this input")
        try Data().write(to: controller.runtimeHome.appendingPathComponent("malformed-public-history"))
        controller.select(id)
        try await eventually { !controller.isRefreshingHistory }
        #expect(controller.error != nil)
        #expect(controller.selected?.messages == messages && controller.selected?.draft == "keep this input")
        await controller.disconnect()
    }

    @Test("Background items retain their own outcome across reply completion, history and later turns", arguments: [0, 7])
    func backgroundActivityLifetime(exitCode: Int) async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root, toolHandler: success)
        try await connect(controller)
        controller.editDraft("background activity")
        controller.send()
        try await eventually { !controller.isBusy && controller.selected?.lastRunStatus == .completed }
        let conversation = try #require(controller.selectedID)
        let command = try #require(controller.selected?.messages.first { $0.activity?.kind == .command })
        func commandStatus() -> AgentChatActivity.Status? {
            controller.selected?.messages.first { $0.id == command.id }?.activity?.status
        }
        #expect(commandStatus() == .running)
        controller.select(conversation)
        try await eventually { !controller.isRefreshingHistory }
        #expect(commandStatus() == .running)
        await controller.disconnect()
        #expect(commandStatus() == .uncertain)
        try await connect(controller)
        try await eventually { !controller.isRefreshingHistory }
        #expect(commandStatus() == .running)
        controller.editDraft("hold next turn")
        controller.send()
        try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let active = controller.currentTurnID
        #expect(active != command.turnID)
        try Data(String(exitCode).utf8).write(to: controller.runtimeHome.appendingPathComponent("complete-background-activity"))
        try await eventually { !controller.isRefreshingQuota }
        controller.refreshQuota()
        try await eventually { commandStatus() == (exitCode == 0 ? .completed : .failed) }
        #expect(controller.state == .working && controller.currentTurnID == active)
        #expect(controller.selected?.messages.first { $0.id == command.id }?.turnID == command.turnID)
        controller.stop()
        try await eventually { !controller.isBusy }
        await controller.disconnect()
    }

    @Test("Runtime public phases survive completed delivery, persisted history and reconnect")
    func publicMessagePhases() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let controller = AgentChatController(triptychID: id, root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await connect(controller)
        controller.editDraft("phased activity")
        controller.send()
        try await eventually { controller.selected?.lastRunStatus == .completed }
        let messages = try #require(controller.selected?.messages)
        #expect(messages.filter { $0.phase == .commentary }.map(\.text) == ["正在核对公开来源。"])
        #expect(messages.filter { $0.phase == .finalAnswer }.count == 1)
        #expect(messages.filter { $0.phase != nil }.allSatisfy { $0.turnID != nil })
        await controller.disconnect()
        let reopened = AgentChatController(triptychID: id, root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await connect(reopened)
        try await eventually { !reopened.isRefreshingHistory }
        #expect(reopened.selected?.messages.filter { $0.phase != nil }.map(\.phase) == messages.filter { $0.phase != nil }.map(\.phase))
        await reopened.disconnect()
    }

    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
    private var executable: URL {
        repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
    }
    @Test(
        "Async questions survive completed turns and reopening; replies preserve drafts and exact question identity",
        arguments: [false, true])
    func asyncQuestionDelivery(working: Bool) async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let triptych = UUID()
        let controller = AgentChatController(triptychID: triptych, root: root, toolHandler: success)
        try await connect(controller)
        controller.editDraft(working ? "hold async-form" : "async-form")
        controller.send()
        try await eventually { controller.pendingAsyncQuestion != nil && (working || !controller.isBusy) }
        let message = try #require(controller.pendingAsyncQuestion)
        let questions = try #require(message.asyncQuestion?.questions)
        #expect(questions.count == 2 && controller.approvals.isEmpty && controller.needsInput)
        let turn = controller.currentTurnID
        controller.editDraft("Keep this unsent draft")
        controller.editAsyncAnswers(
            message.id,
            values: [
                questions[0].id: .option("Compare the passages"),
                questions[1].id: .text("第二段，保留原文。"),
            ])
        controller.answerAsyncQuestion(message.id)
        try await eventually { controller.pendingAsyncQuestion == nil }
        #expect(controller.selected?.draft == "Keep this unsent draft")
        let data = try Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-turn.json"))
        let sent = try JSONDecoder().decode(MCPJSONValue.self, from: data)
        #expect(sent.objectValue?["expectedTurnId"]?.stringValue == (working ? turn : nil))
        let input = try #require(sent.objectValue?["input"]?.arrayValue)
        #expect(input.count == 1)
        let text = try #require(input.first?.objectValue?["text"]?.stringValue)
        let replies = try #require(CodexChatAsyncQuestions.decode(text))
        #expect(replies.map(\.questionItemId) == questions.map(\.id))
        #expect(replies.map(\.answer) == ["Compare the passages", "第二段，保留原文。"])
        #expect(controller.selected?.messages.last(where: { $0.role == .user })?.text.contains("send_user_message") == false)
        await controller.disconnect()
        let reopened = AgentChatController(triptychID: triptych, root: root, toolHandler: success)
        try await eventually { reopened.isLoaded }
        #expect(reopened.pendingAsyncQuestion == nil)
        #expect(reopened.selected?.messages.first(where: { $0.id == message.id })?.asyncQuestion?.responses.count == 2)
        await reopened.disconnect()
    }

    @Test("Unanswered async questions restore with their drafts; skipping and uncertain recovery do not replay", arguments: [false, true])
    func asyncQuestionRecovery(uncertain: Bool) async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let triptych = UUID()
        let initial = AgentChatController(triptychID: triptych, root: root, toolHandler: success)
        try await connect(initial)
        initial.editDraft("async-form")
        initial.send()
        try await eventually { initial.pendingAsyncQuestion != nil && !initial.isBusy }
        let request = try #require(initial.pendingAsyncQuestion)
        let questions = try #require(request.asyncQuestion?.questions)
        initial.editAsyncAnswers(request.id, values: [questions[0].id: .text("保留回答草稿")])
        await initial.disconnect()
        let controller = AgentChatController(triptychID: triptych, root: root, toolHandler: success)
        try await connect(controller)
        #expect(controller.pendingAsyncQuestion?.asyncQuestion?.answers[questions[0].id] == .text("保留回答草稿"))
        let conversationID = try #require(controller.selectedID)
        controller.setArchived(conversationID, archived: true)
        #expect(!controller.needsInput && controller.pendingAsyncQuestion == nil)
        controller.editAsyncAnswers(request.id, values: [:])
        controller.setArchived(conversationID, archived: false)
        #expect(controller.pendingAsyncQuestion?.asyncQuestion?.answers[questions[0].id] == .text("保留回答草稿"))
        if uncertain { try Data().write(to: controller.runtimeHome.appendingPathComponent("hold-parent-input")) }
        controller.answerAsyncQuestion(request.id, skip: true)
        if uncertain {
            try await eventually { controller.selected?.pendingMessageID != nil }
            await controller.disconnect()
            #expect(controller.pendingAsyncQuestion?.asyncQuestion?.pendingMessageID != nil)
            let userCount = controller.selected?.messages.filter { $0.role == .user }.count
            controller.confirmContinueAfterUncertainDelivery()
            #expect(controller.pendingAsyncQuestion == nil)
            #expect(controller.selected?.messages.first { $0.id == request.id }?.asyncQuestion?.responses.isEmpty == true)
            #expect(controller.selected?.messages.filter { $0.role == .user }.count == userCount)
        } else {
            try await eventually { controller.pendingAsyncQuestion == nil }
            #expect(
                controller.selected?.messages.first { $0.id == request.id }?.asyncQuestion?.responses
                    == Dictionary(uniqueKeysWithValues: questions.map { ($0.id, "") }))
            await controller.disconnect()
        }
    }

    @Test(
        "Return preference chooses steer or queue; queued editing preserves current draft, materials and identity",
        arguments: [AgentChatInputBehavior.steer, .queue])
    func inputPreferenceAndQueueEditing(behavior: AgentChatInputBehavior) async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root, toolHandler: success)
        try await connect(controller)
        controller.editDraft("hold activity")
        controller.submitDraft(whileWorking: behavior)  // Idle always starts a turn.
        try await eventually { controller.isBusy && controller.currentTurnID != nil }
        let turn = controller.currentTurnID
        let attachment = AgentChatAttachment(
            noteID: UUID(), vaultID: UUID(), relativePath: "QA.md", text: "Exact fixture", fingerprint: .init(content: "Exact fixture"))
        _ = controller.attachContext([attachment])
        controller.editDraft("hold retained follow-up")
        controller.submitDraft(whileWorking: behavior)
        if behavior == .queue {
            let queued = try #require(controller.queuedMessages.first)
            let owner = try #require(controller.selectedID)
            controller.editDraft("unrelated draft")
            #expect(controller.editQueuedMessage(queued.id, text: "edited follow-up", in: owner))
            #expect(controller.selected?.draft == "unrelated draft")
            #expect(controller.queuedMessages.first?.id == queued.id)
            #expect(controller.queuedMessages.first?.attachments == [attachment])
            #expect(controller.queuedMessages.first?.text == "edited follow-up")
            #expect(!controller.editQueuedMessage(queued.id, text: " ", in: owner))
            controller.removeQueuedMessage(queued.id)
            #expect(!controller.editQueuedMessage(queued.id, text: "late edit", in: owner))
        } else {
            try await eventually { controller.selected?.pendingMessageID == nil && controller.selected?.draft.isEmpty == true }
            #expect(controller.queuedMessages.isEmpty)
            #expect(controller.selected?.messages.last { $0.role == .user }?.attachments == [attachment])
        }
        #expect(controller.currentTurnID == turn)
        controller.stop()
        try await eventually { !controller.isBusy }
        await controller.disconnect()
    }

    private func root() throws -> URL {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func eventually(timeout: Duration = .seconds(8), _ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw TestFailure.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private enum TestFailure: Error { case timeout }
    private func connect(_ controller: AgentChatController) async throws {
        try await eventually { controller.isLoaded }
        controller.connect(executable: executable, home: controller.runtimeHome, cli: executable)
        try await eventually { controller.state == .ready && controller.account != nil }
    }
    private func success(_ request: ScholiumMCPBridgeRequest) -> ScholiumMCPBridgeResponse {
        try! .init(requestID: request.requestID, result: .object(["status": .string("ok")]))
    }
    private func preview(_ request: ScholiumMCPBridgeRequest) throws -> AgentNoteUpdatePreview {
        let before = Data("Synthetic before\n".utf8)
        let after = Data("Synthetic after\n".utf8)
        return .init(
            noteID: request.arguments["note_id"]?.stringValue.flatMap(UUID.init(uuidString:)) ?? UUID(),
            relativePath: "Fixture.md",
            comparison: try ExactSourceComparisonBuilder.build(
                startingData: before, endingData: after, startingRevision: .init(data: before), endingRevision: .init(data: after)))
    }

    @Test("Rename targets its captured conversation without changing another draft or stored messages")
    func renameConversation() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root, toolHandler: success)
        try await eventually { controller.isLoaded }
        let original = try #require(controller.selected)
        controller.newConversation()
        controller.editDraft("Keep this draft")
        controller.rename("  独立解释  ", in: original.id)
        controller.rename(" \n", in: original.id)
        #expect(controller.conversations.first { $0.id == original.id }?.title == "独立解释")
        #expect(controller.conversations.first { $0.id == original.id }?.messages == original.messages)
        #expect(controller.selected?.draft == "Keep this draft" && controller.selected?.title == "")
        await controller.disconnect()
    }

    @Test("Concurrent conversations keep tool tokens, hidden approvals and Stop scoped to their owner")
    func concurrentConversations() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        var writtenNotes: [String] = []
        let triptych = UUID()
        let registry = AgentChatRegistry(root: root, previewUpdate: preview) { request in
            if request.tool == .updateNote { writtenNotes.append(request.arguments["note_id"]?.stringValue ?? "") }
            return success(request)
        }
        let controller = registry.controller(for: triptych)
        try await connect(controller)
        let first = try #require(controller.selectedID)
        controller.editDraft("hold first")
        controller.send()
        try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let firstToken = try #require(controller.token)
        controller.newConversation()
        let second = try #require(controller.selectedID)
        #expect(first != second && controller.state == .ready)
        controller.setPermission(.fullAccess)
        controller.setEffort("high")
        controller.editDraft("hold second")
        controller.send()
        try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let secondToken = try #require(controller.token)
        #expect(firstToken != secondToken)
        let noteA = UUID().uuidString
        let noteB = UUID().uuidString
        let firstWrite = Task {
            await registry.handle(
                .init(
                    tool: .updateNote,
                    arguments: ["note_id": .string(noteA)], conversationToken: firstToken, runtimeContext: controller.runtimeContext(for: firstToken)))
        }
        try await eventually { controller.approvalCount(in: first) == 1 }
        #expect(controller.approvals.isEmpty && controller.needsInput && writtenNotes.isEmpty)
        let secondWrite = await registry.handle(
            .init(
                tool: .updateNote,
                arguments: ["note_id": .string(noteB)], conversationToken: secondToken, runtimeContext: controller.runtimeContext(for: secondToken)))
        #expect(secondWrite.error == nil && writtenNotes == [noteB])
        controller.select(first)
        let approval = try #require(controller.approvals.first?.id)
        controller.select(second)
        controller.answer(approval, allow: true)
        #expect(await firstWrite.value.error == nil)
        #expect(writtenNotes == [noteB, noteA] && !controller.needsInput)
        controller.stop(in: first)
        try await eventually { controller.state(for: first) == .ready }
        #expect(controller.selectedID == second && controller.state == .working)
        #expect(controller.owns(token: secondToken) && !controller.owns(token: firstToken))
        #expect(
            await registry.handle(.init(tool: .updateNote, conversationToken: firstToken, runtimeContext: controller.runtimeContext(for: firstToken))).error
                != nil)
        controller.stop()
        try await eventually { controller.state == .ready }
        await controller.disconnect()
    }

    @Test("Switching during send and steering cannot redirect messages, settings or completion")
    func switchDuringSend() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root, toolHandler: success)
        try await connect(controller)
        let first = try #require(controller.selectedID)
        controller.setEffort("high")
        controller.editDraft("hold first")
        controller.send()
        controller.newConversation()
        let second = try #require(controller.selectedID)
        controller.setEffort("low")
        controller.editDraft("second completes")
        controller.send()
        try await eventually {
            controller.state(for: first) == .working && controller.state(for: second) == .ready
                && controller.conversations.allSatisfy { $0.pendingMessageID == nil }
        }
        #expect(controller.conversations.first { $0.id == first }?.messages.filter { $0.role == .assistant }.isEmpty == true)
        #expect(controller.selected?.messages.last?.text == "中文 😀 fixture reply")
        controller.select(first)
        controller.editDraft("continue first")
        controller.send()
        controller.select(second)
        try await eventually { !controller.hasActiveExecutions }
        let a = try #require(controller.conversations.first { $0.id == first })
        let b = try #require(controller.conversations.first { $0.id == second })
        #expect(a.preferences.effort == "high" && b.preferences.effort == "low")
        #expect(a.messages.filter { $0.role == .user }.map(\.text) == ["hold first", "continue first"])
        #expect(b.messages.filter { $0.role == .user }.map(\.text) == ["second completes"])
        #expect(a.messages.filter { $0.role == .assistant }.count == 1)
        #expect(controller.selectedID == second)
        await controller.disconnect()
    }

    @Test("A mismatched steering acknowledgement cannot confirm additional input")
    func mismatchedSteerAcknowledgement() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root, toolHandler: success)
        try await connect(controller)
        controller.editDraft("hold initial request")
        controller.send()
        try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
        controller.editDraft("hold mismatched-steer-ack")
        controller.send()
        try await eventually { controller.error != nil || (controller.selected?.draft.isEmpty == true && controller.selected?.pendingMessageID == nil) }
        #expect(controller.selected?.pendingMessageID != nil)
        #expect(controller.selected?.lastRunStatus == .uncertain)
        #expect(!controller.canSend)
        await controller.disconnect()
    }

    @Test("Disconnect declines every conversation approval and cannot leave an active token")
    func disconnectConcurrentApprovals() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        var writes = 0
        let controller = AgentChatController(triptychID: UUID(), root: root, previewUpdate: preview) { request in
            if request.tool == .updateNote { writes += 1 }
            return success(request)
        }
        try await connect(controller)
        controller.editDraft("hold first")
        controller.send()
        try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let firstToken = try #require(controller.token)
        let a = Task {
            await controller.handle(.init(tool: .updateNote, conversationToken: firstToken, runtimeContext: controller.runtimeContext(for: firstToken)))
        }
        try await eventually { controller.needsInput }
        controller.newConversation()
        controller.editDraft("hold second")
        controller.send()
        try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let secondToken = try #require(controller.token)
        let b = Task {
            await controller.handle(.init(tool: .updateNote, conversationToken: secondToken, runtimeContext: controller.runtimeContext(for: secondToken)))
        }
        try await eventually { !controller.approvals.isEmpty }
        await controller.disconnect()
        let firstResult = await a.value
        let secondResult = await b.value
        #expect(firstResult.error != nil && secondResult.error != nil)
        #expect(writes == 0 && !controller.needsInput && !controller.hasActiveExecutions)
        #expect(!controller.owns(token: firstToken) && !controller.owns(token: secondToken))
        #expect(controller.connectionState == .disconnected)
    }

    @Test("Search renewal waits for runtime work and commands, preserves input, and keeps the thread")
    func searchRenewalRuntimeWork() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root) { request in success(request) }
        try await connect(controller)
        controller.editDraft("establish")
        controller.send()
        try await eventually { !controller.isBusy && controller.selected?.pendingMessageID == nil }
        let thread = controller.selected?.threadID
        let count = controller.selected?.messages.count
        let active = controller.runtimeHome.appendingPathComponent("settings-runtime-active")
        let command = controller.runtimeHome.appendingPathComponent("settings-background-command")
        try Data().write(to: active)
        try Data().write(to: command)
        controller.editDraft("retained research input")
        controller.setWebSearch(.live)
        #expect(controller.isRenewingSettings && !controller.canSend && !controller.canCompact && !controller.canBranch)
        try await eventually { FileManager.default.fileExists(atPath: controller.runtimeHome.appendingPathComponent("settings-idle-probes").path) }
        #expect(try String(contentsOf: controller.runtimeHome.appendingPathComponent("runtime-launches"), encoding: .utf8) == "1")
        try FileManager.default.removeItem(at: active)
        try await eventually { FileManager.default.fileExists(atPath: controller.runtimeHome.appendingPathComponent("settings-background-probes").path) }
        #expect(controller.isRenewingSettings && controller.selected?.messages.count == count)
        try FileManager.default.removeItem(at: command)
        try await eventually { !controller.isRenewingSettings && !controller.isBusy }
        #expect(controller.account != nil && controller.selected?.threadID == thread)
        #expect(controller.selected?.draft == "retained research input" && controller.selected?.messages.count == count)
        #expect(try String(contentsOf: controller.runtimeHome.appendingPathComponent("runtime-launches"), encoding: .utf8) == "2")
        controller.send()
        try await eventually { !controller.isBusy && controller.selected?.pendingMessageID == nil }
        let config = try JSONDecoder().decode(MCPJSONValue.self, from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("configuration.json")))
        #expect(config.objectValue?["config"]?.objectValue?["web_search"] == .string("live"))
        #expect(controller.selected?.threadID == thread)
        await controller.disconnect()
    }

    @Test("Pending search renewal preserves other turns' additional input and Stop")
    func searchRenewalOtherConversation() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root) { request in success(request) }
        try await connect(controller)
        let first = try #require(controller.selectedID)
        controller.editDraft("establish")
        controller.send()
        try await eventually { !controller.isBusy && controller.selected?.pendingMessageID == nil }
        controller.newConversation()
        let second = try #require(controller.selectedID)
        controller.editDraft("hold activity")
        controller.send()
        try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
        controller.select(first)
        try await eventually { !controller.isBusy }
        controller.editDraft("first draft")
        controller.setWebSearch(.disabled)
        #expect(controller.isRenewingSettings && !controller.canSend)
        controller.select(second)
        try await eventually { !controller.isRefreshingHistory }
        controller.editDraft("additional input")
        #expect(controller.state == .working && controller.canSend)
        controller.stop()
        try await eventually { !controller.isRenewingSettings && !controller.isBusy }
        #expect(controller.conversations.first { $0.id == first }?.draft == "first draft")
        #expect(controller.conversations.first { $0.id == second }?.draft == "additional input")
        #expect(controller.account != nil)
        await controller.disconnect()
    }

    @Test("An unverifiable runtime stays connected and explicit disconnect cancels settings renewal")
    func searchRenewalCancellation() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root) { request in success(request) }
        try await connect(controller)
        controller.editDraft("establish")
        controller.send()
        try await eventually { !controller.isBusy && controller.selected?.pendingMessageID == nil }
        let marker = controller.runtimeHome.appendingPathComponent("settings-probe-malformed")
        try Data().write(to: marker)
        controller.editDraft("not sent")
        controller.setWebSearch(.live)
        try await eventually { controller.settingsRenewalError != nil }
        #expect(controller.connectionState == .ready && controller.isRenewingSettings && !controller.canSend)
        try FileManager.default.removeItem(at: marker)
        let observed = controller.runtimeHome.appendingPathComponent("settings-idle-probes")
        try FileManager.default.removeItem(at: observed)
        try Data().write(to: controller.runtimeHome.appendingPathComponent("settings-probe-hold"))
        controller.renewSettingsWhenIdle()
        try await eventually { FileManager.default.fileExists(atPath: observed.path) }
        await controller.disconnectByUser()
        await Task.yield()
        #expect(controller.connectionState == .disconnected && !controller.isRenewingSettings)
        #expect(controller.selected?.draft == "not sent")
        #expect(try String(contentsOf: controller.runtimeHome.appendingPathComponent("runtime-launches"), encoding: .utf8) == "1")
    }

    @Test("A failed settings restart retains desired settings and input without replay")
    func searchRenewalLaunchFailure() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root) { request in success(request) }
        try await connect(controller)
        controller.editDraft("establish")
        controller.send()
        try await eventually { !controller.isBusy && controller.selected?.pendingMessageID == nil }
        let count = controller.selected?.messages.count
        let thread = controller.selected?.threadID
        let failure = controller.runtimeHome.appendingPathComponent("fail-runtime-start")
        try Data().write(to: failure)
        controller.editDraft("retained after failure")
        controller.setWebSearch(.live)
        try await eventually { controller.connectionState == .disconnected && controller.connectionError != nil }
        #expect(!controller.isRenewingSettings && controller.selected?.draft == "retained after failure")
        #expect(controller.selected?.messages.count == count && controller.selected?.threadID == thread)
        #expect(controller.selected?.preferences.webSearch == .live)
        try FileManager.default.removeItem(at: failure)
        try await connect(controller)
        try await eventually { !controller.isBusy }
        #expect(controller.selected?.draft == "retained after failure" && controller.selected?.messages.count == count)
        await controller.disconnect()
    }

    @Test("Conversation settings reach the runtime and survive reopening without altering another conversation")
    func runtimePreferences() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let triptych = UUID()
        let controller = AgentChatController(triptychID: triptych, root: root) { request in success(request) }
        try await connect(controller)
        let first = try #require(controller.selectedID)
        #expect(controller.selectedModel?.id == "fixture-picker")
        #expect(controller.selectedEffort == "low")
        controller.setModel("fixture-model")
        controller.setEffort("high")
        controller.setWebSearch(.live)
        controller.editDraft("capabilities")
        controller.send()
        try await eventually {
            controller.state == .ready && !controller.isBusy && controller.selected?.pendingMessageID == nil
                && controller.selected?.contextUsage != nil
        }
        let turn = try JSONDecoder().decode(
            MCPJSONValue.self,
            from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-turn.json")))
        #expect(turn.objectValue?["model"] == .string("fixture-model"))
        #expect(turn.objectValue?["effort"] == .string("high"))
        #expect(controller.selected?.contextUsage?.capacity == 32000)
        #expect(controller.selected?.messages.compactMap(\.plan).first?.steps.count == 2)
        #expect(controller.selected?.messages.compactMap(\.plan).first?.runStatus == .completed)
        try await eventually { !controller.isRefreshingQuota }
        #expect(controller.quotas.first?.primary?.usedPercent == 25)
        controller.newConversation()
        #expect(controller.selected?.preferences == .init())
        #expect(controller.selectedEffort == "low")
        controller.select(first)
        try await eventually { !controller.isBusy }
        #expect(controller.selected?.preferences.effort == "high")
        await controller.disconnect()
        let reopened = AgentChatController(triptychID: triptych, root: root) { request in success(request) }
        try await eventually { reopened.isLoaded }
        reopened.select(first)
        #expect(reopened.selected?.preferences.webSearch == .live)
        #expect(reopened.selected?.messages.compactMap(\.plan).count == 1)
        #expect(reopened.selected?.contextUsage?.lastTurnTokens == 1200)
        try await reopened.flushPersistence()
    }

    @Test("Resetting conversation overrides uses the selected runtime configuration on the next turn")
    func resetRuntimePreferences() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root) { request in success(request) }
        try await connect(controller)
        controller.setModel("fixture-model")
        controller.setEffort("high")
        controller.setWebSearch(.live)
        controller.editDraft("first")
        controller.send()
        try await eventually { controller.state == .ready && !controller.isBusy && controller.selected?.pendingMessageID == nil }
        controller.setModel(nil)
        controller.setWebSearch(.runtimeDefault)
        try await eventually { !controller.isRenewingSettings && !controller.isBusy }
        controller.editDraft("second")
        controller.send()
        try await eventually { controller.state == .ready && !controller.isBusy && controller.selected?.pendingMessageID == nil }
        let configuration = try JSONDecoder().decode(
            MCPJSONValue.self,
            from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("configuration.json")))
        #expect(configuration.objectValue?["config"]?.objectValue?["web_search"] == .string("cached"))
        #expect(configuration.objectValue?["config"]?.objectValue?["model_reasoning_effort"] == .string("low"))
        await controller.disconnect()
    }

    @Test("Compaction blocks sending until its runtime outcome and Stop preserves the draft")
    func compactionLifecycle() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root) { request in success(request) }
        try await connect(controller)
        controller.editDraft("establish history")
        controller.send()
        try await eventually { controller.state == .ready && !controller.isBusy && controller.selected?.pendingMessageID == nil }
        try Data().write(to: controller.runtimeHome.appendingPathComponent("hold-compaction"))
        controller.editDraft("Retained draft")
        controller.compactContext()
        #expect(controller.state == .compacting && !controller.canSend)
        controller.setEffort("high")
        #expect(controller.selected?.preferences.effort == nil)
        try await eventually { controller.selected?.messages.last?.activity?.kind == .compaction }
        controller.stop()
        try await eventually { controller.state == .ready }
        #expect(controller.selected?.draft == "Retained draft")
        #expect(controller.selected?.messages.last?.activity?.status == .interrupted)
        await controller.disconnect()
    }

    @Test("Queue steering keeps the draft and snapshots, and never retries an uncertain receipt", arguments: [false, true])
    func steerQueuedInput(uncertain: Bool) async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root, toolHandler: success)
        try await connect(controller)
        controller.editDraft("hold active turn")
        controller.send()
        try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let turn = try #require(controller.currentTurnID)
        controller.editDraft("first stays queued")
        #expect(controller.queue())
        let attachment = AgentChatAttachment(
            noteID: UUID(), vaultID: UUID(), relativePath: "Topics/Fixture.md",
            text: "Exact retained passage", fingerprint: .init(content: "Exact retained passage"))
        #expect(controller.attachContext([attachment]))
        controller.editDraft(uncertain ? "hold mismatched-steer-ack" : "hold queued addition")
        #expect(controller.queue())
        let messages = controller.queuedMessages
        let selected = try #require(messages.last)
        controller.editDraft("Unsent draft stays here")
        #expect(controller.canSteerQueuedMessage(selected.id))
        #expect(!controller.steerQueuedMessage(selected.id, expectedTurnID: "stale"))
        #expect(controller.queuedMessages == messages)
        #expect(controller.steerQueuedMessage(selected.id, expectedTurnID: turn))
        try await eventually {
            uncertain
                ? controller.selected?.lastRunStatus == .uncertain
                : controller.selected?.messages.contains(where: { $0.id == selected.id }) == true
                    && controller.selected?.pendingMessageID == nil
        }
        #expect(controller.selected?.draft == "Unsent draft stays here")
        #expect(controller.queuedMessages.map(\.id) == [messages[0].id])
        let sent = try #require(controller.selected?.messages.first { $0.id == selected.id })
        #expect(sent.attachments == [attachment] && sent.turnID == turn)
        let request = try JSONDecoder().decode(
            MCPJSONValue.self,
            from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-turn.json")))
        #expect(request.objectValue?["expectedTurnId"]?.stringValue == turn)
        #expect(request.objectValue?["input"]?.arrayValue?.first?.objectValue?["text"]?.stringValue?.contains("Exact retained passage") == true)
        if uncertain {
            #expect(controller.selected?.pendingMessageID == selected.id)
            #expect(!controller.canSteerQueuedMessage(messages[0].id))
        } else {
            controller.stop()
            try await eventually { controller.state == .ready }
            #expect(!controller.steerQueuedMessage(messages[0].id, expectedTurnID: turn))
            #expect(controller.queuedMessages.map(\.id) == [messages[0].id])
        }
        await controller.disconnect()
    }

    @Test("A queued steering preflight failure restores the same queue position")
    func steerQueuedMissingMaterial() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root, toolHandler: success)
        try await connect(controller)
        controller.editDraft("hold active turn")
        controller.send()
        try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let turn = try #require(controller.currentTurnID)
        controller.editDraft("first stays queued")
        #expect(controller.queue())
        let file = root.appendingPathComponent("Fixture.txt")
        try Data("Retained file text".utf8).write(to: file)
        await controller.addLocalFiles([file], to: try #require(controller.selectedID))
        controller.editDraft("hold material addition")
        #expect(controller.queue())
        let messages = controller.queuedMessages
        let selected = try #require(messages.last)
        let material = try #require(selected.localMaterials.first)
        let retained = try await controller.previewLocalMaterial(material)
        try FileManager.default.removeItem(at: retained)
        controller.editDraft("Keep this draft")
        #expect(controller.steerQueuedMessage(selected.id, expectedTurnID: turn))
        try await eventually { controller.queuedMessages.count == messages.count }
        #expect(controller.queuedMessages == messages)
        #expect(controller.selected?.draft == "Keep this draft")
        #expect(controller.selected?.pendingMessageID == nil)
        #expect(controller.selected?.messages.contains(where: { $0.id == selected.id }) == false)
        await controller.disconnect()
    }

    @Test("Next-turn queue keeps an explicit order and can be sent after the active turn stops")
    func queuedInput() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root) { request in success(request) }
        try await connect(controller)
        controller.editDraft("hold active turn")
        controller.send()
        try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
        controller.editDraft("queued research question")
        #expect(controller.canQueue)
        #expect(controller.queue())
        controller.editDraft("second queued research question")
        #expect(controller.queue())
        let queued = try #require(controller.selected?.queuedMessages.first)
        let secondQueued = try #require(controller.selected?.queuedMessages.dropFirst().first)
        #expect(queued.text == "queued research question" && queued.turnID == nil)
        #expect(secondQueued.text == "second queued research question" && !controller.canSendQueuedMessage(secondQueued.id))
        #expect(controller.selected?.draft.isEmpty == true)
        controller.stop()
        try await eventually { !controller.isBusy }
        #expect(controller.canSendQueuedMessage(queued.id))
        #expect(controller.sendQueuedMessage(queued.id))
        try await eventually { controller.selected?.queuedMessages.count == 1 && controller.selected?.lastRunStatus == .completed }
        let request = try JSONDecoder().decode(
            MCPJSONValue.self,
            from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-turn.json")))
        #expect(request.objectValue?["input"]?.arrayValue?.first?.objectValue?["text"]?.stringValue == "queued research question")
        #expect(controller.canSendQueuedMessage(secondQueued.id))
        #expect(controller.sendQueuedMessage(secondQueued.id))
        try await eventually { controller.selected?.queuedMessages.isEmpty == true && controller.selected?.lastRunStatus == .completed }
        await controller.disconnect()
    }

    @Test("A completed active turn admits only the first queued message once")
    func queuedInputAutoDispatch() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root) { request in success(request) }
        try await connect(controller)
        controller.editDraft("hold-queue active turn")
        controller.send()
        try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
        controller.editDraft("queued after completion")
        #expect(controller.queue())
        try Data().write(to: controller.runtimeHome.appendingPathComponent("release-queued-turn"))
        controller.refreshQuota()
        try await eventually {
            controller.selected?.queuedMessages.isEmpty == true
                && controller.selected?.messages.contains { $0.text == "Queued fixture reply" } == true
        }
        let request = try JSONDecoder().decode(
            MCPJSONValue.self,
            from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-turn.json")))
        #expect(request.objectValue?["input"]?.arrayValue?.first?.objectValue?["text"]?.stringValue == "queued after completion")
        await controller.disconnect()
    }

    @Test("Provider-neutral context staging preserves a draft, deduplicates snapshots and never sends")
    func stageContext() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root) { request in success(request) }
        try await eventually { controller.isLoaded }
        controller.editDraft("My existing question")
        let receiver: any AgentChatContextReceiving = controller
        let attachment = AgentChatAttachment(
            noteID: UUID(), vaultID: UUID(), relativePath: "Source.md",
            text: "exact source", fingerprint: .init(content: "exact source"), sourceLine: 3)
        #expect(receiver.attachContext([attachment, attachment]))
        let presentationID = controller.contextPresentationID
        #expect(controller.selected?.attachments.count == 1)
        #expect(controller.selected?.draft == "My existing question")
        #expect(controller.selected?.messages.isEmpty == true)
        #expect(controller.state == .disconnected)
        #expect(receiver.attachContext([attachment]))
        #expect(controller.contextPresentationID != presentationID)
        #expect(controller.selected?.attachments.count == 1)
        try await controller.flushPersistence()
    }

    @Test("Attachment reads show their selected scope without Note-reading or mutation evidence")
    func attachmentReadPresentation() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let triptych = UUID()
        let controller = AgentChatController(triptychID: triptych, root: root) { request in
            #expect(request.arguments["triptych_id"]?.stringValue == triptych.uuidString.lowercased())
            return try! .init(
                requestID: request.requestID,
                result: .object([
                    "filename": .string("Original.pdf"),
                    "kind": .string("pdf_text"), "page": .integer(2), "text": .string(""), "text_available": .bool(false), "image": .null,
                    "has_more": .bool(false),
                ]))
        }
        try await connect(controller)
        controller.editDraft("hold")
        controller.send()
        try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let token = try #require(controller.token)
        let response = await controller.handle(.init(tool: .readAttachment, conversationToken: token, runtimeContext: controller.runtimeContext(for: token)))
        #expect(response.error == nil && controller.approvals.isEmpty)
        let activity = try #require(controller.selected?.messages.last?.activity)
        #expect(activity.kind == .readAttachment && !activity.kind.isMutation && activity.status == .completed)
        #expect(activity.files.first?.path == "Original.pdf" && activity.files.first?.noteID == nil && activity.sourceObservation == nil)
        #expect(activity.detail.contains(String(localized: "This selection contains no readable text.")))
        #expect(activity.detail.contains("2") && controller.selected?.messages.last?.changeID == nil)
        await controller.disconnect()
    }

    @Test("Display stays with its admitted window instance and selected conversation")
    func displayAdmission() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = AgentChatDisplayScope(windowID: UUID(), registrationID: UUID())
        var visible: AgentChatDisplayScope? = original
        var calls: [ScholiumMCPBridgeRequest] = []
        let controller = AgentChatController(triptychID: UUID(), root: root, displayWindow: { _ in visible }) { request in
            calls.append(request)
            return try! .init(
                requestID: request.requestID,
                result: .object(["relative_path": .string("Source.md"), "activated": .bool(true), "location_requested": .bool(true)]))
        }
        try await connect(controller)
        controller.editDraft("hold")
        controller.send()
        try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let owner = try #require(controller.selectedID)
        let token = try #require(controller.token)
        let request = ScholiumMCPBridgeRequest(tool: .showNote, conversationToken: token, runtimeContext: controller.runtimeContext(for: token))
        visible = .init(windowID: original.windowID, registrationID: UUID())
        #expect(await controller.handle(request).error != nil && calls.isEmpty)
        visible = original
        controller.newConversation()
        #expect(await controller.handle(request).error != nil && calls.isEmpty)
        controller.select(owner)
        let wrong = ScholiumMCPBridgeRequest(
            tool: .showNote, arguments: ["window_id": .string(UUID().uuidString)], conversationToken: token, runtimeContext: request.runtimeContext)
        #expect(await controller.handle(wrong).error != nil && calls.isEmpty)
        #expect(await controller.handle(request).error == nil && calls.count == 1)
        #expect(calls.first?.arguments["window_id"]?.stringValue == original.windowID.uuidString.lowercased())
        #expect(calls.first?.conversationToken == token && calls.first?.runtimeContext == request.runtimeContext)
        #expect(controller.approvals.isEmpty && controller.selected?.messages.last?.changeID == nil)
        visible = nil
        #expect(await controller.handle(request).error != nil && calls.count == 1)
        await controller.disconnect()
    }

    @Test("A stopped comparison cannot later request approval or write")
    func stopDuringComparison() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        var release: CheckedContinuation<Void, Never>?
        var writes = 0
        let controller = AgentChatController(
            triptychID: UUID(), root: root,
            previewUpdate: { request in
                await withCheckedContinuation { release = $0 }
                return try preview(request)
            }
        ) { request in
            if request.tool == .updateNote { writes += 1 }
            return success(request)
        }
        try await connect(controller)
        controller.editDraft("hold before comparison")
        controller.send()
        try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let token = try #require(controller.token)
        let operation = Task {
            await controller.handle(.init(tool: .updateNote, conversationToken: token, runtimeContext: controller.runtimeContext(for: token)))
        }
        try await eventually { release != nil }
        controller.stop()
        try await eventually { !controller.isBusy }
        release?.resume()
        #expect(await operation.value.error != nil)
        #expect(writes == 0 && controller.approvals.isEmpty)
        #expect(controller.selected?.messages.last?.activity?.status == .interrupted)
        await controller.disconnect()
    }

    @Test(
        "Ask waits, decline and cancellation cannot write; Full Access remains Triptych scoped",
        arguments: [ScholiumMCPToolName.updateNote])
    func permissionAdmission(tool: ScholiumMCPToolName) async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        var writes = 0
        let triptych = UUID()
        let controller = AgentChatController(triptychID: triptych, root: root, previewUpdate: preview) { request in
            #expect(request.arguments["triptych_id"] == .string(triptych.uuidString.lowercased()))
            if request.tool == tool { writes += 1 }
            return success(request)
        }
        try await connect(controller)
        controller.editDraft("hold")
        controller.send()
        try await eventually {
            controller.state == .working && controller.selected?.pendingMessageID == nil
        }
        let token = try #require(controller.token)
        let request = ScholiumMCPBridgeRequest(tool: tool, conversationToken: token, runtimeContext: controller.runtimeContext(for: token))
        let declined = Task { await controller.handle(request) }
        try await eventually { controller.approvals.count == 1 }
        #expect(writes == 0)
        #expect(controller.selected?.messages.last?.activity?.status == .waitingForApproval)
        controller.answer(try #require(controller.approvals.first?.id), allow: false)
        #expect(await declined.value.error != nil)
        #expect(controller.selected?.messages.last?.activity?.status == .declined)
        #expect(writes == 0)
        let cancelled = Task { await controller.handle(request) }
        try await eventually { controller.approvals.count == 1 }
        cancelled.cancel()
        #expect(await cancelled.value.error != nil)
        #expect(controller.approvals.isEmpty && writes == 0)
        let approved = Task { await controller.handle(request) }
        try await eventually { controller.approvals.count == 1 }
        controller.answer(try #require(controller.approvals.first?.id), allow: true)
        #expect(await approved.value.error == nil)
        #expect(writes == 1)
        let stopped = Task { await controller.handle(request) }
        try await eventually { controller.approvals.count == 1 }
        controller.stop()
        #expect(await stopped.value.error != nil)
        try await eventually { controller.state == .ready }
        #expect(writes == 1)
        controller.setPermission(.fullAccess)
        controller.editDraft("hold again")
        controller.send()
        try await eventually {
            controller.state == .working && controller.selected?.pendingMessageID == nil
        }
        #expect(controller.token == token)
        #expect(await controller.handle(request).error != nil)
        let current = try #require(controller.token)
        let wrong = ScholiumMCPBridgeRequest(
            tool: tool, arguments: ["triptych_id": .string(UUID().uuidString)],
            conversationToken: current, runtimeContext: controller.runtimeContext(for: current))
        #expect(await controller.handle(wrong).error != nil)
        #expect(writes == 1)
        #expect(
            await controller.handle(.init(tool: tool, conversationToken: current, runtimeContext: controller.runtimeContext(for: current))).error == nil)
        #expect(writes == 2 && controller.approvals.isEmpty)
        await controller.disconnect()
        #expect(
            await controller.handle(.init(tool: tool, conversationToken: current, runtimeContext: controller.runtimeContext(for: current))).error != nil)
    }

    @Test("Live bridge activity distinguishes reads, no-op updates, confirmed edits and failed writes")
    func operationEvidence() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let note = UUID()
        let change = UUID()
        let controller = AgentChatController(triptychID: UUID(), root: root) { request in
            await Task.yield()
            let mode = request.arguments["content"]?.stringValue ?? "read"
            if mode == "failed" {
                return try! .init(
                    requestID: request.requestID,
                    error: .init(
                        code: .staleRevision, message: "The file changed.", recovery: "Read again."))
            }
            if mode == "noop" {
                return try! .init(
                    requestID: request.requestID,
                    error: .init(
                        code: .noChanges, message: "Unchanged.", recovery: "Continue."))
            }
            var result: [String: MCPJSONValue] = [
                "note_id": .string(note.uuidString),
                "relative_path": .string("Ideas/理由.md"),
            ]
            if request.tool == .readNote {
                let source = "Exact current source.\n"
                let fingerprint = DocumentFingerprint(content: "Exact current source.\n")
                result["source"] = .string(source)
                result["fingerprint"] = .object(["sha256": .string(fingerprint.sha256), "byte_count": .integer(fingerprint.byteCount)])
                result["start_line"] = .integer(1)
                result["line_count"] = .integer(1)
                result["complete"] = .bool(true)
                result["next_line"] = .null
            }
            if request.tool == .updateNote {
                result["change_id"] = .string(change.uuidString)
                result["before_fingerprint"] = .object(["sha256": .string("before")])
                result["after_fingerprint"] = .object(["sha256": .string("after")])
                result["readback_verified"] = .bool(true)
            }
            return try! .init(requestID: request.requestID, result: .object(result))
        }
        try await connect(controller)
        controller.setPermission(.fullAccess)
        controller.editDraft("hold activity")
        controller.send()
        try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let token = try #require(controller.token)
        let arguments: [String: MCPJSONValue] = ["note_id": .string(note.uuidString)]
        _ = await controller.handle(
            .init(tool: .readNote, arguments: arguments, conversationToken: token, runtimeContext: controller.runtimeContext(for: token)))
        #expect(controller.selected?.messages.last?.activity?.files.first?.effect == .read)
        let reading = try #require(controller.selected?.messages.last?.activity?.sourceObservation)
        var updateArguments = arguments
        updateArguments["content"] = .string("noop")
        _ = await controller.handle(
            .init(tool: .updateNote, arguments: updateArguments, conversationToken: token, runtimeContext: controller.runtimeContext(for: token)))
        #expect(controller.selected?.messages.last?.activity?.files.first?.effect == .unchanged)
        updateArguments["content"] = .string("edit")
        _ = await controller.handle(
            .init(tool: .updateNote, arguments: updateArguments, conversationToken: token, runtimeContext: controller.runtimeContext(for: token)))
        #expect(controller.selected?.messages.last?.activity?.files.first?.effect == .edited)
        #expect(controller.selected?.messages.last?.changeID == change)
        updateArguments["content"] = .string("failed")
        _ = await controller.handle(
            .init(tool: .updateNote, arguments: updateArguments, conversationToken: token, runtimeContext: controller.runtimeContext(for: token)))
        #expect(controller.selected?.messages.last?.activity?.status == .failed)
        #expect(controller.selected?.messages.last?.activity?.files.first?.effect == nil)
        let changed = controller.selected?.messages.first { $0.changeID == change }
        #expect(changed?.activity?.files.first?.effect == .edited)
        #expect(changed?.activity?.files.first?.path == "Ideas/理由.md")
        controller.stop()
        try await eventually { controller.state == .ready }
        #expect(controller.selected?.messages.contains { $0.activity?.kind == .command && $0.activity?.status == .failed } == true)
        await controller.disconnect()
        let restored = AgentChatController(triptychID: controller.triptychID, root: root, toolHandler: success)
        try await eventually { restored.isLoaded }
        #expect(restored.selected?.messages.compactMap(\.activity).contains { $0.status.isActive } == false)
        #expect(restored.selected?.messages.first { $0.changeID == change }?.activity?.files.first?.effect == .edited)
        #expect(restored.selected?.messages.contains { $0.activity?.sourceObservation == reading } == true)
        try await connect(restored)
        #expect(restored.selected?.messages.compactMap(\.activity).first { $0.kind == .command }?.status == .failed)
        await restored.disconnect()
    }

    @Test("Early completion, conversation switching, history and drafts survive reconnect")
    func completionAndPersistence() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let triptych = UUID()
        let controller = AgentChatController(triptychID: triptych, root: root, toolHandler: success)
        try await connect(controller)
        controller.setPermission(.fullAccess)
        controller.editDraft("first")
        controller.send()
        try await eventually {
            controller.state == .ready && !controller.isBusy && controller.selected?.pendingMessageID == nil
                && controller.selected?.messages.count == 2
        }
        #expect(controller.selected?.messages.last?.text == "中文 😀 fixture reply")
        let first = try #require(controller.selectedID)
        let firstThread = controller.selected?.threadID
        let oldToken = controller.token
        controller.editDraft("unsent 中文 draft")
        controller.newConversation()
        #expect(controller.token == nil && controller.selected?.threadID == nil)
        controller.select(first)
        try await eventually { controller.state == .ready }
        #expect(controller.selected?.messages.count == 2)
        #expect(controller.selected?.draft == "unsent 中文 draft")
        controller.editDraft("hold approval")
        controller.send()
        try await eventually { controller.approvals.count == 1 }
        #expect(controller.token != oldToken && controller.selected?.threadID == firstThread)
        controller.stop()
        try await eventually { controller.state == .ready }
        await controller.disconnect()
        let restored = AgentChatController(triptychID: triptych, root: root, toolHandler: success)
        try await connect(restored)
        #expect(restored.selected?.permission == .fullAccess)
        #expect(restored.selected?.threadID == firstThread)
        #expect(restored.selected?.messages.filter { $0.role == .assistant }.count == 1)
        await restored.disconnect()
    }

    @Test("Lost acknowledgement is recovered by client message identity without resending")
    func uncertainDelivery() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root, toolHandler: success)
        try await connect(controller)
        controller.editDraft("disconnect")
        controller.send()
        try await eventually { controller.state == .disconnected }
        #expect(controller.selected?.pendingMessageID != nil)
        try await connect(controller)
        #expect(controller.selected?.pendingMessageID == nil)
        #expect(controller.selected?.messages.filter { $0.role == .user }.count == 1)
        #expect(controller.selected?.messages.filter { $0.role == .assistant }.count == 1)
        await controller.disconnect()
    }

    @Test("Disconnect during initialization cannot revive a stale connection")
    func disconnectDuringConnect() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root, toolHandler: success)
        try await eventually { controller.isLoaded }
        controller.connect(executable: executable, home: controller.runtimeHome, cli: executable)
        await controller.disconnect()
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.state == .disconnected && controller.token == nil)
        try await connect(controller)
        await controller.disconnect()
    }

    @Test("Stdio splits Unicode safely, correlates concurrent replies and cancels pending requests")
    func transport() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = CodexAppServer()
        try await runtime.start(executable: executable, home: root)
        async let first = runtime.request("test/echo", params: ["text": .string("中文 😀")])
        async let second = runtime.request("test/echo", params: ["text": .string("second")])
        #expect(try await first.objectValue?["text"] == .string("中文 😀"))
        #expect(try await second.objectValue?["text"] == .string("second"))
        let cancelled = Task { try await runtime.request("test/hang") }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            Issue.record("Cancelled request succeeded")
        } catch {}
        let pending = Task { try await runtime.request("test/hang") }
        await runtime.close()
        do {
            _ = try await pending.value
            Issue.record("Closed request succeeded")
        } catch {}
    }

    @Test("Archiving preserves messages and drafts, blocks sending, and restores after reopening")
    func archiveConversation() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let triptych = UUID()
        let controller = AgentChatController(triptychID: triptych, root: root, toolHandler: success)
        try await connect(controller)
        controller.editDraft("A question")
        controller.send()
        try await eventually { controller.state == .ready && controller.selected?.messages.count == 2 }
        controller.editDraft("A retained follow-up")
        let id = try #require(controller.selectedID)
        let messages = controller.selected!.messages
        let updated = controller.selected!.updatedAt
        controller.editDraft("A retained follow-up")
        #expect(controller.selected?.updatedAt == updated)
        controller.setArchived(id, archived: true)
        #expect(controller.selected?.archivedAt != nil && !controller.canSend)
        #expect(controller.selected?.messages == messages)
        try await controller.flushPersistence()
        await controller.disconnect()
        let reopened = AgentChatController(triptychID: triptych, root: root, toolHandler: success)
        try await eventually { reopened.isLoaded }
        let archived = try #require(reopened.conversations.first { $0.id == id })
        #expect(archived.archivedAt != nil && archived.draft == "A retained follow-up")
        #expect(archived.messages == messages && reopened.selectedID != id)
        reopened.setArchived(id, archived: false)
        reopened.select(id)
        #expect(reopened.selected?.archivedAt == nil && reopened.selected?.messages == messages)
        await reopened.disconnect()
    }

    @Test("Automatic connection uses explicit machine settings without rewriting them")
    func automaticConnection() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "scholium-chat-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(executable.path, forKey: "agent.codex.executable")
        defaults.set(executable.path, forKey: "agent.scholium.helper")
        let controller = AgentChatController(triptychID: UUID(), root: root, toolHandler: success)
        try await eventually { controller.isLoaded }
        controller.connectConfigured(using: defaults)
        try await eventually { controller.state == .ready && controller.account != nil }
        #expect(defaults.string(forKey: "agent.codex.home") == nil)
        await controller.disconnect()
        defaults.set("/missing-test-runtime", forKey: "agent.codex.executable")
        controller.connectConfigured(using: defaults)
        #expect(controller.state == .disconnected && controller.error != nil)
    }

    @Test("Saved connection intent restores transport and a crash never replays input")
    func persistentConnectionRecovery() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "scholium-chat-recovery-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(executable.path, forKey: "agent.codex.executable")
        defaults.set(executable.path, forKey: "agent.scholium.helper")
        let triptych = UUID()
        let controller = AgentChatController(triptychID: triptych, root: root, methodDefaults: defaults, toolHandler: success)
        try await eventually { controller.isLoaded }
        controller.connectConfigured()
        try await eventually { controller.account != nil && controller.state == .ready }
        controller.editDraft("hold disconnect")
        controller.send()
        try await eventually { controller.connectionState == .connecting }
        try await eventually { controller.connectionState == .ready && !controller.isBusy }
        #expect(controller.error == nil && controller.token == nil)
        let messages = try #require(controller.selected?.messages)
        #expect(messages.filter { $0.role == .user }.count == 1)
        let thread = try #require(controller.selected?.threadID)
        let history = try JSONDecoder().decode(
            MCPJSONValue.self,
            from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("fixture-threads.json")))
        #expect(history.objectValue?[thread]?.objectValue?["turns"]?.arrayValue?.count == 1)
        await controller.disconnect()
        let reopened = AgentChatController(triptychID: triptych, root: root, methodDefaults: defaults, toolHandler: success)
        try await eventually { reopened.isLoaded && reopened.account != nil && !reopened.isBusy }
        #expect(reopened.selected?.threadID == thread && reopened.selected?.messages.filter { $0.role == .user }.count == 1)
        await reopened.disconnectByUser()
        let disconnected = AgentChatController(triptychID: triptych, root: root, methodDefaults: defaults, toolHandler: success)
        try await eventually { disconnected.isLoaded }
        #expect(disconnected.connectionState == .disconnected && disconnected.account == nil)
        await disconnected.disconnect()
    }

    @Test("Exhausted automatic recovery preserves input and explicit reconnect starts no new turn")
    func exhaustedConnectionRecovery() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "scholium-chat-offline-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(executable.path, forKey: "agent.codex.executable")
        defaults.set(executable.path, forKey: "agent.scholium.helper")
        let controller = AgentChatController(triptychID: UUID(), root: root, methodDefaults: defaults, toolHandler: success)
        try await eventually { controller.isLoaded }
        controller.connectConfigured()
        try await eventually { controller.account != nil && controller.state == .ready }
        let failure = controller.runtimeHome.appendingPathComponent("fail-runtime-start")
        try Data().write(to: failure)
        controller.editDraft("hold disconnect")
        controller.send()
        try await eventually { controller.connectionState == .connecting }
        controller.editDraft("Preserve this offline draft")
        try await eventually(timeout: .seconds(12)) { controller.connectionState == .disconnected && controller.error != nil }
        #expect(try String(contentsOf: controller.runtimeHome.appendingPathComponent("failed-runtime-starts"), encoding: .utf8) == "3")
        #expect(controller.selected?.pendingMessageID != nil && controller.selected?.draft == "Preserve this offline draft")
        #expect(controller.selected?.messages.filter { $0.role == .user }.count == 1 && controller.token == nil)
        try FileManager.default.removeItem(at: failure)
        controller.connectConfigured()
        try await eventually { controller.account != nil && !controller.isBusy && controller.selected?.pendingMessageID == nil }
        #expect(controller.selected?.draft == "Preserve this offline draft")
        #expect(controller.selected?.messages.filter { $0.role == .user }.count == 1)
        let thread = try #require(controller.selected?.threadID)
        let history = try JSONDecoder().decode(
            MCPJSONValue.self,
            from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("fixture-threads.json")))
        #expect(history.objectValue?[thread]?.objectValue?["turns"]?.arrayValue?.count == 1)
        await controller.disconnectByUser()
    }

    @Test("A reusable tool route admits only its current runtime turn")
    func persistentRouteRequiresCurrentTurn() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        var reads = 0
        let controller = AgentChatController(triptychID: UUID(), root: root) { request in
            reads += 1
            return success(request)
        }
        try await connect(controller)
        controller.editDraft("hold first")
        controller.send()
        try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let route = try #require(controller.token)
        let oldContext = try #require(controller.runtimeContext(for: route))
        let old = ScholiumMCPBridgeRequest(tool: .readNote, conversationToken: route, runtimeContext: oldContext)
        #expect(await controller.handle(old).error == nil)
        controller.stop()
        try await eventually { controller.state == .ready }
        #expect(await controller.handle(old).error != nil)
        controller.editDraft("hold second")
        controller.send()
        try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
        #expect(controller.token == route)
        #expect(await controller.handle(old).error != nil)
        #expect(await controller.handle(.init(tool: .readNote, conversationToken: route)).error != nil)
        let current = try #require(controller.runtimeContext(for: route))
        #expect(current.threadID == oldContext.threadID && current.turnID != oldContext.turnID)
        #expect(
            await controller.handle(
                .init(
                    tool: .readNote, conversationToken: route,
                    runtimeContext: .init(threadID: "another-thread", turnID: current.turnID))
            ).error != nil)
        #expect(await controller.handle(.init(tool: .readNote, conversationToken: route, runtimeContext: current)).error == nil)
        #expect(reads == 2)
        await controller.disconnect()
        #expect(await controller.handle(old).error != nil)
    }

    @Test("Corrupt or linked history is preserved, never silently replaced")
    func storage() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = AgentChatStorage(root: root)
        var conversation = AgentChatConversation(triptychID: UUID())
        conversation.draft = "\u{FEFF}中文 😀\r\n"
        conversation.permission = .fullAccess
        conversation.queuedMessages = [.init(role: .user, text: "待发送的研究问题")]
        try await storage.save([conversation])
        #expect(try await storage.load() == [conversation])
        let file = root.appendingPathComponent("conversations.json")
        try Data("broken".utf8).write(to: file)
        do {
            _ = try await storage.load()
            Issue.record("Corrupt history accepted")
        } catch {}
        #expect(try String(contentsOf: file, encoding: .utf8) == "broken")
        try FileManager.default.removeItem(at: file)
        let target = root.appendingPathComponent("untouched")
        try Data("original".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        do {
            try await storage.save([])
            Issue.record("Linked history overwritten")
        } catch {}
        #expect(try String(contentsOf: target, encoding: .utf8) == "original")
    }

    @Test(
        "Selected installed Codex runtime supports the stable client handshake",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_CODEX_SMOKE_EXECUTABLE"] != nil))
    func officialRuntimeSmoke() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try #require(ProcessInfo.processInfo.environment["SCHOLIUM_CODEX_SMOKE_EXECUTABLE"])
        let runtime = CodexAppServer()
        try await runtime.start(executable: URL(fileURLWithPath: path), home: root)
        let initialized = try await runtime.request(
            "initialize",
            params: [
                "clientInfo": .object(["name": .string("scholium-test"), "version": .string("0.1")]),
                "capabilities": .object(["experimentalApi": .bool(true)]),
            ])
        #expect(initialized.objectValue != nil)
        try await runtime.notify("initialized")
        let account = try await runtime.request("account/read")
        #expect(account.objectValue != nil)
        let models = try await runtime.chatModels()
        #expect(!models.isEmpty)
        _ = try await runtime.chatDefaults()
        let thread = try await runtime.request(
            "thread/start",
            params: [
                "cwd": .string(root.path), "sandbox": .string("read-only"),
                "approvalPolicy": .string("on-request"),
            ])
        #expect(thread.objectValue?["thread"]?.objectValue?["id"]?.stringValue != nil)
        await runtime.close()
    }

    @Test("File references reject paths, duplicate locators, ports and missing identities")
    func references() throws {
        let id = UUID()
        let vault = UUID()
        let fingerprint = DocumentFingerprint(content: "Exact source\r\n")
        let versioned = try #require(
            AgentChatReference.parse(
                AgentChatReference.url(
                    noteID: id, line: 7, revision: fingerprint, vaultID: vault)))
        #expect(versioned.noteID == id && versioned.vaultID == vault)
        #expect(versioned.line == 7 && versioned.revision == fingerprint.sha256)
        #expect(AgentChatReference.parse(AgentChatReference.url(noteID: id))?.revision == nil)
        #expect(AgentChatReference.parse(AgentChatReference.url(noteID: id, line: 7))?.noteID == id)
        #expect(AgentChatReference.parse(AgentChatReference.url(noteID: id, line: 7))?.line == 7)
        for suffix in [
            "/file.md", "?line=0", "?line=x", "?line=1&line=2", ":80", "#fragment",
            "?revision", "?revision=", "?revision=wrong", "?revision=" + String(repeating: "g", count: 64),
            "?revision=\(fingerprint.sha256)&revision=\(fingerprint.sha256)",
            "?vault", "?vault=", "?vault=wrong", "?vault=\(vault)&vault=\(vault)", "?unknown=1",
        ] {
            #expect(
                AgentChatReference.parse(try #require(URL(string: "scholium-note://\(id)\(suffix)"))) == nil
            )
        }
    }
}
