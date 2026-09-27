import Foundation
import ScholiumContracts

@testable import ScholiumCore

/// Test-only in-memory source loader. Production always supplies a compact
/// manifest and descriptor-authorized demand loader from Application.
extension TriptychSearchIndex {
    func synchronize(
        _ documents: [SearchIndexDocument],
        sourceProjectionCaches: [UUID: SourceSearchProjectionCache] = [:]
    ) async throws -> TriptychSearchIndexSyncResult {
        let latest = try await workspaceGeneration()
        return try await synchronize(
            documents, sourceProjectionCaches: sourceProjectionCaches,
            workspaceGeneration: latest + 1)
    }

    func synchronize(
        _ documents: [SearchIndexDocument],
        sourceProjectionCaches: [UUID: SourceSearchProjectionCache] = [:],
        workspaceGeneration: UInt64
    ) async throws -> TriptychSearchIndexSyncResult {
        let byPath = Dictionary(
            documents.map {
                (Data("\($0.vaultID.uuidString.lowercased())/\($0.relativePath)".utf8), $0)
            }, uniquingKeysWith: { first, _ in first })
        return try await synchronizeManifest(
            documents.map(SearchIndexManifestEntry.init(document:)),
            sourceProjectionCaches: sourceProjectionCaches,
            workspaceGeneration: workspaceGeneration,
            loadChanged: { entry in
                guard let source = byPath[Data("\(entry.vaultID.uuidString.lowercased())/\(entry.relativePath)".utf8)]
                else { throw SearchIndexError.invalidDocuments("missing fixture source") }
                return source
            },
            validateManifest: {}
        )
    }
}
