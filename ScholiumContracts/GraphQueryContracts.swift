import Foundation

public enum WorkspaceLinkDirection: String, Codable, Hashable, Sendable {
    case incoming
    case outgoing
}

public enum WorkspaceGraphQueryError: LocalizedError, Hashable, Sendable {
    case graphUnavailable
    case noteNotFound(VaultQualifiedNoteID)
    case invalidMaximumDepth(Int)

    public var errorDescription: String? {
        switch self {
        case .graphUnavailable:
            "The Triptych graph is not ready."
        case .noteNotFound(let note):
            "The workspace note was not found: \(note.vaultID.uuidString.lowercased()):\(note.relativePath)"
        case .invalidMaximumDepth(let depth):
            "Graph maximum depth must be from 1 through 10; received \(depth)."
        }
    }
}
