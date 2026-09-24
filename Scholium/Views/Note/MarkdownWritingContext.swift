import Foundation
import ScholiumContracts

struct MarkdownEditorInsertionPoint: Equatable, Sendable {
    let sessionID: UUID
    let documentID: String
    let generation: Int
    let selection: MarkdownEditorSelectionRange
}

enum MarkdownWritingContextCaptureMode: Sendable {
    case selectionOnly
    /// Empty carets use one logical source line, excluding its line ending and initial BOM.
    case selectionOrCurrentLine
    /// Preserves continuation's paragraph expansion and preceding-paragraph fallback.
    case selectionOrParagraph
}

/// Exact-source projection for native retrieval. Never reconstructs writable text.
enum MarkdownWritingContextProjection {
    static func capture(source: String, selections: [MarkdownEditorSelectionRange], mode: MarkdownWritingContextCaptureMode) throws
        -> MarkdownSourceSelectionSnapshot
    {
        guard selections.count == 1, let selection = selections.first else { throw RelatedMaterialsError.selectionRequired }
        let map = EditorSourceOffsetMap(source: source)
        guard var lower = map.sourceUTF16Offset(forEditorUTF16Offset: min(selection.anchor, selection.head)),
            var upper = map.sourceUTF16Offset(forEditorUTF16Offset: max(selection.anchor, selection.head))
        else { throw RelatedMaterialsError.invalidSeed }
        let native = source as NSString
        var capturedLineStart: Int?
        if lower == upper {
            switch mode {
            case .selectionOnly:
                throw RelatedMaterialsError.selectionRequired
            case .selectionOrCurrentLine:
                // Editor logical lines are LF-delimited (CRLF in exact source),
                // not visual wraps or Foundation's other Unicode line separators.
                let previousNewline = native.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: lower))
                let nextNewline = native.range(of: "\n", range: NSRange(location: lower, length: native.length - lower))
                lower = previousNewline.location == NSNotFound ? 0 : NSMaxRange(previousNewline)
                capturedLineStart = lower
                upper = nextNewline.location == NSNotFound ? native.length : nextNewline.location
                if upper > lower, native.character(at: upper - 1) == 13, nextNewline.location != NSNotFound { upper -= 1 }
                if lower == 0, upper > 0, native.character(at: 0) == 0xFEFF { lower = 1 }
                guard
                    !native.substring(with: NSRange(location: lower, length: upper - lower))
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { throw RelatedMaterialsError.invalidSeed }
            case .selectionOrParagraph:
                var line = native.lineRange(for: NSRange(location: lower, length: 0))
                func blank(_ range: NSRange) -> Bool {
                    native.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                // At the trailing newline, the preceding paragraph is the writing context.
                if blank(line), line.location > 0 { line = native.lineRange(for: NSRange(location: line.location - 1, length: 0)) }
                guard !blank(line) else { throw RelatedMaterialsError.invalidSeed }
                lower = line.location
                upper = NSMaxRange(line)
                while lower > 0 {
                    let previous = native.lineRange(for: NSRange(location: lower - 1, length: 0))
                    if blank(previous) { break }
                    lower = previous.location
                }
                while upper < native.length {
                    let next = native.lineRange(for: NSRange(location: upper, length: 0))
                    if blank(next) { break }
                    upper = NSMaxRange(next)
                }
            }
        }
        guard upper > lower, upper - lower <= 32_000,
            let range = Range(NSRange(location: lower, length: upper - lower), in: source)
        else { throw RelatedMaterialsError.invalidSeed }
        let sourceRange = SearchSourceRange(
            utf16LowerBound: lower, utf16UpperBound: upper,
            line: 1 + source[..<range.lowerBound].utf8.filter { $0 == 10 }.count,
            column: lower - (capturedLineStart ?? native.lineRange(for: NSRange(location: lower, length: 0)).location) + 1,
            endLine: 1 + source[..<range.upperBound].utf8.filter { $0 == 10 }.count,
            endColumn: upper - (capturedLineStart ?? native.lineRange(for: NSRange(location: upper, length: 0)).location) + 1)
        return .init(source: source, excerpt: String(source[range]), sourceRange: sourceRange)
    }
}
