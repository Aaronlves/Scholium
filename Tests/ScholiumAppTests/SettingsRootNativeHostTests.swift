import AppKit
import Combine
import CoreFoundation
import CryptoKit
import Foundation
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

/// The real visual Settings root, hosted privately without WorkspaceStore,
/// a scene launch, external services, a visible window or standard defaults.
/// This endpoint is selected native layout; it does not measure painted UI.
@Suite("Isolated Settings root native hosts", .serialized, .timeLimit(.minutes(5)))
@MainActor
struct SettingsRootNativeHostTests {
    @Test("All Settings pages and Agent segments retain native layout and isolated preferences")
    func pagesAndSegments() async throws {
        for locale in ["en", "zh-Hans"] {
            for size in [NSSize(width: 780, height: 560), NSSize(width: 920, height: 700)] {
                let fixture = try await RootFixture.make()
                let session = RootSession(fixture: fixture, locale: locale, size: size)
                defer {
                    session.close()
                    fixture.removeDefaults()
                }
                try await session.mount()
                let frame = session.window.frame
                var visited: [ScholiumSettingsDestination: NSView] = [:]
                for page in ScholiumSettingsDestination.allCases {
                    _ = try await session.select(page)
                    let host = try #require(session.pageContainer?.selectedView)
                    visited[page] = host
                    try session.assertLayout(page: page)
                    #expect(session.window.frame == frame)
                    try fixture.assertReadOnlyPreferences()
                }
                var segmentHosts: [String: NSView] = [:]
                for route in RootSession.agentRoutes {
                    _ = try await session.reveal(route.section, segment: route.index)
                    let container = try #require(session.agentContainer)
                    segmentHosts[route.section.id] = try #require(container.selectedView)
                    try session.assertLayout(page: .agents)
                    try fixture.assertReadOnlyPreferences()
                }
                #expect(Set(segmentHosts.values.map(ObjectIdentifier.init)).count == 3)
                for page in ScholiumSettingsDestination.allCases {
                    _ = try await session.select(page)
                    #expect(session.pageContainer?.selectedView === visited[page])
                }
                _ = try await session.reveal(.agentBehavior, segment: 0)
                #expect(session.agentContainer?.selectedView === segmentHosts[SettingsSection.agentBehavior.id])
                #expect(!session.window.isVisible)
                #expect(fixture.state.unexpected.isEmpty)
                #expect(fixture.styles.unexpected.isEmpty)
                try fixture.assertReadOnlyPreferences()
            }
        }
    }

    @Test("Root search restores browsing, while toolbar and external routes replace its temporary origin")
    func searchBrowsingContinuity() async throws {
        let fixture = try await RootFixture.make()
        let session = RootSession(fixture: fixture, locale: "en", size: NSSize(width: 780, height: 560))
        defer {
            session.close()
            fixture.removeDefaults()
        }
        try await session.mount()
        _ = try await session.select(.document)
        let documentHost = try #require(session.pageContainer?.selectedView)
        let frame = session.window.frame
        let root = try #require(session.window.contentView)
        let field = try #require(
            activeDescendants(root).compactMap { $0 as? NSSearchField }
                .first { $0.accessibilityIdentifier() == "scholium.settings.search" })
        let search = try #require(field.target as? ScholiumSettingsSearchField.Coordinator)
        let target = try #require(SettingsSearchTarget.all.first { $0.section == .agentChatSidebar })

        search.parent.text = "Chat"
        await session.publishAndLayout()
        search.parent.reveal(target)
        await session.publishAndLayout()
        try session.assertLayout(page: .agents)
        #expect(fixture.defaults.string(forKey: "scholium.settings.selectedPane") == "document")
        search.parent.text = "  "
        await session.publishAndLayout()
        try session.assertLayout(page: .document)
        #expect(session.pageContainer?.selectedView === documentHost)

        search.parent.text = "Chat"
        await session.publishAndLayout()
        search.parent.reveal(target)
        await session.publishAndLayout()
        let storage = try #require(session.window.toolbar?.items.first { $0.itemIdentifier.rawValue == "scholium.settings.category.storage" })
        #expect(NSApp.sendAction(try #require(storage.action), to: storage.target, from: storage))
        await session.publishAndLayout()
        try session.assertLayout(page: .storage)
        #expect(field.stringValue.isEmpty)
        #expect(fixture.defaults.string(forKey: "scholium.settings.selectedPane") == "storage")

