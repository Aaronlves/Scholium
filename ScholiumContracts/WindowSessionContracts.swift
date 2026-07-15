import Foundation

public enum WindowContentDestination: String, Codable, Hashable, Sendable {
    case document

    /// Historical snapshots used `home`, `search`, and `canvas` for
    /// full-document surfaces that are no longer part of Scholium. Decode
    /// every retired value as the document surface without retaining or
    /// writing the retired state.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case Self.document.rawValue:
            self = .document
        case "home", "search", "canvas":
            self = .document
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown window content destination: \(raw)"
            )
        }
    }
}

/// Vault-qualified, most-recent-first document navigation for one window.
///
/// This is intentionally distinct from chronological Back/Forward history.
/// Reopening an existing note promotes it without creating a duplicate, and
/// the bounded value remains useful even when derived search state is absent.
public struct WindowRecentNotes: Codable, Hashable, Sendable {
    public static let maximumCount = 10

    public private(set) var references: [VaultQualifiedNoteID]

    public init(references: [VaultQualifiedNoteID] = []) {
        self.references = Self.unique(references, limit: Self.maximumCount)
    }

    public mutating func record(_ reference: VaultQualifiedNoteID) {
        references.removeAll { $0 == reference }
        references.insert(reference, at: 0)
        if references.count > Self.maximumCount {
            references.removeLast(references.count - Self.maximumCount)
        }
    }

    public mutating func removeAll() {
        references.removeAll()
    }

    public func restricted(to allowedVaultIDs: Set<UUID>) -> Self {
        Self(references: references.filter { allowedVaultIDs.contains($0.vaultID) })
    }

    /// Removes unavailable paths only for the vault whose contents were
    /// authoritatively scanned. Peer-vault entries remain untouched.
    public func normalized(vaultID: UUID, availablePaths: Set<String>) -> Self {
        Self(references: references.filter { reference in
            reference.vaultID != vaultID || availablePaths.contains(reference.relativePath)
        })
    }

    public func removing(vaultID: UUID, paths: Set<String>) -> Self {
        Self(references: references.filter { reference in
            reference.vaultID != vaultID || !paths.contains(reference.relativePath)
        })
    }

    public func migratingPath(
        vaultID: UUID,
        from sourcePath: String,
        to destinationPath: String
    ) -> Self {
        Self(references: references.map { reference in
            guard reference.vaultID == vaultID,
                  reference.relativePath == sourcePath else { return reference }
            return VaultQualifiedNoteID(vaultID: vaultID, relativePath: destinationPath)
        })
    }

    private static func unique(
        _ references: [VaultQualifiedNoteID],
        limit: Int
    ) -> [VaultQualifiedNoteID] {
        var seen: Set<VaultQualifiedNoteID> = []
        return Array(references.filter { seen.insert($0).inserted }.prefix(limit))
    }
}

/// Document presentation owned by one window for one vault in its Triptych.
///
/// Paths are intentionally relative to `vaultID`. Keeping this projection
/// separate for each peer vault lets Analyses, Topics, and Works retain their
/// own bounded tabs, modes, and scroll positions while Back/Forward traverses
/// vault-qualified visits.
public struct WindowVaultPresentationSnapshot: Codable, Hashable, Sendable {
    public let vaultID: UUID
    public var openTabs: [String]
    public var activeTab: String?
    public var documentModes: [String: String]
    public var scrollPositions: [String: Double]

    public init(
        vaultID: UUID,
        openTabs: [String] = [],
        activeTab: String? = nil,
        documentModes: [String: String] = [:],
        scrollPositions: [String: Double] = [:]
    ) {
        self.vaultID = vaultID
        self.openTabs = openTabs
        self.activeTab = activeTab
        self.documentModes = documentModes
        self.scrollPositions = scrollPositions
    }

