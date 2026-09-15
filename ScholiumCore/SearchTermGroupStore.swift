import Foundation
import ScholiumContracts

/// One app-local collection beside Saved Searches. Mutations reload the collection
/// and compare the edited group, preserving unrelated edits from other windows.
public actor SearchTermGroupStore {
    private struct Document: Codable {
        let version: Int
        var groups: [SearchTermGroup]
    }
    private let fileURL: URL
    public init(workspaceStorageURL: URL) { fileURL = workspaceStorageURL.appendingPathComponent("search-term-groups.json") }
    public func load() throws -> [SearchTermGroup] {
        guard ExactStatePreserver.entryExists(at: fileURL) else { return [] }
        do {
            let attributes = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true, (attributes.fileSize ?? Int.max) <= 16_000_000 else {
                throw SearchTermGroupError.unreadable
            }
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
            guard document.version == 1, document.groups.count <= 128, Set(document.groups.map(\.id)).count == document.groups.count else {
                throw SearchTermGroupError.unreadable
            }
            for group in document.groups { try group.validate() }
            return document.groups
        } catch { throw SearchTermGroupError.unreadable }
    }
    @discardableResult
    public func save(_ group: SearchTermGroup, replacing expected: SearchTermGroup?) throws -> [SearchTermGroup] {
        try group.validate()
        var groups = try load()
        guard groups.first(where: { $0.id == group.id }) == expected else { throw SearchTermGroupError.changed }
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
        } else {
            guard groups.count < 128 else { throw SearchTermGroupError.invalid }
            groups.append(group)
        }
        try persist(groups)
        return groups
    }
    @discardableResult
    public func delete(_ expected: SearchTermGroup) throws -> [SearchTermGroup] {
        let groups = try load()
        guard groups.first(where: { $0.id == expected.id }) == expected else { throw SearchTermGroupError.changed }
        let remaining = groups.filter { $0.id != expected.id }
        try persist(remaining)
        return remaining
    }
    private func persist(_ groups: [SearchTermGroup]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Document(version: 1, groups: groups))
        guard data.count <= 16_000_000 else { throw SearchTermGroupError.invalid }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
