import Foundation

public enum MarkdownRelativePathError: LocalizedError, Equatable, Sendable {
    case invalid(String)
    case markdownRequired(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let path):
            "Invalid Markdown vault-relative path: \(path)"
        case .markdownRequired(let path):
            "Scholium note operations require a .md path: \(path)"
        }
    }
}

/// Byte-preserving display spelling for one Markdown path relative to a vault.
/// `/` is the only separator. A backslash is an ordinary filename character
/// and is never rewritten into a directory boundary.
public struct MarkdownRelativePath: Codable, Hashable, Sendable,
    CustomStringConvertible
{
    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard !rawValue.isEmpty,
              !rawValue.hasPrefix("/"),
              !rawValue.contains("\0") else {
            throw MarkdownRelativePathError.invalid(rawValue)
        }
        let components = rawValue.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw MarkdownRelativePathError.invalid(rawValue)
        }
        guard components.last?.lowercased().hasSuffix(".md") == true else {
            throw MarkdownRelativePathError.markdownRequired(rawValue)
        }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public var components: [Substring] {
        rawValue.split(separator: "/", omittingEmptySubsequences: false)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum VaultRelativeFolderPathError: LocalizedError, Equatable, Sendable {
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let path):
            "Invalid vault-relative folder path: \(path)"
        }
    }
}

/// Byte-preserving display spelling for one directory path relative to a
/// vault. A folder is a location and classification aid, never a durable note
/// identity. `/` is the only separator; backslashes remain filename content.
public struct VaultRelativeFolderPath: Codable, Hashable, Sendable,
    CustomStringConvertible
{
    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard !rawValue.isEmpty,
              !rawValue.hasPrefix("/"),
              !rawValue.hasSuffix("/"),
              !rawValue.contains("\0") else {
            throw VaultRelativeFolderPathError.invalid(rawValue)
        }
        let components = rawValue.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw VaultRelativeFolderPathError.invalid(rawValue)
        }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public var components: [Substring] {
        rawValue.split(separator: "/", omittingEmptySubsequences: false)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct VaultPathComparisonKey: Hashable, Sendable {
    public let value: String

    public init(
        _ path: MarkdownRelativePath,
        caseSensitive: Bool,
        normalizationSensitive: Bool
    ) {
        self.init(
            rawValue: path.rawValue,
            caseSensitive: caseSensitive,
            normalizationSensitive: normalizationSensitive
        )
    }

    public init(
        _ path: VaultRelativeFolderPath,
        caseSensitive: Bool,
        normalizationSensitive: Bool
    ) {
        self.init(
            rawValue: path.rawValue,
            caseSensitive: caseSensitive,
            normalizationSensitive: normalizationSensitive
        )
    }

    private init(
        rawValue: String,
        caseSensitive: Bool,
        normalizationSensitive: Bool
    ) {
        var compared = rawValue
        if !normalizationSensitive {
            compared = compared.precomposedStringWithCanonicalMapping
        }
        if !caseSensitive {
            compared = compared.folding(
                options: [.caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
        }
        value = compared
    }
}

/// Immutable projection of one vault volume's filename comparison behavior.
/// Core derives it from the mounted root; delivery consumers may use it only
/// for conservative preflight and must leave final containment and collision
/// authorization to the repository.
public struct VaultPathComparisonPolicy: Codable, Hashable, Sendable {
    public let caseSensitive: Bool
    public let normalizationSensitive: Bool

    public init(caseSensitive: Bool, normalizationSensitive: Bool) {
        self.caseSensitive = caseSensitive
        self.normalizationSensitive = normalizationSensitive
    }

    public func comparisonKey(
        for path: MarkdownRelativePath
    ) -> VaultPathComparisonKey {
        VaultPathComparisonKey(
            path,
            caseSensitive: caseSensitive,
            normalizationSensitive: normalizationSensitive
        )
    }

    public func comparisonKey(
        for path: VaultRelativeFolderPath
    ) -> VaultPathComparisonKey {
        VaultPathComparisonKey(
            path,
            caseSensitive: caseSensitive,
            normalizationSensitive: normalizationSensitive
        )
    }
}

public enum DocumentIdentityResolution: String, Codable, Hashable, Sendable {
    case resolved
    case unresolved
    case pending
    case ambiguous
}

public enum DocumentFileAction: String, Codable, CaseIterable, Hashable, Sendable {
    case duplicate
    case move
    case moveToSystemTrash
}

public struct DocumentCapabilities: Codable, Equatable, Sendable {
    public let canEditSource: Bool
    public let canComment: Bool
    public let canUseResearchFunctions: Bool
    public let isManagedCritique: Bool
    public let fileActions: Set<DocumentFileAction>

    public init(
        role: VaultRole,
        identity: DocumentIdentityResolution,
        isManagedCritique: Bool
    ) {
        self.isManagedCritique = isManagedCritique
        guard identity == .resolved else {
            canEditSource = false
            canComment = false
            canUseResearchFunctions = false
            fileActions = []
            return
        }
        canEditSource = !isManagedCritique
        canComment = (
            role == .sourceCorpus
                || role == .topicKnowledge
                || role == .draftProject
        )
        canUseResearchFunctions = role != .other
            && !isManagedCritique
        fileActions = isManagedCritique
            ? [.move, .moveToSystemTrash]
            : [.duplicate, .move, .moveToSystemTrash]
    }

    public func allows(_ action: DocumentFileAction) -> Bool {
        fileActions.contains(action)
    }
}