    private enum CodingKeys: String, CodingKey {
        case vaultID
        case openTabs
        case activeTab
        case documentModes
        case scrollPositions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            vaultID: try container.decode(UUID.self, forKey: .vaultID),
            openTabs: try container.decodeIfPresent([String].self, forKey: .openTabs) ?? [],
            activeTab: try container.decodeIfPresent(String.self, forKey: .activeTab),
            documentModes: try container.decodeIfPresent(
                [String: String].self,
                forKey: .documentModes
            ) ?? [:],
            scrollPositions: try container.decodeIfPresent(
                [String: Double].self,
                forKey: .scrollPositions
            ) ?? [:]
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vaultID, forKey: .vaultID)
        try container.encode(openTabs, forKey: .openTabs)
        try container.encodeIfPresent(activeTab, forKey: .activeTab)
        try container.encode(documentModes, forKey: .documentModes)
        try container.encode(scrollPositions, forKey: .scrollPositions)
    }

    public func normalized(availablePaths: Set<String>) -> Self {
        var result = self
        result.openTabs = unique(openTabs.filter(availablePaths.contains))
        if let activeTab, availablePaths.contains(activeTab) {
            result.activeTab = activeTab
            if !result.openTabs.contains(activeTab) { result.openTabs.append(activeTab) }
        } else {
            result.activeTab = result.openTabs.last
        }
        result.documentModes = documentModes.filter { availablePaths.contains($0.key) }
        result.scrollPositions = scrollPositions.filter { availablePaths.contains($0.key) }
        return result
    }

    public func migratingPath(from sourcePath: String, to destinationPath: String) -> Self {
        var result = self
        result.openTabs = unique(openTabs.map { $0 == sourcePath ? destinationPath : $0 })
        if result.activeTab == sourcePath { result.activeTab = destinationPath }
        if let mode = result.documentModes.removeValue(forKey: sourcePath) {
            result.documentModes[destinationPath] = mode
        }
        if let scroll = result.scrollPositions.removeValue(forKey: sourcePath) {
            result.scrollPositions[destinationPath] = scroll
        }
        return result
    }

    private func unique(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.filter { seen.insert($0).inserted }
    }
}

/// Committed presentation state for one Scholium window.
///
/// This type intentionally contains note identities and presentation choices,
/// never an editor buffer. Markdown bytes remain authoritative only after a
/// successful `VaultRepository` save.
public struct WindowSessionSnapshot: Codable, Hashable, Sendable {
    public let id: UUID
    /// The complete Triptych selected by this window. Older snapshots omit
    /// this value and restore through the registry's compatibility default.
    public var triptychID: UUID?
    public var vaultID: UUID?
    public var openTabs: [String]
    public var activeTab: String?
    public var navigationHistory: [String]
    public var navigationIndex: Int
    public var documentModes: [String: String]
    public var scrollPositions: [String: Double]
    public var inspectorMode: String
    public var inspectorVisible: Bool?
    public var contentDestination: WindowContentDestination?
    public var searchState: SearchWorkspaceState
    /// Per-window document-only scale. Optional for snapshots written before
    /// reader/editor scaling was introduced.
    public var documentTextScale: Double?
    /// Vault-qualified visits used by current builds. `navigationHistory`
    /// remains as a single-vault compatibility field for older snapshots.
    public var qualifiedNavigationHistory: [VaultQualifiedNoteID]?
    public var qualifiedNavigationIndex: Int?
    /// Per-window, vault-qualified MRU navigation. Optional so snapshots
    /// written before Recent Notes remain decodable without migration.
    public var recentNotes: WindowRecentNotes?
    /// Per-vault tab and document presentation. Optional so sessions written
    /// before peer-vault preservation remain decodable.
    public var vaultPresentations: [WindowVaultPresentationSnapshot]?

