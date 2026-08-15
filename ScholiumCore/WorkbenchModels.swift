import ScholiumContracts
import Foundation

public actor SavedSearchStore {
    private let fileURL: URL
    private var loadFailure: String?

    public init(workspaceStorageURL: URL) {
        fileURL = workspaceStorageURL.appendingPathComponent("saved-searches.json", isDirectory: false)
    }

    public func load() throws -> [SavedSearch] {
        guard ExactStatePreserver.entryExists(at: fileURL) else {
            loadFailure = nil
            return []
        }
        do {
            let values = try fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            // Array order is researcher-defined presentation state. Preserve
            // the persisted order instead of silently sorting by creation date.
            let searches = try JSONDecoder.scholium.decode([SavedSearch].self, from: data)
            loadFailure = nil
            return searches
        } catch {
            loadFailure = error.localizedDescription
            throw SavedSearchStoreError.unreadable(error.localizedDescription)
        }
    }

    public func save(_ searches: [SavedSearch]) throws {
        if let loadFailure { throw SavedSearchStoreError.unreadable(loadFailure) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder.scholium.encode(searches).write(to: fileURL, options: .atomic)
    }

    /// Explicitly preserves an unreadable Saved Search document, then returns
    /// to the missing-file empty state. A valid replacement is never moved.
    @discardableResult
    public func preserveUnreadableAndReset() throws -> URL? {
        guard ExactStatePreserver.entryExists(at: fileURL) else {
            loadFailure = nil
            return nil
        }
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        if (try? JSONDecoder.scholium.decode([SavedSearch].self, from: data)) != nil {
            loadFailure = nil
            return nil
        }
        let preserved = try ExactStatePreserver.preserve(
            fileURL,
            kind: .regularFile,
            recoveryStem: "saved-searches.corrupt",
            recoveryExtension: "json",
            fileEligibility: {
                (try? JSONDecoder.scholium.decode([SavedSearch].self, from: $0)) == nil
            }
        )
        loadFailure = nil
        return preserved
    }
}


private extension JSONEncoder {
    static var scholium: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var scholium: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
