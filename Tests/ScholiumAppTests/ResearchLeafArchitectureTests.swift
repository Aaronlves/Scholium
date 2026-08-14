import ScholiumContracts
import Foundation
import Testing
@testable import ScholiumApp

@Suite("Research leaf architecture")
struct ResearchLeafArchitectureTests {
    @Test("Research leaves receive controllers, immutable values, and closures")
    func researchLeavesDoNotBorrowWindowModel() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "Scholium/Views/Backlinks/ConnectionsInspectorView.swift",
            "Scholium/Views/CheckpointView.swift",
            "Scholium/Views/Note/CritiqueProvenanceView.swift",
            "Scholium/Views/Sidebar/ResearchInspectorContentView.swift",
            "Scholium/Views/ResearchActions/ResearchActionsInspectorView.swift",
            "Scholium/Views/Sidebar/ZoteroBindingPanelView.swift",
        ]
        let sources = try Dictionary(uniqueKeysWithValues: relativePaths.map { path in
            (
                path,
                try String(
                    contentsOf: repositoryRoot.appendingPathComponent(path),
                    encoding: .utf8
                )
            )
        })

        for path in relativePaths {
            let source = try #require(sources[path])
            #expect(
                !source.contains("WindowModel"),
                Comment(rawValue: "\(path) still borrows the complete window model")
            )
            #expect(
                !source.contains("@EnvironmentObject"),
                Comment(rawValue: "\(path) still depends on an ambient environment owner")
            )
            #expect(!source.contains("import Scholium" + "Application"))
            #expect(!source.contains("import Scholium" + "Core"))
            #expect(!source.contains("FileManager"))
            #expect(!source.contains("import Yams"))
        }

        let relationships = try #require(sources[relativePaths[0]])
        #expect(relationships.contains("struct RelationshipInspectorContext"))
        #expect(relationships.contains("let graph: GraphSnapshot?"))
        #expect(relationships.contains("let catalog: WorkspaceCatalogSnapshot?"))
        #expect(relationships.contains("let openReference: (VaultNoteReference, Int?) -> Void"))

        let checkpoints = try #require(sources[relativePaths[1]])
        #expect(checkpoints.contains("@ObservedObject private var controller: ResearchController"))
        #expect(checkpoints.contains("let createCheckpoint: (String) async throws -> Void"))
        #expect(checkpoints.contains("let restoreCheckpoint:"))
        #expect(checkpoints.contains("let revealCheckpoints: () -> Void"))

        let critique = try #require(sources[relativePaths[2]])
        #expect(critique.contains("struct CritiqueProvenanceContext"))
        #expect(critique.contains("let availableNotes: [WindowDocumentLocation]"))
        #expect(critique.contains("let documentRevisions: [String: DocumentFingerprint]"))
        #expect(critique.contains("let loadAssociation:"))
        #expect(critique.contains("let openTarget:"))
        #expect(critique.contains("let openFinding:"))
        #expect(!critique.contains("ResearchController"))
        #expect(!critique.contains("@ObservedObject"))
        #expect(!critique.contains("let controller:"))

        let overview = try #require(sources[relativePaths[3]])
        #expect(overview.contains("struct ResearchInspectorContentContext"))
        #expect(!overview.contains("ResearchController"))
        #expect(overview.contains("let presentation: ResearchOverviewPresentation"))
        #expect(overview.contains("let openProperties: () -> Void"))
        #expect(overview.contains("let openAttention: () -> Void"))
        #expect(overview.contains("let retryRefresh: () -> Void"))
        #expect(overview.contains(
            "let openZoteroItem: (AnalysisZoteroBinding) async -> Void"
        ))
        #expect(overview.contains(
            "let manageZoteroBinding: (UUID, AnalysisZoteroBinding?) -> Void"
        ))
        #expect(overview.contains("Open in Zotero"))
        #expect(overview.contains("Link Zotero Item…"))
        #expect(overview.contains("Manage Zotero Link…"))
        #expect(!overview.contains("resolveSource:"))
        #expect(!overview.contains("openItem:"))
        #expect(!overview.contains("confirmItem:"))

        let bindingPanel = try #require(sources[relativePaths[5]])
        #expect(bindingPanel.contains("struct ZoteroBindingPanelView: View"))
        #expect(bindingPanel.contains("let search: (String) async throws"))
        #expect(bindingPanel.contains("let setBinding: (ZoteroSearchHit)"))
        #expect(bindingPanel.contains("let clearBinding: () async throws"))
        #expect(bindingPanel.contains("Clear Zotero Link?"))
        #expect(!bindingPanel.contains("ZoteroItemMetadata?"))
    }

    @Test("Relationships navigation emits a typed document route with its source locator")
    @MainActor
    func relationshipNavigationUsesResearchIntent() {
        let reference = VaultNoteReference(
            vaultID: UUID(),
            vaultName: "Fixture Topics",
            vaultRole: .topicKnowledge,
            relativePath: "Topics/Agency.md",
            stableNoteID: UUID().uuidString.lowercased()
        )
        var intents: [WindowIntent] = []
        let controller = ResearchController { intents.append($0) }

        controller.requestOpen(reference, sourceLine: 37)

        #expect(intents == [
            .openDocument(WindowDocumentRoute(
                reference: reference,
                sourceLocator: SourceLocator(
                    file: reference.relativePath,
                    line: 37,
                    column: 1
                )
            )),
        ])
    }

    @Test("Research roots route navigation and checkpoint side effects explicitly")
    func researchRootWiringIsExplicit() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let noteContent = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/Note/NoteContentView.swift"
            ),
            encoding: .utf8
        )
        let content = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ContentView.swift"
            ),
            encoding: .utf8
        )
        let controller = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Features/ResearchContext/ResearchController.swift"
            ),
            encoding: .utf8
        )

        #expect(noteContent.contains("ConnectionsInspectorView(context: relationshipContext)"))
        #expect(noteContent.contains("CritiqueProvenanceView("))
        #expect(noteContent.contains("context: critiqueProvenanceContext"))
        #expect(noteContent.contains("ResearchOverviewView("))
        #expect(noteContent.contains("ResearchActionsInspectorView("))
        #expect(noteContent.contains("context: researchInspectorContentContext"))
        #expect(content.contains("controller: appState.researchController"))
        #expect(content.contains("graph: appState.relationshipGraph"))
        #expect(!content.contains("workspaceCatalog?.graph ?? appState.relationshipGraph"))
        #expect(content.contains("private var researchInspectorContentContext: ResearchInspectorContentContext"))
        #expect(content.contains("private var critiqueProvenanceContext: CritiqueProvenanceContext"))
        #expect(content.contains("loadAssociation: { path in"))
        #expect(content.contains("openFinding: { finding, fallbackTargetPath in"))
        #expect(!content.contains("resolveZoteroSource: { source in"))
        #expect(!content.contains("confirmZoteroItem: { itemKey, reference in"))
        #expect(content.contains("zoteroBinding: currentAnalysisZoteroBinding"))
        #expect(content.contains("guard appState.currentDocumentVaultRole == .sourceCorpus"))
        #expect(!content.contains("ZoteroBridge.normalizedItemKey("))
        #expect(content.contains("openZoteroItem: { binding in"))
        #expect(content.contains("openInZotero(binding: binding)"))
        #expect(content.contains("restoreCheckpoint: { checkpointID, selection in"))
        #expect(content.contains("revealCheckpoints: {"))
        #expect(controller.contains("func requestOpen("))
        #expect(controller.contains("intentHandler(.openDocument(WindowDocumentRoute("))
    }
}
