import Foundation

/// Computes one explicit projected-source replacement; completion never resolves
/// authority or rewrites surrounding Markdown through a rendered representation.
enum NativeEditorCompletion {
    static func edit(
        _ candidate: EditorLinkCompletion, kind: EditorLinkCompletionKind,
        queryRange: NSRange, source: String
    ) throws -> (range: NSRange, insertion: String) {
        let text = source as NSString
        func boundary(_ offset: Int) -> Bool {
            guard offset >= 0, offset <= text.length else { return false }
            if offset == 0 || offset == text.length { return true }
            return !(0xD800...0xDBFF).contains(text.character(at: offset - 1))
                || !(0xDC00...0xDFFF).contains(text.character(at: offset))
        }
        guard !candidate.isAmbiguous, !candidate.insertion.isEmpty,
            boundary(queryRange.location), queryRange.length >= 0,
            queryRange.length <= text.length - queryRange.location,
            boundary(queryRange.upperBound)
        else { throw MarkdownEditorSession.SessionError.invalidResult }
        let caret = queryRange.upperBound
        var range = queryRange
        if let count = candidate.replacementUTF16Count {
            guard count >= 0, count <= caret else { throw MarkdownEditorSession.SessionError.invalidResult }
            range = NSRange(location: caret - count, length: count)
            guard boundary(range.location), boundary(range.upperBound) else { throw MarkdownEditorSession.SessionError.invalidResult }
        }
        var insertion = candidate.insertion
        if kind != .term {
            guard !insertion.contains(where: { "[]\r\n".contains($0) }),
                candidate.displayText?.contains(where: { "[]\r\n".contains($0) }) != true
            else {
                throw MarkdownEditorSession.SessionError.invalidResult
            }
            let display = candidate.displayText.map { "|" + $0 } ?? ""
            insertion = "[[" + insertion + display + "]]"
            let text = source as NSString
            var trailing = 0
            while trailing < 2, range.upperBound < text.length, text.character(at: range.upperBound) == 93 {
                range.length += 1
                trailing += 1
            }
        }
        return (range, insertion)
    }
}
