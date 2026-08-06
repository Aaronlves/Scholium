import Foundation
import Testing

@Suite("Research Action handoff presentation")
struct ResearchActionHandoffPresentationTests {
    @Test("One-time codes stay inside complete copied handoffs")
    func pairingCodesAreNotSeparateInterfaceFields() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let actionPanel = try source(
            "Scholium/Views/ResearchActions/ResearchActionPanelView.swift",
            repositoryRoot: repositoryRoot
        )
        let methodFeedback = try source(
            "Scholium/Views/ResearchActions/ResearcherEvaluationView.swift",
            repositoryRoot: repositoryRoot
        )

        #expect(!actionPanel.contains("scholium.researchAction.pairingCode"))
        #expect(!actionPanel.contains("Text(\"PAIRING CODE\")"))
        #expect(!actionPanel.contains("Generate New Pairing Code"))
        #expect(actionPanel.contains("Copy New Handoff"))
        #expect(actionPanel.contains("pendingHandoff = .copyNew"))
        #expect(actionPanel.contains("controller.regenerateHandoff()"))

        #expect(!methodFeedback.contains("scholium.methodFeedback.pairingCode"))
        #expect(!methodFeedback.contains("Text(\"Pairing Code\")"))
        #expect(methodFeedback.contains("Pairing Code: \\(handoff.pairingCode.rawValue)"))
        #expect(methodFeedback.contains("Copy Improvement Handoff"))
    }

    private func source(_ relativePath: String, repositoryRoot: URL) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
