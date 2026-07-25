import Foundation
import Markdown

public enum CommentAttachmentState: String, Codable, Sendable {
    case attached
    case needsReattachment
}

public struct CommentAnchor: Codable, Hashable, Sendable {
    public var fingerprint: DocumentFingerprint
    public var utf8Range: Range<Int>
    public var utf16Range: Range<Int>
    public var line: Int
    public var endLine: Int
    public var quotation: String
    /// The text the researcher saw and selected. This can differ from
    /// `quotation` when Read mode omits Markdown punctuation inside the exact
    /// source range. Reattachment always uses the authoritative source
    /// quotation; presentation uses this value when available.
    public var selectedText: String?
    public var contextBefore: String
    public var contextAfter: String
    public var state: CommentAttachmentState

    public init(
        fingerprint: DocumentFingerprint,
        utf8Range: Range<Int>,
        utf16Range: Range<Int>,
        line: Int,
        endLine: Int,
        quotation: String,
        selectedText: String? = nil,
        contextBefore: String = "",
        contextAfter: String = "",
        state: CommentAttachmentState = .attached
    ) {
        self.fingerprint = fingerprint
        self.utf8Range = utf8Range
        self.utf16Range = utf16Range
        self.line = line
        self.endLine = endLine
        self.quotation = quotation
        self.selectedText = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.state = state
    }
}

/// Constructs fingerprint-bound comment anchors from exact UTF-16 editor
/// selections or from a unique Read-mode quotation. All stored offsets are
/// measured against the full Markdown file, including frontmatter.
public enum CommentAnchorBuilder {
    public static let contextLength = 48

    public static func anchor(
        in source: String,
        fingerprint: DocumentFingerprint,
        utf16Range: Range<Int>,
        selectedText: String? = nil
    ) -> CommentAnchor? {
        let nsSource = source as NSString
        guard utf16Range.lowerBound >= 0,
              utf16Range.upperBound > utf16Range.lowerBound,
              utf16Range.upperBound <= nsSource.length,
              let range = Range(
                NSRange(
                    location: utf16Range.lowerBound,
                    length: utf16Range.upperBound - utf16Range.lowerBound
                ),
                in: source
              ) else { return nil }

        let quotation = String(source[range])
        guard !quotation.isEmpty else { return nil }
        let prefix = source[..<range.lowerBound]
        let utf8Start = prefix.utf8.count
        let utf8End = utf8Start + quotation.utf8.count
        let line = prefix.reduce(into: 1) { count, character in
            if character.isNewline { count += 1 }
        }
        let endLine = quotation.dropLast().reduce(into: line) { count, character in
            if character.isNewline { count += 1 }
        }
        let contextStart = source.index(
            range.lowerBound,
            offsetBy: -contextLength,
            limitedBy: source.startIndex
        ) ?? source.startIndex
        let contextEnd = source.index(
            range.upperBound,
            offsetBy: contextLength,
            limitedBy: source.endIndex
        ) ?? source.endIndex
        let visibleSelection = selectedText?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return CommentAnchor(
            fingerprint: fingerprint,
            utf8Range: utf8Start..<utf8End,
            utf16Range: utf16Range,
            line: line,
            endLine: max(line, endLine),
            quotation: quotation,
            selectedText: visibleSelection == quotation ? nil : visibleSelection,
            contextBefore: String(source[contextStart..<range.lowerBound]),
            contextAfter: String(source[range.upperBound..<contextEnd])
        )
    }

    /// Resolves a Read-mode selection only when one source occurrence is
    /// reliable. Context is advisory: exact source context disambiguates a
    /// repeated quotation, while a unique quotation remains sufficient.
    public static func anchor(
        forRenderedQuotation quotation: String,
        contextBefore: String = "",
        contextAfter: String = "",
        in document: NoteDocument
    ) -> CommentAnchor? {
        let selected = quotation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return nil }
        let candidates = ranges(of: selected, in: document.rawContent)
        let contextual = candidates.filter { range in
            contextMatches(
                range: range,
                source: document.rawContent,
                contextBefore: contextBefore,
                contextAfter: contextAfter
            )
        }
        let resolved: Range<String.Index>?
        if contextual.count == 1 {
            resolved = contextual[0]
        } else if candidates.count == 1 {
            resolved = candidates[0]
        } else {
            resolved = nil
        }
        if resolved == nil {
            return anchorFromRenderedText(
                selected,
                contextBefore: contextBefore,
                contextAfter: contextAfter,
                document: document
            )
        }
        guard let resolved else { return nil }
        let lowerUTF16 = resolved.lowerBound.utf16Offset(in: document.rawContent)
        let upperUTF16 = resolved.upperBound.utf16Offset(in: document.rawContent)
        return anchor(
            in: document.rawContent,
            fingerprint: document.fingerprint,
            utf16Range: lowerUTF16..<upperUTF16,
            selectedText: selected
        )
    }

    /// Returns the visible Markdown text covered by an exact source anchor.
    /// This is used to project Source-mode comments over Read mode without
    /// searching the whole rendered document for an ambiguous quotation.
    public static func renderedQuotation(
        for anchor: CommentAnchor,
        in document: NoteDocument
    ) -> String? {
        guard anchor.state == .attached,
              anchor.fingerprint == document.fingerprint,
              let bodyStart = fullSourceBodyUTF16Offset(document) else { return nil }
        let bodyRange = (anchor.utf16Range.lowerBound - bodyStart)..<(anchor.utf16Range.upperBound - bodyStart)
        guard bodyRange.lowerBound >= 0,
              bodyRange.upperBound <= document.body.utf16.count,
              bodyRange.upperBound > bodyRange.lowerBound else { return nil }
        let parsed = Document(parsing: document.body)
        var collector = RenderedCommentTextCollector(source: document.body)
        collector.visit(parsed)
        return collector.renderedText(forSourceRange: bodyRange)
    }

    private static func anchorFromRenderedText(
        _ selected: String,
        contextBefore: String,
        contextAfter: String,
        document: NoteDocument
    ) -> CommentAnchor? {
        let parsed = Document(parsing: document.body)
        var collector = RenderedCommentTextCollector(source: document.body)
        collector.visit(parsed)
        let candidates = ranges(of: selected, in: collector.renderedText)
        let contextual = candidates.filter { range in
            contextMatches(
                range: range,
                source: collector.renderedText,
                contextBefore: contextBefore,
                contextAfter: contextAfter
            )
        }
        let renderedRange: Range<String.Index>?
        if contextual.count == 1 {
            renderedRange = contextual[0]
        } else if candidates.count == 1 {
            renderedRange = candidates[0]
        } else {
            renderedRange = nil
        }
        guard let renderedRange,
              let bodyRange = collector.sourceRange(for: renderedRange),
              let bodyStart = fullSourceBodyUTF16Offset(document) else { return nil }
        return anchor(
            in: document.rawContent,
            fingerprint: document.fingerprint,
            utf16Range: (bodyStart + bodyRange.lowerBound)..<(bodyStart + bodyRange.upperBound),
            selectedText: selected
        )
    }

    private static func fullSourceBodyUTF16Offset(_ document: NoteDocument) -> Int? {
        let source = document.rawContent
        let byteOffset = document.bodyByteRange.lowerBound
        guard byteOffset >= 0, byteOffset <= source.utf8.count else { return nil }
        let utf8Index = source.utf8.index(source.utf8.startIndex, offsetBy: byteOffset)
        guard let index = String.Index(utf8Index, within: source) else { return nil }
        return index.utf16Offset(in: source)
    }

    private static func ranges(of needle: String, in source: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var cursor = source.startIndex
        while cursor < source.endIndex,
              let range = source.range(of: needle, range: cursor..<source.endIndex) {
            result.append(range)
            cursor = range.upperBound
        }
        return result
    }

    private static func contextMatches(
        range: Range<String.Index>,
        source: String,
        contextBefore: String,
        contextAfter: String
    ) -> Bool {
        let beforeNeedle = String(contextBefore.suffix(contextLength))
        let afterNeedle = String(contextAfter.prefix(contextLength))
        let beforeStart = source.index(
            range.lowerBound,
            offsetBy: -beforeNeedle.count,
            limitedBy: source.startIndex
        ) ?? source.startIndex
        let afterEnd = source.index(
            range.upperBound,
            offsetBy: afterNeedle.count,
            limitedBy: source.endIndex
        ) ?? source.endIndex
        let before = String(source[beforeStart..<range.lowerBound])
        let after = String(source[range.upperBound..<afterEnd])
        return (beforeNeedle.isEmpty || before.hasSuffix(beforeNeedle))
            && (afterNeedle.isEmpty || after.hasPrefix(afterNeedle))
    }
}

