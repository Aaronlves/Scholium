import Foundation
import ScholiumContracts

/// Main-actor exact-source mirror for the retained CodeMirror document.
/// Ordinary input mutates UTF-16 storage in place and maintains its byte count;
/// a complete Swift String is materialized only at an explicit lifecycle,
/// persistence, conflict, recovery, or diagnostic boundary.
final class EditorExactSourceBuffer {
    private var storage: NSMutableString
    private(set) var utf8ByteCount: Int

    init(source: String = "") {
        storage = NSMutableString(string: source)
        utf8ByteCount = source.utf8.count
    }

    var utf16Length: Int { storage.length }

    func snapshot() -> String {
        storage.copy() as! NSString as String
    }

    func isEqual(to source: String) -> Bool {
        storage.isEqual(to: source)
    }

    func character(atUTF16 offset: Int) -> unichar {
        storage.character(at: offset)
    }

    func replace(with source: String) {
        storage = NSMutableString(string: source)
        utf8ByteCount = source.utf8.count
    }

    func apply(
        _ deltas: [MarkdownEditorDelta],
        maximumUTF8Bytes: Int = MarkdownEditorDeltaApplier.maximumResultUTF8Bytes
    ) throws {
        let sourceLength = storage.length
        let ordered = deltas.sorted {
            if $0.fromUTF16 == $1.fromUTF16 { return $0.toUTF16 > $1.toUTF16 }
            return $0.fromUTF16 > $1.fromUTF16
        }
        var previousLowerBound = sourceLength
        var nextUTF8ByteCount = utf8ByteCount
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
            let range = NSRange(
                location: delta.fromUTF16,
                length: delta.toUTF16 - delta.fromUTF16
            )
            let removedUTF8ByteCount = storage.substring(with: range).utf8.count
            let insertedUTF8ByteCount = delta.insertion.utf8.count
            guard nextUTF8ByteCount >= removedUTF8ByteCount,
                  nextUTF8ByteCount - removedUTF8ByteCount
                    <= Int.max - insertedUTF8ByteCount else {
                throw MarkdownEditorDeltaError.oversizedResult
            }
            nextUTF8ByteCount += insertedUTF8ByteCount - removedUTF8ByteCount
            guard nextUTF8ByteCount <= maximumUTF8Bytes else {
                throw MarkdownEditorDeltaError.oversizedResult
            }
        }

        for delta in ordered {
            storage.replaceCharacters(
                in: NSRange(
                    location: delta.fromUTF16,
                    length: delta.toUTF16 - delta.fromUTF16
                ),
                with: delta.insertion
            )
        }
        utf8ByteCount = nextUTF8ByteCount
    }
}
