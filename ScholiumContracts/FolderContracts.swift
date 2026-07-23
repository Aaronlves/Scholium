import Foundation

/// One stable note identity whose location changes because its containing
/// folder moved. Folder paths themselves intentionally have no identity.
public struct FolderNoteMovePlan: Hashable, Sendable {
    public let stableNoteID: UUID
    public let source: VaultQualifiedNoteID
    public let destination: VaultQualifiedNoteID
    public let expectedRevision: DocumentFingerprint

    public init(
        stableNoteID: UUID,
        source: VaultQualifiedNoteID,
        destination: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) {
        self.stableNoteID = stableNoteID
        self.source = source
        self.destination = destination
        self.expectedRevision = expectedRevision
    }
}

public struct FolderIncomingLinkRewritePlan: Hashable, Sendable {
    public let vaultID: UUID
    public let sourceFolder: VaultRelativeFolderPath
    public let destinationFolder: VaultRelativeFolderPath
    public let graphGeneration: Int
    public let noteMoves: [FolderNoteMovePlan]
    public let rewrites: [IncomingLinkRewrite]
    public let blockedIncomingLinks: [IncomingLinkRewriteBlock]

    public init(
        vaultID: UUID,
        sourceFolder: VaultRelativeFolderPath,
        destinationFolder: VaultRelativeFolderPath,
        graphGeneration: Int,
        noteMoves: [FolderNoteMovePlan],
        rewrites: [IncomingLinkRewrite],
        blockedIncomingLinks: [IncomingLinkRewriteBlock] = []
    ) {
        self.vaultID = vaultID
        self.sourceFolder = sourceFolder
        self.destinationFolder = destinationFolder
        self.graphGeneration = graphGeneration
        self.noteMoves = noteMoves
        self.rewrites = rewrites
        self.blockedIncomingLinks = blockedIncomingLinks
    }
}

public struct FolderNoteMoveCommit: Hashable, Sendable {
    public let stableNoteID: UUID
    public let source: VaultQualifiedNoteID
    public let destination: VaultQualifiedNoteID
    public let previousRevision: DocumentFingerprint
    public let committedRevision: DocumentFingerprint

    public init(
        stableNoteID: UUID,
        source: VaultQualifiedNoteID,
        destination: VaultQualifiedNoteID,
        previousRevision: DocumentFingerprint,
        committedRevision: DocumentFingerprint
    ) {
        self.stableNoteID = stableNoteID
        self.source = source
        self.destination = destination
        self.previousRevision = previousRevision
        self.committedRevision = committedRevision
    }
}

public struct FolderMoveCommit: Hashable, Sendable {
    public let vaultID: UUID
    public let sourceFolder: VaultRelativeFolderPath
    public let destinationFolder: VaultRelativeFolderPath
    public let graphGeneration: Int
    public let noteMoves: [FolderNoteMoveCommit]
    public let rewrites: [CoordinatedIncomingLinkRewriteResult]

    public init(
        vaultID: UUID,
        sourceFolder: VaultRelativeFolderPath,
        destinationFolder: VaultRelativeFolderPath,
        graphGeneration: Int,
        noteMoves: [FolderNoteMoveCommit],
        rewrites: [CoordinatedIncomingLinkRewriteResult]
    ) {
        self.vaultID = vaultID
        self.sourceFolder = sourceFolder
        self.destinationFolder = destinationFolder
        self.graphGeneration = graphGeneration
        self.noteMoves = noteMoves
        self.rewrites = rewrites
    }
}
