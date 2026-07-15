import Foundation

public struct DocumentCreationRequest: Hashable, Sendable {
    public let id: VaultQualifiedNoteID
    public let title: String
    public let researchUnitScope: String?
    public let researchUnitLimitations: [String]

    public init(
        id: VaultQualifiedNoteID,
        title: String,
        researchUnitScope: String? = nil,
        researchUnitLimitations: [String] = []
    ) {
        self.id = id
        self.title = title
        self.researchUnitScope = researchUnitScope
        self.researchUnitLimitations = researchUnitLimitations
    }
}

public enum DocumentCreationError: LocalizedError, Equatable, Sendable {
    case invalidMetadata([PropertyValidationIssue])

    public var errorDescription: String? {
        switch self {
        case .invalidMetadata(let issues):
            if issues.contains(where: {
                $0.propertyKey == "research_unit" && $0.code == .missingRequiredProperty
            }) {
                return "New Analysis notes require a Research Status scope. Enter the source material this note will represent."
            }
            return issues.map(\.message).joined(separator: "\n")
        }
    }
}
