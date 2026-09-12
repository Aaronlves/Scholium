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
        let complete: String
        let frontmatter: String
        let frontmatterStartUTF16: Int

        init(document: NoteDocument, frontmatter: String) {
            complete = document.rawContent
            self.frontmatter = frontmatter
            if let byteRange = document.frontmatterByteRange {
                let prefixBytes = document.sourceBytes.prefix(byteRange.lowerBound)
                frontmatterStartUTF16 =
                    String(
                        decoding: prefixBytes,
                        as: UTF8.self
                    ).utf16.count
            } else {
                frontmatterStartUTF16 = 0
            }
        }

        func range(
            startingAt mark: Mark?,
            tokenUTF16Length: Int
        ) -> Range<Int>? {
            guard let start = utf16Offset(for: mark) else { return nil }
            let upper = start + tokenUTF16Length
            guard upper <= complete.utf16.count else { return nil }
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
            guard let start = utf16Offset(for: scalar.mark),
                let startIndex = complete.utf16.index(
                    complete.utf16.startIndex,
                    offsetBy: start,
                    limitedBy: complete.utf16.endIndex
                ),
                let stringStart = startIndex.samePosition(in: complete)
            else {
                return nil
            }
            switch scalar.style {
            case .singleQuoted:
                return quotedRange(start: stringStart, quote: "'", doublesQuote: true)
            case .doubleQuoted:
                return quotedRange(start: stringStart, quote: "\"", doublesQuote: false)
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
                return blockScalarRange(start: stringStart, scalar: scalar)
            }
        }

        func substring(in utf16Range: Range<Int>) -> String? {
            guard
                let lower = complete.utf16.index(
                    complete.utf16.startIndex,
                    offsetBy: utf16Range.lowerBound,
                    limitedBy: complete.utf16.endIndex
                ),
                let upper = complete.utf16.index(
                    complete.utf16.startIndex,
                    offsetBy: utf16Range.upperBound,
                    limitedBy: complete.utf16.endIndex
                ), let lowerIndex = lower.samePosition(in: complete),
                let upperIndex = upper.samePosition(in: complete)
            else { return nil }
            return String(complete[lowerIndex..<upperIndex])
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
            guard let mark, mark.line > 0, mark.column > 0 else { return nil }
            var line = 1
            var lineStart = frontmatter.unicodeScalars.startIndex
            var cursor = lineStart
            while line < mark.line, cursor < frontmatter.unicodeScalars.endIndex {
                if frontmatter.unicodeScalars[cursor].value == 0x0A {
                    line += 1
                    lineStart = frontmatter.unicodeScalars.index(after: cursor)
                }
                cursor = frontmatter.unicodeScalars.index(after: cursor)
            }
            guard line == mark.line,
                let scalarIndex = frontmatter.unicodeScalars.index(
                    lineStart,
                    offsetBy: mark.column - 1,
                    limitedBy: frontmatter.unicodeScalars.endIndex
                ),
                let utf16Index = scalarIndex.samePosition(in: frontmatter.utf16)
            else {
                return nil
            }
            return frontmatterStartUTF16
                + frontmatter.utf16.distance(
                    from: frontmatter.utf16.startIndex,
                    to: utf16Index
                )
        }

        private func quotedRange(
            start: String.Index,
            quote: Character,
            doublesQuote: Bool
        ) -> Range<Int>? {
            guard start < complete.endIndex, complete[start] == quote else { return nil }
            var cursor = complete.index(after: start)
            var escaped = false
            while cursor < complete.endIndex {
                let character = complete[cursor]
                if doublesQuote, character == quote {
                    let next = complete.index(after: cursor)
                    if next < complete.endIndex, complete[next] == quote {
                        cursor = complete.index(after: next)
                        continue
                    }
                    return utf16Range(start..<next)
                }
                if !doublesQuote {
                    if escaped {
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == quote {
                        return utf16Range(start..<complete.index(after: cursor))
                    }
                }
                cursor = complete.index(after: cursor)
            }
            return nil
        }

        private func blockScalarRange(start: String.Index, scalar: Node.Scalar) -> Range<Int>? {
            guard complete[start] == "|" || complete[start] == ">" else { return nil }
            let yamlEnd = frontmatterStartUTF16 + frontmatter.utf16.count
            let prefix = complete[..<start]
            let lineStart =
                prefix.lastIndex(where: { $0.isNewline }).map { complete.index(after: $0) }
                ?? complete.startIndex
            let parentIndent = complete[lineStart..<start].prefix(while: { $0 == " " }).count
            var end = start
            var firstLine = true
            while end < complete.endIndex, end.utf16Offset(in: complete) < yamlEnd {
                let lineEnd =
                    complete[end...].firstIndex(where: { $0.isNewline })
                    .map { complete.index(after: $0) } ?? complete.endIndex
                let line = complete[end..<lineEnd]
                if !firstLine {
                    let nonblank = !line.allSatisfy(\.isWhitespace)
                    let indent = line.prefix(while: { $0 == " " }).count
                    if nonblank && indent <= parentIndent { break }
                }
                firstLine = false
                end = lineEnd
            }
            let boundedEnd = min(end.utf16Offset(in: complete), yamlEnd)
            let result = start.utf16Offset(in: complete)..<boundedEnd
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

        private func utf16Range(_ range: Range<String.Index>) -> Range<Int> {
            let lower = range.lowerBound.utf16Offset(in: complete)
            let upper = range.upperBound.utf16Offset(in: complete)
            return lower..<upper
        }

        private func lineAndColumn(atUTF16Offset offset: Int) -> (line: Int, column: Int) {
            let bounded = min(max(0, offset), complete.utf16.count)
            let prefix = String(complete.utf16.prefix(bounded)) ?? ""
            let line = prefix.reduce(into: 1) { count, character in
                if character.isNewline { count += 1 }
            }
            let lastLine =
                prefix.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).last
                .map(String.init) ?? ""
            return (line, lastLine.utf16.count + 1)
        }
    }
}
