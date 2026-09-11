import Foundation

/// Immutable operation and supported decision scopes; provider encoding is Application-owned.
public struct AgentChatRuntimeApproval: Sendable {
    public enum Kind: Sendable { case command, terminalInput, network, files, permissions, tool }
    public enum Decision: Sendable, Equatable { case once, turn, session, decline, cancel }
    public enum Access: String, Sendable { case read, write, deny }
    public enum Root: String, Sendable {
        case root, minimal
        case projectRoots = "project_roots"
        case temporaryDirectory = "tmpdir"
        case systemTemporaryDirectory = "slash_tmp"
    }
    public enum Path: Sendable {
        case literal(String)
        case pattern(String)
        case special(Root, subpath: String?)
    }
    public struct Rule: Sendable {
        public let access: Access
        public let path: Path
        public init(access: Access, path: Path) {
            self.access = access
            self.path = path
        }
    }
    public struct Permissions: Sendable {
        public let network: Bool?
        public let rules: [Rule]
        public let globScanMaxDepth: Int?
        public init(network: Bool?, rules: [Rule], globScanMaxDepth: Int?) {
            self.network = network
            self.rules = rules
            self.globScanMaxDepth = globScanMaxDepth
        }
    }
    public struct File: Sendable {
        public enum Kind: String, Sendable { case add, update, delete }
        public let path: String
        public let kind: Kind
        public let destination: String?
        public let diff: String
        public init(path: String, kind: Kind, destination: String?, diff: String) {
            self.path = path
            self.kind = kind
            self.destination = destination
            self.diff = diff
        }
    }
    public let kind: Kind
    public let command: String?
    public let cwd: String?
    public let environmentID: String?
    public let reason: String?
    public let networkHost: String?
    public let networkProtocol: String?
    public let permissions: Permissions?
    public let files: [File]
    public let grantRoot: String?
    public let grants: [Decision]
    public let rejection: Decision
    public let toolServer: String?
    public init(
        kind: Kind, command: String?, cwd: String?, environmentID: String?, reason: String?,
        networkHost: String?, networkProtocol: String?, permissions: Permissions?, files: [File],
        grantRoot: String?, grants: [Decision], rejection: Decision, toolServer: String? = nil
    ) {
        self.kind = kind
        self.command = command
        self.cwd = cwd
        self.environmentID = environmentID
        self.reason = reason
        self.networkHost = networkHost
        self.networkProtocol = networkProtocol
        self.permissions = permissions
        self.files = files
        self.grantRoot = grantRoot
        self.grants = grants
        self.rejection = rejection
        self.toolServer = toolServer
    }
}
