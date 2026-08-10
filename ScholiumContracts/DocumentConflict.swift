import Foundation

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

    public func exactComparison() throws -> ExactSourceComparison {
        let editorData = Data(editorSource.utf8)
        let diskData = Data(diskSource.utf8)
        return try ExactSourceComparisonBuilder.build(
            startingData: editorData,
            endingData: diskData,
            startingRevision: editorRevision,
            endingRevision: diskRevision
        )
    }
}
