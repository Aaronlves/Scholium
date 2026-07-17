import Foundation

/// An Analysis-only, immutable source target for bibliography screening.
public struct RecommendedBibliographyTarget: Codable, Hashable, Sendable {
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let fingerprint: DocumentFingerprint
    public let title: String

    public init(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        fingerprint: DocumentFingerprint,
        title: String
    ) {
        self.noteID = noteID
        self.note = note
        self.fingerprint = fingerprint
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func validate() throws {
        guard !title.isEmpty else {
            throw RecommendedBibliographyError.invalidTarget("The Analysis title is empty.")
        }
    }
}

public enum BibliographyRecommendationGoal: String, Codable, CaseIterable, Hashable, Sendable {
    case backgroundReading = "background_reading"
    case corePositions = "core_positions"
    case historicalPredecessors = "historical_predecessors"
    case objections
    case replies
    case companionLiterature = "companion_literature"
    case alternativeApproaches = "alternative_approaches"
    case missingCitations = "missing_citations"
    case recentDevelopments = "recent_developments"
    case classicWorks = "classic_works"
}

public struct RecommendedBibliographyRequest: Codable, Hashable, Sendable {
    public let target: RecommendedBibliographyTarget
    public let goals: [BibliographyRecommendationGoal]
    public let purpose: String?

    public init(
        target: RecommendedBibliographyTarget,
        goals: [BibliographyRecommendationGoal] = [],
        purpose: String? = nil
    ) {
        self.target = target
        let unique = Set(goals)
        self.goals = BibliographyRecommendationGoal.allCases.filter(unique.contains)
        let normalized = purpose?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.purpose = normalized?.isEmpty == false ? normalized : nil
    }

    public func validate() throws {
        try target.validate()
    }
}

public enum RecommendedBibliographyRunState: String, Codable, Hashable, Sendable {
    case prepared
    case complete
    case stale
    case cancelled
}

/// One exact method resource captured at preparation time. The source is kept
/// with the request so an agent can execute the prepared method even after the
/// installed package changes.
public struct RecommendedBibliographyMethodResourceSnapshot: Codable, Hashable, Sendable {
    public let relativePath: String
    public let revision: DocumentFingerprint
    public let source: String

    public init(relativePath: String, revision: DocumentFingerprint, source: String) {
        self.relativePath = relativePath
        self.revision = revision
        self.source = source
    }
}

public struct RecommendedBibliographyMethodSnapshot: Codable, Hashable, Sendable {
    public let packageID: String
    public let origin: ResearchSkillOrigin
    public let version: String
    public let packageRevision: DocumentFingerprint
    public let loadedResources: [ResearchFunctionResourceSnapshot]
    public let renderedResources: [RecommendedBibliographyMethodResourceSnapshot]

    public init(
        packageID: String,
        origin: ResearchSkillOrigin,
        version: String,
        packageRevision: DocumentFingerprint,
        loadedResources: [ResearchFunctionResourceSnapshot],
        renderedResources: [RecommendedBibliographyMethodResourceSnapshot] = []
    ) {
        self.packageID = packageID
        self.origin = origin
        self.version = version
        self.packageRevision = packageRevision
        self.loadedResources = loadedResources.sorted { $0.relativePath < $1.relativePath }
        self.renderedResources = renderedResources.sorted { $0.relativePath < $1.relativePath }
    }

    private enum CodingKeys: String, CodingKey {
        case packageID
        case origin
        case version
        case packageRevision
        case loadedResources
        case renderedResources
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            packageID: try container.decode(String.self, forKey: .packageID),
            origin: try container.decode(ResearchSkillOrigin.self, forKey: .origin),
            version: try container.decode(String.self, forKey: .version),
            packageRevision: try container.decode(DocumentFingerprint.self, forKey: .packageRevision),
            loadedResources: try container.decode(
                [ResearchFunctionResourceSnapshot].self,
                forKey: .loadedResources
            ),
            renderedResources: try container.decodeIfPresent(
                [RecommendedBibliographyMethodResourceSnapshot].self,
                forKey: .renderedResources
            ) ?? []
        )
    }
}

