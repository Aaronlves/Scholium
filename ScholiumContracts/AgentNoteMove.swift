import Foundation

/// One source effect in an immutable preview. Paths locate the stable Note; snapshots grant no write permission.
public struct AgentNoteMoveEffect: Codable, Hashable, Sendable {
    public let noteID: UUID
    public let role: VaultRole
    public let source: VaultQualifiedNoteID
    public let destination: VaultQualifiedNoteID
    public let beforeFingerprint: DocumentFingerprint
    public let afterFingerprint: DocumentFingerprint
    public let rewrittenOccurrences: Int

    public init(noteID: UUID, role: VaultRole, source: VaultQualifiedNoteID, destination: VaultQualifiedNoteID,
                beforeFingerprint: DocumentFingerprint, afterFingerprint: DocumentFingerprint, rewrittenOccurrences: Int) {
        self.noteID = noteID; self.role = role; self.source = source; self.destination = destination
        self.beforeFingerprint = beforeFingerprint; self.afterFingerprint = afterFingerprint
        self.rewrittenOccurrences = rewrittenOccurrences
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case noteID, role, source, destination, beforeFingerprint, afterFingerprint, rewrittenOccurrences
    }
    public init(from decoder: Decoder) throws {
        try requireClosedMoveFields(decoder, allowed: CodingKeys.allCases.map(\.stringValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(noteID: try c.decode(UUID.self, forKey: .noteID), role: try c.decode(VaultRole.self, forKey: .role),
            source: try c.decode(VaultQualifiedNoteID.self, forKey: .source), destination: try c.decode(VaultQualifiedNoteID.self, forKey: .destination),
            beforeFingerprint: try c.decode(DocumentFingerprint.self, forKey: .beforeFingerprint), afterFingerprint: try c.decode(DocumentFingerprint.self, forKey: .afterFingerprint),
            rewrittenOccurrences: try c.decode(Int.self, forKey: .rewrittenOccurrences))
    }
}

public struct AgentNoteMoveBlockedLink: Codable, Hashable, Sendable {
    public let noteID: UUID
    public let role: VaultRole
    public let link: IncomingLinkRewriteBlock
    public init(noteID: UUID, role: VaultRole, link: IncomingLinkRewriteBlock) {
        self.noteID = noteID; self.role = role; self.link = link
    }
}

public struct AgentNoteMovePreview: Sendable {
    public let noteID: UUID
    public let role: VaultRole
    public let source: VaultQualifiedNoteID
    public let destination: VaultQualifiedNoteID
    public let expectedFingerprint: DocumentFingerprint
    public let effects: [AgentNoteMoveEffect]
    public let blockers: [AgentNoteMoveBlockedLink]
    public let planFingerprint: DocumentFingerprint

    public init(noteID: UUID, role: VaultRole, source: VaultQualifiedNoteID, destination: VaultQualifiedNoteID,
                expectedFingerprint: DocumentFingerprint, effects: [AgentNoteMoveEffect], blockers: [AgentNoteMoveBlockedLink]) throws {
        self.noteID = noteID; self.role = role; self.source = source; self.destination = destination
        self.expectedFingerprint = expectedFingerprint
        self.effects = effects.sorted { $0.source < $1.source }
        self.blockers = blockers.sorted { $0.link.source != $1.link.source ? $0.link.source < $1.link.source : $0.link.span.utf16LowerBound < $1.link.span.utf16LowerBound }
        struct Manifest: Encodable {
            let noteID: UUID
            let source: VaultQualifiedNoteID
            let destination: VaultQualifiedNoteID
            let expectedFingerprint: DocumentFingerprint
            let effects: [AgentNoteMoveEffect]
            let blockers: [AgentNoteMoveBlockedLink]
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        planFingerprint = DocumentFingerprint(data: try encoder.encode(Manifest(noteID: noteID, source: source, destination: destination,
            expectedFingerprint: expectedFingerprint, effects: self.effects, blockers: self.blockers)))
    }
}

public struct AgentMoveLinkedSource: Codable, Hashable, Sendable {
    public let effect: AgentNoteMoveEffect
    public let beforeData: Data
    public let afterData: Data
    public init(effect: AgentNoteMoveEffect, beforeData: Data, afterData: Data) {
        self.effect = effect; self.beforeData = beforeData; self.afterData = afterData
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case effect, beforeData, afterData }
    public init(from decoder: Decoder) throws {
        try requireClosedMoveFields(decoder, allowed: CodingKeys.allCases.map(\.stringValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(effect: try c.decode(AgentNoteMoveEffect.self, forKey: .effect), beforeData: try c.decode(Data.self, forKey: .beforeData),
                  afterData: try c.decode(Data.self, forKey: .afterData))
    }
}

/// The primary source bytes retain the ordinary Agent Change fields; only linked preimages live here.
public struct AgentMoveEvidence: Codable, Hashable, Sendable {
    public static let maximumSourceByteCount = 16 * 1024 * 1024
    public static let maximumAffectedNotes = 1000
    public let primary: AgentNoteMoveEffect
    public let linkedSources: [AgentMoveLinkedSource]
    public var effects: [AgentNoteMoveEffect] { [primary] + linkedSources.map(\.effect) }
    public init(primary: AgentNoteMoveEffect, linkedSources: [AgentMoveLinkedSource]) {
        self.primary = primary; self.linkedSources = linkedSources
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case primary, linkedSources }
    public init(from decoder: Decoder) throws {
        try requireClosedMoveFields(decoder, allowed: CodingKeys.allCases.map(\.stringValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(primary: try c.decode(AgentNoteMoveEffect.self, forKey: .primary), linkedSources: try c.decode([AgentMoveLinkedSource].self, forKey: .linkedSources))
    }
}

public struct AgentMoveSourceComparison: Sendable {
    public let effect: AgentNoteMoveEffect
    public let comparison: ExactSourceComparison
    public init(effect: AgentNoteMoveEffect, comparison: ExactSourceComparison) {
        self.effect = effect; self.comparison = comparison
    }
}

public struct AgentNoteMoveResult: Sendable {
    public let change: AgentChange
    public let commit: TriptychMoveCommit
    public let derivedRefreshWarning: String?
    public init(change: AgentChange, commit: TriptychMoveCommit, derivedRefreshWarning: String?) {
        self.change = change; self.commit = commit; self.derivedRefreshWarning = derivedRefreshWarning
    }
}

private struct MoveEvidenceCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
private func requireClosedMoveFields(_ decoder: Decoder, allowed: [String]) throws {
    let values = try decoder.container(keyedBy: MoveEvidenceCodingKey.self)
    guard values.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported move evidence fields."))
    }
}
