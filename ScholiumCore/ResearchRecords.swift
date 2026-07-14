import Foundation
import Markdown

private func persistentlyEquivalent<T: Encodable>(_ lhs: T, _ rhs: T) throws -> Bool {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(lhs) == encoder.encode(rhs)
}

public enum NoteQualification: String, Codable, CaseIterable, Sendable {
    case qualified
    case unqualified
}

/// Researcher-facing state for the exact current fingerprint. Qualification
/// takes precedence over the generic fact that a revision has been reviewed.
public enum HumanReviewDisplayState: Equatable, Sendable {
    case notReviewed
    case reviewed
    case qualified
    case unqualified

    public init(isReviewed: Bool, qualification: NoteQualification?) {
        switch qualification {
        case .qualified: self = .qualified
        case .unqualified: self = .unqualified
        case nil: self = isReviewed ? .reviewed : .notReviewed
        }
    }
}

public enum CommentAttachmentState: String, Codable, Sendable {
    case attached
    case needsReattachment
}

public struct ResearcherCommentAnchor: Codable, Hashable, Sendable {
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
public enum ResearcherCommentAnchorBuilder {
    public static let contextLength = 48

    public static func anchor(
        in source: String,
        fingerprint: DocumentFingerprint,
        utf16Range: Range<Int>,
        selectedText: String? = nil
    ) -> ResearcherCommentAnchor? {
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

        return ResearcherCommentAnchor(
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
    ) -> ResearcherCommentAnchor? {
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
        for anchor: ResearcherCommentAnchor,
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
    ) -> ResearcherCommentAnchor? {
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

public struct ResearcherComment: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let author: String
    public var text: String
    public var anchor: ResearcherCommentAnchor?
    public let createdAt: Date
    public var updatedAt: Date
    public var resolvedAt: Date?

    public init(
        id: UUID = UUID(),
        author: String = "Researcher",
        text: String,
        anchor: ResearcherCommentAnchor? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.author = author
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.anchor = anchor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resolvedAt = resolvedAt
    }
}

public struct HumanReviewDraft: Codable, Hashable, Sendable {
    public var fingerprint: DocumentFingerprint
    public var qualification: NoteQualification?
    public var reviewNote: String
    public var updatedAt: Date

    public init(
        fingerprint: DocumentFingerprint,
        qualification: NoteQualification? = nil,
        reviewNote: String = "",
        updatedAt: Date = Date()
    ) {
        self.fingerprint = fingerprint
        self.qualification = qualification
        self.reviewNote = reviewNote
        self.updatedAt = updatedAt
    }
}

public struct CompletedHumanReview: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let fingerprint: DocumentFingerprint
    public let qualification: NoteQualification
    public let reviewNote: String
    public let completedAt: Date

    public init(
        id: UUID = UUID(),
        fingerprint: DocumentFingerprint,
        qualification: NoteQualification,
        reviewNote: String,
        completedAt: Date = Date()
    ) {
        self.id = id
        self.fingerprint = fingerprint
        self.qualification = qualification
        self.reviewNote = reviewNote.trimmingCharacters(in: .whitespacesAndNewlines)
        self.completedAt = completedAt
    }
}

public struct HumanReviewRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let vaultID: UUID
    public var relativePath: String
    public var draft: HumanReviewDraft?
    public var completedReviews: [CompletedHumanReview]
    public var comments: [ResearcherComment]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        noteID: UUID,
        vaultID: UUID,
        relativePath: String,
        draft: HumanReviewDraft? = nil,
        completedReviews: [CompletedHumanReview] = [],
        comments: [ResearcherComment] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        id = noteID
        self.vaultID = vaultID
        self.relativePath = relativePath
        self.draft = draft
        self.completedReviews = completedReviews.sorted { $0.completedAt < $1.completedAt }
        self.comments = comments.sorted { $0.createdAt < $1.createdAt }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var latestReview: CompletedHumanReview? {
        completedReviews.max { $0.completedAt < $1.completedAt }
    }

    public func review(for fingerprint: DocumentFingerprint) -> CompletedHumanReview? {
        completedReviews.last { $0.fingerprint == fingerprint }
    }

