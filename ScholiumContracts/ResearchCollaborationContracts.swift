import Foundation

/// One Triptych-wide researcher choice. It is never keyed by Skill, digest,
/// Action, Profile revision, or Agent identity.
public enum ResearchCollaborationPolicy: String, Codable, CaseIterable,
    Hashable, Sendable
{
    case askEveryTime = "ask_every_time"
    case askOnlyForWorks = "ask_only_for_works"
    case fullAccess = "full_access"
}

public struct ResearchCollaborationPolicyDocument: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let triptychID: UUID
    public let policy: ResearchCollaborationPolicy

    public init(
        triptychID: UUID,
        policy: ResearchCollaborationPolicy = .askEveryTime
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.triptychID = triptychID
        self.policy = policy
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case triptychID
        case policy
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: CollaborationCodingKey.self)
        let known = Set(CodingKeys.allCases.map(\.stringValue))
        if let unknown = raw.allKeys.map(\.stringValue).first(where: {
            !known.contains($0)
        }) {
            throw ResearchCollaborationContractError.unsupportedField(unknown)
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw ResearchCollaborationContractError.unsupportedSchemaVersion(version)
        }
        schemaVersion = version
        triptychID = try container.decode(UUID.self, forKey: .triptychID)
        policy = try container.decode(ResearchCollaborationPolicy.self, forKey: .policy)
    }
}

public struct ResearchCollaborationPolicySnapshot: Hashable, Sendable {
    public let document: ResearchCollaborationPolicyDocument
    public let revision: DocumentFingerprint

    public init(
        document: ResearchCollaborationPolicyDocument,
        revision: DocumentFingerprint
    ) {
        self.document = document
        self.revision = revision
    }
}

public enum ResearchCollaborationRequestKind: String, Codable, Hashable, Sendable {
    case initialAction = "initial_action"
    case writeSetExtension = "write_set_extension"
    case continueResearch = "continue_research"
}

public struct ResearchCollaborationRequest: Hashable, Sendable {
    public let kind: ResearchCollaborationRequestKind
    public let requestedWritableRoles: Set<ResearchActionTargetRole>
    public let explicitlyApproved: Bool

    public init(
        kind: ResearchCollaborationRequestKind,
        requestedWritableRoles: Set<ResearchActionTargetRole>,
        explicitlyApproved: Bool = false
    ) throws {
        guard kind != .writeSetExtension || !requestedWritableRoles.isEmpty else {
            throw ResearchCollaborationContractError.invalidRequest
        }
        self.kind = kind
        self.requestedWritableRoles = requestedWritableRoles
        self.explicitlyApproved = explicitlyApproved
    }
}

public enum ResearchCollaborationDisposition: String, Codable, Hashable, Sendable {
    case initialObjectAuthorized = "initial_object_authorized"
    case mayProceed = "may_proceed"
    case requiresResearcherDecision = "requires_researcher_decision"
}

public enum ResearchCollaborationPolicyResolver {
    public static func evaluate(
        policy: ResearchCollaborationPolicy,
        request: ResearchCollaborationRequest
    ) -> ResearchCollaborationDisposition {
        if request.kind == .initialAction { return .initialObjectAuthorized }
        if request.explicitlyApproved { return .mayProceed }
        switch policy {
        case .askEveryTime:
            return .requiresResearcherDecision
        case .askOnlyForWorks:
            return request.requestedWritableRoles.contains(.work)
                ? .requiresResearcherDecision
                : .mayProceed
        case .fullAccess:
            return .mayProceed
        }
    }
}

public enum ResearchCollaborationContractError: LocalizedError, Hashable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unsupportedField(String)
    case invalidRequest

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported Triptych collaboration policy schema version \(version)."
        case .unsupportedField(let field):
            "Unsupported Triptych collaboration policy field: \(field)."
        case .invalidRequest:
            "The Triptych collaboration request is invalid."
        }
    }
}

private struct CollaborationCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
