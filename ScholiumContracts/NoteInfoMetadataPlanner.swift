import Foundation

public enum NoteInfoMetadataError: Error, LocalizedError, Equatable, Sendable {
    case invalidPDFBinding

    public var errorDescription: String? {
        "The authored pdf property must be one unambiguous string path. Open Source to edit it."
    }
}

/// Reads the authored binding only. Attachment resolution and access remain
/// Application-owned; a missing or ambiguous value never authorizes a guess.
public enum PDFNoteBinding {
    public static func path(in document: NoteDocument) throws -> String? {
        guard document.frontmatterState != .malformed else {
            throw NoteInfoMetadataError.invalidPDFBinding
        }
        let projection = SearchPropertyProjection(document: document)
        guard !projection.issues.contains(.duplicateKey("pdf")) else {
            throw NoteInfoMetadataError.invalidPDFBinding
        }
        guard let entry = projection.entry(forExactKey: "pdf") else {
            if document.parsedFrontmatter["pdf"] != nil {
                throw NoteInfoMetadataError.invalidPDFBinding
            }
            return nil
        }
        if entry.valueKind == .null { return nil }
        guard entry.valueKind == .string, entry.stringMembers.count == 1,
            let member = entry.stringMembers.first, member.sourceRange != nil,
            !member.value.contains(where: { $0.isNewline || $0 == "\0" })
        else { throw NoteInfoMetadataError.invalidPDFBinding }
        return member.value.isEmpty ? nil : member.value
    }
}

public struct NoteInfoSourcePatch: Equatable, Sendable {
    public let expectedSource: String
    public let resultingSource: String
    public let fromUTF16: Int
    public let toUTF16: Int
    public let replacement: String
}

/// Uses the existing bounded YAML planner, then emits only the changed span.
/// No metadata record exists outside the exact Markdown source.
public enum NoteInfoMetadataPlanner {
    public static func plan(
        document: NoteDocument,
        edits: [String: FrontmatterEditValue]
    ) throws -> NoteInfoSourcePatch? {
        guard !edits.isEmpty else { return nil }
        let meaningfulEdits =
            document.frontmatterState == .absent
            ? edits.filter {
                if case .remove = $0.value { return false }
                return true
            }
            : edits
        guard !meaningfulEdits.isEmpty else { return nil }
        let change: NoteChangeSet =
            document.frontmatterState == .absent
            ? .insertFrontmatter(meaningfulEdits) : .frontmatter(meaningfulEdits)
        let result = try document.applying(change, timestampKey: nil)
        let before = Array(document.rawContent.utf16)
        let after = Array(result.utf16)
        guard before != after else { return nil }
        var lower = 0
        while lower < min(before.count, after.count), before[lower] == after[lower] { lower += 1 }
        while lower > 0, !boundary(lower, in: before) || !boundary(lower, in: after) { lower -= 1 }
        var oldUpper = before.count
        var newUpper = after.count
        while oldUpper > lower, newUpper > lower, before[oldUpper - 1] == after[newUpper - 1] {
            oldUpper -= 1
            newUpper -= 1
        }
        while !boundary(oldUpper, in: before) || !boundary(newUpper, in: after) {
            oldUpper += 1
            newUpper += 1
        }
        return NoteInfoSourcePatch(
            expectedSource: document.rawContent, resultingSource: result,
            fromUTF16: lower, toUTF16: oldUpper,
            replacement: String(decoding: after[lower..<newUpper], as: UTF16.self)
        )
    }

    private static func boundary(_ offset: Int, in units: [UInt16]) -> Bool {
        guard offset > 0, offset < units.count else { return true }
        return !(units[offset - 1] == 13 && units[offset] == 10)
            && !((0xD800...0xDBFF).contains(units[offset - 1])
                && (0xDC00...0xDFFF).contains(units[offset]))
    }
}
