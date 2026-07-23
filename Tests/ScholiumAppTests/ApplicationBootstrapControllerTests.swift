import Foundation
import Testing
@testable import ScholiumApp

@Suite("Application storage bootstrap", .serialized)
@MainActor
struct ApplicationBootstrapControllerTests {
    @Test("Storage failure constructs no runtime and Retry is the only entry to ready")
    func failureThenRetry() async throws {
        let supportURL = testRoot()
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
        var attempts = 0
        let controller = ApplicationBootstrapController {
            attempts += 1
            if attempts == 1 { throw CocoaError(.fileWriteNoPermission) }
            return supportURL
        }

        controller.startIfNeeded()
        await waitUntilSettled(controller)
        guard case .storageUnavailable(let failure) = controller.state else {
            Issue.record("A failed resolver constructed or exposed a Workspace runtime.")
            return
        }
        #expect(failure.summary.contains("Application Support"))
        #expect(!controller.isReady)
        #expect(!FileManager.default.fileExists(atPath: supportURL.path))

        controller.retry()
        await waitUntilSettled(controller)
        guard case .ready(let store) = controller.state else {
            Issue.record("Retry did not construct the runtime after storage became available.")
            return
        }
        #expect(controller.isReady)
        #expect(store.applicationSupportURL == supportURL.standardizedFileURL)
        await store.shutdownApplicationRuntime()
        try? FileManager.default.removeItem(at: supportURL.deletingLastPathComponent())
    }

    @Test("WorkspaceStore refuses an Application Support path below a regular file")
    func storeInitializationFailsClosed() throws {
        let root = testRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blocker = root.appendingPathComponent("not-a-directory")
        try Data("block".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: (any Error).self) {
            _ = try WorkspaceStore(
                applicationSupportURL: blocker.appendingPathComponent(
                    "ApplicationSupport",
                    isDirectory: true
                )
            )
        }
    }

    private func waitUntilSettled(
        _ controller: ApplicationBootstrapController
    ) async {
        for _ in 0..<100 {
            if case .starting = controller.state {
                await Task.yield()
            } else {
                return
            }
        }
    }

    private func testRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/bootstrap-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
    }
}
