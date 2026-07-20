import Foundation
import ScholiumContracts

let markdownEditorProtocolVersion = 3
let markdownEditorMaximumInboundBytes = 2_500_000

enum MarkdownEditorCommand: String, Codable, CaseIterable, Sendable {
    case bold, emphasis, strikethrough, highlight, inlineCode
    case standardLink, wikilink, vectorSupportsTarget, vectorSupportedByTarget, vectorIncompatible
    case paragraph, heading1, heading2, heading3, heading4, heading5, heading6
    case blockQuotation, bulletList, numberedList, taskList, fencedCode, thematicBreak
    case calloutOrient, calloutCite, calloutConnect, calloutState
    case calloutIllustrate, calloutQuote, calloutFlag
    case insertFootnote, insertTable, toggleTask
    case tableInsertRowBefore, tableInsertRowAfter, tableDeleteRow
    case tableInsertColumnBefore, tableInsertColumnAfter, tableDeleteColumn
    case tableAlignLeft, tableAlignCenter, tableAlignRight
    case pastePlain, pasteMarkdown, linkSelectedText
}

struct MarkdownEditorSelectionRange: Codable, Hashable, Sendable {
    let anchor: Int
    let head: Int

    var isNonempty: Bool { anchor != head }
}

struct MarkdownEditorSelectionSnapshot: Codable, Hashable, Sendable {
    let documentID: String
    let fingerprint: String
    let generation: Int
    let ranges: [MarkdownEditorSelectionRange]
}

struct MarkdownEditorRecoverySnapshot: Codable, Hashable, Sendable {
    let documentID: String
    let fingerprint: String
    let generation: Int
    let ranges: [MarkdownEditorSelectionRange]
    let source: String
    let stateJSON: String?
    let undoHistoryPreserved: Bool
    let dirty: Bool
}

/// A revision-bound position shared by the Read and editable projections.
/// Source offsets remain authoritative; block-relative geometry is only a
/// presentation hint and the normalized fraction is a bounded fallback.
struct EditorScrollAnchor: Codable, Hashable, Sendable {
    let sourceFingerprint: String
    let sourceUTF16Offset: Int
    let blockUTF16LowerBound: Int
    let blockUTF16UpperBound: Int
    let relativeBlockPosition: Double
    let fallbackFraction: Double

    func isValid(forUTF16Length length: Int) -> Bool {
        !sourceFingerprint.isEmpty
            && sourceUTF16Offset >= 0
            && sourceUTF16Offset <= length
            && blockUTF16LowerBound >= 0
            && blockUTF16LowerBound <= sourceUTF16Offset
            && blockUTF16UpperBound >= sourceUTF16Offset
            && blockUTF16UpperBound <= length
            && relativeBlockPosition.isFinite
            && (0...1).contains(relativeBlockPosition)
            && fallbackFraction.isFinite
            && (0...1).contains(fallbackFraction)
    }
}

struct MarkdownEditorWireScrollAnchor: Codable, Hashable, Sendable {
    let sourceUTF16Offset: Int
    let blockUTF16LowerBound: Int
    let blockUTF16UpperBound: Int
    let relativeBlockPosition: Double
    let fallbackFraction: Double
}

struct MarkdownEditorTablePosition: Codable, Hashable, Sendable {
    let row: Int
    let column: Int
    let rowCount: Int
    let columnCount: Int
}

struct MarkdownEditorLinkPreview: Codable, Hashable, Sendable {
    let from: Int
    let to: Int
    let title: String
    let relationship: VectorLinkKind?
    let fragment: String?
    let htmlBody: String
}

struct MarkdownEditorContext: Codable, Hashable, Sendable {
    let selections: [MarkdownEditorSelectionRange]
    let activeInlineConstructs: [String]
    let activeBlockConstructs: [String]
    let tablePosition: MarkdownEditorTablePosition?
    let composing: Bool
    let availableCommands: [MarkdownEditorCommand]
    let undoLabel: String?
    let redoLabel: String?
}

struct MarkdownEditorPerformanceSample: Codable, Hashable, Sendable {
    let name: String
    let durationMilliseconds: Double
    let observed: [String: Double]
}

