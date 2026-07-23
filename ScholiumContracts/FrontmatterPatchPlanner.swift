import Foundation
import Yams

public enum FrontmatterPatchRefusal: Error, LocalizedError, Equatable, Sendable {
    case invalidYAML(String)
    case nonBlockMappingRoot
    case ambiguousStructure(String)
    case unsupportedExistingValue(String)

    public var errorDescription: String? {
        switch self {
        case .invalidYAML(let message):
            "The complete YAML frontmatter is invalid: \(message)"
        case .nonBlockMappingRoot:
            "Properties can only patch a YAML block mapping. Open Source to edit this frontmatter."
        case .ambiguousStructure(let message):
            "Properties refused an ambiguous YAML edit: \(message) Open Source to edit it directly."
        case .unsupportedExistingValue(let key):
            "Properties can only replace or remove a uniquely bounded ordinary value for ‘\(key)’. Open Source to edit this value."
        }
    }
}

public struct FrontmatterPatchPlan: Equatable, Sendable {
    public let patchedFrontmatter: String
    public let editedKeys: [String]

    public init(patchedFrontmatter: String, editedKeys: [String]) {
        self.patchedFrontmatter = patchedFrontmatter
        self.editedKeys = editedKeys
    }
}

/// Produces byte-bounded frontmatter changes only when a complete Yams parse
/// and a conservative lexical proof agree on one unambiguous block mapping.
public enum FrontmatterPatchPlanner {
    private struct Line {
        let content: String
        let contentRange: Range<String.Index>
        let fullRange: Range<String.Index>
    }

    private struct Entry {
        let key: String
        let line: Line
        let colon: String.Index
        let fullRange: Range<String.Index>
        let indentation: String
    }

    private struct PatchOperation {
        let range: Range<String.Index>
        let replacement: String
    }

    private struct Analysis {
        let mapping: [String: Any]
        let entries: [String: Entry]
    }

    public static func plan(
        frontmatter: String,
        edits: [String: FrontmatterEditValue],
        newline: String
    ) throws -> FrontmatterPatchPlan {
        var patched = frontmatter
        for key in edits.keys.sorted() {
            guard let edit = edits[key] else { continue }
            let analysis = try analyze(patched, newline: newline)
            if let entry = analysis.entries[key] {
                patched = try patchExisting(
                    patched,
                    key: key,
                    edit: edit,
                    entry: entry,
                    semanticValue: analysis.mapping[key],
                    newline: newline
                )
            } else if case .remove = edit {
                continue
            } else {
                let serialized = serialize(key: key, value: edit, indent: "")
                    .joined(separator: newline)
                guard !serialized.isEmpty else { continue }
                if patched.isEmpty {
                    patched = serialized + newline
                } else if patched.hasSuffix(newline) {
                    patched += serialized + newline
                } else {
                    patched += newline + serialized
                }
            }
        }

        _ = try analyze(patched, newline: newline)
        return FrontmatterPatchPlan(
            patchedFrontmatter: patched,
            editedKeys: edits.keys.sorted()
        )
    }

