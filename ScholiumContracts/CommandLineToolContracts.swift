import Foundation

public enum CommandLineToolInstallationState: String, Codable, Hashable, Sendable {
    case bundledToolUnavailable = "bundled_tool_unavailable"
    case notInstalled = "not_installed"
    case updateAvailable = "update_available"
    case installed
    case invalidInstallation = "invalid_installation"
}

public struct CommandLineToolStatus: Codable, Hashable, Sendable {
    public let state: CommandLineToolInstallationState
    public let version: String
    public let installPath: String
    public let isOnCurrentPATH: Bool
    public let installedRevision: DocumentFingerprint?
    public let bundledRevision: DocumentFingerprint?
    public let repairMessage: String?

    public init(
        state: CommandLineToolInstallationState,
        version: String,
        installPath: String,
        isOnCurrentPATH: Bool,
        installedRevision: DocumentFingerprint? = nil,
        bundledRevision: DocumentFingerprint? = nil,
        repairMessage: String? = nil
    ) {
        self.state = state
        self.version = version
        self.installPath = installPath
        self.isOnCurrentPATH = isOnCurrentPATH
        self.installedRevision = installedRevision
        self.bundledRevision = bundledRevision
        self.repairMessage = repairMessage
    }
}

public enum CommandLineToolInstallationError: LocalizedError, Equatable, Sendable {
    case bundledToolUnavailable
    case destinationIsSymbolicLink
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .bundledToolUnavailable:
            "This Scholium build does not contain the command-line tool."
        case .destinationIsSymbolicLink:
            "The CLI destination is a symbolic link. Remove or inspect it before installing."
        case .verificationFailed:
            "The installed command-line tool did not match the bundled executable."
        }
    }
}
