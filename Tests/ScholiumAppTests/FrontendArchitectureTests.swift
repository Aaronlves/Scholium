import ScholiumContracts
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import ScholiumApp

@Suite("Frontend architecture")
@MainActor
struct FrontendArchitectureTests {
    @Test("EditorHost presentation preserves mounted Read and editor surfaces")
    func editorHostRetainsMountedSurfaces() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let hostSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/DocumentEditorHost.swift"
            ),
            encoding: .utf8
        )
        let noteSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/NoteContentView.swift"
            ),
            encoding: .utf8
        )

        #expect(hostSource.contains("if retainsEditor"))
        #expect(!hostSource.contains("if presentsEditor"))
        #expect(hostSource.contains(".allowsHitTesting(!presentsEditor)"))
        #expect(hostSource.contains("presentsEditor && (hasPresentedEditor || editorIsReady)"))
        #expect(hostSource.contains(".accessibilityHidden(!showsEditor)"))
        #expect(noteSource.contains("@ObservedObject private var documentSession: DocumentSessionModel"))
        #expect(noteSource.contains("retainsEditor: documentSession.retainsEditorSurface"))
        #expect(noteSource.contains("editorIsReady: editorSession.isLoaded"))
        #expect(noteSource.contains(
            "editorSession.presentedMode == documentSession.activeEditorMode"
        ))
        #expect(noteSource.contains("mode: documentSession.retainedEditorMode"))
        #expect(noteSource.contains("renderedReadReadyFingerprint"))
        #expect(noteSource.contains("private var readProjectionTaskIdentity: String"))
        #expect(noteSource.contains("noteFingerprint.sha256"))
        #expect(!noteSource.contains("guard presentationMode == .read else { return }"))

        let sessionSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Features/Document/DocumentSessionStore.swift"
            ),
            encoding: .utf8
        )
        #expect(sessionSource.contains(
            "@Published private(set) var presentation = DocumentPresentationState()"
        ))
        #expect(!sessionSource.contains("@Published var isEditing"))
        #expect(!sessionSource.contains("@Published var retainsEditorSurface"))
        #expect(!sessionSource.contains("@Published private(set) var presentationMode"))
        let presentationSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Features/Document/DocumentPresentationState.swift"
            ),
            encoding: .utf8
        )
        #expect(presentationSource.contains("enum MarkdownEditorMode"))
        #expect(presentationSource.contains("case review(restoration: MarkdownEditorMode?)"))
        #expect(presentationSource.contains("case editing(MarkdownEditorMode)"))

        let webViewSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/MarkdownEditorWebView.swift"
            ),
            encoding: .utf8
        )
        #expect(webViewSource.contains("var lastModeInput: MarkdownEditorMode"))
        #expect(!webViewSource.contains("var mode: MarkdownEditorMode"))
        let readyStart = try #require(webViewSource.range(of: "private func signalReady()"))
        let readySuffix = webViewSource[readyStart.lowerBound...]
        let readyEnd = try #require(readySuffix.range(of: "private func validEnvelope"))
        let readyBody = readySuffix[..<readyEnd.lowerBound]
        #expect(!readyBody.contains("loadDocument("))
    }

    @Test("EditorHost waits on initial entry but preserves an established editor during mode reconfiguration")
    func editorHostPresentationGate() {
        var gate = DocumentEditorPresentationGate()

        gate.reconcile(presentsEditor: false, editorIsReady: false)
        #expect(!gate.showsEditor(presentsEditor: false, editorIsReady: false))

        gate.reconcile(presentsEditor: true, editorIsReady: false)
        #expect(!gate.showsEditor(presentsEditor: true, editorIsReady: false))

        gate.reconcile(presentsEditor: true, editorIsReady: true)
        #expect(gate.showsEditor(presentsEditor: true, editorIsReady: true))

        // A bridge-confirmed editor remains the visible surface while the
        // retained CodeMirror state atomically changes Edit <-> Source.
        gate.reconcile(presentsEditor: true, editorIsReady: false)
        #expect(gate.showsEditor(presentsEditor: true, editorIsReady: false))

        gate.reconcile(presentsEditor: false, editorIsReady: false)
        #expect(!gate.showsEditor(presentsEditor: false, editorIsReady: false))
    }

    @Test("Autosave failure and conflict stay in the Document surface")
    func documentIntegrityStatusOwnership() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let noteSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/NoteContentView.swift"
            ),
            encoding: .utf8
        )
        let componentSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumComponents.swift"
            ),
            encoding: .utf8
        )

        #expect(noteSource.contains("DocumentIntegrityPresentation.resolve("))
        #expect(noteSource.contains("ScholiumDocumentStatusToast("))
        #expect(noteSource.contains("scholium.documentStatus.autosaveFailed"))
        #expect(noteSource.contains("scholium.documentStatus.conflict"))
        #expect(noteSource.contains("AccessibilityNotification.Announcement"))
        #expect(noteSource.contains(".frame(minWidth: 760, idealWidth: 900"))
        #expect(noteSource.contains("ScrollView(.vertical)"))
        #expect(noteSource.contains(".frame(width: max(viewport.size.width, 1)"))
        #expect(noteSource.contains("width: diffTextWidth(in: viewport.size.width)"))
        #expect(noteSource.contains(".lineLimit(nil)"))
        #expect(!noteSource.contains("ScrollView([.vertical, .horizontal])"))
        #expect(!noteSource.contains(".fixedSize(horizontal: true, vertical: false)"))
        #expect(!noteSource.contains(".alert(conflict == nil ? \"Save Failed\""))
        #expect(!noteSource.contains("Native save/conflict recovery owns focus while it is visible."))
        #expect(componentSource.contains("struct ScholiumDocumentStatusToast<Actions: View>"))
        #expect(componentSource.contains("HStack(alignment: .center, spacing: 10)"))
        #expect(componentSource.contains("HStack(alignment: .center, spacing: 8)"))
        #expect(!componentSource.contains("verticalAlignment"))
        #expect(componentSource.contains(".accessibilityLabel(title)"))
        #expect(componentSource.contains(".accessibilityValue(detail)"))
    }

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

        #expect(appSource.contains("id: \"scholium-bootstrap\""))
        #expect(appSource.contains("for: BootstrapWindowRoute.self"))
        #expect(appSource.components(separatedBy: "WindowGroup(").count == 3)
        #expect(!appSource.contains("id: \"scholium-stage4-design-proofs\""))
        #expect(!appSource.contains("id: \"scholium-editor\""))
        #expect(!appSource.contains("Window(\"Editor\""))
        #expect(appSource.contains("private struct ScholiumBootstrapRoot"))
        #expect(appSource.contains("@StateObject private var model: ScholiumBootstrapModel"))
        #expect(appSource.contains("dismissWindow()"))
        #expect(!appSource.contains("ScholiumBootstrapRoot(appState:"))
        #expect(!contentSource.contains("WorkspaceSetupView"))
        #expect(!routerSource.contains("workspaceSetup"))
        #expect(!routerSource.contains("adaptiveContext"))
        #expect(!contentSource.contains("ScholiumInactiveLibrarySurface()"))
        #expect(!contentSource.contains("ScholiumInactiveApparatusSurface()"))
        #expect(appSource.contains(
            "@FocusedObject private var focusedWindowModel: WindowModel?"
        ))
        #expect(appSource.contains(
            "ScholiumResearchRecordUtilityRoot(appState: focusedWindowModel)"
        ))
        #expect(appSource.contains(
            "WindowVisibilityToggle(windowID: \"scholium-research-record\")"
        ))
        #expect(appSource.contains(".focusedSceneObject(appState)"))
        #expect(!appSource.contains("ScholiumWindowModelFocusedKey"))
    }

    @Test("The native split protects Document reachability and Library readability")
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
        let apparatusComponentsSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/UI/Components/ScholiumApparatusComponents.swift"
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
        let windowManagementSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWindowManagement.swift"
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
            "sidebarWithViewController: libraryBackgroundController"
        ))
        #expect(!splitSource.contains("libraryItem.canCollapseFromWindowResize = false"))
        #expect(splitSource.contains(
            "inspectorWithViewController: apparatusBackgroundController"
        ))
        #expect(!splitSource.contains("preferredThicknessFraction"))
        #expect(!splitSource.contains("libraryOpeningSize"))
        #expect(!splitSource.contains("libraryHost.sizingOptions = []"))
        #expect(!splitSource.contains("preferredContentSize"))
        #expect(!splitSource.contains("ScholiumWorkspaceSplitHoldingPriority"))
        #expect(splitSource.contains(
            "libraryItem.minimumThickness = ScholiumMetrics.Library.minimumReadableWidth"
        ))
        #expect(!splitSource.contains("libraryItem.maximumThickness"))
        #expect(!splitSource.contains("libraryItem.automaticMaximumThickness"))
        #expect(!splitSource.contains("documentItem.minimumThickness"))
        #expect(!splitSource.contains("apparatusItem.minimumThickness"))
        #expect(splitSource.contains(
            "apparatusItem.maximumThickness = NSSplitViewItem.unspecifiedDimension"
        ))
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
        #expect(splitSource.contains("ScholiumFirstApparatusWidthOffer"))
        #expect(splitSource.contains("prepareForReveal(animated:"))
        #expect(splitSource.contains("revealAnimationDidFinish()"))
        #expect(splitSource.contains("firstApparatusWidthOffer.offerIfReady()"))
        #expect(splitSource.contains("ScholiumMetrics.Apparatus.firstRevealWidth"))
        #expect(!splitSource.contains("splitView.adjustSubviews"))
        #expect(!splitSource.contains("ScholiumSurfaceHostController"))
        #expect(splitSource.contains("ScholiumSurfaceContainerViewController"))
        #expect(!splitSource.contains("NSBackgroundExtensionView"))
        #expect(!splitSource.contains("installTitlebarControl"))
        #expect(!splitSource.contains("ScholiumPeripheralTitlebarControlView"))
        #expect(splitSource.contains("backgroundHost.safeAreaRegions = []"))
        #expect(!splitSource.contains("NSSplitViewItemAccessoryViewController"))
        #expect(splitSource.contains(
            "rootView: backgroundRole.colorRole.color"
        ))
        #expect(splitSource.contains(
            "equalTo: containerView.topAnchor"
        ))
        #expect(splitSource.contains(
            "equalTo: containerView.safeAreaLayoutGuide.topAnchor"
        ))
        #expect(contentSource.contains(".ignoresSafeArea(.container, edges: .top)"))
        #expect(!splitSource.contains("workspaceWindowDidBecomeKey"))
        #expect(splitSource.contains("researchInspectorVisibilityDidChange"))
        #expect(!contentSource.contains("availableSize: geometry.size"))
        #expect(!contentSource.contains("updateWindowWidth(geometry.size.width)"))
        #expect(!contentSource.contains(".frame(minWidth: 360"))
        #expect(windowManagementSource.contains("final class WorkspaceWindowCoordinator"))
        #expect(windowManagementSource.contains("weak var window: NSWindow?"))
        #expect(windowManagementSource.contains(
            "weak var splitController: (any ScholiumWorkspaceSplitControlling)?"
        ))
        #expect(windowManagementSource.contains("final class ScholiumWindowLifecycleRegistry"))
        #expect(!windowManagementSource.contains("static let shared"))
        #expect(!windowManagementSource.contains("NotificationCenter"))
        #expect(!appSource.contains("workspaceSplitRegistryDidChange"))
        #expect(!appSource.contains("findWorkspaceSplitView"))
        #expect(!appSource.contains("attemptWorkspaceToolbarInstallation"))
        #expect(appSource.contains("defaultValue: { TriptychWindowRoute() }"))
        #expect(!contentSource.contains("ToolbarItem(placement:"))
        #expect(!contentSource.contains("TriptychActionsMenu"))
        #expect(sidebarSource.contains(
            ".accessibilityIdentifier(\"scholium.triptychManagement\")"
        ))
        #expect(toolbarSource.contains("identifier: \"scholium.toggleSidebar\""))
        #expect(toolbarSource.contains("private var desiredItemIdentifiers"))
        #expect(toolbarSource.contains("static func itemIdentifiers("))
        #expect(toolbarSource.contains("Self.itemIdentifiers("))
        #expect(toolbarSource.contains("toolbar.itemIdentifiers = desired"))
        #expect(toolbarSource.contains("NSTrackingSeparatorToolbarItem("))
        #expect(toolbarSource.contains("dividerIndex: 0"))
        #expect(toolbarSource.contains("dividerIndex: 1"))
        #expect(toolbarSource.contains(".flexibleSpace"))
        #expect(!sidebarSource.contains(".ignoresSafeArea(.container, edges: .leading)"))
        #expect(sidebarSource.contains("private var brandHeader"))
        #expect(toolbarSource.contains("ScholiumInkIconControl("))
        #expect(toolbarSource.contains("item.isBordered = false"))
        #expect(toolbarSource.contains("item.style = .plain"))
        #expect(toolbarSource.contains("window.toolbarStyle = .unified"))
        #expect(!toolbarSource.contains("unifiedCompact"))
        #expect(toolbarSource.contains("ScholiumWorkspaceDocumentIdentityToolbarView"))
        #expect(toolbarSource.contains("ScholiumWorkspaceDocumentActionsToolbarView"))
        #expect(!contentSource.contains("private func documentIdentityHeader"))
        #expect(!contentSource.contains("documentIdentityHeader(for:"))
        #expect(toolbarSource.contains("static let inspector = NSToolbarItem.Identifier"))
        #expect(toolbarSource.contains("\"scholium.toolbar.inspector\""))
        #expect(toolbarSource.contains("ScholiumWorkspaceShowInspectorToolbarView"))
        #expect(toolbarSource.contains("identifier: \"scholium.toggleInspector\""))
        #expect(toolbarSource.contains(
            "windowActions.setResearchInspectorVisible(true)"
        ))
        #expect(toolbarSource.contains(
            "appState.documentController.selectedDocument == nil"
        ))
        #expect(!toolbarSource.contains("Hide Research Inspector"))
        #expect(sidebarSource.contains("Hide Sidebar"))
        #expect(noteSource.contains("Hide Research Inspector"))
        #expect(contentSource.contains("apparatusHideControl"))
        #expect(appSource.contains(
            "appState?.researchInspectorVisible != true"
        ))
        #expect(appSource.contains(
            "&& appState?.currentNote == nil"
        ))
        #expect(!toolbarSource.contains("identifiers.append(.toggleInspector)"))
        #expect(!toolbarSource.contains("case .toggleInspector"))
        #expect(!toolbarSource.contains("updateStandardInspectorItem"))
        #expect(!toolbarSource.contains("#selector(toggleInspector"))
        #expect(toolbarSource.contains(
            "let item = NSToolbarItem(itemIdentifier: identifier)"
        ))
        #expect(toolbarSource.contains(
            "host.layer?.backgroundColor = NSColor.clear.cgColor"
        ))
        #expect(toolbarSource.contains(
            "item.isBordered = false"
        ))
        #expect(toolbarSource.contains(
            "item.style = .plain"
        ))
        #expect(!toolbarSource.contains("glassEffect"))
        #expect(noteSource.contains("ScholiumInspectorModeIndex("))
        #expect(!noteSource.contains("Picker(\"Research Inspector\""))
        #expect(apparatusComponentsSource.contains("struct ScholiumInspectorModeIndex"))
        #expect(apparatusComponentsSource.contains(".focusable()"))
        #expect(apparatusComponentsSource.contains(".onMoveCommand(perform: move)"))
        #expect(!appSource.contains("removeAutomaticSidebarToolbarItem"))
        #expect(appSource.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(windowManagementSource.contains("window.titlebarAppearsTransparent = true"))
        #expect(windowManagementSource.contains("scholium.workspaceToolbar.loading"))
        #expect(windowManagementSource.contains("installLoadingToolbarIfNeeded()"))
        #expect(windowManagementSource.contains(
            "loadingToolbar.itemIdentifiers = [.flexibleSpace]"
        ))
        #expect(!windowManagementSource.contains("window.styleMask.remove(.fullSizeContentView)"))
        #expect(windowManagementSource.contains("window.styleMask.insert(.fullSizeContentView)"))
        #expect(contentSource.contains(
            ".toolbarBackgroundVisibility(.hidden, for: .windowToolbar)"
        ))
        #expect(!appSource.contains("Collapse Note"))
        #expect(sidebarSource.contains("ScholiumInterfaceTypography.libraryFolderTitle"))
        #expect(sidebarSource.contains("ScholiumInterfaceTypography.libraryNoteTitle"))
        #expect(sidebarSource.contains("ScholiumInterfaceTypography.metadata"))
        #expect(
            ScholiumMetrics.Library.hierarchyRowHeight
                >= ScholiumMetrics.Accessibility.minimumCustomTarget
        )
        #expect(ScholiumMetrics.Library.contentInset == ScholiumGrid.Peripheral.contentInset)
        #expect(ScholiumMetrics.Library.minimumReadableWidth == 300)
    }

    @Test("The semantic Library sidebar receives the readable minimum without replacing AppKit behavior")
    func librarySidebarReadableMinimum() throws {
        let controller = ScholiumWorkspaceSplitView<EmptyView, EmptyView, EmptyView>.Controller(
            initialLibraryVisible: true,
            initialApparatusVisible: false,
            documentTabs: [],
            selectedDocumentTabID: nil,
            selectDocumentTab: { _ in },
            closeDocumentTab: { _ in },
            libraryVisibilityDidChange: { _ in },
            researchInspectorVisibilityDidChange: { _ in },
            splitControllerDidAttach: { _ in },
            splitControllerDidDetach: { _ in },
            library: EmptyView(),
            document: EmptyView(),
            apparatus: EmptyView()
        )

        _ = controller.view
        let libraryItem = try #require(controller.splitViewItems.first)

        #expect(libraryItem.behavior == .sidebar)
        #expect(libraryItem.minimumThickness == ScholiumMetrics.Library.minimumReadableWidth)
        #expect(libraryItem.canCollapse)
        #expect(libraryItem.canCollapseFromWindowResize)
        #expect(libraryItem.topAlignedAccessoryViewControllers.isEmpty)
        #expect(controller.splitViewItems[1].topAlignedAccessoryViewControllers.isEmpty)
        #expect(controller.splitViewItems[2].topAlignedAccessoryViewControllers.isEmpty)
        #expect(controller.minimumThicknessForInlineSidebars == NSSplitViewController.automaticDimension)
    }

    @Test("Only collapsed peripheral Show controls enter the Document toolbar")
    func collapsedPeripheralToolbarLayout() throws {
        typealias Item = ScholiumWorkspaceToolbarController.Item

        for sidebarVisible in [false, true] {
            for researchInspectorVisible in [false, true] {
                let identifiers = ScholiumWorkspaceToolbarController.itemIdentifiers(
                    sidebarVisible: sidebarVisible,
                    researchInspectorVisible: researchInspectorVisible
                )
                let libraryDividerIndex = try #require(
                    identifiers.firstIndex(of: Item.libraryDivider)
                )
                let documentIndex = try #require(
                    identifiers.firstIndex(of: Item.documentIdentity)
                )
                let apparatusDividerIndex = try #require(
                    identifiers.firstIndex(of: Item.apparatusDivider)
                )
                #expect(libraryDividerIndex < documentIndex)
                #expect(documentIndex < apparatusDividerIndex)
                if sidebarVisible {
                    #expect(!identifiers.contains(Item.sidebar))
                } else {
                    let sidebarIndex = try #require(
                        identifiers.firstIndex(of: Item.sidebar)
                    )
                    #expect(libraryDividerIndex < sidebarIndex)
                    #expect(sidebarIndex < documentIndex)
                }
                if researchInspectorVisible {
                    #expect(!identifiers.contains(Item.inspector))
                } else {
                    let inspectorIndex = try #require(
                        identifiers.firstIndex(of: Item.inspector)
                    )
                    #expect(documentIndex < inspectorIndex)
                    #expect(inspectorIndex < apparatusDividerIndex)
                }
            }
        }

        let toolbarSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "Scholium/UI/Components/ScholiumWorkspaceToolbar.swift"
                ),
            encoding: .utf8
        )
        #expect(!toolbarSource.contains("scholium.toolbar.attention"))
        #expect(!toolbarSource.contains("ScholiumWorkspaceAttentionToolbarView"))

        let windowManagementSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "Scholium/UI/Components/ScholiumWindowManagement.swift"
                ),
            encoding: .utf8
        )
        #expect(!windowManagementSource.contains("anchor: .toolbar"))
        #expect(!windowManagementSource.contains("preferredPresentationSlot"))
    }

    @Test("Native split backgrounds fill the titlebar without an extension effect")
    func nativeSurfaceContainer() throws {
        let contentController = NSViewController()
        contentController.view = NSView()
        let controller = ScholiumSurfaceContainerViewController(
            contentViewController: contentController,
            backgroundRole: .navigation
        )

        _ = controller.view
        let background = controller.backgroundView

        #expect(controller.children == [contentController])
        #expect(background.superview === controller.view)
        #expect(background !== contentController.view)
        #expect(!background.translatesAutoresizingMaskIntoConstraints)
        #expect(contentController.view.superview === controller.view)
        #expect(controller.view.subviews.first === background)
        #expect(controller.view.subviews.last === contentController.view)

    }

    @Test("Research Inspector keeps AppKit behavior after removing its fixed maximum")
    func researchInspectorKeepsAppKitBehavior() throws {
        let controller = ScholiumWorkspaceSplitView<EmptyView, EmptyView, EmptyView>.Controller(
            initialLibraryVisible: true,
            initialApparatusVisible: false,
            documentTabs: [],
            selectedDocumentTabID: nil,
            selectDocumentTab: { _ in },
            closeDocumentTab: { _ in },
            libraryVisibilityDidChange: { _ in },
            researchInspectorVisibilityDidChange: { _ in },
            splitControllerDidAttach: { _ in },
            splitControllerDidDetach: { _ in },
            library: EmptyView(),
            document: EmptyView(),
            apparatus: EmptyView()
        )

        _ = controller.view
        let item = try #require(controller.splitViewItems.last)

        #expect(item.behavior == .inspector)
        #expect(item.canCollapse)
        #expect(item.isCollapsed)
        #expect(item.maximumThickness == NSSplitViewItem.unspecifiedDimension)
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
        let componentsSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumComponents.swift"
            ),
            encoding: .utf8
        )

        #expect(typographySource.contains("static let libraryHierarchy = Font.callout"))
        #expect(typographySource.contains("static let libraryFolderTitle = libraryHierarchy"))
        #expect(typographySource.contains("static let libraryNoteTitle = libraryHierarchy"))
        #expect(typographySource.contains("static let librarySelectedNoteTitle"))
        #expect(typographySource.contains("static let bibliographyEmptyState = metadata"))
        #expect(typographySource.contains("static let noteTitle = Font.body"))
        #expect(typographySource.contains("static let literatureCitation"))
        #expect(typographySource.contains("static let libraryLocation"))
        #expect(componentsSource.contains("struct SidebarAttentionAlert"))
        #expect(componentsSource.contains("title: \"ATTENTION\""))
        #expect(componentsSource.contains("Image(systemName: \"exclamationmark.triangle\")"))
        #expect(!sidebarSource.contains(".focusEffectDisabled()"))
        #expect(sidebarSource.contains("ScholiumColorRole.navigationSurfaceBackground.color"))
        #expect(!sidebarSource.contains(".pickerStyle(.segmented)"))
        #expect(sidebarSource.contains("ScholiumLibraryLocationPicker(selection:"))
        #expect(componentsSource.contains("struct ScholiumLibraryLocationPicker"))
        #expect(componentsSource.contains("struct ScholiumQuietRowButtonStyle"))
        #expect(componentsSource.contains(".menuStyle(.borderlessButton)"))
        #expect(componentsSource.contains("locationChoice(\"Library\", value: .workspace)"))
        #expect(componentsSource.contains("locationChoice(\"Set Aside\", value: .setAside)"))
        #expect(componentsSource.contains("locationChoice(\"Trash\", value: .trash)"))
        #expect(componentsSource.contains(".accessibilityLabel(\"Location\")"))
        #expect(componentsSource.contains(".accessibilityValue(selectedTitle)"))
        #expect(!componentsSource.contains(".accessibilityRepresentation"))
        #expect(!componentsSource.contains("Picker(\"Location\""))
        #expect(!componentsSource.contains("Image(systemName: \"chevron"))
        #expect(sidebarSource.contains(".menuIndicator(.hidden)"))
        #expect(sidebarSource.contains("ScholiumInterfaceTypography.libraryFolderTitle"))
        #expect(sidebarSource.contains("ScholiumInterfaceTypography.librarySelectedNoteTitle"))
        #expect(sidebarSource.contains("ScholiumEditorialIndexUnderline("))
        #expect(sidebarSource.contains(
            "ScholiumMotion.disclosure(reduceMotion: reduceMotion)"
        ))
        #expect(!sidebarSource.contains(
            "withAnimation(.easeInOut(duration: 0.16)"
        ))
        #expect(sidebarSource.contains("if let attentionAlertState"))
        #expect(componentsSource.contains("case active(count: Int)"))
        #expect(componentsSource.contains("case checking"))
        #expect(componentsSource.contains("case unavailable"))
        let attentionSurfaceStart = try #require(componentsSource.range(
            of: "private struct SidebarAttentionAlertSurface"
        ))
        let attentionSurfaceEnd = try #require(componentsSource.range(
            of: "private struct SidebarAttentionAlertButtonStyle",
            range: attentionSurfaceStart.upperBound ..< componentsSource.endIndex
        ))
        let attentionSurface = componentsSource[
            attentionSurfaceStart.lowerBound ..< attentionSurfaceEnd.lowerBound
        ]
        #expect(!attentionSurface.contains("overlay(alignment: .leading)"))
        #expect(ScholiumMetrics.Library.leadingSlotWidth == 16)
        #expect(ScholiumMetrics.Library.hierarchyRowHeight == 28)
        #expect(sidebarSource.contains(
            ".padding(.horizontal, ScholiumMetrics.Library.contentInset)"
        ))
        #expect(!sidebarSource.contains("attentionHorizontalInset"))
        let brandLabel = try #require(sidebarSource.range(of: "Text(\"Scholium\")"))
        let triptychMenu = try #require(sidebarSource.range(
            of: "Menu {",
            range: brandLabel.upperBound ..< sidebarSource.endIndex
        ))
        #expect(brandLabel.lowerBound < triptychMenu.lowerBound)
        let sidebarBody = try #require(sidebarSource.range(of: "var body: some View"))
        let sidebarSectionsEnd = try #require(sidebarSource.range(
            of: "// MARK: Fixed identity and navigation",
            range: sidebarBody.upperBound ..< sidebarSource.endIndex
        ))
        let sidebarSections = sidebarSource[
            sidebarBody.lowerBound ..< sidebarSectionsEnd.lowerBound
        ]
        let scope = try #require(sidebarSections.range(of: "scopeIndex"))
        let attention = try #require(sidebarSections.range(of: "SidebarAttentionAlert("))
        let library = try #require(sidebarSections.range(of: "locationHeader"))
        let sourceScroll = try #require(sidebarSections.range(of: "ScrollView(.vertical)"))
        let bibliography = try #require(sidebarSections.range(
            of: "recommendedBibliographyUtility"
        ))
        #expect(scope.lowerBound < attention.lowerBound)
        #expect(attention.lowerBound < library.lowerBound)
        #expect(sourceScroll.lowerBound < bibliography.lowerBound)
        let sourceRegion = sidebarSections[sourceScroll.lowerBound ..< bibliography.lowerBound]
        #expect(!sourceRegion.contains("SidebarRecommendedBibliographySection("))
        #expect(sourceRegion.contains("scholium.noteList"))
        #expect(sidebarSections.contains(
            "pinnedViews: [.sectionHeaders]"
        ))
        #expect(sidebarSource.contains("struct SidebarSourceSection"))
        #expect(sidebarSource.contains("sidebarSourceSections("))
        #expect(sidebarSource.contains("flattenedVisibleDescendants("))
        #expect(!sidebarSource.contains("struct SidebarTreeBranch"))
        #expect(!sidebarSource.contains("filteredNotes.count"))
        #expect(
            sidebarSource.components(
                separatedBy: "width: ScholiumMetrics.Accessibility.preferredCustomTarget"
            ).count >= 3
        )
        #expect(sidebarSource.contains("title: ScholiumL10n.dynamicString(\"Hide Sidebar\")"))

        for section in ["Integrity", "Metadata", "Properties", "Order", "Actions"] {
            #expect(sidebarSource.contains("Section(\"\(section)\")"))
        }
        #expect(!sidebarSource.contains("Section(\"Review\")"))

        #expect(sidebarSource.contains("SidebarRecommendedBibliographySection("))
        #expect(sidebarSource.contains(
            ".background(ScholiumColorRole.navigationSurfaceBackground.color)"
        ))
        #expect(sidebarSource.contains("ScholiumStructuralRule()"))
        #expect(!sidebarSource.contains("SidebarLiteratureSection("))
        #expect(!sidebarSource.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))

        let brandStart = try #require(sidebarSource.range(of: "private var brandHeader"))
        let brandEnd = try #require(sidebarSource.range(
            of: "private var scopeIndex",
            range: brandStart.upperBound ..< sidebarSource.endIndex
        ))
        let brandHeader = sidebarSource[brandStart.lowerBound ..< brandEnd.lowerBound]
        #expect(brandHeader.contains("Menu {"))
        #expect(!brandHeader.contains("Image(systemName: \"chevron.down\")"))
        let scopeIndexStart = try #require(sidebarSource.range(of: "private var scopeIndex"))
        let scopeIndexEnd = try #require(sidebarSource.range(
            of: "private func isCurrent",
            range: scopeIndexStart.upperBound ..< sidebarSource.endIndex
        ))
        let scopeIndexSource = sidebarSource[
            scopeIndexStart.lowerBound ..< scopeIndexEnd.lowerBound
        ]
        #expect(!scopeIndexSource.contains("attentionCount"))
        #expect(!scopeIndexSource.contains("contentTransition(.numericText())"))
        #expect(!scopeIndexSource.contains("accessibilityValue"))
    }

    @Test("Lifecycle destinations reuse the Library grid without overlay chrome")
    func lifecycleDestinationGridContract() throws {
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
        let componentsSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumComponents.swift"
            ),
            encoding: .utf8
        )

        for required in [
            "ScholiumLibraryLocationPicker(selection: locationSelection)",
            "ScholiumMetrics.Library.hierarchyRowHeight",
            "ScholiumMetrics.Accessibility.preferredCustomTarget",
            "ScholiumGrid.Spacing.inlineControlGap",
            "ScholiumGrid.Spacing.labelAccessoryGap",
            "ScholiumGrid.Spacing.sectionSeparation",
            "ScholiumLibrarySourceState",
            "pinnedViews: [.sectionHeaders]",
            "scholium.lifecyclePutBack.",
        ] {
            #expect(sidebarSource.contains(required), "Missing lifecycle destination contract: \(required)")
        }
        for required in [
            "locationChoice(\"Library\", value: .workspace)",
            "locationChoice(\"Set Aside\", value: .setAside)",
            "locationChoice(\"Trash\", value: .trash)",
            ".menuStyle(.borderlessButton)",
            "struct ScholiumLibrarySourceState",
            ".padding(.horizontal, ScholiumMetrics.Library.contentInset)",
            ".accessibilityLabel(\"Location\")",
            ".accessibilityValue(selectedTitle)",
        ] {
            #expect(componentsSource.contains(required), "Missing LocationPicker component contract: \(required)")
        }
        #expect(!componentsSource.contains("Picker(\"Location\""))
        #expect(!componentsSource.contains(".accessibilityRepresentation"))

        for removed in [
            "SidebarLifecycleCard",
            "SidebarLifecycleDestinationView",
            "lifecycleDestinationScope",
            "scholium.lifecycleBack",
            "sidebarBottomRegion",
            "libraryFooterHeight",
            ".boundedPanel",
            "0.48",
            ".move(edge: .bottom)",
            ".snappy(duration: 0.2)",
            "HStack(spacing: 24)",
            ".padding(.horizontal, 61)",
            ".frame(minHeight: 170, idealHeight: 280, maxHeight: 360)",
        ] {
            #expect(!sidebarSource.contains(removed), "Retired lifecycle overlay remains: \(removed)")
        }
        #expect(!sidebarSource.contains("private enum SidebarSpacing"))
        #expect(!sidebarSource.contains("private enum LifecycleSpacing"))
        #expect(ScholiumMetrics.Library.sourceStateVerticalInset == 16)
    }

    @Test("Attention search lives in the transient Workspace popover without custom close chrome")
    func attentionSearchOwnershipContract() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let attentionSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/AttentionQueueView.swift"
            ),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: repository.appendingPathComponent("Scholium/App/ScholiumApp.swift"),
            encoding: .utf8
        )
        #expect(attentionSource.contains("TextField(\"Search Attention\""))
        #expect(attentionSource.contains("scholium.attentionSearch"))
        #expect(attentionSource.contains("content.popover("))
        #expect(attentionSource.contains("AttentionPopoverContent(session: session)"))
        #expect(attentionSource.contains("session.dismiss()"))
        #expect(attentionSource.contains(
            ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)"
        ))
        #expect(!attentionSource.contains(".searchable("))
        #expect(!attentionSource.contains("placement: .toolbar"))
        #expect(appSource.contains("lazy var attentionPopoverSession"))
        #expect(!appSource.contains("Window(\"Attention\", id: \"scholium-attention\")"))
        #expect(!appSource.contains("AttentionWindowSession"))
        #expect(!attentionSource.contains("Button(\"Close\""))
    }

    @Test("Completed Sidebar and Inspector proofs leave no compatibility residue")
    func sidebarInspectorProofResidueIsAbsent() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for path in [
            "Scholium/UI/PreviewCatalog/DesignContractCompleteWindowProofs.swift",
            "Scholium/UI/PreviewCatalog/EditorialParchmentProof.swift",
            "Scholium/UI/PreviewCatalog/ScholiumComponentCatalog.swift",
        ] {
            #expect(!FileManager.default.fileExists(atPath: repository.appendingPathComponent(path).path))
        }

        let appSource = try String(
            contentsOf: repository.appendingPathComponent("Scholium/App/ScholiumApp.swift"),
            encoding: .utf8
        )
        let componentSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumComponents.swift"
            ),
            encoding: .utf8
        )
        let sidebarSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Sidebar/SidebarView.swift"
            ),
            encoding: .utf8
        )
        let workflowProofSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/PreviewCatalog/ResearchWorkflowPreviewCatalog.swift"
            ),
            encoding: .utf8
        )

        for retiredRoute in [
            "scholium-editorial-parchment-proof",
            "scholium-stage4-design-proofs",
            "DesignContractProofWindowRoute",
        ] {
            #expect(!appSource.contains(retiredRoute))
        }
        for retiredComponent in [
            "ScholiumPanelHeader",
            "ScholiumInlineStatus",
            "ScholiumSourceAnchorRow",
            "ScholiumEmptyState",
            "ScholiumNoteRow",
        ] {
            #expect(!componentSource.contains(retiredComponent))
        }
        #expect(componentSource.contains("enum ScholiumDocumentStatusKind"))
        #expect(sidebarSource.contains("struct SidebarNoteRow"))
        #expect(!sidebarSource.contains("struct NoteCardRow"))
        #expect(!workflowProofSource.contains("case actions"))
        #expect(!workflowProofSource.contains("ResearchActionsProof"))
        #expect(!workflowProofSource.contains("case stateMatrix"))
        #expect(!workflowProofSource.contains("ResearchWorkflowProofState"))
    }

    @Test("Accepted-A heading-wrap proof stays in the QA journey and production renderer")
    func documentHeadingProofIsQABounded() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let uiTestSource = try [
            "ScholiumUITests.swift",
            "ScholiumUITests+WorkspaceResearch.swift",
            "ScholiumUITests+PresentationRecords.swift",
            "ScholiumUITests+WindowsLifecycle.swift",
            "ScholiumUITests+EditorCoordination.swift",
            "ScholiumUITests+Support.swift",
            "ScholiumPerformanceUITests.swift",
            "ScholiumUpgradeSafetyUITests.swift",
        ].map { fileName in
            try String(
                contentsOf: repository.appendingPathComponent("UITests/\(fileName)"),
                encoding: .utf8
            )
        }.joined(separator: "\n")
        let appSource = try String(
            contentsOf: repository.appendingPathComponent("Scholium/App/ScholiumApp.swift"),
            encoding: .utf8
        )
        let noteSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/NoteContentView.swift"
            ),
            encoding: .utf8
        )
        let appearanceSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Styling/DocumentAppearanceStyles.swift"
            ),
            encoding: .utf8
        )

        #expect(uiTestSource.contains("testDocumentHeadingStudyWrapsLongMixedTitleUsingAcceptedBodyRhythm"))
        #expect(uiTestSource.contains("--scholium-document-heading-proof"))
        #expect(uiTestSource.contains("XCUIApplication(bundleIdentifier: \"com.scholium.qa\")"))
        #expect(uiTestSource.contains("workspace.screenshot()"))
        #expect(uiTestSource.contains("lineHeight: 2.00"))
        #expect(uiTestSource.contains("paragraphSpacing: 1.00"))
        #expect(uiTestSource.contains("letterSpacing: 0.020"))
        #expect(!uiTestSource.contains("lineHeight: 1.80"))
        #expect(!uiTestSource.contains("lineHeight: 1.65"))
        #expect(uiTestSource.contains("XCTAssertEqual(sliderNumericValue(lineWidth), 72)"))
        #expect(uiTestSource.contains("Heading Study — accepted A — long mixed H1 — 1180×760 — Review — static secondary toolbar identity"))
        #expect(uiTestSource.contains("Heading Study — accepted A — long mixed H1 — 900×760 — Review — static secondary toolbar identity"))
        #expect(uiTestSource.contains("在长期论证中保持证据边界：Reasons, Values"))
        #expect(!uiTestSource.contains("## Abstract"))
        #expect(uiTestSource.contains("XCTAssertEqual(try Data(contentsOf: noteURL), sourceBefore)"))
        #expect(!appSource.contains("--scholium-document-heading-proof"))
        #expect(!appSource.contains("scholium-document-heading-proof"))
        #expect(appearanceSource.contains(".scholium-document p {"))
        #expect(!appearanceSource.contains(".scholium-document h1 + p"))
        #expect(!appearanceSource.contains(".scholium-document h2 + p"))
        #expect(noteSource.contains("DocumentEditorHost("))
        #expect(noteSource.contains("SafeMarkdownReadWebView("))
        #expect(noteSource.contains("MarkdownEditorWebView("))
        #expect(noteSource.contains("documentPresentation.css + \"\\n\" + state.appearanceCSS"))
    }

    @Test("Overview, Connect, and Actions share one variable-driven Apparatus geometry")
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
        let sharedComponentsSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumComponents.swift"
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
        let actionsSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/ResearchActions/ResearchActionsInspectorView.swift"
            ),
            encoding: .utf8
        )
        let noteSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/NoteContentView.swift"
            ),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )

        #expect(ScholiumMetrics.Apparatus.contentInset == 28)
        #expect(
            ScholiumMetrics.Apparatus.contentInset
                == ScholiumMetrics.Library.contentInset
        )
        #expect(
            ScholiumMetrics.Apparatus.firstSectionSpacing
                == ScholiumGrid.Apparatus.firstSectionGap
        )
        #expect(
            ScholiumMetrics.Apparatus.sectionSpacing
                == ScholiumGrid.Apparatus.sectionGap
        )
        #expect(
            ScholiumMetrics.Apparatus.sectionContentSpacing
                == ScholiumGrid.Apparatus.headingToContentGap
        )
        #expect(
            ScholiumMetrics.Apparatus.iconColumnWidth
                == ScholiumGrid.Apparatus.iconColumnWidth
        )
        #expect(
            ScholiumMetrics.Apparatus.iconToTextSpacing
                == ScholiumGrid.Apparatus.iconToTextGap
        )
        #expect(ScholiumMetrics.Apparatus.factGridMinimumWidth == 204)
        #expect(ScholiumMetrics.Apparatus.factLabelMinimumWidth == 78)
        #expect(ScholiumMetrics.Apparatus.factColumnSpacing == 14)
        #expect(ScholiumMetrics.Apparatus.relationGlyphColumnWidth == 24)
        #expect(ScholiumMetrics.Apparatus.relationGlyphSize == 20)
        #expect(ScholiumMetrics.Apparatus.relationGlyphToTextSpacing == 4)
        #expect(ScholiumMetrics.Apparatus.relationClusterSpacing == 12)
        #expect(ScholiumMetrics.Apparatus.relationPinnedGlyphTop == 36)
        #expect(ScholiumMetrics.Apparatus.relationRowMinimumHeight == 36)
        #expect(ScholiumMetrics.Apparatus.actionRowMinimumHeight == 44)

        #expect(componentsSource.contains("struct ScholiumApparatusSection"))
        #expect(componentsSource.contains("struct ScholiumApparatusRow"))
        #expect(componentsSource.contains("struct ScholiumApparatusFactGrid"))
        #expect(componentsSource.contains("struct ScholiumApparatusActionRowContent"))
        #expect(componentsSource.contains("struct ScholiumApparatusStateView"))
        #expect(!componentsSource.contains("struct ScholiumApparatusQuietRowButtonStyle"))
        #expect(sharedComponentsSource.contains("struct ScholiumQuietRowButtonStyle"))
        #expect(componentsSource.contains("struct ScholiumApparatusSectionHeaderButton"))
        #expect(componentsSource.contains("struct ScholiumInspectorModeIndex"))
        #expect(componentsSource.contains("struct ScholiumConnectionGlyph"))
        #expect(!componentsSource.contains("select(mode)\n        focusedMode = mode"))
        #expect(componentsSource.contains("select(nextMode)\n        focusedMode = nextMode"))
        #expect(componentsSource.contains("ViewThatFits(in: .horizontal)"))
        #expect(componentsSource.contains("ForEach(visibleFacts)"))
        #expect(componentsSource.contains(
            "idealWidth: ScholiumMetrics.Apparatus.factValueMinimumWidth"
        ))
        #expect(sharedComponentsSource.contains("configuration.isPressed"))
        #expect(componentsSource.contains(
            "ScholiumInterfaceTypography.apparatusBody.weight(.semibold)"
        ))
        #expect(!componentsSource.contains(".accessibilityHint(detail"))
        #expect(componentsSource.contains(
            "width: ScholiumMetrics.Apparatus.iconColumnWidth"
        ))
        #expect(componentsSource.contains(
            ".padding(.bottom, ScholiumMetrics.Apparatus.sectionContentSpacing)"
        ))
        #expect(componentsSource.contains(
            ".lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)"
        ))
        #expect(researchSource.contains(
            ".padding(.horizontal, ScholiumMetrics.Apparatus.contentInset)"
        ))
        #expect(researchSource.contains("attentionSection"))
        #expect(!researchSource.contains("if !context.visibleAttentionItems.isEmpty"))
        #expect(researchSource.contains("aboutSection"))
        #expect(researchSource.contains("propertyFacts"))
        #expect(researchSource.contains("ResearchProjectionFreshnessView("))
        #expect(researchSource.contains("ScholiumApparatusStateView("))
        #expect(connectionsSource.contains(
            ".padding(.horizontal, ScholiumMetrics.Apparatus.contentInset)"
        ))
        #expect(connectionsSource.contains("Image(systemName: \"chevron.right\")"))
        #expect(connectionsSource.contains(
            "ScholiumMotion.disclosure(reduceMotion: reduceMotion)"
        ))
        #expect(connectionsSource.contains(
            "ScholiumInterfaceTypography.apparatusResearchContent"
        ))
        #expect(actionsSource.contains(
            ".padding(.horizontal, ScholiumMetrics.Apparatus.contentInset)"
        ))
        #expect(actionsSource.contains("ScholiumApparatusActionRowContent("))
        #expect(actionsSource.contains("ScholiumApparatusStateView("))
        #expect(actionsSource.contains("ResearchActionVisualSection"))
        #expect(actionsSource.contains("BuiltInActionVisualGroup"))
        #expect(actionsSource.contains("title: \"RESEARCH\""))
        #expect(actionsSource.contains("title: \"REVIEW\""))
        #expect(actionsSource.contains("title: \"RESEARCHER SKILLS\""))
        #expect(actionsSource.contains("ScholiumApparatusSection(\"JUDGMENT\")"))
        #expect(!actionsSource.contains("@FocusedValue(\\.scholiumResearchActionActions)"))
        #expect(actionsSource.contains("if shouldRestoreKeyboardFocus"))
        #expect(actionsSource.contains("registerFocusOwner(item.id)"))
        #expect(actionsSource.contains("action(!activationWasPointerDriven)"))
        #expect(actionsSource.contains("case .leftMouseDown, .leftMouseUp"))
        #expect(!actionsSource.contains(
            "focusRestorationTask?.cancel()\n            hasKeyboardFocus = true\n            action()"
        ))
        #expect(!actionsSource.contains("ScholiumStructuralRule()"))
        #expect(actionsSource.contains("ResearchActionHelpModifier(text: item.helpText)"))
        #expect(!actionsSource.contains(".accessibilityHint(detailText"))
        #expect(researchSource.contains("visibleAttentionKinds.prefix(3)"))
        #expect(!researchSource.contains("Text(item.message)"))
        #expect(!researchSource.contains("\"Show All\""))
        #expect(researchSource.contains("if let invalidResearchUnitMessage"))
        #expect(researchSource.contains("systemImage: \"exclamationmark.triangle\""))
        #expect(researchSource.contains("ScholiumApparatusSectionHeaderButton("))
        #expect(researchSource.contains("actionLabel: \"Edit Properties\""))
        #expect(researchSource.contains("accessibilityIdentifier: \"scholium.about.edit\""))
        #expect(researchSource.contains(".accessibilityIdentifier(\"scholium.about\")"))
        #expect(researchSource.contains("title: Text(\"Open in Zotero\")"))
        #expect(researchSource.contains("systemImage: \"arrow.up.forward.app\""))
        #expect(researchSource.contains(
            ".accessibilityIdentifier(\"scholium.researchOverview.openInZotero\")"
        ))
        #expect(!researchSource.contains("ZOTERO SOURCE"))
        #expect(!researchSource.contains("Customize"))
        #expect(!researchSource.contains("prefix(5)"))
        #expect(!researchSource.contains("Scholarly Status"))
        #expect(!researchSource.contains("Provenance"))
        #expect(!researchSource.contains("Derived State"))
        #expect(connectionsSource.contains("private var relationButton: some View"))
        #expect(connectionsSource.contains("pinnedViews: [.sectionHeaders]"))
        #expect(connectionsSource.contains("connectionGroupHeader("))
        #expect(connectionsSource.contains(".scholiumSurface(.apparatus)"))
        #expect(!connectionsSource.contains("ScholiumColorRole.surfaceBackground.color"))
        #expect(connectionsSource.contains("ConnectionRelationshipCluster"))
        #expect(connectionsSource.contains("relationGlyphColumnWidth"))
        #expect(connectionsSource.contains("relationPinnedGlyphTop"))
        #expect(connectionsSource.contains("GeometryReader"))
        #expect(!connectionsSource.contains("symbolText"))
        #expect(connectionsSource.contains("Open relation source"))
        #expect(!connectionsSource.contains("Image(systemName: \"arrow.up.forward\")"))
        #expect(!connectionsSource.contains("Text(\"↗\")"))
        #expect(!connectionsSource.contains("DisclosureGroup(\n            isExpanded:"))
        #expect(noteSource.contains("ScholiumInspectorModeIndex("))
        #expect(appSource.contains("case .researchConfigurationInvalidated = event"))
        #expect(appSource.contains("refreshResearchActionAvailability()"))
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
        #expect(content.contains("ScholiumNoDocumentDetailView()"))
        #expect(content.contains(".accessibilityIdentifier(\"scholium.noDocumentSurface\")"))
        #expect(content.contains("ScholiumWorkspaceSplitView("))
        #expect(!content.contains("NavigationSplitView("))
        #expect(!content.contains("HSplitView {"))
        #expect(!content.contains("preferredApparatusWidth"))
        #expect(content.contains(".padding(.top, ScholiumMetrics.Search.responsiveMargin)"))
        #expect(!content.contains("NavigationBackdropView"))
        #expect(!content.contains(".backgroundExtensionEffect()"))
        #expect(!content.contains(".regularMaterial"))
        #expect(!content.contains("height: geometry.size.height"))
        #expect(!noteSource.contains("ResearchStripView"))
        #expect(!noteSource.contains("scholium.researchStrip"))
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
        #expect(toolbar.contains("windowActions.showResearchRecord()"))
        #expect(toolbar.contains("\"scholium.toolbar.inspector\""))
        #expect(toolbar.contains("ScholiumWorkspaceShowInspectorToolbarView"))
        #expect(toolbar.contains("static let researchRecord"))
        #expect(toolbar.contains("selectedDocument == nil"))
        #expect(toolbar.contains(".disabled(!isAvailable)"))
        #expect(!noteSource.contains("\"scholium.documentMore\""))

        #expect(ScholiumMetrics.Library.contentInset == ScholiumGrid.Peripheral.contentInset)
        #expect(ScholiumMetrics.Library.sectionSpacing == ScholiumGrid.Spacing.sectionSeparation)
        #expect(ScholiumMetrics.Apparatus.contentInset == ScholiumGrid.Apparatus.contentInset)
        #expect(ScholiumMetrics.Apparatus.contentInset == ScholiumMetrics.Library.contentInset)
        #expect(ScholiumMetrics.Apparatus.sectionSpacing == ScholiumGrid.Apparatus.sectionGap)
        #expect(
            ScholiumMetrics.Apparatus.sectionContentSpacing
                == ScholiumGrid.Apparatus.headingToContentGap
        )
        #expect(ScholiumMetrics.Apparatus.headerHeight == ScholiumGrid.Apparatus.modeStripHeight)
        #expect(ScholiumMetrics.Apparatus.headerHeight == 40)
        #expect(ScholiumMetrics.Library.hierarchyRowHeight == 28)

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
        original.restorePresentationMode(.source)
        original.editingSource = "exact markdown bytes\n"

        let afterProjectionChange = store.session(for: key)
        #expect(afterProjectionChange === original)
        #expect(afterProjectionChange.presentationMode == .read)
        #expect(afterProjectionChange.selectedPresentationMode == .source)
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

    @Test("Search preparation failures close only the matching pending projection")
    func searchPreparationFailureClosesPendingProjection() {
        let controller = DiscoveryController()
        let first = SearchWorkspaceState(query: "first", scope: .thisNote)
        let second = SearchWorkspaceState(query: "second", scope: .triptych)

        controller.replaceSearchCriteria(first)
        #expect(controller.search.isRunning)
        controller.replaceSearchCriteria(second)
        controller.failPendingSearch("late bridge failure", for: first)

        #expect(controller.search.criteria == second)
        #expect(controller.search.isRunning)
        #expect(controller.search.errorMessage == nil)

        controller.failPendingSearch("current bridge failure", for: second)
        #expect(!controller.search.isRunning)
        #expect(controller.search.errorMessage == "current bridge failure")
    }

    @Test("Search rejects a response whose contract request ID does not match the active request")
    func searchResponseRequestIDRejection() {
        let controller = DiscoveryController()
        let request = controller.beginSearch(SearchWorkspaceState(
            query: "identity",
            scope: .triptych
        ))
        let generation = SearchGenerationID(
            triptychID: UUID(),
            sequence: 1,
            sourceManifestHash: "manifest"
        )
        controller.receiveSearchResponse(SearchResponse(
            requestID: UUID(),
            scope: .triptych,
            freshnessToken: .triptych(generation),
            availability: .current(generation),
            results: [],
            hasMore: false
        ), for: request)

        #expect(controller.search.responseRequestID == nil)
        #expect(controller.search.hits.isEmpty)
        #expect(controller.search.isRunning)
        #expect(controller.isCurrentSearch(request))
    }

    @Test("Editing a Search query removes the prior result projection immediately")
    func searchQueryChangeClearsPriorProjection() {
        let controller = DiscoveryController()
        let generation = SearchGenerationID(
            triptychID: UUID(),
            sequence: 1,
            sourceManifestHash: "manifest"
        )
        let freshness = SearchFreshnessToken.triptych(generation)
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
            freshnessToken: freshness,
            fingerprint: DocumentFingerprint(content: "# First\n"),
            evidentialLayer: .paperAnalysis,
            classification: .retrievalLead
        )
        let first = controller.beginSearch(SearchWorkspaceState(
            query: "first",
            scope: .triptych
        ))
        controller.receiveSearchResponse(SearchResponse(
            requestID: first.id,
            scope: .triptych,
            freshnessToken: freshness,
            availability: .current(generation),
            results: [hit],
            hasMore: false
        ), for: first)
        #expect(controller.search.hits.count == 1)
        #expect(controller.search.selectedResultID == nil)

        controller.updateSearchQuery("second")

        #expect(controller.search.criteria.query == "second")
        #expect(controller.search.selectedResultID == nil)
        #expect(controller.search.hits.isEmpty)
        #expect(controller.search.relatedItems.isEmpty)
        #expect(controller.search.isRunning)
        #expect(!controller.isCurrentSearch(first))

        let second = controller.beginSearch(controller.search.criteria)
        controller.receiveSearchResponse(SearchResponse(
            requestID: second.id,
            scope: .thisNote,
            freshnessToken: freshness,
            availability: .current(generation),
            results: [hit],
            hasMore: false
        ), for: second)
        controller.selectSearchScope(.thisNote)
        #expect(controller.search.criteria.scope == .thisNote)
        #expect(controller.search.hits.isEmpty)
        #expect(controller.search.relatedItems.isEmpty)
        #expect(controller.search.isRunning)
        #expect(!controller.isCurrentSearch(second))

        let scoped = controller.beginSearch(controller.search.criteria)
        controller.receiveSearchResponse(SearchResponse(
            requestID: scoped.id,
            scope: .thisNote,
            freshnessToken: freshness,
            availability: .current(generation),
            results: [hit],
            hasMore: false
        ), for: scoped)
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

    @Test("Presenting Search does not flush or save the editor")
    func searchPresentationDoesNotCommitTheEditor() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let searchSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/App/Window/WindowSearchController.swift"
            ),
            encoding: .utf8
        )
        let searchBoundary = try #require(
            searchSource.range(of: "func begin(_ invocation: SearchInvocation)")
        )
        let dismissalBoundary = try #require(
            searchSource.range(
                of: "func dismiss()",
                range: searchBoundary.upperBound ..< searchSource.endIndex
            )
        )
        let implementation = searchSource[
            searchBoundary.lowerBound ..< dismissalBoundary.lowerBound
        ]
        #expect(implementation.contains("discoveryController.presentSearch(invocation)"))
        #expect(!implementation.contains("flushRegisteredEditorIfNeeded"))
        #expect(!implementation.contains("save"))
    }

    @Test("Research Inspector has one trailing-context owner")
    func researchContextExclusivity() {
        let controller = ResearchController()
        #expect(!controller.inspector.isVisible)
        controller.showResearchInspector(true)
        #expect(controller.inspector.isVisible)
    }

    @Test("Recommended Bibliography is a Triptych apparatus outside the Library source region")
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
            "ResearchSkillTransactionCoordinator", "import ScholiumApplication",
        ] {
            #expect(!section.contains(forbidden))
            #expect(!controller.contains(forbidden))
        }
        #expect(controller.contains("final class RecommendedBibliographyController"))
        #expect(controller.contains("RecommendedBibliographyScope"))
        #expect(!controller.contains("RecommendedBibliographyTarget"))
        #expect(controller.contains("It owns no repository, skill package, YAML, or filesystem authority."))
        #expect(!section.contains("Triptych · Reading leads, not evidence"))
        #expect(section.contains("Triptych Recommended Bibliography"))
        #expect(section.contains("Image(systemName: \"chevron.forward\")"))
        #expect(section.contains("controller.visibleCandidates.first"))
        #expect(section.contains("ScholiumInterfaceTypography.bibliographyEmptyState"))
        #expect(section.contains("ScholiumQuietRowButtonStyle("))
        #expect(section.contains(".accessibilityValue(recommendationAccessibilityValue)"))
        #expect(!section.contains(".accessibilityElement(children: .ignore)"))
        #expect(!section.contains("arrow.up.right.square"))
        #expect(!section.contains("ScrollView(.horizontal)"))
        #expect(section.contains("Update Recommendations"))
        #expect(!section.contains("Open in Zotero"))
        #expect(!section.contains("openZoteroItem"))
        #expect(section.contains("Dismiss"))
        #expect(section.contains("Repair in Research Guidance"))
        #expect(section.contains("Recommended Bibliography"))
        #expect(!section.contains("Open an Analysis to prepare"))
        #expect(!section.contains("SidebarLiteratureSection"))
        #expect(ScholiumMetrics.Library.bibliographyTopInset == 12)
        #expect(ScholiumMetrics.Library.bibliographyBottomInset == 16)

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
        #expect(splitSource.contains("tabStrip.setAccessibilityElement(true)"))
        #expect(splitSource.contains("tabStrip.setAccessibilityRole(.group)"))
        #expect(splitSource.contains("let documentTabsController:"))
        #expect(appSource.contains("NSWindow.allowsAutomaticWindowTabbing = false"))
        #expect(!appSource.contains("NativeWindowTabCoordinator"))
        #expect(!appSource.contains("addTabbedWindow"))
    }

    @Test("Native toolbar follows the exact per-window coordinator split")
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
        let windowManagementSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWindowManagement.swift"
            ),
            encoding: .utf8
        )

        #expect(splitSource.contains(
            "sidebarWithViewController: libraryBackgroundController"
        ))
        #expect(splitSource.contains(
            "inspectorWithViewController: apparatusBackgroundController"
        ))
        #expect(splitSource.contains("splitControllerDidAttach(self)"))
        #expect(splitSource.contains("splitControllerDidDetach(self)"))
        #expect(windowManagementSource.contains("splitController.nativeSplitViewController"))
        #expect(!appSource.contains("ScholiumWorkspaceSplitRegistry"))
        #expect(!appSource.contains("findWorkspaceSplitView"))
        #expect(toolbarSource.components(
            separatedBy: "NSTrackingSeparatorToolbarItem("
        ).count == 3)
        #expect(toolbarSource.contains("dividerIndex: 0"))
        #expect(toolbarSource.contains("dividerIndex: 1"))
        #expect(!splitSource.contains("ScholiumSurfaceHostController"))
        #expect(splitSource.contains("ScholiumSurfaceContainerViewController"))
        #expect(!splitSource.contains("NSBackgroundExtensionView"))
        #expect(toolbarSource.contains("item.isBordered = false"))
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
        #expect(Set(ScholiumWebDesignTokens.resolvedColorRoleCSSVariableNames) == nativeNames)

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

    @Test("Retired Markdown projections cannot regain a production path")
    func retiredMarkdownProjectionsAreAbsent() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let retiredProjection = repository.appendingPathComponent(
            "Scholium/Views/Note/NativeMarkdownEditorView.swift"
        )
        let retiredSemanticProjection = repository.appendingPathComponent(
            "ScholiumContracts/MarkdownSemantics.swift"
        )
        let contractsDirectory = repository.appendingPathComponent(
            "ScholiumContracts",
            isDirectory: true
        )
        let productionDocument = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/NoteContentView.swift"
            ),
            encoding: .utf8
        )

        #expect(!FileManager.default.fileExists(atPath: retiredProjection.path))
        #expect(!FileManager.default.fileExists(atPath: retiredSemanticProjection.path))
        for sourceURL in try FileManager.default.contentsOfDirectory(
            at: contractsDirectory,
            includingPropertiesForKeys: nil
        ).filter({ $0.pathExtension == "swift" }) {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            #expect(!source.contains("MarkdownSemanticProjection"))
        }
        #expect(!productionDocument.contains("NativeMarkdownReadView("))
        #expect(!productionDocument.contains("NativeMarkdownEditorView("))
    }

    @Test("Custom control metrics preserve native-control ownership")
    func customControlMetricContract() {
        #expect(ScholiumMetrics.Accessibility.preferredCustomTarget == 28)
        #expect(ScholiumMetrics.Accessibility.minimumCustomTarget == 20)
        #expect(ScholiumMetrics.Search.preferredWidth == 640)
        #expect(ScholiumMetrics.Search.cornerRadius == 12)
        #expect(ScholiumMetrics.Search.resultHorizontalInset == ScholiumGrid.Spacing.regionContentInset)
        #expect(ScholiumMetrics.Search.resultVerticalInset == ScholiumGrid.Spacing.labelAccessoryGap)
        #expect(ScholiumMetrics.Search.selectionIndicatorWidth == ScholiumGrid.Spacing.opticalAlignmentAdjustment)
        #expect(ScholiumShape.editorialControlCornerRadius == 8)
        #expect(ScholiumShape.editorialPanelCornerRadius == 10)
    }

    @Test("Adaptive editorial grid exposes semantic roles and explicit document units")
    func adaptiveEditorialGridContract() throws {
        #expect(ScholiumGrid.foundationUnit == 4)
        #expect(ScholiumGrid.Spacing.opticalAlignmentAdjustment == 2)
        #expect(ScholiumGrid.Spacing.labelAccessoryGap == 4)
        #expect(ScholiumGrid.Spacing.inlineControlGap == 8)
        #expect(ScholiumGrid.Spacing.nestedContentInset == 12)
        #expect(ScholiumGrid.Spacing.sectionSeparation == 16)
        #expect(ScholiumGrid.Spacing.regionContentInset == 20)
        #expect(ScholiumGrid.Spacing.documentShellInsetCSSPixels == 32)
        #expect(ScholiumGrid.Spacing.sourceShellInsetCSSPixels == 40)
        #expect(ScholiumGrid.Peripheral.contentInset == 28)
        #expect(ScholiumGrid.Dimension.compactHierarchyRowHeight == 24)
        #expect(ScholiumGrid.Dimension.libraryHierarchyRowHeight == 28)
        #expect(ScholiumGrid.Dimension.documentTabStripHeight == 40)
        #expect(ScholiumGrid.Dimension.researchFunctionTargetHeight == 44)
        #expect(ScholiumGrid.Dimension.regionHeaderHeight == 48)
        #expect(ScholiumGrid.Document.narrowWidthThresholdRootEms == 44)

        #expect(ScholiumMetrics.Library.contentInset == ScholiumGrid.Peripheral.contentInset)
        #expect(ScholiumMetrics.Apparatus.contentInset == ScholiumGrid.Peripheral.contentInset)
        #expect(ScholiumMetrics.Library.sectionSpacing == ScholiumGrid.Spacing.sectionSeparation)
        #expect(ScholiumMetrics.Library.hierarchyRowHeight == ScholiumGrid.Dimension.libraryHierarchyRowHeight)
        #expect(ScholiumMetrics.Search.responsiveMargin == ScholiumGrid.Spacing.regionContentInset)

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let foundation = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Foundation/ScholiumDesignSystem.swift"
            ),
            encoding: .utf8
        )
        let tabs = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWorkspaceSplitView.swift"
            ),
            encoding: .utf8
        )
        #expect(!foundation.contains("510.666"))
        #expect(!foundation.contains("32.333"))
        #expect(!foundation.contains("383 CSS-typographic-point"))
        #expect(tabs.contains("ScholiumGrid.Dimension.documentTabStripHeight"))
        #expect(tabs.contains("ScholiumGrid.Spacing.regionContentInset"))
    }

    @Test("Live Preview omits Source chrome and consumes shared document layout")
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
        let sourceModeStart = try #require(editorSource.range(of: "const sourceMode = ["))
        let sourceModeSuffix = editorSource[sourceModeStart.upperBound...]
        let sourceModeEnd = try #require(sourceModeSuffix.range(of: "];"))
        let sourceModeExtensions = editorSource[
            sourceModeStart.lowerBound..<sourceModeEnd.upperBound
        ]
        let liveModeStart = try #require(editorSource.range(of: "const livePreviewMode = ["))
        let liveModeSuffix = editorSource[liveModeStart.upperBound...]
        let liveModeEnd = try #require(liveModeSuffix.range(of: "];"))
        let liveModeExtensions = editorSource[
            liveModeStart.lowerBound..<liveModeEnd.upperBound
        ]
        #expect(sourceModeExtensions.contains("EditorView.lineWrapping"))
        #expect(sourceModeExtensions.contains("editorModeFacet.of(\"source\")"))
        #expect(sourceModeExtensions.contains("EditorView.editorAttributes.of"))
        #expect(!sourceModeExtensions.contains("defaultHighlightStyle"))
        for liveOnlyExtension in [
            "liveProjectionIndexField",
            "liveSemanticLineField",
            "liveSemanticBlockSpacingField",
            "liveFrontmatterGuardField",
            "liveBlockActivationField",
            "liveTableField",
            "liveDisplayMathField",
            "liveRawHTMLField",
            "liveCalloutField",
            "liveFootnoteField",
            "livePreview",
            "liveProjectionNavigationKeymap",
            "selectionActions.extension",
            "previewPopover.extension",
        ] {
            #expect(liveModeExtensions.contains(liveOnlyExtension))
            #expect(!sourceModeExtensions.contains(liveOnlyExtension))
            #expect(!staticExtensions.contains(liveOnlyExtension))
        }
        #expect(staticExtensions.contains("modeCompartment.of(sourceMode)"))
        #expect(editorSource.contains(#"combine: (modes) => modes[0] ?? "source""#))
        #expect(editorSource.contains(
            "modeCompartment.reconfigure(nextMode === \"livePreview\" ? livePreviewMode : sourceMode)"
        ))
        #expect(!editorSource.contains("highlightSelectionMatches()"))
        #expect(!editorSource.contains("update.focusChanged"))

        #expect(editorStyles.contains(".scholium-live-mode .cm-lineNumbers"))
        #expect(editorStyles.contains(".scholium-source-mode .cm-activeLine"))
        #expect(editorStyles.contains(".scholium-live-mode .cm-activeLine"))
        #expect(editorStyles.contains("#editor .cm-editor.scholium-live-mode .cm-scroller"))
        #expect(editorStyles.contains("#editor .cm-editor.scholium-source-mode .cm-scroller"))
        #expect(!editorSource.contains("editor.dom.classList.toggle"))
        #expect(!editorSource.contains("editor.scrollDOM.classList.toggle"))
        #expect(ScholiumWebDesignTokens.documentPresentationCSS.contains(
            "padding-block: var(--scholium-document-content-top-inset) var(--scholium-rhythm-trailing-scroll)"
        ))
        #expect(ScholiumWebDesignTokens.documentPresentationCSS.contains(
            "calc(50% - var(--scholium-document-half-line-width))"
        ))
        #expect(ScholiumWebDesignTokens.documentPresentationCSS.contains(
            "padding-block: var(--scholium-rhythm-heading-before) var(--scholium-rhythm-heading-after)"
        ))

        #expect(noteSource.contains("ScholiumDocumentPresentationConfiguration"))
        #expect(editorStyles.contains("var(--scholium-document-half-line-width)"))
        #expect(editorStyles.contains("var(--scholium-document-content-top-inset)"))
        #expect(editorStyles.contains("var(--scholium-document-text-scale)"))
        #expect(ScholiumDocumentPresentationConfiguration(textScale: 1).css.contains(
            "@media (max-width:"
        ))
    }

    @Test("Edit vertical geometry is owned by direct CodeMirror StateFields")
    func editVerticalGeometryUsesDirectStateFields() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let editorSource = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/editor.ts"),
            encoding: .utf8
        )
        for field in [
            "liveSemanticLineField",
            "liveSemanticBlockSpacingField",
            "liveTableField",
            "liveDisplayMathField",
            "liveRawHTMLField",
            "liveCalloutField",
            "liveFootnoteField",
            "liveFrontmatterGuardField",
        ] {
            #expect(editorSource.contains("const \(field) = StateField.define"))
        }

        let buildStart = try #require(
            editorSource.range(of: "function buildLiveDecorations(")
        )
        let buildEnd = try #require(
            editorSource.range(
                of: "function replacingDecorationsInRanges(",
                range: buildStart.upperBound..<editorSource.endIndex
            )
        )
        let viewportProjection = editorSource[
            buildStart.lowerBound..<buildEnd.lowerBound
        ]
        #expect(!viewportProjection.contains("block: true"))
        #expect(!viewportProjection.contains("cm-live-semantic-gap"))
        #expect(!viewportProjection.contains("cm-live-blank-line"))
        #expect(!viewportProjection.contains("cm-live-heading-marker-line"))
        #expect(!viewportProjection.contains("cm-live-code-fence-line"))
        #expect(!editorSource.contains("cm-live-list-gap"))
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
            "Scholium/Views/ResearchActions/ResearchActionPanelView.swift": [
                "scholiumSurface(.denseEvidence)",
                "ScholiumColorRole.documentBackground",
                "scholiumForeground(.attention)",
            ],
            "Scholium/Views/Sidebar/SidebarView.swift": [
                ".background(ScholiumColorRole.navigationSurfaceBackground.color)",
                "SidebarRecommendedBibliographySection(",
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

    @Test("Search results use the editorial full-row selection treatment")
    func searchResultSelectionTreatment() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/SearchWorkspaceView.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains(".listStyle(.plain)"))
        #expect(source.contains(".listRowBackground(resultRowBackground(resultID))"))
        #expect(source.contains("ScholiumColorRole.documentBackground.color("))
        #expect(source.contains("ScholiumColorRole.accent.color("))
        #expect(source.contains(".accessibilityIdentifier(\"scholium.searchResults\")"))
        #expect(source.contains(".isSelected"))
        #expect(!source.contains("List(selection:"))
    }

    @Test("Search dismisses outside clicks without dimming the workspace")
    func searchUsesTransparentDismissalLayer() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/ContentView.swift"
            ),
            encoding: .utf8
        )
        let start = try #require(
            source.range(of: "private struct SpotlightSearchOverlay")
        )
        let suffix = source[start.lowerBound...]
        let end = try #require(suffix.range(of: "// MARK: - Loading Overlay"))
        let overlaySource = String(suffix[..<end.lowerBound])

        #expect(overlaySource.contains("Color.clear"))
        #expect(overlaySource.contains(".contentShape(Rectangle())"))
        #expect(overlaySource.contains(".onTapGesture(perform: context.dismiss)"))
        #expect(overlaySource.contains(".accessibilityAddTraits(.isModal)"))
        #expect(!overlaySource.contains(".fill("))
        #expect(!overlaySource.contains("scholiumReduceTransparency"))
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
        let end = suffix.range(of: "private func refreshIdentityState")
        let body = end.map { String(suffix[..<$0.lowerBound]) } ?? String(suffix.prefix(1_000))
        #expect(!body.contains("withAnimation"))
    }

    @Test("Two color Variables resolve the approved light, dark, and contrast roles")
    func reviewedAppearancePalettes() throws {
        #expect(ScholiumColorVariable.allCases == [.accent, .paper])
        #expect(ScholiumColorVariables.editorialCopper[.accent] == 0xA94C22)
        #expect(ScholiumColorVariables.editorialCopper[.paper] == 0xFEF8ED)

        let expectedLight: [ScholiumColorRole: UInt32] = [
            .documentBackground: 0xFEF8ED,
            .surfaceBackground: 0xF4EEE3,
            .navigationSurfaceBackground: 0xECE8E1,
            .apparatusSurfaceBackground: 0xF9F3E8,
            .raisedSurfaceBackground: 0xDDD8CF,
            .primaryText: 0x28241D,
            .secondaryText: 0x4C473E,
            .mutedText: 0x615C53,
            .separator: 0xC5C0B5,
            .accent: 0x9D4114,
            .accentHover: 0x812F02,
            .notificationHighlight: 0xAD7B3D,
            .information: 0x3D6379,
            .attention: 0x81520A,
            .destructive: 0x8D453E,
            .confirmed: 0x3E664B,
            .agentAuthorship: 0x61577C,
            .connectionNeutral: 0x6F593F,
            .connectionSupport: 0x2F675E,
            .connectionIncompatible: 0x72516A,
        ]
        let expectedDark: [ScholiumColorRole: UInt32] = [
            .documentBackground: 0x2E2921,
            .surfaceBackground: 0x3F3A31,
            .navigationSurfaceBackground: 0x383530,
            .apparatusSurfaceBackground: 0x332E26,
            .raisedSurfaceBackground: 0x4D483F,
            .primaryText: 0xF0EAE1,
            .secondaryText: 0xD0CABF,
            .mutedText: 0xBEB8AD,
            .separator: 0x7C776D,
            .accent: 0xFFA17B,
            .accentHover: 0xFEAE8E,
            .notificationHighlight: 0xDAA668,
            .information: 0x95BED6,
            .attention: 0xE3AF71,
            .destructive: 0xF6A39A,
            .confirmed: 0x99C4A6,
            .agentAuthorship: 0xBDB3DD,
            .connectionNeutral: 0xCCB396,
            .connectionSupport: 0x8CC5BA,
            .connectionIncompatible: 0xD2ADC8,
        ]
        let expectedIncreasedContrastLight: [ScholiumColorRole: UInt32] = [
            .documentBackground: 0xFEF8ED,
            .surfaceBackground: 0xF4EEE3,
            .navigationSurfaceBackground: 0xECE8E1,
            .apparatusSurfaceBackground: 0xF9F3E8,
            .raisedSurfaceBackground: 0xDDD8CF,
            .primaryText: 0x28241D,
            .secondaryText: 0x454138,
            .mutedText: 0x474239,
            .separator: 0x8B857C,
            .accent: 0x6E2B0A,
            .accentHover: 0x501A01,
            .notificationHighlight: 0x95631E,
            .information: 0x163C50,
            .attention: 0x4E3107,
            .destructive: 0x681212,
            .confirmed: 0x1A4129,
            .agentAuthorship: 0x3B3154,
            .connectionNeutral: 0x48331A,
            .connectionSupport: 0x01423A,
            .connectionIncompatible: 0x4A2C43,
        ]
        let expectedIncreasedContrastDark: [ScholiumColorRole: UInt32] = [
            .documentBackground: 0x2E2921,
            .surfaceBackground: 0x3F3A31,
            .navigationSurfaceBackground: 0x383530,
            .apparatusSurfaceBackground: 0x332E26,
            .raisedSurfaceBackground: 0x4D483F,
            .primaryText: 0xF0EAE1,
            .secondaryText: 0xEAE4D9,
            .mutedText: 0xEAE4D9,
            .separator: 0xA39E94,
            .accent: 0xFEDCCF,
            .accentHover: 0xFDDED2,
            .notificationHighlight: 0xF6BF7E,
            .information: 0xC5E8FD,
            .attention: 0xFEDFBC,
            .destructive: 0xFFDBD6,
            .confirmed: 0xC3EFD0,
            .agentAuthorship: 0xE6E0FD,
            .connectionNeutral: 0xFAE0C2,
            .connectionSupport: 0xB6F0E5,
            .connectionIncompatible: 0xFED7F4,
        ]

        for palette in [
            expectedLight,
            expectedDark,
            expectedIncreasedContrastLight,
            expectedIncreasedContrastDark,
        ] {
            #expect(Set(palette.keys) == Set(ScholiumColorRole.allCases))
        }

        let aqua = try #require(NSAppearance(named: .aqua))
        let darkAqua = try #require(NSAppearance(named: .darkAqua))
        for role in ScholiumColorRole.allCases {
            let light = try #require(expectedLight[role])
            let dark = try #require(expectedDark[role])
            let contrastLight = try #require(expectedIncreasedContrastLight[role])
            let contrastDark = try #require(expectedIncreasedContrastDark[role])
            #expect(role.resolvedRGBValue(for: aqua, increasedContrast: false) == light)
            #expect(role.resolvedRGBValue(for: darkAqua, increasedContrast: false) == dark)
            #expect(role.resolvedRGBValue(for: aqua, increasedContrast: true) == contrastLight)
            #expect(role.resolvedRGBValue(for: darkAqua, increasedContrast: true) == contrastDark)
            #expect(rgbValue(of: role.nsColor(increasedContrast: false), appearance: aqua) == light)
            #expect(rgbValue(of: role.nsColor(increasedContrast: false), appearance: darkAqua) == dark)
        }

        for (palette, declarations) in [
            (expectedLight, ScholiumWebDesignTokens.rootCSSDeclarations),
            (expectedDark, ScholiumWebDesignTokens.darkAppearanceCSSDeclarations),
            (expectedIncreasedContrastLight, ScholiumWebDesignTokens.increasedContrastCSSDeclarations),
            (expectedIncreasedContrastDark, ScholiumWebDesignTokens.darkIncreasedContrastCSSDeclarations),
        ] {
            for (role, value) in palette {
                let declaration = "\(role.cssVariableName): \(String(format: "#%06x", value));"
                #expect(declarations.contains(declaration))
            }
        }

        let foregroundRoles: [ScholiumColorRole] = [
            .primaryText, .secondaryText, .mutedText, .accent, .accentHover,
            .information, .attention, .destructive, .confirmed, .agentAuthorship,
            .connectionNeutral, .connectionSupport, .connectionIncompatible,
        ]
        let backgroundRoles: [ScholiumColorRole] = [
            .documentBackground, .surfaceBackground, .navigationSurfaceBackground,
            .apparatusSurfaceBackground, .raisedSurfaceBackground,
        ]
        for (palette, target) in [
            (expectedLight, 4.5),
            (expectedDark, 4.5),
            (expectedIncreasedContrastLight, 7.0),
            (expectedIncreasedContrastDark, 7.0),
        ] {
            for foregroundRole in foregroundRoles {
                let foreground = try #require(palette[foregroundRole])
                for backgroundRole in backgroundRoles {
                    let background = try #require(palette[backgroundRole])
                    #expect(contrastRatio(foreground, background) >= target)
                }
            }
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

    @Test("Semantic surfaces, depth, and boundaries adapt without numbered visual scales")
    func semanticSurfaceRecipeContract() {
        #expect(Set(ScholiumSurfaceRole.allCases) == Set([
            .document, .navigation, .apparatus, .floatingControl,
            .boundedPanel, .searchOverlay, .denseEvidence,
        ]))
        #expect(ScholiumSurfaceRole.navigation.colorRole == .navigationSurfaceBackground)
        #expect(ScholiumSurfaceRole.document.colorRole == .documentBackground)
        #expect(ScholiumSurfaceRole.apparatus.colorRole == .apparatusSurfaceBackground)
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

    @Test("Document grid remains renderer-aware and is shared at runtime")
    func documentGridContract() throws {
        for renderer in ScholiumDocumentRenderer.allCases {
            for widthClass in ScholiumDocumentWidthClass.allCases {
                let insets = ScholiumDocumentRhythm.contentInsets(
                    for: renderer,
                    widthClass: widthClass
                )
                #expect(insets.inline >= 0)
                #expect((0 ... 1).contains(insets.trailingViewportFraction))
            }
        }

        #expect(ScholiumDocumentRhythm.contentInsets(for: .read, widthClass: .regular).inline == 32)
        #expect(ScholiumDocumentRhythm.contentInsets(for: .livePreview, widthClass: .regular).inline == 32)
        #expect(ScholiumDocumentRhythm.contentInsets(for: .source, widthClass: .regular).inline == 40)
        #expect(ScholiumDocumentRhythm.contentInsets(for: .read, widthClass: .narrow).inline == 20)
        #expect(ScholiumDocumentRhythm.paragraphGapCSSPixels == 12)
        #expect(ScholiumDocumentRhythm.headingGapBeforeCSSPixels == 24)
        #expect(ScholiumDocumentRhythm.headingGapAfterCSSPixels == 8)

        let sharedCSS = ScholiumWebDesignTokens.documentPresentationCSS
        let editorHTML = try #require(MarkdownEditorWebView.editorHTML)
        for declaration in ScholiumWebDesignTokens.rhythmCSSDeclarations.split(separator: "\n") {
            let normalized = declaration.trimmingCharacters(in: .whitespaces)
            #expect(sharedCSS.contains(normalized))
        }
        #expect(editorHTML.contains(sharedCSS))
        #expect(SafeMarkdownReadWebView.Coordinator.baseCSS.contains(sharedCSS))
        #expect(sharedCSS.contains("--scholium-document-line-width: 72ch"))
        #expect(sharedCSS.contains("--scholium-document-half-line-width: 36ch"))
        let sharedDocumentRoot = try #require(
            sharedCSS.components(
                separatedBy: ".cm-editor.scholium-source-mode .cm-content"
            ).first
        )
        #expect(!sharedDocumentRoot.contains("max-inline-size:"))
        #expect(sharedCSS.contains("inline-size: 100%;"))
        #expect(sharedCSS.contains("calc(50% - var(--scholium-document-half-line-width))"))
        #expect(sharedCSS.contains(".cm-editor.scholium-source-mode .cm-content"))
        let presentationCSS = ScholiumDocumentPresentationConfiguration(textScale: 1).css
        #expect(presentationCSS.contains("var(--scholium-rhythm-inline-narrow)"))
        #expect(presentationCSS.contains("var(--scholium-document-half-line-width)"))
        #expect(presentationCSS.contains(".cm-editor.scholium-live-mode .cm-content"))
    }

    @Test("Read and Live Preview inject one protected callout presentation")
    func readModeInjectsProtectedCalloutPresentation() {
        let css = SafeMarkdownReadWebView.Coordinator.baseCSS
        let calloutCSS = ScholiumCalloutStyles.css
        let editorHTML = MarkdownEditorWebView.editorHTML ?? ""

        #expect(css.contains(".scholium-callout"))
        #expect(!css.contains("(ScholiumCalloutStyles.css)"))
        #expect(css.contains(calloutCSS))
        #expect(editorHTML.contains(calloutCSS))
        #expect(editorHTML.contains(".cm-live-callout-widget"))
        #expect(calloutCSS.contains(".scholium-callout-role,\n.scholium-callout-title"))
        #expect(calloutCSS.contains(".scholium-callout-role {\n  position: absolute;"))
        #expect(!calloutCSS.contains(".cm-live-callout-role"))
        #expect(calloutCSS.contains("--scholium-callout-surface: color-mix("))
        #expect(calloutCSS.contains("background: transparent;"))
        #expect(calloutCSS.contains(".scholium-callout-cite,\n.scholium-callout-flag {"))
        #expect(calloutCSS.contains("padding-block: .72rem .8rem;"))
        #expect(calloutCSS.contains("background: var(--scholium-callout-surface);"))
        #expect(calloutCSS.contains(".scholium-callout-flag {\n  background: var(--scholium-callout-surface-emphasis);"))
        #expect(calloutCSS.contains("--scholium-callout-connect-content-indent: 1.1em;"))
        #expect(calloutCSS.contains(".scholium-callout-connect .scholium-callout-body {\n  margin-top: .34rem;"))
        #expect(calloutCSS.contains("color: var(--scholium-callout-secondary-ink);"))
        #expect(calloutCSS.contains(".scholium-callout-connect .scholium-callout-content > ul > li + li {"))
        #expect(!calloutCSS.contains(".scholium-callout-connect .scholium-callout-content > ul > li::before"))
        #expect(!calloutCSS.contains("content: \"—\";"))
        #expect(!calloutCSS.contains("border-inline-start:"))
        #expect(calloutCSS.contains(".scholium-callout-orient > header .scholium-callout-heading,"))
        #expect(calloutCSS.contains("aside.scholium-callout-state > header,"))
        #expect(calloutCSS.contains("aside.scholium-callout-state .scholium-callout-heading {\n  display: inline;"))
        #expect(calloutCSS.contains("aside.scholium-callout-illustrate {\n  display: grid;"))
        #expect(calloutCSS.contains("aside.scholium-callout-quote > header {\n  order: 2;"))
        #expect(calloutCSS.contains(".scholium-callout-quote .scholium-callout-quotation,"))
        #expect(calloutCSS.contains("background: radial-gradient(circle,"))
        #expect(!calloutCSS.contains("linear-gradient("))
        #expect(!calloutCSS.contains("clip-path: polygon("))
        #expect(!calloutCSS.contains("border-radius: 50%"))
        #expect(!calloutCSS.contains("max-width: 72ch"))
        #expect(calloutCSS.contains("text-align: start;"))
        #expect(!calloutCSS.contains("text-align: justify;"))
        #expect(!calloutCSS.contains("text-align-last:"))
    }

    @Test("Ordinary quotation uses the semantic Accent in Read and Live Preview")
    func ordinaryQuotationUsesSemanticAccent() throws {
        let sharedCSS = ScholiumWebDesignTokens.documentPresentationCSS
        let editorHTML = MarkdownEditorWebView.editorHTML ?? ""
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let editorCSS = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Resources/Editor/editor.css"
            ),
            encoding: .utf8
        )

        #expect(sharedCSS.contains(".scholium-document blockquote,"))
        #expect(sharedCSS.contains(".cm-editor.scholium-live-mode .cm-live-quote"))
        #expect(sharedCSS.contains(
            "border-inline-start: 3px solid var(--scholium-color-accent);"
        ))
        #expect(!sharedCSS.contains(
            "color-mix(in srgb, AccentColor"
        ))
        #expect(editorHTML.contains(sharedCSS))
        #expect(editorCSS.contains(
            "#editor .cm-editor.scholium-live-mode .cm-line.cm-live-quote"
        ))
        #expect(editorCSS.contains(
            "padding-inline-start: var(--scholium-rhythm-quote-inset);"
        ))
    }

    @Test("Edit H1 owns the document-title tier without a cached body-line condition")
    func liveH1OwnsDocumentTitleTier() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let editorSource = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/editor.ts"),
            encoding: .utf8
        )

        #expect(editorSource.contains(
            #"if (heading.headingLevel === 1) classes.add("cm-live-document-title");"#
        ))
        #expect(!editorSource.contains(
            "const isDocumentTitle = headingLevel === 1 && line.from === firstBodyLineFrom;"
        ))
        #expect(ScholiumWebDesignTokens.documentPresentationCSS.contains(
            "text-align: start;"
        ))
        #expect(ScholiumWebDesignTokens.documentPresentationCSS.contains(
            "text-align: center;"
        ))
        #expect(ScholiumWebDesignTokens.documentPresentationCSS.contains(
            ".scholium-live-mode .cm-live-document-title,"
        ))
        #expect(ScholiumWebDesignTokens.documentPresentationCSS.contains(
            ".scholium-live-mode .cm-live-h1 {"
        ))
    }

    @Test("Editor reveal settles hidden WebKit geometry before scroll restoration")
    func editorRevealOwnsAStyleBarrier() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let editorSource = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/editor.ts"),
            encoding: .utf8
        )
        let scrollSource = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/scroll-coordinator.ts"),
            encoding: .utf8
        )
        let fractionOperation = try #require(
            scrollSource.range(of: "function setFraction(requestedFraction: number) {")
        )
        let fractionTail = scrollSource[fractionOperation.lowerBound...]
        let fractionBarrier = try #require(fractionTail.range(
            of: "options.flushPresentationGeometry();"
        ))
        let fractionExtent = try #require(fractionTail.range(
            of: "const extent = Math.max(0, editor.scrollDOM.scrollHeight"
        ))
        #expect(fractionBarrier.lowerBound < fractionExtent.lowerBound)

        let anchorOperation = try #require(
            scrollSource.range(of: "function setAnchor(anchor: EditorScrollAnchor) {")
        )
        let anchorTail = scrollSource[anchorOperation.lowerBound...]
        let anchorBarrier = try #require(anchorTail.range(
            of: "options.flushPresentationGeometry();"
        ))
        let anchorGeometry = try #require(anchorTail.range(of: "editor.lineBlockAt(blockProbe)"))
        #expect(anchorBarrier.lowerBound < anchorGeometry.lowerBound)
        #expect(editorSource.contains(
            "flushPresentationGeometry: flushPresentationStyleAndGeometry"
        ))
        #expect(editorSource.contains("getComputedStyle(element).fontSize"))
        #expect(editorSource.contains("element.getBoundingClientRect().width"))
        #expect(!editorSource.contains("SCHOLIUM_UI_TEST_EDITOR_PRESENTATION_MARKER"))
    }


    @Test("App-owned Annotation and legacy archives stay absent after clean cutover")
    func removedAnnotationAndLegacyArchivesDoNotRegress() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/NoteContentView.swift"
            ),
            encoding: .utf8
        )
        let editorSource = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/editor.ts"),
            encoding: .utf8
        )
        let readSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/SafeMarkdownReadWebView.swift"
            ),
            encoding: .utf8
        )
        #expect(!source.contains("PageAnnotation"))
        #expect(!source.contains("AnnotationRecord"))
        #expect(!editorSource.contains("setPageAnnotations"))
        #expect(!editorSource.contains("PageAnnotationMarginWidget"))
        #expect(!readSource.contains("applyPageAnnotations"))
        #expect(!source.contains("Write Activities"))
        #expect(!source.contains("Earlier Review Archive"))
        #expect(!source.contains("Earlier Dialogue Archive"))
        #expect(!source.contains("entry.functionSnapshot == nil"))
    }

    @Test("Read and Live Preview share one offline mathematics runtime and font set")
    func sharedMathematicsRuntime() throws {
        let editorHTML = try #require(MarkdownEditorWebView.editorHTML)
        let css = ScholiumMathAssets.css

        #expect(ScholiumMathAssets.runtimeJavaScript.contains("scholiumMath"))
        #expect(css.contains(".katex"))
        #expect(css.contains("data:font/woff2;base64,"))
        #expect(!css.contains("url(fonts/"))
        #expect(css.contains(".scholium-math-display"))
        #expect(css.contains("grid-template-columns: minmax(2.5em, 1fr) max-content minmax(2.5em, 1fr)"))
        #expect(css.contains("min-inline-size: max-content;"))
        #expect(!css.contains("grid-template-columns: minmax(2.5em, 1fr) minmax(0, auto)"))
        #expect(css.contains("counter-increment: scholium-equation"))
        #expect(css.contains("content: \"(\" counter(scholium-equation) \")\""))
        #expect(css.contains(".scholium-math-display .katex { font-style: italic; }"))
        #expect(editorHTML.contains(css))
    }

    @Test("Structured Appearance CSS maps the exported typography and callout profile")
    func structuredAppearanceCSS() {
        let profile = DocumentAppearanceProfile(name: "Custom")
        let css = DocumentAppearanceStyles.css(for: profile)

        #expect(css.contains("--scholium-document-prose-font-size: 12pt"))
        #expect(css.contains("--scholium-rhythm-prose-line-height: 2"))
        #expect(css.contains("--scholium-appearance-title-before: 0em"))
        #expect(css.contains("font-size: calc(var(--scholium-document-prose-font-size) * var(--scholium-document-text-scale-factor))"))
        #expect(css.contains("letter-spacing: 0.02em"))
        #expect(css.contains("text-align: justify"))
        #expect(css.contains("margin-inline-start: 3em"))
        #expect(css.contains("margin-inline-end: 3em"))
        #expect(css.contains(".scholium-callout-connect"))
        #expect(css.contains("--scholium-callout-connect-content-indent: 1.1em"))
        #expect(css.contains("grid-template-columns: 6.5em minmax(0, 1fr)"))
        #expect(css.contains("details.scholium-callout > .scholium-callout-body"))
        #expect(css.contains("--scholium-document-line-width: 72ch"))
        #expect(css.contains("--scholium-document-half-line-width: 36ch"))
        #expect(!css.contains("readable-measure"))
        #expect(!css.contains("max-inline-size"))
    }

    @Test("Read and Live Preview share semantic table presentation")
    func sharedTablePresentation() throws {
        let editorHTML = try #require(MarkdownEditorWebView.editorHTML)
        let css = ScholiumTableStyles.css

        #expect(css.contains(".scholium-table-scroll"))
        #expect(css.contains(".scholium-table th"))
        #expect(css.contains("--scholium-table-cell-inline-inset"))
        #expect(css.contains("overflow-x: auto"))
        #expect(editorHTML.contains(css))
        #expect(SafeMarkdownReadWebView.Coordinator.documentHTML(
            body: "<div class=\"scholium-table-scroll\"></div>",
            source: "",
            documentID: "Table.md",
            fingerprint: DocumentFingerprint(content: "").sha256,
            commentEnabled: false,
            selectionEnabled: false,
            linkPreviews: [],
            presentationCSS: "",
            userCSS: ""
        ).contains(css))
    }

    @Test("Read and Live Preview share semantic footnote presentation")
    func sharedFootnotePresentation() throws {
        let editorHTML = try #require(MarkdownEditorWebView.editorHTML)
        let css = ScholiumFootnoteStyles.css

        #expect(css.contains(".footnote-reference"))
        #expect(css.contains(".footnotes"))
        #expect(css.contains(".cm-live-footnotes-widget"))
        #expect(css.contains("padding-inline-end"))
        #expect(editorHTML.contains(css))
        #expect(SafeMarkdownReadWebView.Coordinator.documentHTML(
            body: "<section class=\"footnotes\"></section>",
            source: "",
            documentID: "Footnotes.md",
            fingerprint: DocumentFingerprint(content: "").sha256,
            commentEnabled: false,
            selectionEnabled: false,
            linkPreviews: [],
            presentationCSS: "",
            userCSS: ""
        ).contains(css))
    }

    @Test("Review owns footnote preview and navigation while Edit owns exact-source activation")
    func footnoteInteractionStaysWithinEachModeBoundary() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let editorSource = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/editor.ts"),
            encoding: .utf8
        )
        let referenceStart = try #require(editorSource.range(of: "class FootnoteReferenceWidget"))
        let referenceEnd = try #require(
            editorSource.range(
                of: "const footnoteSectionPresentations",
                range: referenceStart.upperBound..<editorSource.endIndex
            )
        )
        let sectionStart = try #require(editorSource.range(of: "class FootnoteSectionWidget"))
        let sectionEnd = try #require(
            editorSource.range(
                of: "interface LiveFootnoteProjectionState",
                range: sectionStart.upperBound..<editorSource.endIndex
            )
        )
        let editReference = String(editorSource[referenceStart.lowerBound..<referenceEnd.lowerBound])
        let editSection = String(editorSource[sectionStart.lowerBound..<sectionEnd.lowerBound])
        let readHTML = SafeMarkdownReadWebView.Coordinator.documentHTML(
            body: #"<p>Claim<button class="footnote-reference" data-footnote="1">1</button>.</p><section class="footnotes"><ol><li data-footnote="1"><div class="footnote-content">Basis.</div><button class="footnote-return">Return</button></li></ol></section>"#,
            source: "Claim[^one].\n\n[^one]: Basis.\n",
            documentID: "Footnotes.md",
            fingerprint: DocumentFingerprint(content: "Claim[^one].\n\n[^one]: Basis.\n").sha256,
            commentEnabled: false,
            selectionEnabled: true,
            linkPreviews: [],
            presentationCSS: "",
            userCSS: ""
        )

        #expect(!editReference.contains("addEventListener(\"mousedown\""))
        #expect(editSection.contains("addEventListener(\"mousedown\""))
        #expect(editSection.contains("beginProjectedPointerSelection"))
        #expect(editSection.contains("definition.contentFrom"))
        #expect(!editSection.contains("showFootnotePopover"))
        #expect(!editSection.contains("footnote-return"))
        #expect(editReference.contains("ignoreEvent() { return false; }"))
        #expect(editSection.contains("ignoreEvent() { return false; }"))
        #expect(readHTML.contains("showFootnotePopover"))
        #expect(readHTML.contains("event.target.closest('.footnote-reference')"))
        #expect(readHTML.contains("event.target.closest('.footnote-return')"))
    }

    @Test("Read and Live Preview share the bounded preview presentation")
    func sharedPreviewPresentation() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let previewControllerSource = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/preview-popover.ts"),
            encoding: .utf8
        )
        let editorHTML = try #require(MarkdownEditorWebView.editorHTML)
        let css = ScholiumPreviewStyles.css
        #expect(css.contains(".scholium-preview-popover"))
        #expect(css.contains("prefers-contrast: more"))
        #expect(css.contains("prefers-reduced-transparency: reduce"))
        #expect(editorHTML.contains(css))

        let preview = DocumentLinkPreview(
            sourceSpan: SourceSpan(
                utf8LowerBound: 0,
                utf8UpperBound: 10,
                utf16LowerBound: 0,
                utf16UpperBound: 10,
                start: SourcePosition(line: 1, utf8Column: 1, utf16Column: 1),
                end: SourcePosition(line: 1, utf8Column: 11, utf16Column: 11)
            ),
            target: VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Target.md"),
            targetFingerprint: DocumentFingerprint(content: "Target body"),
            title: "Target note",
            relationship: .supports,
            fragment: "Claim",
            htmlBody: "<p>Target body</p>"
        )
        let readHTML = SafeMarkdownReadWebView.Coordinator.documentHTML(
            body: #"<a class="wiki-link" data-source-utf16-start="0" data-source-utf16-end="10">Target</a>"#,
            source: "[[Target]]",
            documentID: "Source.md",
            fingerprint: DocumentFingerprint(content: "[[Target]]").sha256,
            commentEnabled: false,
            selectionEnabled: false,
            linkPreviews: [preview],
            presentationCSS: "",
            userCSS: ""
        )
        #expect(readHTML.contains(css))
        #expect(readHTML.contains("previewByRange"))
        #expect(readHTML.contains("showLinkPopover"))
        #expect(readHTML.contains("showFootnotePopover"))
        #expect(previewControllerSource.contains("ViewPlugin.define"))
        #expect(previewControllerSource.contains("document.removeEventListener"))
        #expect(previewControllerSource.contains("root?.remove()"))
        #expect(!previewControllerSource.contains("mode()"))
    }

    @Test("Review alone offers a direct line-only Comment composer")
    func directLineCommentComposer() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let editorSource = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/editor.ts"),
            encoding: .utf8
        )
        let selectionActionsSource = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/selection-actions.ts"),
            encoding: .utf8
        )
        let editorMenuSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/MarkdownEditorNativeWebView.swift"
            ),
            encoding: .utf8
        )
        let readHTML = SafeMarkdownReadWebView.Coordinator.documentHTML(
            body: #"<p data-source-line="2">A bounded claim.</p>"#,
            source: "# Topic\nA bounded claim.\n",
            documentID: "Topic.md",
            fingerprint: DocumentFingerprint(content: "# Topic\nA bounded claim.\n").sha256,
            commentEnabled: true,
            selectionEnabled: true,
            linkPreviews: [],
            presentationCSS: "",
            userCSS: ""
        )

        #expect(readHTML.contains("Return saves. Shift-Return inserts a line. Escape cancels."))
        #expect(readHTML.contains("commentSubmitted"))
        #expect(readHTML.contains("Comment for"))
        #expect(readHTML.contains(#"class="scholium-selection-actions""#))
        #expect(readHTML.contains(#"class="scholium-selection-toolbar""#))
        #expect(readHTML.contains("ResolveCommentSubmission"))
        #expect(readHTML.contains("Your Comment is still here"))
        #expect(readHTML.contains("TextEncoder"))
        #expect(readHTML.contains("makeRequestID"))
        #expect(readHTML.contains("globalThis.crypto.getRandomValues"))
        #expect(readHTML.contains("commentSelectionRange = range.cloneRange()"))
        #expect(readHTML.contains("selection.addRange(commentSelectionRange)"))
        #expect(!readHTML.contains("Copy and Open Agent App"))
        #expect(!readHTML.contains("Copy Only"))
        #expect(readHTML.contains("startLine"))
        #expect(readHTML.contains("endLine"))
        #expect(!readHTML.contains("quotation:"))
        #expect(!readHTML.contains("utf16Range"))
        #expect(selectionActionsSource.contains("view.composing || !view.hasFocus"))
        #expect(selectionActionsSource.contains("ViewPlugin.define"))
        #expect(selectionActionsSource.contains("destroy()"))
        #expect(selectionActionsSource.contains("root?.remove()"))
        #expect(!selectionActionsSource.contains("mode()"))
        #expect(selectionActionsSource.contains(
            #"addButton(commandBar, "B", "Bold", "bold")"#
        ))
        #expect(selectionActionsSource.contains(#"root.className = "scholium-selection-actions""#))
        #expect(ScholiumWebDesignTokens.documentPresentationCSS.contains(
            ".scholium-selection-actions"
        ))
        #expect(ScholiumWebDesignTokens.documentPresentationCSS.contains(
            "background: var(--scholium-color-surface-background)"
        ))
        #expect(ScholiumWebDesignTokens.documentPresentationCSS.contains(
            "border: 1px solid var(--scholium-color-accent)"
        ))
        #expect(!ScholiumWebDesignTokens.documentPresentationCSS.contains(
            ".scholium-selection-actions {\n      backdrop-filter"
        ))
        #expect(!editorSource.contains("commentSubmitted"))
        #expect(!editorSource.contains("showCommentComposer"))
        #expect(!selectionActionsSource.contains(#"addButton("Comment", "Comment""#))
        #expect(!editorMenuSource.contains("Comment on Selection"))
        #expect(!editorMenuSource.contains("commentSubmitted"))
        #expect(!editorMenuSource.contains("onRequestComment"))
        #expect(!editorMenuSource.contains(#"ScholiumL10n.string("Bold"), MarkdownEditorCommand.bold"#))
        #expect(editorMenuSource.contains("genericPreviewTitles"))
        #expect(editorMenuSource.contains(#""Show Preview""#))
        #expect(editorMenuSource.contains(
            #"ScholiumL10n.string("Show Preview")"#
        ))
        #expect(!editorMenuSource.contains("String(describing: item.action)"))
        #expect(!editorMenuSource.contains("scholium.editor.preview"))
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

        #expect(ScholiumColorRole.connectionSupport.resolvedRGBValue(
            for: aqua,
            increasedContrast: false
        ) == 0x2F675E)
        #expect(ScholiumColorRole.connectionSupport.resolvedRGBValue(
            for: darkAqua,
            increasedContrast: false
        ) == 0x8CC5BA)
        #expect(ScholiumColorRole.connectionSupport.resolvedRGBValue(
            for: aqua,
            increasedContrast: true
        ) == 0x01423A)
        #expect(ScholiumColorRole.connectionSupport.resolvedRGBValue(
            for: darkAqua,
            increasedContrast: true
        ) == 0xB6F0E5)

        #expect(ScholiumColorRole.connectionIncompatible.resolvedRGBValue(
            for: aqua,
            increasedContrast: false
        ) == 0x72516A)
        #expect(ScholiumColorRole.connectionIncompatible.resolvedRGBValue(
            for: darkAqua,
            increasedContrast: false
        ) == 0xD2ADC8)
        #expect(ScholiumColorRole.connectionIncompatible.resolvedRGBValue(
            for: aqua,
            increasedContrast: true
        ) == 0x4A2C43)
        #expect(ScholiumColorRole.connectionIncompatible.resolvedRGBValue(
            for: darkAqua,
            increasedContrast: true
        ) == 0xFED7F4)

        #expect(ScholiumWebDesignTokens.increasedContrastCSSDeclarations.contains("#01423a"))
        #expect(ScholiumWebDesignTokens.increasedContrastCSSDeclarations.contains("#4a2c43"))
        #expect(ScholiumWebDesignTokens.darkIncreasedContrastCSSDeclarations.contains("#b6f0e5"))
        #expect(ScholiumWebDesignTokens.darkIncreasedContrastCSSDeclarations.contains("#fed7f4"))
        for value in ["#01423a", "#4a2c43", "#b6f0e5", "#fed7f4"] {
            #expect(css.contains(value))
        }
    }

    @Test("The live Connections inspector uses one semantic presentation")
    func sharedConnectionPresentation() throws {
        let expected: [
            (ScholiumConnectionPresentation, String, ScholiumConnectionGlyphKind)
        ] = [
            (.supports, "Supports", .supports),
            (.supportsThisNote, "Supports This Note", .supportedBy),
            (.opposes, "Opposes", .opposes),
            (.opposesThisNote, "Opposes This Note", .opposedBy),
            (.incompatible, "Incompatible", .incompatible),
            (.neutral, "Related", .neutral),
        ]
        for (presentation, title, glyphKind) in expected {
            #expect(presentation.title == title)
            #expect(presentation.glyphKind == glyphKind)
        }

        #expect(ScholiumConnectionPresentation(
            vectorKind: .supports,
            currentIsSource: true
        ) == .supports)
        #expect(ScholiumConnectionPresentation(
            vectorKind: .supports,
            currentIsSource: false
        ) == .supportsThisNote)
        #expect(ScholiumConnectionPresentation(
            vectorKind: .opposes,
            currentIsSource: true
        ) == .opposes)
        #expect(ScholiumConnectionPresentation(
            vectorKind: .opposes,
            currentIsSource: false
        ) == .opposesThisNote)
        #expect(ScholiumConnectionPresentation(
            vectorKind: .incompatible,
            currentIsSource: true
        ) == .incompatible)
        #expect(ScholiumConnectionPresentation(
            vectorKind: .incompatible,
            currentIsSource: false
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
