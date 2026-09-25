import Foundation

/// Locates the authored destination within a Markdown AST link/image source span.
/// A caller must first establish that the complete span is a valid inline link.
/// Reference links, autolinks, and destinations spanning lines have no local
/// destination range and are intentionally excluded.
struct MarkdownInlineLinkSource {
    let destinationRange: NSRange
    let pathRange: NSRange
    let alias: String?
    let isAngleDestination: Bool

    init?(_ source: NSString) {
        var cursor = 0
        if source.length > 0, source.character(at: 0) == 0x21 { cursor += 1 }
        guard cursor < source.length, source.character(at: cursor) == 0x5B else { return nil }
        let labelStart = cursor + 1
        cursor = labelStart
        var depth = 1
        while cursor < source.length, depth > 0 {
            let character = source.character(at: cursor)
            if character == 0x5C, cursor + 1 < source.length {
                cursor += 2
                continue
            }
            if character == 0x5B { depth += 1 }
            if character == 0x5D { depth -= 1 }
            cursor += 1
        }
        guard depth == 0, cursor < source.length,
            source.character(at: cursor) == 0x28
        else { return nil }
        let label = source.substring(with: NSRange(location: labelStart, length: cursor - labelStart - 1))
        alias = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : label
        cursor += 1
        while cursor < source.length, Self.isHorizontalSpace(source.character(at: cursor)) { cursor += 1 }
        guard cursor < source.length else { return nil }

        let angle = source.character(at: cursor) == 0x3C
        isAngleDestination = angle
        if angle { cursor += 1 }
        let start = cursor
        var parenthesisDepth = 0
        while cursor < source.length {
            let character = source.character(at: cursor)
            if character == 0x0A || character == 0x0D { return nil }
            if character == 0x5C, cursor + 1 < source.length {
                cursor += 2
                continue
            }
            if angle {
                if character == 0x3E { break }
            } else {
                if character == 0x28 { parenthesisDepth += 1 }
                if character == 0x29 {
                    if parenthesisDepth == 0 { break }
                    parenthesisDepth -= 1
                }
                if parenthesisDepth == 0, Self.isHorizontalSpace(character) { break }
            }
            cursor += 1
        }
        guard cursor > start, cursor < source.length else { return nil }
        let end = cursor
        if angle {
            guard source.character(at: cursor) == 0x3E else { return nil }
            cursor += 1
        }
        // The parser established title and closing syntax; require a closing
        // delimiter after the destination to exclude partial source ranges.
        guard source.character(at: source.length - 1) == 0x29 else { return nil }
        destinationRange = NSRange(location: start, length: end - start)
        let destination = source.substring(with: destinationRange) as NSString
        var fragmentStart: Int?
        var index = 0
        while index < destination.length {
            if destination.character(at: index) == 0x5C, index + 1 < destination.length {
                index += 2
                continue
            }
            if destination.character(at: index) == 0x23 {
                fragmentStart = index
                break
            }
            index += 1
        }
        pathRange = NSRange(location: start, length: fragmentStart ?? destination.length)
    }

    static func unescape(_ raw: String) -> String {
        let scalars = Array(raw.unicodeScalars)
        var result = ""
        var index = 0
        while index < scalars.count {
            if scalars[index] == "\\", index + 1 < scalars.count {
                let next = scalars[index + 1]
                if next.value < 128,
                    CharacterSet.punctuationCharacters.contains(next)
                {
                    index += 1
                }
            }
            result.unicodeScalars.append(scalars[index])
            index += 1
        }
        return result
    }

    private static func isHorizontalSpace(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09
    }
}
