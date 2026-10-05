import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Bootstrap saved-configuration routing", .serialized)
@MainActor
struct BootstrapRoutingTests {
    @Test("An empty registration legitimately opens first-configuration setup")
    func emptyRegistrationRequiresSetup() async throws {
        let fixture = BootstrapRoutingFixture()
        defer { fixture.remove() }

        try await fixture.withStore { (store: WorkspaceStore) async throws in
            let model = ScholiumBootstrapModel(
                workspaceStore: store,
                route: BootstrapWindowRoute(purpose: .firstConfiguration)
            )

            await model.refresh()

            #expect(model.registeredTriptychs.isEmpty)
            #expect(model.workspaceAssignment == nil)
            #expect(!model.isReadyToOpenWorkspace)
            #expect(model.launchFailureMessage == nil)
            #expect(model.requiresSetup)
            #expect(store.workspaceSnapshots.isEmpty)
            #expect(store.workspaceActivations.isEmpty)
        }
    }

    @Test("New Triptych keeps setup available when another Triptych is already saved")
    func newTriptychRequiresSetupWithExistingRegistration() async throws {
        let fixture = BootstrapRoutingFixture()
        defer { fixture.remove() }
        let saved = try await fixture.seedTriptych(named: "Existing Triptych")
        let originalRegistry = try Data(contentsOf: fixture.registryURL)

        try await fixture.withStore { (store: WorkspaceStore) async throws in
            let model = ScholiumBootstrapModel(
                workspaceStore: store,
                route: BootstrapWindowRoute(purpose: .newTriptych)
            )

            await model.refresh()

            #expect(model.registeredTriptychs.map(\.id) == [saved.id])
            #expect(model.isCreatingNewTriptych)
            #expect(model.workspaceAssignment == nil)
            #expect(!model.isReadyToOpenWorkspace)
            #expect(model.launchFailureMessage == nil)
            #expect(model.requiresSetup)
            #expect(try Data(contentsOf: fixture.registryURL) == originalRegistry)
        }
    }

    @Test("A specifically missing registration retains its bounded setup recovery")
    func missingRegistrationRequiresTargetedSetup() async throws {
        let fixture = BootstrapRoutingFixture()
        defer { fixture.remove() }
        let saved = try await fixture.seedTriptych(named: "Existing Triptych")
        let originalRegistry = try Data(contentsOf: fixture.registryURL)
        let missingID = UUID()

        try await fixture.withStore { (store: WorkspaceStore) async throws in
            let model = ScholiumBootstrapModel(
                workspaceStore: store,
                route: BootstrapWindowRoute(
                    purpose: .missingRegistration,
                    targetTriptychID: missingID
                )
            )

            await model.refresh()

            #expect(model.targetTriptychID == missingID)
            #expect(model.registeredTriptychs.map(\.id) == [saved.id])
            #expect(model.workspaceAssignment == nil)
            #expect(!model.isReadyToOpenWorkspace)
            #expect(model.recoveryMessage != nil)
            #expect(model.launchFailureMessage == nil)
            #expect(model.requiresSetup)
            #expect(try Data(contentsOf: fixture.registryURL) == originalRegistry)
        }
    }

    @Test("A saved Triptych with a missing folder routes without opening a workspace runtime")
    func unavailableFolderDoesNotBecomeMissingRegistration() async throws {
        let fixture = BootstrapRoutingFixture()
        defer { fixture.remove() }
        let saved = try await fixture.seedTriptych(named: "Existing Triptych")
        let originalRegistry = try Data(contentsOf: fixture.registryURL)
        let analyses = try #require(saved.vault(for: .paperAnalysis))
        try FileManager.default.removeItem(atPath: analyses.canonicalPath)

        try await fixture.withStore { (store: WorkspaceStore) async throws in
            let model = ScholiumBootstrapModel(
                workspaceStore: store,
                route: BootstrapWindowRoute(purpose: .firstConfiguration)
            )

            await model.refresh()

            #expect(model.workspaceAssignment == saved)
            #expect(model.isReadyToOpenWorkspace)
            #expect(model.launchFailureMessage == nil)
            #expect(!model.requiresSetup)
            #expect(store.workspaceSnapshots.isEmpty)
            #expect(store.workspaceActivations.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: analyses.canonicalPath))
            #expect(try Data(contentsOf: fixture.registryURL) == originalRegistry)
        }
    }

