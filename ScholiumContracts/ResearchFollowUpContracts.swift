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
