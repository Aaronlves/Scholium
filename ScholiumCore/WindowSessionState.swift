import ScholiumContracts
import Foundation

public actor WindowSessionSnapshotStore {
    private let directoryURL: URL
    private var acceptedWriteGenerations: [UUID: UInt64] = [:]

    public init(applicationSupportURL: URL) {
        directoryURL = applicationSupportURL
            .appendingPathComponent("Window Sessions", isDirectory: true)
    }

    public func load(id: UUID) throws -> WindowSessionSnapshot? {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(WindowSessionSnapshot.self, from: data)
        guard snapshot.id == id else { throw WindowSessionStoreError.identityMismatch }
        return snapshot
    }

    public func save(_ snapshot: WindowSessionSnapshot) throws {
        try write(snapshot)
    }

    /// Rejects a late persistence task from an older lifecycle attempt. The
    /// generation is process-local because no task can survive process exit;
    /// the stored JSON contract therefore remains unchanged.
    public func save(
        _ snapshot: WindowSessionSnapshot,
        generation: UInt64
    ) throws {
        guard generation > (acceptedWriteGenerations[snapshot.id] ?? 0) else {
            return
        }
        try write(snapshot)
        acceptedWriteGenerations[snapshot.id] = generation
    }

    private func write(_ snapshot: WindowSessionSnapshot) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: fileURL(for: snapshot.id), options: .atomic)
    }

    public func remove(id: UUID) throws {
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Migrates every committed session currently bound to the moved note's
    /// vault. All files are decoded before any are replaced so corrupt state
    /// cannot cause a knowingly partial migration.
    public func migratePath(vaultID: UUID, from sourcePath: String, to destinationPath: String) throws {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var updates: [(URL, WindowSessionSnapshot)] = []
        for url in urls {
            let snapshot = try decoder.decode(
                WindowSessionSnapshot.self,
                from: Data(contentsOf: url, options: [.mappedIfSafe])
            )
            let migrated = snapshot.migratingPath(
                vaultID: vaultID,
                from: sourcePath,
                to: destinationPath
            )
            guard migrated != snapshot else { continue }
            updates.append((url, migrated))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        for (url, snapshot) in updates {
            try encoder.encode(snapshot).write(to: url, options: .atomic)
        }
    }

    private func fileURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent(id.uuidString + ".json", isDirectory: false)
    }
}
