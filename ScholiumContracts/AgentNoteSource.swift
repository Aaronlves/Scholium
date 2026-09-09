import Foundation

/// One exact current source read bound to a stable Note identity by the
/// Application owner. The source bytes are transient and never become a
/// second writable authority.
public struct AgentNoteSource: Sendable {
    public let note: VaultQualifiedNoteID
    public let role: VaultRole
    public let fingerprint: DocumentFingerprint
    public let source: Data

    public init(
        note: VaultQualifiedNoteID,
        role: VaultRole,
        fingerprint: DocumentFingerprint,
        source: Data
    ) {
        self.note = note
        self.role = role
        self.fingerprint = fingerprint
        self.source = source
    }
}
