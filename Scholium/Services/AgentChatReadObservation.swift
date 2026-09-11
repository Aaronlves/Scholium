import Foundation
import ScholiumContracts

/// Only the scoped App bridge's successful read result enters this parser.
enum AgentChatReadObservation {
    static func parse(_ result: [String: MCPJSONValue]) -> AgentChatSourceObservation? {
        guard let noteID = result["note_id"]?.stringValue.flatMap(UUID.init(uuidString:)),
            let fingerprint = result["fingerprint"]?.objectValue,
            let sha = fingerprint["sha256"]?.stringValue, sha.count == 64,
            sha.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
            let byteCount = fingerprint["byte_count"]?.intValue, byteCount >= 0,
            let start = result["start_line"]?.intValue, start > 0,
            let count = result["line_count"]?.intValue, count >= 0, count <= 1_000,
            start <= Int.max - count,
            let complete = result["complete"]?.boolValue,
            let source = result["source"]?.stringValue,
            (complete && result["next_line"] == .null) || (!complete && count > 0 && result["next_line"]?.intValue == start + count)
        else { return nil }
        let revision = DocumentFingerprint(sha256: sha, byteCount: byteCount)
        if start == 1 && complete, DocumentFingerprint(content: source) != revision { return nil }
        var prefix = Array(source.utf8.prefix(1_600))
        while String(bytes: prefix, encoding: .utf8) == nil { prefix.removeLast() }
        let excerpt = String(decoding: prefix, as: UTF8.self)
        return .noteRead(
            .init(
                noteID: noteID, fingerprint: revision, startLine: start,
                lineCount: count, reachedEnd: complete, excerpt: excerpt,
                excerptIsTruncated: excerpt.utf8.count < source.utf8.count))
    }
}
