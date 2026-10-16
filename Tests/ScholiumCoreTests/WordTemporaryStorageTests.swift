import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Managed generated Word temporary storage")
struct WordTemporaryStorageTests {
    @Test("Independent live jobs do not retain the root lock and cleanup preserves every active job", .timeLimit(.minutes(1)))
    func activeJobsAndCompletedRemoval() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try DerivedStateStorage.makeWordTemporaryDirectory(applicationSupportURL: fixture.support)
        let second = try DerivedStateStorage.makeWordTemporaryDirectory(applicationSupportURL: fixture.support)
        let bytes = Data("generated archive".utf8)
        try bytes.write(to: first.url.appendingPathComponent("source.docx"))
        try bytes.write(to: second.url.appendingPathComponent("document.docx"))
        let busy = try DerivedStateStorage.clearWordTemporaryDirectories(applicationSupportURL: fixture.support)
        #expect(busy.busyDirectories == 2 && busy.removedFiles == 0 && busy.failedFiles == 0)
        #expect(try Data(contentsOf: first.url.appendingPathComponent("source.docx")) == bytes)
        try first.remove()
        #expect(!FileManager.default.fileExists(atPath: first.url.path))
        let remaining = try DerivedStateStorage.clearWordTemporaryDirectories(applicationSupportURL: fixture.support)
        #expect(remaining.busyDirectories == 1 && remaining.removedFiles == 0)
        #expect(try Data(contentsOf: second.url.appendingPathComponent("document.docx")) == bytes)
        try second.remove()
        try first.remove()
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.wordRoot.path) == [DerivedStateStorage.lockFileName])
    }

    @Test("Abandoned and previously isolated jobs are reclaimed while future and unknown namespaces survive", arguments: [false, true])
    func abandonedJobsAndUnknownFormats(isolated: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var job: ScholiumWordTemporaryDirectory? = try DerivedStateStorage.makeWordTemporaryDirectory(applicationSupportURL: fixture.support)
        let url = try #require(job?.url)
        let package = url.appendingPathComponent("package/word", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let source = Data("generated archive".utf8)
        let xml = Data("generated package part".utf8)
        try source.write(to: url.appendingPathComponent("source.docx"))
        try xml.write(to: package.appendingPathComponent("document.xml"))
        job = nil
        let abandoned: URL
        if isolated {
            abandoned = url.deletingLastPathComponent().appendingPathComponent(".word-removing-\(url.lastPathComponent)", isDirectory: true)
            try FileManager.default.moveItem(at: url, to: abandoned)
        } else {
            abandoned = url
        }
        let future = fixture.support.appendingPathComponent("Temporary/WordExports-v2/\(UUID().uuidString)/private.docx")
        try FileManager.default.createDirectory(at: future.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("future unchanged".utf8).write(to: future)
        let unknown = fixture.wordRoot.appendingPathComponent("unknown-job", isDirectory: true)
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: true)
        try source.write(to: unknown.appendingPathComponent("source.docx"))
        let result = try DerivedStateStorage.clearWordTemporaryDirectories(applicationSupportURL: fixture.support)
        #expect(result.removedFiles == 3 && result.removedBytes == Int64(source.count + xml.count))
        #expect(result.busyDirectories == 0 && result.failedFiles == 0 && result.preservedFiles == 1)
        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
        #expect(try Data(contentsOf: future) == Data("future unchanged".utf8))
        #expect(try Data(contentsOf: unknown.appendingPathComponent("source.docx")) == source)
    }

    @Test("Unknown job payloads and links are preserved without removing neighboring bytes", arguments: [false, true])
    func unsafeJobContentsRemain(hardLink: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var job: ScholiumWordTemporaryDirectory? = try DerivedStateStorage.makeWordTemporaryDirectory(applicationSupportURL: fixture.support)
        let url = try #require(job?.url)
        let outside = fixture.root.appendingPathComponent("outside-source.md")
        let bytes = Data("exact source sentinel".utf8)
        try bytes.write(to: outside)
        let linked = url.appendingPathComponent("source.docx")
        if hardLink {
            try FileManager.default.linkItem(at: outside, to: linked)
        } else {
            try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
        }
        job = nil
        let result = try DerivedStateStorage.clearWordTemporaryDirectories(applicationSupportURL: fixture.support)
        #expect(result.removedFiles == 0 && result.removedBytes == 0 && result.preservedFiles == 1)
        #expect(try Data(contentsOf: outside) == bytes)
        #expect(FileManager.default.fileExists(atPath: linked.path))

        let unidentified = fixture.wordRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: unidentified, withIntermediateDirectories: true)
        let futureBytes = Data("unknown format without current job lock".utf8)
        try futureBytes.write(to: unidentified.appendingPathComponent("future-format.bin"))
        _ = try DerivedStateStorage.clearWordTemporaryDirectories(applicationSupportURL: fixture.support)
        #expect(try FileManager.default.contentsOfDirectory(atPath: unidentified.path) == ["future-format.bin"])
        #expect(try Data(contentsOf: unidentified.appendingPathComponent("future-format.bin")) == futureBytes)
    }

    @Test("Completed cleanup still runs in a cancelled task; inventory and clearing never create missing roots")
    func cancellationAndAbsence() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(try DerivedStateStorage.clearWordTemporaryDirectories(applicationSupportURL: fixture.support) == ScholiumStorageClearResult())
        #expect(!FileManager.default.fileExists(atPath: fixture.wordRoot.path))
        let job = try DerivedStateStorage.makeWordTemporaryDirectory(applicationSupportURL: fixture.support)
        try Data("generated".utf8).write(to: job.url.appendingPathComponent("document.docx"))
        let cleanup = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try job.remove()
        }
        try await cleanup.value
        #expect(!FileManager.default.fileExists(atPath: job.url.path))
    }

    @Test("An internal Temporary symlink cannot authorize creation or cleanup outside State-v1")
    func temporaryAncestorSubstitution() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = outside.appendingPathComponent("untouched.md")
        let bytes = Data("outside is not generated state".utf8)
        try bytes.write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: fixture.support.appendingPathComponent("Temporary"), withDestinationURL: outside)
        #expect(throws: SecureRecordDirectoryError.self) { try DerivedStateStorage.makeWordTemporaryDirectory(applicationSupportURL: fixture.support) }
        #expect(throws: SecureRecordDirectoryError.self) { try DerivedStateStorage.clearWordTemporaryDirectories(applicationSupportURL: fixture.support) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path) == ["untouched.md"])
        #expect(try Data(contentsOf: sentinel) == bytes)
    }

    private struct Fixture {
        let root: URL
        let support: URL
        var wordRoot: URL { support.appendingPathComponent("Temporary/WordExports-v1", isDirectory: true) }
        init() throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/word-temporary-storage-tests/\(UUID().uuidString)", isDirectory: true)
            support = root.appendingPathComponent("State-v1", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
