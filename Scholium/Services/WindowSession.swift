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
    let research: WindowResearchCapabilities
    let zoteroBindings: any ZoteroBindingUseCases
    let openingPresentationDidComplete: @Sendable () async -> Void
}

/// The delivery-facing research capabilities for one activated Triptych.
///
/// This is an app composition value rather than a Contracts-owned mega-port.
/// Feature controllers receive only the component protocols they consume.
struct WindowResearchCapabilities: Sendable {
    let records: any ResearchRecordUseCases
    let actions: any ResearchActionUseCases
    let sourceAccess: any ResearchSourceAccessUseCases
    let recoveryRecordsURL: URL
}

/// The macOS delivery adapter over one live Application runtime.
///
/// WorkspaceRuntime owns every repository, index, watcher, research store,
/// and workspace lifetime. This object publishes immutable GUI snapshots,
/// coordinates editor flushes across windows, and owns app-only services.
@MainActor
final class WorkspaceStore: ObservableObject, WorkspaceEditorFlushRegistry {
    private static let publicationLogger = Logger(
        subsystem: "com.scholium.app",
        category: "WorkspacePublication"
    )
    let applicationSupportURL: URL
    let applicationRuntime: WorkspaceRuntime
    let cssSnippetStore: CSSSnippetStore
    let zoteroBridge: ZoteroBridge
    let researchAgentPermissionClaims: ResearchAgentPermissionClaimCoordinator
    private(set) var localAgentBridge: LocalAgentBridgeServer?
    private(set) var localAgentBridgeStartupFailure: LocalAgentBridgeError?

