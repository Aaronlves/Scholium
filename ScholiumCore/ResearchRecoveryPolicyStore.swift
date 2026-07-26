import Foundation
import ScholiumContracts

package struct ResearchRecoveryPolicyStoredState: Sendable {
    package let snapshot: ResearchRecoveryPolicySnapshot
    package let pendingSnapshotIDsToRemove: Set<UUID>
}

/// Revision-checked, machine-local settled-snapshot retention for one
/// Triptych. Snapshot bytes remain in each Vault's Recovery Ledger; this file
/// stores only the shared policy.
package actor ResearchRecoveryPolicyStore {
    private static let schemaVersion = 1
    private static let fileName = "policy.json"
    private static let lockName = ".research-recovery-policy-v1.lock"
    private static let maximumPendingSnapshotCount = 100_000
    private static let maximumPolicyByteCount = 8 * 1024 * 1024

    private struct Payload: Codable, Hashable {
        let schemaVersion: Int
        let triptychID: UUID
        let retention: SettledSnapshotRetention
        let pendingSnapshotIDsToRemove: [UUID]

        init(
            triptychID: UUID,
            retention: SettledSnapshotRetention,
            pendingSnapshotIDsToRemove: Set<UUID> = []
        ) {
            schemaVersion = ResearchRecoveryPolicyStore.schemaVersion
            self.triptychID = triptychID
            self.retention = retention
            self.pendingSnapshotIDsToRemove = pendingSnapshotIDsToRemove.sorted {
                $0.uuidString < $1.uuidString
            }
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case schemaVersion = "schema_version"
            case triptychID = "triptych_id"
            case retention
            case pendingSnapshotIDsToRemove = "pending_snapshot_ids_to_remove"
        }

        init(from decoder: Decoder) throws {
            let raw = try decoder.container(keyedBy: AnyCodingKey.self)
            let allowed = Set(CodingKeys.allCases.map(\.stringValue))
            guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
                throw ResearchRecoveryPolicyError.corruptStore
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let version = try container.decode(Int.self, forKey: .schemaVersion)
            guard version == ResearchRecoveryPolicyStore.schemaVersion else {
                throw ResearchRecoveryPolicyError.corruptStore
            }
            schemaVersion = version
            triptychID = try container.decode(UUID.self, forKey: .triptychID)
            retention = try container.decode(
                SettledSnapshotRetention.self,
                forKey: .retention
            )
            let pending = try container.decodeIfPresent(
                [UUID].self,
                forKey: .pendingSnapshotIDsToRemove
            ) ?? []
            guard pending.count <= ResearchRecoveryPolicyStore.maximumPendingSnapshotCount,
                  Set(pending).count == pending.count else {
                throw ResearchRecoveryPolicyError.corruptStore
            }
            pendingSnapshotIDsToRemove = pending
        }
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    private let triptychID: UUID
    private let storage: SecureRecordDirectory
    private let lock: AdvisoryFileLock

    package init(applicationSupportURL: URL, triptychID: UUID) throws {
        self.triptychID = triptychID
        storage = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: [
                "Triptychs",
                triptychID.uuidString,
                "research-recovery-policy-v1",
            ],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: Self.maximumPolicyByteCount
        )
        lock = try AdvisoryFileLock(directory: storage, fileName: Self.lockName)
    }

    init(storageURL: URL, triptychID: UUID) throws {
        self.triptychID = triptychID
        storage = SecureRecordDirectory(
            trustedRootURL: storageURL.deletingLastPathComponent(),
            components: [storageURL.lastPathComponent],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: Self.maximumPolicyByteCount
        )
        lock = try AdvisoryFileLock(directory: storage, fileName: Self.lockName)
    }

    package func snapshot() throws -> ResearchRecoveryPolicySnapshot {
        try state().snapshot
    }

    package func state() throws -> ResearchRecoveryPolicyStoredState {
        do {
            return try lock.withSharedLock { try loadState() }
        } catch let error as ResearchRecoveryPolicyError {
            throw error
        } catch {
            throw ResearchRecoveryPolicyError.unsafeStore
        }
    }

    package func save(
        _ retention: SettledSnapshotRetention,
        expectedRevision: DocumentFingerprint?
    ) throws -> ResearchRecoveryPolicySnapshot {
        do {
            return try lock.withExclusiveLock {
                let current = try loadState()
                guard current.pendingSnapshotIDsToRemove.isEmpty else {
                    throw ResearchRecoveryPolicyError.stalePreview
                }
                guard current.snapshot.revision == expectedRevision else {
                    throw ResearchRecoveryPolicyError.staleRevision
                }
                let payload = Payload(triptychID: triptychID, retention: retention)
                return try write(payload).snapshot
            }
        } catch let error as ResearchRecoveryPolicyError {
            throw error
        } catch {
            throw ResearchRecoveryPolicyError.unsafeStore
        }
    }

    package func beginChange(
        _ retention: SettledSnapshotRetention,
        approvedSnapshotIDsToRemove: Set<UUID>,
        expectedRevision: DocumentFingerprint?
    ) throws -> ResearchRecoveryPolicyStoredState {
        do {
            return try lock.withExclusiveLock {
                guard approvedSnapshotIDsToRemove.count
                        <= Self.maximumPendingSnapshotCount else {
                    throw ResearchRecoveryPolicyError.changeTooLarge
                }
                let current = try loadState()
                guard current.pendingSnapshotIDsToRemove.isEmpty else {
                    throw ResearchRecoveryPolicyError.stalePreview
                }
                guard current.snapshot.revision == expectedRevision else {
                    throw ResearchRecoveryPolicyError.staleRevision
                }
                return try write(Payload(
                    triptychID: triptychID,
                    retention: retention,
                    pendingSnapshotIDsToRemove: approvedSnapshotIDsToRemove
                ))
            }
        } catch let error as ResearchRecoveryPolicyError {
            throw error
        } catch {
            throw ResearchRecoveryPolicyError.unsafeStore
        }
    }

    package func finishPendingChange(
        retention: SettledSnapshotRetention,
        approvedSnapshotIDsToRemove: Set<UUID>,
        expectedRevision: DocumentFingerprint?
    ) throws -> ResearchRecoveryPolicySnapshot {
        do {
            return try lock.withExclusiveLock {
                let current = try loadState()
                if current.pendingSnapshotIDsToRemove.isEmpty,
                   current.snapshot.retention == retention {
                    return current.snapshot
                }
                guard current.snapshot.revision == expectedRevision else {
                    throw ResearchRecoveryPolicyError.staleRevision
                }
                guard current.snapshot.retention == retention,
                      current.pendingSnapshotIDsToRemove == approvedSnapshotIDsToRemove else {
                    throw ResearchRecoveryPolicyError.stalePreview
                }
                return try write(Payload(
                    triptychID: triptychID,
                    retention: retention
                )).snapshot
            }
        } catch let error as ResearchRecoveryPolicyError {
            throw error
        } catch {
            throw ResearchRecoveryPolicyError.unsafeStore
        }
    }

    private func loadState() throws -> ResearchRecoveryPolicyStoredState {
        let data: Data
        do {
            data = try storage.read(directory: nil, fileName: Self.fileName)
        } catch SecureRecordDirectoryError.notFound {
            return ResearchRecoveryPolicyStoredState(
                snapshot: ResearchRecoveryPolicySnapshot(
                    retention: .defaultValue,
                    revision: nil,
                    settledSnapshotCount: 0,
                    maximumSnapshotsForOneNote: 0
                ),
                pendingSnapshotIDsToRemove: []
            )
        } catch {
            throw ResearchRecoveryPolicyError.unsafeStore
        }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard payload.triptychID == triptychID else {
                throw ResearchRecoveryPolicyError.corruptStore
            }
            return ResearchRecoveryPolicyStoredState(
                snapshot: ResearchRecoveryPolicySnapshot(
                    retention: payload.retention,
                    revision: DocumentFingerprint(data: data),
                    settledSnapshotCount: 0,
                    maximumSnapshotsForOneNote: 0
                ),
                pendingSnapshotIDsToRemove: Set(payload.pendingSnapshotIDsToRemove)
            )
        } catch let error as ResearchRecoveryPolicyError {
            throw error
        } catch {
            throw ResearchRecoveryPolicyError.corruptStore
        }
    }

    private func write(_ payload: Payload) throws -> ResearchRecoveryPolicyStoredState {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        let readback = try storage.replace(
            data,
            directory: nil,
            fileName: Self.fileName
        )
        guard try JSONDecoder().decode(Payload.self, from: readback) == payload else {
            throw ResearchRecoveryPolicyError.unsafeStore
        }
        return ResearchRecoveryPolicyStoredState(
            snapshot: ResearchRecoveryPolicySnapshot(
                retention: payload.retention,
                revision: DocumentFingerprint(data: readback),
                settledSnapshotCount: 0,
                maximumSnapshotsForOneNote: 0
            ),
            pendingSnapshotIDsToRemove: Set(payload.pendingSnapshotIDsToRemove)
        )
    }
}
