import Foundation

/// Describes the research layer represented by an indexed note.
///
/// The value is descriptive search metadata. It never establishes evidential
/// sufficiency, philosophical support, or permission to use the note.
public enum EvidentialLayer: String, Codable, CaseIterable, Sendable {
    case primarySource = "primary_source"
    case paperAnalysis = "paper_analysis"
    case topicNote = "topic_note"
    case draftProse = "draft_prose"
    case researchRecord = "research_record"
    case researcherState = "researcher_state"
    case sourceMaterial = "source_material"
    case agentReconstruction = "agent_reconstruction"
}

/// A vault-qualified reference used by catalog, Attention, and navigation.
///
/// This is an identity and routing value, not an evidence assertion.
/// `stableNoteID` is optional because malformed or externally changed notes
/// may not yet have a reconciled portable identity.
public struct VaultNoteReference: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(vaultID.uuidString):\(relativePath)" }
    public let vaultID: UUID
    public let vaultName: String
    public let vaultRole: VaultRole
    public let relativePath: String
    public let stableNoteID: String?

    public init(
        vaultID: UUID,
        vaultName: String,
        vaultRole: VaultRole,
        relativePath: String,
        stableNoteID: String? = nil
    ) {
        self.vaultID = vaultID
        self.vaultName = vaultName
        self.vaultRole = vaultRole
        self.relativePath = relativePath
        self.stableNoteID = stableNoteID
    }
}
