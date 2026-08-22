import Foundation

public struct CanonicalPropertyInput: Codable, Hashable, Sendable {
    public let key: String
    public let value: YAMLValue

    public init(key: String, value: YAMLValue) throws {
        guard !key.isEmpty,
              key.utf8.count <= 128,
              !key.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw DocumentCreationError.invalidPropertyKey(key)
        }
        self.key = key
        self.value = value
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case key, value
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: ManagedCreationCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DocumentCreationError.invalidMetadata([])
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            key: container.decode(String.self, forKey: .key),
            value: container.decode(CanonicalPropertyJSONValue.self, forKey: .value)
                .value
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(
            CanonicalPropertyJSONValue(value),
            forKey: .value
        )
    }
}

/// Stable delivery encoding for a managed Metadata value. Public CLI and Agent JSON
/// uses ordinary JSON scalar/array/object values; Swift enum synthesis is an
/// implementation detail and never becomes a wire contract.
private struct CanonicalPropertyJSONValue: Codable {
    let value: YAMLValue

    init(_ value: YAMLValue) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = .null
        } else if let value = try? container.decode(Bool.self) {
            self.value = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self.value = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self.value = .double(value)
        } else if let value = try? container.decode(String.self) {
            self.value = .string(value)
        } else if let values = try? container.decode(
            [CanonicalPropertyJSONValue].self
        ) {
            value = .array(values.map(\.value))
        } else if let values = try? container.decode(
            [String: CanonicalPropertyJSONValue].self
        ) {
            value = .object(values.mapValues(\.value))
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Metadata values must be ordinary JSON values."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .array(let values):
            try container.encode(values.map(CanonicalPropertyJSONValue.init))
        case .object(let values):
            try container.encode(values.mapValues(CanonicalPropertyJSONValue.init))
        case .null: try container.encodeNil()
        }
    }
}

public struct AnalysisCreationMetadata: Codable, Hashable, Sendable {
    public let sourceType: AnalysisSourceType
    public let fields: [CanonicalPropertyInput]

    public init(
        sourceType: AnalysisSourceType,
        fields: [CanonicalPropertyInput] = []
    ) throws {
        guard fields.count <= NoteMetadataContractCatalog.analysisCanonicalKeys.count,
              Set(fields.map(\.key)).count == fields.count,
              !fields.contains(where: { $0.key == "type" }) else {
            throw DocumentCreationError.invalidMetadata([])
        }
        let order = Dictionary(uniqueKeysWithValues:
            AnalysisSourceTypeProfileCatalog.profile(for: sourceType)
                .serializationFieldOrder.enumerated().map { ($0.element, $0.offset) }
        )
        self.sourceType = sourceType
        self.fields = fields.sorted { lhs, rhs in
            let left = order[lhs.key] ?? .max
            let right = order[rhs.key] ?? .max
            return left == right ? lhs.key < rhs.key : left < right
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceType = "source_type"
        case fields
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: ManagedCreationCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DocumentCreationError.invalidMetadata([])
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sourceType: container.decode(AnalysisSourceType.self, forKey: .sourceType),
            fields: container.decodeIfPresent(
                [CanonicalPropertyInput].self,
                forKey: .fields
            ) ?? []
        )
    }
}

/// The only authored YAML values that a managed Note creator may receive.
/// Omission is represented in source by the fixed `summary: null` and
/// `keywords: []` scaffold; callers never supply YAML fragments or delimiters.
public struct AuthoredNoteYAML: Codable, Hashable, Sendable {
    public static let maximumSummaryUTF8ByteCount = 32 * 1_024
    public static let maximumKeywordCount = 128
    public static let maximumKeywordUTF8ByteCount = 1_024

    public let summary: String?
    public let keywords: [String]