        search.parent.text = "Chat"
        await session.publishAndLayout()
        search.parent.reveal(target)
        await session.publishAndLayout()
        _ = try await session.reveal(.agentBehavior, segment: 0)
        #expect(field.stringValue.isEmpty)
        _ = try await session.reveal(.agentBehavior, segment: 0)
        search.parent.text = "unmatched synthetic query"
        await session.publishAndLayout()
        search.parent.text = ""
        await session.publishAndLayout()
        try session.assertLayout(page: .agents)
        #expect(fixture.defaults.string(forKey: "scholium.settings.selectedPane") == "agents")
        _ = try await session.select(.document)
        #expect(session.pageContainer?.selectedView === documentHost && session.window.frame == frame)
        try fixture.assertReadOnlyPreferences()
        #expect(fixture.state.unexpected.isEmpty && fixture.styles.unexpected.isEmpty)
    }

    @Test("Only a selected dependent page asks for its current synthetic Chat scope")
    func borrowedControllerAcquisition() async throws {
        let fixture = try await RootFixture.make()
        let session = RootSession(fixture: fixture, locale: "en", size: NSSize(width: 780, height: 560))
        defer {
            session.close()
            fixture.removeDefaults()
        }
        try await session.mount()
        let unrelated: [ScholiumSettingsDestination] = [.workspace, .document, .shortcuts, .storage]
        let dependent: [ScholiumSettingsDestination] = [.writing, .agents, .zotero]
        #expect(fixture.state.providerRequests.isEmpty)
        for page in unrelated {
            let before = fixture.state.providerRequests.count
            _ = try await session.select(page)
            _ = await fixture.model.refresh()
            await session.publishAndLayout()
            #expect(fixture.state.providerRequests.count == before)
        }
        for page in dependent {
            let before = fixture.state.providerRequests.count
            _ = try await session.select(page)
            await session.publishAndLayout()
            let requests = Array(fixture.state.providerRequests.dropFirst(before))
            #expect(!requests.isEmpty)
            #expect(requests.allSatisfy { $0 == fixture.firstID })
        }
        let hiddenCount = fixture.state.providerRequests.count
        _ = try await session.select(.document)
        await fixture.model.activateTriptych(id: fixture.secondID)
        await session.publishAndLayout()
        #expect(fixture.state.providerRequests.count == hiddenCount)
        _ = try await session.select(.writing)
        await session.publishAndLayout()
        let secondRequests = Array(fixture.state.providerRequests.dropFirst(hiddenCount))
        #expect(!secondRequests.isEmpty)
        #expect(secondRequests.allSatisfy { $0 == fixture.secondID })
        let activeScopeCount = fixture.state.providerRequests.count
        await fixture.model.activateTriptych(id: fixture.firstID)
        try await RootSession.waitUntil("active dependent scope re-evaluation") {
            fixture.state.providerRequests.count > activeScopeCount
        }
        #expect(fixture.state.providerRequests.dropFirst(activeScopeCount).allSatisfy { $0 == fixture.firstID })

        let nilCount = fixture.state.providerRequests.count
        _ = try await session.select(.document)
        fixture.model.replaceSnapshot(fixture.snapshot(active: nil))
        await session.publishAndLayout()
        #expect(fixture.state.providerRequests.count == nilCount)
        for page in ScholiumSettingsDestination.allCases {
            _ = try await session.select(page)
            await session.publishAndLayout()
            #expect(fixture.model.selectedTriptychID == nil)
            #expect(fixture.state.providerRequests.count == nilCount)
        }
        #expect(fixture.state.unexpected.isEmpty)
        try fixture.assertReadOnlyPreferences()
    }

    @Test("AppStorage reads and writes cross navigation, category and nested pane hosts in one supplied suite")
    func defaultStoreCrossesEveryManualHost() async throws {
        let fixture = try await RootFixture.make()
        let records = StoreProbeRecords()
        let window = RootSession.makeWindow(size: NSSize(width: 780, height: 560))
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.sizingOptions = []
        host.sceneBridgingOptions = []
        window.contentView = host
        defer {
            records.entries.removeAll()
            host.rootView = AnyView(EmptyView())
            window.contentView = nil
            window.close()
            fixture.removeDefaults()
        }
        let labels = ["navigation", "category", "nested"]
        for label in labels { fixture.defaults.set("fixture-" + label, forKey: StoreProbe.key(label)) }
        let page = VStack {
            StoreProbe(label: "navigation", records: records)
            ScholiumSettingsPaneHost(selection: "category", identifier: "fixture.category") { _ in
                VStack {
                    StoreProbe(label: "category", records: records)
                    ScholiumSettingsPaneHost(selection: "nested", identifier: "fixture.nested") { _ in
                        StoreProbe(label: "nested", records: records)
                    }
                }
            }
        }
        host.rootView = AnyView(
            ScholiumSettingsNavigationHost(selection: .constant(.agents), page: page)
                .environmentObject(fixture.model)
                .environment(\.scholiumSettingsDefaults, fixture.defaults)
                .defaultAppStorage(fixture.defaults)
        )
        try await RootSession.waitUntil("all three AppStorage probes") {
            host.layoutSubtreeIfNeeded()
            return labels.allSatisfy { records.entries[$0]?.value == "fixture-" + $0 }
        }
        for label in labels {
            let entry = try #require(records.entries[label])
            #expect(entry.defaultsID == ObjectIdentifier(fixture.defaults))
            entry.write("edited-" + label)
        }
        try await RootSession.waitUntil("all three isolated AppStorage writes") {
            host.layoutSubtreeIfNeeded()
            return labels.allSatisfy {
                records.entries[$0]?.value == "edited-" + $0
                    && fixture.defaults.string(forKey: StoreProbe.key($0)) == "edited-" + $0
            }
        }
        // This proves the public modifier's effective store, not a private
        // SwiftUI environment getter or only the forwarded custom key.
        #expect(labels.allSatisfy { records.entries[$0]?.defaultsID == ObjectIdentifier(fixture.defaults) })
    }

    @Test("Injected preference owners round trip only their own suite")
    func preferenceOwnersPersistIndependently() async throws {
        let fixture = try await RootFixture.make()
        defer { fixture.removeDefaults() }
        let owners = fixture.preferences
        #expect(owners.writingAssistance === owners.writingAssistance)
        #expect(owners.selectionActions === owners.selectionActions)
        #expect(owners.chatSidebar === owners.chatSidebar)
        #expect(owners.agentContextAccess === owners.agentContextAccess)
        owners.writingAssistance.model = "fixture-model-reloaded"
        owners.writingAssistance.continuationEnabled = true
        owners.writingAssistance.continuationEffort = "low"
        owners.chatSidebar.isEnabled = true
        owners.agentContextAccess.externalWorkingTextAccess = true
        var action = try #require(owners.selectionActions.actions.first)
        action.prompt = "Fixture persisted instruction"
        let actions = [action]
        try owners.selectionActions.save(actions)
        let reloaded = SettingsPreferences(defaults: fixture.defaults)
        #expect(reloaded.writingAssistance.model == "fixture-model-reloaded")
        #expect(reloaded.writingAssistance.continuationEnabled)
        #expect(reloaded.writingAssistance.continuationEffort == "low")
        #expect(reloaded.chatSidebar.isEnabled)
        #expect(reloaded.agentContextAccess.externalWorkingTextAccess)
        #expect(reloaded.selectionActions.actions == actions)
        #expect(reloaded.writingAssistance !== owners.writingAssistance)
        #expect(reloaded.selectionActions !== owners.selectionActions)
    }

    @Test(
        "Opt-in selected-native-layout and fixture request attribution",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_SETTINGS"] == "1"))
    func measureSelectedNativeLayout() async throws {
        var observations: [RootObservation] = []
        for locale in ["en", "zh-Hans"] {
            for size in [NSSize(width: 780, height: 560), NSSize(width: 920, height: 700)] {
                // One complete excluded warmup, then five complete observations.
                for iteration in -1..<5 {
                    let fixture = try await RootFixture.make()
                    let session = RootSession(fixture: fixture, locale: locale, size: size)
                    defer {
                        session.close()
                        fixture.removeDefaults()
                    }
                    let opening = try await session.mount()
                    var stages: [RootStage] = [opening]
                    for page in ScholiumSettingsDestination.allCases {
                        stages.append(try await session.select(page, phase: page == .workspace ? "already_selected" : "first_visit"))
                    }
                    for route in RootSession.agentRoutes {
                        stages.append(try await session.reveal(route.section, segment: route.index))
                    }
                    for page in ScholiumSettingsDestination.allCases {
                        stages.append(try await session.select(page, phase: "revisit"))
                    }
                    try fixture.assertReadOnlyPreferences()
                    #expect(fixture.state.unexpected.isEmpty && fixture.styles.unexpected.isEmpty)
                    let record = RootObservation(
                        iteration: iteration, locale: locale, width: Double(size.width), height: Double(size.height),
                        restoreMilliseconds: fixture.restoreMilliseconds,
                        restoreRequestCounts: fixture.restoreRequestCounts,
                        snapshotRequestIDs: fixture.state.snapshotRequestIDs,
                        portableLookupPaths: fixture.state.portableLookupPaths,
                        stages: stages, counts: fixture.state.counts,
                        providerIDs: fixture.state.providerRequests.map(\.uuidString),
                        preferenceSHA256: try fixture.preferenceDigest(),
                        fixtureMaterialSHA256: fixture.fixtureDigest,
                        styleReads: fixture.styles.reads,
                        inlineDraftState: "unexercised: private SwiftUI editor; existing draft-owner tests remain separate"
                    )
                    if iteration >= 0 { observations.append(record) }
                }
            }
        }
        let report = RootReport(
            schema: "scholium.settings-native-layout.v1", configuration: Self.configuration,
            providerObservation: "selected-detail provider requests counted; nil synthetic controllers",
            endpoint: "private unshown window; selected native host + toolbar + layout, not painted appearance",
            warmupsPerConfiguration: 1, retainedPerConfiguration: 5,
            observations: observations, summaries: RootReport.summarize(observations)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print("SCHOLIUM_SETTINGS_NATIVE_LAYOUT " + String(decoding: try encoder.encode(report), as: UTF8.self))
    }

    private static var configuration: String {
        #if DEBUG
            "debug"
        #else
            "release"
        #endif
    }
}

@MainActor
private final class RootFixture {
    let suiteName: String
    let defaults: UserDefaults
    let preferences: SettingsPreferences
    let root: URL
    let state: RootFixtureState
    let styles: RootStyles
    let store: CSSSnippetStore
    let model: WorkspaceSettingsModel
    let assignments: [TriptychAssignment]
    let restoreMilliseconds: Double
    let restoreRequestCounts: [String: Int]
    let fixtureDigest: String
    private let baseline: Data
    var firstID: UUID { assignments[0].id }
    var secondID: UUID { assignments[1].id }

    private init(
        suiteName: String, defaults: UserDefaults, preferences: SettingsPreferences, root: URL,
        state: RootFixtureState, styles: RootStyles, store: CSSSnippetStore, model: WorkspaceSettingsModel,
        assignments: [TriptychAssignment], restoreMilliseconds: Double, baseline: Data
    ) {
        self.suiteName = suiteName
        self.defaults = defaults
        self.preferences = preferences
        self.root = root
        self.state = state
        self.styles = styles
        self.store = store
        self.model = model
        self.assignments = assignments
        self.restoreMilliseconds = restoreMilliseconds
        self.restoreRequestCounts = state.counts
        self.baseline = baseline
        fixtureDigest = sha256(Data(Self.material.utf8))
    }

    static func make(historyOwner: HistoryHostOwner? = nil) async throws -> RootFixture {
        let suiteName = "scholium.settings-root-native.fixture.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        var succeeded = false
        defer { if !succeeded { defaults.removePersistentDomain(forName: suiteName) } }
        defaults.set(false, forKey: WritingAssistancePreferences.enabledKey)
        defaults.set("fixture-model", forKey: WritingAssistancePreferences.modelKey)
        defaults.set("low", forKey: WritingAssistancePreferences.effortKey)
        defaults.set(false, forKey: ChatSidebarPreferences.enabledKey)
        defaults.set(true, forKey: AgentContextAccessPreferences.chatStateKey)
        defaults.set(false, forKey: AgentContextAccessPreferences.externalStateKey)
        defaults.set(false, forKey: AgentContextAccessPreferences.chatWorkingTextKey)
        defaults.set(false, forKey: AgentContextAccessPreferences.externalWorkingTextKey)
        defaults.set(AgentChatInputBehavior.steer.rawValue, forKey: AgentChatInputBehavior.key)
        defaults.set(ScholiumHotkeyPreferences.defaultData, forKey: ScholiumHotkeyPreferences.defaultsKey)
        defaults.set("", forKey: "agent.codex.executable")
        defaults.set("", forKey: "agent.codex.home")
        defaults.set("", forKey: "agent.scholium.helper")
        let action = SelectionActionDefinition(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            name: "Fixture", prompt: "Read only this synthetic selection.", isEnabled: true)
        defaults.set(try JSONEncoder().encode([action]), forKey: SelectionActionPreferences.key)
        defaults.set(Data("fixture canary \u{0} 中 🧪".utf8), forKey: "fixture.untouchedBytes")
        defaults.set("workspace", forKey: "scholium.settings.selectedPane")
        defaults.set("fixture-initial", forKey: "scholium.settings.navigationRevision")
        defaults.set("connection", forKey: "scholium.settings.agentCategory")
        let preferences = SettingsPreferences(defaults: defaults)
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/settings-root-native/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let assignments = Self.makeAssignments(root: root)
        let state = RootFixtureState(assignments: assignments, root: root)
        state.historyOwner = historyOwner
        let styles = RootStyles(base: StyleOperations(applicationSupportURL: root.appendingPathComponent("Support")))
        let store = CSSSnippetStore(operations: styles)
        // The fixture deliberately declines directory observation. Await the
        // initialization attempt, then drain the real style store's queue.
        try await RootSession.waitUntil("fixture style observation initialization") { styles.observationDeclined }
        await RootSession.mainQueueTurn()
        await store.refresh()
        let model = WorkspaceSettingsModel(
            capabilities: state.capabilities, cssSnippetStore: store,
            agentBridgeAvailability: { .unavailable("Synthetic bridge; no external process") })
        let clock = ContinuousClock()
        let start = clock.now
        await model.restorePreferredWorkspaceIfNeeded(activeTriptychID: assignments[0].id)
        let restoreMilliseconds = milliseconds(start.duration(to: clock.now))
        #expect(model.selectedTriptychID == assignments[0].id)
        let baseline = try preferenceBytes(defaults.persistentDomain(forName: suiteName) ?? [:])
        succeeded = true
        return RootFixture(
            suiteName: suiteName, defaults: defaults, preferences: preferences, root: root,
            state: state, styles: styles, store: store, model: model, assignments: assignments,
            restoreMilliseconds: restoreMilliseconds, baseline: baseline)
    }

    func snapshot(active: UUID?) -> WorkspaceSettingsSnapshot { state.snapshot(active: active) }

    func assertReadOnlyPreferences() throws {
        let current = defaults.persistentDomain(forName: suiteName) ?? [:]
        #expect(try preferenceBytes(current).elementsEqual(baseline))
    }

    func preferenceDigest() throws -> String {
        sha256(try preferenceBytes(defaults.persistentDomain(forName: suiteName) ?? [:]))
    }

    func removeDefaults() { defaults.removePersistentDomain(forName: suiteName) }

    // Fixed semantic fixture identity excludes disposable paths and suite UUIDs.
    static let material =
        "settings-root-v1|2 Triptychs|3 slots each|fixture model|1 fixed Selection Action|empty snippets|synthetic storage|Zotero unavailable|nil Chat|all mutations reject"

    private static func makeAssignments(root: URL) -> [TriptychAssignment] {
        (1...2).map { ordinal in
            let vaults = Dictionary(
                uniqueKeysWithValues: WorkspaceVaultSlot.allCases.enumerated().map { index, slot in
                    let suffix = ordinal * 10 + index
                    let id = UUID(uuidString: String(format: "20000000-0000-0000-0000-%012d", suffix))!
                    return (
                        slot,
                        RegisteredVault(
                            id: id, name: "Fixture \(ordinal) \(slot.rawValue)", role: slot.vaultRole,
                            canonicalPath: root.appendingPathComponent("Triptych-\(ordinal)/\(slot.rawValue)").path,
                            registeredAt: Date(timeIntervalSince1970: 1_700_000_000))
                    )
                })
            let triptych = ScholiumTriptych(
                id: UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", ordinal))!,
                name: "Fixture \(ordinal)", paperAnalysisVaultID: vaults[.paperAnalysis]!.id,
                topicKnowledgeVaultID: vaults[.topicKnowledge]!.id, outputVaultID: vaults[.output]!.id,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
            return TriptychAssignment(triptych: triptych, vaults: vaults, hasCommonParent: true)
        }
    }
}

@MainActor
private final class RootFixtureState {
    var assignments: [TriptychAssignment]
    let root: URL
    var counts: [String: Int] = [:]
    var providerRequests: [UUID] = []
    var capabilityChatController: AgentChatController?
    var snapshotRequestIDs: [String] = []
    var portableLookupPaths: [String] = []
    var snapshotLoaderOverride: (@MainActor (UUID?) async throws -> WorkspaceSettingsSnapshot)?
    var portableLookupOverride: (@MainActor (URL) async -> URL?)?
    let historyUpdates = PassthroughSubject<UUID, Never>()
    var historyOwner: HistoryHostOwner?
    var unexpected: [String] = []

    init(assignments: [TriptychAssignment], root: URL) {
        self.assignments = assignments
        self.root = root
    }
    func count(_ key: String) { counts[key, default: 0] += 1 }
    func reject(_ key: String) -> RootHarnessError {
        unexpected.append(key)
        return .unexpected(key)
    }
    func snapshot(active: UUID?) -> WorkspaceSettingsSnapshot {
        .init(
            registeredVaults: assignments.flatMap { $0.vaults.values }, registeredTriptychs: assignments,
            activeTriptychID: active, portableSettingsState: .unavailable)
    }

    var capabilities: WorkspaceSettingsCapabilities {
        .init(
            workspace: .init(
                loadSnapshot: { [self] id in
                    count("workspace.loadSnapshot")
                    snapshotRequestIDs.append(id?.uuidString ?? "nil")
                    if let snapshotLoaderOverride { return try await snapshotLoaderOverride(id) }
                    return snapshot(active: id)
                },
                configureWorkspace: { [self] _, _, _, _, _, _ in throw reject("workspace.configure") },
                loadSettingsRecovery: { [self] _ in throw reject("workspace.recovery") },
                resetTriptychSettings: { [self] _, _ in throw reject("workspace.reset") },
                portableContainerURL: { [self] url in
                    count("workspace.portableContainerURL")
                    portableLookupPaths.append(url.path)
                    if let portableLookupOverride { return await portableLookupOverride(url) }
                    return nil
                }),
            zotero: .init(
                zoteroConnectionInfo: { [self] in
                    count("zotero.info")
                    return .init(status: .appUnavailable, lastSuccessfulConnection: nil)
                },
                openZotero: { [self] in _ = reject("zotero.open") },
                clearZoteroConnectionHistory: { [self] in throw reject("zotero.clear") },
                refreshZoteroLibraryInfo: { [self] in
                    count("zotero.refresh")
                    return .init(status: .appUnavailable, lastSuccessfulConnection: nil)
                },
                originalAccessGrants: { [self] in
                    count("zotero.grants")
                    return []
                },
                suggestedOriginalLibraryDirectory: { [self] in
                    count("zotero.suggestedDirectory")
                    return nil
                },
                authorizeOriginalAccess: { [self] _, _ in throw reject("zotero.authorize") },
                removeOriginalAccess: { [self] _ in throw reject("zotero.remove") }),
            changesHistory: .init(
                updates: historyOwner == nil
                    ? Empty<UUID, Never>().eraseToAnyPublisher()
                    : historyUpdates.eraseToAnyPublisher(),
                load: { [self] id in
                    count("history.load")
                    if let historyOwner { return try await historyOwner.load(id) }
                    return .init(retention: .days90, usage: .init(count: 3, byteCount: 1024))
                },
                setRetention: { [self] _, _ in throw reject("history.retention") },
                clear: { [self] _ in throw reject("history.clear") }),
            storage: .init(
                inventory: { [self] in
                    count("storage.inventory")
                    return .init(
                        rootURL: root, measuredAt: Date(timeIntervalSince1970: 1_700_000_000),
                        usages: ScholiumStorageCategory.allCases.map { .init(category: $0, byteCount: 1024, fileCount: 1) })
                },
                perform: { [self] _, _ in throw reject("storage.perform") },
                archivedChats: { [self] _ in throw reject("storage.archivedChats") },
                deleteArchivedChats: { [self] _ in throw reject("storage.deleteArchivedChats") },
                unusedChatMaterials: { [self] _ in throw reject("storage.unusedChatMaterials") },
                trashUnusedChatMaterials: { [self] _ in throw reject("storage.trashUnusedChatMaterials") })
        )
    }
}

@MainActor
private final class RootSession {
    static let agentRoutes: [(section: SettingsSection, index: Int)] = [
        (.agentBehavior, 0), (.agentCoreProtocol, 1), (.agentExternal, 2),
    ]
    let fixture: RootFixture
    let locale: Locale
    let window: NSWindow
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    private var isClosed = false
    var allowsVisibleWindow = false
    private weak var navigationController: SettingsNavigationController?
    private weak var cachedPageContainer: SettingsPaneContainerView?
    private weak var cachedAgentContainer: SettingsPaneContainerView?
    var pageContainer: SettingsPaneContainerView? {
        if let cachedPageContainer { return cachedPageContainer }
        let result = container("scholium.settings.pages")
        cachedPageContainer = result
        return result
    }
    var agentContainer: SettingsPaneContainerView? {
        if let cachedAgentContainer, !cachedAgentContainer.isHiddenOrHasHiddenAncestor { return cachedAgentContainer }
        let result = container("scholium.settings.agents.pages")
        cachedAgentContainer = result
        return result
    }

    init(fixture: RootFixture, locale: String, size: NSSize) {
        self.fixture = fixture
        self.locale = Locale(identifier: locale)
        _ = NSApplication.shared
        window = Self.makeWindow(size: size)
        host.sizingOptions = []
        host.sceneBridgingOptions = []
        window.contentView = host
    }

    static func makeWindow(size: NSSize) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    @discardableResult
    func mount() async throws -> RootStage {
        let clock = ContinuousClock()
        let start = clock.now
        host.rootView = AnyView(
            ScholiumSettingsView(
                preferences: fixture.preferences,
                chatControllerProvider: { [state = fixture.state] id in
                    state.providerRequests.append(id)
                    guard let controller = state.capabilityChatController, controller.triptychID == id else { return nil }
                    return controller
                }
            )
            .environmentObject(fixture.model)
            .environment(\.scholiumFileSelectionPresenter, nil)
            .environment(\.locale, locale)
            .environment(
                \.openURL,
                OpenURLAction { [state = fixture.state] _ in
                    _ = state.reject("openURL")
                    return .discarded
                })
        )
        try await waitForSelection(.workspace, previous: nil)
        let duration = milliseconds(start.duration(to: clock.now))
        try assertLayout(page: .workspace)
        return stage("fresh_open", page: .workspace, milliseconds: duration)
    }

    @discardableResult
    func select(_ page: ScholiumSettingsDestination, phase: String = "select") async throws -> RootStage {
        let old = pageContainer?.selectedView
        let wasSelected = window.toolbar?.selectedItemIdentifier == NSToolbarItem.Identifier("scholium.settings.category.\(page.rawValue)")
        let clock = ContinuousClock()
        let start = clock.now
        SettingsNavigationRequest.select(page, defaults: fixture.defaults)
        try await waitForSelection(page, previous: wasSelected ? nil : old)
        let duration = milliseconds(start.duration(to: clock.now))
        try assertLayout(page: page)
        return stage(phase, page: page, milliseconds: duration)
    }

    @discardableResult
    func reveal(_ section: SettingsSection, segment: Int) async throws -> RootStage {
        let clock = ContinuousClock()
        let start = clock.now
        SettingsNavigationRequest.reveal(section, defaults: fixture.defaults)
        try await waitForSelection(.agents, previous: nil)
        try await Self.waitUntil("selected Agent segment \(segment)") { [self] in
            layout()
            guard let active = pageContainer?.selectedView,
                let picker = activeDescendants(active).compactMap({ $0 as? NSSegmentedControl })
                    .first(where: { !$0.isHiddenOrHasHiddenAncestor && $0.segmentCount == 3 }),
                let container = agentContainer, let selected = container.selectedView
            else { return false }
            return picker.selectedSegment == segment && !selected.isHidden && selected.frame == container.bounds
                && fixture.defaults.object(forKey: SettingsNavigationRequest.requestedSectionKey) == nil
        }
        let duration = milliseconds(start.duration(to: clock.now))
        #expect(fixture.defaults.object(forKey: SettingsNavigationRequest.requestedSectionKey) == nil)
        return stage("agent_segment_\(segment)", page: .agents, milliseconds: duration)
    }

    private func stage(_ phase: String, page: ScholiumSettingsDestination, milliseconds: Double) -> RootStage {
        .init(
            phase: phase, page: page.rawValue, milliseconds: milliseconds,
            requestCounts: fixture.state.counts, providerRequestCount: fixture.state.providerRequests.count,
            nativeHostWidth: Double(host.bounds.width), nativeHostHeight: Double(host.bounds.height),
            selectedWidth: Double(pageContainer?.bounds.width ?? 0),
            selectedHeight: Double(pageContainer?.bounds.height ?? 0))
    }

    private func waitForSelection(_ page: ScholiumSettingsDestination, previous: NSView?) async throws {
        try await Self.waitUntil("selected native page \(page.rawValue)") { [self] in
            layout()
            guard let toolbar = window.toolbar, let container = pageContainer, let selected = container.selectedView else { return false }
            return toolbar.selectedItemIdentifier == .init("scholium.settings.category.\(page.rawValue)")
                && !selected.isHidden && selected.frame == container.bounds
                && (previous == nil || selected !== previous)
        }
    }

    func assertLayout(page: ScholiumSettingsDestination) throws {
        let container = try #require(pageContainer)
        let selected = try #require(container.selectedView)
        let toolbar = try #require(window.toolbar)
        var title = page.title
        title.locale = locale
        #expect(window.title == String(localized: title))
        #expect(toolbar.selectedItemIdentifier == .init("scholium.settings.category.\(page.rawValue)"))
        #expect(container.subviews.filter { !$0.isHidden }.count == 1)
        #expect(selected.frame == container.bounds)
        #expect(container.bounds.width > 0 && container.bounds.height > 0)
        #expect(host.bounds.width > 0 && host.bounds.height > 0)
        #expect(container.accessibilityChildren()?.isEmpty == false)
        if !allowsVisibleWindow { #expect(!window.isVisible) }
    }

    private func container(_ id: String) -> SettingsPaneContainerView? {
        activeDescendants(host).compactMap { $0 as? SettingsPaneContainerView }
            .first { $0.accessibilityIdentifier() == id && !$0.isHiddenOrHasHiddenAncestor }
    }

    private func layout() {
        host.layoutSubtreeIfNeeded()
        if navigationController == nil {
            for view in activeDescendants(host) {
                var responder: NSResponder? = view
                var seen: Set<ObjectIdentifier> = []
                while let current = responder, seen.insert(ObjectIdentifier(current)).inserted {
                    if let controller = current as? SettingsNavigationController {
                        navigationController = controller
                        break
                    }
                    responder = current.nextResponder
                }
                if navigationController != nil { break }
            }
        }
        // Unshown windows may not deliver viewDidAppear. This is the existing
        // native owner's method; it neither sends nor changes selection.
        navigationController?.attachToolbar()
        window.contentView?.layoutSubtreeIfNeeded()
    }

    func publishAndLayout() async {
        await Self.mainQueueTurn()
        layout()
        await Self.mainQueueTurn()
        layout()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        // Retire the native toolbar through its owner before removing the
        // SwiftUI host; representable dismantling can run in a later turn.
        navigationController?.detachToolbar()
        host.rootView = AnyView(EmptyView())
        window.toolbar = nil
        window.contentView = nil
        window.close()
    }

    static func mainQueueTurn() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    static func waitUntil(_ description: String, predicate: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        repeat {
            try Task.checkCancellation()
            if predicate() { return }
            await mainQueueTurn()
        } while clock.now < deadline
        throw RootHarnessError.timeout(description)
    }
}

/// No directory watcher and no reachable mutable Application operation. Reads
/// still execute the real StyleOperations against this fixture's Support root.
@MainActor
private final class RootStyles: StyleUseCases {
    let base: StyleOperations
    var observationDeclined = false
    var reads: [String: Int] = [:]
    var unexpected: [String] = []
    init(base: StyleOperations) { self.base = base }
    private func denied(_ name: String) -> RootHarnessError {
        unexpected.append(name)
        return .unexpected(name)
    }
    func styleSnapshot() async throws -> StyleSnapshot {
        reads["snapshot", default: 0] += 1
        return try await base.styleSnapshot()
    }
    func refreshStyleSnippets() async throws -> StyleSnapshot {
        reads["refresh", default: 0] += 1
        return try await base.refreshStyleSnippets()
    }
    func appearanceConfigurationURL() async throws -> URL { throw denied("appearanceURL") }
    func managedStylesLocation() async throws -> URL {
        observationDeclined = true
        throw RootHarnessError.observationDisabled
    }
    func managedStyleSnippetURL(_ id: UUID) async throws -> URL? { nil }
    func obsidianAppearance(at vaultRootURL: URL) async -> ObsidianAppearanceSnapshot? {
        _ = denied("obsidianAppearance")
        return nil
    }
    func createAppearanceProfile(named name: String) async throws -> StyleSnapshot { throw denied("createAppearance") }
    func selectAppearanceProfile(_ id: UUID) async throws -> StyleSnapshot { throw denied("selectAppearance") }
    func updateAppearanceProfile(_ profile: DocumentAppearanceProfile) async throws -> StyleSnapshot { throw denied("updateAppearance") }
    func renameAppearanceProfile(_ id: UUID, to name: String) async throws -> StyleSnapshot { throw denied("renameAppearance") }
    func duplicateAppearanceProfile(_ id: UUID) async throws -> StyleSnapshot { throw denied("duplicateAppearance") }
    func removeAppearanceProfile(_ id: UUID) async throws -> StyleSnapshot { throw denied("removeAppearance") }
    func reloadAppearanceConfiguration() async throws -> StyleSnapshot { throw denied("reloadAppearance") }
    func restoreAppearanceDefaults() async throws -> StyleSnapshot { throw denied("restoreAppearance") }
    func repairAppearanceProfile(_ profile: DocumentAppearanceProfile) async throws -> StyleSnapshot { throw denied("repairAppearance") }
    func restoreStyleSnippetDefaults() async throws -> StyleSnapshot { throw denied("restoreSnippets") }
    func importStyleSnippet(from sourceURL: URL) async throws -> StyleSnapshot { throw denied("importSnippet") }
    func setStyleSnippetEnabled(_ enabled: Bool, id: UUID) async throws -> StyleSnapshot { throw denied("enableSnippet") }
    func moveStyleSnippet(_ id: UUID, by offset: Int) async throws -> StyleSnapshot { throw denied("moveSnippet") }
    func renameStyleSnippet(_ id: UUID, to name: String) async throws -> StyleSnapshot { throw denied("renameSnippet") }
    func duplicateStyleSnippet(_ id: UUID) async throws -> StyleSnapshot { throw denied("duplicateSnippet") }
    func reloadStyleSnippet(_ id: UUID) async throws -> StyleSnapshot { throw denied("reloadSnippet") }
    func removeStyleSnippet(_ id: UUID) async throws -> StyleSnapshot { throw denied("removeSnippet") }
    func disableAllStyleSnippets() async throws -> StyleSnapshot { throw denied("disableSnippets") }
    func enterStyleSafeMode(reason: String) async throws -> StyleSnapshot { throw denied("safeMode") }
}

@MainActor
private final class StoreProbeRecords {
    struct Entry {
        let value: String
        let defaultsID: ObjectIdentifier
        let write: @MainActor (String) -> Void
    }
    var entries: [String: Entry] = [:]
}

private struct StoreProbe: View {
    @Environment(\.scholiumSettingsDefaults) private var defaults
    @AppStorage private var value: String
    let label: String
    let records: StoreProbeRecords
    static func key(_ label: String) -> String { "fixture.appStorage." + label }
    init(label: String, records: StoreProbeRecords) {
        self.label = label
        self.records = records
        _value = AppStorage(wrappedValue: "not-the-fixture", Self.key(label))
    }
    var body: some View {
        StoreProbeNative(label: label, value: value, defaults: defaults, records: records, write: { value = $0 })
    }
}

private struct StoreProbeNative: NSViewRepresentable {
    let label: String
    let value: String
    let defaults: UserDefaults
    let records: StoreProbeRecords
    let write: @MainActor (String) -> Void
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        records.entries[label] = .init(value: value, defaultsID: ObjectIdentifier(defaults), write: write)
    }
}

private struct RootStage: Codable {
    let phase: String
    let page: String
    let milliseconds: Double
    let requestCounts: [String: Int]
    let providerRequestCount: Int?
    let nativeHostWidth: Double
    let nativeHostHeight: Double
    let selectedWidth: Double
    let selectedHeight: Double
}

private struct RootObservation: Codable {
    let iteration: Int
    let locale: String
    let width: Double
    let height: Double
    let restoreMilliseconds: Double
    let restoreRequestCounts: [String: Int]
    let snapshotRequestIDs: [String]
    let portableLookupPaths: [String]
    let stages: [RootStage]
    let counts: [String: Int]
    let providerIDs: [String]?
    let preferenceSHA256: String
    let fixtureMaterialSHA256: String
    let styleReads: [String: Int]
    let inlineDraftState: String
}

private struct RootReport: Codable {
    struct Summary: Codable {
        let name: String
        let samples: Int
        let min: Double
        let median: Double
        let max: Double
    }
    let schema: String
    let configuration: String
    let providerObservation: String
    let endpoint: String
    let warmupsPerConfiguration: Int
    let retainedPerConfiguration: Int
    let observations: [RootObservation]
    let summaries: [Summary]
    static func summarize(_ observations: [RootObservation]) -> [Summary] {
        var values: [String: [Double]] = [:]
        for observation in observations {
            let prefix = "\(observation.locale)/\(Int(observation.width))x\(Int(observation.height))/"
            values[prefix + "model_restore", default: []].append(observation.restoreMilliseconds)
            for stage in observation.stages {
                values[prefix + stage.phase + "/" + stage.page, default: []].append(stage.milliseconds)
            }
        }
        return values.keys.sorted().map { key in
            let sorted = values[key]!.sorted()
            return Summary(name: key, samples: sorted.count, min: sorted.first!, median: sorted[sorted.count / 2], max: sorted.last!)
        }
    }
}

private enum RootHarnessError: Error {
    case unexpected(String)
    case timeout(String)
    case observationDisabled
    case unsupportedPreferenceType(String)
}

@MainActor private func activeDescendants(_ view: NSView) -> [NSView] {
    guard !view.isHidden else { return [] }
    return [view] + view.subviews.flatMap { activeDescendants($0) }
}
private func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1_000_000_000_000_000
}
private func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

/// Compare exact typed fixture values, ignoring only the four route-owned keys.
/// In particular NSNumber(bool) must not equal an integer with the same value.
@MainActor private func preferenceBytes(_ source: [String: Any]) throws -> Data {
    let routeKeys: Set<String> = [
        "scholium.settings.selectedPane", "scholium.settings.navigationRevision",
        SettingsNavigationRequest.requestedSectionKey, "scholium.settings.agentCategory",
    ]
    func tagged(_ value: Any) throws -> Any {
        if let data = value as? Data { return ["data": data.base64EncodedString()] }
        if let date = value as? Date { return ["date": date.timeIntervalSince1970.bitPattern.description] }
        if let number = value as? NSNumber {
            return ["numberType": CFGetTypeID(number) == CFBooleanGetTypeID() ? "bool" : String(cString: number.objCType), "value": number.stringValue]
        }
        if let string = value as? String { return ["utf8": Data(string.utf8).base64EncodedString()] }
        if let array = value as? [Any] { return try array.map(tagged) }
        if let dictionary = value as? [String: Any] { return try dictionary.mapValues(tagged) }
        throw RootHarnessError.unsupportedPreferenceType(String(describing: type(of: value)))
    }
    return try JSONSerialization.data(
        withJSONObject: source.filter { !routeKeys.contains($0.key) }.mapValues(tagged), options: [.sortedKeys])
}

// Actual Workspace host reads through fixture capability overrides. Strict read
// counts, confirmed/requested assignments and public routing are independent
// oracles; SwiftPM native field/Save publication is unrun.

extension SettingsRootNativeHostTests {
    @Test("Workspace host requests initial snapshot and immediate portable reads")
    func workspaceInitialReadAdmission() async throws {
        let fixture = try await RootFixture.make()
        let session = RootSession(fixture: fixture, locale: "en", size: NSSize(width: 780, height: 560))
        defer {
            session.close()
            fixture.removeDefaults()
        }
        let works = try #require(fixture.assignments[0].vault(for: .output))
        fixture.state.portableLookupOverride = { url in
            #expect(url.standardizedFileURL.path == URL(fileURLWithPath: works.canonicalPath).standardizedFileURL.path)
            return url.deletingLastPathComponent().standardizedFileURL
        }
        let before = fixture.state.counts["workspace.loadSnapshot", default: 0]
        try await session.mount()
        try await RootSession.waitUntil("actual Workspace snapshot and portable read admissions") {
            fixture.state.counts["workspace.loadSnapshot", default: 0] > before
                && fixture.state.counts["workspace.portableContainerURL", default: 0] > 0
                && fixture.model.snapshot == fixture.snapshot(active: fixture.firstID)
                && !fixture.model.isRefreshing
        }
        await session.publishAndLayout()
        let mountSnapshotReads = fixture.state.counts["workspace.loadSnapshot", default: 0] - before
        let portableReads = fixture.state.counts["workspace.portableContainerURL", default: 0]
        #expect(mountSnapshotReads == 1)
        #expect(portableReads == 1)
        #expect(fixture.state.snapshotRequestIDs.allSatisfy { $0 == fixture.firstID.uuidString })
        #expect(fixture.state.portableLookupPaths.allSatisfy { $0 == works.canonicalPath })
        #expect(fixture.model.selectedTriptychID == fixture.firstID)
        #expect(fixture.model.workspaceAssignment == fixture.assignments[0])
        #expect(fixture.model.registeredTriptychs == fixture.assignments)
        try session.assertLayout(page: .workspace)

        let manualBefore = fixture.state.counts["workspace.loadSnapshot", default: 0]
        #expect(await fixture.model.refresh())
        await session.publishAndLayout()
        #expect(fixture.state.counts["workspace.loadSnapshot", default: 0] == manualBefore + 1)
        #expect(fixture.model.snapshot == fixture.snapshot(active: fixture.firstID))
        #expect(!fixture.model.isRefreshing && fixture.model.errorMessage == nil)
        let record = [
            "preMountSnapshotReads": before, "mountSnapshotReads": mountSnapshotReads,
            "initialPortableReads": portableReads,
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print("SCHOLIUM_SETTINGS_PATH_INITIAL_READS " + String(decoding: try encoder.encode(record), as: UTF8.self))
        #expect(fixture.state.unexpected.isEmpty)
        try fixture.assertReadOnlyPreferences()
        // This endpoint proves read admission and an immediate fixture reply;
        // it does not prove Name text, a published portable label or Save state.
    }

    @Test("A requested unconfirmed Triptych retains its confirmed snapshot until its read returns")
    func workspaceRequestedScopeWaitsForConfirmation() async throws {
        let fixture = try await RootFixture.make()
        let session = RootSession(fixture: fixture, locale: "en", size: NSSize(width: 780, height: 560))
        defer {
            fixture.state.snapshotLoaderOverride = nil
            session.close()
            fixture.removeDefaults()
        }
        let first = fixture.assignments[0]
        let secondID = fixture.secondID
        let onlyFirst = WorkspaceSettingsSnapshot(
            registeredVaults: Array(first.vaults.values), registeredTriptychs: [first], activeTriptychID: first.id)
        let confirmedSecond = fixture.snapshot(active: secondID)
        let reads = RequestedScopeReadBarrier()
        fixture.state.snapshotLoaderOverride = { id in
            try Task.checkCancellation()
            guard !reads.stopping else { throw CancellationError() }
            guard id == secondID else { return onlyFirst }
            if reads.released { return confirmedSecond }
            return try await withCheckedThrowingContinuation { reads.pending.append($0) }
        }
        fixture.state.portableLookupOverride = { $0.deletingLastPathComponent().standardizedFileURL }
        fixture.model.replaceSnapshot(onlyFirst)
        let before = fixture.state.counts["workspace.loadSnapshot", default: 0]
        try await session.mount()
        try await RootSession.waitUntil("first-scope host read and confirmed model assignment") {
            fixture.state.counts["workspace.loadSnapshot", default: 0] > before
                && fixture.model.snapshot == onlyFirst && fixture.model.workspaceAssignment == first
                && !fixture.model.isRefreshing
        }
        let selection = Task { await fixture.model.activateTriptych(id: secondID) }
        do {
            try await RootSession.waitUntil("requested-scope read enters while confirmation remains A") {
                !reads.pending.isEmpty && fixture.model.selectedTriptychID == secondID
                    && fixture.model.snapshot == onlyFirst && fixture.model.workspaceAssignment == first
            }
            SettingsNavigationRequest.reveal(.workspaceName, defaults: fixture.defaults)
            try await RootSession.waitUntil("public Workspace Name section request is consumed") {
                fixture.defaults.object(forKey: SettingsNavigationRequest.requestedSectionKey) == nil
            }
            await session.publishAndLayout()
            try session.assertLayout(page: .workspace)
            #expect(reads.pending.count == 1)
            print("SCHOLIUM_SETTINGS_PATH_SCOPE_READS \(reads.pending.count)")
            #expect(fixture.model.registeredTriptychs == [first])
            #expect(!fixture.model.registeredTriptychs.contains { $0.id == secondID })
            #expect(fixture.model.snapshot.activeTriptychID == first.id)
            let works = try #require(fixture.assignments[1].vault(for: .output))
            #expect(!fixture.state.portableLookupPaths.contains(works.canonicalPath))
            reads.released = true
            let waiting = reads.pending
            reads.pending.removeAll()
            for continuation in waiting { continuation.resume(returning: confirmedSecond) }
            await selection.value
            try await RootSession.waitUntil("confirmed B assignment permits its actual portable lookup") {
                fixture.model.snapshot == confirmedSecond && fixture.model.selectedTriptychID == secondID
                    && fixture.model.workspaceAssignment == fixture.assignments[1]
                    && fixture.state.portableLookupPaths.contains(works.canonicalPath)
                    && !fixture.model.isRefreshing
            }
            #expect(fixture.model.registeredTriptychs == fixture.assignments)
            #expect(fixture.model.errorMessage == nil)
            #expect(fixture.state.unexpected.isEmpty)
            try fixture.assertReadOnlyPreferences()
            // No native blank/disabled/text/Save claim: those semantic targets
            // are not exposed by this SwiftPM host's public control/AX trees.
        } catch {
            reads.stopping = true
            selection.cancel()
            let waiting = reads.pending
            reads.pending.removeAll()
            for continuation in waiting { continuation.resume(throwing: CancellationError()) }
            await selection.value
            throw error
        }
    }
}

/// Owns only the requested-scope fixture's suspended snapshot reads. A reference
/// captured as a let keeps all mutable barrier state on the MainActor.
@MainActor
private final class RequestedScopeReadBarrier {
    var released = false
    var stopping = false
    var pending: [CheckedContinuation<WorkspaceSettingsSnapshot, any Error>] = []
}

// MARK: - Actual retained History read admissions with controlled capabilities

extension SettingsRootNativeHostTests {
    @Test(
        "Retained History admits reads only for its active selected scope",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_TEST_SETTINGS_READ_HOSTS"] == "1"))
    func historyHiddenAdmissions() async throws {
        try await withHistoryRoot("hidden-admissions") { fixture, session, owner in
            owner.labels["proofBoundary"] = "actual retained read admission and completed fixture replies; native control/display/input unrun"
            owner.phase = "visible-A"
            try await showHistory(session, fixture: fixture)
            let first = try await owner.waitForRequest("load", target: fixture.firstID, ordinal: 1)
            owner.complete(first, with: historySnapshot(.days90, count: 1111))
            try await historyLayoutBoundary(session)
            #expect(owner.record(first)?.completion == "success")
            #expect(owner.requests("load", target: fixture.firstID).count == 1)
            let retainedHost = try #require(session.pageContainer?.selectedView)
            #expect(fixture.model.selectedTriptychID == fixture.firstID)
            #expect(fixture.defaults.object(forKey: SettingsNavigationRequest.requestedSectionKey) == nil)

            // The second real load is the positive subscription/admission
            // oracle. A completed fake reply is not a displayed-popup oracle.
            owner.phase = "visible-A-update"
            fixture.state.historyUpdates.send(fixture.firstID)
            let updated = try await owner.waitForRequest("load", target: fixture.firstID, ordinal: 2)
            owner.complete(updated, with: historySnapshot(.days90, count: 1112))
            try await historyLayoutBoundary(session)
            #expect(owner.record(updated)?.completion == "success")
            #expect(owner.requests("load", target: fixture.firstID).count == 2)

            _ = try await session.select(.document)
            try await historyLayoutBoundary(session)
            #expect(retainedHost.isHidden)
            owner.phase = "hidden-A-update"
            fixture.state.historyUpdates.send(fixture.firstID)
            fixture.state.historyUpdates.send(fixture.secondID)
            try await historyLayoutBoundary(session)
            #expect(owner.requests("load", target: fixture.firstID).count == 2)
            owner.observations["hidden_updates_new_A_reads"] = owner.requests("load", target: fixture.firstID).count - 2

            owner.phase = "hidden-target-B"
            await fixture.model.activateTriptych(id: fixture.secondID)
            try await historyLayoutBoundary(session)
            #expect(fixture.model.selectedTriptychID == fixture.secondID)
            #expect(fixture.model.workspaceAssignment == fixture.assignments[1])
            #expect(retainedHost.isHidden)
            #expect(owner.requests("load", target: fixture.secondID).isEmpty)
            owner.observations["hidden_target_B_reads"] = owner.requests("load", target: fixture.secondID).count
            for hidden in owner.requests("load", target: fixture.secondID) where hidden.completion == nil {
                owner.complete(hidden.id, with: historySnapshot(.days365, count: 2222))
            }
            try await historyLayoutBoundary(session)

            owner.phase = "reactivated-B"
            try await showHistory(session, fixture: fixture)
            if owner.requests("load", target: fixture.secondID).isEmpty {
                _ = try await owner.waitForRequest("load", target: fixture.secondID, ordinal: 1)
            }
            for visible in owner.requests("load", target: fixture.secondID) where visible.completion == nil {
                owner.complete(visible.id, with: historySnapshot(.days365, count: 2222))
            }
            try await historyLayoutBoundary(session)
            #expect(session.pageContainer?.selectedView === retainedHost)
            #expect(!retainedHost.isHidden)
            #expect(fixture.model.selectedTriptychID == fixture.secondID)
            #expect(fixture.defaults.object(forKey: SettingsNavigationRequest.requestedSectionKey) == nil)
            #expect(owner.requests("load", target: fixture.firstID).count == 2)
            #expect(owner.requests("load", target: fixture.secondID).allSatisfy { $0.completion == "success" })
            owner.observations["final_B_reads"] = owner.requests("load", target: fixture.secondID).count
            #expect(owner.requests("load", target: fixture.secondID).count == 1)
            #expect(fixture.state.unexpected.isEmpty)
            try fixture.assertReadOnlyPreferences()
        }
    }
}

@MainActor
private func withHistoryRoot(
    _ name: String,
    operation: @MainActor (RootFixture, RootSession, HistoryHostOwner) async throws -> Void
) async throws {
    let owner = HistoryHostOwner()
    let fixture = try await RootFixture.make(historyOwner: owner)
    let session = RootSession(fixture: fixture, locale: "en", size: NSSize(width: 920, height: 700))
    defer { fixture.removeDefaults() }
    try await withTaskCancellationHandler {
        do {
            try await session.mount()
            try await operation(fixture, session, owner)
        } catch {
            owner.abort()
            session.close()
            await RootSession.mainQueueTurn()
            await RootSession.mainQueueTurn()
            try? owner.writeEvidence(name: name, fixture: fixture, error: String(describing: error))
            throw error
        }
        owner.abort()
        session.close()
        await RootSession.mainQueueTurn()
        await RootSession.mainQueueTurn()
        try owner.writeEvidence(name: name, fixture: fixture, error: nil)
    } onCancel: {
        Task { @MainActor in
            owner.abort()
            session.close()
        }
    }
}

@MainActor
private func showHistory(_ session: RootSession, fixture: RootFixture) async throws {
    _ = try await session.select(.storage)
    SettingsNavigationRequest.reveal(.storageChangesHistory, defaults: fixture.defaults)
    try await historyLayoutBoundary(session)
}

@MainActor
private func historyLayoutBoundary(_ session: RootSession) async throws {
    try Task.checkCancellation()
    // A bounded native projection boundary, not a timing or indefinite-absence
    // proof. Positive request entries use continuation gates below.
    for _ in 0..<3 { await session.publishAndLayout() }
    try Task.checkCancellation()
}

private func historySnapshot(_ retention: DocumentChangeRetention, count: Int) -> WorkspaceChangesHistorySnapshot {
    .init(retention: retention, usage: .init(count: count, byteCount: count * 64))
}

/// Test-only controlled capability, not a shadow of the View state machine.
/// Reads deliberately ignore cancellation until explicitly released, recording
/// the cancellation independently so stale publication cannot masquerade as abort.
@MainActor
private final class HistoryHostOwner {
    struct Record: Codable {
        let id: UUID
        let ordinal: Int
        let operation: String
        let target: UUID
        let phase: String
        var cancellationObserved: Bool
        var completion: String?
    }
    private struct Waiter {
        let operation: String
        let target: UUID
        let ordinal: Int
        let continuation: CheckedContinuation<UUID, Error>
    }

    var phase = "setup"
    var observations: [String: Int] = [:]
    var labels: [String: String] = [:]
    private var records: [Record] = []
    private var pending: [UUID: CheckedContinuation<WorkspaceChangesHistorySnapshot, Error>] = [:]
    private var waiters: [UUID: Waiter] = [:]
    private var deadlines: [UUID: Task<Void, Never>] = [:]
    private var cancelledBeforeEntry: Set<UUID> = []
    private var aborted = false
    private var maximumInFlight = 0

    func requests(_ operation: String, target: UUID) -> [Record] {
        records.filter { $0.operation == operation && $0.target == target }
    }
    func record(_ id: UUID) -> Record? { records.first { $0.id == id } }

    func load(_ target: UUID) async throws -> WorkspaceChangesHistorySnapshot {
        try await request("load", target: target)
    }

    private func request(_ operation: String, target: UUID) async throws -> WorkspaceChangesHistorySnapshot {
        guard !aborted else { throw CancellationError() }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !aborted else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                records.append(
                    .init(
                        id: id, ordinal: records.count, operation: operation, target: target,
                        phase: phase,
                        cancellationObserved: Task.isCancelled || cancelledBeforeEntry.remove(id) != nil,
                        completion: nil))
                pending[id] = continuation
                maximumInFlight = max(maximumInFlight, pending.count)
                releaseSatisfiedWaiters()
            }
        } onCancel: {
            Task { @MainActor in self.noteCancellation(id) }
        }
    }

    private func noteCancellation(_ id: UUID) {
        if let index = records.firstIndex(where: { $0.id == id }) {
            records[index].cancellationObserved = true
        } else {
            cancelledBeforeEntry.insert(id)
        }
        // Intentionally no continuation resume: this is the noncooperative arm.
    }

    func waitForRequest(_ operation: String, target: UUID, ordinal: Int) async throws -> UUID {
        let existing = requests(operation, target: target)
        if existing.count >= ordinal { return existing[ordinal - 1].id }
        guard !aborted else { throw CancellationError() }
        let token = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if aborted {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters[token] = .init(operation: operation, target: target, ordinal: ordinal, continuation: continuation)
                // Deadline only; ordering/entry proof comes from continuations,
                // never a sleep used to manufacture the expected overlap.
                deadlines[token] = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    failWaiter(token, error: RootHarnessError.timeout("History \(operation) #\(ordinal) for \(target)"))
                }
                releaseSatisfiedWaiters()
            }
        } onCancel: {
            Task { @MainActor in self.failWaiter(token, error: CancellationError()) }
        }
    }

    private func releaseSatisfiedWaiters() {
        for (id, waiter) in Array(waiters) {
            let entries = requests(waiter.operation, target: waiter.target)
            if entries.count >= waiter.ordinal {
                waiters[id] = nil
                deadlines.removeValue(forKey: id)?.cancel()
                waiter.continuation.resume(returning: entries[waiter.ordinal - 1].id)
            }
        }
    }
    private func failWaiter(_ id: UUID, error: Error) {
        deadlines.removeValue(forKey: id)?.cancel()
        waiters.removeValue(forKey: id)?.continuation.resume(throwing: error)
    }
    func complete(_ id: UUID, with snapshot: WorkspaceChangesHistorySnapshot) {
        guard let continuation = pending.removeValue(forKey: id) else {
            Issue.record("No pending History capability for \(id)")
            return
        }
        if let index = records.firstIndex(where: { $0.id == id }) { records[index].completion = "success" }
        continuation.resume(returning: snapshot)
    }
    func abort() {
        aborted = true
        for id in Array(waiters.keys) { failWaiter(id, error: CancellationError()) }
        let suspended = pending
        pending.removeAll()
        for (id, continuation) in suspended {
            if let index = records.firstIndex(where: { $0.id == id }) { records[index].completion = "cleanup-cancelled" }
            continuation.resume(throwing: CancellationError())
        }
    }
    func writeEvidence(name: String, fixture: RootFixture, error: String?) throws {
        struct Evidence: Encodable {
            let test: String
            let arm: String
            let endpoint: String
            let fixtureDigest: String
            let requests: [Record]
            let observations: [String: Int]
            let maximumInFlight: Int
            let labels: [String: String]
            let error: String?
            let testResult: String
        }
        let evidence = Evidence(
            test: name, arm: "active-read-candidate",
            endpoint:
                "actual unshown Settings root and History read capability; native control/input/display and late mutation integration unrun; no scene or timing proof",
            fixtureDigest: fixture.fixtureDigest, requests: records,
            observations: observations, maximumInFlight: maximumInFlight, labels: labels, error: error,
            testResult: "Testing runner owns pass/fail; completed records are not a correctness or performance pass")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(evidence).write(
            to: fixture.root.appendingPathComponent("history-host-\(name)-candidate.json"),
            options: .atomic)
    }
}

