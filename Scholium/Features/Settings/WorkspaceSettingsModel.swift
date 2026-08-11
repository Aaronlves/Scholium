import ScholiumContracts
import Combine
import Foundation

enum WorkspaceSettingsPane: String, CaseIterable, Identifiable, Sendable {
    case vaults
    case appearance
    case properties
    case researchGuidance = "research-guidance"
    case attention
    case zotero

    var id: String { rawValue }
}

enum WorkspacePortableSettingsState: Equatable, Sendable {
    case unavailable
    case current(SettingsRevision)
    case needsReview(SettingsRevision, reason: String)
    case missing
    case oldSchema(Int?)
    case futureSchema(Int)
    case corrupted

    var editableRevision: SettingsRevision? {
        switch self {
        case .current(let revision), .needsReview(let revision, _): revision
        case .unavailable, .missing, .oldSchema, .futureSchema, .corrupted: nil
        }
    }
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
    var propertyKeysBySlot: [WorkspaceVaultSlot: Set<String>]

    init(
        registeredVaults: [RegisteredVault] = [],
        registeredTriptychs: [TriptychAssignment] = [],
        activeTriptychID: UUID? = nil,
        triptychSettings: TriptychSettings = TriptychSettings(),
        settingsRevision: SettingsRevision? = nil,
        portableSettingsState: WorkspacePortableSettingsState? = nil,
        propertyKeysBySlot: [WorkspaceVaultSlot: Set<String>] = [:]
    ) {
        self.registeredVaults = registeredVaults
        self.registeredTriptychs = registeredTriptychs
        self.activeTriptychID = activeTriptychID
        self.triptychSettings = triptychSettings
        self.settingsRevision = settingsRevision
        self.portableSettingsState = portableSettingsState
            ?? settingsRevision.map(WorkspacePortableSettingsState.current)
            ?? .unavailable
        self.propertyKeysBySlot = propertyKeysBySlot
    }
}

struct WorkspacePortableSettingsRead: Equatable, Sendable {
    let triptychID: UUID
    let settings: TriptychSettings
    let state: WorkspacePortableSettingsState
}

struct WorkspaceSettingsCommit: Equatable, Sendable {
    let triptychID: UUID
    let snapshot: TriptychSettingsSnapshot
    let derivedRefreshWarning: String?
}

struct WorkspaceSettingsSaveResult: Equatable, Sendable {
    let warning: String?
    let targetIsCurrent: Bool
}

enum WorkspaceSettingsMutationError: LocalizedError, Equatable {
    case triptychChanged
    case commitRequiresReview(String)
    case reconciliationRequired

    var errorDescription: String? {
        switch self {
        case .triptychChanged:
            String(localized: "The active Triptych changed. The Properties draft was preserved and was not written.", table: "Localizable", bundle: .module)
        case .commitRequiresReview:
            String(localized: "Scholium reread the portable settings after an uncertain save. Review the current saved version before trying again.", table: "Localizable", bundle: .module)
        case .reconciliationRequired:
            String(localized: "Portable settings must be reread successfully before another save can be attempted.", table: "Localizable", bundle: .module)
        }
    }
}

/// Triptych registration and portable-settings operations used by Settings.
@MainActor
struct WorkspaceSettingsWorkspaceCapabilities {
    let loadSnapshot: (UUID?) async throws -> WorkspaceSettingsSnapshot
    let loadPortableSettings: (UUID) async throws -> WorkspacePortableSettingsRead
    let configureWorkspace: (
        URL, URL, URL, URL, UUID?, String?
    ) async throws -> WorkspaceSettingsSnapshot
    let saveTriptychSettings: (
        UUID, TriptychSettings, SettingsRevision
    ) async throws -> WorkspaceSettingsCommit
    let portableContainerURL: (URL) async -> URL?
}

/// Machine-local installation and external-opening operations used by Settings.
@MainActor
struct WorkspaceSettingsMachineCapabilities {
    let commandLineToolStatus: () async -> CommandLineToolStatus
    let installCommandLineTool: () async throws -> CommandLineToolStatus
    let openExternal: (URL) -> Bool
}

