import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

/// Synthetic CPU diagnostics against independent original label helpers. A bounded
/// visible-row subset models repeated body work; it does not mount SwiftUI,
/// realize a native list, invoke navigation, or establish visible latency.
@Suite(
    "Chat material and outline helper diagnostics", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_CHAT_MEASURE"] == "1"))
@MainActor
struct AgentChatMaterialOutlinePerformanceDiagnosticTests {
    private static let rebuilds = 3
    private static let visibleRows = 4

    @Test("Material excerpt and accessibility copy during repeated hover-equivalent rebuilds", arguments: [1_024, 4_096])
    func materialExcerptRebuilds(repetitions: Int) throws {
        let source = Self.markdown(kind: "material", ordinal: 0, repetitions: repetitions)
        let sourceBytes = Array(source.utf8)
        for extent in [AgentChatAttachment.Extent.wholeNote, .passage] {
            let attachment = AgentChatAttachment(
                noteID: UUID(), vaultID: UUID(), relativePath: "Synthetic/Exact cafe\u{301}.md", text: source,
                fingerprint: .init(content: source), sourceLine: 7, extent: extent, source: .editorSnapshot)
            let expected = Self.materialBodyCopy(attachment)
            let projection = AgentChatMaterialExcerptProjection()
            try #require(expected.accessibleExcerpt.count <= 120)
            try #require(expected.visibleExcerpt == (extent == .wholeNote ? nil : ResearchExcerptPresentation.readableText(source)))
            print(
                "CHAT_MATERIAL_OUTLINE_INPUT kind=material extent=\(extent.rawValue) "
                    + "utf8_bytes=\(sourceBytes.count) rebuilds=\(Self.rebuilds) source_unchanged=true")
            try Self.measure(
                "material_\(extent.rawValue)_rebuild", count: repetitions,
                operation: {
                    (0..<Self.rebuilds).map { _ in Self.materialProjectionCopy(attachment, projection: projection) }
                },
                verify: { values in
                    try #require(values.count == Self.rebuilds)
                    for value in values {
                        try #require(value.title.utf8.elementsEqual(expected.title.utf8))
                        try #require(value.accessibleExcerpt.utf8.elementsEqual(expected.accessibleExcerpt.utf8))
                        try #require(value.accessibilityValue.utf8.elementsEqual(expected.accessibilityValue.utf8))
                        switch (value.visibleExcerpt, expected.visibleExcerpt) {
                        case (nil, nil): break
                        case (.some(let actual), .some(let expected)):
                            try #require(actual.utf8.elementsEqual(expected.utf8))
                        default: Issue.record("Material extent changed its visible copy")
                        }
                    }
                    try #require(attachment.text.utf8.elementsEqual(sourceBytes))
                    try #require(attachment.fingerprint == DocumentFingerprint(content: source))
                    try #require(attachment.sourceLine == 7 && attachment.extent == extent && attachment.source == .editorSnapshot)
                })
        }
    }

    @Test("Outline visible question and first eligible reply copy during repeated open-equivalent rebuilds", arguments: [24, 100])
    func outlineVisibleRows(turnCount: Int) throws {
        let messages = Self.outlineMessages(turnCount: turnCount)
        let sourceBytes = messages.map { Array($0.text.utf8) }
        let currentID = "question-\(turnCount - 2)"
        let projection = AgentChatOutlineProjection()
        let scenarios: [(name: String, query: String, tail: Bool, expectedIDs: [String])] = [
            ("open_first", "", false, (0..<Self.visibleRows).map { "question-\($0)" }),
            ("browse_tail", "", true, ((turnCount - Self.visibleRows)..<turnCount).map { "question-\($0)" }),
            // The URL is absent from the visible link label. Outline's owning
            // predicate still searches the captured raw question source.
            ("hidden_destination", "hidden-question-target.invalid/17", false, ["question-17"]),
        ]
        for scenario in scenarios {
            let expected = Self.outlineBodyCopy(messages, query: scenario.query, tail: scenario.tail, currentID: currentID)
            try #require(expected.map(\.id) == scenario.expectedIDs)
            try #require(expected.allSatisfy { $0.question.count <= 240 && ($0.response?.count ?? 0) <= 180 })
            for row in expected {
                let ordinal = try #require(Int(row.id.dropFirst("question-".count)))
                try #require(row.responseID == "answer-\(ordinal)")
                try #require(row.isCurrent == (row.id == currentID))
                try #require(row.response?.hasPrefix("Synthetic answer \(ordinal)") == true)
            }
            print(
                "CHAT_MATERIAL_OUTLINE_INPUT kind=outline scenario=\(scenario.name) turns=\(turnCount) "
                    + "message_count=\(messages.count) visible_rows=\(expected.count) "
                    + "utf8_bytes=\(sourceBytes.reduce(0) { $0 + $1.count }) rebuilds=\(Self.rebuilds) source_unchanged=true")
            try Self.measure(
                "outline_\(scenario.name)_rebuild", count: turnCount,
                operation: {
                    (0..<Self.rebuilds).map { _ in
                        Self.outlineProjectionCopy(
                            messages, projection: projection, query: scenario.query, tail: scenario.tail, currentID: currentID)
                    }
                },
                verify: { values in
                    try #require(values.count == Self.rebuilds)
                    for rows in values {
                        try #require(rows.count == expected.count)
                        for (actual, expected) in zip(rows, expected) {
                            try #require(actual.id == expected.id && actual.responseID == expected.responseID && actual.isCurrent == expected.isCurrent)
                            try #require(actual.question.utf8.elementsEqual(expected.question.utf8))
                            switch (actual.response, expected.response) {
                            case (nil, nil): break
                            case (.some(let actual), .some(let expected)):
                                try #require(actual.utf8.elementsEqual(expected.utf8))
                            default: Issue.record("Outline changed the eligible response")
                            }
                        }
                    }
                    try #require(messages.count == sourceBytes.count)
                    try #require(zip(messages, sourceBytes).allSatisfy { pair in pair.0.text.utf8.elementsEqual(pair.1) })
                })
        }
    }

    private struct MaterialCopy {
        let title: String
        let visibleExcerpt: String?
        let accessibleExcerpt: String
        let accessibilityValue: String
    }

    /// Test-only composition of AgentChatMaterialChip's current private
    /// helpers, keeping its dialect-aware projection distinct from Outline.
    private static func materialBodyCopy(_ attachment: AgentChatAttachment) -> MaterialCopy {
        let visible: String? = attachment.extent == .wholeNote ? nil : ResearchExcerptPresentation.readableText(attachment.text)
        let accessible = String(ResearchExcerptPresentation.readableText(attachment.text).prefix(120))
        let extent = attachment.extent == .wholeNote ? ScholiumL10n.string("Whole Note") : ScholiumL10n.string("Attached Passage")
        let source = attachment.source == .editorSnapshot ? ScholiumL10n.string("Editor Snapshot") : ScholiumL10n.string("Saved Source")
        return .init(
            title: URL(fileURLWithPath: attachment.relativePath).deletingPathExtension().lastPathComponent,
            visibleExcerpt: visible, accessibleExcerpt: accessible,
            accessibilityValue: "\(extent), \(source): \(accessible)")
    }

    private static func materialProjectionCopy(
        _ attachment: AgentChatAttachment, projection: AgentChatMaterialExcerptProjection
    ) -> MaterialCopy {
        let excerpt = projection.excerpt(for: attachment.text, extent: attachment.extent)
        let extent = attachment.extent == .wholeNote ? ScholiumL10n.string("Whole Note") : ScholiumL10n.string("Attached Passage")
        let source = attachment.source == .editorSnapshot ? ScholiumL10n.string("Editor Snapshot") : ScholiumL10n.string("Saved Source")
        return .init(
            title: URL(fileURLWithPath: attachment.relativePath).deletingPathExtension().lastPathComponent,
            visibleExcerpt: excerpt.visibleText, accessibleExcerpt: excerpt.accessibilityText,
            accessibilityValue: "\(extent), \(source): \(excerpt.accessibilityText)")
    }

    private struct OutlineCopy {
        let id: String
        let question: String
        let responseID: String?
        let response: String?
        let isCurrent: Bool
    }

    /// Test-only composition of the current lazy row labels. Limiting rows
    /// avoids claiming that opening Outline eagerly realizes every request.
    private static func outlineBodyCopy(
        _ messages: [AgentChatMessage], query: String, tail: Bool, currentID: String?
    ) -> [OutlineCopy] {
        let requests = messages.filter { $0.role == .user && (query.isEmpty || $0.text.localizedStandardContains(query)) }
        let visible = tail ? Array(requests.suffix(visibleRows)) : Array(requests.prefix(visibleRows))
        return visible.map { message in
            let response = messages.first {
                $0.turnID != nil && $0.turnID == message.turnID && $0.role == .assistant && $0.phase != .commentary && !$0.text.isEmpty
            }
            return .init(
                id: message.id,
                question: message.text.isEmpty ? ScholiumL10n.string("Materials") : String(AgentChatListPresentation.plainText(message.text).prefix(240)),
                responseID: response?.id,
                response: response.map { String(AgentChatListPresentation.plainText($0.text).prefix(180)) },
                isCurrent: message.id == currentID)
        }
    }

    private static func outlineProjectionCopy(
        _ messages: [AgentChatMessage], projection: AgentChatOutlineProjection,
        query: String, tail: Bool, currentID: String?
    ) -> [OutlineCopy] {
        let requests = projection.requests(in: messages, query: query)
        let visible = tail ? Array(requests.suffix(visibleRows)) : Array(requests.prefix(visibleRows))
        return visible.map { request in
            .init(
                id: request.id, question: projection.question(for: request), responseID: request.responseID,
                response: projection.response(for: request), isCurrent: request.id == currentID)
        }
    }

    private static func markdown(kind: String, ordinal: Int, repetitions: Int) -> String {
        // A few formatted nodes surrounding one long plain paragraph avoids
        // measuring an unrelated many-node Markdown projection pathology.
        "# Synthetic \(kind) \(ordinal)\r\n\r\n"
            + "[visible \(kind) link](https://hidden-\(kind)-target.invalid/\(ordinal)) and [[Notes/Exact|captured alias]].\r\n\r\n"
            + String(repeating: "Synthetic exact paragraph 中文 cafe\u{301} 👨‍👩‍👧‍👦. ", count: repetitions)
            + "\r\n\r\nFinal **visible ending**.\r\n"
    }

    private static func outlineMessages(turnCount: Int) -> [AgentChatMessage] {
        (0..<turnCount).flatMap { ordinal in
            let turnID = "turn-\(ordinal)"
            var question = AgentChatMessage(
                id: "question-\(ordinal)", role: .user,
                text: markdown(kind: "question", ordinal: ordinal, repetitions: 384))
            var commentary = AgentChatMessage(
                id: "commentary-\(ordinal)", role: .assistant, text: "Excluded public progress", phase: .commentary)
            var empty = AgentChatMessage(id: "empty-\(ordinal)", role: .assistant, text: "", phase: .finalAnswer)
            var answer = AgentChatMessage(
                id: "answer-\(ordinal)", role: .assistant,
                text: markdown(kind: "answer", ordinal: ordinal, repetitions: 384), phase: .finalAnswer)
            var later = AgentChatMessage(id: "later-\(ordinal)", role: .assistant, text: "A later answer must not replace the first eligible reply")
            question.turnID = turnID
            commentary.turnID = turnID
            empty.turnID = turnID
            answer.turnID = turnID
            later.turnID = turnID
            return [question, commentary, empty, answer, later]
        }
    }

    private static func measure<Value>(
        _ scenario: String, count: Int, operation: () -> Value, verify: (Value) throws -> Void
    ) throws {
        let warmups = 1
        let retainedSamples = 3
        var samples: [Double] = []
        for sample in 0..<(warmups + retainedSamples) {
            let start = ContinuousClock.now
            let value = operation()
            let duration = start.duration(to: .now).components
            let milliseconds = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
            try verify(value)
            try #require(milliseconds.isFinite && milliseconds >= 0)
            if sample >= warmups { samples.append(milliseconds) }
        }
        let sorted = samples.sorted()
        print(
            "CHAT_MATERIAL_OUTLINE_DIAGNOSTIC scenario=\(scenario) count=\(count) warmups=\(warmups) samples=\(samples.count) "
                + "median_ms=\(sorted[1]) max_ms=\(sorted.last!) raw_ms=\(samples.map { String($0) }.joined(separator: ",")) "
                + "boundary=helper_cpu projection=retained_view_owner native_visible_latency=unmeasured diagnostic_only=true")
    }
}
