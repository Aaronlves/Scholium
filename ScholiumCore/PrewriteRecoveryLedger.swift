import Darwin
import Foundation
import ScholiumContracts

/// Core-only durable evidence for source replacements whose final canonical
/// state has not yet been proven. Completed saves leave no record here.
final class PrewriteRecoveryLedger {
    struct MutationTransaction: Codable, Hashable, Sendable {
        static let currentSchemaVersion = 2

        let schemaVersion: Int
        let id: UUID
        let relativePath: String
        let expected: DocumentFingerprint
        let candidate: DocumentFingerprint
        let createdAt: Date
        var retainedReason: String?
        var replacementReconciled: Bool
        var displaced: DocumentFingerprint?

        var recoveryExpected: DocumentFingerprint { displaced == nil ? expected : candidate }
        var recoveryCandidate: DocumentFingerprint { displaced ?? candidate }
        var recoveryFileName: String { displaced == nil ? "candidate.md" : "displaced.md" }
        var backupPath: MarkdownRelativePath {
            get throws {
                let path = try MarkdownRelativePath(relativePath)
                let parent = path.components.dropLast().joined(separator: "/")
                let name = VaultMutationCoordinator.replacementBackupName(id)
                return try MarkdownRelativePath(parent.isEmpty ? name : "\(parent)/\(name)")
            }
        }

        init(
            id: UUID = UUID(),
            relativePath: String,
            expected: DocumentFingerprint,
            candidate: DocumentFingerprint,
            createdAt: Date = Date(),
            retainedReason: String? = nil,
            replacementReconciled: Bool = false,
            displaced: DocumentFingerprint? = nil
        ) {
            schemaVersion = Self.currentSchemaVersion
            self.id = id
            self.relativePath = relativePath
            self.expected = expected
            self.candidate = candidate
            self.createdAt = Date(
                timeIntervalSince1970: floor(createdAt.timeIntervalSince1970)
            )
            self.retainedReason = retainedReason
            self.replacementReconciled = replacementReconciled
            self.displaced = displaced
        }
    }

    private struct VerifiedMutation {
        let transaction: MutationTransaction
        let candidate: Data
    }

    private let rootURL: URL
    private let storage: SecureRecordDirectory
    private let byteAccess: VaultDescriptorAccess
    private let lock: AdvisoryFileLock
    private let fileManager: FileManager
    private(set) var healthDiagnostic: String?

    init(
        storageURL: URL,
        vaultURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
        rootURL = storageURL.appendingPathComponent("save-transactions-v2", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        storage = SecureRecordDirectory(
            trustedRootURL: storageURL,
            components: ["save-transactions-v2"],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: .max
        )
        byteAccess = try VaultDescriptorAccess(rootURL: rootURL)
        do {
            lock = try AdvisoryFileLock(directory: storage, fileName: ".transactions.lock")
            try lock.withExclusiveLock {
                try storage.removeAbandonedStagingFiles(in: [nil])
            }
        } catch {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "The interrupted-save transaction store is unavailable: \(error.localizedDescription)"
            )
        }
        if let vaultURL {
            replayMutationTransactions(vaultURL: vaultURL)
        }
    }

    func beginMutation(
        relativePath: String,
        expected: Data,
        candidate: Data
    ) throws -> MutationTransaction {
        let path = try MarkdownRelativePath(relativePath)
        let transaction = MutationTransaction(
            relativePath: path.rawValue,
            expected: DocumentFingerprint(data: expected),
            candidate: DocumentFingerprint(data: candidate)
        )
        return try locked {
            let directory = transactionDirectory(transaction.id)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
            do {
                let expectedURL = directory.appendingPathComponent("expected.md")
                let candidateURL = directory.appendingPathComponent("candidate.md")
                try expected.write(to: expectedURL, options: .atomic)
                try candidate.write(to: candidateURL, options: .atomic)
                guard
                    DocumentFingerprint(data: try Data(contentsOf: expectedURL))
                        == transaction.expected,
                    DocumentFingerprint(data: try Data(contentsOf: candidateURL))
                        == transaction.candidate
                else {
                    throw VaultRepositoryError.recoveryLedgerUnavailable(
                        "An interrupted-save transaction failed exact-byte readback."
                    )
                }
                try writeManifest(transaction)
                return transaction
            } catch {
                try? fileManager.removeItem(at: directory)
                throw error
            }
        }
    }