    @Test("Registry damage after startup stays a launch failure until a successful refresh")
    func registryFailurePreservesBytesAndRetriesSavedAssignment() async throws {
        let fixture = BootstrapRoutingFixture()
        defer { fixture.remove() }
        let saved = try await fixture.seedTriptych(named: "Existing Triptych")
        let originalRegistry = try Data(contentsOf: fixture.registryURL)
        let damagedRegistry = Data("damaged disposable registry".utf8)

        try await fixture.withStore { (store: WorkspaceStore) async throws in
            let model = ScholiumBootstrapModel(
                workspaceStore: store,
                route: BootstrapWindowRoute(purpose: .firstConfiguration)
            )
            await model.refresh()
            #expect(model.workspaceAssignment == saved)

            try damagedRegistry.write(to: fixture.registryURL, options: .atomic)
            await model.refresh()

            #expect(model.workspaceAssignment == nil)
            #expect(!model.isReadyToOpenWorkspace)
            #expect(model.launchFailureMessage != nil)
            #expect(!model.requiresSetup)
            #expect(try Data(contentsOf: fixture.registryURL) == damagedRegistry)
            #expect(store.workspaceSnapshots.isEmpty)
            #expect(store.workspaceActivations.isEmpty)

            try originalRegistry.write(to: fixture.registryURL, options: .atomic)
            await model.refresh()

            #expect(model.workspaceAssignment == saved)
            #expect(model.isReadyToOpenWorkspace)
            #expect(model.launchFailureMessage == nil)
            #expect(!model.requiresSetup)
            #expect(try Data(contentsOf: fixture.registryURL) == originalRegistry)
        }
    }

    @Test("Saved default selection is retained when name sorting puts another Triptych first")
    func savedDefaultIsIndependentOfRegistrationNameSort() async throws {
        let fixture = BootstrapRoutingFixture()
        defer { fixture.remove() }
        let savedDefault = try await fixture.seedTriptych(named: "Zeta")
        let other = try await fixture.seedTriptych(named: "Alpha")

        try await fixture.withStore { (store: WorkspaceStore) async throws in
            let model = ScholiumBootstrapModel(
                workspaceStore: store,
                route: BootstrapWindowRoute(purpose: .firstConfiguration)
            )

            await model.refresh()

            #expect(model.registeredTriptychs.map(\.id) == [other.id, savedDefault.id])
            #expect(model.workspaceAssignment == savedDefault)
            #expect(model.isReadyToOpenWorkspace)
            #expect(model.launchFailureMessage == nil)
            #expect(!model.requiresSetup)
            #expect(store.workspaceSnapshots.isEmpty)
            #expect(store.workspaceActivations.isEmpty)
        }
    }
}

@MainActor
private struct BootstrapRoutingFixture {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(".build/bootstrap-routing-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)

    var supportURL: URL {
        root.appendingPathComponent("ApplicationSupport", isDirectory: true)
    }

    var registryURL: URL {
        supportURL.appendingPathComponent("Workspace/workspace-registration-v3.json")
    }

    func withStore<Result>(
        _ operation: @MainActor (WorkspaceStore) async throws -> Result
    ) async throws -> Result {
        let store = try WorkspaceStore(applicationSupportURL: supportURL)
        do {
            let result = try await operation(store)
            await store.shutdownApplicationRuntime()
            return result
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
    }

    func seedTriptych(named name: String) async throws -> TriptychAssignment {
        let parent = root.appendingPathComponent(name, isDirectory: true)
        let folders = ["Analyses", "Topics", "Works"].map {
            parent.appendingPathComponent($0, isDirectory: true)
        }
        for folder in folders {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return try await withStore { store in
            let capabilities = try await store.configureTriptychCapabilities(
                paperAnalysisURL: folders[0],
                topicKnowledgeURL: folders[1],
                outputURL: folders[2],
                portableContainerURL: parent,
                triptychName: name
            )
            return try #require(
                try await store.registeredTriptychs().first { $0.id == capabilities.id }
            )
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
