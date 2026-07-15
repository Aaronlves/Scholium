import Foundation

public struct WorkspaceBootstrapRequest: Hashable, Sendable {
    public let triptychSelector: String
    public let triptychName: String
    public let targetURL: URL
    public let researcherConventions: String

    public init(
        triptychSelector: String,
        triptychName: String,
        targetURL: URL,
        researcherConventions: String = "None recorded."
    ) {
        self.triptychSelector = triptychSelector
        self.triptychName = triptychName
        self.targetURL = targetURL
        self.researcherConventions = researcherConventions
    }
}

public struct WorkspaceBootstrapCandidate: Codable, Hashable, Sendable {
    public let triptychSelector: String
    public let triptychName: String
    public let targetPath: String
    public let content: String

    public init(
        triptychSelector: String,
        triptychName: String,
        targetPath: String,
        content: String
    ) {
        self.triptychSelector = triptychSelector
        self.triptychName = triptychName
        self.targetPath = targetPath
        self.content = content
    }
}

public enum WorkspaceBootstrapError: LocalizedError, Equatable, Sendable {
    case invalidSelector
    case invalidTriptychName
    case targetDoesNotExist(String)
    case targetIsNotDirectory(String)
    case applicationCheckout(String)
    case applicableInstructions([String])

    public var errorDescription: String? {
        switch self {
        case .invalidSelector:
            "A registered Triptych selector is required."
        case .invalidTriptychName:
            "The Triptych name must be a nonempty single-line value."
        case .targetDoesNotExist(let path):
            "The bootstrap target does not exist: \(path)"
        case .targetIsNotDirectory(let path):
            "The bootstrap target is not a directory: \(path)"
        case .applicationCheckout(let path):
            "Refusing to create researcher workspace instructions inside the Scholium application checkout: \(path)"
        case .applicableInstructions(let paths):
            "An applicable AGENTS.md already exists: \(paths.joined(separator: ", "))"
        }
    }
}

/// Validates and renders the protected one-shot workspace bootstrap. This
/// type never writes a file; the external agent owns candidate promotion and
