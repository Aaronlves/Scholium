import Darwin
import Foundation
import Testing

@testable import ScholiumCore

@Suite("Secure record directory")
struct SecureRecordDirectoryTests {
    @Test("Independent enumeration leaves the anchored descriptor available for preflight, deletion and verification")
    func repeatedAnchoredEnumeration() throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = SecureRecordDirectory(
            trustedRootURL: root, components: ["repeated"], directoryMode: 0o700,
            fileMode: 0o600, maximumByteCount: 1_024)
        let bytes = Data("generated record".utf8)
        _ = try directory.replace(bytes, directory: nil, fileName: "state.json")
        let lock = try directory.openLockFile(".coordination.lock")
        defer { Darwin.close(lock) }
        let parent = try directory.openStorageDirectory(createIfMissing: false)
        defer { Darwin.close(parent) }
        let initialOffset = lseek(parent, 0, SEEK_CUR)
        #expect(initialOffset >= 0)
        let expected = [".coordination.lock", "state.json"]
        #expect(try directory.fileNames(parent: parent, includingStaging: true) == expected)
        #expect(lseek(parent, 0, SEEK_CUR) == initialOffset)
        #expect(try directory.fileNames(parent: parent, includingStaging: true) == expected)
        #expect(lseek(parent, 0, SEEK_CUR) == initialOffset)
        let retained = root.appendingPathComponent("retained", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = Data("outside bytes remain exact".utf8)
        try sentinel.write(to: outside.appendingPathComponent("state.json"))
        try FileManager.default.moveItem(at: directory.directoryURL, to: retained)
        try FileManager.default.createSymbolicLink(at: directory.directoryURL, withDestinationURL: outside)
        #expect(throws: SecureRecordDirectoryError.self) { try directory.fileNames(in: nil) }
        #expect(try directory.fileNames(parent: parent, includingStaging: true) == expected)
        #expect("state.json".withCString { unlinkat(parent, $0, 0) } == 0)
        #expect(try directory.fileNames(parent: parent, includingStaging: true) == [".coordination.lock"])
        #expect(try directory.fileNames(parent: parent, includingStaging: true) == [".coordination.lock"])
        var held = stat()
        var current = stat()
        #expect(fstat(lock, &held) == 0)
        #expect(".coordination.lock".withCString { fstatat(parent, $0, &current, AT_SYMLINK_NOFOLLOW) } == 0)
        #expect(SecureRecordDirectory.sameFile(held, current))
        #expect(current.st_nlink == 1)
        #expect(try Data(contentsOf: outside.appendingPathComponent("state.json")) == sentinel)
    }

    @Test("Binary record extensions require explicit ownership and retain contained bounded writes")
    func explicitlyOwnedBinaryRecords() throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let jsonOnly = SecureRecordDirectory(
            trustedRootURL: root, components: ["json-only"], directoryMode: 0o700,
            fileMode: 0o600, maximumByteCount: 1_024)
        #expect(throws: SecureRecordDirectoryError.self) {
            try jsonOnly.replace(Data(), directory: nil, fileName: "state.plist")
        }
        let binary = SecureRecordDirectory(
            trustedRootURL: root, components: ["binary"], directoryMode: 0o700,
            fileMode: 0o600, maximumByteCount: 1_024, fileExtensions: [.plist])
        let bytes = Data([0, 0xff, 0, 1, 2])
        #expect(try binary.replace(bytes, directory: nil, fileName: "state.plist") == bytes)
        #expect(try binary.read(directory: nil, fileName: "state.plist") == bytes)
        for name in ["../outside.plist", "/outside.plist", "state.json", "state.md"] {
            #expect(throws: SecureRecordDirectoryError.self) {
                try binary.replace(bytes, directory: nil, fileName: name)
            }
        }
        #expect(throws: SecureRecordDirectoryError.self) {
            try binary.replace(Data(repeating: 0, count: 1_025), directory: nil, fileName: "oversize.plist")
        }
        #expect(try binary.read(directory: nil, fileName: "state.plist") == bytes)
    }

    @Test("A post-rename failure leaves exact committed bytes observable")
    func secureReplacementReportsPostRenameUncertainty() throws {
        enum InjectedFailure: Error { case afterRename }
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = SecureRecordDirectory(
            trustedRootURL: root,
            components: ["post-rename-fault"],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: 1_024,
            postCommitFault: { _ in throw InjectedFailure.afterRename }
        )
        try directory.ensureDirectories([])
        let expected = Data("exact committed state".utf8)

        do {
            _ = try directory.replace(
                expected,
                directory: nil,
                fileName: "state.json"
            )
            Issue.record("Expected typed post-rename commit uncertainty.")
        } catch let error as SecureRecordDirectoryError {
            guard case .replacementCommitUncertain = error else {
                Issue.record("Unexpected replacement error: \(error)")
                return
            }
        }
        #expect(try directory.read(directory: nil, fileName: "state.json") == expected)

        do {
            _ = try directory.replace(
                Data(repeating: 0, count: 2_048),
                directory: nil,
                fileName: "oversize.json"
            )
            Issue.record("Expected typed pre-rename refusal.")
        } catch let error as SecureRecordDirectoryError {
            guard case .replacementNotCommitted = error else {
                Issue.record("Unexpected replacement error: \(error)")
                return
            }
        }
        #expect(
            !FileManager.default.fileExists(
                atPath:
                    root
                    .appendingPathComponent("post-rename-fault/oversize.json").path))
    }

    private func fixtureRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/secure-record-directory-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
