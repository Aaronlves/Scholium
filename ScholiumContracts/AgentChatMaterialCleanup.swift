import Foundation

public struct AgentChatMaterialCleanupPlan: Equatable, Sendable {
    public let rootURL: URL
    public let candidateFileNames: [String]
    public let byteCount: Int64
    public let preservedFiles: Int
    public let revision: String
    public var fileCount: Int { candidateFileNames.count }

    package let rootIdentity: AgentChatMaterialCleanupIdentity?
    package let historyBinding: AgentChatMaterialCleanupBinding?
    package let bindings: [AgentChatMaterialCleanupBinding]

    package init(
        rootURL: URL, rootIdentity: AgentChatMaterialCleanupIdentity?, historyBinding: AgentChatMaterialCleanupBinding?,
        bindings: [AgentChatMaterialCleanupBinding], preservedFiles: Int, revision: String
    ) {
        self.rootURL = rootURL
        self.rootIdentity = rootIdentity
        self.historyBinding = historyBinding
        self.bindings = bindings
        candidateFileNames = bindings.map(\.fileName)
        byteCount = bindings.reduce(0) { $0 + $1.byteCount }
        self.preservedFiles = preservedFiles
        self.revision = revision
    }
}

package struct AgentChatMaterialCleanupIdentity: Equatable, Sendable {
    package let device: UInt64
    package let inode: UInt64
    package init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

package struct AgentChatMaterialCleanupBinding: Equatable, Sendable {
    package let fileName: String
    package let identity: AgentChatMaterialCleanupIdentity
    package let byteCount: Int64
    package let modifiedSeconds: Int64
    package let modifiedNanoseconds: Int64
    package let changedSeconds: Int64
    package let changedNanoseconds: Int64
    package let digest: String

    package init(
        fileName: String, identity: AgentChatMaterialCleanupIdentity, byteCount: Int64,
        modifiedSeconds: Int64, modifiedNanoseconds: Int64,
        changedSeconds: Int64, changedNanoseconds: Int64, digest: String
    ) {
        self.fileName = fileName
        self.identity = identity
        self.byteCount = byteCount
        self.modifiedSeconds = modifiedSeconds
        self.modifiedNanoseconds = modifiedNanoseconds
        self.changedSeconds = changedSeconds
        self.changedNanoseconds = changedNanoseconds
        self.digest = digest
    }
}

public struct AgentChatMaterialCleanupResult: Equatable, Sendable {
    public let movedFiles: Int
    public let movedBytes: Int64
    public let preservedFiles: Int
    public let failedFiles: Int
    public let uncertainFiles: Int
    public let uncertainFileNames: [String]
    public let wasCancelled: Bool
    public let rootURL: URL?
    /// Recoverable copies still in App storage; no failed transfer is unlinked.
    public let retainedFileNames: [String]
    public let resultingTrashURLs: [URL]

    public init(
        movedFiles: Int = 0, movedBytes: Int64 = 0, preservedFiles: Int = 0,
        failedFiles: Int = 0, uncertainFiles: Int = 0, uncertainFileNames: [String] = [],
        wasCancelled: Bool = false, rootURL: URL? = nil,
        retainedFileNames: [String] = [], resultingTrashURLs: [URL] = []
    ) {
        self.movedFiles = movedFiles
        self.movedBytes = movedBytes
        self.preservedFiles = preservedFiles
        self.failedFiles = failedFiles
        self.uncertainFiles = uncertainFiles
        self.uncertainFileNames = uncertainFileNames
        self.wasCancelled = wasCancelled
        self.rootURL = rootURL
        self.retainedFileNames = retainedFileNames
        self.resultingTrashURLs = resultingTrashURLs
    }
}

public enum AgentChatMaterialCleanupError: Error, LocalizedError, Equatable {
    case invalidRoot
    case changed

    public var errorDescription: String? {
        switch self {
        case .invalidRoot: "The managed Chat-material folder is unavailable or unsafe."
        case .changed: "Chat materials changed. Refresh the cleanup preview before trying again."
        }
    }
}
