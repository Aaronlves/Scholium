import Foundation
import ScholiumCore

/// Thin app adapter over the persistent ScholiumCore search contract. The GUI
/// does not own a second tokenizer, ranking model, or link/evidence meaning.
actor SearchEngine {
    private var currentIndex: SQLiteSearchIndex?
    private var currentVaultID: UUID?
    private var recoveredCorruption = false

    func synchronize(
        notes: [Note],
        vault: RegisteredVault,
        applicationSupportURL: URL,
        brokenLinkPaths: Set<String> = [],
        forceRebuild: Bool = false
    ) async throws -> SearchIndexSyncResult {
        let index = try ensureIndex(vault: vault, applicationSupportURL: applicationSupportURL)
        let documents = Self.documents(
            notes: notes,
            vault: vault,
            brokenLinkPaths: brokenLinkPaths
        )
        let result = try await index.synchronize(
            documents,
            vaultName: vault.name,
            vaultRole: vault.role,
            forceRebuild: forceRebuild,
            recoveredCorruption: recoveredCorruption
        )
        recoveredCorruption = false
        return result
    }

    func buildIndex(
        notes: [Note],
        vault: RegisteredVault,
        applicationSupportURL: URL,
        brokenLinkPaths: Set<String> = []
    ) async throws {
        _ = try await synchronize(
            notes: notes,
            vault: vault,
            applicationSupportURL: applicationSupportURL,
            brokenLinkPaths: brokenLinkPaths,
            forceRebuild: false
        )
    }

    /// Applies a complete, transactional generation for only the files whose
    /// catalog or derived broken-link state changed. The caller is responsible
    /// for recomputing graph semantics before constructing these mutations.
    func applyChanges(
        notes: [Note],
        deletedPaths: Set<String>,
        vault: RegisteredVault,
        brokenLinkPaths: Set<String>
    ) async throws {
        guard currentVaultID == vault.id, let currentIndex else {
            throw SearchIndexError.invalidQuery("the current vault index is unavailable")
        }
        var mutations = deletedPaths.sorted().map(SearchIndexMutation.delete(relativePath:))
        mutations.append(contentsOf: notes.sorted(by: { $0.relativePath < $1.relativePath }).map { note in
            .upsert(SearchIndexDocument(
                vaultID: vault.id,
                vaultName: vault.name,
                vaultRole: vault.role,
                document: NoteDocument(relativePath: note.relativePath, rawContent: note.rawContent),
                review: note.isReviewed ? "reviewed" : "unreviewed",
                hasBrokenLink: brokenLinkPaths.contains(note.relativePath)
            ))
        })
        _ = try await currentIndex.apply(mutations)
    }

    func index() -> SQLiteSearchIndex? {
        currentIndex
    }

    func generation() async throws -> IndexGeneration? {
        guard let currentIndex else { return nil }
        return try await currentIndex.generation()
    }

    func search(
        query: String,
        notes: [Note],
        filterKB: KnowledgeBase? = nil,
        filterTag: String? = nil,
        filterReviewed: Bool? = nil,
        limit: Int = 50
    ) async throws -> [SearchResult] {
        guard let currentIndex else {
            throw SearchIndexError.invalidQuery("the current vault index is unavailable")
        }
        var queryText = query
        if let filterTag, !filterTag.isEmpty {
            queryText += " tag:\(Self.quoted(filterTag))"
        }
        let filter = SearchFilter(review: filterReviewed.map { $0 ? "reviewed" : "unreviewed" })
        let hits = try await currentIndex.search(SearchQuery(queryText), filter: filter, limit: limit)
        let notesByPath = Dictionary(uniqueKeysWithValues: notes.map { ($0.relativePath, $0) })
        return hits.compactMap { hit in
            guard let note = notesByPath[hit.relativePath], filterKB == nil || note.kb == filterKB else { return nil }
            return SearchResult(
                notePath: hit.relativePath,
                displayName: hit.title,
                kb: note.kb,
                score: hit.score,
                matchField: hit.matchedField.rawValue,
                snippet: hit.snippet,
                highlights: hit.highlights,
                sourceLine: hit.sourceLine,
                isReviewed: note.isReviewed
            )
        }
    }

    private nonisolated static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func ensureIndex(
        vault: RegisteredVault,
        applicationSupportURL: URL
    ) throws -> SQLiteSearchIndex {
        if currentVaultID == vault.id, let currentIndex { return currentIndex }
        let url = SQLiteSearchIndex.databaseURL(
            applicationSupportURL: applicationSupportURL,
            vaultID: vault.id
        )
        let opened = try SQLiteSearchIndex.openRecovering(databaseURL: url, vaultID: vault.id)
        currentIndex = opened.index
        currentVaultID = vault.id
        recoveredCorruption = opened.recoveredCorruption
        return opened.index
    }

    private nonisolated static func documents(
        notes: [Note],
        vault: RegisteredVault,
        brokenLinkPaths: Set<String>
    ) -> [SearchIndexDocument] {
        notes.map { note in
            SearchIndexDocument(
                vaultID: vault.id,
                vaultName: vault.name,
                vaultRole: vault.role,
                document: NoteDocument(relativePath: note.relativePath, rawContent: note.rawContent),
                review: note.isReviewed ? "reviewed" : "unreviewed",
                hasBrokenLink: brokenLinkPaths.contains(note.relativePath)
            )
        }
    }
}
