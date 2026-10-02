import Foundation
import ScholiumContracts

#if canImport(AppKit)
    import AppKit
#endif

/// macOS presentation adapter over the Application-owned Zotero connection.
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

    func pdfAttachments(for item: ZoteroSearchHit) async throws -> [ZoteroPDFSource] {
        try await operations.pdfAttachments(for: item)
    }

    func resolvePDFImport(_ source: ZoteroPDFSource) async throws -> ZoteroPDFImportCandidate {
        try await operations.resolvePDFImport(source)
    }

    func revalidatePDFImport(_ candidate: ZoteroPDFImportCandidate) async throws {
        try await operations.revalidatePDFImport(candidate)
    }

    func pdfImportOptions(for item: ZoteroSearchHit) async throws -> [ZoteroPDFImportOption] {
        try await operations.pdfImportOptions(for: item)
    }

    func resolvePDFLocalCopy(_ observation: ZoteroPDFLocalCopyObservation) async throws -> ZoteroPDFLocalCopyCandidate {
        try await operations.resolvePDFLocalCopy(observation)
    }

    func openZotero() {
        #if canImport(AppKit)
            if let url = URL(string: "zotero://select/library") {
                NSWorkspace.shared.open(url)
            }
        #endif
    }

}
