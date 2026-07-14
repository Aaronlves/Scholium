import CryptoKit
import Foundation
import Yams

public enum NewlineStyle: String, Codable, Sendable {
    case lf
    case crlf

    public var sequence: String { self == .crlf ? "\r\n" : "\n" }
}

public struct DocumentFingerprint: Codable, Hashable, Sendable {
    public let sha256: String
    public let byteCount: Int

    public init(data: Data) {
        self.sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        self.byteCount = data.count
    }

    public init(content: String) {
        self.init(data: Data(content.utf8))
    }
}

public indirect enum YAMLValue: Codable, Hashable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case null
    case array([YAMLValue])
    case object([String: YAMLValue])

    public var scalarString: String? {
        switch self {
        case .string(let value): value
        case .integer(let value): String(value)
        case .double(let value): String(value)
        case .boolean(let value): value ? "true" : "false"
        case .null, .array, .object: nil
        }
    }

    static func convert(_ value: Any) -> YAMLValue {
        switch value {
        case let value as String: return .string(value)
        case let value as Bool: return .boolean(value)
        case let value as Int: return .integer(value)
        case let value as Double: return .double(value)
        case let value as Date:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return .string(formatter.string(from: value))
        case let value as [Any]: return .array(value.map(Self.convert))
        case let value as [String: Any]: return .object(value.mapValues(Self.convert))
        default: return .null
        }
    }
}

public enum FrontmatterEditValue: Hashable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case array([String])
    case remove
}

public enum NoteChangeSet: Sendable {
    case body(String)
    case frontmatter([String: FrontmatterEditValue])
    case composite(body: String?, frontmatter: [String: FrontmatterEditValue])
    /// Replace the user-editable Markdown source, then apply the configured
    /// successful-save timestamp as a targeted top-level edit.
    case source(String)
    /// Restore an exact historical snapshot without adding a new timestamp.
    case exactContent(String)
}

public struct NoteDocument: Sendable {
    public let relativePath: String
    /// Exact UTF-8 bytes loaded from disk. These bytes, not parsed metadata,
    /// are the source of truth for fingerprints, snapshots, and targeted edits.
    public let sourceBytes: Data
    public let rawContent: String
    public let body: String
    public let rawFrontmatter: String?
    public let frontmatterByteRange: Range<Int>?
    public let bodyByteRange: Range<Int>
    public let parsedFrontmatter: [String: YAMLValue]
    public let newlineStyle: NewlineStyle
    public let fingerprint: DocumentFingerprint
    public let validationWarnings: [String]

    private let prefix: String
    private let closingDelimiter: String

    /// Foundation's UTF-8 decoder may consume a leading BOM. Scholium keeps
    /// the BOM inside its exact-source string so a String-based mutation path
    /// can round-trip the authoritative bytes without silently dropping it.
    public static func decodeUTF8PreservingBOM(_ data: Data) -> String? {
        guard var content = String(data: data, encoding: .utf8) else { return nil }
        let hasUTF8BOM = data.starts(with: [0xEF, 0xBB, 0xBF])
        if hasUTF8BOM, content.unicodeScalars.first?.value != 0xFEFF {
            content.insert("\u{FEFF}", at: content.startIndex)
        }
        return content
    }

