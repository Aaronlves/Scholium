import ScholiumContracts
import Combine
import Foundation
import Testing
@testable import ScholiumApp

@Suite("Window controller architecture")
@MainActor
struct WindowControllerArchitectureTests {
    @Test("Lifecycle presentation clears moved notes and direct Put Back skips editor flush")
    func lifecyclePresentationCutover() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let putBackStart = try #require(appSource.range(
            of: "func putBackNote(_ target: NoteLifecycleTarget) async throws"
        ))
        let putBackEnd = try #require(appSource.range(
            of: "func requestDocumentMode(",
            range: putBackStart.upperBound..<appSource.endIndex
        ))
        let putBackSource = appSource[
            putBackStart.lowerBound..<putBackEnd.lowerBound
        ]
        #expect(putBackSource.contains("documentController.putBack(target)"))
        #expect(!putBackSource.contains("flushRegisteredEditorIfNeeded"))
        #expect(!putBackSource.contains("currentRegisteredVault"))
        #expect(!putBackSource.contains("documentRevisions"))
        #expect(!putBackSource.contains("noteIdentityByPath"))

        let presentationStart = try #require(appSource.range(
            of: "private func presentCommittedLifecycleMove("
        ))
        let presentationEnd = try #require(appSource.range(
            of: "private func migrateInMemoryPath(",
            range: presentationStart.upperBound..<appSource.endIndex
        ))
        let presentationSource = appSource[
            presentationStart.lowerBound..<presentationEnd.lowerBound
        ]
        #expect(presentationSource.contains(
            "removePresentedDocumentAfterLifecycleMove("
        ))
        #expect(presentationSource.contains(
            "documentTabController.removeTabs(withIDs: matchingTabIDs)"
        ))
        #expect(presentationSource.contains(
            "documentController.clearSelectionAfterClosingLastTab()"
        ))
        #expect(!presentationSource.contains("activateDocument("))

        let splitSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWorkspaceSplitView.swift"
            ),
            encoding: .utf8
        )
        #expect(splitSource.contains(
            "let showsPlaceholder = tabs.isEmpty || selectedTabID == nil"
        ))
    }

    @Test("Folder commands fail explicitly while another folder mutation owns the window")
    func folderMutationBusyFailure() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let moveStart = try #require(appSource.range(
            of: "func moveFolder(\n        _ target: FolderLifecycleTarget,"
        ))
        let trashStart = try #require(appSource.range(
            of: "func moveFolderToTrash(_ target: FolderLifecycleTarget)",
            range: moveStart.upperBound ..< appSource.endIndex
        ))
        let refreshStart = try #require(appSource.range(
            of: "private func refreshCachedWorkspaceVaultSnapshot(",
            range: trashStart.upperBound ..< appSource.endIndex
        ))
        let moveSource = appSource[moveStart.lowerBound ..< trashStart.lowerBound]
        let trashSource = appSource[trashStart.lowerBound ..< refreshStart.lowerBound]

        for source in [moveSource, trashSource] {
            #expect(source.contains("guard !isMutatingFolder else"))
            #expect(source.contains(
                "throw WindowFileTreeMutationError.folderMutationInProgress"
            ))
            #expect(!source.contains("guard !isMutatingFolder else { return }"))
        }
        #expect(trashSource.contains("let vaultID = target.vaultID"))
        #expect(trashSource.contains("relativePath: target.relativePath"))
    }

    @Test("Attention observes only its exact workspace projections")
    func attentionObservationOwnership() throws {
        let store = makeTestWorkspaceStore()
        let workspaceController = WindowWorkspaceController(
            workspaceStore: store,
            requestedTriptychID: nil
        )
        let discoveryController = DiscoveryController()
        let projectionController = WindowWorkspaceProjectionController {
            throw DiscoverySearchExecutionError.workspaceUnavailable
        }
        let dismissalDays = PassthroughSubject<Int, Never>()
        let session = AttentionPopoverSession(
            presentation: AttentionPresentationState(),
            discoveryController: discoveryController,
            workspaceController: workspaceController,
            projectionController: projectionController,
            dismissalDays: 7,
            dependencies: .init(
                dismissalDaysChanges: dismissalDays.eraseToAnyPublisher(),
                refresh: {},
                resynthesize: { _ in }
            )
        )
        var invalidations = 0
        let observation = session.objectWillChange.sink { invalidations += 1 }

        workspaceController.setRecoveryMessage("Unrelated recovery state")
        discoveryController.synchronizeLibrarySelection(
            workspaceSlot: .output,
            location: .setAside
        )
        #expect(invalidations == 0)

        projectionController.reportCatalogError("Fixture catalog failure")
        #expect(invalidations == 1)

        dismissalDays.send(14)
        #expect(session.dismissalDays == 14)
        #expect(invalidations == 2)
        observation.cancel()

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sessionSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/Window/AttentionPopoverSession.swift"
            ),
            encoding: .utf8
        )
        #expect(!sessionSource.contains("WindowModel"))
        #expect(!sessionSource.contains("workspace.objectWillChange"))
        #expect(!sessionSource.contains("?? discoveryController.library.workspaceSlot"))
        #expect(sessionSource.contains(
            "if let workspaceSlot = presentation.workspaceSlot"
        ))
        #expect(sessionSource.contains("workspaceController.$state"))
        #expect(sessionSource.contains("projectionController.$state"))
    }

    @Test("Visible Sidebar always owns the stable Triptych Attention route")
    func stableTriptychAttentionRoute() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWindowManagement.swift"
            ),
            encoding: .utf8
        )
        let start = try #require(source.range(of: "private func preferredAttentionRoute()"))
        let end = try #require(source.range(
            of: "private func registerQAFocusRequest()",
            range: start.upperBound ..< source.endIndex
        ))
        let route = source[start.lowerBound ..< end.lowerBound]

        #expect(route.contains("if appState.sidebarVisible"))
        #expect(route.contains("anchor: .sidebar"))
        #expect(route.contains("workspaceSlot: nil"))
        #expect(!route.contains("visibleTotalCount"))
        #expect(!route.contains("count > 0"))
    }

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
        let content = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ContentView.swift"
            ),
            encoding: .utf8
        )

        #expect(app.contains("lazy var searchController = WindowSearchController("))
        #expect(!app.contains("searchController.objectWillChange"))
        #expect(content.contains(
            "@ObservedObject private var searchController: WindowSearchController"
        ))
        #expect(content.contains(
            "@ObservedObject private var discoveryController: DiscoveryController"
        ))
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
        #expect(!controller.contains("discoveryController.objectWillChange"))
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
        let content = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ContentView.swift"
            ),
            encoding: .utf8
        )

        #expect(app.contains(
            "lazy var workspaceProjectionController = WindowWorkspaceProjectionController("
        ))
        #expect(!app.contains("workspaceProjectionController.objectWillChange"))
        #expect(content.contains(
            "@ObservedObject private var workspaceProjectionController: WindowWorkspaceProjectionController"
        ))
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

    @Test("Agent permission claims and exact-window presentation have distinct owners")
    func researchAgentPermissionWindowOwnership() throws {
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
                "Scholium/Features/ResearchContext/ResearchAgentPermissionWindowController.swift"
            ),
            encoding: .utf8
        )
        let claims = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Features/ResearchContext/ResearchAgentPermissionClaimCoordinator.swift"
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
                "Scholium/Views/ResearchActions/ResearchWriteSetExtensionView.swift"
            ),
            encoding: .utf8
        )

        #expect(app.contains(
            "lazy var researchAgentPermissionWindowController =\n        ResearchAgentPermissionWindowController("
        ))
        #expect(!app.contains("researchAgentPermissionWindowController.objectWillChange"))
        #expect(content.contains(
            "@ObservedObject private var researchAgentPermissionWindowController:"
        ))
        for retiredWindowModelOwner in [
            "@Published private(set) var presentedResearchWriteSetExtension",
            "researchWriteSetExtensionExpiryTask",
            "func resolvePresentedResearchWriteSetExtension",
        ] {
            #expect(!app.contains(retiredWindowModelOwner))
        }
        #expect(controller.contains(
            "final class ResearchAgentPermissionWindowController: ObservableObject"
        ))
        #expect(controller.contains("@Published private(set) var claim"))
        #expect(controller.contains("private var decisionTask"))
        #expect(controller.contains("func registerWindowEndpoint"))
        #expect(controller.contains("func finishDismissal"))
        #expect(controller.contains("private func resetPresentationState"))
        #expect(claims.contains("final class ResearchAgentPermissionClaimCoordinator"))
        #expect(claims.contains("private var claims: [UUID: UUID]"))
        #expect(windowManagement.contains(
            "researchAgentPermissionWindowController.registerWindowEndpoint("
        ))
        #expect(windowManagement.contains("func windowWillClose("))
        #expect(windowManagement.contains("unregisterResearchAgentPermissionWindow()"))
        #expect(windowManagement.contains("agentRequestPriorResponder"))
        #expect(windowManagement.contains("restoreResearchAgentPermissionFocus"))
        #expect(content.contains("appState.researchAgentPermissionWindowController"))
        #expect(sheet.contains("struct ResearchAgentPermissionView: View"))
        #expect(sheet.contains("struct ResearchWriteSetExtensionView: View"))
        #expect(sheet.contains("struct ResearchContinuationPermissionView: View"))
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

    @Test("WindowModel publishes only owned state while commands observe a narrow scope")
    func windowObservationScopes() {
        let store = makeTestWorkspaceStore()
        let first = WindowModel(workspaceStore: store)
        let second = WindowModel(workspaceStore: store)
        let firstCommandRevision = first.commandObservation.revision
        let secondCommandRevision = second.commandObservation.revision
        var rootInvalidations = 0
        let rootObservation = first.objectWillChange.sink {
            rootInvalidations += 1
        }

        first.presentationRouter.present(.createCheckpoint)
        #expect(rootInvalidations == 0)
        #expect(first.commandObservation.revision == firstCommandRevision)

        first.shellState.recordLibraryVisibility(false)
        #expect(rootInvalidations == 0)
        #expect(first.commandObservation.revision > firstCommandRevision)
        #expect(second.commandObservation.revision == secondCommandRevision)

        let revisionAfterShellChange = first.commandObservation.revision
        first.documentController.selectUnavailableDocument(
            vaultID: UUID(),
            relativePath: "Topics/Command Target.md"
        )
        #expect(rootInvalidations == 0)
        #expect(first.commandObservation.revision > revisionAfterShellChange)
        #expect(second.commandObservation.revision == secondCommandRevision)
        rootObservation.cancel()
    }

    @Test("Document tabs borrow one window peripheral presentation")
    func documentTabsBorrowWindowPeripheralPresentation() {
        let presentation = WindowShellState()
        let firstDiscovery = DiscoveryController(shellState: presentation)
        let secondDiscovery = DiscoveryController(shellState: presentation)
        let scope = LibraryDisclosureScope(
            vaultID: UUID(),
            locationScope: .workspace
        )

        firstDiscovery.setExpandedFolders(["Ethics", "Ethics/Agency"], in: scope)
        #expect(secondDiscovery.expandedFolders(in: scope) == ["Ethics", "Ethics/Agency"])

        let firstResearch = ResearchController(shellState: presentation)
        let secondResearch = ResearchController(shellState: presentation)
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
            shellState: WindowShellState()
        )
        let second = DiscoveryController(
            shellState: WindowShellState()
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
        #expect(!controllerSource.contains("@Published private(set) var openDocuments"))
        #expect(!controllerSource.contains("@Published var openDocuments"))
        #expect(!controllerSource.contains("activeDocumentKey"))
        #expect(controllerSource.contains("@Published private(set) var selectedDocument"))
    }

    @Test("The live Document presentation owns mode while sessions retain scroll")
    func documentPresentationOwnsCurrentMode() {
        let reference = fixtureReference(path: "Topics/Presentation.md")
        let descriptor = WindowDocumentDescriptor(
            sessionKey: DocumentSessionKey(vaultID: reference.vaultID, noteID: UUID()),
            reference: reference
        )
        let controller = DocumentController()
        controller.restorePresentationState(
            scrollPositions: [reference.relativePath: 0.64],
            vaultID: reference.vaultID
        )

        controller.installOpenedDocument(descriptor)
        let session = controller.session(for: descriptor)
        #expect(session.presentationMode == .read)
        #expect(session.pendingEditorMode == nil)
        #expect(controller.currentPresentationMode == .read)
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

        controller.rememberPresentationMode(.livePreview)
        controller.rememberScrollPosition(
            0.31,
            for: reference.relativePath,
            vaultID: reference.vaultID
        )
        controller.clearSelection(forRemovedPaths: [reference.relativePath])
        controller.installOpenedDocument(descriptor)

        #expect(controller.session(for: descriptor) === session)
        #expect(session.presentationMode == .read)
        #expect(session.pendingEditorMode == .livePreview)
        #expect(controller.currentPresentationMode == .livePreview)
        #expect(session.scrollFraction == 0.31)
        #expect(session.scrollAnchor == semanticAnchor)
        #expect(controller.presentationSnapshot(vaultID: reference.vaultID) ==
            DocumentPresentationSnapshot(
                scrollPositions: [reference.relativePath: 0.31]
            ))

        controller.resetPresentationState()
        #expect(controller.currentPresentationMode == .read)
        #expect(session.presentationMode == .read)
        #expect(session.scrollFraction == 0)
        #expect(session.scrollAnchor == nil)
    }

    @Test("Document and Inspector modes are retained independently by workspace")
    func workspaceModesAreIndependent() {
        let document = DocumentController()
        let shell = WindowShellState()

        document.rememberPresentationMode(.livePreview)
        shell.selectInspectorMode(.actions)

        shell.selectWorkspace(.topicKnowledge)
        document.selectWorkspace(.topicKnowledge)
        #expect(document.currentPresentationMode == .read)
        #expect(shell.inspector.mode == .overview)

        document.rememberPresentationMode(.source)
        shell.selectInspectorMode(.connect)
        shell.selectWorkspace(.paperAnalysis)
        document.selectWorkspace(.paperAnalysis)

        #expect(document.currentPresentationMode == .livePreview)
        #expect(shell.inspector.mode == .actions)
        #expect(document.presentationMode(for: .topicKnowledge) == .source)
        #expect(shell.inspectorMode(for: .topicKnowledge) == .connect)
    }

    @Test("The current Document mode carries across selected Notes")
    func currentModeCarriesAcrossDocuments() {
        let vaultID = UUID()
        func descriptor(_ path: String) -> WindowDocumentDescriptor {
            WindowDocumentDescriptor(
                sessionKey: DocumentSessionKey(vaultID: vaultID, noteID: UUID()),
                reference: fixtureReference(vaultID: vaultID, path: path)
            )
        }
        let first = descriptor("Topics/First.md")
        let second = descriptor("Topics/Second.md")
        let controller = DocumentController()

        controller.installOpenedDocument(first)
        let firstSession = controller.session(for: first)
        firstSession.preparePresentationMode(.source)
        controller.rememberPresentationMode(.source)

        controller.installOpenedDocument(second)
        let secondSession = controller.session(for: second)
        #expect(controller.currentPresentationMode == .source)
        #expect(secondSession.presentationMode == .read)
        #expect(secondSession.pendingEditorMode == .source)

        secondSession.preparePresentationMode(.livePreview)
        controller.rememberPresentationMode(.livePreview)
        controller.installOpenedDocument(first)

        #expect(controller.currentPresentationMode == .livePreview)
        #expect(firstSession.presentationMode == .read)
        #expect(firstSession.pendingEditorMode == .livePreview)
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
        let target = DocumentEditingTarget.unavailable(
            vaultID: vaultID,
            relativePath: path
        )
        let controller = DocumentController()
        controller.restorePresentationState(
            scrollPositions: [path: 0.42],
            vaultID: nil
        )
        controller.selectUnavailableDocument(vaultID: vaultID, relativePath: path)

        let session = controller.session(for: target)
        #expect(session.presentationMode == .read)
        #expect(session.pendingEditorMode == nil)
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

        controller.failSearch(.failed("stale"), for: first)
        #expect(controller.search.executionIssue == nil)
        #expect(controller.search.criteria.query == "second")

        controller.failSearch(.failed("current"), for: second)
        #expect(controller.search.executionIssue == .failed("current"))
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

        #expect(controller.search.executionIssue == .unavailable(
            "Open a complete Triptych before searching."
        ))
        #expect(!controller.search.isRunning)

        await #expect(throws: DiscoverySearchExecutionError.currentNoteUnavailable) {
            try await controller.executeSearch(
                SearchWorkspaceState(query: "agency", scope: .thisNote),
                context: DiscoverySearchExecutionContext(
                    workspaceIsAvailable: true,
                    currentNoteSnapshot: nil,
                    currentVaultID: nil
                )
            )
        }
        #expect(controller.search.executionIssue == .unavailable(
            "Open a note before searching This Note."
        ))

        await #expect(throws: DiscoverySearchExecutionError.currentVaultUnavailable) {
            try await controller.executeSearch(
                SearchWorkspaceState(query: "agency", scope: .currentVault),
                context: DiscoverySearchExecutionContext(
                    workspaceIsAvailable: true,
                    currentNoteSnapshot: nil,
                    currentVaultID: nil
                )
            )
        }
        #expect(controller.search.executionIssue == .unavailable(
            "Select an available vault before searching This Vault."
        ))
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
        let shell = WindowShellState()
        let controller = DiscoveryController(shellState: shell)
        let request = controller.beginLocationRequest(
            workspaceSlot: .topicKnowledge,
            location: .setAside
        )
        #expect(!controller.library.locationIsLoading)
        #expect(controller.libraryState(for: .topicKnowledge).locationIsLoading)
        #expect(controller.library.workspaceSlot == .paperAnalysis)
        #expect(controller.library.locationScope == .workspace)

        #expect(controller.receiveLocationResult(for: request))
        #expect(controller.library.workspaceSlot == .paperAnalysis)
        #expect(controller.library.locationScope == .workspace)
        shell.selectWorkspace(.topicKnowledge)
        #expect(controller.library.workspaceSlot == .topicKnowledge)
        #expect(controller.library.locationScope == .setAside)
        #expect(!controller.library.locationIsLoading)
        #expect(controller.library.locationError == nil)
    }

    @Test("Each workspace retains its own Library presentation")
    func workspacesRetainIndependentLibraryPresentation() {
        let shell = WindowShellState()
        let controller = DiscoveryController(shellState: shell)
        controller.synchronizeLibrarySelection(
            workspaceSlot: .paperAnalysis,
            location: .trash
        )
        controller.synchronizeLibrarySelection(
            workspaceSlot: .topicKnowledge,
            location: .setAside
        )

        #expect(controller.library.locationScope == .trash)
        shell.selectWorkspace(.topicKnowledge)
        #expect(controller.library.locationScope == .setAside)
        #expect(
            controller.libraryState(for: .paperAnalysis).locationScope == .trash
        )
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

        // Scope browsing, Location browsing, and automatic current-Note reveal
        // all stage from the last accepted Workspace snapshot.
        #expect(
            source.components(separatedBy: "presentation: .stagedReplacement").count - 1 == 3
        )
        #expect(source.contains("private func currentWorkspaceVaultSnapshot("))
        #expect(source.contains(
            "workspaceProjectionController.vaultSnapshot(id: vaultID)"
        ))
    }

    @Test("Location requests in different workspaces remain independent")
    func workspaceLocationRequestsAreIndependent() {
        let shell = WindowShellState()
        let controller = DiscoveryController(shellState: shell)
        let setAside = controller.beginLocationRequest(
            workspaceSlot: .paperAnalysis,
            location: .setAside
        )
        let trash = controller.beginLocationRequest(
            workspaceSlot: .output,
            location: .trash
        )

        #expect(controller.receiveLocationResult(for: setAside))
        #expect(controller.library.workspaceSlot == .paperAnalysis)
        #expect(controller.library.locationScope == .setAside)

        #expect(controller.receiveLocationResult(for: trash))
        #expect(controller.library.workspaceSlot == .paperAnalysis)
        #expect(controller.library.locationScope == .setAside)
        shell.selectWorkspace(.output)
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

    @Test("Created Notes clear filters, preserve sort, and request one exact reveal")
    func createdNoteRevealOwnsLibraryPresentation() throws {
        let controller = DiscoveryController()
        var filters = DiscoveryFilterState()
        filters.needsAttention = true
        filters.tag = "ethics"
        filters.year = 2026
        controller.replaceFilters(filters)
        controller.selectSortOrder(.titleDescending)
        let scope = LibraryDisclosureScope(
            vaultID: UUID(),
            locationScope: .workspace
        )
        controller.setExpandedFolders(["Existing"], in: scope)

        controller.prepareCreatedNoteReveal(
            relativePath: "Arguments/Agency/Untitled.md",
            folderAncestors: ["Arguments", "Arguments/Agency"],
            in: scope
        )

        #expect(controller.library.filters == DiscoveryFilterState())
        #expect(controller.library.sortOrder == .titleDescending)
        #expect(controller.expandedFolders(in: scope) == [
            "Existing", "Arguments", "Arguments/Agency",
        ])
        let request = try #require(controller.libraryRevealRequest)
        #expect(request.scope == scope)
        #expect(request.relativePath == "Arguments/Agency/Untitled.md")
        #expect(request.alignment == .center)
        controller.consumeLibraryRevealRequest(request)
        #expect(controller.libraryRevealRequest == nil)
    }

    @Test("Ordinary Note reveal preserves useful filters and clears only excluding filters")
    func ordinaryNoteRevealOwnsMinimumLibraryPresentation() throws {
        let controller = DiscoveryController()
        var filters = DiscoveryFilterState()
        filters.tag = "ethics"
        controller.replaceFilters(filters)
        controller.selectSortOrder(.titleAscending)
        let scope = LibraryDisclosureScope(
            vaultID: UUID(),
            locationScope: .workspace
        )
        controller.setExpandedFolders(["Existing"], in: scope)

        controller.prepareLibraryNoteReveal(
            relativePath: "Arguments/Agency/Current.md",
            folderAncestors: ["Arguments", "Arguments/Agency"],
            clearFilters: false,
            in: scope
        )

        #expect(controller.library.filters == filters)
        #expect(controller.library.sortOrder == .titleAscending)
        #expect(controller.expandedFolders(in: scope) == [
            "Existing", "Arguments", "Arguments/Agency",
        ])
        let first = try #require(controller.libraryRevealRequest)
        #expect(first.alignment == .nearest)
        controller.consumeLibraryRevealRequest(first)

        controller.prepareLibraryNoteReveal(
            relativePath: "Other/Hidden.md",
            folderAncestors: ["Other"],
            clearFilters: true,
            in: scope
        )
        #expect(controller.library.filters == DiscoveryFilterState())
        #expect(controller.library.sortOrder == .titleAscending)
        #expect(controller.expandedFolders(in: scope).contains("Other"))
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
        #expect(source.contains("scheduleLibraryReveal(for: document)"))
        #expect(source.contains("prepareLibraryNoteReveal("))
        #expect(!source.contains("requestRevealCurrentDocumentInLibrary"))
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

    @Test("Research child owners do not invalidate the records owner")
    func researchObservationOwnership() throws {
        let shellState = WindowShellState()
        let controller = ResearchController(shellState: shellState)
        var invalidations = 0
        let observation = controller.objectWillChange.sink { invalidations += 1 }

        shellState.selectInspectorMode(.actions)
        controller.actions.textValues = ["prompt": "Fixture"]
        #expect(invalidations == 0)

        controller.setActiveDocument(fixtureReference(path: "Topics/Owned.md"))
        #expect(invalidations == 1)
        observation.cancel()

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let controllerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Features/ResearchContext/ResearchController.swift"
            ),
            encoding: .utf8
        )
        let contentSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ContentView.swift"
            ),
            encoding: .utf8
        )
        let noteSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/Note/NoteContentView.swift"
            ),
            encoding: .utf8
        )

        #expect(!controllerSource.contains("shellState.objectWillChange"))
        #expect(!controllerSource.contains("actions.objectWillChange"))
        #expect(contentSource.contains(
            "@ObservedObject private var researchActionController: ResearchActionController"
        ))
        #expect(contentSource.contains(
            "@ObservedObject private var shellState: WindowShellState"
        ))
        #expect(noteSource.contains(
            "@ObservedObject private var shellState: WindowShellState"
        ))
        #expect(!noteSource.contains(
            "@ObservedObject private var controller: ResearchController"
        ))
    }

    @Test("Library disclosure does not invalidate the Discovery owner")
    func discoveryObservationOwnership() throws {
        let shellState = WindowShellState()
        let controller = DiscoveryController(shellState: shellState)
        let scope = LibraryDisclosureScope(
            vaultID: UUID(),
            locationScope: .workspace
        )
        var invalidations = 0
        let observation = controller.objectWillChange.sink { invalidations += 1 }

        shellState.setExpandedFolders(["Sources"], in: scope)
        #expect(invalidations == 0)
        controller.selectSortOrder(.titleAscending)
        #expect(invalidations == 1)
        observation.cancel()

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Features/Discovery/DiscoveryController.swift"
            ),
            encoding: .utf8
        )
        #expect(!source.contains("shellState.objectWillChange"))
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
                    $0.contains("@ObservedObject") && $0.contains("WindowModel")
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
        let creationStart = try #require(windowModelSource.range(
            of: "func requestUntitledNoteCreation(in folderRelativePath: String?)"
        ))
        let creationEnd = try #require(windowModelSource.range(
            of: "func requestUntitledFolderCreation(in parentRelativePath: String?)",
            range: creationStart.upperBound..<windowModelSource.endIndex
        ))
        let creationSource = String(
            windowModelSource[creationStart.lowerBound..<creationEnd.lowerBound]
        )
        let create = try #require(creationSource.range(
            of: "documentController.createUntitledNote("
        ))
        let sourceAhead = try #require(creationSource.range(
            of: "let sourceAheadSnapshot = commit.sourceAheadSnapshot",
            range: create.upperBound..<creationSource.endIndex
        ))
        let install = try #require(creationSource.range(
            of: "workspaceProjectionController.recordCommittedNote(",
            range: sourceAhead.upperBound..<creationSource.endIndex
        ))
        let activate = try #require(creationSource.range(
            of: "activateWorkspaceReference(",
            range: install.upperBound..<creationSource.endIndex
        ))
        _ = try #require(creationSource.range(
            of: "revealCreatedNoteInLibrary(document.relativePath, vaultID: vault.id)",
            range: activate.upperBound..<creationSource.endIndex
        ))
        #expect(creationSource.contains("let commit = outcome.committedValue"))
        #expect(creationSource.contains("let document = commit.document"))
        #expect(!creationSource.contains("refreshCachedWorkspaceVaultSnapshot"))
        #expect(!creationSource.contains("browseRegisteredVault"))
        #expect(creationSource.contains("reportCommittedMutationWarnings(outcome)"))
        let folderCreationStart = try #require(windowModelSource.range(
            of: "func requestUntitledFolderCreation(in parentRelativePath: String?)"
        ))
        let folderCreationEnd = try #require(windowModelSource.range(
            of: "func moveFolder(",
            range: folderCreationStart.upperBound..<windowModelSource.endIndex
        ))
        let folderCreationSource = windowModelSource[
            folderCreationStart.lowerBound..<folderCreationEnd.lowerBound
        ]
        let committedFolder = try #require(folderCreationSource.range(
            of: "workspaceProjectionController.recordCommittedFolder("
        ))
        let recoveryRefresh = try #require(folderCreationSource.range(
            of: "refreshCachedWorkspaceVaultSnapshot",
            range: committedFolder.upperBound..<folderCreationSource.endIndex
        ))
        #expect(committedFolder.lowerBound < recoveryRefresh.lowerBound)
        #expect(windowModelSource.contains(
            "private func presentCommittedLifecycleMove("
        ))
        #expect(windowModelSource.contains(
            "workspaceProjectionController.recordCommittedNoteMove("
        ))
        let moveStart = try #require(windowModelSource.range(
            of: "func moveNote("
        ))
        let moveEnd = try #require(windowModelSource.range(
            of: "func setAsideNote(",
            range: moveStart.upperBound..<windowModelSource.endIndex
        ))
        let moveSource = windowModelSource[
            moveStart.lowerBound..<moveEnd.lowerBound
        ]
        let moveProjection = try #require(moveSource.range(
            of: "workspaceProjectionController.recordCommittedNoteMove("
        ))
        let moveFallbackRefresh = try #require(moveSource.range(
            of: "refreshCachedWorkspaceVaultSnapshot(",
            range: moveProjection.upperBound..<moveSource.endIndex
        ))
        #expect(moveProjection.lowerBound < moveFallbackRefresh.lowerBound)
        #expect(moveSource.contains("if outcome.identityRecoveryWarning == nil"))
        #expect(moveSource.contains("documentController.recordCommittedSnapshot("))
        #expect(moveSource.contains("revealCreatedNoteInLibrary("))
        #expect(windowModelSource.contains(
            "let lifecycle = currentNote?.workspaceSnapshot?.lifecycle ?? .active"
        ))
        #expect(windowModelSource.contains(
            "func importMarkdownFiles(_ urls: [URL]) async throws -> MarkdownImportBatchOutcome"
        ))
        #expect(source.contains("appState.requestMarkdownImport(urls)"))
        #expect(windowModelSource.contains(
            "private var markdownImportTask: Task<Void, Never>?"
        ))
        #expect(windowModelSource.contains("func requestMarkdownImport(_ urls: [URL])"))
        #expect(windowModelSource.contains("try Task.checkCancellation()"))
        #expect(windowModelSource.contains("failures.append(MarkdownImportFailure("))
        #expect(windowModelSource.contains(
            "identityRecoveryWarnings.append(warning)"
        ))
        #expect(windowModelSource.contains(
            "let destinationWorkspaceID = workspaceAssignment?.id"
        ))
        #expect(windowModelSource.contains(
            "guard workspaceAssignment?.id == destinationWorkspaceID"
        ))
        #expect(windowModelSource.contains("catch is CancellationError"))
        #expect(windowModelSource.contains(
            "if currentRegisteredVault?.id == vault.id"
        ))
        #expect(windowModelSource.contains(
            "The imported files are already committed; do not import them again."
        ))
        #expect(!windowModelSource.contains(
            "func importMarkdownFiles(_ urls: [URL]) async throws -> [NoteDocument]"
        ))
        #expect(!windowModelSource.contains("committedButRefreshFailed"))
        #expect(windowModelSource.contains(
            "identityResolved: outcome.identityRecoveryWarning == nil"
        ))
        #expect(windowModelSource.contains("searchController.open("))
        #expect(searchControllerSource.contains("discoveryController.executeSearch("))
        #expect(windowModelSource.contains("researchController.actions"))
    }

    @Test("Partial Markdown import never presents committed files as retryable")
    func markdownImportOutcomePresentation() {
        let window = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let imported = NoteDocument(
            relativePath: "Imported.md",
            rawContent: "# Imported\n"
        )

        window.presentMarkdownImportOutcome(.init(
            destinationName: "Topics",
            documents: [imported],
            failures: [.init(sourceName: "Broken.md", reason: "Invalid UTF-8")],
            derivedRefreshWarnings: [],
            identityRecoveryWarnings: ["Identity registry is unavailable."],
            presentationWarning: nil
        ))

        #expect(window.vaultError == nil)
        #expect(window.toastMessage?.kind == .warning)
        #expect(window.toastMessage?.message.contains("already committed") == true)
        #expect(window.toastMessage?.message.contains("do not import them again") == true)
        #expect(window.toastMessage?.message.contains("Topics") == true)
        #expect(window.toastMessage?.message.contains(
            "stable note identity recovery is incomplete"
        ) == true)
        #expect(window.toastMessage?.message.contains(
            "Identity registry is unavailable."
        ) == true)

        window.presentMarkdownImportOutcome(.init(
            destinationName: "Topics",
            documents: [],
            failures: [.init(sourceName: "Broken.md", reason: "Invalid UTF-8")],
            derivedRefreshWarnings: [],
            identityRecoveryWarnings: [],
            presentationWarning: nil
        ))

        #expect(window.vaultError?.contains("No Markdown files were imported") == true)
        #expect(window.vaultError?.contains("Broken.md") == true)
    }

    @Test("Window composition consumes research capabilities without a mega-port")
    func researchCapabilityCompositionIsNarrow() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contracts = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ScholiumContracts/UseCases.swift"
            ),
            encoding: .utf8
        )
        let windowSession = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Services/WindowSession.swift"
            ),
            encoding: .utf8
        )
        let researchController = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Features/ResearchContext/ResearchController.swift"
            ),
            encoding: .utf8
        )
        let commandLineContracts = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ScholiumContracts/CommandLineToolContracts.swift"
            ),
            encoding: .utf8
        )
        let researchActivityContracts = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ScholiumContracts/ResearchActivityContracts.swift"
            ),
            encoding: .utf8
        )
        let workspaceModels = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ScholiumContracts/WorkspaceModels.swift"
            ),
            encoding: .utf8
        )

        #expect(!contracts.contains("protocol ResearchUseCases"))
        for unconsumedPort in [
            "protocol ResearchSkillInstallationUseCases",
            "protocol ResearchPermissionUseCases",
            "protocol SettingsUseCases",
            "protocol WorkspaceEventStreaming",
        ] {
            #expect(!contracts.contains(unconsumedPort))
        }
        #expect(!commandLineContracts.contains("protocol CommandLineToolUseCases"))
        #expect(!researchActivityContracts.contains("PendingResearchState"))
        #expect(!researchActivityContracts.contains("PendingResearchRoute"))
        #expect(!workspaceModels.contains("pendingResearchStates"))
        #expect(windowSession.contains("struct WindowResearchCapabilities: Sendable"))
        for capability in [
            "let records: any ResearchRecordUseCases",
            "let checkpoints: any ResearchCheckpointUseCases",
            "let actions: any ResearchActionUseCases",
            "let sourceAccess: any ResearchSourceAccessUseCases",
        ] {
            #expect(windowSession.contains(capability))
        }
        #expect(!researchController.contains("ResearchUseCases"))
        #expect(researchController.contains("struct ResearchControllerCapabilities: Sendable"))
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
        let shellStateSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/Window/WindowShellState.swift"
            ),
            encoding: .utf8
        )
        let workspaceControllerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/Window/WindowWorkspaceController.swift"
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
        #expect(!windowModelSource.contains("cssSnippetStore.objectWillChange"))

        for shellOwnedState in [
            "@Published var sidebarVisible",
            "@Published private(set) var hasCompletedInitialRestore",
            "@Published var documentTextScale",
            "@Published var refreshStatusText",
            "@Published var windowSessionPersistenceError",
        ] {
            #expect(!windowModelSource.contains(shellOwnedState))
        }
        #expect(windowModelSource.contains("let shellState = WindowShellState()"))
        #expect(shellStateSource.contains("@Published private(set) var libraryVisible"))
        #expect(shellStateSource.contains("@Published private(set) var documentTextScale"))
        #expect(shellStateSource.contains("@Published private(set) var refreshStatusText"))
        for workspaceSessionState in [
            "@Published var workspaceAssignment",
            "@Published var registeredTriptychs",
            "@Published var workspaceRecoveryMessage",
            "@Published var workspaceAccessRecovery",
            "@Published private(set) var activeTriptychServicesID",
        ] {
            #expect(!windowModelSource.contains(workspaceSessionState))
        }
        #expect(workspaceControllerSource.contains(
            "@Published private(set) var state = WindowWorkspaceSessionState()"
        ))
        #expect(workspaceControllerSource.contains(
            "private(set) var activeCapabilities: WindowWorkspaceCapabilities?"
        ))

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
        #expect(!windowModelSource.contains("@Published var interruptedSaveRecoveries"))
        #expect(!researchControllerSource.contains("@Published var dialogueInitialNotes"))
        #expect(researchControllerSource.contains("@Published var transactionRecoveryRecords"))
        #expect(researchControllerSource.contains("@Published var interruptedSaveRecoveries"))

        #expect(controllerSource.contains("private let sessions = DocumentSessionStore()"))
        #expect(!controllerSource.contains("sessions: DocumentSessionStore"))
    }

    @Test("Interrupted save recovery reuses one route and flushes before restore")
    func interruptedSaveRecoveryBoundary() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scholium/App/ScholiumApp.swift"),
            encoding: .utf8
        )
        let contentSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scholium/Views/ContentView.swift"),
            encoding: .utf8
        )
        let recoveryViewSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/Note/TransactionRecoveryView.swift"
            ),
            encoding: .utf8
        )
        let routerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/Window/WindowPresentationRouter.swift"
            ),
            encoding: .utf8
        )
        let restoreStart = try #require(appSource.range(
            of: "func restoreInterruptedSaveRecovery("
        ))
        let restoreEnd = try #require(appSource.range(
            of: "private func migrateAppOwnedState(",
            range: restoreStart.upperBound..<appSource.endIndex
        ))
        let restoreSource = String(
            appSource[restoreStart.lowerBound..<restoreEnd.lowerBound]
        )
        let flush = try #require(restoreSource.range(
            of: "editorFlushCoordinator.flushAllEditors(in: assignment.id)"
        ))
        _ = try #require(restoreSource.range(
            of: "researchController.restoreInterruptedSaveRecovery(recovery)",
            range: flush.upperBound..<restoreSource.endIndex
        ))

        #expect(contentSource.contains("case .transactionRecovery:"))
        #expect(contentSource.contains("interruptedSaves: appState.interruptedSaveRecoveries"))
        #expect(recoveryViewSource.contains("DisclosureGroup(\"View Candidate Source\""))
        #expect(recoveryViewSource.contains("Button(\"Copy Candidate\")"))
        #expect(recoveryViewSource.contains("Button(restoreButtonTitle)"))
        #expect(routerSource.contains("case transactionRecovery"))
        #expect(!routerSource.contains("case interruptedSaveRecovery"))
    }

    @Test("Research reset cannot carry an interrupted save into another Triptych")
    func interruptedSaveRecoveryReset() {
        let controller = ResearchController()
        let expected = DocumentFingerprint(content: "expected")
        controller.interruptedSaveRecoveries = [InterruptedSaveRecovery(
            id: InterruptedSaveRecoveryID(
                vaultID: UUID(),
                transactionID: UUID()
            ),
            relativePath: "Note.md",
            expectedRevision: expected,
            candidateRevision: DocumentFingerprint(content: "candidate"),
            createdAt: Date(),
            retainedReason: "Interrupted",
            sourceState: .expectedRevision
        )]
        controller.interruptedSaveRecoveryError = "Unavailable"

        controller.reset()

        #expect(controller.interruptedSaveRecoveries.isEmpty)
        #expect(controller.interruptedSaveRecoveryError == nil)
    }

    @Test("Editor flush registration has one exact-window coordinator")
    func editorFlushOwnership() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let coordinatorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/Window/WindowEditorFlushCoordinator.swift"
            ),
            encoding: .utf8
        )
        let storeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Services/WindowSession.swift"
            ),
            encoding: .utf8
        )
        let start = try #require(appSource.range(of: "final class WindowModel: ObservableObject"))
        let end = try #require(appSource.range(
            of: "private enum ClipboardWorkflowError",
            range: start.upperBound..<appSource.endIndex
        ))
        let windowModelSource = String(appSource[start.lowerBound..<end.lowerBound])

        #expect(windowModelSource.contains(
            "private let editorFlushCoordinator: WindowEditorFlushCoordinator"
        ))
        for retiredRootResponsibility in [
            "private struct EditorFlushRegistration",
            "stableEditorFlushToken",
            "stableEditorFlushTriptychID",
            "workspaceStore.registerEditorFlush",
            "workspaceStore.unregisterEditorFlush",
            "workspaceStore.flushEditors",
        ] {
            #expect(!windowModelSource.contains(retiredRootResponsibility))
        }
        #expect(coordinatorSource.contains(
            "final class WindowEditorFlushCoordinator"
        ))
        #expect(coordinatorSource.contains(
            "protocol WorkspaceEditorFlushRegistry: AnyObject"
        ))
        #expect(coordinatorSource.contains("func activateTriptych("))
        #expect(coordinatorSource.contains("func updateWindowID("))
        #expect(coordinatorSource.contains("func shutdown()"))
        #expect(windowModelSource.contains("func finalizeWindowClose()"))
        let closePreparationStart = try #require(windowModelSource.range(
            of: "func prepareForWindowClose() async throws -> ClosePreparationOutcome"
        ))
        let closeFinalizationStart = try #require(windowModelSource.range(
            of: "func finalizeWindowClose()",
            range: closePreparationStart.upperBound..<windowModelSource.endIndex
        ))
        let closePreparationSource = String(
            windowModelSource[
                closePreparationStart.lowerBound..<closeFinalizationStart.lowerBound
            ]
        )
        #expect(!closePreparationSource.contains("editorFlushCoordinator.shutdown()"))
        let closeFinalizationEnd = try #require(windowModelSource.range(
            of: "private func enqueueDocumentTransition(",
            range: closeFinalizationStart.upperBound..<windowModelSource.endIndex
        ))
        let closeFinalizationSource = String(
            windowModelSource[
                closeFinalizationStart.lowerBound..<closeFinalizationEnd.lowerBound
            ]
        )
        #expect(closeFinalizationSource.contains("markdownImportTask?.cancel()"))
        #expect(closeFinalizationSource.contains("markdownImportTask = nil"))
        #expect(closeFinalizationSource.contains("editorFlushCoordinator.shutdown()"))
        #expect(storeSource.contains(
            "WorkspaceStore: ObservableObject, WorkspaceEditorFlushRegistry"
        ))
    }

    @Test("Remaining WindowModel Store calls are classified and allowlisted")
    func workspaceStoreCallAudit() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let coordinatorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/Window/WindowSessionPersistenceCoordinator.swift"
            ),
            encoding: .utf8
        )
        let start = try #require(appSource.range(of: "final class WindowModel: ObservableObject"))
        let end = try #require(appSource.range(
            of: "private enum ClipboardWorkflowError",
            range: start.upperBound..<appSource.endIndex
        ))
        let windowModelSource = String(appSource[start.lowerBound..<end.lowerBound])
        let calls = windowModelSource
            .components(separatedBy: "workspaceStore.")
            .dropFirst()
            .map { fragment in
                String(fragment.prefix { character in
                    character.isLetter
                        || character.isNumber
                        || character == "_"
                        || character == "$"
                })
            }
        let actual = Dictionary(grouping: calls, by: { $0 }).mapValues(\.count)

        let compositionAndSubscription = [
            "savedSearches": 1,
            "saveSavedSearches": 1,
            "researchAgentPermissionClaims": 1,
            "refreshResearchWriteSetExtension": 1,
            "resolveResearchWriteSetExtension": 1,
            "refreshResearchContinuation": 1,
            "resolveResearchContinuation": 1,
            "cssSnippetStore": 1,
            "zoteroBridge": 1,
            "$latestWorkspaceActivation": 1,
            "$workspaceEvents": 1,
        ]
        let windowIntentAndDelivery = [
            "resolveVault": 2,
            "revealInFinder": 5,
            "openExternal": 1,
        ]
        let workspaceActivationAndRecovery = [
            "configureTriptychCapabilities": 1,
            "registeredVaults": 2,
            "registeredTriptychs": 2,
            "portableContainerURL": 2,
            "workspaceCapabilities": 2,
            "refreshPendingResearchAgentPermissions": 1,
            "vaultConfig": 2,
            "snapshot": 1,
        ]
        var approved: [String: Int] = [:]
        for category in [
            compositionAndSubscription,
            windowIntentAndDelivery,
            workspaceActivationAndRecovery,
        ] {
            for (name, count) in category {
                approved[name, default: 0] += count
            }
        }

        #expect(compositionAndSubscription.values.reduce(0, +) == 11)
        #expect(windowIntentAndDelivery.values.reduce(0, +) == 8)
        #expect(workspaceActivationAndRecovery.values.reduce(0, +) == 13)
        #expect(actual == approved)
        #expect(!windowModelSource.contains("workspaceStore.windowSession"))
        #expect(!windowModelSource.contains("workspaceStore.saveWindowSession"))
        #expect(coordinatorSource.contains(
            "protocol WindowSessionPersistenceStore: AnyObject"
        ))
        #expect(coordinatorSource.contains("func load(id: UUID)"))
        #expect(coordinatorSource.contains("store.saveWindowSession("))
    }

    @Test("Window consumers observe bounded owners instead of one root relay")
    func windowObservationOwnership() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let commandObservationSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/Window/WindowCommandObservation.swift"
            ),
            encoding: .utf8
        )
        let contentSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ContentView.swift"
            ),
            encoding: .utf8
        )
        let toolbarSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWorkspaceToolbar.swift"
            ),
            encoding: .utf8
        )
        let start = try #require(appSource.range(of: "final class WindowModel: ObservableObject"))
        let end = try #require(appSource.range(
            of: "private enum ClipboardWorkflowError",
            range: start.upperBound..<appSource.endIndex
        ))
        let windowModelSource = String(appSource[start.lowerBound..<end.lowerBound])
        let rootStart = try #require(appSource.range(of: "private struct ScholiumWindowRoot: View"))
        let observedRootStart = try #require(appSource.range(
            of: "private struct ScholiumWindowObservedRoot: View",
            range: rootStart.upperBound..<appSource.endIndex
        ))
        let observedRootEnd = try #require(appSource.range(
            of: "private struct ScholiumSettingsRoot: View",
            range: observedRootStart.upperBound..<appSource.endIndex
        ))
        let stateObjectRootSource = String(
            appSource[rootStart.lowerBound..<observedRootStart.lowerBound]
        )
        let observedRootSource = String(
            appSource[observedRootStart.lowerBound..<observedRootEnd.lowerBound]
        )

        #expect(!windowModelSource.contains("self?.objectWillChange.send()"))
        #expect(windowModelSource.contains(
            "lazy var commandObservation = WindowCommandObservation("
        ))
        #expect(appSource.contains(
            ".focusedSceneObject(appState.commandObservation)"
        ))
        #expect(appSource.contains(
            "@FocusedObject private var commandObservation: WindowCommandObservation?"
        ))
        #expect(stateObjectRootSource.contains("@StateObject private var appState: WindowModel"))
        #expect(stateObjectRootSource.contains("ScholiumWindowObservedRoot("))
        #expect(!stateObjectRootSource.contains("@ObservedObject"))
        #expect(observedRootSource.contains("let appState: WindowModel"))
        #expect(observedRootSource.contains(
            "@ObservedObject private var shellState: WindowShellState"
        ))
        #expect(observedRootSource.contains(
            "_shellState = ObservedObject(wrappedValue: appState.shellState)"
        ))
        #expect(commandObservationSource.contains(
            "final class WindowCommandObservation: ObservableObject"
        ))
        #expect(commandObservationSource.contains(
            "changes(shellState.$libraryVisible)"
        ))
        #expect(commandObservationSource.contains(
            "changes(researchActionController.$availability)"
        ))
        #expect(!contentSource.contains("@EnvironmentObject var appState: WindowModel"))
        for boundedOwner in [
            "@ObservedObject private var presentationRouter: WindowPresentationRouter",
            "@ObservedObject private var discoveryController: DiscoveryController",
            "@ObservedObject private var searchController: WindowSearchController",
            "@ObservedObject private var researchController: ResearchController",
            "@ObservedObject private var researchActionController: ResearchActionController",
            "@ObservedObject private var shellState: WindowShellState",
            "@ObservedObject private var documentController: DocumentController",
            "@ObservedObject private var workspaceProjectionController: WindowWorkspaceProjectionController",
        ] {
            #expect(contentSource.contains(boundedOwner))
        }
        #expect(!toolbarSource.contains("appState.objectWillChange"))
        #expect(!toolbarSource.contains("visibilityObservation"))
        #expect(toolbarSource.contains("static var itemIdentifiers:"))
        #expect(toolbarSource.contains(
            "private struct ScholiumWorkspaceSidebarToolbarView: View"
        ))
        #expect(toolbarSource.contains(
            "private struct ScholiumWorkspaceInspectorToolbarView: View"
        ))
        #expect(toolbarSource.contains("@ObservedObject var shellState: WindowShellState"))
    }

    @Test("Return and Record windows share one accessible Result, Evaluation, and Method-feedback surface")
    func sharedResearchEvaluationSurface() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(
                contentsOf: repositoryRoot.appendingPathComponent(path),
                encoding: .utf8
            )
        }
        let evaluation = try source(
            "Scholium/Views/ResearchActions/ResearcherEvaluationView.swift"
        )
        let actionPanel = try source(
            "Scholium/Views/ResearchActions/ResearchActionPanelView.swift"
        )
        let recordBrowser = try source(
            "Scholium/Views/ResearchRecord/ResearchRecordBrowserView.swift"
        )
        let permissions = try source(
            "Scholium/Views/ResearchActions/ResearchWriteSetExtensionView.swift"
        )

        for sharedView in [
            "ResearchFinalizedResultView(",
            "ResearcherEvaluationView(",
            "ResearchMethodFeedbackView(",
        ] {
            #expect(actionPanel.contains(sharedView))
            #expect(recordBrowser.contains(sharedView))
        }
        for semanticBoundary in [
            "RESEARCH RESULT", "RESEARCHER EVALUATION", "METHOD FEEDBACK",
            "does not change the Agent's finalized result",
            "does not by itself establish a philosophical truth",
            "Source or Attribution", "Concept or Interpretation",
            "Argument or Objection/Reply",
            "Epistemic Identity or Researcher State",
            "Evidential Scope or Restraint", "Research Help or Next Step",
            "No Issues Observed", "Valuable Discovery",
        ] {
            #expect(evaluation.contains(semanticBoundary))
        }
        #expect(evaluation.contains("let expectedRevision = baseline.revision"))
        #expect(evaluation.contains("record.finalizedResultFingerprint()"))
        #expect(evaluation.contains("sourceEvaluationRevision:"))
        #expect(evaluation.contains("Improve Current Method…"))
        #expect(evaluation.contains(
            "it does not copy or reinterpret the evaluation automatically"
        ))
        for identifier in [
            "scholium.researchResult.finalized",
            "scholium.researchEvaluation.saveState",
            "scholium.researchEvaluation.note",
            "scholium.researchEvaluation.save",
            "scholium.methodFeedback.improve",
        ] {
            #expect(evaluation.contains(identifier))
        }

        #expect(permissions.contains(".accessibilityAddTraits(.isModal)"))
        #expect(permissions.contains(".toggleStyle(.checkbox)"))
        #expect(permissions.contains(".keyboardShortcut(.defaultAction)"))
        #expect(permissions.contains(".keyboardShortcut(.cancelAction)"))
        #expect(permissions.contains("Allow Selected Notes"))
        #expect(permissions.contains("Continue Without Changes"))
        #expect(permissions.contains(
            "This starts a new independent Run with current permissions"
        ))
        #expect(!permissions.contains("Allow Entire Triptych"))
    }

    @Test("Permission presentation keeps decisions separate from execution guarantees")
    func permissionPresentationUsesDecisionCopy() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(
                contentsOf: repositoryRoot.appendingPathComponent(path),
                encoding: .utf8
            )
        }

        let permissions = try source(
            "Scholium/Views/ResearchActions/ResearchWriteSetExtensionView.swift"
        )
        let settings = try source(
            "Scholium/Views/ResearchPermissionSettingsView.swift"
        )
        let preview = try source(
            "Scholium/UI/PreviewCatalog/ResearchWorkflowPreviewCatalog.swift"
        )

        #expect(permissions.contains(
            "Select the requested Notes this Run may modify."
        ))
        #expect(permissions.contains(
            "This starts a new independent Run with current permissions"
        ))
        for retiredCopy in [
            "One decision may add any selected subset to this Run",
            "Scholium will recheck every selected document",
            "Material instructions cannot change the selected Action",
            "it will not inherit the prior Run's search responses",
        ] {
            #expect(!permissions.contains(retiredCopy))
        }
        #expect(!settings.contains("INVARIANTS"))
        #expect(!preview.contains("ResearchProofNotice"))
        #expect(preview.contains("Select the requested Notes this Run may modify."))
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
