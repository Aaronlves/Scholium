import Foundation
import ScholiumContracts
import Testing
import os

@testable import ScholiumCore

@Suite("Disposable derived-state storage lifecycle")
struct DerivedStateStorageTests {
    @Test("Shared live connections prevent recovery and retirement until explicit close")
    func sharedConnectionsOwnTheirFiles() async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        let first = try fixture.index()
        let second = try fixture.index()
        let old = fixture.indexDirectory.appendingPathComponent("search-v9.sqlite")
        try Data("retired generated database".utf8).write(to: old)
        let registry = WorkspaceRegistry(storageURL: fixture.registry)
        #expect(try await registry.maintainDerivedState(applicationSupportURL: fixture.support).busyDirectories == 1)
        #expect(FileManager.default.fileExists(atPath: old.path))
        await first.shutdown()
        await #expect(throws: SearchIndexError.self) { try await first.generation() }
        #expect(try await registry.maintainDerivedState(applicationSupportURL: fixture.support).busyDirectories == 1)
        await second.shutdown()
        #expect(!FileManager.default.fileExists(atPath: fixture.database.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: fixture.database.path + "-shm"))
        let cleaned = try await registry.maintainDerivedState(applicationSupportURL: fixture.support)
        #expect(cleaned.removedFiles >= 2)
        #expect(!FileManager.default.fileExists(atPath: fixture.database.path))
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fixture.indexDirectory.appendingPathComponent(".derived-state.lock").path))
    }

    @Test(
        "Future Search policy is nonrecoverable and cannot be orphan-collected",
        arguments: [
            "schema_version", "query_contract_version", "tokenizer_policy_version", "ranking_policy_version",
        ])
    func futureSearchPolicyIsPreserved(_ column: String) async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        await index.shutdown()
        let database = try SearchSQLiteDatabase(path: fixture.database.path)
        try database.execute("UPDATE search_index_state SET \(column) = \(column) + 1;")
        database.close()
        let before = try Data(contentsOf: fixture.database)
        let wal = URL(fileURLWithPath: fixture.database.path + "-wal")
        let shm = URL(fileURLWithPath: fixture.database.path + "-shm")
        let beforeWAL = try Data(contentsOf: wal)
        #expect(!beforeWAL.isEmpty)
        #expect(FileManager.default.fileExists(atPath: shm.path))
        await #expect(throws: DerivedStateStorageError.futurePolicy) {
            try await TriptychSearchIndex.openRecovering(applicationSupportURL: fixture.support, triptychID: fixture.triptychID)
        }
        #expect(try Data(contentsOf: fixture.database) == before)
        #expect(try Data(contentsOf: wal) == beforeWAL)
        #expect(FileManager.default.fileExists(atPath: shm.path))
        let summary = try await WorkspaceRegistry(storageURL: fixture.registry)
            .maintainDerivedState(applicationSupportURL: fixture.support)
        #expect(summary.preservedFiles >= 1)
        #expect(try Data(contentsOf: fixture.database) == before)
        #expect(try Data(contentsOf: wal) == beforeWAL)
        #expect(FileManager.default.fileExists(atPath: shm.path))
    }

    @Test("Clean future or unknown policies remain durable-byte unchanged without creating sidecars", arguments: [false, true])
    func cleanUnrecognizedPolicyPreservesBytes(future: Bool) async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        await index.shutdown()
        let writer = try SearchSQLiteDatabase(path: fixture.database.path)
        try writer.execute(future ? "UPDATE search_index_state SET schema_version = schema_version + 1;" : "DROP TABLE search_index_state;")
        try writer.admitCheckpointOnClose()
        writer.close()
        #expect(!FileManager.default.fileExists(atPath: fixture.database.path + "-wal"))
        let before = try Data(contentsOf: fixture.database)
        await #expect(throws: future ? DerivedStateStorageError.futurePolicy : .unrecognizedPolicy) {
            try await TriptychSearchIndex.openRecovering(applicationSupportURL: fixture.support, triptychID: fixture.triptychID)
        }
        _ = try await WorkspaceRegistry(storageURL: fixture.registry).maintainDerivedState(applicationSupportURL: fixture.support)
        #expect(try Data(contentsOf: fixture.database) == before)
        #expect(!FileManager.default.fileExists(atPath: fixture.database.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: fixture.database.path + "-shm"))
    }

    @Test("Unknown database policy and future filenames remain byte unchanged")
    func unknownFilesAreNotRetired() async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.indexDirectory, withIntermediateDirectories: true)
        let database = try SearchSQLiteDatabase(path: fixture.database.path)
        try database.execute("PRAGMA journal_mode=WAL;")
        try database.execute("CREATE TABLE future_owner(value TEXT);")
        database.close()
        let before = try Data(contentsOf: fixture.database)
        let wal = URL(fileURLWithPath: fixture.database.path + "-wal")
        let shm = URL(fileURLWithPath: fixture.database.path + "-shm")
        let beforeWAL = try Data(contentsOf: wal)
        #expect(!beforeWAL.isEmpty)
        #expect(FileManager.default.fileExists(atPath: shm.path))
        let future = fixture.indexDirectory.appendingPathComponent("search-v11.sqlite")
        let sentinel = Data("future and unrelated bytes".utf8)
        try sentinel.write(to: future)
        await #expect(throws: DerivedStateStorageError.unrecognizedPolicy) {
            try await TriptychSearchIndex.openRecovering(applicationSupportURL: fixture.support, triptychID: fixture.triptychID)
        }
        let summary = try await WorkspaceRegistry(storageURL: fixture.registry)
            .maintainDerivedState(applicationSupportURL: fixture.support)
        #expect(summary.preservedFiles >= 1)
        #expect(try Data(contentsOf: fixture.database) == before)
        #expect(try Data(contentsOf: future) == sentinel)
        #expect(try Data(contentsOf: wal) == beforeWAL)
        #expect(FileManager.default.fileExists(atPath: shm.path))
    }

    enum WrappedPolicy: String, CaseIterable, Sendable { case future, unknown }
    enum CleanupBoundary: String, CaseIterable, Sendable { case startup, maintenance }
    enum UncertainCohort: String, CaseIterable, Sendable {
        case originalMainWithWrappedSidecars
        case wrappedMainWithOriginalSidecars
        case originalSidecarsWithoutMain
        case originalCohortWithWrappedMain
        case mixedNestedWrappers
    }

    @Test(
        "Wrapped current databases preserve future and unknown policy at both cleanup boundaries",
        arguments: WrappedPolicy.allCases, CleanupBoundary.allCases)
    func wrappedPolicyPreservation(policy: WrappedPolicy, boundary: CleanupBoundary) async throws {
        for nested in [false, true] {
            let fixture = try StorageFixture()
            defer { fixture.remove() }
            let initial = try fixture.index()
            await initial.shutdown()
            let knownBytes = try Data(contentsOf: fixture.database)
            let writer = try SearchSQLiteDatabase(path: fixture.database.path)
            try writer.execute(
                policy == .future
                    ? "UPDATE search_index_state SET schema_version = schema_version + 1;"
                    : "DROP TABLE search_index_state;")
            try writer.admitCheckpointOnClose()
            writer.close()
            let protectedBytes = try Data(contentsOf: fixture.database)
            let protected = fixture.indexDirectory.appendingPathComponent(Self.wrapped("search-v10.sqlite", nested: nested))
            try FileManager.default.moveItem(at: fixture.database, to: protected)
            let current = fixture.indexDirectory.appendingPathComponent(Self.wrapped("search-v10.sqlite", nested: nested))
            let corrupt = fixture.indexDirectory.appendingPathComponent(Self.wrapped("search-v10.sqlite", nested: nested))
            try knownBytes.write(to: current)
            try Data("corrupt disposable SQLite database".utf8).write(to: corrupt)

            switch boundary {
            case .startup:
                let opened = try await TriptychSearchIndex.openRecovering(applicationSupportURL: fixture.support, triptychID: fixture.triptychID)
                await opened.index.shutdown()
            case .maintenance:
                let summary = try await WorkspaceRegistry(storageURL: fixture.registry)
                    .maintainDerivedState(applicationSupportURL: fixture.support)
                #expect(summary.removedFiles == 2)
                #expect(summary.preservedFiles >= 1)
            }
            #expect(try Data(contentsOf: protected) == protectedBytes)
            #expect(!FileManager.default.fileExists(atPath: current.path))
            #expect(!FileManager.default.fileExists(atPath: corrupt.path))
            let names = try FileManager.default.contentsOfDirectory(atPath: fixture.indexDirectory.path)
            #expect(!names.contains { $0.hasSuffix("-wal") || $0.hasSuffix("-shm") })
        }
    }

    @Test(
        "Uncertain current or staging cohorts preserve every main and sidecar before policy inspection",
        arguments: UncertainCohort.allCases, CleanupBoundary.allCases)
    func uncertainCohortsPreserveAllArtifacts(cohort: UncertainCohort, boundary: CleanupBoundary) async throws {
        for staging in [false, true] {
            let fixture = try StorageFixture()
            defer { fixture.remove() }
            let initial = try fixture.index()
            await initial.shutdown()
            let mainBytes = try Data(contentsOf: fixture.database)
            try FileManager.default.removeItem(at: fixture.database)
            let main = staging ? ".search-v10-staging-\(UUID().uuidString).sqlite" : "search-v10.sqlite"
            let names: [String]
            switch cohort {
            case .originalMainWithWrappedSidecars:
                names = [main, Self.wrapped(main + "-wal", nested: false), Self.wrapped(main + "-shm", nested: true)]
            case .wrappedMainWithOriginalSidecars:
                names = [Self.wrapped(main, nested: true), main + "-wal", main + "-shm"]
            case .originalSidecarsWithoutMain:
                names = [main + "-wal", main + "-shm"]
            case .originalCohortWithWrappedMain:
                names = [main, main + "-wal", main + "-shm", Self.wrapped(main, nested: true)]
            case .mixedNestedWrappers:
                names = [
                    main, Self.wrapped(main, nested: true), main + "-wal",
                    Self.wrapped(main + "-wal", nested: true), Self.wrapped(main + "-shm", nested: false),
                ]
            }
            let expected = Dictionary(
                uniqueKeysWithValues: names.map { name in
                    let bytes =
                        name.hasSuffix("-wal") || name.hasSuffix("-shm")
                        ? Data("unassociated disposable sidecar: \(name)".utf8) : mainBytes
                    return (name, bytes)
                })
            for (name, bytes) in expected { try bytes.write(to: fixture.indexDirectory.appendingPathComponent(name)) }
            let beforeNames = Set(try FileManager.default.contentsOfDirectory(atPath: fixture.indexDirectory.path))
            switch boundary {
            case .startup:
                let lease = try DerivedStateStorage.searchLease(
                    storage: DerivedStateStorage.searchStorage(applicationSupportURL: fixture.support, triptychID: fixture.triptychID))
                withExtendedLifetime(lease) {}
            case .maintenance:
                let summary = try await WorkspaceRegistry(storageURL: fixture.registry)
                    .maintainDerivedState(applicationSupportURL: fixture.support)
                #expect(summary.removedFiles == 0)
                #expect(summary.preservedFiles == expected.count)
            }
            for (name, bytes) in expected {
                #expect(try Data(contentsOf: fixture.indexDirectory.appendingPathComponent(name)) == bytes)
            }
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath: fixture.indexDirectory.path)) == beforeNames)
            if staging {
                // A different origin's ambiguous staging files do not block
                // creation of the normal current database.
                let opened = try await TriptychSearchIndex.openRecovering(applicationSupportURL: fixture.support, triptychID: fixture.triptychID)
                await opened.index.shutdown()
            } else {
                await #expect(throws: DerivedStateStorageError.unrecognizedPolicy) {
                    try await TriptychSearchIndex.openRecovering(applicationSupportURL: fixture.support, triptychID: fixture.triptychID)
                }
                #expect(throws: DerivedStateStorageError.unrecognizedPolicy) {
                    try TriptychSearchIndex.openRecovering(isolatedDatabaseURL: fixture.database, triptychID: fixture.triptychID)
                }
                let shared = try DerivedStateStorage.searchLease(
                    storage: DerivedStateStorage.searchStorage(applicationSupportURL: fixture.support, triptychID: fixture.triptychID))
                try shared.downgrade()
                // Admission is also enforced when a peer prevents exclusive
                // startup cleanup and the opener receives a shared lease.
                await #expect(throws: DerivedStateStorageError.unrecognizedPolicy) {
                    try await TriptychSearchIndex.openRecovering(applicationSupportURL: fixture.support, triptychID: fixture.triptychID)
                }
                withExtendedLifetime(shared) {}
            }
            for (name, bytes) in expected {
                #expect(try Data(contentsOf: fixture.indexDirectory.appendingPathComponent(name)) == bytes)
            }
            let allowedNames = staging ? beforeNames.union(["search-v10.sqlite"]) : beforeNames
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath: fixture.indexDirectory.path)) == allowedNames)
        }
    }

    private static func wrapped(_ name: String, nested: Bool) -> String {
        let wrapped = ".derived-retired-\(UUID().uuidString.lowercased())-\(name)"
        return nested ? ".derived-retired-\(UUID().uuidString.lowercased())-\(wrapped)" : wrapped
    }

    @Test("Known-schema recovery cannot replace a live peer and is admitted after its drain")
    func recoveryWaitsForLivePeer() async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        let live = try fixture.index()
        let writer = try SearchSQLiteDatabase(path: fixture.database.path)
        try writer.execute("UPDATE search_index_state SET schema_version = schema_version - 1;")
        writer.close()
        await #expect(throws: DerivedStateStorageError.inUse) {
            try await TriptychSearchIndex.openRecovering(applicationSupportURL: fixture.support, triptychID: fixture.triptychID)
        }
        await live.shutdown()
        let recovered = try await TriptychSearchIndex.openRecovering(applicationSupportURL: fixture.support, triptychID: fixture.triptychID)
        #expect(recovered.recoveredCorruption)
        await recovered.index.shutdown()
    }

    @Test("Missing, damaged and future registry state cannot authorize orphan deletion", arguments: ["missing", "damaged", "future"])
    func unavailableMembershipPreservesDerivedState(_ state: String) async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        await index.shutdown()
        let before = try Data(contentsOf: fixture.database)
        let registryFile = WorkspaceRegistry.registryURL(storageURL: fixture.registry)
        switch state {
        case "missing": try FileManager.default.removeItem(at: registryFile)
        case "damaged": try Data("invalid registry bytes".utf8).write(to: registryFile)
        default:
            try Data(#"{"schemaVersion":999,"vaults":[],"triptychs":[]}"#.utf8).write(to: registryFile)
        }
        await #expect(throws: WorkspaceRegistryError.self) {
            try await WorkspaceRegistry(storageURL: fixture.registry).maintainDerivedState(applicationSupportURL: fixture.support)
        }
        #expect(try Data(contentsOf: fixture.database) == before)
    }

    @Test("The permanent owner lock excludes maintenance from a different process")
    func ownerLockIsProcessShared() async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let lock = fixture.indexDirectory.appendingPathComponent(".derived-state.lock")
        #expect(try competingProcess(lock: lock) == 73)
        await index.shutdown()
        #expect(try competingProcess(lock: lock) == 0)
    }

    private func competingProcess(lock: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            "-c",
            """
            import fcntl, os, sys
            fd = os.open(sys.argv[1], os.O_RDWR | os.O_NOFOLLOW)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                sys.exit(73)
            finally:
                os.close(fd)
            """, lock.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test("Physical trusted-root paths retain the real system alias spelling without creating test state there")
    func physicalSystemRootAlias() throws {
        let logical = URL(fileURLWithPath: "/var/folders", isDirectory: true)
        let storage = SecureRecordDirectory(
            trustedRootURL: logical, components: ["unused-test-component"],
            directoryMode: 0o700, fileMode: 0o600, maximumByteCount: 0)
        // Only existing directory metadata is opened. No files or permissions
        // outside the repository-owned fixture are changed by this proof.
        let physical = try storage.physicalTrustedRootPath()
        #expect(physical == "/private/var/folders")
        #expect(logical.resolvingSymlinksInPath().path == "/var/folders")
        #expect(physical != logical.resolvingSymlinksInPath().path)
    }

    @Test("A trusted-root alias opens clean WAL state without resolving internal storage ancestors")
    func trustedRootAliasReopensExactGeneration() async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        let alias = fixture.root.appendingPathComponent("Trusted Support Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.support)
        let index = try TriptychSearchIndex(applicationSupportURL: alias, triptychID: fixture.triptychID)
        let published = try await index.synchronize([
            SearchIndexDocument(
                vaultID: UUID(), vaultName: "Topics", vaultRole: .topicKnowledge,
                document: NoteDocument(relativePath: "Exact.md", rawContent: "exact persisted source"))
        ])
        await index.shutdown()
        #expect(!FileManager.default.fileExists(atPath: fixture.database.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: fixture.database.path + "-shm"))
        let before = try Data(contentsOf: fixture.database)
        let reopened = try await TriptychSearchIndex.openRecovering(applicationSupportURL: alias, triptychID: fixture.triptychID)
        #expect(!reopened.recoveredCorruption)
        #expect(try await reopened.index.generation() == published.generation)
        await reopened.index.shutdown()
        #expect(try Data(contentsOf: fixture.database) == before)
        try Data("retired index".utf8).write(to: fixture.indexDirectory.appendingPathComponent("search-v9.sqlite"))
        let maintenance = try await WorkspaceRegistry(storageURL: fixture.registry).maintainDerivedState(applicationSupportURL: alias)
        #expect(maintenance.removedFiles == 2)
        #expect(!FileManager.default.fileExists(atPath: fixture.database.path))
    }

    @Test("Registered cache records retire known internal policies without loading or inflating them", arguments: [false, true])
    func registeredCachePolicyRetirement(catalog: Bool) async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        let vaultID = UUID()
        let vault = fixture.root.appendingPathComponent("Registered Library")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let registry = WorkspaceRegistry(storageURL: fixture.registry)
        _ = try await registry.register(path: vault, name: "Topics", role: .topicKnowledge, stableID: vaultID)
        let document = NoteDocument(relativePath: "A.md", rawContent: "# Exact source\n\n[[Target]]")
        let cache = SourceProjectionCache(applicationSupportURL: fixture.support, vaultID: vaultID, role: .topicKnowledge)
        if catalog {
            cache.storeCatalog(
                WorkspaceSourceProjection(vaultID: vaultID, document: document, semantic: MarkdownSemanticDocument(parsing: document)),
                for: document)
        } else {
            cache.store(SearchDocumentProjection(document: document), for: document)
        }
        let directory = fixture.cacheDirectory(vaultID)
        let fileName = catalog ? SourceProjectionCache.catalogFileName(document.relativePath) : SourceProjectionCache.fileName(document.relativePath)
        let suffix = catalog ? ".catalog.plist" : ".projection.plist"
        let retired = directory.appendingPathComponent(fileName)
        var frame = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: retired), format: nil) as? [String: Any])
        var policy = try #require(frame["policy"] as? [String: Any])
        // Header inspection must not inflate even this deliberately invalid payload.
        frame["payload"] = Data("not a compressed projection".utf8)
        let current = directory.appendingPathComponent(String(repeating: "b", count: 64) + suffix)
        let currentBytes = try PropertyListSerialization.data(fromPropertyList: frame, format: .binary, options: 0)
        try currentBytes.write(to: current)
        policy["projectionVersion"] = 0
        frame["policy"] = policy
        try PropertyListSerialization.data(fromPropertyList: frame, format: .binary, options: 0).write(to: retired)
        policy["projectionVersion"] = Int.max
        frame["policy"] = policy
        let future = directory.appendingPathComponent(String(repeating: "c", count: 64) + suffix)
        let futureBytes = try PropertyListSerialization.data(fromPropertyList: frame, format: .binary, options: 0)
        try futureBytes.write(to: future)
        let corrupt = directory.appendingPathComponent(String(repeating: "d", count: 64) + suffix)
        try Data("incomplete recognized generated record".utf8).write(to: corrupt)
        let summary = try await registry.maintainDerivedState(applicationSupportURL: fixture.support)
        #expect(summary.removedFiles == 2)
        #expect(!FileManager.default.fileExists(atPath: retired.path))
        #expect(!FileManager.default.fileExists(atPath: corrupt.path))
        #expect(try Data(contentsOf: current) == currentBytes)
        #expect(try Data(contentsOf: future) == futureBytes)
    }

    @Test("A symlink in the production index ancestor cannot reach external files")
    func symlinkAncestorCannotAuthorizeStorage() async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("Outside")
        let target = outside.appendingPathComponent("\(fixture.triptychID.uuidString.lowercased())/indexes")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let sentinel = target.appendingPathComponent("search-v9.sqlite")
        let bytes = Data("external sentinel".utf8)
        try bytes.write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: fixture.support.appendingPathComponent("Triptychs"), withDestinationURL: outside)
        #expect(throws: (any Error).self) { try fixture.index() }
        let summary = try await WorkspaceRegistry(storageURL: fixture.registry)
            .maintainDerivedState(applicationSupportURL: fixture.support)
        #expect(summary.failedDirectories > 0)
        #expect(try Data(contentsOf: sentinel) == bytes)
        #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("search-v10.sqlite").path))
    }

    @Test("Cache references, active leases and future records bound garbage collection")
    func cacheCollectionRespectsReferencesAndPolicy() async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        let vaultID = UUID()
        let vault = fixture.root.appendingPathComponent("Registered Library")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let registry = WorkspaceRegistry(storageURL: fixture.registry)
        _ = try await registry.register(path: vault, name: "Registered", role: .topicKnowledge, stableID: vaultID)
        let document = NoteDocument(relativePath: "A.md", rawContent: "# Exact\r\n\r\n中文 😀")
        let cache = SourceProjectionCache(applicationSupportURL: fixture.support, vaultID: vaultID, role: .topicKnowledge)
        cache.store(SearchDocumentProjection(document: document), for: document)
        let directory = fixture.cacheDirectory(vaultID)
        let record = directory.appendingPathComponent(SourceProjectionCache.fileName(document.relativePath))
        let bytes = try Data(contentsOf: record)
        let summary = try await registry.maintainDerivedState(applicationSupportURL: fixture.support)
        #expect(summary.removedFiles == 0)
        #expect(try Data(contentsOf: record) == bytes)

        let orphanID = UUID()
        let orphan = SourceProjectionCache(applicationSupportURL: fixture.support, vaultID: orphanID, role: .topicKnowledge)
        orphan.store(SearchDocumentProjection(document: document), for: document)
        let orphanDirectory = fixture.cacheDirectory(orphanID)
        let orphanRecord = orphanDirectory.appendingPathComponent(SourceProjectionCache.fileName(document.relativePath))
        var frame = try #require(PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any])
        var policy = try #require(frame["policy"] as? [String: Any])
        policy["formatVersion"] = 999
        frame["policy"] = policy
        let future = orphanDirectory.appendingPathComponent(String(repeating: "a", count: 64) + ".projection.plist")
        let futureBytes = try PropertyListSerialization.data(fromPropertyList: frame, format: .binary, options: 0)
        try futureBytes.write(to: future)
        let pending = orphanDirectory.appendingPathComponent(".scholium-pending-\(UUID().uuidString.lowercased())")
        var lease: DerivedStateStorageLease? = try DerivedStateStorage.vaultCacheLease(applicationSupportURL: fixture.support, vaultID: orphanID)
        try Data("incomplete disposable staging".utf8).write(to: pending)
        #expect(try await registry.maintainDerivedState(applicationSupportURL: fixture.support).busyDirectories == 1)
        #expect(FileManager.default.fileExists(atPath: pending.path))
        withExtendedLifetime(lease) {}
        lease = nil
        let cleaned = try await registry.maintainDerivedState(applicationSupportURL: fixture.support)
        #expect(cleaned.removedFiles >= 1)
        #expect(!FileManager.default.fileExists(atPath: orphanRecord.path))
        #expect(!FileManager.default.fileExists(atPath: pending.path))
        #expect(try Data(contentsOf: future) == futureBytes)
        #expect(try Data(contentsOf: record) == bytes)
    }

    @Test("Shutdown joins the active writer and releases maintenance only after rollback", .timeLimit(.minutes(1)))
    func shutdownDrainsWriter() async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let document = NoteDocument(relativePath: "A.md", rawContent: "exact source")
        let vaultID = UUID()
        let initial = try await index.synchronize([
            SearchIndexDocument(
                vaultID: vaultID, vaultName: "Topics", vaultRole: .topicKnowledge,
                document: NoteDocument(relativePath: "A.md", rawContent: "previous exact source"))
        ])
        let gate = StorageWriterGate()
        let entry = SearchIndexManifestEntry(
            vaultID: vaultID, vaultName: "Topics", vaultRole: .topicKnowledge,
            relativePath: document.relativePath, stableNoteID: nil, fingerprint: document.fingerprint, hasBrokenLink: false)
        let publication = Task {
            try await index.synchronizeManifest(
                [entry], workspaceGeneration: 2,
                loadChanged: { _ in
                    await gate.hold()
                    return SearchIndexDocument(vaultID: vaultID, vaultName: "Topics", vaultRole: .topicKnowledge, document: document)
                }, validateManifest: {})
        }
        await gate.waitUntilEntered()
        let first = Task { await index.shutdown() }
        for _ in 0..<10_000 {
            if await index.availability() == .unavailable { break }
            await Task.yield()
        }
        #expect(await index.availability() == .unavailable)
        let second = Task { await index.shutdown() }
        await #expect(throws: SearchIndexError.self) { try await index.generation() }
        #expect(throws: DerivedStateStorageError.inUse) {
            try DerivedStateStorage.searchMaintenanceLease(
                storage: .init(
                    trustedRootURL: fixture.support, components: ["Triptychs", fixture.triptychID.uuidString.lowercased(), "indexes"],
                    directoryMode: 0o700, fileMode: 0o600, maximumByteCount: 0))
        }
        await gate.release()
        await first.value
        await second.value
        await #expect(throws: CancellationError.self) { try await publication.value }
        let reopened = try fixture.index()
        #expect(try await reopened.workspaceGeneration() == 1)
        #expect(try await reopened.generation() == initial.generation)
        await reopened.shutdown()
    }

    #if DEBUG
        @Test("Opening waits for exclusive storage admission and preserves cancellation", arguments: [false, true])
        func openingWaitsForStorage(cancel: Bool) async throws {
            let fixture = try StorageFixture()
            defer { fixture.remove() }
            let initial = try fixture.index()
            let published = try await initial.synchronize([
                SearchIndexDocument(
                    vaultID: UUID(), vaultName: "Topics", vaultRole: .topicKnowledge,
                    document: NoteDocument(relativePath: "Exact.md", rawContent: "exact committed source"))
            ])
            await initial.shutdown()
            let before = try Data(contentsOf: fixture.database)
            let storage = DerivedStateStorage.searchStorage(applicationSupportURL: fixture.support, triptychID: fixture.triptychID)
            var maintenance: DerivedStateStorageLease? = try DerivedStateStorage.searchMaintenanceLease(storage: storage)
            let signal = StorageOpeningSignal()
            let opening = Task {
                try await TriptychSearchIndex.openRecovering(applicationSupportURL: fixture.support, triptychID: fixture.triptychID) {
                    await signal.observeWait()
                }
            }
            await signal.waitUntilEntered()
            #expect(try Data(contentsOf: fixture.database) == before)
            if cancel {
                opening.cancel()
                await #expect(throws: CancellationError.self) { try await opening.value }
                #expect(try Data(contentsOf: fixture.database) == before)
            }
            withExtendedLifetime(maintenance) {}
            maintenance = nil
            if !cancel {
                let opened = try await opening.value
                #expect(!opened.recoveredCorruption)
                #expect(try await opened.index.generation() == published.generation)
                await opened.index.shutdown()
            } else {
                let opened = try await TriptychSearchIndex.openRecovering(applicationSupportURL: fixture.support, triptychID: fixture.triptychID)
                #expect(try await opened.index.generation() == published.generation)
                await opened.index.shutdown()
            }
        }

        @Test("Registry mutation cannot pass the reference snapshot held by maintenance", .timeLimit(.minutes(1)))
        func registryMutationSharesMaintenanceLock() async throws {
            let fixture = try StorageFixture()
            defer { fixture.remove() }
            let maintenance = WorkspaceRegistry(storageURL: fixture.registry)
            let writer = WorkspaceRegistry(storageURL: fixture.registry)
            let attempting = DispatchSemaphore(value: 0)
            let complete = DispatchSemaphore(value: 0)
            await writer.setRegistrationLockAttemptForTesting { attempting.signal() }
            let vault = fixture.root.appendingPathComponent("New Library")
            try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
            // First establish the lock before admitting the competing call.
            // The task below is created by the callback, after snapshot capture.
            let taskBox = StorageTaskBox()
            _ = try await maintenance.maintainDerivedState(applicationSupportURL: fixture.support) {
                taskBox.start {
                    let result = try await writer.register(path: vault, name: "New", role: .topicKnowledge)
                    complete.signal()
                    return result
                }
                #expect(attempting.wait(timeout: .now() + 5) == .success)
                #expect(complete.wait(timeout: .now()) == .timedOut)
                #expect(throws: DerivedStateStorageError.inUse) {
                    try DerivedStateStorage.registryLease(storageURL: fixture.registry, wait: false)
                }
            }
            let task = try #require(taskBox.task)
            _ = try await task.value
            #expect(try await maintenance.allVaults().count == 1)
        }
    #endif
}

