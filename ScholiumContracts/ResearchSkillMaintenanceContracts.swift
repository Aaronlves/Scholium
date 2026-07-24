import Foundation

/// One exact file in a proposed whole-package replacement. Omitted files are
/// removed by the replacement; every retained file must be present here.
public struct ResearchSkillMaintenanceFile: Codable, Hashable, Identifiable, Sendable {
    public let relativePath: String
    public let source: String
    public let revision: DocumentFingerprint

    public var id: String { relativePath }

    public init(relativePath: String, source: String) {
        self.relativePath = relativePath
        self.source = source
        self.revision = DocumentFingerprint(content: source)
    }

    private enum CodingKeys: String, CodingKey {
        case relativePath
        case source
        case revision
    }

    /// `revision` is derived evidence, not agent authority. Returned proposal
    /// JSON may omit it; when present it must describe the exact UTF-8 source.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        source = try container.decode(String.self, forKey: .source)
        let computedRevision = DocumentFingerprint(content: source)
        if let suppliedRevision = try container.decodeIfPresent(
            DocumentFingerprint.self,
            forKey: .revision
        ), suppliedRevision != computedRevision {
            throw DecodingError.dataCorruptedError(
                forKey: .revision,
                in: container,
                debugDescription: "The file revision does not match the exact UTF-8 source."
            )
        }
        revision = computedRevision
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encode(source, forKey: .source)
        try container.encode(revision, forKey: .revision)
    }
}

/// A complete candidate package, not an unbounded filesystem patch. Only the
/// entry point and one-level references/templates/evals resources are valid.
public struct ResearchSkillProposedPackage: Codable, Hashable, Sendable {
    public let files: [ResearchSkillMaintenanceFile]

    public init(files: [ResearchSkillMaintenanceFile]) {
        self.files = files.sorted { $0.relativePath < $1.relativePath }
    }

    public var entryPoint: ResearchSkillMaintenanceFile? {
        files.first { $0.relativePath == "SKILL.md" }
    }

    /// Deterministic whole-package revision used to bind external evaluation
    /// evidence before Core prepares the replacement.
    public var packageRevision: DocumentFingerprint {
        var bytes = Data()
        for file in files.sorted(by: { $0.relativePath < $1.relativePath }) {
            let data = Data(file.source.utf8)
            bytes.append(Data(file.relativePath.utf8))
            bytes.append(0)
            bytes.append(Data(String(data.count).utf8))
            bytes.append(0)
            bytes.append(data)
            bytes.append(0)
        }
        return DocumentFingerprint(data: bytes)
    }

    public func validate() throws {
        guard entryPoint != nil else {
            throw ResearchSkillMaintenanceError.missingEntryPoint
        }
        guard Set(files.map(\.relativePath)).count == files.count else {
            throw ResearchSkillMaintenanceError.duplicatePath
        }
        for file in files where !ResearchSkillMaintenancePath.isAllowed(file.relativePath) {
            throw ResearchSkillMaintenanceError.invalidResourcePath(file.relativePath)
        }
    }
}

public struct ResearchSkillMaintenanceRequest: Codable, Hashable, Sendable {
    public let packageID: String
    public let expectedPackageRevision: DocumentFingerprint
    public let proposedPackage: ResearchSkillProposedPackage
    public let instruction: String
    /// Optional externally produced semantic/adversarial evaluation evidence.
    /// Core never infers this evidence from the mere presence of eval files.
    public let evaluationEvidence: ResearchSkillMaintenanceExternalEvaluation?

    public init(
        packageID: String,
        expectedPackageRevision: DocumentFingerprint,
        proposedPackage: ResearchSkillProposedPackage,
        instruction: String,
        evaluationEvidence: ResearchSkillMaintenanceExternalEvaluation? = nil
    ) {
        self.packageID = packageID
        self.expectedPackageRevision = expectedPackageRevision
        self.proposedPackage = proposedPackage
        self.instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        self.evaluationEvidence = evaluationEvidence
    }

    public func validate() throws {
        guard packageID.range(
            of: #"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$"#,
            options: .regularExpression
        ) != nil else {
            throw ResearchSkillMaintenanceError.invalidPackageID(packageID)
        }
        guard !instruction.isEmpty else {
            throw ResearchSkillMaintenanceError.emptyInstruction
        }
        try proposedPackage.validate()
    }
}

public enum ResearchSkillMaintenanceEvaluationStatus: String, Codable, Hashable, Sendable {
    case passed
    case failed
    case incomplete
}

