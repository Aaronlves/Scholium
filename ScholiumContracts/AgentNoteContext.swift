import Foundation

public struct AgentNoteContext: Sendable {
    public let note: VaultQualifiedNoteID
    public let attachments: AgentAttachmentListing
    public init(note: VaultQualifiedNoteID, attachments: AgentAttachmentListing) {
        self.note = note
        self.attachments = attachments
    }
}
