import Foundation
import Testing
@testable import ScholiumContracts
@testable import ScholiumCore

@Suite("Machine-local Research Source Access store", .serialized)
struct ResearchSourceAccessStoreTests {
    @Test("A selected regular file reopens through a balanced bookmark lease")
    func bindResolveAndReopen() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.file(named: "Source.pdf", bytes: Data("source".utf8))
        let probe = BookmarkProbe(url: source)
        let noteID = UUID()
        let store = fixture.store(bookmarkAccess: probe.access)

        let reference = try await store.bindLocalFile(
            analysisNoteID: noteID,
            selectedURL: source
        )
        #expect(reference.displayName == "Source.pdf")
        #expect(reference.fingerprint == DocumentFingerprint(content: "source"))
        #expect(probe.counts == (starts: 2, stops: 2))

        let reopened = fixture.store(bookmarkAccess: probe.access)
        let resolved = try await reopened.resolve(analysisNoteID: noteID)
        #expect(resolved.reference == reference)
        #expect(resolved.fileURL == source.standardizedFileURL)
        #expect(probe.counts == (starts: 3, stops: 3))

        let attributes = try FileManager.default.attributesOfItem(
            atPath: fixture.bindingURL.path
        )
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let stored = try Data(contentsOf: fixture.bindingURL)
        let payload = try #require(
            JSONSerialization.jsonObject(with: stored) as? [String: Any]
        )
        let bindings = try #require(payload["bindings"] as? [[String: Any]])
        #expect(bindings.first?["canonicalPath"] as? String == source.path)
        #expect(String(decoding: stored, as: UTF8.self).contains("bookmarkData"))
    }

    @Test("Changed bytes block reuse until the researcher binds again")
    func changedFileFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.file(named: "Source.txt", bytes: Data("first".utf8))
        let store = fixture.store()
        let noteID = UUID()
        _ = try await store.bindLocalFile(analysisNoteID: noteID, selectedURL: source)

        try Data("second".utf8).write(to: source)
        let status = await store.status(analysisNoteID: noteID)
        #expect(status.state == .repairRequired)
        #expect(status.failure?.code == .sourceChanged)
        #expect(status.reference?.displayName == "Source.txt")

        let rebound = try await store.bindLocalFile(
            analysisNoteID: noteID,
            selectedURL: source
        )
        #expect(rebound.identity.id == status.reference?.identity.id)
        #expect(rebound.fingerprint == DocumentFingerprint(content: "second"))
    }

    @Test("Stale and unavailable bookmarks fail closed and balance successful starts")
    func bookmarkLifecycle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.file(named: "Source.txt", bytes: Data("source".utf8))
        let probe = BookmarkProbe(url: source)
        let store = fixture.store(bookmarkAccess: probe.access)
        let noteID = UUID()
        _ = try await store.bindLocalFile(analysisNoteID: noteID, selectedURL: source)

        probe.isStale = true
        #expect(await store.status(analysisNoteID: noteID).failure?.code == .bookmarkStale)
        #expect(probe.counts == (starts: 2, stops: 2))

        probe.isStale = false
        probe.allowsStart = false
        #expect(
            await store.status(analysisNoteID: noteID).failure?.code
                == .bookmarkUnavailable
        )
        #expect(probe.counts == (starts: 3, stops: 2))
    }

    @Test("Symlinks, directories, and missing files never become source bindings")
    func rejectsNonregularAndSymlinkSources() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let regular = try fixture.file(named: "Regular.txt", bytes: Data("source".utf8))
        let link = fixture.root.appendingPathComponent("Link.txt")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: regular
        )
        let realDirectory = fixture.root.appendingPathComponent(
            "Real Sources",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: realDirectory,
            withIntermediateDirectories: true
        )
        let nested = realDirectory.appendingPathComponent("Nested.txt")
        try Data("nested".utf8).write(to: nested, options: .atomic)
        let linkedDirectory = fixture.root.appendingPathComponent(
            "Linked Sources",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: linkedDirectory,
            withDestinationURL: realDirectory
        )
        let store = fixture.store()

        await expectFailure(.sourceIsSymbolicLink) {
            _ = try await store.bindLocalFile(
                analysisNoteID: UUID(),
                selectedURL: link
            )
        }
        await expectFailure(.sourceNotRegular) {
            _ = try await store.bindLocalFile(
                analysisNoteID: UUID(),
                selectedURL: fixture.root
            )
        }
        await expectFailure(.sourceIsSymbolicLink) {
            _ = try await store.bindLocalFile(
                analysisNoteID: UUID(),
                selectedURL: linkedDirectory.appendingPathComponent("Nested.txt")
            )
        }
        await expectFailure(.sourceMissing) {
            _ = try await store.bindLocalFile(
                analysisNoteID: UUID(),
                selectedURL: fixture.root.appendingPathComponent("Missing.pdf")
            )
        }
    }

    @Test("Corrupt or cross-Triptych binding data is never rewritten")
    func corruptBindingFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.storage,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: fixture.storage.path
        )
        let original = Data("{\"schemaVersion\":99}".utf8)
        try original.write(to: fixture.bindingURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: fixture.bindingURL.path
        )
        let store = fixture.store()
        #expect(await store.status(analysisNoteID: UUID()).failure?.code == .corruptBinding)
        #expect(try Data(contentsOf: fixture.bindingURL) == original)
    }

    @Test("Choosing a valid source atomically replaces corrupt private bytes")
    func validReselectionRepairsCorruptBinding() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.file(named: "Source.txt", bytes: Data("source".utf8))
        try FileManager.default.createDirectory(
            at: fixture.storage,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: fixture.storage.path
        )
        let original = Data("not-json".utf8)
        try original.write(to: fixture.bindingURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: fixture.bindingURL.path
        )

        let rebound = try await fixture.store().bindLocalFile(
            analysisNoteID: UUID(),
            selectedURL: source
        )
        #expect(rebound.fingerprint == DocumentFingerprint(content: "source"))
        let quarantined = try FileManager.default.contentsOfDirectory(
            at: fixture.storage,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("source-bindings-v1.corrupt-") }
        #expect(quarantined.isEmpty)
        #expect(try Data(contentsOf: fixture.bindingURL) != original)
    }

    @Test("A binding-file symlink is quarantined without touching its target")
    func bindingSymlinkCannotEscapeStore() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.file(named: "Source.txt", bytes: Data("source".utf8))
        let outside = try fixture.file(named: "Outside.json", bytes: Data("sentinel".utf8))
        try FileManager.default.createDirectory(
            at: fixture.storage,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: fixture.storage.path
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.bindingURL,
            withDestinationURL: outside
        )

        let store = fixture.store()
        #expect(await store.status(analysisNoteID: UUID()).failure?.code == .corruptBinding)
        _ = try await store.bindLocalFile(
            analysisNoteID: UUID(),
            selectedURL: source
        )
        #expect(try Data(contentsOf: outside) == Data("sentinel".utf8))
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fixture.bindingURL.path
        )
        #expect((attributes[.type] as? FileAttributeType) == .typeRegular)
    }

    @Test("A non-regular binding leaf is quarantined by exact directory entry")
    func bindingDirectoryCanBeRepaired() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.file(named: "Source.txt", bytes: Data("source".utf8))
        try FileManager.default.createDirectory(
            at: fixture.storage,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: fixture.storage.path
        )
        try FileManager.default.createDirectory(
            at: fixture.bindingURL,
            withIntermediateDirectories: false
        )

        let store = fixture.store()
        #expect(await store.status(analysisNoteID: UUID()).failure?.code == .corruptBinding)
        _ = try await store.bindLocalFile(
            analysisNoteID: UUID(),
            selectedURL: source
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fixture.bindingURL.path
        )
        #expect((attributes[.type] as? FileAttributeType) == .typeRegular)
    }

    @Test("A hard-linked binding leaf cannot expose or chmod an outside inode")
    func bindingHardLinkCannotEscapeStore() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.file(named: "Source.txt", bytes: Data("source".utf8))
        let outside = try fixture.file(named: "Outside.json", bytes: Data("sentinel".utf8))
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o644)],
            ofItemAtPath: outside.path
        )
        try FileManager.default.createDirectory(
            at: fixture.storage,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: fixture.storage.path
        )
        try FileManager.default.linkItem(at: outside, to: fixture.bindingURL)

        let store = fixture.store()
        #expect(await store.status(analysisNoteID: UUID()).failure?.code == .corruptBinding)
        _ = try await store.bindLocalFile(
            analysisNoteID: UUID(),
            selectedURL: source
        )
        #expect(try Data(contentsOf: outside) == Data("sentinel".utf8))
        let outsideAttributes = try FileManager.default.attributesOfItem(
            atPath: outside.path
        )
        #expect((outsideAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o644)
    }

    @Test("A symlink in an owned storage ancestor cannot redirect persistence")
    func ancestorSymlinkCannotEscapeStore() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.file(named: "Source.txt", bytes: Data("source".utf8))
        let outside = fixture.root.appendingPathComponent("Outside", isDirectory: true)
        let triptychs = fixture.root.appendingPathComponent("Triptychs", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: triptychs,
            withDestinationURL: outside
        )
        let probe = BookmarkProbe(url: source)
        let store = ResearchSourceAccessStore(
            trustedRootURL: fixture.root,
            storageComponents: ["Triptychs", fixture.triptychID.uuidString, "source-access"],
            triptychID: fixture.triptychID,
            bookmarkAccess: probe.access
        )

        await expectFailure(.corruptBinding) {
            _ = try await store.bindLocalFile(
                analysisNoteID: UUID(),
                selectedURL: source
            )
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: outside.appendingPathComponent(fixture.triptychID.uuidString).path
            )
        )
    }

    @Test("Overbroad private-store permissions fail closed")
    func permissionDriftFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.file(named: "Source.txt", bytes: Data("source".utf8))
        let peerSource = try fixture.file(
            named: "Peer Source.txt",
            bytes: Data("peer source".utf8)
        )
        let noteID = UUID()
        let peerNoteID = UUID()
        let store = fixture.store()
        _ = try await store.bindLocalFile(analysisNoteID: noteID, selectedURL: source)
        let peerReference = try await store.bindLocalFile(
            analysisNoteID: peerNoteID,
            selectedURL: peerSource
        )

        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o644)],
            ofItemAtPath: fixture.bindingURL.path
        )
        #expect(await store.status(analysisNoteID: noteID).failure?.code == .corruptBinding)

        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: fixture.storage.path
        )
        #expect(await store.status(analysisNoteID: noteID).failure?.code == .corruptBinding)
        _ = try await store.bindLocalFile(
            analysisNoteID: noteID,
            selectedURL: source
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fixture.storage.path
        )
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect(await store.status(analysisNoteID: noteID).state == .available)
        #expect(
            try await store.resolve(analysisNoteID: peerNoteID).reference
                == peerReference
        )
    }

    private func expectFailure(
        _ expected: ResearchSourceAccessFailureCode,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected source access failure \(expected.rawValue).")
        } catch let error as ResearchSourceAccessStoreError {
            #expect(error.failure.code == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private final class BookmarkProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private var _starts = 0
    private var _stops = 0
    private var _isStale = false
    private var _allowsStart = true

    init(url: URL) {
        self.url = url.standardizedFileURL
    }

    var isStale: Bool {
        get { lock.withLock { _isStale } }
        set { lock.withLock { _isStale = newValue } }
    }

    var allowsStart: Bool {
        get { lock.withLock { _allowsStart } }
        set { lock.withLock { _allowsStart = newValue } }
    }

    var counts: (starts: Int, stops: Int) {
        lock.withLock { (_starts, _stops) }
    }

    var access: ResearchSourceBookmarkAccess {
        ResearchSourceBookmarkAccess(
            create: { _ in Data("bookmark".utf8) },
            resolve: { [self] _ in
                ResearchSourceBookmarkResolution(url: url, isStale: isStale)
            },
            start: { [self] _ in
                lock.withLock {
                    _starts += 1
                    return _allowsStart
                }
            },
            stop: { [self] _ in
                lock.withLock { _stops += 1 }
            }
        )
    }
}

private struct Fixture {
    let root: URL
    let storage: URL
    let triptychID = UUID()

    init() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        root = repositoryRoot
            .appendingPathComponent(".build/test-fixtures", isDirectory: true)
            .appendingPathComponent(
            "ScholiumResearchSourceStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        storage = root.appendingPathComponent("Source Access", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var bindingURL: URL {
        storage.appendingPathComponent("source-bindings-v1.json")
    }

    func file(named name: String, bytes: Data) throws -> URL {
        let url = root.appendingPathComponent(name)
        try bytes.write(to: url, options: .atomic)
        return url
    }

    func store(
        bookmarkAccess: ResearchSourceBookmarkAccess = .foundation
    ) -> ResearchSourceAccessStore {
        ResearchSourceAccessStore(
            storageURL: storage,
            triptychID: triptychID,
            bookmarkAccess: bookmarkAccess
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
