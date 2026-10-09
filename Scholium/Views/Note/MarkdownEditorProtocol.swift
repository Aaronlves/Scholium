import Foundation
import ScholiumContracts

let markdownEditorProtocolVersion = 46
let markdownEditorMaximumInteractionRevision = 9_007_199_254_740_991

func markdownEditorInteractionRevisionIsValid(_ revision: Int) -> Bool {
    (0...markdownEditorMaximumInteractionRevision).contains(revision)
}
let markdownEditorMaximumInboundBytes = 2_500_000
let markdownEditorMaximumSelectionRangeCount = 128
// Two exact-source strings may each require six JSON bytes per source byte.
// Transport size is distinct from the source capacity enforced on each field.
let markdownEditorMaximumSourceEnvelopeBytes = MarkdownEditorDeltaApplier.maximumResultUTF8Bytes * 12 + 512_000
// Admitted local images use their own outbound-only capacity; source and
// inbound envelopes retain the ordinary limits above.
let markdownEditorMaximumImageResourceBytes = 80 * 1_024 * 1_024
let markdownEditorMaximumImageResourceMetadataBytes = 512 * 1_024
let markdownEditorMaximumImageResourceEnvelopeBytes =
    4 * ((markdownEditorMaximumImageResourceBytes + 2) / 3)
    + markdownEditorMaximumImageResourceMetadataBytes

enum MarkdownEditorCommand: String, Codable, CaseIterable, Sendable {
    case bold, emphasis, strikethrough, highlight, inlineCode, markdownComment
    case standardLink, wikilink, annotatedWikilink
    case paragraph, heading1, heading2, heading3, heading4, heading5, heading6
    case blockQuotation, bulletList, numberedList, taskList, fencedCode, thematicBreak
    case calloutOrient, calloutCite, calloutConnect, calloutState
    case calloutIllustrate, calloutQuote, calloutFlag
    case insertFootnote, insertInlineFootnote, insertTable, insertImage, insertAttachment, toggleTask
    case tableInsertRowBefore, tableInsertRowAfter, tableDeleteRow
    case tableInsertColumnBefore, tableInsertColumnAfter, tableDeleteColumn
    case tableAlignLeft, tableAlignCenter, tableAlignRight
    case pastePlain, pasteMarkdown, linkSelectedText
    case insertCitation, insertBibliography, refreshCitations, citationStyle, cancelCitation
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
    var citationSnapshot: ZoteroCitationSnapshot? = nil
    var citationData: ZoteroCitationData? = nil
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
    var citationState: MarkdownEditorCitationState? = nil
    var imageTarget: String? = nil
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
    let citationState: MarkdownEditorCitationState?
    let imageTarget: String?

    init(context: MarkdownEditorContext) {
        activeInlineConstructs = context.activeInlineConstructs
        activeBlockConstructs = context.activeBlockConstructs
        tablePosition = context.tablePosition
        composing = context.composing
        hasNonemptySelection = context.selections.contains(where: \.isNonempty)
        availableCommands = context.availableCommands
        undoLabel = context.undoLabel
        redoLabel = context.redoLabel
        citationState = context.citationState
        imageTarget = context.imageTarget
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
            redoLabel: redoLabel,
            citationState: citationState,
            imageTarget: imageTarget
        )
    }
}

struct MarkdownEditorPerformanceSample: Codable, Hashable, Sendable {
    let name: String
    let durationMilliseconds: Double
    let observed: [String: Double]
}

