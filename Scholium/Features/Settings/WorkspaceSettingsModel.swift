import Combine
import Foundation
import ScholiumContracts

enum WorkspacePortableSettingsState: Equatable, Sendable {
    case unavailable
    case readFailed(String)
    case current(SettingsRevision)
    case needsReview(SettingsRevision, reason: String)
    case missing
    case oldSchema(Int?)
    case futureSchema(Int)
    case corrupted
}

enum AgentBridgeAvailability: Equatable, Sendable {
    case available
    case unavailable(String)
}

/// Delivery-neutral values required by Settings. No document buffer, window
/// route, presentation state, or editor session belongs in this snapshot.
struct WorkspaceSettingsSnapshot: Equatable, Sendable {
    var registeredVaults: [RegisteredVault]
    var registeredTriptychs: [TriptychAssignment]
    var activeTriptychID: UUID?
    var triptychSettings: TriptychSettings
    var portableSettingsState: WorkspacePortableSettingsState

    init(
        registeredVaults: [RegisteredVault] = [],
        registeredTriptychs: [TriptychAssignment] = [],
        activeTriptychID: UUID? = nil,
        triptychSettings: TriptychSettings = TriptychSettings(),
        settingsRevision: SettingsRevision? = nil,
        portableSettingsState: WorkspacePortableSettingsState? = nil
    ) {
        self.registeredVaults = registeredVaults
        self.registeredTriptychs = registeredTriptychs
        self.activeTriptychID = activeTriptychID
        self.triptychSettings = triptychSettings
        self.portableSettingsState =
            portableSettingsState
            ?? settingsRevision.map(WorkspacePortableSettingsState.current)
            ?? .unavailable
    }
}

struct WorkspaceSettingsRecoveryCommit: Sendable {
    let triptychID: UUID
    let recovery: TriptychSettingsRecoveryResult
    let derivedRefreshWarning: String?
}

struct WorkspaceSettingsRecoveryRequest: Sendable {
    let triptychID: UUID
    let revision: SettingsRevision?
}

enum WorkspaceSettingsMutationError: LocalizedError, Equatable {
    case triptychChanged
    case recoveryInProgress

    var errorDescription: String? {
        switch self {
        case .triptychChanged:
            String(
                localized:
                    "The active Triptych changed. Reload the current settings before trying again.",
                table: "Localizable", bundle: .module)
        case .recoveryInProgress:
            String(
                localized:
                    "Portable settings are already being restored. Wait for the current operation to finish.",
                table: "Localizable", bundle: .module)
        }
    }
}

/// Triptych registration and portable-settings operations used by Settings.
@MainActor
struct WorkspaceSettingsWorkspaceCapabilities {
    let loadSnapshot: @MainActor (UUID?) async throws -> WorkspaceSettingsSnapshot
    let configureWorkspace:
        (
            URL, URL, URL, URL, UUID?, String?
        ) async throws -> WorkspaceSettingsSnapshot
    let loadSettingsRecovery: (UUID) async throws -> TriptychSettingsRecoverySnapshot
    let resetTriptychSettings: (UUID, SettingsRevision?) async throws -> WorkspaceSettingsRecoveryCommit
    let portableContainerURL: (URL) async -> URL?
}

/// Zotero operations used by its dedicated settings page.
@MainActor
struct WorkspaceSettingsZoteroCapabilities {
    let zoteroConnectionInfo: () async -> ZoteroLibraryInfo
    let openZotero: () async -> Void
    let clearZoteroConnectionHistory: () async throws -> Void
    let refreshZoteroLibraryInfo: () async throws -> ZoteroLibraryInfo
}

struct WorkspaceChangesHistorySnapshot: Equatable, Sendable {
    let retention: DocumentChangeRetention
    let usage: DocumentChangeHistoryUsage
}

@MainActor
struct WorkspaceChangesHistoryCapabilities {
    let updates: AnyPublisher<UUID, Never>
    let load: (UUID) async throws -> WorkspaceChangesHistorySnapshot
    let setRetention: (UUID, DocumentChangeRetention) async throws -> WorkspaceChangesHistorySnapshot
    let clear: (UUID) async throws -> WorkspaceChangesHistorySnapshot
}

/// Delivery-neutral operations assembled by the macOS composition root.
/// Settings owns feature state but never receives an Application handle.
@MainActor
struct WorkspaceSettingsCapabilities {
    let workspace: WorkspaceSettingsWorkspaceCapabilities
    let zotero: WorkspaceSettingsZoteroCapabilities
    let changesHistory: WorkspaceChangesHistoryCapabilities
}

/// Application-lifetime Settings boundary. It receives delivery-neutral
/// operations; it never constructs a window, document controller, or session.
@MainActor
final class WorkspaceSettingsModel: ObservableObject {
    typealias SnapshotLoader = @MainActor (UUID?) async throws -> WorkspaceSettingsSnapshot
    @Published private(set) var snapshot: WorkspaceSettingsSnapshot
    /// Selection owns load routing; snapshot remains a complete confirmed read.
    @Published private(set) var selectedTriptychID: UUID?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published var workspaceRecoveryMessage: String?

