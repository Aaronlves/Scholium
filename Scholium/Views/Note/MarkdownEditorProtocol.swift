import Foundation
import ScholiumContracts

let markdownEditorMaximumSelectionRangeCount = 128

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

/// Native ranges use UTF-16 scalar boundaries, including positions within a
/// combining sequence, but never the interior of a surrogate pair.
func markdownEditorSelectionRangesAreValid(
    _ ranges: [MarkdownEditorSelectionRange],
    forProjectedText text: String
) -> Bool {
    let units = text as NSString
    guard markdownEditorSelectionRangesAreValid(ranges, forEditorUTF16Length: units.length) else { return false }
    func isBoundary(_ offset: Int) -> Bool {
        offset == 0 || offset == units.length
            || !(0xD800...0xDBFF).contains(units.character(at: offset - 1))
            || !(0xDC00...0xDFFF).contains(units.character(at: offset))
    }
    return ranges.allSatisfy { isBoundary($0.anchor) && isBoundary($0.head) }
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
