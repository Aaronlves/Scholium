import ScholiumContracts
import Combine
import Foundation
import Testing
@testable import ScholiumApp

@Suite("Window controller architecture")
@MainActor
struct WindowControllerArchitectureTests {
    @Test("Search execution and Saved Search persistence have one window owner")
    func windowSearchOwnership() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let controller = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/Window/WindowSearchController.swift"
            ),
            encoding: .utf8
        )

        #expect(app.contains("lazy var searchController = WindowSearchController("))
        #expect(app.contains("searchController.objectWillChange"))
        for retiredRootOwner in [
            "@Published var savedSearches",
            "savedSearchMutationTail",
            "advancedSearchExecutionTask",
            "advancedSearchExecutionID",
            "func refreshAdvancedSearch(",
            "func saveCurrentSearch(",
            "func runSavedSearch(",
        ] {
            #expect(!app.contains(retiredRootOwner))
        }
        #expect(controller.contains(
            "final class WindowSearchController: ObservableObject"
        ))
        #expect(controller.contains("@Published private(set) var savedSearches"))
        #expect(controller.contains("private var executionTask"))
        #expect(controller.contains("private var savedSearchMutationTail"))
        #expect(controller.contains("func searchGenerationDidChange()"))
    }

    @Test("Workspace events have one exact-window projection owner")
    func workspaceProjectionOwnership() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let controller = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/Window/WindowWorkspaceProjectionController.swift"
            ),
            encoding: .utf8
        )
        let store = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Services/WindowSession.swift"
            ),
            encoding: .utf8
        )

        #expect(app.contains(
            "lazy var workspaceProjectionController = WindowWorkspaceProjectionController("
        ))
        #expect(app.contains("workspaceProjectionController.objectWillChange"))
        #expect(app.contains("workspaceStore.$workspaceEvents"))
        for retiredRootOwner in [
            "@Published var notes:",
            "@Published var allTags:",
            "@Published var documentRevisions:",
            "@Published var workspaceCatalog:",
            "@Published var relationshipGraph:",
            "workspaceVaultSnapshotsByID",
            "workspaceProjectionTail",
            "receiveWorkspaceSnapshots(",
            "receiveWorkspaceDerivedRefreshStatuses(",
            "applyWorkspaceSnapshot(",
            "refreshDocumentRevisions(",
            "workspaceStore.$workspaceSnapshots",
            "workspaceStore.$workspaceDerivedRefreshStatuses",
        ] {
            #expect(!app.contains(retiredRootOwner))
        }
        #expect(controller.contains(
            "final class WindowWorkspaceProjectionController: ObservableObject"
        ))
        #expect(controller.contains("@Published private(set) var state = State()"))
        #expect(controller.contains("private var runtimeIdentity"))
        #expect(controller.contains("private var acceptedGeneration"))
        #expect(controller.contains("event.generation > $0"))
        #expect(controller.contains("func recordCommittedNote("))
        #expect(controller.contains("private func installVisibleNotes("))
        #expect(!store.contains("workspaceEventGenerations"))
        #expect(!store.contains("workspaceDerivedRefreshStatuses"))
    }

    @Test("Agent request claims and exact-window presentation have distinct owners")
    func agentRequestWindowOwnership() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let controller = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Features/ResearchContext/AgentNoteChangeWindowController.swift"
            ),
            encoding: .utf8
        )
        let claims = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Features/ResearchContext/AgentNoteChangeClaimCoordinator.swift"
            ),
            encoding: .utf8
        )
        let windowManagement = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWindowManagement.swift"
            ),
            encoding: .utf8
        )
        let content = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ContentView.swift"
            ),
            encoding: .utf8
        )
        let sheet = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ResearchActions/AgentNoteChangeRequestView.swift"
            ),
            encoding: .utf8
        )

        #expect(app.contains(
            "lazy var agentNoteChangeWindowController = AgentNoteChangeWindowController("
        ))
        #expect(app.contains("agentNoteChangeWindowController.objectWillChange"))
        for retiredWindowModelOwner in [
            "@Published private(set) var presentedAgentNoteChangeRequest",
            "@Published private(set) var presentedAgentNoteChangeIdentity",
            "agentNoteChangeIdentityTask",
            "agentNoteChangeExpiryTask",
            "func resolvePresentedAgentNoteChangeRequest",
            "func finishAgentNoteChangeRequestDismissal",
            "func displayTargets(\n        for record: AgentNoteChangeRequestRecord",
        ] {
            #expect(!app.contains(retiredWindowModelOwner))
        }
        #expect(controller.contains(
            "final class AgentNoteChangeWindowController: ObservableObject"
        ))
        #expect(controller.contains("@Published private(set) var record"))
        #expect(controller.contains("struct AgentNoteChangeDisplayTarget"))
        #expect(controller.contains("struct AgentNoteChangePresentationIdentity"))
        #expect(controller.contains("private var decisionTask"))
        #expect(controller.contains("func registerWindowEndpoint"))
        #expect(controller.contains("func finishDismissal"))
        #expect(controller.contains("private func resetPresentationState"))
        #expect(claims.contains("final class AgentNoteChangeClaimCoordinator"))
        #expect(claims.contains("private var claims: [UUID: UUID]"))
        #expect(windowManagement.contains(
            "agentNoteChangeWindowController.registerWindowEndpoint("
        ))
        #expect(windowManagement.contains("func windowWillClose("))
        #expect(windowManagement.contains("unregisterAgentNoteChangeWindow()"))
        #expect(windowManagement.contains("agentRequestPriorResponder"))
        #expect(windowManagement.contains("restoreAgentNoteChangeFocus"))
        #expect(content.contains("appState.agentNoteChangeWindowController"))
        #expect(!sheet.contains("struct AgentNoteChangeDisplayTarget"))
        #expect(!sheet.contains("struct AgentNoteChangePresentationIdentity"))
        #expect(!FileManager.default.fileExists(atPath: repositoryRoot
            .appendingPathComponent(
                "Scholium/Features/ResearchContext/AgentNoteChangePresentationCoordinator.swift"
            ).path))
    }

    @Test("Workspace activation distinguishes a popover key transition from a window switch")
    func attentionWorkspaceSwitchDetection() {
        let registry = ScholiumWindowLifecycleRegistry()
        let first = UUID()
        let second = UUID()

        #expect(!registry.noteWorkspaceWindowActivated(first))
        #expect(!registry.noteWorkspaceWindowActivated(first))
        #expect(registry.noteWorkspaceWindowActivated(second))
        #expect(registry.noteWorkspaceWindowActivated(first))
    }

    @Test("Feature controllers emit closed intents without mutating peers")
    func closedIntentRouting() {
        let reference = fixtureReference(path: "Topics/Agency.md")
        var discoveryIntents: [WindowIntent] = []
        var documentIntents: [WindowIntent] = []
        var researchIntents: [WindowIntent] = []
        let discovery = DiscoveryController { discoveryIntents.append($0) }
        let document = DocumentController { documentIntents.append($0) }
        let research = ResearchController { researchIntents.append($0) }
        let presentationID = UUID()
        let lifecycleTarget = NoteLifecycleTarget(
            documentID: VaultQualifiedNoteID(
                vaultID: reference.vaultID,
                relativePath: reference.relativePath
            ),
            stableNoteID: UUID(),
            revision: DocumentFingerprint(content: "# Agency\n")
        )

        discovery.requestOpen(reference, disposition: .newTab)
        document.requestLifecycle(.move(lifecycleTarget))
        research.setActiveDocument(reference)
        research.requestPresentAction(
            .discuss,
            target: reference,
            presentationID: presentationID
        )

        #expect(discoveryIntents == [
            .openDocument(WindowDocumentRoute(
                reference: reference,
                disposition: .newTab
            )),
        ])
        #expect(documentIntents == [.presentLifecycle(.move(lifecycleTarget))])
        #expect(researchIntents == [
            .presentResearchAction(ResearchActionPanelRoute(
                target: reference,
                actionID: .discuss,
                presentationID: presentationID
            )),
        ])
        #expect(document.selectedDocument == nil)
        #expect(discovery.library.locationScope == .workspace)
    }

    @Test("Two document controllers never share document sessions")
    func documentControllerIsolation() {
        let reference = fixtureReference(path: "Topics/Identity.md")
        let key = DocumentSessionKey(vaultID: reference.vaultID, noteID: UUID())
        let descriptor = WindowDocumentDescriptor(sessionKey: key, reference: reference)
        let first = DocumentController()
        let second = DocumentController()

        first.installOpenedDocument(descriptor)
        second.installOpenedDocument(descriptor)
        let firstSession = first.session(for: descriptor)
        let secondSession = second.session(for: descriptor)
        firstSession.editingSource = "window one exact bytes\n"

        #expect(firstSession !== secondSession)
        #expect(secondSession.editingSource.isEmpty)
        #expect(first.selectedDocument == .workspace(descriptor))
        #expect(second.selectedDocument == .workspace(descriptor))
    }

    @Test("Source deltas do not invalidate WindowModel after the dirty chrome transition")
    func sourceDeltasStayBelowTheChromeBoundary() async {
        let window = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let reference = fixtureReference(path: "Topics/Hot Path.md")
        let key = DocumentSessionKey(vaultID: reference.vaultID, noteID: UUID())
        let descriptor = WindowDocumentDescriptor(sessionKey: key, reference: reference)
        window.documentController.installOpenedDocument(descriptor)
        let session = window.documentController.session(for: key)
        window.documentController.beginEditing(
            session: session,
            target: .workspace(key),
            source: "clean\n",
            revision: DocumentFingerprint(content: "clean\n"),
            mode: .livePreview
        )
        await Task.yield()
        await Task.yield()
        // WindowModel also loads saved-search presentation once at startup.
        // Drain that unrelated initialization before measuring source-only
        // invalidations so parallel suite scheduling cannot contaminate the
        // hot-path assertion.
        try? await Task.sleep(for: .milliseconds(300))

        var invalidations = 0
        let observation = window.objectWillChange.sink { invalidations += 1 }
        session.editingSource = "dirty 0\n"
        await Task.yield()
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(invalidations <= 1)
        #expect(window.documentController.chromeProjection.dirtyState == .dirty)

        invalidations = 0
        for index in 1...100 {
            session.editingSource = "dirty \(index)\n"
        }
        await Task.yield()
        await Task.yield()

        #expect(invalidations == 0)
        observation.cancel()
    }

    @Test("Document tabs borrow one window peripheral presentation")
    func documentTabsBorrowWindowPeripheralPresentation() {
        let presentation = WindowPeripheralPresentationState()
        let firstDiscovery = DiscoveryController(peripheralPresentation: presentation)
        let secondDiscovery = DiscoveryController(peripheralPresentation: presentation)
        let scope = LibraryDisclosureScope(
            vaultID: UUID(),
            locationScope: .workspace
        )

        firstDiscovery.setExpandedFolders(["Ethics", "Ethics/Agency"], in: scope)
        #expect(secondDiscovery.expandedFolders(in: scope) == ["Ethics", "Ethics/Agency"])

        let firstResearch = ResearchController(peripheralPresentation: presentation)
        let secondResearch = ResearchController(peripheralPresentation: presentation)
        firstResearch.selectInspectorMode(.actions)
        firstResearch.showResearchInspector(true)
        #expect(secondResearch.inspector.mode == .actions)
        #expect(secondResearch.inspector.isVisible)

        let firstDocument = DocumentController()
        let secondDocument = DocumentController()
        let reference = fixtureReference(path: "Topics/Shared Chrome.md")
        let descriptor = WindowDocumentDescriptor(
            sessionKey: DocumentSessionKey(vaultID: reference.vaultID, noteID: UUID()),
            reference: reference
        )
        firstDocument.installOpenedDocument(descriptor)
        #expect(secondDocument.selectedDocument == nil)
    }

    @Test(
        "Inspector restoration normalizes current, adjacent, absent, and unknown mode values",
        arguments: [
            (nil as String?, ResearchInspectorMode.overview),
            ("overview", ResearchInspectorMode.overview),
            ("connect", .connect),
            ("actions", .actions),
            ("connections", .connect),
            ("functions", .overview),
            ("research", .overview),
            ("relationships", .overview),
            ("incoming", .connect),
            ("outgoing", .connect),
            ("unknown", .overview),
        ]
    )
    func inspectorModeRestoration(
        rawValue: String?,
        expected: ResearchInspectorMode
    ) {
        #expect(ResearchInspectorMode(restoring: rawValue) == expected)
    }

    @Test("A new window defaults to Overview without making Inspector visible")
    func newWindowInspectorDefaults() {
        let controller = ResearchController()
        #expect(controller.inspector.mode == .overview)
        #expect(!controller.inspector.isVisible)
    }

    @Test("Separate windows do not share peripheral presentation")
    func separateWindowPeripheralPresentationIsolation() {
        let first = DiscoveryController(
            peripheralPresentation: WindowPeripheralPresentationState()
        )
        let second = DiscoveryController(
            peripheralPresentation: WindowPeripheralPresentationState()
        )
        let scope = LibraryDisclosureScope(
            vaultID: UUID(),
            locationScope: .workspace
        )

        first.setExpandedFolders(["Ethics"], in: scope)
        #expect(second.expandedFolders(in: scope).isEmpty)
    }

    @Test("One controller selection covers stable and unavailable documents")
    func documentControllerOwnsTheCompleteSelection() {
        let controller = DocumentController()

        let recoveryVaultID = UUID()
        controller.selectUnavailableDocument(
            vaultID: recoveryVaultID,
            relativePath: "Topics/Ambiguous.md"
        )
        #expect(controller.selectedDocument == .unavailable(
            vaultID: recoveryVaultID,
            relativePath: "Topics/Ambiguous.md"
        ))
        #expect(controller.selectedDocumentPath == "Topics/Ambiguous.md")
        #expect(controller.selectedDocument?.vaultID == recoveryVaultID)

        let reference = fixtureReference(path: "Topics/Stable.md")
        let descriptor = WindowDocumentDescriptor(
            sessionKey: DocumentSessionKey(vaultID: reference.vaultID, noteID: UUID()),
            reference: reference
        )
        controller.installOpenedDocument(descriptor)
        let retained = controller.session(for: descriptor)
        controller.clearSelection(forRemovedPaths: [reference.relativePath])

        #expect(controller.selectedDocument == nil)
        #expect(controller.selectedDocumentPath == nil)
        #expect(controller.retainedSession(for: descriptor.sessionKey) === retained)
    }

    @Test("Window model derives selection from the document controller")
    func windowModelDerivesDocumentSelection() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let windowSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scholium/App/ScholiumApp.swift"),
            encoding: .utf8
        )
        let controllerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Features/Document/DocumentController.swift"
            ),
            encoding: .utf8
        )

        #expect(!windowSource.contains("@Published private(set) var selectedDocumentPath"))
        #expect(!windowSource.contains("@Published var documentModes"))
        #expect(!windowSource.contains("@Published var documentScrollPositions"))
        #expect(windowSource.contains("documentController.selectedDocumentPath"))
        #expect(!controllerSource.contains("openDocuments"))
        #expect(!controllerSource.contains("activeDocumentKey"))
        #expect(controllerSource.contains("@Published private(set) var selectedDocument"))
    }

    @Test("Retained document sessions solely own mode and scroll state")
    func documentSessionOwnsPresentationState() {
        let reference = fixtureReference(path: "Topics/Presentation.md")
        let descriptor = WindowDocumentDescriptor(
            sessionKey: DocumentSessionKey(vaultID: reference.vaultID, noteID: UUID()),
            reference: reference
        )
        let controller = DocumentController()
        controller.restorePresentationState(
            modes: [reference.relativePath: NotePresentationMode.source.rawValue],
            scrollPositions: [reference.relativePath: 0.64],
            vaultID: reference.vaultID
        )

        controller.installOpenedDocument(descriptor)
        let session = controller.session(for: descriptor)
        #expect(session.presentationMode == .source)
        #expect(session.scrollFraction == 0.64)
        let semanticAnchor = EditorScrollAnchor(
            sourceFingerprint: "revision-bound-fingerprint",
            sourceUTF16Offset: 12,
            blockUTF16LowerBound: 10,
            blockUTF16UpperBound: 24,
            relativeBlockPosition: 0.25,
            fallbackFraction: 0.64
        )
        session.scrollAnchor = semanticAnchor

        controller.rememberPresentationMode(
            .livePreview,
            for: reference.relativePath,
            vaultID: reference.vaultID
        )
        controller.rememberScrollPosition(
            0.31,
            for: reference.relativePath,
            vaultID: reference.vaultID
        )
        controller.clearSelection(forRemovedPaths: [reference.relativePath])
        controller.installOpenedDocument(descriptor)

        #expect(controller.session(for: descriptor) === session)
        #expect(session.presentationMode == .livePreview)
        #expect(session.scrollFraction == 0.31)
        #expect(session.scrollAnchor == semanticAnchor)
        #expect(controller.presentationSnapshot(vaultID: reference.vaultID) ==
            DocumentPresentationSnapshot(
                modes: [reference.relativePath: NotePresentationMode.livePreview.rawValue],
                scrollPositions: [reference.relativePath: 0.31]
            ))

        controller.resetPresentationState()
        #expect(session.presentationMode == .read)
        #expect(session.scrollFraction == 0)
        #expect(session.scrollAnchor == nil)
    }

    @Test("Observed scrolling never becomes a restore request or invalidates the session")
    func observedScrollingIsNotRestoration() {
        let session = DocumentSessionModel(key: nil)
        var invalidationCount = 0
        let observation = session.objectWillChange.sink {
            invalidationCount += 1
        }

        session.observeScrollFraction(0.41)
        session.observeScrollAnchor(EditorScrollAnchor(
            sourceFingerprint: "scroll-fixture",
            sourceUTF16Offset: 8,
            blockUTF16LowerBound: 4,
            blockUTF16UpperBound: 16,
            relativeBlockPosition: 0.25,
            fallbackFraction: 0.41
        ))

        #expect(session.scrollRestoreRequest == nil)
        #expect(invalidationCount == 0)
        #expect(session.scrollFraction == 0.41)

        let first = session.requestScrollRestore(
            fingerprint: "scroll-fixture",
            reason: .documentLoad
        )
        let invalidationsAfterRequest = invalidationCount
        session.observeScrollFraction(0.73)

        #expect(session.scrollRestoreRequest == first)
        #expect(invalidationCount == invalidationsAfterRequest)
        let second = session.requestScrollRestore(
            fingerprint: "scroll-fixture",
            reason: .modeHandoff
        )
        #expect(second.id == first.id + 1)
        #expect(second.position.fraction == 0.73)
        session.acknowledgeScrollRestoreRequest(
            id: first.id,
            fingerprint: first.fingerprint
        )
        #expect(session.scrollRestoreRequest == second)
        session.acknowledgeScrollRestoreRequest(
            id: second.id,
            fingerprint: "stale-fingerprint"
        )
        #expect(session.scrollRestoreRequest == second)
        session.acknowledgeScrollRestoreRequest(
            id: second.id,
            fingerprint: second.fingerprint
        )
        #expect(session.scrollRestoreRequest == nil)
        _ = observation
    }

    @Test("Retained stable identity keeps its save address while selection is temporarily absent")
    func retainedSessionKeepsSaveAddressWithoutSelection() {
        let reference = fixtureReference(path: "Topics/Retained Save.md")
        let descriptor = WindowDocumentDescriptor(
            sessionKey: DocumentSessionKey(vaultID: reference.vaultID, noteID: UUID()),
            reference: reference
        )
        let controller = DocumentController()

        controller.installOpenedDocument(descriptor)
        controller.clearSelectionAfterClosingLastTab()

        #expect(controller.selectedDocument == nil)
        #expect(controller.relativePath(for: .workspace(descriptor.sessionKey)) == reference.relativePath)
    }

    @Test("Path-only fallback presentation state is retained by the controller")
    func fallbackPresentationStateIsControllerOwned() {
        let path = "Inbox/Imported.md"
        let vaultID = UUID()
        let target = DocumentEditingTarget.unavailable(relativePath: path)
        let controller = DocumentController()
        controller.restorePresentationState(
            modes: [path: NotePresentationMode.source.rawValue],
            scrollPositions: [path: 0.42],
            vaultID: nil
        )
        controller.selectUnavailableDocument(vaultID: vaultID, relativePath: path)

        let session = controller.session(for: target)
        #expect(session.presentationMode == .source)
        #expect(session.scrollFraction == 0.42)
        controller.clearSelection(forRemovedPaths: [path])
        controller.selectUnavailableDocument(vaultID: vaultID, relativePath: path)
        #expect(controller.session(for: target) === session)
    }

    @Test("Read presentation retains the initialized editor buffer and mode")
    func readPresentationRetainsInitializedEditor() {
        let reference = fixtureReference(path: "Topics/Retained Editor.md")
        let descriptor = WindowDocumentDescriptor(
            sessionKey: DocumentSessionKey(vaultID: reference.vaultID, noteID: UUID()),
            reference: reference
        )
        let controller = DocumentController()
        controller.installOpenedDocument(descriptor)
        let session = controller.session(for: descriptor)
        let source = "# Retained\n\nExact Markdown.\n"
        let revision = DocumentFingerprint(content: source)

        controller.beginEditing(
            session: session,
            target: .workspace(descriptor.sessionKey),
            source: source,
            revision: revision,
            mode: .source
        )
        controller.finishEditing(
            session: session,
            target: .workspace(descriptor.sessionKey)
        )

        #expect(!session.isEditing)
        #expect(session.presentationMode == .read)
        #expect(session.retainsEditorSurface)
        #expect(session.retainedEditorMode == .source)
        #expect(session.editingSource == source)
        #expect(session.originalEditingSource == source)
        #expect(session.editingRevision == revision)
        #expect(!session.hasUnsavedChanges)
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
        controller.installOpenedDocument(original)
        let session = controller.session(for: original)
        let bridgeDocumentID = session.editorSession.bridgeDocumentID
        controller.beginEditing(
            session: session,
            target: .workspace(original.sessionKey),
            source: "original exact buffer",
            revision: DocumentFingerprint(content: "original exact buffer"),
            mode: .livePreview
        )
        session.suppressAutosave = false
        session.editingSource = "dirty exact buffer"
        session.editError = "The note no longer exists at the previous path."
        session.canRetrySave = false
        controller.setSaveError(session.editError)
        session.scrollAnchor = EditorScrollAnchor(
            sourceFingerprint: "rename-stable-fingerprint",
            sourceUTF16Offset: 8,
            blockUTF16LowerBound: 4,
            blockUTF16UpperBound: 18,
            relativeBlockPosition: 0.5,
            fallbackFraction: 0.4
        )

        controller.updateDocumentProjection(renamed)

        #expect(controller.activeDocument == renamed)
        #expect(controller.session(for: renamed) === session)
        #expect(session.editorSession.bridgeDocumentID == bridgeDocumentID)
        #expect(session.editingSource == "dirty exact buffer")
        #expect(session.scrollAnchor?.sourceFingerprint == "rename-stable-fingerprint")
        #expect(controller.editingDocumentPath == "Topics/New.md")
        #expect(session.autosaveTask != nil)
        session.cancelScheduledWork()
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
                    currentNoteSnapshot: nil,
                    currentVaultID: nil
                )
            )
        }

        #expect(controller.search.errorMessage == "Open a complete Triptych before searching.")
        #expect(!controller.search.isRunning)
    }

    @Test("Discovery rejects a stale Location completion for the same Scope and Location")
    func staleLocationCompletion() {
        let controller = DiscoveryController()
        let first = controller.beginLocationRequest(
            workspaceSlot: .paperAnalysis,
            location: .trash
        )
        let second = controller.beginLocationRequest(
            workspaceSlot: .paperAnalysis,
            location: .trash
        )

        controller.failLocationRequest("stale", for: first)
        #expect(controller.library.locationError == nil)
        #expect(controller.library.locationIsLoading)

        controller.failLocationRequest("current", for: second)
        #expect(controller.library.locationError == "current")
        #expect(!controller.library.locationIsLoading)
    }

    @Test("Location commits one coherent Scope and Location pair")
    func locationRequestStateMachine() {
        let controller = DiscoveryController()
        let request = controller.beginLocationRequest(
            workspaceSlot: .topicKnowledge,
            location: .setAside
        )
        #expect(controller.library.locationIsLoading)
        #expect(controller.library.workspaceSlot == .paperAnalysis)
        #expect(controller.library.locationScope == .workspace)

        #expect(controller.receiveLocationResult(for: request))
        #expect(controller.library.workspaceSlot == .topicKnowledge)
        #expect(controller.library.locationScope == .setAside)
        #expect(!controller.library.locationIsLoading)
        #expect(controller.library.locationError == nil)
    }

    @Test("Ordinary Location navigation stages without replacing trusted content with Loading")
    func stagedLocationReplacement() {
        let controller = DiscoveryController()
        let request = controller.beginLocationRequest(
            workspaceSlot: .topicKnowledge,
            location: .trash,
            presentation: .stagedReplacement
        )

        #expect(!controller.library.locationIsLoading)
        #expect(controller.library.workspaceSlot == .paperAnalysis)
        #expect(controller.library.locationScope == .workspace)

        controller.failLocationRequest("target failed", for: request)
        #expect(controller.library.locationError == nil)
        #expect(controller.library.workspaceSlot == .paperAnalysis)
        #expect(controller.library.locationScope == .workspace)
    }

    @Test("Window Scope and Location navigation stages from the published Workspace snapshot")
    func stagedLocationNavigationAdoption() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )

        #expect(
            source.components(separatedBy: "presentation: .stagedReplacement").count - 1 == 2
        )
        #expect(source.contains("private func currentWorkspaceVaultSnapshot("))
        #expect(source.contains(
            "workspaceProjectionController.vaultSnapshot(id: vaultID)"
        ))
    }

    @Test("Changing Scope or Location rejects the previous request")
    func locationSwitchRejectsStaleResponse() {
        let controller = DiscoveryController()
        let setAside = controller.beginLocationRequest(
            workspaceSlot: .paperAnalysis,
            location: .setAside
        )
        let trash = controller.beginLocationRequest(
            workspaceSlot: .output,
            location: .trash
        )

        #expect(!controller.receiveLocationResult(for: setAside))
        #expect(controller.library.workspaceSlot == .paperAnalysis)
        #expect(controller.library.locationScope == .workspace)
        #expect(controller.library.locationIsLoading)

        #expect(controller.receiveLocationResult(for: trash))
        #expect(controller.library.workspaceSlot == .output)
        #expect(controller.library.locationScope == .trash)
    }

    @Test("Attention presentation is independent of Library Location")
    func attentionPresentationIsIndependent() {
        let controller = DiscoveryController()
        let attention = AttentionPresentationState()
        let noteScope = VaultQualifiedNoteID(
            vaultID: UUID(),
            relativePath: "analysis.md"
        )

        attention.present(workspaceSlot: .paperAnalysis, noteScope: noteScope)
        #expect(attention.noteScope == noteScope)
        let request = controller.beginLocationRequest(
            workspaceSlot: .paperAnalysis,
            location: .trash
        )
        #expect(controller.receiveLocationResult(for: request))
        #expect(attention.noteScope == noteScope)
        #expect(controller.library.locationScope == .trash)

        attention.selectWorkspaceSlot(.output)
        #expect(attention.workspaceSlot == .output)
        #expect(attention.noteScope == nil)
    }

    @Test("Location requests preserve Library filters, sort, and disclosure")
    func locationRequestPreservesWorkspacePresentation() {
        let controller = DiscoveryController()
        var filters = DiscoveryFilterState()
        filters.tag = "ethics"
        filters.needsAttention = true
        controller.replaceFilters(filters)
        controller.selectSortOrder(.titleAscending)
        let disclosureScope = LibraryDisclosureScope(
            vaultID: UUID(),
            locationScope: .workspace
        )
        controller.setExpandedFolders(["Arguments", "Sources"], in: disclosureScope)

        let request = controller.beginLocationRequest(
            workspaceSlot: .paperAnalysis,
            location: .trash
        )
        #expect(controller.receiveLocationResult(for: request))

        #expect(controller.library.filters == filters)
        #expect(controller.library.sortOrder == .titleAscending)
        #expect(controller.expandedFolders(in: disclosureScope) == ["Arguments", "Sources"])
        #expect(controller.library.locationScope == .trash)
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

        let attentionSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/AttentionQueueView.swift"
            ),
            encoding: .utf8
        )
        #expect(attentionSource.contains("@ObservedObject private var session: AttentionPopoverSession"))
        #expect(attentionSource.contains("session.inspect(item)"))
        #expect(!attentionSource.contains("WindowModel"))
        #expect(!attentionSource.contains("@EnvironmentObject"))
        #expect(!attentionSource.contains("NSApp.windows"))
        #expect(!attentionSource.contains("NotificationCenter"))

        let contentView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scholium/Views/ContentView.swift"),
            encoding: .utf8
        )
        #expect(contentView.contains("context: spotlightSearchContext"))
        #expect(contentView.contains("windowCoordinator.actions.showAttention"))
        #expect(!contentView.contains("WorkspaceSetupView"))
        #expect(contentView.contains("context: sidebarContext"))
    }

    @Test("Research controller owns Inspector independently from Research Record")
    func researchPresentationIsolation() {
        let controller = ResearchController()
        #expect(controller.inspector.mode == .overview)
        #expect(!controller.inspector.isVisible)
        controller.showResearchInspector(true)
        #expect(controller.inspector.isVisible)

        #expect(controller.actions.presentationID == nil)
    }

    @Test("Research destinations receive narrow contexts instead of the window model")
    func researchDestinationsAreLeafBoundaries() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "Scholium/Views/ResearchActions/ResearchActionPanelView.swift",
            "Scholium/Views/ResearchActions/ResearchActionsInspectorView.swift",
            "Scholium/Views/Note/NoteContentView.swift",
            "Scholium/Views/Note/SafeMarkdownReadWebView.swift",
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

    @Test("The typed Research Action route is the only judgment and agent entry panel")
    func legacyResearchPanelsStayRetired() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let router = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/Window/WindowPresentationRouter.swift"
            ),
            encoding: .utf8
        )
        let app = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )

        #expect(router.contains("case researchAction(ResearchActionPanelRoute)"))
        #expect(!router.contains("case critique(path:"))
        #expect(!router.contains("case qualityReview"))
        #expect(!router.contains("case researcherComments"))
        #expect(!app.contains("pendingCritiquePath"))
        #expect(!app.contains("qualityReviewPath"))
        #expect(!app.contains("researcherCommentsPath"))
        #expect(!app.contains("copyCritiqueInstructions"))
        #expect(!FileManager.default.fileExists(atPath: repositoryRoot
            .appendingPathComponent("Scholium/Views/CritiqueRequestView.swift").path))
        #expect(!FileManager.default.fileExists(atPath: repositoryRoot
            .appendingPathComponent("Scholium/Views/DialogueView.swift").path))
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
        let searchControllerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/Window/WindowSearchController.swift"
            ),
            encoding: .utf8
        )
        let start = try #require(source.range(of: "final class WindowModel: ObservableObject"))
        let end = try #require(source.range(
            of: "private enum ClipboardWorkflowError",
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
        #expect(windowModelSource.contains("documentController.createUntitledNote("))
        #expect(windowModelSource.contains("searchController.open("))
        #expect(searchControllerSource.contains("discoveryController.executeSearch("))
        #expect(windowModelSource.contains("researchController.actions"))
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
        let researchControllerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Features/ResearchContext/ResearchController.swift"
            ),
            encoding: .utf8
        )
        let start = try #require(appSource.range(of: "final class WindowModel: ObservableObject"))
        let end = try #require(appSource.range(
            of: "private enum ClipboardWorkflowError",
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
        #expect(windowModelSource.contains("cssSnippetStore.objectWillChange"))

        for documentOwnedState in [
            "@Published private(set) var lifecycleMutationGeneration",
            "@Published var pendingSourceLine",
            "@Published var requestPresentationMode",
            "@Published var noteIdentityByPath",
            "@Published var identityAmbiguities",
        ] {
            #expect(!windowModelSource.contains(documentOwnedState))
        }
        #expect(controllerSource.contains("@Published var lifecycleMutationGeneration"))
        #expect(!controllerSource.contains("@Published var annotationsByNoteID"))
        #expect(controllerSource.contains("@Published var noteIdentityByPath"))

        #expect(!windowModelSource.contains("@Published var dialogueInitialNotes"))
        #expect(!windowModelSource.contains("@Published var checkpointListingError"))
        #expect(!windowModelSource.contains("@Published var transactionRecoveryRecords"))
        #expect(!researchControllerSource.contains("@Published var dialogueInitialNotes"))
        #expect(researchControllerSource.contains("@Published var transactionRecoveryRecords"))

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
