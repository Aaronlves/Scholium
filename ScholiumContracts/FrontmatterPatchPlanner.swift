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
        /// Keys whose authored bytes cannot be bounded. Each one withdraws
        /// only itself; every other key in the same envelope stays patchable.
        let unpatchableKeys: [String: FrontmatterPatchRefusal]
    }

    public static func plan(
        frontmatter: String,
        edits: [String: FrontmatterEditValue],
        newline: String
    ) throws -> FrontmatterPatchPlan {
        var patched = frontmatter
        let original = try analyze(frontmatter)
        for key in edits.keys.sorted() {
            guard let edit = edits[key] else { continue }
            let analysis = try analyze(patched)
            if let refusal = analysis.unpatchableKeys[key] {
                throw refusal
            }
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
                } else if trailingLineTerminator(of: patched).isEmpty {
                    patched += newline + serialized
                } else {
                    patched += serialized + newline
                }
            }
        }

        let finalAnalysis = try analyze(patched)
        for (key, edit) in edits {
            let actual = finalAnalysis.mapping[key].flatMap(projectedYAMLValue)
            guard semanticValue(for: edit) == actual else {
                throw FrontmatterPatchRefusal.semanticMismatch(key)
            }
        }
        // Withdrawing one key rather than the whole envelope is only sound if
        // the bytes written for that key left every other property exactly as
        // authored. Prove that against the same complete parse instead of
        // assuming it from the lexical bounds.
        for key in Set(original.mapping.keys).union(finalAnalysis.mapping.keys)
        where edits[key] == nil {
            let before = original.mapping[key].flatMap(projectedYAMLValue)
            let after = finalAnalysis.mapping[key].flatMap(projectedYAMLValue)
            guard before == after else {
                throw FrontmatterPatchRefusal.semanticMismatch(key)
            }
        }
        return FrontmatterPatchPlan(
            patchedFrontmatter: patched,
            editedKeys: edits.keys.sorted()
        )
    }

    private static func analyze(_ frontmatter: String) throws -> Analysis {
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
        let lines = splitLines(frontmatter)
        guard
            let firstSignificant = lines.first(where: { line in
                let trimmed = line.content.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !trimmed.hasPrefix("#")
            })
        else {
            return Analysis(mapping: mapping, entries: [:], unpatchableKeys: [:])
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
        // Every top-level line opens a region covering itself and the lines
        // indented beneath it. A defect is recorded against the region that
        // contains it rather than thrown, so one quoted key, one tab or one
        // anchor withdraws only its own property and leaves the rest of the
        // note's properties readable and writable.
        var regionIndex = -1
        var regionKeys: [Int: String] = [:]
        var regionRefusals: [Int: FrontmatterPatchRefusal] = [:]

        func record(_ refusal: FrontmatterPatchRefusal) throws {
            // A defect above the first top-level line belongs to no property,
            // so it can only withdraw the envelope.
            guard regionIndex >= 0 else { throw refusal }
            if regionRefusals[regionIndex] == nil {
                regionRefusals[regionIndex] = refusal
            }
        }

        for (lineIndex, line) in lines.enumerated() {
            let text = line.content
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let position = FrontmatterSourcePosition(line: lineIndex + 1, column: 1)
            let isTopLevel = text.first?.isWhitespace != true
            if isTopLevel { regionIndex += 1 }

            // A nested document marker divides the envelope itself, so no one
            // region can bound it.
            guard !trimmed.hasPrefix("---"), !trimmed.hasPrefix("...") else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "complex keys and nested YAML documents are not patchable",
                    position: position
                )
            }

            var defect: FrontmatterPatchRefusal?
            if containsAliasOrAnchorSyntax(text) {
                defect = .ambiguousStructure(
                    "anchors and aliases are not patchable",
                    position: position
                )
            } else if text.first == "\t" {
                defect = .ambiguousStructure(
                    "tab-indented YAML cannot be bounded reliably",
                    position: position
                )
            }

            guard isTopLevel else {
                if let defect { try record(defect) }
                continue
            }

            var colonOffset: Int?
            if let offset = firstMappingColon(in: text) {
                colonOffset = offset
                let colon = text.index(text.startIndex, offsetBy: offset)
                let rawKey = text[..<colon].trimmingCharacters(in: .whitespaces)
                // A quoted key names the same property as its plain spelling,
                // so its defect has to withdraw the decoded name.
                regionKeys[regionIndex] = decodedKeyName(rawKey)
                let keyDefect: FrontmatterPatchRefusal? =
                    if rawKey.isEmpty {
                        .ambiguousStructure("an empty key is present", position: position)
                    } else if rawKey.first == "\"" || rawKey.first == "'" {
                        .ambiguousStructure(
                            "quoted keys can be semantically equivalent to plain keys",
                            position: position
                        )
                    } else if rawKey == "<<" {
                        .ambiguousStructure(
                            "a YAML merge key can change the root mapping",
                            position: position
                        )
                    } else if trimmed.hasPrefix("?") {
                        .ambiguousStructure(
                            "complex keys and nested YAML documents are not patchable",
                            position: position
                        )
                    } else if !isPlainBoundedKey(rawKey) {
                        .ambiguousStructure(
                            "the key ‘\(rawKey)’ is not a bounded plain key",
                            position: position
                        )
                    } else if !seenKeys.insert(rawKey).inserted {
                        .ambiguousStructure(
                            "the key ‘\(rawKey)’ occurs more than once",
                            position: position
                        )
                    } else {
                        nil
                    }
                defect = defect ?? keyDefect
            } else {
                defect =
                    defect
                    ?? .ambiguousStructure(
                        "a top-level line is not a bounded mapping entry",
                        position: position
                    )
            }

            if let defect {
                try record(defect)
                continue
            }
            guard let colonOffset, let key = regionKeys[regionIndex] else { continue }
            let absoluteColon = frontmatter.index(
                line.contentRange.lowerBound,
                offsetBy: colonOffset
            )
            candidates.append(
                Candidate(
                    key: key,
                    lineIndex: lineIndex,
                    colon: absoluteColon
                ))
        }

        var unpatchableKeys: [String: FrontmatterPatchRefusal] = [:]
        for (index, refusal) in regionRefusals {
            guard let key = regionKeys[index] else { continue }
            unpatchableKeys[key] = refusal
        }
        // A key that is clean on one line and defective on another — a
        // duplicate, or a quoted restatement — is not uniquely bounded either.
        candidates.removeAll { unpatchableKeys[$0.key] != nil }

        var entries: [String: Entry] = [:]
        for candidate in candidates {
            let line = lines[candidate.lineIndex]
            let end =
                lines[(candidate.lineIndex + 1)...].first(where: { next in
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
        return Analysis(
            mapping: mapping,
            entries: entries,
            unpatchableKeys: unpatchableKeys
        )
    }

    /// A quoted key names the same property as its plain spelling, so a
    /// defect on `"title": …` has to withdraw `title`, not the literal quotes.
    private static func decodedKeyName(_ rawKey: String) -> String {
        guard rawKey.first == "\"" || rawKey.first == "'" else { return rawKey }
        guard let decoded = try? Yams.load(yaml: rawKey) as? String else { return rawKey }
        return decoded
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
                )
            else { return nil }
            let prefix = source[..<index]
            let line = prefix.reduce(into: 1) { count, character in
                if character == "\n" { count += 1 }
            }
            let lineStart =
                prefix.lastIndex(of: "\n").map {
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
                hasStructuredContinuation(in: frontmatter, entry: entry)
            {
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
            case .mapping(let desired) = edit
        {
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
            let replacement =
                serialize(
                    key: key,
                    value: edit,
                    indent: entry.indentation
                ).joined(separator: newline)
                + trailingLineTerminator(of: String(frontmatter[entry.fullRange]))
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
                operations.append(
                    PatchOperation(
                        range: childEntry.fullRange,
                        replacement: ""
                    ))
                continue
            }
            let existing = semanticMapping[childKey]
            if semanticMatches(existing, requested) { continue }

            if isOrdinaryScalar(existing), let replacement = scalar(requested) {
                operations.append(
                    PatchOperation(
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
                let serialized =
                    serialize(
                        key: childKey,
                        value: requested,
                        indent: childEntry.indentation
                    ).joined(separator: newline)
                    + trailingLineTerminator(of: String(frontmatter[childEntry.fullRange]))
                operations.append(
                    PatchOperation(
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
            let parentTerminator = trailingLineTerminator(of: parentText)
            operations.append(
                PatchOperation(
                    range: entry.fullRange.upperBound..<entry.fullRange.upperBound,
                    replacement: (parentTerminator.isEmpty ? newline : "")
                        + serialized
                        + parentTerminator
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
        let lines = splitLines(frontmatter)
        guard
            let parentLineIndex = lines.firstIndex(where: {
                $0.fullRange.lowerBound == parent.line.fullRange.lowerBound
            })
        else {
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

        let indentCount =
            structuralIndices.map {
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
                let colonOffset = firstMappingColon(in: text)
            else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "a target member is not an ordinary bounded key"
                )
            }
            let colon = text.index(text.startIndex, offsetBy: colonOffset)
            let rawKey = text[..<colon].trimmingCharacters(in: .whitespaces)
            guard !rawKey.isEmpty,
                rawKey.first != "\"", rawKey.first != "'",
                rawKey != "<<", isPlainBoundedKey(rawKey),
                seenKeys.insert(rawKey).inserted
            else {
                throw FrontmatterPatchRefusal.ambiguousStructure(
                    "a target member key is duplicated or semantically ambiguous"
                )
            }
            let absoluteColon = frontmatter.index(
                line.contentRange.lowerBound,
                offsetBy: indentCount + colonOffset
            )
            candidates.append(
                ChildCandidate(
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
            let end =
                lines[(candidate.lineIndex + 1)...].first(where: { next in
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

    /// Splits on every authored line terminator rather than on the document’s
    /// dominant one. A note that mixes CRLF and LF is still a note, and a YAML
    /// parser reads both; splitting on the dominant terminator alone would fold
    /// a whole LF region into one apparently unbounded line and withdraw every
    /// key inside it.
    private static func splitLines(_ text: String) -> [Line] {
        var result: [Line] = []
        var start = text.startIndex
        var cursor = text.startIndex
        while cursor < text.endIndex {
            // Swift reads CRLF as one grapheme, so advancing past the cluster
            // consumes the whole terminator.
            guard isLineTerminator(text[cursor]) else {
                cursor = text.index(after: cursor)
                continue
            }
            let terminatorEnd = text.index(after: cursor)
            result.append(
                Line(
                    content: String(text[start..<cursor]),
                    contentRange: start..<cursor,
                    fullRange: start..<terminatorEnd
                ))
            start = terminatorEnd
            cursor = terminatorEnd
        }
        if start < text.endIndex {
            result.append(
                Line(
                    content: String(text[start..<text.endIndex]),
                    contentRange: start..<text.endIndex,
                    fullRange: start..<text.endIndex
                ))
        }
        return result
    }

    /// YAML 1.2 breaks lines on LF and CR only; Unicode’s other separators are
    /// ordinary content inside a scalar.
    private static func isLineTerminator(_ character: Character) -> Bool {
        character == "\n" || character == "\r" || character == "\r\n"
    }

    /// The terminator a stretch of authored bytes actually ends with, which is
    /// not always the document’s dominant one. Returns an empty string when the
    /// text ends without a terminator, so it can be concatenated unconditionally.
    private static func trailingLineTerminator(of text: String) -> String {
        guard let last = text.last, isLineTerminator(last) else { return "" }
        return String(last)
    }

    private static func firstMappingColon(in line: String) -> Int? {
        var singleQuoted = false
        var doubleQuoted = false
        var escaped = false
        for (offset, character) in line.enumerated() {
            if escaped {
                escaped = false
                continue
            }
            if character == "\\", doubleQuoted {
                escaped = true
                continue
            }
            if character == "'", !doubleQuoted {
                singleQuoted.toggle()
                continue
            }
            if character == "\"", !singleQuoted {
                doubleQuoted.toggle()
                continue
            }
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
            if escaped {
                escaped = false
                previousWasWhitespace = character.isWhitespace
                continue
            }
            if character == "\\", doubleQuoted {
                escaped = true
                continue
            }
            if character == "'", !doubleQuoted { singleQuoted.toggle() }
            if character == "\"", !singleQuoted { doubleQuoted.toggle() }
            if character == "#", !singleQuoted, !doubleQuoted, previousWasWhitespace {
                return offset
            }
            previousWasWhitespace = character.isWhitespace
        }
        return nil
    }

    /// Anchors and aliases only occur where a YAML node may begin: line start,
    /// after a mapping colon, after a block sequence indicator, or after a flow
    /// collection separator. A `&` or `*` in any other position belongs to a
    /// plain scalar, so `authors: Smith & Jones` and `summary: see *this*` are
    /// ordinary text and must not refuse the envelope.
    private static func containsAliasOrAnchorSyntax(_ line: String) -> Bool {
        var singleQuoted = false
        var doubleQuoted = false
        var escaped = false
        var atNodeStart = true
        var previousWasSpace = true
        for character in line {
            if escaped {
                escaped = false
                atNodeStart = false
                previousWasSpace = false
                continue
            }
            if character == "\\", doubleQuoted {
                escaped = true
                continue
            }
            if character == "'", !doubleQuoted {
                singleQuoted.toggle()
                atNodeStart = false
                previousWasSpace = false
                continue
            }
            if character == "\"", !singleQuoted {
                doubleQuoted.toggle()
                atNodeStart = false
                previousWasSpace = false
                continue
            }
            if !singleQuoted, !doubleQuoted {
                // A `#` only opens a comment at a whitespace boundary; the rest
                // of the line is then commentary and cannot anchor a node.
                if character == "#", previousWasSpace { return false }
                if character == "&" || character == "*", atNodeStart { return true }
            }
            if character.isWhitespace {
                // Whitespace separates tokens without ending a node position.
                previousWasSpace = true
                continue
            }
            previousWasSpace = false
            if singleQuoted || doubleQuoted {
                atNodeStart = false
                continue
            }
            switch character {
            case ":", ",", "[", "{":
                atNodeStart = true
            case "-":
                // A leading `-` is a sequence indicator and keeps the node
                // position open; inside a scalar it is already closed.
                break
            default:
                atNodeStart = false
            }
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
            return ["\(prefix):"]
                + values.flatMap {
                    serializeSequenceItem($0, indent: indent + "  ")
                }
        case .mapping(let values):
            if values.isEmpty { return ["\(prefix): {}"] }
            return ["\(prefix):"]
                + orderedMappingKeys(values).flatMap {
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
            return ["\(indent)-"]
                + values.flatMap {
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
        let ambiguous =
            matchesImplicitNonString(value)
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
        guard
            let expression = try? NSRegularExpression(
                pattern: rule.pattern
            )
        else { return false }
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
            .object(
                values.reduce(into: [:]) { result, entry in
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
            .object(
                values.reduce(into: [:]) { result, entry in
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
