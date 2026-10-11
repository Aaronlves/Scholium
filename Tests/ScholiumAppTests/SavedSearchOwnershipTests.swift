import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Saved Search collection ownership", .serialized)
@MainActor
struct SavedSearchOwnershipTests {
    @Test("Successive edits from one window survive persisted date precision")
    func successiveWindowMutationsUsePersistedPrecision() async throws {
        try await withFixture(seed: []) { fixture in
            let window = fixture.makeWindow()
            await load(window.controller)
            window.controller.criteria = .init(query: "first", scope: .triptych)
            window.controller.saveCurrent(named: "First")
            await window.controller.waitForPendingWorkForTesting()
            let first = try #require(window.controller.savedSearches.first)

            window.controller.criteria = .init(query: "second", scope: .currentVault)
            window.controller.saveCurrent(named: "Second")
            await window.controller.waitForPendingWorkForTesting()
            let second = try #require(window.controller.savedSearches.first { $0.id != first.id })
            window.controller.rename(first.id, to: "Renamed first")
            await window.controller.waitForPendingWorkForTesting()
            window.controller.move(second.id, by: 1)
            await window.controller.waitForPendingWorkForTesting()
            #expect(window.controller.savedSearches.map(\.id) == [first.id, second.id])
            #expect(window.controller.savedSearches.first?.name == "Renamed first")
            #expect(try await fixture.runtime.savedSearches().map(\.id) == [first.id, second.id])

            window.controller.delete(first.id)
            await window.controller.waitForPendingWorkForTesting()
            #expect(window.controller.savedSearches.map(\.id) == [second.id])
            #expect(try await fixture.runtime.savedSearches().map(\.id) == [second.id])
            #expect(window.probe.saveFailures.isEmpty)
        }
    }

    @Test("A stale window cannot erase a sibling's committed Saved Search")
    func sequentialWindowsPreserveCommittedAppends() async throws {
        let original = savedSearch("Original", query: "original")
        try await withFixture(seed: [original]) { fixture in
            let first = fixture.makeWindow()
            let second = fixture.makeWindow()
            await load(first.controller, second.controller)
            #expect(first.controller.savedSearches == [original])
            #expect(second.controller.savedSearches == [original])

            first.controller.criteria = .init(query: "title:committed", scope: .triptych)
            first.controller.saveCurrent(named: "Committed by first window")
            await first.controller.waitForPendingWorkForTesting()
            let committed = try #require(first.controller.savedSearches.first { $0.id != original.id })
            let firstPersisted = try await fixture.runtime.savedSearches()
            #expect(firstPersisted.map(\.id) == [committed.id, original.id])
            let persistedCommit = try #require(firstPersisted.first { $0.id == committed.id })
            #expect(persistedCommit.name == committed.name)
            #expect(persistedCommit.definition == committed.definition)
            #expect(first.probe.saveFailures.isEmpty)
            // The second window still holds the snapshot from before this commit.
            #expect(second.controller.savedSearches == [original])

            let draft = SearchWorkspaceState(query: "title:\"原文 😀\" OR reason", scope: .currentVault)
            second.controller.criteria = draft
            second.controller.saveCurrent(named: "Second window draft")
            await second.controller.waitForPendingWorkForTesting()
            let persisted = try await fixture.runtime.savedSearches()
            #expect(persisted == firstPersisted)
            #expect(second.controller.savedSearches == firstPersisted)
            #expect(!persisted.contains { $0.name == "Second window draft" })
            #expect(second.probe.saveFailures.count == 1)
            #expect(second.controller.savedSearchLoadFailure == nil)
            #expect(second.controller.criteria == draft)

            second.controller.saveCurrent(named: "Second window draft")
            await second.controller.waitForPendingWorkForTesting()
            let retried = try await fixture.runtime.savedSearches()
            let savedDraft = try #require(retried.first)
            #expect(savedDraft.name == "Second window draft")
            #expect(savedDraft.definition == .init(query: draft.query, presentationScope: draft.scope))
            #expect(Array(retried.dropFirst()) == firstPersisted)
            #expect(second.controller.savedSearches.map(\.id) == retried.map(\.id))
            #expect(second.probe.saveFailures.count == 1)
            #expect(second.controller.criteria == draft)
        }
    }

