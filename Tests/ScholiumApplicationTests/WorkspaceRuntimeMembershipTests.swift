import ScholiumContracts
import Foundation
import ScholiumApplication
import Testing

@Suite("Workspace runtime membership and presentation persistence")
struct WorkspaceRuntimeMembershipTests {
    @Test("Live runtime owns saved-search and window-session persistence")
    func livePresentationPersistence() async throws {
        let fixture = try await RuntimeMembershipFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.liveRuntime()

        #expect(try await runtime.savedSearches().isEmpty)
        #expect(try await runtime.windowSession(id: fixture.session.id) == nil)

        try await runtime.saveSavedSearches(fixture.savedSearches)
        try await runtime.saveWindowSession(fixture.session)
        #expect(try await runtime.savedSearches() == fixture.savedSearches)
        #expect(try await runtime.windowSession(id: fixture.session.id) == fixture.session)
        await runtime.shutdown()

        let reopened = fixture.liveRuntime()
        #expect(try await reopened.savedSearches() == fixture.savedSearches)
        #expect(try await reopened.windowSession(id: fixture.session.id) == fixture.session)
        #expect(FileManager.default.fileExists(
            atPath: fixture.registryStorageURL
                .appendingPathComponent("saved-searches.json")
                .path
        ))
        #expect(FileManager.default.fileExists(
            atPath: fixture.applicationSupportURL
                .appendingPathComponent("Window Sessions", isDirectory: true)
                .appendingPathComponent(fixture.session.id.uuidString + ".json")
                .path
        ))
        await reopened.shutdown()
    }

    @Test("Live and snapshot runtimes resolve only their owned vault membership")
    func vaultResolution() async throws {
        let fixture = try await RuntimeMembershipFixture.make()
        defer { fixture.remove() }
        let analyses = try #require(fixture.assignment.vault(for: .paperAnalysis))

        let live = fixture.liveRuntime()
        let liveByID = try await live.resolveVault(analyses.id.uuidString)
        let liveByName = try await live.resolveVault("analyses")
        let liveByPath = try await live.resolveVault(fixture.analysesURL.path)
        expectSameVault(liveByID, as: analyses)
        expectSameVault(liveByName, as: analyses)
        expectSameVault(liveByPath, as: analyses)
        await live.shutdown()

        let snapshot = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )
        let snapshotByID = try await snapshot.resolveVault(analyses.id.uuidString)
        let snapshotByName = try await snapshot.resolveVault("ANALYSES")
        let snapshotByPath = try await snapshot.resolveVault(fixture.analysesURL.path)
        expectSameVault(snapshotByID, as: analyses)
        expectSameVault(snapshotByName, as: analyses)
        expectSameVault(snapshotByPath, as: analyses)
        await snapshot.shutdown()
    }

    @Test("Live runtime exposes stable identities and reconciliation is idempotent")
    func identityReconciliation() async throws {
        let fixture = try await RuntimeMembershipFixture.make()
        defer { fixture.remove() }
        let stableAnalyses = try #require(fixture.assignment.vault(for: .paperAnalysis))
        let stableTopics = try #require(fixture.assignment.vault(for: .topicKnowledge))
        let stableWorks = try #require(fixture.assignment.vault(for: .output))
        let runtime = fixture.liveRuntime()
        let analysesIdentity = try #require(try await runtime.vaultIdentity(id: stableAnalyses.id))
        #expect(analysesIdentity.id == stableAnalyses.id)
        #expect(analysesIdentity.canonicalPath == stableAnalyses.canonicalPath)
        let repaired = try await runtime.reconcileWorkspaceIdentity(id: fixture.assignment.id)
        #expect(repaired.vault(for: .paperAnalysis)?.id == stableAnalyses.id)
        #expect(repaired.vault(for: .topicKnowledge)?.id == stableTopics.id)
        #expect(repaired.vault(for: .output)?.id == stableWorks.id)
        let available = try await runtime.availableWorkspaces()
        #expect(available.map(\.id) == [repaired.id])
        #expect(try #require(available.first).vaultIDs == repaired.vaultIDs)

        let registryURL = fixture.registryStorageURL.appendingPathComponent(
            "workspace-registry-v2.json"
        )
        let bytesBeforeRepeatedReconciliation = try Data(contentsOf: registryURL)
        let repeated = try await runtime.reconcileWorkspaceIdentity(id: fixture.assignment.id)
        #expect(repeated.id == repaired.id)
        #expect(repeated.vaultIDs == repaired.vaultIDs)
        #expect(try Data(contentsOf: registryURL) == bytesBeforeRepeatedReconciliation)
        await runtime.shutdown()
    }

    @Test("Snapshot runtime freezes membership and rejects registry or presentation mutations")
    func snapshotIsReadOnly() async throws {
        let fixture = try await RuntimeMembershipFixture.make()
        defer { fixture.remove() }
        let seedingRuntime = fixture.liveRuntime()
        try await seedingRuntime.saveSavedSearches(fixture.savedSearches)
        try await seedingRuntime.saveWindowSession(fixture.session)
        await seedingRuntime.shutdown()

        let snapshot = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )
        let laterAssignment = try await fixture.addSecondAssignment()

        let captured = try await snapshot.availableWorkspaces()
        #expect(captured.map(\.id) == [fixture.assignment.id])
        #expect(try #require(captured.first).vaultIDs == fixture.assignment.vaultIDs)
        #expect(try await snapshot.registeredVaults().count == 3)
        #expect(try await snapshot.savedSearches() == fixture.savedSearches)
        #expect(try await snapshot.windowSession(id: fixture.session.id) == fixture.session)
        #expect(try await snapshot.vaultIdentity(
            id: try #require(fixture.assignment.vault(for: .paperAnalysis)).id
        ) == nil)

        let laterVault = try #require(laterAssignment.vault(for: .paperAnalysis))
        do {
            _ = try await snapshot.resolveVault(laterVault.id.uuidString)
            Issue.record("The fixed snapshot resolved a vault registered after capture.")
        } catch let error as WorkspaceRegistryError {
            guard case .vaultNotFound(let selector) = error else {
                Issue.record("Unexpected fixed-membership error: \(error)")
                await snapshot.shutdown()
                return
            }
            #expect(selector == laterVault.id.uuidString)
        }

        await expectRuntimeConfigurationUnavailable("save Saved Searches") {
            try await snapshot.saveSavedSearches([])
        }
        await expectRuntimeConfigurationUnavailable("save a window session") {
            try await snapshot.saveWindowSession(WindowSessionSnapshot())
        }
        await expectRuntimeConfigurationUnavailable("reconcile workspace identity") {
            _ = try await snapshot.reconcileWorkspaceIdentity(id: fixture.assignment.id)
        }
        await expectRuntimeConfigurationUnavailable("reidentify a workspace") {
            _ = try await snapshot.reidentifyWorkspace(
                id: fixture.assignment.id,
                as: UUID()
            )
        }
        await expectRuntimeConfigurationUnavailable("register a vault") {
            _ = try await snapshot.registerVault(
                path: fixture.analysesURL,
                name: "Changed Analyses",
                role: .sourceCorpus
            )
        }
        await expectRuntimeConfigurationUnavailable("configure a Triptych") {
            _ = try await snapshot.configureTriptych(
                paperAnalysisURL: fixture.analysesURL,
                topicKnowledgeURL: fixture.topicsURL,
                outputURL: fixture.worksURL,
                portableContainerURL: fixture.rootURL,
                triptychID: fixture.assignment.id,
                triptychName: "Changed"
            )
        }
        await expectRuntimeConfigurationUnavailable("change the default Triptych") {
            try await snapshot.setDefaultWorkspace(id: fixture.assignment.id)
        }

        #expect(try await snapshot.savedSearches() == fixture.savedSearches)
        #expect(try await snapshot.windowSession(id: fixture.session.id) == fixture.session)
        let observer = fixture.liveRuntime()
        let persistedLaterAssignment = try await observer.availableWorkspaces().first {
            $0.id == laterAssignment.id
        }
        #expect(persistedLaterAssignment?.id == laterAssignment.id)
        #expect(persistedLaterAssignment?.vaultIDs == laterAssignment.vaultIDs)
        await observer.shutdown()
        await snapshot.shutdown()
    }
}

