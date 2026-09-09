import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Reply source evidence")
struct AgentChatSourceEvidenceTests {
  @Test("Zotero reports remain separate by source version and exact cited page")
  func zoteroScopeAndVersions() throws {
    let page = try ZoteroReference(library: .group(42), kind: .pdf, itemKey: "ATTACH01", page: 2)
    let first = ZoteroReadReport(server: "scholium-zotero", tool: "zotero_read_original", reference: page,
      representation: .pdfText, fingerprint: String(repeating: "a", count: 64), range: .init(start: 0, end: 4, total: 40), excerpt: "Read")
    let second = ZoteroReadReport(server: "custom-zotero", tool: "zotero_read_original", reference: page,
      representation: .pdfImage, fingerprint: String(repeating: "b", count: 64))
    func event(_ report: ZoteroReadReport) -> AgentChatMessage {
      var activity = AgentChatActivity(kind: .tool, status: .completed, source: .runtime)
      activity.sourceObservation = .zoteroReadReport(report)
      var message = AgentChatMessage(role: .operation, text: "", activity: activity); message.turnID = "turn"; return message
    }
    let answer = reply()
    let context = AgentChatReplySourceContext(reply: answer, history: [event(first), event(second), answer])
    guard case .zotero(let reports) = context.evidence(for: page.url) else { Issue.record("Missing reports"); return }
    #expect(reports == [first, second])
    let plain = ZoteroReadReport(server: "custom-zotero", tool: "zotero_read_original",
      reference: try ZoteroReference(library: .group(42), itemKey: "ATTACH01"), representation: .text,
      fingerprint: String(repeating: "a", count: 64), range: .init(start: 0, end: 4, total: 4), excerpt: "Read")
    #expect(!plain.matches(try ZoteroReference(library: .group(42), kind: .pdf, itemKey: "ATTACH01")))
    let wrongPage = try ZoteroReference(library: .group(42), kind: .pdf, itemKey: "ATTACH01", page: 3)
    let wrongLibrary = try ZoteroReference(library: .user, kind: .pdf, itemKey: "ATTACH01", page: 2)
    for wrong in [wrongPage, wrongLibrary] {
      if case .unrecorded = context.evidence(for: wrong.url) {} else { Issue.record("Crossed material scope") }
    }
    var previous = event(first); previous.turnID = "previous"
    var failed = event(first); failed.activity?.status = .failed
    var spoof = event(first)
    var falseOrigin = AgentChatActivity(kind: .tool, status: .completed, source: .scholium)
    falseOrigin.sourceObservation = .zoteroReadReport(first); spoof.activity = falseOrigin
    let unrelated = AgentChatReplySourceContext(reply: answer, history: [previous, failed, spoof, answer, event(second)])
    if case .unrecorded = unrelated.evidence(for: page.url) {} else { Issue.record("Unrelated or false-origin report was admitted") }
  }

  @Test("An annotation report cannot stand in for PDF text or another annotation")
  func annotationIsSeparateMaterial() throws {
    let reference = try ZoteroReference(library: .user, kind: .pdf, itemKey: "ATTACH01", page: 2, annotationKey: "ANNO0001")
    let report = ZoteroReadReport(server: "custom-zotero", tool: "zotero_read_annotation", reference: reference,
      representation: .annotation, fingerprint: String(repeating: "a", count: 64), excerpt: "Selected text", comment: "A comment", pageLabel: "xii")
    #expect(report.matches(reference))
    #expect(report.matches(try ZoteroReference(library: .user, kind: .pdf, itemKey: "ATTACH01", annotationKey: "ANNO0001")))
    #expect(!report.matches(try ZoteroReference(library: .user, kind: .pdf, itemKey: "ATTACH01", page: 2)))
    #expect(!report.matches(try ZoteroReference(library: .user, kind: .pdf, itemKey: "ATTACH01", annotationKey: "ANNO0002")))
    let corrupted = ZoteroReadReport(server: "custom-zotero", tool: "zotero_read_annotation", reference: reference,
      representation: .annotation, fingerprint: "invalid", excerpt: String(repeating: "a", count: 2_000))
    #expect(!corrupted.isValid && !corrupted.matches(reference))
  }

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
