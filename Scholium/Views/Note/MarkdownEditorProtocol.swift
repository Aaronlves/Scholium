import Foundation
import ScholiumContracts

let markdownEditorProtocolVersion = 19
let markdownEditorMaximumInboundBytes = 2_500_000
let markdownEditorMaximumSelectionRangeCount = 128

enum MarkdownEditorCommand: String, Codable, CaseIterable, Sendable {
    case bold, emphasis, strikethrough, highlight, inlineCode, markdownComment
    case standardLink, wikilink, annotatedWikilink
    case paragraph, heading1, heading2, heading3, heading4, heading5, heading6
    case blockQuotation, bulletList, numberedList, taskList, fencedCode, thematicBreak
    case calloutOrient, calloutCite, calloutConnect, calloutState
    case calloutIllustrate, calloutQuote, calloutFlag
    case insertFootnote, insertTable, insertImage, toggleTask
    case tableInsertRowBefore, tableInsertRowAfter, tableDeleteRow
    case tableInsertColumnBefore, tableInsertColumnAfter, tableDeleteColumn
    case tableAlignLeft, tableAlignCenter, tableAlignRight
    case pastePlain, pasteMarkdown, linkSelectedText
}

struct MarkdownEditorSelectionRange: Codable, Hashable, Sendable {
    let anchor: Int
    let head: Int

    var isNonempty: Bool { anchor != head }

    func isValid(forEditorUTF16Length length: Int) -> Bool {
        length >= 0
            && anchor >= 0
            && anchor <= length
            && head >= 0
            && head <= length
    }
}

func markdownEditorSelectionRangesAreValid(
    _ ranges: [MarkdownEditorSelectionRange],
    forEditorUTF16Length length: Int
) -> Bool {
    !ranges.isEmpty
        && ranges.count <= markdownEditorMaximumSelectionRangeCount
        && ranges.allSatisfy { $0.isValid(forEditorUTF16Length: length) }
}

struct MarkdownEditorSelectionSnapshot: Codable, Hashable, Sendable {
    let documentID: String
    let fingerprint: String
    let generation: Int
    let ranges: [MarkdownEditorSelectionRange]

    func isValid(
        documentID expectedDocumentID: String,
        fingerprint expectedFingerprint: String,
        generation expectedGeneration: Int,
        editorUTF16Length: Int
    ) -> Bool {
        documentID == expectedDocumentID
            && fingerprint == expectedFingerprint
            && generation == expectedGeneration
            && markdownEditorSelectionRangesAreValid(
                ranges,
                forEditorUTF16Length: editorUTF16Length
            )
    }
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
    let focusTarget: WindowDocumentFocusTarget?
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
    let isEmbedded: Bool
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

/// The comparatively small, Equatable part of editor interaction state that
/// can change command presentation. Exact caret coordinates are deliberately
/// excluded so ordinary cursor motion does not invalidate SwiftUI.
struct EditorInteractionAvailability: Hashable, Sendable {
    let activeInlineConstructs: [String]
    let activeBlockConstructs: [String]
    let tablePosition: MarkdownEditorTablePosition?
    let composing: Bool
    let hasNonemptySelection: Bool
    let availableCommands: [MarkdownEditorCommand]
    let undoLabel: String?
    let redoLabel: String?

    init(context: MarkdownEditorContext) {
        activeInlineConstructs = context.activeInlineConstructs
        activeBlockConstructs = context.activeBlockConstructs
        tablePosition = context.tablePosition
        composing = context.composing
        hasNonemptySelection = context.selections.contains(where: \.isNonempty)
        availableCommands = context.availableCommands
        undoLabel = context.undoLabel
        redoLabel = context.redoLabel
    }

