import ScholiumContracts
import Combine
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
        research.requestPresentFunction(
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
            .presentResearchFunction(ResearchFunctionPanelRoute(
                target: reference,
                function: .discuss,
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
        "Inspector restoration normalizes current, legacy, absent, and unknown mode values",
        arguments: [
            (nil as String?, ResearchInspectorMode.overview),
            ("overview", ResearchInspectorMode.overview),
            ("connect", .connect),
            ("actions", .actions),
            ("connections", .connect),
            ("functions", .actions),
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

    @Test("One controller selection covers stable and path-only documents")
    func documentControllerOwnsTheCompleteSelection() {
        let controller = DocumentController()

        controller.selectUnclassifiedDocument(relativePath: "Inbox/Imported.md")
        #expect(controller.selectedDocument == .unclassified(relativePath: "Inbox/Imported.md"))
        #expect(controller.selectedDocumentPath == "Inbox/Imported.md")
        #expect(controller.activeDocument == nil)

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
        let target = DocumentEditingTarget.unclassified(relativePath: path)
        let controller = DocumentController()
        controller.restorePresentationState(
            modes: [path: NotePresentationMode.source.rawValue],
            scrollPositions: [path: 0.42],
            vaultID: nil
        )
        controller.selectUnclassifiedDocument(relativePath: path)

        let session = controller.session(for: target)
        #expect(session.presentationMode == .source)
        #expect(session.scrollFraction == 0.42)
        controller.clearSelection(forRemovedPaths: [path])
        controller.selectUnclassifiedDocument(relativePath: path)
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

    @Test("Lifecycle destinations own immediate loading, retry, and dismissal state")
    func lifecycleDestinationStateMachine() {
        let controller = DiscoveryController()

        controller.presentLifecycleListing(.setAside)
        #expect(controller.library.lifecycleScope == .setAside)
        #expect(controller.library.lifecycleItems.isEmpty)
        #expect(controller.library.lifecycleIsLoading)
        #expect(controller.library.lifecycleError == nil)

        let first = controller.beginLifecycleListing(.setAside)
        controller.receiveLifecycleItems([], for: first)
        #expect(!controller.library.lifecycleIsLoading)
        #expect(controller.library.lifecycleError == nil)

        let retry = controller.beginLifecycleListing(.setAside)
        #expect(controller.library.lifecycleIsLoading)
        controller.failLifecycleListing("unavailable", for: retry)
        #expect(controller.library.lifecycleError == "unavailable")
        #expect(!controller.library.lifecycleIsLoading)

        controller.dismissLifecycleListing()
        #expect(controller.library.lifecycleScope == nil)
        #expect(controller.library.lifecycleItems.isEmpty)
        #expect(controller.library.lifecycleError == nil)
        #expect(!controller.library.lifecycleIsLoading)
    }

    @Test("Lifecycle destination switching rejects the previous scope response")
    func lifecycleDestinationSwitchRejectsStaleResponse() {
        let controller = DiscoveryController()
        controller.presentLifecycleListing(.setAside)
        let setAside = controller.beginLifecycleListing(.setAside)

        controller.presentLifecycleListing(.trash)
        let trash = controller.beginLifecycleListing(.trash)
        controller.failLifecycleListing("stale set aside", for: setAside)

        #expect(controller.library.lifecycleScope == .trash)
        #expect(controller.library.lifecycleError == nil)
        #expect(controller.library.lifecycleIsLoading)

        controller.receiveLifecycleItems([], for: trash)
        #expect(controller.library.lifecycleScope == .trash)
        #expect(!controller.library.lifecycleIsLoading)
    }

    @Test("Attention and lifecycle destinations are mutually exclusive")
    func attentionAndLifecycleDestinationMutualExclusion() {
        let controller = DiscoveryController()

        controller.showAttentionQueue(true)
        controller.presentLifecycleListing(.trash)
        #expect(!controller.library.showsAttentionQueue)
        #expect(controller.library.lifecycleScope == .trash)

        controller.showAttentionQueue(true)
        #expect(controller.library.showsAttentionQueue)
        #expect(controller.library.lifecycleScope == nil)
    }

    @Test("Lifecycle destinations preserve Library filters, sort, and disclosure")
    func lifecycleDestinationPreservesWorkspacePresentation() {
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

        controller.presentLifecycleListing(.setAside)
        controller.presentLifecycleListing(.trash)
        controller.dismissLifecycleListing()

        #expect(controller.library.filters == filters)
        #expect(controller.library.sortOrder == .titleAscending)
        #expect(controller.expandedFolders(in: disclosureScope) == ["Arguments", "Sources"])
        #expect(controller.library.locationScope == .workspace)
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
        #expect(contentView.contains("attentionQueueContext: attentionQueueContext"))
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

        let current = UUID()
        controller.functions.begin(
            target: fixtureFunctionTarget(),
            function: .discuss,
            selection: nil,
            presentationID: current
        )
        controller.functions.dismiss(presentationID: UUID())
        #expect(controller.functions.presentationID == current)
        controller.functions.dismiss(presentationID: current)
        #expect(controller.functions.presentationID == nil)
    }

    @Test("Research destinations receive narrow contexts instead of the window model")
    func researchDestinationsAreLeafBoundaries() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "Scholium/Views/ResearchFunctions/ResearchFunctionPanelView.swift",
            "Scholium/Views/ResearchFunctions/ResearchFunctionsInspectorView.swift",
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

    @Test("The typed Research Function route is the only judgment and agent entry panel")
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

        #expect(router.contains("case researchFunction(ResearchFunctionPanelRoute)"))
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
        #expect(windowModelSource.contains("discoveryController.executeSearch("))
        #expect(windowModelSource.contains("researchController.functions"))
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
        #expect(researchControllerSource.contains("@Published var dialogueInitialNotes"))
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

    private func fixtureFunctionTarget() -> ResearchFunctionTarget {
        let vaultID = UUID()
        return ResearchFunctionTarget(
            noteID: UUID(),
            note: VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: "Topics/Agency.md"
            ),
            role: .topic,
            fingerprint: DocumentFingerprint(content: "# Agency\n"),
            title: "Agency"
        )
    }
}
