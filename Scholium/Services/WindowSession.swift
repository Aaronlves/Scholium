import ScholiumContracts
import Combine
import Foundation
import OSLog
import ScholiumApplication
#if canImport(AppKit)
import AppKit
#endif

@MainActor
private struct WorkspaceEditorFlushRegistration {
    let token: UUID
    let triptychID: UUID
    let windowID: UUID
    let relativePath: String
    let flush: @MainActor () async throws -> Void
}

@MainActor
private struct PendingWorkspaceInstallation {
    let token: UUID
    let task: Task<Void, Error>
}

enum WorkspaceActivationKind: Equatable, Sendable {
    case initial
    case replacement(previous: TriptychRuntimeIdentity)
}

/// The one app-delivery handoff for a Triptych activation. Window models use
/// this typed value to replace all three capability actors together; they do
/// not subscribe to a handle's Application event source independently.
struct WorkspaceActivation: Sendable {
    let kind: WorkspaceActivationKind
    let capabilities: WindowWorkspaceCapabilities
    let snapshot: WorkspaceSnapshot

    var runtimeIdentity: TriptychRuntimeIdentity { capabilities.runtimeIdentity }
    var workspaceID: UUID { runtimeIdentity.triptychID }

    func replaces(_ identity: TriptychRuntimeIdentity) -> Bool {
        guard case .replacement(let previous) = kind else { return false }
        return previous == identity
    }
}

/// The complete set of one Triptych's narrow frontend capabilities. The
/// concrete Application handle remains private to `WorkspaceStore`.
struct WindowWorkspaceCapabilities: Sendable {
    let id: UUID
    let runtimeIdentity: TriptychRuntimeIdentity
    let assignment: TriptychAssignment
    let documents: any DocumentUseCases
    let discovery: any DiscoveryUseCases
    let research: any ResearchUseCases
}

/// Machine-local persistence for the one app-wide agent-application choice.
/// Filesystem I/O stays at the delivery composition boundary rather than in
/// the handoff controller or its views.
@MainActor
struct FileAgentApplicationPreferenceStore: AgentApplicationPreferencePersisting {
    private struct Envelope: Codable {
        let schema: String
        let application: RememberedAgentApplication
    }

    private static let schema = "scholium-agent-application-preference-v1"
    private static let maximumPreferenceBytes = 1_048_576
    private let fileURL: URL
    private let fileManager: FileManager

    init(applicationSupportURL: URL, fileManager: FileManager = .default) {
        fileURL = applicationSupportURL.appendingPathComponent(
            "AgentApplicationHandoff.json",
            isDirectory: false
        )
        self.fileManager = fileManager
    }

    func load() throws -> RememberedAgentApplication? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber,
              size.intValue <= Self.maximumPreferenceBytes else {
            throw AgentApplicationHandoffError.invalidPreference
        }
        let envelope = try JSONDecoder().decode(
            Envelope.self,
            from: Data(contentsOf: fileURL)
        )
        guard envelope.schema == Self.schema else {
            throw AgentApplicationHandoffError.unsupportedPreference
        }
        guard !envelope.application.bookmarkData.isEmpty,
              envelope.application.bookmarkData.count <= Self.maximumPreferenceBytes else {
            throw AgentApplicationHandoffError.invalidPreference
        }
        return RememberedAgentApplication(
            displayName: AgentApplicationDisplayName.sanitized(
                envelope.application.displayName
            ),
            bundleIdentifier: envelope.application.bundleIdentifier,
            bookmarkData: envelope.application.bookmarkData
        )
    }

    func save(_ application: RememberedAgentApplication) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(Envelope(
            schema: Self.schema,
            application: application
        ))
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    func forget() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}

/// The macOS delivery adapter over one live Application runtime.
///
/// WorkspaceRuntime owns every repository, index, watcher, research store,
/// and workspace lifetime. This object publishes immutable GUI snapshots,
/// coordinates editor flushes across windows, and owns app-only services.
@MainActor
final class WorkspaceStore: ObservableObject {
    private static let publicationLogger = Logger(
        subsystem: "com.scholium.app",
        category: "WorkspacePublication"
    )
    let applicationSupportURL: URL
    let applicationRuntime: WorkspaceRuntime
    let cssSnippetStore: CSSSnippetStore
    let zoteroBridge: ZoteroBridge
    let commandLineToolInstaller: CommandLineToolInstaller
    let agentApplicationHandoff: AgentApplicationHandoffController
    let agentNoteChangePresentations: AgentNoteChangePresentationCoordinator
    private(set) var localAgentBridge: LocalAgentBridgeServer?
    private(set) var localAgentBridgeStartupFailure: LocalAgentBridgeError?