    func context(
        selections: [MarkdownEditorSelectionRange]
    ) -> MarkdownEditorContext {
        MarkdownEditorContext(
            selections: selections,
            activeInlineConstructs: activeInlineConstructs,
            activeBlockConstructs: activeBlockConstructs,
            tablePosition: tablePosition,
            composing: composing,
            availableCommands: availableCommands,
            undoLabel: undoLabel,
            redoLabel: redoLabel
        )
    }
}

struct MarkdownEditorPerformanceSample: Codable, Hashable, Sendable {
    let name: String
    let durationMilliseconds: Double
    let observed: [String: Double]
}

enum DocumentFindAction: String, Codable, Hashable, Sendable {
    case update, next, previous, replaceCurrent, replaceAll
}

enum DocumentFindShortcut: String, Codable, Hashable, Sendable {
    case present, next, previous, useSelection
}

struct DocumentFindQuery: Codable, Hashable, Sendable {
    let query: String
    let replacement: String
    let caseSensitive: Bool
    let wholeWord: Bool
    let action: DocumentFindAction
}

struct DocumentFindResult: Codable, Hashable, Sendable {
    let current: Int
    let total: Int
}

enum MarkdownEditorOperation: Codable, Hashable, Sendable {
    case initialize(
        text: String,
        mode: MarkdownEditorMode,
        dialect: MarkdownEditingDialect,
        initialSelection: MarkdownEditorSelectionRange?
    )
    case setMode(MarkdownEditorMode)
    case setDocumentTitle(String)
    case setPresentationCSS(String)
    case setUserCSS(String)
    case setLinkPreviews([MarkdownEditorLinkPreview])
    case showPreview
    case measureVisibleProjection
    case showPreviewAt(x: Double, y: Double)
    case announceStatus(String)
    case goToLine(Int)
    case revealSourceRange(fromUTF16: Int, toUTF16: Int)
    case setScrollFraction(Double)
    case setScrollAnchor(MarkdownEditorWireScrollAnchor)
    case queryText, querySelection, queryContext, queryScrollAnchor, queryPerformance, captureRecovery
    case documentFind(DocumentFindQuery)
    case clearDocumentFind
    case restoreRecovery(MarkdownEditorRecoverySnapshot)
    case acknowledgeCommittedSnapshot(expected: String, committed: String, fingerprint: String)
    case command(MarkdownEditorCommand, argument: String?)
    case markClean, focus, focusTitle, blur