/// Produces the text a reader sees after Markdown syntax is removed. Search
/// uses this projection only for result presentation; source locations and
/// writes continue to use the exact Markdown bytes.
public enum MarkdownVisibleText {
    public static func render(_ source: String) -> String {
        let parsed = Document(parsing: source)
        var collector = RenderedCommentTextCollector(source: source)
        collector.visit(parsed)
        return collector.renderedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct RenderedCommentTextFragment {
    let renderedRange: Range<Int>
    let sourceRange: Range<Int>?
    let exact: Bool
}

private struct RenderedCommentTextCollector: MarkupWalker {
    private let source: String
    private let mapper: RenderedCommentSourceMapper
    private(set) var renderedText = ""
    private var fragments: [RenderedCommentTextFragment] = []

    init(source: String) {
        self.source = source
        mapper = RenderedCommentSourceMapper(source)
    }

    mutating func visitDocument(_ document: Document) { descendInto(document) }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        descendInto(paragraph)
        appendSeparator("\n")
    }

    mutating func visitHeading(_ heading: Heading) {
        descendInto(heading)
        appendSeparator("\n")
    }

    mutating func visitText(_ text: Markdown.Text) {
        append(text.string, sourceRange: text.range)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        append(inlineCode.code, sourceRange: inlineCode.range)
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) { appendSeparator("\n") }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { appendSeparator("\n") }

    mutating func visitImage(_ image: Image) {
        if let title = image.title, !title.isEmpty {
            append(title, sourceRange: image.range)
        }
    }

    func sourceRange(for renderedRange: Range<String.Index>) -> Range<Int>? {
        let lower = renderedRange.lowerBound.utf16Offset(in: renderedText)
        let upper = renderedRange.upperBound.utf16Offset(in: renderedText)
        let overlapping = fragments.filter {
            $0.sourceRange != nil
                && $0.renderedRange.lowerBound < upper
                && $0.renderedRange.upperBound > lower
        }
        guard let first = overlapping.first,
              let last = overlapping.last,
              let firstSource = first.sourceRange,
              let lastSource = last.sourceRange else { return nil }

        let sourceLower: Int
        if first.exact {
            sourceLower = firstSource.lowerBound + max(0, lower - first.renderedRange.lowerBound)
        } else {
            sourceLower = firstSource.lowerBound
        }
        let sourceUpper: Int
        if last.exact {
            sourceUpper = lastSource.lowerBound
                + min(lastSource.count, upper - last.renderedRange.lowerBound)
        } else {
            sourceUpper = lastSource.upperBound
        }
        guard sourceUpper > sourceLower else { return nil }
        return sourceLower..<sourceUpper
    }

    func renderedText(forSourceRange sourceRange: Range<Int>) -> String? {
        let overlapping = fragments.filter {
            guard let fragmentSource = $0.sourceRange else { return false }
            return fragmentSource.lowerBound < sourceRange.upperBound
                && fragmentSource.upperBound > sourceRange.lowerBound
        }
        guard let first = overlapping.first,
              let last = overlapping.last,
              let firstSource = first.sourceRange,
              let lastSource = last.sourceRange else { return nil }

        let renderedLower = first.exact
            ? first.renderedRange.lowerBound
                + max(0, sourceRange.lowerBound - firstSource.lowerBound)
            : first.renderedRange.lowerBound
        let renderedUpper = last.exact
            ? last.renderedRange.lowerBound
                + min(last.renderedRange.count, sourceRange.upperBound - lastSource.lowerBound)
            : last.renderedRange.upperBound
        guard renderedUpper > renderedLower else { return nil }
        let nsRendered = renderedText as NSString
        let result = nsRendered.substring(with: NSRange(
            location: renderedLower,
            length: renderedUpper - renderedLower
        )).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private mutating func append(_ text: String, sourceRange: Markdown.SourceRange?) {
        guard !text.isEmpty else { return }
        let renderedStart = renderedText.utf16.count
        renderedText += text
        let renderedEnd = renderedText.utf16.count
        guard var range = sourceRange.flatMap(mapper.utf16Range) else {
            fragments.append(RenderedCommentTextFragment(
                renderedRange: renderedStart..<renderedEnd,
                sourceRange: nil,
                exact: false
            ))
            return
        }
        let nsSource = source as NSString
        let raw = nsSource.substring(with: NSRange(
            location: range.lowerBound,
            length: range.count
        ))
        if raw != text,
           let match = raw.range(of: text),
           raw.range(of: text, range: match.upperBound..<raw.endIndex) == nil {
            let lower = match.lowerBound.utf16Offset(in: raw)
            let upper = match.upperBound.utf16Offset(in: raw)
            range = (range.lowerBound + lower)..<(range.lowerBound + upper)
        }
        let exact = (source as NSString).substring(with: NSRange(
            location: range.lowerBound,
            length: range.count
        )) == text
        fragments.append(RenderedCommentTextFragment(
            renderedRange: renderedStart..<renderedEnd,
            sourceRange: range,
            exact: exact
        ))
    }

    private mutating func appendSeparator(_ separator: String) {
        guard !renderedText.hasSuffix(separator) else { return }
        let start = renderedText.utf16.count
        renderedText += separator
        fragments.append(RenderedCommentTextFragment(
            renderedRange: start..<renderedText.utf16.count,
            sourceRange: nil,
            exact: false
        ))
    }
}

private struct RenderedCommentSourceMapper {
    let source: String
    let lineStarts: [Int]

    init(_ source: String) {
        self.source = source
        let nsSource = source as NSString
        var starts = [0]
        var offset = 0
        while offset < nsSource.length {
            let value = nsSource.character(at: offset)
            if value == 13 {
                if offset + 1 < nsSource.length, nsSource.character(at: offset + 1) == 10 {
                    offset += 1
                }
                starts.append(offset + 1)
            } else if value == 10 {
                starts.append(offset + 1)
            }
            offset += 1
        }
        lineStarts = starts
    }

    func utf16Range(_ range: Markdown.SourceRange) -> Range<Int>? {
        guard let lower = utf16Offset(
            line: range.lowerBound.line,
            utf8Column: range.lowerBound.column
        ), let upper = utf16Offset(
            line: range.upperBound.line,
            utf8Column: range.upperBound.column
        ), upper >= lower else { return nil }
        return lower..<upper
    }

    private func utf16Offset(line: Int, utf8Column: Int) -> Int? {
        guard line > 0, line <= lineStarts.count else { return nil }
        let lineStart = lineStarts[line - 1]
        let nsSource = source as NSString
        let lineRange = nsSource.lineRange(for: NSRange(location: lineStart, length: 0))
        let lineText = nsSource.substring(with: lineRange)
        let byteOffset = max(0, utf8Column - 1)
        guard byteOffset <= lineText.utf8.count else { return nil }
        let byteIndex = lineText.utf8.index(lineText.utf8.startIndex, offsetBy: byteOffset)
        guard let index = String.Index(byteIndex, within: lineText) else { return nil }
        return lineStart + index.utf16Offset(in: lineText)
    }
}

public enum ResearchRecordStoreError: LocalizedError, Sendable {
    case unreadableStore(kind: String, reason: String)
    case restorationConflict(kind: String, identity: String)

    public var errorDescription: String? {
        switch self {
        case .unreadableStore(let kind, let reason):
            "Scholium could not safely load the \(kind) records. Their file was left unchanged. \(reason)"
        case .restorationConflict(let kind, let identity):
            "Scholium did not replace a concurrently changed \(kind) record during rollback: \(identity)"
        }
    }
}


public struct DialogueNoteReference: Codable, Hashable, Identifiable, Sendable {
    public let noteID: UUID
    public let vaultID: UUID
    public let vaultName: String
    public let title: String
    public let relativePath: String
    public let fingerprint: DocumentFingerprint
    /// Optional researcher-facing Work metadata. Location remains the note's
    /// authoritative role; this value is prompt context, not a type system.
    public let kind: String?

    public var id: UUID { noteID }

    public init(
        noteID: UUID,
        vaultID: UUID,
        vaultName: String,
        title: String,
        relativePath: String,
        fingerprint: DocumentFingerprint,
        kind: String? = nil
    ) {
        self.noteID = noteID
        self.vaultID = vaultID
        self.vaultName = vaultName
        self.title = title
        self.relativePath = relativePath
        self.fingerprint = fingerprint
        let normalizedKind = kind?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = normalizedKind?.isEmpty == false ? normalizedKind : nil
    }
}

/// A finished Comment exchange captured for one Research Function request
/// together with the exact note identity shown to the agent.
public struct DialogueIncludedComment: Codable, Hashable, Identifiable, Sendable {
    public let note: DialogueNoteReference
    public let exchange: CommentExchange

    public var id: UUID { exchange.id }

    public init(note: DialogueNoteReference, exchange: CommentExchange) {
        self.note = note
        self.exchange = exchange
    }

}

public struct DialogueReply: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let agentName: String
    public let text: String
    public let noteID: UUID?
    public let commentID: UUID?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        agentName: String,
        text: String,
        noteID: UUID? = nil,
        commentID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.agentName = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.noteID = noteID
        self.commentID = commentID
        self.createdAt = createdAt
    }
}