enum MarkdownEditorOperation: Codable, Hashable, Sendable {
    case initialize(text: String, mode: NotePresentationMode, dialect: MarkdownEditingDialect)
    case setMode(NotePresentationMode)
    case setUserCSS(String)
    case setLinkCompletions([EditorLinkCompletion])
    case setLinkPreviews([MarkdownEditorLinkPreview])
    case setResearcherComments([MarkdownEditorCommentAnnotation])
    case showPreview
    case showPreviewAt(x: Double, y: Double)
    case announceStatus(String)
    case goToLine(Int)
    case setScrollFraction(Double)
    case setScrollAnchor(MarkdownEditorWireScrollAnchor)
    case queryText, querySelection, queryContext, queryScrollAnchor, queryPerformance, captureRecovery
    case restoreRecovery(MarkdownEditorRecoverySnapshot)
    case synchronizeCommittedText(expected: String, committed: String, fingerprint: String)
    case command(MarkdownEditorCommand, argument: String?)
    case markClean, focus, blur

    private enum CodingKeys: String, CodingKey {
        case type, text, mode, dialect, value, line, fraction, anchor, snapshot, x, y
        case expectedText, committedText, committedFingerprint, command, argument
    }
    private enum Kind: String, Codable {
        case initialize, setMode, setUserCSS, setLinkCompletions, setLinkPreviews, setResearcherComments, showPreview, showPreviewAt, announceStatus
        case goToLine, setScrollFraction, setScrollAnchor, queryText, querySelection, queryContext, queryScrollAnchor, queryPerformance
        case captureRecovery, restoreRecovery, synchronizeCommittedText, command, markClean, focus, blur
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .initialize:
            self = try .initialize(
                text: container.decode(String.self, forKey: .text),
                mode: container.decode(NotePresentationMode.self, forKey: .mode),
                dialect: container.decode(MarkdownEditingDialect.self, forKey: .dialect)
            )
        case .setMode: self = try .setMode(container.decode(NotePresentationMode.self, forKey: .mode))
        case .setUserCSS: self = try .setUserCSS(container.decode(String.self, forKey: .value))
        case .setLinkCompletions: self = try .setLinkCompletions(container.decode([EditorLinkCompletion].self, forKey: .value))
        case .setLinkPreviews: self = try .setLinkPreviews(container.decode([MarkdownEditorLinkPreview].self, forKey: .value))
        case .setResearcherComments: self = try .setResearcherComments(container.decode([MarkdownEditorCommentAnnotation].self, forKey: .value))
        case .showPreview: self = .showPreview
        case .showPreviewAt:
            self = try .showPreviewAt(
                x: container.decode(Double.self, forKey: .x),
                y: container.decode(Double.self, forKey: .y)
            )
        case .announceStatus: self = try .announceStatus(container.decode(String.self, forKey: .value))
        case .goToLine: self = try .goToLine(container.decode(Int.self, forKey: .line))
        case .setScrollFraction: self = try .setScrollFraction(container.decode(Double.self, forKey: .fraction))
        case .setScrollAnchor: self = try .setScrollAnchor(container.decode(MarkdownEditorWireScrollAnchor.self, forKey: .anchor))
        case .queryText: self = .queryText
        case .querySelection: self = .querySelection
        case .queryContext: self = .queryContext
        case .queryScrollAnchor: self = .queryScrollAnchor
        case .queryPerformance: self = .queryPerformance
        case .captureRecovery: self = .captureRecovery
        case .restoreRecovery: self = try .restoreRecovery(container.decode(MarkdownEditorRecoverySnapshot.self, forKey: .snapshot))
        case .synchronizeCommittedText:
            self = try .synchronizeCommittedText(
                expected: container.decode(String.self, forKey: .expectedText),
                committed: container.decode(String.self, forKey: .committedText),
                fingerprint: container.decode(String.self, forKey: .committedFingerprint)
            )
        case .command:
            self = try .command(
                container.decode(MarkdownEditorCommand.self, forKey: .command),
                argument: container.decodeIfPresent(String.self, forKey: .argument)
            )
        case .markClean: self = .markClean
        case .focus: self = .focus
        case .blur: self = .blur
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .initialize(text, mode, dialect):
            try container.encode(Kind.initialize, forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(mode, forKey: .mode)
            try container.encode(dialect, forKey: .dialect)
        case let .setMode(mode): try pair(.setMode, mode, .mode, into: &container)
        case let .setUserCSS(value): try pair(.setUserCSS, value, .value, into: &container)
        case let .setLinkCompletions(value): try pair(.setLinkCompletions, value, .value, into: &container)
        case let .setLinkPreviews(value): try pair(.setLinkPreviews, value, .value, into: &container)
        case let .setResearcherComments(value): try pair(.setResearcherComments, value, .value, into: &container)
        case .showPreview: try container.encode(Kind.showPreview, forKey: .type)
        case let .showPreviewAt(x, y):
            try container.encode(Kind.showPreviewAt, forKey: .type)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        case let .announceStatus(value): try pair(.announceStatus, value, .value, into: &container)
        case let .goToLine(line): try pair(.goToLine, line, .line, into: &container)
        case let .setScrollFraction(fraction): try pair(.setScrollFraction, fraction, .fraction, into: &container)
        case let .setScrollAnchor(anchor): try pair(.setScrollAnchor, anchor, .anchor, into: &container)
        case .queryText: try container.encode(Kind.queryText, forKey: .type)
        case .querySelection: try container.encode(Kind.querySelection, forKey: .type)
        case .queryContext: try container.encode(Kind.queryContext, forKey: .type)
        case .queryScrollAnchor: try container.encode(Kind.queryScrollAnchor, forKey: .type)
        case .queryPerformance: try container.encode(Kind.queryPerformance, forKey: .type)
        case .captureRecovery: try container.encode(Kind.captureRecovery, forKey: .type)
        case let .restoreRecovery(snapshot): try pair(.restoreRecovery, snapshot, .snapshot, into: &container)
        case let .synchronizeCommittedText(expected, committed, fingerprint):
            try container.encode(Kind.synchronizeCommittedText, forKey: .type)
            try container.encode(expected, forKey: .expectedText)
            try container.encode(committed, forKey: .committedText)
            try container.encode(fingerprint, forKey: .committedFingerprint)
        case let .command(command, argument):
            try container.encode(Kind.command, forKey: .type)
            try container.encode(command, forKey: .command)
            try container.encodeIfPresent(argument, forKey: .argument)
        case .markClean: try container.encode(Kind.markClean, forKey: .type)
        case .focus: try container.encode(Kind.focus, forKey: .type)
        case .blur: try container.encode(Kind.blur, forKey: .type)
        }
    }

