import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("Verified child history")
struct CodexChatChildReaderTests {
  @Test("Read follows exact ancestry and excludes private reasoning without resuming")
  func ancestry() async throws {
    let fixture = ChildReadFixture(parents: ["child": "middle", "middle": "root"])
    let snapshot = try await CodexChatChildReader.load(childID: "child", parentID: "root", request: { try await fixture.request($0, $1) })
    #expect(snapshot.metadata.parentID == "middle" && snapshot.activeTurnID == "active")
    #expect(snapshot.page.turns.first?.items.count == 1)
    #expect(snapshot.page.turns.first?.items.first?.content == .assistant(text: "Public reply", phase: nil))
    #expect(await fixture.methods == ["thread/read", "thread/read", "thread/read"])
    for parents in [["child": "child"], ["child": "middle", "middle": "child"], ["child": "unrelated"]] {
      let invalid = ChildReadFixture(parents: parents)
      await #expect(throws: CodexConnectionError.self) {
        try await CodexChatChildReader.load(childID: "child", parentID: "root", request: { try await invalid.request($0, $1) })
      }
    }
  }

  @Test("Pagination retains order and refuses duplicate turns or incomplete item projections")
  func pages() async throws {
    let fixture = ChildReadFixture(parents: ["child": "root"], paginated: true)
    let snapshot = try await CodexChatChildReader.load(childID: "child", parentID: "root", request: { try await fixture.request($0, $1) })
    #expect(snapshot.page.nextCursor == "older" && snapshot.page.turns.map(\.id) == ["recent", "active"])
    let page = try await CodexChatChildReader.older(childID: "child", cursor: "older", request: { try await fixture.request($0, $1) })
    let full = try CodexChatChildReader.prepending(page, to: snapshot)
    #expect(full.page.turns.map(\.id) == ["earlier", "recent", "active"] && full.page.nextCursor == nil)
    #expect(throws: CodexConnectionError.self) { try CodexChatChildReader.prepending(page, to: full) }
    await fixture.useSummary()
    await #expect(throws: CodexConnectionError.self) {
      try await CodexChatChildReader.older(childID: "child", cursor: nil, request: { try await fixture.request($0, $1) })
    }
  }
}

private actor ChildReadFixture {
  let parents: [String: String]
  let paginated: Bool
  var methods: [String] = []
  var summary = false
  init(parents: [String: String], paginated: Bool = false) { self.parents = parents; self.paginated = paginated }
  func useSummary() { summary = true }
  func request(_ method: String, _ params: [String: MCPJSONValue]) throws -> MCPJSONValue {
    methods.append(method)
    func turn(_ id: String) -> MCPJSONValue {
      .object(["id": .string(id), "status": .string(id == "active" ? "inProgress" : "completed"),
        "itemsView": .string(summary ? "summary" : "full"), "items": .array([
          .object(["id": .string(id + "-private"), "type": .string("reasoning"), "text": .string("Private state")]),
          .object(["id": .string(id + "-public"), "type": .string("agentMessage"), "text": .string("Public reply")])])])
    }
    if method == "thread/turns/list" {
      return .object(["data": .array(params["cursor"] == nil ? [turn("active"), turn("recent")] : [turn("earlier")]),
        "nextCursor": params["cursor"] == nil ? .string("older") : .null])
    }
    guard method == "thread/read", let id = params["threadId"]?.stringValue,
      let parent = parents[id] else { throw CodexConnectionError.invalidMessage }
    return .object(["thread": .object(["id": .string(id), "parentThreadId": .string(parent),
      "historyMode": .string(paginated ? "paginated" : "legacy"),
      "status": .object(["type": .string("active"), "activeFlags": .array([])]),
      "turns": .array(params["includeTurns"] == .bool(true) ? [turn("active")] : [])])])
  }
}
