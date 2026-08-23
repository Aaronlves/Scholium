import Foundation

/// Delivery-neutral structured recovery code surfaced by an Agent command.
/// The CLI consumes this narrow contract without importing an Application
/// transport implementation or reconstructing its error taxonomy.
public protocol AgentCommandErrorCodeProviding: Error {
    var agentCommandErrorCode: String { get }
    var agentCommandRecovery: AgentOperationRecovery? { get }
}

public extension AgentCommandErrorCodeProviding {
    var agentCommandRecovery: AgentOperationRecovery? { nil }
}

/// One machine-actionable recovery instruction for an Agent-facing result.
/// The boolean fields make retry safety explicit instead of relying on prose.
public struct AgentOperationRecovery: Codable, Hashable, Sendable {
    public let safeToRetry: Bool
    public let mustReuseRequestIdentity: Bool
    public let nextStep: AgentRecoveryNextStep
    public let creationBranches: [AgentCreationRecoveryBranch]

    public init(
        safeToRetry: Bool,
        mustReuseRequestIdentity: Bool,
        nextStep: AgentRecoveryNextStep,
        creationBranches: [AgentCreationRecoveryBranch] = []
    ) {
        self.safeToRetry = safeToRetry
        self.mustReuseRequestIdentity = mustReuseRequestIdentity
        self.nextStep = nextStep
        self.creationBranches = creationBranches
    }

    private enum CodingKeys: String, CodingKey {
        case safeToRetry = "safe_to_retry"
        case mustReuseRequestIdentity = "must_reuse_request_identity"
        case nextStep = "next_step"
        case creationBranches = "creation_branches"
    }
}

public enum AgentRecoveryNextStep: String, Codable, Hashable, Sendable {
    case startWithReturnedTemplate = "start_with_returned_template"
    case requestResearcherDistinctFilenameAndPreflight = "request_researcher_distinct_filename_and_preflight"
    case startExistingAnalysis = "start_existing_analysis"
    case requestResearcherRecoveryChoice = "request_researcher_recovery_choice"
    case resolveSourceAccess = "resolve_source_access"
    case rerunCreationPreflight = "rerun_creation_preflight"
    case retryExactRequest = "retry_exact_request"
    case inspectOriginalRequestState = "inspect_original_request_state"
    case copyNewHandoffAndPairSameRun = "copy_new_handoff_and_pair_same_run"
    case startNewActionFromCurrentRevision = "start_new_action_from_current_revision"
    case correctRequest = "correct_request"
    case stopAndReport = "stop_and_report"
}

/// The only branches exposed when a portable identity remains but its source
/// is absent. Neither branch is selected by Scholium or an Agent.
public enum AgentCreationRecoveryBranchKind: String, Codable, Hashable, Sendable {
    case restoreOriginalSource = "restore_original_source"
    case explicitlyCreateAtDistinctDestination = "explicitly_create_at_distinct_destination"
}

/// One researcher-controlled branch after a retained portable identity loses
/// its source. Identity reuse is branch-specific: restoring request-owned work
/// resumes the original identity, while distinct creation never does.
public struct AgentCreationRecoveryBranch: Codable, Hashable, Sendable {
    public let kind: AgentCreationRecoveryBranchKind
    public let mustReuseRequestIdentity: Bool
    public let nextStep: AgentRecoveryNextStep

    public init(
        kind: AgentCreationRecoveryBranchKind,
        mustReuseRequestIdentity: Bool,
        nextStep: AgentRecoveryNextStep
    ) {
        self.kind = kind
        self.mustReuseRequestIdentity = mustReuseRequestIdentity
        self.nextStep = nextStep
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case mustReuseRequestIdentity = "must_reuse_request_identity"
        case nextStep = "next_step"
    }
}

public enum AgentCommandActionKind: String, Codable, Hashable, Sendable {
    case inspect
    case reply
    case promote
    case selectResources = "select_resources"
    case submitResult = "submit_result"
    case finish
    case cancel
}

/// A delivery-neutral, shell-safe next step. `command` is an argument vector,
/// never a shell-interpolated command string. `inputTemplate` is illustrative
/// JSON and may intentionally contain non-decodable replacement markers.
public struct AgentCommandAction: Codable, Hashable, Sendable {
    public let kind: AgentCommandActionKind
    public let label: String
    public let command: [String]
    public let inputTemplate: String?

    public init(
        kind: AgentCommandActionKind,
        label: String,
        command: [String],
        inputTemplate: String? = nil
    ) {
        self.kind = kind
        self.label = label
        self.command = command
        self.inputTemplate = inputTemplate
    }
}
