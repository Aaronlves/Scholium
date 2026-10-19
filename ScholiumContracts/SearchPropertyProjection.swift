import Foundation
import Yams

/// A read-only projection of user-authored YAML, retaining exact source ranges.
public struct SearchPropertyProjection: Hashable, Sendable {
    public enum ValueKind: String, Codable, Hashable, Sendable {
        case null
        case string
        case stringSequence = "string_sequence"
        case scalar
        case sequence
        case mapping
        case alias
    }

    public struct StringMember: Codable, Hashable, Sendable {
        public let value: String
        public let normalizedValue: String
        public let sourceRange: SearchSourceRange?

        public init(
            value: String,
            normalizedValue: String,
            sourceRange: SearchSourceRange?
        ) {
            self.value = value
            self.normalizedValue = normalizedValue
            self.sourceRange = sourceRange
        }
    }

    public struct Entry: Codable, Hashable, Sendable {
        public let key: String
        public let keySourceRange: SearchSourceRange?
        public let valueKind: ValueKind
        public let isEmpty: Bool
        public let stringMembers: [StringMember]

        public init(
            key: String,
            keySourceRange: SearchSourceRange?,
            valueKind: ValueKind,
            isEmpty: Bool,
            stringMembers: [StringMember]
        ) {
            self.key = key
            self.keySourceRange = keySourceRange
            self.valueKind = valueKind
            self.isEmpty = isEmpty
            self.stringMembers = stringMembers
        }
    }

    public enum Issue: Codable, Hashable, Sendable {
        case invalidYAML
        case nonMappingRoot
        case duplicateKey(String)
        case unboundedKey
        case unboundedScalarValue(String)
    }

    public let entries: [Entry]
    public let issues: [Issue]

    public init(
        document: NoteDocument,
        profile: SchemaProfileID = .genericMarkdown
    ) {
        guard document.hasProvableBodyBoundary else {
            entries = []
            issues = [.invalidYAML]
            return
        }
        guard let frontmatter = document.rawFrontmatter else {
            entries = []
            issues = document.rawFrontmatter == nil ? [] : [.invalidYAML]
            return
        }

        let root: Node?
        do {
            root = try Yams.compose(yaml: frontmatter)
        } catch {
            entries = []
            issues = [.invalidYAML]
            return
        }
        guard let root else {
            entries = []
            issues = []
            return
        }
        guard case .mapping(let mapping) = root else {
            entries = []
            issues = [.nonMappingRoot]
            return
        }

        let source = Source(document: document, frontmatter: frontmatter)
        var projected: [Entry] = []
        var projectionIssues: [Issue] = []
        var keyCounts: [String: Int] = [:]

        for pair in mapping {
            guard case .scalar(let keyScalar) = pair.key,
                pair.key.tag.rawValue == Tag.Name.str.rawValue,
                !keyScalar.string.isEmpty,
                !keyScalar.string.contains(where: { $0.isNewline })
            else {
                projectionIssues.append(.unboundedKey)
                continue
            }
            let key = keyScalar.string.precomposedStringWithCanonicalMapping
            keyCounts[key, default: 0] += 1
            guard let keyRange = source.keyTokenRange(keyScalar) else {
                projectionIssues.append(.unboundedKey)
                continue
            }
            let projectedValue = Self.project(pair.value, key: key, source: source)
            projected.append(
                Entry(
                    key: key,
                    keySourceRange: source.searchRange(for: keyRange),
                    valueKind: projectedValue.kind, isEmpty: projectedValue.isEmpty,
                    stringMembers: projectedValue.members
                ))
            projectionIssues.append(contentsOf: projectedValue.issues)
        }

        let duplicates = Set(
            keyCounts.compactMap { key, count in
                count > 1 ? key : nil
            })
        projected.removeAll { $0.keySourceRange != nil && duplicates.contains($0.key) }
        projectionIssues.append(contentsOf: duplicates.sorted().map(Issue.duplicateKey))
        entries = projected.sorted {
            if $0.key != $1.key { return $0.key < $1.key }
            return ($0.keySourceRange?.utf16LowerBound ?? Int.max)
                < ($1.keySourceRange?.utf16LowerBound ?? Int.max)
        }
        issues = projectionIssues
    }

