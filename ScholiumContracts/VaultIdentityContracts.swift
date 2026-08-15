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

public struct PortableControlAccess: Codable, Hashable, Sendable {
    public let canonicalContainerPath: String
    public let bookmarkData: Data

    public init(canonicalContainerPath: String, bookmarkData: Data) {
        self.canonicalContainerPath = canonicalContainerPath
        self.bookmarkData = bookmarkData
    }
}

public enum PortableControlAccessError: LocalizedError, Sendable {
    case invalidContainer(expected: String, selected: String)

    public var errorDescription: String? {
        switch self {
        case .invalidContainer(let expected, let selected):
            "Choose the folder containing Works. Expected '\(expected)', but received '\(selected)'."
        }
    }
}
