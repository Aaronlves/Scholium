import Foundation

public enum DialogueResponseModule: String, CaseIterable, Codable, Hashable, Sendable {
    case criticalReflection = "critical-reflection"
    case remainingQuestions = "remaining-questions"
    case philosophicalSignificance = "philosophical-significance"
    case debateContext = "debate-context"
    case researchDirections = "research-directions"

    public var displayName: String {
        switch self {
        case .criticalReflection: "Critical Reflection"
        case .remainingQuestions: "Remaining Questions"
        case .philosophicalSignificance: "Philosophical Significance"
        case .debateContext: "Debate Context"
        case .researchDirections: "Research Directions"
        }
    }

    public var promptQuestion: String {
        switch self {
        case .criticalReflection:
            "What important weakness, assumption, tension, counterexample, or interpretive risk remains?"
        case .remainingQuestions:
            "What directly relevant questions remain unresolved?"
        case .philosophicalSignificance:
            "Why does the result matter philosophically, and what is at stake?"
        case .debateContext:
            "How does the result bear on the relevant debate, positions, motivations, or costs?"
        case .researchDirections:
            "What bounded next investigation is warranted by an identified gap or pressure?"
        }
    }
}

public enum DialogueResponseConcision: String, CaseIterable, Codable, Hashable, Sendable {
    case concise
}

public enum DialogueCommentPreservation: String, CaseIterable, Codable, Hashable, Sendable {
    case keepAllComments = "keep-all-comments"
    case keepAcademicIntentions = "keep-academic-intentions"
    case keepOverallComment = "keep-overall-comment"

    public var displayName: String {
        switch self {
        case .keepAllComments: "Keep all Comments"
        case .keepAcademicIntentions: "Keep academic intentions"
        case .keepOverallComment: "Keep the overall Comment"
        }
    }
}

/// The mutable Triptych default used when a new Dialogue is prepared.
/// Unknown module IDs are retained for forward compatibility and surfaced by
/// validationIssues; they are never silently mapped to a known module.
public struct DialogueResponseProfile: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let academicOutcome = "academic-outcome"

    public let schemaVersion: Int
    public let profileRevision: UUID
    public let updatedAt: Date
    public let base: String
    public let modules: [String]
    public let concision: String
    public let commentPreservation: String

    public init(
        profileRevision: UUID = UUID(),
        updatedAt: Date = Date(),
        modules: [DialogueResponseModule] = [.remainingQuestions],
        concision: DialogueResponseConcision = .concise,
        commentPreservation: DialogueCommentPreservation = .keepAcademicIntentions
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.profileRevision = profileRevision
        self.updatedAt = updatedAt
        self.base = Self.academicOutcome
        self.modules = Self.unique(modules.map(\.rawValue))
        self.concision = concision.rawValue
        self.commentPreservation = commentPreservation.rawValue
    }

    public init(
        profileRevision: UUID = UUID(),
        updatedAt: Date = Date(),
        modules: [String],
        concision: String = DialogueResponseConcision.concise.rawValue,
        commentPreservation: String = DialogueCommentPreservation.keepAcademicIntentions.rawValue
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.profileRevision = profileRevision
        self.updatedAt = updatedAt
        self.base = Self.academicOutcome
        self.modules = Self.unique(modules)
        self.concision = concision
        self.commentPreservation = commentPreservation
    }

    public var knownModules: [DialogueResponseModule] {
        modules.compactMap(DialogueResponseModule.init(rawValue:))
    }

    public var unknownModuleIDs: [String] {
        modules.filter { DialogueResponseModule(rawValue: $0) == nil }
    }

    public var validationIssues: [String] {
        var issues: [String] = []
        if schemaVersion != Self.currentSchemaVersion {
            issues.append("Unsupported response profile schema version \(schemaVersion).")
        }
        if base != Self.academicOutcome {
            issues.append("The response base must be academic-outcome.")
        }
        if !DialogueResponseConcision.allCases.contains(where: { $0.rawValue == concision }) {
            issues.append("Unsupported response concision: \(concision).")
        }
        if !DialogueCommentPreservation.allCases.contains(where: { $0.rawValue == commentPreservation }) {
            issues.append("Unsupported Comment-preservation mode: \(commentPreservation).")
        }
        issues.append(contentsOf: unknownModuleIDs.map { "Unsupported response module: \($0)." })
        return issues
    }

    public func updated(
        modules: [String],
        commentPreservation: String? = nil
    ) -> Self {
        Self(
            profileRevision: UUID(),
            updatedAt: Date(),
            modules: modules,
            concision: concision,
            commentPreservation: commentPreservation ?? self.commentPreservation
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case profileRevision
        case updatedAt
        case base
        case modules
        case concision
        case commentPreservation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported response profile schema version \(schemaVersion)."
            )
        }
        self.schemaVersion = schemaVersion
        self.profileRevision = try container.decode(UUID.self, forKey: .profileRevision)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.base = try container.decode(String.self, forKey: .base)
        self.modules = Self.unique(try container.decode([String].self, forKey: .modules))
        self.concision = try container.decode(String.self, forKey: .concision)
        self.commentPreservation = try container.decode(String.self, forKey: .commentPreservation)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(profileRevision, forKey: .profileRevision)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(base, forKey: .base)
        try container.encode(modules, forKey: .modules)
        try container.encode(concision, forKey: .concision)
        try container.encode(commentPreservation, forKey: .commentPreservation)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}