    func completeMutation(_ transaction: MutationTransaction, sourceAccess: VaultDescriptorAccess? = nil) throws {
        try locked {
            let verified = try verifiedMutation(
                matching: transaction,
                requiresRetention: false
            )
            if let sourceAccess,
                try sourceAccess.presence(verified.transaction.backupPath) != .absent
            {
                // Keep the durable cleanup address without turning a verified
                // ordinary save into another source write or visible failure.
                return
            }
            try fileManager.removeItem(at: transactionDirectory(verified.transaction.id))
        }
    }

    /// Capture the system-preserved original before either backup or transaction
    /// cleanup. A late external revision becomes the existing Recovery candidate.
    func reconcileReplacementBackup(
        _ transaction: MutationTransaction,
        access: VaultDescriptorAccess,
        required: Bool = false
    ) throws -> MutationTransaction {
        try locked {
            try reconcileReplacementBackupLocked(transaction, access: access, required: required)
        }
    }

    private func reconcileReplacementBackupLocked(
        _ reference: MutationTransaction,
        access: VaultDescriptorAccess,
        required: Bool
    ) throws -> MutationTransaction {
        var transaction = try verifiedMutation(matching: reference, requiresRetention: false).transaction
        let path = try transaction.backupPath
        let data: Data
        do {
            data = try access.read(path)
        } catch VaultRepositoryError.fileDoesNotExist {
            guard !required || transaction.replacementReconciled else {
                throw VaultRepositoryError.recoveryLedgerUnavailable("The replaced source backup could not be verified.")
            }
            return transaction
        }
        let fingerprint = DocumentFingerprint(data: data)
        if fingerprint != transaction.expected {
            if let displaced = transaction.displaced, displaced != fingerprint {
                throw VaultRepositoryError.recoveryLedgerUnavailable("The retained external source changed; its backup remains untouched.")
            }
            let displacedPath = try MarkdownRelativePath("\(transaction.id.uuidString.lowercased())/displaced.md")
            if try byteAccess.presence(displacedPath) == .absent {
                // Reuse exclusive exact-byte creation; JSON record storage is
                // deliberately not a Markdown-file writer.
                try VaultMutationCoordinator(
                    resolver: VaultPathResolver(rootURL: rootURL),
                    descriptorAccess: byteAccess
                ).create(path: displacedPath, data: data)
            }
            guard try byteAccess.read(displacedPath) == data else {
                throw VaultRepositoryError.recoveryLedgerUnavailable("The external source could not be retained exactly.")
            }
            transaction.displaced = fingerprint
            transaction.retainedReason =
                "Another program changed this Note during saving. Its displaced source is retained here; the attempted Scholium source remains in candidate.md. Inspect both before restoring."
        }
        transaction.replacementReconciled = true
        try writeManifest(transaction)
        if let reason = transaction.retainedReason {
            healthDiagnostic = "A save transaction requires researcher-visible recovery: \(reason)"
        }
        // The exact bytes are now durable. Remove only the same checked backup.
        try access.withOpenRegularFile(path) { descriptor, parent, name, status in
            guard try VaultDescriptorAccess.readAll(from: descriptor) == data,
                try VaultDescriptorAccess.identity(name: name, parentDescriptor: parent) == VaultDescriptorAccess.FileIdentity(status)
            else { throw VaultRepositoryError.commitUncertain("The save backup changed before cleanup.") }
            try access.verifyCurrentParent(path, retainedDescriptor: parent)
            _ = unlinkat(parent, name, 0)
        }
        return transaction
    }