public struct RecommendedBibliographyPreparation: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let confirmationToken: UUID
    public let request: RecommendedBibliographyRequest
    public let method: RecommendedBibliographyMethodSnapshot
    public let instructions: String
    public let preparedAt: Date
    public let state: RecommendedBibliographyRunState
    public let nextActions: [AgentCommandAction]?

    public init(
        id: UUID = UUID(),
        confirmationToken: UUID = UUID(),
        request: RecommendedBibliographyRequest,
        method: RecommendedBibliographyMethodSnapshot,
        instructions: String,
        preparedAt: Date = Date(),
        state: RecommendedBibliographyRunState = .prepared,
        nextActions: [AgentCommandAction] = []
    ) {
        self.id = id
        self.confirmationToken = confirmationToken
        self.request = request
        self.method = method
        self.instructions = instructions
        self.preparedAt = preparedAt
        self.state = state
        self.nextActions = nextActions.isEmpty ? nil : nextActions
    }
}

public struct BibliographyCandidateIdentity: Codable, Hashable, Sendable {
    public let rawCitation: String
    public let title: String?
    public let authors: [String]
    public let year: Int?
    public let doi: String?
    public let isbn: String?
    public let citationKey: String?
    public let zoteroItemKey: String?
    public let isChapter: Bool?
    public let containerTitle: String?
    public let editors: [String]
    public let edition: String?
    public let translators: [String]

    public init(
        rawCitation: String,
        title: String? = nil,
        authors: [String] = [],
        year: Int? = nil,
        doi: String? = nil,
        isbn: String? = nil,
        citationKey: String? = nil,
        zoteroItemKey: String? = nil,
        isChapter: Bool? = nil,
        containerTitle: String? = nil,
        editors: [String] = [],
        edition: String? = nil,
        translators: [String] = []
    ) {
        self.rawCitation = rawCitation.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = Self.normalized(title)
        self.authors = authors.compactMap(Self.normalized)
        self.year = year
        self.doi = Self.normalized(doi)
        self.isbn = Self.normalized(isbn)
        self.citationKey = Self.normalized(citationKey)
        self.zoteroItemKey = Self.normalized(zoteroItemKey)
        self.isChapter = isChapter
        self.containerTitle = Self.normalized(containerTitle)
        self.editors = editors.compactMap(Self.normalized)
        self.edition = Self.normalized(edition)
        self.translators = translators.compactMap(Self.normalized)
    }

    private enum CodingKeys: String, CodingKey {
        case rawCitation
        case title
        case authors
        case year
        case doi
        case isbn
        case citationKey
        case zoteroItemKey
        case isChapter
        case containerTitle
        case editors
        case edition
        case translators
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rawCitation: try container.decode(String.self, forKey: .rawCitation),
            title: try container.decodeIfPresent(String.self, forKey: .title),
            authors: try container.decodeIfPresent([String].self, forKey: .authors) ?? [],
            year: try container.decodeIfPresent(Int.self, forKey: .year),
            doi: try container.decodeIfPresent(String.self, forKey: .doi),
            isbn: try container.decodeIfPresent(String.self, forKey: .isbn),
            citationKey: try container.decodeIfPresent(String.self, forKey: .citationKey),
            zoteroItemKey: try container.decodeIfPresent(String.self, forKey: .zoteroItemKey),
            isChapter: try container.decodeIfPresent(Bool.self, forKey: .isChapter),
            containerTitle: try container.decodeIfPresent(String.self, forKey: .containerTitle),
            editors: try container.decodeIfPresent([String].self, forKey: .editors) ?? [],
            edition: try container.decodeIfPresent(String.self, forKey: .edition),
            translators: try container.decodeIfPresent([String].self, forKey: .translators) ?? []
        )
    }

    private static func normalized(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}

