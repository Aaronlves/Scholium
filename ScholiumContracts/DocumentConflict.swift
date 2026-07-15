import Foundation

public enum DocumentConflictLineKind: String, Codable, Hashable, Sendable {
    case unchanged
    case editorOnly
    case diskOnly
}

public struct DocumentConflictLine: Codable, Hashable, Sendable {
    public let kind: DocumentConflictLineKind
    public let text: String

    public init(kind: DocumentConflictLineKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// An immutable comparison between the complete editor buffer and one exact
/// disk revision. Keeping the fingerprints with the source prevents a reload
/// action from silently accepting bytes that weren't shown to the researcher.
public struct DocumentConflictSnapshot: Hashable, Sendable {
    public let relativePath: String
    public let editorSource: String
    public let diskSource: String
    public let baseRevision: DocumentFingerprint
    public let editorRevision: DocumentFingerprint
    public let diskRevision: DocumentFingerprint

    public init(
        relativePath: String,
        editorSource: String,
        diskSource: String,
        baseRevision: DocumentFingerprint
    ) {
        self.relativePath = relativePath
        self.editorSource = editorSource
        self.diskSource = diskSource
        self.baseRevision = baseRevision
        self.editorRevision = DocumentFingerprint(content: editorSource)
        self.diskRevision = DocumentFingerprint(content: diskSource)
    }

    public var comparisonLines: [DocumentConflictLine] {
        let editorLines = editorSource.components(separatedBy: .newlines)
        let diskLines = diskSource.components(separatedBy: .newlines)
        let difference = diskLines.difference(from: editorLines)

        var removals: Set<Int> = []
        var insertions: Set<Int> = []
        for change in difference {
            switch change {
            case .remove(let offset, _, _):
                removals.insert(offset)
            case .insert(let offset, _, _):
                insertions.insert(offset)
            }
        }

        var result: [DocumentConflictLine] = []
        var editorIndex = 0
        var diskIndex = 0
        while editorIndex < editorLines.count || diskIndex < diskLines.count {
            if editorIndex < editorLines.count, removals.contains(editorIndex) {
                result.append(DocumentConflictLine(
                    kind: .editorOnly,
                    text: editorLines[editorIndex]
                ))
                editorIndex += 1
                continue
            }
            if diskIndex < diskLines.count, insertions.contains(diskIndex) {
                result.append(DocumentConflictLine(
                    kind: .diskOnly,
                    text: diskLines[diskIndex]
                ))
                diskIndex += 1
                continue
            }
            if editorIndex < editorLines.count, diskIndex < diskLines.count {
                result.append(DocumentConflictLine(
                    kind: .unchanged,
                    text: editorLines[editorIndex]
                ))
                editorIndex += 1
                diskIndex += 1
                continue
            }
            if editorIndex < editorLines.count {
                result.append(DocumentConflictLine(
                    kind: .editorOnly,
                    text: editorLines[editorIndex]
                ))
                editorIndex += 1
            } else if diskIndex < diskLines.count {
                result.append(DocumentConflictLine(
                    kind: .diskOnly,
                    text: diskLines[diskIndex]
                ))
                diskIndex += 1
            }
        }
        return result
    }
}
