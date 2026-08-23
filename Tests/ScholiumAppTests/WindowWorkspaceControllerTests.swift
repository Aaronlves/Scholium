import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Window Workspace controller")
@MainActor
struct WindowWorkspaceControllerTests {
    @Test("Cancelling recovery stops the owned operation before configuration returns")
    func recoveryCancellation() async throws {
        let assignment = makeAssignment()
        let analyses = try #require(assignment.vault(for: .paperAnalysis))
        let controller = WindowWorkspaceController(
            workspaceStore: makeTestWorkspaceStore(),
            requestedTriptychID: nil
        )
        controller.setAssignment(assignment)
        controller.setAccessRecovery(WorkspaceAccessRecovery(
            kind: .vault,
            expectedPath: analyses.canonicalPath
        ))
        var didStart = false
        var didFinish = false
        controller.bindRecoveryDependencies(WindowWorkspaceRecoveryDependencies(
            configureTriptych: { _, _, _, _, _, _ in
                didStart = true
                do {
                    try await Task.sleep(for: .seconds(30))
                    didFinish = true
                } catch is CancellationError {
                    throw CancellationError()
                }
            },
            didRemoveRegistration: { _, _, _ in },
            reportInformation: { _ in }
        ))

        let task = Task { @MainActor in
            try await controller.restoreWorkspaceAccess(
                using: URL(fileURLWithPath: analyses.canonicalPath, isDirectory: true)
            )
        }
        for _ in 0..<100 where !didStart { await Task.yield() }
        #expect(controller.isRecovering)

        controller.cancelRecovery()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        #expect(!controller.isRecovering)
        #expect(!didFinish)
        #expect(controller.state.accessRecovery != nil)
    }

    private func makeAssignment() -> TriptychAssignment {
        let analyses = RegisteredVault(
            name: "Analyses",
            role: .sourceCorpus,
            canonicalPath: "/nonexistent/window-recovery/Analyses"
        )
        let topics = RegisteredVault(
            name: "Topics",
            role: .topicKnowledge,
            canonicalPath: "/nonexistent/window-recovery/Topics"
        )
        let works = RegisteredVault(
            name: "Works",
            role: .draftProject,
            canonicalPath: "/nonexistent/window-recovery/Works"
        )
        return TriptychAssignment(
            triptych: ScholiumTriptych(
                name: "Recovery",
                paperAnalysisVaultID: analyses.id,
                topicKnowledgeVaultID: topics.id,
                outputVaultID: works.id
            ),
            vaults: [
                .paperAnalysis: analyses,
                .topicKnowledge: topics,
                .output: works,
            ],
            hasCommonParent: true
        )
    }
}
