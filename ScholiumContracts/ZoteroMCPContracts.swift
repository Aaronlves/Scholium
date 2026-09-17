import Foundation

public enum ZoteroMCPAccess: String, Sendable {
    case readOnly = "read-only"
}

public enum ZoteroMCPCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case status
    case search
    case itemInspection = "item-inspection"
    case attachmentPointers = "attachment-pointers"
    case annotationReading = "annotation-reading"
    case originalReading = "original-reading"
    case selectedTarget = "selected-target"
}

public struct ZoteroMCPClientConfiguration: Codable, Hashable, Sendable {
    public let command: String
    public let arguments: [String]
    public let environment: [String: String]

    public init(
        command: String,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
    }
}

/// A transport that an external agent can use for Zotero access.
///
/// `supportedLocal` describes Scholium's compatibility helper. `provider`
/// describes the provider-managed Zotero MCP used by Chat when it is
/// installed. The provider owns its complete tool surface and its own
/// Zotero-side authorization; this contract does not copy or truncate that
/// surface into Scholium.
public struct ZoteroMCPTransportDescriptor: Codable, Hashable, Sendable {
    public static let providerServerName = "scholium-zotero"

    public let identifier: String
    public let displayName: String
    public let command: String
    public let clientConfiguration: ZoteroMCPClientConfiguration
    public let capabilities: [ZoteroMCPCapability]
    public let localReadOnlyByDefault: Bool
    public let sourceURL: String

    public init(
        identifier: String,
        displayName: String,
        command: String,
        clientConfiguration: ZoteroMCPClientConfiguration,
        capabilities: [ZoteroMCPCapability],
        localReadOnlyByDefault: Bool,
        sourceURL: String
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.command = command
        self.clientConfiguration = clientConfiguration
        self.capabilities = Self.unique(capabilities)
        self.localReadOnlyByDefault = localReadOnlyByDefault
        self.sourceURL = sourceURL
    }

    public static let supportedLocal = Self(
        identifier: "scholium-zotero-mcp",
        displayName: "Scholium Zotero MCP",
        command: "ScholiumAgentHelper",
        clientConfiguration: ZoteroMCPClientConfiguration(
            command: "ScholiumAgentHelper",
            arguments: ["zotero", "mcp", "serve", "--read-only"]
        ),
        capabilities: ZoteroMCPCapability.allCases,
        localReadOnlyByDefault: true,
        sourceURL: "https://github.com/Aaronlves/Scholium"
    )

    /// The provider-managed Zotero MCP. Chat carries this non-secret default
    /// environment so the provider uses Zotero's local API backend and exposes
    /// all provider tool groups without giving Scholium a second Zotero
    /// database authority.
    public static let provider = Self(
        identifier: "zotero-mcp-provider",
        displayName: "Zotero MCP provider",
        command: "zotero-mcp",
        clientConfiguration: ZoteroMCPClientConfiguration(
            command: "zotero-mcp",
            arguments: ["serve", "--transport", "stdio"],
            environment: [
                "ZOTERO_LOCAL": "true",
                "ZOTERO_BACKEND": "api",
                "ZOTERO_MCP_TOOLSETS": "all",
            ]
        ),
        capabilities: ZoteroMCPCapability.allCases,
        localReadOnlyByDefault: false,
        sourceURL: "https://github.com/54yyyu/zotero-mcp"
    )

    public var readOnlyArguments: [String] { clientConfiguration.arguments }

    private static func unique(_ values: [ZoteroMCPCapability]) -> [ZoteroMCPCapability] {
        var seen: Set<ZoteroMCPCapability> = []
        return values.filter { seen.insert($0).inserted }
    }
}

public enum ZoteroMCPTransportState: String, Codable, Hashable, Sendable {
    case notConfigured = "not-configured"
    case commandAvailable = "command-available"
    case handshakeSucceeded = "handshake-succeeded"
    case handshakeFailed = "handshake-failed"
    case unavailable
    case notProbed = "not-probed"
}

/// A status report intentionally distinguishes local configuration from a
/// live MCP handshake. Scholium never presents a Skill file as a connection.
public struct ZoteroMCPTransportReport: Codable, Hashable, Sendable {
    public let descriptorID: String
    public let state: ZoteroMCPTransportState
    public let commandPath: String?
    public let liveHandshakePerformed: Bool
    public let serverProtocolVersion: String?
    public let serverName: String?
    public let serverVersion: String?
    public let capabilities: [String]
    public let note: String

    public init(
        descriptorID: String,
        state: ZoteroMCPTransportState,
        commandPath: String? = nil,
        liveHandshakePerformed: Bool = false,
        serverProtocolVersion: String? = nil,
        serverName: String? = nil,
        serverVersion: String? = nil,
        capabilities: [String] = [],
        note: String
    ) {
        self.descriptorID = descriptorID
        self.state = state
        self.commandPath = commandPath
        self.liveHandshakePerformed = liveHandshakePerformed
        self.serverProtocolVersion = serverProtocolVersion
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.capabilities = capabilities.sorted()
        self.note = note
    }
}
