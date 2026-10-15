import Darwin
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Zotero original read access")
struct ZoteroOriginalAccessStoreTests {
    @Test("Selected storage-folder access survives reconstruction and can be revoked without touching originals")
    func persistentFolderAndRevocation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let nested = fixture.originals.appendingPathComponent("ATTACH01", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let original = nested.appendingPathComponent("source.txt")
        let bytes = Data("An original, with exact bytes.\r\n".utf8)
        try bytes.write(to: original)
        let initial = ZoteroOriginalAccessStore(applicationSupportURL: fixture.support)
        await #expect(throws: CocoaError.self) {
            try await initial.readOriginal(at: original, maximumByteCount: 1024)
        }
        try await initial.authorize(selectedURL: fixture.originals)
        let reconstructed = ZoteroOriginalAccessStore(applicationSupportURL: fixture.support)
        let grant = try #require(try await reconstructed.grants().first)
        #expect(grant.path == fixture.originals.path && grant.kind == .folder && grant.status == .available)
        #expect(try await reconstructed.readOriginal(at: original, maximumByteCount: 1024) == bytes)
        let storage = fixture.support.appendingPathComponent("Zotero/original-access/original-access-v1.json")
        let permissions = try FileManager.default.attributesOfItem(atPath: storage.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        try await initial.remove(grantID: grant.id)
        #expect(try await reconstructed.grants().isEmpty)
        await #expect(throws: CocoaError.self) {
            try await reconstructed.readOriginal(at: original, maximumByteCount: 1024)
        }
        #expect(try Data(contentsOf: original) == bytes)
    }

    @Test("An exact linked-file grant cannot read a neighboring file or silently move to another original")
    func exactFileGrant() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = fixture.originals.appendingPathComponent("first.txt")
        let second = fixture.originals.appendingPathComponent("second.txt")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let store = ZoteroOriginalAccessStore(applicationSupportURL: fixture.support)
        try await store.authorize(selectedURL: first)
        let grant = try #require(try await store.grants().first)
        #expect(try await store.readOriginal(at: first, maximumByteCount: 1024) == Data("first".utf8))
        await #expect(throws: CocoaError.self) { try await store.readOriginal(at: second, maximumByteCount: 1024) }
        await #expect(throws: ZoteroOriginalAccessError.self) {
            try await store.authorize(selectedURL: second, replacing: grant.id)
        }
        #expect(try await store.grants().first?.path == first.path)
        let moved = fixture.originals.appendingPathComponent("moved.txt")
        try FileManager.default.moveItem(at: first, to: moved)
        try Data("replacement".utf8).write(to: first)
        #expect(try await store.grants().first?.status == .accessRequired)
        await #expect(throws: CocoaError.self) { try await store.readOriginal(at: first, maximumByteCount: 1024) }
        try await store.authorize(selectedURL: first, replacing: grant.id)
        #expect(try await store.grants().first?.id == grant.id)
        #expect(try await store.readOriginal(at: first, maximumByteCount: 1024) == Data("replacement".utf8))
        #expect(try Data(contentsOf: moved) == Data("first".utf8))
    }

    @Test("Folder grants reject symlink descendants, symlinked parents, sibling-prefix escapes and oversize originals")
    func containment() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("private.txt")
        try Data("outside grant".utf8).write(to: outside)
        let linked = fixture.originals.appendingPathComponent("linked.txt")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
        let linkedDirectory = fixture.originals.appendingPathComponent("linked-directory")
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: fixture.root)
        let sibling = fixture.root.appendingPathComponent("OriginalsExtra", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: false)
        let siblingFile = sibling.appendingPathComponent("source.txt")
        try Data("sibling".utf8).write(to: siblingFile)
        let store = ZoteroOriginalAccessStore(applicationSupportURL: fixture.support)
        try await store.authorize(selectedURL: fixture.originals)
        for path in [linked, linkedDirectory.appendingPathComponent("private.txt")] {
            do {
                _ = try await store.readOriginal(at: path, maximumByteCount: 1024)
                Issue.record("A symbolic-link original was read")
            } catch let error as POSIXError {
                #expect(error.code == .ELOOP || error.code == .ENOTDIR)
            }
        }
        await #expect(throws: CocoaError.self) { try await store.readOriginal(at: siblingFile, maximumByteCount: 1024) }
        await #expect(throws: ZoteroOriginalAccessError.self) { try await store.authorize(selectedURL: linked) }
        let large = fixture.originals.appendingPathComponent("large.txt")
        try Data(repeating: 65, count: 2048).write(to: large)
        do {
            _ = try await store.readOriginal(at: large, maximumByteCount: 1024)
            Issue.record("An oversized original was read")
        } catch let error as POSIXError { #expect(error.code == .EFBIG) }
        #expect(try Data(contentsOf: outside) == Data("outside grant".utf8))
    }

    @Test("Unsupported saved grants grant no access and remain byte-exact")
    func unsupportedStorage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ZoteroOriginalAccessStore(applicationSupportURL: fixture.support)
        try await store.authorize(selectedURL: fixture.originals)
        let storage = fixture.support.appendingPathComponent("Zotero/original-access/original-access-v1.json")
        let unsupported = Data("{\"schemaVersion\":999,\"bindings\":[]}".utf8)
        try unsupported.write(to: storage)
        await #expect(throws: ZoteroOriginalAccessError.self) { try await store.grants() }
        await #expect(throws: ZoteroOriginalAccessError.self) { try await store.authorize(selectedURL: fixture.originals) }
        #expect(try Data(contentsOf: storage) == unsupported)
    }

    @Test("An expired exact-file grant cannot block a separately selected live folder grant")
    func separatelyAuthorizedFolder() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = fixture.originals.appendingPathComponent("source.txt")
        try Data("old original".utf8).write(to: original)
        let store = ZoteroOriginalAccessStore(applicationSupportURL: fixture.support)
        try await store.authorize(selectedURL: original)
        try await store.authorize(selectedURL: fixture.originals)
        try FileManager.default.moveItem(at: original, to: fixture.originals.appendingPathComponent("old.txt"))
        try Data("current original".utf8).write(to: original)
        #expect(try await store.grants().first(where: { $0.kind == .file })?.status == .accessRequired)
        #expect(try await store.readOriginal(at: original, maximumByteCount: 1024) == Data("current original".utf8))
    }

    @Test("Moving an opened leaf or its parent out of the selected root cannot publish detached bytes", arguments: [false, true])
    func substitutionAfterRead(moveDirectory: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let nested = fixture.originals.appendingPathComponent("ATTACH01", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let original = nested.appendingPathComponent("source.txt")
        let bytes = Data("original bytes".utf8)
        try bytes.write(to: original)
        let moved = fixture.root.appendingPathComponent(moveDirectory ? "DetachedDirectory" : "detached.txt")
        let store = ZoteroOriginalAccessStore(
            applicationSupportURL: fixture.support,
            beforeReadbackFault: {
                if moveDirectory {
                    try FileManager.default.moveItem(at: nested, to: moved)
                    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
                } else {
                    try FileManager.default.moveItem(at: original, to: moved)
                }
                try Data("replacement bytes".utf8).write(to: original)
            })
        try await store.authorize(selectedURL: fixture.originals)
        do {
            _ = try await store.readOriginal(at: original, maximumByteCount: 1024)
            Issue.record("Detached original bytes were published after a path substitution")
        } catch let error as POSIXError { #expect(error.code == .ELOOP || error.code == .EIO) }
        #expect(try Data(contentsOf: original) == Data("replacement bytes".utf8))
        #expect(try Data(contentsOf: moveDirectory ? moved.appendingPathComponent("source.txt") : moved) == bytes)
    }

    private struct Fixture {
        let root: URL
        let support: URL
        let originals: URL

        init() throws {
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            root = repository.appendingPathComponent(".build/zotero-original-access-tests/\(UUID().uuidString)")
            support = root.appendingPathComponent("Support", isDirectory: true)
            originals = root.appendingPathComponent("Originals", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
