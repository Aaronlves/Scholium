import ScholiumContracts
import Foundation
import ScholiumCore

enum WorkspaceVaultPoolMode: Sendable {
    case live(identityRegistry: VaultIdentityRegistry)
    case snapshot
}

/// One process-owned repository/index/native watcher authority for a stable
/// vault identity. The native stream has one consumer here and is fanned out
/// into a distinct bounded stream for each borrowing WorkspaceHandle.
actor PooledWorkspaceVault {
    private struct Subscriber: Sendable {
        let token: UUID
        let continuation: AsyncStream<VaultWatchEvent>.Continuation
    }

    nonisolated let vault: RegisteredVault
    nonisolated let rootURL: URL
    nonisolated let repository: VaultRepository
    nonisolated let index: SQLiteSearchIndex
    nonisolated let recoveredIndexCorruption: Bool

    private let securityScopeURL: URL?
    private let watcher: WorkspaceFileEventWatcher?
    private var watcherTask: Task<Void, Never>?
    private var subscribers: [UUID: Subscriber] = [:]
    private var isShutDown = false

    init(
        vault: RegisteredVault,
        rootURL: URL,
        repository: VaultRepository,
        index: SQLiteSearchIndex,
        recoveredIndexCorruption: Bool,
        securityScopeURL: URL?,
        watcher: WorkspaceFileEventWatcher?
    ) {
        self.vault = vault
        self.rootURL = rootURL
        self.repository = repository
        self.index = index
        self.recoveredIndexCorruption = recoveredIndexCorruption
        self.securityScopeURL = securityScopeURL
        self.watcher = watcher
    }

    func start() async throws {
        guard !isShutDown, watcherTask == nil, let watcher else { return }
        let events = try await watcher.start()
        watcherTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled, let self else { return }
                await self.publish(event)
            }
            guard !Task.isCancelled, let self else { return }
            await self.reportUnexpectedWatcherTermination()
        }
    }

    func events() -> AsyncStream<VaultWatchEvent> {
        let pair = AsyncStream<VaultWatchEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        guard !isShutDown else {
            pair.continuation.finish()
            return pair.stream
        }
        let id = UUID()
        let token = UUID()
        subscribers[id] = Subscriber(token: token, continuation: pair.continuation)
        // A new borrower begins from its own complete snapshot and needs only
        // a full-reconciliation hint, never replay of an incomplete raw batch.
        pair.continuation.yield(.reconciliationRequired(sequence: 0))
        pair.continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeSubscriber(id: id, token: token) }
        }
        return pair.stream
    }

    func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true
        let task = watcherTask
        watcherTask = nil
        task?.cancel()
        if let watcher { await watcher.stop() }
        await task?.value
        let active = subscribers.values
        subscribers.removeAll()
        for subscriber in active { subscriber.continuation.finish() }
        securityScopeURL?.stopAccessingSecurityScopedResource()
    }

    private func publish(_ event: VaultWatchEvent) {
        for subscriber in subscribers.values {
            subscriber.continuation.yield(event)
        }
    }

    private func reportUnexpectedWatcherTermination() {
        guard !isShutDown else { return }
        // The raw watcher stream is intentionally not exposed as a generic
        // error bus. A root-change reconciliation hint lets each borrowing
        // WorkspaceHandle publish its own typed stale derived-state event.
        publish(.reconciliationRequired(sequence: 0, rootChanged: true))
    }

    private func removeSubscriber(id: UUID, token: UUID) {
        guard subscribers[id]?.token == token else { return }
        subscribers[id] = nil
    }

    var subscriberCount: Int { subscribers.count }
    var ownsNativeWatcher: Bool { watcherTask != nil }
}

