import ScholiumContracts
import Foundation
import Testing
@testable import ScholiumApp

@Suite("Window controller architecture")
@MainActor
struct WindowControllerArchitectureTests {
    @Test("Feature controllers emit closed intents without mutating peers")
    func closedIntentRouting() {
        let reference = fixtureReference(path: "Topics/Agency.md")
        var discoveryIntents: [WindowIntent] = []
        var documentIntents: [WindowIntent] = []
        var researchIntents: [WindowIntent] = []
        let discovery = DiscoveryController { discoveryIntents.append($0) }
        let document = DocumentController { documentIntents.append($0) }
        let research = ResearchController { researchIntents.append($0) }

        discovery.requestOpen(reference, inNewTab: true)
        document.requestLifecycle(.move(reference.relativePath))
        research.setActiveDocument(reference)
        research.requestPresentScholia(section: .dialogue)

        #expect(discoveryIntents == [
            .openDocument(WindowDocumentRoute(
                reference: reference,
                opensInNewTab: true
            )),
        ])
        #expect(documentIntents == [.presentLifecycle(.move("Topics/Agency.md"))])
        #expect(researchIntents == [
            .presentScholia(ScholiaRoute(reference: reference, section: .dialogue)),
        ])
        #expect(document.openDocuments.isEmpty)
        #expect(discovery.library.locationScope == .workspace)
    }

    @Test("Two document controllers never share document sessions")
    func documentControllerIsolation() {
        let reference = fixtureReference(path: "Topics/Identity.md")
        let key = DocumentSessionKey(vaultID: reference.vaultID, noteID: UUID())
        let descriptor = WindowDocumentDescriptor(sessionKey: key, reference: reference)
        let first = DocumentController()
        let second = DocumentController()

        first.installOpenedDocument(descriptor, inNewTab: false)
        second.installOpenedDocument(descriptor, inNewTab: false)
        let firstSession = first.session(for: descriptor)
        let secondSession = second.session(for: descriptor)
        firstSession.editingSource = "window one exact bytes\n"

        #expect(firstSession !== secondSession)
        #expect(secondSession.editingSource.isEmpty)
        #expect(first.openDocuments == [descriptor])
        #expect(second.openDocuments == [descriptor])
    }

    @Test("A rename updates projection without replacing the editor session")
    func renamePreservesDocumentSession() {
        let vaultID = UUID()
        let noteID = UUID()
        let original = WindowDocumentDescriptor(
            sessionKey: DocumentSessionKey(vaultID: vaultID, noteID: noteID),
            reference: fixtureReference(vaultID: vaultID, path: "Topics/Old.md")
        )
        let renamed = WindowDocumentDescriptor(
            sessionKey: original.sessionKey,
            reference: fixtureReference(vaultID: vaultID, path: "Topics/New.md")
        )
        let controller = DocumentController()
        controller.installOpenedDocument(original, inNewTab: false)
        let session = controller.session(for: original)
        session.editingSource = "dirty exact buffer"

        controller.updateDocumentProjection(renamed)

        #expect(controller.activeDocument == renamed)
        #expect(controller.session(for: renamed) === session)
        #expect(session.editingSource == "dirty exact buffer")
    }

    @Test("Document controller owns the Put Back path projection")
    func documentControllerProjectsPutBackDestination() {
        let controller = DocumentController()

        #expect(controller.putBackDestination(for: "Set Aside/Topics/Agency.md") == "Topics/Agency.md")
        #expect(controller.putBackDestination(for: "Trash/Agency.md") == "Agency.md")
        #expect(controller.putBackDestination(for: "Set Aside/") == nil)
        #expect(controller.putBackDestination(for: "Topics/Agency.md") == nil)
    }

    @Test("Discovery rejects a stale Search completion")
    func staleSearchCompletion() {
        let controller = DiscoveryController()
        let first = controller.beginSearch(SearchWorkspaceState(
            query: "first",
            scope: .triptych
        ))
        let second = controller.beginSearch(SearchWorkspaceState(
            query: "second",
            scope: .thisNote
        ))

        controller.failSearch("stale", for: first)
        #expect(controller.search.errorMessage == nil)
        #expect(controller.search.criteria.query == "second")

        controller.failSearch("current", for: second)
        #expect(controller.search.errorMessage == "current")
        #expect(!controller.search.isRunning)
    }

    @Test("Discovery owns Search preflight and failure state")
    func discoveryOwnsSearchExecutionPreflight() async {
        let controller = DiscoveryController()

        await #expect(throws: DiscoverySearchExecutionError.workspaceUnavailable) {
            try await controller.executeSearch(
                SearchWorkspaceState(query: "agency", scope: .triptych),
                context: DiscoverySearchExecutionContext(
                    workspaceIsAvailable: false,
                    currentNote: nil,
                    currentVaultID: nil
                )
            )
        }

        #expect(controller.search.errorMessage == "Open a complete Triptych before searching.")
        #expect(!controller.search.isRunning)
    }

    @Test("Discovery rejects a stale lifecycle completion for the same scope")
    func staleLifecycleCompletion() {
        let controller = DiscoveryController()
        let first = controller.beginLifecycleListing(.trash)
        let second = controller.beginLifecycleListing(.trash)

        controller.failLifecycleListing("stale", for: first)
        #expect(controller.library.lifecycleError == nil)
        #expect(controller.library.lifecycleIsLoading)

        controller.failLifecycleListing("current", for: second)
        #expect(controller.library.lifecycleError == "current")
        #expect(!controller.library.lifecycleIsLoading)
    }

    @Test("Discovery views share one controller instead of parallel feature models")
    func discoveryViewAdoption() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "Scholium/App/ScholiumApp.swift",
            "Scholium/Views/ContentView.swift",
            "Scholium/Views/SearchWorkspaceView.swift",
            "Scholium/Views/Sidebar/SidebarView.swift",
        ]
        let source = try relativePaths.map {
            try String(
                contentsOf: repositoryRoot.appendingPathComponent($0),
                encoding: .utf8
            )
        }.joined(separator: "\n")

        for legacyOwner in [
            "SearchFeatureModel",
            "QuickOpenFeatureModel",
            "LibraryFeatureModel",
        ] {
            #expect(!source.contains(legacyOwner))
        }
        #expect(source.contains("controller: appState.discoveryController"))
        #expect(source.contains("context: sidebarContext"))
    }

    @Test("Discovery destinations receive controllers or narrow root contexts")
    func discoveryDestinationsAreExplicitBoundaries() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "Scholium/Views/SearchWorkspaceView.swift",
            "Scholium/Views/AttentionQueueView.swift",
            "Scholium/Views/WorkspaceSetupView.swift",
            "Scholium/Views/Sidebar/SidebarView.swift",
        ]

        for relativePath in relativePaths {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            #expect(
                !source.contains("WindowModel"),
                Comment(rawValue: "\(relativePath) still receives the complete window model")
            )
            #expect(
                !source.contains("@EnvironmentObject"),
                Comment(rawValue: "\(relativePath) still reads broad environment state")
            )
        }

        let contentView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scholium/Views/ContentView.swift"),
            encoding: .utf8
        )
        #expect(contentView.contains("context: spotlightSearchContext"))
        #expect(contentView.contains("context: attentionQueueContext"))
        #expect(contentView.contains("WorkspaceSetupView(context: workspaceSetupContext)"))
        #expect(contentView.contains("context: sidebarContext"))
    }

    @Test("Research controller keeps inspector and History mutually exclusive")
    func researchPresentationIsolation() {
        let controller = ResearchController()
        controller.showResearchInspector(true)
        #expect(controller.inspector.showsResearchInspector)
        #expect(!controller.inspector.showsNoteHistory)

        controller.showNoteHistory(true)
        #expect(controller.inspector.showsNoteHistory)
        #expect(!controller.inspector.showsResearchInspector)

        let current = UUID()
        controller.beginScholiaPresentation(id: current, section: .dialogue)
        controller.dismissScholiaPresentation(id: UUID())
        #expect(controller.scholia.presentationID == current)
        controller.dismissScholiaPresentation(id: current)
        #expect(controller.scholia == ScholiaPresentationState())
    }

    @Test("Research destinations receive narrow contexts instead of the window model")
    func researchDestinationsAreLeafBoundaries() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "Scholium/Views/ScholiaPanelView.swift",
            "Scholium/Views/QualityReviewView.swift",
            "Scholium/Views/CritiqueRequestView.swift",
            "Scholium/Views/ResearcherCommentsView.swift",
            "Scholium/Views/DialogueView.swift",
        ]

        for relativePath in relativePaths {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            #expect(!source.contains("WindowModel"))
            #expect(!source.contains("@EnvironmentObject"))
        }
    }

    @Test("Only the view composition root receives the complete window model")
    func leafViewsDoNotReceiveWindowModel() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewsRoot = repositoryRoot.appendingPathComponent(
            "Scholium/Views",
            isDirectory: true
        )
        let enumerator = try #require(FileManager.default.enumerator(
            at: viewsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))
        var violations: [String] = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            let relativePath = file.path.replacingOccurrences(
                of: repositoryRoot.path + "/",
                with: ""
            )
            if file.lastPathComponent == "ContentView.swift" {
                let declarations = source.components(separatedBy: "\n").filter {
                    $0.contains("@EnvironmentObject") && $0.contains("WindowModel")
                }
                if declarations.count != 1 {
                    violations.append("\(relativePath): expected one WindowModel root")
                }
            } else if source.contains("WindowModel") {
                violations.append("\(relativePath): references WindowModel")
            }
        }

        #expect(
            violations.isEmpty,
            Comment(rawValue: violations.sorted().joined(separator: "\n"))
        )
    }

    @Test("Settings constructs independently of any document window")
    func standaloneSettingsConstruction() {
        let model = WorkspaceSettingsModel(selectedPane: .properties)

        #expect(model.selectedPane == .properties)
        #expect(model.snapshot.registeredVaults.isEmpty)
        #expect(model.snapshot.registeredTriptychs.isEmpty)
        model.selectPane(.researchGuidance)
        #expect(model.selectedPane == .researchGuidance)
    }

    @Test("Window model routes application operations through feature controllers")
    func windowModelDoesNotExecuteApplicationCapabilitiesDirectly() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scholium/App/ScholiumApp.swift"),
            encoding: .utf8
        )
        let start = try #require(source.range(of: "final class WindowModel: ObservableObject"))
        let end = try #require(source.range(
            of: "private enum HumanReviewWorkflowError",
            range: start.upperBound..<source.endIndex
        ))
        let windowModelSource = String(source[start.lowerBound..<end.lowerBound])

        for prohibited in [
            "activeWorkspaceHandle?.documents",
            "activeWorkspaceHandle?.discovery",
            "activeWorkspaceHandle?.research",
            "handle.documents",
            "handle.discovery",
            "handle.research",
            "handle.snapshot()",
            "workspaceStore.vaultSearch",
            "workspaceStore.federatedSearch",
            "PropertyContractCatalog.validate",
            "discoveryController.search(",
            "discoveryController.relatedResults(",
            "SearchQuery(",
            "newAnalysisContent",
            "yamlQuotedScalar",
        ] {
            #expect(
                !windowModelSource.contains(prohibited),
                Comment(rawValue: "WindowModel still executes \(prohibited) directly")
            )
        }
        #expect(windowModelSource.contains("documentController.create(DocumentCreationRequest("))
        #expect(windowModelSource.contains("discoveryController.executeSearch("))
        #expect(windowModelSource.contains("researchController.createDialogue("))
    }

    @Test("Window and document ownership boundaries cannot regress")
    func ownershipBoundaries() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scholium/App/ScholiumApp.swift"),
            encoding: .utf8
        )
        let controllerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Features/Document/DocumentController.swift"
            ),
            encoding: .utf8
        )
        let start = try #require(appSource.range(of: "final class WindowModel: ObservableObject"))
        let end = try #require(appSource.range(
            of: "private enum HumanReviewWorkflowError",
            range: start.upperBound..<appSource.endIndex
        ))
        let windowModelSource = String(appSource[start.lowerBound..<end.lowerBound])

        #expect(windowModelSource.contains("workspaceStore: WorkspaceStore,"))
        #expect(!windowModelSource.contains("workspaceStore: WorkspaceStore?"))
        #expect(!windowModelSource.contains("workspaceStore ?? WorkspaceStore()"))
        #expect(!windowModelSource.contains("DocumentSessionStore("))
        #expect(!windowModelSource.contains("putBackDestination"))
        #expect(windowModelSource.contains("documentController.putBack("))
        #expect(!windowModelSource.contains("if triptychSettings.properties.isEmpty"))

        #expect(controllerSource.contains("private let sessions = DocumentSessionStore()"))
        #expect(!controllerSource.contains("sessions: DocumentSessionStore"))
    }

    private func fixtureReference(
        vaultID: UUID = UUID(),
        path: String
    ) -> VaultNoteReference {
        VaultNoteReference(
            vaultID: vaultID,
            vaultName: "Fixture Topics",
            vaultRole: .topicKnowledge,
            relativePath: path,
            stableNoteID: UUID().uuidString.lowercased()
        )
    }
}
