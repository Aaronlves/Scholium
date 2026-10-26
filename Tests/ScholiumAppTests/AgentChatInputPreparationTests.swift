import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp
@testable import ScholiumApplication

@Suite("Chat input preparation", .serialized)
struct AgentChatInputPreparationTests {
    @Test("Preparation preserves exact supplied text and Note snapshot attribution")
    func exactTextAndSnapshot() async throws {
        let raw = "\u{feff}Question: e\u{301}, 中文, \\\"quoted\\\"\r\n\r\n"
        let excerpt = "\u{feff}# Source\r\nExact e\u{301} text\r\n"
        let noteID = UUID(), vaultID = UUID()
        let fingerprint = DocumentFingerprint(content: excerpt)
        let attachment = AgentChatAttachment(
            noteID: noteID, vaultID: vaultID, relativePath: "Sources/Exact.md", text: excerpt,
            fingerprint: fingerprint, sourceLine: 2, extent: .wholeNote, source: .editorSnapshot, vaultRole: .sourceCorpus)
        let message = AgentChatMessage(role: .user, text: raw, attachments: [attachment])
        let text = try #require(try await AgentChatInputPreparation.prepare(message))
        #expect(text.hasPrefix(raw))
        #expect(text.contains("\nNote: Sources/Exact.md\nID: \(noteID.uuidString)\nExtent: wholeNote\nSource: editorSnapshot\nVault role: source_corpus\n"))
        #expect(text.contains("Snapshot SHA-256: \(fingerprint.sha256)\nReference: \(AgentChatReference.url(noteID: noteID, line: 2, revision: fingerprint, vaultID: vaultID).absoluteString)\n"))
        #expect(text.hasSuffix(excerpt + "\nEnd material."))
        #expect(String(text.prefix(raw.count)).utf8.elementsEqual(raw.utf8))
    }

    @Test("Async question replies keep their exact system-encoded envelope")
    func questionReplyEnvelope() async throws {
        let replies: [AgentChatQuestionReply] = [
            .init(questionItemId: "item/1", question: "Which \"source\"?", answer: "原文\r\ne\u{301}"),
            .init(questionItemId: "item/2", question: "Other?", answer: ""),
        ]
        var message = AgentChatMessage(role: .user, text: "Display text is not the structured answer payload")
        message.questionReplies = replies
        message.replyQuotes = [.init(conversationID: UUID(), messageID: "old-reply", text: "Do not append this quote")]
        let text = try #require(try await AgentChatInputPreparation.prepare(message))
        let expected = try CodexChatAsyncQuestions.encode(replies)
        #expect(text.utf8.elementsEqual(expected.utf8))
        #expect(CodexChatAsyncQuestions.decode(text) == replies)
    }

    @Test("The existing seven MiB encoded-string limit includes JSON escapes", arguments: [false, true])
    func encodedBudgetBoundary(escaped: Bool) async throws {
        // The two enclosing quotes also count. A literal quote is encoded as
        // two bytes; this checks the real encoder rather than a raw-text cap.
        let maximum = 7 * 1_024 * 1_024
        let unit = escaped ? "\"" : "x"
        let count = (maximum - 2) / (escaped ? 2 : 1)
        let accepted = String(repeating: unit, count: count)
        let prepared = try await AgentChatInputPreparation.prepare(.init(role: .user, text: accepted))
        #expect(prepared?.utf8.elementsEqual(accepted.utf8) == true)
        let refused = try await AgentChatInputPreparation.prepare(.init(role: .user, text: accepted + unit))
        #expect(refused == nil)
    }

