import Darwin
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("File Provider and process interruption fixtures", .serialized)
struct FileProviderProcessInterruptionFixtureTests {
    enum InterruptionPoint: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case unstaged
        case staged
        case replaced
        case replacedExternal
        case acknowledged

        var testDescription: String {
            switch self {
            case .unstaged: "input held only in process memory"
            case .staged: "before canonical replacement"
            case .replaced: "after canonical replacement"
            case .replacedExternal: "after replacing a late external revision"
            case .acknowledged: "after an acknowledged source commit"
            }
        }
    }

    @Test("A coordinated provider conflict leaves no successful-save history")
    func coordinatedProviderConflictLeavesNoHistory() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var repository: VaultRepository? = try fixture.repository()
        let presenter = ProviderMutationPresenter(
            url: fixture.note,
            mutation: {
                try fixture.externalData.write(to: fixture.note, options: .atomic)
            }
        )

        NSFileCoordinator.addFilePresenter(presenter)
        do {
            defer { NSFileCoordinator.removeFilePresenter(presenter) }
            let activeRepository = try #require(repository)
            let loaded = try await activeRepository.load(
                relativePath: fixture.relativePath
            )
            await #expect {
                _ = try await activeRepository.save(
                    relativePath: fixture.relativePath,
                    changeSet: .exactContent(fixture.candidate),
                    expectedRevision: loaded.fingerprint
                )
            } throws: { error in
                guard case VaultRepositoryError.conflict = error else { return false }
                return true
            }

            #expect(presenter.writerRequestCount == 1)
            #expect(presenter.mutationErrorDescription == nil)
            #expect(try Data(contentsOf: fixture.note) == fixture.externalData)
            let pending = try fixture.pendingMutationDirectories()
            #expect(pending.isEmpty)
        }

        repository = nil
        let reopened = try fixture.repository()
        #expect(try fixture.stagedFiles().isEmpty)
        #expect(try fixture.pendingMutationDirectories().isEmpty)
        #expect(try await reopened.load(relativePath: fixture.relativePath).rawContent == fixture.external)
        #expect(try await reopened.interruptedSaveRecoveries().isEmpty)
    }

    @Test(
        "SIGKILL leaves one canonical revision and exact restart recovery",
        arguments: InterruptionPoint.allCases
    )
    func processKillRecoversDeterministically(_ point: InterruptionPoint) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let rootPath = fixture.root.path
        let supportPath = fixture.support.path
        let identityString = fixture.identity.id.uuidString
        let relativePath = fixture.relativePath
        let candidate = fixture.candidate
        let pointRawValue = point.rawValue
        let external = fixture.external

        await #expect(processExitsWith: .signal(SIGKILL)) {
            [
                rootPath = rootPath as String,
                supportPath = supportPath as String,
                identityString = identityString as String,
                relativePath = relativePath as String,
                candidate = candidate as String,
                pointRawValue = pointRawValue as String,
                external = external as String,
            ] in
            let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            let support = URL(fileURLWithPath: supportPath, isDirectory: true)
            guard let point = InterruptionPoint(rawValue: pointRawValue) else { throw CocoaError(.fileReadCorruptFile) }
            let killAfterReplacement = point == .replaced || point == .replacedExternal
            let injectExternal = point == .replacedExternal
            let unstaged = point == .unstaged
            let acknowledged = point == .acknowledged
            let markerPath = root.deletingLastPathComponent().appendingPathComponent("owned-writer.json").path
            let identity = VaultIdentity(
                id: UUID(uuidString: identityString)!,
                canonicalPath: root.path,
                bookmarkData: nil
            )
            let interruptionPhase: VaultMutationPhase = killAfterReplacement ? .replaced : .staged
            let repository = try VaultRepository(
                vaultURL: root,
                identity: identity,
                applicationSupportURL: support,
                mutationHooks: VaultMutationHooks(didReach: { phase in
                    if injectExternal, phase == .replacing {
                        try Data(external.utf8).write(to: root.appendingPathComponent(relativePath), options: .atomic)
                    }
                    guard !unstaged, !acknowledged, phase == interruptionPhase else { return }
                    try Self.terminateOwnedWriter(markerPath: markerPath, phase: killAfterReplacement ? "replaced" : "staged")
                })
            )
            let loaded = try await repository.load(relativePath: relativePath)
            if unstaged {
                let buffer = try loaded.applying(.source(candidate), timestampKey: nil)
                guard buffer == candidate else { throw CocoaError(.fileReadCorruptFile) }
                try Self.terminateOwnedWriter(markerPath: markerPath, phase: "unstaged")
            }
            let saved = try await repository.save(
                relativePath: relativePath,
                changeSet: .exactContent(candidate),
                expectedRevision: loaded.fingerprint
            )
            if acknowledged {
                guard saved.document.sourceBytes == Data(candidate.utf8) else { throw CocoaError(.fileReadCorruptFile) }
                try Self.terminateOwnedWriter(markerPath: markerPath, phase: "acknowledged")
            }
            _exit(0)
        }

        try fixture.verifyOwnedWriterTermination()

        let expectedCanonical =
            point == .staged || point == .unstaged
            ? fixture.original
            : fixture.candidateData
        #expect(try Data(contentsOf: fixture.note) == expectedCanonical)
        let stagedFiles = try fixture.stagedFiles()
        if point == .staged {
            #expect(stagedFiles.count == 1)
            #expect(try Data(contentsOf: stagedFiles[0]) == fixture.candidateData)
        } else {
            #expect(stagedFiles.isEmpty)
        }

        let reopened = try fixture.repository()
        let reopenedDocument = try await reopened.load(relativePath: fixture.relativePath)
        let expectedCanonicalContent =
            point == .staged || point == .unstaged
            ? fixture.originalContent
            : fixture.candidate
        #expect(reopenedDocument.rawContent == expectedCanonicalContent)
        let pending = try fixture.pendingMutationDirectories()
        for _ in 0..<3 {
            let repeated = try fixture.repository()
            #expect(try await repeated.load(relativePath: fixture.relativePath).sourceBytes == expectedCanonical)
            #expect(try await repeated.interruptedSaveRecoveries().count == (point == .staged || point == .replacedExternal ? 1 : 0))
        }
        if point == .staged {
            #expect(pending.count == 1)
            #expect(
                try Data(contentsOf: pending[0].appendingPathComponent("candidate.md"))
                    == fixture.candidateData
            )
            #expect(
                await reopened.recoveryLedgerHealthDiagnostic()?.contains(
                    "candidate bytes remain"
                ) == true
            )
            let retained = try #require(
                try await reopened.interruptedSaveRecoveries().first
            )
            #expect(retained.sourceState == .expectedRevision)
            #expect(retained.expectedRevision == reopenedDocument.fingerprint)
            #expect(retained.candidateRevision == DocumentFingerprint(data: fixture.candidateData))
            let content = try await reopened.interruptedSaveRecoveryContent(retained)
            #expect(content.exactSource == fixture.candidate)
            #expect(content.fingerprint == retained.candidateRevision)
            let location = try await reopened.prepareInterruptedSaveRecoveryLocation(retained)
            #expect(try Data(contentsOf: location) == fixture.candidateData)

            let wrongVault = InterruptedSaveRecovery(
                id: InterruptedSaveRecoveryID(
                    vaultID: UUID(),
                    transactionID: retained.id.transactionID
                ),
                relativePath: retained.relativePath,
                expectedRevision: retained.expectedRevision,
                candidateRevision: retained.candidateRevision,
                createdAt: retained.createdAt,
                retainedReason: retained.retainedReason,
                sourceState: retained.sourceState
            )
            await #expect(throws: VaultRepositoryError.self) {
                _ = try await reopened.interruptedSaveRecoveryContent(wrongVault)
            }
            let substitutedPath = InterruptedSaveRecovery(
                id: retained.id,
                relativePath: "topics/other.md",
                expectedRevision: retained.expectedRevision,
                candidateRevision: retained.candidateRevision,
                createdAt: retained.createdAt,
                retainedReason: retained.retainedReason,
                sourceState: retained.sourceState
            )
            await #expect(throws: VaultRepositoryError.self) {
                _ = try await reopened.restoreInterruptedSaveRecovery(substitutedPath)
            }
            #expect(try Data(contentsOf: fixture.note) == fixture.original)

            // A later external edit must survive a stale restoration request.
            try fixture.externalData.write(to: fixture.note, options: .atomic)
            await #expect(throws: VaultRepositoryError.self) {
                _ = try await reopened.restoreInterruptedSaveRecovery(retained)
            }
            #expect(try Data(contentsOf: fixture.note) == fixture.externalData)
            #expect(try await reopened.interruptedSaveRecoveryContent(retained).exactSource == fixture.candidate)
            try fixture.original.write(to: fixture.note, options: .atomic)
            let restored = try await reopened.restoreInterruptedSaveRecovery(retained)
            #expect(restored.didReplaceSource)
            #expect(restored.document.rawContent == fixture.candidate)
            #expect(try Data(contentsOf: fixture.note) == fixture.candidateData)
            #expect(try await reopened.interruptedSaveRecoveries().isEmpty)
            await #expect(throws: VaultRepositoryError.self) {
                _ = try await reopened.restoreInterruptedSaveRecovery(retained)
            }
            #expect(try Data(contentsOf: fixture.note) == fixture.candidateData)
        } else if point == .replacedExternal {
            #expect(pending.count == 1)
            let retained = try #require(try await reopened.interruptedSaveRecoveries().first)
            #expect(try await reopened.interruptedSaveRecoveryContent(retained).exactSource == fixture.external)
            #expect(retained.expectedRevision == DocumentFingerprint(data: fixture.candidateData))
            let restored = try await reopened.restoreInterruptedSaveRecovery(retained)
            #expect(restored.didReplaceSource)
            #expect(try Data(contentsOf: fixture.note) == fixture.externalData)
        } else {
            #expect(pending.isEmpty)
            #expect(await reopened.recoveryLedgerHealthDiagnostic() == nil)
            #expect(try await reopened.interruptedSaveRecoveries().isEmpty)
        }
        #expect(
            try await reopened.markdownRelativePaths()
                == [fixture.relativePath]
        )

        let followupStartingDocument = try await reopened.load(
            relativePath: fixture.relativePath
        )
        let followup = "# Saved after restart\n"
        _ = try await reopened.save(
            relativePath: fixture.relativePath,
            changeSet: .exactContent(followup),
            expectedRevision: followupStartingDocument.fingerprint
        )
        #expect(try Data(contentsOf: fixture.note) == Data(followup.utf8))
    }

    @Test("SIGKILL before manifest publication leaves verified candidates accessible")
    func processKillDuringManifestPreparation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let repository = try fixture.repository()
        let storage = await repository.storageURL
        let ledger = try PrewriteRecoveryLedger(storageURL: storage)
        let transaction = try ledger.beginMutation(
            relativePath: fixture.relativePath, expected: fixture.original, candidate: fixture.candidateData)
        try ledger.retainMutation(transaction, reason: "Earlier interrupted write")
        let storagePath = storage.path
        let rootPath = fixture.root.path
        let markerPath = fixture.base.appendingPathComponent("owned-writer.json").path
        await #expect(processExitsWith: .signal(SIGKILL)) {
            [storagePath = storagePath as String, rootPath = rootPath as String, markerPath = markerPath as String] in
            let manager = InterruptedLedgerFileManager(markerPath: markerPath)
            let interrupted = try PrewriteRecoveryLedger(
                storageURL: URL(fileURLWithPath: storagePath), vaultURL: URL(fileURLWithPath: rootPath), fileManager: manager)
            _ = try interrupted.beginMutation(relativePath: "Unpublished.md", expected: Data("before".utf8), candidate: Data("never published".utf8))
            _exit(0)
        }
        try fixture.verifyOwnedWriterTermination()
        #expect(try fixture.pendingMutationDirectories().count == 2)
        for _ in 0..<3 {
            let reopened = try fixture.repository()
            let retained = try #require(try await reopened.interruptedSaveRecoveries().first)
            #expect(retained.id.transactionID == transaction.id)
            #expect(try await reopened.interruptedSaveRecoveries().count == 1)
            #expect(try await reopened.interruptedSaveRecoveryContent(retained).exactSource == fixture.candidate)
            #expect(await reopened.recoveryLedgerHealthDiagnostic()?.contains("no manifest") == true)
            #expect(try Data(contentsOf: fixture.note) == fixture.original)
        }
        let reopened = try fixture.repository()
        let retained = try #require(try await reopened.interruptedSaveRecoveries().first)
        _ = try await reopened.restoreInterruptedSaveRecovery(retained)
        #expect(try Data(contentsOf: fixture.note) == fixture.candidateData)
        #expect(try await reopened.interruptedSaveRecoveries().isEmpty)
        #expect(try fixture.pendingMutationDirectories().count == 1)
        #expect(try await reopened.markdownRelativePaths() == [fixture.relativePath])
    }

    private static func terminateOwnedWriter(markerPath: String, phase: String) throws -> Never {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard ExitTest.current != nil,
            markerPath.hasPrefix(repositoryRoot.appendingPathComponent(".build/file-provider-process-interruption").path + "/")
        else { throw CocoaError(.fileWriteNoPermission) }
        let identity: [String: Any] = ["pid": getpid(), "parent_pid": getppid(), "executable": executable, "fixture_marker": markerPath, "phase": phase]
        try JSONSerialization.data(withJSONObject: identity, options: .sortedKeys).write(to: URL(fileURLWithPath: markerPath), options: .atomic)
        guard kill(getpid(), SIGKILL) == 0 else { throw POSIXError(.EPERM) }
        // Let the kernel deliver SIGKILL. An immediate _exit can win that race
        // and only prove an exit code, even though no Swift cleanup ran.
        while true { _ = pause() }
    }

    private final class InterruptedLedgerFileManager: FileManager, @unchecked Sendable {
        let markerPath: String
        init(markerPath: String) {
            self.markerPath = markerPath
            super.init()
        }
        override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]? = nil) throws {
            try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
            if url.deletingLastPathComponent().lastPathComponent == "save-transactions-v2", UUID(uuidString: url.lastPathComponent) != nil {
                try terminateOwnedWriter(markerPath: markerPath, phase: "before manifest publication")
            }
        }
    }

    private final class ProviderMutationPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
        let presentedItemURL: URL?
        let presentedItemOperationQueue: OperationQueue
        private let mutation: @Sendable () throws -> Void
        private let lock = NSLock()
        private var storedWriterRequestCount = 0
        private var storedMutationErrorDescription: String?

        init(url: URL, mutation: @escaping @Sendable () throws -> Void) {
            presentedItemURL = url
            presentedItemOperationQueue = OperationQueue()
            presentedItemOperationQueue.maxConcurrentOperationCount = 1
            presentedItemOperationQueue.qualityOfService = .userInitiated
            self.mutation = mutation
        }

        func relinquishPresentedItem(
            toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void
        ) {
            lock.lock()
            storedWriterRequestCount += 1
            lock.unlock()
            do {
                try mutation()
            } catch {
                lock.lock()
                storedMutationErrorDescription = error.localizedDescription
                lock.unlock()
            }
            writer(nil)
        }

        var writerRequestCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return storedWriterRequestCount
        }

        var mutationErrorDescription: String? {
            lock.lock()
            defer { lock.unlock() }
            return storedMutationErrorDescription
        }
    }

    private final class Fixture: @unchecked Sendable {
        let base: URL
        let root: URL
        let support: URL
        let note: URL
        let identity: VaultIdentity
        let relativePath = "topics/note.md"
        let original = Data([0xEF, 0xBB, 0xBF] + Array("# Original\r\n".utf8))
        let candidate = "\u{FEFF}# Candidate\r\n\r\n论点 e\u{301} 🦉"
        let external = "# Provider revision\n"

        var candidateData: Data { Data(candidate.utf8) }
        var externalData: Data { Data(external.utf8) }
        var originalContent: String {
            NoteDocument.decodeUTF8PreservingBOM(original)!
        }

        init() throws {
            let repositoryRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            base =
                repositoryRoot
                .appendingPathComponent(
                    ".build/file-provider-process-interruption",
                    isDirectory: true
                )
                .appendingPathComponent(
                    UUID().uuidString.lowercased(),
                    isDirectory: true
                )
            root = base.appendingPathComponent("vault", isDirectory: true)
            support = base.appendingPathComponent("support", isDirectory: true)
            note = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: note.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try original.write(to: note)
            identity = VaultIdentity(
                id: UUID(),
                canonicalPath: root.path,
                bookmarkData: nil
            )
        }

        func repository(hooks: VaultMutationHooks = .none) throws -> VaultRepository {
            try VaultRepository(
                vaultURL: root,
                identity: identity,
                applicationSupportURL: support,
                mutationHooks: hooks
            )
        }

        func pendingMutationDirectories() throws -> [URL] {
            let directory =
                support
                .appendingPathComponent("Vaults", isDirectory: true)
                .appendingPathComponent(identity.id.uuidString, isDirectory: true)
                .appendingPathComponent("save-transactions-v2", isDirectory: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey]
            ).filter { url in
                guard url.lastPathComponent != ".transactions.lock",
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                else {
                    return false
                }
                return values.isDirectory == true
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        func stagedFiles() throws -> [URL] {
            try FileManager.default.contentsOfDirectory(
                at: note.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasPrefix(".scholium-replacement-") }
        }

        func verifyOwnedWriterTermination() throws {
            let marker = try Data(contentsOf: base.appendingPathComponent("owned-writer.json"))
            let identity = try #require(JSONSerialization.jsonObject(with: marker) as? [String: Any])
            #expect((identity["pid"] as? Int) != Int(getpid()))
            #expect((identity["pid"] as? Int ?? 0) > 0)
            print("Owned interruption writer: \(String(decoding: marker, as: UTF8.self))")
        }

        func remove() {
            try? FileManager.default.removeItem(at: base)
        }
    }
}