    func retainMutation(_ transaction: MutationTransaction, reason: String) throws {
        try locked {
            _ = try verifiedMutation(matching: transaction, requiresRetention: false)
            try retainMutationLocked(transaction, reason: reason)
        }
    }

    func retainedMutations() throws -> [MutationTransaction] {
        try locked {
            try pendingMutationsLocked().compactMap { transaction in
                guard transaction.retainedReason != nil else { return nil }
                return try verifiedMutation(matching: transaction).transaction
            }
        }
    }

    func retainedMutation(id: UUID) throws -> MutationTransaction {
        try locked {
            guard let transaction = try pendingMutationsLocked().first(where: { $0.id == id }),
                transaction.retainedReason != nil
            else {
                throw VaultRepositoryError.recoveryEntryNotFound(id)
            }
            return try verifiedMutation(matching: transaction).transaction
        }
    }

    func candidateData(for transaction: MutationTransaction) throws -> Data {
        try locked { try verifiedMutation(matching: transaction).candidate }
    }

    func retainedMutationDirectory(for transaction: MutationTransaction) throws -> URL {
        try locked {
            _ = try verifiedMutation(matching: transaction)
            return transactionDirectory(transaction.id)
        }
    }

    func remapRetainedTransactions(from source: String, to destination: String) throws {
        _ = try MarkdownRelativePath(source)
        _ = try MarkdownRelativePath(destination)
        try locked {
            let pending = try pendingMutationsLocked()
            guard pending.contains(where: { $0.relativePath == source }) else { return }
            guard !pending.contains(where: { $0.relativePath == destination }) else {
                throw VaultRepositoryError.recoveryPathConflict(destination)
            }
            for transaction in pending where transaction.relativePath == source {
                let replacement = MutationTransaction(
                    id: transaction.id,
                    relativePath: destination,
                    expected: transaction.expected,
                    candidate: transaction.candidate,
                    createdAt: transaction.createdAt,
                    retainedReason: transaction.retainedReason,
                    replacementReconciled: transaction.replacementReconciled,
                    displaced: transaction.displaced
                )
                try writeManifest(replacement)
            }
        }
    }

