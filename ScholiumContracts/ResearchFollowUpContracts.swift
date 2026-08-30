import Foundation

/// The researcher-owned epistemic role of the short bridge from one completed
/// Record to a new, independently resolved Action.
public enum ResearchFollowUpKind: String, Codable, CaseIterable, Hashable, Sendable {
    case finding
    case question
    case hypothesis
}

public struct ResearchFollowUpStatement: Codable, Hashable, Sendable {
    public let kind: ResearchFollowUpKind
    public let text: String

    public init(kind: ResearchFollowUpKind, text: String) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              text.utf8.count <= 8_192,
              PortableResearchRecordValidation.hasNoDisallowedControlCharacters(text),
              !PortableResearchRecordValidation.containsAbsolutePath(text) else {
            throw ResearchContinuationContractError.invalidRequest
        }
        self.kind = kind
        self.text = text
    }
}

/// One explicit researcher confirmation for a Follow-up. The Action request
/// carries only current UI selections and expected Profile revisions; the
/// Application must resolve the current Method, Profile, note revisions,
/// permissions, materials, and write boundary again before creating the Run.
public struct ResearchFollowUpRequest: Hashable, Sendable {
    public let parentRecordID: UUID
    public let expectedFinalizedResultFingerprint: DocumentFingerprint
    public let statement: ResearchFollowUpStatement
    public let action: ResearchActionExecutionRequest
    public let methodFeedbackText: String?
    public let expectedMethodFeedbackRevision: UUID?

    public init(
        parentRecordID: UUID,
        expectedFinalizedResultFingerprint: DocumentFingerprint,
        statement: ResearchFollowUpStatement,
        action: ResearchActionExecutionRequest,
        methodFeedbackText: String?,
        expectedMethodFeedbackRevision: UUID?
    ) throws {
        let feedback = methodFeedbackText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let feedback, !feedback.isEmpty {
            _ = try ResearchMethodFeedbackDraft(text: feedback)
            self.methodFeedbackText = feedback
        } else {
            self.methodFeedbackText = nil
        }
        guard case .freeText(let request)? = action.academicInputs.values[
            "research-request"
        ], !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ResearchContinuationContractError.invalidRequest
        }
        self.parentRecordID = parentRecordID
        self.expectedFinalizedResultFingerprint = expectedFinalizedResultFingerprint
        self.statement = statement
        self.action = action
        self.expectedMethodFeedbackRevision = expectedMethodFeedbackRevision
    }
}

public struct ResearchFollowUpContext: Hashable, Sendable {
    public let parentRecordID: UUID
    public let expectedFinalizedResultFingerprint: DocumentFingerprint
    public let target: ResearchActionNoteSnapshot
    public let methodFeedbackText: String?
    public let methodFeedbackRevision: UUID?

    public init(
        parentRecordID: UUID,
        expectedFinalizedResultFingerprint: DocumentFingerprint,
        target: ResearchActionNoteSnapshot,
        methodFeedbackText: String?,
        methodFeedbackRevision: UUID?
    ) {
        self.parentRecordID = parentRecordID
        self.expectedFinalizedResultFingerprint = expectedFinalizedResultFingerprint
        self.target = target
        self.methodFeedbackText = methodFeedbackText
        self.methodFeedbackRevision = methodFeedbackRevision
    }
}

/// A Follow-up attempt that stopped after reconciling the parent Record.
///
/// The latest context lets the same sheet retain the researcher's draft while
/// advancing its optimistic Method Feedback revision. This is intentionally a
/// typed failure instead of a generic retry: the caller must not reuse the
/// superseded revision or imply that a child Run was created.
public struct ResearchFollowUpPreparationError: LocalizedError, Hashable, Sendable {
    public let latestContext: ResearchFollowUpContext
    public let methodFeedbackWasSaved: Bool
    public let reason: String

    public init(
        latestContext: ResearchFollowUpContext,
        methodFeedbackWasSaved: Bool,
        reason: String
    ) {
        self.latestContext = latestContext
        self.methodFeedbackWasSaved = methodFeedbackWasSaved
        self.reason = reason
    }

    public var errorDescription: String? {
        if methodFeedbackWasSaved {
            return "Method Feedback was saved, but the Follow-up Action was not created. The retained draft now uses the saved revision and can be tried again safely. \(reason)"
        }
        return "The Follow-up Action was not created. Method Feedback was reconciled with the current parent Record; review the retained draft before trying again. \(reason)"
    }
}

public enum ResearchFollowUpError: LocalizedError, Hashable, Sendable {
    case parentUnavailable
    case parentResultChanged
    case targetUnavailable

    public var errorDescription: String? {
        switch self {
        case .parentUnavailable:
            "The completed Research Record is no longer available for Follow-up."
        case .parentResultChanged:
            "The completed Research Result changed before this Follow-up was created."
        case .targetUnavailable:
            "The Record's target Note is no longer available for a Follow-up Action."
        }
    }
}