    @MainActor
    @Test("A queued send cannot publish a stale budget error or consume input", .timeLimit(.minutes(1)), arguments: [
        "cancelled", "connection", "thread", "pending", "state", "sendingIdentity", "boundTurn",
    ])
    func invalidatedPreparation(reason: String) async throws {
        try await withController { controller in
            let id = try #require(controller.selectedID)
            let originalConnection = controller.connectionID
            let raw = String(repeating: "x", count: 7 * 1_024 * 1_024)
            controller.editDraft(raw)
            let attachment = AgentChatAttachment(
                noteID: UUID(), vaultID: UUID(), relativePath: "Retained.md",
                text: "Exact retained source\r\n", fingerprint: .init(content: "Exact retained source\r\n"))
            controller.attach(attachment)
            controller.update(in: id) {
                $0.draftReplyQuotes = [.init(conversationID: id, messageID: "quote", text: "Retained Agent quote")]
            }
            if reason == "boundTurn" {
                controller.update(in: id) { $0.threadID = "existing-thread" }
                controller.executions[id]?.state = .working
                controller.executions[id]?.turnID = "original-turn"
            }
            let before = try #require(controller.conversation(id))
            try #require(controller.canSend)
            var receipt: AgentChatDeliveryReceipt?
            controller.send(controller.draftMessage(before), in: before, consumesDraft: true) { receipt = $0 }
            let operation = try #require(controller.executions[id]?.operationTask)

            // The MainActor has not yielded since send enqueued its operation.
            // Invalidation therefore precedes the preparation result without
            // depending on a sleep or hitting the encoder at a particular time.
            switch reason {
            case "cancelled": operation.cancel()
            case "connection": controller.connectionID = UUID()
            case "thread": controller.update(in: id) { $0.threadID = "replacement-thread" }
            case "pending": controller.update(in: id) { $0.pendingMessageID = "newer-pending-message" }
            case "state": controller.executions[id]?.state = .stopping
            case "sendingIdentity": controller.executions[id]?.sendingMessageID = "newer-send"
            case "boundTurn": controller.executions[id]?.turnID = "replacement-turn"
            default: Issue.record("Unknown invalidation case")
            }
            controller.materialErrors[id] = "Current material explanation"
            await operation.value
            let retained = try #require(controller.conversation(id))
            #expect(receipt == .unavailable)
            #expect(controller.materialErrors[id] == "Current material explanation")
            #expect(retained.draft.utf8.elementsEqual(raw.utf8))
            #expect(retained.attachments == before.attachments && retained.draftReplyQuotes == before.draftReplyQuotes)
            #expect(retained.messages.isEmpty && retained.queuedMessages.isEmpty)
            #expect(retained.lastRunStatus != .uncertain)
            #expect(!FileManager.default.fileExists(atPath: controller.runtimeHome.appendingPathComponent("last-turn.json").path))
            if reason == "boundTurn" {
                #expect(controller.executions[id]?.recovery == .turnEnded)
            } else {
                #expect(controller.executions[id]?.error == nil)
            }
            if reason == "pending" { #expect(retained.pendingMessageID == "newer-pending-message") }
            if reason == "sendingIdentity" { #expect(controller.executions[id]?.sendingMessageID == "newer-send") }
            controller.connectionID = originalConnection
        }
    }

    @MainActor
    @Test("A current oversized send retains the exact draft and never attempts delivery", .timeLimit(.minutes(1)))
    func budgetRefusalPreservesDraft() async throws {
        try await withController { controller in
            let id = try #require(controller.selectedID)
            let raw = String(repeating: "x", count: 7 * 1_024 * 1_024)
            controller.editDraft(raw)
            try #require(controller.canSend)
            controller.send()
            await controller.executions[id]?.operationTask?.value
            let retained = try #require(controller.conversation(id))
            #expect(controller.materialErrors[id] != nil && controller.executions[id]?.error == nil)
            #expect(retained.draft.utf8.elementsEqual(raw.utf8))
            #expect(retained.messages.isEmpty && retained.pendingMessageID == nil && retained.threadID == nil)
            #expect(retained.lastRunStatus != .uncertain)
            #expect(!FileManager.default.fileExists(atPath: controller.runtimeHome.appendingPathComponent("last-turn.json").path))
        }
    }

    @MainActor
    @Test("An old send cannot clear the replacement's queue state or task", .timeLimit(.minutes(1)), arguments: [false, true])
    func replacementOwnsCleanup(reentersFromCompletion: Bool) async throws {
        let replacement = AgentChatMessage(role: .user, text: "Exact next queued request\r\n")
        let gate = PreparationHistoryGate(messageID: replacement.id)
        defer { gate.release() }
        try await withController(saveHistory: { await gate.save($0) }) { controller in
            // Release the existing persistence injection on every failure path
            // before withController closes and drains the connection.
            defer { gate.release() }
            let id = try #require(controller.selectedID)
            let originalDraft = String(repeating: "x", count: 7 * 1_024 * 1_024)
            controller.editDraft(originalDraft)
            controller.update(in: id) { $0.queuedMessages = [replacement] }
            let conversation = try #require(controller.conversation(id))
            var dispatched = false
            controller.send(controller.draftMessage(conversation), in: conversation, consumesDraft: true) { receipt in
                if reentersFromCompletion {
                    #expect(receipt == .unavailable)
                    dispatched = controller.sendQueuedMessage(replacement.id)
                    controller.executions[id]?.pendingQueueAdvanceTurnID = "replacement-completion"
                }
            }
            let original = try #require(controller.executions[id]?.operationTask)
            if !reentersFromCompletion {
                // Both calls run before this MainActor task yields. Stop
                // cancels A, and B acquires the actual send owner before A's
                // cancellation can run its deferred cleanup.
                controller.stop(in: id)
                dispatched = controller.sendQueuedMessage(replacement.id)
                controller.executions[id]?.pendingQueueAdvanceTurnID = "replacement-completion"
            }
            await original.value
            #expect(dispatched)
            #expect(controller.executions[id]?.sendingMessageID == replacement.id)
            #expect(controller.executions[id]?.automaticallyAdvancesQueue == true)
            #expect(controller.executions[id]?.pendingQueueAdvanceTurnID == "replacement-completion")
            let currentOperation = try #require(controller.executions[id]?.operationTask)
            #expect(!currentOperation.isCancelled)
            #expect(controller.conversation(id)?.draft.utf8.elementsEqual(originalDraft.utf8) == true)
            gate.release()
            await currentOperation.value
            let retained = try #require(controller.conversation(id))
            let trace = try JSONDecoder().decode(
                MCPJSONValue.self, from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-turn.json")))
            #expect(trace.objectValue?["clientUserMessageId"]?.stringValue == replacement.id)
            #expect(retained.messages.contains { $0.id == replacement.id && $0.turnID != nil })
            #expect(retained.messages.allSatisfy { $0.text != originalDraft })
            #expect(retained.pendingMessageID == nil && retained.draft.utf8.elementsEqual(originalDraft.utf8))
        }
    }

    @MainActor
    @Test("An ordinary send still delivers exact Unicode and newline bytes", .timeLimit(.minutes(1)))
    func ordinarySend() async throws {
        try await withController { controller in
            let id = try #require(controller.selectedID)
            let raw = "Exact 中文 e\u{301} \"quote\" \\ slash\r\nsecond line\r\n"
            controller.editDraft(raw)
            controller.send()
            await controller.executions[id]?.operationTask?.value
            let retained = try #require(controller.conversation(id))
            let trace = try JSONDecoder().decode(
                MCPJSONValue.self, from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-turn.json")))
            let delivered = try #require(trace.objectValue?["input"]?.arrayValue?.first?.objectValue?["text"]?.stringValue)
            let user = try #require(retained.messages.first { $0.role == .user })
            #expect(delivered.utf8.elementsEqual(raw.utf8) && user.text.utf8.elementsEqual(raw.utf8))
            #expect(trace.objectValue?["clientUserMessageId"]?.stringValue == user.id)
            #expect(retained.draft.isEmpty && retained.pendingMessageID == nil && user.turnID != nil)
            #expect(controller.materialErrors[id] == nil && controller.executions[id]?.error == nil)
        }
    }

    @MainActor
    private func withController(
        saveHistory: (@MainActor ([AgentChatConversation]) async throws -> Void)? = nil,
        _ body: (AgentChatController) async throws -> Void
    ) async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/chat-input-preparation-tests/\(UUID())")
        let executable = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        defer { try? FileManager.default.removeItem(at: root) }
        let triptychID = UUID()
        let controller = fixtureChatControllerWithAdmission(
            triptychID: triptychID, root: root,
            workspaceDirectory: { try agentChatFixtureWorkspace(root: root, triptychID: triptychID) },
            saveHistory: saveHistory
        ) { request, _ in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        do {
            try #require(await controller.waitUntilLoaded())
            controller.connect(executable: executable, home: controller.runtimeHome, helper: executable)
            try #require(await controller.waitUntilReady())
            try await body(controller)
            await controller.disconnect()
        } catch {
            await controller.disconnect()
            throw error
        }
    }
}

/// Holds only the replacement's existing save-history boundary, so it cannot
/// finish and erase the queue facts being checked while A completes cleanup.
@MainActor
private final class PreparationHistoryGate {
    let messageID: String
    private var isReleased = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(messageID: String) { self.messageID = messageID }

    func save(_ conversations: [AgentChatConversation]) async {
        guard !isReleased, conversations.contains(where: { $0.messages.contains { $0.id == messageID } }) else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func release() {
        isReleased = true
        let waiting = continuations
        continuations.removeAll()
        for continuation in waiting { continuation.resume() }
    }
}
