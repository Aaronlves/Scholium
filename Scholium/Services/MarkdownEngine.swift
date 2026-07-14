import Foundation
import ScholiumCore

enum MarkdownError: LocalizedError {
    case invalidFrontmatter
    case malformedYAML(String)

    var errorDescription: String? {
        switch self {
        case .invalidFrontmatter:
            "The file does not contain valid YAML frontmatter delimited by ---"
        case .malformedYAML(let detail):
            "Malformed YAML frontmatter: \(detail)"
        }
    }
}

/// Produces the legacy UI metadata projection used while AppState is migrated
/// to `NoteDocument` directly. It never renders HTML, serializes YAML, or
/// reconstructs writable source. `NoteDocument` remains the exact authority.
actor MarkdownEngine {
    func parse(_ content: String) throws -> (frontmatter: [String: FrontmatterValue], body: String) {
        let document = NoteDocument(relativePath: "projection.md", rawContent: content)
        if document.rawFrontmatter != nil, !document.validationWarnings.isEmpty {
            throw MarkdownError.malformedYAML(document.validationWarnings.joined(separator: "\n"))
        }
        return (
            document.parsedFrontmatter.mapValues(Self.project),
            document.body
        )
    }

    /// Nested mappings remain a read-only, dotted-key projection. They never
    /// become a second writable YAML representation.
    private static func project(_ value: YAMLValue) -> FrontmatterValue {
        switch value {
        case .string(let value):
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            if value.count == 10, let date = formatter.date(from: value) {
                return .date(date)
            }
            return .string(value)
        case .integer(let value):
            return .int(value)
        case .double(let value):
            return .double(value)
        case .boolean(let value):
            return .bool(value)
        case .null:
            return .string("")
        case .array(let values):
            return .array(values.map(\.displayScalar))
        case .object(let values):
            return .dictionary(YAMLValue.object(values).flattenedScalarValues)
        }
    }
}