/// An append-only researcher contribution recorded after the initial Dialogue
/// instruction. Follow-ups remain scholarly record content; they are not
/// transport prompts and do not authorize or trigger file changes.
public struct DialogueFollowUpComment: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let text: String
    public let noteID: UUID?
    public let commentID: UUID?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        noteID: UUID? = nil,
        commentID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.noteID = noteID
        self.commentID = commentID
        self.createdAt = createdAt
    }
}

/// A stable chronological projection over the two persisted Dialogue record
/// types. The initial researcher instruction remains on `DialogueEntry` and is
/// presented before these later turns.
public enum DialogueTurn: Hashable, Identifiable, Sendable {
    case researcher(DialogueFollowUpComment)
    case agent(DialogueReply)

    public var id: UUID {
        switch self {
        case .researcher(let comment): comment.id
        case .agent(let reply): reply.id
        }
    }

    public var createdAt: Date {
        switch self {
        case .researcher(let comment): comment.createdAt
        case .agent(let reply): reply.createdAt
        }
    }
}

public struct DialogueEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let triptychID: UUID
    public let instruction: String
    public let selectedNotes: [DialogueNoteReference]
    public let includedComments: [DialogueIncludedComment]
    public let preparedInstructions: String
    public let checkpointID: UUID?
    /// Required current Research Function evidence. Pre-Function Dialogue
    /// records are unsupported by the clean cutover and are never decoded.
    public let functionSnapshot: ResearchFunctionSnapshot
    public let functionCompletion: ResearchFunctionCompletion?
    /// Immutable request-time presentation choices.
    public let responseContract: DialogueResponseContract
    public let requestedDestination: String?
    public let linkedNoteSummary: String?
    public let createdAt: Date
    public var followUpComments: [DialogueFollowUpComment]
    public var replies: [DialogueReply]

    private enum CodingKeys: String, CodingKey {
        case id
        case triptychID
        case instruction
        case selectedNotes
        case includedComments
        case preparedInstructions
        case checkpointID
        case functionSnapshot
        case functionCompletion
        case responseContract
        case requestedDestination
        case linkedNoteSummary
        case createdAt
        case followUpComments
        case replies
    }

    public init(
        id: UUID = UUID(),
        triptychID: UUID,
        instruction: String,
        selectedNotes: [DialogueNoteReference],
        includedComments: [DialogueIncludedComment],
        preparedInstructions: String,
        checkpointID: UUID?,
        functionSnapshot: ResearchFunctionSnapshot,
        functionCompletion: ResearchFunctionCompletion? = nil,
        responseContract: DialogueResponseContract = DialogueResponseContract(
            profile: DialogueResponseProfile()
        ),
        requestedDestination: String? = nil,
        linkedNoteSummary: String? = nil,
        createdAt: Date = Date(),
        followUpComments: [DialogueFollowUpComment] = [],
        replies: [DialogueReply] = []
    ) {
        self.id = id
        self.triptychID = triptychID
        self.instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        self.selectedNotes = selectedNotes
        self.includedComments = includedComments
        self.preparedInstructions = preparedInstructions
        self.checkpointID = checkpointID
        self.functionSnapshot = functionSnapshot
        self.functionCompletion = functionCompletion
        self.responseContract = responseContract
        let normalizedDestination = requestedDestination?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.requestedDestination = normalizedDestination?.isEmpty == false ? normalizedDestination : nil
        let normalizedLinks = linkedNoteSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.linkedNoteSummary = normalizedLinks?.isEmpty == false ? normalizedLinks : nil
        self.createdAt = createdAt
        self.followUpComments = followUpComments
        self.replies = replies
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        triptychID = try container.decode(UUID.self, forKey: .triptychID)
        instruction = try container.decode(String.self, forKey: .instruction)
        selectedNotes = try container.decode([DialogueNoteReference].self, forKey: .selectedNotes)
        includedComments = try container.decodeIfPresent(
            [DialogueIncludedComment].self,
            forKey: .includedComments
        ) ?? []
        preparedInstructions = try container.decode(String.self, forKey: .preparedInstructions)
        checkpointID = try container.decodeIfPresent(UUID.self, forKey: .checkpointID)
        functionSnapshot = try container.decode(
            ResearchFunctionSnapshot.self,
            forKey: .functionSnapshot
        )
        functionCompletion = try container.decodeIfPresent(
            ResearchFunctionCompletion.self,
            forKey: .functionCompletion
        )
        responseContract = try container.decode(
            DialogueResponseContract.self,
            forKey: .responseContract
        )
        requestedDestination = try container.decodeIfPresent(String.self, forKey: .requestedDestination)
        linkedNoteSummary = try container.decodeIfPresent(String.self, forKey: .linkedNoteSummary)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        followUpComments = try container.decodeIfPresent(
            [DialogueFollowUpComment].self,
            forKey: .followUpComments
        ) ?? []
        replies = try container.decodeIfPresent([DialogueReply].self, forKey: .replies) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(triptychID, forKey: .triptychID)
        try container.encode(instruction, forKey: .instruction)
        try container.encode(selectedNotes, forKey: .selectedNotes)
        try container.encode(includedComments, forKey: .includedComments)
        try container.encode(preparedInstructions, forKey: .preparedInstructions)
        try container.encodeIfPresent(checkpointID, forKey: .checkpointID)
        try container.encode(functionSnapshot, forKey: .functionSnapshot)
        try container.encodeIfPresent(functionCompletion, forKey: .functionCompletion)
        try container.encode(responseContract, forKey: .responseContract)
        try container.encodeIfPresent(requestedDestination, forKey: .requestedDestination)
        try container.encodeIfPresent(linkedNoteSummary, forKey: .linkedNoteSummary)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(followUpComments, forKey: .followUpComments)
        try container.encode(replies, forKey: .replies)
    }

    public var chronologicalTurns: [DialogueTurn] {
        let turns = followUpComments.map(DialogueTurn.researcher)
            + replies.map(DialogueTurn.agent)
        return turns.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

public struct DialoguePromptContext: Sendable {
    public let instruction: String
    public let selectedNotes: [DialogueNoteReference]
    public let comments: [DialogueIncludedComment]
    public let triptychSummary: String?
    public let linkedNoteSummary: String?
    public let requestedDestination: String?
    public let editingRules: String

    public init(
        instruction: String,
        selectedNotes: [DialogueNoteReference],
        comments: [DialogueIncludedComment] = [],
        triptychSummary: String? = nil,
        linkedNoteSummary: String? = nil,
        requestedDestination: String? = nil,
        editingRules: String = "Preserve source fidelity, provenance, uncertainty, and exact Markdown outside intended edits."
    ) {
        self.instruction = instruction
        self.selectedNotes = selectedNotes
        self.comments = comments
        self.triptychSummary = triptychSummary
        self.linkedNoteSummary = linkedNoteSummary
        self.requestedDestination = requestedDestination
        self.editingRules = editingRules
    }
}

public enum DialoguePromptBuilder {
    public static func build(
        _ context: DialoguePromptContext,
        template: String = TriptychSettings.defaultDialoguePromptTemplate
    ) -> String {
        var selectedNoteLines: [String] = []
        for note in context.selectedNotes {
            selectedNoteLines.append("- \(note.title)")
            selectedNoteLines.append("  Vault: \(note.vaultName)")
            selectedNoteLines.append("  Path: \(note.relativePath)")
            selectedNoteLines.append("  Advisory SHA-256: \(note.fingerprint.sha256)")
            if let kind = note.kind {
                selectedNoteLines.append("  Kind: \(kind)")
            }
        }
        var commentLines: [String] = []
        for includedComment in context.comments {
            let exchange = includedComment.exchange
            let note = includedComment.note
            let anchor = exchange.anchor
            commentLines.append("- Note: \(note.title)")
            commentLines.append("  Comment ID: \(exchange.id.uuidString)")
            commentLines.append("  Note ID: \(note.noteID.uuidString)")
            commentLines.append("  Vault: \(note.vaultName)")
            commentLines.append("  Path: \(note.relativePath)")
            commentLines.append("  Location: Lines \(anchor.line)–\(anchor.endLine)")
            commentLines.append("  Selected text: \(anchor.quotation)")
            for turn in exchange.turns {
                let author = turn.author == .researcher ? "Researcher" : "Agent"
                commentLines.append("  \(author): \(turn.text)")
            }
        }
        let replacements = [
            "{{researcher_instruction}}": context.instruction.trimmingCharacters(in: .whitespacesAndNewlines),
            "{{selected_notes}}": selectedNoteLines.joined(separator: "\n"),
            "{{triptych_context}}": context.triptychSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "None provided.",
            "{{researcher_comments}}": commentLines.isEmpty ? "None included." : commentLines.joined(separator: "\n"),
            "{{linked_note_context}}": context.linkedNoteSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "None available.",
            "{{requested_destination}}": {
                let value = context.requestedDestination?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return value.isEmpty ? "No destination specified." : value
            }(),
            "{{editing_rules}}": context.editingRules,
        ]
        return replacements.reduce(template) { result, replacement in
            result.replacingOccurrences(of: replacement.key, with: replacement.value)
        }
    }
}

public enum DialogueError: LocalizedError, Sendable {
    case emptyInstruction
    case noSelectedNotes
    case invalidCommentOwner
    case entryNotFound(UUID)
    case invalidReplyTarget
    case emptyFollowUpComment
    case emptyReply
    case emptyAgentName
    case duplicateFollowUpComment(UUID)
    case duplicateReply(UUID)
    case noteReferencePathMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .emptyInstruction: return "Write an instruction before copying it for an agent."
        case .noSelectedNotes: return "Select at least one note for Discuss."
        case .invalidCommentOwner: return "Every included comment must identify one selected source note."
        case .entryNotFound(let id): return "Discussion record not found: \(id.uuidString)"
        case .invalidReplyTarget: return "The selected target is not part of this Discussion."
        case .emptyFollowUpComment: return "Write a follow-up before adding it to Discuss."
        case .emptyReply: return "An agent reply cannot be empty."
        case .emptyAgentName: return "Identify the agent before recording its reply."
        case .duplicateFollowUpComment(let id): return "Discuss follow-up already recorded: \(id.uuidString)"
        case .duplicateReply(let id): return "Discuss reply already recorded: \(id.uuidString)"
        case .noteReferencePathMismatch(let expected, let actual):
            return "The Discussion note reference is at '\(actual)', not the expected path '\(expected)'."
        }
    }
}