extension SettingsRootNativeHostTests {
    @Test(
        "Opt-in owned Settings host pixel evidence without benchmark timing",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_CAPTURE_SETTINGS_VISUAL"] == "1"))
    func captureNativeSettingsPixels() async throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let template = repository.appendingPathComponent("TestVaults", isDirectory: true)
        guard FileManager.default.fileExists(atPath: template.appendingPathComponent("README.md").path) else {
            throw RootHarnessError.unexpected("Standard TestVaults unavailable; do not substitute a real vault")
        }
        let originalBytes = try visualSourceInventory(template)
        let expectedRoleCounts = ["01-analyses": 160, "02-topics": 220, "03-works": 120]
        let roleNoteCounts = expectedRoleCounts.keys.map { role in
            (role, originalBytes.keys.filter { $0.hasPrefix(role + "/") && $0.lowercased().hasSuffix(".md") }.count)
        }
        let copiedRoleNoteCounts = Dictionary(uniqueKeysWithValues: roleNoteCounts)
        guard copiedRoleNoteCounts == expectedRoleCounts else {
            throw RootHarnessError.unexpected("Standard TestVaults must contain the expected 500 role notes")
        }
        let scenarios: [(locale: String, width: Double, height: Double, appearance: NSAppearance.Name, allPages: Bool)] = [
            ("en", 780, 560, .aqua, true),
            ("zh-Hans", 780, 560, .aqua, true),
            ("en", 920, 700, .accessibilityHighContrastDarkAqua, false),
        ]
        var reports: [String] = []
        for scenario in scenarios {
            let fixture = try await RootFixture.make()
            defer { fixture.removeDefaults() }
            let copy = fixture.root.appendingPathComponent("StandardTriptych", isDirectory: true)
            guard !FileManager.default.fileExists(atPath: copy.path) else {
                throw RootHarnessError.unexpected("Refusing to replace an existing visual fixture copy")
            }
            // Registered only after proving this exact owned path absent, and
            // before copyItem so even its partial failure is cleaned up. On the
            // success path this runs after inventory proof/report writing and
            // session.close(); PNGs, reports and the original remain untouched.
            defer {
                do {
                    if FileManager.default.fileExists(atPath: copy.path) {
                        try FileManager.default.removeItem(at: copy)
                    }
                    #expect(!FileManager.default.fileExists(atPath: copy.path))
                } catch {
                    Issue.record(error, "Could not remove the owned StandardTriptych visual copy")
                }
            }
            try FileManager.default.copyItem(at: template, to: copy)
            guard try visualSourceInventory(copy) == originalBytes else {
                fixture.removeDefaults()
                throw RootHarnessError.unexpected("Copied standard fixture differs before visual hosting")
            }
            let originalAssignment = fixture.assignments[0]
            let roles: [WorkspaceVaultSlot: String] = [
                .paperAnalysis: "01-analyses", .topicKnowledge: "02-topics", .output: "03-works",
            ]
            var copiedVaults: [WorkspaceVaultSlot: RegisteredVault] = [:]
            for slot in WorkspaceVaultSlot.allCases {
                let originalVault = try #require(originalAssignment.vault(for: slot))
                let path = copy.appendingPathComponent(try #require(roles[slot]), isDirectory: true)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    fixture.removeDefaults()
                    throw RootHarnessError.unexpected("Missing copied role directory")
                }
                copiedVaults[slot] = RegisteredVault(
                    id: originalVault.id, name: originalVault.name, role: slot.vaultRole,
                    canonicalPath: path.path, registeredAt: originalVault.registeredAt)
            }
            fixture.state.assignments = [
                TriptychAssignment(triptych: originalAssignment.triptych, vaults: copiedVaults, hasCommonParent: true)
            ]
            fixture.model.replaceSnapshot(fixture.snapshot(active: originalAssignment.id))
            let session = RootSession(
                fixture: fixture, locale: scenario.locale,
                size: NSSize(width: scenario.width, height: scenario.height))
            defer { session.close() }
            session.allowsVisibleWindow = true
            _ = try await session.mount()
            let appearance = try #require(NSAppearance(named: scenario.appearance))
            session.window.appearance = appearance
            session.host.appearance = appearance
            session.window.orderFront(nil)
            let output = fixture.root.appendingPathComponent("visual", isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            var captures: [SettingsVisualCapture] = []
            let pages: [ScholiumSettingsDestination] =
                scenario.allPages
                ? ScholiumSettingsDestination.allCases : [.document, .writing, .storage]
            for page in pages {
                _ = try await session.select(page)
                await session.publishAndLayout()
                captures += try await captureOwnedSettingsHost(session, output: output, name: page.rawValue)
                try fixture.assertReadOnlyPreferences()
            }
            if scenario.allPages {
                for route in RootSession.agentRoutes {
                    _ = try await session.reveal(route.section, segment: route.index)
                    await session.publishAndLayout()
                    captures += try await captureOwnedSettingsHost(session, output: output, name: "agents-segment-\(route.index)")
                    try fixture.assertReadOnlyPreferences()
                }
            }
            #expect(session.window.isVisible)
            #expect(fixture.state.unexpected.isEmpty && fixture.styles.unexpected.isEmpty)
            let copyUnchanged = try visualSourceInventory(copy) == originalBytes
            let originalUnchanged = try visualSourceInventory(template) == originalBytes
            #expect(copyUnchanged && originalUnchanged)
            let report = SettingsVisualReport(
                schema: "scholium.settings-owned-host-pixels.v1", locale: scenario.locale,
                requestedSize: [scenario.width, scenario.height], appearance: scenario.appearance.rawValue,
                copyRoot: copy.path, sourceInventorySHA256: sha256(try visualEncode(originalBytes)),
                sourceFileCount: originalBytes.count, copiedRoleNoteCounts: copiedRoleNoteCounts, unchangedOriginalAndCopy: copyUnchanged && originalUnchanged,
                windowWasVisible: session.window.isVisible,
                localization: settingsVisualLocalizationBoundary(locale: scenario.locale),
                captures: captures, preferenceSHA256: try fixture.preferenceDigest(),
                limits: [
                    "Owned NSHostingView bitmaps only; native window titlebar/toolbar chrome is outside captured host bounds",
                    "Synthetic Settings capabilities and nil Chat; no original vault registration, live runtime or external actions",
                    "Layout/display callback proxy; no screen capture, paint latency, keyboard/IME or human/VoiceOver acceptance",
                    "Public NSScrollView tiles request 0.85-viewport advances, at most 12 captures including top/bottom; actual origins and incomplete sweeps are recorded",
                    "Private font-catalog/background completion is not an observed endpoint",
                    "High-contrast Dark uses a local NSAppearance on one owned window/host; no global preference changes",
                ])
            let url = output.appendingPathComponent("report.json")
            try visualEncode(report).write(to: url, options: .atomic)
            reports.append(url.path)
        }
        #expect(try visualSourceInventory(template) == originalBytes)
        print("SCHOLIUM_SETTINGS_VISUAL " + String(decoding: try visualEncode(reports), as: UTF8.self))
    }
}

private struct SettingsVisualCapture: Codable {
    let name: String
    let position: String
    let png: String
    let pngSHA256: String
    let pixels: [Int]
    let hostBounds: [Double]
    let scrollObservation: String
    let scrollOriginY: Double?
    let viewportHeight: Double?
    let documentHeight: Double?
}

private struct SettingsVisualReport: Codable {
    let schema: String
    let locale: String
    let requestedSize: [Double]
    let appearance: String
    let copyRoot: String
    let sourceInventorySHA256: String
    let sourceFileCount: Int
    let copiedRoleNoteCounts: [String: Int]
    let unchangedOriginalAndCopy: Bool
    let windowWasVisible: Bool
    let localization: SettingsVisualLocalization
    let captures: [SettingsVisualCapture]
    let preferenceSHA256: String
    let limits: [String]
}

@MainActor
private func captureOwnedSettingsHost(_ session: RootSession, output: URL, name: String) async throws -> [SettingsVisualCapture] {
    let selected = try #require(session.pageContainer?.selectedView)
    // Choose the largest visible overflowing scroll viewport, rather than a
    // private SwiftUI view or a local text editor with an assumed class name.
    let scroll = activeDescendants(selected).compactMap { $0 as? NSScrollView }.filter {
        guard let document = $0.documentView else { return false }
        return document.bounds.height > $0.contentView.bounds.height + 1
    }.max { lhs, rhs in
        lhs.contentView.bounds.width * lhs.contentView.bounds.height
            < rhs.contentView.bounds.width * rhs.contentView.bounds.height
    }
    func move(to y: CGFloat) {
        guard let scroll, y.isFinite else { return }
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.origin.x, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    func move(_ bottom: Bool) {
        guard let scroll, let document = scroll.documentView else { return }
        let low = document.bounds.minY
        let high = max(low, document.bounds.maxY - scroll.contentView.bounds.height)
        move(to: (bottom == document.isFlipped) ? high : low)
    }
    func bitmap(_ position: String, observation: String) throws -> SettingsVisualCapture {
        session.host.layoutSubtreeIfNeeded()
        session.host.displayIfNeeded()
        let representation = try #require(session.host.bitmapImageRepForCachingDisplay(in: session.host.bounds))
        session.host.cacheDisplay(in: session.host.bounds, to: representation)
        let png = try #require(representation.representation(using: .png, properties: [:]))
        let url = output.appendingPathComponent(name + "-" + position + ".png")
        try png.write(to: url, options: .atomic)
        let bounds = session.host.bounds
        return SettingsVisualCapture(
            name: name, position: position, png: url.path, pngSHA256: sha256(png),
            pixels: [representation.pixelsWide, representation.pixelsHigh],
            hostBounds: [Double(bounds.minX), Double(bounds.minY), Double(bounds.width), Double(bounds.height)],
            scrollObservation: observation, scrollOriginY: scroll.map { Double($0.contentView.bounds.origin.y) },
            viewportHeight: scroll.map { Double($0.contentView.bounds.height) },
            documentHeight: (scroll?.documentView).map { Double($0.bounds.height) })
    }
    move(false)
    await session.publishAndLayout()
    let top = try bitmap(
        "top",
        observation: scroll == nil
            ? "No overflowing public NSScrollView discovered; bottom is unverified or unnecessary" : "Largest visible overflowing public NSScrollView")
    guard let scroll else { return [top] }
    let maximumCaptures = 12  // Includes top, at most ten interior tiles, and bottom.
    var captures = [top]
    var tilingObservation = "Interior sweep reached within one 0.85-viewport step of bottom"
    while captures.count < maximumCaptures - 1 {
        guard let document = scroll.documentView else {
            tilingObservation = "Document view disappeared; full coverage unverified"
            break
        }
        let viewport = scroll.contentView.bounds.height
        guard viewport.isFinite && viewport > 0 else {
            tilingObservation = "Invalid scroll viewport; full coverage unverified"
            break
        }
        let low = document.bounds.minY
        let high = max(low, document.bounds.maxY - viewport)
        let bottom = document.isFlipped ? high : low
        let oldY = scroll.contentView.bounds.origin.y
        guard bottom.isFinite && oldY.isFinite else {
            tilingObservation = "Invalid clip/document bounds; full coverage unverified"
            break
        }
        let step = viewport * 0.85
        guard abs(bottom - oldY) > step else { break }
        let direction: CGFloat = document.isFlipped ? 1 : -1
        move(to: oldY + direction * step)
        await session.publishAndLayout()
        let progress = (scroll.contentView.bounds.origin.y - oldY) * direction
        guard progress > 0.5 else {
            tilingObservation = "Interior request made no forward progress; full coverage unverified"
            break
        }
        let boundedAdvance = progress <= step + 0.5  // Allow subpoint AppKit rounding.
        captures.append(
            try bitmap(
                "tile-\(captures.count)",
                observation: boundedAdvance
                    ? "Interior public clip origin; requested advance 0.85 viewport, actual origin recorded"
                    : "Public clip jumped beyond requested step; full coverage unverified"))
        if !boundedAdvance {
            tilingObservation = "Interior clip jump exceeded requested step; full coverage unverified"
            break
        }
    }
    if captures.count == maximumCaptures - 1 {
        tilingObservation = "Twelve-capture bound reached; final bottom may leave an interior gap"
    }
    let oldY = scroll.contentView.bounds.origin.y
    move(true)  // Always request and record bottom, even after a bound/no-progress bail.
    await session.publishAndLayout()
    let moved = abs(scroll.contentView.bounds.origin.y - oldY) > 0.5
    let reachedBottom =
        scroll.documentView.map { document in
            let low = document.bounds.minY
            let high = max(low, document.bounds.maxY - scroll.contentView.bounds.height)
            let expected = document.isFlipped ? high : low
            return expected.isFinite && abs(scroll.contentView.bounds.origin.y - expected) <= 0.5
        } ?? false
    let bottomObservation =
        reachedBottom
        ? "Final actual clip origin matches the live bottom bound"
        : "Final bottom request did not reach a verified live bottom bound"
    captures.append(
        try bitmap("bottom", observation: tilingObservation + "; " + bottomObservation + (moved ? "; distinct final origin" : "; unchanged final origin")))
    return captures
}

private func visualEncode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
}

private func visualSourceInventory(_ root: URL) throws -> [String: String] {
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
    var enumerationError: Error?
    guard
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys),
            errorHandler: { _, error in
                enumerationError = error
                return false
            })
    else {
        throw RootHarnessError.unexpected("Cannot enumerate owned standard fixture")
    }
    var result: [String: String] = [:]
    for case let file as URL in enumerator {
        let values = try file.resourceValues(forKeys: keys)
        guard values.isSymbolicLink != true else { throw RootHarnessError.unexpected("Fixture symlink is not accepted for this visual harness") }
        if values.isRegularFile == true {
            guard file.path.hasPrefix(root.path + "/") else { throw RootHarnessError.unexpected("Fixture path escaped its root") }
            result[String(file.path.dropFirst(root.path.count + 1))] = sha256(try Data(contentsOf: file))
        }
    }
    if let enumerationError { throw enumerationError }
    return result
}