    private func replayMutationTransactions(vaultURL: URL) {
        let access: VaultDescriptorAccess
        do {
            access = try VaultDescriptorAccess(
                rootURL: vaultURL.resolvingSymlinksInPath().standardizedFileURL
            )
        } catch {
            healthDiagnostic = "Interrupted saves remain retained because the authorized vault root is unavailable."
            return
        }
        do {
            try locked {
                for pending in try pendingMutationsLocked() {
                    do {
                        let transaction = try reconcileReplacementBackupLocked(pending, access: access, required: false)
                        _ = try verifiedMutation(
                            matching: transaction,
                            requiresRetention: false
                        )
                        let path = try MarkdownRelativePath(transaction.relativePath)
                        let observed: DocumentFingerprint
                        do {
                            observed = DocumentFingerprint(data: try access.read(path))
                        } catch VaultRepositoryError.fileDoesNotExist {
                            try retainMutationLocked(
                                transaction,
                                reason: "The interrupted save target is missing. The exact candidate remains available for inspection and copying."
                            )
                            continue
                        } catch VaultRepositoryError.notRegularFile {
                            try retainMutationLocked(
                                transaction,
                                reason:
                                    "The interrupted save target is no longer a regular file. The exact candidate remains available for inspection and copying."
                            )
                            continue
                        }
                        if transaction.displaced != nil {
                            try retainMutationLocked(transaction, reason: transaction.retainedReason!)
                        } else if transaction.replacementReconciled
                            && (observed == transaction.candidate
                                || (observed == transaction.expected
                                    && transaction.expected == transaction.candidate))
                        {
                            if try access.presence(transaction.backupPath) == .absent {
                                try fileManager.removeItem(at: transactionDirectory(transaction.id))
                            }
                        } else if observed == transaction.expected {
                            try retainMutationLocked(
                                transaction,
                                reason:
                                    "The previous process ended before the candidate revision became canonical. The canonical source remains at its expected revision and the candidate bytes remain in machine-local recovery."
                            )
                        } else {
                            try retainMutationLocked(
                                transaction,
                                reason:
                                    "The canonical source changed after an interrupted save. The exact candidate remains available for inspection and copying."
                            )
                        }
                    } catch {
                        healthDiagnostic = "A pending save transaction could not be verified and remains untouched: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            healthDiagnostic = "Interrupted-save transactions could not be enumerated: \(error.localizedDescription)"
        }
    }

    private func pendingMutationsLocked() throws -> [MutationTransaction] {
        try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ).filter { $0.lastPathComponent != ".transactions.lock" }
            .compactMap { directory in
                let values = try directory.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    throw VaultRepositoryError.recoveryLedgerUnavailable(
                        "The interrupted-save store contains an unsafe entry."
                    )
                }
                let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let transaction = try decoder.decode(MutationTransaction.self, from: data)
                guard transaction.schemaVersion == MutationTransaction.currentSchemaVersion,
                    directory.lastPathComponent == transaction.id.uuidString.lowercased()
                else {
                    throw VaultRepositoryError.recoveryLedgerUnavailable(
                        "The interrupted-save store contains an unsupported transaction."
                    )
                }
                return transaction
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func verifiedMutation(
        matching reference: MutationTransaction,
        requiresRetention: Bool = true
    ) throws -> VerifiedMutation {
        let directoryName = reference.id.uuidString.lowercased()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            MutationTransaction.self,
            from: storage.read(directory: directoryName, fileName: "manifest.json")
        )
        guard manifest.schemaVersion == MutationTransaction.currentSchemaVersion,
            manifest.id == reference.id,
            manifest.relativePath == reference.relativePath,
            manifest.expected == reference.expected,
            manifest.candidate == reference.candidate,
            manifest.createdAt == reference.createdAt,
            !requiresRetention || manifest.retainedReason != nil
        else {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "The interrupted-save manifest changed after it was listed."
            )
        }
        _ = try MarkdownRelativePath(manifest.relativePath)
        let expected = try byteAccess.read(
            MarkdownRelativePath("\(directoryName)/expected.md")
        )
        let candidate = try byteAccess.read(
            MarkdownRelativePath("\(directoryName)/candidate.md")
        )
        guard DocumentFingerprint(data: expected) == manifest.expected,
            DocumentFingerprint(data: candidate) == manifest.candidate
        else {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "The interrupted-save bytes no longer match their recorded fingerprints."
            )
        }
        if let fingerprint = manifest.displaced {
            let displaced = try byteAccess.read(MarkdownRelativePath("\(directoryName)/displaced.md"))
            guard manifest.replacementReconciled, manifest.retainedReason != nil,
                DocumentFingerprint(data: displaced) == fingerprint
            else { throw VaultRepositoryError.recoveryLedgerUnavailable("The retained external source failed verification.") }
            return VerifiedMutation(transaction: manifest, candidate: displaced)
        }
        return VerifiedMutation(transaction: manifest, candidate: candidate)
    }

    private func retainMutationLocked(
        _ transaction: MutationTransaction,
        reason: String
    ) throws {
        var retained = transaction
        retained.retainedReason = reason
        try writeManifest(retained)
        healthDiagnostic = "A save transaction requires researcher-visible recovery: \(reason)"
    }

    private func writeManifest(_ transaction: MutationTransaction) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(transaction)
        let readback = try storage.replace(
            data,
            directory: transaction.id.uuidString.lowercased(),
            fileName: "manifest.json"
        )
        guard readback == data else {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "An interrupted-save manifest failed durable readback."
            )
        }
    }

    private func transactionDirectory(_ id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try lock.withExclusiveLock(operation)
        } catch let error as VaultRepositoryError {
            throw error
        } catch {
            throw VaultRepositoryError.recoveryLedgerUnavailable(error.localizedDescription)
        }
    }
}