public enum CritiqueFindingDispositionDecision: String, Codable, CaseIterable, Hashable, Sendable {
    case accept
    case reject
    case rebut
}

public struct CritiqueFindingDisposition: Codable, Hashable, Identifiable, Sendable {
    public var id: String { findingID }
    public let findingID: String
    public let decision: CritiqueFindingDispositionDecision
    public let rationale: String?
    /// Exact Work revision observed when an accepted finding was recorded
    /// after a text change. This does not claim which bytes addressed it.
    public let acceptedRevision: DocumentFingerprint?
    /// Researcher-authored explanation used only when Accept requires no text
    /// change. It is mutually exclusive with `acceptedRevision`.
    public let noTextChangeRationale: String?
    public let disposedAt: Date

    public init(
        findingID: String,
        decision: CritiqueFindingDispositionDecision,
        rationale: String? = nil,
        acceptedRevision: DocumentFingerprint? = nil,
        noTextChangeRationale: String? = nil,
        disposedAt: Date = Date()
    ) {
        self.findingID = findingID
        self.decision = decision
        let normalizedRationale = rationale?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rationale = normalizedRationale?.isEmpty == false ? normalizedRationale : nil
        self.acceptedRevision = acceptedRevision
        let normalizedNoChange = noTextChangeRationale?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.noTextChangeRationale = normalizedNoChange?.isEmpty == false
            ? normalizedNoChange
            : nil
        self.disposedAt = disposedAt
    }

