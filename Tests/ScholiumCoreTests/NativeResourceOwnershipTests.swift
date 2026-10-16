import Darwin
import Dispatch
import Foundation
import ScholiumContracts
import Testing
import os

@testable import ScholiumCore

@Suite("Native resource ownership")
struct NativeResourceOwnershipTests {
    enum LockOwner: String, CaseIterable, Sendable { case storageLease, advisoryLock }

    @Test("Concurrent first lock opens all acquire the same permanent inode", .timeLimit(.minutes(1)))
    func concurrentLockBootstrap() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for round in 0..<64 {
            let directory = SecureRecordDirectory(
                trustedRootURL: root, components: ["round-\(round)"], directoryMode: 0o700,
                fileMode: 0o600, maximumByteCount: 1_024)
            try directory.ensureDirectories([])
            let ready = DispatchSemaphore(value: 0)
            let start = DispatchSemaphore(value: 0)
            let finished = DispatchGroup()
            let observations = OSAllocatedUnfairLock<[LockBootstrapObservation]>(initialState: [])
            for _ in 0..<3 {
                finished.enter()
                Thread.detachNewThread {
                    defer { finished.leave() }
                    ready.signal()
                    start.wait()
                    let observation: LockBootstrapObservation
                    do {
                        let descriptor = try directory.openLockFile(DerivedStateStorage.lockFileName)
                        defer { Darwin.close(descriptor) }
                        var status = stat()
                        if fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG, status.st_nlink == 1 {
                            observation = .init(identity: "\(status.st_dev):\(status.st_ino)", failure: nil)
                        } else {
                            observation = .init(identity: nil, failure: "Opened lock is not a single regular inode.")
                        }
                    } catch {
                        observation = .init(identity: nil, failure: String(describing: error))
                    }
                    observations.withLock { $0.append(observation) }
                }
            }
            // Dedicated threads reach the same first-create boundary before
            // any open begins. No sleep or syscall substitution creates it.
            for _ in 0..<3 { ready.wait() }
            for _ in 0..<3 { start.signal() }
            finished.wait()
            let result = observations.withLock { $0 }
            #expect(result.count == 3)
            #expect(result.compactMap(\.failure).isEmpty)
            #expect(Set(result.compactMap(\.identity)).count == 1)
            let descriptor = try directory.openLockFile(DerivedStateStorage.lockFileName)
            defer { Darwin.close(descriptor) }
            var status = stat()
            #expect(fstat(descriptor, &status) == 0)
            #expect(result.allSatisfy { $0.identity == "\(status.st_dev):\(status.st_ino)" })
        }
    }

    @Test("Rejected lock descriptors close once, then an accepted owner closes once", arguments: LockOwner.allCases)
    func rejectedLockClosesExactlyOnce(_ owner: LockOwner) throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = storage(in: root)
        try directory.ensureDirectories([])
        let name = owner == .storageLease ? DerivedStateStorage.lockFileName : ".coordination.lock"
        let file = directory.directoryURL.appendingPathComponent(name)
        let alias = directory.directoryURL.appendingPathComponent("linked-lock")
        try Data().write(to: file)
        try FileManager.default.linkItem(at: file, to: alias)
        let closes = NativeCloseCounter()
        switch owner {
        case .storageLease:
            #expect(throws: DerivedStateStorageError.unavailable) {
                try DerivedStateStorageLease(storage: directory, exclusive: true, didClose: { closes.record() })
            }
        case .advisoryLock:
            #expect(throws: SecureRecordDirectoryError.self) {
                try AdvisoryFileLock(directory: directory, fileName: name, didClose: { closes.record() })
            }
        }
        // Counts native close attempts, including a failed initializer's
        // deinit, rather than merely observing an already closed descriptor.
        #expect(closes.count == 1)
        try FileManager.default.removeItem(at: alias)
        switch owner {
        case .storageLease:
            let lease = try DerivedStateStorageLease(storage: directory, exclusive: true, didClose: { closes.record() })
            try lease.validateCurrent()
            #expect(closes.count == 1)
            withExtendedLifetime(lease) {}
        case .advisoryLock:
            let lock = try AdvisoryFileLock(directory: directory, fileName: name, didClose: { closes.record() })
            #expect(try lock.withExclusiveLock { 73 } == 73)
            #expect(closes.count == 1)
            withExtendedLifetime(lock) {}
        }
        #expect(closes.count == 2)
    }

    @Test("Contended storage admission closes only its own descriptor once")
    func contendedLeaseClosesExactlyOnce() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = storage(in: root)
        let first = try DerivedStateStorageLease(storage: directory, exclusive: true)
        let closes = NativeCloseCounter()
        #expect(throws: DerivedStateStorageError.inUse) {
            try DerivedStateStorageLease(storage: directory, exclusive: true, didClose: { closes.record() })
        }
        #expect(closes.count == 1)
        try first.validateCurrent()
        #expect(throws: DerivedStateStorageError.inUse) {
            try DerivedStateStorageLease(storage: directory, exclusive: true)
        }
        withExtendedLifetime(first) {}
    }

    @Test("SQLite open failure releases its returned native handle exactly once")
    func sqliteFailedOpenClosesExactlyOnce() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("missing-parent/index.sqlite")
        let closes = NativeCloseCounter()
        #expect(throws: SearchIndexError.self) {
            try SearchSQLiteDatabase(path: missing.path, didClose: { closes.record() })
        }
        #expect(closes.count == 1)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test("Explicit SQLite close, repeated close and deinit share one native release")
    func sqliteSuccessfulOpenClosesExactlyOnce() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let closes = NativeCloseCounter()
        var database: SearchSQLiteDatabase? = try SearchSQLiteDatabase(
            path: root.appendingPathComponent("index.sqlite").path, didClose: { closes.record() })
        try database?.execute("CREATE TABLE ownership(value INTEGER);")
        #expect(closes.count == 0)
        database?.close()
        database?.close()
        #expect(closes.count == 1)
        #expect(throws: SearchIndexError.self) { try database?.execute("SELECT 1;") }
        database = nil
        #expect(closes.count == 1)
    }

    private func storage(in root: URL) -> SecureRecordDirectory {
        SecureRecordDirectory(
            trustedRootURL: root, components: ["records"], directoryMode: 0o700,
            fileMode: 0o600, maximumByteCount: 1_024)
    }

    private func fixtureRoot() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/native-resource-ownership-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private struct LockBootstrapObservation: Sendable {
    let identity: String?
    let failure: String?
}

private final class NativeCloseCounter: Sendable {
    private let value = OSAllocatedUnfairLock<Int>(initialState: 0)
    var count: Int { value.withLock { $0 } }
    func record() { value.withLock { $0 += 1 } }
}
