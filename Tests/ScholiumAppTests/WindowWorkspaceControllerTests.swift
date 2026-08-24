import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Window Workspace controller")
@MainActor
struct WindowWorkspaceControllerTests {
    @Test("Cancelling recovery stops the owned operation before configuration returns")
    func recoveryCancellation() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = repositoryRoot
            .appendingPathComponent(".build/app-unit-state", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let analyses = root.appendingPathComponent("Analyses", isDirectory: true)
        let topics = root.appendingPathComponent("Topics", isDirectory: true)
        let works = root.appendingPathComponent("Works", isDirectory: true)
        for directory in [analyses, topics, works] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let controller = WindowWorkspaceController(
            workspaceStore: makeTestWorkspaceStore(),
            requestedTriptychID: nil
        )
        var installCount = 0
        var didStart = false
        var didFinish = false
        controller.bindDependencies(WindowWorkspaceDependencies(
            installSession: { _, _ in
                installCount += 1
                guard installCount > 1 else {
                    return WindowWorkspaceInstallationFeedback(
                        transactionRecoveryIssues: []
                    )
                }
                didStart = true
                do {
                    try await Task.sleep(for: .seconds(30))
                    didFinish = true
                } catch is CancellationError {
                    throw CancellationError()
                }
                return WindowWorkspaceInstallationFeedback(
                    transactionRecoveryIssues: []
                )
            },
            didRemoveRegistration: { _ in },
            reportInformation: { _ in }
        ))
        let assignment = try await controller.configureTriptych(
            paperAnalysisURL: analyses,
            topicKnowledgeURL: topics,
            outputURL: works,
            portableContainerURL: root,
            triptychID: nil,
            triptychName: "Recovery",
            openingVault: .paperAnalysis
        )
        let registeredAnalyses = try #require(assignment.vault(for: .paperAnalysis))
        controller.setAccessRecovery(WorkspaceAccessRecovery(
            kind: .vault,
            expectedPath: registeredAnalyses.canonicalPath
        ))

        let task = Task { @MainActor in
            try await controller.restoreWorkspaceAccess(
                using: analyses
            )
        }
        for _ in 0..<100 where !didStart { await Task.yield() }
        #expect(controller.isRecovering)

        controller.cancelAll()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        #expect(!controller.isRecovering)
        #expect(!didFinish)
        #expect(controller.state.accessRecovery != nil)
    }

}
