import Foundation

public struct TriptychRoots: Sendable {
    public let analyses: URL
    public let topics: URL
    public let works: URL
    public let control: URL

    public init(analyses: URL, topics: URL, works: URL, control: URL) {
        self.analyses = analyses.standardizedFileURL
        self.topics = topics.standardizedFileURL
        self.works = works.standardizedFileURL
        self.control = control.standardizedFileURL
    }

    public func url(for area: TriptychCheckpointArea) -> URL {
        switch area {
        case .analyses: analyses
        case .topics: topics
        case .works: works
        case .control: control
        }
    }
}

public enum TriptychCheckpointArea: String, Codable, CaseIterable, Sendable {
    case analyses = "Analyses"
    case topics = "Topics"
    case works = "Works"
    case control = ".scholium"

    public var vaultSlot: WorkspaceVaultSlot? {
        switch self {
        case .analyses: .paperAnalysis
        case .topics: .topicKnowledge
        case .works: .output
        case .control: nil
        }
    }
}

public enum TriptychCheckpointKind: String, Codable, Sendable {
    case automatic
    case manual
    /// Exact-note recovery owned by one independently authorized continuation
    /// run. It is not part of the rolling automatic-checkpoint retention set.
    case researchContinuation = "research_continuation"
}

public struct TriptychCheckpointFileKey: Codable, Hashable, Sendable {
    public let area: TriptychCheckpointArea
    public let relativePath: String

    public init(area: TriptychCheckpointArea, relativePath: String) {
        self.area = area
        self.relativePath = relativePath
    }
}

public struct TriptychCheckpointFile: Codable, Hashable, Sendable {
    public let key: TriptychCheckpointFileKey
    public let fingerprint: DocumentFingerprint

    public init(key: TriptychCheckpointFileKey, fingerprint: DocumentFingerprint) {
        self.key = key
        self.fingerprint = fingerprint
    }
}

public struct TriptychCheckpoint: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public let triptychID: UUID
    public let name: String
    public let kind: TriptychCheckpointKind
    public let createdAt: Date
    public let triptychFingerprint: String
    public let files: [TriptychCheckpointFile]

    public init(
        id: UUID = UUID(),
        triptychID: UUID,
        name: String,
        kind: TriptychCheckpointKind,
        createdAt: Date = Date(),
        triptychFingerprint: String,
        files: [TriptychCheckpointFile]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.triptychID = triptychID
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
        self.triptychFingerprint = triptychFingerprint
        self.files = files
    }
}

public enum TriptychCheckpointChangeKind: String, Codable, Hashable, Sendable {
    case created
    case changed
    case moved
    case deleted
    case unchanged
}

public struct TriptychCheckpointChange: Codable, Hashable, Sendable {
    public let kind: TriptychCheckpointChangeKind
    public let area: TriptychCheckpointArea
    public let checkpointPath: String?
    public let currentPath: String?
    public let checkpointFingerprint: DocumentFingerprint?
    public let currentFingerprint: DocumentFingerprint?

    public init(
        kind: TriptychCheckpointChangeKind,
        area: TriptychCheckpointArea,
        checkpointPath: String?,
        currentPath: String?,
        checkpointFingerprint: DocumentFingerprint?,
        currentFingerprint: DocumentFingerprint?
    ) {
        self.kind = kind
        self.area = area
        self.checkpointPath = checkpointPath
        self.currentPath = currentPath
        self.checkpointFingerprint = checkpointFingerprint
        self.currentFingerprint = currentFingerprint
    }
}

public enum TriptychCheckpointRestoreSelection: Sendable {
    case files(Set<TriptychCheckpointFileKey>)
    case mappedFiles(Set<TriptychCheckpointFileRestore>)
    case completeTriptych
}

public struct TriptychCheckpointFileRestore: Hashable, Sendable {
    public let source: TriptychCheckpointFileKey
    public let destination: TriptychCheckpointFileKey

    public init(source: TriptychCheckpointFileKey, destination: TriptychCheckpointFileKey) {
        self.source = source
        self.destination = destination
    }
}

public struct TriptychCheckpointRestoreResult: Sendable {
    public let recoveryCheckpoint: TriptychCheckpoint
    public let restoredFiles: [TriptychCheckpointFileKey]
    public let movedToTrash: [TriptychCheckpointFileKey]

    public init(
        recoveryCheckpoint: TriptychCheckpoint,
        restoredFiles: [TriptychCheckpointFileKey],
        movedToTrash: [TriptychCheckpointFileKey]
    ) {
        self.recoveryCheckpoint = recoveryCheckpoint
        self.restoredFiles = restoredFiles
        self.movedToTrash = movedToTrash
    }
}

public enum TriptychCheckpointError: LocalizedError, Sendable {
    case invalidName
    case invalidKind(TriptychCheckpointKind)
    case missingRoot(String)
    case symbolicLink(String)
    case invalidCheckpoint(UUID)
    case cannotDiscardManualCheckpoint(UUID)
    case corruptCheckpoint(UUID, String)
    case wrongTriptych(expected: UUID, actual: UUID)
    case invalidRelativePath(String)
    case repositoryUnavailable(TriptychCheckpointArea)
    case sourceChangedDuringCapture(String)
    case snapshotWriteFailed(String)
    case unsafeRestorePath(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName: return "A checkpoint requires a name."
        case .invalidKind(let kind):
            return "Checkpoint kind \(kind.rawValue) requires its dedicated creation boundary."
        case .missingRoot(let path): return "A Triptych location is unavailable: \(path)"
        case .symbolicLink(let path): return "Checkpoints do not follow symbolic links: \(path)"
        case .invalidCheckpoint(let id): return "Checkpoint not found or invalid: \(id.uuidString)"
        case .cannotDiscardManualCheckpoint(let id):
            return "Only a just-created automatic checkpoint may be discarded: \(id.uuidString)"
        case .corruptCheckpoint(let id, let reason):
            return "Checkpoint \(id.uuidString) failed its integrity check: \(reason)"
        case .wrongTriptych(let expected, let actual):
            return "Checkpoint belongs to Triptych \(actual.uuidString), not \(expected.uuidString)."
        case .invalidRelativePath(let path): return "Invalid checkpoint path: \(path)"
        case .repositoryUnavailable(let area): return "No repository is available for \(area.rawValue)."
        case .sourceChangedDuringCapture(let path):
            return "The Triptych changed while Scholium was creating the checkpoint: \(path). No checkpoint was kept."
        case .snapshotWriteFailed(let path):
            return "Scholium could not verify the checkpoint copy of \(path). No checkpoint was kept."
        case .unsafeRestorePath(let detail):
            return "Checkpoint restore refused an unsafe filesystem path: \(detail)"
        }
    }
}

public struct TriptychCheckpointListing: Sendable {
    public let checkpoints: [TriptychCheckpoint]
    public let unreadableEntries: [String]

    public init(checkpoints: [TriptychCheckpoint], unreadableEntries: [String]) {
        self.checkpoints = checkpoints
        self.unreadableEntries = unreadableEntries
    }
}