    public init(
        id: UUID = UUID(),
        triptychID: UUID? = nil,
        vaultID: UUID? = nil,
        openTabs: [String] = [],
        activeTab: String? = nil,
        navigationHistory: [String] = [],
        navigationIndex: Int = -1,
        documentModes: [String: String] = [:],
        scrollPositions: [String: Double] = [:],
        inspectorMode: String = "incoming",
        inspectorVisible: Bool? = nil,
        contentDestination: WindowContentDestination? = nil,
        searchState: SearchWorkspaceState = SearchWorkspaceState(),
        documentTextScale: Double? = nil,
        qualifiedNavigationHistory: [VaultQualifiedNoteID]? = nil,
        qualifiedNavigationIndex: Int? = nil,
        recentNotes: WindowRecentNotes? = nil,
        vaultPresentations: [WindowVaultPresentationSnapshot]? = nil
    ) {
        self.id = id
        self.triptychID = triptychID
        self.vaultID = vaultID
        self.openTabs = openTabs
        self.activeTab = activeTab
        self.navigationHistory = navigationHistory
        self.navigationIndex = navigationIndex
        self.documentModes = documentModes
        self.scrollPositions = scrollPositions
        self.inspectorMode = inspectorMode
        self.inspectorVisible = inspectorVisible
        self.contentDestination = contentDestination
        self.searchState = searchState
        self.documentTextScale = documentTextScale
        self.qualifiedNavigationHistory = qualifiedNavigationHistory
        self.qualifiedNavigationIndex = qualifiedNavigationIndex
        self.recentNotes = recentNotes
        self.vaultPresentations = vaultPresentations
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case triptychID
        case vaultID
        case openTabs
        case activeTab
        case navigationHistory
        case navigationIndex
        case documentModes
        case scrollPositions
        case inspectorMode
        case inspectorVisible
        case contentDestination
        case searchState
        case documentTextScale
        case qualifiedNavigationHistory
        case qualifiedNavigationIndex
        case recentNotes
        case vaultPresentations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            triptychID: try container.decodeIfPresent(UUID.self, forKey: .triptychID),
            vaultID: try container.decodeIfPresent(UUID.self, forKey: .vaultID),
            openTabs: try container.decodeIfPresent([String].self, forKey: .openTabs) ?? [],
            activeTab: try container.decodeIfPresent(String.self, forKey: .activeTab),
            navigationHistory: try container.decodeIfPresent(
                [String].self,
                forKey: .navigationHistory
            ) ?? [],
            navigationIndex: try container.decodeIfPresent(Int.self, forKey: .navigationIndex) ?? -1,
            documentModes: try container.decodeIfPresent(
                [String: String].self,
                forKey: .documentModes
            ) ?? [:],
            scrollPositions: try container.decodeIfPresent(
                [String: Double].self,
                forKey: .scrollPositions
            ) ?? [:],
            inspectorMode: try container.decodeIfPresent(String.self, forKey: .inspectorMode) ?? "incoming",
            inspectorVisible: try container.decodeIfPresent(Bool.self, forKey: .inspectorVisible),
            contentDestination: try container.decodeIfPresent(
                WindowContentDestination.self,
                forKey: .contentDestination
            ),
            searchState: try container.decodeIfPresent(
                SearchWorkspaceState.self,
                forKey: .searchState
            ) ?? SearchWorkspaceState(),
            documentTextScale: try container.decodeIfPresent(Double.self, forKey: .documentTextScale),
            qualifiedNavigationHistory: try container.decodeIfPresent(
                [VaultQualifiedNoteID].self,
                forKey: .qualifiedNavigationHistory
            ),
            qualifiedNavigationIndex: try container.decodeIfPresent(
                Int.self,
                forKey: .qualifiedNavigationIndex
            ),
            recentNotes: try container.decodeIfPresent(
                WindowRecentNotes.self,
                forKey: .recentNotes
            ),
            vaultPresentations: try container.decodeIfPresent(
                [WindowVaultPresentationSnapshot].self,
                forKey: .vaultPresentations
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(triptychID, forKey: .triptychID)
        try container.encodeIfPresent(vaultID, forKey: .vaultID)
        try container.encode(openTabs, forKey: .openTabs)
        try container.encodeIfPresent(activeTab, forKey: .activeTab)
        try container.encode(navigationHistory, forKey: .navigationHistory)
        try container.encode(navigationIndex, forKey: .navigationIndex)
        try container.encode(documentModes, forKey: .documentModes)
        try container.encode(scrollPositions, forKey: .scrollPositions)
        try container.encode(inspectorMode, forKey: .inspectorMode)
        try container.encodeIfPresent(inspectorVisible, forKey: .inspectorVisible)
        try container.encodeIfPresent(contentDestination, forKey: .contentDestination)
        try container.encode(searchState, forKey: .searchState)
        try container.encodeIfPresent(documentTextScale, forKey: .documentTextScale)
        try container.encodeIfPresent(qualifiedNavigationHistory, forKey: .qualifiedNavigationHistory)
        try container.encodeIfPresent(qualifiedNavigationIndex, forKey: .qualifiedNavigationIndex)
        try container.encodeIfPresent(recentNotes, forKey: .recentNotes)
        try container.encodeIfPresent(vaultPresentations, forKey: .vaultPresentations)
    }

    /// Removes paths that no longer exist without inventing a replacement
    /// document or restoring uncommitted bytes.
    public func normalized(availablePaths: Set<String>) -> WindowSessionSnapshot {
        var result = self
        let currentHistoryPath = navigationHistory.indices.contains(navigationIndex)
            ? navigationHistory[navigationIndex]
            : nil
        result.openTabs = unique(openTabs.filter(availablePaths.contains))
        result.navigationHistory = navigationHistory.filter(availablePaths.contains)
        if let currentHistoryPath,
           let restoredIndex = result.navigationHistory.lastIndex(of: currentHistoryPath) {
            result.navigationIndex = restoredIndex
        } else {
            result.navigationIndex = result.navigationHistory.isEmpty
                ? -1
                : min(max(0, navigationIndex), result.navigationHistory.count - 1)
        }
        if let activeTab, availablePaths.contains(activeTab) {
            result.activeTab = activeTab
            if !result.openTabs.contains(activeTab) { result.openTabs.append(activeTab) }
        } else {
            result.activeTab = result.openTabs.last
        }
        result.documentModes = documentModes.filter { availablePaths.contains($0.key) }
        result.scrollPositions = scrollPositions.filter { availablePaths.contains($0.key) }
        if let vaultID {
            result.recentNotes = recentNotes?.normalized(
                vaultID: vaultID,
                availablePaths: availablePaths
            )
            result.vaultPresentations = vaultPresentations?.map { presentation in
                presentation.vaultID == vaultID
                    ? presentation.normalized(availablePaths: availablePaths)
                    : presentation
            }
            if let qualifiedNavigationHistory {
                let oldIndex = qualifiedNavigationIndex ?? navigationIndex
                var history: [VaultQualifiedNoteID] = []
                var restoredIndex = -1
                for (index, reference) in qualifiedNavigationHistory.enumerated() {
                    if reference.vaultID == vaultID,
                       !availablePaths.contains(reference.relativePath) {
                        continue
                    }
                    history.append(reference)
                    if index <= oldIndex { restoredIndex = history.count - 1 }
                }
                result.qualifiedNavigationHistory = history
                result.qualifiedNavigationIndex = history.isEmpty
                    ? -1
                    : min(max(0, restoredIndex), history.count - 1)
            }
        }
        return result
    }

    /// Preserves presentation state when a stable note identity receives a new
    /// path. No editor buffer is stored or migrated here.
    public func migratingPath(from sourcePath: String, to destinationPath: String) -> WindowSessionSnapshot {
        var result = self
        result.openTabs = unique(openTabs.map { $0 == sourcePath ? destinationPath : $0 })
        if result.activeTab == sourcePath { result.activeTab = destinationPath }
        result.navigationHistory = navigationHistory.map { $0 == sourcePath ? destinationPath : $0 }
        if let mode = result.documentModes.removeValue(forKey: sourcePath) {
            result.documentModes[destinationPath] = mode
        }
        if let scroll = result.scrollPositions.removeValue(forKey: sourcePath) {
            result.scrollPositions[destinationPath] = scroll
        }
        return result
    }

    /// Migrates both the current compatibility projection and every
    /// vault-qualified presentation reference belonging to `vaultID`.
    public func migratingPath(
        vaultID: UUID,
        from sourcePath: String,
        to destinationPath: String
    ) -> WindowSessionSnapshot {
        var result = self
        if self.vaultID == vaultID {
            result = result.migratingPath(from: sourcePath, to: destinationPath)
        }
        result.qualifiedNavigationHistory = qualifiedNavigationHistory?.map { reference in
            guard reference.vaultID == vaultID, reference.relativePath == sourcePath else {
                return reference
            }
            return VaultQualifiedNoteID(vaultID: vaultID, relativePath: destinationPath)
        }
        result.recentNotes = recentNotes?.migratingPath(
            vaultID: vaultID,
            from: sourcePath,
            to: destinationPath
        )
        result.vaultPresentations = vaultPresentations?.map { presentation in
            guard presentation.vaultID == vaultID else { return presentation }
            return presentation.migratingPath(from: sourcePath, to: destinationPath)
        }
        return result
    }

    private func unique(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.filter { seen.insert($0).inserted }
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
