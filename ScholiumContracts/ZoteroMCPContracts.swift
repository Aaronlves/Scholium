import Foundation

public enum ZoteroMCPCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case status
    case search
    case itemInspection = "item-inspection"
    case attachmentPointers = "attachment-pointers"
    case selectedTarget = "selected-target"
    case bibtexImport = "bibtex-import"
    case risImport = "ris-import"
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

/// The release-supported installation path for external-agent Zotero access.
/// This describes Scholium's first-party CLI transport; it is not a claim that
/// the Markdown Skill itself can reach Zotero.
public struct ZoteroMCPTransportDescriptor: Codable, Hashable, Sendable {
    public let identifier: String
    public let displayName: String
    public let command: String
    public let installationCommand: String
    public let setupCommand: String
    public let clientConfiguration: ZoteroMCPClientConfiguration
    public let capabilities: [ZoteroMCPCapability]
    public let localReadOnlyByDefault: Bool
    public let importsRequireWebAPICredentials: Bool
    public let importsUseLocalConnector: Bool
    public let importsRequireDryRunAndConfirmation: Bool
    public let importsRequireReadBackVerification: Bool
    public let sourceURL: String

    public init(
        identifier: String,
        displayName: String,
        command: String,
        installationCommand: String,
        setupCommand: String,
        clientConfiguration: ZoteroMCPClientConfiguration,
        capabilities: [ZoteroMCPCapability],
        localReadOnlyByDefault: Bool,
        importsRequireWebAPICredentials: Bool,
        importsUseLocalConnector: Bool = false,
        importsRequireDryRunAndConfirmation: Bool,
        importsRequireReadBackVerification: Bool = true,
        sourceURL: String
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.command = command
        self.installationCommand = installationCommand
        self.setupCommand = setupCommand
        self.clientConfiguration = clientConfiguration
        self.capabilities = Self.unique(capabilities)
        self.localReadOnlyByDefault = localReadOnlyByDefault
        self.importsRequireWebAPICredentials = importsRequireWebAPICredentials
        self.importsUseLocalConnector = importsUseLocalConnector
        self.importsRequireDryRunAndConfirmation = importsRequireDryRunAndConfirmation
        self.importsRequireReadBackVerification = importsRequireReadBackVerification
        self.sourceURL = sourceURL
    }

    public static let supportedLocal = Self(
        identifier: "scholium-zotero-mcp",
        displayName: "Scholium Zotero MCP",
        command: "scholium",
        installationCommand: "Tools/Scripts/install-cli.sh",
        setupCommand: "export PATH=\"$HOME/.local/bin:$PATH\"",
        clientConfiguration: ZoteroMCPClientConfiguration(
            command: "scholium",
            arguments: ["zotero", "mcp", "serve"]
        ),
        capabilities: ZoteroMCPCapability.allCases,
        localReadOnlyByDefault: true,
        importsRequireWebAPICredentials: false,
        importsUseLocalConnector: true,
        importsRequireDryRunAndConfirmation: true,
        importsRequireReadBackVerification: true,
        sourceURL: "https://github.com/Aaronlves/Scholium"
    )

    public var supportsGuardedImports: Bool {
        capabilities.contains(.bibtexImport)
            && capabilities.contains(.risImport)
            && (importsUseLocalConnector || importsRequireWebAPICredentials)
            && importsRequireDryRunAndConfirmation
            && importsRequireReadBackVerification
    }

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
