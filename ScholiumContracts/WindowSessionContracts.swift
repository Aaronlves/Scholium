import Foundation

public enum WindowContentDestination: String, Codable, Hashable, Sendable {
    case document

    /// Historical snapshots used `home`, `search`, and `canvas` for
    /// full-document surfaces that are no longer part of Scholium.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case Self.document.rawValue, "home", "search", "canvas":
            self = .document
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown window content destination: \(raw)"
            )
        }
    }
}

/// Committed presentation state for one complete native-tab window session.
///
/// Exactly one vault-qualified document may be restored. Historical custom
/// tabs, Back/Forward visits, and Recent Notes are accepted only while
/// decoding and are never written again. Editor bytes remain solely in the
/// conflict-aware document session and never enter this value.
public struct WindowSessionSnapshot: Codable, Hashable, Sendable {
    public let id: UUID
    public var triptychID: UUID?
    public var vaultID: UUID?
    public var selectedDocument: VaultQualifiedNoteID?
    public var documentModes: [String: String]
    public var scrollPositions: [String: Double]
    public var inspectorMode: String
    public var inspectorVisible: Bool?
    public var contentDestination: WindowContentDestination?
    public var searchState: SearchWorkspaceState
    public var documentTextScale: Double?
    private var legacySelectionFallbacks: [VaultQualifiedNoteID]

    public init(
        id: UUID = UUID(),
        triptychID: UUID? = nil,
        vaultID: UUID? = nil,
        selectedDocument: VaultQualifiedNoteID? = nil,
        documentModes: [String: String] = [:],
        scrollPositions: [String: Double] = [:],
        inspectorMode: String = "incoming",
        inspectorVisible: Bool? = nil,
        contentDestination: WindowContentDestination? = nil,
        searchState: SearchWorkspaceState = SearchWorkspaceState(),
        documentTextScale: Double? = nil
    ) {
        self.id = id
        self.triptychID = triptychID
        self.vaultID = vaultID ?? selectedDocument?.vaultID
        self.selectedDocument = selectedDocument
        self.documentModes = documentModes
        self.scrollPositions = scrollPositions
        self.inspectorMode = inspectorMode
        self.inspectorVisible = inspectorVisible
        self.contentDestination = contentDestination
        self.searchState = searchState
        self.documentTextScale = documentTextScale
        legacySelectionFallbacks = []
    }

    private struct LegacyVaultPresentation: Decodable {
        let vaultID: UUID
        let openTabs: [String]
        let activeTab: String?

        private enum CodingKeys: String, CodingKey {
            case vaultID
            case openTabs
            case activeTab
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            vaultID = try container.decode(UUID.self, forKey: .vaultID)
            openTabs = try container.decodeIfPresent([String].self, forKey: .openTabs) ?? []
            activeTab = try container.decodeIfPresent(String.self, forKey: .activeTab)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case triptychID
        case vaultID
        case selectedDocument
        case documentModes
        case scrollPositions
        case inspectorMode
        case inspectorVisible
        case contentDestination
        case searchState
        case documentTextScale

        // Decode-only compatibility keys.
        case openTabs
        case activeTab
        case vaultPresentations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVaultID = try container.decodeIfPresent(UUID.self, forKey: .vaultID)
        let legacyActiveTab = try container.decodeIfPresent(String.self, forKey: .activeTab)
        let legacyOpenTabs = try container.decodeIfPresent([String].self, forKey: .openTabs) ?? []
        let legacyPresentations = try container.decodeIfPresent(
            [LegacyVaultPresentation].self,
            forKey: .vaultPresentations
        ) ?? []