    @Published private(set) var workspaceSnapshots: [UUID: WorkspaceSnapshot] = [:]
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
        let registryHealth = WorkspaceRegistryRecoveryOperations.health(
            storageURL: workspaceURL
        )
        guard registryHealth.isHealthy else {
            throw WorkspaceRegistryError.registryRecoveryRequired(registryHealth)
        }
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: applicationSupportURL,
            workspaceRegistryStorageURL: workspaceURL
        )))
        applicationRuntime = runtime
        cssSnippetStore = CSSSnippetStore(operations: applicationRuntime.styles)
        zoteroBridge = ZoteroBridge(operations: applicationRuntime.zotero)
        let researchAgentPermissionClaims =
            ResearchAgentPermissionClaimCoordinator()
        self.researchAgentPermissionClaims = researchAgentPermissionClaims
        do {
            let bridgeContainerURL = try ScholiumPaths.agentBridgeContainerURL(
                debugFallbackURL: applicationSupportURL
            )
            localAgentBridge = try LocalAgentBridgeServer(
                applicationSupportURL: bridgeContainerURL
            ) { [weak self] request in
                try Task.checkCancellation()
                guard let self else { throw LocalAgentBridgeError.unavailable }
                switch request.operation {
                case .preflightAnalysisCreation:
                    guard let triptychID = request.triptychID,
                          let preflightRequest =
                            request.analysisCreationPreflightRequest else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    return .analysisCreationPreflight(
                        try await runtime.preflightResearchAgentAnalysisCreation(
                            triptychID: triptychID,
                            request: preflightRequest
                        )
                    )
                case .start:
                    guard let triptychID = request.triptychID,
                          let startRequest = request.startRequest else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    let started = try await runtime.startResearchAgentRun(
                        triptychID: triptychID,
                        request: startRequest
                    )
                    return .started(
                        receipt: started.receipt,
                        credential: started.credential
                    )
                case .pair:
                    guard let run = request.run,
                          let pairingCode = request.pairingCode else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    return .credential(try await runtime.pairResearchAgent(
                        run: run,
                        pairingCode: pairingCode
                    ))
                case .context:
                    guard let run = request.run,
                          let credential = request.credential else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    return .context(try await runtime.researchAgentContext(
                        credential: credential,
                        run: run
                    ))
                case .query:
                    guard let run = request.run,
                          let credential = request.credential,
                          let contextRequest = request.contextRequest else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    return .researchContext(try await runtime.queryResearchContext(
                        credential: credential,
                        run: run,
                        request: contextRequest
                    ))
                case .discussionReply:
                    guard let run = request.run,
                          let credential = request.credential,
                          let reply = request.discussionReplyRequest else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    let triptychID = try await runtime.researchAgentWorkspaceID(
                        credential: credential,
                        run: run
                    )
                    try await self.flushEditors(in: triptychID)
                    return .discussionReply(
                        try await runtime.replyToResearchAgentDiscussion(
                            credential: credential,
                            run: run,
                            request: reply
                        )
                    )
                case .extendWriteSet:
                    guard let run = request.run,
                          let credential = request.credential,
                          let intent = request.writeSetIntent else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    let triptychID = try await runtime.researchAgentWorkspaceID(
                        credential: credential,
                        run: run
                    )
                    try await self.flushEditors(in: triptychID)
                    let delivery = try await runtime.extendResearchWriteSet(
                        credential: credential,
                        run: run,
                        intent: intent
                    )
                    if let record = delivery.record, record.isUnresolved {
                        await researchAgentPermissionClaims.receive(
                            .writeSetExtension(record),
                            intent: .submit
                        )
                    }
                    return .writeSet(delivery.result)
                case .writeDocument:
                    guard let run = request.run,
                          let credential = request.credential,
                          let intent = request.documentWriteIntent else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    return .documentWrite(try await runtime.writeResearchDocument(
                        credential: credential,
                        run: run,
                        intent: intent
                    ))
                case .writeZoteroBinding:
                    guard let run = request.run,
                          let credential = request.credential,
                          let intent = request.zoteroBindingWriteIntent else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    return .zoteroBindingWrite(
                        try await runtime.writeResearchZoteroBinding(
                            credential: credential,
                            run: run,
                            intent: intent
                        )
                    )
                case .resolveWriteConflict:
                    guard let run = request.run,
                          let credential = request.credential,
                          let intent = request.conflictResolutionIntent else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    let triptychID = try await runtime.researchAgentWorkspaceID(
                        credential: credential,
                        run: run
                    )
                    try await self.flushEditors(in: triptychID)
                    return .conflictResolution(
                        try await runtime.resolveResearchWriteConflict(
                            credential: credential,
                            run: run,
                            intent: intent
                        )
                    )
                case .submitResult:
                    guard let run = request.run,
                          let credential = request.credential,
                          let submission = request.resultSubmission else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    let triptychID = try await runtime.researchAgentWorkspaceID(
                        credential: credential,
                        run: run,
                        allowFinalized: true
                    )
                    try await self.flushEditors(in: triptychID)
                    return .resultReceipt(try await runtime.submitResearchAgentResult(
                        credential: credential,
                        run: run,
                        submission: submission
                    ))
                case .continueResearch:
                    guard let run = request.run,
                          let credential = request.credential,
                          let continuation = request.continuationRequest else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    let triptychID = try await runtime.researchAgentWorkspaceID(
                        credential: credential,
                        run: run,
                        allowFinalized: true
                    )
                    try await self.flushEditors(in: triptychID)
                    let result = try await runtime.continueResearch(
                        credential: credential,
                        run: run,
                        request: continuation
                    )
                    if result.state == .pendingResearcherDecision {
                        let decision = try await runtime
                            .researchContinuationRequest(
                                credential: credential,
                                run: run,
                                request: continuation
                            )
                        await researchAgentPermissionClaims.receive(
                            .continuation(decision),
                            intent: .submit
                        )
                    }
                    return .continuation(result)
                case .methodImprovementContext:
                    guard let run = request.run,
                          let credential = request.credential else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    return .methodImprovementContext(
                        try await runtime.researchMethodImprovementContext(
                            credential: credential,
                            run: run
                        )
                    )
                case .submitMethodImprovement:
                    guard let run = request.run,
                          let credential = request.credential,
                          let submission = request.methodImprovementSubmission else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    let triptychID = try await runtime.researchAgentWorkspaceID(
                        credential: credential,
                        run: run,
                        allowFinalized: true
                    )
                    try await self.flushEditors(in: triptychID)
                    return .methodImprovementReceipt(
                        try await runtime.submitResearchMethodImprovement(
                            credential: credential,
                            run: run,
                            submission: submission
                        )
                    )
                case .end:
                    guard let run = request.run,
                          let credential = request.credential else {
                        throw LocalAgentBridgeError.invalidRequest
                    }
                    return .endReceipt(try await runtime.endResearchAgentRun(
                        credential: credential,
                        run: run
                    ))
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
                "Local Agent bridge startup failed with an unrecognized local error."
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

    func registeredVaults() async throws -> [RegisteredVault] {
        try await applicationRuntime.registeredVaults()
    }

    func defaultTriptych() async throws -> TriptychAssignment {
        try await applicationRuntime.defaultWorkspace()
    }

    func removeLocalTriptychRegistration(id: UUID) async throws {
        guard handles[id] == nil, installationTasks[id] == nil else {
            throw ScholiumApplicationError.workspaceRegistrationInUse(id)
        }
        try await applicationRuntime.removeLocalTriptychRegistration(id: id)
        workspaceSnapshots[id] = nil
        workspaceEvents[id] = nil
        workspaceActivations[id] = nil
        if latestWorkspaceActivation?.workspaceID == id {
            latestWorkspaceActivation = nil
        }
    }

    @discardableResult
    func preserveUnsupportedPortableControl(
        portableContainerURL: URL,
        worksURL: URL,
        triptychID: UUID? = nil
    ) async throws -> URL {
        if let triptychID, handles[triptychID] != nil || installationTasks[triptychID] != nil {
            throw ScholiumApplicationError.workspaceRegistrationInUse(triptychID)
        }
        return try await applicationRuntime.preserveUnsupportedPortableControl(
            portableContainerURL: portableContainerURL,
            worksURL: worksURL,
            triptychID: triptychID
        )
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

    @discardableResult
    func preserveUnreadableSavedSearchesAndReset() async throws -> URL? {
        try await applicationRuntime.preserveUnreadableSavedSearchesAndReset()
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

    private func workspaceHandle(
        id: UUID,
        openingVault: WorkspaceVaultSlot? = nil
    ) async throws -> WorkspaceHandle {
        let handle = try await applicationRuntime.openWorkspace(
            id: id,
            openingVault: openingVault
        )
        try await install(handle: handle)
        return handle
    }

    func workspaceCapabilities(
        id: UUID,
        openingVault: WorkspaceVaultSlot? = nil
    ) async throws -> WindowWorkspaceCapabilities {
        capabilities(from: try await workspaceHandle(
            id: id,
            openingVault: openingVault
        ))
    }

    private func configureTriptych(
        paperAnalysisURL: URL,
        topicKnowledgeURL: URL,
        outputURL: URL,
        portableContainerURL: URL,
        triptychID: UUID? = nil,
        triptychName: String? = nil,
        openingVault: WorkspaceVaultSlot? = nil
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
            triptychName: triptychName,
            openingVault: openingVault
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
        triptychName: String? = nil,
        openingVault: WorkspaceVaultSlot? = nil
    ) async throws -> WindowWorkspaceCapabilities {
        capabilities(from: try await configureTriptych(
            paperAnalysisURL: paperAnalysisURL,
            topicKnowledgeURL: topicKnowledgeURL,
            outputURL: outputURL,
            portableContainerURL: portableContainerURL,
            triptychID: triptychID,
            triptychName: triptychName,
            openingVault: openingVault
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
        let vaults = try await registeredVaults()
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
        let settingsLoadState = try await handle.research.settingsLoadState()
        let triptychSettings: TriptychSettings
        let settingsRevision: SettingsRevision?
        let portableSettingsState: WorkspacePortableSettingsState
        switch settingsLoadState {
        case .current(let snapshot):
            triptychSettings = snapshot.settings
            settingsRevision = snapshot.revision
            portableSettingsState = .current(snapshot.revision)
        case .needsReview(let settings, let revision, let reason):
            triptychSettings = settings
            settingsRevision = revision
            portableSettingsState = .needsReview(revision, reason: reason)
        case .missing:
            triptychSettings = TriptychSettings()
            settingsRevision = nil
            portableSettingsState = .missing
        case .oldSchema(let version):
            triptychSettings = TriptychSettings()
            settingsRevision = nil
            portableSettingsState = .oldSchema(version)
        case .futureSchema(let version):
            triptychSettings = TriptychSettings()
            settingsRevision = nil
            portableSettingsState = .futureSchema(version)
        case .corrupted:
            triptychSettings = TriptychSettings()
            settingsRevision = nil
            portableSettingsState = .corrupted
        }
        return WorkspaceSettingsSnapshot(
            registeredVaults: vaults,
            registeredTriptychs: triptychs,
            activeTriptychID: handle.id,
            triptychSettings: triptychSettings,
            settingsRevision: settingsRevision,
            portableSettingsState: portableSettingsState
        )
    }

    private func portableSettingsRead(
        triptychID: UUID
    ) async throws -> WorkspacePortableSettingsRead {
        let handle = try await workspaceHandle(id: triptychID)
        switch try await handle.research.settingsLoadState() {
        case .current(let snapshot):
            return WorkspacePortableSettingsRead(
                triptychID: triptychID,
                settings: snapshot.settings,
                state: .current(snapshot.revision)
            )
        case .needsReview(let settings, let revision, let reason):
            return WorkspacePortableSettingsRead(
                triptychID: triptychID,
                settings: settings,
                state: .needsReview(revision, reason: reason)
            )
        case .missing:
            return WorkspacePortableSettingsRead(
                triptychID: triptychID,
                settings: TriptychSettings(),
                state: .missing
            )
        case .oldSchema(let version):
            return WorkspacePortableSettingsRead(
                triptychID: triptychID,
                settings: TriptychSettings(),
                state: .oldSchema(version)
            )
        case .futureSchema(let version):
            return WorkspacePortableSettingsRead(
                triptychID: triptychID,
                settings: TriptychSettings(),
                state: .futureSchema(version)
            )
        case .corrupted:
            return WorkspacePortableSettingsRead(
                triptychID: triptychID,
                settings: TriptychSettings(),
                state: .corrupted
            )
        }
    }

    func settingsCapabilities() -> WorkspaceSettingsCapabilities {
        WorkspaceSettingsCapabilities(
            workspace: WorkspaceSettingsWorkspaceCapabilities(
                loadSnapshot: { [self] preferredID in
                    try await settingsSnapshot(preferredTriptychID: preferredID)
                },
                loadPortableSettings: { [self] id in
                    try await portableSettingsRead(triptychID: id)
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
                saveTriptychSettings: { [self] id, settings, expectedRevision in
                    let handle = try await workspaceHandle(id: id)
                    let outcome = try await handle.research.saveSettingsOutcome(
                        settings,
                        expectedRevision: expectedRevision
                    )
                    return WorkspaceSettingsCommit(
                        triptychID: id,
                        snapshot: outcome.committedValue,
                        derivedRefreshWarning: outcome.derivedRefreshWarning
                    )
                },
                portableContainerURL: { [self] url in
                    await portableContainerURL(forWorksURL: url)
                }
            ),
            machine: WorkspaceSettingsMachineCapabilities(
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
            researchSkillRegistrations: { [self] id in
                try await workspaceHandle(id: id).research.researchSkillRegistrations()
            },
            saveResearchSkillRegistrations: { [self] id, document, revision in
                try await workspaceHandle(id: id).research.saveResearchSkillRegistrations(
                    document,
                    expectedRevision: revision
                )
            },
            academicActionProfiles: { [self] id in
                try await workspaceHandle(id: id).research.academicActionProfiles()
            },
            saveAcademicActionProfiles: { [self] id, document, revision in
                try await workspaceHandle(id: id).research.saveAcademicActionProfiles(
                    document,
                    expectedRevision: revision
                )
            },
            collaborationPolicy: { [self] id in
                try await workspaceHandle(id: id).research.collaborationPolicy()
            },
            saveCollaborationPolicy: { [self] id, document, revision in
                try await workspaceHandle(id: id).research.saveCollaborationPolicy(
                    document,
                    expectedRevision: revision
                )
            },
            researchMethod: { [self] id, actionID in
                try await workspaceHandle(id: id).research.researchMethod(for: actionID)
            },
            saveResearchMethod: { [self] id, key, source, revision in
                try await workspaceHandle(id: id).research.saveResearchMethod(
                    registrationKey: key,
                    source: source,
                    expectedRevision: revision
                )
            },
            registerExternalResearchMethod: {
                [self] id, actionID, name, primaryPath, folderPath, revision in
                try await workspaceHandle(id: id).research.registerExternalResearchMethod(
                    actionID: actionID,
                    displayName: name,
                    primaryMarkdownPath: primaryPath,
                    skillFolderPath: folderPath,
                    expectedRegistrationRevision: revision
                )
            },
            createResearchMethod: { [self] id, actionID, name, source, revision in
                try await workspaceHandle(id: id).research.createResearchMethod(
                    actionID: actionID,
                    displayName: name,
                    source: source,
                    expectedRegistrationRevision: revision
                )
            },
            restoreDefaultResearchMethod: { [self] id, actionID, revision in
                try await workspaceHandle(id: id).research.restoreDefaultResearchMethod(
                    actionID: actionID,
                    expectedRevision: revision
                )
            },
            recoverMachineLocalMethodLocators: { [self] id in
                try await workspaceHandle(id: id).research
                    .preserveInvalidMachineLocalMethodLocatorsAndReset()
            },
            philosophicalPractices: { [self] id in
                try await workspaceHandle(id: id).research.philosophicalPractices()
            },
            createPhilosophicalPractice: { [self] id, title, source in
                try await workspaceHandle(id: id).research.createPhilosophicalPractice(
                    title: title,
                    source: source
                )
            },
            savePhilosophicalPractice: { [self] id, path, source, revision in
                try await workspaceHandle(id: id).research.savePhilosophicalPractice(
                    relativePath: path,
                    source: source,
                    expectedRevision: revision
                )
            },
            citationMethodStatus: { [self] workspaceID in
                try await workspaceHandle(id: workspaceID).research.citationMethodStatus()
            },
            activateCitationMethod: { [self] workspaceID, selection, revision in
                try await workspaceHandle(id: workspaceID).research.activateCitationMethod(
                    selection: selection,
                    expectedConfigurationRevision: revision
                )
            },
            clearCitationMethod: { [self] workspaceID, revision in
                try await workspaceHandle(id: workspaceID).research.clearCitationMethod(
                    expectedConfigurationRevision: revision
                )
            }
            )
        )
    }

    func snapshot(
        for runtimeIdentity: TriptychRuntimeIdentity
    ) -> WorkspaceSnapshot? {
        guard workspaceActivations[runtimeIdentity.triptychID]?.runtimeIdentity
                == runtimeIdentity else { return nil }
        return workspaceSnapshots[runtimeIdentity.triptychID]
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

    func refreshPendingResearchAgentPermissions(in triptychID: UUID) async {
        guard let handle = handles[triptychID] else { return }
        if let records = try? await handle.research
            .pendingAgentWriteSetExtensions() {
            for record in records {
                researchAgentPermissionClaims.receive(
                    .writeSetExtension(record),
                    intent: .refresh
                )
            }
        }
        if let records = try? await handle.research
            .pendingContinuationRequests() {
            for record in records {
                researchAgentPermissionClaims.receive(
                    .continuation(record),
                    intent: .refresh
                )
            }
        }
    }

    func refreshResearchWriteSetExtension(
        id: UUID,
        in triptychID: UUID
    ) async throws {
        let record = try await workspaceHandle(id: triptychID).research
            .agentWriteSetExtension(requestID: id)
        researchAgentPermissionClaims.receive(
            .writeSetExtension(record),
            intent: .refresh
        )
    }

    func resolveResearchWriteSetExtension(
        triptychID: UUID,
        requestID: UUID,
        state: ResearchWriteSetExtensionState,
        allowedHandles: [ResearchWriteTargetHandle]
    ) async throws -> ResearchWriteSetExtensionRecord {
        try await flushEditors(in: triptychID)
        let record = try await workspaceHandle(id: triptychID).research
            .resolveAgentWriteSetExtension(
                requestID: requestID,
                state: state,
                allowedHandles: allowedHandles
            )
        researchAgentPermissionClaims.receive(
            .writeSetExtension(record),
            intent: .decision
        )
        return record
    }

    func refreshResearchContinuation(
        triptychID: UUID,
        parentRunID: UUID,
        requestID: UUID
    ) async throws {
        let record = try await workspaceHandle(id: triptychID).research
            .continuationRequest(
                parentRunID: parentRunID,
                requestID: requestID
            )
        researchAgentPermissionClaims.receive(
            .continuation(record),
            intent: .refresh
        )
    }

    func resolveResearchContinuation(
        triptychID: UUID,
        parentRunID: UUID,
        requestID: UUID,
        allow: Bool
    ) async throws -> ResearchContinuationRequestRecord {
        let record = try await workspaceHandle(id: triptychID).research
            .resolveContinuationRequest(
                parentRunID: parentRunID,
                requestID: requestID,
                allow: allow
            )
        researchAgentPermissionClaims.receive(
            .continuation(record),
            intent: .decision
        )
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
        // explicitly phased installation is committed and retained.
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
            workspaceEvents[previousIdentity.triptychID] = nil
            workspaceActivations[previousIdentity.triptychID] = nil
        }
        eventTasks[handle.id]?.cancel()
        handles[handle.id] = handle
        workspaceSnapshots[handle.id] = snapshot
        eventGates[handle.id] = WorkspaceEventGenerationGate()
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
        let research = handle.research
        return WindowWorkspaceCapabilities(
            id: handle.id,
            runtimeIdentity: handle.runtimeIdentity,
            assignment: handle.assignment,
            documents: handle.documents,
            discovery: handle.discovery,
            research: WindowResearchCapabilities(
                records: research,
                actions: research,
                sourceAccess: research,
                recoveryRecordsURL: research.recoveryRecordsURL
            ),
            zoteroBindings: handle.zoteroBindings,
            openingPresentationDidComplete: {
                await handle.openingPresentationDidComplete()
            }
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
        // Research Guidance changes invalidate Action resolution but do not
        // rebuild or supersede the current workspace snapshot. Publishing the
        // typed event must therefore not clear an existing stale/failed
        // derived-state status or replay the same snapshot through every
        // document consumer.
        if case .researchConfigurationInvalidated = event {
            return
        }
        workspaceSnapshots[triptychID] = event.snapshot
        let publicationDuration = publicationStart.duration(to: ContinuousClock().now)
        Self.publicationLogger.info(
            "generation=\(event.generation, privacy: .public) notes=\(event.snapshot.vaults.flatMap(\.documents).count, privacy: .public) mainActorPublish=\(String(describing: publicationDuration), privacy: .public)"
        )
    }
}
