import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Child Agent inspection and interruption", .serialized) @MainActor
struct AgentChatChildTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !predicate() {
            try #require(ContinuousClock.now < deadline, "Child Agent fixture did not reach its expected state")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private func make(_ root: URL, prompt: String = "hold delegation") async throws -> (AgentChatController, AgentChatChildController) {
        let parent = AgentChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await wait { parent.isLoaded }
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        parent.connect(executable: fixture, home: parent.runtimeHome, cli: fixture)
        try await wait { parent.account != nil && parent.state == .ready }
        parent.editDraft(prompt)
        parent.send()
        try await wait { parent.selected?.messages.contains { $0.activity?.delegation?.operation == .spawnAgent } == true }
        let message = try #require(parent.selected?.messages.first { $0.activity?.delegation?.operation == .spawnAgent })
        let target = try #require(message.activity?.delegation?.targets.first?.id)
        let conversationID = try #require(parent.selectedID)
        let child = try #require(parent.childController(targetID: target, messageID: message.id, in: conversationID))
        child.refresh()
        try await wait { !child.isWorking && child.snapshot != nil }
        return (parent, child)
    }

    @Test("Nested paginated child history opens without resuming or admitting another conversation")
    func reading() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/child-reading-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (parent, child) = try await make(root, prompt: "hold delegation nested-child paginated-child")
        #expect(child.snapshot?.page.turns.count == 25 && child.snapshot?.page.nextCursor != nil && child.canStop)
        #expect(child.messages.contains { $0.value.text.contains("第一处原文") })
        #expect(!child.messages.contains { $0.value.text.contains("synthetic-private-reasoning") })
        let request = try #require(child.messages.first { $0.value.role == .user })
        #expect(request.hasAdditionalMaterial && request.value.text == "核对所选原文，保留页码。")
        #expect(
            child.messages.contains {
                $0.value.activity?.kind == .read
                    && $0.value.activity?.detail.contains("scholium_read_note") == true && $0.value.changeID == nil
            })
        #expect(parent.conversations.count == 1 && parent.approvals.isEmpty)
        child.loadEarlier()
        try await wait { !child.isWorking }
        #expect(child.snapshot?.page.turns.count == 27 && child.snapshot?.page.nextCursor == nil)
        let report = try #require(parent.selected?.messages.first { $0.activity?.delegation != nil })
        let conversationID = try #require(parent.selectedID)
        let unrelated = try #require(parent.childController(targetID: "unrelated", messageID: report.id, in: conversationID))
        unrelated.refresh()
        try await wait { !unrelated.isWorking }
        #expect(unrelated.snapshot == nil && unrelated.error != nil && !unrelated.canStop)
        #expect(!FileManager.default.fileExists(atPath: parent.runtimeHome.appendingPathComponent("unexpected-child-resume").path))
        child.cancel()
        unrelated.cancel()
        await parent.disconnect()
    }

    @Test("Nested reports retain the original conversation scope and reject invented or unrelated targets")
    func nestedReports() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/nested-report-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (parent, child) = try await make(root, prompt: "hold delegation nested-report")
        let owner = try #require(parent.selectedID)
        let token = try #require(parent.token)
        let report = try #require(child.messages.first { $0.value.activity?.delegation != nil })
        let target = child.childID + "-reader"
        #expect(child.reportedAgent(targetID: "invented", messageID: report.id) == nil)
        #expect(child.reportedAgent(targetID: target, messageID: "invented") == nil)
        let nested = try #require(child.reportedAgent(targetID: target, messageID: report.id))
        #expect(nested.snapshot == nil && nested.parentID == child.parentID && nested.parentTitle == child.parentTitle)
        #expect(!nested.canInspectReports)
        child.editDraft("Keep the first Agent draft")
        parent.newConversation()
        let visible = parent.selectedID
        nested.refresh()
        try await wait { !nested.isWorking }
        #expect(nested.snapshot?.metadata.parentID == child.childID)
        #expect(nested.canInspectReports)
        #expect(nested.messages.contains { $0.value.text.contains("第二页第三段") })
        #expect(parent.selectedID == visible && parent.conversations.count == 2 && parent.owns(token: token))
        nested.editDraft("hold: Recheck this exact paragraph")
        nested.askParent()
        try await wait { nested.receipt != nil }
        #expect(nested.receipt == .received && nested.draft.isEmpty && child.draft == "Keep the first Agent draft")
        let sent = try #require(parent.conversations.first { $0.id == owner }?.messages.last { $0.role == .user })
        #expect(sent.coordinationTarget?.childThreadID == target && sent.coordinationTarget?.parentThreadID == child.parentID)
        #expect(parent.selectedID == visible && parent.owns(token: token))
        let returningReport = try #require(nested.messages.first { $0.value.activity?.delegation != nil })
        let returning = try #require(nested.reportedAgent(targetID: child.childID, messageID: returningReport.id))
        #expect(returning.parentID == child.parentID && returning.draft == child.draft)
        returning.cancel()
        let unrelated = try #require(child.reportedAgent(targetID: "unrelated-report-target", messageID: report.id))
        unrelated.refresh()
        try await wait { !unrelated.isWorking }
        #expect(unrelated.snapshot == nil && unrelated.error != nil && !unrelated.canSend && !unrelated.canStop)
        #expect(parent.approvals.isEmpty && parent.conversations.count == 2)
        nested.cancel()
        #expect(!nested.canInspectReports)
        #expect(nested.reportedAgent(targetID: child.childID, messageID: returningReport.id) == nil)
        await parent.disconnect()
        #expect(!child.canInspectReports)
        #expect(child.reportedAgent(targetID: target, messageID: report.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: parent.runtimeHome.appendingPathComponent("unexpected-child-resume").path))
        child.cancel()
        unrelated.cancel()
    }

    @Test("Stop targets the observed child turn and waits for confirmation without stopping its parent")
    func interruption() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/child-stop-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (parent, child) = try await make(root)
        let owner = try #require(parent.selectedID)
        let token = try #require(parent.token)
        let turn = try #require(child.snapshot?.activeTurnID)
        parent.newConversation()
        let visible = parent.selectedID
        try Data().write(to: parent.runtimeHome.appendingPathComponent("hold-child-stop"))
        child.stop()
        try await wait { !child.isWorking }
        #expect(child.pendingStop == turn && !child.canStop && child.snapshot?.activeTurnID == turn)
        let response = try JSONDecoder().decode(MCPJSONValue.self, from: Data(contentsOf: parent.runtimeHome.appendingPathComponent("child-interrupt.json")))
        #expect(response.objectValue?["threadId"]?.stringValue == child.childID && response.objectValue?["turnId"]?.stringValue == turn)
        child.stop()
        #expect(try String(contentsOf: parent.runtimeHome.appendingPathComponent("child-interrupt-count"), encoding: .utf8) == "1")
        try Data().write(to: parent.runtimeHome.appendingPathComponent("confirm-child-stop"))
        child.refresh()
        try await wait { !child.isWorking }
        #expect(child.pendingStop == nil && child.snapshot?.confirmsEnd(of: turn) == true && !child.canStop)
        #expect(parent.state(for: owner) == .working && parent.owns(token: token) && parent.selectedID == visible)
        await parent.disconnect()
        #expect(child.isDisconnected && !child.canStop)
        child.cancel()
    }

    @Test("A stale turn or closed inspection cannot issue an interruption")
    func staleAndCancelled() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/child-stale-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (parent, child) = try await make(root)
        let turn = child.snapshot?.activeTurnID
        try Data().write(to: parent.runtimeHome.appendingPathComponent("rotate-child-turn"))
        child.stop()
        try await wait { !child.isWorking }
        #expect(child.snapshot?.activeTurnID != turn && child.error != nil && !child.canStop)
        #expect(!FileManager.default.fileExists(atPath: parent.runtimeHome.appendingPathComponent("child-interrupt.json").path))
        let count = try String(contentsOf: parent.runtimeHome.appendingPathComponent("child-read-count"), encoding: .utf8)
        try Data().write(to: parent.runtimeHome.appendingPathComponent("hold-child-read"))
        child.refresh()
        try await wait { (try? String(contentsOf: parent.runtimeHome.appendingPathComponent("child-read-count"), encoding: .utf8)) != count }
        child.cancel()
        #expect(!child.isWorking && !child.canStop && parent.state == .working)
        await parent.disconnect()
    }

    @Test("Ask Parent preserves ordinary materials and selection, and branches retain the exact target")
    func coordination() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/child-coordination-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (parent, child) = try await make(root)
        let owner = try #require(parent.selectedID)
        let token = try #require(parent.token)
        let parentThread = try #require(parent.selected?.threadID)
        parent.editDraft("Unsent ordinary draft")
        let material = AgentChatAttachment(
            noteID: UUID(), vaultID: UUID(), relativePath: "Unsent.md",
            text: "Unsubmitted material", fingerprint: .init(content: "Unsubmitted material"))
        parent.attach(material)
        try await wait { parent.capabilities.hasMethods && !parent.capabilities.isRefreshing }
        let method = try #require(parent.capabilities.methods.first { !$0.isProtected })
        parent.toggleMethod(method.selection)
        let ordinary = try #require(parent.selected)
        parent.newConversation()
        parent.editDraft("Visible unrelated draft")
        let visible = parent.selectedID
        child.editDraft("hold\n请核对第二处引文，保留原文。")
        #expect(child.canSend)
        child.askParent()
        try await wait { child.receipt != nil }
        #expect(child.receipt == .received && child.draft.isEmpty && parent.selectedID == visible)
        #expect(parent.selected?.draft == "Visible unrelated draft" && parent.owns(token: token))
        let updated = try #require(parent.conversations.first { $0.id == owner })
        #expect(updated.draft == ordinary.draft && updated.attachments == ordinary.attachments && updated.selectedMethods == ordinary.selectedMethods)
        let adjustment = try #require(updated.messages.last { $0.role == .user })
        #expect(adjustment.text == "hold\n请核对第二处引文，保留原文。" && adjustment.attachments.isEmpty && adjustment.methods == nil)
        #expect(adjustment.coordinationTarget?.childThreadID == child.childID && adjustment.coordinationTarget?.parentThreadID == parentThread)
        let input = try JSONDecoder().decode(MCPJSONValue.self, from: Data(contentsOf: parent.runtimeHome.appendingPathComponent("last-turn.json"))).objectValue
        #expect(input?["threadId"]?.stringValue == parentThread && input?["expectedTurnId"]?.stringValue == adjustment.turnID)
        let text = try #require(input?["input"]?.arrayValue?.first?.objectValue?["text"]?.stringValue)
        #expect(text.hasPrefix(adjustment.text) && text.contains(child.childID) && !text.contains("Unsubmitted material"))
        #expect(AgentChatSearch.passage(in: adjustment, query: child.childID) != nil)
        parent.stop(in: owner)
        try await wait { parent.state(for: owner) == .ready }
        child.editDraft("再核对一次页码。")
        child.askParent()
        try await wait { child.receipt == .received && parent.state(for: owner) == .ready }
        let request = try #require(parent.conversations.first { $0.id == owner }?.messages.last { $0.role == .user })
        child.openParent()
        try await wait { parent.canBranch }
        parent.editInNewBranch(request.id)
        try await wait { parent.selectedID != owner && !parent.hasActiveExecutions }
        #expect(parent.selected?.draft == request.text && parent.selected?.draftCoordinationTarget == request.coordinationTarget)
        #expect(parent.selected?.childDrafts.isEmpty == true && !parent.canSend)
        let lastInput = try Data(contentsOf: parent.runtimeHome.appendingPathComponent("last-turn.json"))
        parent.send()
        #expect(try Data(contentsOf: parent.runtimeHome.appendingPathComponent("last-turn.json")) == lastInput)
        parent.removeDraftCoordinationTarget()
        #expect(parent.canSend && parent.selected?.draft == request.text)
        child.editDraft("Retained child draft")
        child.cancel()
        await parent.disconnect()
        let stored = try await AgentChatStorage(root: root.appendingPathComponent(parent.triptychID.uuidString)).load()
        #expect(stored.first { $0.id == owner }?.childDrafts[child.childID] == "Retained child draft")
        #expect(stored.first { $0.id == owner }?.messages.contains { $0.coordinationTarget == request.coordinationTarget } == true)
    }

    @Test("Closing a child does not cancel admitted parent input, and unknown delivery is retained without replay")
    func coordinationUncertainty() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/child-receipt-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (parent, child) = try await make(root)
        let owner = try #require(parent.selectedID)
        try Data().write(to: parent.runtimeHome.appendingPathComponent("hold-parent-input"))
        child.editDraft("Exact adjustment")
        child.askParent()
        try await wait { parent.selected?.pendingMessageID != nil && child.draft.isEmpty }
        child.editDraft("Next unsent adjustment")
        child.cancel()
        #expect(parent.selected?.pendingMessageID != nil && !child.canSend)
        await parent.disconnect()
        try await wait { child.receipt == .unconfirmed }
        let stored = try await AgentChatStorage(root: root.appendingPathComponent(parent.triptychID.uuidString)).load()
        let conversation = try #require(stored.first { $0.id == owner })
        #expect(conversation.pendingMessageID != nil && conversation.childDrafts[child.childID] == "Next unsent adjustment")
        #expect(conversation.messages.filter { $0.text == "Exact adjustment" }.count == 1)
        let reopened = AgentChatController(triptychID: parent.triptychID, root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await wait { reopened.isLoaded }
        #expect(reopened.conversations.first { $0.id == owner }?.pendingMessageID == conversation.pendingMessageID)
        #expect(reopened.connectionState == .disconnected)
        await reopened.disconnect()
    }

    @Test("A turn ending during input preparation cannot silently start a new execution")
    func completedTargetDuringPreparation() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/input-completed-target-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (parent, child) = try await make(root)
        try await wait { parent.selected?.pendingMessageID == nil }
        let original = try #require(parent.selected)
        let lastInput = try Data(contentsOf: parent.runtimeHome.appendingPathComponent("last-turn.json"))
        try Data().write(to: parent.runtimeHome.appendingPathComponent("complete-parent-before-input"))
        child.editDraft("Keep this additional request")
        child.askParent()
        try await wait { parent.state == .ready }
        parent.refreshQuota()  // Release the pending verification only after completion reached the client.
        try await wait { !parent.isBusy }
        #expect(child.draft == "Keep this additional request")
        #expect(parent.selected?.messages == original.messages)
        #expect(parent.selected?.pendingMessageID == nil)
        #expect(try Data(contentsOf: parent.runtimeHome.appendingPathComponent("last-turn.json")) == lastInput)
        child.cancel()
        await parent.disconnect()
    }

    @Test("A changed ancestry or archived parent cannot consume an adjustment draft")
    func coordinationAdmission() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/child-admission-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (parent, child) = try await make(root)
        let owner = try #require(parent.selectedID)
        let count = parent.selected?.messages.count
        child.editDraft("Do not lose this request")
        try Data().write(to: parent.runtimeHome.appendingPathComponent("unrelated-child-parent"))
        child.askParent()
        try await wait { child.receipt != nil }
        #expect(child.receipt == .unavailable && child.draft == "Do not lose this request")
        #expect(parent.selected?.messages.count == count && parent.selected?.pendingMessageID == nil)
        parent.stop()
        try await wait { parent.state == .ready }
        parent.setArchived(owner, archived: true)
        #expect(!child.canSend && !child.canEdit)
        child.askParent()
        child.editDraft("Must not replace archived draft")
        #expect(child.draft == "Do not lose this request")
        child.cancel()
        await parent.disconnect()
    }
}
