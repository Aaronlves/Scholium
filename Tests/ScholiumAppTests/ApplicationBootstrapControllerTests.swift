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

    @Test("Damaged registry stays at the app root until relinking preserves it")
    func damagedRegistryRequiresExplicitRelinking() async throws {
        let supportURL = testRoot()
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
        let registryURL = supportURL
            .appendingPathComponent("Workspace", isDirectory: true)
            .appendingPathComponent("workspace-registration-v3.json")
        try FileManager.default.createDirectory(
            at: registryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let damaged = Data("damaged registry bytes".utf8)
        try damaged.write(to: registryURL)
        defer { try? FileManager.default.removeItem(at: supportURL.deletingLastPathComponent()) }

        let controller = ApplicationBootstrapController { supportURL }
        controller.startIfNeeded()
        await waitUntilSettled(controller)
        guard case .registryRecovery(let recovery) = controller.state else {
            Issue.record("A damaged registry entered Bootstrap or constructed a runtime.")
            return
        }
        guard case .triptych(let health, let observedRegistryURL) = recovery.source else {
            Issue.record("The damaged Triptych registry used the wrong recovery owner.")
            return
        }
        #expect(health.canRelinkAfterPreserving)
        #expect(observedRegistryURL == registryURL)
        #expect(!controller.isReady)
        #expect(try Data(contentsOf: registryURL) == damaged)

        controller.repairRegistryAndRetry()
        await waitUntilSettled(controller)
        guard case .ready(let store) = controller.state else {
            Issue.record("Relinking did not restore the normal Bootstrap route.")
            return
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: registryURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        let backup = try #require(contents.first(where: {
            $0.lastPathComponent.hasPrefix("workspace-registration-v3.corrupt-")
        }))
        #expect(try Data(contentsOf: backup) == damaged)
        #expect(!FileManager.default.fileExists(atPath: registryURL.path))
        await store.shutdownApplicationRuntime()
    }

    @Test("A registry that disappears during relinking changes to Retry-only I/O recovery")
    func relinkFailureUpdatesRegistryHealth() async throws {
        let supportURL = testRoot()
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
        let registryURL = supportURL
            .appendingPathComponent("Workspace", isDirectory: true)
            .appendingPathComponent("workspace-registration-v3.json")
        try FileManager.default.createDirectory(
            at: registryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("damaged registry bytes".utf8).write(to: registryURL)
        defer { try? FileManager.default.removeItem(at: supportURL.deletingLastPathComponent()) }

        let controller = ApplicationBootstrapController { supportURL }
        controller.startIfNeeded()
        await waitUntilSettled(controller)
        guard case .registryRecovery = controller.state else {
            Issue.record("The fixture did not reach Registry Recovery.")
            return
        }
        try FileManager.default.removeItem(at: registryURL)

        controller.repairRegistryAndRetry()
        guard case .registryRecovery(let recovery) = controller.state else {
            Issue.record("A failed relink did not remain in the recovery state.")
            return
        }
        guard case .triptych(let health, _) = recovery.source,
              case .ioFailure = health else {
            Issue.record("A failed relink retained the stale malformed health and Relink action.")
            return
        }
        #expect(!health.canRelinkAfterPreserving)
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