    public func hasChangedSinceReview(current fingerprint: DocumentFingerprint) -> Bool {
        guard let latestReview else { return false }
        return latestReview.fingerprint != fingerprint
    }
}

public enum HumanReviewError: LocalizedError, Sendable {
    case recordNotFound(UUID)
    case commentNotFound(UUID)
    case emptyComment
    case missingQualification
    case emptyReviewNote
    case reviewNoteTooLong
    case recordVaultMismatch
    case recordPathMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .recordNotFound(let id): return "Human Review record not found: \(id.uuidString)"
        case .commentNotFound(let id): return "Researcher comment not found: \(id.uuidString)"
        case .emptyComment: return "A comment cannot be empty."
        case .missingQualification: return "Choose Qualified or Unqualified to complete Review."
        case .emptyReviewNote: return "Write a Review Note before completing Review."
        case .reviewNoteTooLong: return "The Review Note must be 500 characters or fewer."
        case .recordVaultMismatch: return "The Human Review record belongs to a different vault."
        case .recordPathMismatch(let expected, let actual):
            return "The Human Review record is at '\(actual)', not the expected path '\(expected)'."
        }
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

/// One atomic store owns Human Review, qualification, and researcher comments.
public actor HumanReviewStore {
    private struct Payload: Codable {
        let schemaVersion: Int
        var records: [UUID: HumanReviewRecord]
    }

    public let storageURL: URL
    private let fileURL: URL
    private let fileManager: FileManager
    private var records: [UUID: HumanReviewRecord]
    private let loadFailure: String?

    public init(storageURL: URL, fileManager: FileManager = .default) {
        self.storageURL = storageURL
        fileURL = storageURL.appendingPathComponent("human-reviews.json")
        self.fileManager = fileManager
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                let payload = try decoder.decode(Payload.self, from: data)
                records = payload.records
                loadFailure = payload.schemaVersion == 1
                    ? nil
                    : "Unsupported Human Review schema version \(payload.schemaVersion)."
            } catch {
                records = [:]
                loadFailure = error.localizedDescription
            }
        } else {
            records = [:]
            loadFailure = nil
        }
    }

    public func healthError() -> String? {
        loadFailure.map {
            ResearchRecordStoreError.unreadableStore(kind: "Human Review", reason: $0)
                .localizedDescription
        }
    }

    public func record(noteID: UUID) -> HumanReviewRecord? {
        records[noteID]
    }

    public func record(vaultID: UUID, relativePath: String) -> HumanReviewRecord? {
        records.values.first { $0.vaultID == vaultID && $0.relativePath == relativePath }
    }

    public func allRecords() -> [HumanReviewRecord] {
        records.values.sorted {
            if $0.updatedAt == $1.updatedAt { return $0.relativePath < $1.relativePath }
            return $0.updatedAt > $1.updatedAt
        }
    }

    /// Permanently removes the complete researcher-owned record for one note.
    /// This is intentionally distinct from removing an individual comment and
    /// is used only after the researcher confirms permanent note deletion.
    @discardableResult
    public func purge(noteID: UUID) throws -> HumanReviewRecord? {
        try requireHealthyStore(kind: "Human Review")
        guard let removed = records[noteID] else { return nil }
        var proposed = records
        proposed.removeValue(forKey: noteID)
        try commit(proposed)
        return removed
    }

    func restorePurgedRecord(_ record: HumanReviewRecord) throws {
        try requireHealthyStore(kind: "Human Review")
        if let existing = records[record.id] {
            guard try persistentlyEquivalent(existing, record) else {
                throw ResearchRecordStoreError.restorationConflict(
                    kind: "Human Review",
                    identity: record.id.uuidString
                )
            }
            return
        }
        var proposed = records
        proposed[record.id] = record
        try commit(proposed)
    }

    @discardableResult
    public func saveDraft(
        noteID: UUID,
        vaultID: UUID,
        relativePath: String,
        draft: HumanReviewDraft,
        comments: [ResearcherComment]? = nil
    ) throws -> HumanReviewRecord {
        try validateReviewNoteLength(draft.reviewNote)
        var record = records[noteID] ?? HumanReviewRecord(
            noteID: noteID,
            vaultID: vaultID,
            relativePath: relativePath
        )
        record.relativePath = relativePath
        record.draft = draft
        if let comments { record.comments = comments.sorted { $0.createdAt < $1.createdAt } }
        record.updatedAt = Date()
        var proposed = records
        proposed[noteID] = record
        try commit(proposed)
        return record
    }

    @discardableResult
    public func completeReview(
        noteID: UUID,
        vaultID: UUID,
        relativePath: String,
        fingerprint: DocumentFingerprint,
        qualification: NoteQualification?,
        reviewNote: String,
        comments: [ResearcherComment]? = nil
    ) throws -> HumanReviewRecord {
        guard let qualification else { throw HumanReviewError.missingQualification }
        let note = reviewNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { throw HumanReviewError.emptyReviewNote }
        try validateReviewNoteLength(note)
        var record = records[noteID] ?? HumanReviewRecord(
            noteID: noteID,
            vaultID: vaultID,
            relativePath: relativePath
        )
        record.relativePath = relativePath
        record.completedReviews.append(CompletedHumanReview(
            fingerprint: fingerprint,
            qualification: qualification,
            reviewNote: note
        ))
        if let comments { record.comments = comments.sorted { $0.createdAt < $1.createdAt } }
        record.draft = nil
        record.updatedAt = Date()
        var proposed = records
        proposed[noteID] = record
        try commit(proposed)
        return record
    }

    @discardableResult
    public func addComment(
        noteID: UUID,
        vaultID: UUID,
        relativePath: String,
        comment: ResearcherComment
    ) throws -> HumanReviewRecord {
        guard !comment.text.isEmpty else { throw HumanReviewError.emptyComment }
        var record = records[noteID] ?? HumanReviewRecord(
            noteID: noteID,
            vaultID: vaultID,
            relativePath: relativePath
        )
        record.relativePath = relativePath
        record.comments.append(comment)
        record.comments.sort { $0.createdAt < $1.createdAt }
        record.updatedAt = Date()
        var proposed = records
        proposed[noteID] = record
        try commit(proposed)
        return record
    }

    public func updateCommentText(noteID: UUID, commentID: UUID, text: String) throws {
        guard var record = records[noteID] else { throw HumanReviewError.recordNotFound(noteID) }
        guard let index = record.comments.firstIndex(where: { $0.id == commentID }) else {
            throw HumanReviewError.commentNotFound(commentID)
        }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw HumanReviewError.emptyComment }
        record.comments[index].text = text
        record.comments[index].updatedAt = Date()
        record.updatedAt = Date()
        var proposed = records
        proposed[noteID] = record
        try commit(proposed)
    }

    /// Only the human-facing application calls this operation. Dialogue replies
    /// are immutable agent records and deliberately have no resolution API.
    public func setCommentResolvedByResearcher(
        noteID: UUID,
        commentID: UUID,
        resolved: Bool
    ) throws {
        guard var record = records[noteID] else { throw HumanReviewError.recordNotFound(noteID) }
        guard let index = record.comments.firstIndex(where: { $0.id == commentID }) else {
            throw HumanReviewError.commentNotFound(commentID)
        }
        record.comments[index].resolvedAt = resolved ? Date() : nil
        record.comments[index].updatedAt = Date()
        record.updatedAt = Date()
        var proposed = records
        proposed[noteID] = record
        try commit(proposed)
    }

    public func reattachComment(
        noteID: UUID,
        commentID: UUID,
        to anchor: ResearcherCommentAnchor
    ) throws {
        guard var record = records[noteID] else { throw HumanReviewError.recordNotFound(noteID) }
        guard let index = record.comments.firstIndex(where: { $0.id == commentID }) else {
            throw HumanReviewError.commentNotFound(commentID)
        }
        var anchor = anchor
        anchor.state = .attached
        record.comments[index].anchor = anchor
        record.comments[index].updatedAt = Date()
        record.updatedAt = Date()
        var proposed = records
        proposed[noteID] = record
        try commit(proposed)
    }

    public func removeComment(noteID: UUID, commentID: UUID) throws {
        guard var record = records[noteID] else { throw HumanReviewError.recordNotFound(noteID) }
        guard record.comments.contains(where: { $0.id == commentID }) else {
            throw HumanReviewError.commentNotFound(commentID)
        }
        record.comments.removeAll { $0.id == commentID }
        record.updatedAt = Date()
        var proposed = records
        proposed[noteID] = record
        try commit(proposed)
    }

    public func moveRecord(noteID: UUID, to relativePath: String) throws {
        guard var record = records[noteID] else { throw HumanReviewError.recordNotFound(noteID) }
        record.relativePath = relativePath
        record.updatedAt = Date()
        var proposed = records
        proposed[noteID] = record
        try commit(proposed)
    }

    @discardableResult
    public func migratePathIfPresent(
        noteID: UUID,
        vaultID: UUID,
        from sourcePath: String,
        to destinationPath: String
    ) throws -> Bool {
        guard var record = records[noteID] else { return false }
        guard record.vaultID == vaultID else { throw HumanReviewError.recordVaultMismatch }
        if record.relativePath == destinationPath { return false }
        guard record.relativePath == sourcePath else {
            throw HumanReviewError.recordPathMismatch(
                expected: sourcePath,
                actual: record.relativePath
            )
        }
        record.relativePath = destinationPath
        record.updatedAt = Date()
        var proposed = records
        proposed[noteID] = record
        try commit(proposed)
        return true
    }

    /// Reattaches comments only when quotation and context identify one reliable location.
    public func reattachComments(noteID: UUID, to document: NoteDocument) throws {
        guard var record = records[noteID] else { throw HumanReviewError.recordNotFound(noteID) }
        var changed = false
        record.comments = record.comments.map { comment in
            guard var anchor = comment.anchor else { return comment }
            guard anchor.fingerprint != document.fingerprint || anchor.state == .needsReattachment else {
                return comment
            }
            var updated = comment
            let candidates = Self.ranges(of: anchor.quotation, in: document.rawContent)
            let reliable = candidates.filter { range in
                Self.contextMatches(anchor: anchor, range: range, source: document.rawContent)
            }
            guard reliable.count == 1, let range = reliable.first else {
                anchor.state = .needsReattachment
                updated.anchor = anchor
                updated.updatedAt = Date()
                changed = true
                return updated
            }
            let utf16Start = range.lowerBound.utf16Offset(in: document.rawContent)
            let utf16End = range.upperBound.utf16Offset(in: document.rawContent)
            let prefix = document.rawContent[..<range.lowerBound]
            let startLine = prefix.reduce(into: 1) { if $1.isNewline { $0 += 1 } }
            let selected = document.rawContent[range]
            let endLine = selected.reduce(into: startLine) { if $1.isNewline { $0 += 1 } }
            let utf8Start = Data(document.rawContent[..<range.lowerBound].utf8).count
            let utf8End = Data(document.rawContent[..<range.upperBound].utf8).count
            anchor.fingerprint = document.fingerprint
            anchor.utf8Range = utf8Start..<utf8End
            anchor.utf16Range = utf16Start..<utf16End
            anchor.line = startLine
            anchor.endLine = endLine
            anchor.state = .attached
            updated.anchor = anchor
            updated.updatedAt = Date()
            changed = true
            return updated
        }
        guard changed else { return }
        record.updatedAt = Date()
        var proposed = records
        proposed[noteID] = record
        try commit(proposed)
    }

    private func validateReviewNoteLength(_ reviewNote: String) throws {
        guard reviewNote.count <= 500 else { throw HumanReviewError.reviewNoteTooLong }
    }

    private func commit(_ proposed: [UUID: HumanReviewRecord]) throws {
        try requireHealthyStore(kind: "Human Review")
        try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Payload(schemaVersion: 1, records: proposed)).write(to: fileURL, options: .atomic)
        records = proposed
    }

    private func requireHealthyStore(kind: String) throws {
        if let loadFailure {
            throw ResearchRecordStoreError.unreadableStore(kind: kind, reason: loadFailure)
        }
    }

    private static func ranges(of needle: String, in source: String) -> [Range<String.Index>] {
        guard !needle.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var cursor = source.startIndex
        while cursor < source.endIndex, let range = source.range(of: needle, range: cursor..<source.endIndex) {
            ranges.append(range)
            cursor = range.upperBound
        }
        return ranges
    }

    private static func contextMatches(
        anchor: ResearcherCommentAnchor,
        range: Range<String.Index>,
        source: String
    ) -> Bool {
        let beforeStart = source.index(range.lowerBound, offsetBy: -anchor.contextBefore.count, limitedBy: source.startIndex)
            ?? source.startIndex
        let afterEnd = source.index(range.upperBound, offsetBy: anchor.contextAfter.count, limitedBy: source.endIndex)
            ?? source.endIndex
        let before = String(source[beforeStart..<range.lowerBound])
        let after = String(source[range.upperBound..<afterEnd])
        let beforeMatches = anchor.contextBefore.isEmpty || before.hasSuffix(anchor.contextBefore)
        let afterMatches = anchor.contextAfter.isEmpty || after.hasPrefix(anchor.contextAfter)
        return beforeMatches && afterMatches
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

/// A researcher comment captured for one Dialogue request together with the
/// exact note identity shown to the agent. The note reference is a snapshot of
/// the title, vault-relative path, and advisory fingerprint at request time.
///
/// `note` is optional only so Dialogue records written by builds that stored a
/// bare `ResearcherComment` continue to decode. New Dialogue requests always
/// create this value with a note reference and the UI labels an unresolved
/// legacy owner explicitly instead of presenting an ambiguous line number.
public struct DialogueIncludedComment: Codable, Hashable, Identifiable, Sendable {
    public let note: DialogueNoteReference?
    public let comment: ResearcherComment

    public var id: UUID { comment.id }

    public init(note: DialogueNoteReference, comment: ResearcherComment) {
        self.note = note
        self.comment = comment
    }

    private enum CodingKeys: String, CodingKey {
        case note
        case comment
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.comment) {
            note = try container.decodeIfPresent(DialogueNoteReference.self, forKey: .note)
            comment = try container.decode(ResearcherComment.self, forKey: .comment)
        } else {
            // Compatibility with schema v1, where includedComments contained
            // bare ResearcherComment values and therefore had no note owner.
            note = nil
            comment = try ResearcherComment(from: decoder)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(comment, forKey: .comment)
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
    public let generatedPrompt: String
    public let checkpointID: UUID
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
        case generatedPrompt
        case checkpointID
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
        generatedPrompt: String,
        checkpointID: UUID,
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
        self.generatedPrompt = generatedPrompt
        self.checkpointID = checkpointID
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
        let decodedComments = try container.decodeIfPresent(
            [DialogueIncludedComment].self,
            forKey: .includedComments
        ) ?? []
        if selectedNotes.count == 1, let onlyNote = selectedNotes.first {
            includedComments = decodedComments.map { included in
                included.note == nil
                    ? DialogueIncludedComment(note: onlyNote, comment: included.comment)
                    : included
            }
        } else {
            includedComments = decodedComments
        }
        generatedPrompt = try container.decode(String.self, forKey: .generatedPrompt)
        checkpointID = try container.decode(UUID.self, forKey: .checkpointID)
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
        try container.encode(generatedPrompt, forKey: .generatedPrompt)
        try container.encode(checkpointID, forKey: .checkpointID)
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
            let comment = includedComment.comment
            if let note = includedComment.note {
                commentLines.append("- Note: \(note.title)")
                commentLines.append("  Note ID: \(note.noteID.uuidString)")
                commentLines.append("  Vault: \(note.vaultName)")
                commentLines.append("  Path: \(note.relativePath)")
            } else {
                commentLines.append("- Note: Source note unavailable (legacy Dialogue entry)")
            }
            if let anchor = comment.anchor {
                commentLines.append("  Location: Lines \(anchor.line)–\(anchor.endLine)")
                commentLines.append("  Comment: \(comment.text)")
                commentLines.append("  Selected text: \(anchor.quotation)")
            } else {
                commentLines.append("  Location: Whole note")
                commentLines.append("  Comment: \(comment.text)")
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
        case .noSelectedNotes: return "Select at least one note for Dialogue."
        case .invalidCommentOwner: return "Every included comment must identify one selected source note."
        case .entryNotFound(let id): return "Dialogue entry not found: \(id.uuidString)"
        case .invalidReplyTarget: return "The selected target is not part of this Dialogue entry."
        case .emptyFollowUpComment: return "Write a follow-up Comment before adding it to Dialogue."
        case .emptyReply: return "An agent reply cannot be empty."
        case .emptyAgentName: return "Identify the agent before recording its reply."
        case .duplicateFollowUpComment(let id): return "Dialogue follow-up Comment already recorded: \(id.uuidString)"
        case .duplicateReply(let id): return "Dialogue reply already recorded: \(id.uuidString)"
        case .noteReferencePathMismatch(let expected, let actual):
            return "The Dialogue note reference is at '\(actual)', not the expected path '\(expected)'."
        }
    }
}

public actor DialogueStore {
    private struct Payload: Codable {
        let schemaVersion: Int
        var entries: [UUID: DialogueEntry]
    }

    public let storageURL: URL
    private let fileURL: URL
    private let fileManager: FileManager
    private var entries: [UUID: DialogueEntry]
    private let loadFailure: String?

    public init(storageURL: URL, fileManager: FileManager = .default) {
        self.storageURL = storageURL
        fileURL = storageURL.appendingPathComponent("dialogue.json")
        self.fileManager = fileManager
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                let payload = try decoder.decode(Payload.self, from: data)
                entries = payload.entries
                loadFailure = payload.schemaVersion == 2
                    ? nil
                    : "Unsupported Dialogue schema version \(payload.schemaVersion)."
            } catch {
                entries = [:]
                loadFailure = error.localizedDescription
            }
        } else {
            entries = [:]
            loadFailure = nil
        }
    }

    public func healthError() -> String? {
        loadFailure.map {
            ResearchRecordStoreError.unreadableStore(kind: "Dialogue", reason: $0)
                .localizedDescription
        }
    }

    public func entry(id: UUID) throws -> DialogueEntry {
        guard let entry = entries[id] else { throw DialogueError.entryNotFound(id) }
        return entry
    }

    public func entries(noteID: UUID) -> [DialogueEntry] {
        entries.values.filter { entry in
            entry.selectedNotes.contains { $0.noteID == noteID }
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func allEntries() -> [DialogueEntry] {
        entries.values.sorted { $0.createdAt > $1.createdAt }
    }

    /// Removes every Dialogue containing the note. Shared entries are deleted
    /// in full so permanent deletion cannot retain the deleted note's selected
    /// context, comments, quotations, replies, or generated transport text.
    @discardableResult
    public func purgeEntries(containing noteID: UUID) throws -> [DialogueEntry] {
        try requireHealthyStore(kind: "Dialogue")
        let removed = entries.values.filter { entry in
            entry.selectedNotes.contains { $0.noteID == noteID }
        }
        guard !removed.isEmpty else { return [] }
        let removedIDs = Set(removed.map(\.id))
        let proposed = entries.filter { !removedIDs.contains($0.key) }
        try commit(proposed)
        return removed.sorted { $0.createdAt > $1.createdAt }
    }

    func restorePurgedEntries(_ removed: [DialogueEntry]) throws {
        try requireHealthyStore(kind: "Dialogue")
        var proposed = entries
        for entry in removed {
            if let existing = proposed[entry.id] {
                guard try persistentlyEquivalent(existing, entry) else {
                    throw ResearchRecordStoreError.restorationConflict(
                        kind: "Dialogue",
                        identity: entry.id.uuidString
                    )
                }
                continue
            }
            proposed[entry.id] = entry
        }
        guard proposed != entries else { return }
        try commit(proposed)
    }

    @discardableResult
    public func save(_ entry: DialogueEntry) throws -> DialogueEntry {
        guard !entry.instruction.isEmpty else { throw DialogueError.emptyInstruction }
        guard !entry.selectedNotes.isEmpty else { throw DialogueError.noSelectedNotes }
        let selectedNoteIDs = Set(entry.selectedNotes.map(\.noteID))
        let selectedNoteReferences = Set(entry.selectedNotes)
        guard selectedNoteIDs.count == entry.selectedNotes.count else {
            throw DialogueError.invalidCommentOwner
        }
        guard entry.includedComments.allSatisfy({ included in
            guard let note = included.note else { return false }
            return selectedNoteReferences.contains(note)
        }) else {
            throw DialogueError.invalidCommentOwner
        }
        var proposed = entries
        proposed[entry.id] = entry
        try commit(proposed)
        return entry
    }

    @discardableResult
    public func appendReply(_ reply: DialogueReply, to entryID: UUID) throws -> DialogueEntry {
        guard !reply.text.isEmpty else { throw DialogueError.emptyReply }
        guard !reply.agentName.isEmpty else { throw DialogueError.emptyAgentName }
        guard var entry = entries[entryID] else { throw DialogueError.entryNotFound(entryID) }
        guard !entry.replies.contains(where: { $0.id == reply.id }) else {
            throw DialogueError.duplicateReply(reply.id)
        }
        try validateDialogueTarget(noteID: reply.noteID, commentID: reply.commentID, in: entry)
        entry.replies.append(reply)
        var proposed = entries
        proposed[entryID] = entry
        try commit(proposed)
        return entry
    }

    @discardableResult
    public func appendFollowUpComment(
        _ comment: DialogueFollowUpComment,
        to entryID: UUID
    ) throws -> DialogueEntry {
        guard !comment.text.isEmpty else { throw DialogueError.emptyFollowUpComment }
        guard var entry = entries[entryID] else { throw DialogueError.entryNotFound(entryID) }
        guard !entry.followUpComments.contains(where: { $0.id == comment.id }) else {
            throw DialogueError.duplicateFollowUpComment(comment.id)
        }
        try validateDialogueTarget(
            noteID: comment.noteID,
            commentID: comment.commentID,
            in: entry
        )
        entry.followUpComments.append(comment)
        var proposed = entries
        proposed[entryID] = entry
        try commit(proposed)
        return entry
    }

    private func validateDialogueTarget(
        noteID: UUID?,
        commentID: UUID?,
        in entry: DialogueEntry
    ) throws {
        if let noteID,
           !entry.selectedNotes.contains(where: { $0.noteID == noteID }) {
            throw DialogueError.invalidReplyTarget
        }
        if let commentID,
           !entry.includedComments.contains(where: { $0.comment.id == commentID }) {
            throw DialogueError.invalidReplyTarget
        }
        if let noteID, let commentID,
           !entry.includedComments.contains(where: {
               $0.comment.id == commentID && $0.note?.noteID == noteID
           }) {
            throw DialogueError.invalidReplyTarget
        }
    }

    /// Migrates only the current structured note references. The generated
    /// prompt remains an immutable historical record of what was copied.
    @discardableResult
    public func migratePathIfPresent(
        noteID: UUID,
        vaultID: UUID,
        from sourcePath: String,
        to destinationPath: String
    ) throws -> Int {
        var changedEntries = 0
        var updatedEntries = entries

        for (entryID, entry) in entries {
            let references = entry.selectedNotes.filter {
                $0.noteID == noteID && $0.vaultID == vaultID
            }
            guard !references.isEmpty else { continue }
            if let unexpected = references.first(where: {
                $0.relativePath != sourcePath && $0.relativePath != destinationPath
            }) {
                throw DialogueError.noteReferencePathMismatch(
                    expected: sourcePath,
                    actual: unexpected.relativePath
                )
            }
            guard references.contains(where: { $0.relativePath == sourcePath }) else { continue }

            let migratedNotes = entry.selectedNotes.map { note -> DialogueNoteReference in
                guard note.noteID == noteID,
                      note.vaultID == vaultID,
                      note.relativePath == sourcePath else { return note }
                return DialogueNoteReference(
                    noteID: note.noteID,
                    vaultID: note.vaultID,
                    vaultName: note.vaultName,
                    title: note.title,
                    relativePath: destinationPath,
                    fingerprint: note.fingerprint,
                    kind: note.kind
                )
            }
            let migratedReference = migratedNotes.first {
                $0.noteID == noteID && $0.vaultID == vaultID
            }
            let migratedComments = entry.includedComments.map { included -> DialogueIncludedComment in
                guard let note = included.note,
                      note.noteID == noteID,
                      note.vaultID == vaultID,
                      note.relativePath == sourcePath,
                      let migratedReference else { return included }
                return DialogueIncludedComment(
                    note: migratedReference,
                    comment: included.comment
                )
            }
            updatedEntries[entryID] = DialogueEntry(
                id: entry.id,
                triptychID: entry.triptychID,
                instruction: entry.instruction,
                selectedNotes: migratedNotes,
                includedComments: migratedComments,
                generatedPrompt: entry.generatedPrompt,
                checkpointID: entry.checkpointID,
                requestedDestination: entry.requestedDestination,
                linkedNoteSummary: entry.linkedNoteSummary,
                createdAt: entry.createdAt,
                followUpComments: entry.followUpComments,
                replies: entry.replies
            )
            changedEntries += 1
        }

        guard changedEntries > 0 else { return 0 }
        try commit(updatedEntries)
        return changedEntries
    }

    private func commit(_ proposed: [UUID: DialogueEntry]) throws {
        try requireHealthyStore(kind: "Dialogue")
        try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Payload(schemaVersion: 2, entries: proposed)).write(to: fileURL, options: .atomic)
        entries = proposed
    }

    private func requireHealthyStore(kind: String) throws {
        if let loadFailure {
            throw ResearchRecordStoreError.unreadableStore(kind: kind, reason: loadFailure)
        }
    }
}

