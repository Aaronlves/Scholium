import Foundation

/// A source-preserving lexical projection used only to color authored
/// frontmatter. It does not parse values, authorize edits, or replace the
/// complete YAML parser owned by NoteDocument/Yams.
public enum FrontmatterPresentation {
    public enum LineRole: Sendable, Equatable {
        case blank
        case comment
        case mapping(key: String, value: String, valueKind: ValueKind)
        case value(valueKind: ValueKind)
    }

    public enum ValueKind: String, Sendable, Equatable {
        case value
        case string
        case collection
        case scalar

        public var cssClass: String {
            switch self {
            case .value: "cm-live-yaml-value"
            case .string: "cm-live-yaml-string"
            case .collection: "cm-live-yaml-collection"
            case .scalar: "cm-live-yaml-scalar"
            }
        }
    }

    public struct Line: Sendable, Equatable {
        public let text: String
        public let role: LineRole

        public init(text: String, role: LineRole) {
            self.text = text
            self.role = role
        }
    }

    /// Splits one already-bounded frontmatter payload into presentation lines.
    /// The input is not repaired or reserialized; the trailing boundary newline
    /// is omitted only because the closing delimiter owns that boundary.
    public static func lines(in frontmatter: String) -> [Line] {
        let normalized = frontmatter
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if lines.last == "" { lines.removeLast() }
        return lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                return Line(text: line, role: .blank)
            }
            if trimmed.hasPrefix("#") {
                return Line(text: line, role: .comment)
            }
            if let colon = keyColon(in: line) {
                let key = String(line[..<colon])
                let valueStart = line.index(after: colon)
                let value = String(line[valueStart...])
                return Line(
                    text: line,
                    role: .mapping(
                        key: key,
                        value: value,
                        valueKind: valueKind(value)))
            }
            return Line(text: line, role: .value(valueKind: valueKind(line)))
        }
    }

    private static func keyColon(in line: String) -> String.Index? {
        var index = scalarStart(in: line)
        let keyStart = index
        guard index < line.endIndex else { return nil }

        if line[index] == "\"" || line[index] == "'" {
            guard let afterScalar = endOfQuotedScalar(in: line, from: index) else {
                return nil
            }
            index = afterScalar
            while index < line.endIndex, line[index] == " " || line[index] == "\t" {
                index = line.index(after: index)
            }
            guard index < line.endIndex, line[index] == ":",
                isKeySeparator(line, at: index)
            else { return nil }
            return index
        }

        while index < line.endIndex {
            if line[index] == ":", isKeySeparator(line, at: index) {
                return index > keyStart ? index : nil
            }
            index = line.index(after: index)
        }
        return nil
    }

    private static func scalarStart(in line: String) -> String.Index {
        var index = line.startIndex
        func skipSpacing() {
            while index < line.endIndex, line[index] == " " || line[index] == "\t" {
                index = line.index(after: index)
            }
        }
        skipSpacing()
        while index < line.endIndex, line[index] == "-" {
            let next = line.index(after: index)
            guard next == line.endIndex || line[next] == " " || line[next] == "\t" else {
                break
            }
            index = next
            skipSpacing()
        }
        return index
    }

    private static func isKeySeparator(_ line: String, at colon: String.Index) -> Bool {
        let next = line.index(after: colon)
        return next == line.endIndex || line[next] == " " || line[next] == "\t"
    }

    private static func endOfQuotedScalar(
        in line: String,
        from start: String.Index
    ) -> String.Index? {
        let quote = line[start]
        var index = line.index(after: start)
        while index < line.endIndex {
            if quote == "\"", line[index] == "\\" {
                let escaped = line.index(after: index)
                guard escaped < line.endIndex else { return nil }
                index = line.index(after: escaped)
                continue
            }
            if line[index] == quote {
                let next = line.index(after: index)
                if quote == "'", next < line.endIndex, line[next] == "'" {
                    index = line.index(after: next)
                    continue
                }
                return next
            }
            index = line.index(after: index)
        }
        return nil
    }

    private static func valueKind(_ value: String) -> ValueKind {
        let scalar = value[scalarStart(in: value)...]
        let trimmed = scalar.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return .value }
        if first == "\"" || first == "'" { return .string }
        if first == "[" || first == "{" { return .collection }
        if first == "|" || first == ">" { return .scalar }
        return .value
    }
}
