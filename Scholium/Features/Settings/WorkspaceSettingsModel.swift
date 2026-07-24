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

struct ResearchActionProfileCopyOutcome: Equatable, Sendable {
    let copiedTriptychIDs: [UUID]
    let failures: [UUID: String]
}

/// Triptych registration and portable-settings operations used by Settings.
@MainActor
struct WorkspaceSettingsWorkspaceCapabilities {
    let loadSnapshot: (UUID?) async throws -> WorkspaceSettingsSnapshot
    let configureWorkspace: (
        URL, URL, URL, URL, UUID?, String?
    ) async throws -> WorkspaceSettingsSnapshot
    let saveTriptychSettings: (UUID, TriptychSettings) async throws -> WorkspaceSettingsSnapshot
    let discussResponseProfile: (UUID) async throws -> DialogueResponseProfile
    let saveDiscussResponseProfile: (UUID, DialogueResponseProfile) async throws -> Void
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
    let researchSkills: (UUID) async throws -> [ResearchSkillPackage]
    let inspectResearchSkillDraft: (
        UUID, String, String, ResearchSkillOrigin
    ) async throws -> ResearchSkillPackage
    let researchFunctionSkillBindingStatus: (
        UUID, ResearchFunctionID
    ) async throws -> ResearchFunctionSkillBindingStatus
    let saveResearchFunctionSkillSelection: (
        UUID, ResearchFunctionSkillSelection, DocumentFingerprint?
    ) async throws -> ResearchFunctionSkillBindingStatus
    let citationMethodStatus: (UUID) async throws -> ResearchCitationMethodStatus
    let activateCitationMethod: (
        UUID, ResearchCitationMethodSelection, DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus
    let clearCitationMethod: (
        UUID, DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus
    let adoptBundledCitationStarter: (
        UUID, DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus
    let bibliographyMethodStatus: (
        UUID
    ) async throws -> RecommendedBibliographyMethodStatus
    let setBibliographyMethod: (
        UUID, String?, DocumentFingerprint?
    ) async throws -> RecommendedBibliographyMethodStatus
    let createResearchSkill: (UUID, String, String) async throws -> ResearchSkillPackage
    let duplicateBundledResearchSkill: (UUID, String, String) async throws -> ResearchSkillPackage
    let renameResearchSkill: (UUID, String, String, DocumentFingerprint) async throws -> ResearchSkillPackage
    let saveResearchSkill: (UUID, String, String, DocumentFingerprint) async throws -> ResearchSkillPackage
    let deleteResearchSkill: (UUID, String, DocumentFingerprint) async throws -> Void
    let researchSkillResourcePaths: (UUID, String) async throws -> [String]
    let researchSkillResource: (UUID, String, String) async throws -> String
    let prepareResearchSkillMaintenance: (
        UUID, ResearchSkillMaintenanceRequest
    ) async throws -> ResearchSkillMaintenancePreparation
    let applyResearchSkillMaintenance: (
        UUID,
        ResearchSkillMaintenancePreparation,
        ResearchSkillMaintenanceConfirmationToken
    ) async throws -> ResearchSkillMaintenanceApplyOutcome
    let researchSkillMaintenanceSnapshots: (
        UUID, String?
    ) async throws -> ResearchSkillMaintenanceSnapshotListing
    let restoreResearchSkillMaintenance: (
        UUID, UUID, ResearchSkillMaintenanceExpectedCurrentState
    ) async throws -> ResearchSkillMaintenanceRestoreOutcome
    let researchSkillsURL: (UUID) async throws -> URL
    let workingMethodBindings: (
        UUID
    ) async throws -> ResearchWorkingMethodBindingSnapshot?
    let installDefaultWorkingMethods: (
        UUID
    ) async throws -> ResearchWorkingMethodBindingSnapshot
    let saveWorkingMethod: (
        UUID,
        ResearchActionID,
        String,
        DocumentFingerprint,
        DocumentFingerprint
    ) async throws -> ResearchSkillPackage
    let disableWorkingMethod: (
        UUID, ResearchActionID, DocumentFingerprint
    ) async throws -> ResearchWorkingMethodBindingSnapshot
    let activateResearcherSkill: (
        UUID, String, ResearchActionID, DocumentFingerprint
    ) async throws -> ResearchWorkingMethodBindingSnapshot
    let restoreBundledWorkingMethod: (
        UUID,
        ResearchActionID,
        ResearchWorkingMethodExpectedPackageState,
        DocumentFingerprint
    ) async throws -> ResearchWorkingMethodRestoreOutcome
    let actionProfiles: (UUID) async throws -> ResearchActionProfileSnapshot?
    let saveActionProfile: (
        UUID,
        ResearchActionProfileBinding,
        DocumentFingerprint?
    ) async throws -> ResearchActionProfileSnapshot
    let removeActionProfile: (
        UUID, ResearchActionID, DocumentFingerprint
    ) async throws -> ResearchActionProfileSnapshot
    let saveActionProfileDocument: (
        UUID, ResearchActionProfileDocument, DocumentFingerprint?
    ) async throws -> ResearchActionProfileSnapshot
    let stageResearcherSkillInstallation: (
        URL
    ) async throws -> ResearchSkillInstallationPreparation
    let installResearcherSkill: (
        ResearchSkillInstallationPreparation, [UUID]
    ) async throws -> ResearchSkillInstallationOutcome
    let discardResearcherSkillInstallation: (UUID) async -> Void
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

extension ResearchSkillMaintenancePreparation {
    /// Settings remains fail-closed until both independent checks pass for the
    /// exact package revision represented by the opaque confirmation token.
    var isReadyForSettingsApply: Bool {
        guard evaluation.structuralStatus == .passed,
              evaluation.externalStatus == .passed,
              evaluation.proposedPackageRevision == proposedPackageRevision,
              let confirmationToken else { return false }
        return confirmationToken.preparationID == id
            && confirmationToken.packageID == request.packageID
            && confirmationToken.expectedPackageRevision == request.expectedPackageRevision
            && confirmationToken.proposedPackageRevision == proposedPackageRevision
    }
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
    @Published private(set) var toastMessage: String?
    @Published var workspaceRecoveryMessage: String?
    @Published private(set) var activeTriptychServicesID: UUID?

    let cssSnippetStore: CSSSnippetStore?

    private let capabilities: WorkspaceSettingsCapabilities?
    private let loadSnapshot: SnapshotLoader?
    private let activateSnapshot: TriptychActivator?
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
            await perform {
                try await capabilities.workspace.loadSnapshot(self.snapshot.activeTriptychID)
            }
        } else if let loadSnapshot {
            await perform { try await loadSnapshot() }
        }
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

    func saveTriptychSettings(_ settings: TriptychSettings) async throws {
        if let saveSnapshot {
            replaceSnapshot(try await saveSnapshot(settings))
            return
        }
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        replaceSnapshot(try await capabilities.workspace.saveTriptychSettings(id, settings))
    }

    func discussResponseProfile() async throws -> DialogueResponseProfile {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.workspace.discussResponseProfile(id)
    }

    func saveDiscussResponseProfile(_ profile: DialogueResponseProfile) async throws {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await capabilities.workspace.saveDiscussResponseProfile(id, profile)
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

    func researchSkills() async throws -> [ResearchSkillPackage] {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.researchSkills(id)
    }

    func workingMethodBindings() async throws -> ResearchWorkingMethodBindingSnapshot? {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.workingMethodBindings(id)
    }

    func installDefaultWorkingMethods() async throws -> ResearchWorkingMethodBindingSnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.installDefaultWorkingMethods(id)
    }

    func saveWorkingMethod(
        for actionID: ResearchActionID,
        source: String,
        expectedPackageRevision: DocumentFingerprint,
        expectedBindingRevision: DocumentFingerprint
    ) async throws -> ResearchSkillPackage {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.saveWorkingMethod(
            id,
            actionID,
            source,
            expectedPackageRevision,
            expectedBindingRevision
        )
    }

    func disableWorkingMethod(
        for actionID: ResearchActionID,
        expectedBindingRevision: DocumentFingerprint
    ) async throws -> ResearchWorkingMethodBindingSnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.disableWorkingMethod(
            id,
            actionID,
            expectedBindingRevision
        )
    }

    func activateResearcherSkill(
        packageID: String,
        for actionID: ResearchActionID,
        expectedBindingRevision: DocumentFingerprint
    ) async throws -> ResearchWorkingMethodBindingSnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.activateResearcherSkill(
            id,
            packageID,
            actionID,
            expectedBindingRevision
        )
    }

    func restoreBundledWorkingMethod(
        for actionID: ResearchActionID,
        expectedPackageState: ResearchWorkingMethodExpectedPackageState,
        expectedBindingRevision: DocumentFingerprint
    ) async throws -> ResearchWorkingMethodRestoreOutcome {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.restoreBundledWorkingMethod(
            id,
            actionID,
            expectedPackageState,
            expectedBindingRevision
        )
    }

    func actionProfiles() async throws -> ResearchActionProfileSnapshot? {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.actionProfiles(id)
    }

    func saveActionProfile(
        _ binding: ResearchActionProfileBinding,
        expectedDocumentRevision: DocumentFingerprint?
    ) async throws -> ResearchActionProfileSnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.saveActionProfile(
            id,
            binding,
            expectedDocumentRevision
        )
    }

