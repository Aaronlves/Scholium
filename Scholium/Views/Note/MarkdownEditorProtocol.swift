import Foundation
import ScholiumContracts

let markdownEditorProtocolVersion = 2
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

struct MarkdownEditorTablePosition: Codable, Hashable, Sendable {
    let row: Int
    let column: Int
    let rowCount: Int
    let columnCount: Int
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

enum MarkdownEditorOperation: Codable, Hashable, Sendable {
    case initialize(text: String, mode: NotePresentationMode, dialect: MarkdownEditingDialect)
    case setMode(NotePresentationMode)
    case setUserCSS(String)
    case setLinkCompletions([EditorLinkCompletion])
    case setResearcherComments([MarkdownEditorCommentAnnotation])
    case announceStatus(String)
    case goToLine(Int)
    case setScrollFraction(Double)
    case queryText, querySelection, queryContext, captureRecovery
    case restoreRecovery(MarkdownEditorRecoverySnapshot)
    case synchronizeCommittedText(expected: String, committed: String, fingerprint: String)
    case command(MarkdownEditorCommand, argument: String?)
    case markClean, focus

    private enum CodingKeys: String, CodingKey {
        case type, text, mode, dialect, value, line, fraction, snapshot
        case expectedText, committedText, committedFingerprint, command, argument
    }
    private enum Kind: String, Codable {
        case initialize, setMode, setUserCSS, setLinkCompletions, setResearcherComments, announceStatus
        case goToLine, setScrollFraction, queryText, querySelection, queryContext
        case captureRecovery, restoreRecovery, synchronizeCommittedText, command, markClean, focus
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
        case .setResearcherComments: self = try .setResearcherComments(container.decode([MarkdownEditorCommentAnnotation].self, forKey: .value))
        case .announceStatus: self = try .announceStatus(container.decode(String.self, forKey: .value))
        case .goToLine: self = try .goToLine(container.decode(Int.self, forKey: .line))
        case .setScrollFraction: self = try .setScrollFraction(container.decode(Double.self, forKey: .fraction))
        case .queryText: self = .queryText
        case .querySelection: self = .querySelection
        case .queryContext: self = .queryContext
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
        case let .setResearcherComments(value): try pair(.setResearcherComments, value, .value, into: &container)
        case let .announceStatus(value): try pair(.announceStatus, value, .value, into: &container)
        case let .goToLine(line): try pair(.goToLine, line, .line, into: &container)
        case let .setScrollFraction(fraction): try pair(.setScrollFraction, fraction, .fraction, into: &container)
        case .queryText: try container.encode(Kind.queryText, forKey: .type)
        case .querySelection: try container.encode(Kind.querySelection, forKey: .type)
        case .queryContext: try container.encode(Kind.queryContext, forKey: .type)
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
    let accepted: Bool
    let error: String?
}

enum MarkdownEditorBridgeEvent: Codable, Hashable, Sendable {
    case ready(generation: Int)
    case deltas(baseGeneration: Int, resultingGeneration: Int, changes: [MarkdownEditorDelta])
    case contextChanged(generation: Int, context: MarkdownEditorContext)
    case requestSave(generation: Int)
    case requestSearch(generation: Int)
    case linkActivated(generation: Int, target: String)
    case commentActivated(generation: Int, id: UUID)
    case scrollChanged(generation: Int, fraction: Double)
    case failure(generation: Int, message: String)
}
