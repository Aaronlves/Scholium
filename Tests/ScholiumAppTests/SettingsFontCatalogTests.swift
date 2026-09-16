import Foundation
import Testing

@testable import ScholiumApp

@Suite("Settings font catalogue", .timeLimit(.minutes(1)))
@MainActor
struct SettingsFontCatalogTests {
    @Test("Concurrent readers share one query and repeated access reuses its result")
    func coalescesQueries() async {
        let source = ControlledFontLoader()
        let catalog = makeCatalog(source)
        let first = Task { await catalog.loadIfNeeded() }
        let second = Task { await catalog.loadIfNeeded() }
        await source.waitForRequests(1)
        #expect(catalog.families.isEmpty)
        await source.complete(1, with: ["Alegreya", "Courier"])
        await first.value
        await second.value
        await catalog.loadIfNeeded()

        #expect(catalog.families == ["Alegreya", "Courier"])
        #expect(await source.requestCount == 1)
    }

    @Test("A registry change rejects an in-flight result and keeps the last usable list during refresh")
    func invalidationRejectsStaleResult() async {
        let source = ControlledFontLoader()
        let catalog = makeCatalog(source)
        let initial = Task { await catalog.loadIfNeeded() }
        await source.waitForRequests(1)
        await source.complete(1, with: ["Original"])
        await initial.value

        catalog.invalidate()
        await source.waitForRequests(2)
        catalog.invalidate()
        catalog.invalidate()
        let refreshed = Task { await catalog.loadIfNeeded() }
        await source.complete(2, with: ["Obsolete"])
        await source.waitForRequests(3)
        #expect(catalog.families == ["Original"])
        await source.complete(3, with: ["Current"])
        await refreshed.value

        #expect(catalog.families == ["Current"])
        #expect(await source.requestCount == 3)
    }

    @Test("Preset and saved fonts remain selectable before loading and after a font disappears")
    func retainsSelectedFontWithoutDuplicatePresetTags() async {
        let source = ControlledFontLoader()
        let catalog = makeCatalog(source)
        #expect(catalog.families(retaining: "Saved Font") == ["Saved Font"])
        #expect(catalog.families(retaining: "Preset", excluding: ["Preset"]).isEmpty)
        #expect(catalog.families(retaining: nil).isEmpty)
        #expect(catalog.families(retaining: "").isEmpty)

        let loaded = Task { await catalog.loadIfNeeded() }
        await source.waitForRequests(1)
        await source.complete(1, with: ["Preset", "Installed"])
        await loaded.value
        #expect(catalog.families(retaining: "Installed") == ["Preset", "Installed"])
        #expect(catalog.families(retaining: "Removed", excluding: ["Preset"]) == ["Installed", "Removed"])
    }

    private func makeCatalog(_ source: ControlledFontLoader) -> ScholiumSettingsFontCatalog {
        ScholiumSettingsFontCatalog(
            loader: { await source.load() },
            localNotifications: NotificationCenter(),
            distributedNotifications: NotificationCenter())
    }
}

private actor ControlledFontLoader {
    private(set) var requestCount = 0
    private var pending: [Int: CheckedContinuation<[String], Never>] = [:]
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func load() async -> [String] {
        requestCount += 1
        let request = requestCount
        let ready = waiters.filter { $0.count <= requestCount }
        waiters.removeAll { $0.count <= requestCount }
        ready.forEach { $0.continuation.resume() }
        return await withCheckedContinuation { pending[request] = $0 }
    }

    func waitForRequests(_ count: Int) async {
        if requestCount >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func complete(_ request: Int, with families: [String]) {
        guard let continuation = pending.removeValue(forKey: request) else {
            preconditionFailure("Font request was not started or was already completed")
        }
        continuation.resume(returning: families)
    }
}