    public init(relativePath: String, rawContent: String) {
        self.relativePath = relativePath
        self.sourceBytes = Data(rawContent.utf8)
        self.rawContent = rawContent
        self.newlineStyle = rawContent.contains("\r\n") ? .crlf : .lf
        self.fingerprint = DocumentFingerprint(data: sourceBytes)

        let split = Self.split(rawContent)
        self.prefix = split.prefix
        self.rawFrontmatter = split.frontmatter
        self.closingDelimiter = split.closing
        self.body = split.body

        if let frontmatter = split.frontmatter {
            let frontmatterStart = Data(split.prefix.utf8).count
            let frontmatterEnd = frontmatterStart + Data(frontmatter.utf8).count
            self.frontmatterByteRange = frontmatterStart..<frontmatterEnd
            let bodyStart = frontmatterEnd + Data(split.closing.utf8).count
            self.bodyByteRange = bodyStart..<sourceBytes.count
        } else {
            self.frontmatterByteRange = nil
            self.bodyByteRange = 0..<sourceBytes.count
        }

        if let frontmatter = split.frontmatter {
            do {
                let loaded = try Yams.load(yaml: frontmatter)
                if let dictionary = loaded as? [String: Any] {
                    self.parsedFrontmatter = dictionary.mapValues(YAMLValue.convert)
                    self.validationWarnings = []
                } else if loaded == nil {
                    self.parsedFrontmatter = [:]
                    self.validationWarnings = []
                } else {
                    self.parsedFrontmatter = [:]
                    self.validationWarnings = ["Frontmatter root must be a mapping."]
                }
            } catch {
                self.parsedFrontmatter = [:]
                self.validationWarnings = [error.localizedDescription]
            }
        } else {
            self.parsedFrontmatter = [:]
            self.validationWarnings = []
        }
    }

    public func applying(
        _ changeSet: NoteChangeSet,
        timestampKey: String?,
        timestamp: Date = Date()
    ) throws -> String {
        switch changeSet {
        case .exactContent(let content):
            return content
        case .source(let content):
            let proposed = NoteDocument(relativePath: relativePath, rawContent: content)
            guard proposed.validationWarnings.isEmpty || proposed.rawFrontmatter == nil else {
                throw VaultRepositoryError.invalidFrontmatter(proposed.validationWarnings.joined(separator: "\n"))
            }
            guard proposed.rawFrontmatter != nil, timestampKey != nil else { return content }
            return try proposed.rebuild(
                body: proposed.body,
                edits: proposed.timestampEdit(timestampKey, timestamp)
            )
        case .body(let newBody):
            return try rebuild(body: newBody, edits: timestampEdit(timestampKey, timestamp))
        case .frontmatter(let edits):
            return try rebuild(body: body, edits: edits.merging(timestampEdit(timestampKey, timestamp)) { current, _ in current })
        case .composite(let newBody, let edits):
            return try rebuild(body: newBody ?? body, edits: edits.merging(timestampEdit(timestampKey, timestamp)) { current, _ in current })
        }
    }

    private func timestampEdit(_ key: String?, _ date: Date) -> [String: FrontmatterEditValue] {
        guard let key else { return [:] }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return [key: .string(formatter.string(from: date))]
    }

    private func rebuild(body newBody: String, edits: [String: FrontmatterEditValue]) throws -> String {
        guard !edits.isEmpty else {
            if rawFrontmatter == nil { return newBody }
            return prefix + (rawFrontmatter ?? "") + closingDelimiter + newBody
        }
        guard let rawFrontmatter else {
            throw VaultRepositoryError.invalidFrontmatter("Cannot edit metadata because the note has no YAML frontmatter.")
        }
        guard validationWarnings.isEmpty else {
            throw VaultRepositoryError.invalidFrontmatter(validationWarnings.joined(separator: "\n"))
        }
        let patched = Self.patch(frontmatter: rawFrontmatter, edits: edits, newline: newlineStyle.sequence)
        do {
            let value = try Yams.load(yaml: patched)
            guard value == nil || value is [String: Any] else {
                throw VaultRepositoryError.invalidFrontmatter("Frontmatter root must remain a mapping.")
            }
        } catch let error as VaultRepositoryError {
            throw error
        } catch {
            throw VaultRepositoryError.invalidFrontmatter(error.localizedDescription)
        }
        return prefix + patched + closingDelimiter + newBody
    }

