import Foundation

public enum ResearchMethodLocatorError: LocalizedError, Hashable, Sendable {
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let reason):
            "The machine-local Method access registry is invalid. \(reason)"
        }
    }
}

public struct ResearchSkillRegistrationKey: RawRepresentable, Codable, Hashable,
    Sendable, CustomStringConvertible
{
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString.lowercased() }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UUID.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum ResearchMethodFileLocationKind: String, Codable, CaseIterable,
    Hashable, Sendable
{
    /// Path relative to the Triptych's `.scholium` control directory.
    case triptychControl = "triptych_control"
    /// The absolute path and bookmark exist only in the machine-local locator
    /// store under the registration's opaque key.
    case machineLocal = "machine_local"
}

/// A portable location marker. It either contains one safe `.scholium`-
/// relative path or says that the registration's opaque key must be resolved
/// in machine-local state. It never encodes an absolute path or bookmark.
public struct ResearchMethodFileLocation: Codable, Hashable, Sendable {
    public let kind: ResearchMethodFileLocationKind
    public let triptychRelativePath: String?

    public static func triptychControl(_ relativePath: String) throws -> Self {
        try Self(kind: .triptychControl, triptychRelativePath: relativePath)
    }

    public static func machineLocal() -> Self {
        Self(machineLocalMarker: ())
    }

    private init(machineLocalMarker: Void) {
        kind = .machineLocal
        triptychRelativePath = nil
    }

    private init(
        kind: ResearchMethodFileLocationKind,
        triptychRelativePath: String?
    ) throws {
        switch kind {
        case .triptychControl:
            guard let triptychRelativePath,
                  triptychRelativePath.utf8.count <= 4_096,
                  ResearchSkillRegistrationValidation.isSafeRelativePath(
                    triptychRelativePath
                  ) else {
                throw ResearchSkillRegistrationError.invalidMethodPath
            }
        case .machineLocal:
            guard triptychRelativePath == nil else {
                throw ResearchSkillRegistrationError.invalidMethodPath
            }
        }
        self.kind = kind
        self.triptychRelativePath = triptychRelativePath
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case triptychRelativePath
    }

    public init(from decoder: Decoder) throws {
        try ResearchSkillRegistrationValidation.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: container.decode(ResearchMethodFileLocationKind.self, forKey: .kind),
            triptychRelativePath: container.decodeIfPresent(
                String.self,
                forKey: .triptychRelativePath
            )
        )
    }
}

/// The only current routing relation between one public Action and one primary
/// Research Skill Markdown file.
public struct ResearchSkillRegistration: Codable, Hashable, Identifiable, Sendable {
    public var id: ResearchSkillRegistrationKey { key }

    public let key: ResearchSkillRegistrationKey
    public let actionID: ResearchActionID
    public let displayName: String
    public let primaryMarkdown: ResearchMethodFileLocation
    public let skillFolder: ResearchMethodFileLocation?
    public let isEnabled: Bool

    public init(
        key: ResearchSkillRegistrationKey = ResearchSkillRegistrationKey(),
        actionID: ResearchActionID,
        displayName: String,
        primaryMarkdown: ResearchMethodFileLocation,
        skillFolder: ResearchMethodFileLocation? = nil,
        isEnabled: Bool = true
    ) throws {
        let name = try ResearchSkillRegistrationValidation.text(
            displayName,
            maximumUTF8Count: 256
        )
        if let skillFolder {
            guard skillFolder.kind == primaryMarkdown.kind else {
                throw ResearchSkillRegistrationError.entryOutsideFolder
            }
            if primaryMarkdown.kind == .triptychControl {
                guard let primary = primaryMarkdown.triptychRelativePath,
                      let folder = skillFolder.triptychRelativePath,
                      ResearchSkillRegistrationValidation.containsRelative(
                        path: primary,
                        inFolder: folder
                      ) else {
                    throw ResearchSkillRegistrationError.entryOutsideFolder
                }
            }
        }
        self.key = key
        self.actionID = actionID
        self.displayName = name
        self.primaryMarkdown = primaryMarkdown
        self.skillFolder = skillFolder
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case key
        case actionID
        case displayName
        case primaryMarkdown
        case skillFolder
        case isEnabled
    }

