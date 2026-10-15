import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Material and Outline projection fidelity")
@MainActor
struct AgentChatMaterialOutlineProjectionTests {
    @Test("Material reuses exact source and keeps whole-Note AX and full passage copy")
    func materialRetainsOnlyItsCurrentCopy() throws {
        var parses = 0
        let projection = AgentChatMaterialExcerptProjection { source in
            parses += 1
            return ResearchExcerptPresentation.readableText(source)
        }
        let source =
            "# Exact 中文 cafe\u{301} 👨‍👩‍👧‍👦\r\n\r\n[[Note|captured alias]] and [visible link](https://example.invalid/exact).\r\n\r\n"
            + String(repeating: "Synthetic unchanged paragraph 中文😀. ", count: 512)
        let bytes = Array(source.utf8)
        let readable = ResearchExcerptPresentation.readableText(source)
        for _ in 0..<4 {
            let excerpt = projection.excerpt(for: source, extent: .wholeNote)
            #expect(excerpt.visibleText == nil)
            #expect(excerpt.accessibilityText.utf8.elementsEqual(String(readable.prefix(120)).utf8))
            #expect(excerpt.accessibilityText.count == 120)
        }
        #expect(parses == 1)
        let passage = projection.excerpt(for: source, extent: .passage)
        let visible = try #require(passage.visibleText)
        #expect(visible.utf8.elementsEqual(readable.utf8))
        #expect(passage.accessibilityText.utf8.elementsEqual(String(readable.prefix(120)).utf8))
        #expect(parses == 2)
        let independent = String(decoding: bytes, as: UTF8.self)
        _ = projection.excerpt(for: independent, extent: .passage)
        #expect(parses == 2)
        _ = projection.excerpt(for: "replacement", extent: .passage)
        _ = projection.excerpt(for: source, extent: .passage)
        #expect(parses == 4, "The owner retains its current projection, not past material history")
        #expect(source.utf8.elementsEqual(bytes))
    }

    @Test("Material passage bytes invalidate even when Note identity and revision are unchanged")
    func differentPassagesInOneNoteRevision() throws {
        var parses = 0
        let projection = AgentChatMaterialExcerptProjection { source in
            parses += 1
            return ResearchExcerptPresentation.readableText(source)
        }
        let noteID = UUID()
        let vaultID = UUID()
        let revision = DocumentFingerprint(content: "# Full Note\r\n\r\nFirst and second captured passages")
        let passages = ["**First** exact passage", "**Second** exact passage"]
        for source in passages {
            let attachment = AgentChatAttachment(
                noteID: noteID, vaultID: vaultID, relativePath: "Exact.md", text: source,
                fingerprint: revision, extent: .passage, source: .savedSource)
            let excerpt = projection.excerpt(for: attachment.text, extent: attachment.extent)
            let visible = try #require(excerpt.visibleText)
            #expect(visible.utf8.elementsEqual(ResearchExcerptPresentation.readableText(source).utf8))
            #expect(attachment.fingerprint == revision && attachment.text.utf8.elementsEqual(source.utf8))
        }
        #expect(parses == 2)
    }

    @Test("Canonical-equivalent material replacement preserves the new source's Unicode bytes")
    func materialCanonicalReplacement() throws {
        var parses = 0
        let projection = AgentChatMaterialExcerptProjection { source in
            parses += 1
            return ResearchExcerptPresentation.readableText(source)
        }
        let first = "**Café** [[Note|中文😀]]\r\n"
        let second = "**Cafe\u{301}** [[Note|中文😀]]\r\n"
        try #require(first == second && !first.utf8.elementsEqual(second.utf8))
        let before = try #require(projection.excerpt(for: first, extent: .passage).visibleText)
        let after = try #require(projection.excerpt(for: second, extent: .passage).visibleText)
        #expect(before.utf8.elementsEqual(ResearchExcerptPresentation.readableText(first).utf8))
        #expect(after.utf8.elementsEqual(ResearchExcerptPresentation.readableText(second).utf8))
        #expect(!before.utf8.elementsEqual(after.utf8))
        _ = projection.excerpt(for: second, extent: .passage)
        #expect(parses == 2)
    }

