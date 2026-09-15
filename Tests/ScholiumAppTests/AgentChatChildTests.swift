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
        let parent = fixtureChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await wait { parent.isLoaded }
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        parent.connect(executable: fixture, home: parent.runtimeHome, helper: fixture)
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
        parent.editDraft("Keep the ordinary conversation draft")
        parent.newConversation()
        let visible = parent.selectedID
        nested.refresh()
        try await wait { !nested.isWorking }
        #expect(nested.snapshot?.metadata.parentID == child.childID)
        #expect(nested.canInspectReports)
        #expect(nested.messages.contains { $0.value.text.contains("第二页第三段") })
        #expect(parent.selectedID == visible && parent.conversations.count == 2 && parent.owns(token: token))
        #expect(parent.conversations.first { $0.id == owner }?.draft == "Keep the ordinary conversation draft")
        let returningReport = try #require(nested.messages.first { $0.value.activity?.delegation != nil })
        let returning = try #require(nested.reportedAgent(targetID: child.childID, messageID: returningReport.id))
        #expect(returning.parentID == child.parentID && returning.hasParent)
        returning.openParent()
        #expect(parent.selectedID == owner && parent.owns(token: token))
        parent.select(try #require(visible))
        returning.cancel()
        let unrelated = try #require(child.reportedAgent(targetID: "unrelated-report-target", messageID: report.id))
        unrelated.refresh()
        try await wait { !unrelated.isWorking }
        #expect(unrelated.snapshot == nil && unrelated.error != nil && !unrelated.canStop)
        #expect(parent.approvals.isEmpty && parent.conversations.count == 2)
        nested.cancel()
        #expect(!nested.canInspectReports && !nested.hasParent)
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

    @Test("A turn ending before Stop preserves access to earlier paginated history")
    func paginationAfterChangedTurn() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/child-stop-pagination-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (parent, child) = try await make(root, prompt: "hold delegation paginated-child")
        let turn = try #require(child.snapshot?.activeTurnID)
        let cursor = try #require(child.snapshot?.page.nextCursor)
        child.loadEarlier()
        try await wait { !child.isWorking }
        #expect(child.snapshot?.page.turns.count == 27 && child.snapshot?.page.nextCursor == nil)

        try Data().write(to: parent.runtimeHome.appendingPathComponent("confirm-child-stop"))
        child.stop()
        try await wait { !child.isWorking }
        #expect(child.error == .changedTurn && child.snapshot?.confirmsEnd(of: turn) == true)
        #expect(child.snapshot?.page.turns.count == 25 && child.snapshot?.page.nextCursor == cursor)
        #expect(!FileManager.default.fileExists(atPath: parent.runtimeHome.appendingPathComponent("child-interrupt.json").path))

        child.loadEarlier()
        try await wait { !child.isWorking }
        #expect(child.error == nil)
        #expect(child.snapshot?.page.turns.count == 27 && child.snapshot?.page.nextCursor == nil)
        child.cancel()
        await parent.disconnect()
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

    @Test("Inspecting and closing a child preserves the ordinary draft, materials and selected conversation")
    func inspectionPreservesInput() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/child-input-preservation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (parent, child) = try await make(root)
        let owner = try #require(parent.selectedID)
        let token = try #require(parent.token)
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
        child.refresh()
        try await wait { !child.isWorking }
        child.cancel()
        let updated = try #require(parent.conversations.first { $0.id == owner })
        #expect(updated.draft == ordinary.draft && updated.attachments == ordinary.attachments && updated.selectedMethods == ordinary.selectedMethods)
        #expect(updated.messages == ordinary.messages && updated.pendingMessageID == ordinary.pendingMessageID)
        #expect(parent.selectedID == visible && parent.selected?.draft == "Visible unrelated draft" && parent.owns(token: token))
        #expect(!FileManager.default.fileExists(atPath: parent.runtimeHome.appendingPathComponent("unexpected-child-resume").path))
        await parent.disconnect()
    }

    @Test("Closing a child leaves admitted ordinary input and uncertain delivery with the conversation")
    func closingPreservesOrdinaryInput() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/child-ordinary-input-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (parent, child) = try await make(root)
        let owner = try #require(parent.selectedID)
        try await wait { parent.selected?.pendingMessageID == nil }
        try Data().write(to: parent.runtimeHome.appendingPathComponent("hold-parent-input"))
        parent.editDraft("Exact ordinary request")
        parent.send()
        try await wait { parent.selected?.pendingMessageID != nil && parent.selected?.draft.isEmpty == true }
        parent.editDraft("Next unsent ordinary draft")
        child.cancel()
        #expect(parent.selected?.pendingMessageID != nil && !child.canStop)
        await parent.disconnect()
        let stored = try await AgentChatStorage(root: root.appendingPathComponent(parent.triptychID.uuidString)).load()
        let conversation = try #require(stored.first { $0.id == owner })
        #expect(conversation.pendingMessageID != nil && conversation.draft == "Next unsent ordinary draft")
        #expect(conversation.messages.filter { $0.text == "Exact ordinary request" }.count == 1)
        let reopened = fixtureChatController(triptychID: parent.triptychID, root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await wait { reopened.isLoaded }
        #expect(reopened.conversations.first { $0.id == owner }?.pendingMessageID == conversation.pendingMessageID)
        #expect(reopened.connectionState == .disconnected)
        await reopened.disconnect()
    }

    @Test("Retained child data stays inert while historical target references keep their branch boundary")
    func retainedChildData() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/retained-child-data-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (parent, child) = try await make(root)
        let owner = try #require(parent.selectedID)
        parent.stop()
        try await wait { parent.state == .ready && parent.canBranch }
        child.cancel()
        await parent.disconnect()

        let storage = AgentChatStorage(root: root.appendingPathComponent(parent.triptychID.uuidString))
        var stored = try await storage.load()
        let index = try #require(stored.firstIndex { $0.id == owner })
        let requestIndex = try #require(stored[index].messages.firstIndex { $0.role == .user })
        stored[index].childDrafts = [child.childID: "Retained unsent text"]
        stored[index].messages[requestIndex].coordinationTarget = .init(
            parentThreadID: child.parentID, childThreadID: child.childID, name: "Original child")
        let request = stored[index].messages[requestIndex]
        try await storage.save(stored)

        let reopened = fixtureChatController(triptychID: parent.triptychID, root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await wait { reopened.isLoaded }
        reopened.select(owner)
        let retained = try #require(reopened.selected)
        #expect(retained.childDrafts == stored[index].childDrafts && retained.messages == stored[index].messages)
        #expect(!AgentChatListFilter.hasDraft(retained))
        #expect(AgentChatSearch.passage(in: request, query: child.childID) != nil)
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        reopened.connect(executable: fixture, home: reopened.runtimeHome, helper: fixture)
        try await wait { reopened.account != nil && reopened.state == .ready && reopened.canBranch }
        reopened.editInNewBranch(request.id)
        try await wait { reopened.selectedID != owner && !reopened.hasActiveExecutions }
        #expect(reopened.selected?.draft == request.text && reopened.selected?.draftCoordinationTarget == request.coordinationTarget)
        #expect(!reopened.canSend && reopened.selected?.childDrafts.isEmpty == true)
        let lastInput = try Data(contentsOf: reopened.runtimeHome.appendingPathComponent("last-turn.json"))
        reopened.send()
        #expect(try Data(contentsOf: reopened.runtimeHome.appendingPathComponent("last-turn.json")) == lastInput)
        reopened.removeDraftCoordinationTarget()
        #expect(reopened.canSend && reopened.selected?.draft == request.text)
        await reopened.disconnect()
        let persisted = try await storage.load()
        #expect(persisted.first { $0.id == owner }?.childDrafts == stored[index].childDrafts)
        #expect(persisted.first { $0.id == owner }?.messages.contains { $0.id == request.id && $0.coordinationTarget == request.coordinationTarget } == true)
    }
}