/// Zotero operations used by the dedicated Settings pane.
@MainActor
struct WorkspaceSettingsZoteroCapabilities {
    let zoteroConnectionInfo: () async -> ZoteroLibraryInfo
    let openZotero: () async -> Void
    let clearZoteroConnectionHistory: () async throws -> Void
    let refreshZoteroLibraryInfo: () async throws -> ZoteroLibraryInfo
}

/// Research Guidance package, binding, and recovery operations used by Settings.
@MainActor
struct WorkspaceSettingsResearchGuidanceCapabilities {
    let researchSkillRegistrations: (
        UUID
    ) async throws -> ResearchSkillRegistrationSnapshot
    let saveResearchSkillRegistrations: (
        UUID, ResearchSkillRegistrationDocument, DocumentFingerprint
    ) async throws -> ResearchSkillRegistrationSnapshot
    let academicActionProfiles: (
        UUID
    ) async throws -> ResearchAcademicProfileSnapshot
    let saveAcademicActionProfiles: (
        UUID, ResearchAcademicProfileDocument, DocumentFingerprint
    ) async throws -> ResearchAcademicProfileSnapshot
    let collaborationPolicy: (
        UUID
    ) async throws -> ResearchCollaborationPolicySnapshot
    let saveCollaborationPolicy: (
        UUID, ResearchCollaborationPolicyDocument, DocumentFingerprint
    ) async throws -> ResearchCollaborationPolicySnapshot
    let researchMethod: (
        UUID, ResearchActionID
    ) async throws -> ResearchMethodSnapshot
    let saveResearchMethod: (
        UUID, ResearchSkillRegistrationKey, String, DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot
    let registerExternalResearchMethod: (
        UUID,
        ResearchActionID,
        String,
        String,
        String?,
        DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot
    let createResearchMethod: (
        UUID,
        ResearchActionID,
        String,
        String,
        DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot
    let restorePreviousResearchMethod: (
        UUID, ResearchSkillRegistrationKey, DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot
    let restoreDefaultResearchMethod: (
        UUID, ResearchActionID, DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot
    let philosophicalPractices: (
        UUID
    ) async throws -> [ResearchPracticeSnapshot]
    let createPhilosophicalPractice: (
        UUID, String, String
    ) async throws -> ResearchPracticeSnapshot
    let savePhilosophicalPractice: (
        UUID, String, String, DocumentFingerprint
    ) async throws -> ResearchPracticeSnapshot
    let restorePreviousPhilosophicalPractice: (
        UUID, String, DocumentFingerprint
    ) async throws -> ResearchPracticeSnapshot
    let citationMethodStatus: (UUID) async throws -> ResearchCitationMethodStatus
    let activateCitationMethod: (
        UUID, ResearchCitationMethodSelection, DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus
    let clearCitationMethod: (
        UUID, DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus
    let recoveryPolicy: (
        UUID
    ) async throws -> ResearchRecoveryPolicySnapshot
    let prepareRecoveryPolicyChange: (
        UUID, SettledSnapshotRetention, DocumentFingerprint?
    ) async throws -> ResearchRecoveryPolicyChangePreview
    let applyRecoveryPolicyChange: (
        UUID, ResearchRecoveryPolicyChangePreview
    ) async throws -> ResearchRecoveryPolicyApplyOutcome
}

/// Delivery-neutral operations assembled by the macOS composition root.
/// Settings owns feature state but never receives an Application handle.
@MainActor
struct WorkspaceSettingsCapabilities {
    let workspace: WorkspaceSettingsWorkspaceCapabilities
    let machine: WorkspaceSettingsMachineCapabilities
    let zotero: WorkspaceSettingsZoteroCapabilities
    let researchGuidance: WorkspaceSettingsResearchGuidanceCapabilities
}

/// Application-lifetime Settings boundary. It receives delivery-neutral
/// operations; it never constructs a window, document controller, or session.
@MainActor
final class WorkspaceSettingsModel: ObservableObject {
    typealias SnapshotLoader = @MainActor () async throws -> WorkspaceSettingsSnapshot
    typealias TriptychActivator = @MainActor (UUID) async throws -> WorkspaceSettingsSnapshot
    typealias PortableSettingsLoader = @MainActor (
        UUID
    ) async throws -> WorkspacePortableSettingsRead
    typealias SettingsSaver = @MainActor (
        UUID, TriptychSettings, SettingsRevision
    ) async throws -> WorkspaceSettingsCommit

    @Published private(set) var selectedPane: WorkspaceSettingsPane
    @Published private(set) var snapshot: WorkspaceSettingsSnapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var toastMessage: String?
    @Published var workspaceRecoveryMessage: String?
    @Published private(set) var activeTriptychServicesID: UUID?
    @Published private(set) var settingsReconciliationRequiredTriptychIDs: Set<UUID> = []

    let cssSnippetStore: CSSSnippetStore?

    private let capabilities: WorkspaceSettingsCapabilities?
    private let loadSnapshot: SnapshotLoader?
    private let activateSnapshot: TriptychActivator?
    private let loadPortableSettingsSnapshot: PortableSettingsLoader?
    private let saveSnapshot: SettingsSaver?
    /// The Settings scene root and its visible pane can refresh concurrently.
    /// A newer request must run and win rather than being dropped as "busy."
    private var refreshGeneration: UInt64 = 0

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
        self.loadPortableSettingsSnapshot = nil
        self.saveSnapshot = nil
    }

    /// Pure construction seam for feature tests and previews.
    init(
        selectedPane: WorkspaceSettingsPane = .vaults,
        snapshot: WorkspaceSettingsSnapshot = WorkspaceSettingsSnapshot(),
        loadSnapshot: SnapshotLoader? = nil,
        activateTriptych: TriptychActivator? = nil,
        loadPortableSettings: PortableSettingsLoader? = nil,
        saveSettings: SettingsSaver? = nil
    ) {
        self.selectedPane = selectedPane
        self.snapshot = snapshot
        self.capabilities = nil
        self.cssSnippetStore = nil
        self.loadSnapshot = loadSnapshot
        self.activateSnapshot = activateTriptych
        self.loadPortableSettingsSnapshot = loadPortableSettings
        self.saveSnapshot = saveSettings
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
    func propertyKeys(for slot: WorkspaceVaultSlot) -> [String] {
        Array(snapshot.propertyKeysBySlot[slot, default: []])
    }

    func selectPane(_ pane: WorkspaceSettingsPane) {
        selectedPane = pane
    }

    func replaceSnapshot(_ snapshot: WorkspaceSettingsSnapshot) {
        self.snapshot = snapshot
        activeTriptychServicesID = snapshot.activeTriptychID
        if let id = snapshot.activeTriptychID,
           snapshot.portableSettingsState != .unavailable {
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

    func commandLineToolStatus() async -> CommandLineToolStatus {
        guard let capabilities else {
            return CommandLineToolStatus(
                state: .bundledToolUnavailable,
                version: "Unknown",
                installPath: "~/.local/bin/scholium",
                isOnCurrentPATH: false,
                repairMessage: "The command-line installer is unavailable in this preview."
            )
        }
        return await capabilities.machine.commandLineToolStatus()
    }

    func installCommandLineTool() async throws -> CommandLineToolStatus {
        guard let capabilities else {
            throw CommandLineToolInstallationError.bundledToolUnavailable
        }
        return try await capabilities.machine.installCommandLineTool()
    }

    func refreshRegisteredVaults() async {
        await refresh()
    }

    func refreshWorkspaceAssignment() async {
        await refresh()
    }

    func restorePreferredWorkspaceIfNeeded(activeTriptychID: UUID? = nil) async {
        // The application activation is already authoritative enough to route
        // delivery-neutral Settings capabilities. Publish that ID before the
        // broader registry/property snapshot finishes so Research Guidance
        // does not misreport a valid live Triptych as incomplete.
        if let activeTriptychID {
            snapshot.activeTriptychID = activeTriptychID
            activeTriptychServicesID = activeTriptychID
        }
        let preferred = activeTriptychID
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

    func activateRegisteredTriptych(id: UUID) async {
        await activateTriptych(id: id)
    }

    @discardableResult
    func saveTriptychSettings(
        _ settings: TriptychSettings
    ) async throws -> WorkspaceSettingsSaveResult {
        guard let triptychID = snapshot.activeTriptychID,
              let expectedRevision = settingsRevision else {
            throw TriptychControlError.settingsMissing
        }
        return try await saveTriptychSettings(
            settings,
            targetTriptychID: triptychID,
            expectedRevision: expectedRevision
        )
    }

    @discardableResult
    func saveTriptychSettings(
        _ settings: TriptychSettings,
        targetTriptychID: UUID,
        expectedRevision: SettingsRevision
    ) async throws -> WorkspaceSettingsSaveResult {
        guard snapshot.activeTriptychID == targetTriptychID else {
            throw WorkspaceSettingsMutationError.triptychChanged
        }
        guard !settingsReconciliationRequiredTriptychIDs.contains(targetTriptychID) else {
            throw WorkspaceSettingsMutationError.reconciliationRequired
        }
        do {
            let commit: WorkspaceSettingsCommit
            if let saveSnapshot {
                commit = try await saveSnapshot(
                    targetTriptychID,
                    settings,
                    expectedRevision
                )
            } else {
                guard let capabilities else {
                    throw WorkspaceRegistryError.incompleteWorkspace
                }
                commit = try await capabilities.workspace.saveTriptychSettings(
                    targetTriptychID,
                    settings,
                    expectedRevision
                )
            }
            guard commit.triptychID == targetTriptychID else {
                throw WorkspaceSettingsMutationError.triptychChanged
            }
            let targetIsCurrent = snapshot.activeTriptychID == targetTriptychID
            if targetIsCurrent {
                installPortableSettings(WorkspacePortableSettingsRead(
                    triptychID: targetTriptychID,
                    settings: commit.snapshot.settings,
                    state: .current(commit.snapshot.revision)
                ))
            }
            let warning: String?
            if !targetIsCurrent {
                warning = String(localized: "The settings were saved to the Triptych where the edit began. Reload Properties to show the currently active Triptych.", table: "Localizable", bundle: .module)
            } else if commit.derivedRefreshWarning != nil {
                warning = String(localized: "Portable settings were saved. Research views will refresh when the workspace is available.", table: "Localizable", bundle: .module)
            } else {
                warning = nil
            }
            return WorkspaceSettingsSaveResult(
                warning: warning,
                targetIsCurrent: targetIsCurrent
            )
        } catch let error as ScholiumApplicationError
            where error.mutationRequiresReconciliation {
            let reread: WorkspacePortableSettingsRead
            do {
                if let loadPortableSettingsSnapshot {
                    reread = try await loadPortableSettingsSnapshot(targetTriptychID)
                } else if let capabilities {
                    reread = try await capabilities.workspace.loadPortableSettings(
                        targetTriptychID
                    )
                } else {
                    throw error
                }
            } catch {
                settingsReconciliationRequiredTriptychIDs.insert(targetTriptychID)
                throw WorkspaceSettingsMutationError.reconciliationRequired
            }
            let targetIsCurrent = snapshot.activeTriptychID == targetTriptychID
            if targetIsCurrent {
                installPortableSettings(reread)
            }
            if case .current = reread.state, reread.settings == settings {
                return WorkspaceSettingsSaveResult(
                    warning: targetIsCurrent
                        ? String(localized: "Portable settings were reread and the requested save is present.", table: "Localizable", bundle: .module)
                        : String(localized: "The settings were saved to the Triptych where the edit began. Reload Properties to show the currently active Triptych.", table: "Localizable", bundle: .module),
                    targetIsCurrent: targetIsCurrent
                )
            }
            throw WorkspaceSettingsMutationError.commitRequiresReview(
                error.localizedDescription
            )
        }
    }

    private func installPortableSettings(_ read: WorkspacePortableSettingsRead) {
        guard snapshot.activeTriptychID == read.triptychID else { return }
        snapshot.triptychSettings = read.settings
        snapshot.settingsRevision = read.state.editableRevision
        snapshot.portableSettingsState = read.state
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
        replaceSnapshot(try await capabilities.workspace.configureWorkspace(
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

    func refreshZoteroLibraryInfo() async throws -> ZoteroLibraryInfo {
        guard let capabilities else {
            return ZoteroLibraryInfo(status: .appUnavailable, lastSuccessfulConnection: nil)
        }
        return try await capabilities.zotero.refreshZoteroLibraryInfo()
    }

    func researchSkillRegistrations() async throws
        -> ResearchSkillRegistrationSnapshot
    {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.researchSkillRegistrations(id)
    }

    func saveResearchSkillRegistrations(
        _ document: ResearchSkillRegistrationDocument,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchSkillRegistrationSnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.saveResearchSkillRegistrations(
            id,
            document,
            expectedRevision
        )
    }

    func academicActionProfiles() async throws -> ResearchAcademicProfileSnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.academicActionProfiles(id)
    }

    func saveAcademicActionProfiles(
        _ document: ResearchAcademicProfileDocument,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchAcademicProfileSnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.saveAcademicActionProfiles(
            id,
            document,
            expectedRevision
        )
    }

    func collaborationPolicy() async throws -> ResearchCollaborationPolicySnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.collaborationPolicy(id)
    }

    func saveCollaborationPolicy(
        _ document: ResearchCollaborationPolicyDocument,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchCollaborationPolicySnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.saveCollaborationPolicy(
            id,
            document,
            expectedRevision
        )
    }

    func researchMethod(for actionID: ResearchActionID) async throws
        -> ResearchMethodSnapshot
    {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.researchMethod(id, actionID)
    }

    func saveResearchMethod(
        registrationKey: ResearchSkillRegistrationKey,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.saveResearchMethod(
            id,
            registrationKey,
            source,
            expectedRevision
        )
    }

    func registerExternalResearchMethod(
        actionID: ResearchActionID,
        displayName: String,
        primaryMarkdownPath: String,
        skillFolderPath: String?,
        expectedRegistrationRevision: DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.registerExternalResearchMethod(
            id,
            actionID,
            displayName,
            primaryMarkdownPath,
            skillFolderPath,
            expectedRegistrationRevision
        )
    }

    func createResearchMethod(
        actionID: ResearchActionID,
        displayName: String,
        source: String,
        expectedRegistrationRevision: DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.createResearchMethod(
            id,
            actionID,
            displayName,
            source,
            expectedRegistrationRevision
        )
    }

    func restorePreviousResearchMethod(
        registrationKey: ResearchSkillRegistrationKey,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.restorePreviousResearchMethod(
            id,
            registrationKey,
            expectedRevision
        )
    }

    func restoreDefaultResearchMethod(
        actionID: ResearchActionID,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.restoreDefaultResearchMethod(
            id,
            actionID,
            expectedRevision
        )
    }

    func philosophicalPractices() async throws -> [ResearchPracticeSnapshot] {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.philosophicalPractices(id)
    }

    func createPhilosophicalPractice(
        title: String,
        source: String
    ) async throws -> ResearchPracticeSnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.createPhilosophicalPractice(
            id,
            title,
            source
        )
    }

    func savePhilosophicalPractice(
        relativePath: String,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchPracticeSnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.savePhilosophicalPractice(
            id,
            relativePath,
            source,
            expectedRevision
        )
    }

    func restorePreviousPhilosophicalPractice(
        relativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchPracticeSnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance
            .restorePreviousPhilosophicalPractice(id, relativePath, expectedRevision)
    }

    func citationMethodStatus() async throws -> ResearchCitationMethodStatus {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.citationMethodStatus(workspaceID)
    }

    func activateCitationMethod(
        citationStyle: String,
        expectedConfigurationRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.activateCitationMethod(
            workspaceID,
            ResearchCitationMethodSelection(
                citationStyle: citationStyle
            ),
            expectedConfigurationRevision
        )
    }

    func clearCitationMethod(
        expectedConfigurationRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.clearCitationMethod(
            workspaceID,
            expectedConfigurationRevision
        )
    }

    func recoveryPolicy() async throws -> ResearchRecoveryPolicySnapshot {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.recoveryPolicy(workspaceID)
    }

    func prepareRecoveryPolicyChange(
        _ retention: SettledSnapshotRetention,
        expectedRevision: DocumentFingerprint?
    ) async throws -> ResearchRecoveryPolicyChangePreview {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.prepareRecoveryPolicyChange(
            workspaceID,
            retention,
            expectedRevision
        )
    }

    func applyRecoveryPolicyChange(
        _ preview: ResearchRecoveryPolicyChangePreview
    ) async throws -> ResearchRecoveryPolicyApplyOutcome {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.applyRecoveryPolicyChange(
            workspaceID,
            preview
        )
    }

    func openExternal(_ url: URL) {
        _ = capabilities?.machine.openExternal(url)
    }

    func showToast(_ message: String) {
        toastMessage = message
    }

    func dismissToast(_ message: String) {
        guard toastMessage == message else { return }
        toastMessage = nil
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
