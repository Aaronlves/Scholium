import Foundation

public enum ScholiumMCPContract {
    public static let maximumDocumentUTF8ByteCount = 512 * 1_024
    public static let currentToolSchemaVersion = 7
}

/// JSON values accepted at the MCP delivery boundary. Domain owners decode
/// closed argument objects from this value; no untyped value crosses into a
/// repository or source mutation.
public enum MCPJSONValue: Codable, Hashable, Sendable {
    case object([String: MCPJSONValue])
    case array([MCPJSONValue])
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([MCPJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: MCPJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "The MCP value is not valid JSON."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var objectValue: [String: MCPJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public var arrayValue: [MCPJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var intValue: Int? {
        guard case .integer(let value) = self else { return nil }
        return value
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}

public enum ScholiumMCPToolName: String, Codable, CaseIterable, Sendable {
    case workspaceStatus = "scholium_workspace_status"
    case browse = "scholium_browse"
    case search = "scholium_search"
    case readNote = "scholium_read_note"
    case showNote = "scholium_show_note"
    case listAttachments = "scholium_list_attachments"
    case readAttachment = "scholium_read_attachment"
    case listLinks = "scholium_list_links"
    case createNote = "scholium_create_note"
    case updateNote = "scholium_update_note"
    case updateMetadata = "scholium_update_metadata"
    case updateAttachment = "scholium_update_attachment"
    case moveNote = "scholium_move_note"
    case previewMove = "scholium_preview_move"
    case listChanges = "scholium_list_changes"
    case readChange = "scholium_read_change"
    case undoChange = "scholium_undo_change"
    case trashNote = "scholium_trash_note"
    case capabilities = "scholium_capabilities"
    case configureSkill = "scholium_configure_skill"
    case configureTool = "scholium_configure_tool"
    case configureChat = "scholium_configure_chat"

    /// These controls belong to the in-app Agent conversation. They are not
    /// part of the standalone external research MCP surface because that
    /// surface has no conversation-owned runtime configuration target.
    public var isChatControl: Bool {
        switch self {
        case .capabilities, .configureSkill, .configureTool, .configureChat: true
        default: false
        }
    }
}

public enum ScholiumMCPFailureCode: String, Codable, CaseIterable, Sendable {
    case appUnavailable = "app_unavailable"
    case workspaceSelectionRequired = "workspace_selection_required"
    case workspaceNotReady = "workspace_not_ready"
    case notFound = "not_found"
    case ambiguous
    case pathOccupied = "path_occupied"
    case staleRevision = "stale_revision"
    case conflict
    case invalidRequest = "invalid_request"
    case noChanges = "no_changes"
    case operationUncertain = "operation_uncertain"
    case internalError = "internal_error"
}

public struct ScholiumMCPFailure: Codable, Hashable, Sendable, Error {
    public let schemaVersion: Int
    public let status: String
    public let code: ScholiumMCPFailureCode
    public let message: String
    public let recovery: String
    public let recoveryDetails: ScholiumMCPRecoveryDetails?

    public init(
        code: ScholiumMCPFailureCode,
        message: String,
        recovery: String,
        recoveryDetails: ScholiumMCPRecoveryDetails? = nil
    ) {
        schemaVersion = ScholiumMCPContract.currentToolSchemaVersion
        status = "failed"
        self.code = code
        self.message = message
        self.recovery = recovery
        self.recoveryDetails = recoveryDetails
    }
}

public struct ScholiumMCPRecoveryDetails: Codable, Hashable, Sendable {
    public let recoveryID: UUID
    public let files: [TriptychMutationRecoveryFile]
    public let total: Int
    public init(record: TriptychMutationRecoveryRecord) {
        recoveryID = record.id; files = Array(record.files.prefix(100)); total = record.files.count
    }
    public var jsonValue: MCPJSONValue {
        func fingerprint(_ value: DocumentFingerprint?) -> MCPJSONValue {
            value.map { .object(["sha256": .string($0.sha256), "byte_count": .integer($0.byteCount)]) } ?? .null
        }
        return .object(["recovery_id": .string(recoveryID.uuidString.lowercased()), "total": .integer(total), "has_more": .bool(files.count < total),
            "files": .array(files.map { file in .object([
                "vault_id": file.vaultID.map { .string($0.uuidString.lowercased()) } ?? .null, "path": .string(file.path),
                "alternate_path": file.alternatePath.map(MCPJSONValue.string) ?? .null, "role": .string(file.role.rawValue),
                "before_fingerprint": fingerprint(file.beforeRevision), "intended_fingerprint": fingerprint(file.intendedRevision),
                "observed_fingerprint": fingerprint(file.observedRevision), "state": .string(file.state.rawValue), "detail": .string(file.detail),
            ]) })])
    }
}

/// Runtime-provided scope metadata; it never grants authority by itself.
public struct ScholiumMCPRuntimeContext: Codable, Hashable, Sendable {
    public let threadID: String
    public let turnID: String

    public init(threadID: String, turnID: String) {
        self.threadID = threadID
        self.turnID = turnID
    }
}

/// An authenticated adapter request. The App owns all admission and permission decisions.
public struct ScholiumMCPBridgeRequest: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let requestID: UUID
    public let tool: ScholiumMCPToolName
    public let arguments: [String: MCPJSONValue]
    public let conversationToken: UUID?
    public let runtimeContext: ScholiumMCPRuntimeContext?

    public init(
        requestID: UUID = UUID(),
        tool: ScholiumMCPToolName,
        arguments: [String: MCPJSONValue] = [:],
        conversationToken: UUID? = nil,
        runtimeContext: ScholiumMCPRuntimeContext? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.requestID = requestID
        self.tool = tool
        self.arguments = arguments
        self.conversationToken = conversationToken
        self.runtimeContext = runtimeContext
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case tool, arguments
        case conversationToken = "conversation_token"
        case runtimeContext = "runtime_context"
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: MCPDynamicCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw ScholiumMCPFailure(
                code: .invalidRequest,
                message: "The App bridge request contains unsupported fields.",
                recovery: "Send only the published Scholium MCP request shape."
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw ScholiumMCPFailure(
                code: .invalidRequest,
                message: "The App bridge request schema is unsupported.",
                recovery: "Use a Scholium CLI version compatible with the running App."
            )
        }
        schemaVersion = version
        requestID = try container.decode(UUID.self, forKey: .requestID)
        tool = try container.decode(ScholiumMCPToolName.self, forKey: .tool)
        arguments = try container.decodeIfPresent(
            [String: MCPJSONValue].self,
            forKey: .arguments
        ) ?? [:]
        conversationToken = try container.decodeIfPresent(UUID.self, forKey: .conversationToken)
        runtimeContext = try container.decodeIfPresent(ScholiumMCPRuntimeContext.self, forKey: .runtimeContext)
    }
}

public struct ScholiumMCPBridgeResponse: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let requestID: UUID
    public let result: MCPJSONValue?
    public let error: ScholiumMCPFailure?

    public init(
        requestID: UUID,
        result: MCPJSONValue? = nil,
        error: ScholiumMCPFailure? = nil
    ) throws {
        guard (result == nil) != (error == nil) else {
            throw ScholiumMCPFailure(
                code: .internalError,
                message: "The App bridge response was invalid.",
                recovery: "Restart Scholium and retry after checking current workspace status."
            )
        }
        schemaVersion = Self.currentSchemaVersion
        self.requestID = requestID
        self.result = result
        self.error = error
    }
}

private struct MCPDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
