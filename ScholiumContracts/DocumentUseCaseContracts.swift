import Foundation

public struct DocumentCreationRequest: Hashable, Sendable {
    public let id: VaultQualifiedNoteID
    public let title: String

    public init(
        id: VaultQualifiedNoteID,
        title: String
    ) {
        self.id = id
        self.title = title
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

public enum DocumentImportError: LocalizedError, Equatable, Sendable {
    case unsupportedSource(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSource(let path):
            "Only regular UTF-8 Markdown files can be imported: \(path)"
        }
    }
}
