import Foundation
import Yams

/// A read-only projection of canonical structured Note fields. Authored YAML
/// retains exact ranges; managed Metadata deliberately has no Markdown range.
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
        case unboundedStringValue(String)
    }

    public let entries: [Entry]
    public let issues: [Issue]

    public init(
        document: NoteDocument,
        profile: SchemaProfileID = .genericMarkdown,
        metadata: NoteMetadataSnapshot? = nil,
        metadataCatalog: NoteMetadataCatalog = .builtIn
    ) {
        let managedEntries = Self.managedEntries(
            metadata,
            profile: profile,
            catalog: metadataCatalog
        )
        guard let frontmatter = document.rawFrontmatter,
              document.validationWarnings.isEmpty else {
            entries = managedEntries
            issues = document.rawFrontmatter == nil ? [] : [.invalidYAML]
            return
        }

        let root: Node?
        do {
            root = try Yams.compose(yaml: frontmatter)
        } catch {
            entries = managedEntries
            issues = [.invalidYAML]
            return
        }
        guard let root else {
            entries = managedEntries
            issues = []
            return
        }
        guard case .mapping(let mapping) = root else {
            entries = managedEntries
            issues = [.nonMappingRoot]
            return
        }

        let source = Source(document: document, frontmatter: frontmatter)
        let authoredKeys = Set(
            PropertyContractCatalog.contracts(for: profile).map(\.canonicalKey)
        )
        var projected: [Entry] = managedEntries
        var projectionIssues: [Issue] = []
        var keyCounts: [String: Int] = [:]

        for pair in mapping {
            guard case .scalar(let keyScalar) = pair.key,
                  keyScalar.style == .plain,
                  let rawKey = pair.key.string,
                  authoredKeys.contains(
                    rawKey.precomposedStringWithCanonicalMapping
                  ) else {
                continue
            }
            guard Self.isQueryableKey(keyScalar.string),
                  let keyRange = source.range(
                    startingAt: keyScalar.mark,
                    tokenUTF16Length: keyScalar.string.utf16.count
                  ),
                  source.substring(in: keyRange) == keyScalar.string else {
                projectionIssues.append(.unboundedKey)
                continue
            }
            let key = keyScalar.string.precomposedStringWithCanonicalMapping
            keyCounts[key, default: 0] += 1
            let projectedValue = Self.project(
                pair.value,
                key: key,
                source: source
            )
            projected.append(Entry(
                key: key,
                keySourceRange: source.searchRange(for: keyRange),
                valueKind: projectedValue.kind,
                isEmpty: projectedValue.isEmpty,
                stringMembers: projectedValue.members
            ))
            projectionIssues.append(contentsOf: projectedValue.issues)
        }

        let duplicates = Set(keyCounts.compactMap { key, count in
            count > 1 ? key : nil
        })
        projected.removeAll { duplicates.contains($0.key) }
        projectionIssues.append(contentsOf: duplicates.sorted().map(Issue.duplicateKey))
        entries = projected.sorted {
            if $0.key != $1.key { return $0.key < $1.key }
            return ($0.keySourceRange?.utf16LowerBound ?? -1)
                < ($1.keySourceRange?.utf16LowerBound ?? -1)
        }
        issues = projectionIssues
    }

    public func entry(forExactKey key: String) -> Entry? {
        let exact = key.precomposedStringWithCanonicalMapping
        return entries.first { $0.key == exact }
    }

    private static func managedEntries(
        _ metadata: NoteMetadataSnapshot?,
        profile: SchemaProfileID,
        catalog: NoteMetadataCatalog
    ) -> [Entry] {
        guard let metadata else { return [] }
        let recognized = Set(catalog.contracts(for: profile).map(\.canonicalKey))
        return metadata.record.fields.keys.filter(recognized.contains).sorted().compactMap { key in
            guard let value = metadata.record.fields[key] else { return nil }
            let kind: ValueKind
            let values: [String]
            let isEmpty: Bool
            switch value {
            case .null:
                kind = .null; values = []; isEmpty = true
            case .string(let text):
                kind = .string; values = [text]
                isEmpty = SearchTextNormalization.normalize(text).isEmpty
            case .array(let members):
                let strings = members.compactMap(\.scalarString)
                if strings.count == members.count {
                    kind = .stringSequence
                    values = strings
                } else {
                    kind = .sequence
                    values = []
                }
                isEmpty = members.isEmpty
            case .object(let members):
                kind = .mapping; values = []; isEmpty = members.isEmpty
            case .integer, .double, .boolean:
                kind = .scalar
                values = value.scalarString.map { [$0] } ?? []
                isEmpty = false
            }
            return Entry(
                key: key,
                keySourceRange: nil,
                valueKind: kind,
                isEmpty: isEmpty,
                stringMembers: values.map {
                    StringMember(
                        value: $0,
                        normalizedValue: SearchTextNormalization.normalize($0),
                        sourceRange: nil
                    )
                }
            )
        }
    }

    private static func project(
        _ node: Node,
        key: String,
        source: Source
    ) -> (kind: ValueKind, members: [StringMember], isEmpty: Bool, issues: [Issue]) {
        switch node {
        case .scalar(let scalar):
            guard node.tag.rawValue == Tag.Name.str.rawValue else {
                return (
                    node.tag.rawValue == Tag.Name.null.rawValue ? .null : .scalar,
                    [],
                    node.tag.rawValue == Tag.Name.null.rawValue,
                    []
                )
            }
            guard let range = source.scalarTokenRange(scalar) else {
                return (
                    .string,
                    [],
                    SearchTextNormalization.normalize(scalar.string).isEmpty,
                    [.unboundedStringValue(key)]
                )
            }
            return (
                .string,
                [StringMember(
                    value: scalar.string,
                    normalizedValue: SearchTextNormalization.normalize(scalar.string),
                    sourceRange: source.searchRange(for: range)
                )],
                SearchTextNormalization.normalize(scalar.string).isEmpty,
                []
            )
        case .sequence(let sequence):
            var members: [StringMember] = []
            var allStrings = true
            var issues: [Issue] = []
            for child in sequence {
                guard case .scalar(let scalar) = child,
                      child.tag.rawValue == Tag.Name.str.rawValue else {
                    allStrings = false
                    continue
                }
                guard let range = source.scalarTokenRange(scalar) else {
                    allStrings = false
                    issues.append(.unboundedStringValue(key))
                    continue
                }
                members.append(StringMember(
                    value: scalar.string,
                    normalizedValue: SearchTextNormalization.normalize(scalar.string),
                    sourceRange: source.searchRange(for: range)
                ))
            }
            return (
                allStrings ? .stringSequence : .sequence,
                allStrings ? members : [],
                sequence.isEmpty,
                issues
            )
        case .mapping(let mapping):
            return (.mapping, [], mapping.isEmpty, [])
        case .alias:
            return (.alias, [], false, [])
        }
    }

    private static func isQueryableKey(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first,
              CharacterSet.letters.contains(first) || first == "_" else {
            return false
        }
        return key.unicodeScalars.dropFirst().allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "_" || scalar == "-"
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
                frontmatterStartUTF16 = String(
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

        func scalarTokenRange(_ scalar: Node.Scalar) -> Range<Int>? {
            guard let start = utf16Offset(for: scalar.mark),
                  let startIndex = complete.utf16.index(
                    complete.utf16.startIndex,
                    offsetBy: start,
                    limitedBy: complete.utf16.endIndex
                  ),
                  let stringStart = startIndex.samePosition(in: complete) else {
                return nil
            }
            switch scalar.style {
            case .singleQuoted:
                return quotedRange(start: stringStart, quote: "'", doublesQuote: true)
            case .doubleQuoted:
                return quotedRange(start: stringStart, quote: "\"", doublesQuote: false)
            case .plain, .any:
                return plainScalarRange(start: stringStart)
            case .literal, .folded:
                // Block scalars retain presence but exact-value Search is
                // intentionally unavailable until their full source span can
                // be proved without reconstructing YAML.
                return nil
            }
        }

        func substring(in utf16Range: Range<Int>) -> String? {
            guard let lower = complete.utf16.index(
                complete.utf16.startIndex,
                offsetBy: utf16Range.lowerBound,
                limitedBy: complete.utf16.endIndex
            ), let upper = complete.utf16.index(
                complete.utf16.startIndex,
                offsetBy: utf16Range.upperBound,
                limitedBy: complete.utf16.endIndex
            ), let lowerIndex = lower.samePosition(in: complete),
               let upperIndex = upper.samePosition(in: complete) else { return nil }
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
                  let utf16Index = scalarIndex.samePosition(in: frontmatter.utf16) else {
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

        private func plainScalarRange(start: String.Index) -> Range<Int>? {
            var cursor = start
            var lastNonWhitespace = start
            var sawContent = false
            var precedingWhitespace = false
            while cursor < complete.endIndex {
                let character = complete[cursor]
                if character == "\n" || character == "\r" || character == "," || character == "]" {
                    break
                }
                if character == "#", precedingWhitespace { break }
                if character.isWhitespace {
                    precedingWhitespace = true
                } else {
                    precedingWhitespace = false
                    sawContent = true
                    lastNonWhitespace = complete.index(after: cursor)
                }
                cursor = complete.index(after: cursor)
            }
            guard sawContent else { return nil }
            return utf16Range(start..<lastNonWhitespace)
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
                if character == "\n" { count += 1 }
            }
            let lastLine = prefix.split(separator: "\n", omittingEmptySubsequences: false).last
                .map(String.init) ?? ""
            return (line, lastLine.utf16.count + 1)
        }
    }
}