    public var satisfiesRoundCompletion: Bool {
        switch decision {
        case .accept:
            (acceptedRevision != nil) != (noTextChangeRationale != nil)
        case .reject, .rebut:
            true
        }
    }
}

public struct CritiqueRound: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let requestedAt: Date
    public let targetFingerprint: DocumentFingerprint
    public let checkpointID: UUID?
    public let scope: CritiqueRequestScope
    public let functionSnapshot: ResearchFunctionSnapshot?
    public let functionCompletion: ResearchFunctionCompletion?
    public let functionInstructions: String?
    public let actionableFindings: [CritiqueFinding]
    public let localExecutionFindingsCaptured: Bool
    public let findingDispositions: [CritiqueFindingDisposition]
    public let completedAt: Date?

    public init(
        id: UUID = UUID(),
        requestedAt: Date = Date(),
        targetFingerprint: DocumentFingerprint,
        checkpointID: UUID?,
        scope: CritiqueRequestScope,
        functionSnapshot: ResearchFunctionSnapshot? = nil,
        functionCompletion: ResearchFunctionCompletion? = nil,
        functionInstructions: String? = nil,
        actionableFindings: [CritiqueFinding] = [],
        localExecutionFindingsCaptured: Bool = false,
        findingDispositions: [CritiqueFindingDisposition] = [],
        completedAt: Date? = nil
    ) {
        self.id = id
        self.requestedAt = requestedAt
        self.targetFingerprint = targetFingerprint
        self.checkpointID = checkpointID
        self.scope = scope
        self.functionSnapshot = functionSnapshot
        self.functionCompletion = functionCompletion
        let normalized = functionInstructions?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.functionInstructions = normalized?.isEmpty == false ? normalized : nil
        self.actionableFindings = Self.uniqueFindings(actionableFindings)
        self.localExecutionFindingsCaptured = localExecutionFindingsCaptured
        let actionableIDs = Set(self.actionableFindings.map(\.id))
        self.findingDispositions = Dictionary(
            findingDispositions
                .filter { actionableIDs.contains($0.findingID) }
                .map { ($0.findingID, $0) },
            uniquingKeysWith: { _, newest in newest }
        ).values.sorted { $0.findingID < $1.findingID }
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, requestedAt, targetFingerprint, checkpointID, scope
        case functionSnapshot, functionCompletion, functionInstructions
        case actionableFindings, localExecutionFindingsCaptured
        case findingDispositions, completedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            requestedAt: try container.decode(Date.self, forKey: .requestedAt),
            targetFingerprint: try container.decode(
                DocumentFingerprint.self,
                forKey: .targetFingerprint
            ),
            checkpointID: try container.decodeIfPresent(UUID.self, forKey: .checkpointID),
            scope: try container.decode(CritiqueRequestScope.self, forKey: .scope),
            functionSnapshot: try container.decodeIfPresent(
                ResearchFunctionSnapshot.self,
                forKey: .functionSnapshot
            ),
            functionCompletion: try container.decodeIfPresent(
                ResearchFunctionCompletion.self,
                forKey: .functionCompletion
            ),
            functionInstructions: try container.decodeIfPresent(
                String.self,
                forKey: .functionInstructions
            ),
            actionableFindings: try container.decodeIfPresent(
                [CritiqueFinding].self,
                forKey: .actionableFindings
            ) ?? [],
            localExecutionFindingsCaptured: try container.decodeIfPresent(
                Bool.self,
                forKey: .localExecutionFindingsCaptured
            ) ?? false,
            findingDispositions: try container.decodeIfPresent(
                [CritiqueFindingDisposition].self,
                forKey: .findingDispositions
            ) ?? [],
            completedAt: try container.decodeIfPresent(Date.self, forKey: .completedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(requestedAt, forKey: .requestedAt)
        try container.encode(targetFingerprint, forKey: .targetFingerprint)
        try container.encodeIfPresent(checkpointID, forKey: .checkpointID)
        try container.encode(scope, forKey: .scope)
        try container.encodeIfPresent(functionSnapshot, forKey: .functionSnapshot)
        try container.encodeIfPresent(functionCompletion, forKey: .functionCompletion)
        try container.encodeIfPresent(functionInstructions, forKey: .functionInstructions)
        if !actionableFindings.isEmpty {
            try container.encode(actionableFindings, forKey: .actionableFindings)
        }
        if localExecutionFindingsCaptured {
            try container.encode(true, forKey: .localExecutionFindingsCaptured)
        }
        if !findingDispositions.isEmpty {
            try container.encode(findingDispositions, forKey: .findingDispositions)
        }
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
    }

    public var isReadyToComplete: Bool {
        guard completedAt == nil, !actionableFindings.isEmpty else { return false }
        let dispositions = Dictionary(
            uniqueKeysWithValues: findingDispositions.map { ($0.findingID, $0) }
        )
        return actionableFindings.allSatisfy {
            dispositions[$0.id]?.satisfiesRoundCompletion == true
        }
    }

    private static func uniqueFindings(_ findings: [CritiqueFinding]) -> [CritiqueFinding] {
        var seen: Set<String> = []
        return findings.filter { seen.insert($0.id).inserted }
    }
}

