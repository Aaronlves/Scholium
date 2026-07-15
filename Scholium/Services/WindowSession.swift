import ScholiumContracts
import Combine
import Foundation
import ScholiumApplication
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class WindowSession: ObservableObject, Identifiable {
    let id: UUID
    @Published var snapshot: WindowSessionSnapshot

    init(snapshot: WindowSessionSnapshot = WindowSessionSnapshot()) {
        id = snapshot.id
        self.snapshot = snapshot
    }
}

@MainActor
private struct WorkspaceEditorFlushRegistration {
    let token: UUID
    let triptychID: UUID
    let windowID: UUID
    let relativePath: String
    let flush: @MainActor () async throws -> Void
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

/// The macOS delivery adapter over one live Application runtime.
///
/// WorkspaceRuntime owns every repository, index, watcher, research store,
/// and workspace lifetime. This object publishes immutable GUI snapshots,
/// coordinates editor flushes across windows, and owns app-only services.
@MainActor
final class WorkspaceStore: ObservableObject {
    let applicationSupportURL: URL
    let applicationRuntime: WorkspaceRuntime
    let cssSnippetStore: CSSSnippetStore
    let zoteroBridge: ZoteroBridge

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
    private var eventGates: [UUID: WorkspaceEventGenerationGate] = [:]
    private var editorFlushRegistrations: [UUID: WorkspaceEditorFlushRegistration] = [:]

    init() {
        if let isolated = ProcessInfo.processInfo.environment["SCHOLIUM_HOME"],
           !isolated.isEmpty {
            applicationSupportURL = URL(
                fileURLWithPath: (isolated as NSString).expandingTildeInPath,
                isDirectory: true
            ).appendingPathComponent("ApplicationSupport", isDirectory: true)
        } else {
            applicationSupportURL = (try? ScholiumPaths.sharedApplicationSupportURL())
                ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                    "Scholium",
                    isDirectory: true
                )
        }
        let workspaceURL = applicationSupportURL.appendingPathComponent(
            "Workspace",
            isDirectory: true
        )
        applicationRuntime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: applicationSupportURL,
            workspaceRegistryStorageURL: workspaceURL
        )))
        cssSnippetStore = CSSSnippetStore(operations: applicationRuntime.styles)
        zoteroBridge = ZoteroBridge(operations: applicationRuntime.zotero)
    }

    deinit {
        let runtime = applicationRuntime
        Task { await runtime.shutdown() }
    }

    func shutdownApplicationRuntime() async {
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

    func existingTriptychManifestID(forWorksURL worksURL: URL) async -> UUID? {
        await applicationRuntime.portableManifestID(forWorksURL: worksURL)
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

    func workspaceHandle(id: UUID) async throws -> WorkspaceHandle {
        let handle = try await applicationRuntime.openWorkspace(id: id)
        try await install(handle: handle)
        return handle
    }

    func workspaceCapabilities(id: UUID) async throws -> WindowWorkspaceCapabilities {
        capabilities(from: try await workspaceHandle(id: id))
    }

    func configureTriptych(
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

    func reloadTriptych(id: UUID) async throws -> WorkspaceHandle {
        let previous = handles[id]?.runtimeIdentity
        let handle = try await applicationRuntime.reloadWorkspace(id: id)
        try await install(handle: handle, replacing: previous)
        return handle
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
            dialogueResponseProfile: { [self] id in
                try await workspaceHandle(id: id).research.dialogueResponseProfile()
            },
            saveDialogueResponseProfile: { [self] id, profile in
                try await workspaceHandle(id: id).research.saveDialogueResponseProfile(profile)
            },
            portableContainerURL: { [self] url in
                await portableContainerURL(forWorksURL: url)
            },
            zoteroConnectionInfo: { [self] in await zoteroBridge.connectionInfo() },
            openZotero: { [self] in await zoteroBridge.openZotero() },
            forgetZoteroCache: { [self] in try await zoteroBridge.forgetCache() },
            refreshZoteroLibraryInfo: { [self] in
                try await zoteroBridge.refreshLibraryInfo()
            },
            researchSkills: { [self] id in
                try await workspaceHandle(id: id).research.skills()
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
            researchSkillsURL: { [self] id in
                try await workspaceHandle(id: id).research.skillsURL
            },
            openExternal: { [self] url in openExternal(url) }
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
            .sorted {
                if $0.windowID != $1.windowID {
                    return $0.windowID.uuidString < $1.windowID.uuidString
                }
                return $0.relativePath < $1.relativePath
            }
        for registration in registrations { try await registration.flush() }
    }

    private func install(
        handle: WorkspaceHandle,
        replacing previousIdentity: TriptychRuntimeIdentity? = nil,
        announcedSnapshot: WorkspaceSnapshot? = nil
    ) async throws {
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
        // Runtime replacement is announced to existing consumers as well as
        // returned to the explicit caller. Whichever path installs the same
        // activation first wins; the second must not create a duplicate
        // stream subscription. Cross-ID reidentification still publishes its
        // replacement activation after clearing the previous key above.
        if let existing = handles[handle.id],
           existing.runtimeIdentity == handle.runtimeIdentity,
           previousIdentity == nil || previousIdentity?.triptychID == handle.id {
            return
        }
        eventTasks[handle.id]?.cancel()
        handles[handle.id] = handle
        let snapshot: WorkspaceSnapshot
        if let announcedSnapshot {
            snapshot = announcedSnapshot
        } else {
            snapshot = try await handle.snapshot()
        }
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
        workspaceActivations[handle.id] = activation
        latestWorkspaceActivation = activation
        let activationID = handle.runtimeIdentity.activationID
        // Establish the sole delivery subscription before publishing a
        // completed installation. This is an explicit readiness handshake,
        // not a task-scheduling assumption.
        let stream = await handle.events.events()
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
        eventGates[triptychID] = gate
        workspaceEvents[triptychID] = event
        workspaceSnapshots[triptychID] = event.snapshot
        workspaceEventGenerations[triptychID] = event.generation
        workspaceDerivedRefreshStatuses[triptychID] = event.derivedRefreshStatus
    }
}
