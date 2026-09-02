import Foundation

public enum ScholiumMCPContract {
    public static let maximumDocumentUTF8ByteCount = 512 * 1_024
    public static let currentToolSchemaVersion = 2
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
    case search = "scholium_search"
    case readNote = "scholium_read_note"
    case readRecord = "scholium_read_record"
    case listLinks = "scholium_list_links"
    case createNote = "scholium_create_note"
    case updateNote = "scholium_update_note"
    case trashNote = "scholium_trash_note"
    case recordProgress = "scholium_record_progress"
    case correctRecordStep = "scholium_correct_record_step"
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
    case operationUncertain = "operation_uncertain"
    case internalError = "internal_error"
}

public struct ScholiumMCPFailure: Codable, Hashable, Sendable, Error {
    public let schemaVersion: Int
    public let status: String
    public let code: ScholiumMCPFailureCode
    public let message: String
    public let recovery: String

    public init(
        code: ScholiumMCPFailureCode,
        message: String,
        recovery: String
    ) {
        schemaVersion = ScholiumMCPContract.currentToolSchemaVersion
        status = "failed"
        self.code = code
        self.message = message
        self.recovery = recovery
    }
}

/// One authenticated request from the standalone stdio adapter to the
/// currently running App. It carries no Agent identity, task, permission, or
/// durable lifecycle state.
public struct ScholiumMCPBridgeRequest: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let requestID: UUID
    public let tool: ScholiumMCPToolName
    public let arguments: [String: MCPJSONValue]

    public init(
        requestID: UUID = UUID(),
        tool: ScholiumMCPToolName,
        arguments: [String: MCPJSONValue] = [:]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.requestID = requestID
        self.tool = tool
        self.arguments = arguments
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case tool, arguments
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
