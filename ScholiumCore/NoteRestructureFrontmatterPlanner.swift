import Foundation
import ScholiumContracts
import Yams

/// Transfers authored entry slices; Yams proves their boundaries and values but never serializes source.
enum NoteRestructureFrontmatterPlanner {
    private struct Entry {
        let key: String
        let range: Range<Int>
        let raw: String
        let trailingTrivia: String
        let value: Node
    }

    private struct Mapping {
        let prefix: String
        let entries: [Entry]
    }

    static func edits(
        source: NoteDocument, target: NoteDocument,
        resolutions: [String: NoteRestructurePropertyResolution]
    ) throws -> [AgentSourceEdit] {
        guard source.hasProvableBodyBoundary, target.hasProvableBodyBoundary else {
            throw refusal("Close the YAML frontmatter before merging notes.")
        }
        guard let incoming = source.rawFrontmatter, !incoming.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let from = try mapping(incoming)
        let existing = target.rawFrontmatter ?? ""
        let into = try mapping(existing)
        if Data(incoming.utf8) == Data(existing.utf8) { return [] }
        let current = Dictionary(uniqueKeysWithValues: into.entries.map { ($0.key, $0) })
        var conflicts: [NoteRestructurePropertyConflict] = []
        for entry in from.entries {
            if let old = current[entry.key], Data(old.raw.utf8) != Data(entry.raw.utf8), resolutions[entry.key] == nil {
                conflicts.append(.init(key: entry.key, sourceEntry: entry.raw, destinationEntry: old.raw))
            }
        }
        guard conflicts.isEmpty else { throw NoteRestructureError.propertyConflicts(conflicts) }

        var expected = Dictionary(uniqueKeysWithValues: into.entries.map { ($0.key, $0.value) })
        var replacements: [AgentSourceEdit] = []
        var appended = from.prefix
        for entry in from.entries {
            // Standalone comments have no YAML node owner. Keep them even when
            // the researcher chooses the other value for the preceding key.
            defer { appended += entry.trailingTrivia }
            if let old = current[entry.key] {
                if Data(old.raw.utf8) == Data(entry.raw.utf8) { continue }
                if resolutions[entry.key] == .useSource {
                    replacements.append(
                        .init(
                            startUTF8: old.range.lowerBound, endUTF8: old.range.upperBound,
                            expectedText: old.raw, replacement: entry.raw))
                    expected[entry.key] = entry.value
                }
            } else {
                appended += entry.raw
                expected[entry.key] = entry.value
            }
        }
        var merged = replacements.isEmpty ? existing : try AgentSourceEdit.applying(replacements, to: Data(existing.utf8))
        if !appended.isEmpty {
            if !merged.isEmpty && merged.utf8.last != 10 { merged += target.newlineStyle.sequence }
            merged += appended
        }
        // A following fence needs a newline. Reparse after adding it: block-scalar chomping must not change a value.
        if !merged.isEmpty && merged.utf8.last != 10 { merged += target.newlineStyle.sequence }
        let final = try mapping(merged)
        let actual = Dictionary(uniqueKeysWithValues: final.entries.map { ($0.key, $0.value) })
        guard actual == expected else {
            throw refusal("The combined YAML would change an authored value. Reconcile that property in Source before merging.")
        }
        if let range = target.frontmatterByteRange {
            guard Data(merged.utf8) != Data(existing.utf8) else { return [] }
            return [.init(startUTF8: range.lowerBound, endUTF8: range.upperBound, expectedText: existing, replacement: merged)]
        }
        guard !merged.isEmpty else { return [] }
        let offset = target.rawContent.hasPrefix("\u{FEFF}") ? 3 : 0
        let newline = target.newlineStyle.sequence
        return [.init(startUTF8: offset, endUTF8: offset, expectedText: "", replacement: "---" + newline + merged + "---" + newline)]
    }

