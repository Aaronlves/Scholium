import Foundation

public struct SourceLocator: Codable, Hashable, Sendable {
    public let file: String
    public let line: Int
    public let column: Int
    public let headingOrBlock: String?

    public init(file: String, line: Int, column: Int, headingOrBlock: String? = nil) {
        self.file = file
        self.line = line
        self.column = column
        self.headingOrBlock = headingOrBlock
    }
}

public enum WorkspaceLinkDirection: String, Codable, Hashable, Sendable {
    case incoming
    case outgoing
}

public enum WorkspaceGraphQueryError: LocalizedError, Hashable, Sendable {
    case graphUnavailable
    case noteNotFound(VaultQualifiedNoteID)

    public var errorDescription: String? {
        switch self {
        case .graphUnavailable:
            "The Triptych graph is not ready."
        case .noteNotFound(let note):
            "The workspace note was not found: \(note.vaultID.uuidString.lowercased()):\(note.relativePath)"
        }
    }
}