public enum BibliographyDiscussionStatus: String, Codable, Hashable, Sendable {
    case referenceListOnly = "reference_list_only"
    case citedInText = "cited_in_text"
    case substantivelyDiscussed = "substantively_discussed"
}

public enum BibliographyAuthorialFraming: String, Codable, Hashable, Sendable {
    case central
    case praised
    case criticized
    case neutral
    case unclear
}

public struct BibliographyRecommendationEvidence: Codable, Hashable, Sendable {
    public let discussionStatus: BibliographyDiscussionStatus
    public let sourceLocators: [String]
    public let authorialFraming: BibliographyAuthorialFraming?
    public let metadataVerified: Bool
    public let sourceInspected: Bool
    public let verificationProvenance: String?

    public init(
        discussionStatus: BibliographyDiscussionStatus,
        sourceLocators: [String] = [],
        authorialFraming: BibliographyAuthorialFraming? = nil,
        metadataVerified: Bool = false,
        sourceInspected: Bool = false,
        verificationProvenance: String? = nil
    ) {
        self.discussionStatus = discussionStatus
        self.sourceLocators = sourceLocators.compactMap {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        self.authorialFraming = authorialFraming
        self.metadataVerified = metadataVerified
        self.sourceInspected = sourceInspected
        let provenance = verificationProvenance?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.verificationProvenance = provenance?.isEmpty == false ? provenance : nil
    }
}

public enum BibliographyMatchState: String, Codable, Hashable, Sendable {
    case unmatched
    case matchedZotero = "matched_zotero"
    case matchedAnalysis = "matched_analysis"
    case duplicate
    case ambiguous
}

public struct RecommendedBibliographyCandidate: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let identity: BibliographyCandidateIdentity
    public let goals: [BibliographyRecommendationGoal]
    public let reason: String
    public let possibleUse: String?
    public let uncertainty: String?
    public let evidence: BibliographyRecommendationEvidence
    public let requiredNextCheck: String
    /// Derived by Scholium. Agent submissions are normalized back to
    /// `unmatched` before deterministic matching.
    public let matchState: BibliographyMatchState
    public let matchedAnalysis: VaultQualifiedNoteID?
    public let matchedZoteroItemKey: String?
    public let duplicateOfCandidateID: UUID?
    public let isDismissed: Bool

    public init(
        id: UUID = UUID(),
        identity: BibliographyCandidateIdentity,
        goals: [BibliographyRecommendationGoal] = [],
        reason: String,
        possibleUse: String? = nil,
        uncertainty: String? = nil,
        evidence: BibliographyRecommendationEvidence,
        requiredNextCheck: String,
        matchState: BibliographyMatchState = .unmatched,
        matchedAnalysis: VaultQualifiedNoteID? = nil,
        matchedZoteroItemKey: String? = nil,
        duplicateOfCandidateID: UUID? = nil,
        isDismissed: Bool = false
    ) {
        self.id = id
        self.identity = identity
        let uniqueGoals = Set(goals)
        self.goals = BibliographyRecommendationGoal.allCases.filter(uniqueGoals.contains)
        self.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        self.possibleUse = Self.normalized(possibleUse)
        self.uncertainty = Self.normalized(uncertainty)
        self.evidence = evidence
        self.requiredNextCheck = requiredNextCheck.trimmingCharacters(in: .whitespacesAndNewlines)
        self.matchState = matchState
        self.matchedAnalysis = matchedAnalysis
        self.matchedZoteroItemKey = Self.normalized(matchedZoteroItemKey)
        self.duplicateOfCandidateID = duplicateOfCandidateID
        self.isDismissed = isDismissed
    }

    public func validatedForSubmission() throws -> Self {
        guard !identity.rawCitation.isEmpty else {
            throw RecommendedBibliographyError.invalidCandidate("A raw citation is required.")
        }
        guard !reason.isEmpty else {
            throw RecommendedBibliographyError.invalidCandidate("A recommendation reason is required.")
        }
        guard !requiredNextCheck.isEmpty else {
            throw RecommendedBibliographyError.invalidCandidate("A required next check is required.")
        }
        guard matchState == .unmatched,
              matchedAnalysis == nil,
              matchedZoteroItemKey == nil,
              duplicateOfCandidateID == nil,
              !isDismissed else {
            throw RecommendedBibliographyError.invalidCandidate(
                "Matching and dismissal state is owned by Scholium."
            )
        }
        return self
    }