    let cssSnippetStore: CSSSnippetStore?

    private let agentBridgeAvailabilityProvider: @MainActor () -> AgentBridgeAvailability

    private let capabilities: WorkspaceSettingsCapabilities?
    private let loadSnapshot: SnapshotLoader?
    private let loadRecoverySnapshot: (@MainActor (UUID) async throws -> TriptychSettingsRecoverySnapshot)?
    private let resetSnapshot: (@MainActor (UUID, SettingsRevision?) async throws -> WorkspaceSettingsRecoveryCommit)?
    @Published private(set) var isRestoringSettings = false
    /// The Settings scene root and its visible pane can refresh concurrently.
    /// A newer request must run and win rather than being dropped as "busy."
    private var refreshGeneration: UInt64 = 0

    /// Production construction borrows the application composition root.
    init(
        capabilities: WorkspaceSettingsCapabilities,
        cssSnippetStore: CSSSnippetStore,
        agentBridgeAvailability: @escaping @MainActor () -> AgentBridgeAvailability = {
            .unavailable("The App bridge is unavailable.")
        }
    ) {
        self.snapshot = WorkspaceSettingsSnapshot()
        self.capabilities = capabilities
        self.cssSnippetStore = cssSnippetStore
        self.agentBridgeAvailabilityProvider = agentBridgeAvailability
        self.loadSnapshot = capabilities.workspace.loadSnapshot
        self.loadRecoverySnapshot = nil
        self.resetSnapshot = nil
    }

    /// Pure construction seam for feature tests and previews.
    init(
        snapshot: WorkspaceSettingsSnapshot = WorkspaceSettingsSnapshot(),
        loadSnapshot: SnapshotLoader? = nil,
        loadSettingsRecovery: (@MainActor (UUID) async throws -> TriptychSettingsRecoverySnapshot)? = nil,
        resetSettings: (@MainActor (UUID, SettingsRevision?) async throws -> WorkspaceSettingsRecoveryCommit)? = nil
    ) {
        self.snapshot = snapshot
        self.selectedTriptychID = snapshot.activeTriptychID
        self.capabilities = nil
        self.cssSnippetStore = nil
        self.agentBridgeAvailabilityProvider = {
            .unavailable("The App bridge is unavailable in this preview.")
        }
        self.loadSnapshot = loadSnapshot
        self.loadRecoverySnapshot = loadSettingsRecovery
        self.resetSnapshot = resetSettings
    }

    var registeredVaults: [RegisteredVault] { snapshot.registeredVaults }
    var registeredTriptychs: [TriptychAssignment] { snapshot.registeredTriptychs }
    var portableSettingsState: WorkspacePortableSettingsState {
        snapshot.portableSettingsState
    }
    var workspaceAssignment: TriptychAssignment? {
        guard let id = snapshot.activeTriptychID else { return nil }
        return snapshot.registeredTriptychs.first { $0.id == id }
    }
    var agentBridgeAvailability: AgentBridgeAvailability {
        agentBridgeAvailabilityProvider()
    }
    func replaceSnapshot(_ snapshot: WorkspaceSettingsSnapshot) {
        refreshGeneration &+= 1
        isRefreshing = false
        self.snapshot = snapshot
        selectedTriptychID = snapshot.activeTriptychID
        errorMessage = nil
    }

    @discardableResult
    func refresh() async -> Bool {
        guard let loadSnapshot else { return false }
        let requestedTriptychID = selectedTriptychID
        return await perform { try await loadSnapshot(requestedTriptychID) }
    }

    func restorePreferredWorkspaceIfNeeded(activeTriptychID: UUID? = nil) async {
        // The requested scope can route its existing services immediately, but
        // it cannot relabel a confirmed snapshot from another Triptych.
        if let activeTriptychID {
            selectedTriptychID = activeTriptychID
        }
        await refresh()
    }

    func activateTriptych(id: UUID) async {
        selectedTriptychID = id
        await refresh()
    }

    /// Confirmation is prepared from a fresh authoritative read, never from
    /// fallback values or a fingerprint belonging to another Triptych.
    func prepareSettingsRecovery(triptychID: UUID) async throws -> WorkspaceSettingsRecoveryRequest {
        guard selectedTriptychID == triptychID, snapshot.activeTriptychID == triptychID else {
            throw WorkspaceSettingsMutationError.triptychChanged
        }
        let read: TriptychSettingsRecoverySnapshot
        if let loadRecoverySnapshot {
            read = try await loadRecoverySnapshot(triptychID)
        } else if let capabilities {
            read = try await capabilities.workspace.loadSettingsRecovery(triptychID)
        } else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try Task.checkCancellation()
        guard selectedTriptychID == triptychID, snapshot.activeTriptychID == triptychID else {
            throw WorkspaceSettingsMutationError.triptychChanged
        }
        return WorkspaceSettingsRecoveryRequest(triptychID: triptychID, revision: read.revision)
    }