    private func pair<Value: Encodable>(
        _ kind: Kind,
        _ value: Value,
        _ key: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(kind, forKey: .type)
        try container.encode(value, forKey: key)
    }
}

struct MarkdownEditorRequest: Codable, Hashable, Sendable {
    let protocolVersion: Int
    let requestID: UUID
    let sessionID: UUID
    let documentID: String
    let startingFingerprint: String
    let expectedGeneration: Int
    let operation: MarkdownEditorOperation

    init(
        requestID: UUID = UUID(), sessionID: UUID, documentID: String,
        startingFingerprint: String, expectedGeneration: Int,
        operation: MarkdownEditorOperation
    ) {
        protocolVersion = markdownEditorProtocolVersion
        self.requestID = requestID
        self.sessionID = sessionID
        self.documentID = documentID
        self.startingFingerprint = startingFingerprint
        self.expectedGeneration = expectedGeneration
        self.operation = operation
    }
}

struct MarkdownEditorCommandResult: Codable, Hashable, Sendable {
    let requestID: UUID
    let resultingGeneration: Int
    let sourceChanged: Bool
    let selections: [MarkdownEditorSelectionRange]
    let undoLabel: String?
    let text: String?
    let context: MarkdownEditorContext?
    let selection: MarkdownEditorSelectionSnapshot?
    let recovery: MarkdownEditorRecoverySnapshot?
    let scrollAnchor: MarkdownEditorWireScrollAnchor?
    let performanceSamples: [MarkdownEditorPerformanceSample]?
    let accepted: Bool
    let error: String?
}
