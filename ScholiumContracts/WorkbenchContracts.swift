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
    /// Search all three vaults in the active Triptych.
    case triptych
    /// Search the currently open note through the same indexed query path.
    case thisNote
    /// Search only the currently selected vault in the active Triptych.
    case currentVault

    // Read-only compatibility cases for saved searches and window snapshots
    // written before the three-scope Search contract. They are never presented
    // as selectable UI modes and are canonicalized by the window controller.
    case currentNote
    case allWorkspace
    case selectedRoles

    public var canonical: SearchPresentationScope {
        switch self {
        case .triptych, .thisNote, .currentVault: self
        case .currentNote: .thisNote
        case .allWorkspace, .selectedRoles: .triptych
        }
    }

    public static var visibleModes: [SearchPresentationScope] {
        [.thisNote, .currentVault, .triptych]
    }

    public var displayTitle: String {
        switch canonical {
        case .thisNote: "This Note"
        case .currentVault: "This Vault"
        case .triptych: "Triptych"
        default: "Triptych"
        }
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


public struct FederatedSearchGeneration: Codable, Hashable, Sendable {
    public let perVault: [UUID: IndexGeneration]
    public let publishedAt: Date

    public init(perVault: [UUID: IndexGeneration], publishedAt: Date = Date()) {
        self.perVault = perVault
        self.publishedAt = publishedAt
    }
}