    private static func analyze(_ frontmatter: String, newline: String) throws -> Analysis {
        let loaded: Any?
        do {
            loaded = try Yams.load(yaml: frontmatter)
        } catch {
            throw FrontmatterPatchRefusal.invalidYAML(error.localizedDescription)
        }
        guard loaded == nil || loaded is [String: Any] else {
            throw FrontmatterPatchRefusal.nonBlockMappingRoot
        }
        let mapping = loaded as? [String: Any] ?? [:]
        let lines = splitLines(frontmatter, newline: newline)
        guard let firstSignificant = lines.first(where: { line in
            let trimmed = line.content.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#")
        }) else {
            return Analysis(mapping: mapping, entries: [:])
        }
        let rootPrefix = firstSignificant.content.trimmingCharacters(in: .whitespaces)
        guard !rootPrefix.hasPrefix("{") else {
            throw FrontmatterPatchRefusal.nonBlockMappingRoot
        }

        struct Candidate {
            let key: String
            let lineIndex: Int
            let colon: String.Index
        }

        var candidates: [Candidate] = []
        var seenKeys: Set<String> = []
        for (lineIndex, line) in lines.enumerated() {
            let text = line.content
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if containsAliasOrAnchorSyntax(text) {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "anchors and aliases are not patchable"
                )
            }
            if text.first == "\t" {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "tab-indented YAML cannot be bounded reliably"
                )
            }
            guard text.first?.isWhitespace != true else { continue }
            guard !trimmed.hasPrefix("?"), !trimmed.hasPrefix("---"),
                  !trimmed.hasPrefix("...") else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "complex keys and nested YAML documents are not patchable"
                )
            }
            guard let colonOffset = firstMappingColon(in: text) else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "a top-level line is not a bounded mapping entry"
                )
            }
            let colon = text.index(text.startIndex, offsetBy: colonOffset)
            let rawKey = text[..<colon].trimmingCharacters(in: .whitespaces)
            guard !rawKey.isEmpty else {
                throw FrontmatterPatchRefusal.ambiguousStructure("an empty key is present")
            }
            guard rawKey.first != "\"", rawKey.first != "'" else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "quoted keys can be semantically equivalent to plain keys"
                )
            }
            guard rawKey != "<<" else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "a YAML merge key can change the root mapping"
                )
            }
            guard isPlainBoundedKey(rawKey) else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "the key ‘\(rawKey)’ is not a bounded plain key"
                )
            }
            guard seenKeys.insert(rawKey).inserted else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "the key ‘\(rawKey)’ occurs more than once"
                )
            }
            let absoluteColon = frontmatter.index(
                line.contentRange.lowerBound,
                offsetBy: colonOffset
            )
            candidates.append(Candidate(
                key: rawKey,
                lineIndex: lineIndex,
                colon: absoluteColon
            ))
        }

        var entries: [String: Entry] = [:]
        for candidate in candidates {
            let line = lines[candidate.lineIndex]
            let end = lines[(candidate.lineIndex + 1)...].first(where: { next in
                let trimmed = next.content.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && next.content.first?.isWhitespace != true
            })?.fullRange.lowerBound ?? frontmatter.endIndex
            entries[candidate.key] = Entry(
                key: candidate.key,
                line: line,
                colon: candidate.colon,
                fullRange: line.fullRange.lowerBound..<end,
                indentation: ""
            )
        }
        return Analysis(mapping: mapping, entries: entries)
    }

    private static func patchExisting(
        _ frontmatter: String,
        key: String,
        edit: FrontmatterEditValue,
        entry: Entry,
        semanticValue: Any?,
        newline: String
    ) throws -> String {
        if case .remove = edit {
            if isOrdinaryScalar(semanticValue),
               hasStructuredContinuation(in: frontmatter, entry: entry) {
                throw FrontmatterPatchRefusal.unsupportedExistingValue(key)
            }
            var result = frontmatter
            result.removeSubrange(
                isOrdinaryScalar(semanticValue) ? entry.line.fullRange : entry.fullRange
            )
            return result
        }

        if isOrdinaryScalar(semanticValue), let replacement = scalar(edit) {
            return try replacingScalar(
                in: frontmatter,
                key: key,
                entry: entry,
                with: replacement
            )
        }
        if let mapping = semanticValue as? [String: Any],
           case .mapping(let desired) = edit {
            return try patchBlockMapping(
                frontmatter,
                key: key,
                entry: entry,
                semanticMapping: mapping,
                desired: desired,
                newline: newline
            )
        }
        if semanticValue is [Any], case .array = edit {
            let replacement = serialize(
                key: key,
                value: edit,
                indent: entry.indentation
            ).joined(separator: newline)
                + (String(frontmatter[entry.fullRange]).hasSuffix(newline) ? newline : "")
            var result = frontmatter
            result.replaceSubrange(entry.fullRange, with: replacement)
            return result
        }

        throw FrontmatterPatchRefusal.unsupportedExistingValue(key)
    }

    private static func replacingScalar(
        in frontmatter: String,
        key: String,
        entry: Entry,
        with replacement: String
    ) throws -> String {
        let tokenRange = try scalarTokenRange(
            in: frontmatter,
            key: key,
            entry: entry
        )
        var result = frontmatter
        result.replaceSubrange(tokenRange, with: replacement)
        return result
    }

    private static func scalarTokenRange(
        in frontmatter: String,
        key: String,
        entry: Entry
    ) throws -> Range<String.Index> {
        guard !hasStructuredContinuation(in: frontmatter, entry: entry) else {
            throw FrontmatterPatchRefusal.unsupportedExistingValue(key)
        }
        let afterColon = frontmatter.index(after: entry.colon)
        let lineEnd = entry.line.contentRange.upperBound
        let rawValue = String(frontmatter[afterColon..<lineEnd])
        let valueOffset = rawValue.distance(
            from: rawValue.startIndex,
            to: rawValue.firstIndex(where: { !$0.isWhitespace }) ?? rawValue.endIndex
        )
        guard valueOffset < rawValue.count else {
            throw FrontmatterPatchRefusal.unsupportedExistingValue(key)
        }
        let commentOffset = inlineCommentOffset(in: rawValue) ?? rawValue.count
        var valueEndOffset = commentOffset
        while valueEndOffset > valueOffset {
            let index = rawValue.index(rawValue.startIndex, offsetBy: valueEndOffset - 1)
            guard rawValue[index].isWhitespace else { break }
            valueEndOffset -= 1
        }
        guard valueEndOffset > valueOffset else {
            throw FrontmatterPatchRefusal.unsupportedExistingValue(key)
        }
        let existingTokenStart = frontmatter.index(afterColon, offsetBy: valueOffset)
        let existingTokenEnd = frontmatter.index(afterColon, offsetBy: valueEndOffset)
        let existingToken = frontmatter[existingTokenStart..<existingTokenEnd]
        guard existingToken.first != "|", existingToken.first != ">" else {
            throw FrontmatterPatchRefusal.unsupportedExistingValue(key)
        }
        return existingTokenStart..<existingTokenEnd
    }

    private static func hasStructuredContinuation(
        in frontmatter: String,
        entry: Entry
    ) -> Bool {
        frontmatter[entry.line.fullRange.upperBound..<entry.fullRange.upperBound]
            .split(whereSeparator: \Character.isNewline)
            .contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !trimmed.hasPrefix("#")
            }
    }

    private static func patchBlockMapping(
        _ frontmatter: String,
        key: String,
        entry: Entry,
        semanticMapping: [String: Any],
        desired: [String: FrontmatterEditValue],
        newline: String
    ) throws -> String {
        let headerValue = frontmatter[frontmatter.index(after: entry.colon)..<entry.line.contentRange.upperBound]
            .trimmingCharacters(in: .whitespaces)
        guard headerValue.isEmpty || headerValue.hasPrefix("#") else {
            throw FrontmatterPatchRefusal.unsupportedExistingValue(key)
        }

        let children = try analyzeChildEntries(
            in: frontmatter,
            parent: entry,
            semanticKeys: Set(semanticMapping.keys),
            newline: newline
        )
        let childIndent = children.values.first?.indentation ?? "  "
        var operations: [PatchOperation] = []

        for (childKey, childEntry) in children {
            guard let requested = desired[childKey], requested != .remove else {
                operations.append(PatchOperation(
                    range: childEntry.fullRange,
                    replacement: ""
                ))
                continue
            }
            let existing = semanticMapping[childKey]
            if semanticMatches(existing, requested) { continue }

            if isOrdinaryScalar(existing), let replacement = scalar(requested) {
                operations.append(PatchOperation(
                    range: try scalarTokenRange(
                        in: frontmatter,
                        key: "\(key).\(childKey)",
                        entry: childEntry
                    ),
                    replacement: replacement
                ))
                continue
            }
            if existing is [Any], case .array = requested {
                let serialized = serialize(
                    key: childKey,
                    value: requested,
                    indent: childEntry.indentation
                ).joined(separator: newline)
                    + (String(frontmatter[childEntry.fullRange]).hasSuffix(newline) ? newline : "")
                operations.append(PatchOperation(
                    range: childEntry.fullRange,
                    replacement: serialized
                ))
                continue
            }
            throw FrontmatterPatchRefusal.unsupportedExistingValue(
                "\(key).\(childKey)"
            )
        }

        let missing = orderedMappingKeys(desired).filter { childKey in
            children[childKey] == nil && desired[childKey] != .remove
        }
        if !missing.isEmpty {
            let serialized = missing.flatMap { childKey -> [String] in
                guard let value = desired[childKey] else { return [] }
                return serialize(key: childKey, value: value, indent: childIndent)
            }.joined(separator: newline)
            guard !serialized.isEmpty else {
                throw FrontmatterPatchRefusal.unsupportedExistingValue(key)
            }
            let parentText = String(frontmatter[entry.fullRange])
            operations.append(PatchOperation(
                range: entry.fullRange.upperBound..<entry.fullRange.upperBound,
                replacement: (parentText.hasSuffix(newline) ? "" : newline)
                    + serialized
                    + (parentText.hasSuffix(newline) ? newline : "")
            ))
        }

        return applying(operations, to: frontmatter)
    }

    private static func analyzeChildEntries(
        in frontmatter: String,
        parent: Entry,
        semanticKeys: Set<String>,
        newline: String
    ) throws -> [String: Entry] {
        let lines = splitLines(frontmatter, newline: newline)
        guard let parentLineIndex = lines.firstIndex(where: {
            $0.fullRange.lowerBound == parent.line.fullRange.lowerBound
        }) else {
            throw FrontmatterPatchRefusal.ambiguousStructure(
                "the target mapping boundary could not be recovered"
            )
        }

        let descendantIndices = lines.indices.filter { index in
            index > parentLineIndex
                && lines[index].fullRange.lowerBound < parent.fullRange.upperBound
        }
        let structuralIndices = descendantIndices.filter { index in
            let trimmed = lines[index].content.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#")
        }
        guard !structuralIndices.isEmpty else {
            guard semanticKeys.isEmpty else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "the target mapping has no lexically bounded members"
                )
            }
            return [:]
        }

        let indentCount = structuralIndices.map {
            leadingSpaceCount(lines[$0].content)
        }.min() ?? 0
        guard indentCount > 0 else {
            throw FrontmatterPatchRefusal.ambiguousStructure(
                "the target mapping indentation cannot be bounded"
            )
        }
        let indentation = String(repeating: " ", count: indentCount)

        struct ChildCandidate {
            let key: String
            let lineIndex: Int
            let colon: String.Index
        }
        var candidates: [ChildCandidate] = []
        var seenKeys: Set<String> = []
        for index in structuralIndices {
            let line = lines[index]
            guard !line.content.prefix(while: { $0.isWhitespace }).contains("\t") else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "tab-indented YAML cannot be bounded reliably"
                )
            }
            let leading = leadingSpaceCount(line.content)
            guard leading >= indentCount else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "the target mapping contains inconsistent indentation"
                )
            }
            guard leading == indentCount else { continue }

            let text = String(line.content.dropFirst(indentCount))
            guard !containsAliasOrAnchorSyntax(text),
                  !text.hasPrefix("?"),
                  let colonOffset = firstMappingColon(in: text) else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "a target member is not an ordinary bounded key"
                )
            }
            let colon = text.index(text.startIndex, offsetBy: colonOffset)
            let rawKey = text[..<colon].trimmingCharacters(in: .whitespaces)
            guard !rawKey.isEmpty,
                  rawKey.first != "\"", rawKey.first != "'",
                  rawKey != "<<", isPlainBoundedKey(rawKey),
                  seenKeys.insert(rawKey).inserted else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "a target member key is duplicated or semantically ambiguous"
                )
            }
            let absoluteColon = frontmatter.index(
                line.contentRange.lowerBound,
                offsetBy: indentCount + colonOffset
            )
            candidates.append(ChildCandidate(
                key: rawKey,
                lineIndex: index,
                colon: absoluteColon
            ))
        }

        guard Set(candidates.map(\.key)) == semanticKeys else {
            throw FrontmatterPatchRefusal.ambiguousStructure(
                "the parsed and lexical members of the target mapping disagree"
            )
        }

        var entries: [String: Entry] = [:]
        for candidate in candidates {
            let line = lines[candidate.lineIndex]
            let end = lines[(candidate.lineIndex + 1)...].first(where: { next in
                guard next.fullRange.lowerBound < parent.fullRange.upperBound else {
                    return true
                }
                let trimmed = next.content.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return false }
                return leadingSpaceCount(next.content) <= indentCount
            })?.fullRange.lowerBound ?? parent.fullRange.upperBound
            entries[candidate.key] = Entry(
                key: candidate.key,
                line: line,
                colon: candidate.colon,
                fullRange: line.fullRange.lowerBound..<min(end, parent.fullRange.upperBound),
                indentation: indentation
            )
        }
        return entries
    }

    private static func applying(
        _ operations: [PatchOperation],
        to source: String
    ) -> String {
        guard !operations.isEmpty else { return source }
        let ordered = operations.sorted {
            if $0.range.lowerBound == $1.range.lowerBound {
                return $0.range.upperBound < $1.range.upperBound
            }
            return $0.range.lowerBound < $1.range.lowerBound
        }
        var result = ""
        var cursor = source.startIndex
        for operation in ordered {
            precondition(operation.range.lowerBound >= cursor)
            result += source[cursor..<operation.range.lowerBound]
            result += operation.replacement
            cursor = operation.range.upperBound
        }
        result += source[cursor..<source.endIndex]
        return result
    }

    private static func semanticMatches(
        _ existing: Any?,
        _ desired: FrontmatterEditValue
    ) -> Bool {
        switch desired {
        case .string(let value):
            return existing as? String == value
        case .integer(let value):
            return existing as? Int == value
        case .double(let value):
            return existing as? Double == value
        case .boolean(let value):
            return existing as? Bool == value
        case .array(let values):
            guard let existing = existing as? [Any] else { return false }
            return existing.count == values.count
                && zip(existing, values).allSatisfy { item, value in
                    item as? String == value
                }
        case .mapping(let values):
            guard let existing = existing as? [String: Any] else { return false }
            let retained = values.filter { $0.value != .remove }
            guard existing.count == retained.count else { return false }
            return retained.allSatisfy { childKey, childValue in
                semanticMatches(existing[childKey], childValue)
            }
        case .remove:
            return existing == nil
        }
    }

    private static func leadingSpaceCount(_ text: String) -> Int {
        text.prefix(while: { $0 == " " }).count
    }

    private static func splitLines(_ text: String, newline: String) -> [Line] {
        var result: [Line] = []
        var start = text.startIndex
        while start < text.endIndex {
            if let delimiter = text.range(of: newline, range: start..<text.endIndex) {
                result.append(Line(
                    content: String(text[start..<delimiter.lowerBound]),
                    contentRange: start..<delimiter.lowerBound,
                    fullRange: start..<delimiter.upperBound
                ))
                start = delimiter.upperBound
            } else {
                result.append(Line(
                    content: String(text[start..<text.endIndex]),
                    contentRange: start..<text.endIndex,
                    fullRange: start..<text.endIndex
                ))
                break
            }
        }
        return result
    }

    private static func firstMappingColon(in line: String) -> Int? {
        var singleQuoted = false
        var doubleQuoted = false
        var escaped = false
        for (offset, character) in line.enumerated() {
            if escaped { escaped = false; continue }
            if character == "\\", doubleQuoted { escaped = true; continue }
            if character == "'", !doubleQuoted { singleQuoted.toggle(); continue }
            if character == "\"", !singleQuoted { doubleQuoted.toggle(); continue }
            if character == ":", !singleQuoted, !doubleQuoted { return offset }
        }
        return nil
    }

    private static func inlineCommentOffset(in value: String) -> Int? {
        var singleQuoted = false
        var doubleQuoted = false
        var escaped = false
        var previousWasWhitespace = true
        for (offset, character) in value.enumerated() {
            if escaped { escaped = false; previousWasWhitespace = character.isWhitespace; continue }
            if character == "\\", doubleQuoted { escaped = true; continue }
            if character == "'", !doubleQuoted { singleQuoted.toggle() }
            if character == "\"", !singleQuoted { doubleQuoted.toggle() }
            if character == "#", !singleQuoted, !doubleQuoted, previousWasWhitespace {
                return offset
            }
            previousWasWhitespace = character.isWhitespace
        }
        return nil
    }

    private static func containsAliasOrAnchorSyntax(_ line: String) -> Bool {
        var singleQuoted = false
        var doubleQuoted = false
        var escaped = false
        var previousWasBoundary = true
        for character in line {
            if escaped { escaped = false; previousWasBoundary = character.isWhitespace; continue }
            if character == "\\", doubleQuoted { escaped = true; continue }
            if character == "'", !doubleQuoted { singleQuoted.toggle(); continue }
            if character == "\"", !singleQuoted { doubleQuoted.toggle(); continue }
            if character == "#", !singleQuoted, !doubleQuoted { return false }
            if (character == "&" || character == "*"),
               !singleQuoted, !doubleQuoted, previousWasBoundary {
                return true
            }
            previousWasBoundary = character.isWhitespace || character == ":" || character == "["
        }
        return false
    }

    private static func isPlainBoundedKey(_ key: String) -> Bool {
        let forbidden = CharacterSet(charactersIn: "[]{}&*#!|>'\"%@`,?")
        return key.unicodeScalars.allSatisfy { !forbidden.contains($0) }
            && key.first?.isWhitespace != true
            && key.last?.isWhitespace != true
    }

    private static func isOrdinaryScalar(_ value: Any?) -> Bool {
        guard let value else { return true }
        return !(value is [Any]) && !(value is [String: Any])
            && !(value is NSArray) && !(value is NSDictionary)
    }

    private static func scalar(_ value: FrontmatterEditValue) -> String? {
        switch value {
        case .string(let value): quote(value)
        case .integer(let value): String(value)
        case .double(let value): String(value)
        case .boolean(let value): value ? "true" : "false"
        case .array, .mapping, .remove: nil
        }
    }

    private static func serialize(
        key: String,
        value: FrontmatterEditValue,
        indent: String
    ) -> [String] {
        let prefix = indent + key
        switch value {
        case .string(let value):
            return ["\(prefix): \(quote(value))"]
        case .integer(let value):
            return ["\(prefix): \(value)"]
        case .double(let value):
            return ["\(prefix): \(value)"]
        case .boolean(let value):
            return ["\(prefix): \(value ? "true" : "false")"]
        case .array(let values):
            return values.isEmpty
                ? ["\(prefix): []"]
                : ["\(prefix):"] + values.map { "\(indent)  - \(quote($0))" }
        case .mapping(let values):
            if values.isEmpty { return ["\(prefix): {}"] }
            return ["\(prefix):"] + orderedMappingKeys(values).flatMap {
                nestedKey -> [String] in
                guard let nestedValue = values[nestedKey] else { return [] }
                if case .remove = nestedValue { return [] }
                return serialize(key: nestedKey, value: nestedValue, indent: indent + "  ")
            }
        case .remove:
            return []
        }
    }

    private static func orderedMappingKeys(
        _ values: [String: FrontmatterEditValue]
    ) -> [String] {
        let preferred = ["scope", "limitations"]
        return preferred.filter { values[$0] != nil }
            + values.keys.filter { !preferred.contains($0) }.sorted()
    }

    private static func quote(_ value: String) -> String {
        guard !value.isEmpty else { return "\"\"" }
        let lower = value.lowercased()
        let ambiguous = ["true", "false", "null", "~"].contains(lower)
            || Int(value) != nil || Double(value) != nil
            || value.contains(":") || value.contains("#") || value.contains("[")
            || value.contains("]") || value.contains("{") || value.contains("}")
            || value.contains(",") || value.contains("\n")
            || value.first?.isWhitespace == true || value.last?.isWhitespace == true
        guard ambiguous else { return value }
        return "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
}
