import ScholiumContracts
import Combine
import Foundation

enum WorkspaceSettingsPane: String, CaseIterable, Identifiable, Sendable {
    case vaults
    case documentStyles = "document-styles"
    case properties
    case researchGuidance = "research-guidance"
    case attention
    case zotero

    var id: String { rawValue }
}

/// Delivery-neutral values required by Settings. No document buffer, window
/// route, presentation state, or editor session belongs in this snapshot.
struct WorkspaceSettingsSnapshot: Equatable, Sendable {
    var registeredVaults: [RegisteredVault]
    var registeredTriptychs: [TriptychAssignment]
    var activeTriptychID: UUID?
    var triptychSettings: TriptychSettings
    var propertyKeysBySlot: [WorkspaceVaultSlot: Set<String>]

    init(
        registeredVaults: [RegisteredVault] = [],
        registeredTriptychs: [TriptychAssignment] = [],
        activeTriptychID: UUID? = nil,
        triptychSettings: TriptychSettings = TriptychSettings(),
        propertyKeysBySlot: [WorkspaceVaultSlot: Set<String>] = [:]
    ) {
        self.registeredVaults = registeredVaults
        self.registeredTriptychs = registeredTriptychs
        self.activeTriptychID = activeTriptychID
        self.triptychSettings = triptychSettings
        self.propertyKeysBySlot = propertyKeysBySlot
    }
}

/// Delivery-neutral operations assembled by the macOS composition root.
/// Settings owns feature state but never receives an Application handle.
@MainActor
struct WorkspaceSettingsCapabilities {
    let loadSnapshot: (UUID?) async throws -> WorkspaceSettingsSnapshot
    let configureWorkspace: (
        URL, URL, URL, URL, UUID?, String?
    ) async throws -> WorkspaceSettingsSnapshot
    let saveTriptychSettings: (UUID, TriptychSettings) async throws -> WorkspaceSettingsSnapshot
    let dialogueResponseProfile: (UUID) async throws -> DialogueResponseProfile
    let saveDialogueResponseProfile: (UUID, DialogueResponseProfile) async throws -> Void
    let portableContainerURL: (URL) async -> URL?
    let zoteroConnectionInfo: () async -> ZoteroLibraryInfo
    let openZotero: () async -> Void
    let forgetZoteroCache: () async throws -> Void
    let refreshZoteroLibraryInfo: () async throws -> ZoteroLibraryInfo
    let researchSkills: (UUID) async throws -> [ResearchSkillPackage]
    let createResearchSkill: (UUID, String, String) async throws -> ResearchSkillPackage
    let duplicateBundledResearchSkill: (UUID, String, String) async throws -> ResearchSkillPackage
    let renameResearchSkill: (UUID, String, String, DocumentFingerprint) async throws -> ResearchSkillPackage
    let saveResearchSkill: (UUID, String, String, DocumentFingerprint) async throws -> ResearchSkillPackage
    let deleteResearchSkill: (UUID, String, DocumentFingerprint) async throws -> Void
    let researchSkillsURL: (UUID) async throws -> URL
    let openExternal: (URL) -> Bool
}

/// Application-lifetime Settings boundary. It receives delivery-neutral
/// operations; it never constructs a window, document controller, or session.
@MainActor
final class WorkspaceSettingsModel: ObservableObject {
    typealias SnapshotLoader = @MainActor () async throws -> WorkspaceSettingsSnapshot
    typealias TriptychActivator = @MainActor (UUID) async throws -> WorkspaceSettingsSnapshot
    typealias SettingsSaver = @MainActor (TriptychSettings) async throws -> WorkspaceSettingsSnapshot

    @Published private(set) var selectedPane: WorkspaceSettingsPane
    @Published private(set) var snapshot: WorkspaceSettingsSnapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published var workspaceRecoveryMessage: String?
    @Published private(set) var activeTriptychServicesID: UUID?

    let cssSnippetStore: CSSSnippetStore?

    private let capabilities: WorkspaceSettingsCapabilities?
    private let loadSnapshot: SnapshotLoader?
    private let activateSnapshot: TriptychActivator?
    private let saveSnapshot: SettingsSaver?

    /// Production construction borrows the application composition root.
    init(
        capabilities: WorkspaceSettingsCapabilities,
        cssSnippetStore: CSSSnippetStore,
        selectedPane: WorkspaceSettingsPane = .vaults
    ) {
        self.selectedPane = selectedPane
        self.snapshot = WorkspaceSettingsSnapshot()
        self.capabilities = capabilities
        self.cssSnippetStore = cssSnippetStore
        self.loadSnapshot = nil
        self.activateSnapshot = nil
        self.saveSnapshot = nil
    }

    /// Pure construction seam for feature tests and previews.
    init(
        selectedPane: WorkspaceSettingsPane = .vaults,
        snapshot: WorkspaceSettingsSnapshot = WorkspaceSettingsSnapshot(),
        loadSnapshot: SnapshotLoader? = nil,
        activateTriptych: TriptychActivator? = nil,
        saveSettings: SettingsSaver? = nil
    ) {
        self.selectedPane = selectedPane
        self.snapshot = snapshot
        self.capabilities = nil
        self.cssSnippetStore = nil
        self.loadSnapshot = loadSnapshot
        self.activateSnapshot = activateTriptych
        self.saveSnapshot = saveSettings
        self.activeTriptychServicesID = snapshot.activeTriptychID
    }

