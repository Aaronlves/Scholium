import Foundation

/// Shared range rules for deciding when Live Preview exposes Markdown source
/// markers around the insertion point. The source string is never modified.
public enum MarkdownSyntaxProjection {
    public static func shouldReveal(
        enclosingRange: NSRange,
        selections: [NSRange],
        isEditable: Bool
    ) -> Bool {
        guard isEditable,
              enclosingRange.location != NSNotFound,
              enclosingRange.location >= 0,
              enclosingRange.length >= 0 else { return false }

        let end = NSMaxRange(enclosingRange)
        return selections.contains { selection in
            guard selection.location != NSNotFound, selection.location >= 0 else { return false }
            if selection.length == 0 {
                return selection.location >= enclosingRange.location && selection.location <= end
            }
            return NSIntersectionRange(enclosingRange, selection).length > 0
        }
    }

    /// Returns a clamped scroll origin that keeps an anchored glyph at the
    /// same visible position after projection attributes change its layout.
    public static func viewportOriginPreservingAnchor(
        currentOrigin: CGFloat,
        anchorPositionBefore: CGFloat,
        anchorPositionAfter: CGFloat,
        minimumOrigin: CGFloat = 0,
        maximumOrigin: CGFloat
    ) -> CGFloat {
        let proposedOrigin = currentOrigin + anchorPositionAfter - anchorPositionBefore
        return min(maximumOrigin, max(minimumOrigin, proposedOrigin))
    }
}

public struct MarkdownEditorDelta: Codable, Hashable, Sendable {
    public let fromUTF16: Int
    public let toUTF16: Int
    public let insertion: String

    public init(fromUTF16: Int, toUTF16: Int, insertion: String) {
        self.fromUTF16 = fromUTF16
        self.toUTF16 = toUTF16
        self.insertion = insertion
    }
}

public enum MarkdownEditorDeltaError: LocalizedError, Sendable {
    case invalidRange
    case overlappingRanges
    case oversizedResult

    public var errorDescription: String? {
        switch self {
        case .invalidRange: "The editor returned an invalid UTF-16 change range."
        case .overlappingRanges: "The editor returned overlapping document changes."
        case .oversizedResult: "The edited Markdown document exceeds the supported bridge size."
        }
    }
}

public enum MarkdownEditorDeltaApplier {
    public static let maximumResultUTF8Bytes = 8_000_000

    public static func apply(
        _ deltas: [MarkdownEditorDelta],
        to source: String,
        maximumUTF8Bytes: Int = maximumResultUTF8Bytes
    ) throws -> String {
        let sourceLength = (source as NSString).length
        let ordered = deltas.sorted {
            if $0.fromUTF16 == $1.fromUTF16 { return $0.toUTF16 > $1.toUTF16 }
            return $0.fromUTF16 > $1.fromUTF16
        }
        var previousLowerBound = sourceLength
        for delta in ordered {
            guard delta.fromUTF16 >= 0,
                  delta.toUTF16 >= delta.fromUTF16,
                  delta.toUTF16 <= sourceLength else {
                throw MarkdownEditorDeltaError.invalidRange
            }
            guard delta.toUTF16 <= previousLowerBound else {
                throw MarkdownEditorDeltaError.overlappingRanges
            }
            previousLowerBound = delta.fromUTF16
        }

        let result = NSMutableString(string: source)
        for delta in ordered {
            result.replaceCharacters(
                in: NSRange(
                    location: delta.fromUTF16,
                    length: delta.toUTF16 - delta.fromUTF16
                ),
                with: delta.insertion
            )
        }
        let updated = result as String
        guard updated.utf8.count <= maximumUTF8Bytes else {
            throw MarkdownEditorDeltaError.oversizedResult
        }
        return updated
    }
}