private struct RuntimeMembershipFixture: Sendable {
    let rootURL: URL
    let applicationSupportURL: URL
    let registryStorageURL: URL
    let analysesURL: URL
    let topicsURL: URL
    let worksURL: URL
    let assignment: TriptychAssignment
    let savedSearches: [SavedSearch]
    let session: WindowSessionSnapshot

    static func make() async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumRuntimeMembershipTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let registryStorage = root.appendingPathComponent("Registry", isDirectory: true)
        let analyses = root.appendingPathComponent("Analyses", isDirectory: true)
        let topics = root.appendingPathComponent("Topics", isDirectory: true)
        let works = root.appendingPathComponent("Works", isDirectory: true)
        for directory in [support, registryStorage, analyses, topics, works] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: support,
            workspaceRegistryStorageURL: registryStorage
        )))
        let handle = try await runtime.configureTriptych(
            paperAnalysisURL: analyses,
            topicKnowledgeURL: topics,
            outputURL: works,
            portableContainerURL: root,
            triptychName: "Membership Fixture"
        )
        let assignment = handle.assignment
        let analysesIdentity = try #require(assignment.vault(for: .paperAnalysis))
        await runtime.shutdown()
        let savedSearches = [
            SavedSearch(
                id: UUID(),
                name: "Open questions",
                state: SearchWorkspaceState(
                    query: "agency",
                    scope: .triptych,
                    selectedRoles: [.sourceCorpus, .topicKnowledge],
                    selectedResultID: "result-1"
                ),
                createdAt: Date(timeIntervalSince1970: 1_234)
            ),
            SavedSearch(
                id: UUID(),
                name: "Current source",
                state: SearchWorkspaceState(query: "freedom", scope: .thisNote),
                createdAt: Date(timeIntervalSince1970: 5_678)
            ),
        ]
        let session = WindowSessionSnapshot(
            id: UUID(),
            triptychID: assignment.id,
            vaultID: analysesIdentity.id,
            selectedDocument: VaultQualifiedNoteID(
                vaultID: analysesIdentity.id,
                relativePath: "Agency.md"
            ),
            documentModes: ["Agency.md": "source"],
            scrollPositions: ["Agency.md": 0.25],
            inspectorMode: "outgoing",
            inspectorVisible: true,
            contentDestination: .document,
            searchState: SearchWorkspaceState(query: "reasons", scope: .currentVault),
            documentTextScale: 1.25
        )
        return Self(
            rootURL: root,
            applicationSupportURL: support,
            registryStorageURL: registryStorage,
            analysesURL: analyses,
            topicsURL: topics,
            worksURL: works,
            assignment: assignment,
            savedSearches: savedSearches,
            session: session
        )
    }

    func liveRuntime() -> WorkspaceRuntime {
        WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: applicationSupportURL,
            workspaceRegistryStorageURL: registryStorageURL
        )))
    }

    func addSecondAssignment() async throws -> TriptychAssignment {
        let container = rootURL.appendingPathComponent("Later", isDirectory: true)
        let analyses = container.appendingPathComponent("Analyses", isDirectory: true)
        let topics = container.appendingPathComponent("Topics", isDirectory: true)
        let works = container.appendingPathComponent("Works", isDirectory: true)
        for directory in [analyses, topics, works] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let runtime = liveRuntime()
        let handle = try await runtime.configureTriptych(
            paperAnalysisURL: analyses,
            topicKnowledgeURL: topics,
            outputURL: works,
            portableContainerURL: container,
            triptychName: "Later Membership"
        )
        await runtime.shutdown()
        return handle.assignment
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private func expectRuntimeConfigurationUnavailable(
    _ operationName: String,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("A fixed snapshot was allowed to \(operationName).")
    } catch let error as ScholiumApplicationError {
        guard case .runtimeConfigurationUnavailable = error else {
            Issue.record("Unexpected error while trying to \(operationName): \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected error while trying to \(operationName): \(error)")
    }
}

private func expectSameVault(_ actual: RegisteredVault, as expected: RegisteredVault) {
    #expect(actual.id == expected.id)
    #expect(actual.name == expected.name)
    #expect(actual.role == expected.role)
    #expect(actual.canonicalPath == expected.canonicalPath)
}

private extension TriptychAssignment {
    var vaultIDs: [WorkspaceVaultSlot: UUID] {
        Dictionary(
            uniqueKeysWithValues: WorkspaceVaultSlot.allCases.compactMap { slot in
                vault(for: slot).map { (slot, $0.id) }
            }
        )
    }
}