    @Test("A stale window cannot resurrect a Saved Search deleted by another window")
    func staleWindowCannotResurrectDeletedSearch() async throws {
        let deleted = savedSearch("Deleted by first window", query: "deleted")
        try await withFixture(seed: [deleted]) { fixture in
            let first = fixture.makeWindow()
            let second = fixture.makeWindow()
            await load(first.controller, second.controller)
            #expect(second.controller.savedSearches == [deleted])

            first.controller.delete(deleted.id)
            await first.controller.waitForPendingWorkForTesting()
            #expect(try await fixture.runtime.savedSearches().isEmpty)
            #expect(first.probe.saveFailures.isEmpty)
            #expect(second.controller.savedSearches == [deleted])

            let draft = SearchWorkspaceState(query: "author:Teroni OR reason", scope: .triptych)
            second.controller.criteria = draft
            second.controller.saveCurrent(named: "Second window draft")
            await second.controller.waitForPendingWorkForTesting()
            let persisted = try await fixture.runtime.savedSearches()
            #expect(persisted.isEmpty)
            #expect(second.controller.savedSearches.isEmpty)
            #expect(second.probe.saveFailures.count == 1)
            #expect(second.controller.savedSearchLoadFailure == nil)
            #expect(second.controller.criteria == draft)

            second.controller.saveCurrent(named: "Second window draft")
            await second.controller.waitForPendingWorkForTesting()
            let retried = try await fixture.runtime.savedSearches()
            #expect(retried.count == 1)
            let savedDraft = try #require(retried.first)
            #expect(savedDraft.name == "Second window draft")
            #expect(savedDraft.definition == .init(query: draft.query, presentationScope: draft.scope))
            #expect(!retried.contains { $0.id == deleted.id })
            #expect(second.controller.savedSearches.map(\.id) == retried.map(\.id))
            #expect(second.probe.saveFailures.count == 1)
            #expect(second.controller.criteria == draft)
        }
    }

    @Test("Newly damaged Saved Search bytes survive a rejected save until explicit recovery")
    func newlyDamagedBytesRequireExplicitRecovery() async throws {
        let original = savedSearch("Original", query: "original")
        try await withFixture(seed: [original]) { fixture in
            let window = fixture.makeWindow()
            await load(window.controller)
            #expect(window.controller.savedSearches == [original])
            let draft = SearchWorkspaceState(query: "title:\"保留 😀\" OR reason", scope: .currentVault)
            window.controller.criteria = draft
            let damagedBytes = Data([0x00, 0xff, 0x7b, 0x0a, 0x22])
            try damagedBytes.write(to: fixture.savedSearchFile, options: .atomic)

            window.controller.saveCurrent(named: "Retained draft")
            await window.controller.waitForPendingWorkForTesting()
            #expect(try Data(contentsOf: fixture.savedSearchFile) == damagedBytes)
            #expect(window.controller.savedSearches == [original])
            #expect(!window.probe.saveFailures.isEmpty)
            // The existing recovery action is offered through this state.
            #expect(window.controller.savedSearchLoadFailure != nil)
            #expect(window.controller.criteria == draft)
            #expect(window.probe.preservedFiles.isEmpty)

            await window.controller.recoverSavedSearches()
            let preservedFile = try #require(window.probe.preservedFiles.first)
            #expect(try Data(contentsOf: preservedFile) == damagedBytes)
            #expect(!FileManager.default.fileExists(atPath: fixture.savedSearchFile.path))
            #expect(window.controller.savedSearches.isEmpty)
            #expect(window.controller.savedSearchLoadFailure == nil)
            #expect(window.controller.criteria == draft)
            #expect(try await fixture.runtime.savedSearches().isEmpty)

            window.controller.saveCurrent(named: "Retained draft")
            await window.controller.waitForPendingWorkForTesting()
            let retried = try await fixture.runtime.savedSearches()
            #expect(retried.count == 1)
            #expect(retried.first?.definition == .init(query: draft.query, presentationScope: draft.scope))
            #expect(window.probe.saveFailures.count == 1)
            #expect(window.controller.savedSearchLoadFailure == nil)
            #expect(window.controller.criteria == draft)
            #expect(try Data(contentsOf: preservedFile) == damagedBytes)
        }
    }