    func removeActionProfile(
        actionID: ResearchActionID,
        expectedDocumentRevision: DocumentFingerprint
    ) async throws -> ResearchActionProfileSnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.removeActionProfile(
            id,
            actionID,
            expectedDocumentRevision
        )
    }

    func saveActionProfileDocument(
        _ document: ResearchActionProfileDocument,
        expectedDocumentRevision: DocumentFingerprint?
    ) async throws -> ResearchActionProfileSnapshot {
        guard let id = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.saveActionProfileDocument(
            id,
            document,
            expectedDocumentRevision
        )
    }

    /// Creates explicit independent Profile copies. Package bytes are never
    /// synchronized here: every destination must already contain its own
    /// compatible Skill snapshot from staged installation.
    func copyActionProfile(
        _ binding: ResearchActionProfileBinding,
        to triptychIDs: [UUID]
    ) async -> ResearchActionProfileCopyOutcome {
        guard let capabilities else {
            return ResearchActionProfileCopyOutcome(
                copiedTriptychIDs: [],
                failures: Dictionary(uniqueKeysWithValues: triptychIDs.map {
                    ($0, WorkspaceRegistryError.incompleteWorkspace.localizedDescription)
                })
            )
        }
        var revisions: [UUID: DocumentFingerprint?] = [:]
        var failures: [UUID: String] = [:]
        for id in triptychIDs {
            do {
                let packages = try await capabilities.researchGuidance.researchSkills(id)
                guard packages.contains(where: {
                    $0.origin == .triptych
                        && $0.id == binding.packageID
                        && $0.isValid
                        && $0.supports(binding.profile.actionID)
                }) else {
                    throw ResearchActionProfileStorageError.packageDoesNotSupportAction(
                        packageID: binding.packageID,
                        actionID: binding.profile.actionID
                    )
                }
                revisions[id] = try await capabilities.researchGuidance
                    .actionProfiles(id)?.revision
            } catch {
                failures[id] = error.localizedDescription
            }
        }
        var copied: [UUID] = []
        for id in triptychIDs where failures[id] == nil {
            do {
                _ = try await capabilities.researchGuidance.saveActionProfile(
                    id,
                    binding,
                    revisions[id] ?? nil
                )
                copied.append(id)
            } catch {
                failures[id] = error.localizedDescription
            }
        }
        return ResearchActionProfileCopyOutcome(
            copiedTriptychIDs: copied,
            failures: failures
        )
    }

    func stageResearcherSkillInstallation(
        from directoryURL: URL
    ) async throws -> ResearchSkillInstallationPreparation {
        guard let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance
            .stageResearcherSkillInstallation(directoryURL)
    }

    func installResearcherSkill(
        _ preparation: ResearchSkillInstallationPreparation,
        to triptychIDs: [UUID]
    ) async throws -> ResearchSkillInstallationOutcome {
        guard let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.installResearcherSkill(
            preparation,
            triptychIDs
        )
    }

    func discardResearcherSkillInstallation(preparationID: UUID) async {
        await capabilities?.researchGuidance
            .discardResearcherSkillInstallation(preparationID)
    }

    func inspectResearchSkillDraft(
        id: String,
        source: String,
        origin: ResearchSkillOrigin
    ) async -> ResearchSkillPackage? {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            return nil
        }
        return try? await capabilities.researchGuidance.inspectResearchSkillDraft(
            workspaceID,
            id,
            source,
            origin
        )
    }

    func citationMethodStatus() async throws -> ResearchCitationMethodStatus {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.citationMethodStatus(workspaceID)
    }

    func researchFunctionSkillBindingStatus(
        for function: ResearchFunctionID
    ) async throws -> ResearchFunctionSkillBindingStatus {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.researchFunctionSkillBindingStatus(
            workspaceID,
            function
        )
    }

    func bibliographyMethodStatus() async throws -> RecommendedBibliographyMethodStatus {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.bibliographyMethodStatus(workspaceID)
    }

    func setBibliographyMethod(
        packageID: String?,
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> RecommendedBibliographyMethodStatus {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.setBibliographyMethod(
            workspaceID,
            packageID,
            expectedBindingRevision
        )
    }

    func saveResearchFunctionSkillSelection(
        _ selection: ResearchFunctionSkillSelection,
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> ResearchFunctionSkillBindingStatus {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.saveResearchFunctionSkillSelection(
            workspaceID,
            selection,
            expectedBindingRevision
        )
    }

    func activateCitationMethod(
        packageID: String,
        citationStyle: String,
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.activateCitationMethod(
            workspaceID,
            ResearchCitationMethodSelection(
                packageID: packageID,
                citationStyle: citationStyle
            ),
            expectedBindingRevision
        )
    }

    func clearCitationMethod(
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.clearCitationMethod(
            workspaceID,
            expectedBindingRevision
        )
    }

    func adoptBundledCitationStarter(
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.adoptBundledCitationStarter(
            workspaceID,
            expectedBindingRevision
        )
    }

    func createResearchSkill(id: String, source: String) async throws -> ResearchSkillPackage {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.createResearchSkill(workspaceID, id, source)
    }

    func duplicateBundledResearchSkill(
        id: String,
        as newID: String
    ) async throws -> ResearchSkillPackage {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.duplicateBundledResearchSkill(
            workspaceID,
            id,
            newID
        )
    }

    func renameResearchSkill(
        id: String,
        to newID: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchSkillPackage {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.renameResearchSkill(
            workspaceID,
            id,
            newID,
            expectedRevision
        )
    }

    func saveResearchSkill(
        id: String,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchSkillPackage {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.saveResearchSkill(
            workspaceID,
            id,
            source,
            expectedRevision
        )
    }

    func deleteResearchSkill(
        id: String,
        expectedRevision: DocumentFingerprint
    ) async throws {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await capabilities.researchGuidance.deleteResearchSkill(
            workspaceID,
            id,
            expectedRevision
        )
    }

    func researchSkillResourcePaths(id: String) async throws -> [String] {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.researchSkillResourcePaths(workspaceID, id)
    }

    func researchSkillResource(id: String, relativePath: String) async throws -> String {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.researchSkillResource(
            workspaceID,
            id,
            relativePath
        )
    }

    func prepareResearchSkillMaintenance(
        _ request: ResearchSkillMaintenanceRequest
    ) async throws -> ResearchSkillMaintenancePreparation {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.prepareResearchSkillMaintenance(
            workspaceID,
            request
        )
    }

    func applyResearchSkillMaintenance(
        _ preparation: ResearchSkillMaintenancePreparation
    ) async throws -> ResearchSkillMaintenanceApplyOutcome {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        guard preparation.isReadyForSettingsApply,
              let confirmationToken = preparation.confirmationToken else {
            throw ResearchSkillMaintenanceError.evaluationFailed
        }
        return try await capabilities.researchGuidance.applyResearchSkillMaintenance(
            workspaceID,
            preparation,
            confirmationToken
        )
    }

    func restoreResearchSkillMaintenance(
        snapshotID: UUID,
        expectedCurrentState: ResearchSkillMaintenanceExpectedCurrentState
    ) async throws -> ResearchSkillMaintenanceRestoreOutcome {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.restoreResearchSkillMaintenance(
            workspaceID,
            snapshotID,
            expectedCurrentState
        )
    }

    func researchSkillMaintenanceSnapshots(
        packageID: String? = nil
    ) async throws -> ResearchSkillMaintenanceSnapshotListing {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.researchSkillMaintenanceSnapshots(
            workspaceID,
            packageID
        )
    }

    func researchSkillsURL() async throws -> URL {
        guard let workspaceID = snapshot.activeTriptychID, let capabilities else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await capabilities.researchGuidance.researchSkillsURL(workspaceID)
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

    private func perform(
        _ operation: @MainActor () async throws -> WorkspaceSettingsSnapshot
    ) async {
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
            guard refreshGeneration == generation else { return }
            replaceSnapshot(refreshedSnapshot)
        } catch is CancellationError {
            return
        } catch {
            guard refreshGeneration == generation else { return }
            errorMessage = error.localizedDescription
        }
    }
}