    public func entry(forExactKey key: String) -> Entry? {
        let exact = key.precomposedStringWithCanonicalMapping
        return entries.first { $0.key == exact }
    }

    public func textValues(forExactKey key: String) -> [String] {
        entry(forExactKey: key)?.stringMembers.map(\.value) ?? []
    }

    /// The string-list lexical projection. A lone string scalar is the
    /// one-member case of that list, so `keywords: philosophy` and
    /// `keywords: [philosophy]` project identically. Non-string scalars carry
    /// no lexical projection and yield no members.
    public func stringListMembers(forExactKey key: String) -> [StringMember] {
        guard let entry = entry(forExactKey: key) else { return [] }
        switch entry.valueKind {
        case .string, .stringSequence:
            return entry.stringMembers
        case .null, .scalar, .sequence, .mapping, .alias:
            return []
        }
    }

    private static func project(
        _ node: Node,
        key: String,
        source: Source
    ) -> (kind: ValueKind, members: [StringMember], isEmpty: Bool, issues: [Issue]) {
        switch node {
        case .scalar(let scalar):
            let isString = node.tag.rawValue == Tag.Name.str.rawValue
            guard node.tag.rawValue != Tag.Name.null.rawValue else {
                return (.null, [], true, [])
            }
            guard let range = source.scalarTokenRange(scalar) else {
                return (
                    isString ? .string : .scalar,
                    [],
                    SearchTextNormalization.normalize(scalar.string).isEmpty,
                    [.unboundedScalarValue(key)]
                )
            }
            return (
                isString ? .string : .scalar,
                [
                    StringMember(
                        value: scalar.string,
                        normalizedValue: SearchTextNormalization.normalize(scalar.string),
                        sourceRange: source.searchRange(for: range)
                    )
                ],
                SearchTextNormalization.normalize(scalar.string).isEmpty,
                []
            )
        case .sequence(let sequence):
            var members: [StringMember] = []
            var allStrings = true
            var issues: [Issue] = []
            for child in sequence {
                guard case .scalar(let scalar) = child,
                    child.tag.rawValue != Tag.Name.null.rawValue
                else {
                    allStrings = false
                    continue
                }
                if child.tag.rawValue != Tag.Name.str.rawValue { allStrings = false }
                guard let range = source.scalarTokenRange(scalar) else {
                    allStrings = false
                    issues.append(.unboundedScalarValue(key))
                    continue
                }
                members.append(
                    StringMember(
                        value: scalar.string,
                        normalizedValue: SearchTextNormalization.normalize(scalar.string),
                        sourceRange: source.searchRange(for: range)
                    ))
            }
            return (
                allStrings ? .stringSequence : .sequence,
                members,
                sequence.isEmpty,
                issues
            )
        case .mapping(let mapping):
            return (.mapping, [], mapping.isEmpty, [])
        case .alias:
            return (.alias, [], false, [])
        }
    }
}

private extension SearchPropertyProjection {
    struct Source {
        let units: [UInt16]
        let frontmatterStartUTF16: Int
        private let scalarOffsetsUTF16: [Int]
        private let parserLineStarts: [Int]
        private let sourceLineStartsUTF16: [Int]