public struct CritiqueAssociation: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let workNoteID: UUID
    public var workRelativePath: String
    public var targetFingerprint: DocumentFingerprint
    public var critiqueRelativePath: String
    public let createdAt: Date
    public var updatedAt: Date
    public var rounds: [CritiqueRound]

    public init(
        id: UUID = UUID(),
        workNoteID: UUID,
        workRelativePath: String,
        targetFingerprint: DocumentFingerprint,
        critiqueRelativePath: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        rounds: [CritiqueRound] = []
    ) {
        self.id = id
        self.workNoteID = workNoteID
        self.workRelativePath = workRelativePath
        self.targetFingerprint = targetFingerprint
        self.critiqueRelativePath = critiqueRelativePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rounds = rounds
    }

    private enum CodingKeys: String, CodingKey {
        case id, workNoteID, workRelativePath, targetFingerprint
        case critiqueRelativePath, createdAt, updatedAt, rounds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        workNoteID = try container.decode(UUID.self, forKey: .workNoteID)
        workRelativePath = try container.decode(String.self, forKey: .workRelativePath)
        targetFingerprint = try container.decode(DocumentFingerprint.self, forKey: .targetFingerprint)
        critiqueRelativePath = try container.decode(String.self, forKey: .critiqueRelativePath)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        rounds = try container.decodeIfPresent([CritiqueRound].self, forKey: .rounds) ?? []
    }
}

public enum CritiqueRequestScope: String, Codable, CaseIterable, Sendable {
    case overall = "Overall Critique"
    case specific = "Specific Comments"
    case both = "Both"
}

public struct CritiquePromptContext: Sendable {
    public let template: String
    public let scope: CritiqueRequestScope
    public let lens: String
    public let selectedRanges: String
    public let additionalInstructions: String
    public let workTitle: String
    public let workRelativePath: String
    public let workFingerprint: DocumentFingerprint
    public let critiqueRelativePath: String

    public init(
        template: String,
        scope: CritiqueRequestScope,
        lens: String = "",
        selectedRanges: String = "",
        additionalInstructions: String = "",
        workTitle: String,
        workRelativePath: String,
        workFingerprint: DocumentFingerprint,
        critiqueRelativePath: String
    ) {
        self.template = template
        self.scope = scope
        self.lens = lens
        self.selectedRanges = selectedRanges
        self.additionalInstructions = additionalInstructions
        self.workTitle = workTitle
        self.workRelativePath = workRelativePath
        self.workFingerprint = workFingerprint
        self.critiqueRelativePath = critiqueRelativePath
    }
}

public enum CritiquePromptBuilder {
    public static func build(_ context: CritiquePromptContext) -> String {
        let replacements = [
            "{{critique_scope}}": context.scope.rawValue,
            "{{critique_lens}}": context.lens.isEmpty ? "No additional lens specified" : context.lens,
            "{{selected_ranges}}": context.selectedRanges.isEmpty ? "No passage specified" : context.selectedRanges,
            "{{additional_instructions}}": context.additionalInstructions.isEmpty
                ? "No additional instructions"
                : context.additionalInstructions,
        ]
        var body = context.template
        for (placeholder, value) in replacements {
            body = body.replacingOccurrences(of: placeholder, with: value)
        }
        return [
            "Scholium Critique request",
            "Target Work: \(context.workTitle)",
            "Target path: \(context.workRelativePath)",
            "Target advisory SHA-256: \(context.workFingerprint.sha256)",
            "Write Critique to: \(context.critiqueRelativePath)",
            "Keep critique_authorship as agent, critique_target_path as \(context.workRelativePath), and critique_target_fingerprint as \(context.workFingerprint.sha256).",
            "Under Specific Findings, give each finding a level-three heading and the fields Target Work, Target fingerprint, Target heading or Target line, and Target quotation when available.",
            "",
            body,
        ].joined(separator: "\n")
    }
}

public enum CritiquePlacementError: LocalizedError, Sendable {
    case invalidCritiquePath(String)
    case crossesCritiqueBoundary(source: String, destination: String)
    case directCreationRequiresRequestCritique
    case duplicateNotSupported
    case malformedFrontmatter

    public var errorDescription: String? {
        switch self {
        case .invalidCritiquePath(let path):
            "A Critique must remain inside the Works/Critiques folder: \(path)"
        case .crossesCritiqueBoundary(let source, let destination):
            "Scholium cannot move a Critique outside Works/Critiques or turn an ordinary Work into a Critique by moving it there. Move within Critiques, use Set Aside or Trash, or cancel. (\(source) → \(destination))"
        case .directCreationRequiresRequestCritique:
            "Use Request Critique on a Work to create its associated Critique."
        case .duplicateNotSupported:
            "A Work has at most one current Critique. Request another Critique round instead of duplicating the Critique document."
        case .malformedFrontmatter:
            "The existing Critique begins with malformed or unterminated YAML. Repair it in an external editor before requesting another round."
        }
    }
}

public enum CritiquePlacement {
    public static func isActiveCritiquePath(_ relativePath: String) -> Bool {
        return relativePath.hasPrefix("Critiques/")
            && relativePath.lowercased().hasSuffix(".md")
            && !relativePath.dropFirst("Critiques/".count).isEmpty
    }

    public static func isManagedCritiquePath(_ relativePath: String) -> Bool {
        isActiveCritiquePath(workspacePath(from: relativePath))
    }

