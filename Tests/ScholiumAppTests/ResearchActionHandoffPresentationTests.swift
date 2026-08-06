import Foundation
import Testing

@Suite("Research Action handoff presentation")
struct ResearchActionHandoffPresentationTests {
    @Test("Action sheets expose researcher decisions instead of implementation boundaries")
    func researcherFacingActionStatus() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let actionPanel = try source(
            "Scholium/Views/ResearchActions/ResearchActionPanelView.swift",
            repositoryRoot: repositoryRoot
        )

        #expect(actionPanel.contains("Text(\"Target\")"))
        #expect(actionPanel.contains("Text(actionEffectLabel)"))
        #expect(actionPanel.contains("localized: \"May update this \\(role).\""))
        #expect(actionPanel.contains("localized: \"Does not change research documents.\""))
        #expect(actionPanel.contains("Label(\"Handoff ready\""))
        #expect(actionPanel.contains("scholium.researchAction.connection"))
        #expect(actionPanel.contains("Closing this sheet leaves the Action active."))
        #expect(actionPanel.contains("preparation.derivedRefreshWarning"))
        #expect(actionPanel.contains("Button(\"End Action…\", role: .destructive)"))

        for implementationCopy in [
            "RUN BOUNDARY",
            "PREPARED",
            "Method + Academic Profile",
            "revisionLabel",
            "fingerprint.sha256.prefix",
            "Candidate write to current",
            "The exact Action, Method and Profile revisions",
            "Validates and freezes this Action",
        ] {
            #expect(!actionPanel.contains(implementationCopy))
        }
    }

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
        let discussion = try source(
            "Scholium/Views/Note/NoteContentView.swift",
            repositoryRoot: repositoryRoot
        )

        #expect(!actionPanel.contains("scholium.researchAction.pairingCode"))
        #expect(!actionPanel.contains("Text(\"PAIRING CODE\")"))
        #expect(!actionPanel.contains("Generate New Pairing Code"))
        #expect(actionPanel.contains("Copy New Handoff"))
        #expect(actionPanel.contains("pendingHandoff = .copyNew"))
        #expect(actionPanel.contains("controller.regenerateHandoff()"))
        #expect(actionPanel.contains("title: \"Copy Handoff\""))
        #expect(actionPanel.contains("scholium.researchAction.copyHandoff"))
        #expect(!actionPanel.contains("AgentApplicationHandoffController"))
        #expect(!actionPanel.contains("copyAndOpen"))
        #expect(!actionPanel.contains("Copy Only"))

        #expect(discussion.contains("Button(\"Copy Handoff\")"))
        #expect(discussion.contains("scholium.discussion.copyHandoff"))
        #expect(!discussion.contains("Copy and Open Agent App"))
        #expect(!discussion.contains("Copy Only"))

        #expect(!FileManager.default.fileExists(atPath: repositoryRoot
            .appendingPathComponent("Scholium/Services/AgentApplicationHandoff.swift")
            .path))
        #expect(!FileManager.default.fileExists(atPath: repositoryRoot
            .appendingPathComponent("Tests/ScholiumAppTests/AgentApplicationHandoffControllerTests.swift")
            .path))

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
