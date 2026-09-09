import Foundation

/// Existing local records for one exact Note revision, kept separate from its
/// authored source and from any fresh Zotero item or attachment-content read.
public struct AgentNoteContext: Sendable {
    public let note: VaultQualifiedNoteID
    public let metadata: NoteMetadataSnapshot?
    public let zoteroBinding: AnalysisZoteroBinding?
    public let zoteroBindingsRevision: DocumentFingerprint?
    public let attachments: AgentAttachmentListing

    public init(note: VaultQualifiedNoteID, metadata: NoteMetadataSnapshot?, zoteroBinding: AnalysisZoteroBinding?,
                zoteroBindingsRevision: DocumentFingerprint?, attachments: AgentAttachmentListing) {
        self.note = note
        self.metadata = metadata
        self.zoteroBinding = zoteroBinding
        self.zoteroBindingsRevision = zoteroBindingsRevision
        self.attachments = attachments
    }
}
