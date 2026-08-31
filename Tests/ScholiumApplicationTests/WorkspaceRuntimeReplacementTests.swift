import ScholiumContracts
import Foundation
import Testing
@testable import ScholiumApplication

@Suite("Workspace runtime replacement", .serialized)
struct WorkspaceRuntimeReplacementTests {
    @Test("Vault registration and Triptych configuration replace every borrower")
    func membershipMutationsHandOffEveryPeer() async throws {
        let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
        defer { fixture.remove() }
        let runtime = liveRuntime(for: fixture)
        let initial = try await runtime.openWorkspace(id: fixture.assignment.id)
        var registrationFirst = (await initial.events.events()).makeAsyncIterator()
        var registrationSecond = (await initial.events.events()).makeAsyncIterator()
        _ = try #require(await registrationFirst.next())
        _ = try #require(await registrationSecond.next())

        let updatedVault = try await runtime.registerVault(
            path: fixture.analysesURL,
            name: "Renamed Analyses",
            role: .sourceCorpus
        )
        let registeredReplacement = try await runtime.openWorkspace(id: fixture.assignment.id)
        #expect(registeredReplacement !== initial)
        #expect(updatedVault.name == "Renamed Analyses")
        #expect(updatedVault.role == .sourceCorpus)
        for event in [
            try #require(await registrationFirst.next()),
            try #require(await registrationSecond.next()),
        ] {
            try await expectReplacement(
                event,
                previous: initial,
                replacement: registeredReplacement
            )
            #expect(event.snapshot.vault(id: updatedVault.id)?.vault.role == .sourceCorpus)
        }
        #expect(await initial.events.subscriberCount == 0)
        #expect(await initial.ownedBackgroundTaskCount == 0)

        var configurationFirst = (await registeredReplacement.events.events())
            .makeAsyncIterator()
        var configurationSecond = (await registeredReplacement.events.events())
            .makeAsyncIterator()
        _ = try #require(await configurationFirst.next())
        _ = try #require(await configurationSecond.next())
        let configuredReplacement = try await runtime.configureTriptych(
            paperAnalysisURL: fixture.analysesURL,
            topicKnowledgeURL: fixture.topicsURL,
            outputURL: fixture.worksURL,
            portableContainerURL: fixture.rootURL,
            triptychID: fixture.assignment.id,
            triptychName: "Reconfigured Triptych"
        )
        #expect(configuredReplacement !== registeredReplacement)
        #expect(configuredReplacement.assignment.triptych.name == "Reconfigured Triptych")
        for event in [
            try #require(await configurationFirst.next()),
            try #require(await configurationSecond.next()),
        ] {
            try await expectReplacement(
                event,
                previous: registeredReplacement,
                replacement: configuredReplacement
            )
        }
        #expect(await registeredReplacement.events.subscriberCount == 0)
        #expect(await registeredReplacement.ownedBackgroundTaskCount == 0)
        #expect(
            try await runtime.openWorkspace(id: fixture.assignment.id)
                === configuredReplacement
        )