enum DocumentFindAction: String, Codable, Hashable, Sendable {
    case present, update, next, previous, replaceCurrent, replaceAll
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
        initialSelection: MarkdownEditorSelectionRange?,
        citationSnapshot: ZoteroCitationSnapshot? = nil
    )
    case setMode(MarkdownEditorMode)
    case setDocumentTitle(String)
    case setPresentationCSS(String)
    case setUserCSS(String)
    case setLinkPreviews([MarkdownEditorLinkPreview])
    case setImageResources([String: String])
    case setWritingContinuation(enabled: Bool, contextKey: String)
    case setWritingIndexContext(String)
    case showPreview
    case measureVisibleProjection
    case showPreviewAt(x: Double, y: Double)
    case announceStatus(String)
    case goToLine(Int, focusesEditor: Bool)
    case revealSourceRange(fromUTF16: Int, toUTF16: Int)
    case selectAll
    case setScrollFraction(Double)
    case setScrollAnchor(MarkdownEditorWireScrollAnchor)
    case queryText, querySelection, queryContext, queryScrollAnchor, queryPerformance, captureRecovery
    case documentFind(DocumentFindQuery)
    case clearDocumentFind
    case suspendForDetachment(suspensionID: String)
    case resumeAfterDetachment(suspensionID: String)
    case restoreRecovery(MarkdownEditorRecoverySnapshot)
    case acknowledgeCommittedSnapshot(
        expected: String, committed: String, fingerprint: String,
        expectedCitationData: ZoteroCitationData? = nil, committedCitationSnapshot: ZoteroCitationSnapshot? = nil)
    case replacePassage(expectedText: String, fromUTF16: Int, toUTF16: Int, replacement: String, preserveSelection: Bool)
    case insertReference(selection: MarkdownEditorSelectionRange, generation: Int, target: String)
    case beginCitation(transactionID: String, command: String, reference: MarkdownEditorCitationReference?)
    case citationCallback(transactionID: String, value: MarkdownEditorCitationCallback)
    case finishCitation(transactionID: String)
    case cancelCitation(transactionID: String)
    case command(MarkdownEditorCommand, argument: String?)
    case pasteClipboard(plainText: String, selections: [MarkdownEditorSelectionRange])
    case markClean, focus, focusTitle, blur

    /// Only operations that can replace or mutate authoritative source need
    /// transport ordering. Snapshot reads and presentation intents must not
    /// queue behind one another or behind an obsolete content generation.
    var serializesSourceMutation: Bool {
        switch self {
        case .initialize, .restoreRecovery, .acknowledgeCommittedSnapshot, .replacePassage, .insertReference, .finishCitation, .command, .pasteClipboard,
            .suspendForDetachment, .resumeAfterDetachment:
            true
        case .documentFind(let query):
            query.action == .replaceCurrent || query.action == .replaceAll
        default:
            false
        }
    }

    var maximumRequestEnvelopeBytes: Int {
        if case .setImageResources = self {
            return markdownEditorMaximumImageResourceEnvelopeBytes
        }
        return markdownEditorMaximumSourceEnvelopeBytes
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, mode, dialect, initialSelection, value, line, focusesEditor, fromUTF16, toUTF16, fraction, anchor, snapshot, x, y
        case selection, generation, target, replacement, preserveSelection, expectedText, committedText, committedFingerprint, command, argument, suspensionID,
            enabled, contextKey, plainText, selections, transactionID, reference
        case citationSnapshot, expectedCitationData, committedCitationSnapshot
    }
    private enum Kind: String, Codable {
        case initialize, setMode, setDocumentTitle, setPresentationCSS, setUserCSS, setLinkPreviews, setImageResources,
            setWritingContinuation, setWritingIndexContext, showPreview,
            measureVisibleProjection, showPreviewAt,
            announceStatus
        case goToLine, revealSourceRange, selectAll, setScrollFraction, setScrollAnchor, queryText, querySelection, queryContext, queryScrollAnchor,
            queryPerformance
        case captureRecovery, suspendForDetachment, resumeAfterDetachment, restoreRecovery, acknowledgeCommittedSnapshot, replacePassage, insertReference,
            beginCitation, citationCallback, finishCitation, cancelCitation, command, pasteClipboard, documentFind, clearDocumentFind,
            markClean, focus,
            focusTitle, blur
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
                ),
                citationSnapshot: container.decodeIfPresent(ZoteroCitationSnapshot.self, forKey: .citationSnapshot)
            )
        case .setMode: self = try .setMode(container.decode(MarkdownEditorMode.self, forKey: .mode))
        case .setDocumentTitle:
            self = try .setDocumentTitle(container.decode(String.self, forKey: .value))
        case .setPresentationCSS: self = try .setPresentationCSS(container.decode(String.self, forKey: .value))
        case .setUserCSS: self = try .setUserCSS(container.decode(String.self, forKey: .value))
        case .setLinkPreviews: self = try .setLinkPreviews(container.decode([MarkdownEditorLinkPreview].self, forKey: .value))
        case .setImageResources: self = try .setImageResources(container.decode([String: String].self, forKey: .value))
        case .setWritingContinuation:
            self = try .setWritingContinuation(
                enabled: container.decode(Bool.self, forKey: .enabled),
                contextKey: container.decode(String.self, forKey: .contextKey))
        case .setWritingIndexContext:
            self = try .setWritingIndexContext(container.decode(String.self, forKey: .contextKey))
        case .showPreview: self = .showPreview
        case .measureVisibleProjection: self = .measureVisibleProjection
        case .showPreviewAt:
            self = try .showPreviewAt(
                x: container.decode(Double.self, forKey: .x),
                y: container.decode(Double.self, forKey: .y)
            )
        case .announceStatus: self = try .announceStatus(container.decode(String.self, forKey: .value))
        case .goToLine: self = try .goToLine(container.decode(Int.self, forKey: .line), focusesEditor: container.decode(Bool.self, forKey: .focusesEditor))
        case .revealSourceRange:
            self = try .revealSourceRange(
                fromUTF16: container.decode(Int.self, forKey: .fromUTF16),
                toUTF16: container.decode(Int.self, forKey: .toUTF16)
            )
        case .setScrollFraction: self = try .setScrollFraction(container.decode(Double.self, forKey: .fraction))
        case .selectAll: self = .selectAll
        case .setScrollAnchor: self = try .setScrollAnchor(container.decode(MarkdownEditorWireScrollAnchor.self, forKey: .anchor))
        case .queryText: self = .queryText
        case .querySelection: self = .querySelection
        case .queryContext: self = .queryContext
        case .queryScrollAnchor: self = .queryScrollAnchor
        case .queryPerformance: self = .queryPerformance
        case .documentFind: self = try .documentFind(container.decode(DocumentFindQuery.self, forKey: .value))
        case .clearDocumentFind: self = .clearDocumentFind
        case .captureRecovery: self = .captureRecovery
        case .suspendForDetachment:
            self = try .suspendForDetachment(suspensionID: container.decode(String.self, forKey: .suspensionID))
        case .resumeAfterDetachment:
            self = try .resumeAfterDetachment(suspensionID: container.decode(String.self, forKey: .suspensionID))
        case .restoreRecovery: self = try .restoreRecovery(container.decode(MarkdownEditorRecoverySnapshot.self, forKey: .snapshot))
        case .acknowledgeCommittedSnapshot:
            self = try .acknowledgeCommittedSnapshot(
                expected: container.decode(String.self, forKey: .expectedText),
                committed: container.decode(String.self, forKey: .committedText),
                fingerprint: container.decode(String.self, forKey: .committedFingerprint),
                expectedCitationData: container.decodeIfPresent(ZoteroCitationData.self, forKey: .expectedCitationData),
                committedCitationSnapshot: container.decodeIfPresent(ZoteroCitationSnapshot.self, forKey: .committedCitationSnapshot)
            )
        case .replacePassage:
            self = try .replacePassage(
                expectedText: container.decode(String.self, forKey: .expectedText),
                fromUTF16: container.decode(Int.self, forKey: .fromUTF16),
                toUTF16: container.decode(Int.self, forKey: .toUTF16),
                replacement: container.decode(String.self, forKey: .replacement),
                preserveSelection: container.decode(Bool.self, forKey: .preserveSelection))
        case .insertReference:
            self = try .insertReference(
                selection: container.decode(MarkdownEditorSelectionRange.self, forKey: .selection),
                generation: container.decode(Int.self, forKey: .generation),
                target: container.decode(String.self, forKey: .target))
        case .beginCitation:
            self = try .beginCitation(
                transactionID: container.decode(String.self, forKey: .transactionID),
                command: container.decode(String.self, forKey: .command),
                reference: container.decodeIfPresent(MarkdownEditorCitationReference.self, forKey: .reference))
        case .citationCallback:
            self = try .citationCallback(
                transactionID: container.decode(String.self, forKey: .transactionID),
                value: container.decode(MarkdownEditorCitationCallback.self, forKey: .value))
        case .finishCitation:
            self = try .finishCitation(transactionID: container.decode(String.self, forKey: .transactionID))
        case .cancelCitation:
            self = try .cancelCitation(transactionID: container.decode(String.self, forKey: .transactionID))
        case .command:
            self = try .command(
                container.decode(MarkdownEditorCommand.self, forKey: .command),
                argument: container.decodeIfPresent(String.self, forKey: .argument)
            )
        case .pasteClipboard:
            let plainText = try container.decode(String.self, forKey: .plainText)
            let selections = try container.decode([MarkdownEditorSelectionRange].self, forKey: .selections)
            guard plainText.utf8.count <= MarkdownEditorDeltaApplier.maximumResultUTF8Bytes,
                markdownEditorSelectionRangesAreValid(
                    selections, forEditorUTF16Length: MarkdownEditorDeltaApplier.maximumResultUTF8Bytes)
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .plainText, in: container, debugDescription: "Clipboard source or selection exceeds the editor bounds")
            }
            self = .pasteClipboard(plainText: plainText, selections: selections)
        case .markClean: self = .markClean
        case .focus: self = .focus
        case .focusTitle: self = .focusTitle
        case .blur: self = .blur
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .initialize(let text, let mode, let dialect, let initialSelection, let citationSnapshot):
            try container.encode(Kind.initialize, forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(mode, forKey: .mode)
            try container.encode(dialect, forKey: .dialect)
            try container.encodeIfPresent(
                initialSelection,
                forKey: .initialSelection
            )
            try container.encodeIfPresent(citationSnapshot, forKey: .citationSnapshot)
        case .setMode(let mode): try pair(.setMode, mode, .mode, into: &container)
        case .setDocumentTitle(let value):
            try pair(.setDocumentTitle, value, .value, into: &container)
        case .setPresentationCSS(let value): try pair(.setPresentationCSS, value, .value, into: &container)
        case .setUserCSS(let value): try pair(.setUserCSS, value, .value, into: &container)
        case .setLinkPreviews(let value): try pair(.setLinkPreviews, value, .value, into: &container)
        case .setImageResources(let value): try pair(.setImageResources, value, .value, into: &container)
        case .setWritingContinuation(let enabled, let contextKey):
            try container.encode(Kind.setWritingContinuation, forKey: .type)
            try container.encode(enabled, forKey: .enabled)
            try container.encode(contextKey, forKey: .contextKey)
        case .setWritingIndexContext(let contextKey):
            try container.encode(Kind.setWritingIndexContext, forKey: .type)
            try container.encode(contextKey, forKey: .contextKey)
        case .showPreview: try container.encode(Kind.showPreview, forKey: .type)
        case .measureVisibleProjection:
            try container.encode(Kind.measureVisibleProjection, forKey: .type)
        case .showPreviewAt(let x, let y):
            try container.encode(Kind.showPreviewAt, forKey: .type)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        case .announceStatus(let value): try pair(.announceStatus, value, .value, into: &container)
        case .goToLine(let line, let focusesEditor):
            try pair(.goToLine, line, .line, into: &container)
            try container.encode(focusesEditor, forKey: .focusesEditor)
        case .revealSourceRange(let fromUTF16, let toUTF16):
            try container.encode(Kind.revealSourceRange, forKey: .type)
            try container.encode(fromUTF16, forKey: .fromUTF16)
            try container.encode(toUTF16, forKey: .toUTF16)
        case .setScrollFraction(let fraction): try pair(.setScrollFraction, fraction, .fraction, into: &container)
        case .setScrollAnchor(let anchor): try pair(.setScrollAnchor, anchor, .anchor, into: &container)
        case .queryText: try container.encode(Kind.queryText, forKey: .type)
        case .querySelection: try container.encode(Kind.querySelection, forKey: .type)
        case .queryContext: try container.encode(Kind.queryContext, forKey: .type)
        case .queryScrollAnchor: try container.encode(Kind.queryScrollAnchor, forKey: .type)
        case .queryPerformance: try container.encode(Kind.queryPerformance, forKey: .type)
        case .documentFind(let value): try pair(.documentFind, value, .value, into: &container)
        case .clearDocumentFind: try container.encode(Kind.clearDocumentFind, forKey: .type)
        case .captureRecovery: try container.encode(Kind.captureRecovery, forKey: .type)
        case .suspendForDetachment(let suspensionID):
            try pair(.suspendForDetachment, suspensionID, .suspensionID, into: &container)
        case .resumeAfterDetachment(let suspensionID):
            try pair(.resumeAfterDetachment, suspensionID, .suspensionID, into: &container)
        case .restoreRecovery(let snapshot): try pair(.restoreRecovery, snapshot, .snapshot, into: &container)
        case .acknowledgeCommittedSnapshot(let expected, let committed, let fingerprint, let expectedCitationData, let committedCitationSnapshot):
            try container.encode(Kind.acknowledgeCommittedSnapshot, forKey: .type)
            try container.encode(expected, forKey: .expectedText)
            try container.encode(committed, forKey: .committedText)
            try container.encode(fingerprint, forKey: .committedFingerprint)
            try container.encodeIfPresent(expectedCitationData, forKey: .expectedCitationData)
            try container.encodeIfPresent(committedCitationSnapshot, forKey: .committedCitationSnapshot)
        case .replacePassage(let expectedText, let fromUTF16, let toUTF16, let replacement, let preserveSelection):
            try container.encode(Kind.replacePassage, forKey: .type)
            try container.encode(expectedText, forKey: .expectedText)
            try container.encode(fromUTF16, forKey: .fromUTF16)
            try container.encode(toUTF16, forKey: .toUTF16)
            try container.encode(replacement, forKey: .replacement)
            try container.encode(preserveSelection, forKey: .preserveSelection)
        case .insertReference(let selection, let generation, let target):
            try container.encode(Kind.insertReference, forKey: .type)
            try container.encode(selection, forKey: .selection)
            try container.encode(generation, forKey: .generation)
            try container.encode(target, forKey: .target)
        case .beginCitation(let transactionID, let command, let reference):
            try container.encode(Kind.beginCitation, forKey: .type)
            try container.encode(transactionID, forKey: .transactionID)
            try container.encode(command, forKey: .command)
            try container.encodeIfPresent(reference, forKey: .reference)
        case .citationCallback(let transactionID, let value):
            try container.encode(Kind.citationCallback, forKey: .type)
            try container.encode(transactionID, forKey: .transactionID)
            try container.encode(value, forKey: .value)
        case .finishCitation(let transactionID):
            try container.encode(Kind.finishCitation, forKey: .type)
            try container.encode(transactionID, forKey: .transactionID)
        case .cancelCitation(let transactionID):
            try container.encode(Kind.cancelCitation, forKey: .type)
            try container.encode(transactionID, forKey: .transactionID)
        case .command(let command, let argument):
            try container.encode(Kind.command, forKey: .type)
            try container.encode(command, forKey: .command)
            try container.encodeIfPresent(argument, forKey: .argument)
        case .pasteClipboard(let plainText, let selections):
            guard plainText.utf8.count <= MarkdownEditorDeltaApplier.maximumResultUTF8Bytes,
                markdownEditorSelectionRangesAreValid(
                    selections, forEditorUTF16Length: MarkdownEditorDeltaApplier.maximumResultUTF8Bytes)
            else {
                throw EncodingError.invalidValue(
                    self, .init(codingPath: encoder.codingPath, debugDescription: "Clipboard source or selection exceeds the editor bounds"))
            }
            try container.encode(Kind.pasteClipboard, forKey: .type)
            try container.encode(plainText, forKey: .plainText)
            try container.encode(selections, forKey: .selections)
        case .selectAll: try container.encode(Kind.selectAll, forKey: .type)
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
    let expiresAt: Int64
    let operation: MarkdownEditorOperation

    init(
        requestID: UUID = UUID(), sessionID: UUID, documentID: String,
        startingFingerprint: String, knownGeneration: Int, expiresAt: Int64,
        operation: MarkdownEditorOperation
    ) {
        protocolVersion = markdownEditorProtocolVersion
        self.requestID = requestID
        self.sessionID = sessionID
        self.documentID = documentID
        self.startingFingerprint = startingFingerprint
        self.knownGeneration = knownGeneration
        self.expiresAt = expiresAt
        self.operation = operation
    }
}

struct MarkdownEditorCommandResult: Codable, Hashable, Sendable {
    let requestID: UUID
    let resultingGeneration: Int
    let interactionRevision: Int
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
    var citationReply: MarkdownEditorCitationReply? = nil
    var citationManaged: Bool? = nil
    var citationData: ZoteroCitationData? = nil
    let accepted: Bool
    let error: String?
}
