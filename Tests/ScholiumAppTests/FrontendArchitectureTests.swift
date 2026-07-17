import ScholiumContracts
import AppKit
import Foundation
import ImageIO
import Testing
@testable import ScholiumApp

@Suite("Frontend architecture")
@MainActor
struct FrontendArchitectureTests {
    @Test("A window presents at most one sheet route")
    func presentationRouteExclusivity() {
        let router = WindowPresentationRouter()

        router.present(.createCheckpoint)
        #expect(router.sheet?.id == "create-checkpoint")

        router.presentFrontmatter(path: "Topics/Agency.md")
        guard case .frontmatter(let frontmatterRoute) = router.sheet else {
            Issue.record("Expected Properties to replace the checkpoint route")
            return
        }
        #expect(frontmatterRoute.path == "Topics/Agency.md")
        router.dismissSheet(if: "create-checkpoint")
        #expect(router.sheet?.id == frontmatterRoute.id)

        router.dismissSheet(if: frontmatterRoute.id)
        #expect(router.sheet == nil)

        router.fileImport = .markdown
        router.alert = .actionFailure(message: "Fixture failure")
        #expect(router.fileImport == .markdown)
        #expect(router.alert?.message == "Fixture failure")
        router.dismissAll()
        #expect(router.fileImport == nil)
        #expect(router.alert == nil)
    }