private struct StorageFixture: Sendable {
    let root: URL
    let support: URL
    let registry: URL
    let triptychID = UUID()
    var database: URL { TriptychSearchIndex.databaseURL(applicationSupportURL: support, triptychID: triptychID) }
    var indexDirectory: URL { database.deletingLastPathComponent() }
    init() throws {
        root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/derived-state-storage-tests/\(UUID().uuidString)")
        support = root.appendingPathComponent("Support")
        registry = root.appendingPathComponent("Registry")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: registry, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":3,"vaults":[],"triptychs":[]}"#.utf8)
            .write(to: WorkspaceRegistry.registryURL(storageURL: registry))
    }
    func index() throws -> TriptychSearchIndex { try .init(applicationSupportURL: support, triptychID: triptychID) }
    func cacheDirectory(_ id: UUID) -> URL { support.appendingPathComponent("Vaults/\(id.uuidString)/source-projections-v1") }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private actor StorageWriterGate {
    private var entered = false
    private var entry: CheckedContinuation<Void, Never>?
    private var exit: CheckedContinuation<Void, Never>?
    func hold() async {
        entered = true
        entry?.resume()
        entry = nil
        await withCheckedContinuation { exit = $0 }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { entry = $0 }
    }
    func release() {
        exit?.resume()
        exit = nil
    }
}

private final class StorageTaskBox: Sendable {
    private let lock = OSAllocatedUnfairLock<Task<RegisteredVault, Error>?>(initialState: nil)
    var task: Task<RegisteredVault, Error>? { lock.withLock { $0 } }
    func start(_ operation: @escaping @Sendable () async throws -> RegisteredVault) {
        lock.withLock { $0 = Task.detached(operation: operation) }
    }
}

#if DEBUG
    private actor StorageOpeningSignal {
        private var entered = false
        private var waiter: CheckedContinuation<Void, Never>?
        func observeWait() {
            entered = true
            waiter?.resume()
            waiter = nil
        }
        func waitUntilEntered() async {
            if entered { return }
            await withCheckedContinuation { waiter = $0 }
        }
    }
#endif