/// An immutable request-time copy of the profile. It intentionally retains
/// raw strings so a future module stays visible instead of being rewritten.
public struct DialogueResponseContract: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = DialogueResponseProfile.currentSchemaVersion

    public let schemaVersion: Int
    public let profileRevision: UUID
    public let base: String
    public let modules: [String]
    public let concision: String
    public let commentPreservation: String

    public init(profile: DialogueResponseProfile) {
        self.schemaVersion = profile.schemaVersion
        self.profileRevision = profile.profileRevision
        self.base = profile.base
        self.modules = profile.modules
        self.concision = profile.concision
        self.commentPreservation = profile.commentPreservation
    }

    public var knownModules: [DialogueResponseModule] {
        modules.compactMap(DialogueResponseModule.init(rawValue:))
    }

    public var unknownModuleIDs: [String] {
        modules.filter { DialogueResponseModule(rawValue: $0) == nil }
    }

    public var validationIssues: [String] {
        var issues: [String] = []
        if schemaVersion != Self.currentSchemaVersion {
            issues.append("Unsupported response contract schema version \(schemaVersion).")
        }
        if base != DialogueResponseProfile.academicOutcome {
            issues.append("The response base must be academic-outcome.")
        }
        if !DialogueResponseConcision.allCases.contains(where: { $0.rawValue == concision }) {
            issues.append("Unsupported response concision: \(concision).")
        }
        if !DialogueCommentPreservation.allCases.contains(where: { $0.rawValue == commentPreservation }) {
            issues.append("Unsupported Comment-preservation mode: \(commentPreservation).")
        }
        issues.append(contentsOf: unknownModuleIDs.map { "Unsupported response module: \($0)." })
        return issues
    }
}

/// The bounded response contract frozen into one machine-local Discuss run.
/// Scholarly turns live only in the portable active Discussion; this value is
/// transport evidence and cannot authorize file mutation.
public struct ResearchDiscussionExecutionContract: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let responseContract: DialogueResponseContract

    public init(id: UUID, responseContract: DialogueResponseContract) throws {
        guard responseContract.validationIssues.isEmpty else {
            throw ResearchOperationError.invalidDialogueResponseContract(
                responseContract.validationIssues
            )
        }
        self.id = id
        self.responseContract = responseContract
    }
}

/// Renders the bounded locator attached to copied Dialogue instructions.
/// The locator exposes the immutable request snapshot without persisting a
/// workflow contract or presenting the snapshot as file-edit authorization.
public enum DiscussResponseTransport {
    public static func locator(
        discussionID: UUID,
        triptychID: UUID,
        contract: DialogueResponseContract
    ) -> String {
        let modules = contract.modules.isEmpty
            ? "None selected."
            : contract.modules.joined(separator: ", ")
        return """
        Scholium Discuss locator
        Discussion ID: \(discussionID.uuidString)
        Triptych selector: \(triptychID.uuidString)
        Response contract: request-snapshot
        Required base: \(contract.base)
        Optional modules: \(modules)
        Concision: \(contract.concision)
        Comment preservation: \(contract.commentPreservation)
        Retrieve the exact request and response contract with:
        scholium discuss show \(discussionID.uuidString) --triptych \(triptychID.uuidString) --format json
        Append an attributed Agent turn through the authenticated Run with:
        scholium agent discuss-reply --run <locator> --from <json|->
        Use one stable statement_id and repeat the same statement_id,
        attribution, and text after an outcome-unknown response.
        A successful reply forms the Research Record and completes the
        Discussion automatically; no separate Finish is required.
        """
    }
}