        var decodedSelection = try container.decodeIfPresent(
            VaultQualifiedNoteID.self,
            forKey: .selectedDocument
        )
        var legacyFallbacks: [VaultQualifiedNoteID] = []
        if decodedSelection == nil, let decodedVaultID {
            let presentation = legacyPresentations.last(where: { $0.vaultID == decodedVaultID })
            var orderedPaths = [legacyActiveTab].compactMap { $0 }
            orderedPaths.append(contentsOf: legacyOpenTabs.reversed())
            if let active = presentation?.activeTab { orderedPaths.append(active) }
            if let openTabs = presentation?.openTabs {
                orderedPaths.append(contentsOf: openTabs.reversed())
            }
            let candidates = orderedPaths.reduce(into: [String]()) {
                    if !$0.contains($1) { $0.append($1) }
                }
            let references = candidates.map {
                VaultQualifiedNoteID(vaultID: decodedVaultID, relativePath: $0)
            }
            decodedSelection = references.first
            legacyFallbacks = Array(references.dropFirst())
        }

        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            triptychID: try container.decodeIfPresent(UUID.self, forKey: .triptychID),
            vaultID: decodedVaultID,
            selectedDocument: decodedSelection,
            documentModes: try container.decodeIfPresent(
                [String: String].self,
                forKey: .documentModes
            ) ?? [:],
            scrollPositions: try container.decodeIfPresent(
                [String: Double].self,
                forKey: .scrollPositions
            ) ?? [:],
            inspectorMode: try container.decodeIfPresent(
                String.self,
                forKey: .inspectorMode
            ) ?? "incoming",
            inspectorVisible: try container.decodeIfPresent(Bool.self, forKey: .inspectorVisible),
            contentDestination: try container.decodeIfPresent(
                WindowContentDestination.self,
                forKey: .contentDestination
            ),
            searchState: try container.decodeIfPresent(
                SearchWorkspaceState.self,
                forKey: .searchState
            ) ?? SearchWorkspaceState(),
            documentTextScale: try container.decodeIfPresent(
                Double.self,
                forKey: .documentTextScale
            )
        )
        legacySelectionFallbacks = legacyFallbacks
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(triptychID, forKey: .triptychID)
        try container.encodeIfPresent(vaultID, forKey: .vaultID)
        try container.encodeIfPresent(selectedDocument, forKey: .selectedDocument)
        try container.encode(documentModes, forKey: .documentModes)
        try container.encode(scrollPositions, forKey: .scrollPositions)
        try container.encode(inspectorMode, forKey: .inspectorMode)
        try container.encodeIfPresent(inspectorVisible, forKey: .inspectorVisible)
        try container.encodeIfPresent(contentDestination, forKey: .contentDestination)
        try container.encode(searchState, forKey: .searchState)
        try container.encodeIfPresent(documentTextScale, forKey: .documentTextScale)
    }

    /// Removes an unavailable selection without inventing a replacement.
    public func normalized(availablePaths: Set<String>) -> WindowSessionSnapshot {
        var result = self
        if let selectedDocument,
           !availablePaths.contains(selectedDocument.relativePath) {
            result.selectedDocument = legacySelectionFallbacks.first {
                $0.vaultID == selectedDocument.vaultID
                    && availablePaths.contains($0.relativePath)
            }
        }
        result.legacySelectionFallbacks = []
        result.documentModes = documentModes.filter { availablePaths.contains($0.key) }
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
        } else if legacySelectionFallbacks.contains(where: {
            $0.vaultID == vaultID && $0.relativePath == sourcePath
        }) {
            // A confirmed identity move proves that this decode-only fallback
            // names a real note. Promote the moved candidate so saving the
            // modern single-selection snapshot cannot silently discard it.
            result.selectedDocument = VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: destinationPath
            )
        }
        result.legacySelectionFallbacks = legacySelectionFallbacks.compactMap { candidate in
            guard candidate.vaultID == vaultID,
                  candidate.relativePath == sourcePath else { return candidate }
            let migrated = VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: destinationPath
            )
            return migrated == result.selectedDocument ? nil : migrated
        }
        if selectedDocument?.vaultID == vaultID || self.vaultID == vaultID {
            if let mode = result.documentModes.removeValue(forKey: sourcePath) {
                result.documentModes[destinationPath] = mode
            }
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