    public func deriving(
        matchState: BibliographyMatchState,
        matchedAnalysis: VaultQualifiedNoteID? = nil,
        matchedZoteroItemKey: String? = nil,
        duplicateOfCandidateID: UUID? = nil,
        isDismissed: Bool? = nil
    ) -> Self {
        Self(
            id: id,
            identity: identity,
            goals: goals,
            reason: reason,
            possibleUse: possibleUse,
            uncertainty: uncertainty,
            evidence: evidence,
            requiredNextCheck: requiredNextCheck,
            matchState: matchState,
            matchedAnalysis: matchedAnalysis,
            matchedZoteroItemKey: matchedZoteroItemKey,
            duplicateOfCandidateID: duplicateOfCandidateID,
            isDismissed: isDismissed ?? self.isDismissed
        )
    }

    private static func normalized(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}

public struct RecommendedBibliographyCompletionSubmission: Codable, Hashable, Sendable {
    public let requestID: UUID
    public let confirmationToken: UUID
    public let targetFingerprint: DocumentFingerprint
    public let sourceScope: String
    public let candidates: [RecommendedBibliographyCandidate]

    public init(
        requestID: UUID,
        confirmationToken: UUID,
        targetFingerprint: DocumentFingerprint,
        sourceScope: String,
        candidates: [RecommendedBibliographyCandidate]
    ) {
        self.requestID = requestID
        self.confirmationToken = confirmationToken
        self.targetFingerprint = targetFingerprint
        self.sourceScope = sourceScope.trimmingCharacters(in: .whitespacesAndNewlines)
        self.candidates = candidates
    }

    public func validate() throws {
        guard !sourceScope.isEmpty else {
            throw RecommendedBibliographyError.invalidCompletion("The inspected source scope is required.")
        }
        guard Set(candidates.map(\.id)).count == candidates.count else {
            throw RecommendedBibliographyError.invalidCompletion("Candidate identifiers must be unique.")
        }
        for candidate in candidates { _ = try candidate.validatedForSubmission() }
    }
}

public struct RecommendedBibliographyProjection: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let request: RecommendedBibliographyRequest
    public let method: RecommendedBibliographyMethodSnapshot
    public let state: RecommendedBibliographyRunState
    public let sourceScope: String?
    public let candidates: [RecommendedBibliographyCandidate]
    public let preparedAt: Date
    public let completedAt: Date?

    public init(
        id: UUID,
        request: RecommendedBibliographyRequest,
        method: RecommendedBibliographyMethodSnapshot,
        state: RecommendedBibliographyRunState,
        sourceScope: String? = nil,
        candidates: [RecommendedBibliographyCandidate] = [],
        preparedAt: Date,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.request = request
        self.method = method
        self.state = state
        self.sourceScope = sourceScope
        self.candidates = candidates
        self.preparedAt = preparedAt
        self.completedAt = completedAt
    }
}

/// The durable state needed by one Analysis inspector. A completed or stale
/// result and a newer prepared request are intentionally represented
/// separately so refreshing never hides prior reading leads.
public struct RecommendedBibliographyOverview: Codable, Hashable, Sendable {
    public let result: RecommendedBibliographyProjection?
    public let activePreparation: RecommendedBibliographyPreparation?
    public let latestRun: RecommendedBibliographyProjection?

    public init(
        result: RecommendedBibliographyProjection? = nil,
        activePreparation: RecommendedBibliographyPreparation? = nil,
        latestRun: RecommendedBibliographyProjection? = nil
    ) {
        self.result = result
        self.activePreparation = activePreparation
        self.latestRun = latestRun
    }
}

