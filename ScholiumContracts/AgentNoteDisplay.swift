import Foundation

/// Transient exact-source display request; not a stored passage or write capability.
public struct AgentNoteDisplayTarget: Sendable {
    public let triptychID: UUID
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let fingerprint: DocumentFingerprint
    public let range: SearchSourceRange?
    public let excerpt: String?
    public init(triptychID: UUID, noteID: UUID, note: VaultQualifiedNoteID, fingerprint: DocumentFingerprint,
                source: Data, startUTF8: Int? = nil, endUTF8: Int? = nil, expectedText: String? = nil) throws {
        func invalid() -> ScholiumMCPFailure { .init(code: .invalidRequest, message: "The Note display range is incomplete or does not match exact current source.", recovery: "Read the Note again and use its full-source UTF-8 offsets and exact text.") }
        guard DocumentFingerprint(data: source) == fingerprint, let text = NoteDocument.decodeUTF8PreservingBOM(source) else { throw invalid() }
        self.triptychID = triptychID; self.noteID = noteID; self.note = note; self.fingerprint = fingerprint
        if startUTF8 == nil && endUTF8 == nil && expectedText == nil { range = nil; excerpt = nil; return }
        guard let lower = startUTF8, let upper = endUTF8, let expectedText,
              lower >= 0, upper > lower, upper <= source.count, expectedText.utf8.count <= 65_536,
              source.subdata(in: lower..<upper) == Data(expectedText.utf8),
              let prefix = NoteDocument.decodeUTF8PreservingBOM(source.prefix(lower)),
              let ending = NoteDocument.decodeUTF8PreservingBOM(source.prefix(upper)),
              Range(NSRange(location: prefix.utf16.count, length: ending.utf16.count - prefix.utf16.count), in: text) != nil else { throw invalid() }
        func position(_ prefix: String) -> (Int, Int) {
            var line = 1; var column = 1
            for character in prefix {
                if character == "\n" || character == "\r" || character == "\r\n" { line += 1; column = 1 }
                else { column += String(character).utf16.count }
            }
            return (line, column)
        }
        let start = position(prefix), end = position(ending)
        range = .init(utf16LowerBound: prefix.utf16.count, utf16UpperBound: ending.utf16.count,
            line: start.0, column: start.1, endLine: end.0, endColumn: end.1)
        excerpt = expectedText
    }
}