    public init(
        summary: String? = nil,
        keywords: [String] = []
    ) throws {
        guard summary.map({ value in
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && value.utf8.count <= Self.maximumSummaryUTF8ByteCount
                && !value.contains("\r")
                && !value.unicodeScalars.contains(where: { scalar in
                    scalar != "\n" && CharacterSet.controlCharacters.contains(scalar)
                })
        }) ?? true,
        keywords.count <= Self.maximumKeywordCount,
        Set(keywords).count == keywords.count,
        keywords.allSatisfy({ value in
            value == value.trimmingCharacters(in: .whitespacesAndNewlines)
                && !value.isEmpty
                && value.utf8.count <= Self.maximumKeywordUTF8ByteCount
                && !value.unicodeScalars.contains(where: {
                    CharacterSet.controlCharacters.contains($0)
                })
        }) else {
            throw DocumentCreationError.invalidAuthoredYAML
        }
        self.summary = summary
        self.keywords = keywords
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case summary, keywords
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: ManagedCreationCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DocumentCreationError.invalidAuthoredYAML
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            summary: container.decodeIfPresent(String.self, forKey: .summary),
            keywords: container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        )
    }
}

public enum ManagedCreationDestination: Hashable, Sendable {
    case untitled(folderRelativePath: String?)
    case exact(relativePath: String)
}

public enum ManagedCreationAuthority: Hashable, Sendable {
    case researcher
    case authenticatedAgent(reservedIdentity: UUID)
}

public struct ManagedNoteCreationRequest: Hashable, Sendable {
    public let vaultID: UUID
    public let destination: ManagedCreationDestination
    public let body: String
    public let authoredYAML: AuthoredNoteYAML?
    public let analysisMetadata: AnalysisCreationMetadata?
    public let authority: ManagedCreationAuthority

    public init(
        vaultID: UUID,
        destination: ManagedCreationDestination,
        body: String = "",
        authoredYAML: AuthoredNoteYAML? = nil,
        analysisMetadata: AnalysisCreationMetadata? = nil,
        authority: ManagedCreationAuthority = .researcher
    ) throws {
        guard body.utf8.count <= ResearchBoundedWriteSet.maximumDocumentUTF8ByteCount,
              !body.hasPrefix("\u{FEFF}"),
              !body.contains("\r"),
              !body.unicodeScalars.contains(where: { $0.value == 0 }),
              NoteDocument(
                  relativePath: "Managed Body.md",
                  rawContent: body
              ).frontmatterState == .absent else {
            throw DocumentCreationError.invalidBody
        }
        self.vaultID = vaultID
        self.destination = destination
        self.body = body
        self.authoredYAML = authoredYAML
        self.analysisMetadata = analysisMetadata
        self.authority = authority
    }
}

public enum DocumentCreationError: LocalizedError, Equatable, Sendable {
    case invalidMetadata([PropertyValidationIssue])
    case invalidPropertyKey(String)
    case invalidBody
    case invalidAuthoredYAML
    case analysisMetadataRoleMismatch
    case missingAgentAnalysisMetadata
    case inapplicableAnalysisProperty(String, AnalysisSourceType)
    case portableIdentityAlreadyExists
    case reservedIdentityMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidMetadata(let issues):
            return issues.isEmpty
                ? "The managed creation metadata is invalid."
                : issues.map(\.message).joined(separator: "\n")
        case .invalidPropertyKey(let key):
            return "The managed creation Metadata key is invalid: \(key)"
        case .invalidBody:
            return "Managed creation accepts UTF-8 LF body text without a BOM, carriage returns, NUL bytes, or a top-level YAML envelope. Use Import for complete authored Markdown source."
        case .invalidAuthoredYAML:
            return "Managed creation accepts only a bounded nonempty Summary and unique nonempty Keywords; omit either value to keep its fixed empty scaffold."
        case .analysisMetadataRoleMismatch:
            return "Typed Analysis creation metadata is available only in the Analyses vault."
        case .missingAgentAnalysisMetadata:
            return "Authenticated Agent creation in Analyses requires one source type."
        case .inapplicableAnalysisProperty(let key, let sourceType):
            return "The field \(key) does not apply to Analysis source type \(sourceType.rawValue)."
        case .portableIdentityAlreadyExists:
            return "The managed creation path already belongs to a portable Note identity. Choose a new path instead of reusing that identity."
        case .reservedIdentityMismatch:
            return "The created note did not receive the stable identity reserved by its authorization."
        }
    }
}

private struct ManagedCreationCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
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
