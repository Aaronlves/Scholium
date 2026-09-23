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
        // Match the editor's logical newline model exactly: CRLF, CR and LF.
        // Other Unicode line separators are authored characters, not new rows.
        var lines: [(start: Int, contentEnd: Int, end: Int)] = []
        var start = 0
        var cursor = 0
        while cursor < native.length {
            let unit = native.character(at: cursor)
            if unit == 10 || unit == 13 {
                let width = unit == 13 && cursor + 1 < native.length && native.character(at: cursor + 1) == 10 ? 2 : 1
                lines.append((start, cursor, cursor + width))
                cursor += width
                start = cursor
            } else {
                cursor += 1
            }
        }
        lines.append((start, native.length, native.length))
        func lineIndex(at offset: Int) -> Int {
            lines.lastIndex(where: { $0.start <= offset }) ?? 0
        }
        func blank(_ index: Int) -> Bool {
            let line = lines[index]
            let from = line.start == 0 && native.length > 0 && native.character(at: 0) == 0xFEFF ? 1 : line.start
            return native.substring(with: NSRange(location: from, length: max(0, line.contentEnd - from)))
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if lower == upper {
            switch mode {
            case .selectionOnly:
                throw RelatedMaterialsError.selectionRequired
            case .selectionOrCurrentLine:
                let index = lineIndex(at: lower)
                guard !blank(index) else { throw RelatedMaterialsError.invalidSeed }
                lower = lines[index].start
                upper = lines[index].contentEnd
                if lower == 0, upper > 0, native.character(at: 0) == 0xFEFF { lower = 1 }
            case .selectionOrParagraph:
                var first = lineIndex(at: lower)
                if blank(first), first > 0 { first -= 1 }
                guard !blank(first) else { throw RelatedMaterialsError.invalidSeed }
                var last = first
                while first > 0, !blank(first - 1) { first -= 1 }
                while last + 1 < lines.count, !blank(last + 1) { last += 1 }
                lower = lines[first].start
                upper = lines[last].end
                if lower == 0, upper > 0, native.character(at: 0) == 0xFEFF { lower = 1 }
            }
        }
        guard upper > lower, upper - lower <= 32_000,
            let range = Range(NSRange(location: lower, length: upper - lower), in: source)
        else { throw RelatedMaterialsError.invalidSeed }
        let lowerLine = lineIndex(at: lower)
        let upperLine = lineIndex(at: upper)
        let sourceRange = SearchSourceRange(
            utf16LowerBound: lower, utf16UpperBound: upper,
            line: lowerLine + 1, column: lower - lines[lowerLine].start + 1,
            endLine: upperLine + 1, endColumn: upper - lines[upperLine].start + 1)
        return .init(source: source, excerpt: String(source[range]), sourceRange: sourceRange)
    }
}