    public static func validateOrdinaryMove(from source: String, to destination: String) throws {
        let sourceIsCritique = isManagedCritiquePath(source)
        let destinationIsCritique = isManagedCritiquePath(destination)
        guard sourceIsCritique == destinationIsCritique else {
            throw CritiquePlacementError.crossesCritiqueBoundary(source: source, destination: destination)
        }
    }

    private static func workspacePath(from relativePath: String) -> String {
        for prefix in ["Set Aside/", "Trash/"] where relativePath.hasPrefix(prefix) {
            return String(relativePath.dropFirst(prefix.count))
        }
        return relativePath
    }
}

public struct CritiqueDocumentMetadata: Codable, Hashable, Sendable {
    public let authorship: String?
    public let targetRelativePath: String?
    public let targetFingerprintSHA256: String?
    public let requestedAt: Date?
    public let scope: CritiqueRequestScope?

    public var isAgentAttributed: Bool {
        authorship?.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("agent") == .orderedSame
    }
}

public enum CritiqueFindingJudgment: String, Codable, Hashable, Sendable {
    case traced = "Traced"
    case untraced = "Untraced"
    case disputed = "Disputed"
    case beyondSources = "Beyond Sources"
    case unspecified = "Finding"
}

public struct CritiqueFinding: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(critiqueSourceLine):\(title)" }
    public let judgment: CritiqueFindingJudgment
    public let title: String
    public let critiqueSourceLine: Int
    public let targetRelativePath: String?
    public let targetFingerprintSHA256: String?
    public let targetHeading: String?
    public let targetLine: Int?
    public let targetQuotation: String?

    public init(
        judgment: CritiqueFindingJudgment,
        title: String,
        critiqueSourceLine: Int,
        targetRelativePath: String? = nil,
        targetFingerprintSHA256: String? = nil,
        targetHeading: String? = nil,
        targetLine: Int? = nil,
        targetQuotation: String? = nil
    ) {
        self.judgment = judgment
        self.title = title
        self.critiqueSourceLine = critiqueSourceLine
        self.targetRelativePath = targetRelativePath
        self.targetFingerprintSHA256 = targetFingerprintSHA256
        self.targetHeading = targetHeading
        self.targetLine = targetLine
        self.targetQuotation = targetQuotation
    }

    /// Resolves only explicit source information. Ambiguous quotations never
    /// select an arbitrary occurrence.
    public func resolvedTargetLine(in document: NoteDocument) -> Int? {
        if let targetLine,
           targetLine > 0,
           targetLine <= document.rawContent.components(separatedBy: .newlines).count {
            return targetLine
        }
        if let targetHeading {
            let matching = MarkdownSemanticDocument(parsing: document).headings.filter {
                $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(targetHeading.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
            }
            if matching.count == 1 { return matching[0].span.start.line }
        }
        if let targetQuotation, !targetQuotation.isEmpty {
            var ranges: [Range<String.Index>] = []
            var searchStart = document.rawContent.startIndex
            while searchStart < document.rawContent.endIndex,
                  let range = document.rawContent.range(of: targetQuotation, range: searchStart..<document.rawContent.endIndex) {
                ranges.append(range)
                searchStart = range.upperBound
            }
            if ranges.count == 1 {
                return document.rawContent[..<ranges[0].lowerBound].reduce(1) { count, character in
                    character == "\n" ? count + 1 : count
                }
            }
        }
        return nil
    }
}

public enum CritiqueDocumentContract {
    public static let authorshipKey = "critique_authorship"
    public static let targetPathKey = "critique_target_path"
    public static let targetFingerprintKey = "critique_target_fingerprint"
    public static let requestedAtKey = "critique_requested_at"
    public static let requestScopeKey = "critique_request_scope"

    public static func scaffold(
        title: String,
        targetRelativePath: String,
        targetFingerprint: DocumentFingerprint,
        scope: CritiqueRequestScope,
        requestedAt: Date = Date()
    ) -> String {
        let timestamp = timestampString(requestedAt)
        let headingTitle = title
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return """
        ---
        \(authorshipKey): agent
        \(targetPathKey): \(quoted(targetRelativePath))
        \(targetFingerprintKey): \(targetFingerprint.sha256)
        \(requestedAtKey): \(quoted(timestamp))
        \(requestScopeKey): \(quoted(scope.rawValue))
        ---
        # Critique: \(headingTitle)

        ## Overall Assessment

        ## Strengths

        ## Major Concerns

        ## Source Support

        ## Objections and Alternatives

        ## Revision Priorities

        ## Specific Findings

        <!-- For each finding, use a level-three heading and list Target Work,
        Target fingerprint, Target heading or Target line, and Target quotation
        when available. Scholium uses those explicit fields for source navigation. -->

        ## Materials Consulted and Limitations
        """ + "\n"
    }

    public static func requestEdits(
        targetRelativePath: String,
        targetFingerprint: DocumentFingerprint,
        scope: CritiqueRequestScope,
        requestedAt: Date = Date()
    ) -> [String: FrontmatterEditValue] {
        [
            authorshipKey: .string("agent"),
            targetPathKey: .string(targetRelativePath),
            targetFingerprintKey: .string(targetFingerprint.sha256),
            requestedAtKey: .string(timestampString(requestedAt)),
            requestScopeKey: .string(scope.rawValue),
        ]
    }

    /// Adds a new metadata block to a Critique that has no frontmatter,
    /// preserving every existing source byte after the optional BOM.
    public static func sourceByAddingRequestMetadata(
        to document: NoteDocument,
        targetRelativePath: String,
        targetFingerprint: DocumentFingerprint,
        scope: CritiqueRequestScope,
        requestedAt: Date = Date()
    ) throws -> String {
        guard document.rawFrontmatter == nil else { return document.rawContent }
        var existing = document.rawContent
        let bom: String
        if existing.unicodeScalars.first?.value == 0xFEFF {
            bom = "\u{FEFF}"
            existing.removeFirst()
        } else {
            bom = ""
        }
        let firstLine = existing.split(whereSeparator: \.isNewline)
            .first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard firstLine != "---" else {
            throw CritiquePlacementError.malformedFrontmatter
        }
        let newline = document.newlineStyle.sequence
        let orderedKeys = [authorshipKey, targetPathKey, targetFingerprintKey, requestedAtKey, requestScopeKey]
        let values: [String: String] = [
            authorshipKey: "agent",
            targetPathKey: quoted(targetRelativePath),
            targetFingerprintKey: targetFingerprint.sha256,
            requestedAtKey: quoted(timestampString(requestedAt)),
            requestScopeKey: quoted(scope.rawValue),
        ]
        let frontmatter = (["---"] + orderedKeys.compactMap { key in
            values[key].map { "\(key): \($0)" }
        } + ["---", ""]).joined(separator: newline)
        return bom + frontmatter + existing
    }

