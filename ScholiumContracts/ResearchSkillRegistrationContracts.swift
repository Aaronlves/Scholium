import Foundation

public enum ResearchSkillFolderLocatorError: LocalizedError, Hashable, Sendable {
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let reason):
            "The machine-local Skill-folder access registry is invalid. \(reason)"
        }
    }
}

/// Short-lived, read-only access to a registered Skill folder for presentation
/// such as revealing it in Finder. Retaining this value keeps the underlying
/// security scope active; it provides no file-content operation.
public protocol ResearchSkillFolderAccess: AnyObject, Sendable {
    var url: URL { get }
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

public enum ResearchSkillFolderLocationKind: String, Codable, CaseIterable,
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
public struct ResearchSkillFolderLocation: Codable, Hashable, Sendable {
    public let kind: ResearchSkillFolderLocationKind
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
        kind: ResearchSkillFolderLocationKind,
        triptychRelativePath: String?
    ) throws {
        switch kind {
        case .triptychControl:
            guard let triptychRelativePath,
                  triptychRelativePath.utf8.count <= 4_096,
                  ResearchSkillRegistrationValidation.isSafeRelativePath(
                    triptychRelativePath
                  ) else {
                throw ResearchSkillRegistrationError.invalidFolderPath
            }
        case .machineLocal:
            guard triptychRelativePath == nil else {
                throw ResearchSkillRegistrationError.invalidFolderPath
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
            kind: container.decode(ResearchSkillFolderLocationKind.self, forKey: .kind),
            triptychRelativePath: container.decodeIfPresent(
                String.self,
                forKey: .triptychRelativePath
            )
        )
    }
}

/// The only current routing relation between one public Action and one
/// researcher-owned Skill folder. Scholium never reads or writes its contents.
public struct ResearchSkillRegistration: Codable, Hashable, Identifiable, Sendable {
    public var id: ResearchSkillRegistrationKey { key }

    public let key: ResearchSkillRegistrationKey
    public let actionID: ResearchActionID
    public let displayName: String
    public let skillFolder: ResearchSkillFolderLocation
    public let isEnabled: Bool

    public init(
        key: ResearchSkillRegistrationKey = ResearchSkillRegistrationKey(),
        actionID: ResearchActionID,
        displayName: String,
        skillFolder: ResearchSkillFolderLocation,
        isEnabled: Bool = true
    ) throws {
        let name = try ResearchSkillRegistrationValidation.text(
            displayName,
            maximumUTF8Count: 256
        )
        self.key = key
        self.actionID = actionID
        self.displayName = name
        self.skillFolder = skillFolder
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case key
        case actionID
        case displayName
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
            skillFolder: container.decode(
                ResearchSkillFolderLocation.self,
                forKey: .skillFolder
            ),
            isEnabled: container.decode(Bool.self, forKey: .isEnabled)
        )
    }
}

public struct ResearchSkillRegistrationDocument: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 3
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

public struct ResearchSkillBindingSnapshot: Codable, Hashable, Sendable {
    public let registration: ResearchSkillRegistration
    public let registrationRevision: DocumentFingerprint
    /// Resolved machine-local delivery value. Local Execution may freeze it;
    /// portable registration and Record contracts never contain it.
    public let skillFolderPath: String
    public let skillFolderIsAvailable: Bool

    public init(
        registration: ResearchSkillRegistration,
        registrationRevision: DocumentFingerprint,
        skillFolderPath: String,
        skillFolderIsAvailable: Bool
    ) throws {
        guard !skillFolderPath.isEmpty,
              skillFolderPath.utf8.count <= 4_096 else {
            throw ResearchSkillRegistrationError.invalidSnapshot
        }
        self.registration = registration
        self.registrationRevision = registrationRevision
        self.skillFolderPath = skillFolderPath
        self.skillFolderIsAvailable = skillFolderIsAvailable
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case registration
        case registrationRevision
        case skillFolderPath
        case skillFolderIsAvailable
    }

    public init(from decoder: Decoder) throws {
        try ResearchSkillRegistrationValidation.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            registration: container.decode(
                ResearchSkillRegistration.self,
                forKey: .registration
            ),
            registrationRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .registrationRevision
            ),
            skillFolderPath: container.decode(
                String.self,
                forKey: .skillFolderPath
            ),
            skillFolderIsAvailable: container.decode(
                Bool.self,
                forKey: .skillFolderIsAvailable
            )
        )
    }
}

public enum ResearchSkillRegistrationError: LocalizedError, Hashable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unsupportedField(String)
    case invalidFolderPath
    case invalidDocument
    case invalidSnapshot
    case invalidText

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported Research Skill registration schema version \(version)."
        case .unsupportedField(let field):
            "Unsupported Research Skill registration field: \(field)."
        case .invalidFolderPath:
            "The Research Skill folder path is invalid."
        case .invalidDocument:
            "The Research Skill registration document is invalid."
        case .invalidSnapshot:
            "The frozen Research Skill binding is invalid."
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
