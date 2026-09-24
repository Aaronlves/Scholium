import Combine
import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Style store lifecycle", .serialized)
@MainActor
struct CSSSnippetStoreLifecycleTests {
    @Test("A held mutation reply prevents later operations from starting or publishing")
    func mutationRepliesRemainOrdered() async throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let operations = HeldStyleOperations(base: StyleOperations(applicationSupportURL: root.appendingPathComponent("Support")))
        let initial = try await operations.styleSnapshot()
        var profile = try #require(initial.appearanceProfiles.first)
        let store = CSSSnippetStore(operations: operations)
        await store.refresh()
        profile.settings.body.fontSizePoints = 16
        store.updateAppearance(profile)
        await operations.waitUntilUpdateIsHeld()
        store.renameAppearance(profile.id, to: "Newest Name")
        // This main-queue barrier admits already scheduled MainActor jobs
        // without a timing sleep. The held reply remains explicitly controlled.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(operations.mutationStarts == ["update"])
        operations.releaseUpdate()
        let source = root.appendingPathComponent("barrier.css")
        try Data("p { color: #543210; }".utf8).write(to: source)
        // Await a later queued operation to establish all prior publication.
        try await store.importSnippet(from: source)
        #expect(operations.mutationStarts == ["update", "rename"])
        #expect(store.selectedAppearanceProfile?.name == "Newest Name")
        #expect(store.selectedAppearanceProfile?.settings.body.fontSizePoints == 16)
        #expect(store.readCSS.contains("#543210"))
    }

    @Test("Failed appearance reload publishes its scoped repair state and retains the profile")
    func failedReloadExposesRepair() async throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let operations = StyleOperations(applicationSupportURL: root)
        let store = CSSSnippetStore(operations: operations)
        await store.refresh()
        let original = store.appearanceProfiles
        let url = try await operations.appearanceConfigurationURL()
        var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var profiles = try #require(manifest["profiles"] as? [[String: Any]])
        var settings = try #require(profiles[0]["settings"] as? [String: Any])
        settings["lineWidthCharacterUnits"] = 999
        profiles[0]["settings"] = settings
        manifest["profiles"] = profiles
        let invalid = try JSONSerialization.data(withJSONObject: manifest)
        try invalid.write(to: url, options: .atomic)
        var subscription: AnyCancellable?
        defer { subscription?.cancel() }
        await withCheckedContinuation { continuation in
            var resumed = false
            subscription = store.$storeError.compactMap { $0 }.sink { _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
            store.reloadAppearanceConfiguration()
        }
        #expect(!store.canModifyAppearance && store.canRepairAppearance)
        #expect(store.appearanceError != nil)
        #expect(store.appearanceProfiles == original)
        #expect(try Data(contentsOf: url) == invalid)
    }

    private func fixtureRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/style-store-lifecycle-fixtures/\(UUID())", isDirectory: true)
    }
}

/// Withholds one authoritative reply after the real owner has committed it.
/// Every other use case forwards to the same disposable real style owner.
@MainActor
private final class HeldStyleOperations: StyleUseCases {
    let base: StyleOperations
    private(set) var mutationStarts: [String] = []
    private var heldUpdate: CheckedContinuation<Void, Never>?
    private var updateHeldWaiter: CheckedContinuation<Void, Never>?

    init(base: StyleOperations) { self.base = base }

    func waitUntilUpdateIsHeld() async {
        if heldUpdate != nil { return }
        await withCheckedContinuation { updateHeldWaiter = $0 }
    }
    func releaseUpdate() {
        heldUpdate?.resume()
        heldUpdate = nil
    }
    func updateAppearanceProfile(_ profile: DocumentAppearanceProfile) async throws -> StyleSnapshot {
        mutationStarts.append("update")
        let snapshot = try await base.updateAppearanceProfile(profile)
        await withCheckedContinuation {
            heldUpdate = $0
            updateHeldWaiter?.resume()
            updateHeldWaiter = nil
        }
        return snapshot
    }
    func renameAppearanceProfile(_ id: UUID, to name: String) async throws -> StyleSnapshot {
        mutationStarts.append("rename")
        return try await base.renameAppearanceProfile(id, to: name)
    }
    func styleSnapshot() async throws -> StyleSnapshot { try await base.styleSnapshot() }
    func createAppearanceProfile(named name: String) async throws -> StyleSnapshot { try await base.createAppearanceProfile(named: name) }
    func selectAppearanceProfile(_ id: UUID) async throws -> StyleSnapshot { try await base.selectAppearanceProfile(id) }
    func duplicateAppearanceProfile(_ id: UUID) async throws -> StyleSnapshot { try await base.duplicateAppearanceProfile(id) }
    func removeAppearanceProfile(_ id: UUID) async throws -> StyleSnapshot { try await base.removeAppearanceProfile(id) }
    func appearanceConfigurationURL() async throws -> URL { try await base.appearanceConfigurationURL() }
    func reloadAppearanceConfiguration() async throws -> StyleSnapshot { try await base.reloadAppearanceConfiguration() }
    func restoreAppearanceDefaults() async throws -> StyleSnapshot { try await base.restoreAppearanceDefaults() }
    func repairAppearanceProfile(_ profile: DocumentAppearanceProfile) async throws -> StyleSnapshot { try await base.repairAppearanceProfile(profile) }
    func restoreStyleSnippetDefaults() async throws -> StyleSnapshot { try await base.restoreStyleSnippetDefaults() }
    func importStyleSnippet(from sourceURL: URL) async throws -> StyleSnapshot { try await base.importStyleSnippet(from: sourceURL) }
    func refreshStyleSnippets() async throws -> StyleSnapshot { try await base.refreshStyleSnippets() }
    func setStyleSnippetEnabled(_ enabled: Bool, id: UUID) async throws -> StyleSnapshot { try await base.setStyleSnippetEnabled(enabled, id: id) }
    func moveStyleSnippet(_ id: UUID, by offset: Int) async throws -> StyleSnapshot { try await base.moveStyleSnippet(id, by: offset) }
    func renameStyleSnippet(_ id: UUID, to name: String) async throws -> StyleSnapshot { try await base.renameStyleSnippet(id, to: name) }
    func duplicateStyleSnippet(_ id: UUID) async throws -> StyleSnapshot { try await base.duplicateStyleSnippet(id) }
    func reloadStyleSnippet(_ id: UUID) async throws -> StyleSnapshot { try await base.reloadStyleSnippet(id) }
    func removeStyleSnippet(_ id: UUID) async throws -> StyleSnapshot { try await base.removeStyleSnippet(id) }
    func disableAllStyleSnippets() async throws -> StyleSnapshot { try await base.disableAllStyleSnippets() }
    func enterStyleSafeMode(reason: String) async throws -> StyleSnapshot { try await base.enterStyleSafeMode(reason: reason) }
    func managedStyleSnippetURL(_ id: UUID) async throws -> URL? { try await base.managedStyleSnippetURL(id) }
    func managedStylesLocation() async throws -> URL { try await base.managedStylesLocation() }
    func obsidianAppearance(at vaultRootURL: URL) async -> ObsidianAppearanceSnapshot? { await base.obsidianAppearance(at: vaultRootURL) }
}