public struct ResearchSkillMaintenanceEvaluationCase: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let status: ResearchSkillMaintenanceEvaluationStatus
    public let summary: String

    public init(
        id: String,
        status: ResearchSkillMaintenanceEvaluationStatus,
        summary: String
    ) {
        self.id = id
        self.status = status
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Attributed evaluation supplied by an external agent or researcher-operated
/// evaluation process. Its authority is limited to the exact proposed package
/// revision recorded here.
public struct ResearchSkillMaintenanceExternalEvaluation: Codable, Hashable, Sendable {
    public let proposedPackageRevision: DocumentFingerprint
    public let evaluator: String
    public let method: String
    public let status: ResearchSkillMaintenanceEvaluationStatus
    public let cases: [ResearchSkillMaintenanceEvaluationCase]
    public let evaluatedAt: Date

    public init(
        proposedPackageRevision: DocumentFingerprint,
        evaluator: String,
        method: String,
        status: ResearchSkillMaintenanceEvaluationStatus,
        cases: [ResearchSkillMaintenanceEvaluationCase],
        evaluatedAt: Date = Date()
    ) {
        self.proposedPackageRevision = proposedPackageRevision
        self.evaluator = evaluator.trimmingCharacters(in: .whitespacesAndNewlines)
        self.method = method.trimmingCharacters(in: .whitespacesAndNewlines)
        self.status = status
        self.cases = cases
        self.evaluatedAt = evaluatedAt
    }
}

public struct ResearchSkillMaintenanceEvaluationResult: Codable, Hashable, Sendable {
    public let status: ResearchSkillMaintenanceEvaluationStatus
    public let structuralStatus: ResearchSkillMaintenanceEvaluationStatus?
    public let externalStatus: ResearchSkillMaintenanceEvaluationStatus?
    public let validationIssues: [String]
    public let cases: [ResearchSkillMaintenanceEvaluationCase]
    public let evaluator: String?
    public let method: String?
    public let proposedPackageRevision: DocumentFingerprint?
    public let evaluatedAt: Date

    public init(
        status: ResearchSkillMaintenanceEvaluationStatus,
        structuralStatus: ResearchSkillMaintenanceEvaluationStatus? = nil,
        externalStatus: ResearchSkillMaintenanceEvaluationStatus? = nil,
        validationIssues: [String] = [],
        cases: [ResearchSkillMaintenanceEvaluationCase] = [],
        evaluator: String? = nil,
        method: String? = nil,
        proposedPackageRevision: DocumentFingerprint? = nil,
        evaluatedAt: Date = Date()
    ) {
        self.status = status
        self.structuralStatus = structuralStatus ?? status
        self.externalStatus = externalStatus ?? status
        self.validationIssues = validationIssues
        self.cases = cases
        let normalizedEvaluator = evaluator?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.evaluator = normalizedEvaluator?.isEmpty == false ? normalizedEvaluator : nil
        let normalizedMethod = method?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.method = normalizedMethod?.isEmpty == false ? normalizedMethod : nil
        self.proposedPackageRevision = proposedPackageRevision
        self.evaluatedAt = evaluatedAt
    }
}

public enum ResearchSkillMaintenanceChangeKind: String, Codable, Hashable, Sendable {
    case added
    case modified
    case removed
    case unchanged
}

public struct ResearchSkillMaintenanceFileChange: Codable, Hashable, Identifiable, Sendable {
    public let relativePath: String
    public let kind: ResearchSkillMaintenanceChangeKind
    public let previousRevision: DocumentFingerprint?
    public let proposedRevision: DocumentFingerprint?

    public var id: String { relativePath }

    public init(
        relativePath: String,
        kind: ResearchSkillMaintenanceChangeKind,
        previousRevision: DocumentFingerprint?,
        proposedRevision: DocumentFingerprint?
    ) {
        self.relativePath = relativePath
        self.kind = kind
        self.previousRevision = previousRevision
        self.proposedRevision = proposedRevision
    }
}

/// Opaque, preparation-bound confirmation evidence. It grants no authority
/// beyond applying the exact evaluated package revision before expiration.
public struct ResearchSkillMaintenanceConfirmationToken: Codable, Hashable, Sendable {
    public let value: UUID
    public let preparationID: UUID
    public let packageID: String
    public let expectedPackageRevision: DocumentFingerprint
    public let proposedPackageRevision: DocumentFingerprint
    public let expiresAt: Date

    public init(
        value: UUID = UUID(),
        preparationID: UUID,
        packageID: String,
        expectedPackageRevision: DocumentFingerprint,
        proposedPackageRevision: DocumentFingerprint,
        expiresAt: Date
    ) {
        self.value = value
        self.preparationID = preparationID
        self.packageID = packageID
        self.expectedPackageRevision = expectedPackageRevision
        self.proposedPackageRevision = proposedPackageRevision
        self.expiresAt = expiresAt
    }
}

public struct ResearchSkillMaintenancePreparation: Codable, Hashable, Sendable {
    public let id: UUID
    public let request: ResearchSkillMaintenanceRequest
    public let proposedPackageRevision: DocumentFingerprint
    public let changes: [ResearchSkillMaintenanceFileChange]
    public let evaluation: ResearchSkillMaintenanceEvaluationResult
    /// Present only after every required evaluation passes. Failed or
    /// incomplete proposals remain inspectable but cannot be applied.
    public let confirmationToken: ResearchSkillMaintenanceConfirmationToken?
    public let preparedAt: Date

    public init(
        id: UUID,
        request: ResearchSkillMaintenanceRequest,
        proposedPackageRevision: DocumentFingerprint,
        changes: [ResearchSkillMaintenanceFileChange],
        evaluation: ResearchSkillMaintenanceEvaluationResult,
        confirmationToken: ResearchSkillMaintenanceConfirmationToken?,
        preparedAt: Date = Date()
    ) {
        self.id = id
        self.request = request
        self.proposedPackageRevision = proposedPackageRevision
        self.changes = changes
        self.evaluation = evaluation
        self.confirmationToken = confirmationToken
        self.preparedAt = preparedAt
    }
}

public struct ResearchSkillMaintenanceApplyOutcome: Codable, Hashable, Sendable {
    public let packageID: String
    public let previousPackageRevision: DocumentFingerprint
    public let packageRevision: DocumentFingerprint
    public let snapshotID: UUID
    public let evaluation: ResearchSkillMaintenanceEvaluationResult
    public let appliedAt: Date

    public init(
        packageID: String,
        previousPackageRevision: DocumentFingerprint,
        packageRevision: DocumentFingerprint,
        snapshotID: UUID,
        evaluation: ResearchSkillMaintenanceEvaluationResult,
        appliedAt: Date = Date()
    ) {
        self.packageID = packageID
        self.previousPackageRevision = previousPackageRevision
        self.packageRevision = packageRevision
        self.snapshotID = snapshotID
        self.evaluation = evaluation
        self.appliedAt = appliedAt
    }
}

/// Durable recovery metadata for one whole-package snapshot. The package
/// contents and storage location remain Core-private; delivery targets need
/// only this opaque identity and revision evidence to offer Restore after a
/// Settings view or application restart.
public struct ResearchSkillMaintenanceSnapshot: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let packageID: String
    public let packageRevision: DocumentFingerprint
    public let createdAt: Date
    /// Safely observed revision of a displaced package that remains under its
    /// hidden portable staging name after verified cross-volume snapshot copy.
    /// Nil means none was observed; callers must still inspect listing issues.
    public let retainedPortablePackageRevision: DocumentFingerprint?

    public init(
        id: UUID,
        packageID: String,
        packageRevision: DocumentFingerprint,
        createdAt: Date,
        retainedPortablePackageRevision: DocumentFingerprint? = nil
    ) {
        self.id = id
        self.packageID = packageID
        self.packageRevision = packageRevision
        self.createdAt = createdAt
        self.retainedPortablePackageRevision = retainedPortablePackageRevision
    }
}

