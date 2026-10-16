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

    @Test("Opt-in selected-native-layout and fixture request attribution")
    func measureSelectedNativeLayout() async throws {
        guard ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_SETTINGS"] == "1" else { return }
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
                        providerIDs: nil,
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
            providerObservation: "unobserved DI-only baseline; no provider API or eager-root proxy",
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

    static func make() async throws -> RootFixture {
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
    let assignments: [TriptychAssignment]
    let root: URL
    var counts: [String: Int] = [:]
    var providerRequests: [UUID] = []
    var snapshotRequestIDs: [String] = []
    var portableLookupPaths: [String] = []
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
                    return snapshot(active: id)
                },
                configureWorkspace: { [self] _, _, _, _, _, _ in throw reject("workspace.configure") },
                loadSettingsRecovery: { [self] _ in throw reject("workspace.recovery") },
                resetTriptychSettings: { [self] _, _ in throw reject("workspace.reset") },
                portableContainerURL: { [self] url in
                    count("workspace.portableContainerURL")
                    portableLookupPaths.append(url.path)
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
                updates: Empty<UUID, Never>().eraseToAnyPublisher(),
                load: { [self] _ in
                    count("history.load")
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
                deleteArchivedChats: { [self] _ in throw reject("storage.deleteArchivedChats") })
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
            ScholiumSettingsView(preferences: fixture.preferences)
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
            requestCounts: fixture.state.counts, providerRequestCount: nil,
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
        #expect(!window.isVisible)
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
