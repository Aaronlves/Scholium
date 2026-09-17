import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Settings recovery service")
struct SettingsRecoveryTests {
    @Test("Damaged settings remain readable for recovery after reopening without blocking Notes")
    func damagedSettingsCanBeRecoveredAfterReopening() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let settingsURL = fixture.rootURL.appendingPathComponent(".scholium/settings.json")
        let manifestURL = fixture.rootURL.appendingPathComponent(".scholium/manifest.json")
        let originalManifest = try Data(contentsOf: manifestURL)
        let damagedBytes = Data("{ damaged settings".utf8)
        try damagedBytes.write(to: settingsURL, options: .atomic)
        let runtime = makeRuntime(fixture)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)

        let document = try await handle.documents.load(fixture.analysisNoteID)
        #expect(document.rawContent.contains("Freedom enables action."))
        let observed = try await handle.research.settingsRecoverySnapshot()
        #expect(observed.loadState == .corrupted)
        #expect(observed.revision != nil)
        let outcome = try await handle.research.resetSettingsToDefaultsOutcome(
            expectedRevision: observed.revision
        )
        let preservedURL = try #require(outcome.committedValue.preservedSettingsURL)
        #expect(try Data(contentsOf: preservedURL) == damagedBytes)
        #expect(outcome.committedValue.snapshot.settings == TriptychSettings())
        #expect(try await handle.research.settings() == outcome.committedValue.snapshot)
        #expect(try Data(contentsOf: manifestURL) == originalManifest)
        await runtime.shutdown()
    }

    @Test("Recovery returns proven settings and preserved bytes when derived refresh fails")
    func committedRecoveryRetainsDerivedFailureWarning() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = makeRuntime(fixture)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let settingsURL = fixture.rootURL.appendingPathComponent(".scholium/settings.json")
        let originalSettings = try Data(contentsOf: settingsURL)
        let observed = try await handle.research.settingsRecoverySnapshot()
        let services = await handle.services
        let settlementURL = services.settlementStore.storageURL
        let retainedSettlementURL = settlementURL.appendingPathExtension("retained")
        try FileManager.default.moveItem(at: settlementURL, to: retainedSettlementURL)
        try Data("Unavailable derived research state".utf8).write(to: settlementURL)

        let outcome = try await handle.research.resetSettingsToDefaultsOutcome(
            expectedRevision: observed.revision
        )
        #expect(outcome.derivedRefreshWarning?.isEmpty == false)
        #expect(outcome.committedValue.snapshot.settings == TriptychSettings())
        let preservedURL = try #require(outcome.committedValue.preservedSettingsURL)
        #expect(try Data(contentsOf: preservedURL) == originalSettings)
        #expect(try await handle.research.settings() == outcome.committedValue.snapshot)
        try FileManager.default.removeItem(at: settlementURL)
        try FileManager.default.moveItem(at: retainedSettlementURL, to: settlementURL)
        _ = try await handle.discovery.refresh()
        await runtime.shutdown()
    }

    @Test("Captured recovery service cannot mutate after its workspace is shut down")
    func recoveryServiceRetainsWorkspaceLifetime() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = makeRuntime(fixture)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let research = handle.research
        let observed = try await research.settingsRecoverySnapshot()
        let settingsURL = fixture.rootURL.appendingPathComponent(".scholium/settings.json")
        let originalBytes = try Data(contentsOf: settingsURL)
        await runtime.shutdown()

        await #expect(throws: ScholiumApplicationError.self) {
            _ = try await research.resetSettingsToDefaults(expectedRevision: observed.revision)
        }
        #expect(try Data(contentsOf: settingsURL) == originalBytes)
    }

    private func makeRuntime(_ fixture: ApplicationFixture) -> WorkspaceRuntime {
        WorkspaceRuntime(
            configuration: .snapshot(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL,
                    assignments: [fixture.assignment]
                )))
    }
}