        init(document: NoteDocument, frontmatter: String) {
            units = Array(frontmatter.utf16)
            let prefix: String
            if let byteRange = document.frontmatterByteRange {
                let prefixBytes = document.sourceBytes.prefix(byteRange.lowerBound)
                prefix = String(decoding: prefixBytes, as: UTF8.self)
            } else {
                prefix = ""
            }
            frontmatterStartUTF16 = prefix.utf16.count

            // Yams marks count Unicode scalars; Search locators count UTF-16.
            // Build this immutable, operation-local map once instead of walking
            // the source prefix again for every key and sequence member.
            var scalarOffsets = [0]
            var parserStarts = [0]
            var utf16Offset = 0
            var scalarOffset = 0
            var previousWasCR = false
            for scalar in frontmatter.unicodeScalars {
                utf16Offset += scalar.value > 0xFFFF ? 2 : 1
                scalarOffset += 1
                scalarOffsets.append(utf16Offset)
                if scalar.value == 0x0A, previousWasCR {
                    parserStarts[parserStarts.count - 1] = scalarOffset
                } else if Self.isYAMLLineBreak(scalar.value) {
                    parserStarts.append(scalarOffset)
                }
                previousWasCR = scalar.value == 0x0D
            }
            scalarOffsetsUTF16 = scalarOffsets
            parserLineStarts = parserStarts

            // Source ranges never leave authored frontmatter. Include its exact
            // delimiter/BOM prefix, without scanning or retaining the Note body.
            var sourceStarts = [0]
            utf16Offset = 0
            previousWasCR = false
            for unit in (prefix + frontmatter).utf16 {
                utf16Offset += 1
                if unit == 0x0A, previousWasCR {
                    sourceStarts[sourceStarts.count - 1] = utf16Offset
                } else if unit == 0x0A || unit == 0x0D {
                    sourceStarts.append(utf16Offset)
                }
                previousWasCR = unit == 0x0D
            }
            sourceLineStartsUTF16 = sourceStarts
        }

        func range(
            startingAt mark: Mark?,
            tokenUTF16Length: Int
        ) -> Range<Int>? {
            guard let start = utf16Offset(for: mark) else { return nil }
            let upper = start + tokenUTF16Length
            guard upper <= frontmatterStartUTF16 + units.count else { return nil }
            return start..<upper
        }

        func keyTokenRange(_ scalar: Node.Scalar) -> Range<Int>? {
            if scalar.style == .plain {
                guard let range = range(startingAt: scalar.mark, tokenUTF16Length: scalar.string.utf16.count),
                    substring(in: range) == scalar.string
                else { return nil }
                return range
            }
            return scalarTokenRange(scalar)
        }

        func scalarTokenRange(_ scalar: Node.Scalar) -> Range<Int>? {
            guard let start = utf16Offset(for: scalar.mark) else { return nil }
            switch scalar.style {
            case .singleQuoted:
                return quotedRange(start: start, quote: 0x27, doublesQuote: true)
            case .doubleQuoted:
                return quotedRange(start: start, quote: 0x22, doublesQuote: false)
            case .plain, .any:
                // A plain scalar has no escape spelling. Prove the complete
                // decoded text at the parser's start mark; never return a
                // truncated prefix for commas, flow syntax or folded lines.
                guard
                    let range = range(
                        startingAt: scalar.mark,
                        tokenUTF16Length: scalar.string.utf16.count),
                    !scalar.string.isEmpty,
                    substring(in: range) == scalar.string
                else { return nil }
                return range
            case .literal, .folded:
                return blockScalarRange(start: start, scalar: scalar)
            }
        }

        func substring(in utf16Range: Range<Int>) -> String? {
            let lower = utf16Range.lowerBound - frontmatterStartUTF16
            let upper = utf16Range.upperBound - frontmatterStartUTF16
            guard lower >= 0, upper <= units.count,
                isScalarBoundary(lower), isScalarBoundary(upper)
            else { return nil }
            return String(decoding: units[lower..<upper], as: UTF16.self)
        }

        func searchRange(for utf16Range: Range<Int>) -> SearchSourceRange {
            let lowerPosition = lineAndColumn(atUTF16Offset: utf16Range.lowerBound)
            let upperPosition = lineAndColumn(atUTF16Offset: utf16Range.upperBound)
            return SearchSourceRange(
                utf16LowerBound: utf16Range.lowerBound,
                utf16UpperBound: utf16Range.upperBound,
                line: lowerPosition.line,
                column: lowerPosition.column,
                endLine: upperPosition.line,
                endColumn: upperPosition.column
            )
        }

        private func utf16Offset(for mark: Mark?) -> Int? {
            guard let mark, mark.line > 0, mark.line <= parserLineStarts.count, mark.column > 0
            else { return nil }
            let lineStart = parserLineStarts[mark.line - 1]
            let column = mark.column - 1
            guard column < scalarOffsetsUTF16.count - lineStart else { return nil }
            return frontmatterStartUTF16 + scalarOffsetsUTF16[lineStart + column]
        }

