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

    var isReadFailure: Bool {
        if case .readFailed = self { return true }
        return false
    }

    var editableRevision: SettingsRevision? {
        switch self {
        case .current(let revision), .needsReview(let revision, _): revision
        case .unavailable, .readFailed, .missing, .oldSchema, .futureSchema, .corrupted: nil
        }
    }
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
    var settingsRevision: SettingsRevision?
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
        self.settingsRevision = settingsRevision
        self.portableSettingsState =
            portableSettingsState
            ?? settingsRevision.map(WorkspacePortableSettingsState.current)
            ?? .unavailable
    }
}

struct WorkspacePortableSettingsRead: Equatable, Sendable {
    let triptychID: UUID
    let settings: TriptychSettings
    let state: WorkspacePortableSettingsState
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
    case reconciliationRequired

    var errorDescription: String? {
        switch self {
        case .triptychChanged:
            String(
                localized:
                    "The active Triptych changed. Reload the current settings before trying again.",
                table: "Localizable", bundle: .module)
        case .reconciliationRequired:
            String(
                localized:
                    "Portable settings must be reread successfully before recovery can continue.",
                table: "Localizable", bundle: .module)
        }
    }
}

/// Triptych registration and portable-settings operations used by Settings.
@MainActor
struct WorkspaceSettingsWorkspaceCapabilities {
    let loadSnapshot: (UUID?) async throws -> WorkspaceSettingsSnapshot
    let loadPortableSettings: (UUID) async throws -> WorkspacePortableSettingsRead
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
    typealias SnapshotLoader = @MainActor () async throws -> WorkspaceSettingsSnapshot
    typealias TriptychActivator = @MainActor (UUID) async throws -> WorkspaceSettingsSnapshot
    typealias PortableSettingsLoader =
        @MainActor (
            UUID
        ) async throws -> WorkspacePortableSettingsRead
    @Published private(set) var snapshot: WorkspaceSettingsSnapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published var workspaceRecoveryMessage: String?
    @Published private(set) var activeTriptychServicesID: UUID?
    @Published private(set) var settingsReconciliationRequiredTriptychIDs: Set<UUID> = []

    let cssSnippetStore: CSSSnippetStore?

    private let agentBridgeAvailabilityProvider: @MainActor () -> AgentBridgeAvailability