    /// Only operations that can replace or mutate authoritative source need
    /// transport ordering. Snapshot reads and presentation intents must not
    /// queue behind one another or behind an obsolete content generation.
    var serializesSourceMutation: Bool {
        switch self {
        case .initialize, .restoreRecovery, .acknowledgeCommittedSnapshot, .command:
            true
        case .documentFind(let query):
            query.action == .replaceCurrent || query.action == .replaceAll
        default:
            false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, mode, dialect, initialSelection, value, line, fromUTF16, toUTF16, fraction, anchor, snapshot, x, y
        case expectedText, committedText, committedFingerprint, command, argument
    }
    private enum Kind: String, Codable {
        case initialize, setMode, setDocumentTitle, setPresentationCSS, setUserCSS, setLinkPreviews, showPreview, measureVisibleProjection, showPreviewAt, announceStatus
        case goToLine, revealSourceRange, setScrollFraction, setScrollAnchor, queryText, querySelection, queryContext, queryScrollAnchor, queryPerformance
        case captureRecovery, restoreRecovery, acknowledgeCommittedSnapshot, command, documentFind, clearDocumentFind, markClean, focus, focusTitle, blur
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .initialize:
            self = try .initialize(
                text: container.decode(String.self, forKey: .text),
                mode: container.decode(MarkdownEditorMode.self, forKey: .mode),
                dialect: container.decode(MarkdownEditingDialect.self, forKey: .dialect),
                initialSelection: container.decodeIfPresent(
                    MarkdownEditorSelectionRange.self,
                    forKey: .initialSelection
                )
            )
        case .setMode: self = try .setMode(container.decode(MarkdownEditorMode.self, forKey: .mode))
        case .setDocumentTitle:
            self = try .setDocumentTitle(container.decode(String.self, forKey: .value))
        case .setPresentationCSS: self = try .setPresentationCSS(container.decode(String.self, forKey: .value))
        case .setUserCSS: self = try .setUserCSS(container.decode(String.self, forKey: .value))
        case .setLinkPreviews: self = try .setLinkPreviews(container.decode([MarkdownEditorLinkPreview].self, forKey: .value))
        case .showPreview: self = .showPreview
        case .measureVisibleProjection: self = .measureVisibleProjection
        case .showPreviewAt:
            self = try .showPreviewAt(
                x: container.decode(Double.self, forKey: .x),
                y: container.decode(Double.self, forKey: .y)
            )
        case .announceStatus: self = try .announceStatus(container.decode(String.self, forKey: .value))
        case .goToLine: self = try .goToLine(container.decode(Int.self, forKey: .line))
        case .revealSourceRange:
            self = try .revealSourceRange(
                fromUTF16: container.decode(Int.self, forKey: .fromUTF16),
                toUTF16: container.decode(Int.self, forKey: .toUTF16)
            )
        case .setScrollFraction: self = try .setScrollFraction(container.decode(Double.self, forKey: .fraction))
        case .setScrollAnchor: self = try .setScrollAnchor(container.decode(MarkdownEditorWireScrollAnchor.self, forKey: .anchor))
        case .queryText: self = .queryText
        case .querySelection: self = .querySelection
        case .queryContext: self = .queryContext
        case .queryScrollAnchor: self = .queryScrollAnchor
        case .queryPerformance: self = .queryPerformance
        case .documentFind: self = try .documentFind(container.decode(DocumentFindQuery.self, forKey: .value))
        case .clearDocumentFind: self = .clearDocumentFind
        case .captureRecovery: self = .captureRecovery
        case .restoreRecovery: self = try .restoreRecovery(container.decode(MarkdownEditorRecoverySnapshot.self, forKey: .snapshot))
        case .acknowledgeCommittedSnapshot:
            self = try .acknowledgeCommittedSnapshot(
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
        case .focusTitle: self = .focusTitle
        case .blur: self = .blur
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .initialize(text, mode, dialect, initialSelection):
            try container.encode(Kind.initialize, forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(mode, forKey: .mode)
            try container.encode(dialect, forKey: .dialect)
            try container.encodeIfPresent(
                initialSelection,
                forKey: .initialSelection
            )
        case let .setMode(mode): try pair(.setMode, mode, .mode, into: &container)
        case let .setDocumentTitle(value):
            try pair(.setDocumentTitle, value, .value, into: &container)
        case let .setPresentationCSS(value): try pair(.setPresentationCSS, value, .value, into: &container)
        case let .setUserCSS(value): try pair(.setUserCSS, value, .value, into: &container)
        case let .setLinkPreviews(value): try pair(.setLinkPreviews, value, .value, into: &container)
        case .showPreview: try container.encode(Kind.showPreview, forKey: .type)
        case .measureVisibleProjection:
            try container.encode(Kind.measureVisibleProjection, forKey: .type)
        case let .showPreviewAt(x, y):
            try container.encode(Kind.showPreviewAt, forKey: .type)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        case let .announceStatus(value): try pair(.announceStatus, value, .value, into: &container)
        case let .goToLine(line): try pair(.goToLine, line, .line, into: &container)
        case let .revealSourceRange(fromUTF16, toUTF16):
            try container.encode(Kind.revealSourceRange, forKey: .type)
            try container.encode(fromUTF16, forKey: .fromUTF16)
            try container.encode(toUTF16, forKey: .toUTF16)
        case let .setScrollFraction(fraction): try pair(.setScrollFraction, fraction, .fraction, into: &container)
        case let .setScrollAnchor(anchor): try pair(.setScrollAnchor, anchor, .anchor, into: &container)
        case .queryText: try container.encode(Kind.queryText, forKey: .type)
        case .querySelection: try container.encode(Kind.querySelection, forKey: .type)
        case .queryContext: try container.encode(Kind.queryContext, forKey: .type)
        case .queryScrollAnchor: try container.encode(Kind.queryScrollAnchor, forKey: .type)
        case .queryPerformance: try container.encode(Kind.queryPerformance, forKey: .type)
        case let .documentFind(value): try pair(.documentFind, value, .value, into: &container)
        case .clearDocumentFind: try container.encode(Kind.clearDocumentFind, forKey: .type)
        case .captureRecovery: try container.encode(Kind.captureRecovery, forKey: .type)
        case let .restoreRecovery(snapshot): try pair(.restoreRecovery, snapshot, .snapshot, into: &container)
        case let .acknowledgeCommittedSnapshot(expected, committed, fingerprint):
            try container.encode(Kind.acknowledgeCommittedSnapshot, forKey: .type)
            try container.encode(expected, forKey: .expectedText)
            try container.encode(committed, forKey: .committedText)
            try container.encode(fingerprint, forKey: .committedFingerprint)
        case let .command(command, argument):
            try container.encode(Kind.command, forKey: .type)
            try container.encode(command, forKey: .command)
            try container.encodeIfPresent(argument, forKey: .argument)
        case .markClean: try container.encode(Kind.markClean, forKey: .type)
        case .focus: try container.encode(Kind.focus, forKey: .type)
        case .focusTitle: try container.encode(Kind.focusTitle, forKey: .type)
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
    let knownGeneration: Int
    let operation: MarkdownEditorOperation

    init(
        requestID: UUID = UUID(), sessionID: UUID, documentID: String,
        startingFingerprint: String, knownGeneration: Int,
        operation: MarkdownEditorOperation
    ) {
        protocolVersion = markdownEditorProtocolVersion
        self.requestID = requestID
        self.sessionID = sessionID
        self.documentID = documentID
        self.startingFingerprint = startingFingerprint
        self.knownGeneration = knownGeneration
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
    let find: DocumentFindResult?
    let commitSuperseded: Bool?
    let accepted: Bool
    let error: String?
}
