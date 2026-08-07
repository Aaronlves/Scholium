import Foundation

public enum WindowContentDestination: String, Codable, Hashable, Sendable {
    case document
}

/// Committed presentation state for one workspace window.
/// Editor bytes remain solely in the conflict-aware document session and never
/// enter this value.
public struct WindowSessionSnapshot: Codable, Hashable, Sendable {
    public let id: UUID
    public var triptychID: UUID?
    public var vaultID: UUID?
    public var selectedDocument: VaultQualifiedNoteID?
    public var scrollPositions: [String: Double]
    public var libraryVisible: Bool?
    public var inspectorMode: String
    public var inspectorVisible: Bool?
    public var contentDestination: WindowContentDestination?
    public var searchState: SearchWorkspaceState
    public var documentTextScale: Double?

    public init(
        id: UUID = UUID(),
        triptychID: UUID? = nil,
        vaultID: UUID? = nil,
        selectedDocument: VaultQualifiedNoteID? = nil,
        scrollPositions: [String: Double] = [:],
        libraryVisible: Bool? = nil,
        inspectorMode: String = "overview",
        inspectorVisible: Bool? = nil,
        contentDestination: WindowContentDestination? = nil,
        searchState: SearchWorkspaceState = SearchWorkspaceState(),
        documentTextScale: Double? = nil
    ) {
        self.id = id
        self.triptychID = triptychID
        self.vaultID = vaultID ?? selectedDocument?.vaultID
        self.selectedDocument = selectedDocument
        self.scrollPositions = scrollPositions
        self.libraryVisible = libraryVisible
        self.inspectorMode = inspectorMode
        self.inspectorVisible = inspectorVisible
        self.contentDestination = contentDestination
        self.searchState = searchState
        self.documentTextScale = documentTextScale
    }

    /// Removes an unavailable selection without inventing a replacement.
    public func normalized(availablePaths: Set<String>) -> WindowSessionSnapshot {
        var result = self
        if let selectedDocument,
           !availablePaths.contains(selectedDocument.relativePath) {
            result.selectedDocument = nil
        }
        result.scrollPositions = scrollPositions.filter { availablePaths.contains($0.key) }
        return result
    }

    public func migratingPath(
        from sourcePath: String,
        to destinationPath: String
    ) -> WindowSessionSnapshot {
        guard let vaultID else { return self }
        return migratingPath(
            vaultID: vaultID,
            from: sourcePath,
            to: destinationPath
        )
    }

    public func migratingPath(
        vaultID: UUID,
        from sourcePath: String,
        to destinationPath: String
    ) -> WindowSessionSnapshot {
        var result = self
        if selectedDocument?.vaultID == vaultID,
           selectedDocument?.relativePath == sourcePath {
            result.selectedDocument = VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: destinationPath
            )
        }
        if selectedDocument?.vaultID == vaultID || self.vaultID == vaultID {
            if let scroll = result.scrollPositions.removeValue(forKey: sourcePath) {
                result.scrollPositions[destinationPath] = scroll
            }
        }
        return result
    }
}

public enum WindowSessionStoreError: LocalizedError, Sendable {
    case identityMismatch

    public var errorDescription: String? {
        switch self {
        case .identityMismatch:
            "The stored window session does not match the requested window."
        }
    }
}