        await runtime.shutdown()
    }

    @Test("Identity reconciliation preserves an already-correct active runtime")
    func reconciliationDoesNotStrandCorrectPeers() async throws {
        let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
        defer { fixture.remove() }
        let runtime = liveRuntime(for: fixture)
        let active = try await runtime.openWorkspace(id: fixture.assignment.id)
        var first = (await active.events.events()).makeAsyncIterator()
        var second = (await active.events.events()).makeAsyncIterator()
        _ = try #require(await first.next())
        _ = try #require(await second.next())

        let repaired = try await runtime.reconcileWorkspaceIdentity(id: fixture.assignment.id)
        #expect(repaired.id == fixture.assignment.id)
        for slot in WorkspaceVaultSlot.allCases {
            #expect(repaired.vault(for: slot)?.id == fixture.assignment.vault(for: slot)?.id)
        }
        #expect(try await runtime.openWorkspace(id: repaired.id) === active)

        _ = try await active.discovery.refresh()
        #expect((try #require(await first.next())).generation == 1)
        #expect((try #require(await second.next())).generation == 1)
        #expect(await active.events.subscriberCount == 2)
        #expect(await active.ownedBackgroundTaskCount > 0)
        await runtime.shutdown()
    }

    @Test("Reidentification hands existing peers to the stable Triptych identity")
    func reidentificationHandsOffEveryPeer() async throws {
        let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
        defer { fixture.remove() }
        let runtime = liveRuntime(for: fixture)
        let previous = try await runtime.openWorkspace(id: fixture.assignment.id)
        var first = (await previous.events.events()).makeAsyncIterator()
        var second = (await previous.events.events()).makeAsyncIterator()
        _ = try #require(await first.next())
        _ = try #require(await second.next())

        let manifestURL = fixture.rootURL
            .appendingPathComponent(".scholium", isDirectory: true)
            .appendingPathComponent("manifest.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let existing = try decoder.decode(
            TriptychManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let stableID = UUID()
        let restored = TriptychManifest(
            id: stableID,
            vaultIDs: existing.vaultIDs,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(restored).write(to: manifestURL, options: .atomic)
        try rewritePortableOwnerIdentities(
            controlURL: manifestURL.deletingLastPathComponent(),
            stableID: stableID
        )

        let assignment = try await runtime.reidentifyWorkspace(
            id: fixture.assignment.id,
            as: stableID
        )
        let replacement = try await runtime.openWorkspace(id: stableID)
        #expect(assignment.id == stableID)
        #expect(replacement.id == stableID)
        #expect(replacement !== previous)
        for event in [
            try #require(await first.next()),
            try #require(await second.next()),
        ] {
            try await expectReplacement(
                event,
                previous: previous,
                replacement: replacement
            )
        }
        #expect(await previous.events.subscriberCount == 0)
        #expect(await previous.ownedBackgroundTaskCount == 0)
        #expect(try await runtime.openWorkspace(id: stableID) === replacement)
        await runtime.shutdown()
    }

    @Test("A partial portable identity change fails before registry or peer replacement")
    func partialReidentificationFailsClosed() async throws {
        let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
        defer { fixture.remove() }
        let runtime = liveRuntime(for: fixture)
        let previous = try await runtime.openWorkspace(id: fixture.assignment.id)
        var events = (await previous.events.events()).makeAsyncIterator()
        _ = try #require(await events.next())

        let manifestURL = fixture.rootURL
            .appendingPathComponent(".scholium", isDirectory: true)
            .appendingPathComponent("manifest.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let existing = try decoder.decode(
            TriptychManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let stableID = UUID()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(TriptychManifest(
            id: stableID,
            vaultIDs: existing.vaultIDs,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )).write(to: manifestURL, options: .atomic)

        do {
            _ = try await runtime.reidentifyWorkspace(
                id: fixture.assignment.id,
                as: stableID
            )
            Issue.record("A partial portable identity change was accepted.")
        } catch {
            // The exact owner mismatch is the expected fail-closed outcome.
        }
        let assignments = try await runtime.availableWorkspaces()
        #expect(assignments.contains { $0.id == fixture.assignment.id })
        #expect(!assignments.contains { $0.id == stableID })
        #expect(try await runtime.openWorkspace(id: fixture.assignment.id) === previous)
        #expect(await previous.events.subscriberCount == 1)
        await runtime.shutdown()
    }

    private func liveRuntime(for fixture: ApplicationFixture) -> WorkspaceRuntime {
        WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )))
    }

    private func expectReplacement(
        _ event: WorkspaceEvent,
        previous: WorkspaceHandle,
        replacement: WorkspaceHandle
    ) async throws {
        guard case .runtimeReloaded(let reload) = event else {
            Issue.record("An existing peer did not receive runtimeReloaded.")
            return
        }
        #expect(reload.runtimeIdentity == replacement.runtimeIdentity)
        #expect(reload.runtimeIdentity != previous.runtimeIdentity)
        #expect(reload.snapshot.triptych.id == replacement.id)
        #expect(reload.snapshot.generatedAt == (try await replacement.snapshot()).generatedAt)
    }

    private func rewritePortableOwnerIdentities(
        controlURL: URL,
        stableID: UUID
    ) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let citationURL = controlURL.appendingPathComponent(
            "citation-method-v1.json"
        )
        let citation = try decoder.decode(
            ResearchCitationMethodDocument.self,
            from: Data(contentsOf: citationURL)
        )
        try encoder.encode(ResearchCitationMethodDocument(
            triptychID: stableID,
            activeCitationStyle: citation.activeCitationStyle
        )).write(to: citationURL, options: .atomic)
    }
}