/// The exact on-disk state that a restore caller observed before requesting a
/// whole-package replacement. `.present` deliberately covers both valid and
/// semantically malformed bounded packages: the fingerprint, rather than a
/// parser judgment, is the mutation authority. `.missing` is an explicit
/// absence assertion and never means "ignore the current package".
public enum ResearchSkillMaintenanceExpectedCurrentState: Codable, Hashable, Sendable {
    case present(DocumentFingerprint)
    case missing

    public var revision: DocumentFingerprint? {
        switch self {
        case .present(let revision): revision
        case .missing: nil
        }
    }
}

public enum ResearchSkillMaintenanceSnapshotIssueCode: String, Codable, Hashable, Sendable {
    case invalidEntryName
    case unsafeEntry
    case invalidManifest
    case invalidPackage
    case revisionMismatch
    case notResearcherSkill
}

/// One corrupt or unsafe entry found while enumerating durable maintenance
/// recovery. Valid snapshots remain available in the same listing.
public struct ResearchSkillMaintenanceSnapshotIssue: Codable, Hashable, Identifiable, Sendable {
    public let entryName: String
    public let snapshotID: UUID?
    public let code: ResearchSkillMaintenanceSnapshotIssueCode
    public let summary: String

    public var id: String { entryName }

    public init(
        entryName: String,
        snapshotID: UUID?,
        code: ResearchSkillMaintenanceSnapshotIssueCode,
        summary: String
    ) {
        self.entryName = entryName
        self.snapshotID = snapshotID
        self.code = code
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ResearchSkillMaintenanceSnapshotListing: Codable, Hashable, Sendable {
    public let snapshots: [ResearchSkillMaintenanceSnapshot]
    public let issues: [ResearchSkillMaintenanceSnapshotIssue]

    public init(
        snapshots: [ResearchSkillMaintenanceSnapshot],
        issues: [ResearchSkillMaintenanceSnapshotIssue] = []
    ) {
        self.snapshots = snapshots
        self.issues = issues
    }
}

public struct ResearchSkillMaintenanceRestoreOutcome: Codable, Hashable, Sendable {
    public let packageID: String
    public let replacedPackageRevision: DocumentFingerprint?
    public let restoredPackageRevision: DocumentFingerprint
    public let snapshotID: UUID
    /// A new durable snapshot of the package displaced by this restore. It is
    /// nil only when the caller explicitly proved that the package was absent.
    public let undoSnapshot: ResearchSkillMaintenanceSnapshot?
    public let restoredAt: Date

    public init(
        packageID: String,
        replacedPackageRevision: DocumentFingerprint?,
        restoredPackageRevision: DocumentFingerprint,
        snapshotID: UUID,
        undoSnapshot: ResearchSkillMaintenanceSnapshot? = nil,
        restoredAt: Date = Date()
    ) {
        self.packageID = packageID
        self.replacedPackageRevision = replacedPackageRevision
        self.restoredPackageRevision = restoredPackageRevision
        self.snapshotID = snapshotID
        self.undoSnapshot = undoSnapshot
        self.restoredAt = restoredAt
    }
}

public enum ResearchSkillMaintenancePath {
    public static func isAllowed(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard components.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".")
        }) else { return false }
        if components == ["SKILL.md"] { return true }
        guard components.count == 2,
              ["references", "templates", "evals"].contains(components[0]) else {
            return false
        }
        return components[1].range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#,
            options: .regularExpression
        ) != nil
    }
}

