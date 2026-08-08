import Foundation

public enum WindowContentDestination: String, Codable, Hashable, Sendable {
    case document
}

/// Committed presentation state for one role workspace inside a window.
/// Editor bytes remain solely in the conflict-aware document session and never
/// enter this value.
public struct WindowWorkspaceSessionSnapshot: Codable, Hashable, Sendable {
    public let workspace: WorkspaceVaultSlot
    public var vaultID: UUID?
    public var openDocuments: [VaultQualifiedNoteID]
    public var selectedDocument: VaultQualifiedNoteID?
    public var scrollPositions: [String: Double]
    public var location: String
    public var inspectorMode: String
    public var documentMode: String

    public init(
        workspace: WorkspaceVaultSlot,
        vaultID: UUID? = nil,
        openDocuments: [VaultQualifiedNoteID] = [],
        selectedDocument: VaultQualifiedNoteID? = nil,
        scrollPositions: [String: Double] = [:],
        location: String = "workspace",
        inspectorMode: String = "overview",
        documentMode: String = "read"
    ) {
        self.workspace = workspace
        self.vaultID = vaultID
            ?? selectedDocument?.vaultID
            ?? openDocuments.first?.vaultID
        self.openDocuments = openDocuments
        self.selectedDocument = selectedDocument
        self.scrollPositions = scrollPositions
        self.location = location
        self.inspectorMode = inspectorMode
        self.documentMode = documentMode
    }

    public func normalized(availablePaths: Set<String>) -> Self {
        var result = self
        result.openDocuments = openDocuments.filter {
            availablePaths.contains($0.relativePath)
        }
        if let selectedDocument,
           !result.openDocuments.contains(selectedDocument) {
            result.selectedDocument = nil
        }
        result.scrollPositions = scrollPositions.filter {
            availablePaths.contains($0.key)
        }
        return result
    }

    public func migratingPath(
        vaultID: UUID,
        from sourcePath: String,
        to destinationPath: String
    ) -> Self {
        var result = self
        result.openDocuments = openDocuments.map { document in
            guard document.vaultID == vaultID,
                  document.relativePath == sourcePath else { return document }
            return VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: destinationPath
            )
        }
        if selectedDocument?.vaultID == vaultID,
           selectedDocument?.relativePath == sourcePath {
            result.selectedDocument = VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: destinationPath
            )
        }
        if self.vaultID == vaultID,
           let scroll = result.scrollPositions.removeValue(forKey: sourcePath) {
            result.scrollPositions[destinationPath] = scroll
        }
        return result
    }
}

/// Committed presentation state for one configured window. Each Triptych role
/// keeps its own Library, tabs, Document mode, and Inspector mode while native
/// split geometry and visibility remain window-wide.
public struct WindowSessionSnapshot: Codable, Hashable, Sendable {
    public let id: UUID
    public var triptychID: UUID?
    public var selectedWorkspace: WorkspaceVaultSlot
    public var workspaceSessions: [WindowWorkspaceSessionSnapshot]
    public var libraryVisible: Bool?
    public var inspectorVisible: Bool?
    public var contentDestination: WindowContentDestination?
    public var searchState: SearchWorkspaceState
    public var documentTextScale: Double?

    public init(
        id: UUID = UUID(),
        triptychID: UUID? = nil,
        selectedWorkspace: WorkspaceVaultSlot = .paperAnalysis,
        workspaceSessions: [WindowWorkspaceSessionSnapshot] = [],
        libraryVisible: Bool? = nil,
        inspectorVisible: Bool? = nil,
        contentDestination: WindowContentDestination? = nil,
        searchState: SearchWorkspaceState = SearchWorkspaceState(),
        documentTextScale: Double? = nil
    ) {
        self.id = id
        self.triptychID = triptychID
        self.selectedWorkspace = selectedWorkspace
        self.workspaceSessions = workspaceSessions
        self.libraryVisible = libraryVisible
        self.inspectorVisible = inspectorVisible
        self.contentDestination = contentDestination
        self.searchState = searchState
        self.documentTextScale = documentTextScale
    }

    public func workspaceSession(
        for workspace: WorkspaceVaultSlot
    ) -> WindowWorkspaceSessionSnapshot? {
        workspaceSessions.first { $0.workspace == workspace }
    }

    /// Removes unavailable documents without inventing replacement selections.
    public func normalized(
        availablePathsByVault: [UUID: Set<String>]
    ) -> WindowSessionSnapshot {
        var result = self
        result.workspaceSessions = workspaceSessions.map { session in
            guard let vaultID = session.vaultID else { return session }
            return session.normalized(
                availablePaths: availablePathsByVault[vaultID] ?? []
            )
        }
        return result
    }

    public func migratingPath(
        vaultID: UUID,
        from sourcePath: String,
        to destinationPath: String
    ) -> WindowSessionSnapshot {
        var result = self
        result.workspaceSessions = workspaceSessions.map {
            $0.migratingPath(
                vaultID: vaultID,
                from: sourcePath,
                to: destinationPath
            )
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
