import Foundation

public enum ManagedCreationDestination: Hashable, Sendable {
    case untitled(folderRelativePath: String?)
    case exact(relativePath: String)
}

public enum ManagedCreationAuthority: Hashable, Sendable {
    case researcher
    /// One exact creation requested through the fixed Scholium MCP tool. The
    /// value reserves only the stable Note identity for this transaction; it
    /// is not an Agent identity or continuing permission.
    case mcp(reservedIdentity: UUID)
}

/// Complete authored Markdown, preserved exactly; YAML has no separate mutation owner.
public struct ManagedNoteCreationRequest: Hashable, Sendable {
    public let vaultID: UUID
    public let destination: ManagedCreationDestination
    public let source: String
    public let authority: ManagedCreationAuthority
    public init(vaultID: UUID, destination: ManagedCreationDestination, source: String = "", authority: ManagedCreationAuthority = .researcher) throws {
        guard source.utf8.count <= ScholiumMCPContract.maximumDocumentUTF8ByteCount, !source.contains("\0") else { throw DocumentCreationError.invalidSource }
        self.vaultID = vaultID
        self.destination = destination
        self.source = source
        self.authority = authority
    }
}

public enum ManagedNoteSourceBuilder {
    public static func source(for request: ManagedNoteCreationRequest, vaultRole: VaultRole) throws -> String { request.source }
}

public enum DocumentCreationError: LocalizedError, Equatable, Sendable {
    case invalidSource
    case portableIdentityAlreadyExists
    case reservedIdentityMismatch
    public var errorDescription: String? {
        switch self {
        case .invalidSource: "Provide bounded UTF-8 Markdown without NUL bytes."
        case .portableIdentityAlreadyExists: "The creation path already belongs to a portable Note identity. Choose a new path."
        case .reservedIdentityMismatch: "The created note did not receive the stable identity reserved by its authorization."
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