public struct CritiqueRound: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let requestedAt: Date
    public let targetFingerprint: DocumentFingerprint
    public let checkpointID: UUID?
    public let scope: CritiqueRequestScope

    public init(
        id: UUID = UUID(),
        requestedAt: Date = Date(),
        targetFingerprint: DocumentFingerprint,
        checkpointID: UUID?,
        scope: CritiqueRequestScope
    ) {
        self.id = id
        self.requestedAt = requestedAt
        self.targetFingerprint = targetFingerprint
        self.checkpointID = checkpointID
        self.scope = scope
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
        let path = relativePath.replacingOccurrences(of: "\\", with: "/")
        return path.hasPrefix("Critiques/")
            && path.lowercased().hasSuffix(".md")
            && !path.dropFirst("Critiques/".count).isEmpty
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

    /// Adds a new metadata block to a legacy Critique that has no frontmatter,
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

    public var errorDescription: String? {
        switch self {
        case .destinationAlreadyAssociated(let path):
            "The Critique at \(path) is already associated with another Work."
        case .workPathMismatch(let expected, let actual):
            "The Critique association expected its Work at \(expected), but it currently records \(actual)."
        }
    }
}

public actor CritiqueRegistry {
    private struct Payload: Codable {
        let schemaVersion: Int
        var associations: [UUID: CritiqueAssociation]
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private var associations: [UUID: CritiqueAssociation]
    private let loadFailure: String?

    public init(controlURL: URL, fileManager: FileManager = .default) {
        fileURL = controlURL.appendingPathComponent("critiques.json")
        self.fileManager = fileManager
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                let payload = try decoder.decode(Payload.self, from: data)
                let normalized = Self.normalized(payload.associations)
                associations = normalized
                if payload.schemaVersion != 2 {
                    loadFailure = "Unsupported Critique schema version \(payload.schemaVersion)."
                } else if normalized.count != payload.associations.count {
                    loadFailure = "The file contains duplicate Work or Critique associations. Scholium selected the newest entries for reading but will not rewrite the file automatically."
                } else {
                    loadFailure = nil
                }
            } catch {
                associations = [:]
                loadFailure = error.localizedDescription
            }
        } else {
            associations = [:]
            loadFailure = nil
        }
    }

    public func healthError() -> String? {
        loadFailure.map {
            ResearchRecordStoreError.unreadableStore(kind: "Critique", reason: $0)
                .localizedDescription
        }
    }

    public func association(workNoteID: UUID) -> CritiqueAssociation? {
        associations.values.first { $0.workNoteID == workNoteID }
    }

    public func association(critiqueRelativePath: String) -> CritiqueAssociation? {
        associations.values.first { $0.critiqueRelativePath == critiqueRelativePath }
    }

    func associationsRelated(noteID: UUID, relativePath: String) -> [CritiqueAssociation] {
        associations.values.filter {
            $0.workNoteID == noteID || $0.critiqueRelativePath == relativePath
        }.sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    public func save(_ association: CritiqueAssociation) throws -> CritiqueAssociation {
        if associations.values.contains(where: {
            $0.id != association.id
                && $0.critiqueRelativePath == association.critiqueRelativePath
                && $0.workNoteID != association.workNoteID
        }) {
            throw CritiqueRegistryError.destinationAlreadyAssociated(association.critiqueRelativePath)
        }
        var updated = association
        updated.updatedAt = Date()
        var proposed = associations
        for duplicateID in proposed.values
            .filter({ $0.id != association.id && $0.workNoteID == association.workNoteID })
            .map(\.id) {
            proposed.removeValue(forKey: duplicateID)
        }
        proposed[association.id] = updated
        try commit(proposed)
        return updated
    }

    @discardableResult
    public func recordRequest(
        workNoteID: UUID,
        workRelativePath: String,
        targetFingerprint: DocumentFingerprint,
        critiqueRelativePath: String,
        checkpointID: UUID?,
        scope: CritiqueRequestScope,
        requestedAt: Date = Date()
    ) throws -> CritiqueAssociation {
        var association = association(workNoteID: workNoteID) ?? CritiqueAssociation(
            workNoteID: workNoteID,
            workRelativePath: workRelativePath,
            targetFingerprint: targetFingerprint,
            critiqueRelativePath: critiqueRelativePath,
            createdAt: requestedAt,
            updatedAt: requestedAt
        )
        association.workRelativePath = workRelativePath
        association.targetFingerprint = targetFingerprint
        association.critiqueRelativePath = critiqueRelativePath
        association.rounds.append(CritiqueRound(
            requestedAt: requestedAt,
            targetFingerprint: targetFingerprint,
            checkpointID: checkpointID,
            scope: scope
        ))
        return try save(association)
    }

    /// Keeps a Work association and its Critique destination attached to a
    /// stable note after a confirmed move. Historical target fingerprints are
    /// intentionally unchanged.
    @discardableResult
    public func movePath(
        noteID: UUID,
        from sourcePath: String,
        to destinationPath: String
    ) throws -> [CritiqueAssociation] {
        if let workAssociation = associations.values.first(where: { $0.workNoteID == noteID }),
           workAssociation.workRelativePath != sourcePath,
           workAssociation.workRelativePath != destinationPath {
            throw CritiqueRegistryError.workPathMismatch(
                expected: sourcePath,
                actual: workAssociation.workRelativePath
            )
        }
        var proposed = associations
        var changed: [CritiqueAssociation] = []
        for id in Array(proposed.keys) {
            guard var association = proposed[id] else { continue }
            var didChange = false
            if association.workNoteID == noteID && association.workRelativePath == sourcePath {
                association.workRelativePath = destinationPath
                didChange = true
            }
            if association.critiqueRelativePath == sourcePath {
                association.critiqueRelativePath = destinationPath
                didChange = true
            }
            guard didChange else { continue }
            association.updatedAt = Date()
            proposed[id] = association
            changed.append(association)
        }
        if !changed.isEmpty {
            try commit(proposed)
        }
        return changed
    }

    public func remove(id: UUID) throws {
        var proposed = associations
        proposed.removeValue(forKey: id)
        try commit(proposed)
    }

    /// Removes associations owned by a deleted Work or pointing at a deleted
    /// Critique path. The Critique Markdown itself is handled by the vault
    /// deletion coordinator; this store owns only portable association state.
    @discardableResult
    public func purgeAssociations(
        noteID: UUID,
        relativePath: String
    ) throws -> [CritiqueAssociation] {
        try requireHealthyStore(kind: "Critique")
        let removed = associations.values.filter {
            $0.workNoteID == noteID || $0.critiqueRelativePath == relativePath
        }
        guard !removed.isEmpty else { return [] }
        let removedIDs = Set(removed.map(\.id))
        let proposed = associations.filter { !removedIDs.contains($0.key) }
        try commit(proposed)
        return removed.sorted { $0.createdAt < $1.createdAt }
    }

    func restorePurgedAssociations(_ removed: [CritiqueAssociation]) throws {
        try requireHealthyStore(kind: "Critique")
        var proposed = associations
        for association in removed {
            if let existing = proposed[association.id] {
                guard try persistentlyEquivalent(existing, association) else {
                    throw ResearchRecordStoreError.restorationConflict(
                        kind: "Critique",
                        identity: association.id.uuidString
                    )
                }
                continue
            }
            if proposed.values.contains(where: {
                $0.id != association.id
                    && ($0.workNoteID == association.workNoteID
                        || $0.critiqueRelativePath == association.critiqueRelativePath)
            }) {
                throw ResearchRecordStoreError.restorationConflict(
                    kind: "Critique",
                    identity: association.id.uuidString
                )
            }
            proposed[association.id] = association
        }
        guard proposed != associations else { return }
        try commit(proposed)
    }

    private func commit(_ proposed: [UUID: CritiqueAssociation]) throws {
        try requireHealthyStore(kind: "Critique")
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Payload(schemaVersion: 2, associations: proposed)).write(to: fileURL, options: .atomic)
        associations = proposed
    }

    private func requireHealthyStore(kind: String) throws {
        if let loadFailure {
            throw ResearchRecordStoreError.unreadableStore(kind: kind, reason: loadFailure)
        }
    }

    private static func normalized(
        _ candidates: [UUID: CritiqueAssociation]
    ) -> [UUID: CritiqueAssociation] {
        var workIDs: Set<UUID> = []
        var critiquePaths: Set<String> = []
        var result: [UUID: CritiqueAssociation] = [:]
        for association in candidates.values.sorted(by: {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }) {
            guard workIDs.insert(association.workNoteID).inserted,
                  critiquePaths.insert(association.critiqueRelativePath).inserted else { continue }
            result[association.id] = association
        }
        return result
    }
}