    public static func metadata(in document: NoteDocument) -> CritiqueDocumentMetadata {
        let values = document.parsedFrontmatter
        let fingerprint: String?
        if let sha = values[targetFingerprintKey]?.scalarString,
           sha.count == 64,
           sha.allSatisfy({ $0.isHexDigit }) {
            fingerprint = sha.lowercased()
        } else {
            fingerprint = nil
        }
        let scope = values[requestScopeKey]?.scalarString.flatMap(CritiqueRequestScope.init(rawValue:))
        let requestedAt = values[requestedAtKey]?.scalarString.flatMap(timestampDate)
        return CritiqueDocumentMetadata(
            authorship: values[authorshipKey]?.scalarString,
            targetRelativePath: values[targetPathKey]?.scalarString,
            targetFingerprintSHA256: fingerprint,
            requestedAt: requestedAt,
            scope: scope
        )
    }

    public static func findings(in document: NoteDocument) -> [CritiqueFinding] {
        let metadata = metadata(in: document)
        let lines = document.rawContent.components(separatedBy: .newlines)
        var inSpecificFindings = false
        var inFence = false
        var current: FindingBuilder?
        var result: [CritiqueFinding] = []

        func finish(_ builder: FindingBuilder?) -> CritiqueFinding? {
            guard let builder,
                  builder.targetLine != nil || builder.targetHeading != nil || builder.targetQuotation != nil else {
                return nil
            }
            return builder.build(defaultMetadata: metadata)
        }

        for (offset, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }
            if line.hasPrefix("## ") && !line.hasPrefix("### ") {
                if let finding = finish(current) { result.append(finding) }
                current = nil
                inSpecificFindings = String(line.dropFirst(3))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare("Specific Findings") == .orderedSame
                continue
            }
            guard inSpecificFindings else { continue }
            if line.hasPrefix("### ") {
                if let finding = finish(current) { result.append(finding) }
                current = FindingBuilder(heading: String(line.dropFirst(4)), sourceLine: offset + 1)
                continue
            }
            guard var builder = current,
                  let pair = labelledValue(in: line) else { continue }
            builder.consume(label: pair.label, value: pair.value)
            current = builder
        }
        if let finding = finish(current) { result.append(finding) }
        return result
    }

    private struct FindingBuilder {
        let judgment: CritiqueFindingJudgment
        let title: String
        let sourceLine: Int
        var targetRelativePath: String?
        var targetFingerprintSHA256: String?
        var targetHeading: String?
        var targetLine: Int?
        var targetQuotation: String?

        init(heading: String, sourceLine: Int) {
            let cleaned = clean(heading)
            let lower = cleaned.lowercased()
            let matched: (CritiqueFindingJudgment, String)? = [
                (.beyondSources, "beyond sources"),
                (.untraced, "untraced"),
                (.disputed, "disputed"),
                (.traced, "traced"),
            ].first { lower.hasPrefix($0.1) }
            judgment = matched?.0 ?? .unspecified
            if let (matchedJudgment, prefix) = matched {
                var remainder = String(cleaned.dropFirst(prefix.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " :—–-"))
                if remainder.isEmpty { remainder = matchedJudgment.rawValue }
                title = remainder
            } else {
                title = cleaned.isEmpty ? CritiqueFindingJudgment.unspecified.rawValue : cleaned
            }
            self.sourceLine = sourceLine
        }

        mutating func consume(label: String, value: String) {
            switch normalized(label) {
            case "target", "targetwork", "targetpath", "work": targetRelativePath = clean(value)
            case "targetfingerprint", "fingerprint", "targetsha256", "sha256":
                let sha = clean(value).lowercased()
                if sha.count == 64, sha.allSatisfy({ $0.isHexDigit }) {
                    targetFingerprintSHA256 = sha
                }
            case "targetheading", "heading", "section": targetHeading = clean(value)
            case "targetline", "line", "originalline":
                targetLine = clean(value).split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.first
            case "targetquotation", "quotation", "quote": targetQuotation = clean(value)
            default: break
            }
        }

        func build(defaultMetadata: CritiqueDocumentMetadata) -> CritiqueFinding {
            CritiqueFinding(
                judgment: judgment,
                title: title,
                critiqueSourceLine: sourceLine,
                targetRelativePath: targetRelativePath ?? defaultMetadata.targetRelativePath,
                targetFingerprintSHA256: targetFingerprintSHA256 ?? defaultMetadata.targetFingerprintSHA256,
                targetHeading: targetHeading,
                targetLine: targetLine,
                targetQuotation: targetQuotation
            )
        }
    }

    private static func labelledValue(in line: String) -> (label: String, value: String)? {
        var value = line
        if value.hasPrefix("-") || value.hasPrefix("*") { value.removeFirst() }
        value = value.trimmingCharacters(in: .whitespaces)
        guard let colon = value.firstIndex(of: ":") else { return nil }
        let label = clean(String(value[..<colon]))
        let content = clean(String(value[value.index(after: colon)...]))
        guard !label.isEmpty, !content.isEmpty else { return nil }
        return (label, content)
    }

    private static func normalized(_ value: String) -> String {
        clean(value).lowercased().filter(\.isLetter)
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "`*_“”\"")))
    }

    private static func timestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func timestampDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func quoted(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
}

public enum CritiqueRegistryError: LocalizedError, Sendable {
    case destinationAlreadyAssociated(String)
    case workPathMismatch(expected: String, actual: String)
    case roundNotFound(UUID)
    case roundNotReady(UUID)
    case roundAlreadyCompleted(UUID)
    case findingSetAlreadyCaptured(UUID)
    case findingNotFound(String)
    case acceptRequiresChangeOrRationale(String)
    case incompleteDispositions(UUID)

    public var errorDescription: String? {
        switch self {
        case .destinationAlreadyAssociated(let path):
            "The Critique at \(path) is already associated with another Work."
        case .workPathMismatch(let expected, let actual):
            "The Critique association expected its Work at \(expected), but it currently records \(actual)."
        case .roundNotFound(let id):
            "Critique round was not found: \(id.uuidString)"
        case .roundNotReady(let id):
            "Critique round is not ready for finding disposition: \(id.uuidString)"
        case .roundAlreadyCompleted(let id):
            "Critique round is already complete: \(id.uuidString)"
        case .findingSetAlreadyCaptured(let id):
            "The actionable finding set is already fixed for Critique round \(id.uuidString)."
        case .findingNotFound(let id):
            "Critique finding was not found in the fixed round: \(id)"
        case .acceptRequiresChangeOrRationale(let id):
            "Accept requires a changed Work revision or an explicit no-text-change rationale for finding \(id)."
        case .incompleteDispositions(let id):
            "Every actionable finding must be disposed before completing Critique round \(id.uuidString)."
        }
    }
}
