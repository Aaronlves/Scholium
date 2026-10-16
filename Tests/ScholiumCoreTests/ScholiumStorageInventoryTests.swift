import Darwin
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Explicit App storage metadata inventory")
struct ScholiumStorageInventoryTests {
    @Test("Search sizes stay scoped to each Triptych and skipped index links mark only that scope incomplete")
    func searchSizesByTriptych() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = UUID()
        let second = UUID()
        let firstDirectory = "Triptychs/\(first.uuidString)/indexes"
        let secondDirectory = "Triptychs/\(second.uuidString.lowercased())/indexes"
        try fixture.write("\(firstDirectory)/search-v10.sqlite", Data(repeating: 0x11, count: 123))
        try fixture.write("\(firstDirectory)/search-v10.sqlite-wal", Data(repeating: 0x22, count: 47))
        try fixture.write("\(secondDirectory)/search-v10.sqlite", Data(repeating: 0x33, count: 281))
        try fixture.write("\(secondDirectory)/unknown-format.bin", Data(repeating: 0x44, count: 19))
        let outside = fixture.root.appendingPathComponent("not-an-index.md")
        let sentinel = Data("exact outside bytes must not be read or changed".utf8)
        try sentinel.write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: fixture.support.appendingPathComponent("\(secondDirectory)/search-v10.sqlite-wal"), withDestinationURL: outside)

        let inventory = try ScholiumStorageInventoryReader.scan(applicationSupportURL: fixture.support)
        #expect(inventory.searchIndexesByTriptych.count == 2)
        #expect(inventory.searchIndexesByTriptych[first] == ScholiumStorageUsage(category: .searchIndexes, byteCount: 170, fileCount: 2))
        #expect(
            inventory.searchIndexesByTriptych[second]
                == ScholiumStorageUsage(
                    category: .searchIndexes, byteCount: 281, fileCount: 1, skippedEntries: 2))
        let total = try #require(inventory.usages.first { $0.category == .searchIndexes })
        #expect(total.byteCount == 451 && total.fileCount == 3)
        #expect(try Data(contentsOf: outside) == sentinel)
    }

    @Test("Explicit namespaces are measured once without entering Agent Runtime or unknown directories")
    func knownNamespacesAndRuntimeExclusion() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let triptych = UUID().uuidString
        let vault = UUID().uuidString
        let conversation = UUID().uuidString
        let note = UUID().uuidString
        let wordJob = UUID().uuidString
        let records: [(String, ScholiumStorageCategory)] = [
            ("Workspace/workspace-registration-v3.json", .configuration),
            ("Workspace/saved-searches.json", .configuration),
            ("Workspace/search-term-groups.json", .configuration),
            ("Workspace/Styles/appearances.json", .configuration),
            ("Workspace/Styles/Snippets/\(UUID().uuidString).css", .configuration),
            ("Window Sessions/\(UUID().uuidString).json", .configuration),
            ("Triptychs/\(triptych)/attachment-access/indexed-attachments-v2.json", .configuration),
            ("Zotero/original-access/original-access-v1.json", .configuration),
            ("AppBridge/app-bridge-auth-v1", .configuration),
            ("Triptychs/\(triptych)/indexes/search-v10.sqlite", .searchIndexes),
            ("Triptychs/\(triptych)/indexes/search-v10.sqlite-wal", .searchIndexes),
            ("Triptychs/\(triptych)/indexes/search-v9.sqlite", .searchIndexes),
            ("Vaults/\(vault)/source-projections-v1/\(SourceProjectionCache.fileName("Note.md"))", .sourceProjectionCache),
            ("Vaults/\(vault)/source-projections-v1/\(SourceProjectionCache.catalogFileName("Note.md"))", .sourceProjectionCache),
            ("Chat/\(conversation)/conversations.json", .chatHistory),
            ("Chat/\(conversation)/Materials/\(UUID().uuidString).page-1.png", .chatMaterials),
            ("Triptychs/\(triptych)/document-reviews-v1/\(note).json", .researchHistory),
            ("Triptychs/\(triptych)/agent-changes-v1/\(UUID().uuidString).json", .researchHistory),
            ("Triptychs/\(triptych)/transactions/records/\(UUID().uuidString).json", .recovery),
            ("Triptychs/\(triptych)/transactions/citation-pairs-v1/\(UUID().uuidString)-source-before.json", .recovery),
            ("Vaults/\(vault)/save-transactions-v2/\(UUID().uuidString)/expected.md", .recovery),
            ("Temporary/WordExports-v1/\(wordJob)/source.docx", .temporaryFiles),
            ("Temporary/WordExports-v1/\(wordJob)/package/word/document.xml", .temporaryFiles),
        ]
        var expected: [String: (bytes: Int64, count: Int)] = [:]
        for (ordinal, record) in records.enumerated() {
            // Deliberately not valid JSON/SQLite/plist: inventory is metadata
            // only and must not deserialize these research-bearing records.
            let bytes = Data(repeating: UInt8(ordinal + 1), count: ordinal + 17)
            try fixture.write(record.0, bytes)
            var usage = expected[record.1.rawValue] ?? (0, 0)
            usage.bytes += Int64(bytes.count)
            usage.count += 1
            expected[record.1.rawValue] = usage
        }
        try fixture.write("Chat/Codex/conversations.json", Data(repeating: 0x77, count: 31_337))
        try fixture.write("Future-v2/private.bin", Data(repeating: 0x66, count: 17_177))
        try fixture.write("Temporary/WordExports-v2/private.bin", Data(repeating: 0x55, count: 11_111))
        let inventory = try ScholiumStorageInventoryReader.scan(applicationSupportURL: fixture.support)
        #expect(inventory.rootURL == fixture.support.resolvingSymlinksInPath().standardizedFileURL)
        #expect(inventory.usages.count == ScholiumStorageCategory.allCases.count)
        for category in ScholiumStorageCategory.allCases where category != .unclassified {
            let usage = try #require(inventory.usages.first { $0.category == category })
            #expect(usage.byteCount == (expected[category.rawValue]?.bytes ?? 0))
            #expect(usage.fileCount == (expected[category.rawValue]?.count ?? 0))
            #expect(usage.unreadableEntries == 0 && usage.skippedEntries == 0)
        }
        let unknown = try #require(inventory.usages.first { $0.category == .unclassified })
        #expect(unknown.fileCount == 0 && unknown.byteCount == 0 && unknown.skippedEntries == 2)
        #expect(inventory.usages.reduce(0) { $0 + $1.fileCount } == records.count)
    }

    @Test("Metadata never follows internal links, double-counts hardlinks or blocks on special files")
    func linksAndSpecialFiles() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = fixture.support.appendingPathComponent("unknown-original")
        let linked = fixture.support.appendingPathComponent("unknown-hardlink")
        let bytes = Data("one physical inode".utf8)
        try bytes.write(to: original)
        try FileManager.default.linkItem(at: original, to: linked)
        let outside = fixture.root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data(repeating: 0x11, count: 99_999).write(to: outside.appendingPathComponent("never-read.md"))
        let vaults = fixture.support.appendingPathComponent("Vaults", isDirectory: true)
        try FileManager.default.createDirectory(at: vaults, withIntermediateDirectories: true)
        let symlink = vaults.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
        var linkStatus = stat()
        #expect(lstat(symlink.path, &linkStatus) == 0)
        let fifo = fixture.support.appendingPathComponent("unknown-fifo")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        let inventory = try ScholiumStorageInventoryReader.scan(applicationSupportURL: fixture.support)
        let unknown = try #require(inventory.usages.first { $0.category == .unclassified })
        #expect(unknown.byteCount == Int64(bytes.count) + Int64(linkStatus.st_size))
        #expect(unknown.fileCount == 3 && unknown.skippedEntries == 4)
        #expect(inventory.usages.filter { $0.category != .unclassified }.allSatisfy { $0.byteCount == 0 && $0.fileCount == 0 })
        #expect(try Data(contentsOf: original) == bytes)
        #expect(try Data(contentsOf: outside.appendingPathComponent("never-read.md")).count == 99_999)
    }

    @Test("Absent roots remain absent and cancellation does not mutate storage")
    func absenceAndCancellation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let absent = fixture.support.appendingPathComponent("Absent")
        #expect(throws: DerivedStateStorageError.unavailable) { try ScholiumStorageInventoryReader.scan(applicationSupportURL: absent) }
        #expect(!FileManager.default.fileExists(atPath: absent.path))
        try fixture.write("Workspace/saved-searches.json", Data("unchanged".utf8))
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ScholiumStorageInventoryReader.scan(applicationSupportURL: fixture.support)
        }
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
        #expect(try Data(contentsOf: fixture.support.appendingPathComponent("Workspace/saved-searches.json")) == Data("unchanged".utf8))
    }

    private struct Fixture {
        let root: URL
        let support: URL
        init() throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/storage-inventory-tests/\(UUID().uuidString)", isDirectory: true)
            support = root.appendingPathComponent("State-v1", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }
        func write(_ relativePath: String, _ bytes: Data) throws {
            let target = support.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: target)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