private struct SettingsVisualLocalization: Codable {
    let mainBundlePath: String
    let mainExecutablePath: String?
    let mainResourcesPath: String?
    let availableMainLocalizations: [String]
    let requestedLocale: String
    let languageResourcePath: String?
    let compiledLanguageResourceSHA256: [String: String]
    let localizedSentinels: [String: String]
    let resourceStatus: String
    let scope: String
}

private func settingsVisualLocalizationBoundary(locale: String) -> SettingsVisualLocalization {
    let languagePath = Bundle.main.path(forResource: locale, ofType: "lproj")
    let languageBundle = languagePath.flatMap { Bundle(path: $0) }
    let expectations: [String: String] =
        locale == "zh-Hans"
        ? ["Open Workspace Settings": "打开工作区设置", "Keep Reviewed History": "保留已查看历史"]
        : ["Open Workspace Settings": "Open Workspace Settings", "Keep Reviewed History": "Keep Reviewed History"]
    let resolved = expectations.mapValues { _ in "" }
    var sentinels = resolved
    for key in expectations.keys {
        sentinels[key] = languageBundle?.localizedString(forKey: key, value: nil, table: "Localizable") ?? "<language bundle unavailable>"
    }
    var hashes: [String: String] = [:]
    if let languagePath, let files = try? FileManager.default.contentsOfDirectory(atPath: languagePath) {
        for name in files.sorted() where name.hasSuffix(".strings") || name.hasSuffix(".stringsdict") {
            let file = URL(fileURLWithPath: languagePath).appendingPathComponent(name)
            hashes[name] = (try? Data(contentsOf: file)).map(sha256) ?? "unreadable"
        }
    }
    let available = languageBundle != nil && sentinels == expectations && !hashes.isEmpty && !hashes.values.contains("unreadable")
    return SettingsVisualLocalization(
        mainBundlePath: Bundle.main.bundleURL.path, mainExecutablePath: Bundle.main.executableURL?.path,
        mainResourcesPath: Bundle.main.resourceURL?.path, availableMainLocalizations: Bundle.main.localizations,
        requestedLocale: locale, languageResourcePath: languagePath, compiledLanguageResourceSHA256: hashes,
        localizedSentinels: sentinels,
        resourceStatus: available
            ? "requested main language resources and exact sentinels present" : "UNRESOLVED: main language resources/sentinels incomplete",
        scope: available
            ? "Main catalogs available; actual body pixels still require review. Module-explicit labels/title checked separately."
            : "Body text relying on Bundle.main is not full localized visual proof. Module-explicit labels/title remain separate proof. Never assemble into toolchain/system main bundle."
    )
}