    @Test("Outline preserves empty requests, nil turn IDs and the first nonempty noncommentary response")
    func outlineAssociationSemantics() throws {
        let messages = [
            Self.message("orphan-answer", .assistant, "Never inferred for a nil turn"),
            Self.message("nil-question", .user, "A nil turn question"),
            Self.message("empty-question", .user, "", turn: "turn-a"),
            Self.message("progress", .assistant, "Excluded progress", turn: "turn-a", phase: .commentary),
            Self.message("empty-answer", .assistant, "", turn: "turn-a", phase: .finalAnswer),
            Self.message("operation", .operation, "Excluded operation", turn: "turn-a"),
            Self.message("first-answer", .assistant, "**First** eligible reply", turn: "turn-a"),
            Self.message("later-answer", .assistant, "Later final reply", turn: "turn-a", phase: .finalAnswer),
            Self.message("second-question", .user, "Another question in the confirmed turn", turn: "turn-a"),
            Self.message("empty-id-question", .user, "An explicitly present empty turn ID", turn: ""),
            Self.message("empty-id-answer", .assistant, "Empty turn ID answer", turn: ""),
        ]
        let projection = AgentChatOutlineProjection()
        let requests = projection.requests(in: messages, query: "")
        #expect(requests.map(\.id) == ["nil-question", "empty-question", "second-question", "empty-id-question"])
        #expect(requests.map(\.responseID) == [nil, "first-answer", "first-answer", "empty-id-answer"])
        try Self.verifyOriginalLabels(projection, requests: requests, messages: messages)
        #expect(projection.question(for: requests[1]) == ScholiumL10n.string("Materials"))
        #expect(projection.response(for: requests[0]) == nil)
    }

    @Test("Outline parses only demanded labels and reuses them across raw-source queries and retained inputs")
    func outlineLazyReuseAndRemoval() throws {
        var parses = 0
        let projection = AgentChatOutlineProjection { source in
            parses += 1
            return AgentChatListPresentation.plainText(source)
        }
        var messages = (0..<12).flatMap { ordinal in
            [
                Self.message(
                    "question-\(ordinal)", .user,
                    "[Question \(ordinal)](https://hidden.invalid/\(ordinal)) " + String(repeating: "中文😀 exact paragraph. ", count: 256),
                    turn: "turn-\(ordinal)"),
                Self.message(
                    "answer-\(ordinal)", .assistant, "**Answer \(ordinal)** " + String(repeating: "Unchanged reply. ", count: 256), turn: "turn-\(ordinal)",
                    phase: .finalAnswer),
            ]
        }
        let originalBytes = messages.map { Array($0.text.utf8) }
        let requests = projection.requests(in: messages, query: "")
        #expect(parses == 0, "Building request associations must not realize lazy Markdown labels")
        for request in requests.prefix(2) {
            _ = projection.question(for: request)
            _ = projection.response(for: request)
        }
        #expect(parses == 4)
        for _ in 0..<3 {
            let hidden = projection.requests(in: messages, query: "hidden.invalid/0")
            #expect(hidden.map(\.id) == ["question-0"])
            _ = projection.question(for: hidden[0])
            _ = projection.response(for: hidden[0])
        }
        #expect(parses == 4)
        #expect(projection.requests(in: messages, query: "absent-query").isEmpty)
        let independent = messages.map { message in
            var result = message
            result.text = String(decoding: Array(message.text.utf8), as: UTF8.self)
            return result
        }
        let retained = projection.requests(in: independent, query: "")
        _ = projection.question(for: retained[0])
        _ = projection.response(for: retained[0])
        #expect(parses == 4)
        #expect(zip(messages, originalBytes).allSatisfy { pair in pair.0.text.utf8.elementsEqual(pair.1) })
        messages.removeFirst(2)
        _ = projection.requests(in: messages, query: "")
        let restored = projection.requests(in: independent, query: "")[0]
        _ = projection.question(for: restored)
        _ = projection.response(for: restored)
        #expect(parses == 6, "Removed messages must leave this mounted Outline's label cache")
    }

