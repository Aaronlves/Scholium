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

    func openZotero() {
        #if canImport(AppKit)
        if let url = URL(string: "zotero://select/library") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    func openInZotero(zoteroKey: String) {
        guard let url = Self.itemURL(zoteroKey: zoteroKey) else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    nonisolated static func normalizedItemKey(_ value: String?) -> String? {
        try? ResearchSourceIdentity.normalizedZoteroKey(value)
    }

    nonisolated static func itemURL(zoteroKey: String?) -> URL? {
        guard let key = normalizedItemKey(zoteroKey) else { return nil }
        return URL(string: "zotero://select/library/items/\(key)")
    }
}