    private static func split(_ content: String) -> (prefix: String, frontmatter: String?, closing: String, body: String) {
        var working = content
        let bom: String
        if working.unicodeScalars.first?.value == 0xFEFF {
            bom = "\u{FEFF}"
            working.removeFirst()
        } else {
            bom = ""
        }
        let start = working.startIndex
        guard working.hasPrefix("---") else { return ("", nil, "", content) }

        let firstLineEnd = lineEnd(in: working, from: start)
        let firstLine = working[start..<firstLineEnd.contentEnd].trimmingCharacters(in: .whitespaces)
        guard firstLine == "---", firstLineEnd.nextStart < working.endIndex else { return ("", nil, "", content) }

        var cursor = firstLineEnd.nextStart
        while cursor <= working.endIndex {
            let end = lineEnd(in: working, from: cursor)
            let line = working[cursor..<end.contentEnd].trimmingCharacters(in: .whitespaces)
            if line == "---" {
                let prefix = bom + String(working[..<firstLineEnd.nextStart])
                let frontmatter = String(working[firstLineEnd.nextStart..<cursor])
                let closing = String(working[cursor..<end.nextStart])
                let body = String(working[end.nextStart...])
                return (prefix, frontmatter, closing, body)
            }
            if end.nextStart == working.endIndex { break }
            cursor = end.nextStart
        }
        return ("", nil, "", content)
    }

    private static func lineEnd(in text: String, from start: String.Index) -> (contentEnd: String.Index, nextStart: String.Index) {
        guard start < text.endIndex else { return (text.endIndex, text.endIndex) }
        var cursor = start
        while cursor < text.endIndex {
            let character = text[cursor]
            if character == "\n" || character == "\r\n" || character == "\r" {
                return (cursor, text.index(after: cursor))
            }
            cursor = text.index(after: cursor)
        }
        return (text.endIndex, text.endIndex)
    }

    private static func patch(
        frontmatter: String,
        edits: [String: FrontmatterEditValue],
        newline: String
    ) -> String {
        var lines = frontmatter.components(separatedBy: newline)
        let hadTrailingNewline = frontmatter.hasSuffix(newline)
        if hadTrailingNewline, lines.last == "" { lines.removeLast() }

        for key in edits.keys.sorted() {
            guard let edit = edits[key] else { continue }
            let startIndex = lines.firstIndex { line in
                guard !line.hasPrefix(" "), !line.hasPrefix("\t"), let colon = line.firstIndex(of: ":") else { return false }
                return line[..<colon].trimmingCharacters(in: .whitespaces) == key
            }

            var endIndex: Int?
            if let startIndex {
                var candidate = startIndex + 1
                while candidate < lines.count {
                    let line = lines[candidate]
                    if line.isEmpty || line.hasPrefix(" ") || line.hasPrefix("\t") { candidate += 1; continue }
                    break
                }
                endIndex = candidate
            }

            if case .remove = edit {
                if let startIndex, let endIndex { lines.removeSubrange(startIndex..<endIndex) }
                continue
            }

            let replacement = serialize(key: key, value: edit, newline: newline)
            if let startIndex, let endIndex {
                lines.replaceSubrange(startIndex..<endIndex, with: replacement)
            } else {
                lines.append(contentsOf: replacement)
            }
        }

        var result = lines.joined(separator: newline)
        if hadTrailingNewline || !result.isEmpty { result += newline }
        return result
    }

    private static func serialize(key: String, value: FrontmatterEditValue, newline: String) -> [String] {
        switch value {
        case .string(let value): return ["\(key): \(quote(value))"]
        case .integer(let value): return ["\(key): \(value)"]
        case .double(let value): return ["\(key): \(value)"]
        case .boolean(let value): return ["\(key): \(value ? "true" : "false")"]
        case .array(let values):
            if values.isEmpty { return ["\(key): []"] }
            return ["\(key):"] + values.map { "  - \(quote($0))" }
        case .remove: return []
        }
    }

    private static func quote(_ value: String) -> String {
        guard !value.isEmpty else { return "\"\"" }
        let lower = value.lowercased()
        let ambiguous = ["true", "false", "null", "~"].contains(lower)
            || Int(value) != nil || Double(value) != nil
            || value.contains(":") || value.contains("#") || value.contains("[") || value.contains("]")
            || value.contains("{") || value.contains("}") || value.contains(",") || value.contains("\n")
            || value.first?.isWhitespace == true || value.last?.isWhitespace == true
        guard ambiguous else { return value }
        return "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
}
