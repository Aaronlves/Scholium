import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Reply source evidence")
struct AgentChatSourceEvidenceTests {
  let noteID = UUID()
  let revision = DocumentFingerprint(content: "Current source")
  func read(_ start: Int, _ count: Int, end: Bool = false, revision other: DocumentFingerprint? = nil) -> AgentChatMessage {
    var activity = AgentChatActivity(kind: .read, status: .completed, source: .scholium)
    activity.sourceObservation = .noteRead(.init(noteID: noteID, fingerprint: other ?? revision,
      startLine: start, lineCount: count, reachedEnd: end, excerpt: "Exact excerpt", excerptIsTruncated: true))
    var message = AgentChatMessage(role: .operation, text: "", activity: activity)
    message.turnID = "turn"; return message
  }
  func reply() -> AgentChatMessage {
    var result = AgentChatMessage(role: .assistant, text: "Answer", phase: .finalAnswer)
    result.turnID = "turn"; return result
  }

  @Test("Disjoint ranges and different versions cannot become complete source reading")
  func rangesAndRevisions() throws {
    let answer = reply()
    let events = [read(1, 10), read(20, 5, end: true), answer]
    let context = AgentChatReplySourceContext(reply: answer, history: events)
    let url = AgentChatReference.url(noteID: noteID, line: 15, revision: revision)
    guard case .note(let coverage) = context.evidence(for: url) else { Issue.record("Missing current read observation"); return }
    #expect(coverage.ranges == [1...10, 20...24])
    #expect(!coverage.coversWholeSource && !coverage.coversCitedLine)
    let complete = AgentChatReplySourceContext(reply: answer, history: [read(1, 10), read(11, 5, end: true), answer])
    guard case .note(let all) = complete.evidence(for: url) else { Issue.record("Missing complete coverage"); return }
    #expect(all.coversWholeSource && all.coversCitedLine)
    let changed = AgentChatReplySourceContext(reply: answer, history: [read(1, 10), read(11, 5, end: true,
      revision: DocumentFingerprint(content: "Different source")), answer])
    guard case .note(let old) = changed.evidence(for: url) else { Issue.record("Missing matching revision"); return }
    #expect(!old.coversWholeSource && old.ranges == [1...10])
    if case .differentRevision = context.evidence(for: AgentChatReference.url(noteID: noteID,
      revision: DocumentFingerprint(content: "Unobserved"))) {} else { Issue.record("Version mismatch was concealed") }
  }

  @Test("Evidence cannot come from another turn, after the reply, a failed read or a runtime impersonation")
  func scopeAndOrigin() {
    let answer = reply()
    var previous = read(1, 5, end: true); previous.turnID = "previous"
    var failed = read(1, 5, end: true); failed.activity?.status = .failed
    var spoof = AgentChatActivity(kind: .read, status: .completed, source: .runtime)
    spoof.sourceObservation = read(1, 5, end: true).activity?.sourceObservation
    var runtime = AgentChatMessage(role: .operation, text: "", activity: spoof); runtime.turnID = "turn"
    let context = AgentChatReplySourceContext(reply: answer, history: [previous, failed, runtime, answer, read(1, 5, end: true)])
    if case .unrecorded = context.evidence(for: AgentChatReference.url(noteID: noteID)) {} else { Issue.record("Unrelated evidence admitted") }
  }

  @Test("Supplied PDF page representations remain separate material, not fabricated citations")
  func suppliedMaterials() {
    let material = AgentChatLocalMaterial(id: UUID(), source: .file(URL(fileURLWithPath: "/synthetic/paper.pdf")),
      storedFileName: "snapshot.pdf", fingerprint: revision, kind: .pdf,
      pages: [.init(number: 2, text: "Supplied page"), .init(number: 3, text: "")])
    var input = AgentChatMessage(role: .user, text: "Discuss this", localMaterials: [material]); input.turnID = "turn"
    let answer = reply()
    let context = AgentChatReplySourceContext(reply: answer, history: [input, answer])
    #expect(context.hasMaterials && context.localMaterials == [material])
    #expect(context.localMaterials[0].pagesWithoutText == [3])
    #expect(AgentChatReplySource.collect(answer.text).isEmpty)
    #expect(!AgentChatReplySourceContext(reply: AgentChatMessage(role: .assistant, text: "Unknown turn"), history: [input]).hasMaterials)
  }

  @Test("App read parsing validates full-source fingerprints and bounds the exact preview")
  func parsing() throws {
    let source = String(repeating: "原文 😀\n", count: 400)
    let fingerprint = DocumentFingerprint(content: source)
    var value: [String: MCPJSONValue] = ["note_id": .string(noteID.uuidString),
      "fingerprint": .object(["sha256": .string(fingerprint.sha256), "byte_count": .integer(fingerprint.byteCount)]),
      "start_line": .integer(1), "line_count": .integer(400), "source": .string(source),
      "complete": .bool(true), "next_line": .null]
    guard case .noteRead(let observation) = AgentChatReadObservation.parse(value) else { Issue.record("Missing read evidence"); return }
    #expect(source.utf8.starts(with: observation.excerpt.utf8) && observation.excerpt.utf8.count <= 1_600)
    #expect(!observation.excerpt.contains("�") && observation.excerptIsTruncated)
    #expect(try JSONDecoder().decode(AgentChatSourceObservation.self,
      from: JSONEncoder().encode(AgentChatSourceObservation.noteRead(observation))) == .noteRead(observation))
    value["source"] = .string("different")
    #expect(AgentChatReadObservation.parse(value) == nil)
    value["source"] = .string(source); value["start_line"] = .integer(Int.max)
    #expect(AgentChatReadObservation.parse(value) == nil)
    value["start_line"] = .integer(1); value["complete"] = .bool(false)
    #expect(AgentChatReadObservation.parse(value) == nil)
  }
}