    public init(from decoder: Decoder) throws {
        try ResearchSkillRegistrationValidation.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            key: container.decode(ResearchSkillRegistrationKey.self, forKey: .key),
            actionID: container.decode(ResearchActionID.self, forKey: .actionID),
            displayName: container.decode(String.self, forKey: .displayName),
            primaryMarkdown: container.decode(
                ResearchMethodFileLocation.self,
                forKey: .primaryMarkdown
            ),
            skillFolder: container.decodeIfPresent(
                ResearchMethodFileLocation.self,
                forKey: .skillFolder
            ),
            isEnabled: container.decode(Bool.self, forKey: .isEnabled)
        )
    }
}

public struct ResearchSkillRegistrationDocument: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2
    public static let maximumRegistrationCount = 64

    public let schemaVersion: Int
    public let registrations: [ResearchSkillRegistration]

    public init(registrations: [ResearchSkillRegistration]) throws {
        guard registrations.count <= Self.maximumRegistrationCount,
              Set(registrations.map(\.key)).count == registrations.count,
              Set(registrations.map(\.actionID)).count == registrations.count else {
            throw ResearchSkillRegistrationError.invalidDocument
        }
        schemaVersion = Self.currentSchemaVersion
        self.registrations = registrations.sorted {
            $0.actionID.rawValue < $1.actionID.rawValue
        }
    }

    public func registration(for actionID: ResearchActionID) -> ResearchSkillRegistration? {
        registrations.first { $0.actionID == actionID }
    }

    public func replacing(_ registration: ResearchSkillRegistration) throws -> Self {
        try Self(registrations: registrations.filter {
            $0.actionID != registration.actionID && $0.key != registration.key
        } + [registration])
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case registrations
    }

    public init(from decoder: Decoder) throws {
        try ResearchSkillRegistrationValidation.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw ResearchSkillRegistrationError.unsupportedSchemaVersion(version)
        }
        try self.init(registrations: container.decode(
            [ResearchSkillRegistration].self,
            forKey: .registrations
        ))
    }
}

public struct ResearchSkillRegistrationSnapshot: Hashable, Sendable {
    public let document: ResearchSkillRegistrationDocument
    public let revision: DocumentFingerprint

    public init(document: ResearchSkillRegistrationDocument, revision: DocumentFingerprint) {
        self.document = document
        self.revision = revision
    }
}

public struct ResearchPracticeSnapshot: Codable, Hashable, Identifiable, Sendable {
    public var id: String { relativePath }

    public let title: String
    public let relativePath: String
    public let source: String
    public let revision: DocumentFingerprint

    public init(
        title: String,
        relativePath: String,
        source: String,
        revision: DocumentFingerprint? = nil
    ) throws {
        self.title = try ResearchSkillRegistrationValidation.text(
            title,
            maximumUTF8Count: 256
        )
        guard ResearchSkillRegistrationValidation.isSafeRelativePath(relativePath),
              relativePath.lowercased().hasSuffix(".md"),
              source.utf8.count <= 1_048_576 else {
            throw ResearchSkillRegistrationError.invalidPractice
        }
        self.relativePath = relativePath
        self.source = source
        self.revision = revision ?? DocumentFingerprint(content: source)
    }
}

public enum ResearchPracticeResolutionIssueKind: String, Codable, Hashable, Sendable {
    case missing
    case ambiguous
    case unsupportedReference = "unsupported_reference"
}

public struct ResearchPracticeResolutionIssue: Codable, Hashable, Sendable {
    public let kind: ResearchPracticeResolutionIssueKind
    public let target: String