    @Test("Properties can suspend and resume exactly one Research Function route")
    func frontmatterResearchFunctionContinuation() throws {
        let router = WindowPresentationRouter()
        let functionRoute = ResearchFunctionPanelRoute(
            target: VaultNoteReference(
                vaultID: UUID(),
                vaultName: "Topics",
                vaultRole: .topicKnowledge,
                relativePath: "Topics/Agency.md"
            ),
            function: .review,
            presentationID: UUID()
        )
        let propertiesRoute = FrontmatterPanelRoute(
            path: "Topics/Agency.md",
            returnToResearchFunction: functionRoute
        )

        router.present(.researchFunction(functionRoute))
        router.present(.frontmatter(propertiesRoute))
        #expect(router.suspendsResearchFunction(
            presentationID: functionRoute.presentationID
        ))

        router.finishFrontmatter(propertiesRoute)
        guard case .researchFunction(let resumedRoute) = router.sheet else {
            Issue.record("Expected the same Review route to resume")
            return
        }
        #expect(resumedRoute == functionRoute)
        router.dismissSheet(if: propertiesRoute.id)
        #expect(router.sheet?.id == "research-function:\(functionRoute.presentationID.uuidString.lowercased())")
    }

    @Test("A stale Properties completion cannot replace a newer same-path continuation")
    func staleFrontmatterContinuationIsRejected() {
        let router = WindowPresentationRouter()
        let target = VaultNoteReference(
            vaultID: UUID(),
            vaultName: "Topics",
            vaultRole: .topicKnowledge,
            relativePath: "Topics/Agency.md"
        )
        let olderFunction = ResearchFunctionPanelRoute(
            target: target,
            function: .review,
            presentationID: UUID()
        )
        let newerFunction = ResearchFunctionPanelRoute(
            target: target,
            function: .dialogue,
            presentationID: UUID()
        )
        let older = FrontmatterPanelRoute(
            path: target.relativePath,
            returnToResearchFunction: olderFunction
        )
        let newer = FrontmatterPanelRoute(
            path: target.relativePath,
            returnToResearchFunction: newerFunction
        )

        router.present(.frontmatter(older))
        router.present(.frontmatter(newer))
        router.finishFrontmatter(older)
        #expect(router.sheet?.id == newer.id)

        router.finishFrontmatter(newer)
        guard case .researchFunction(let resumed) = router.sheet else {
            Issue.record("Expected only the current Properties continuation to resume")
            return
        }
        #expect(resumed == newerFunction)
    }

    @Test("Root setup and workspace setup sheet are mutually exclusive")
    func workspaceSetupPresentationExclusivity() {
        let router = WindowPresentationRouter()

        router.setWorkspaceSetupPresented(true, rootSetupOwnsPresentation: true)
        #expect(router.sheet == nil)

        router.setWorkspaceSetupPresented(true, rootSetupOwnsPresentation: false)
        #expect(router.sheet?.id == "workspace-setup")

        router.setWorkspaceSetupPresented(false, rootSetupOwnsPresentation: false)
        #expect(router.sheet == nil)
    }

    @Test("Launch geometry waits for restoration before choosing setup or workspace")
    func launchGeometryDecision() {
        #expect(ScholiumWindowPresentation.resolve(
            hasCompletedInitialRestore: false,
            hasVaultConfiguration: false
        ) == .launching)
        #expect(ScholiumWindowPresentation.resolve(
            hasCompletedInitialRestore: false,
            hasVaultConfiguration: true
        ) == .launching)
        #expect(ScholiumWindowPresentation.resolve(
            hasCompletedInitialRestore: true,
            hasVaultConfiguration: false
        ) == .setup)
        #expect(ScholiumWindowPresentation.resolve(
            hasCompletedInitialRestore: true,
            hasVaultConfiguration: true
        ) == .workspace)
    }

    @Test("A 900-point workspace keeps Library reachable through native sidebar chrome")
    func compactLibraryReachability() throws {
        #expect(ScholiumLibraryVisibilityPolicy.automaticVisibility(
            windowWidth: 900,
            hasOpenDocument: false,
            isInitial: true,
            previousLayoutMode: .medium
        ) == true)
        #expect(ScholiumLibraryVisibilityPolicy.automaticVisibility(
            windowWidth: 900,
            hasOpenDocument: true,
            isInitial: true,
            previousLayoutMode: .medium
        ) == false)
        #expect(ScholiumLibraryVisibilityPolicy.automaticVisibility(
            windowWidth: 900,
            hasOpenDocument: false,
            isInitial: true,
            previousLayoutMode: .compact
        ) == true)

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scholium/Views/ContentView.swift"),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scholium/App/ScholiumApp.swift"),
            encoding: .utf8
        )
        let sidebarSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/Sidebar/SidebarView.swift"
            ),
            encoding: .utf8
        )
        let noteSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/Note/NoteContentView.swift"
            ),
            encoding: .utf8
        )
        #expect(!contentSource.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(!noteSource.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(contentSource.contains("ToolbarItem(placement: .navigation)"))
        #expect(contentSource.contains("Label(\"Triptych management\", systemImage: \"ellipsis\")"))
        #expect(!appSource.contains("suppressSystemSidebarToggle"))
        #expect(!appSource.contains("Collapse Note"))
        #expect(sidebarSource.contains(".font(ScholiumInterfaceTypography.rowTitle)"))
        #expect(sidebarSource.contains(".font(ScholiumInterfaceTypography.metadata)"))
        #expect(sidebarSource.contains(".font(.body)"))
    }

    @Test("Atmospheric artwork is fixed, Library-only, and decorative")
    func atmosphericNavigationArtworkContract() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for name in [
            "ScholiumNavigationBackdropLight.png",
            "ScholiumNavigationBackdropDark.png",
        ] {
            let url = repository.appendingPathComponent("Scholium/Resources/Artwork/\(name)")
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let properties = try #require(
                CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            )
            #expect(properties[kCGImagePropertyPixelWidth] as? Int == 3_200)
            #expect(properties[kCGImagePropertyPixelHeight] as? Int == 2_000)
        }

        let content = try String(
            contentsOf: repository.appendingPathComponent("Scholium/Views/ContentView.swift"),
            encoding: .utf8
        )
        #expect(content.contains("if !reduceTransparency"))
        #expect(content.contains("NavigationBackdropView(colorScheme: colorScheme)"))
        #expect(content.contains("Rectangle().fill(.regularMaterial)"))
        #expect(content.contains(".ignoresSafeArea(.container, edges: .top)"))
        #expect(content.contains(".backgroundExtensionEffect()"))
        #expect(content.contains(".accessibilityHidden(true)"))
        #expect(content.contains("ScholiumMetrics.Navigation.panelInset"))
        #expect(content.contains("ScholiumMetrics.Navigation.panelCornerRadius"))
    }

    @Test("Independent windows do not share presentation or document sessions")
    func windowIsolation() {
        let firstRouter = WindowPresentationRouter()
        let secondRouter = WindowPresentationRouter()
        firstRouter.present(.createCheckpoint)
        #expect(secondRouter.sheet == nil)

        let key = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        let firstStore = DocumentSessionStore()
        let secondStore = DocumentSessionStore()
        let first = firstStore.session(for: key)
        let retained = firstStore.session(for: key)
        let second = secondStore.session(for: key)

        #expect(first === retained)
        #expect(first !== second)
        first.editingSource = "window one"
        #expect(second.editingSource.isEmpty)
    }

    @Test("Document identity is stable across path and title changes")
    func documentSessionIdentity() {
        let store = DocumentSessionStore()
        let key = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        let original = store.session(for: key)
        original.presentationMode = .source
        original.editingSource = "exact markdown bytes\n"

        let afterProjectionChange = store.session(for: key)
        #expect(afterProjectionChange === original)
        #expect(afterProjectionChange.presentationMode == .source)
        #expect(afterProjectionChange.editingSource == "exact markdown bytes\n")

        let conflict = DocumentConflictSnapshot(
            relativePath: "Renamed/Note.md",
            editorSource: "local",
            diskSource: "external",
            baseRevision: DocumentFingerprint(content: "base")
        )
        original.conflict = conflict
        original.editError = "This Note Changed on Disk"
        #expect(store.session(for: key).conflict == conflict)
        #expect(store.session(for: key).editError == "This Note Changed on Disk")
    }

    @Test("Document sessions retain scheduled work across view reconstruction")
    func documentSessionRetainsScheduledWork() async {
        let store = DocumentSessionStore()
        let key = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        let session = store.session(for: key)

        await confirmation("retained autosave completed") { completed in
            session.autosaveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled else { return }
                completed()
            }

            let reconstructed = store.session(for: key)
            #expect(reconstructed === session)
            await session.autosaveTask?.value
        }
    }

    @Test("Search rejects stale completion")
    func searchStaleResultRejection() {
        let controller = DiscoveryController()
        let first = SearchWorkspaceState(query: "first", scope: .triptych)
        let second = SearchWorkspaceState(query: "second", scope: .thisNote)
        let firstRequest = controller.beginSearch(first)
        let secondRequest = controller.beginSearch(second)

        controller.failSearch("stale", for: firstRequest)
        #expect(controller.search.errorMessage == nil)
        #expect(controller.search.criteria.query == "second")

        controller.failSearch("current", for: secondRequest)
        #expect(controller.search.errorMessage == "current")
    }

    @Test("Editing a Search query removes the prior result projection immediately")
    func searchQueryChangeClearsPriorProjection() {
        let controller = DiscoveryController()
        let hit = SearchHit(
            vaultID: UUID(),
            vaultName: "Analyses",
            vaultRole: .sourceCorpus,
            relativePath: "First.md",
            stableNoteID: nil,
            title: "First",
            matchedField: .title,
            context: nil,
            sourceLine: 1,
            snippet: "First",
            highlights: [],
            score: 1,
            fingerprint: DocumentFingerprint(content: "# First\n"),
            indexGeneration: 1,
            evidentialLayer: .paperAnalysis,
            classification: .retrievalLead
        )
        let first = controller.beginSearch(SearchWorkspaceState(
            query: "first",
            scope: .triptych
        ))
        controller.receiveSearchResults(
            hits: [hit],
            relatedItems: [],
            for: first
        )
        #expect(controller.search.hits.count == 1)
        #expect(controller.search.criteria.selectedResultID != nil)

        controller.updateSearchQuery("second")

        #expect(controller.search.criteria.query == "second")
        #expect(controller.search.criteria.selectedResultID == nil)
        #expect(controller.search.hits.isEmpty)
        #expect(controller.search.relatedItems.isEmpty)
        #expect(controller.search.isRunning)
        #expect(!controller.isCurrentSearch(first))

        let second = controller.beginSearch(controller.search.criteria)
        controller.receiveSearchResults(hits: [hit], relatedItems: [], for: second)
        controller.selectSearchScope(.thisNote)
        #expect(controller.search.criteria.scope == .thisNote)
        #expect(controller.search.hits.isEmpty)
        #expect(controller.search.relatedItems.isEmpty)
        #expect(controller.search.isRunning)
        #expect(!controller.isCurrentSearch(second))

        let scoped = controller.beginSearch(controller.search.criteria)
        controller.receiveSearchResults(hits: [hit], relatedItems: [], for: scoped)
        controller.replaceSearchCriteria(SearchWorkspaceState(
            query: "saved",
            scope: .currentVault
        ))
        #expect(controller.search.criteria.query == "saved")
        #expect(controller.search.criteria.scope == .currentVault)
        #expect(controller.search.hits.isEmpty)
        #expect(controller.search.isRunning)
        #expect(!controller.isCurrentSearch(scoped))
    }

    @Test("Research context enforces one trailing context owner")
    func researchContextExclusivity() {
        let controller = ResearchController()
        controller.showResearchInspector(true)
        #expect(controller.inspector.showsResearchInspector)
        #expect(!controller.inspector.showsNoteHistory)

        controller.showNoteHistory(true)
        #expect(controller.inspector.showsNoteHistory)
        #expect(!controller.inspector.showsResearchInspector)
    }

    @Test("Research Function presentation is target-locked and resettable")
    func researchFunctionStateTransitions() {
        let controller = ResearchController()
        let vaultID = UUID()
        let target = ResearchFunctionTarget(
            noteID: UUID(),
            note: VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: "Topics/Agency.md"
            ),
            role: .topic,
            fingerprint: DocumentFingerprint(content: "# Agency\n"),
            title: "Agency"
        )
        let firstPresentation = UUID()
        controller.functions.begin(
            target: target,
            function: .dialogue,
            selection: nil,
            presentationID: firstPresentation
        )
        #expect(controller.functions.activeFunction == .dialogue)
        #expect(controller.functions.target == target)
        #expect(controller.functions.presentationID == firstPresentation)

        let secondPresentation = UUID()
        controller.functions.begin(
            target: target,
            function: .develop,
            selection: nil,
            presentationID: secondPresentation
        )
        #expect(controller.functions.activeFunction == .develop)
        #expect(controller.functions.presentationID == secondPresentation)

        controller.functions.dismiss(presentationID: firstPresentation)
        #expect(controller.functions.presentationID == secondPresentation)

        controller.functions.dismiss(presentationID: secondPresentation)
        #expect(controller.functions.presentationID == nil)
        #expect(controller.functions.target == nil)
    }

    @Test("Command-F restores the previous ordinary scope and rejects late results")
    func temporaryFindScopeRestoration() {
        let controller = DiscoveryController()
        controller.replaceSearchCriteria(SearchWorkspaceState(scope: .currentVault))
        controller.presentSearch(.findInNote(previousScope: .currentVault))
        #expect(controller.search.criteria.scope == .thisNote)
        controller.updateSearchQuery("agency")
        let request = controller.beginSearch(controller.search.criteria)

        controller.dismissSearch()
        controller.failSearch("late", for: request)

        #expect(controller.search.criteria.query.isEmpty)
        #expect(controller.search.criteria.scope == .currentVault)
        #expect(controller.search.ordinaryScope == .currentVault)
        #expect(controller.search.errorMessage == nil)
    }

    @Test("Changing scope during Command-F makes that scope ordinary")
    func temporaryFindExplicitScopeChange() {
        let controller = DiscoveryController()
        controller.presentSearch(.findInNote(previousScope: .currentVault))
        controller.selectSearchScope(.triptych)
        controller.dismissSearch()

        #expect(controller.search.criteria.scope == .triptych)
        #expect(controller.search.ordinaryScope == .triptych)
        #expect(controller.search.invocation == .general)
    }

    @Test("Native tab coordinator groups complete Scholium windows")
    func nativeTabGrouping() {
        let coordinator = NativeWindowTabCoordinator()
        let anchorID = UUID()
        let childID = UUID()
        let anchor = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let child = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        coordinator.register(anchor, id: anchorID, anchorWindowID: nil)
        coordinator.register(child, id: childID, anchorWindowID: anchorID)

        #expect(anchor.tabbingMode == .automatic)
        #expect(child.tabbingMode == .automatic)
        #expect(anchor.tabbingIdentifier == NativeWindowTabCoordinator.tabbingIdentifier)
        #expect(child.tabbingIdentifier == NativeWindowTabCoordinator.tabbingIdentifier)
        #expect(anchor.tabGroup?.windows.contains(where: { $0 === child }) == true)

        coordinator.unregister(id: childID, window: child)
        coordinator.unregister(id: anchorID, window: anchor)
    }

    @Test("Duplicate native-tab titles gain Triptych and path context")
    func nativeTabTitleDisambiguation() {
        let coordinator = NativeWindowTabCoordinator()
        let anchorID = UUID()
        let childID = UUID()
        let anchor = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let child = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        coordinator.register(anchor, id: anchorID, anchorWindowID: nil)
        coordinator.register(child, id: childID, anchorWindowID: anchorID)

        let anchorToolTip = "Agency — Ethics — Topics/Agency.md"
        let childToolTip = "Agency — Mind — Analyses/Agency.md"
        coordinator.updateIdentity(NativeWindowTabIdentity(
            baseTitle: "Agency",
            triptychName: "Ethics",
            relativePath: "Topics/Agency.md",
            toolTip: anchorToolTip,
            isDocumentEdited: false
        ), for: anchorID)
        coordinator.updateIdentity(NativeWindowTabIdentity(
            baseTitle: "Agency",
            triptychName: "Mind",
            relativePath: "Analyses/Agency.md",
            toolTip: childToolTip,
            isDocumentEdited: true
        ), for: childID)

        #expect(anchor.tab.title == "Agency — Ethics")
        #expect(child.tab.title == "Agency — Mind")
        #expect(anchor.tab.toolTip == anchorToolTip)
        #expect(child.tab.toolTip == childToolTip)
        #expect(child.isDocumentEdited)

        coordinator.updateIdentity(NativeWindowTabIdentity(
            baseTitle: "Agency",
            triptychName: "Ethics",
            relativePath: "Works/Agency.md",
            toolTip: "Agency — Ethics — Works/Agency.md",
            isDocumentEdited: true
        ), for: childID)
        #expect(anchor.tab.title == "Agency — Ethics — Topics/Agency.md")
        #expect(child.tab.title == "Agency — Ethics — Works/Agency.md")

        coordinator.updateIdentity(NativeWindowTabIdentity(
            baseTitle: "Reasons",
            triptychName: "Ethics",
            relativePath: "Works/Reasons.md",
            toolTip: "Reasons — Ethics — Works/Reasons.md",
            isDocumentEdited: false
        ), for: childID)
        #expect(anchor.tab.title == "Agency")
        #expect(child.tab.title == "Reasons")

        coordinator.unregister(id: childID, window: child)
        coordinator.unregister(id: anchorID, window: anchor)
    }

    @Test("Native and WebKit color roles use one semantic vocabulary")
    func semanticColorParity() throws {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repository = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let cssURL = repository.appendingPathComponent("Scholium/Resources/Editor/editor.css")
        let css = try String(contentsOf: cssURL, encoding: .utf8)

        let nativeNames = Set(ScholiumColorRole.allCases.map(\.cssVariableName))
        let expression = try NSRegularExpression(pattern: #"--scholium-color-[a-z-]+"#)
        let range = NSRange(css.startIndex..<css.endIndex, in: css)
        let cssNames = Set(expression.matches(in: css, range: range).compactMap { match in
            Range(match.range, in: css).map { String(css[$0]) }
        })

        #expect(cssNames == nativeNames)
        #expect(Set(ScholiumWebDesignTokens.colorVariableNames) == nativeNames)

        for declarations in [
            ScholiumWebDesignTokens.rootCSSDeclarations,
            ScholiumWebDesignTokens.darkAppearanceCSSDeclarations,
            ScholiumWebDesignTokens.increasedContrastCSSDeclarations,
            ScholiumWebDesignTokens.darkIncreasedContrastCSSDeclarations,
        ] {
            for declaration in declarations.split(separator: "\n") {
                let normalized = declaration.trimmingCharacters(in: .whitespaces)
                guard normalized.hasPrefix("--scholium-color-") else { continue }
                #expect(css.contains(normalized))
            }
        }
    }

    @Test("Document and interface typography expose semantic roles")
    func semanticTypographyContract() {
        #expect(ScholiumTypography.body().pointSize == 12)
        #expect(ScholiumTypography.exactSource().pointSize == 14)
        #expect(ScholiumTypography.code().pointSize == 13)
        #expect(ScholiumTypography.diff().pointSize == 13)
        #expect(ScholiumTypography.revisionIdentity().pointSize == 11)

        let expectedHeadingSizes: [(ScholiumTypography.HeadingLevel, CGFloat)] = [
            (.h1, 18),
            (.h2, 15.6),
            (.h3, 13.8),
            (.h4, 12),
            (.h5, 12),
            (.h6, 12),
        ]
        for (level, expectedSize) in expectedHeadingSizes {
            #expect(abs(ScholiumTypography.heading(level: level).pointSize - expectedSize) < 0.001)
        }
    }

    @Test("Dormant native editor shares the document typography contract")
    func dormantNativeEditorTypographyContract() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let nativeEditor = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/NativeMarkdownEditorView.swift"
            ),
            encoding: .utf8
        )
        let productionDocument = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/NoteContentView.swift"
            ),
            encoding: .utf8
        )

        #expect(nativeEditor.contains("ScholiumTypography.body("))
        #expect(nativeEditor.contains("ScholiumTypography.heading("))
        #expect(nativeEditor.contains("ScholiumTypography.exactSource("))
        #expect(!nativeEditor.contains("readingBodySize"))
        #expect(!productionDocument.contains("NativeMarkdownEditorView("))
    }

    @Test("Custom control metrics preserve native-control ownership")
    func customControlMetricContract() {
        #expect(ScholiumMetrics.Accessibility.preferredCustomTarget == 28)
        #expect(ScholiumMetrics.Accessibility.minimumCustomTarget == 20)
        #expect(ScholiumMetrics.ContextSurface.controlHeight == 40)
        #expect(ScholiumMetrics.Navigation.panelInset == 10)
        #expect(ScholiumMetrics.Navigation.panelCornerRadius == 18)
    }

    @Test("Live Preview omits Source chrome and keeps context clearance in scrolling content")
    func livePreviewPresentationContract() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let editorSource = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/editor.ts"),
            encoding: .utf8
        )
        let editorStyles = try String(
            contentsOf: repository.appendingPathComponent("Scholium/Resources/Editor/editor.css"),
            encoding: .utf8
        )
        let noteSource = try String(
            contentsOf: repository.appendingPathComponent("Scholium/Views/Note/NoteContentView.swift"),
            encoding: .utf8
        )

        let extensionsStart = try #require(editorSource.range(of: "const editorExtensions = ["))
        let extensionSuffix = editorSource[extensionsStart.upperBound...]
        let extensionsEnd = try #require(extensionSuffix.range(of: "];"))
        let staticExtensions = editorSource[
            extensionsStart.lowerBound..<extensionsEnd.upperBound
        ]
        for sourceOnlyExtension in [
            "lineNumbers()",
            "highlightActiveLineGutter()",
            "foldGutter()",
            "highlightActiveLine()",
        ] {
            #expect(!staticExtensions.contains(sourceOnlyExtension))
            #expect(editorSource.contains(sourceOnlyExtension))
        }
        #expect(editorSource.contains("const sourceMode = ["))
        #expect(editorSource.contains(
            "modeCompartment.reconfigure(mode === \"livePreview\" ? livePreviewMode : sourceMode)"
        ))

        #expect(editorStyles.contains(".scholium-live-mode .cm-lineNumbers"))
        #expect(editorStyles.contains(".scholium-source-mode .cm-activeLine"))
        #expect(editorStyles.contains(".scholium-live-mode .cm-activeLine"))
        #expect(editorStyles.contains("padding-inline: var(--scholium-rhythm-inline-regular)"))
        #expect(editorStyles.contains(
            "padding-block: var(--scholium-rhythm-heading-before) var(--scholium-rhythm-heading-after)"
        ))

        #expect(ScholiumMetrics.ContextSurface.initialOverlayClearance == 92)
        #expect(noteSource.contains(".scholium-live-mode .cm-content,"))
        #expect(noteSource.contains(".scholium-source-mode .cm-content"))
        #expect(noteSource.contains(
            #"padding-top: \(ScholiumMetrics.ContextSurface.initialOverlayClearance)px;"#
        ))
    }

    @Test("Production native surfaces consume semantic color roles")
    func productionNativeSurfaceTokenAdoption() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let expectedAdoption: [String: [String]] = [
            "Scholium/Views/ContentView.swift": [
                "scholiumMaterialSurface(",
                ".navigation",
                "ScholiumColorRole.documentBackground",
            ],
            "Scholium/Views/ResearchFunctions/ResearchStripView.swift": [
                "scholiumGlassSurface(.floatingControl",
                "ScholiumColorRole.accent",
            ],
            "Scholium/Views/ResearchFunctions/ResearchFunctionPanelView.swift": [
                "scholiumSurface(.denseEvidence)",
                "ScholiumColorRole.documentBackground",
                "scholiumForeground(.attention)",
            ],
            "Scholium/Views/QualityReviewView.swift": [
                "scholiumSurface(.denseEvidence)",
                "ScholiumColorRole.destructive",
            ],
            "Scholium/Views/Sidebar/SidebarView.swift": [
                "scholiumMaterialSurface(",
                ".boundedPanel",
                "ScholiumColorRole.confirmed",
            ],
        ]

        for (path, tokens) in expectedAdoption {
            let source = try String(
                contentsOf: repository.appendingPathComponent(path),
                encoding: .utf8
            )
            for token in tokens {
                #expect(source.contains(token), "\(path) must consume \(token)")
            }
        }
    }

    @Test("Transient status motion is accessibility-owned by the view")
    func transientStatusMotionToken() throws {
        #expect(ScholiumMotion.transientStatus(reduceMotion: true) == nil)
        #expect(ScholiumMotion.transientStatus(reduceMotion: false) != nil)

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: repository.appendingPathComponent("Scholium/App/ScholiumApp.swift"),
            encoding: .utf8
        )
        let showToastSource = try #require(
            appSource.range(of: "func showToast(_ message:")
        )
        let suffix = appSource[showToastSource.lowerBound...]
        let end = suffix.range(of: "private func refreshDocumentRevisions")
        let body = end.map { String(suffix[..<$0.lowerBound]) } ?? String(suffix.prefix(1_000))
        #expect(!body.contains("withAnimation"))
    }

    @Test("Light and dark appearances use the reviewed Scholium palettes")
    func reviewedAppearancePalettes() throws {
        #expect(ScholiumInlineStatusKind.information.colorRole == .information)

        let expectedLight: [ScholiumLightPalette: UInt32] = [
            .primary: 0xA94C22,
            .primaryHover: 0x7A2917,
            .notificationHighlight: 0xB47617,
            .neutral: 0x706B65,
            .background: 0xFFFCF5,
            .navigation: 0xEFE9DF,
            .surface: 0xF7F1E7,
            .surfaceRaised: 0xDED3C5,
            .textPrimary: 0x17191C,
            .textSecondary: 0x514D48,
            .border: 0xC8BCAE,
            .confirmed: 0x2C7048,
            .attention: 0x976015,
            .destructive: 0xA13235,
            .information: 0x315F88,
            .agentAuthorship: 0x5D568F,
            .connectionSupport: 0x276F68,
            .connectionIncompatible: 0x6F4D83,
        ]
        #expect(Set(expectedLight.keys) == Set(ScholiumLightPalette.allCases))
        for (role, value) in expectedLight {
            #expect(role.rawValue == value)
        }

        let expectedDark: [ScholiumDarkPalette: UInt32] = [
            .primary: 0xEF8D5B,
            .primaryHover: 0xF5AA7B,
            .notificationHighlight: 0xE1B64F,
            .neutral: 0xB6A38F,
            .background: 0x302A26,
            .navigation: 0x3A2B2B,
            .surface: 0x3A322D,
            .surfaceRaised: 0x423831,
            .textPrimary: 0xF4E8D5,
            .textSecondary: 0xD4C2AD,
            .border: 0x807064,
            .confirmed: 0x7FC39A,
            .attention: 0xE0AB61,
            .destructive: 0xEA817C,
            .information: 0x84B0D4,
            .agentAuthorship: 0xB5A6DC,
            .connectionSupport: 0x79B9AB,
            .connectionIncompatible: 0xC29CCF,
        ]
        #expect(Set(expectedDark.keys) == Set(ScholiumDarkPalette.allCases))
        for (role, value) in expectedDark {
            #expect(role.rawValue == value)
        }

        let expectedLightCSS = [
            "--scholium-color-document-background: #fffcf5",
            "--scholium-color-navigation-background: #efe9df",
            "--scholium-color-surface-background: #f7f1e7",
            "--scholium-color-raised-surface-background: #ded3c5",
            "--scholium-color-primary-text: #17191c",
            "--scholium-color-secondary-text: #514d48",
            "--scholium-color-muted-text: #706b65",
            "--scholium-color-separator: #c8bcae",
            "--scholium-color-accent: #a94c22",
            "--scholium-color-accent-hover: #7a2917",
            "--scholium-color-notification-highlight: #b47617",
            "--scholium-color-information: #315f88",
            "--scholium-color-attention: #976015",
            "--scholium-color-destructive: #a13235",
            "--scholium-color-confirmed: #2c7048",
            "--scholium-color-agent-authorship: #5d568f",
            "--scholium-color-connection-support: #276f68",
            "--scholium-color-connection-incompatible: #6f4d83",
        ]
        for declaration in expectedLightCSS {
            #expect(ScholiumWebDesignTokens.rootCSSDeclarations.contains(declaration))
        }

        let expectedDarkCSS = [
            "--scholium-color-document-background: #302a26",
            "--scholium-color-navigation-background: #3a2b2b",
            "--scholium-color-surface-background: #3a322d",
            "--scholium-color-raised-surface-background: #423831",
            "--scholium-color-primary-text: #f4e8d5",
            "--scholium-color-secondary-text: #d4c2ad",
            "--scholium-color-muted-text: #b6a38f",
            "--scholium-color-separator: #807064",
            "--scholium-color-accent: #ef8d5b",
            "--scholium-color-accent-hover: #f5aa7b",
            "--scholium-color-notification-highlight: #e1b64f",
            "--scholium-color-information: #84b0d4",
            "--scholium-color-attention: #e0ab61",
            "--scholium-color-destructive: #ea817c",
            "--scholium-color-confirmed: #7fc39a",
            "--scholium-color-agent-authorship: #b5a6dc",
            "--scholium-color-connection-support: #79b9ab",
            "--scholium-color-connection-incompatible: #c29ccf",
        ]
        for declaration in expectedDarkCSS {
            #expect(ScholiumWebDesignTokens.darkAppearanceCSSDeclarations.contains(declaration))
        }

        let aqua = try #require(NSAppearance(named: .aqua))
        let darkAqua = try #require(NSAppearance(named: .darkAqua))
        let expectedNativeLightRoles: [ScholiumColorRole: UInt32] = [
            .documentBackground: 0xFFFCF5,
            .navigationBackground: 0xEFE9DF,
            .surfaceBackground: 0xF7F1E7,
            .raisedSurfaceBackground: 0xDED3C5,
            .primaryText: 0x17191C,
            .secondaryText: 0x514D48,
            .mutedText: 0x706B65,
            .separator: 0xC8BCAE,
            .accent: 0xA94C22,
            .accentHover: 0x7A2917,
            .notificationHighlight: 0xB47617,
            .information: 0x315F88,
            .attention: 0x976015,
            .attentionForeground: 0x976015,
            .destructive: 0xA13235,
            .destructiveForeground: 0xA13235,
            .confirmed: 0x2C7048,
            .confirmedForeground: 0x2C7048,
            .agentAuthorship: 0x5D568F,
            .connectionNeutral: 0xA94C22,
            .connectionSupport: 0x276F68,
            .connectionIncompatible: 0x6F4D83,
        ]
        for (role, expectedValue) in expectedNativeLightRoles {
            #expect(rgbValue(
                of: role.nsColor(increasedContrast: false),
                appearance: aqua
            ) == expectedValue)
        }

        let expectedNativeDarkRoles: [ScholiumColorRole: UInt32] = [
            .documentBackground: 0x302A26,
            .navigationBackground: 0x3A2B2B,
            .surfaceBackground: 0x3A322D,
            .raisedSurfaceBackground: 0x423831,
            .primaryText: 0xF4E8D5,
            .secondaryText: 0xD4C2AD,
            .mutedText: 0xB6A38F,
            .separator: 0x807064,
            .accent: 0xEF8D5B,
            .accentHover: 0xF5AA7B,
            .notificationHighlight: 0xE1B64F,
            .information: 0x84B0D4,
            .attention: 0xE0AB61,
            .attentionForeground: 0xE0AB61,
            .destructive: 0xEA817C,
            .destructiveForeground: 0xEA817C,
            .confirmed: 0x7FC39A,
            .confirmedForeground: 0x7FC39A,
            .agentAuthorship: 0xB5A6DC,
            .connectionNeutral: 0xEF8D5B,
            .connectionSupport: 0x79B9AB,
            .connectionIncompatible: 0xC29CCF,
        ]
        for (role, expectedValue) in expectedNativeDarkRoles {
            #expect(rgbValue(
                of: role.nsColor(increasedContrast: false),
                appearance: darkAqua
            ) == expectedValue)
        }

        for foreground in [
            0x17191C,
            0x514D48,
            0x706B65,
            0xA94C22,
            0x315F88,
            0x976015,
            0xA13235,
            0x2C7048,
            0x5D568F,
            0x276F68,
            0x6F4D83,
        ] as [UInt32] {
            #expect(contrastRatio(foreground, 0xF7F1E7) >= 4.5)
        }

        for foreground in [
            0xF4E8D5,
            0xD4C2AD,
            0xB6A38F,
            0xEF8D5B,
            0x84B0D4,
            0xE0AB61,
            0xEA817C,
            0x7FC39A,
            0xB5A6DC,
            0x79B9AB,
            0xC29CCF,
        ] as [UInt32] {
            #expect(contrastRatio(foreground, 0x3A322D) >= 4.5)
        }
    }

    @Test("Reduce Motion removes app-defined transitions")
    func reducedMotionRemovesTransitions() {
        #expect(ScholiumMotion.documentReveal(reduceMotion: true) == nil)
        #expect(ScholiumMotion.searchPresentation(reduceMotion: true) == nil)
        #expect(ScholiumMotion.searchExpansion(reduceMotion: true) == nil)
        #expect(ScholiumMotion.disclosure(reduceMotion: true) == nil)

        #expect(ScholiumMotion.documentReveal(reduceMotion: false) != nil)
        #expect(ScholiumMotion.searchPresentation(reduceMotion: false) != nil)
        #expect(ScholiumMotion.searchExpansion(reduceMotion: false) != nil)
        #expect(ScholiumMotion.disclosure(reduceMotion: false) != nil)
    }

    @Test("Semantic surfaces, depth, and boundaries adapt without numbered scales")
    func semanticSurfaceRecipeContract() {
        #expect(Set(ScholiumSurfaceRole.allCases) == Set([
            .document, .navigation, .floatingControl,
            .boundedPanel, .searchOverlay, .denseEvidence,
        ]))
        #expect(ScholiumSurfaceRole.document.isOpaque)
        #expect(ScholiumSurfaceRole.denseEvidence.isOpaque)
        #expect(ScholiumSurfaceRole.navigation.usesMaterial)
        #expect(ScholiumSurfaceRole.boundedPanel.usesMaterial)
        #expect(ScholiumSurfaceRole.floatingControl.usesLiquidGlass)
        #expect(ScholiumSurfaceRole.searchOverlay.usesLiquidGlass)

        let triptych = ScholiumElevationRole.triptychEdge.style(
            reduceTransparency: false,
            appearsActive: true
        )
        #expect(triptych == .init(opacity: 0.14, radius: 10, x: 5, y: 0))
        #expect(ScholiumElevationRole.floatingControl.style(
            reduceTransparency: false,
            appearsActive: true
        ) == .init(opacity: 0.10, radius: 10, x: 0, y: 4))
        #expect(ScholiumElevationRole.boundedPanel.style(
            reduceTransparency: false,
            appearsActive: true
        ) == .init(opacity: 0.08, radius: 12, x: 0, y: 4))
        #expect(ScholiumElevationRole.searchOverlay.style(
            reduceTransparency: false,
            appearsActive: true
        ) == .init(opacity: 0.20, radius: 22, x: 0, y: 12))
        #expect(ScholiumElevationRole.searchOverlay.style(
            reduceTransparency: true,
            appearsActive: false
        ).opacity == 0.06)

        #expect(ScholiumBoundaryRole.floatingBoundary.style(
            increasedContrast: false,
            reduceTransparency: false
        ).lineWidth == 0)
        #expect(ScholiumBoundaryRole.floatingBoundary.style(
            increasedContrast: true,
            reduceTransparency: false
        ).lineWidth == 1)
        #expect(ScholiumBoundaryRole.structuralDivider.style(
            increasedContrast: false,
            reduceTransparency: true
        ).opacity == 0.78)
    }

    @Test("Document rhythm remains renderer-aware and CSS-aligned")
    func provisionalDocumentRhythmContract() throws {
        #expect(ScholiumDocumentRhythm.lineHeight(for: .read) == 1.58)
        #expect(ScholiumDocumentRhythm.lineHeight(for: .livePreview) == 1.58)
        #expect(ScholiumDocumentRhythm.lineHeight(for: .source) == 1.5)
        #expect(ScholiumDocumentRhythm.contentInsets(
            for: .read,
            widthClass: .regular
        ) == .init(inline: 54, blockStart: 44, trailingViewportFraction: 0.45))
        #expect(ScholiumDocumentRhythm.contentInsets(
            for: .source,
            widthClass: .regular
        ) == .init(inline: 42, blockStart: 92, trailingViewportFraction: 0.45))
        #expect(ScholiumDocumentRhythm.contentInsets(
            for: .livePreview,
            widthClass: .narrow
        ) == .init(inline: 24, blockStart: 92, trailingViewportFraction: 0.45))

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let css = try String(
            contentsOf: repository.appendingPathComponent("Scholium/Resources/Editor/editor.css"),
            encoding: .utf8
        )
        for declaration in ScholiumWebDesignTokens.rhythmCSSDeclarations.split(separator: "\n") {
            let normalized = declaration.trimmingCharacters(in: .whitespaces)
            #expect(css.contains(normalized.replacingOccurrences(of: ".0", with: "")))
        }
    }

    @Test("Relationship colors provide increased-contrast variants")
    func increasedContrastRelationshipColors() throws {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repository = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let cssURL = repository.appendingPathComponent("Scholium/Resources/Editor/editor.css")
        let css = try String(contentsOf: cssURL, encoding: .utf8)
        let aqua = try #require(NSAppearance(named: .aqua))
        let darkAqua = try #require(NSAppearance(named: .darkAqua))

        #expect(ScholiumColorRole.connectionSupport.resolvedCustomRGBValue(
            for: aqua,
            increasedContrast: false
        ) == 0x276F68)
        #expect(ScholiumColorRole.connectionSupport.resolvedCustomRGBValue(
            for: darkAqua,
            increasedContrast: false
        ) == 0x79B9AB)
        #expect(ScholiumColorRole.connectionSupport.resolvedCustomRGBValue(
            for: aqua,
            increasedContrast: true
        ) == 0x195A54)
        #expect(ScholiumColorRole.connectionSupport.resolvedCustomRGBValue(
            for: darkAqua,
            increasedContrast: true
        ) == 0x9CD5CA)

        #expect(ScholiumColorRole.connectionIncompatible.resolvedCustomRGBValue(
            for: aqua,
            increasedContrast: false
        ) == 0x6F4D83)
        #expect(ScholiumColorRole.connectionIncompatible.resolvedCustomRGBValue(
            for: darkAqua,
            increasedContrast: false
        ) == 0xC29CCF)
        #expect(ScholiumColorRole.connectionIncompatible.resolvedCustomRGBValue(
            for: aqua,
            increasedContrast: true
        ) == 0x50365F)
        #expect(ScholiumColorRole.connectionIncompatible.resolvedCustomRGBValue(
            for: darkAqua,
            increasedContrast: true
        ) == 0xDDBCE5)

        #expect(ScholiumWebDesignTokens.increasedContrastCSSDeclarations.contains("#195a54"))
        #expect(ScholiumWebDesignTokens.increasedContrastCSSDeclarations.contains("#50365f"))
        #expect(ScholiumWebDesignTokens.darkIncreasedContrastCSSDeclarations.contains("#9cd5ca"))
        #expect(ScholiumWebDesignTokens.darkIncreasedContrastCSSDeclarations.contains("#ddbce5"))
        for value in ["#195a54", "#50365f", "#9cd5ca", "#ddbce5"] {
            #expect(css.contains(value))
        }
    }

    @Test("Connection inspectors share one semantic presentation")
    func sharedConnectionPresentation() throws {
        let expected: [
            (ScholiumConnectionPresentation, String, String, ScholiumColorRole)
        ] = [
            (.supports, "Supports", "arrow.right.circle", .connectionSupport),
            (.supportedBy, "Supported By", "arrow.left.circle", .connectionSupport),
            (.incompatible, "Incompatible With", "xmark.circle", .connectionIncompatible),
            (.neutral, "Related", "link.circle", .connectionNeutral),
        ]
        for (presentation, title, symbolName, colorRole) in expected {
            #expect(presentation.title == title)
            #expect(presentation.symbolName == symbolName)
            #expect(presentation.colorRole == colorRole)
        }

        #expect(ScholiumConnectionPresentation(
            vectorKind: .supportsTarget,
            currentIsSource: true
        ) == .supports)
        #expect(ScholiumConnectionPresentation(
            vectorKind: .supportsTarget,
            currentIsSource: false
        ) == .supportedBy)
        #expect(ScholiumConnectionPresentation(
            vectorKind: .supportedByTarget,
            currentIsSource: true
        ) == .supportedBy)
        #expect(ScholiumConnectionPresentation(
            vectorKind: .supportedByTarget,
            currentIsSource: false
        ) == .supports)
        #expect(ScholiumConnectionPresentation(
            vectorKind: .incompatible,
            currentIsSource: true
        ) == .incompatible)
        #expect(ScholiumConnectionPresentation(
            vectorKind: nil,
            currentIsSource: true
        ) == .neutral)

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for relativePath in [
            "Scholium/Views/Backlinks/BacklinksPanelView.swift",
            "Scholium/Views/Sidebar/RelationshipView.swift",
        ] {
            let source = try String(
                contentsOf: repository.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            #expect(source.contains("ScholiumConnectionPresentation"))
            #expect(!source.contains("VectorRelationshipSection"))
            #expect(!source.contains("WorkspaceConnectionKind"))
        }
    }

    private func rgbValue(of color: NSColor, appearance: NSAppearance) -> UInt32? {
        var result: UInt32?
        appearance.performAsCurrentDrawingAppearance {
            guard let rgb = color.usingColorSpace(.sRGB) else { return }
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            result = (UInt32((red * 255).rounded()) << 16)
                | (UInt32((green * 255).rounded()) << 8)
                | UInt32((blue * 255).rounded())
        }
        return result
    }

    private func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private func relativeLuminance(_ value: UInt32) -> Double {
        let red = linearized(Double((value >> 16) & 0xFF) / 255)
        let green = linearized(Double((value >> 8) & 0xFF) / 255)
        let blue = linearized(Double(value & 0xFF) / 255)
        return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }

    private func linearized(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}
