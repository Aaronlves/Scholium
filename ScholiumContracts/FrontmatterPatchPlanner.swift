import Foundation
import Yams

public struct FrontmatterSourcePosition: Equatable, Sendable {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }
}

public enum FrontmatterPatchRefusal: Error, LocalizedError, Equatable, Sendable {
    case invalidYAML(String, position: FrontmatterSourcePosition? = nil)
    case nonBlockMappingRoot
    case ambiguousStructure(String, position: FrontmatterSourcePosition? = nil)
    case unsupportedExistingValue(String)
    case semanticMismatch(String)

    public var sourcePosition: FrontmatterSourcePosition? {
        switch self {
        case .invalidYAML(_, let position), .ambiguousStructure(_, let position):
            position
        case .nonBlockMappingRoot:
            FrontmatterSourcePosition(line: 1, column: 1)
        case .unsupportedExistingValue, .semanticMismatch:
            nil
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidYAML(let message, _):
            "The complete YAML frontmatter is invalid: \(message)"
        case .nonBlockMappingRoot:
            "This YAML operation requires a block mapping. Open Source to edit this frontmatter."
        case .ambiguousStructure(let message, _):
            "Scholium refused an ambiguous YAML edit: \(message) Open Source to edit it directly."
        case .unsupportedExistingValue(let key):
            "Scholium can only replace or remove a uniquely bounded ordinary YAML value for ‘\(key)’. Open Source to edit this value."
        case .semanticMismatch(let key):
            "Scholium could not prove that the encoded YAML preserves the requested value for ‘\(key)’. No replacement source was accepted."
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

        let finalAnalysis = try analyze(patched, newline: newline)
        for (key, edit) in edits {
            let actual = finalAnalysis.mapping[key].flatMap(projectedYAMLValue)
            guard semanticValue(for: edit) == actual else {
                throw FrontmatterPatchRefusal.semanticMismatch(key)
            }
        }
        return FrontmatterPatchPlan(
            patchedFrontmatter: patched,
            editedKeys: edits.keys.sorted()
        )
    }

    public static func authoredScalarToken(
        frontmatter: String,
        key: String,
        newline: String
    ) throws -> String? {
        let analysis = try analyze(frontmatter, newline: newline)
        guard let entry = analysis.entries[key],
              isOrdinaryScalar(analysis.mapping[key]) else { return nil }
        let range = try scalarTokenRange(
            in: frontmatter,
            key: key,
            entry: entry
        )
        return String(frontmatter[range])
    }

    public static func isTimestampScalarToken(_ scalarToken: String) -> Bool {
        guard let node = try? compose(yaml: scalarToken) else { return false }
        return node.tag == Tag(.timestamp)
    }

    /// Serializes an already validated ordered set of plain top-level fields.
    /// Delivery adapters never call this with YAML fragments; managed creation
    /// first resolves every value through the canonical property catalog.
    public static func serializeTopLevelMapping(
        _ entries: [(key: String, value: FrontmatterEditValue)]
    ) throws -> String {
        guard !entries.isEmpty,
              Set(entries.map(\.key)).count == entries.count,
              entries.allSatisfy({ entry in
                  !entry.key.isEmpty
                      && !entry.key.contains(":")
                      && !entry.key.contains("#")
                      && !entry.key.unicodeScalars.contains(where: {
                          CharacterSet.controlCharacters.contains($0)
                      })
              }) else {
            throw FrontmatterPatchRefusal.ambiguousStructure(
                "Managed creation requires unique plain top-level YAML keys."
            )
        }
        let source = entries.flatMap {
            serialize(key: $0.key, value: $0.value, indent: "")
        }.joined(separator: "\n") + "\n"
        _ = try analyze(source, newline: "\n")
        return source
    }

    private static func analyze(_ frontmatter: String, newline: String) throws -> Analysis {
        let loaded: Any?
        do {
            loaded = try Yams.load(yaml: frontmatter)
        } catch {
            throw FrontmatterPatchRefusal.invalidYAML(
                error.localizedDescription,
                position: sourcePosition(for: error, source: frontmatter)
            )
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
                    "anchors and aliases are not patchable",
                    position: FrontmatterSourcePosition(line: lineIndex + 1, column: 1)
                )
            }
            if text.first == "\t" {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "tab-indented YAML cannot be bounded reliably",
                    position: FrontmatterSourcePosition(line: lineIndex + 1, column: 1)
                )
            }
            guard text.first?.isWhitespace != true else { continue }
            guard !trimmed.hasPrefix("?"), !trimmed.hasPrefix("---"),
                  !trimmed.hasPrefix("...") else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "complex keys and nested YAML documents are not patchable",
                    position: FrontmatterSourcePosition(line: lineIndex + 1, column: 1)
                )
            }
            guard let colonOffset = firstMappingColon(in: text) else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "a top-level line is not a bounded mapping entry",
                    position: FrontmatterSourcePosition(line: lineIndex + 1, column: 1)
                )
            }
            let colon = text.index(text.startIndex, offsetBy: colonOffset)
            let rawKey = text[..<colon].trimmingCharacters(in: .whitespaces)
            guard !rawKey.isEmpty else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "an empty key is present",
                    position: FrontmatterSourcePosition(line: lineIndex + 1, column: 1)
                )
            }
            guard rawKey.first != "\"", rawKey.first != "'" else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "quoted keys can be semantically equivalent to plain keys",
                    position: FrontmatterSourcePosition(line: lineIndex + 1, column: 1)
                )
            }
            guard rawKey != "<<" else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "a YAML merge key can change the root mapping",
                    position: FrontmatterSourcePosition(line: lineIndex + 1, column: 1)
                )
            }
            guard isPlainBoundedKey(rawKey) else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "the key ‘\(rawKey)’ is not a bounded plain key",
                    position: FrontmatterSourcePosition(line: lineIndex + 1, column: 1)
                )
            }
            guard seenKeys.insert(rawKey).inserted else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "the key ‘\(rawKey)’ occurs more than once",
                    position: FrontmatterSourcePosition(line: lineIndex + 1, column: 1)
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

    private static func sourcePosition(
        for error: Error,
        source: String
    ) -> FrontmatterSourcePosition? {
        guard let yamlError = error as? YamlError else { return nil }
        switch yamlError {
        case .scanner(_, _, let mark, _),
             .parser(_, _, let mark, _),
             .composer(_, _, let mark, _):
            return FrontmatterSourcePosition(line: mark.line, column: mark.column)
        case .duplicatedKeysInMapping(_, let context):
            return FrontmatterSourcePosition(
                line: context.mark.line,
                column: context.mark.column
            )
        case .reader(_, let offset, _, _):
            guard let offset,
                  let index = source.index(
                    source.startIndex,
                    offsetBy: offset,
                    limitedBy: source.endIndex
                  ) else { return nil }
            let prefix = source[..<index]
            let line = prefix.reduce(into: 1) { count, character in
                if character == "\n" { count += 1 }
            }
            let lineStart = prefix.lastIndex(of: "\n").map {
                source.index(after: $0)
            } ?? source.startIndex
            return FrontmatterSourcePosition(
                line: line,
                column: source[lineStart..<index].unicodeScalars.count + 1
            )
        case .no, .memory, .writer, .emitter, .representer,
             .dataCouldNotBeDecoded:
            return nil
        }
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
        if semanticValue is [Any], edit.isSequenceEdit {
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
            if existing is [Any], requested.isSequenceEdit {
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
        case .sequence(let values):
            guard let existing = existing as? [Any], existing.count == values.count else {
                return false
            }
            return zip(existing, values).allSatisfy { item, value in
                semanticMatches(item, value)
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
        case .array, .sequence, .mapping, .remove: nil
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
        case .sequence(let values):
            guard !values.isEmpty else { return ["\(prefix): []"] }
            return ["\(prefix):"] + values.flatMap {
                serializeSequenceItem($0, indent: indent + "  ")
            }
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
        values.keys.sorted()
    }

    private static func serializeSequenceItem(
        _ value: FrontmatterEditValue,
        indent: String
    ) -> [String] {
        if let scalar = scalar(value) { return ["\(indent)- \(scalar)"] }
        switch value {
        case .mapping(let values):
            if values.isEmpty { return ["\(indent)- {}"] }
            let children: [String] = orderedMappingKeys(values).flatMap { key -> [String] in
                guard let child = values[key], child != .remove else { return [] }
                return serialize(key: key, value: child, indent: indent + "  ")
            }
            return ["\(indent)-"] + children
        case .array(let values):
            return ["\(indent)-"] + values.map { "\(indent)  - \(quote($0))" }
        case .sequence(let values):
            return ["\(indent)-"] + values.flatMap {
                serializeSequenceItem($0, indent: indent + "  ")
            }
        case .remove:
            return []
        case .string, .integer, .double, .boolean:
            return []
        }
    }

    private static func quote(_ value: String) -> String {
        guard !value.isEmpty else { return "\"\"" }
        let lower = value.lowercased()
        let leadingIndicators = CharacterSet(charactersIn: "-?:,[]{}#&*!|>'\"%@`")
        let containsControl = value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
        let ambiguous = matchesImplicitNonString(value)
            || ["true", "false", "null", "~", ".nan", ".inf", "-.inf", "+.inf"].contains(lower)
            || Int(value) != nil || Double(value) != nil
            || value.contains(":") || value.contains("#") || value.contains("[")
            || value.contains("]") || value.contains("{") || value.contains("}")
            || value.contains(",") || value.contains("\n")
            || value.unicodeScalars.first.map(leadingIndicators.contains) == true
            || containsControl
            || value.first?.isWhitespace == true || value.last?.isWhitespace == true
        guard ambiguous else { return value }
        guard let encoded = try? JSONEncoder().encode(value) else { return "\"\"" }
        return String(decoding: encoded, as: UTF8.self)
    }

    private static func matchesImplicitNonString(_ value: String) -> Bool {
        return [
            Resolver.Rule.bool,
            Resolver.Rule.int,
            Resolver.Rule.float,
            Resolver.Rule.merge,
            Resolver.Rule.null,
            Resolver.Rule.timestamp,
            Resolver.Rule.value,
        ].contains { matches(value, rule: $0) }
    }

    private static func matches(_ value: String, rule: Resolver.Rule) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        guard let expression = try? NSRegularExpression(
            pattern: rule.pattern
        ) else { return false }
        return expression.firstMatch(in: value, range: range) != nil
    }

    private static func semanticValue(
        for edit: FrontmatterEditValue
    ) -> YAMLValue? {
        switch edit {
        case .string(let value): .string(value)
        case .integer(let value): .integer(value)
        case .double(let value): .double(value)
        case .boolean(let value): .boolean(value)
        case .array(let values): .array(values.map(YAMLValue.string))
        case .sequence(let values): .array(values.compactMap(semanticValue))
        case .mapping(let values):
            .object(values.reduce(into: [:]) { result, entry in
                if let value = semanticValue(for: entry.value) {
                    result[entry.key] = value
                }
            })
        case .remove: nil
        }
    }

    private static func projectedYAMLValue(_ value: Any) -> YAMLValue? {
        switch value {
        case let value as String: .string(value)
        case let value as Bool: .boolean(value)
        case let value as Int: .integer(value)
        case let value as Double: .double(value)
        case let values as [Any]: .array(values.compactMap(projectedYAMLValue))
        case let values as [String: Any]:
            .object(values.reduce(into: [:]) { result, entry in
                if let value = projectedYAMLValue(entry.value) {
                    result[entry.key] = value
                }
            })
        default: nil
        }
    }
}

private extension FrontmatterEditValue {
    var isSequenceEdit: Bool {
        switch self {
        case .array, .sequence: true
        case .string, .integer, .double, .boolean, .mapping, .remove: false
        }
    }
}
