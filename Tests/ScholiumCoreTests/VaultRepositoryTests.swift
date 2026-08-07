import Darwin
import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Transactional vault repository")
struct VaultRepositoryTests {
    private enum SaveFault: Error {
        case afterSwap
    }

    private func fixture() throws -> (root: URL, support: URL, note: URL) {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureID = String(UUID().uuidString.prefix(12)).lowercased()
        let base = repositoryRoot
            .appendingPathComponent(".build/vt", isDirectory: true)
            .appendingPathComponent(fixtureID, isDirectory: true)
        let root = base.appendingPathComponent("vault", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        let note = root.appendingPathComponent("topics/note.md")
        try FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\ntitle: Note\nmodified: 2025-01-01\n---\nOriginal\n".write(to: note, atomically: true, encoding: .utf8)
        return (root, support, note)
    }

    @Test("FIFO, socket, and directory leaves are rejected without blocking")
    func specialFilesAreRejectedWithoutBlocking() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil),
            applicationSupportURL: f.support
        )
        try FileManager.default.removeItem(at: f.note)

        #expect(mkfifo(f.note.path, 0o600) == 0)
        let clock = ContinuousClock()
        let fifoStart = clock.now
        await #expect(throws: (any Error).self) {
            _ = try await repository.load(relativePath: "topics/note.md")
        }
        #expect(fifoStart.duration(to: clock.now) < .seconds(1))
        try FileManager.default.removeItem(at: f.note)

        try FileManager.default.createDirectory(at: f.note, withIntermediateDirectories: false)
        await #expect(throws: (any Error).self) {
            _ = try await repository.load(relativePath: "topics/note.md")
        }
        try FileManager.default.removeItem(at: f.note)

        let socketDescriptor = try bindUnixSocket(at: f.note)
        defer { close(socketDescriptor) }
        let socketStart = clock.now
        await #expect(throws: (any Error).self) {
            _ = try await repository.load(relativePath: "topics/note.md")
        }
        #expect(socketStart.duration(to: clock.now) < .seconds(1))
    }

    @Test("Inventory enumeration fails closed when a vault subtree is unreadable")
    func unreadableInventoryIsNotTreatedAsDeletion() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: VaultIdentity(
                id: UUID(),
                canonicalPath: f.root.path,
                bookmarkData: nil
            ),
            applicationSupportURL: f.support
        )
        let unreadable = f.root.appendingPathComponent(
            "unreadable",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: unreadable,
            withIntermediateDirectories: false
        )
        try Data("# Hidden from an incomplete inventory\n".utf8).write(
            to: unreadable.appendingPathComponent("Hidden.md")
        )
        guard chmod(unreadable.path, 0) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = chmod(unreadable.path, 0o700) }

        await #expect(throws: (any Error).self) {
            _ = try await repository.markdownRelativePaths(
                includeLifecycle: true
            )
        }
        await #expect(throws: (any Error).self) {
            _ = try await repository.folderRelativePaths(
                includeLifecycle: true
            )
        }
    }

    private func bindUnixSocket(at url: URL) throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var address = sockaddr_un()
        let bytes = Array(url.path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(descriptor)
            throw POSIXError(.ENAMETOOLONG)
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sa_family_t>.size + bytes.count)
        withUnsafeMutablePointer(to: &address.sun_path.0) { destination in
            bytes.withUnsafeBytes { source in
                _ = memcpy(destination, source.baseAddress, bytes.count)
            }
        }
        let addressLength = socklen_t(address.sun_len)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, addressLength)
            }
        }
        guard result == 0 else {
            let code = errno
            close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return descriptor
    }

    @Test("Save records immutable prewrite recovery without exposing delivery restore")
    func saveRecordsPrewriteRecovery() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(vaultURL: f.root, identity: identity, applicationSupportURL: f.support)
        let original = try await repository.load(relativePath: "topics/note.md")
        let saved = try await repository.save(
            relativePath: "topics/note.md",
            changeSet: .body("Changed\n"),
            expectedRevision: original.fingerprint
        )
        let savedContent = try String(contentsOf: f.note, encoding: .utf8)
        #expect(savedContent.contains("Changed"))
        let firstRecovery = await repository.recoveryEntries(relativePath: "topics/note.md")
        #expect(firstRecovery.count == 1)
        #expect(try await repository.recoveryContent(entryID: firstRecovery[0].id) == original.rawContent)

        _ = try await repository.save(
            relativePath: "topics/note.md",
            changeSet: .body("Changed again\n"),
            expectedRevision: saved.document.fingerprint
        )
        #expect((await repository.recoveryEntries(relativePath: "topics/note.md")).count == 2)
    }

    @Test("External changes cause a conflict")
    func conflict() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(vaultURL: f.root, identity: identity, applicationSupportURL: f.support)
        let loaded = try await repository.load(relativePath: "topics/note.md")
        try "External edit".write(to: f.note, atomically: true, encoding: .utf8)

        await #expect(throws: VaultRepositoryError.self) {
            try await repository.save(
                relativePath: "topics/note.md",
                changeSet: .body("Local edit"),
                expectedRevision: loaded.fingerprint
            )
        }
        #expect(try String(contentsOf: f.note, encoding: .utf8) == "External edit")
    }

    @Test("Post-swap and repository readback uncertainty retain exact save recovery")
    func unknownSaveOutcomesRequireRecovery() async throws {
        try await expectRecoveryOutcome(at: .swapped)
        try await expectRecoveryOutcome(at: .completedReplacement)
    }

    @Test("A committed save retries displaced-source cleanup after reopening the vault")
    func committedSaveRetriesCleanupAfterReopen() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        var repository: VaultRepository? = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support,
            mutationHooks: VaultMutationHooks(
                didReach: { phase in
                    if phase == .cleanup { throw SaveFault.afterSwap }
                }
            )
        )
        let original = try await repository!.load(relativePath: "topics/note.md")
        let outcome = try await repository!.saveOutcome(
            relativePath: "topics/note.md",
            changeSet: .exactContent("# Candidate\n"),
            expectedRevision: original.fingerprint
        )
        guard case .committed(let result) = outcome else {
            Issue.record("A cleanup-only failure was not reported as a committed save.")
            return
        }
        #expect(result.cleanupWarning?.kind == .displacedSourceCopy)
        #expect(try String(contentsOf: f.note, encoding: .utf8) == "# Candidate\n")
        #expect(try stagedFiles(in: f.root).count == 1)

        repository = nil
        let reopened = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        #expect(try stagedFiles(in: f.root).isEmpty)
        #expect(await reopened.recoveryLedgerHealthDiagnostic() == nil)
    }

    @Test("A committed save distinguishes transaction-record cleanup from displaced source cleanup")
    func transactionRecordCleanupWarningIsTypedSeparately() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        var repository: VaultRepository? = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support,
            mutationHooks: VaultMutationHooks(
                cleanupRecordRemovalOverride: {
                    throw CocoaError(.fileWriteUnknown)
                }
            )
        )
        let original = try await repository!.load(relativePath: "topics/note.md")
        let result = try await repository!.save(
            relativePath: "topics/note.md",
            changeSet: .exactContent("# Candidate\n"),
            expectedRevision: original.fingerprint
        )

        #expect(result.cleanupWarning?.kind == .transactionRecord)
        #expect(result.cleanupWarning?.message.contains("transaction record") == true)
        #expect(try stagedFiles(in: f.root).isEmpty)
        #expect(try Data(contentsOf: f.note) == Data("# Candidate\n".utf8))

        repository = nil
        let reopened = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        #expect(try stagedFiles(in: f.root).isEmpty)
        #expect(await reopened.recoveryLedgerHealthDiagnostic() == nil)
    }

    @Test("Cleanup authorization persistence failure prevents canonical replacement")
    func cleanupAuthorizationFailurePreventsSwap() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        var repository: VaultRepository? = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support,
            mutationHooks: VaultMutationHooks(
                cleanupPersistenceOverride: {
                    throw CocoaError(.fileWriteUnknown)
                }
            )
        )
        let original = try await repository!.load(relativePath: "topics/note.md")
        let outcome = try await repository!.saveOutcome(
            relativePath: "topics/note.md",
            changeSet: .exactContent("# Candidate\n"),
            expectedRevision: original.fingerprint
        )
        guard case .recoveryRequired = outcome else {
            Issue.record("Cleanup authorization failure did not retain recovery.")
            return
        }
        #expect(try Data(contentsOf: f.note) == Data(original.rawContent.utf8))
        #expect(try stagedFiles(in: f.root).isEmpty)

        repository = nil
        let reopened = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        #expect(try await reopened.interruptedSaveRecoveries().count == 1)
        #expect(try stagedFiles(in: f.root).isEmpty)
    }

    @Test("Pre-swap cleanup failure preserves authorization instead of leaving an orphan staging file")
    func atomicUnsupportedCleanupFailureRetainsTask() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        var repository: VaultRepository? = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support,
            mutationHooks: VaultMutationHooks(
                didReach: { phase in
                    if phase == .finalCheck {
                        throw VaultRepositoryError.atomicCommitUnsupported(
                            "Injected unsupported swap."
                        )
                    }
                },
                cleanupOverride: {
                    throw CocoaError(.fileWriteUnknown)
                }
            )
        )
        let original = try await repository!.load(relativePath: "topics/note.md")
        let outcome = try await repository!.saveOutcome(
            relativePath: "topics/note.md",
            changeSet: .exactContent("# Candidate\n"),
            expectedRevision: original.fingerprint
        )

        guard case .recoveryRequired = outcome else {
            Issue.record("Failed pre-swap cleanup deleted its only authorization.")
            return
        }
        #expect(try Data(contentsOf: f.note) == Data(original.rawContent.utf8))
        #expect(try stagedFiles(in: f.root).count == 1)
        #expect(try mutationManifest(support: f.support, vaultID: identity.id) != nil)

        repository = nil
        let reopened = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        #expect(try stagedFiles(in: f.root).isEmpty)
        #expect(try await reopened.interruptedSaveRecoveries().count == 1)
    }

    @Test("Cleanup retry refuses a substituted staging inode")
    func cleanupRetryRejectsSubstitutedStaging() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        var repository: VaultRepository? = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support,
            mutationHooks: VaultMutationHooks(
                cleanupOverride: {
                    let stagingURL = try FileManager.default.contentsOfDirectory(
                        at: f.note.deletingLastPathComponent(),
                        includingPropertiesForKeys: nil
                    ).first { $0.lastPathComponent.hasPrefix(".scholium-swap-") }
                    let staging = try #require(stagingURL)
                    try FileManager.default.removeItem(at: staging)
                    try Data("untrusted replacement".utf8).write(to: staging)
                    throw SaveFault.afterSwap
                }
            )
        )
        let original = try await repository!.load(relativePath: "topics/note.md")
        let outcome = try await repository!.saveOutcome(
            relativePath: "topics/note.md",
            changeSet: .exactContent("# Candidate\n"),
            expectedRevision: original.fingerprint
        )
        guard case .committed(let result) = outcome else {
            Issue.record("A substituted cleanup file changed the source outcome.")
            return
        }
        #expect(result.cleanupWarning?.kind == .displacedSourceCopy)
        repository = nil

        let reopened = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        #expect(try stagedFiles(in: f.root).count == 1)
        #expect(try Self.cleanupDirectories(in: f.root).isEmpty)
        #expect(await reopened.recoveryLedgerHealthDiagnostic()?.contains("cleanup") == true)
        #expect(try String(contentsOf: stagedFiles(in: f.root)[0], encoding: .utf8)
            == "untrusted replacement")
    }

    @Test("Cleanup refuses an isolated entry replaced before final authorization")
    func cleanupRejectsSubstitutedIsolatedEntry() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        var repository: VaultRepository? = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support,
            mutationHooks: VaultMutationHooks(
                cleanupIsolationOverride: {
                    let directory = try #require(
                        try Self.cleanupDirectories(in: f.root).first
                    )
                    let isolated = try #require(
                        try FileManager.default.contentsOfDirectory(
                            at: directory,
                            includingPropertiesForKeys: nil
                        ).first
                    )
                    try Data("untrusted isolated replacement".utf8).write(
                        to: isolated
                    )
                }
            )
        )
        let original = try await repository!.load(relativePath: "topics/note.md")
        let outcome = try await repository!.saveOutcome(
            relativePath: "topics/note.md",
            changeSet: .exactContent("# Candidate\n"),
            expectedRevision: original.fingerprint
        )
        guard case .committed(let result) = outcome else {
            Issue.record("The isolated cleanup race changed the source outcome.")
            return
        }
        #expect(result.cleanupWarning?.kind == .displacedSourceCopy)
        repository = nil

        let reopened = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        let directory = try #require(try Self.cleanupDirectories(in: f.root).first)
        let isolated = try #require(try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).first)
        #expect(try String(contentsOf: isolated, encoding: .utf8)
            == "untrusted isolated replacement")
        #expect(await reopened.recoveryLedgerHealthDiagnostic()?.contains("cleanup") == true)
    }

    @Test("Cleanup refuses an isolated entry with an added hard link")
    func cleanupRejectsLinkedIsolatedEntry() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support,
            mutationHooks: VaultMutationHooks(
                cleanupIsolationOverride: {
                    let directory = try #require(
                        try Self.cleanupDirectories(in: f.root).first
                    )
                    let isolated = try #require(
                        try FileManager.default.contentsOfDirectory(
                            at: directory,
                            includingPropertiesForKeys: nil
                        ).first
                    )
                    try FileManager.default.linkItem(
                        at: isolated,
                        to: directory.appendingPathComponent("linked-source.md")
                    )
                }
            )
        )
        let original = try await repository.load(relativePath: "topics/note.md")
        let result = try await repository.save(
            relativePath: "topics/note.md",
            changeSet: .exactContent("# Candidate\n"),
            expectedRevision: original.fingerprint
        )

        #expect(result.cleanupWarning?.kind == .displacedSourceCopy)
        let directory = try #require(try Self.cleanupDirectories(in: f.root).first)
        #expect(try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).count == 2)
        #expect(try Data(contentsOf: f.note) == Data("# Candidate\n".utf8))
    }

    @Test("Cleanup retains an isolated preimage when its original staging name reappears")
    func cleanupRejectsSimultaneousIsolatedAndStagingPaths() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        var repository: VaultRepository? = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support,
            mutationHooks: VaultMutationHooks(
                cleanupIsolationOverride: {
                    throw CocoaError(.fileWriteUnknown)
                }
            )
        )
        let original = try await repository!.load(relativePath: "topics/note.md")
        let result = try await repository!.save(
            relativePath: "topics/note.md",
            changeSet: .exactContent("# Candidate\n"),
            expectedRevision: original.fingerprint
        )
        #expect(result.cleanupWarning?.kind == .displacedSourceCopy)
        repository = nil

        let manifestURL = try #require(try mutationManifest(
            support: f.support,
            vaultID: identity.id
        ))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let transaction = try decoder.decode(
            PrewriteRecoveryLedger.MutationTransaction.self,
            from: Data(contentsOf: manifestURL)
        )
        let cleanup = try #require(transaction.cleanupPending)
        let staging = f.note.deletingLastPathComponent()
            .appendingPathComponent(cleanup.stagingName)
        try Data("replacement staging".utf8).write(to: staging)

        let reopened = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        #expect(try Data(contentsOf: staging) == Data("replacement staging".utf8))
        let directory = try #require(try Self.cleanupDirectories(in: f.root).first)
        let isolated = try #require(try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).first)
        #expect(try Data(contentsOf: isolated) == Data(original.rawContent.utf8))
        #expect(await reopened.recoveryLedgerHealthDiagnostic()?.contains("cleanup") == true)
    }

    @Test("Cleanup retains a task when staging reappears during isolated removal")
    func cleanupRejectsStagingReappearingDuringRemoval() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        var repository: VaultRepository? = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support,
            mutationHooks: VaultMutationHooks(
                cleanupIsolationOverride: {
                    let directory = try #require(
                        try Self.cleanupDirectories(in: f.root).first
                    )
                    let stagingName = directory.lastPathComponent
                        .replacingOccurrences(
                            of: ".scholium-cleanup-",
                            with: ".scholium-swap-",
                            options: [.anchored]
                        ) + ".md"
                    try Data("replacement during cleanup".utf8).write(
                        to: directory.deletingLastPathComponent()
                            .appendingPathComponent(stagingName)
                    )
                }
            )
        )
        let original = try await repository!.load(relativePath: "topics/note.md")
        let result = try await repository!.save(
            relativePath: "topics/note.md",
            changeSet: .exactContent("# Candidate\n"),
            expectedRevision: original.fingerprint
        )

        #expect(result.cleanupWarning?.kind == .displacedSourceCopy)
        #expect(try stagedFiles(in: f.root).count == 1)
        #expect(try String(
            contentsOf: try #require(try stagedFiles(in: f.root).first),
            encoding: .utf8
        ) == "replacement during cleanup")
        #expect(try Self.cleanupDirectories(in: f.root).isEmpty)
        #expect(try mutationManifest(support: f.support, vaultID: identity.id) != nil)
        repository = nil

        let reopened = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        #expect(await reopened.recoveryLedgerHealthDiagnostic()?.contains("cleanup") == true)
        #expect(try stagedFiles(in: f.root).count == 1)
    }

    @Test("Cleanup retry rejects a task detached from its source transaction")
    func cleanupRetryRejectsTamperedTask() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        var repository: VaultRepository? = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support,
            mutationHooks: VaultMutationHooks(
                didReach: { phase in
                    if phase == .cleanup { throw SaveFault.afterSwap }
                }
            )
        )
        let original = try await repository!.load(relativePath: "topics/note.md")
        _ = try await repository!.saveOutcome(
            relativePath: "topics/note.md",
            changeSet: .exactContent("# Candidate\n"),
            expectedRevision: original.fingerprint
        )
        repository = nil

        let manifestURL = try #require(try mutationManifest(
            support: f.support,
            vaultID: identity.id
        ))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let transaction = try decoder.decode(
            PrewriteRecoveryLedger.MutationTransaction.self,
            from: Data(contentsOf: manifestURL)
        )
        let cleanup = try #require(transaction.cleanupPending)
        let tampered = PrewriteRecoveryLedger.MutationTransaction(
            id: transaction.id,
            relativePath: transaction.relativePath,
            expected: transaction.expected,
            candidate: transaction.candidate,
            createdAt: transaction.createdAt,
            retainedReason: transaction.retainedReason,
            cleanupPending: VaultMutationCleanupTask(
                relativePath: "Other.md",
                stagingName: cleanup.stagingName,
                stagedCandidate: cleanup.stagedCandidate,
                displacedSource: cleanup.displacedSource
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(tampered).write(to: manifestURL, options: .atomic)

        let reopened = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        #expect(try stagedFiles(in: f.root).count == 1)
        #expect(await reopened.recoveryLedgerHealthDiagnostic()?.contains(
            "cleanup task does not match"
        ) == true)
    }

    @Test("A downstream history failure retains the already-persisted cleanup task")
    func downstreamFailureRetainsCleanupTask() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let transactions = f.support
            .appendingPathComponent("Vaults", isDirectory: true)
            .appendingPathComponent(identity.id.uuidString, isDirectory: true)
            .appendingPathComponent("recovery-v2/transactions", isDirectory: true)
        var repository: VaultRepository? = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support,
            mutationHooks: VaultMutationHooks(
                didReach: { phase in
                    if phase == .cleanup {
                        guard chmod(transactions.path, 0o500) == 0 else {
                            throw POSIXError(
                                POSIXErrorCode(rawValue: errno) ?? .EIO
                            )
                        }
                        throw SaveFault.afterSwap
                    }
                }
            )
        )
        defer { _ = chmod(transactions.path, 0o700) }
        let original = try await repository!.load(relativePath: "topics/note.md")
        let outcome = try await repository!.saveOutcome(
            relativePath: "topics/note.md",
            changeSet: .exactContent("# Candidate\n"),
            expectedRevision: original.fingerprint
        )
        guard case .recoveryRequired = outcome else {
            Issue.record("The downstream history failure did not retain recovery.")
            return
        }
        #expect(try stagedFiles(in: f.root).count == 1)
        #expect(chmod(transactions.path, 0o700) == 0)

        repository = nil
        let reopened = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        #expect(try stagedFiles(in: f.root).isEmpty)
        #expect(await reopened.recoveryLedgerHealthDiagnostic() == nil)
    }

    private func stagedFiles(in root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("topics", isDirectory: true),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".scholium-swap-") }
    }

    private static func cleanupDirectories(in root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("topics", isDirectory: true),
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { url in
            guard url.lastPathComponent.hasPrefix(".scholium-cleanup-") else {
                return false
            }
            return try url.resourceValues(forKeys: [.isDirectoryKey])
                .isDirectory == true
        }
    }

    private func mutationManifest(support: URL, vaultID: UUID) throws -> URL? {
        let mutations = support
            .appendingPathComponent("Vaults", isDirectory: true)
            .appendingPathComponent(vaultID.uuidString, isDirectory: true)
            .appendingPathComponent(
                "recovery-v2/transactions/mutations",
                isDirectory: true
            )
        return try FileManager.default.contentsOfDirectory(
            at: mutations,
            includingPropertiesForKeys: nil
        ).first?.appendingPathComponent("manifest.json")
    }

    private func expectRecoveryOutcome(
        at phase: VaultMutationPhase
    ) async throws {
        let f = try fixture()
        defer {
            try? FileManager.default.removeItem(
                at: f.root.deletingLastPathComponent()
            )
        }
        let identity = VaultIdentity(
            id: UUID(),
            canonicalPath: f.root.path,
            bookmarkData: nil
        )
        let externallyReplaced = Data("# External readback revision\n".utf8)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support,
            mutationHooks: VaultMutationHooks(didReach: { reached in
                guard reached == phase else { return }
                if phase == .swapped {
                    throw SaveFault.afterSwap
                }
                try externallyReplaced.write(to: f.note, options: .atomic)
            })
        )
        let original = try await repository.load(relativePath: "topics/note.md")
        let candidate = "# Exact Agent candidate\r\n\r\nPreserve bytes.\r\n"
        let outcome = try await repository.saveOutcome(
            relativePath: "topics/note.md",
            changeSet: .exactContent(candidate),
            expectedRevision: original.fingerprint
        )
        guard case .recoveryRequired(let recovery) = outcome else {
            Issue.record("The post-transaction result was not retained for recovery.")
            return
        }
        #expect(recovery.id.vaultID == identity.id)
        #expect(recovery.relativePath == "topics/note.md")
        #expect(recovery.expectedRevision == original.fingerprint)
        #expect(recovery.candidateRevision == DocumentFingerprint(content: candidate))
        #expect(try await repository.interruptedSaveRecoveries().map(\.id)
            == [recovery.id])
        #expect(try await repository.interruptedSaveRecoveryContent(recovery)
            .exactSource == candidate)
        if phase == .swapped {
            try await repository.abandonInterruptedSaveRecovery(recovery)
            #expect(try await repository.interruptedSaveRecoveries().isEmpty)
        } else {
            #expect(recovery.sourceState == .changed(
                DocumentFingerprint(data: externallyReplaced)
            ))
        }
    }

    @Test("Traversal, missing files, and symlink escapes are rejected")
    func pathSafety() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(vaultURL: f.root, identity: identity, applicationSupportURL: f.support)

        await #expect(throws: VaultRepositoryError.self) { try await repository.load(relativePath: "../outside.md") }
        await #expect(throws: VaultRepositoryError.self) { try await repository.load(relativePath: "topics/missing.md") }

        let outside = f.root.deletingLastPathComponent().appendingPathComponent("outside.md")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)
        let link = f.root.appendingPathComponent("topics/link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        await #expect(throws: VaultRepositoryError.self) { try await repository.load(relativePath: "topics/link.md") }
    }

    @Test("History is isolated per vault and capped at ten")
    func isolationAndRetention() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let firstID = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let first = try VaultRepository(vaultURL: f.root, identity: firstID, applicationSupportURL: f.support)

        var document = try await first.load(relativePath: "topics/note.md")
        for index in 0..<12 {
            let result = try await first.save(
                relativePath: "topics/note.md",
                changeSet: .body("Change \(index)\n"),
                expectedRevision: document.fingerprint
            )
            document = result.document
        }
        #expect((await first.recoveryEntries(relativePath: "topics/note.md")).count == 10)

        let secondID = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let second = try VaultRepository(vaultURL: f.root, identity: secondID, applicationSupportURL: f.support)
        #expect((await second.recoveryEntries(relativePath: "topics/note.md")).isEmpty)
    }

    @Test("A corrupt legacy recovery index blocks writes without replacing evidence")
    func corruptVersionIndexIsPreserved() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let versions = f.support
            .appendingPathComponent("Vaults", isDirectory: true)
            .appendingPathComponent(identity.id.uuidString, isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
        try FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
        let index = versions.appendingPathComponent("index.json")
        let corrupt = Data("{damaged version index".utf8)
        try corrupt.write(to: index)

        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        #expect(await repository.recoveryLedgerHealthDiagnostic() != nil)
        let original = try await repository.load(relativePath: "topics/note.md")
        await #expect(throws: VaultRepositoryError.self) {
            _ = try await repository.save(
                relativePath: original.relativePath,
                changeSet: .body("Must not be written\n"),
                expectedRevision: original.fingerprint
            )
        }

        #expect(try Data(contentsOf: index) == corrupt)
        #expect(try await repository.load(relativePath: original.relativePath).rawContent == original.rawContent)
    }

    @Test("A tampered recovery blob is rejected before use")
    func tamperedRecoveryBlobIsRejected() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        let original = try await repository.load(relativePath: "topics/note.md")
        let saved = try await repository.save(
            relativePath: original.relativePath,
            changeSet: .body("Changed\n"),
            expectedRevision: original.fingerprint
        )
        let recovery = try #require(await repository.recoveryEntries(relativePath: original.relativePath).first)
        let versionsRoot = f.support
            .appendingPathComponent("Vaults", isDirectory: true)
            .appendingPathComponent(identity.id.uuidString, isDirectory: true)
            .appendingPathComponent("recovery-v2", isDirectory: true)
            .appendingPathComponent("objects", isDirectory: true)
            .appendingPathComponent(recovery.id.uuidString.lowercased(), isDirectory: true)
        let blob = versionsRoot.appendingPathComponent("source.md")
        #expect(FileManager.default.fileExists(atPath: blob.path))
        try Data("tampered".utf8).write(to: blob, options: .atomic)

        await #expect(throws: VaultRepositoryError.self) {
            _ = try await repository.recoveryContent(entryID: recovery.id)
        }
        #expect(try await repository.load(relativePath: original.relativePath).rawContent == saved.document.rawContent)
    }

    @Test("Create and duplicate never replace an existing note")
    func createAndDuplicate() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(vaultURL: f.root, identity: identity, applicationSupportURL: f.support)

        let created = try await repository.create(
            relativePath: "new/Created.md",
            content: "# Created\r\n\r\nExact body\r\n"
        )
        #expect(created.newlineStyle == .crlf)
        #expect(try String(contentsOf: f.root.appendingPathComponent("new/Created.md"), encoding: .utf8) == created.rawContent)

        await #expect(throws: VaultRepositoryError.self) {
            try await repository.create(relativePath: "new/Created.md", content: "Replacement")
        }

        let duplicate = try await repository.duplicate(
            relativePath: "new/Created.md",
            to: "new/Created copy.md",
            expectedRevision: created.fingerprint
        )
        #expect(duplicate.rawContent == created.rawContent)
        #expect(duplicate.relativePath == "new/Created copy.md")
    }

    @Test("Import preserves exact source bytes at the vault root and resolves collisions")
    func importPreservesExactSourceAndResolvesCollisions() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        let source = Data([0xEF, 0xBB, 0xBF]) + Data(
            "---\r\nunknown: [source material\r\n---\r\n# Imported\r\n".utf8
        )

        let first = try await repository.importMarkdown(
            preferredFilename: "Imported.md",
            sourceData: source
        )
        let second = try await repository.importMarkdown(
            preferredFilename: "Imported.md",
            sourceData: source
        )

        #expect(first.relativePath == "Imported.md")
        #expect(second.relativePath == "Imported 2.md")
        #expect(try Data(contentsOf: f.root.appendingPathComponent(first.relativePath)) == source)
        #expect(try Data(contentsOf: f.root.appendingPathComponent(second.relativePath)) == source)
        #expect(!FileManager.default.fileExists(
            atPath: f.root.appendingPathComponent(".scholium/unclassified").path
        ))
    }

    @Test("Import rejects non-Markdown and non-UTF-8 source material")
    func importRejectsUnsupportedSource() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )

        await #expect(throws: DocumentImportError.self) {
            _ = try await repository.importMarkdown(
                preferredFilename: "Imported.txt",
                sourceData: Data("# Imported\n".utf8)
            )
        }
        await #expect(throws: DocumentImportError.self) {
            _ = try await repository.importMarkdown(
                preferredFilename: "Imported.md",
                sourceData: Data([0xFF, 0xFE, 0x00])
            )
        }
    }

    @Test("Folder inventory includes empty directories and one directory move preserves all contents")
    func folderInventoryAndMove() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        let empty = try await repository.createFolder(relativePath: "topics/Empty")
        #expect(empty.rawValue == "topics/Empty")
        #expect(try await repository.folderRelativePaths().contains(empty))

        let attachment = f.root.appendingPathComponent("topics/source.bin")
        let attachmentBytes = Data([0, 1, 2, 255])
        try attachmentBytes.write(to: attachment)
        let original = try await repository.load(relativePath: "topics/note.md")
        let source = try VaultRelativeFolderPath("topics")
        let destination = try VaultRelativeFolderPath("Renamed")
        let moved = try await repository.moveFolder(
            from: source,
            to: destination,
            expectedDocuments: [original.relativePath: original.fingerprint]
        )

        #expect(moved.documents.map(\.relativePath) == ["Renamed/note.md"])
        #expect(moved.documents[0].rawContent == original.rawContent)
        #expect(try Data(contentsOf: f.root.appendingPathComponent("Renamed/source.bin")) == attachmentBytes)
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("topics").path))
        #expect(try await repository.folderRelativePaths().contains(destination))
    }

    @Test("Folder move rejects an inventory changed outside Scholium")
    func folderMoveRejectsChangedInventory() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        let original = try await repository.load(relativePath: "topics/note.md")
        try "# Added externally\n".write(
            to: f.root.appendingPathComponent("topics/Added.md"),
            atomically: true,
            encoding: .utf8
        )

        await #expect(throws: VaultRepositoryError.self) {
            _ = try await repository.moveFolder(
                from: VaultRelativeFolderPath("topics"),
                to: VaultRelativeFolderPath("Renamed"),
                expectedDocuments: [original.relativePath: original.fingerprint]
            )
        }
        #expect(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("topics").path))
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("Renamed").path))
    }

    @Test("Creation rollback is revision checked and does not create history")
    func creationRollback() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        let relativePath = "Critiques/Created Critique.md"
        let created = try await repository.create(relativePath: relativePath, content: "# Critique\n")

        try await repository.removeCreatedFileForRollback(
            relativePath: relativePath,
            createdRevision: created.fingerprint
        )

        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent(relativePath).path))
        #expect((await repository.recoveryEntries(relativePath: relativePath)).isEmpty)
    }

    @Test("Creation rollback preserves a concurrently changed file")
    func creationRollbackConflict() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        let relativePath = "Critiques/Created Critique.md"
        let created = try await repository.create(relativePath: relativePath, content: "# Critique\n")
        let destination = f.root.appendingPathComponent(relativePath)
        try "External edit\n".write(to: destination, atomically: true, encoding: .utf8)

        await #expect(throws: VaultRepositoryError.self) {
            try await repository.removeCreatedFileForRollback(
                relativePath: relativePath,
                createdRevision: created.fingerprint
            )
        }

        #expect(try String(contentsOf: destination, encoding: .utf8) == "External edit\n")
    }

    @Test("Moves preserve bytes and Set Aside and Trash are locations")
    func moveSetAsideAndTrash() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(vaultURL: f.root, identity: identity, applicationSupportURL: f.support)
        let original = try await repository.load(relativePath: "topics/note.md")

        let moved = try await repository.move(
            relativePath: "topics/note.md",
            to: "Knowledge/Renamed.md",
            expectedRevision: original.fingerprint
        )
        #expect(moved.document.rawContent == original.rawContent)
        #expect(!FileManager.default.fileExists(atPath: f.note.path))

        let setAside = try await repository.setAside(
            relativePath: moved.relativePath,
            expectedRevision: moved.document.fingerprint
        )
        #expect(setAside.relativePath == "Set Aside/Knowledge/Renamed.md")

        let trashed = try await repository.moveToTrash(
            relativePath: setAside.relativePath,
            expectedRevision: setAside.document.fingerprint
        )
        #expect(trashed.relativePath == "Trash/Set Aside/Knowledge/Renamed.md")
        #expect(try await repository.load(relativePath: trashed.relativePath).rawContent == original.rawContent)
    }

    @Test("Confirmed moves preserve prewrite recovery at the destination path")
    func movedRecoveryLedger() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        let original = try await repository.load(relativePath: "topics/note.md")
        let saved = try await repository.save(
            relativePath: original.relativePath,
            changeSet: .body("Changed\n"),
            expectedRevision: original.fingerprint
        )
        let savedRecovery = try #require(
            await repository.recoveryEntries(relativePath: original.relativePath).first
        )
        let moved = try await repository.move(
            relativePath: saved.document.relativePath,
            to: "Knowledge/Renamed.md",
            expectedRevision: saved.document.fingerprint
        )

        try await repository.migrateRecoveryLedger(
            from: "topics/note.md",
            to: "Knowledge/Renamed.md"
        )

        #expect((await repository.recoveryEntries(relativePath: "topics/note.md")).isEmpty)
        let recoveryEntries = await repository.recoveryEntries(relativePath: "Knowledge/Renamed.md")
        #expect(recoveryEntries.count == 2)
        #expect(try await repository.recoveryContent(entryID: savedRecovery.id) == original.rawContent)
        #expect(try await repository.load(relativePath: "Knowledge/Renamed.md").rawContent == moved.document.rawContent)

        // Retrying after an interrupted caller is idempotent.
        try await repository.migrateRecoveryLedger(
            from: "topics/note.md",
            to: "Knowledge/Renamed.md"
        )
        #expect((await repository.recoveryEntries(relativePath: "Knowledge/Renamed.md")).count == 2)
    }

    @Test("Permanent deletion is revision checked and purges repository recovery bytes")
    func permanentDeletion() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(vaultURL: f.root, identity: identity, applicationSupportURL: f.support)
        let original = try await repository.load(relativePath: "topics/note.md")

        let deletion = try await repository.deletePermanently(
            relativePath: "topics/note.md",
            expectedRevision: original.fingerprint
        )
        #expect(!FileManager.default.fileExists(atPath: f.note.path))
        #expect(deletion.fingerprint == original.fingerprint)
        #expect(await repository.recoveryEntries(relativePath: "topics/note.md").isEmpty)
    }

    @Test("Prepared deletion never replaces a concurrently recreated path and retains recovery bytes")
    func preparedDeletionConflictRetainsRecovery() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(vaultURL: f.root, identity: identity, applicationSupportURL: f.support)
        let original = try await repository.load(relativePath: "topics/note.md")
        let prepared = try await repository.preparePermanentDeletion(
            relativePath: original.relativePath,
            expectedRevision: original.fingerprint
        )

        try await repository.applyPreparedPermanentDeletion(prepared)
        try FileManager.default.createDirectory(
            at: f.note.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "Concurrent replacement\n".write(to: f.note, atomically: true, encoding: .utf8)
        await #expect(throws: VaultRepositoryError.self) {
            try await repository.rollbackPreparedPermanentDeletion(prepared)
        }

        #expect(try String(contentsOf: f.note, encoding: .utf8) == "Concurrent replacement\n")
        #expect(await repository.recoveryEntries(relativePath: original.relativePath).contains {
            $0.id == prepared.recoveryReference.id && $0.fingerprint == original.fingerprint
        })

        try FileManager.default.removeItem(at: f.note)
        try await repository.rollbackPreparedPermanentDeletion(prepared)
        #expect(try String(contentsOf: f.note, encoding: .utf8) == original.rawContent)
        #expect(await repository.recoveryEntries(relativePath: original.relativePath).isEmpty)
    }

    @Test("Lifecycle paths reject traversal, non-Markdown targets, and symlink parents")
    func lifecyclePathSafety() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(vaultURL: f.root, identity: identity, applicationSupportURL: f.support)

        await #expect(throws: VaultRepositoryError.self) {
            try await repository.create(relativePath: "../escape.md", content: "escape")
        }
        await #expect(throws: VaultRepositoryError.self) {
            try await repository.create(relativePath: "note.txt", content: "text")
        }

        let outside = f.root.deletingLastPathComponent().appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let linkedDirectory = f.root.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: outside)
        await #expect(throws: VaultRepositoryError.self) {
            try await repository.create(relativePath: "linked/escape.md", content: "escape")
        }
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("escape.md").path))
    }

    @Test("Paper profile saves keep time in app history instead of injecting YAML")
    func paperTimestampIsAppOwned() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("vault", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        let note = root.appendingPathComponent("papers/legacy.md")
        try FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\ntitle: Legacy\nmodified: 2025-01-01\n---\nOriginal\n".write(
            to: note,
            atomically: true,
            encoding: .utf8
        )
        let identity = VaultIdentity(id: UUID(), canonicalPath: root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: root,
            identity: identity,
            applicationSupportURL: support,
            vaultRole: .sourceCorpus
        )
        let original = try await repository.load(relativePath: "papers/legacy.md")

        _ = try await repository.save(
            relativePath: "papers/legacy.md",
            changeSet: .body("Changed\n"),
            expectedRevision: original.fingerprint
        )
        let content = try String(contentsOf: note, encoding: .utf8)

        #expect(content.contains("modified: 2025-01-01"))
        #expect(content.contains("updated: ") == false)
        #expect(content.contains("analysis_updated_at:") == false)
    }

    @Test("Paper profile preserves an existing legacy timestamp without refreshing it")
    func legacyPaperTimestampCompatibility() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("vault", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        let note = root.appendingPathComponent("papers/legacy.md")
        try FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\ntitle: Legacy\nanalysis_updated_at: 2025-01-01\n---\nOriginal\n".write(
            to: note,
            atomically: true,
            encoding: .utf8
        )
        let identity = VaultIdentity(id: UUID(), canonicalPath: root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: root,
            identity: identity,
            applicationSupportURL: support,
            vaultRole: .sourceCorpus
        )
        let original = try await repository.load(relativePath: "papers/legacy.md")

        _ = try await repository.save(
            relativePath: "papers/legacy.md",
            changeSet: .body("Changed\n"),
            expectedRevision: original.fingerprint
        )
        let content = try String(contentsOf: note, encoding: .utf8)

        #expect(content.contains("analysis_updated_at: 2025-01-01"))
        #expect(content.contains("\nupdated:") == false)
    }

    @Test("Topic and Work saves do not inject workflow review metadata")
    func nonSyntheticWorkflowMetadata() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("vault", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let topic = root.appendingPathComponent("Concept.md")
        try "# Concept\n".write(to: topic, atomically: true, encoding: .utf8)
        let identity = VaultIdentity(id: UUID(), canonicalPath: root.path, bookmarkData: nil)
        let topicRepository = try VaultRepository(
            vaultURL: root,
            identity: identity,
            applicationSupportURL: support,
            vaultRole: .topicKnowledge
        )
        let topicDocument = try await topicRepository.load(relativePath: "Concept.md")
        _ = try await topicRepository.save(
            relativePath: "Concept.md",
            changeSet: .body("# Revised concept\n"),
            expectedRevision: topicDocument.fingerprint
        )
        #expect(try String(contentsOf: topic, encoding: .utf8) == "# Revised concept\n")

        let dossier = root.appendingPathComponent("ARG-001.md")
        let original = "---\nnote_type: argument_dossier\nlast_reviewed: 2026-07-01\nreview_status: needs_researcher_review\n---\nOpen\n"
        try original.write(to: dossier, atomically: true, encoding: .utf8)
        let workRepository = try VaultRepository(
            vaultURL: root,
            identity: identity,
            applicationSupportURL: support,
            vaultRole: .draftProject
        )
        let dossierDocument = try await workRepository.load(relativePath: "ARG-001.md")
        _ = try await workRepository.save(
            relativePath: "ARG-001.md",
            changeSet: .body("Revised\n"),
            expectedRevision: dossierDocument.fingerprint
        )
        let result = try String(contentsOf: dossier, encoding: .utf8)
        #expect(result.contains("last_reviewed: 2026-07-01"))
        #expect(result.contains("review_status: needs_researcher_review"))
        #expect(result.contains("modified:") == false)
    }
}