/// Runtime-owned pool keyed by stable vault UUID and guarded by canonical
/// path equality. Handles for different Triptychs borrow the same authority.
actor WorkspaceVaultPool {
    private struct Opening: Sendable {
        let token: UUID
        let canonicalPath: String
        let task: Task<PooledWorkspaceVault, Error>
    }

    private let applicationSupportURL: URL
    private let mode: WorkspaceVaultPoolMode
    private var vaults: [UUID: PooledWorkspaceVault] = [:]
    private var openings: [UUID: Opening] = [:]
    private var isShutDown = false

    init(applicationSupportURL: URL, mode: WorkspaceVaultPoolMode) {
        self.applicationSupportURL = applicationSupportURL.standardizedFileURL
        self.mode = mode
    }

    func vault(for registeredVault: RegisteredVault) async throws -> PooledWorkspaceVault {
        guard !isShutDown else { throw ScholiumApplicationError.runtimeShutDown }
        let expectedURL = URL(
            fileURLWithPath: registeredVault.canonicalPath,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL
        if let existing = vaults[registeredVault.id] {
            guard existing.rootURL.path == expectedURL.path else {
                throw WorkspaceRegistryError.vaultIdentityMismatch(
                    registeredVault.id,
                    existing.rootURL.path,
                    expectedURL.path
                )
            }
            return existing
        }

        if let opening = openings[registeredVault.id] {
            guard opening.canonicalPath == expectedURL.path else {
                throw WorkspaceRegistryError.vaultIdentityMismatch(
                    registeredVault.id,
                    opening.canonicalPath,
                    expectedURL.path
                )
            }
            return try await opening.task.value
        }

        let token = UUID()
        let task = Task {
            try await Self.makeVault(
                registeredVault,
                expectedURL: expectedURL,
                applicationSupportURL: applicationSupportURL,
                mode: mode
            )
        }
        openings[registeredVault.id] = Opening(
            token: token,
            canonicalPath: expectedURL.path,
            task: task
        )

        do {
            let pooled = try await task.value
            if openings[registeredVault.id]?.token == token {
                openings[registeredVault.id] = nil
            }
            guard !isShutDown else {
                await pooled.shutdown()
                throw ScholiumApplicationError.runtimeShutDown
            }
            vaults[registeredVault.id] = pooled
            return pooled
        } catch {
            if openings[registeredVault.id]?.token == token {
                openings[registeredVault.id] = nil
            }
            throw error
        }
    }

    func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true
        let pending = openings.values.map(\.task)
        openings.removeAll()
        pending.forEach { $0.cancel() }
        for task in pending {
            if let vault = try? await task.value { await vault.shutdown() }
        }
        let active = vaults.values
        vaults.removeAll()
        for vault in active { await vault.shutdown() }
    }

    /// Detaches one pooled authority without stopping it. Existing handles
    /// keep their watcher streams during replacement; a successor can open a
    /// new authority under the same stable ID before the old one is retired.
    func detach(vaultID: UUID) async -> PooledWorkspaceVault? {
        if let opening = openings.removeValue(forKey: vaultID) {
            opening.task.cancel()
            if let opened = try? await opening.task.value { await opened.shutdown() }
        }
        return vaults.removeValue(forKey: vaultID)
    }

    /// Rolls back a failed replacement without leaving two native watchers or
    /// abandoning consumers of the prior pooled authority.
    func restore(_ previous: PooledWorkspaceVault, vaultID: UUID) async {
        if let replacement = vaults.removeValue(forKey: vaultID),
           replacement !== previous {
            await replacement.shutdown()
        }
        vaults[vaultID] = previous
    }

    var runtimeCount: Int { vaults.count }

    func runtime(vaultID: UUID) -> PooledWorkspaceVault? { vaults[vaultID] }

    private nonisolated static func makeVault(
        _ registeredVault: RegisteredVault,
        expectedURL: URL,
        applicationSupportURL: URL,
        mode: WorkspaceVaultPoolMode
    ) async throws -> PooledWorkspaceVault {
        try Task.checkCancellation()
        let identity: VaultIdentity
        let rootURL: URL
        let securityScopeURL: URL?
        switch mode {
        case .snapshot:
            rootURL = expectedURL
            identity = VaultIdentity(
                id: registeredVault.id,
                canonicalPath: expectedURL.path,
                bookmarkData: nil
            )
            securityScopeURL = nil
        case .live(let registry):
            guard let registeredIdentity = await registry.identity(id: registeredVault.id) else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            identity = registeredIdentity
            let resolution = try resolveLiveAccess(
                vault: registeredVault,
                identity: registeredIdentity
            )
            rootURL = resolution.url
            securityScopeURL = resolution.securityScopeURL
        }

        do {
            try Task.checkCancellation()
            let repository = try VaultRepository(
                vaultURL: rootURL,
                identity: identity,
                applicationSupportURL: applicationSupportURL,
                vaultRole: registeredVault.role
            )
            let opened = try SQLiteSearchIndex.openRecovering(
                databaseURL: SQLiteSearchIndex.databaseURL(
                    applicationSupportURL: applicationSupportURL,
                    vaultID: registeredVault.id
                ),
                vaultID: registeredVault.id
            )
            let watcher: WorkspaceFileEventWatcher? = switch mode {
            case .live: WorkspaceFileEventWatcher(rootURL: rootURL)
            case .snapshot: nil
            }
            let pooled = PooledWorkspaceVault(
                vault: registeredVault,
                rootURL: rootURL,
                repository: repository,
                index: opened.index,
                recoveredIndexCorruption: opened.recoveredCorruption,
                securityScopeURL: securityScopeURL,
                watcher: watcher
            )
            try await pooled.start()
            return pooled
        } catch {
            securityScopeURL?.stopAccessingSecurityScopedResource()
            throw error
        }
    }

    private nonisolated static func resolveLiveAccess(
        vault: RegisteredVault,
        identity: VaultIdentity
    ) throws -> (url: URL, securityScopeURL: URL?) {
        let canonical = URL(fileURLWithPath: vault.canonicalPath, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        guard identity.id == vault.id, identity.canonicalPath == canonical.path else {
            throw WorkspaceRegistryError.vaultIdentityMismatch(
                vault.id,
                identity.canonicalPath,
                canonical.path
            )
        }
        guard let bookmark = identity.bookmarkData else {
            return (canonical, nil)
        }
        var stale = false
        let resolved: URL
        do {
            resolved = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            throw WorkspaceRegistryError.vaultAccessUnavailable(vault.canonicalPath)
        }
        let resolvedCanonical = resolved.resolvingSymlinksInPath().standardizedFileURL
        guard !stale,
              resolvedCanonical.path == canonical.path,
              resolved.startAccessingSecurityScopedResource() else {
            throw WorkspaceRegistryError.vaultAccessUnavailable(vault.canonicalPath)
        }
        return (resolvedCanonical, resolved)
    }
}
