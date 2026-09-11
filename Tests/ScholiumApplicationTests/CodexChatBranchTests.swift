import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("Runtime conversation branches")
struct CodexChatBranchTests {
    private func history(_ turns: [(String, String)]) -> MCPJSONValue {
        .object([
            "thread": .object([
                "id": .string("source"),
                "turns": .array(
                    turns.map {
                        .object(["id": .string($0.0), "status": .string($0.1), "items": .array([])])
                    }),
            ])
        ])
    }

    @Test("A branch boundary must be a known ended turn on the exact runtime thread")
    func boundaries() throws {
        let result = history([("one", "completed"), ("two", "interrupted"), ("three", "inProgress")])
        #expect(try CodexChatBranch.turnIDs(in: result, threadID: "source", through: "two") == ["one", "two"])
        for target in ["three", "missing"] {
            #expect(throws: CodexConnectionError.self) {
                try CodexChatBranch.turnIDs(in: result, threadID: "source", through: target)
            }
        }
        #expect(throws: CodexConnectionError.self) {
            try CodexChatBranch.turnIDs(in: result, threadID: "another", through: "one")
        }
        #expect(throws: CodexConnectionError.self) {
            try CodexChatBranch.turnIDs(
                in: history([("one", "completed"), ("one", "completed"), ("two", "completed")]),
                threadID: "source", through: "two")
        }
    }

    @Test("Projection retains exact selected history and original receipts, never unsent input or pending authority")
    func projection() throws {
        var source = AgentChatConversation(triptychID: UUID())
        source.threadID = "source"
        source.permission = .fullAccess
        source.preferences = .init(model: "model", effort: "high", webSearch: .live)
        source.draft = "Unsent interpretation"
        let material = AgentChatAttachment(
            noteID: UUID(), vaultID: UUID(), relativePath: "原文.md",
            text: "Exact\r\nquotation 😀", fingerprint: .init(content: "Exact\r\nquotation 😀"))
        source.attachments = [material]
        var question = AgentChatMessage(role: .user, text: "Compare", attachments: [material])
        question.turnID = "one"
        let receipt = UUID()
        var change = AgentChatMessage(
            role: .operation, text: "", changeID: receipt,
            activity: .init(kind: .update, status: .completed, source: .scholium))
        change.turnID = "one"
        var later = AgentChatMessage(role: .assistant, text: "Later interpretation")
        later.turnID = "two"
        source.messages = [question, change, later]
        let original = source
        let branch = try CodexChatBranch.project(source: source, threadID: "child", retaining: ["one"], boundary: "one", position: .through)
        #expect(branch.messages == [question, change] && branch.messages.last?.changeID == receipt)
        #expect(branch.id != source.id && branch.threadID == "child" && branch.triptychID == source.triptychID)
        #expect(branch.branchOrigin == .init(conversationID: source.id, turnID: "one"))
        #expect(branch.permission == source.permission && branch.preferences == source.preferences)
        #expect(branch.draft.isEmpty && branch.attachments.isEmpty && branch.pendingMessageID == nil && branch.contextUsage == nil)
        #expect(source == original)
        let empty = try CodexChatBranch.project(
            source: source, threadID: "empty",
            retaining: [], boundary: "one", position: .before)
        #expect(empty.messages.isEmpty && empty.branchOrigin?.position == .before)
        try CodexChatBranch.confirm(history([]), threadID: "source", expected: [])
        #expect(throws: CodexConnectionError.self) {
            try CodexChatBranch.confirm(history([("one", "completed")]), threadID: "source", expected: [])
        }
        #expect(throws: CodexConnectionError.self) {
            try CodexChatBranch.project(source: source, threadID: "child", retaining: ["one"], boundary: "one", position: .before)
        }
        source.messages.append(.init(role: .assistant, text: "Unknown boundary"))
        #expect(throws: CodexConnectionError.self) {
            try CodexChatBranch.project(source: source, threadID: "child", retaining: ["one"], boundary: "one", position: .through)
        }
    }
}
