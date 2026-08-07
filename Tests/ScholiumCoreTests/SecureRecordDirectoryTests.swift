import Foundation
@testable import ScholiumCore
import Testing

@Suite("Secure record directory")
struct SecureRecordDirectoryTests {
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
        #expect(!FileManager.default.fileExists(atPath: root
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