    @Test("Streaming replacement and eligibility changes update only the current Outline labels")
    func outlineStreamingReplacement() throws {
        var parses = 0
        let projection = AgentChatOutlineProjection { source in
            parses += 1
            return AgentChatListPresentation.plainText(source)
        }
        var messages = [
            Self.message("question", .user, "[Visible question](https://old-destination.invalid/)", turn: "turn"),
            Self.message("early", .assistant, "", turn: "turn", phase: .finalAnswer),
            Self.message("later", .assistant, "Later eligible reply", turn: "turn", phase: .finalAnswer),
        ]
        var request = try #require(projection.requests(in: messages, query: "old-destination.invalid").first)
        #expect(request.responseID == "later")
        _ = projection.question(for: request)
        _ = projection.response(for: request)
        #expect(parses == 2)
        messages[1].text = "First streaming reply"
        request = try #require(projection.requests(in: messages, query: "old-destination.invalid").first)
        #expect(request.responseID == "early")
        _ = projection.question(for: request)
        #expect(projection.response(for: request) == "First streaming reply")
        #expect(parses == 3)
        messages[1].text += " grows"
        request = try #require(projection.requests(in: messages, query: "old-destination.invalid").first)
        #expect(projection.response(for: request) == "First streaming reply grows")
        #expect(parses == 4)
        messages[0].text = "[Visible question](https://new-destination.invalid/)"
        #expect(projection.requests(in: messages, query: "old-destination.invalid").isEmpty)
        request = try #require(projection.requests(in: messages, query: "new-destination.invalid").first)
        _ = projection.question(for: request)
        #expect(parses == 5)
        messages[1].phase = .commentary
        request = try #require(projection.requests(in: messages, query: "").first)
        #expect(request.responseID == "later")
        try Self.verifyOriginalLabels(projection, requests: [request], messages: messages)
        messages[0].turnID = nil
        request = try #require(projection.requests(in: messages, query: "").first)
        #expect(request.responseID == nil && projection.response(for: request) == nil)
    }

    @Test("Canonical-equivalent Outline replacement refreshes both question and response bytes")
    func outlineCanonicalReplacement() throws {
        var parses = 0
        let projection = AgentChatOutlineProjection { source in
            parses += 1
            return AgentChatListPresentation.plainText(source)
        }
        var messages = [
            Self.message("question", .user, "**Café** question", turn: "turn"),
            Self.message("answer", .assistant, "**Café** reply", turn: "turn", phase: .finalAnswer),
        ]
        var request = try #require(projection.requests(in: messages, query: "café").first)
        let beforeQuestion = projection.question(for: request)
        let beforeReply = try #require(projection.response(for: request))
        messages[0].text = "**Cafe\u{301}** question"
        messages[1].text = "**Cafe\u{301}** reply"
        request = try #require(projection.requests(in: messages, query: "cafe\u{301}").first)
        let afterQuestion = projection.question(for: request)
        let afterReply = try #require(projection.response(for: request))
        #expect(!beforeQuestion.utf8.elementsEqual(afterQuestion.utf8) && !beforeReply.utf8.elementsEqual(afterReply.utf8))
        try Self.verifyOriginalLabels(projection, requests: [request], messages: messages)
        #expect(parses == 4)
    }

    private static func message(
        _ id: String, _ role: AgentChatMessage.Role, _ text: String,
        turn: String? = nil, phase: AgentChatMessage.Phase? = nil
    ) -> AgentChatMessage {
        var message = AgentChatMessage(id: id, role: role, text: text, phase: phase)
        message.turnID = turn
        return message
    }

    private static func verifyOriginalLabels(
        _ projection: AgentChatOutlineProjection, requests: [AgentChatOutlineRequest], messages: [AgentChatMessage]
    ) throws {
        for request in requests {
            let original = try #require(messages.first { $0.id == request.id })
            let question = original.text.isEmpty ? ScholiumL10n.string("Materials") : String(AgentChatListPresentation.plainText(original.text).prefix(240))
            #expect(projection.question(for: request).utf8.elementsEqual(question.utf8))
            let response = messages.first {
                $0.turnID != nil && $0.turnID == original.turnID && $0.role == .assistant && $0.phase != .commentary && !$0.text.isEmpty
            }
            #expect(request.responseID == response?.id)
            if let response {
                let projected = try #require(projection.response(for: request))
                #expect(projected.utf8.elementsEqual(String(AgentChatListPresentation.plainText(response.text).prefix(180)).utf8))
            } else {
                #expect(projection.response(for: request) == nil)
            }
        }
    }
}
