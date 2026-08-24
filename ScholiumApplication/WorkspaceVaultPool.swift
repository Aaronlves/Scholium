import ScholiumContracts
import Foundation
import ScholiumCore

enum WorkspaceVaultPoolMode: Sendable {
    case live
    case snapshot
}

/// One process-owned repository/native watcher authority for a stable
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
    nonisolated let sourceCatalog: VaultSourceCatalog

    private let securityScopeURL: URL?
    private let watcher: WorkspaceFileEventWatcher?
    private var watcherTask: Task<Void, Never>?
    private var watcherTaskToken: UUID?
    private var subscribers: [UUID: Subscriber] = [:]
    private var rootAuthorityIsInvalid = false
    private var isShutDown = false

    init(
        vault: RegisteredVault,
        rootURL: URL,
        repository: VaultRepository,
        sourceCatalog: VaultSourceCatalog,
        securityScopeURL: URL?,
        watcher: WorkspaceFileEventWatcher?
    ) {
        self.vault = vault
        self.rootURL = rootURL
        self.repository = repository
        self.sourceCatalog = sourceCatalog
        self.securityScopeURL = securityScopeURL
        self.watcher = watcher
    }

    func start() async throws {
        guard !isShutDown,
              !rootAuthorityIsInvalid,
              watcherTask == nil,
              let watcher else { return }
        let events = try await watcher.start()
        let token = UUID()
        watcherTaskToken = token
        watcherTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled, let self else { return }
                await self.receive(event)
            }
            guard !Task.isCancelled, let self else { return }
            await self.watcherDidTerminate(token: token)
        }
    }

    func events() -> AsyncStream<VaultWatchEvent> {
        let pair = WorkspaceWatchEventBuffer.makeStream()
        guard !isShutDown else {
            pair.continuation.finish()
            return pair.stream
        }
        let id = UUID()
        let token = UUID()
        subscribers[id] = Subscriber(token: token, continuation: pair.continuation)
        // A new borrower begins from its own complete snapshot and needs only
        // a full-reconciliation hint, never replay of an incomplete raw batch.
        WorkspaceWatchEventBuffer.yield(
            .reconciliationRequired(
                sequence: 0,
                rootChanged: rootAuthorityIsInvalid
            ),
            to: pair.continuation
        )
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
        watcherTaskToken = nil
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
            WorkspaceWatchEventBuffer.yield(
                event,
                to: subscriber.continuation
            )
        }
    }

    private func receive(_ event: VaultWatchEvent) async {
        if event.rootChanged {
            await invalidateRootAuthority(sequence: event.sequence)
            return
        }
        guard !rootAuthorityIsInvalid else { return }
        do {
            try await sourceCatalog.apply(event)
            publish(event)
        } catch {
            await sourceCatalog.requireFullReconcile()
            publish(.reconciliationRequired(
                sequence: event.sequence,
                rootChanged: event.rootChanged
            ))
        }
    }

    private func watcherDidTerminate(token: UUID) async {
        guard watcherTaskToken == token else { return }
        watcherTaskToken = nil
        watcherTask = nil
        guard !isShutDown, !rootAuthorityIsInvalid else { return }
        // The raw watcher stream is intentionally not exposed as a generic
        // error bus. A root-change reconciliation hint lets each borrowing
        // WorkspaceHandle publish its own typed stale derived-state event.
        await invalidateRootAuthority(sequence: 0)
    }

    private func invalidateRootAuthority(sequence: UInt64) async {
        guard !isShutDown, !rootAuthorityIsInvalid else { return }
        rootAuthorityIsInvalid = true
        await sourceCatalog.requireFullReconcile()
        publish(.reconciliationRequired(
            sequence: sequence,
            rootChanged: true
        ))
        if let watcher { await watcher.stop() }
    }

    private func removeSubscriber(id: UUID, token: UUID) {
        guard subscribers[id]?.token == token else { return }
        subscribers[id] = nil
    }

    var subscriberCount: Int { subscribers.count }
    var ownsNativeWatcher: Bool { watcherTask != nil }
    var hasInvalidRootAuthority: Bool {
        get async {
            if rootAuthorityIsInvalid { return true }
            return await repository.rootAuthorityIsInvalid
        }
    }

    // Internal deterministic seam for root-discontinuity integration tests.
    func receiveForTesting(_ event: VaultWatchEvent) async {
        await receive(event)
    }
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

    func invalidRootVaultIDs() async -> Set<UUID> {
        var invalid: Set<UUID> = []
        for (vaultID, vault) in vaults where await vault.hasInvalidRootAuthority {
            invalid.insert(vaultID)
        }
        return invalid
    }

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
        case .live:
            identity = VaultIdentity(
                id: registeredVault.id,
                canonicalPath: registeredVault.canonicalPath,
                bookmarkData: registeredVault.bookmarkData
            )
            let resolution = try resolveLiveAccess(
                vault: registeredVault,
                identity: identity
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
            let watcher: WorkspaceFileEventWatcher? = switch mode {
            case .live: WorkspaceFileEventWatcher(rootURL: rootURL)
            case .snapshot: nil
            }
            let pooled = PooledWorkspaceVault(
                vault: registeredVault,
                rootURL: rootURL,
                repository: repository,
                sourceCatalog: VaultSourceCatalog(
                    repository: repository,
                    vaultRole: registeredVault.role
                ),
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
