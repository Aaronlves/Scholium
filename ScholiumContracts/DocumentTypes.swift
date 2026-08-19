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

    public init(sha256: String, byteCount: Int) {
        self.sha256 = sha256
        self.byteCount = byteCount
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

public indirect enum FrontmatterEditValue: Hashable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case array([String])
    /// A heterogeneous or nested YAML sequence. Scalar string lists retain
    /// the dedicated `array` case so ordinary tag/list edits stay simple.
    case sequence([FrontmatterEditValue])
    case mapping([String: FrontmatterEditValue])
    case remove
}

public enum NoteFrontmatterState: Hashable, Sendable {
    case absent
    case valid
    case malformed
}

public enum NoteChangeSet: Sendable {
    case body(String)
    case frontmatter([String: FrontmatterEditValue])
    /// Explicitly creates the first YAML envelope around an existing
    /// frontmatter-free Note. Ordinary Property edits never select this case
    /// implicitly, and an empty envelope is refused.
    case insertFrontmatter([String: FrontmatterEditValue])
    case composite(body: String?, frontmatter: [String: FrontmatterEditValue])
    /// Replace the user-editable Markdown source. Creation and modification
    /// time are app-owned History data, not injected frontmatter properties.
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

    /// Exact CodeMirror UTF-16 position at which authored body content begins.
    /// A valid frontmatter envelope may therefore have an empty body even when
    /// the complete source is nonempty.
    public var bodyUTF16Offset: Int {
        let byteOffset = bodyByteRange.lowerBound
        guard byteOffset <= rawContent.utf8.count else { return 0 }
        let utf8Index = rawContent.utf8.index(
            rawContent.utf8.startIndex,
            offsetBy: byteOffset
        )
        guard let index = String.Index(utf8Index, within: rawContent) else { return 0 }
        return index.utf16Offset(in: rawContent)
    }

    /// Empty Note presentation is body-aware, not a raw-file byte-count test.
    public var hasExactEmptyBody: Bool {
        body.isEmpty && validationWarnings.isEmpty
    }

    /// A source-boundary classification for Properties. Incomplete opening
    /// delimiters are malformed, never YAML-free insertion candidates.
    public var frontmatterState: NoteFrontmatterState {
        if rawFrontmatter != nil {
            return validationWarnings.isEmpty ? .valid : .malformed
        }
        if Self.hasFrontmatterOpeningDelimiter(rawContent)
            || !validationWarnings.isEmpty {
            return .malformed
        }
        return .absent
    }

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
            guard proposed.frontmatterState != .malformed else {
                throw VaultRepositoryError.invalidFrontmatter(
                    proposed.validationWarnings.first
                        ?? "The proposed source has malformed YAML frontmatter."
                )
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
        case .insertFrontmatter(let edits):
            guard timestampKey == nil else {
                throw VaultRepositoryError.invalidFrontmatter(
                    "The first YAML envelope cannot be combined with an implicit timestamp."
                )
            }
            return try insertingFirstFrontmatter(edits)
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
        let patched: String
        do {
            patched = try FrontmatterPatchPlanner.plan(
                frontmatter: rawFrontmatter,
                edits: edits,
                newline: newlineStyle.sequence
            ).patchedFrontmatter
        } catch let refusal as FrontmatterPatchRefusal {
            throw VaultRepositoryError.invalidFrontmatter(
                refusal.localizedDescription
            )
        }
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

    private func insertingFirstFrontmatter(
        _ edits: [String: FrontmatterEditValue]
    ) throws -> String {
        guard rawFrontmatter == nil else {
            throw VaultRepositoryError.invalidFrontmatter(
                "This note already has YAML frontmatter."
            )
        }
        guard !Self.hasFrontmatterOpeningDelimiter(rawContent) else {
            throw VaultRepositoryError.invalidFrontmatter(
                "The existing YAML frontmatter is incomplete or malformed."
            )
        }
        let insertions = edits.filter { _, value in
            if case .remove = value { return false }
            return true
        }
        guard !insertions.isEmpty else {
            throw VaultRepositoryError.invalidFrontmatter(
                "Add at least one Property before creating YAML frontmatter."
            )
        }

        let planned: FrontmatterPatchPlan
        do {
            planned = try FrontmatterPatchPlanner.plan(
                frontmatter: "",
                edits: insertions,
                newline: newlineStyle.sequence
            )
        } catch let refusal as FrontmatterPatchRefusal {
            throw VaultRepositoryError.invalidFrontmatter(
                refusal.localizedDescription
            )
        }
        guard !planned.patchedFrontmatter
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VaultRepositoryError.invalidFrontmatter(
                "Add at least one Property before creating YAML frontmatter."
            )
        }

        var existingBody = rawContent
        let bom: String
        if existingBody.unicodeScalars.first?.value == 0xFEFF {
            bom = "\u{FEFF}"
            existingBody.removeFirst()
        } else {
            bom = ""
        }
        let newline = newlineStyle.sequence
        let candidate = bom
            + "---" + newline
            + planned.patchedFrontmatter
            + "---" + newline
            + existingBody
        let validated = NoteDocument(relativePath: relativePath, rawContent: candidate)
        guard validated.rawFrontmatter != nil,
              validated.validationWarnings.isEmpty else {
            throw VaultRepositoryError.invalidFrontmatter(
                validated.validationWarnings.first
                    ?? "The first YAML envelope could not be validated."
            )
        }
        return candidate
    }

    private static func hasFrontmatterOpeningDelimiter(_ content: String) -> Bool {
        var working = content
        if working.unicodeScalars.first?.value == 0xFEFF {
            working.removeFirst()
        }
        guard working.hasPrefix("---") else { return false }
        let start = working.startIndex
        let firstLineEnd = lineEnd(in: working, from: start)
        return isColumnZeroFrontmatterDelimiter(
            working[start..<firstLineEnd.contentEnd]
        )
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
        let firstLine = working[start..<firstLineEnd.contentEnd]
        guard isColumnZeroFrontmatterDelimiter(firstLine),
              firstLineEnd.nextStart < working.endIndex else {
            return ("", nil, "", content)
        }

        var cursor = firstLineEnd.nextStart
        while cursor <= working.endIndex {
            let end = lineEnd(in: working, from: cursor)
            let line = working[cursor..<end.contentEnd]
            if isColumnZeroFrontmatterDelimiter(line) {
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

    private static func isColumnZeroFrontmatterDelimiter(
        _ line: Substring
    ) -> Bool {
        line.hasPrefix("---")
            && line.dropFirst(3).allSatisfy { $0 == " " || $0 == "\t" }
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

}