    @Published private(set) var workspaceSnapshots: [UUID: WorkspaceSnapshot] = [:]
    @Published private(set) var workspaceEventGenerations: [UUID: UInt64] = [:]
    @Published private(set) var workspaceDerivedRefreshStatuses: [
        UUID: WorkspaceDerivedRefreshStatus
    ] = [:]
    /// Latest accepted typed Application event per active Triptych. This is
    /// the narrow delivery adapter for event-specific projections such as a
    /// stable-identity move; WorkspaceStore remains the only stream consumer.
    @Published private(set) var workspaceEvents: [UUID: WorkspaceEvent] = [:]
    @Published private(set) var workspaceActivations: [UUID: WorkspaceActivation] = [:]
    @Published private(set) var latestWorkspaceActivation: WorkspaceActivation?

    private var handles: [UUID: WorkspaceHandle] = [:]
    private var eventTasks: [UUID: Task<Void, Never>] = [:]
    private var installationTasks: [UUID: PendingWorkspaceInstallation] = [:]
    private var eventGates: [UUID: WorkspaceEventGenerationGate] = [:]
    private var editorFlushRegistrations: [UUID: WorkspaceEditorFlushRegistration] = [:]

    init(applicationSupportURL requestedURL: URL) throws {
        let applicationSupportURL = requestedURL.standardizedFileURL
        try Self.validateApplicationSupportURL(applicationSupportURL)
        self.applicationSupportURL = applicationSupportURL
        let workspaceURL = applicationSupportURL.appendingPathComponent(
            "Workspace",
            isDirectory: true
        )
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: applicationSupportURL,
            workspaceRegistryStorageURL: workspaceURL
        )))
        applicationRuntime = runtime
        cssSnippetStore = CSSSnippetStore(operations: applicationRuntime.styles)
        zoteroBridge = ZoteroBridge(operations: applicationRuntime.zotero)
        commandLineToolInstaller = CommandLineToolInstaller()
        agentApplicationHandoff = AgentApplicationHandoffController(
            applicationSupportURL: applicationSupportURL
        )
        let agentNoteChangePresentations = AgentNoteChangePresentationCoordinator()
        self.agentNoteChangePresentations = agentNoteChangePresentations
        do {
            localAgentBridge = try LocalAgentBridgeServer(
                applicationSupportURL: applicationSupportURL
            ) { [weak self] request in
                try Task.checkCancellation()
                guard let self else { throw LocalAgentBridgeError.unavailable }
                let handle = try await runtime.openWorkspace(id: request.triptychID)
                try Task.checkCancellation()
                switch request.operation {
                case .submit:
                    guard let changeRequest = request.changeRequest else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    var record = try await handle.research
                        .submitAgentNoteChangeRequestFromBridge(
                            changeRequest,
                            coordinationKey: request.coordinationKey
                        )
                    if record.isUnresolved {
                        try await self.flushEditors(in: request.triptychID)
                        try Task.checkCancellation()
                        record = try await handle.research
                            .applyStandingPermissionToAgentNoteChangeRequest(
                                id: record.id
                            )
                    }
                    await agentNoteChangePresentations.receive(
                        record,
                        intent: .submit
                    )
                    return record
                case .status:
                    guard let requestID = request.changeRequestID else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    let record = try await handle.research.agentNoteChangeRequestFromBridge(
                        id: requestID,
                        coordinationKey: request.coordinationKey
                    )
                    await agentNoteChangePresentations.receive(
                        record,
                        intent: .showExisting
                    )
                    return record
                case .cancel:
                    guard let requestID = request.changeRequestID else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    let record = try await handle.research
                        .cancelAgentNoteChangeRequestFromBridge(
                            id: requestID,
                            coordinationKey: request.coordinationKey
                        )
                    await agentNoteChangePresentations.receive(
                        record,
                        intent: .cancel
                    )
                    return record
                }
            }
            localAgentBridgeStartupFailure = nil
        } catch let error as LocalAgentBridgeError {
            localAgentBridge = nil
            localAgentBridgeStartupFailure = error
            Self.publicationLogger.error(
                "Local Agent bridge startup failed: \(error.localizedDescription, privacy: .public)"
            )
        } catch {
            localAgentBridge = nil
            localAgentBridgeStartupFailure = .systemCall("start", EIO)
            Self.publicationLogger.error(
                "Local Agent bridge startup failed with an unclassified local error."
            )
        }
    }

    private static func validateApplicationSupportURL(_ url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        let probe = url.appendingPathComponent(
            ".scholium-storage-probe-\(UUID().uuidString.lowercased())",
            isDirectory: false
        )
        do {
            try Data().write(to: probe, options: .withoutOverwriting)
            try fileManager.removeItem(at: probe)
        } catch {
            try? fileManager.removeItem(at: probe)
            throw error
        }
    }

    deinit {
        let bridge = localAgentBridge
        let runtime = applicationRuntime
        Task {
            if let bridge {
                while !(await bridge.stopAndWait(timeout: 30)) {
                    await Task.yield()
                }
            }
            await runtime.shutdown()
        }
    }

    func shutdownApplicationRuntime() async {
        if let localAgentBridge,
           !(await localAgentBridge.stopAndWait()) {
            Self.publicationLogger.fault(
                "Application runtime shutdown was deferred because the local Agent bridge handler did not stop."
            )
            return
        }
        let pendingInstallations = installationTasks.values.map(\.task)
        installationTasks.removeAll()
        pendingInstallations.forEach { $0.cancel() }
        let tasks = eventTasks.values
        eventTasks.removeAll()
        tasks.forEach { $0.cancel() }
        handles.removeAll()
        eventGates.removeAll()
        workspaceSnapshots.removeAll()
        workspaceEventGenerations.removeAll()
        workspaceDerivedRefreshStatuses.removeAll()
        workspaceEvents.removeAll()
        workspaceActivations.removeAll()
        latestWorkspaceActivation = nil
        for task in pendingInstallations {
            _ = try? await task.value
        }
        await applicationRuntime.shutdown()
    }

    func revealInFinder(_ url: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }

    @discardableResult
    func openExternal(_ url: URL) -> Bool {
        #if canImport(AppKit)
        return NSWorkspace.shared.open(url)
        #else
        return false
        #endif
    }

    func registeredTriptychs() async throws -> [TriptychAssignment] {
        try await applicationRuntime.availableWorkspaces()
    }

    func registeredVaults() async -> [RegisteredVault] {
        (try? await applicationRuntime.registeredVaults()) ?? []
    }

    func defaultTriptych() async throws -> TriptychAssignment {
        try await applicationRuntime.defaultWorkspace()
    }

    func resolveVault(_ selector: String) async throws -> RegisteredVault {
        try await applicationRuntime.resolveVault(selector)
    }

    func reconcileTriptychIdentity(id: UUID) async throws -> TriptychAssignment {
        let previous = handles[id]?.runtimeIdentity
        let assignment = try await applicationRuntime.reconcileWorkspaceIdentity(id: id)
        if let previous {
            let replacement = try await applicationRuntime.openWorkspace(id: assignment.id)
            try await install(handle: replacement, replacing: previous)
        }
        return assignment
    }

    func reidentifyTriptych(
        id currentID: UUID,
        as stableID: UUID
    ) async throws -> TriptychAssignment {
        let previous = handles[currentID]?.runtimeIdentity
        let assignment = try await applicationRuntime.reidentifyWorkspace(
            id: currentID,
            as: stableID
        )
        if let previous {
            let replacement = try await applicationRuntime.openWorkspace(id: assignment.id)
            try await install(handle: replacement, replacing: previous)
        }
        return assignment
    }

    func registerVault(
        path: URL,
        name: String?,
        role: VaultRole,
        stableID: UUID? = nil
    ) async throws -> RegisteredVault {
        let affected = handles.values.compactMap { handle in
            handle.assignment.vaults.values.contains(where: {
                $0.canonicalPath == path.resolvingSymlinksInPath().standardizedFileURL.path
            }) ? handle.runtimeIdentity : nil
        }
        let updated = try await applicationRuntime.registerVault(
            path: path,
            name: name,
            role: role,
            stableID: stableID
        )
        for previous in affected {
            let replacement = try await applicationRuntime.openWorkspace(
                id: previous.triptychID
            )
            try await install(handle: replacement, replacing: previous)
        }
        return updated
    }

    func savedSearches() async throws -> [SavedSearch] {
        try await applicationRuntime.savedSearches()
    }

    func saveSavedSearches(_ searches: [SavedSearch]) async throws {
        try await applicationRuntime.saveSavedSearches(searches)
    }

    func windowSession(id: UUID) async throws -> WindowSessionSnapshot? {
        try await applicationRuntime.windowSession(id: id)
    }

    func saveWindowSession(_ snapshot: WindowSessionSnapshot) async throws {
        try await applicationRuntime.saveWindowSession(snapshot)
    }

    func saveWindowSession(
        _ snapshot: WindowSessionSnapshot,
        attempt: LifecycleAttemptID
    ) async throws {
        try await applicationRuntime.saveWindowSession(
            snapshot,
            generation: attempt.rawValue
        )
    }

    private func workspaceHandle(id: UUID) async throws -> WorkspaceHandle {
        let handle = try await applicationRuntime.openWorkspace(id: id)
        try await install(handle: handle)
        return handle
    }

    func workspaceCapabilities(id: UUID) async throws -> WindowWorkspaceCapabilities {
        capabilities(from: try await workspaceHandle(id: id))
    }

    private func configureTriptych(
        paperAnalysisURL: URL,
        topicKnowledgeURL: URL,
        outputURL: URL,
        portableContainerURL: URL,
        triptychID: UUID? = nil,
        triptychName: String? = nil
    ) async throws -> WorkspaceHandle {
        let selectedPaths = Set([
            paperAnalysisURL,
            topicKnowledgeURL,
            outputURL,
        ].map { $0.resolvingSymlinksInPath().standardizedFileURL.path })
        let previous = triptychID.flatMap { handles[$0]?.runtimeIdentity }
            ?? handles.values.first(where: { handle in
                Set(handle.assignment.vaults.values.map(\.canonicalPath)) == selectedPaths
            })?.runtimeIdentity
        let handle = try await applicationRuntime.configureTriptych(
            paperAnalysisURL: paperAnalysisURL,
            topicKnowledgeURL: topicKnowledgeURL,
            outputURL: outputURL,
            portableContainerURL: portableContainerURL,
            triptychID: triptychID,
            triptychName: triptychName
        )
        try await install(handle: handle, replacing: previous)
        return handle
    }

    func configureTriptychCapabilities(
        paperAnalysisURL: URL,
        topicKnowledgeURL: URL,
        outputURL: URL,
        portableContainerURL: URL,
        triptychID: UUID? = nil,
        triptychName: String? = nil
    ) async throws -> WindowWorkspaceCapabilities {
        capabilities(from: try await configureTriptych(
            paperAnalysisURL: paperAnalysisURL,
            topicKnowledgeURL: topicKnowledgeURL,
            outputURL: outputURL,
            portableContainerURL: portableContainerURL,
            triptychID: triptychID,
            triptychName: triptychName
        ))
    }

    func portableContainerURL(forWorksURL worksURL: URL) async -> URL? {
        await applicationRuntime.portableContainerURL(forWorksURL: worksURL)
    }

    func vaultConfig(rootURL: URL) async -> VaultConfig {
        let appearance = await applicationRuntime.styles.obsidianAppearance(at: rootURL)
        return VaultConfig(
            path: rootURL,
            name: rootURL.lastPathComponent,
            obsidianConfig: appearance.map {
                VaultConfig.ObsidianConfig(
                    vaultName: $0.vaultName,
                    theme: $0.theme,
                    showLineNumbers: $0.showLineNumbers,
                    defaultViewMode: $0.defaultViewMode,
                    attachmentFolderPath: $0.attachmentFolderPath,
                    newLinkFormat: $0.newLinkFormat
                )
            }
        )
    }

    func settingsSnapshot(preferredTriptychID: UUID?) async throws -> WorkspaceSettingsSnapshot {
        let vaults = await registeredVaults()
        let triptychs = try await registeredTriptychs()
        guard let assignment = preferredTriptychID.flatMap({ preferred in
            triptychs.first { $0.id == preferred }
        }) ?? triptychs.first else {
            return WorkspaceSettingsSnapshot(
                registeredVaults: vaults,
                registeredTriptychs: triptychs
            )
        }
        let handle = try await workspaceHandle(id: assignment.id)
        let settings = try await handle.research.settings()
        var propertyKeys: [WorkspaceVaultSlot: Set<String>] = [:]
        for vault in try await handle.documents.snapshot() {
            propertyKeys[vault.slot] = Set(
                vault.documents.flatMap { $0.document.parsedFrontmatter.keys }
            )
        }
        return WorkspaceSettingsSnapshot(
            registeredVaults: vaults,
            registeredTriptychs: triptychs,
            activeTriptychID: handle.id,
            triptychSettings: settings,
            propertyKeysBySlot: propertyKeys
        )
    }

    func settingsCapabilities() -> WorkspaceSettingsCapabilities {
        WorkspaceSettingsCapabilities(
            workspace: WorkspaceSettingsWorkspaceCapabilities(
                loadSnapshot: { [self] preferredID in
                    try await settingsSnapshot(preferredTriptychID: preferredID)
                },
                configureWorkspace: { [self] paper, topics, works, portable, id, name in
                    let handle = try await configureTriptych(
                        paperAnalysisURL: paper,
                        topicKnowledgeURL: topics,
                        outputURL: works,
                        portableContainerURL: portable,
                        triptychID: id,
                        triptychName: name
                    )
                    return try await settingsSnapshot(preferredTriptychID: handle.id)
                },
                saveTriptychSettings: { [self] id, settings in
                    let handle = try await workspaceHandle(id: id)
                    try await handle.research.saveSettings(settings)
                    return try await settingsSnapshot(preferredTriptychID: id)
                },
                discussResponseProfile: { [self] id in
                    try await workspaceHandle(id: id).research.discussResponseProfile()
                },
                saveDiscussResponseProfile: { [self] id, profile in
                    try await workspaceHandle(id: id).research.saveDiscussResponseProfile(profile)
                },
                portableContainerURL: { [self] url in
                    await portableContainerURL(forWorksURL: url)
                }
            ),
            machine: WorkspaceSettingsMachineCapabilities(
                commandLineToolStatus: { [self] in
                    await commandLineToolInstaller.commandLineToolStatus()
                },
                installCommandLineTool: { [self] in
                    try await commandLineToolInstaller.installCommandLineTool()
                },
                openExternal: { [self] url in openExternal(url) }
            ),
            zotero: WorkspaceSettingsZoteroCapabilities(
                zoteroConnectionInfo: { [self] in await zoteroBridge.connectionInfo() },
                openZotero: { [self] in await zoteroBridge.openZotero() },
                clearZoteroConnectionHistory: {
                    [self] in try await zoteroBridge.clearConnectionHistory()
                },
                refreshZoteroLibraryInfo: { [self] in
                    try await zoteroBridge.refreshLibraryInfo()
                }
            ),
            researchGuidance: WorkspaceSettingsResearchGuidanceCapabilities(
                researchSkills: { [self] id in
                try await workspaceHandle(id: id).research.skills()
            },
            inspectResearchSkillDraft: { [self] workspaceID, id, source, origin in
                try await workspaceHandle(id: workspaceID).research.inspectSkillDraft(
                    id: id,
                    source: source,
                    origin: origin
                )
            },
            researchFunctionSkillBindingStatus: { [self] workspaceID, function in
                try await workspaceHandle(id: workspaceID).research
                    .researchFunctionSkillBindingStatus(for: function)
            },
            saveResearchFunctionSkillSelection: {
                [self] workspaceID, selection, revision in
                try await workspaceHandle(id: workspaceID).research
                    .saveResearchFunctionSkillSelection(
                        selection,
                        expectedBindingRevision: revision
                    )
            },
            citationMethodStatus: { [self] workspaceID in
                try await workspaceHandle(id: workspaceID).research.citationMethodStatus()
            },
            activateCitationMethod: { [self] workspaceID, selection, revision in
                try await workspaceHandle(id: workspaceID).research.activateCitationMethod(
                    selection: selection,
                    expectedBindingRevision: revision
                )
            },
            clearCitationMethod: { [self] workspaceID, revision in
                try await workspaceHandle(id: workspaceID).research.clearCitationMethod(
                    expectedBindingRevision: revision
                )
            },
            adoptBundledCitationStarter: { [self] workspaceID, revision in
                try await workspaceHandle(id: workspaceID).research
                    .adoptBundledCitationStarter(expectedBindingRevision: revision)
            },
            bibliographyMethodStatus: { [self] workspaceID in
                try await workspaceHandle(id: workspaceID).research
                    .bibliographyMethodStatus()
            },
            setBibliographyMethod: { [self] workspaceID, packageID, revision in
                try await workspaceHandle(id: workspaceID).research
                    .setBibliographyMethod(
                        packageID: packageID,
                        expectedBindingRevision: revision
                    )
            },
            createResearchSkill: { [self] workspaceID, id, source in
                try await workspaceHandle(id: workspaceID).research.createSkill(
                    id: id,
                    source: source
                )
            },
            duplicateBundledResearchSkill: { [self] workspaceID, id, newID in
                try await workspaceHandle(id: workspaceID).research.duplicateBundledSkill(
                    id: id,
                    as: newID
                )
            },
            renameResearchSkill: { [self] workspaceID, id, newID, revision in
                try await workspaceHandle(id: workspaceID).research.renameSkill(
                    id: id,
                    to: newID,
                    expectedRevision: revision
                )
            },
            saveResearchSkill: { [self] workspaceID, id, source, revision in
                try await workspaceHandle(id: workspaceID).research.saveSkill(
                    id: id,
                    source: source,
                    expectedRevision: revision
                )
            },
            deleteResearchSkill: { [self] workspaceID, id, revision in
                try await workspaceHandle(id: workspaceID).research.deleteSkill(
                    id: id,
                    expectedRevision: revision
                )
            },
            researchSkillResourcePaths: { [self] workspaceID, id in
                try await workspaceHandle(id: workspaceID).research.skillResourcePaths(id: id)
            },
            researchSkillResource: { [self] workspaceID, id, relativePath in
                try await workspaceHandle(id: workspaceID).research.skillResource(
                    id: id,
                    relativePath: relativePath
                )
            },
            prepareResearchSkillMaintenance: { [self] workspaceID, request in
                try await workspaceHandle(id: workspaceID).research.prepareSkillMaintenance(request)
            },
            applyResearchSkillMaintenance: {
                [self] workspaceID, preparation, confirmationToken in
                try await workspaceHandle(id: workspaceID).research.applySkillMaintenance(
                    preparation,
                    confirmationToken: confirmationToken
                )
            },
            researchSkillMaintenanceSnapshots: { [self] workspaceID, packageID in
                try await workspaceHandle(id: workspaceID).research.skillMaintenanceSnapshots(
                    packageID: packageID
                )
            },
            restoreResearchSkillMaintenance: { [self] workspaceID, snapshotID, expectedState in
                try await workspaceHandle(id: workspaceID).research.restoreSkillMaintenance(
                    snapshotID: snapshotID,
                    expectedCurrentState: expectedState
                )
            },
            researchSkillsURL: { [self] id in
                try await workspaceHandle(id: id).research.skillsURL
            },
            legacyResearchDataURL: { [self] id in
                try await workspaceHandle(id: id).research.legacyResearchDataURL
            },
            workingMethodBindings: { [self] id in
                try await workspaceHandle(id: id).research.workingMethodBindings()
            },
            installDefaultWorkingMethods: { [self] id in
                try await workspaceHandle(id: id).research.installDefaultWorkingMethods()
            },
            saveWorkingMethod: {
                [self] id, actionID, source, packageRevision, bindingRevision in
                try await workspaceHandle(id: id).research.saveWorkingMethod(
                    for: actionID,
                    source: source,
                    expectedPackageRevision: packageRevision,
                    expectedBindingRevision: bindingRevision
                )
            },
            disableWorkingMethod: { [self] id, actionID, revision in
                try await workspaceHandle(id: id).research.disableWorkingMethod(
                    for: actionID,
                    expectedBindingRevision: revision
                )
            },
            activateResearcherSkill: { [self] id, packageID, actionID, revision in
                try await workspaceHandle(id: id).research.activateResearcherSkill(
                    packageID: packageID,
                    for: actionID,
                    expectedBindingRevision: revision
                )
            },
            restoreBundledWorkingMethod: {
                [self] id, actionID, expectedPackageState, revision in
                try await workspaceHandle(id: id).research.restoreBundledWorkingMethod(
                    for: actionID,
                    expectedPackageState: expectedPackageState,
                    expectedBindingRevision: revision
                )
            },
            actionProfiles: { [self] id in
                try await workspaceHandle(id: id).research.actionProfiles()
            },
            saveActionProfile: { [self] id, binding, revision in
                try await workspaceHandle(id: id).research.saveActionProfile(
                    binding,
                    expectedDocumentRevision: revision
                )
            },
            removeActionProfile: { [self] id, actionID, revision in
                try await workspaceHandle(id: id).research.removeActionProfile(
                    actionID: actionID,
                    expectedDocumentRevision: revision
                )
            },
            saveActionProfileDocument: { [self] id, document, revision in
                try await workspaceHandle(id: id).research.saveActionProfileDocument(
                    document,
                    expectedDocumentRevision: revision
                )
            },
            stageResearcherSkillInstallation: { [self] directoryURL in
                try await applicationRuntime.stageResearcherSkillInstallation(
                    from: directoryURL
                )
            },
            installResearcherSkill: { [self] preparation, triptychIDs in
                try await applicationRuntime.installResearcherSkill(
                    preparation,
                    to: triptychIDs
                )
            },
            discardResearcherSkillInstallation: { [self] preparationID in
                await applicationRuntime.discardResearcherSkillInstallation(
                    preparationID: preparationID
                )
            },
            permissionSettings: { [self] id in
                try await workspaceHandle(id: id).research.permissionSettings()
            },
            saveTriptychPermissionPolicy: { [self] id, policy, revision in
                try await workspaceHandle(id: id).research
                    .saveTriptychPermissionPolicy(
                        policy,
                        expectedRevision: revision
                    )
            },
            saveSkillPermissionOverride: {
                [self] id, packageID, policy, digest, revision in
                try await workspaceHandle(id: id).research
                    .saveSkillPermissionOverride(
                        packageID: packageID,
                        policy: policy,
                        expectedEnvelopeDigest: digest,
                        expectedRevision: revision
                    )
            },
            removeSkillPermissionOverride: { [self] id, packageID, revision in
                try await workspaceHandle(id: id).research
                    .removeSkillPermissionOverride(
                        packageID: packageID,
                        expectedRevision: revision
                    )
            },
            recoveryPolicy: { [self] id in
                try await workspaceHandle(id: id).research.recoveryPolicy()
            },
            prepareRecoveryPolicyChange: { [self] id, retention, revision in
                try await workspaceHandle(id: id).research
                    .prepareRecoveryPolicyChange(
                        retention,
                        expectedRevision: revision
                    )
            },
            applyRecoveryPolicyChange: { [self] id, preview in
                try await workspaceHandle(id: id).research
                    .applyRecoveryPolicyChange(preview)
            }
            )
        )
    }

    func snapshot(for triptychID: UUID) -> WorkspaceSnapshot? {
        workspaceSnapshots[triptychID]
    }

    func registerEditorFlush(
        token: UUID,
        triptychID: UUID,
        windowID: UUID,
        relativePath: String,
        flush: @escaping @MainActor () async throws -> Void
    ) {
        editorFlushRegistrations[token] = WorkspaceEditorFlushRegistration(
            token: token,
            triptychID: triptychID,
            windowID: windowID,
            relativePath: relativePath,
            flush: flush
        )
    }

    func unregisterEditorFlush(token: UUID) {
        editorFlushRegistrations[token] = nil
    }

    func flushEditors(in triptychID: UUID) async throws {
        let registrations = editorFlushRegistrations.values
            .filter { $0.triptychID == triptychID }
        let registrationsByWindow = Dictionary(grouping: registrations, by: \.windowID)
        for windowID in registrationsByWindow.keys.sorted(by: {
            $0.uuidString < $1.uuidString
        }) {
            guard let windowRegistrations = registrationsByWindow[windowID] else { continue }
            if let aggregate = windowRegistrations.first(where: { $0.relativePath.isEmpty }) {
                try await aggregate.flush()
                continue
            }
            for registration in windowRegistrations.sorted(by: {
                $0.relativePath < $1.relativePath
            }) {
                try await registration.flush()
            }
        }
    }

    func refreshPendingAgentNoteChangeRequests(in triptychID: UUID) async {
        guard let handle = handles[triptychID],
              let records = try? await handle.research.pendingAgentNoteChangeRequests()
        else { return }
        for record in records {
            agentNoteChangePresentations.receive(record, intent: .refresh)
        }
    }

    func agentNoteChangePresentationIdentity(
        for record: AgentNoteChangeRequestRecord
    ) async throws -> AgentNoteChangePresentationIdentity {
        let handle = try await workspaceHandle(id: record.request.triptychID)
        guard let target = record.request.targets.first,
              let document = workspaceSnapshots[record.request.triptychID]?
                .document(id: target.note),
              document.stableIdentity.resolvedID == target.noteID else {
            throw LocalAgentBridgeError.invalidResponse
        }
        let note = ResearchActionNoteSnapshot(
            noteID: target.noteID,
            note: target.note,
            role: target.role,
            lifecycle: document.lifecycle,
            fingerprint: document.fingerprint,
            title: ResearchNoteTitleResolver.resolve(
                document: document.document,
                vaultRole: document.vaultRole
            ).title
        )
        let actions = try await handle.research.availableActions(for: note)
        guard let action = actions.first(where: {
            $0.definition == record.request.requestedAction.definition
                && $0.profile.origin == record.request.requestedAction.profileOrigin
                && $0.profile.profileRevision
                    == record.request.requestedAction.profileRevision
                && $0.profile.profileDocumentRevision
                    == record.request.requestedAction.profileDocumentRevision
        }) else {
            throw LocalAgentBridgeError.invalidResponse
        }
        let skills = try await handle.research.skills()
        guard let skill = skills.first(where: {
            $0.id == record.request.requestedAction.packageID
                && $0.revision == record.request.requestedAction.skillRevision
        }) else {
            throw LocalAgentBridgeError.invalidResponse
        }
        return AgentNoteChangePresentationIdentity(
            actionName: action.buttonName,
            skillName: skill.name
        )
    }

    func refreshAgentNoteChangeRequest(
        id: UUID,
        in triptychID: UUID
    ) async throws {
        let handle = try await workspaceHandle(id: triptychID)
        let record = try await handle.research.agentNoteChangeRequest(id: id)
        agentNoteChangePresentations.receive(record, intent: .refresh)
    }

    func resolveAgentNoteChangeRequest(
        triptychID: UUID,
        requestID: UUID,
        state: AgentNoteChangeDecisionState,
        allowedNoteIDs: [UUID] = []
    ) async throws -> AgentNoteChangeRequestRecord {
        try await flushEditors(in: triptychID)
        let record = try await workspaceHandle(id: triptychID).research
            .resolveAgentNoteChangeRequest(
                id: requestID,
                state: state,
                allowedNoteIDs: allowedNoteIDs
            )
        agentNoteChangePresentations.receive(record, intent: .decision)
        return record
    }

    private func install(
        handle: WorkspaceHandle,
        replacing previousIdentity: TriptychRuntimeIdentity? = nil,
        announcedSnapshot: WorkspaceSnapshot? = nil
    ) async throws {
        if let pending = installationTasks[handle.id] {
            try await pending.task.value
            return try await install(
                handle: handle,
                replacing: previousIdentity,
                announcedSnapshot: announcedSnapshot
            )
        }
        if let existing = handles[handle.id],
           existing.runtimeIdentity == handle.runtimeIdentity,
           previousIdentity == nil || previousIdentity?.triptychID == handle.id {
            return
        }

        let token = UUID()
        let workspaceID = handle.id
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finishInstallation(workspaceID: workspaceID, token: token) }
            try await self.performInstall(
                handle: handle,
                replacing: previousIdentity,
                announcedSnapshot: announcedSnapshot
            )
        }
        installationTasks[workspaceID] = PendingWorkspaceInstallation(
            token: token,
            task: task
        )
        try await task.value
    }

    private func finishInstallation(workspaceID: UUID, token: UUID) {
        guard installationTasks[workspaceID]?.token == token else { return }
        installationTasks[workspaceID] = nil
    }

    private func performInstall(
        handle: WorkspaceHandle,
        replacing previousIdentity: TriptychRuntimeIdentity?,
        announcedSnapshot: WorkspaceSnapshot?
    ) async throws {
        let snapshot: WorkspaceSnapshot
        if let announcedSnapshot {
            snapshot = announcedSnapshot
        } else {
            snapshot = try await handle.snapshot()
        }
        try Task.checkCancellation()
        // Obtaining the stream is the readiness handshake: WorkspaceEventSource
        // has registered this continuation before the actor call returns.
        let stream = await handle.events.events()
        try Task.checkCancellation()

        // A caller and the old handle's runtimeReloaded event can converge on
        // the same successor. Recheck after both suspension points so only one
        // complete installation is committed and retained.
        if let existing = handles[handle.id],
           existing.runtimeIdentity == handle.runtimeIdentity,
           previousIdentity == nil || previousIdentity?.triptychID == handle.id {
            return
        }
        if let previousIdentity,
           previousIdentity.triptychID != handle.id {
            eventTasks[previousIdentity.triptychID]?.cancel()
            eventTasks[previousIdentity.triptychID] = nil
            handles[previousIdentity.triptychID] = nil
            eventGates[previousIdentity.triptychID] = nil
            workspaceSnapshots[previousIdentity.triptychID] = nil
            workspaceEventGenerations[previousIdentity.triptychID] = nil
            workspaceDerivedRefreshStatuses[previousIdentity.triptychID] = nil
            workspaceEvents[previousIdentity.triptychID] = nil
            workspaceActivations[previousIdentity.triptychID] = nil
        }
        eventTasks[handle.id]?.cancel()
        handles[handle.id] = handle
        workspaceSnapshots[handle.id] = snapshot
        eventGates[handle.id] = WorkspaceEventGenerationGate()
        workspaceEventGenerations[handle.id] = 0
        workspaceDerivedRefreshStatuses[handle.id] = .current(
            WorkspaceDerivedRefreshEvidence(snapshot: snapshot)
        )
        workspaceEvents[handle.id] = .snapshot(WorkspaceSnapshotEvent(
            generation: 0,
            snapshot: snapshot
        ))
        let activationKind: WorkspaceActivationKind
        if let previousIdentity {
            activationKind = .replacement(previous: previousIdentity)
        } else {
            activationKind = .initial
        }
        let activation = WorkspaceActivation(
            kind: activationKind,
            capabilities: capabilities(from: handle),
            snapshot: snapshot
        )
        let activationID = handle.runtimeIdentity.activationID
        eventTasks[handle.id] = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled, let self else { return }
                if case .runtimeReloaded(let reload) = event,
                   reload.runtimeIdentity != handle.runtimeIdentity {
                    await self.adoptRuntimeReplacement(
                        reload,
                        previousIdentity: handle.runtimeIdentity
                    )
                    return
                }
                self.receive(
                    event,
                    triptychID: handle.id,
                    activationID: activationID
                )
            }
        }
        workspaceActivations[handle.id] = activation
        latestWorkspaceActivation = activation
    }

    private func capabilities(from handle: WorkspaceHandle) -> WindowWorkspaceCapabilities {
        WindowWorkspaceCapabilities(
            id: handle.id,
            runtimeIdentity: handle.runtimeIdentity,
            assignment: handle.assignment,
            documents: handle.documents,
            discovery: handle.discovery,
            research: handle.research
        )
    }

    private func adoptRuntimeReplacement(
        _ reload: WorkspaceRuntimeReloadedEvent,
        previousIdentity: TriptychRuntimeIdentity
    ) async {
        guard handles[previousIdentity.triptychID]?.runtimeIdentity == previousIdentity else {
            return
        }
        do {
            let replacement = try await applicationRuntime.openWorkspace(
                id: reload.runtimeIdentity.triptychID
            )
            guard replacement.runtimeIdentity == reload.runtimeIdentity else { return }
            try await install(
                handle: replacement,
                replacing: previousIdentity,
                announcedSnapshot: reload.snapshot
            )
        } catch {
            // The old Application activation remains live if opening its
            // successor fails. A delivery caller can retry the same bounded
            // mutation without losing editor or presentation state.
        }
    }

    private func receive(
        _ event: WorkspaceEvent,
        triptychID: UUID,
        activationID: UUID
    ) {
        guard let handle = handles[triptychID],
              handle.runtimeIdentity.activationID == activationID else { return }
        var gate = eventGates[triptychID] ?? WorkspaceEventGenerationGate()
        guard gate.accept(event) else { return }
        let publicationStart = ContinuousClock().now
        eventGates[triptychID] = gate
        workspaceEvents[triptychID] = event
        workspaceSnapshots[triptychID] = event.snapshot
        workspaceEventGenerations[triptychID] = event.generation
        workspaceDerivedRefreshStatuses[triptychID] = event.derivedRefreshStatus
        let publicationDuration = publicationStart.duration(to: ContinuousClock().now)
        Self.publicationLogger.info(
            "generation=\(event.generation, privacy: .public) notes=\(event.snapshot.vaults.flatMap(\.documents).count, privacy: .public) mainActorPublish=\(String(describing: publicationDuration), privacy: .public)"
        )
    }
}