    private func savedSearch(_ name: String, query: String) -> SavedSearch {
        SavedSearch(
            name: name,
            definition: .init(query: query, presentationScope: .triptych),
            createdAt: Date(timeIntervalSince1970: 10))
    }

    private func load(_ controllers: WindowSearchController...) async {
        for controller in controllers { controller.loadSavedSearches() }
        for controller in controllers { await controller.waitForPendingWorkForTesting() }
    }

    private func withFixture(
        seed: [SavedSearch], _ body: (SavedSearchFixture) async throws -> Void
    ) async throws {
        let fixture = try SavedSearchFixture.make(seed: seed)
        do {
            try await body(fixture)
            await fixture.finish()
        } catch {
            await fixture.finish()
            throw error
        }
    }
}

@MainActor
private final class SavedSearchFixture {
    final class Probe {
        var saveFailures: [String] = []
        var loadFailures: [String] = []
        var preservedFiles: [URL] = []
    }

    struct Window {
        let controller: WindowSearchController
        let probe: Probe
    }

    let root: URL
    let savedSearchFile: URL
    let runtime: WorkspaceRuntime
    private let defaults: UserDefaults
    private let defaultsSuiteName: String
    private var controllers: [WindowSearchController] = []

    static func make(seed: [SavedSearch]) throws -> SavedSearchFixture {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/saved-search-ownership/\(UUID())", isDirectory: true)
        let registry = root.appendingPathComponent("Registry", isDirectory: true)
        let suiteName = "ScholiumSavedSearchOwnershipTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        do {
            try FileManager.default.createDirectory(at: registry, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(seed).write(to: registry.appendingPathComponent("saved-searches.json"), options: .atomic)
            return SavedSearchFixture(root: root, registry: registry, defaults: defaults, suiteName: suiteName)
        } catch {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    private init(root: URL, registry: URL, defaults: UserDefaults, suiteName: String) {
        self.root = root
        self.defaults = defaults
        defaultsSuiteName = suiteName
        savedSearchFile = registry.appendingPathComponent("saved-searches.json")
        runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: root.appendingPathComponent("Support", isDirectory: true),
                    workspaceRegistryStorageURL: registry)))
    }

    func makeWindow() -> Window {
        let probe = Probe()
        let runtime = runtime
        let discovery = DiscoveryController(shellState: WindowShellState(userDefaults: defaults))
        let controller = WindowSearchController(
            discoveryController: discovery,
            dependencies: .init(
                loadSavedSearches: { try await runtime.savedSearches() },
                saveSavedSearches: { searches, expected in
                    try await runtime.saveSavedSearches(searches, replacing: expected)
                },
                recoverSavedSearches: {
                    let preserved = try await runtime.preserveUnreadableSavedSearchesAndReset()
                    if let preserved { probe.preservedFiles.append(preserved) }
                    return preserved
                },
                executionContext: { _ in
                    .init(workspaceIsAvailable: false, currentNoteSnapshot: nil, currentVaultID: nil)
                },
                resultEvidence: { _, _ in .init(freshness: nil, fingerprint: nil) },
                open: { _, _, _ in false },
                hasCurrentNote: { false },
                reportInformation: { _ in },
                reportLoadFailure: { probe.loadFailures.append($0) },
                reportSaveFailure: { probe.saveFailures.append($0) },
                setAvailabilityStatus: { _ in },
                reportCatalogFailure: { _ in }))
        controllers.append(controller)
        return .init(controller: controller, probe: probe)
    }

    func finish() async {
        for controller in controllers { await controller.waitForPendingWorkForTesting() }
        controllers.removeAll()
        await runtime.shutdown()
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: root)
    }
}