public struct RecommendedBibliographyMethodCandidate: Codable, Hashable, Identifiable, Sendable {
    public let packageID: String
    public let name: String
    public let version: String
    public var id: String { packageID }

    public init(packageID: String, name: String, version: String) {
        self.packageID = packageID
        self.name = name
        self.version = version
    }
}

public enum RecommendedBibliographyMethodIssue: String, Codable, Hashable, Sendable {
    case malformedBinding = "malformed_binding"
    case invalidPackage = "invalid_package"
    case missingCapability = "missing_capability"
}

public struct RecommendedBibliographyMethodStatus: Codable, Hashable, Sendable {
    public let activePackageID: String?
    public let usesBundledDefault: Bool
    public let candidates: [RecommendedBibliographyMethodCandidate]
    public let bindingRevision: DocumentFingerprint?
    public let issue: RecommendedBibliographyMethodIssue?

    public init(
        activePackageID: String? = nil,
        usesBundledDefault: Bool,
        candidates: [RecommendedBibliographyMethodCandidate] = [],
        bindingRevision: DocumentFingerprint? = nil,
        issue: RecommendedBibliographyMethodIssue? = nil
    ) {
        self.activePackageID = activePackageID
        self.usesBundledDefault = usesBundledDefault
        self.candidates = candidates.sorted { $0.name < $1.name }
        self.bindingRevision = bindingRevision
        self.issue = issue
    }
}

public protocol RecommendedBibliographyUseCases: Sendable {
    func recommendationOverview(
        for target: RecommendedBibliographyTarget
    ) async throws -> RecommendedBibliographyOverview

    func recommendations(
        for target: RecommendedBibliographyTarget
    ) async throws -> RecommendedBibliographyProjection?

    func prepareRecommendation(
        _ request: RecommendedBibliographyRequest
    ) async throws -> RecommendedBibliographyPreparation

    func recommendationRequest(
        id: UUID
    ) async throws -> RecommendedBibliographyPreparation

    func completeRecommendation(
        _ submission: RecommendedBibliographyCompletionSubmission
    ) async throws -> RecommendedBibliographyProjection

    func cancelRecommendation(id: UUID) async throws
    func dismissRecommendation(requestID: UUID, candidateID: UUID) async throws

    func bibliographyMethodStatus() async throws -> RecommendedBibliographyMethodStatus
    func setBibliographyMethod(
        packageID: String?,
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> RecommendedBibliographyMethodStatus
}

public enum RecommendedBibliographyError: LocalizedError, Sendable {
    case invalidTarget(String)
    case invalidCandidate(String)
    case invalidCompletion(String)
    case analysisTargetRequired
    case requestNotFound(UUID)
    case candidateNotFound(UUID)
    case activeRequestExists(UUID)
    case confirmationMismatch
    case targetChanged
    case methodChanged
    case methodRequiresRepair
    case alreadyCompleted(UUID)
    case cancelled(UUID)
    case storeUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTarget(let message), .invalidCandidate(let message),
             .invalidCompletion(let message), .storeUnavailable(let message):
            message
        case .analysisTargetRequired:
            "Recommended Bibliography is available only for an Analysis."
        case .requestNotFound(let id):
            "Recommended Bibliography request was not found: \(id.uuidString)"
        case .candidateNotFound(let id):
            "Recommended Bibliography candidate was not found: \(id.uuidString)"
        case .activeRequestExists(let id):
            "Recommended Bibliography request is already awaiting completion: \(id.uuidString)"
        case .confirmationMismatch:
            "The Recommended Bibliography confirmation token does not match."
        case .targetChanged:
            "The Analysis changed after this recommendation request was prepared."
        case .methodChanged:
            "The selected bibliography method changed after preparation."
        case .methodRequiresRepair:
            "The configured bibliography method requires repair in Research Guidance."
        case .alreadyCompleted(let id):
            "Recommended Bibliography request is already complete: \(id.uuidString)"
        case .cancelled(let id):
            "Recommended Bibliography request was cancelled: \(id.uuidString)"
        }
    }
}
