import Foundation

/// One code-owned citation style that the current Platform can pass to a
/// Research Run. A style is an integration setting, not a Skill package or a
/// capability declaration.
public struct ResearchCitationStyleOption: Codable, Hashable, Identifiable, Sendable {
    public let citationStyle: String
    public let displayName: String
    public let description: String

    public var id: String { citationStyle }

    public init(
        citationStyle: String,
        displayName: String,
        description: String
    ) {
        self.citationStyle = citationStyle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Closed Platform support for citation-style identifiers. Intellectual prose
/// for a citation-aware Action remains in its researcher-owned Skill folder.
public enum ResearchCitationStyleCatalog {
    public static let options = [
        ResearchCitationStyleOption(
            citationStyle: "apa-7",
            displayName: "APA 7",
            description: "Use APA Publication Manual, Seventh Edition conventions."
        ),
    ]

    public static func option(for citationStyle: String) -> ResearchCitationStyleOption? {
        let normalized = citationStyle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return options.first { $0.citationStyle == normalized }
    }
}

/// One strict Triptych-owned current selection. It contains no package,
/// resource, version, digest, migration alias, or executable-method claim.
public struct ResearchCitationMethodDocument: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let triptychID: UUID
    public let activeCitationStyle: String?

    public init(
        triptychID: UUID,
        activeCitationStyle: String? = nil
    ) throws {
        let normalized = activeCitationStyle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized == nil
                || ResearchCitationStyleCatalog.option(for: normalized!) != nil else {
            throw ResearchCitationMethodContractError.unsupportedCitationStyle(
                normalized ?? ""
            )
        }
        schemaVersion = Self.currentSchemaVersion
        self.triptychID = triptychID
        self.activeCitationStyle = normalized
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case triptychID
        case activeCitationStyle
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: ResearchCitationAnyCodingKey.self)
        let known = Set(CodingKeys.allCases.map(\.stringValue))
        if let unknown = raw.allKeys.map(\.stringValue).first(where: {
            !known.contains($0)
        }) {
            throw ResearchCitationMethodContractError.unsupportedField(unknown)
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw ResearchCitationMethodContractError.unsupportedSchemaVersion(version)
        }
        try self.init(
            triptychID: container.decode(UUID.self, forKey: .triptychID),
            activeCitationStyle: container.decodeIfPresent(
                String.self,
                forKey: .activeCitationStyle
            )
        )
    }
}

public struct ResearchCitationMethodSnapshot: Hashable, Sendable {
    public let document: ResearchCitationMethodDocument
    public let revision: DocumentFingerprint

    public init(
        document: ResearchCitationMethodDocument,
        revision: DocumentFingerprint
    ) {
        self.document = document
        self.revision = revision
    }
}

public struct ResearchCitationMethodStatus: Codable, Hashable, Sendable {
    public let availableStyles: [ResearchCitationStyleOption]
    public let activeCitationStyle: String?
    public let configurationRevision: DocumentFingerprint?

    public init(
        availableStyles: [ResearchCitationStyleOption],
        activeCitationStyle: String?,
        configurationRevision: DocumentFingerprint?
    ) {
        self.availableStyles = availableStyles.sorted {
            $0.displayName == $1.displayName
                ? $0.citationStyle < $1.citationStyle
                : $0.displayName < $1.displayName
        }
        self.activeCitationStyle = activeCitationStyle
        self.configurationRevision = configurationRevision
    }
}

public struct ResearchCitationMethodSelection: Codable, Hashable, Sendable {
    public let citationStyle: String

    public init(citationStyle: String) {
        self.citationStyle = citationStyle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

public enum ResearchCitationMethodContractError: LocalizedError, Hashable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unsupportedField(String)
    case unsupportedCitationStyle(String)
    case triptychMismatch

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported Citation Method schema version \(version)."
        case .unsupportedField(let field):
            "Citation Method contains unsupported field \(field)."
        case .unsupportedCitationStyle(let style):
            "Citation style \(style) is not supported by the current Platform."
        case .triptychMismatch:
            "The Citation Method configuration belongs to another Triptych."
        }
    }
}

private struct ResearchCitationAnyCodingKey: CodingKey {
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