    private static func mapping(_ source: String) throws -> Mapping {
        let node: Node?
        do { node = try Yams.compose(yaml: source) } catch { throw refusal("The YAML is invalid. Correct it in Source before merging notes.") }
        guard let node else { return Mapping(prefix: source, entries: []) }
        let firstContent = source.split(whereSeparator: \.isNewline).first {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return !line.isEmpty && !line.hasPrefix("#")
        }?.trimmingCharacters(in: .whitespaces)
        // The bundled Yams mapping loader does not retain a reliable collection style.
        // Key marks plus isolated-entry reparsing prove block boundaries instead.
        guard case .mapping(let map) = node, firstContent?.hasPrefix("{") != true else {
            throw refusal("Merge properties require a YAML block mapping. Reconcile other YAML structures in Source.")
        }
        try validate(node)
        let bytes = Array(source.utf8)
        var lineStarts = [0]
        for index in bytes.indices where bytes[index] == 10 { lineStarts.append(index + 1) }
        var starts: [(key: String, start: Int, value: Node)] = []
        for pair in map {
            guard case .scalar(let scalar) = pair.key, pair.key.tag == Tag(.str),
                !scalar.string.isEmpty, !scalar.string.contains(where: \.isNewline), scalar.string != "<<",
                let mark = scalar.mark, mark.column == 1, mark.line > 0, mark.line <= lineStarts.count
            else { throw refusal("A YAML key cannot be moved independently. Reconcile it in Source before merging.") }
            starts.append((scalar.string, lineStarts[mark.line - 1], pair.value))
        }
        guard Set(starts.map(\.key)).count == starts.count,
            zip(starts, starts.dropFirst()).allSatisfy({ $0.start < $1.start })
        else { throw refusal("Duplicate or ambiguous YAML keys must be reconciled before merging.") }
        guard let first = starts.first else { return Mapping(prefix: source, entries: []) }
        var entries: [Entry] = []
        for (index, entry) in starts.enumerated() {
            let upper = index + 1 < starts.count ? starts[index + 1].start : bytes.count
            let end = entryEnd(in: bytes, start: entry.start, upper: upper, key: entry.key, value: entry.value)
            let range = entry.start..<end
            let raw = String(decoding: bytes[range], as: UTF8.self)
            // Parsing each exact slice also refuses complex keys and dependencies crossing entry boundaries.
            guard let isolated = try? Yams.compose(yaml: raw), case .mapping(let isolatedMap) = isolated,
                isolatedMap.count == 1, let pair = isolatedMap.first,
                pair.key.string == entry.key, pair.value == entry.value
            else { throw refusal("A YAML entry depends on surrounding syntax. Reconcile it in Source before merging.") }
            entries.append(
                Entry(
                    key: entry.key, range: range, raw: raw,
                    trailingTrivia: String(decoding: bytes[end..<upper], as: UTF8.self), value: entry.value))
        }
        return Mapping(prefix: String(decoding: bytes[..<first.start], as: UTF8.self), entries: entries)
    }

    private static func entryEnd(in bytes: [UInt8], start: Int, upper: Int, key: String, value: Node) -> Int {
        // Yams exposes node starts, but no concrete-syntax end tokens. Walk only
        // the trailing run of comment/blank lines, and prove each possible cut
        // against the parsed value. A '#' line inside a block scalar and blank
        // lines retained by '+' chomping must remain part of that value.
        var candidates: [Int] = []
        var end = upper
        while end > start {
            var lineStart = end
            if bytes[lineStart - 1] == 10 { lineStart -= 1 }
            while lineStart > start, bytes[lineStart - 1] != 10 { lineStart -= 1 }
            let line = String(decoding: bytes[lineStart..<end], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.isEmpty || line.hasPrefix("#") else { break }
            candidates.append(lineStart)
            end = lineStart
        }
        for candidate in candidates.reversed() {
            let raw = String(decoding: bytes[start..<candidate], as: UTF8.self)
            guard let isolated = try? Yams.compose(yaml: raw), case .mapping(let map) = isolated,
                map.count == 1, let pair = map.first, pair.key.string == key, pair.value == value
            else { continue }
            return candidate
        }
        return upper
    }

    private static func validate(_ node: Node) throws {
        guard node.anchor == nil else { throw refusal("YAML anchors and aliases must be reconciled in Source before merging properties.") }
        switch node {
        case .alias:
            throw refusal("YAML anchors and aliases must be reconciled in Source before merging properties.")
        case .scalar: break
        case .sequence(let sequence):
            for child in sequence { try validate(child) }
        case .mapping(let mapping):
            var keys: Set<Node> = []
            for pair in mapping {
                guard keys.insert(pair.key).inserted, pair.key.string != "<<" else {
                    throw refusal("Duplicate keys and YAML merge keys must be reconciled in Source before merging properties.")
                }
                try validate(pair.key)
                try validate(pair.value)
            }
        }
    }

    private static func refusal(_ message: String) -> NoteRestructureError { .unavailable(message) }
}