    func restoreSettingsDefaults(_ request: WorkspaceSettingsRecoveryRequest) async throws -> WorkspaceSettingsRecoveryCommit {
        guard selectedTriptychID == request.triptychID,
            snapshot.activeTriptychID == request.triptychID
        else {
            throw WorkspaceSettingsMutationError.triptychChanged
        }
        guard !isRestoringSettings else {
            throw WorkspaceSettingsMutationError.recoveryInProgress
        }
        isRestoringSettings = true
        defer { isRestoringSettings = false }
        do {
            let commit: WorkspaceSettingsRecoveryCommit
            if let resetSnapshot {
                commit = try await resetSnapshot(request.triptychID, request.revision)
            } else if let capabilities {
                commit = try await capabilities.workspace.resetTriptychSettings(request.triptychID, request.revision)
            } else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            guard commit.triptychID == request.triptychID else {
                throw WorkspaceSettingsMutationError.triptychChanged
            }
            installSettingsRecovery(commit)
            return commit
        } catch let error as ScholiumApplicationError where error.mutationRequiresReconciliation {
            _ = await refresh()
            throw error
        }
    }

    private func installSettingsRecovery(_ commit: WorkspaceSettingsRecoveryCommit) {
        guard selectedTriptychID == commit.triptychID,
            snapshot.activeTriptychID == commit.triptychID
        else { return }
        // A refresh started before this durable commit cannot reinstall stale values.
        refreshGeneration &+= 1
        isRefreshing = false
        snapshot.triptychSettings = commit.recovery.snapshot.settings
        snapshot.portableSettingsState = .current(commit.recovery.snapshot.revision)
        errorMessage = nil
    }

    func configureTriptych(
        paperAnalysisURL: URL,
        topicKnowledgeURL: URL,
        outputURL: URL,
        portableContainerURL: URL,
        triptychID: UUID? = nil,
        triptychName: String? = nil
    ) async throws {
        guard let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let activeIDAtSubmission = selectedTriptychID
        let configured = try await capabilities.workspace.configureWorkspace(
            paperAnalysisURL,
            topicKnowledgeURL,
            outputURL,
            portableContainerURL,
            triptychID ?? activeIDAtSubmission,
            triptychName
        )
        if selectedTriptychID == activeIDAtSubmission {
            replaceSnapshot(configured)
        } else {
            // Saving the original target cannot undo a later scope selection.
            _ = await refresh()
        }
        workspaceRecoveryMessage = nil
    }

    func portableContainerURL(for worksURL: URL) async -> URL? {
        await capabilities?.workspace.portableContainerURL(worksURL)
    }

    func zoteroConnectionInfo() async -> ZoteroLibraryInfo {
        guard let capabilities else {
            return ZoteroLibraryInfo(status: .appUnavailable, lastSuccessfulConnection: nil)
        }
        return await capabilities.zotero.zoteroConnectionInfo()
    }

    func openZotero() async {
        await capabilities?.zotero.openZotero()
    }

    func clearZoteroConnectionHistory() async throws {
        try await capabilities?.zotero.clearZoteroConnectionHistory()
    }

    func changesHistory(triptychID: UUID) async throws -> WorkspaceChangesHistorySnapshot {
        guard let capabilities else { throw WorkspaceRegistryError.incompleteWorkspace }
        return try await capabilities.changesHistory.load(triptychID)
    }

    var changesHistoryUpdates: AnyPublisher<UUID, Never> {
        capabilities?.changesHistory.updates ?? Empty().eraseToAnyPublisher()
    }

    func setChangesHistoryRetention(
        _ retention: DocumentChangeRetention,
        triptychID: UUID
    ) async throws -> WorkspaceChangesHistorySnapshot {
        guard let capabilities else { throw WorkspaceRegistryError.incompleteWorkspace }
        return try await capabilities.changesHistory.setRetention(triptychID, retention)
    }

    func clearChangesHistory(triptychID: UUID) async throws -> WorkspaceChangesHistorySnapshot {
        guard let capabilities else { throw WorkspaceRegistryError.incompleteWorkspace }
        return try await capabilities.changesHistory.clear(triptychID)
    }

    func refreshZoteroLibraryInfo() async throws -> ZoteroLibraryInfo {
        guard let capabilities else {
            return ZoteroLibraryInfo(status: .appUnavailable, lastSuccessfulConnection: nil)
        }
        return try await capabilities.zotero.refreshZoteroLibraryInfo()
    }

    @discardableResult
    private func perform(
        _ operation: @MainActor () async throws -> WorkspaceSettingsSnapshot
    ) async -> Bool {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        isRefreshing = true
        errorMessage = nil
        defer {
            if refreshGeneration == generation {
                isRefreshing = false
            }
        }
        do {
            let refreshedSnapshot = try await operation()
            try Task.checkCancellation()
            guard refreshGeneration == generation else { return false }
            replaceSnapshot(refreshedSnapshot)
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard refreshGeneration == generation else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }
}
