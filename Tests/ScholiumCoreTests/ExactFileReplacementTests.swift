import Darwin
import Foundation
import Testing

@testable import ScholiumCore

@Suite("Exact configuration-file replacement")
struct ExactFileReplacementTests {
    @Test("An absent-file claim cannot overwrite a final-window writer")
    func absentClaimRace() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let external = Data("external".utf8)
        #expect(throws: ExactFileReplacementError.self) {
            try ExactFileReplacement.replace(
                at: fixture.target, expected: nil, candidate: Data("default".utf8),
                preCommitHook: { try external.write(to: $0) }
            )
        }
        #expect(try Data(contentsOf: fixture.target) == external)
    }

    @Test("Directory substitution cannot redirect recovery or replacement")
    func directorySubstitution() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = Data("original".utf8)
        try original.write(to: fixture.target)
        let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let outsideTarget = outside.appendingPathComponent("config.json")
        try original.write(to: outsideTarget)
        let displaced = fixture.root.appendingPathComponent("displaced", isDirectory: true)
        let directory = fixture.directory
        #expect(throws: ExactFileReplacementError.self) {
            try ExactFileReplacement.replace(
                at: fixture.target, expected: original, candidate: Data("defaults".utf8), preserveOriginal: true,
                preCommitHook: { _ in
                    try FileManager.default.moveItem(at: directory, to: displaced)
                    try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: outside)
                }
            )
        }
        #expect(try Data(contentsOf: outsideTarget) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path) == ["config.json"])
        #expect(try Data(contentsOf: displaced.appendingPathComponent("config.json")) == original)
        let backups = try FileManager.default.contentsOfDirectory(at: displaced, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".recovery-") }
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: #require(backups.first)) == original)
    }

    @Test("Final-window symlink substitution is restored without following its target")
    func fileSymlinkSubstitution() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = Data("original".utf8)
        try original.write(to: fixture.target)
        let outside = fixture.root.appendingPathComponent("outside.json")
        let outsideBytes = Data("outside".utf8)
        try outsideBytes.write(to: outside)
        #expect(throws: ExactFileReplacementError.self) {
            try ExactFileReplacement.replace(
                at: fixture.target, expected: original, candidate: Data("defaults".utf8), preserveOriginal: true,
                preCommitHook: { target in
                    try FileManager.default.removeItem(at: target)
                    try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
                }
            )
        }
        #expect(try Data(contentsOf: outside) == outsideBytes)
        #expect(try fixture.target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    }

    @Test("A changed backup leaves the displaced exact original available and reports uncertainty")
    func backupChangedBeforeProof() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = Data("original".utf8)
        try original.write(to: fixture.target)
        do {
            _ = try ExactFileReplacement.replace(
                at: fixture.target, expected: original, candidate: Data("defaults".utf8), preserveOriginal: true,
                postCommitHook: { target in
                    let backups = try FileManager.default.contentsOfDirectory(at: target.deletingLastPathComponent(), includingPropertiesForKeys: nil)
                        .filter { $0.lastPathComponent.contains(".recovery-") }
                    try Data("changed backup".utf8).write(to: #require(backups.first))
                }
            )
            Issue.record("Recovery proof must fail after its backup changes.")
        } catch ExactFileReplacementError.commitUncertain {}
        let staged = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("-staging-") }
        #expect(staged.count == 1)
        #expect(try Data(contentsOf: #require(staged.first)) == original)
    }

    @Test("Ordinary replacement uncertainty retains displaced source bytes")
    func ordinarySaveUncertainty() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = Data("original".utf8)
        try original.write(to: fixture.target)
        do {
            _ = try ExactFileReplacement.replace(
                at: fixture.target, expected: original, candidate: Data("saved".utf8),
                postCommitHook: { _ in throw POSIXError(.EIO) }
            )
            Issue.record("The injected post-commit failure must be reported.")
        } catch ExactFileReplacementError.commitUncertain {}
        let staged = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("-staging-") }
        #expect(staged.count == 1)
        #expect(try Data(contentsOf: #require(staged.first)) == original)
        #expect(try Data(contentsOf: fixture.target) == Data("saved".utf8))
    }

    @Test("Nonregular and oversized configuration files cannot enter a transaction")
    func boundedRegularReads() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(mkfifo(fixture.target.path, 0o600) == 0)
        #expect(throws: POSIXError.self) {
            try ExactFileReplacement.replace(at: fixture.target, expected: nil, candidate: Data())
        }
        try FileManager.default.removeItem(at: fixture.target)
        try Data(repeating: 0, count: 16 * 1_024 * 1_024 + 1).write(to: fixture.target)
        #expect(throws: POSIXError.self) {
            try ExactFileReplacement.replace(at: fixture.target, expected: nil, candidate: Data())
        }
        #expect(try FileManager.default.attributesOfItem(atPath: fixture.target.path)[.size] as? Int == 16 * 1_024 * 1_024 + 1)
    }

    @Test("A second final-window writer survives an unproven conflict rollback")
    func rollbackPreservesSecondWriter() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = Data("original".utf8)
        let firstWriter = Data("first external revision".utf8)
        let secondWriter = Data("second external revision".utf8)
        try original.write(to: fixture.target)
        do {
            _ = try ExactFileReplacement.replace(
                at: fixture.target, expected: original, candidate: Data("saved".utf8),
                preCommitHook: { try firstWriter.write(to: $0, options: .atomic) },
                preRollbackHook: { try secondWriter.write(to: $0, options: .atomic) }
            )
            Issue.record("The rollback displaced an unobserved writer and must report uncertainty.")
        } catch ExactFileReplacementError.commitUncertain {}
        let staged = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("-staging-") }
        #expect(staged.count == 1)
        #expect(try Data(contentsOf: #require(staged.first)) == secondWriter)
        #expect(try Data(contentsOf: fixture.target) == firstWriter)
    }

    @Test("Nonregular rollback-displaced entries remain available after uncertainty", arguments: ["symlink", "fifo"])
    func rollbackPreservesNonregularSecondWriter(kind: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = Data("original".utf8)
        let firstWriter = Data("first external revision".utf8)
        try original.write(to: fixture.target)
        let outside = fixture.root.appendingPathComponent("outside.json")
        let outsideBytes = Data("outside bytes".utf8)
        try outsideBytes.write(to: outside)
        do {
            _ = try ExactFileReplacement.replace(
                at: fixture.target, expected: original, candidate: Data("saved".utf8),
                preCommitHook: { try firstWriter.write(to: $0, options: .atomic) },
                preRollbackHook: { target in
                    try FileManager.default.removeItem(at: target)
                    if kind == "symlink" {
                        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
                    } else {
                        guard mkfifo(target.path, 0o600) == 0 else { throw POSIXError(.EIO) }
                    }
                }
            )
            Issue.record("The rollback displaced a nonregular entry and must report uncertainty.")
        } catch ExactFileReplacementError.commitUncertain {}
        let staged = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("-staging-") }
        #expect(staged.count == 1)
        var status = stat()
        #expect(lstat(try #require(staged.first).path, &status) == 0)
        #expect((status.st_mode & S_IFMT) == (kind == "symlink" ? S_IFLNK : S_IFIFO))
        #expect(try Data(contentsOf: fixture.target) == firstWriter)
        #expect(try Data(contentsOf: outside) == outsideBytes)
    }

    private struct Fixture: Sendable {
        let root: URL
        let directory: URL
        let target: URL
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("Scholium-Exact-Configuration-\(UUID().uuidString)", isDirectory: true)
            directory = root.appendingPathComponent("owned", isDirectory: true)
            target = directory.appendingPathComponent("config.json")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
