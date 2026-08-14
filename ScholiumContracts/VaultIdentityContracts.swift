import Foundation

public struct VaultIdentity: Codable, Hashable, Sendable {
    public let id: UUID
    public let canonicalPath: String
    public let bookmarkData: Data?

    public init(id: UUID, canonicalPath: String, bookmarkData: Data?) {
        self.id = id
        self.canonicalPath = canonicalPath
        self.bookmarkData = bookmarkData
    }
}

public enum VaultIdentityRegistryError: LocalizedError, Sendable {
    case corruptRegistry(String)
    case identityConflict(existing: UUID, requested: UUID, path: String)

    public var errorDescription: String? {
        switch self {
        case .corruptRegistry(let reason):
            "Scholium could not safely load the vault-access registry. The existing file was left unchanged. \(reason)"
        case .identityConflict(let existing, let requested, let path):
            "The vault at '\(path)' is already registered as \(existing.uuidString) and cannot also use \(requested.uuidString)."
        }
    }
}

public struct PortableControlAccess: Codable, Hashable, Sendable {
    public let canonicalContainerPath: String
    public let bookmarkData: Data

    public init(canonicalContainerPath: String, bookmarkData: Data) {
        self.canonicalContainerPath = canonicalContainerPath
        self.bookmarkData = bookmarkData
    }
}

public enum PortableControlAccessRegistryError: LocalizedError, Sendable {
    case corruptRegistry(String)
    case invalidContainer(expected: String, selected: String)

    public var errorDescription: String? {
        switch self {
        case .corruptRegistry(let reason):
            "Scholium could not safely load the portable-folder access registry. The existing file was left unchanged. \(reason)"
        case .invalidContainer(let expected, let selected):
            "Choose the folder containing Works. Expected '\(expected)', but received '\(selected)'."
        }
    }
}
