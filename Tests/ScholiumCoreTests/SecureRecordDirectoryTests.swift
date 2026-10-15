import Foundation
import Testing

@testable import ScholiumCore

@Suite("Secure record directory")
struct SecureRecordDirectoryTests {
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