    private let capabilities: WorkspaceSettingsCapabilities?
    private let loadSnapshot: SnapshotLoader?
    private let activateSnapshot: TriptychActivator?
    private let loadPortableSettingsSnapshot: PortableSettingsLoader?
    private let loadRecoverySnapshot: (@MainActor (UUID) async throws -> TriptychSettingsRecoverySnapshot)?
    private let resetSnapshot: (@MainActor (UUID, SettingsRevision?) async throws -> WorkspaceSettingsRecoveryCommit)?
    @Published private(set) var isRestoringSettings = false
    /// The Settings scene root and its visible pane can refresh concurrently.
    /// A newer request must run and win rather than being dropped as "busy."
    private var refreshGeneration: UInt64 = 0
    private var uncertainSettingsRecoveryTriptychIDs: Set<UUID> = []

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
        self.loadSnapshot = nil
        self.activateSnapshot = nil
        self.loadPortableSettingsSnapshot = nil
        self.loadRecoverySnapshot = nil
        self.resetSnapshot = nil
    }

    /// Pure construction seam for feature tests and previews.
    init(
        snapshot: WorkspaceSettingsSnapshot = WorkspaceSettingsSnapshot(),
        loadSnapshot: SnapshotLoader? = nil,
        activateTriptych: TriptychActivator? = nil,
        loadPortableSettings: PortableSettingsLoader? = nil,
        loadSettingsRecovery: (@MainActor (UUID) async throws -> TriptychSettingsRecoverySnapshot)? = nil,
        resetSettings: (@MainActor (UUID, SettingsRevision?) async throws -> WorkspaceSettingsRecoveryCommit)? = nil
    ) {
        self.snapshot = snapshot
        self.capabilities = nil
        self.cssSnippetStore = nil
        self.agentBridgeAvailabilityProvider = {
            .unavailable("The App bridge is unavailable in this preview.")
        }
        self.loadSnapshot = loadSnapshot
        self.activateSnapshot = activateTriptych
        self.loadPortableSettingsSnapshot = loadPortableSettings
        self.loadRecoverySnapshot = loadSettingsRecovery
        self.resetSnapshot = resetSettings
        self.activeTriptychServicesID = snapshot.activeTriptychID
    }

    var registeredVaults: [RegisteredVault] { snapshot.registeredVaults }
    var registeredTriptychs: [TriptychAssignment] { snapshot.registeredTriptychs }
    var triptychSettings: TriptychSettings { snapshot.triptychSettings }
    var portableSettingsState: WorkspacePortableSettingsState {
        snapshot.portableSettingsState
    }
    var settingsRevision: SettingsRevision? {
        snapshot.portableSettingsState.editableRevision
    }
    var hasWritableTriptychSettings: Bool { settingsRevision != nil }
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
        activeTriptychServicesID = snapshot.activeTriptychID
        if let id = snapshot.activeTriptychID,
            snapshot.portableSettingsState != .unavailable,
            !snapshot.portableSettingsState.isReadFailure,
            !uncertainSettingsRecoveryTriptychIDs.contains(id)
        {
            settingsReconciliationRequiredTriptychIDs.remove(id)
        }
        errorMessage = nil
    }

    func requiresSettingsReconciliation(for triptychID: UUID?) -> Bool {
        triptychID.map(settingsReconciliationRequiredTriptychIDs.contains) ?? false
    }

    @discardableResult
    func refresh() async -> Bool {
        if let capabilities {
            return await perform {
                try await capabilities.workspace.loadSnapshot(self.snapshot.activeTriptychID)
            }
        } else if let loadSnapshot {
            return await perform { try await loadSnapshot() }
        }
        return false
    }

    func restorePreferredWorkspaceIfNeeded(activeTriptychID: UUID? = nil) async {
        // The application activation is already authoritative enough to route
        // delivery-neutral Settings capabilities. Publish that ID before the
        // broader registry/property snapshot finishes so settings integrations
        // does not misreport a valid live Triptych as incomplete.
        if let activeTriptychID {
            snapshot.activeTriptychID = activeTriptychID
            activeTriptychServicesID = activeTriptychID
        }
        let preferred =
            activeTriptychID
            ?? UserDefaults.standard.string(forKey: "scholium.settings.triptychID")
            .flatMap(UUID.init(uuidString:))
        guard let capabilities else {
            await refresh()
            return
        }
        await perform { try await capabilities.workspace.loadSnapshot(preferred) }
    }

    func activateTriptych(id: UUID) async {
        if let capabilities {
            await perform { try await capabilities.workspace.loadSnapshot(id) }
        } else if let activateSnapshot {
            await perform { try await activateSnapshot(id) }
        }
    }

    /// Confirmation is prepared from a fresh authoritative read, never from
    /// fallback values or a fingerprint belonging to another Triptych.
    func prepareSettingsRecovery(triptychID: UUID) async throws -> WorkspaceSettingsRecoveryRequest {
        guard snapshot.activeTriptychID == triptychID else {
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
        guard snapshot.activeTriptychID == triptychID else {
            throw WorkspaceSettingsMutationError.triptychChanged
        }
        return WorkspaceSettingsRecoveryRequest(triptychID: triptychID, revision: read.revision)
    }

    func restoreSettingsDefaults(_ request: WorkspaceSettingsRecoveryRequest) async throws -> WorkspaceSettingsRecoveryCommit {
        guard snapshot.activeTriptychID == request.triptychID else {
            throw WorkspaceSettingsMutationError.triptychChanged
        }
        guard !isRestoringSettings else {
            throw WorkspaceSettingsMutationError.reconciliationRequired
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
            if snapshot.activeTriptychID == commit.triptychID {
                installPortableSettings(
                    WorkspacePortableSettingsRead(
                        triptychID: commit.triptychID,
                        settings: commit.recovery.snapshot.settings,
                        state: .current(commit.recovery.snapshot.revision)))
            }
            return commit
        } catch let error as ScholiumApplicationError where error.mutationRequiresReconciliation {
            uncertainSettingsRecoveryTriptychIDs.insert(request.triptychID)
            settingsReconciliationRequiredTriptychIDs.insert(request.triptychID)
            _ = await refresh()
            throw error
        }
    }

    private func installPortableSettings(_ read: WorkspacePortableSettingsRead) {
        guard snapshot.activeTriptychID == read.triptychID else { return }
        // A refresh started before this durable commit cannot reinstall stale values.
        refreshGeneration &+= 1
        isRefreshing = false
        snapshot.triptychSettings = read.settings
        snapshot.settingsRevision = read.state.editableRevision
        snapshot.portableSettingsState = read.state
        uncertainSettingsRecoveryTriptychIDs.remove(read.triptychID)
        settingsReconciliationRequiredTriptychIDs.remove(read.triptychID)
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
        let activeIDAtSubmission = snapshot.activeTriptychID
        let configured = try await capabilities.workspace.configureWorkspace(
            paperAnalysisURL,
            topicKnowledgeURL,
            outputURL,
            portableContainerURL,
            triptychID ?? activeIDAtSubmission,
            triptychName
        )
        if snapshot.activeTriptychID == activeIDAtSubmission {
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
