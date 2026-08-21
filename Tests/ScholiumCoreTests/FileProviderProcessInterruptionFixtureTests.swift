import Darwin
import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("File Provider and process interruption fixtures", .serialized)
struct FileProviderProcessInterruptionFixtureTests {
    enum InterruptionPoint: CaseIterable, Sendable, CustomTestStringConvertible {
        case staged
        case replaced

        var testDescription: String {
            switch self {
            case .staged: "before canonical replacement"
            case .replaced: "after canonical replacement"
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
        let killAfterReplacement = point == .replaced

        await #expect(processExitsWith: .failure) {
            [
                rootPath = rootPath as String,
                supportPath = supportPath as String,
                identityString = identityString as String,
                relativePath = relativePath as String,
                candidate = candidate as String,
                killAfterReplacement = killAfterReplacement as Bool,
            ] in
            let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            let support = URL(fileURLWithPath: supportPath, isDirectory: true)
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
                    guard phase == interruptionPhase else { return }
                    _ = kill(getpid(), SIGKILL)
                    _exit(137)
                })
            )
            let loaded = try await repository.load(relativePath: relativePath)
            _ = try await repository.save(
                relativePath: relativePath,
                changeSet: .exactContent(candidate),
                expectedRevision: loaded.fingerprint
            )
            _exit(0)
        }

        let expectedCanonical = point == .staged
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
        let expectedCanonicalContent = point == .staged
            ? fixture.originalContent
            : fixture.candidate
        #expect(reopenedDocument.rawContent == expectedCanonicalContent)
        let pending = try fixture.pendingMutationDirectories()
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

            let restored = try await reopened.restoreInterruptedSaveRecovery(retained)
            #expect(restored.didReplaceSource)
            #expect(restored.document.rawContent == fixture.candidate)
            #expect(try Data(contentsOf: fixture.note) == fixture.candidateData)
            #expect(try await reopened.interruptedSaveRecoveries().isEmpty)
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
        let candidate = "# Candidate\n"
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
            base = repositoryRoot
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
            let directory = support
                .appendingPathComponent("Vaults", isDirectory: true)
                .appendingPathComponent(identity.id.uuidString, isDirectory: true)
                .appendingPathComponent("save-transactions-v1", isDirectory: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey]
            ).filter { url in
                guard url.lastPathComponent != ".transactions.lock",
                      let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) else {
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

        func remove() {
            try? FileManager.default.removeItem(at: base)
        }
    }
}