// MARK: - Actual retained capability consumers using the existing stdio fixture

extension SettingsRootNativeHostTests {
    @Test(
        "Actual retained capability consumers stop hidden thread refreshes",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_TEST_SETTINGS_READ_HOSTS"] == "1"))
    func capabilityHiddenThreadAdmissions() async throws {
        try await withCapabilityRoot("hidden-thread-admissions") { fixture, session, probe in
            let initial = try await probe.receipt("attached")
            _ = try await session.reveal(.agentCoreProtocol, segment: 1)
            let skills = try await probe.settled(after: initial.count, session: session, label: "first-skills")
            let retainedAgents = try #require(session.pageContainer?.selectedView)
            let retainedSkills = try #require(session.agentContainer?.selectedView)
            _ = try await session.select(.zotero)
            let zotero = try await probe.settled(after: skills.count, session: session, label: "first-zotero")
            let retainedZotero = try #require(session.pageContainer?.selectedView)
            #expect(probe.controller.capabilities.zoteroConnectionState == .available)

            _ = try await session.select(.document)
            try await capabilityProjectionBoundary(session)
            let before = try await probe.receipt("hidden-before-switch")
            #expect(before.count == zotero.count)
            probe.controller.select(probe.second.id)
            try await RootSession.waitUntil("actual second conversation history read") {
                probe.controller.selectedID == probe.second.id && !probe.controller.isRefreshingHistory
            }
            try await capabilityProjectionBoundary(session)
            let after = try await probe.receipt("hidden-after-switch")
            probe.observations["hidden_new_inventory_rpcs"] = after.count - before.count
            #expect(after.count == before.count)
            #expect(probe.controller.selected?.threadID == probe.second.threadID)
            #expect(retainedAgents.isHidden && retainedZotero.isHidden)
            #expect(retainedSkills.isHiddenOrHasHiddenAncestor)

            _ = try await session.reveal(.agentCoreProtocol, segment: 1)
            let activeSkills = try await probe.settled(after: after.count, session: session, label: "reactivate-skills")
            #expect(session.pageContainer?.selectedView === retainedAgents)
            #expect(session.agentContainer?.selectedView === retainedSkills)
            try probe.requireOneCycle(Array(activeSkills.dropFirst(after.count)))
            _ = try await session.select(.zotero)
            let activeZotero = try await probe.settled(after: activeSkills.count, session: session, label: "reactivate-zotero")
            #expect(session.pageContainer?.selectedView === retainedZotero)
            try probe.requireOneCycle(Array(activeZotero.dropFirst(activeSkills.count)))
            #expect(probe.controller.capabilities.zoteroConnectionState == .available)
            try probe.assertPreservation(fixture)
        }
    }

    @Test(
        "Actual admitted shared inventory survives hiding its Settings consumer",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_TEST_SETTINGS_READ_HOSTS"] == "1"))
    func capabilityAdmittedInventorySurvivesHiding() async throws {
        try await withCapabilityRoot("admitted-inventory-survives-hiding") { fixture, session, probe in
            let initial = try await probe.receipt("attached")
            _ = try await session.reveal(.agentCoreProtocol, segment: 1)
            let ready = try await probe.settled(after: initial.count, session: session, label: "first-skills")
            let connection = try #require(probe.controller.connectionID)
            let runtime = try #require(probe.controller.runtime)
            let capabilities = probe.controller.capabilities
            try Data().write(to: probe.controller.runtimeHome.appendingPathComponent("gate-capability-tools-list"))
            probe.controller.select(probe.second.id)
            let entered = probe.controller.runtimeHome.appendingPathComponent("entered-capability-tools-list")
            try await RootSession.waitUntil("active consumer inventory reaches fixture gate") {
                FileManager.default.fileExists(atPath: entered.path)
            }
            let heldID = try String(contentsOf: entered, encoding: .utf8)
            let held = try await probe.receipt("held-visible")
            #expect(held.count == ready.count + 2)
            #expect(held.last?.method == "mcpServerStatus/list" && held.last?.requestID == heldID)
            #expect(held.last?.threadID == probe.second.threadID)
            #expect(capabilities.isRefreshing && !capabilities.hasTools)

            _ = try await session.select(.document)
            try await capabilityProjectionBoundary(session)
            let hidden = try await probe.receipt("held-hidden")
            #expect(hidden == held)
            #expect(capabilities.isRefreshing && !capabilities.hasTools)
            #expect(probe.controller.connectionID == connection && probe.controller.runtime === runtime)
            let released = try await runtime.request("fixture/releaseCapabilityToolsList")
            let releasedIDs = try #require(released.objectValue?["releasedRequestIds"]?.arrayValue)
            #expect(releasedIDs.compactMap { $0.intValue.map(String.init) } == [heldID])
            let finished = try await probe.settled(after: ready.count, session: session, label: "completed-while-hidden")
            try probe.requireOneCycle(Array(finished.dropFirst(ready.count)))
            #expect(capabilities.tools.contains { $0.name == "scholium" })
            #expect(capabilities.canConfigureTools && capabilities.zoteroConnectionState == .available)
            #expect(probe.controller.connectionID == connection && probe.controller.runtime === runtime)
            #expect(probe.controller.connectionState == .ready)
            #expect(try String(contentsOf: probe.controller.runtimeHome.appendingPathComponent("runtime-launches"), encoding: .utf8) == "1")

            // A second real consumer can borrow the completed shared owner.
            _ = try await session.select(.zotero)
            _ = try await probe.settled(after: finished.count, session: session, label: "new-zotero-consumer")
            #expect(probe.controller.capabilities === capabilities)
            #expect(capabilities.zoteroConnectionState == .available)
            #expect(probe.controller.connectionID == connection)
            try probe.assertPreservation(fixture)
        }
    }
}

@MainActor
private func withCapabilityRoot(
    _ name: String,
    operation: @MainActor (RootFixture, RootSession, CapabilityHostProbe) async throws -> Void
) async throws {
    let fixture = try await RootFixture.make()
    defer { fixture.removeDefaults() }
    let probe = try await CapabilityHostProbe.make(fixture)
    fixture.state.capabilityChatController = probe.controller
    let session = RootSession(fixture: fixture, locale: "en", size: NSSize(width: 920, height: 700))
    try await withTaskCancellationHandler {
        do {
            try await probe.connect(fixture)
            try await session.mount()
            try await operation(fixture, session, probe)
        } catch {
            session.close()
            fixture.state.capabilityChatController = nil
            await probe.close()
            await RootSession.mainQueueTurn()
            try? probe.writeEvidence(name: name, fixture: fixture, error: String(describing: error))
            throw error
        }
        session.close()
        fixture.state.capabilityChatController = nil
        await probe.close()
        await RootSession.mainQueueTurn()
        try probe.writeEvidence(name: name, fixture: fixture, error: nil)
    } onCancel: {
        Task { @MainActor in
            session.close()
            await probe.close()
        }
    }
}

@MainActor
private func capabilityProjectionBoundary(_ session: RootSession) async throws {
    try Task.checkCancellation()
    for _ in 0..<3 { await session.publishAndLayout() }
    try Task.checkCancellation()
}

/// Test-owned fixture receipts, not a second capability state machine. The real
/// consumers admit work to the real controller and its existing stdio runtime.
@MainActor
private final class CapabilityHostProbe {
    struct Request: Codable, Equatable {
        let ordinal: Int
        let requestID: String
        let method: String
        let threadID: String?
    }
    struct Receipt: Codable {
        let label: String
        let requests: [Request]
    }
    let controller: AgentChatController
    let first: AgentChatConversation
    let second: AgentChatConversation
    var observations: [String: Int] = [:]
    private var receipts: [Receipt] = []
    private var preferencesAtReady: Data?
    private var cleanupTask: Task<Void, Never>?
    private var logURL: URL { controller.runtimeHome.appendingPathComponent("capability-requests.jsonl") }

    private init(controller: AgentChatController, first: AgentChatConversation, second: AgentChatConversation) {
        self.controller = controller
        self.first = first
        self.second = second
    }

    static func make(_ fixture: RootFixture) async throws -> CapabilityHostProbe {
        let root = fixture.root.appendingPathComponent("CapabilityChat", isDirectory: true)
        let home = root.appendingPathComponent("Codex", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var first = AgentChatConversation(triptychID: fixture.firstID)
        first.threadID = "settings-capability-A"
        first.title = "Synthetic capability A"
        first.draft = "Unsent A Cafe\u{301} 中文 🧪\r\nexact source\n"
        first.updatedAt = Date(timeIntervalSince1970: 1_700_000_010)
        var second = AgentChatConversation(triptychID: fixture.firstID)
        second.threadID = "settings-capability-B"
        second.title = "Synthetic capability B"
        second.draft = "Unsent B 中文 👩‍🔬\nexact source\r\n"
        second.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try await AgentChatStorage(root: root.appendingPathComponent(fixture.firstID.uuidString)).save([first, second])
        let threads: [String: Any] = Dictionary(
            uniqueKeysWithValues: [first, second].map {
                ($0.threadID!, ["id": $0.threadID!, "turns": []] as [String: Any])
            })
        try JSONSerialization.data(withJSONObject: threads, options: [.sortedKeys])
            .write(to: home.appendingPathComponent("fixture-threads.json"))
        try Data().write(to: home.appendingPathComponent("record-capability-requests"))
        let controller = fixtureChatController(
            triptychID: fixture.firstID, root: root, methodDefaults: fixture.defaults,
            contextAccessPreferences: fixture.preferences.agentContextAccess
        ) { [weak state = fixture.state] request in
            _ = state?.reject("capabilityFixture.unexpectedBridge")
            return try! .init(requestID: request.requestID, result: .object([:]))
        }
        return CapabilityHostProbe(controller: controller, first: first, second: second)
    }

    func connect(_ fixture: RootFixture) async throws {
        try #require(await controller.waitUntilLoaded())
        #expect(controller.selectedID == first.id)
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let executable = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: executable, home: controller.runtimeHome, helper: executable)
        try #require(await controller.waitUntilReady())
        #expect(controller.capabilities.canConfigureTools)
        preferencesAtReady = try preferenceBytes(fixture.defaults.persistentDomain(forName: fixture.suiteName) ?? [:])
    }

    private func records() throws -> [Request] {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return [] }
        let data = try Data(contentsOf: logURL)
        return try data.split(separator: 0x0A).map { try JSONDecoder().decode(Request.self, from: Data($0)) }
    }

    func receipt(_ label: String) async throws -> [Request] {
        let runtime = try #require(controller.runtime)
        let response = try await runtime.request("fixture/capabilityRequestReceipt")
        let count = try #require(response.objectValue?["recordCount"]?.intValue)
        let value = try #require(response.objectValue?["records"])
        let current = try JSONDecoder().decode([Request].self, from: JSONEncoder().encode(value))
        // The fixture response is an immutable transport-prefix receipt. Raw
        // append-only records remain in the isolated home as failure evidence.
        #expect(current.count == count)
        #expect(current.map(\.ordinal) == (0..<count).map { $0 + 1 })
        receipts.append(.init(label: label, requests: current))
        return current
    }

    func settled(after count: Int, session: RootSession, label: String) async throws -> [Request] {
        try await RootSession.waitUntil("actual capability refresh completes: \(label)") {
            guard let current = try? records(), current.count > count,
                current.last?.method == "config/read"
            else { return false }
            return !controller.capabilities.isRefreshing && controller.capabilities.hasTools
                && controller.capabilities.canConfigureTools
        }
        try await capabilityProjectionBoundary(session)
        return try await receipt(label)
    }

    func requireOneCycle(_ requests: [Request]) throws {
        #expect(requests.map(\.method) == ["skills/list", "mcpServerStatus/list", "config/read"])
        #expect(requests.first(where: { $0.method == "mcpServerStatus/list" })?.threadID == second.threadID)
    }

    func assertPreservation(_ fixture: RootFixture) throws {
        let expected = try #require(preferencesAtReady)
        #expect(try preferenceBytes(fixture.defaults.persistentDomain(forName: fixture.suiteName) ?? [:]) == expected)
        #expect(controller.conversations.count == 2)
        for original in [first, second] {
            let current = try #require(controller.conversations.first { $0.id == original.id })
            #expect(Data(current.draft.utf8) == Data(original.draft.utf8))
            #expect(current.messages.isEmpty && current.queuedMessages.isEmpty)
            #expect(current.threadID == original.threadID)
        }
        #expect(fixture.state.unexpected.isEmpty && fixture.styles.unexpected.isEmpty)
        #expect(fixture.model.selectedTriptychID == fixture.firstID)
    }

    func close() async {
        if let cleanupTask {
            await cleanupTask.value
            return
        }
        let task = Task { @MainActor [controller] in await controller.disconnect() }
        cleanupTask = task
        await task.value
    }

    func writeEvidence(name: String, fixture: RootFixture, error: String?) throws {
        struct Evidence: Codable {
            let schema: Int
            let name: String
            let enforcesGate: Bool
            let error: String?
            let observations: [String: Int]
            let receipts: [Receipt]
            let rawRequests: [Request]
            let unexpected: [String]
            let cleanupJoined: Bool
        }
        let value = Evidence(
            schema: 1, name: name, enforcesGate: true, error: error,
            observations: observations, receipts: receipts, rawRequests: try records(),
            unexpected: fixture.state.unexpected + fixture.styles.unexpected,
            cleanupJoined: cleanupTask != nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let output = fixture.root.appendingPathComponent("capability-host-\(name).json")
        try encoder.encode(value).write(to: output, options: .atomic)
        print("SETTINGS_CAPABILITY_HOST evidence=\(output.path) acceptance=true")
    }
}
