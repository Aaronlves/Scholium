import Foundation

public struct SearchWorkspaceState: Codable, Hashable, Sendable {
    public var query: String
    public var scope: SearchPresentationScope
    public var selectedRoles: Set<VaultRole>
    public var selectedResultID: String?

    public init(
        query: String = "",
        scope: SearchPresentationScope = .triptych,
        selectedRoles: Set<VaultRole> = [],
        selectedResultID: String? = nil
    ) {
        self.query = query
        self.scope = scope
        self.selectedRoles = selectedRoles
        self.selectedResultID = selectedResultID
    }

    private enum CodingKeys: String, CodingKey {
        case query
        case scope
        case selectedRoles
        case selectedResultID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            query: try container.decodeIfPresent(String.self, forKey: .query) ?? "",
            scope: try container.decodeIfPresent(SearchPresentationScope.self, forKey: .scope) ?? .triptych,
            selectedRoles: try container.decodeIfPresent(Set<VaultRole>.self, forKey: .selectedRoles) ?? [],
            selectedResultID: try container.decodeIfPresent(String.self, forKey: .selectedResultID)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(query, forKey: .query)
        try container.encode(scope, forKey: .scope)
        try container.encode(selectedRoles, forKey: .selectedRoles)
        try container.encodeIfPresent(selectedResultID, forKey: .selectedResultID)
    }
}

public enum SearchPresentationScope: String, Codable, CaseIterable, Sendable {
    /// The active Analyses, Topics, or Works segment selects the searched
    /// Triptych vault. This is the only workspace-wide search mode.
    case triptych
    /// Search the currently open note through the same indexed query path.
    case thisNote

    // Read-only compatibility cases for saved searches and window snapshots
    // written before the unified Search contract. They are never presented as
    // selectable UI modes and are canonicalized by AppState.
    case currentNote
    case currentVault
    case allWorkspace
    case selectedRoles

    public var canonical: SearchPresentationScope {
        switch self {
        case .triptych, .thisNote: self
        case .currentNote: .thisNote
        case .currentVault, .allWorkspace, .selectedRoles: .triptych
        }
    }

    public static var visibleModes: [SearchPresentationScope] {
        [.triptych, .thisNote]
    }
}

public struct SavedSearch: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var state: SearchWorkspaceState
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, state: SearchWorkspaceState, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.state = state
        self.createdAt = createdAt
    }
}

public enum SavedSearchStoreError: LocalizedError, Sendable {
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let reason):
            "Scholium could not safely load Saved Searches. The existing file was left unchanged. \(reason)"
        }
    }
}

/// Persists researcher-created search definitions outside every vault.
public actor SavedSearchStore {
    private let fileURL: URL
    private var loadFailure: String?

    public init(workspaceStorageURL: URL) {
        fileURL = workspaceStorageURL.appendingPathComponent("saved-searches.json", isDirectory: false)
    }

    public func load() throws -> [SavedSearch] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            loadFailure = nil
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            // Array order is researcher-defined presentation state. Preserve
            // the persisted order instead of silently sorting by creation date.
            let searches = try JSONDecoder.scholium.decode([SavedSearch].self, from: data)
            loadFailure = nil
            return searches
        } catch {
            loadFailure = error.localizedDescription
            throw SavedSearchStoreError.unreadable(error.localizedDescription)
        }
    }

    public func save(_ searches: [SavedSearch]) throws {
        if let loadFailure { throw SavedSearchStoreError.unreadable(loadFailure) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder.scholium.encode(searches).write(to: fileURL, options: .atomic)
    }
}

public struct FederatedSearchGeneration: Codable, Hashable, Sendable {
    public let perVault: [UUID: IndexGeneration]
    public let publishedAt: Date

    public init(perVault: [UUID: IndexGeneration], publishedAt: Date = Date()) {
        self.perVault = perVault
        self.publishedAt = publishedAt
    }
}

public enum CanvasEdgeOrigin: String, Codable, Sendable {
    case derivedRelationship
    case canvasAnnotation
}

public struct CanvasPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct CanvasViewport: Codable, Hashable, Sendable {
    public var offset: CanvasPoint
    public var scale: Double
    public init(offset: CanvasPoint = .init(x: 100, y: 100), scale: Double = 1) {
        self.offset = offset
        self.scale = scale
    }
}

public struct CanvasNode: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let relativePath: String
    public var position: CanvasPoint
    public var sourceLine: Int?

    public init(id: UUID = UUID(), relativePath: String, position: CanvasPoint, sourceLine: Int? = nil) {
        self.id = id
        self.relativePath = relativePath
        self.position = position
        self.sourceLine = sourceLine
    }
}

public struct CanvasEdge: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let subjectNodeID: UUID
    public let objectNodeID: UUID
    public var predicate: String
    public let origin: CanvasEdgeOrigin

    public init(
        id: UUID = UUID(),
        subjectNodeID: UUID,
        objectNodeID: UUID,
        predicate: String,
        origin: CanvasEdgeOrigin = .canvasAnnotation
    ) {
        self.id = id
        self.subjectNodeID = subjectNodeID
        self.objectNodeID = objectNodeID
        self.predicate = predicate
        self.origin = origin
    }
}

public struct NamedCanvas: Codable, Hashable, Identifiable, Sendable {
    public static let formatVersion = 1
    public let formatVersion: Int
    public let id: UUID
    public var name: String
    public var nodes: [CanvasNode]
    public var edges: [CanvasEdge]
    public var viewport: CanvasViewport
    public var visiblePredicates: Set<String>
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        nodes: [CanvasNode] = [],
        edges: [CanvasEdge] = [],
        viewport: CanvasViewport = .init(),
        visiblePredicates: Set<String> = [],
        updatedAt: Date = Date()
    ) {
        self.formatVersion = Self.formatVersion
        self.id = id
        self.name = name
        self.nodes = nodes
        self.edges = edges
        self.viewport = viewport
        self.visiblePredicates = visiblePredicates
        self.updatedAt = updatedAt
    }
}

public actor NamedCanvasStore {
    private let directoryURL: URL

    public init(vaultStorageURL: URL) {
        directoryURL = vaultStorageURL.appendingPathComponent("canvases", isDirectory: true)
    }

    public func list() throws -> [NamedCanvas] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .compactMap { try? JSONDecoder.scholium.decode(NamedCanvas.self, from: Data(contentsOf: $0)) }
        .sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func save(_ canvas: NamedCanvas) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var updated = canvas
        updated.updatedAt = Date()
        let target = directoryURL.appendingPathComponent(updated.id.uuidString.lowercased() + ".json")
        try JSONEncoder.scholium.encode(updated).write(to: target, options: .atomic)
    }

    /// Rebinds every persisted Canvas node that points at a confirmed moved
    /// note. Canvas-only edges retain their node identities and therefore need
    /// no separate rewrite.
    @discardableResult
    public func moveNotePath(from sourcePath: String, to destinationPath: String) throws -> [NamedCanvas] {
        var changed: [NamedCanvas] = []
        for var canvas in try list() where canvas.nodes.contains(where: { $0.relativePath == sourcePath }) {
            canvas.nodes = canvas.nodes.map { node in
                guard node.relativePath == sourcePath else { return node }
                return CanvasNode(
                    id: node.id,
                    relativePath: destinationPath,
                    position: node.position,
                    sourceLine: node.sourceLine
                )
            }
            try save(canvas)
            changed.append(canvas)
        }
        return changed
    }
}

private extension JSONEncoder {
    static var scholium: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var scholium: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
