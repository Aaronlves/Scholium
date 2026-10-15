import Foundation

/// Native Settings-only description of a machine-local read grant. Bookmark
/// bytes remain in the access store and are never supplied to an Agent.
public struct ZoteroOriginalAccessGrant: Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable { case file, folder }
    public enum Status: Equatable, Sendable { case available, accessRequired }

    public let id: UUID
    public let path: String
    public let kind: Kind
    public let status: Status

    public init(id: UUID, path: String, kind: Kind, status: Status) {
        self.id = id
        self.path = path
        self.kind = kind
        self.status = status
    }
}

public enum ZoteroOriginalAccessError: LocalizedError {
    case storageUnavailable
    case damagedConfiguration
    case invalidSelection
    case grantMissing

    public var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            "Original access settings are unavailable. Reopen Scholium and try again."
        case .damagedConfiguration:
            "Original access settings cannot be read. Existing settings were preserved."
        case .invalidSelection:
            "Select an original file or its folder directly. Symbolic links are not supported."
        case .grantMissing:
            "This original access grant was removed. Reload the list and try again."
        }
    }
}