public enum ResearchSkillMaintenanceError: LocalizedError, Sendable {
    case invalidPackageID(String)
    case packageNotResearcherOwned(String)
    case evolutionNotEnabled(String)
    case stalePackage(String)
    case missingEntryPoint
    case duplicatePath
    case invalidResourcePath(String)
    case emptyInstruction
    case evaluationFailed
    case preparationNotFound(UUID)
    case invalidConfirmation
    case confirmationExpired
    case snapshotNotFound(UUID)
    case corruptSnapshot(UUID, ResearchSkillMaintenanceSnapshotIssueCode)
    case replacementRecoveryRequired(UUID)

    public var errorDescription: String? {
        switch self {
        case .invalidPackageID(let id):
            "Invalid Researcher Skill package identifier: \(id)"
        case .packageNotResearcherOwned(let id):
            "Only a Triptych-local Researcher Skill may evolve: \(id)"
        case .evolutionNotEnabled(let id):
            "The Researcher Skill has not opted into guided evolution: \(id)"
        case .stalePackage(let id):
            "The Researcher Skill changed after maintenance began: \(id)"
        case .missingEntryPoint:
            "A proposed Researcher Skill package must contain SKILL.md."
        case .duplicatePath:
            "A proposed Researcher Skill package contains a duplicate resource path."
        case .invalidResourcePath(let path):
            "The proposed Researcher Skill resource path is not allowed: \(path)"
        case .emptyInstruction:
            "Research Guidance maintenance requires an explicit researcher instruction."
        case .evaluationFailed:
            "The proposed Researcher Skill package did not pass its required evaluation."
        case .preparationNotFound(let id):
            "Researcher Skill maintenance preparation not found: \(id.uuidString)"
        case .invalidConfirmation:
            "The confirmation token does not match the evaluated package replacement."
        case .confirmationExpired:
            "The Researcher Skill maintenance confirmation expired. Prepare it again."
        case .snapshotNotFound(let id):
            "Researcher Skill maintenance snapshot not found: \(id.uuidString)"
        case .corruptSnapshot(let id, let code):
            "Researcher Skill maintenance snapshot \(id.uuidString) is not safe to restore (\(code.rawValue))."
        case .replacementRecoveryRequired(let snapshotID):
            "Researcher Skill replacement could not prove automatic rollback. Preserve and restore snapshot \(snapshotID.uuidString) before continuing."
        }
    }
}
