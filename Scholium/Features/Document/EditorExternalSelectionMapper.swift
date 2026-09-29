import Foundation

/// Retains only editor selections whose exact source remains unchanged across
/// an external revision. The changed corridor may include several edits; no
/// position inside it is inferred from text similarity or a stale UTF-16 offset.
enum EditorExternalSelectionMapper {
    static func map(
        _ ranges: [MarkdownEditorSelectionRange],
        from oldSource: String,
        to newSource: String
    ) -> [MarkdownEditorSelectionRange]? {
        let oldMap = EditorSourceOffsetMap(source: oldSource)
        let newMap = EditorSourceOffsetMap(source: newSource)
        guard markdownEditorSelectionRangesAreValid(
            ranges, forEditorUTF16Length: oldMap.editorUTF16Length
        ) else { return nil }

        let oldUnits = Array(oldSource.utf16)
        let newUnits = Array(newSource.utf16)
        if oldUnits == newUnits {
            let endpoints = ranges.flatMap { range in
                [range.anchor, range.head].compactMap {
                    oldMap.sourceUTF16Offset(forEditorUTF16Offset: $0)
                }
            }
            guard endpoints.count == ranges.count * 2,
                areCharacterBoundaries(Set(endpoints), in: oldSource)
            else { return nil }
            return ranges
        }
        var prefix = 0
        while prefix < min(oldUnits.count, newUnits.count),
            oldUnits[prefix] == newUnits[prefix]
        {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldUnits.count - prefix,
            suffix < newUnits.count - prefix,
            oldUnits[oldUnits.count - suffix - 1] == newUnits[newUnits.count - suffix - 1]
        {
            suffix += 1
        }
        let oldSuffixStart = oldUnits.count - suffix
        let shift = newUnits.count - oldUnits.count

        var oldEndpoints: Set<Int> = []
        var newEndpoints: Set<Int> = []
        var mapped: [MarkdownEditorSelectionRange] = []
        mapped.reserveCapacity(ranges.count)
        for range in ranges {
            guard let anchor = oldMap.sourceUTF16Offset(forEditorUTF16Offset: range.anchor),
                let head = oldMap.sourceUTF16Offset(forEditorUTF16Offset: range.head),
                let anchorRegion = region(of: anchor, prefix: prefix, suffixStart: oldSuffixStart),
                region(of: head, prefix: prefix, suffixStart: oldSuffixStart) == anchorRegion
            else { return nil }
            let mappedAnchor = anchor + (anchorRegion == .suffix ? shift : 0)
            let mappedHead = head + (anchorRegion == .suffix ? shift : 0)
            guard let editorAnchor = newMap.editorUTF16Offset(forSourceUTF16Offset: mappedAnchor),
                let editorHead = newMap.editorUTF16Offset(forSourceUTF16Offset: mappedHead)
            else { return nil }
            oldEndpoints.formUnion([anchor, head])
            newEndpoints.formUnion([mappedAnchor, mappedHead])
            mapped.append(.init(anchor: editorAnchor, head: editorHead))
        }
        guard areCharacterBoundaries(oldEndpoints, in: oldSource),
            areCharacterBoundaries(newEndpoints, in: newSource),
            markdownEditorSelectionRangesAreValid(
                mapped, forEditorUTF16Length: newMap.editorUTF16Length
            )
        else { return nil }
        return mapped
    }

    private enum Region: Equatable {
        case prefix
        case suffix
    }

    private static func region(
        of offset: Int, prefix: Int, suffixStart: Int
    ) -> Region? {
        // An insertion has no old changed span. Its seam has two possible
        // affinities, so a caret or selection endpoint there cannot be mapped.
        if prefix == suffixStart, offset == prefix { return nil }
        if offset <= prefix { return .prefix }
        if offset >= suffixStart { return .suffix }
        return nil
    }

    private static func areCharacterBoundaries(
        _ offsets: Set<Int>, in source: String
    ) -> Bool {
        var remaining = offsets
        remaining.remove(0)
        if remaining.isEmpty { return true }
        var offset = 0
        for character in source {
            offset += String(character).utf16.count
            remaining.remove(offset)
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }
}
