import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Pooled vault root authority forwarding")
struct WorkspaceVaultPoolRootAuthorityTests {
    enum RootFailure: CaseIterable, Sendable { case descriptorReplacement, catalogRetirement }

    @Test("Ordinary hints forward discovered root retirement to every subscriber", arguments: RootFailure.allCases)
    func sourcePreparationRootFailureIsTyped(_ failure: RootFailure) async throws {
        try await withFixture { fixture in
            let first = await fixture.pooled.events()
            let second = await fixture.pooled.events()
            var firstIterator = first.makeAsyncIterator()
            var secondIterator = second.makeAsyncIterator()
            #expect(try #require(await firstIterator.next()).rootChanged == false)
            #expect(try #require(await secondIterator.next()).rootChanged == false)

            switch failure {
            case .descriptorReplacement:
                try FileManager.default.moveItem(at: fixture.vaultURL, to: fixture.retiredURL)
                try FileManager.default.createDirectory(at: fixture.vaultURL, withIntermediateDirectories: false)
                try Fixture.foreignSource.write(to: fixture.noteURL)
            case .catalogRetirement:
                await fixture.catalog.invalidateRootAuthority()
            }
            await fixture.pooled.receiveForTesting(
                .init(
                    added: [], modified: [Fixture.path], deleted: [], sequence: 73,
                    requiresFullRescan: false, rootChanged: false))
            for event in [try #require(await firstIterator.next()), try #require(await secondIterator.next())] {
                #expect(event.sequence == 73)
                #expect(event.rootChanged)
                #expect(event.requiresFullRescan)
                #expect(event.added.isEmpty)
                #expect(event.modified.isEmpty)
                #expect(event.deleted.isEmpty)
            }
            #expect(await fixture.pooled.hasInvalidRootAuthority)
            await #expect(throws: VaultSourceCatalogError.rootUnavailable) { try await fixture.catalog.snapshot() }

            let later = await fixture.pooled.events()
            var laterIterator = later.makeAsyncIterator()
            #expect(try #require(await laterIterator.next()).rootChanged)
            await fixture.pooled.receiveForTesting(.reconciliationRequired(sequence: 74))
            await fixture.pooled.shutdown()
            #expect(await firstIterator.next() == nil)
            #expect(await secondIterator.next() == nil)
            #expect(await laterIterator.next() == nil)
            switch failure {
            case .descriptorReplacement:
                #expect(try Data(contentsOf: fixture.noteURL) == Fixture.foreignSource)
                #expect(try Data(contentsOf: fixture.retiredURL.appendingPathComponent(Fixture.path)) == Fixture.source)
            case .catalogRetirement:
                #expect(try Data(contentsOf: fixture.noteURL) == Fixture.source)
            }
        }
    }

    @Test("A malformed Note requests reconciliation without retiring its authorized root")
    func sourceFailureRemainsReconciliation() async throws {
        try await withFixture { fixture in
            let stream = await fixture.pooled.events()
            var iterator = stream.makeAsyncIterator()
            _ = try #require(await iterator.next())
            let unreadable = Data([0xFF, 0xFE, 0xFF])
            try unreadable.write(to: fixture.noteURL)
            await fixture.pooled.receiveForTesting(
                .init(
                    added: [], modified: [Fixture.path], deleted: [], sequence: 88,
                    requiresFullRescan: false, rootChanged: false))
            let event = try #require(await iterator.next())
            #expect(event.sequence == 88)
            #expect(event.requiresFullRescan)
            #expect(!event.rootChanged)
            #expect(await fixture.pooled.hasInvalidRootAuthority == false)
            #expect(try Data(contentsOf: fixture.noteURL) == unreadable)
            await fixture.pooled.shutdown()
            #expect(await iterator.next() == nil)
        }
    }

    enum StoppedDelivery: CaseIterable, Sendable { case cancellation, shutdown }

    @Test("Cancelled and shut-down delivery cannot publish fallback reconciliation", arguments: StoppedDelivery.allCases)
    func stoppedDeliveryPublishesNothing(_ stopped: StoppedDelivery) async throws {
        try await withFixture { fixture in
            let stream = await fixture.pooled.events()
            var iterator = stream.makeAsyncIterator()
            _ = try #require(await iterator.next())
            switch stopped {
            case .cancellation:
                let delivery = Task {
                    withUnsafeCurrentTask { $0?.cancel() }
                    await fixture.pooled.receiveForTesting(.reconciliationRequired(sequence: 91))
                }
                await delivery.value
                #expect(await fixture.pooled.hasInvalidRootAuthority == false)
                await fixture.pooled.shutdown()
            case .shutdown:
                await fixture.pooled.shutdown()
                await fixture.pooled.receiveForTesting(.reconciliationRequired(sequence: 91))
            }
            #expect(await iterator.next() == nil)
            #expect(try Data(contentsOf: fixture.noteURL) == Fixture.source)
        }
    }

    private func withFixture(_ operation: (Fixture) async throws -> Void) async throws {
        let fixture = try await Fixture()
        do {
            try await operation(fixture)
        } catch {
            await fixture.shutdownAndRemove()
            throw error
        }
        await fixture.shutdownAndRemove()
    }

    private struct Fixture: Sendable {
        static let path = "Note.md"
        static let source = Data("\u{FEFF}# Authorized source\r\nExact bytes, unchanged.\r\n".utf8)
        static let foreignSource = Data("# A different filesystem root\n".utf8)
        let root: URL
        let vaultURL: URL
        let retiredURL: URL
        let catalog: VaultSourceCatalog
        let pooled: PooledWorkspaceVault
        var noteURL: URL { vaultURL.appendingPathComponent(Self.path) }

        init() async throws {
            root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent(".build/pooled-root-authority/\(UUID().uuidString)")
            vaultURL = root.appendingPathComponent("Vault")
            retiredURL = root.appendingPathComponent("Retired vault")
            let support = root.appendingPathComponent("Application Support")
            let topics = root.appendingPathComponent("Topics")
            let works = root.appendingPathComponent("Works")
            let runtime = WorkspaceRuntime(
                configuration: .live(
                    .init(
                        applicationSupportURL: support,
                        workspaceRegistryStorageURL: root.appendingPathComponent("Registry"))))
            do {
                for directory in [vaultURL, topics, works] {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                }
                try Self.source.write(to: vaultURL.appendingPathComponent(Self.path))
                let handle = try await runtime.configureTriptych(
                    paperAnalysisURL: vaultURL, topicKnowledgeURL: topics, outputURL: works,
                    portableContainerURL: root, triptychName: "Pooled root fixture")
                let vault = try #require(handle.assignment.vault(for: .paperAnalysis))
                let services = await handle.services
                let repository = try #require(services.repositories[vault.id])
                catalog = VaultSourceCatalog(repository: repository)
                pooled = PooledWorkspaceVault(
                    vault: vault, rootURL: vaultURL, repository: repository, sourceCatalog: catalog,
                    cacheStorageLease: nil, securityScopeURL: nil, watcher: nil)
                await runtime.shutdown()
            } catch {
                await runtime.shutdown()
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }

        func shutdownAndRemove() async {
            await pooled.shutdown()
            try? FileManager.default.removeItem(at: root)
        }
    }
}