    var registeredVaults: [RegisteredVault] { snapshot.registeredVaults }
    var registeredTriptychs: [TriptychAssignment] { snapshot.registeredTriptychs }
    var triptychSettings: TriptychSettings { snapshot.triptychSettings }
    var workspaceAssignment: TriptychAssignment? {
        guard let id = snapshot.activeTriptychID else { return nil }
        return snapshot.registeredTriptychs.first { $0.id == id }
    }
    func propertyKeys(for slot: WorkspaceVaultSlot) -> [String] {
        Array(snapshot.propertyKeysBySlot[slot, default: []])
    }

    func selectPane(_ pane: WorkspaceSettingsPane) {
        selectedPane = pane
    }

    func replaceSnapshot(_ snapshot: WorkspaceSettingsSnapshot) {
        self.snapshot = snapshot
        activeTriptychServicesID = snapshot.activeTriptychID
        errorMessage = nil
    }

    func refresh() async {
        if let capabilities {
            await perform { try await capabilities.loadSnapshot(self.snapshot.activeTriptychID) }
        } else if let loadSnapshot {
            await perform { try await loadSnapshot() }
        }
    }

    func refreshRegisteredVaults() async {
        await refresh()
    }

    func refreshWorkspaceAssignment() async {
        await refresh()
    }

    func restorePreferredWorkspaceIfNeeded() async {
        let preferred = UserDefaults.standard.string(forKey: "scholium.settings.triptychID")
            .flatMap(UUID.init(uuidString:))
        guard let capabilities else {
            await refresh()
            return
        }
        await perform { try await capabilities.loadSnapshot(preferred) }
    }

    func activateTriptych(id: UUID) async {
        if let capabilities {
            await perform { try await capabilities.loadSnapshot(id) }
        } else if let activateSnapshot {
            await perform { try await activateSnapshot(id) }
        }
    }

    func activateRegisteredTriptych(id: UUID) async {
        await activateTriptych(id: id)
    }

    func saveTriptychSettings(_ settings: TriptychSettings) async throws {
        if let saveSnapshot {
            replaceSnapshot(try await saveSnapshot(settings))
            return
        }
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        replaceSnapshot(try await capabilities.saveTriptychSettings(id, settings))
    }

    func dialogueResponseProfile() async throws -> DialogueResponseProfile {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.dialogueResponseProfile(id)
    }

    func saveDialogueResponseProfile(_ profile: DialogueResponseProfile) async throws {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await capabilities.saveDialogueResponseProfile(id, profile)
    }

    func configureThreeVaultWorkspace(
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
        replaceSnapshot(try await capabilities.configureWorkspace(
            paperAnalysisURL,
            topicKnowledgeURL,
            outputURL,
            portableContainerURL,
            triptychID ?? snapshot.activeTriptychID,
            triptychName
        ))
        workspaceRecoveryMessage = nil
    }

    func portableContainerURL(for worksURL: URL) async -> URL? {
        await capabilities?.portableContainerURL(worksURL)
    }

    func zoteroConnectionInfo() async -> ZoteroLibraryInfo {
        guard let capabilities else {
            return ZoteroLibraryInfo(status: .appUnavailable, lastSuccessfulConnection: nil)
        }
        return await capabilities.zoteroConnectionInfo()
    }

    func openZotero() async {
        await capabilities?.openZotero()
    }

    func forgetZoteroCache() async throws {
        try await capabilities?.forgetZoteroCache()
    }

    func refreshZoteroLibraryInfo() async throws -> ZoteroLibraryInfo {
        guard let capabilities else {
            return ZoteroLibraryInfo(status: .appUnavailable, lastSuccessfulConnection: nil)
        }
        return try await capabilities.refreshZoteroLibraryInfo()
    }

    func researchSkills() async throws -> [ResearchSkillPackage] {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchSkills(id)
    }

    func createResearchSkill(id: String, source: String) async throws -> ResearchSkillPackage {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.createResearchSkill(workspaceID, id, source)
    }

    func duplicateBundledResearchSkill(
        id: String,
        as newID: String
    ) async throws -> ResearchSkillPackage {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.duplicateBundledResearchSkill(workspaceID, id, newID)
    }

    func renameResearchSkill(
        id: String,
        to newID: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchSkillPackage {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.renameResearchSkill(workspaceID, id, newID, expectedRevision)
    }

    func saveResearchSkill(
        id: String,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchSkillPackage {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.saveResearchSkill(workspaceID, id, source, expectedRevision)
    }

    func deleteResearchSkill(
        id: String,
        expectedRevision: DocumentFingerprint
    ) async throws {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await capabilities.deleteResearchSkill(workspaceID, id, expectedRevision)
    }

    func researchSkillsURL() async throws -> URL {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchSkillsURL(workspaceID)
    }

    func openExternal(_ url: URL) {
        _ = capabilities?.openExternal(url)
    }

    func showToast(_ message: String) {
        // Settings previously wrote to a window-only toast surface that its
        // scene did not render. Keep success paths silent and nonmodal.
        _ = message
    }

    func clearError() {
        errorMessage = nil
    }

    private func perform(
        _ operation: @MainActor () async throws -> WorkspaceSettingsSnapshot
    ) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }
        do {
            replaceSnapshot(try await operation())
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
