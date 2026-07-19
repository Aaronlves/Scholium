import ScholiumContracts
import AppKit
import Foundation
import SwiftUI
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

    @Test("Bootstrap is a separate scene without the workspace shell")
    func bootstrapSceneBoundary() throws {
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
        let routerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/Window/WindowPresentationRouter.swift"
            ),
            encoding: .utf8
        )

        #expect(appSource.contains("WindowGroup(id: \"scholium-bootstrap\""))
        #expect(appSource.contains("private struct ScholiumBootstrapRoot"))
        #expect(appSource.contains("@StateObject private var model: ScholiumBootstrapModel"))
        #expect(appSource.contains("dismissWindow()"))
        #expect(!appSource.contains("ScholiumBootstrapRoot(appState:"))
        #expect(!contentSource.contains("WorkspaceSetupView"))
        #expect(!routerSource.contains("workspaceSetup"))
        #expect(!routerSource.contains("adaptiveContext"))
        #expect(!contentSource.contains("ScholiumInactiveLibrarySurface()"))
        #expect(!contentSource.contains("ScholiumInactiveApparatusSurface()"))
    }

    @Test("The native split owns Inspector visibility while protecting Document reachability")
    func compactLibraryReachability() throws {
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
        let splitSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWorkspaceSplitView.swift"
            ),
            encoding: .utf8
        )
        let toolbarSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWorkspaceToolbar.swift"
            ),
            encoding: .utf8
        )
        let registrySource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWorkspaceSplitRegistry.swift"
            ),
            encoding: .utf8
        )
        #expect(contentSource.contains("ScholiumWorkspaceSplitView("))
        #expect(!contentSource.contains("NavigationSplitView("))
        #expect(!contentSource.contains("HSplitView {"))
        #expect(!contentSource.contains("ScholiumLibraryVisibilityPolicy"))
        #expect(!contentSource.contains("applyInitialDocumentCompositionIfNeeded"))
        #expect(!contentSource.contains("updateLibraryVisibilityForDocumentChange"))
        #expect(splitSource.contains("NSSplitViewController"))
        #expect(splitSource.contains(
            "libraryItem = NSSplitViewItem(sidebarWithViewController: libraryHost)"
        ))
        #expect(splitSource.contains(
            "inspectorWithViewController: apparatusHost"
        ))
        #expect(!splitSource.contains("preferredThicknessFraction"))
        #expect(!splitSource.contains("libraryOpeningSize"))
        #expect(!splitSource.contains("libraryHost.sizingOptions = []"))
        #expect(!splitSource.contains("preferredContentSize"))
        #expect(!splitSource.contains("ScholiumWorkspaceSplitHoldingPriority"))
        #expect(!splitSource.contains("libraryItem.minimumThickness"))
        #expect(!splitSource.contains("libraryItem.maximumThickness"))
        #expect(!splitSource.contains("libraryItem.automaticMaximumThickness"))
        #expect(!splitSource.contains("documentItem.minimumThickness"))
        #expect(!appSource.contains("window.contentMinSize"))
        #expect(!splitSource.contains("ScholiumResearchInspectorSplitItemConfiguration"))
        #expect(!splitSource.contains("apparatusItem.minimumThickness"))
        #expect(!splitSource.contains("apparatusItem.maximumThickness"))
        #expect(!splitSource.contains("apparatusItem.automaticMaximumThickness"))
        #expect(!splitSource.contains("apparatusItem.preferredThicknessFraction"))
        #expect(!splitSource.contains("apparatusItem.holdingPriority"))
        #expect(!splitSource.contains("apparatusItem.collapseBehavior"))
        #expect(splitSource.contains("toggleInspector(nil)"))
        #expect(!splitSource.contains("effectiveRect proposedEffectiveRect"))
        #expect(!splitSource.contains("dividerHitExpansion"))
        #expect(!splitSource.contains("ScholiumInteractiveSplitView"))
        #expect(!splitSource.contains("func sizeThatFits("))
        #expect(!splitSource.contains("availableSize"))
        #expect(!splitSource.contains("libraryHost.sizingOptions = []"))
        #expect(!splitSource.contains("apparatusHost.sizingOptions = []"))
        #expect(splitSource.contains("placeholderHost.sizingOptions = []"))
        #expect(splitSource.contains("host.sizingOptions = []"))
        #expect(!splitSource.contains("sizingOptions = [.minSize]"))
        #expect(!splitSource.contains("scholium.library.preferred-width"))
        #expect(!splitSource.contains("scholium.apparatus.preferred-width"))
        #expect(!splitSource.contains("priority = .init(999)"))
        #expect(!splitSource.contains("restoreResearchInspectorWidthIfNeeded"))
        #expect(splitSource.contains("splitViewDidResizeSubviews"))
        #expect(splitSource.contains("researchInspectorVisibilityDidChange(isVisible)"))
        #expect(!splitSource.contains("rememberResearchInspectorWidth"))
        #expect(!splitSource.contains("splitView.adjustSubviews"))
        #expect(!splitSource.contains("ScholiumSurfaceHostController"))
        #expect(!splitSource.contains("workspaceWindowDidBecomeKey"))
        #expect(splitSource.contains("researchInspectorVisibilityDidChange"))
        #expect(!contentSource.contains("availableSize: geometry.size"))
        #expect(!contentSource.contains("updateWindowWidth(geometry.size.width)"))
        #expect(registrySource.contains("final class ScholiumWorkspaceSplitRegistry"))
        #expect(registrySource.contains(
            "weak var splitViewController: NSSplitViewController?"
        ))
        #expect(appSource.contains("installWorkspaceToolbarIfPossible"))
        #expect(appSource.contains("workspaceSplitRegistryDidChange"))
        #expect(!appSource.contains("findWorkspaceSplitView"))
        #expect(!appSource.contains("attemptWorkspaceToolbarInstallation"))
        #expect(appSource.contains("func windowDidResize("))
        #expect(!contentSource.contains("ToolbarItem(placement:"))
        #expect(!contentSource.contains("TriptychActionsMenu"))
        #expect(sidebarSource.contains(
            ".accessibilityIdentifier(\"scholium.triptychManagement\")"
        ))
        #expect(toolbarSource.contains("identifier: \"scholium.toggleSidebar\""))
        #expect(toolbarSource.contains("NSTrackingSeparatorToolbarItem("))
        #expect(toolbarSource.contains("dividerIndex: 0"))
        #expect(toolbarSource.contains("dividerIndex: 1"))
        #expect(toolbarSource.contains(".flexibleSpace"))
        #expect(!sidebarSource.contains(".ignoresSafeArea(.container, edges: .leading)"))
        #expect(sidebarSource.contains("private var triptychIdentity"))
        #expect(toolbarSource.contains("ScholiumInkIconControl("))
        #expect(toolbarSource.contains("item.isBordered = false"))
        #expect(toolbarSource.contains("item.style = .plain"))
        #expect(toolbarSource.contains("window.toolbarStyle = .unified"))
        #expect(!toolbarSource.contains("unifiedCompact"))
        #expect(toolbarSource.contains("ScholiumWorkspaceDocumentIdentityToolbarView"))
        #expect(toolbarSource.contains("ScholiumWorkspaceDocumentActionsToolbarView"))
        #expect(!contentSource.contains("private func documentIdentityHeader"))
        #expect(!contentSource.contains("documentIdentityHeader(for:"))
        #expect(toolbarSource.contains(".toggleInspector"))
        #expect(toolbarSource.contains("item.target = self"))
        #expect(toolbarSource.contains("item.action = #selector(toggleInspector(_:))"))
        #expect(toolbarSource.contains("if let control = item.view as? NSControl"))
        #expect(toolbarSource.contains("control.target = self"))
        #expect(toolbarSource.contains(
            "appState.setResearchInspectorVisible(!appState.backlinksVisible)"
        ))
        #expect(toolbarSource.contains("item.autovalidates = false"))
        #expect(!toolbarSource.contains("ScholiumWorkspaceInspectorToolbarView"))
        #expect(!toolbarSource.contains("static let inspector ="))
        #expect(!toolbarSource.contains("glassEffect"))
        #expect(noteSource.contains("private var inspectorTabs"))
        #expect(!noteSource.contains("Picker(\"Research Inspector\""))
        #expect(!appSource.contains("removeAutomaticSidebarToolbarItem"))
        #expect(appSource.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(appSource.contains("window.titlebarAppearsTransparent = true"))
        #expect(!appSource.contains("window.styleMask.remove(.fullSizeContentView)"))
        #expect(appSource.contains("window.styleMask.insert(.fullSizeContentView)"))
        #expect(!contentSource.contains(".toolbarBackgroundVisibility("))
        #expect(!appSource.contains("Collapse Note"))
        #expect(sidebarSource.contains(".font(ScholiumInterfaceTypography.libraryHierarchy)"))
        #expect(sidebarSource.contains("ScholiumInterfaceTypography.metadata"))
        #expect(
            ScholiumMetrics.Library.hierarchyRowHeight
                >= ScholiumMetrics.Accessibility.minimumCustomTarget
        )
        #expect(
            ScholiumMetrics.Library.contentInset
                == ScholiumMetrics.Peripheral.contentInset
        )
    }

    @Test("Research Inspector uses AppKit's unmodified semantic item")
    func researchInspectorUsesAppKitDefaults() {
        let controller = NSViewController()
        controller.view = NSView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 320,
                height: 600
            )
        )
        let item = NSSplitViewItem(inspectorWithViewController: controller)

        #expect(item.behavior == .inspector)
        #expect(item.canCollapse)
    }

    @Test("Library hierarchy, Attention, Recommended Bibliography, and filters share one contract")
    func compactLibraryComponentContract() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sidebarSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Sidebar/SidebarView.swift"
            ),
            encoding: .utf8
        )
        let typographySource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Styling/ScholiumTypography.swift"
            ),
            encoding: .utf8
        )

        #expect(typographySource.contains("static let libraryHierarchy = Font.callout"))
        #expect(typographySource.contains("static let libraryNoteTitle = libraryHierarchy"))
        #expect(typographySource.contains("static let noteTitle = Font.body"))
        #expect(typographySource.contains("static let literatureCitation"))
        #expect(sidebarSource.contains("Text(\"ATTENTION\")"))
        #expect(sidebarSource.contains("Image(systemName: \"tray.full\")"))
        #expect(sidebarSource.contains(".focusEffectDisabled()"))
        #expect(sidebarSource.contains("? ScholiumColorRole.surfaceBackground.color"))
        #expect(!sidebarSource.contains(".pickerStyle(.segmented)"))
        #expect(ScholiumMetrics.Library.navigationIconWidth == 16)
        #expect(sidebarSource.contains(
            ".padding(.horizontal, ScholiumMetrics.Library.contentInset)"
        ))
        #expect(!sidebarSource.contains("attentionHorizontalInset"))
        let brandLabel = try #require(sidebarSource.range(of: "Text(\"Scholium\")"))
        let brandTriangle = try #require(sidebarSource.range(
            of: "Text(\"⌄\")",
            range: brandLabel.upperBound ..< sidebarSource.endIndex
        ))
        #expect(brandLabel.lowerBound < brandTriangle.lowerBound)
        let sidebarBody = try #require(sidebarSource.range(of: "var body: some View"))
        let sidebarSectionsEnd = try #require(sidebarSource.range(
            of: "// MARK: - Search",
            range: sidebarBody.upperBound ..< sidebarSource.endIndex
        ))
        let sidebarSections = sidebarSource[
            sidebarBody.lowerBound ..< sidebarSectionsEnd.lowerBound
        ]
        let scope = try #require(sidebarSections.range(of: "workspaceVaultPicker"))
        let attention = try #require(sidebarSections.range(of: "attentionNavigation"))
        let library = try #require(sidebarSections.range(of: "libraryHeader"))
        #expect(scope.lowerBound < attention.lowerBound)
        #expect(attention.lowerBound < library.lowerBound)
        #expect(
            sidebarSections.components(
                separatedBy: ".padding(.top, ScholiumMetrics.Library.sectionSpacing)"
            ).count == 3
        )
        #expect(sidebarSections.contains(
            ".padding(.horizontal, ScholiumMetrics.Library.contentInset)"
        ))
        #expect(!sidebarSource.contains("filteredNotes.count"))
        #expect(
            sidebarSource.components(
                separatedBy: ".frame(height: ScholiumMetrics.Library.hierarchyRowHeight)"
            ).count >= 3
        )
        #expect(
            sidebarSource.components(
                separatedBy: "width: ScholiumMetrics.Accessibility.preferredCustomTarget"
            ).count >= 5
        )

        for section in ["Review", "Integrity", "Metadata", "Properties", "Order", "Actions"] {
            #expect(sidebarSource.contains("Section(\"\(section)\")"))
        }

        #expect(sidebarSource.contains("SidebarRecommendedBibliographySection("))
        #expect(!sidebarSource.contains("SidebarLiteratureSection("))
        #expect(sidebarSource.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
    }

    @Test("Connections and Research share one Apparatus geometry")
    func apparatusAlignmentContract() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let componentsSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumApparatusComponents.swift"
            ),
            encoding: .utf8
        )
        let researchSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Sidebar/ResearchInspectorContentView.swift"
            ),
            encoding: .utf8
        )
        let connectionsSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Backlinks/ConnectionsInspectorView.swift"
            ),
            encoding: .utf8
        )

        #expect(
            ScholiumMetrics.Apparatus.contentInset
                == ScholiumMetrics.Peripheral.contentInset
        )
        #expect(
            ScholiumMetrics.Apparatus.firstSectionSpacing
                == ScholiumMetrics.Peripheral.sectionSpacing
        )
        #expect(
            ScholiumMetrics.Apparatus.sectionSpacing
                == ScholiumMetrics.Peripheral.sectionSpacing
        )
        #expect(
            ScholiumMetrics.Apparatus.sectionContentSpacing
                == ScholiumMetrics.Peripheral.sectionContentSpacing
        )
        #expect(
            ScholiumMetrics.Apparatus.sectionContentInset
                == ScholiumMetrics.Peripheral.sectionContentInset
        )
        #expect(
            ScholiumMetrics.Apparatus.iconColumnWidth
                == ScholiumMetrics.Peripheral.iconColumnWidth
        )
        #expect(
            ScholiumMetrics.Apparatus.iconToTextSpacing
                == ScholiumMetrics.Peripheral.iconToTextSpacing
        )

        #expect(componentsSource.contains("struct ScholiumApparatusSection"))
        #expect(componentsSource.contains("struct ScholiumApparatusRow"))
        #expect(componentsSource.contains(
            "width: ScholiumMetrics.Apparatus.iconColumnWidth"
        ))
        #expect(componentsSource.contains(
            ".padding(.leading, ScholiumMetrics.Apparatus.sectionContentInset)"
        ))
        #expect(researchSource.contains(
            ".padding(.horizontal, ScholiumMetrics.Apparatus.contentInset)"
        ))
        #expect(researchSource.components(
            separatedBy: "ScholiumApparatusSection("
        ).count >= 4)
        #expect(researchSource.components(
            separatedBy: "ScholiumApparatusRow("
        ).count >= 5)
        #expect(connectionsSource.contains(
            ".padding(.horizontal, ScholiumMetrics.Apparatus.contentInset)"
        ))
        #expect(connectionsSource.contains(
            ".padding(.leading, ScholiumMetrics.Apparatus.sectionContentInset)"
        ))
        #expect(connectionsSource.contains(
            "ScholiumInterfaceTypography.apparatusResearchContent"
        ))
        #expect(researchSource.contains("ScholiumInterfaceTypography.reviewValue"))
        #expect(researchSource.contains("\"Current revision\""))
        #expect(researchSource.contains("private var propertiesSection"))
        #expect(researchSource.contains("prefix(5)"))
        #expect(researchSource.contains(".lineLimit(2)"))
        #expect(connectionsSource.contains("ScholiumApparatusRow("))
        #expect(!connectionsSource.contains("DisclosureGroup(\n            isExpanded:"))
    }

    @Test("The Library is opaque and the no-note detail is a quiet semantic surface")
    func scholarlyEditorialWorkspaceSurfaceContract() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(atPath: repository.appendingPathComponent(
            "Scholium/Resources/Artwork/ScholiumFeaturedFolioLight.png"
        ).path))
        #expect(!FileManager.default.fileExists(atPath: repository.appendingPathComponent(
            "Scholium/Resources/Artwork/ScholiumFeaturedFolioDark.png"
        ).path))

        let content = try String(
            contentsOf: repository.appendingPathComponent("Scholium/Views/ContentView.swift"),
            encoding: .utf8
        )
        let noteSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/NoteContentView.swift"
            ),
            encoding: .utf8
        )
        #expect(content.contains(".scholiumSurface(.navigation)"))
        #expect(content.contains(".ignoresSafeArea(.container, edges: .top)"))
        #expect(!content.contains("geometry.safeAreaInsets.top"))
        #expect(content.contains("ScholiumNoDocumentDetailView()"))
        #expect(content.contains(".accessibilityIdentifier(\"scholium.noDocumentSurface\")"))
        #expect(content.contains("ScholiumWorkspaceSplitView("))
        #expect(!content.contains("NavigationSplitView("))
        #expect(!content.contains("HSplitView {"))
        #expect(!content.contains("preferredApparatusWidth"))
        #expect(content.contains(".padding(.top, ScholiumMetrics.Search.responsiveMargin)"))
        #expect(!content.contains(".ignoresSafeArea()"))
        #expect(!content.contains("NavigationBackdropView"))
        #expect(!content.contains(".backgroundExtensionEffect()"))
        #expect(!content.contains(".regularMaterial"))
        #expect(!content.contains("height: geometry.size.height"))
        #expect(noteSource.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        #expect(noteSource.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)"))
        let toolbar = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWorkspaceToolbar.swift"
            ),
            encoding: .utf8
        )
        #expect(toolbar.contains("\"scholium.headingOutline\""))
        #expect(toolbar.contains("\"scholium.documentSearch\""))
        #expect(toolbar.contains("\"scholium.showResearchRecord\""))
        #expect(toolbar.contains(".toggleInspector"))
        #expect(toolbar.contains("static let researchRecord"))
        #expect(toolbar.contains(
            "item.isEnabled = appState.documentController.selectedDocument != nil"
        ))
        #expect(toolbar.contains(".disabled(!isAvailable)"))
        #expect(!noteSource.contains("\"scholium.documentMore\""))

        #expect(ScholiumMetrics.Library.contentInset == ScholiumMetrics.Peripheral.contentInset)
        #expect(ScholiumMetrics.Library.sectionSpacing == ScholiumMetrics.Peripheral.sectionSpacing)
        #expect(ScholiumMetrics.Apparatus.contentInset == ScholiumMetrics.Peripheral.contentInset)
        #expect(ScholiumMetrics.Apparatus.sectionSpacing == ScholiumMetrics.Peripheral.sectionSpacing)
        #expect(
            ScholiumMetrics.Apparatus.sectionContentSpacing
                == ScholiumMetrics.Peripheral.sectionContentSpacing
        )
        #expect(
            ScholiumMetrics.Apparatus.sectionContentInset
                == ScholiumMetrics.Peripheral.sectionContentInset
        )
        #expect(ScholiumMetrics.Apparatus.headerHeight == 48)
        #expect(ScholiumMetrics.Workspace.bottomCommandBarHeight == 52)
        #expect(
            ScholiumMetrics.Document.researchStripMaximumWidth
                == ScholiumMetrics.Document.readableMeasure + 60
        )

        let preview = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/PreviewCatalog/ScholiumComponentCatalog.swift"
            ),
            encoding: .utf8
        )
        #expect(preview.contains(".init(increasedContrast: true)"))
        #expect(preview.contains(".init(reduceTransparency: true)"))
        #expect(preview.contains(".init(reduceMotion: true)"))
        #expect(preview.contains("swiftUIReadingFont(size: 12, relativeTo: .body)"))

        let productionRoot = repository.appendingPathComponent("Scholium")
        let forbiddenSurfaceAPIs = [
            "glassEffect(",
            "GlassEffectContainer",
            ".buttonStyle(.glass",
            ".regularMaterial",
            ".ultraThinMaterial",
            "NSVisualEffectView",
            "backgroundExtensionEffect(",
            "scholiumGlassSurface(",
            "scholiumMaterialSurface(",
        ]
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: productionRoot,
                includingPropertiesForKeys: nil
            )
        )
        for case let sourceURL as URL in enumerator where sourceURL.pathExtension == "swift" {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            for forbiddenAPI in forbiddenSurfaceAPIs {
                #expect(
                    !source.contains(forbiddenAPI),
                    "\(sourceURL.lastPathComponent) must not use \(forbiddenAPI)"
                )
            }
        }
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

    @Test("Search flushes the registered editor before presenting retrieval")
    func searchPresentationCommitsTheEditorFirst() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: repository.appendingPathComponent("Scholium/App/ScholiumApp.swift"),
            encoding: .utf8
        )
        let searchBoundary = try #require(
            appSource.range(of: "func beginSearch(_ invocation: SearchInvocation)")
        )
        let dismissalBoundary = try #require(
            appSource.range(
                of: "func dismissSearch()",
                range: searchBoundary.upperBound ..< appSource.endIndex
            )
        )
        let implementation = appSource[searchBoundary.lowerBound ..< dismissalBoundary.lowerBound]
        let flush = try #require(
            implementation.range(of: "try await self.flushRegisteredEditorIfNeeded()")
        )
        let presentation = try #require(
            implementation.range(of: "self.discoveryController.presentSearch(invocation)")
        )
        #expect(flush.lowerBound < presentation.lowerBound)
    }

    @Test("Research Inspector has one trailing-context owner")
    func researchContextExclusivity() {
        let controller = ResearchController()
        #expect(!controller.inspector.showsResearchInspector)
        controller.showResearchInspector(true)
        #expect(controller.inspector.showsResearchInspector)
    }

    @Test("Recommended Bibliography remains an isolated Library feature")
    func recommendedBibliographyOwnershipAndPlacement() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let section = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Sidebar/RecommendedBibliographySection.swift"
            ),
            encoding: .utf8
        )
        let controller = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Features/ResearchContext/RecommendedBibliographyController.swift"
            ),
            encoding: .utf8
        )
        for forbidden in [
            "WindowModel", "ResearchFunctionController", "FileManager",
            "ResearchSkillStore", "import ScholiumApplication",
        ] {
            #expect(!section.contains(forbidden))
            #expect(!controller.contains(forbidden))
        }
        #expect(controller.contains("final class RecommendedBibliographyController"))
        #expect(controller.contains("It owns no repository, skill package, YAML, or filesystem authority."))
        #expect(!section.contains("Reading leads, not evidence."))
        #expect(section.contains("Update Recommendations"))
        #expect(section.contains("Open in Zotero"))
        #expect(section.contains("Dismiss"))
        #expect(section.contains("Repair in Research Guidance"))
        #expect(section.contains("Recommended Bibliography"))
        #expect(!section.contains("SidebarLiteratureSection"))

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

    @Test("Document tabs use one central AppKit container without taking toolbar ownership")
    func documentTabContainerOwnership() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let splitSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWorkspaceSplitView.swift"
            ),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )

        #expect(splitSource.contains("private let tabViewController = NSTabViewController()"))
        #expect(splitSource.contains("tabViewController.tabStyle = .unspecified"))
        #expect(splitSource.contains("tabButtonStack.distribution = .fillEqually"))
        #expect(splitSource.contains("let documentTabsController:"))
        #expect(appSource.contains("NSWindow.allowsAutomaticWindowTabbing = false"))
        #expect(!appSource.contains("NativeWindowTabCoordinator"))
        #expect(!appSource.contains("addTabbedWindow"))
    }

    @Test("Native toolbar follows the explicitly registered workspace split")
    func documentScopedNativeTabGeometry() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let splitSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWorkspaceSplitView.swift"
            ),
            encoding: .utf8
        )
        let toolbarSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWorkspaceToolbar.swift"
            ),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let registrySource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWorkspaceSplitRegistry.swift"
            ),
            encoding: .utf8
        )

        #expect(splitSource.contains(
            "NSSplitViewItem(sidebarWithViewController: libraryHost)"
        ))
        #expect(splitSource.contains(
            "inspectorWithViewController: apparatusHost"
        ))
        #expect(splitSource.contains(
            "ScholiumWorkspaceSplitRegistry.shared.register(self, in: window)"
        ))
        #expect(registrySource.contains("static let didChangeNotification"))
        #expect(appSource.contains(
            "ScholiumWorkspaceSplitRegistry.shared"
        ))
        #expect(!appSource.contains("findWorkspaceSplitView"))
        #expect(toolbarSource.components(
            separatedBy: "NSTrackingSeparatorToolbarItem("
        ).count == 3)
        #expect(toolbarSource.contains("dividerIndex: 0"))
        #expect(toolbarSource.contains("dividerIndex: 1"))
        #expect(!splitSource.contains("ScholiumSurfaceHostController"))
        #expect(toolbarSource.contains("item.isBordered = false"))
    }

    @Test("Workspace split registration is scoped to one exact window")
    func workspaceSplitRegistryLifecycle() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 760),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let splitViewController = NSSplitViewController()
        splitViewController.view.frame = window.contentView?.bounds ?? .zero

        ScholiumWorkspaceSplitRegistry.shared.register(splitViewController, in: window)
        #expect(
            ScholiumWorkspaceSplitRegistry.shared.splitViewController(for: window)
                === splitViewController
        )
        #expect(
            ScholiumWorkspaceSplitRegistry.shared.splitView(for: window)
                === splitViewController.splitView
        )

        ScholiumWorkspaceSplitRegistry.shared.unregister(splitViewController, from: window)
        #expect(ScholiumWorkspaceSplitRegistry.shared.splitView(for: window) == nil)
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
        #expect(ScholiumMetrics.Search.preferredWidth == 640)
        #expect(ScholiumMetrics.Search.cornerRadius == 12)
        #expect(ScholiumShape.editorialControlCornerRadius == 8)
        #expect(ScholiumShape.editorialPanelCornerRadius == 10)
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
            #"padding-top: \(ScholiumMetrics.Document.contentTopInset)px;"#
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
                ".scholiumSurface(.navigation)",
                "ScholiumColorRole.documentBackground",
            ],
            "Scholium/Views/ResearchFunctions/ResearchStripView.swift": [
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
                "scholiumEditorialSurface(",
                ".boundedPanel",
                "ScholiumColorRole.confirmed",
            ],
            "Scholium/Views/Note/NoteContentView.swift": [
                ".scholiumSurface(.document)",
                ".scholiumSurface(.apparatus)",
            ],
            "Scholium/Views/SearchWorkspaceView.swift": [
                "scholiumEditorialSurface(",
                ".searchOverlay",
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
            .document, .navigation, .apparatus, .floatingControl,
            .boundedPanel, .searchOverlay, .denseEvidence,
        ]))
        #expect(ScholiumSurfaceRole.navigation.colorRole == .navigationBackground)
        #expect(ScholiumSurfaceRole.document.colorRole == .documentBackground)
        #expect(ScholiumSurfaceRole.apparatus.colorRole == .surfaceBackground)
        #expect(ScholiumSurfaceRole.floatingControl.defaultBoundaryRole == .floatingBoundary)
        #expect(ScholiumSurfaceRole.searchOverlay.defaultBoundaryRole == .floatingBoundary)
        #expect(ScholiumSurfaceRole.boundedPanel.defaultBoundaryRole == .subtleBoundary)
        #expect(ScholiumSurfaceRole.floatingControl.defaultElevationRole == .floatingControl)
        #expect(ScholiumSurfaceRole.searchOverlay.defaultElevationRole == .searchOverlay)
        #expect(ScholiumSurfaceRole.boundedPanel.defaultElevationRole == .boundedPanel)
        #expect(ScholiumSurfaceRole.document.defaultElevationRole == nil)
        #expect(ScholiumSurfaceRole.navigation.defaultElevationRole == nil)
        #expect(ScholiumSurfaceRole.apparatus.defaultElevationRole == nil)
        #expect(ScholiumSurfaceRole.denseEvidence.defaultElevationRole == nil)

        var environment = EnvironmentValues()
        environment.scholiumVisualEnvironmentOverride = .init(
            increasedContrast: true,
            reduceTransparency: true,
            reduceMotion: true,
            appearsActive: false
        )
        #expect(environment.scholiumIncreasedContrast)
        #expect(environment.scholiumReduceTransparency)
        #expect(environment.scholiumReduceMotion)
        #expect(!environment.scholiumAppearsActive)

        #expect(Set(ScholiumElevationRole.allCases) == Set([
            .floatingControl, .boundedPanel, .searchOverlay,
        ]))
        #expect(ScholiumElevationRole.floatingControl.style(
            reduceTransparency: false,
            appearsActive: true
        ) == .init(opacity: 0.04, radius: 4, x: 0, y: 2))
        #expect(ScholiumElevationRole.boundedPanel.style(
            reduceTransparency: false,
            appearsActive: true
        ) == .init(opacity: 0.03, radius: 4, x: 0, y: 2))
        #expect(ScholiumElevationRole.searchOverlay.style(
            reduceTransparency: false,
            appearsActive: true
        ) == .init(opacity: 0.12, radius: 12, x: 0, y: 6))
        #expect(ScholiumElevationRole.searchOverlay.style(
            reduceTransparency: true,
            appearsActive: false
        ).opacity == 0.036)

        #expect(ScholiumBoundaryRole.floatingBoundary.style(
            increasedContrast: false,
            reduceTransparency: false
        ).lineWidth == 0.75)
        #expect(ScholiumBoundaryRole.floatingBoundary.style(
            increasedContrast: true,
            reduceTransparency: false
        ).lineWidth == 1)
        #expect(ScholiumBoundaryRole.structuralDivider.style(
            increasedContrast: false,
            reduceTransparency: false
        ).opacity == 0.42)
        #expect(ScholiumBoundaryRole.structuralDivider.style(
            increasedContrast: false,
            reduceTransparency: true
        ).opacity == 0.78)
    }

    @Test("Document rhythm remains renderer-aware and CSS-aligned")
    func provisionalDocumentRhythmContract() throws {
        // The exact rhythm is intentionally provisional until the dedicated
        // Editor pass. Keep testing the renderer contract without freezing a
        // visual trial as a permanent acceptance value.
        for renderer in ScholiumDocumentRenderer.allCases {
            for widthClass in ScholiumDocumentWidthClass.allCases {
                let insets = ScholiumDocumentRhythm.contentInsets(
                    for: renderer,
                    widthClass: widthClass
                )
                #expect(insets.inline >= 0)
                #expect(insets.blockStart >= 0)
                #expect((0 ... 1).contains(insets.trailingViewportFraction))
            }
        }

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let css = try String(
            contentsOf: repository.appendingPathComponent("Scholium/Resources/Editor/editor.css"),
            encoding: .utf8
        )
        withKnownIssue(
            "Editor CSS rhythm synchronization is deferred to the dedicated Editor pass."
        ) {
            for declaration in ScholiumWebDesignTokens.rhythmCSSDeclarations.split(separator: "\n") {
                let normalized = declaration.trimmingCharacters(in: .whitespaces)
                #expect(css.contains(normalized.replacingOccurrences(of: ".0", with: "")))
            }
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

    @Test("The live Connections inspector uses one semantic presentation")
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
        for relativePath in ["Scholium/Views/Backlinks/ConnectionsInspectorView.swift"] {
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