    public init(kind: ResearchPracticeResolutionIssueKind, target: String) throws {
        self.kind = kind
        self.target = try ResearchSkillRegistrationValidation.text(
            target,
            maximumUTF8Count: 1_024
        )
    }
}

public struct ResearchMethodSnapshot: Codable, Hashable, Sendable {
    public let registration: ResearchSkillRegistration
    public let primaryMarkdownSource: String
    public let primaryMarkdownRevision: DocumentFingerprint
    public let practices: [ResearchPracticeSnapshot]
    public let practiceIssues: [ResearchPracticeResolutionIssue]
    /// Resolved machine-local delivery value. Local Execution may freeze it;
    /// portable registration and Record contracts never contain it.
    public let skillFolderPath: String?
    public let skillFolderIsAvailable: Bool?

    public init(
        registration: ResearchSkillRegistration,
        primaryMarkdownSource: String,
        primaryMarkdownRevision: DocumentFingerprint? = nil,
        practices: [ResearchPracticeSnapshot],
        practiceIssues: [ResearchPracticeResolutionIssue] = [],
        skillFolderPath: String? = nil,
        skillFolderIsAvailable: Bool? = nil
    ) throws {
        guard primaryMarkdownSource.utf8.count <= 1_048_576,
              Set(practices.map(\.relativePath)).count == practices.count else {
            throw ResearchSkillRegistrationError.invalidSnapshot
        }
        self.registration = registration
        self.primaryMarkdownSource = primaryMarkdownSource
        self.primaryMarkdownRevision = primaryMarkdownRevision
            ?? DocumentFingerprint(content: primaryMarkdownSource)
        self.practices = practices
        self.practiceIssues = practiceIssues
        self.skillFolderPath = skillFolderPath
        self.skillFolderIsAvailable = registration.skillFolder == nil
            ? nil
            : skillFolderIsAvailable
    }
}

public enum ResearchSkillRegistrationError: LocalizedError, Hashable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unsupportedField(String)
    case invalidMethodPath
    case invalidFolderPath
    case entryOutsideFolder
    case invalidDocument
    case invalidPractice
    case invalidSnapshot
    case invalidText

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported Research Skill registration schema version \(version)."
        case .unsupportedField(let field):
            "Unsupported Research Skill registration field: \(field)."
        case .invalidMethodPath:
            "The primary Research Skill Markdown path is invalid."
        case .invalidFolderPath:
            "The optional Research Skill folder path is invalid."
        case .entryOutsideFolder:
            "The primary Markdown entry must remain inside its registered Skill folder."
        case .invalidDocument:
            "The Research Skill registration document is invalid."
        case .invalidPractice:
            "The Philosophical Practice is invalid."
        case .invalidSnapshot:
            "The frozen Research Method snapshot is invalid."
        case .invalidText:
            "Research Skill registration text is invalid."
        }
    }
}

private enum ResearchSkillRegistrationValidation {
    static func text(_ value: String, maximumUTF8Count: Int) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf8.count <= maximumUTF8Count,
              !trimmed.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else { throw ResearchSkillRegistrationError.invalidText }
        return trimmed
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }

    static func containsRelative(path: String, inFolder folder: String) -> Bool {
        let pathComponents = path.split(separator: "/").map(String.init)
        let folderComponents = folder.split(separator: "/").map(String.init)
        return pathComponents.count > folderComponents.count
            && Array(pathComponents.prefix(folderComponents.count)) == folderComponents
    }

    static func rejectUnknownFields<Key: CodingKey & CaseIterable>(
        _ decoder: Decoder,
        allowed: Key.Type
    ) throws {
        let raw = try decoder.container(keyedBy: RegistrationCodingKey.self)
        let known = Set(Key.allCases.map(\.stringValue))
        if let unknown = raw.allKeys.map(\.stringValue).first(where: {
            !known.contains($0)
        }) {
            throw ResearchSkillRegistrationError.unsupportedField(unknown)
        }
    }

    private struct RegistrationCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}
