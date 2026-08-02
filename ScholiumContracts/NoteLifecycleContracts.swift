import Foundation

/// Immutable authority captured when a researcher invokes an identity-dependent
/// mutation from a concrete Note projection. The vault-qualified location,
/// stable identity, and exact source revision travel together to the
/// Application transaction boundary so a reused path cannot retarget a stale
/// interface command.
public struct NoteLifecycleTarget: Codable, Hashable, Identifiable, Sendable {
    public let documentID: VaultQualifiedNoteID
    public let stableNoteID: UUID
    public let revision: DocumentFingerprint

    public var id: String {
        [
            documentID.vaultID.uuidString.lowercased(),
            documentID.relativePath,
            stableNoteID.uuidString.lowercased(),
        ].joined(separator: ":")
    }

    public var relativePath: String { documentID.relativePath }

    public init(
        documentID: VaultQualifiedNoteID,
        stableNoteID: UUID,
        revision: DocumentFingerprint
    ) {
        self.documentID = documentID
        self.stableNoteID = stableNoteID
        self.revision = revision
    }
}
