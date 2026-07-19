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

}

public enum SearchPresentationScope: String, Codable, CaseIterable, Sendable {
    /// Search all three vaults in the active Triptych.
    case triptych
    /// Search the currently open note through the same indexed query path.
    case thisNote
    /// Search only the currently selected vault in the active Triptych.
    case currentVault

    public static var visibleModes: [SearchPresentationScope] {
        [.thisNote, .currentVault, .triptych]
    }

    public var displayTitle: String {
        switch self {
        case .thisNote: "This Note"
        case .currentVault: "This Vault"
        case .triptych: "Triptych"
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
