import ScholiumApplication
import ScholiumContracts
import Testing
import Foundation

@Suite("Unified public transcript decoding")
struct CodexChatTranscriptTests {
  @Test("Activity descriptions use public command actions without interpreting shell text")
  func commandActions() throws {
    let raw: [String: MCPJSONValue] = ["type": .string("commandExecution"), "status": .string("inProgress"),
      "command": .string("arbitrary shell text"), "commandActions": .array([.object([
        "type": .string("read"), "path": .string("/fixture/SKILL.md"), "name": .string("SKILL.md")])])]
    let activity = try #require(CodexChatActivity.parse(raw, completed: false))
    #expect(activity.commandAction == .init(kind: .read, target: "/fixture/SKILL.md"))
    #expect(activity.kind == .command && activity.subject == "arbitrary shell text")
    let stored = try JSONDecoder().decode(AgentChatActivity.self, from: JSONEncoder().encode(activity))
    #expect(stored == activity)
    var unknown = raw; unknown["commandActions"] = .array([.object(["type": .string("future")])])
    #expect(CodexChatActivity.parse(unknown, completed: false)?.commandAction == nil)
    unknown["commandActions"] = nil
    #expect(CodexChatActivity.parse(unknown, completed: false)?.commandAction == nil)
  }

  @Test("Live, restored and child history preserve identical public text and phase", arguments: ["commentary", "final_answer", "future-phase", "missing"])
  func messageParity(phase: String) async throws {
    let text = "原文 😀\r\n**保留原样**"
    var item: [String: MCPJSONValue] = ["id": .string("reply"), "type": .string("agentMessage"), "text": .string(text)]
    if phase != "missing" { item["phase"] = .string(phase) }
    let value = turn(items: [.object(item)])
    let event = try #require(try CodexChatTranscript.event([
      "method": .string("item/completed"), "params": .object(["threadId": .string("child"), "turnId": .string("turn"), "item": .object(item)])]))
    guard case .item(let live, _, let context) = event.content else { Issue.record("Expected a public item"); return }
    let history = try CodexChatTranscript.history(.object(["thread": .object([
      "id": .string("child"), "turns": .array([value])])]), threadID: "child")
    let child = try await CodexChatChildReader.load(childID: "child", parentID: "parent") { _, _ in
      .object(["thread": .object(["id": .string("child"), "parentThreadId": .string("parent"),
        "status": .object(["type": .string("idle")]), "turns": .array([value])])])
    }
    #expect(live == history.first?.items.first && live == child.page.turns.first?.items.first)
    #expect(live.content == .assistant(text: text, phase: AgentChatMessage.Phase(rawValue: phase)))
    #expect(context == nil && event.turnID == "turn")
  }

  @Test("Async structured questions retain protocol identity in live and restored history; prose stays prose")
  func asyncQuestions() throws {
    var item: [String: MCPJSONValue] = ["id": .string("call/中文"), "type": .string("agentMessage"),
      "delivery": .string("async"), "text": .string("Summary"), "questions": .array([
        .object(["title": .string("Which passage?"), "options": .array([.string("First"), .string("Second")])]),
        .object(["title": .string("Why?")])])]
    let history = try CodexChatTranscript.turn(turn(items: [.object(item)]), threadID: "thread")
    let questions = try #require(history.items.first?.asyncQuestions)
    #expect(questions.map(\.id) == ["[\"request_user_input_async\",\"call/中文\",0]", "[\"request_user_input_async\",\"call/中文\",1]"])
    #expect(questions[0].allowsOther && questions[1].options.isEmpty)
    let reply = AgentChatQuestionReply(questionItemId: questions[0].id, question: questions[0].prompt, answer: "其他\n答案")
    let encoded = try CodexChatAsyncQuestions.encode([reply])
    #expect(CodexChatAsyncQuestions.decode(encoded) == [reply])
    #expect(CodexChatAsyncQuestions.decode("Quoted " + encoded) == nil)
    item["delivery"] = nil
    #expect(try CodexChatTranscript.turn(turn(items: [.object(item)]), threadID: "thread").items.first?.asyncQuestions == nil)
    item["delivery"] = .string("async"); item["questions"] = .null
    #expect(try CodexChatTranscript.turn(turn(items: [.object(item)]), threadID: "thread").items.first?.asyncQuestions?.first?.id == "call/中文")
    item["questions"] = .array([.object(["title": .string("Choose"), "options": .array([.integer(1)])])])
    #expect(throws: CodexConnectionError.self) { try CodexChatTranscript.turn(turn(items: [.object(item)]), threadID: "thread") }
  }

  @Test("Public identity, private exclusions and tool outcomes do not depend on parent completion")
  func identitiesAndActivities() throws {
    let command: MCPJSONValue = .object(["id": .string("command"), "type": .string("commandExecution"),
      "command": .string("inspect"), "status": .string("inProgress")])
    let user: MCPJSONValue = .object(["id": .string("user"), "type": .string("userMessage"), "clientId": .string("client"),
      "content": .array([.object(["type": .string("text"), "text": .string("exact")]), .object(["type": .string("localImage")])])])
    let privateItem: MCPJSONValue = .object(["id": .string("private"), "type": .string("reasoning"), "text": .string("must not escape")])
    let parsed = try CodexChatTranscript.turn(turn(items: [user, command, privateItem]), threadID: "thread")
    #expect(parsed.items.count == 2 && parsed.messageIDs.contains("client") && !parsed.messageIDs.contains("private"))
    #expect(parsed.items.first?.content == .user(text: "exact", hasAdditionalMaterial: true))
    guard case .activity(let activity) = parsed.items.last?.content else { Issue.record("Expected tool activity"); return }
    #expect(activity.status == .running && parsed.status == .completed)
    let live = try #require(try CodexChatTranscript.event(["method": .string("item/started"), "params": .object([
      "threadId": .string("thread"), "turnId": .string("turn"), "item": command])]))
    guard case .item(let item, _, _) = live.content else { Issue.record("Expected live tool"); return }
    #expect(item == parsed.items.last)
    #expect(try CodexChatTranscript.event(["method": .string("item/completed"), "params": .object([
      "threadId": .string("thread"), "item": privateItem])]) == nil)
  }

  @Test("Malformed attributed history is rejected completely, including duplicate identities and unknown outcomes")
  func invalidHistory() throws {
    let good: MCPJSONValue = .object(["id": .string("reply"), "type": .string("agentMessage"), "text": .string("valid")])
    let bad: MCPJSONValue = .object(["id": .string("bad"), "type": .string("agentMessage")])
    for items in [[good, bad], [good, good], [.object(["id": .string("tool"), "type": .string("commandExecution"), "status": .string("future-outcome")])]] {
      #expect(throws: CodexConnectionError.self) { try CodexChatTranscript.turn(turn(items: items), threadID: "thread") }
    }
    #expect(throws: CodexConnectionError.self) {
      try CodexChatTranscript.turns([turn(items: [good]), turn(items: [good])], threadID: "thread")
    }
    #expect(throws: CodexConnectionError.self) {
      try CodexChatTranscript.event(["method": .string("turn/completed"), "params": .object([
        "threadId": .string("thread"), "turn": .object(["status": .string("completed"), "items": .array([])])])])
    }
    #expect(throws: CodexConnectionError.self) {
      try CodexChatTranscript.history(.object(["thread": .object(["id": .string("other"), "turns": .array([])])]), threadID: "thread")
    }
    #expect(throws: CodexConnectionError.self) {
      try CodexChatTranscript.turn(turn(items: [.object(["id": .string("command"), "type": .string("commandExecution"),
        "status": .string("interrupted")])]), threadID: "thread")
    }
  }

  @Test("Paginated storage can return a complete full-item history, while summary items remain unavailable")
  func historyCoverage() throws {
    let value: MCPJSONValue = .object(["id": .string("report"), "type": .string("subAgentActivity"),
      "kind": .string("interacted"), "agentThreadId": .string("child"), "agentPath": .string("/root/child")])
    let history: MCPJSONValue = .object(["thread": .object(["id": .string("branch"),
      "historyMode": .string("paginated"), "turns": .array([turn(items: [value])])])])
    let parsed = try CodexChatTranscript.history(history, threadID: "branch", delegationOrigins: ["runtime:report": "original"])
    guard case .activity(let activity) = parsed.first?.items.first?.content else { Issue.record("Expected public report"); return }
    #expect(activity.delegation?.senderThreadID == "original")
    #expect(throws: CodexConnectionError.self) {
      try CodexChatTranscript.turns([.object(["id": .string("turn"), "status": .string("completed"),
        "itemsView": .string("summary"), "items": .array([value])])], threadID: "branch")
    }
  }

  @Test("Public turn timing uses seconds and milliseconds consistently, while malformed optional timing never blocks prose")
  func turnTiming() throws {
    let item: MCPJSONValue = .object(["id": .string("reply"), "type": .string("agentMessage"), "text": .string("Answer")])
    var value = try #require(turn(items: [item]).objectValue)
    value["startedAt"] = .integer(1_000); value["completedAt"] = .integer(1_038); value["durationMs"] = .integer(38_500)
    let parsed = try CodexChatTranscript.turn(.object(value), threadID: "thread")
    #expect(parsed.timing.startedAt == Date(timeIntervalSince1970: 1_000))
    #expect(parsed.timing.completedSeconds == 38)
    let history: MCPJSONValue = .object(["thread": .object(["id": .string("thread"), "turns": .array([.object(value)])])])
    #expect(try CodexChatTranscript.history(history, threadID: "thread").first?.timing == parsed.timing)
    value["durationMs"] = .integer(-1); value["completedAt"] = .integer(900)
    let invalid = try CodexChatTranscript.turn(.object(value), threadID: "thread")
    #expect(invalid.items.count == 1 && invalid.timing.completedSeconds == nil)
  }

  private func turn(items: [MCPJSONValue]) -> MCPJSONValue {
    .object(["id": .string("turn"), "status": .string("completed"), "items": .array(items)])
  }

  @Test("Current runtime turn acknowledgements can omit items without becoming a history snapshot")
  func lifecycleMetadata() throws {
    for coverage in ["notLoaded", "summary"] {
      let metadata: MCPJSONValue = .object(["id": .string("turn"), "status": .string("inProgress"),
        "itemsView": .string(coverage), "items": .array([])])
      let turn = try CodexChatTranscript.turn(metadata, threadID: "thread")
      #expect(turn.id == "turn" && turn.status == .inProgress && turn.items.isEmpty)
      let event = try #require(try CodexChatTranscript.event(["method": .string("turn/started"),
        "params": .object(["threadId": .string("thread"), "turn": metadata])]))
      guard case .turnStarted(let started) = event.content else { Issue.record("Expected lifecycle metadata"); return }
      #expect(started == turn)
      #expect(throws: CodexConnectionError.self) { try CodexChatTranscript.turns([metadata], threadID: "thread") }
    }
  }
}