        private func quotedRange(
            start: Int,
            quote: UInt16,
            doublesQuote: Bool
        ) -> Range<Int>? {
            let localStart = start - frontmatterStartUTF16
            guard localStart >= 0, localStart < units.count, units[localStart] == quote else { return nil }
            var cursor = localStart + 1
            var escaped = false
            while cursor < units.count {
                let character = units[cursor]
                if doublesQuote, character == quote {
                    let next = cursor + 1
                    if next < units.count, units[next] == quote {
                        cursor = next + 1
                        continue
                    }
                    return start..<(frontmatterStartUTF16 + next)
                }
                if !doublesQuote {
                    if escaped {
                        escaped = false
                    } else if character == 0x5C {
                        escaped = true
                    } else if character == quote {
                        return start..<(frontmatterStartUTF16 + cursor + 1)
                    }
                }
                cursor += 1
            }
            return nil
        }

        private func blockScalarRange(start: Int, scalar: Node.Scalar) -> Range<Int>? {
            let localStart = start - frontmatterStartUTF16
            guard localStart >= 0, localStart < units.count,
                units[localStart] == 0x7C || units[localStart] == 0x3E
            else { return nil }
            guard let mark = scalar.mark, mark.line > 0, mark.line <= parserLineStarts.count else { return nil }
            let lineStart = scalarOffsetsUTF16[parserLineStarts[mark.line - 1]]
            let parentIndent = units[lineStart..<localStart].prefix(while: { $0 == 0x20 }).count
            var end = localStart
            var firstLine = true
            while end < units.count {
                var lineEnd = end
                while lineEnd < units.count, !Self.isSourceLineBreak(units[lineEnd]) { lineEnd += 1 }
                if lineEnd < units.count {
                    if units[lineEnd] == 0x0D, lineEnd + 1 < units.count, units[lineEnd + 1] == 0x0A {
                        lineEnd += 1
                    }
                    lineEnd += 1
                }
                let line = String(decoding: units[end..<lineEnd], as: UTF16.self)
                if !firstLine {
                    let nonblank = !line.allSatisfy(\.isWhitespace)
                    let indent = line.prefix(while: { $0 == " " }).count
                    if nonblank && indent <= parentIndent { break }
                }
                firstLine = false
                end = lineEnd
            }
            let result = start..<(frontmatterStartUTF16 + end)
            guard let token = substring(in: result) else { return nil }
            let lines = token.components(separatedBy: "\n")
            let rebased = lines.enumerated().map { index, line in
                index == 0 ? line : String(line.dropFirst(min(parentIndent, line.prefix(while: { $0 == " " }).count)))
            }.joined(separator: "\n")
            guard let root = try? Yams.compose(yaml: "value: " + rebased),
                case .mapping(let mapping) = root,
                let value = mapping.first?.value,
                case .scalar(let parsed) = value,
                parsed.string == scalar.string,
                value.tag.rawValue == scalar.tag.rawValue
            else { return nil }
            return result
        }

        private func isScalarBoundary(_ offset: Int) -> Bool {
            offset >= 0 && offset <= units.count
                && (offset == units.count || !(0xDC00...0xDFFF).contains(units[offset]))
        }

        private func lineAndColumn(atUTF16Offset offset: Int) -> (line: Int, column: Int) {
            let bounded = min(max(0, offset), frontmatterStartUTF16 + units.count)
            let line = sourceLineIndex(at: bounded)
            return (line + 1, bounded - sourceLineStartsUTF16[line] + 1)
        }

        private func sourceLineIndex(at offset: Int) -> Int {
            var lower = 0
            var upper = sourceLineStartsUTF16.count
            while lower + 1 < upper {
                let middle = (lower + upper) / 2
                if sourceLineStartsUTF16[middle] <= offset { lower = middle } else { upper = middle }
            }
            return lower
        }

        private static func isYAMLLineBreak(_ scalar: UInt32) -> Bool {
            scalar == 0x0A || scalar == 0x0D || scalar == 0x85 || scalar == 0x2028 || scalar == 0x2029
        }

        private static func isSourceLineBreak(_ unit: UInt16) -> Bool {
            isYAMLLineBreak(UInt32(unit)) || unit == 0x0B || unit == 0x0C
        }
    }
}
