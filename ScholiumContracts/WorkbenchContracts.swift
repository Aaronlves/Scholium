import Foundation
public struct SearchWorkspaceState: Codable, Hashable, Sendable {
    public var query: String
    public var scope: SearchPresentationScope
    public var providerSelection: SearchProviderSelection

    public init(
        query: String = "",
        scope: SearchPresentationScope = .triptych,
        providerSelection: SearchProviderSelection = .all
    ) {
        self.query = query
        self.scope = scope
        self.providerSelection = providerSelection
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
        if !SearchContract.isSavedSearchContractCompatible(definition.contractVersion) {
            return SearchQueryDiagnostic(
                code: .needsEditing,
                message: "This Saved Search uses Search contract \(definition.contractVersion), which is not declared compatible with contract \(SearchContract.currentVersion); review it before running.",
                utf16LowerBound: 0,
                utf16UpperBound: definition.query.utf16.count,
                needsEditing: true
            )
        }
        return SearchQueryParser.parse(definition.query).diagnostics.first { $0.needsEditing }
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
