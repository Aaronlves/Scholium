import Foundation

public enum WindowDocumentFocusTarget: String, Codable, Hashable, Sendable {
    case title
    case editor
}

public struct WindowDocumentSelectionRange: Codable, Hashable, Sendable {
    public let anchor: Int
    public let head: Int

    public init(anchor: Int, head: Int) {
        self.anchor = anchor
        self.head = head
    }
}

/// Lightweight, source-neutral presentation for one document that remains
/// open in a window. Editor bytes and undo history never enter this value.
public struct WindowDocumentPresentationSnapshot: Codable, Hashable, Sendable {
    public var scrollFraction: Double
    public var sourceFingerprint: String?
    public var selections: [WindowDocumentSelectionRange]
    public var focusTarget: WindowDocumentFocusTarget?

    public init(
        scrollFraction: Double = 0,
        sourceFingerprint: String? = nil,
        selections: [WindowDocumentSelectionRange] = [],
        focusTarget: WindowDocumentFocusTarget? = nil
    ) {
        self.scrollFraction =
            scrollFraction.isFinite
            ? min(1, max(0, scrollFraction))
            : 0
        self.sourceFingerprint = sourceFingerprint
        self.selections = selections
        self.focusTarget = focusTarget
    }
}

/// Committed presentation state for one role workspace inside a window.
/// Editor bytes remain solely in the conflict-aware document session and never
/// enter this value.
public struct WindowWorkspaceSessionSnapshot: Codable, Hashable, Sendable {
    public let workspace: WorkspaceVaultSlot
    public var vaultID: UUID?
    public var documentPresentations: [String: WindowDocumentPresentationSnapshot]
    public var inspectorMode: String
    public var documentMode: String

    public init(
        workspace: WorkspaceVaultSlot,
        vaultID: UUID? = nil,
        documentPresentations: [String: WindowDocumentPresentationSnapshot] = [:],
        inspectorMode: String = "overview",
        documentMode: String = "read"
    ) {
        self.workspace = workspace
        self.vaultID = vaultID
        self.documentPresentations = documentPresentations
        self.inspectorMode = inspectorMode
        self.documentMode = documentMode
    }

    public func normalized(availablePaths: Set<String>) -> Self {
        var result = self
        result.documentPresentations = documentPresentations.filter {
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
        if self.vaultID == vaultID,
            let presentation = result.documentPresentations.removeValue(
                forKey: sourcePath
            )
        {
            result.documentPresentations[destinationPath] = presentation
        }
        return result
    }
}

/// Committed window-wide tab order and selection, with role-local presentation.
/// Editor bytes and Undo remain in the live document sessions.
public struct WindowSessionSnapshot: Codable, Hashable, Sendable {
    public let id: UUID
    public var triptychID: UUID?
    public var selectedWorkspace: WorkspaceVaultSlot
    public var openDocuments: [VaultQualifiedNoteID]
    public var selectedDocument: VaultQualifiedNoteID?
    public var workspaceSessions: [WindowWorkspaceSessionSnapshot]
    public var libraryVisible: Bool?
    public var inspectorVisible: Bool?
    public var searchState: SearchWorkspaceState
    public var documentTextScale: Double?

    public init(
        id: UUID = UUID(),
        triptychID: UUID? = nil,
        selectedWorkspace: WorkspaceVaultSlot = .paperAnalysis,
        openDocuments: [VaultQualifiedNoteID] = [],
        selectedDocument: VaultQualifiedNoteID? = nil,
        workspaceSessions: [WindowWorkspaceSessionSnapshot] = [],
        libraryVisible: Bool? = nil,
        inspectorVisible: Bool? = nil,
        searchState: SearchWorkspaceState = SearchWorkspaceState(),
        documentTextScale: Double? = nil
    ) {
        self.id = id
        self.triptychID = triptychID
        self.selectedWorkspace = selectedWorkspace
        self.openDocuments = openDocuments
        self.selectedDocument = selectedDocument
        self.workspaceSessions = workspaceSessions
        self.libraryVisible = libraryVisible
        self.inspectorVisible = inspectorVisible
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
        result.openDocuments = openDocuments.filter {
            availablePathsByVault[$0.vaultID]?.contains($0.relativePath) == true
        }
        if let selectedDocument, !result.openDocuments.contains(selectedDocument) {
            result.selectedDocument = nil
        }
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
        func migrated(_ document: VaultQualifiedNoteID) -> VaultQualifiedNoteID {
            guard document.vaultID == vaultID, document.relativePath == sourcePath else {
                return document
            }
            return VaultQualifiedNoteID(vaultID: vaultID, relativePath: destinationPath)
        }
        result.openDocuments = openDocuments.map(migrated)
        result.selectedDocument = selectedDocument.map(migrated)
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
