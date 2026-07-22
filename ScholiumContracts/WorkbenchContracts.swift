import Foundation
public struct SearchWorkspaceState: Codable, Hashable, Sendable {
    public var query: String
    public var scope: SearchPresentationScope

    public init(
        query: String = "",
        scope: SearchPresentationScope = .triptych
    ) {
        self.query = query
        self.scope = scope
    }

}

public enum SearchPresentationScope: String, Codable, CaseIterable, Sendable {
    /// Search all three vaults in the active Triptych.
    case triptych
    /// Search the exact current editor snapshot without saving or indexing it.
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
    public var definition: SearchDefinition
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        definition: SearchDefinition,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.definition = definition
        self.createdAt = createdAt
    }

    public var needsEditingDiagnostic: SearchQueryDiagnostic? {
        SearchQueryParser.parse(definition.query).diagnostics.first { $0.needsEditing }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, definition, state, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        if let current = try container.decodeIfPresent(
            SearchDefinition.self,
            forKey: .definition
        ) {
            definition = current
        } else {
            let legacy = try container.decode(SearchWorkspaceState.self, forKey: .state)
            definition = SearchDefinition(
                query: legacy.query,
                presentationScope: legacy.scope
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(definition, forKey: .definition)
        try container.encode(createdAt, forKey: .createdAt)
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
