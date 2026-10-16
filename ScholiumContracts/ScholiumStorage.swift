import Foundation

/// Machine-local App storage only. Agent Runtime and research source roots are
/// outside this inventory and never traversed by its reader.
public enum ScholiumStorageCategory: String, CaseIterable, Sendable {
    case temporaryFiles
    case sourceProjectionCache
    case searchIndexes
    case chatHistory
    case chatMaterials
    case researchHistory
    case recovery
    case configuration
    case unclassified
}

public struct ScholiumStorageUsage: Equatable, Sendable {
    public let category: ScholiumStorageCategory
    public let byteCount: Int64
    public let fileCount: Int
    public let unreadableEntries: Int
    public let skippedEntries: Int

    public init(
        category: ScholiumStorageCategory, byteCount: Int64, fileCount: Int,
        unreadableEntries: Int = 0, skippedEntries: Int = 0
    ) {
        self.category = category
        self.byteCount = byteCount
        self.fileCount = fileCount
        self.unreadableEntries = unreadableEntries
        self.skippedEntries = skippedEntries
    }
}

public struct ScholiumStorageInventory: Equatable, Sendable {
    public let rootURL: URL
    public let measuredAt: Date
    public let usages: [ScholiumStorageUsage]
    public let searchIndexesByTriptych: [UUID: ScholiumStorageUsage]

    public init(
        rootURL: URL, measuredAt: Date, usages: [ScholiumStorageUsage],
        searchIndexesByTriptych: [UUID: ScholiumStorageUsage] = [:]
    ) {
        self.rootURL = rootURL
        self.measuredAt = measuredAt
        self.usages = usages
        self.searchIndexesByTriptych = searchIndexesByTriptych
    }
}

public struct ScholiumStorageClearResult: Equatable, Sendable {
    public let removedFiles: Int
    public let removedBytes: Int64
    public let preservedFiles: Int
    public let failedFiles: Int
    public let busyDirectories: Int

    public init(
        removedFiles: Int = 0, removedBytes: Int64 = 0, preservedFiles: Int = 0,
        failedFiles: Int = 0, busyDirectories: Int = 0
    ) {
        self.removedFiles = removedFiles
        self.removedBytes = removedBytes
        self.preservedFiles = preservedFiles
        self.failedFiles = failedFiles
        self.busyDirectories = busyDirectories
    }
}

public enum ScholiumStorageAction: String, Sendable {
    case clearTemporaryFiles
    case clearProjectionCache
    case cleanRetiredDerivedState
    case rebuildIndex
    case clearIndex
}

public enum ScholiumStorageManagementError: Error, LocalizedError, Equatable {
    case operationInProgress
    case triptychRequired

    public var errorDescription: String? {
        switch self {
        case .operationInProgress: "Another storage operation is already running."
        case .triptychRequired: "Choose the Triptych whose index you want to manage."
        }
    }
}

public struct ScholiumStorageOperationResult: Equatable, Sendable {
    public let action: ScholiumStorageAction
    public let cleanup: ScholiumStorageClearResult
    public let warnings: [String]

    public init(
        action: ScholiumStorageAction, cleanup: ScholiumStorageClearResult = .init(), warnings: [String] = []
    ) {
        self.action = action
        self.cleanup = cleanup
        self.warnings = warnings
    }
}
