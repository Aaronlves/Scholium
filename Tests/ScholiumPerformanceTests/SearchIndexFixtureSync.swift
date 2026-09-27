import Foundation
import ScholiumContracts

@testable import ScholiumCore

extension TriptychSearchIndex {
    func synchronize(_ documents: [SearchIndexDocument]) async throws -> TriptychSearchIndexSyncResult {
        let generation = try await workspaceGeneration() + 1
        let byPath = Dictionary(
            documents.map {
                (Data("\($0.vaultID.uuidString.lowercased())/\($0.relativePath)".utf8), $0)
            }, uniquingKeysWith: { first, _ in first })
        return try await synchronizeManifest(
            documents.map(SearchIndexManifestEntry.init(document:)),
            workspaceGeneration: generation,
            loadChanged: { entry in
                guard let source = byPath[Data("\(entry.vaultID.uuidString.lowercased())/\(entry.relativePath)".utf8)]
                else { throw SearchIndexError.invalidDocuments("missing fixture source") }
                return source
            },
            validateManifest: {}
        )
    }
}
