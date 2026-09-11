import Foundation

/// Derived locations in one fingerprint-bound complete source, never durable block identities.
public struct AgentSourceEdit: Hashable, Sendable {
    public static let maximumCount = 100
    public let startUTF8: Int
    public let endUTF8: Int
    public let expectedText: String
    public let replacement: String

    public init(startUTF8: Int, endUTF8: Int, expectedText: String, replacement: String) {
        self.startUTF8 = startUTF8
        self.endUTF8 = endUTF8
        self.expectedText = expectedText
        self.replacement = replacement
    }

    public static func applying(_ edits: [Self], to source: Data) throws -> String {
        guard (1...maximumCount).contains(edits.count),
            source.count <= ScholiumMCPContract.maximumDocumentUTF8ByteCount,
            String(data: source, encoding: .utf8) != nil
        else {
            throw AgentCollaborationError.invalidRequest("Supply 1–100 edits against bounded UTF-8 source.")
        }
        let bytes = Array(source)
        let ordered = edits.sorted { $0.startUTF8 < $1.startUTF8 }
        var previous: Self?
        var output = Data()
        var cursor = 0
        for edit in ordered {
            guard edit.startUTF8 >= 0, edit.endUTF8 >= edit.startUTF8, edit.endUTF8 <= bytes.count,
                previous.map({ edit.startUTF8 >= $0.endUTF8 && edit.startUTF8 != $0.startUTF8 }) ?? true,
                isBoundary(edit.startUTF8, in: bytes), isBoundary(edit.endUTF8, in: bytes)
            else {
                throw AgentCollaborationError.invalidRequest("Edit ranges must be distinct, nonoverlapping UTF-8 scalar boundaries in the original source.")
            }
            guard bytes[edit.startUTF8..<edit.endUTF8].elementsEqual(edit.expectedText.utf8) else {
                throw AgentCollaborationError.invalidRequest(
                    "The exact expected text does not match its source range. Read the current source; do not relocate by similarity.")
            }
            guard edit.replacement.utf8.count <= ScholiumMCPContract.maximumDocumentUTF8ByteCount,
                !edit.replacement.unicodeScalars.contains(where: { $0.value == 0 })
            else {
                throw AgentCollaborationError.invalidRequest("The replacement is invalid or exceeds the UTF-8 size limit.")
            }
            output.append(contentsOf: bytes[cursor..<edit.startUTF8])
            output.append(contentsOf: edit.replacement.utf8)
            guard output.count <= ScholiumMCPContract.maximumDocumentUTF8ByteCount else {
                throw AgentCollaborationError.invalidRequest("The edited source exceeds the UTF-8 size limit.")
            }
            cursor = edit.endUTF8
            previous = edit
        }
        output.append(contentsOf: bytes[cursor...])
        guard output.count <= ScholiumMCPContract.maximumDocumentUTF8ByteCount,
            let result = NoteDocument.decodeUTF8PreservingBOM(output)
        else {
            throw AgentCollaborationError.invalidRequest("The edited source exceeds the UTF-8 size limit or is invalid UTF-8.")
        }
        return result
    }

    private static func isBoundary(_ offset: Int, in bytes: [UInt8]) -> Bool {
        offset == bytes.count || bytes[offset] & 0xC0 != 0x80
    }
}
