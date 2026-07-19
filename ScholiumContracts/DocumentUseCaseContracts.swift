import Foundation

public enum AnalysisResearchStatusChoice: Hashable, Sendable {
    case declareNow(scope: String, limitations: [String])
    case notYet
}

public struct DocumentCreationRequest: Hashable, Sendable {
    public let id: VaultQualifiedNoteID
    public let title: String
    public let analysisResearchStatus: AnalysisResearchStatusChoice

    public var researchUnitScope: String? {
        guard case .declareNow(let scope, _) = analysisResearchStatus else {
            return nil
        }
        return scope
    }

    public var researchUnitLimitations: [String] {
        guard case .declareNow(_, let limitations) = analysisResearchStatus else {
            return []
        }
        return limitations
    }

    public init(
        id: VaultQualifiedNoteID,
        title: String,
        analysisResearchStatus: AnalysisResearchStatusChoice = .notYet
    ) {
        self.id = id
        self.title = title
        self.analysisResearchStatus = analysisResearchStatus
    }

}

public enum DocumentCreationError: LocalizedError, Equatable, Sendable {
    case invalidMetadata([PropertyValidationIssue])

    public var errorDescription: String? {
        switch self {
        case .invalidMetadata(let issues):
            return issues.map(\.message).joined(separator: "\n")
        }
    }
}
