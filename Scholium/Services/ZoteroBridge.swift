import ScholiumContracts
import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// macOS presentation adapter over the Application-owned Zotero capability.
/// HTTP, decoding, matching, and connection history remain behind `ZoteroUseCases`;
/// this adapter owns only external-app presentation.
actor ZoteroBridge {
    private let operations: any ZoteroUseCases

    init(operations: any ZoteroUseCases) {
        self.operations = operations
    }

    func connectionInfo() async -> ZoteroLibraryInfo {
        await operations.libraryInfo()
    }

    func refreshLibraryInfo() async throws -> ZoteroLibraryInfo {
        try await operations.refreshLibraryInfo()
    }

    func clearConnectionHistory() async throws {
        try await operations.clearConnectionHistory()
    }

    func searchLibrary(query: String) async throws -> [ZoteroSearchHit] {
        try await operations.searchLibrary(query: query, limit: 25)
    }

    func openZotero() {
        #if canImport(AppKit)
        if let url = URL(string: "zotero://select/library") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    func openInZotero(binding: AnalysisZoteroBinding) {
        guard let url = Self.itemURL(binding: binding) else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    nonisolated static func itemURL(binding: AnalysisZoteroBinding) -> URL? {
        let path = switch binding.library {
        case .user:
            "library/items/\(binding.itemKey)"
        case .group(let groupID):
            "groups/\(groupID)/items/\(binding.itemKey)"
        }
        return URL(string: "zotero://select/\(path)")
    }
}
