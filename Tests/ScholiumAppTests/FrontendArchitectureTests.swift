import AppKit
import Foundation
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Frontend architecture")
@MainActor
struct FrontendArchitectureTests {
    @Test("Window feedback uses content-fitting edge overlays without Document reflow")
    func windowFeedbackUsesConsequenceSpecificPlacement() throws {
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
        let settingsSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/WorkspaceSettingsView.swift"
            ),
            encoding: .utf8
        )
        let componentsSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumComponents.swift"
            ),
            encoding: .utf8
        )
        let windowManagementSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWindowManagement.swift"
            ),
            encoding: .utf8
        )
        let designSystemSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Foundation/ScholiumDesignSystem.swift"
            ),
            encoding: .utf8
        )
        let documentStart = try #require(source.range(of: "} document: {"))
        let apparatusStart = try #require(
            source.range(
                of: "} apparatus: {",
                range: documentStart.upperBound..<source.endIndex
            )
        )
        let documentRegion = source[
            documentStart.lowerBound..<apparatusStart.lowerBound
        ]

        #expect(documentRegion.contains("detailRegion"))
        #expect(source.contains("ScholiumWindowTopOverlayHost("))
        #expect(source.contains(".overlay(alignment: .bottom)"))
        #expect(source.contains("windowTopNotificationOverlay"))
        #expect(source.contains("shellState.transientFeedbackItems.first"))
        #expect(source.contains("shellState.persistentFeedbackItems.first"))
        #expect(source.contains("ScholiumMetrics.Notice.transientToastMaximumWidth"))
        #expect(source.contains("ScholiumMetrics.Notice.windowFeedbackMaximumWidth"))
        #expect(source.contains("WindowFeedbackItem("))
        #expect(source.contains("ScholiumOperationFeedback("))
        #expect(settingsSource.contains("WorkspaceSettingsFeedbackItem("))
        #expect(settingsSource.contains("ScholiumWindowTopOverlayHost("))
        #expect(settingsSource.contains(
            "topInset: ScholiumGrid.Spacing.sectionSeparation"
        ))
        #expect(settingsSource.contains("settingsModel.feedbackItems.first"))
        #expect(settingsSource.contains("ScholiumOperationFeedback("))
        #expect(componentsSource.contains("struct ScholiumOperationFeedback: View"))
        #expect(componentsSource.contains("struct ScholiumNotificationBanner<Actions: View>"))
        #expect(componentsSource.contains("private var transientToast: some View"))
        #expect(componentsSource.contains("private var persistentNotice: some View"))
        #expect(componentsSource.contains(".lineLimit(1)"))
        let toastStart = try #require(
            componentsSource.range(of: "private var transientToast: some View")
        )
        let persistentNoticeStart = try #require(
            componentsSource.range(
                of: "private var persistentNotice: some View",
                range: toastStart.upperBound..<componentsSource.endIndex
            )
        )
        let toastSource = componentsSource[
            toastStart.lowerBound..<persistentNoticeStart.lowerBound
        ]
        #expect(!toastSource.contains("Button(action: dismiss)"))
        #expect(
            componentsSource.contains(
                ".scholiumContentFittingWidth(maximumWidth: maximumWidth)"
            )
        )
        #expect(
            designSystemSource.contains(
                "ProposedViewSize(width: availableWidth, height: nil)"
            )
        )
        #expect(componentsSource.contains("Button(\"Dismiss\", action: dismiss)"))
        #expect(componentsSource.contains(".keyboardShortcut(.cancelAction)"))
        #expect(componentsSource.contains("guard kind.dismissesAutomatically"))
        #expect(windowManagementSource.contains("fittingSizeDidChange"))
        #expect(
            windowManagementSource.contains(
                "while let superview = frameView.superview"
            )
        )
        #expect(!windowManagementSource.contains("fullWidthTitlebarView"))
        #expect(!source.contains("WindowFeedbackStack"))
        #expect(!settingsSource.contains("WorkspaceSettingsFeedbackStack"))
        #expect(source.contains("refreshStatusNotice"))
        #expect(
            source.components(
                separatedBy: ".accessibilityIdentifier(\"scholium.refreshStatus\")"
            ).count == 2
        )
    }

    @Test("Window feedback queues distinct notices and keeps warnings persistent")
    func windowFeedbackQueue() throws {
        let shell = WindowShellState()

        shell.presentFeedback("Saved", kind: .confirmation)
        let confirmation = try #require(shell.feedbackItems.first)
        #expect(confirmation.kind.dismissesAutomatically)

        shell.presentFeedback("Recovery required", kind: .warning)
        let warning = try #require(shell.feedbackItems.last)
        #expect(shell.feedbackItems.map(\.message) == ["Saved", "Recovery required"])
        #expect(shell.transientFeedbackItems == [confirmation])
        #expect(shell.persistentFeedbackItems == [warning])
        #expect(!warning.kind.dismissesAutomatically)

        shell.dismissFeedback(id: confirmation.id)
        #expect(shell.feedbackItems == [warning])

        shell.resetWorkspaceSessions()
        #expect(shell.feedbackItems.isEmpty)
    }

    @Test("Research Action availability reconverges after progressive loading")
    func researchActionsRefreshWhenWorkspaceBecomesComplete() throws {
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

        #expect(source.contains(
            "let snapshotPhase: WorkspaceSnapshotPhase?"
        ))
        #expect(source.contains(
            "snapshotPhase: workspaceProjectionController.snapshotPhase"
        ))
        #expect(source.contains(
            ".task(id: researchActionAvailabilityRefreshIdentity)"
        ))
        #expect(!source.contains(
            ".task(id: appState.currentResearchActionTarget)"
        ))
    }

    @Test("Packaged performance prepares its UI driver before the cooled gate")
    func performanceGateUsesPreparedDriver() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runner = try String(
            contentsOf: repository.appendingPathComponent(
                "Tools/Scripts/run-performance-benchmarks.sh"
            ),
            encoding: .utf8
        )
        let preparer = try String(
            contentsOf: repository.appendingPathComponent(
                "Tools/Scripts/prepare-performance-driver.sh"
            ),
            encoding: .utf8
        )
        let summarizer = try String(
            contentsOf: repository.appendingPathComponent(
                "Tools/Scripts/summarize-performance-results.py"
            ),
            encoding: .utf8
        )

        #expect(runner.contains(
            "A product gate requires --prepared-driver from prepare-performance-driver.sh."
        ))
        #expect(runner.contains("if [[ -z \"${PREPARED_DRIVER}\" ]]; then"))
        #expect(runner.contains("scholium-performance-driver-v1"))
        #expect(runner.contains("plutil -extract git_commit"))
        #expect(runner.contains("plutil -extract xcode_build"))
        #expect(preparer.contains("build-for-testing"))
        #expect(preparer.contains("source_clean -bool true"))
        #expect(preparer.contains("Cool the reference machine before invoking"))
        #expect(runner.contains("testRDF1HundredThousandCJKCorrectness"))
        #expect(runner.contains("SCHOLIUM_PERFORMANCE_CJK_RESULTS_PATH"))
        #expect(runner.contains("APP_RESULT_ROOT=\"${APP_SCRATCH}/raw\""))
        #expect(runner.contains("cp \"${driver_results}\" \"${results}\""))
        #expect(runner.contains("cp \"${cjk_driver_results}\" \"${cjk_results}\""))
        #expect(runner.contains("20...50 retained latency samples"))
        #expect(runner.contains("30...60 memory transitions"))
        #expect(runner.contains("FULL_GATE_RUN=0"))
        #expect(!runner.contains("A product gate is fixed at 5 warm-ups"))
        #expect(summarizer.contains("predeclared_before_measurement"))
        #expect(summarizer.contains(
            "return (\"passed\" if not missing else \"incomplete\"), missing"
        ))
    }

    @Test("VoiceOver service automation never claims human acceptance")
    func voiceOverServiceAutomationKeepsItsEvidenceBoundary() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let journey = try String(
            contentsOf: repository.appendingPathComponent(
                "UITests/ScholiumUITests+WorkspaceResearch.swift"
            ),
            encoding: .utf8
        )
        let support = try String(
            contentsOf: repository.appendingPathComponent(
                "UITests/ScholiumUITests+Support.swift"
            ),
            encoding: .utf8
        )

        #expect(journey.contains(
            "func testResearchActionsVoiceOverServiceSpeechOrder()"
        ))
        #expect(journey.contains(
            "VoiceOver-service automation is opt-in engineering evidence, not human acceptance"
        ))
        #expect(!journey.contains(
            "Real VoiceOver traversal is an explicit acceptance journey"
        ))
        #expect(support.contains(
            "testResearchActionsVoiceOverServiceSpeechOrder"
        ))
    }

    @Test("Fixture launch opens the requested Vault once before its document")
    func fixtureLaunchDoesNotReopenConfiguredVault() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent("Scholium/App/ScholiumApp.swift"),
            encoding: .utf8
        )
        let restore = try #require(source.range(of: "func restoreWorkspaceIfNeeded() async"))
        let fixtureEnd = try #require(source.range(
            of: "await windowWorkspaceController.refreshRegistrations()\n        await refreshWorkspaceAssignment()",
            range: restore.upperBound..<source.endIndex
        ))
        let fixtureBranch = source[restore.lowerBound..<fixtureEnd.lowerBound]

        #expect(fixtureBranch.contains("try await configureTriptych("))
        #expect(fixtureBranch.contains(
            "await windowWorkspaceController.refreshRegistrations()"
        ))
        #expect(fixtureBranch.contains("shellState.selectWorkspace(requestedInitialWorkspaceSlot)"))
        #expect(fixtureBranch.contains("try await openRegisteredVault(openingVault)"))
        #expect(fixtureBranch.contains("openRequestedTestNoteIfNeeded()"))
        #expect(!fixtureBranch.contains("try await openWorkspaceVault("))
    }

    @Test("Initial Vault publication reuses its runtime-bound accepted snapshot")
    func initialVaultPublicationReusesAcceptedSnapshot() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent("Scholium/App/ScholiumApp.swift"),
            encoding: .utf8
        )
        let loadVault = try #require(source.range(of: "private func loadVault("))
        let restore = try #require(source.range(
            of: "func restoreWorkspaceIfNeeded() async",
            range: loadVault.upperBound..<source.endIndex
        ))
        let initialPublication = source[loadVault.lowerBound..<restore.lowerBound]

        #expect(initialPublication.contains("workspaceProjectionController.activate("))
        #expect(initialPublication.contains("applyWorkspaceProjectionCommit(commit)"))
        #expect(initialPublication.contains("windowWorkspaceController.activeSession("))
        #expect(initialPublication.contains("let workspaceSnapshot = session.snapshot"))
        #expect(!initialPublication.contains("workspaceStore.snapshot("))
        #expect(!initialPublication.contains("workspaceStore.workspaceCapabilities("))
        #expect(initialPublication.contains("markVaultConfigurationReady()"))
        #expect(initialPublication.contains("markWarmLibraryProjectionReady()"))
        #expect(initialPublication.contains("isLoading = false"))
        #expect(!initialPublication.contains("documentController.workspaceSnapshots()"))
        #expect(!initialPublication.contains("researchController.researchSnapshot()"))
        #expect(!initialPublication.contains("await refreshWindowProjection()"))

        let adoptionStart = try #require(source.range(
            of: "private func adoptWorkspaceActivation("
        ))
        let adoptionEnd = try #require(source.range(
            of: "var currentWorkspaceSlot:",
            range: adoptionStart.upperBound..<source.endIndex
        ))
        let adoption = source[adoptionStart.lowerBound..<adoptionEnd.lowerBound]
        #expect(adoption.contains(
            "if currentRegisteredVault != nil {\n"
                + "            PerformanceProbe.shared.markWarmLibraryProjectionReady()"
        ))

        let storeSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Services/WindowSession.swift"
            ),
            encoding: .utf8
        )
        let acceptedSnapshot = try #require(storeSource.range(
            of: "func snapshot(\n        for runtimeIdentity: TriptychRuntimeIdentity"
        ))
        let registration = try #require(storeSource.range(
            of: "func registerEditorFlush(",
            range: acceptedSnapshot.upperBound..<storeSource.endIndex
        ))
        let implementation = storeSource[acceptedSnapshot.lowerBound..<registration.lowerBound]
        #expect(implementation.contains("workspaceActivations[runtimeIdentity.triptychID]"))
        #expect(implementation.contains("== runtimeIdentity"))
    }

    @Test("Retained-memory driver synchronizes on app records without observer artifacts")
    func retainedMemoryDriverAvoidsRepeatedAccessibilitySnapshots() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent(
                "UITests/ScholiumPerformanceUITests.swift"
            ),
            encoding: .utf8
        )
        let start = try #require(source.range(of: "func testRDF1EditorRetainedMemory()"))
        let end = try #require(source.range(
            of: "func testRDF1HundredThousandCJKCorrectness()",
            range: start.upperBound..<source.endIndex
        ))
        let journey = source[start.lowerBound..<end.lowerBound]

        #expect(journey.contains("lineCount(at: progressPath) == transition + 1"))
        #expect(!journey.contains("XCUIScreen.main.screenshot()"))
        #expect(!journey.contains("Thread.sleep"))
    }

    @Test("Performance environment records accessibility settings as booleans")
    func performanceEnvironmentHasNoUnrecordedAccessibilitySentinel() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent(
                "Tools/Scripts/capture-performance-environment.py"
            ),
            encoding: .utf8
        )

        #expect(source.contains("process_is_running(\"VoiceOver\")"))
        #expect(source.contains("FullKeyboardAccessEnabled"))
        #expect(source.contains("AppleKeyboardUIMode"))
        #expect(!source.contains("voiceOverOnOffKey"))
        #expect(!source.contains("not_recorded_by_automation"))
    }

    @Test("Packaged Search performance uses the product global Search shortcut")
    func performanceSearchDriverUsesGlobalSearchShortcut() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let driver = try String(
            contentsOf: repository.appendingPathComponent(
                "UITests/ScholiumPerformanceUITests.swift"
            ),
            encoding: .utf8
        )
        let app = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let hotkeys = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Features/Settings/HotkeyPreferences.swift"
            ),
            encoding: .utf8
        )
        #expect(driver.contains(
            "application.typeKey(\"f\", modifierFlags: [.command, .shift])"
        ))
        #expect(app.contains(".scholiumKeyboardShortcut(shortcut(for: .searchResearch))"))
        #expect(hotkeys.contains("ScholiumHotkeyBinding(key: \"f\", modifiers: [.shift, .command])"))
    }

    @Test("Packaged editor performance actions remain reachable only in an explicit run")
    func packagedEditorPerformanceActionsHaveReleaseReachability() throws {
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
        let tokenOwner = try #require(
            source.range(of: "private var performanceModeNotificationTokens")
        )
        let registrationStart = try #require(
            source.range(
                of: "if PerformanceProbe.shared.isEnabled,",
                range: tokenOwner.lowerBound..<source.endIndex
            )
        )
        let registrationEnd = try #require(
            source.range(
                of: "searchController.loadSavedSearches()",
                range: registrationStart.upperBound..<source.endIndex
            )
        )
        let registration = source[
            registrationStart.lowerBound..<registrationEnd.lowerBound
        ]
        let requestOwner = try #require(
            source.range(of: "private func requestPerformanceEditorMode")
        )
        let requestEnd = try #require(
            source.range(
                of: "func openResearchAction(",
                range: requestOwner.lowerBound..<source.endIndex
            )
        )
        let requests = source[requestOwner.lowerBound..<requestEnd.lowerBound]

        #expect(registration.contains("PerformanceProbe.shared.isEnabled"))
        #expect(registration.contains(
            "--scholium-performance-editor-mode-notifications"
        ))
        #expect(!registration.contains("#if DEBUG"))
        #expect(!registration.contains("Bundle.main.bundleIdentifier"))
        #expect(requests.contains("PerformanceProbe.shared.isEnabled"))
        #expect(requests.contains("exercisesLargeCJKCorrectness"))
        #expect(requests.contains("requestDocumentMode(mode)"))
        #expect(!requests.contains("#if DEBUG"))
    }

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
        #expect(hostSource.contains("allowsPendingReadRecovery"))
        #expect(hostSource.contains("presentsEditor && (hasPresentedEditor || editorIsReady)"))
        #expect(hostSource.contains(".accessibilityHidden(!showsEditor)"))
        #expect(
            noteSource.contains("@ObservedObject private var documentSession: DocumentSessionModel")
        )
        #expect(noteSource.contains("retainsEditor: documentSession.retainsEditorSurface"))
        #expect(noteSource.contains("editorIsReady: editorSession.isLoaded"))
        #expect(
            noteSource.contains(
                "editorSession.presentedMode == documentSession.activeEditorMode"
            ))
        #expect(noteSource.contains("mode: documentSession.retainedEditorMode"))
        #expect(noteSource.contains("renderedReadReadyFingerprint"))
        #expect(noteSource.contains("private var readProjectionTaskIdentity: String"))
        #expect(noteSource.contains("noteFingerprint.sha256"))
        #expect(noteSource.contains("if note.document.hasExactEmptyBody"))
        #expect(noteSource.contains("scholium.emptyRenderedReview"))
        #expect(noteSource.contains("This note has no body content."))
        #expect(noteSource.contains("documentSession.isEnteringManagedCreation"))
        #expect(noteSource.contains("Retry Edit"))
        #expect(noteSource.contains("managedCreationBodyStartUTF16"))
        #expect(noteSource.contains(".id(editorSession.viewReconstructionID)"))
        #expect(noteSource.contains("note.relativePath):"))
        #expect(!noteSource.contains("guard presentationMode == .read else { return }"))

        let sessionSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Features/Document/DocumentSessionStore.swift"
            ),
            encoding: .utf8
        )
        #expect(
            sessionSource.contains(
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
        #expect(presentationSource.contains("case review(editorIntent: MarkdownEditorMode?)"))
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

    @Test("Read readiness preserves the native per-document accessibility identity")
    func readReadinessKeepsDocumentIdentityQueryable() throws {
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
        let webViewSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/SafeMarkdownReadWebView.swift"
            ),
            encoding: .utf8
        )
        let uiSupport = try String(
            contentsOf: repository.appendingPathComponent(
                "UITests/ScholiumUITests+Support.swift"
            ),
            encoding: .utf8
        )

        #expect(!noteSource.contains("scholium.readProjection."))
        #expect(webViewSource.contains(
            #"scholium.renderedDocument.\(expectedDocumentID)"#
        ))
        #expect(uiSupport.contains("identifier BEGINSWITH %@"))
        #expect(uiSupport.contains("scholium.renderedDocument.loading"))
        #expect(uiSupport.contains("scholium.renderedDocument.failed"))
    }

    @Test(
        "EditorHost waits on initial entry but preserves an established editor during mode reconfiguration"
    )
    func editorHostPresentationGate() {
        var gate = DocumentEditorPresentationGate()

        gate.reconcile(presentsEditor: false, editorIsReady: false)
        #expect(!gate.showsEditor(presentsEditor: false, editorIsReady: false))

        gate.reconcile(presentsEditor: true, editorIsReady: false)
        #expect(!gate.showsEditor(presentsEditor: true, editorIsReady: false))
        #expect(!gate.allowsReadHitTesting(
            presentsEditor: true,
            editorIsReady: false,
            allowsPendingRecovery: false
        ))
        #expect(gate.allowsReadHitTesting(
            presentsEditor: true,
            editorIsReady: false,
            allowsPendingRecovery: true
        ))

        gate.reconcile(presentsEditor: true, editorIsReady: true)
        #expect(gate.showsEditor(presentsEditor: true, editorIsReady: true))
        #expect(!gate.allowsReadHitTesting(
            presentsEditor: true,
            editorIsReady: true,
            allowsPendingRecovery: true
        ))

        // A bridge-confirmed editor remains the visible surface while the
        // retained CodeMirror state atomically changes Edit <-> Source.
        gate.reconcile(presentsEditor: true, editorIsReady: false)
        #expect(gate.showsEditor(presentsEditor: true, editorIsReady: false))

        gate.reconcile(presentsEditor: false, editorIsReady: false)
        #expect(!gate.showsEditor(presentsEditor: false, editorIsReady: false))

        #expect(gate.allowsEditorFocus(
            isEditing: true,
            isReturningToReview: false,
            editorIsReady: true,
            presentedModeMatchesIntent: true
        ))
        #expect(!gate.allowsEditorFocus(
            isEditing: true,
            isReturningToReview: true,
            editorIsReady: true,
            presentedModeMatchesIntent: true
        ))
        #expect(!gate.allowsEditorFocus(
            isEditing: true,
            isReturningToReview: false,
            editorIsReady: false,
            presentedModeMatchesIntent: true
        ))
        #expect(!gate.allowsEditorFocus(
            isEditing: true,
            isReturningToReview: false,
            editorIsReady: true,
            presentedModeMatchesIntent: false
        ))
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
        let comparisonSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ExactSourceComparisonView.swift"
            ),
            encoding: .utf8
        )

        #expect(noteSource.contains("DocumentIntegrityPresentation.resolve("))
        #expect(noteSource.contains("ScholiumDocumentStatusNotice("))
        #expect(!noteSource.contains(
            ".overlay(alignment: .bottom) {\n"
                + "            if let presentation = documentIntegrityPresentation"
        ))
        #expect(noteSource.contains("scholium.documentStatus.autosaveFailed"))
        #expect(noteSource.contains("scholium.documentStatus.conflict"))
        #expect(noteSource.contains("AccessibilityNotification.Announcement"))
        #expect(noteSource.contains("ExactSourceComparisonSheetLayout("))
        #expect(noteSource.contains("ExactSourceComparisonView("))
        #expect(noteSource.contains("ScrollView(.vertical)"))
        #expect(comparisonSource.contains(
            "ScholiumMetrics.ResearchSheet.Comparison.minimumWidth"
        ))
        #expect(comparisonSource.contains(".lineLimit(nil)"))
        #expect(!comparisonSource.contains("ScrollView([.vertical, .horizontal])"))
        #expect(!comparisonSource.contains(
            ".fixedSize(horizontal: true, vertical: false)"
        ))
        #expect(!noteSource.contains(".alert(conflict == nil ? \"Save Failed\""))
        #expect(
            !noteSource.contains("Native save/conflict recovery owns focus while it is visible."))
        #expect(componentSource.contains("struct ScholiumDocumentStatusNotice<Actions: View>"))
        #expect(
            componentSource.contains(
                "HStack(alignment: .center, spacing: ScholiumMetrics.Notice.contentSpacing)"
            )
        )
        #expect(
            componentSource.contains(
                "HStack(alignment: .center, "
                    + "spacing: ScholiumGrid.Spacing.inlineControlGap)"
            )
        )
        #expect(!componentSource.contains("verticalAlignment"))
        #expect(componentSource.contains(".accessibilityLabel(title)"))
        #expect(componentSource.contains(".accessibilityValue(detail)"))
    }

    @Test("Recovery notices share presentation without moving workflow ownership")
    func recoveryNoticePresentationResponsibility() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let componentSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumComponents.swift"
            ),
            encoding: .utf8
        )
        let identitySource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/IdentityResolutionView.swift"
            ),
            encoding: .utf8
        )
        let transactionSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/TransactionRecoveryView.swift"
            ),
            encoding: .utf8
        )
        let searchSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/SearchWorkspaceView.swift"
            ),
            encoding: .utf8
        )

        let componentStart = try #require(
            componentSource.range(
                of: "struct ScholiumRecoveryNoticePresentation"
            ))
        let componentEnd = try #require(
            componentSource.range(
                of: "enum ScholiumDocumentStatusKind",
                range: componentStart.upperBound..<componentSource.endIndex
            ))
        let recoveryComponent = componentSource[
            componentStart.lowerBound..<componentEnd.lowerBound
        ]
        let migrationStart = try #require(
            identitySource.range(
                of: "struct IdentityMigrationNotice"
            ))
        let ambiguityStart = try #require(
            identitySource.range(
                of: "struct IdentityAmbiguityNotice",
                range: migrationStart.upperBound..<identitySource.endIndex
            ))
        let migrationNotice = identitySource[
            migrationStart.lowerBound..<ambiguityStart.lowerBound
        ]
        let ambiguityNotice = identitySource[ambiguityStart.lowerBound...]
        let transactionStart = try #require(
            transactionSource.range(
                of: "struct TransactionRecoveryNotice"
            ))
        let transactionEnd = try #require(
            transactionSource.range(
                of: "struct TransactionRecoveryView",
                range: transactionStart.upperBound..<transactionSource.endIndex
            ))
        let transactionNotice = transactionSource[
            transactionStart.lowerBound..<transactionEnd.lowerBound
        ]

        #expect(recoveryComponent.contains("enum ScholiumRecoveryNoticeRegion"))
        #expect(recoveryComponent.contains("case documentInline"))
        #expect(recoveryComponent.contains("case workspaceBanner"))
        #expect(recoveryComponent.contains("struct ScholiumRecoveryNotice<Action: View>"))
        #expect(recoveryComponent.contains(".scholiumForeground(.attention)"))
        #expect(
            recoveryComponent.contains(
                "ScholiumColorRole.raisedSurfaceBackground.color"
            )
        )
        #expect(recoveryComponent.contains("ScholiumStructuralRule()"))
        #expect(recoveryComponent.contains("ViewThatFits(in: .horizontal)"))
        #expect(recoveryComponent.contains(".accessibilityElement(children: .combine)"))
        #expect(recoveryComponent.contains(".accessibilityElement(children: .contain)"))
        #expect(!recoveryComponent.contains("Task {"))
        #expect(!recoveryComponent.contains("NoteIdentity"))
        #expect(!recoveryComponent.contains("TriptychMutationRecoveryRecord"))

        #expect(migrationNotice.contains("ScholiumRecoveryNotice("))
        #expect(migrationNotice.contains("region: .documentInline"))
        #expect(migrationNotice.contains("Task { await onRetry() }"))
        #expect(!migrationNotice.contains(".background(.orange"))
        #expect(!migrationNotice.contains(".stroke(.orange"))

        #expect(ambiguityNotice.contains("ScholiumRecoveryNotice("))
        #expect(ambiguityNotice.contains("region: .documentInline"))
        #expect(!ambiguityNotice.contains(".background(.orange"))
        #expect(!ambiguityNotice.contains(".stroke(.orange"))

        let documentAdapterCount =
            identitySource.components(
                separatedBy: "region: .documentInline"
            ).count - 1
        #expect(documentAdapterCount == 2)
        #expect(transactionNotice.contains("ScholiumRecoveryNotice("))
        #expect(transactionNotice.contains("region: .workspaceBanner"))
        #expect(transactionNotice.contains("Button(\"Inspect Recovery…\", action: onInspect)"))
        #expect(
            transactionNotice.contains(
                ".accessibilityIdentifier(\"scholium.transactionRecovery.notice\")"
            ))
        #expect(!transactionNotice.contains("Color.orange"))
        #expect(!searchSource.contains("ScholiumRecoveryNotice("))
    }

    @Test("Production colors have one semantic owner with bounded exceptions")
    func featureViewsUseResolvedFunctionalColorRoles() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewsRoot = repository.appendingPathComponent("Scholium/Views")
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: viewsRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ))
        var viewSources: [String: String] = [:]
        while let file = enumerator.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let relativePath = file.path.replacingOccurrences(
                of: repository.path + "/",
                with: ""
            )
            viewSources[relativePath] = try String(contentsOf: file, encoding: .utf8)
        }
        #expect(!viewSources.isEmpty)

        let rawFunctionalColor = try NSRegularExpression(
            pattern:
                #"(?:Color\.(?:red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown)|NSColor\.system(?:Red|Orange|Yellow|Green|Mint|Teal|Cyan|Blue|Indigo|Purple|Pink|Brown)|(?<![A-Za-z0-9_])\.(?:red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|system(?:Red|Orange|Yellow|Green|Mint|Teal|Cyan|Blue|Indigo|Purple|Pink|Brown))\b)"#
        )
        for (path, source) in viewSources.sorted(by: { $0.key < $1.key }) {
            let match = rawFunctionalColor.firstMatch(
                in: source,
                range: NSRange(source.startIndex..<source.endIndex, in: source)
            )
            #expect(match == nil, "\(path) contains a raw functional color")
        }

        let applicationRoot = repository.appendingPathComponent("Scholium")
        let applicationEnumerator = try #require(
            FileManager.default.enumerator(
                at: applicationRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )
        var applicationSources: [String: String] = [:]
        while let file = applicationEnumerator.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let relativePath = file.path.replacingOccurrences(
                of: repository.path + "/",
                with: ""
            )
            applicationSources[relativePath] = try String(contentsOf: file, encoding: .utf8)
        }

        let designSystemPath = "Scholium/UI/Foundation/ScholiumDesignSystem.swift"
        let bootstrapArtworkPath = "Scholium/Views/BootstrapStageArtworkView.swift"
        let searchPath = "Scholium/Views/SearchWorkspaceView.swift"
        let rawAppKitPaletteAccess = try NSRegularExpression(
            pattern:
                #"\.(?:labelColor|secondaryLabelColor|tertiaryLabelColor|windowBackgroundColor|controlBackgroundColor|textBackgroundColor|findHighlightColor|shadowColor)\b"#
        )
        let directSystemForeground = try NSRegularExpression(
            pattern: #"\.foregroundStyle\(\.(?:primary|secondary|tertiary)\)"#
        )
        let directRoleForeground = try NSRegularExpression(
            pattern: #"\.foregroundStyle\(ScholiumColorRole\.[A-Za-z]+\.color\)"#
        )
        let localSemanticOpacity = try NSRegularExpression(
            pattern: #"ScholiumColorRole\.[A-Za-z]+\.color(?:\([^)]*\))?\.opacity\([0-9]"#
        )
        let rawSwiftColorInput = try NSRegularExpression(
            pattern: #"\b(?:Color\((?:red|white):|NSColor\((?:calibrated|device|sRGB))"#
        )

        for (path, source) in applicationSources.sorted(by: { $0.key < $1.key }) {
            let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)
            if path != designSystemPath {
                #expect(
                    rawAppKitPaletteAccess.firstMatch(
                        in: source,
                        range: sourceRange
                    ) == nil,
                    "\(path) reaches into AppKit's color palette directly"
                )
                #expect(
                    localSemanticOpacity.firstMatch(
                        in: source,
                        range: sourceRange
                    ) == nil,
                    "\(path) owns a numeric semantic-color opacity recipe"
                )
            }
            #expect(
                directSystemForeground.firstMatch(
                    in: source,
                    range: sourceRange
                ) == nil,
                "\(path) bypasses Scholium foreground roles"
            )

            let directRoleMatches = directRoleForeground.matches(
                in: source,
                range: sourceRange
            )
            if path == searchPath {
                #expect(directRoleMatches.count == 1)
                #expect(
                    source.contains(
                        "prompt: Text(\"Spotlight Search\")\n"
                            + "                    .foregroundStyle("
                            + "ScholiumColorRole.secondaryText.color)"
                    )
                )
            } else if path != designSystemPath {
                #expect(
                    directRoleMatches.isEmpty,
                    "\(path) bypasses the adaptive Scholium foreground modifier"
                )
            }

            let rawInputMatches = rawSwiftColorInput.matches(
                in: source,
                range: sourceRange
            )
            if path == bootstrapArtworkPath {
                #expect(rawInputMatches.count == 7)
            } else if path != designSystemPath {
                #expect(
                    rawInputMatches.isEmpty,
                    "\(path) introduces a raw Swift color input"
                )
            }
        }
        let critique = try #require(
            viewSources["Scholium/Views/Note/CritiqueProvenanceView.swift"]
        )
        #expect(critique.contains("metadata.isAgentAttributed ? .agentAuthorship : .attention"))

        let comparison = try #require(
            applicationSources["Scholium/UI/Components/ExactSourceComparisonView.swift"]
        )
        #expect(comparison.contains("case .startingOnly, .endingOnly: .attention"))

        let settings = try #require(viewSources["Scholium/Views/WorkspaceSettingsView.swift"])
        #expect(settings.contains("info.status == .available ? .confirmed : .attention"))

        let frontmatter = try #require(
            viewSources["Scholium/Views/Metadata/MetadataEditorView.swift"]
        )
        #expect(frontmatter.contains("ScholiumColorRole.destructive.color"))

        let search = try #require(viewSources["Scholium/Views/SearchWorkspaceView.swift"])
        #expect(search.contains(".scholiumForeground(.destructive)"))
    }

    @Test("A window presents at most one sheet route")
    func presentationRouteExclusivity() {
        let router = WindowPresentationRouter()

        router.present(.transactionRecovery)
        #expect(router.sheet?.id == "transaction-recovery")

        router.presentMetadata(path: "Topics/Agency.md")
        guard case .metadata(let metadataRoute) = router.sheet else {
            Issue.record("Expected Metadata to replace the transaction recovery route")
            return
        }
        #expect(metadataRoute.path == "Topics/Agency.md")
        router.dismissSheet(if: "transaction-recovery")
        #expect(router.sheet?.id == metadataRoute.id)

        router.dismissSheet(if: metadataRoute.id)
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
        #expect(appSource.components(separatedBy: "WindowGroup(").count == 4)
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
        #expect(!appSource.contains("@FocusedObject private var focusedWindowModel"))
        #expect(appSource.contains("\"Research Records\""))
        #expect(appSource.contains("id: \"scholium-research-records\""))
        #expect(appSource.contains("for: UUID.self"))
        #expect(appSource.contains("workspaceStore.workspaceCapabilities(id: triptychID)"))
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
        let sidebarTreeRowsSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/Sidebar/SidebarTreeRows.swift"
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
        let workspaceSplitStart = try #require(
            splitSource.range(of: "struct ScholiumWorkspaceSplitView<")
        )
        let workspaceSplitSource = splitSource[workspaceSplitStart.lowerBound...]
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
        #expect(
            splitSource.contains(
                "sidebarWithViewController: libraryBackgroundController"
            ))
        #expect(!splitSource.contains("libraryItem.canCollapseFromWindowResize = false"))
        #expect(
            !splitSource.contains(
                "inspectorWithViewController: apparatusBackgroundController"
            ))
        #expect(!workspaceSplitSource.contains("preferredThicknessFraction"))
        #expect(!splitSource.contains("libraryOpeningSize"))
        #expect(!splitSource.contains("libraryHost.sizingOptions = []"))
        #expect(!splitSource.contains("preferredContentSize"))
        #expect(!splitSource.contains("ScholiumWorkspaceSplitHoldingPriority"))
        #expect(
            splitSource.contains(
                "libraryItem.minimumThickness = ScholiumMetrics.Library.minimumReadableWidth"
            ))
        #expect(!splitSource.contains("libraryItem.maximumThickness"))
        #expect(!splitSource.contains("libraryItem.automaticMaximumThickness"))
        #expect(!splitSource.contains("documentItem.minimumThickness"))
        #expect(
            splitSource.contains(
                "ScholiumMetrics.Apparatus.minimumReadableWidth"
            ))
        #expect(
            splitSource.contains(
                "apparatusItem.maximumThickness = NSSplitViewItem.unspecifiedDimension"
            ))
        #expect(splitSource.contains("apparatusItem.canCollapse = false"))
        #expect(splitSource.contains("apparatusItem.isCollapsed = !visible"))
        #expect(!workspaceSplitSource.contains("toggleInspector(nil)"))
        #expect(!splitSource.contains("effectiveRect proposedEffectiveRect"))
        #expect(!splitSource.contains("dividerHitExpansion"))
        #expect(!splitSource.contains("ScholiumInteractiveSplitView"))
        #expect(!splitSource.contains("func sizeThatFits("))
        #expect(!splitSource.contains("availableSize"))
        #expect(!splitSource.contains("libraryHost.sizingOptions = []"))
        #expect(splitSource.contains("apparatusHost.sizingOptions = []"))
        #expect(splitSource.contains("placeholderHost.sizingOptions = []"))
        #expect(splitSource.contains("host.sizingOptions = []"))
        #expect(!splitSource.contains("sizingOptions = [.minSize]"))
        #expect(!splitSource.contains("scholium.library.preferred-width"))
        #expect(splitSource.contains("ScholiumFirstApparatusWidthOffer"))
        #expect(splitSource.contains("firstApparatusWidthOffer.offerAfterReveal()"))
        #expect(
            splitSource.components(
                separatedBy: "firstApparatusWidthOffer.offerAfterReveal()"
            ).count == 3
        )
        #expect(!splitSource.contains("prepareForReveal(animated:"))
        #expect(!splitSource.contains("revealAnimationDidFinish()"))
        #expect(!splitSource.contains("firstApparatusWidthOffer.offerIfReady()"))
        #expect(splitSource.contains("ScholiumMetrics.Apparatus.firstRevealWidth"))
        #expect(!splitSource.contains("splitView.adjustSubviews"))
        #expect(!splitSource.contains("ScholiumSurfaceHostController"))
        #expect(splitSource.contains("ScholiumSurfaceContainerViewController"))
        #expect(!splitSource.contains("NSBackgroundExtensionView"))
        #expect(!splitSource.contains("installTitlebarControl"))
        #expect(!splitSource.contains("ScholiumPeripheralTitlebarControlView"))
        #expect(splitSource.contains("backgroundHost.safeAreaRegions = []"))
        #expect(!splitSource.contains("NSSplitViewItemAccessoryViewController"))
        #expect(
            splitSource.contains(
                "rootView: backgroundRole.colorRole.color"
            ))
        #expect(
            splitSource.contains(
                "equalTo: containerView.topAnchor"
            ))
        #expect(
            splitSource.contains(
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
        #expect(
            windowManagementSource.contains(
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
        #expect(
            sidebarSource.contains(
                ".accessibilityIdentifier(\"scholium.triptychManagement\")"
            ))
        #expect(!toolbarSource.contains("private var desiredItemIdentifiers"))
        #expect(ScholiumWorkspaceToolbarController.itemIdentifiers == [
            ScholiumWorkspaceToolbarController.Item.sidebar,
            ScholiumWorkspaceToolbarController.Item.back,
            ScholiumWorkspaceToolbarController.Item.forward,
            ScholiumWorkspaceToolbarController.Item.libraryDivider,
            ScholiumWorkspaceToolbarController.Item.headingOutline,
            .flexibleSpace,
            ScholiumWorkspaceToolbarController.Item.search,
            ScholiumWorkspaceToolbarController.Item.documentMode,
            ScholiumWorkspaceToolbarController.Item.researchRecords,
            ScholiumWorkspaceToolbarController.Item.apparatusDivider,
            .flexibleSpace,
            ScholiumWorkspaceToolbarController.Item.inspector,
        ])
        #expect(!sidebarSource.contains(".ignoresSafeArea(.container, edges: .leading)"))
        #expect(sidebarSource.contains("private var brandHeader"))
        #expect(toolbarSource.contains("button.setAccessibilityRole(.popUpButton)"))
        #expect(appSource.contains(".navigationTitle(workspaceWindowTitle)"))
        #expect(appSource.contains("@ObservedObject private var commandObservation"))
        #expect(!toolbarSource.contains("window?.title ="))
        #expect(!toolbarSource.contains("NSHostingView"))
        #expect(!toolbarSource.contains("documentTitleMaximumWidth"))
        #expect(!toolbarSource.contains("documentIdentity"))
        #expect(!toolbarSource.contains("documentCommands"))
        #expect(!contentSource.contains("private func documentIdentityHeader"))
        #expect(!contentSource.contains("documentIdentityHeader(for:"))
        #expect(toolbarSource.contains("static let inspector = NSToolbarItem.Identifier"))
        #expect(toolbarSource.contains("\"scholium.toolbar.inspector\""))
        #expect(
            toolbarSource.contains(
                "windowActions.setResearchInspectorVisible(!appState.shellState.inspector.isVisible)"
            ))
        #expect(
            toolbarSource.contains(
                "appState.documentController.selectedDocument != nil"
            ))
        #expect(toolbarSource.contains("Hide Sidebar"))
        #expect(toolbarSource.contains("Hide Research Inspector"))
        #expect(!sidebarSource.contains("Hide Sidebar"))
        #expect(!noteSource.contains("Hide Research Inspector"))
        #expect(!contentSource.contains("apparatusHideControl"))
        #expect(
            appSource.contains(
                "appState?.researchInspectorVisible != true"
            ))
        #expect(
            appSource.contains(
                "&& appState?.currentNote == nil"
            ))
        #expect(!toolbarSource.contains("glassEffect"))
        #expect(noteSource.contains("ScholiumInspectorModeIndex("))
        #expect(!noteSource.contains("Picker(\"Research Inspector\""))
        #expect(apparatusComponentsSource.contains("struct ScholiumInspectorModeIndex"))
        #expect(apparatusComponentsSource.contains("ScholiumSegmentedControl("))
        #expect(!appSource.contains("removeAutomaticSidebarToolbarItem"))
        #expect(appSource.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(windowManagementSource.contains("window.titlebarAppearsTransparent = true"))
        #expect(!windowManagementSource.contains("windowDidEnterFullScreen"))
        #expect(!windowManagementSource.contains("windowDidExitFullScreen"))
        #expect(windowManagementSource.contains("ScholiumWindowAppearance.apply"))
        #expect(!windowManagementSource.contains("titlebarContainer"))
        #expect(!windowManagementSource.contains("layer?.backgroundColor"))
        #expect(windowManagementSource.contains("scholium.workspaceToolbar.loading"))
        #expect(windowManagementSource.contains("installLoadingToolbarIfNeeded()"))
        #expect(
            windowManagementSource.contains(
                "loadingToolbar.itemIdentifiers = [.flexibleSpace]"
            ))
        #expect(windowManagementSource.contains("window.styleMask.insert(.fullSizeContentView)"))
        #expect(!contentSource.contains(".toolbarBackground(.clear, for: .windowToolbar)"))
        #expect(
            contentSource.contains(
                ".toolbarBackgroundVisibility(.hidden, for: .windowToolbar)"
            ))
        #expect(!appSource.contains("Collapse Note"))
        #expect(sidebarTreeRowsSource.contains("ScholiumTypography.interface(.body)"))
        #expect(sidebarSource.contains("ScholiumTypography.interface(.small, emphasis: .medium)"))
        #expect(
            ScholiumMetrics.Library.hierarchyRowHeight
                >= ScholiumMetrics.Accessibility.minimumCustomTarget
        )
        #expect(ScholiumMetrics.Library.contentInset == ScholiumGrid.Peripheral.contentInset)
        #expect(ScholiumMetrics.Library.minimumReadableWidth == 300)
    }

    @Test(
        "The semantic Library sidebar receives the readable minimum without replacing AppKit behavior"
    )
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
        #expect(
            controller.minimumThicknessForInlineSidebars == NSSplitViewController.automaticDimension
        )
    }

    @Test("Peripheral visibility controls occupy their native toolbar planes")
    func stablePeripheralToolbarLayout() throws {
        typealias Item = ScholiumWorkspaceToolbarController.Item

        let identifiers = ScholiumWorkspaceToolbarController.itemIdentifiers
        let documentFlexibleSpaceIndex = try #require(
            identifiers.firstIndex(of: .flexibleSpace)
        )
        let apparatusFlexibleSpaceIndex = try #require(
            identifiers.lastIndex(of: .flexibleSpace)
        )
        let libraryDividerIndex = try #require(
            identifiers.firstIndex(of: Item.libraryDivider)
        )
        let sidebarIndex = try #require(identifiers.firstIndex(of: Item.sidebar))
        let backIndex = try #require(identifiers.firstIndex(of: Item.back))
        let forwardIndex = try #require(identifiers.firstIndex(of: Item.forward))
        let headingIndex = try #require(
            identifiers.firstIndex(of: Item.headingOutline)
        )
        let searchIndex = try #require(identifiers.firstIndex(of: Item.search))
        let modeIndex = try #require(identifiers.firstIndex(of: Item.documentMode))
        let recordsIndex = try #require(
            identifiers.firstIndex(of: Item.researchRecords)
        )
        let inspectorIndex = try #require(identifiers.firstIndex(of: Item.inspector))
        let apparatusDividerIndex = try #require(
            identifiers.firstIndex(of: Item.apparatusDivider)
        )
        #expect(sidebarIndex < backIndex)
        #expect(backIndex < forwardIndex)
        #expect(forwardIndex < libraryDividerIndex)
        #expect(libraryDividerIndex < headingIndex)
        #expect(headingIndex < documentFlexibleSpaceIndex)
        #expect(documentFlexibleSpaceIndex < searchIndex)
        #expect(searchIndex < modeIndex)
        #expect(modeIndex < recordsIndex)
        #expect(recordsIndex < apparatusDividerIndex)
        #expect(apparatusDividerIndex < apparatusFlexibleSpaceIndex)
        #expect(apparatusFlexibleSpaceIndex < inspectorIndex)
        #expect(identifiers.filter { $0 == .flexibleSpace }.count == 2)
        #expect(identifiers.filter { $0 == Item.sidebar }.count == 1)
        #expect(identifiers.filter { $0 == Item.back }.count == 1)
        #expect(identifiers.filter { $0 == Item.forward }.count == 1)
        #expect(identifiers.filter { $0 == Item.inspector }.count == 1)

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

    @Test("Document toolbar exposes one current-state Review and Edit button")
    @MainActor
    func documentReviewEditToolbarButton() throws {
        let review = ScholiumDocumentModeToolbarButtonPresentation(mode: .read)
        let edit = ScholiumDocumentModeToolbarButtonPresentation(mode: .livePreview)
        let source = ScholiumDocumentModeToolbarButtonPresentation(mode: .source)

        #expect(review.destination == .livePreview)
        #expect(edit.destination == .read)
        #expect(source.destination == .read)
        #expect(review.symbol == NotePresentationMode.read.symbol)
        #expect(edit.symbol == NotePresentationMode.livePreview.symbol)
        #expect(source.symbol == NotePresentationMode.source.symbol)
        #expect(review.toolTip == NotePresentationMode.read.title)
        #expect(NotePresentationMode.livePreview.symbol == "square.and.pencil")

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let toolbarSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWorkspaceToolbar.swift"
            ),
            encoding: .utf8
        )
        #expect(toolbarSource.contains("ScholiumDocumentModeToolbarButtonPresentation"))
        #expect(
            ScholiumWorkspaceToolbarController.Item.documentMode.rawValue
                == "scholium.toolbar.documentMode"
        )
        #expect(toolbarSource.contains("systemImage: presentation.symbol"))
        #expect(toolbarSource.contains("toolTip: presentation.toolTip"))
        #expect(
            toolbarSource.contains(
                "mode: appState.documentController.chromeProjection.mode"
            )
        )
        #expect(toolbarSource.contains("appState.requestDocumentMode(presentation.destination)"))
        #expect(!toolbarSource.contains("NSSegmentedControl(frame: .zero)"))
        #expect(!toolbarSource.contains("scholium.documentModeToggle"))
        #expect(!toolbarSource.contains("scholium.documentModeMenu"))
        #expect(!toolbarSource.contains("NotePresentationMode.allCases.map"))

        let appSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let menuStart = try #require(appSource.range(of: "Menu(\"Document Mode\")"))
        let menuEnd = try #require(
            appSource.range(
                of: "Divider()",
                range: menuStart.upperBound..<appSource.endIndex
            )
        )
        let documentModeMenu = appSource[
            menuStart.lowerBound..<menuEnd.lowerBound
        ]
        #expect(documentModeMenu.contains("Button(\"Source\")"))
        #expect(documentModeMenu.contains(
            ".scholiumKeyboardShortcut(shortcut(for: .toggleReviewEdit))"
        ))

        let commandObservation = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/App/Window/WindowCommandObservation.swift"
            ),
            encoding: .utf8
        )
        #expect(
            commandObservation.contains(
                "changes(documentController.$currentPresentationMode)"
            )
        )
        #expect(
            commandObservation.contains(
                "changes(documentController.$chromeProjection)"
            )
        )
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
        #expect(controller.structuralDepthView == nil)

    }

    @Test("Document-navigation depth is one full-height noninteractive Library projection")
    func documentNavigationDepthContainer() throws {
        let contentController = NSViewController()
        contentController.view = NSView()
        let controller = ScholiumSurfaceContainerViewController(
            contentViewController: contentController,
            backgroundRole: .navigation,
            structuralDepthRole: .documentNavigationBoundary
        )

        controller.view.frame = NSRect(x: 0, y: 0, width: 300, height: 760)
        controller.view.layoutSubtreeIfNeeded()
        let depthView = try #require(controller.structuralDepthView)

        #expect(depthView.superview === controller.view)
        #expect(controller.view.subviews.first === controller.backgroundView)
        #expect(controller.view.subviews.last === depthView)
        #expect(depthView.frame == controller.view.bounds)
        #expect(depthView.hitTest(NSPoint(x: 299, y: 380)) == nil)
        #expect(depthView.isAccessibilityElement() == false)

        let splitController = ScholiumWorkspaceSplitView<EmptyView, EmptyView, EmptyView>
            .Controller(
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
        _ = splitController.view

        #expect(splitController.splitView.dividerStyle == .thin)
        #expect(splitController.splitViewItems.count == 3)
        let depthCounts = splitController.splitViewItems.map { item in
            (item.viewController as? ScholiumSurfaceContainerViewController)?
                .structuralDepthView == nil ? 0 : 1
        }
        #expect(depthCounts == [1, 0, 0])
    }

    @Test("Research Inspector separates divider resizing from explicit visibility")
    func researchInspectorSeparatesResizeAndVisibility() throws {
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

        #expect(item.behavior == .default)
        #expect(!item.canCollapse)
        #expect(!item.canCollapseFromWindowResize)
        #expect(item.isCollapsed)
        #expect(
            item.minimumThickness
                == ScholiumMetrics.Apparatus.minimumReadableWidth
        )
        #expect(item.maximumThickness == NSSplitViewItem.unspecifiedDimension)
        #expect(
            item.collapseBehavior
                == .preferResizingSiblingsWithFixedSplitView
        )
    }

    @Test("Custom activation controls share one focus and hover policy")
    func customControlInteractionPolicy() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let designSystemSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Foundation/ScholiumDesignSystem.swift"
            ),
            encoding: .utf8
        )

        #expect(designSystemSource.contains("ScholiumBooleanActivationFocusModifier"))
        #expect(designSystemSource.contains("ScholiumValueActivationFocusModifier"))
        #expect(designSystemSource.contains("func scholiumActivationFocus("))
        #expect(
            designSystemSource.contains(
                "ScholiumContentControlPointerFeedbackModifier"
            ))
        #expect(
            designSystemSource.contains(
                "func scholiumContentControlPointerFeedback"
            ))
        #expect(designSystemSource.contains("struct ScholiumContentControlButtonStyle"))
        #expect(
            designSystemSource.contains(
                "ScholiumContentControlButtonFeedbackModifier"
            ))
        #expect(designSystemSource.contains("let tracksHover: Bool"))
        #expect(
            designSystemSource.contains(
                "let effectiveIsHovering = tracksHover && isHovering"
            ))
        #expect(designSystemSource.contains("if tracksHover {"))
        #expect(designSystemSource.contains("ScholiumPointerInteractionReader"))
        #expect(designSystemSource.contains("ScholiumPointerTrackingView"))
        #expect(designSystemSource.contains("override func hitTest"))
        #expect(designSystemSource.contains("NSEvent.addLocalMonitorForEvents"))
        #expect(designSystemSource.contains("NSTrackingArea("))
        #expect(designSystemSource.contains("@State private var isPressed"))
        #expect(!designSystemSource.contains("@GestureState private var isPressed"))
        #expect(!designSystemSource.contains("ScholiumControlActivation"))
        #expect(
            ScholiumContentInteractionSurface.opacity(
                isHovering: true,
                isFocused: false,
                increasedContrast: false
            ) == 0.05)
        #expect(
            ScholiumContentInteractionSurface.opacity(
                isHovering: false,
                isFocused: true,
                increasedContrast: false
            ) == 0.42)
        #expect(
            ScholiumContentInteractionSurface.opacity(
                isHovering: false,
                isFocused: false,
                isPressed: true,
                increasedContrast: false
            ) == 0.05)
        #expect(
            ScholiumContentInteractionSurface.opacity(
                isHovering: true,
                isFocused: false,
                increasedContrast: true
            ) == 0.075)
        #expect(
            ScholiumContentInteractionSurface.opacity(
                isHovering: false,
                isFocused: false,
                increasedContrast: false
            ) == 0)
    }

    @Test("WebKit hover, keyboard focus, and selection share the native semantic resolver")
    func webContentInteractionPolicy() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let callouts = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Resources/Editor/callouts.css"
            ),
            encoding: .utf8
        )
        let footnotes = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Resources/Editor/footnotes.css"
            ),
            encoding: .utf8
        )
        let editor = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Resources/Editor/editor.css"
            ),
            encoding: .utf8
        )
        let read = try String(
            contentsOf: repository.appendingPathComponent(
                "WebEditor/reader.ts"
            ),
            encoding: .utf8
        )
        let sharedCSS = ScholiumWebDesignTokens.documentPresentationCSS

        #expect(
            ScholiumContentInteractionSurface.webCSSDeclarations.contains(
                "var(--scholium-color-primary-text) 5%"
            ))
        #expect(
            ScholiumContentInteractionSurface.webCSSDeclarations.contains(
                "var(--scholium-color-raised-surface-background) 42%"
            ))
        #expect(
            ScholiumContentInteractionSurface.increasedContrastWebCSSDeclarations
                .contains("var(--scholium-color-primary-text) 7.5%")
        )
        #expect(
            ScholiumContentInteractionSurface.increasedContrastWebCSSDeclarations
                .contains("var(--scholium-color-raised-surface-background) 56%")
        )
        #expect(sharedCSS.contains("background: var(--scholium-content-hover-surface)"))
        #expect(
            sharedCSS.contains(
                "background: var(--scholium-content-keyboard-focus-surface)"
            ))
        #expect(
            sharedCSS.contains(
                #"li[aria-selected="true"] {"#
            ))
        #expect(sharedCSS.contains("background: var(--scholium-color-raised-surface-background)"))
        #expect(callouts.contains("var(--scholium-content-hover-surface, transparent)"))
        #expect(callouts.contains("--scholium-content-keyboard-focus-surface"))
        #expect(callouts.contains("var(--scholium-content-focus-ring, Highlight)"))
        #expect(!callouts.contains("--scholium-callout-hover"))
        #expect(!callouts.contains("--scholium-callout-focus"))
        #expect(footnotes.contains("outline: 2px solid var(--scholium-content-focus-ring)"))
        #expect(editor.contains("outline: 2px solid var(--scholium-content-focus-ring)"))
        #expect(read.contains("previewAnchorFor"))
        #expect(read.contains("remainsInsidePreviewAnchor"))
        #expect(read.contains("document.addEventListener('focusout'"))
    }

    @Test("Library hierarchy, Attention, and filters share one contract")
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
        let filterMenuSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Sidebar/SidebarLibraryFilterMenu.swift"
            ),
            encoding: .utf8
        )
        let outlineSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Sidebar/SidebarOutlineSourceList.swift"
            ),
            encoding: .utf8
        )
        let outlineCoordinatorSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Sidebar/SidebarOutlineCoordinator.swift"
            ),
            encoding: .utf8
        )
        let treeRowsSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Sidebar/SidebarTreeRows.swift"
            ),
            encoding: .utf8
        )
        let outlineRowsSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Sidebar/SidebarOutlineRows.swift"
            ),
            encoding: .utf8
        )
        let nativeDropSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Sidebar/SidebarNativeDropDestination.swift"
            ),
            encoding: .utf8
        )
        let treeProjectionSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Features/Discovery/LibraryTreeProjection.swift"
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
        let designSystemSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Foundation/ScholiumDesignSystem.swift"
            ),
            encoding: .utf8
        )

        #expect(typographySource.contains("case body"))
        #expect(typographySource.contains("case compact"))
        #expect(typographySource.contains("case small"))
        #expect(typographySource.contains("(size, defaultWeight) = (12, .regular)"))
        #expect(typographySource.contains("(size, defaultWeight) = (11, .regular)"))
        #expect(typographySource.contains("(size, defaultWeight) = (10, .regular)"))
        #expect(componentsSource.contains("ScholiumTypography.interface(.body)"))
        #expect(
            componentsSource.contains(
                "ScholiumTypography.interface(.body, emphasis: .strong)"
            ))
        #expect(componentsSource.contains("struct SidebarTriptychAttentionEntry"))
        #expect(!componentsSource.contains("title: \"ATTENTION\""))
        #expect(
            componentsSource.contains(
                "Text(Image(systemName: \"bell\"))"
            ))
        #expect(componentsSource.contains("alignment: .firstTextBaseline"))
        #expect(
            componentsSource.contains(
                "spacing: ScholiumGrid.Spacing.labelAccessoryGap"
            ))
        #expect(!sidebarSource.contains(".focusEffectDisabled()"))
        #expect(sidebarSource.contains("ScholiumColorRole.navigationSurfaceBackground.color"))
        #expect(!sidebarSource.contains(".pickerStyle(.segmented)"))
        #expect(
            componentsSource.contains(
                "struct ScholiumEditorialIconControl<NativeControl: View>"
            ))
        #expect(componentsSource.contains(".menuStyle(.button)"))
        #expect(componentsSource.contains(".buttonStyle(.borderless)"))
        #expect(
            sidebarSource.components(
                separatedBy: "ScholiumEditorialIconControl("
            ).count == 3)
        #expect(filterMenuSource.contains("ScholiumEditorialIconControl("))
        #expect(!filterMenuSource.contains(".menuStyle(.borderlessButton)"))
        #expect(componentsSource.contains("struct ScholiumQuietRowButtonStyle"))
        #expect(!componentsSource.contains(".menuStyle(.borderlessButton)"))
        #expect(!componentsSource.contains(".accessibilityRepresentation"))
        #expect(!componentsSource.contains("Image(systemName: \"chevron"))
        #expect(componentsSource.contains(".menuIndicator(.hidden)"))
        #expect(treeRowsSource.contains("ScholiumTypography.interface(.body)"))
        #expect(treeRowsSource.contains("ScholiumTypography.interface(.body, emphasis: .strong)"))
        #expect(!componentsSource.contains("ScholiumEditorialIndexUnderline"))
        let workspaceButtonStart = try #require(
            componentsSource.range(
                of: "private struct ScholiumTriptychWorkspaceButton"
            ))
        let workspaceButtonEnd = try #require(
            componentsSource.range(
                of: "/// Page-level Library content",
                range: workspaceButtonStart.upperBound..<componentsSource.endIndex
            ))
        let workspaceButton = componentsSource[
            workspaceButtonStart.lowerBound..<workspaceButtonEnd.lowerBound
        ]
        #expect(!workspaceButton.contains(".onHover"))
        #expect(workspaceButton.contains("Button(action: select)"))
        #expect(
            workspaceButton.contains(
                ".scholiumActivationFocus(focusedSlot, equals: slot)"
            ))
        #expect(workspaceButton.contains("ScholiumContentControlButtonStyle("))
        #expect(workspaceButton.contains(".scholiumContentControlInk()"))
        #expect(!workspaceButton.contains("ScholiumControlActivation"))
        #expect(workspaceButton.contains(".scholiumForeground(.mutedText)"))
        #expect(
            workspaceButton.contains(
                "ScholiumShape.workspaceNavigationCornerRadius"
            ))
        #expect(workspaceButton.contains("RoundedRectangle"))
        #expect(!workspaceButton.contains("ScholiumEditorialIndexUnderline"))
        #expect(!workspaceButton.contains("ScholiumColorRole.accent"))
        #expect(!treeRowsSource.contains("rotationEffect(.degrees(isExpanded"))
        #expect(
            !treeRowsSource.contains(
                "withAnimation(.easeInOut(duration: 0.16)"
            ))
        #expect(sidebarSource.contains("private var triptychAttentionState"))
        #expect(componentsSource.contains("case zero"))
        #expect(componentsSource.contains("case active(count: Int)"))
        #expect(componentsSource.contains("case checking"))
        #expect(componentsSource.contains("case unavailable"))
        #expect(!componentsSource.contains("Circle().fill(controlSurface)"))
        #expect(componentsSource.contains(".scholiumForeground(.attention)"))
        #expect(componentsSource.contains("scholiumAttentionPopoverIsPresented"))
        #expect(!componentsSource.contains("SidebarTriptychAttentionButtonStyle"))
        #expect(componentsSource.contains("ScholiumContentControlButtonStyle("))
        #expect(!componentsSource.contains("SidebarAttentionAlertSurface"))
        #expect(ScholiumMetrics.Library.leadingSlotWidth == 16)
        #expect(ScholiumMetrics.Library.hierarchyRowHeight == 28)
        #expect(
            sidebarSource.contains(
                ".padding(.horizontal, ScholiumMetrics.Library.contentInset)"
            ))
        #expect(!sidebarSource.contains("attentionHorizontalInset"))
        let brandLabel = try #require(sidebarSource.range(of: "Text(\"Scholium\")"))
        let triptychMenu = try #require(
            sidebarSource.range(
                of: "Menu {",
                range: brandLabel.upperBound..<sidebarSource.endIndex
            ))
        #expect(brandLabel.lowerBound < triptychMenu.lowerBound)
        let sidebarBody = try #require(sidebarSource.range(of: "var body: some View"))
        let sidebarSectionsEnd = try #require(
            sidebarSource.range(
                of: "// MARK: Fixed identity and navigation",
                range: sidebarBody.upperBound..<sidebarSource.endIndex
            ))
        let sidebarSections = sidebarSource[
            sidebarBody.lowerBound..<sidebarSectionsEnd.lowerBound
        ]
        let workspaceNavigator = try #require(
            sidebarSections.range(
                of: "ScholiumTriptychWorkspaceNavigator"
            ))
        let library = try #require(sidebarSections.range(of: "libraryHeader"))
        let sourceRegion = try #require(sidebarSections.range(of: "sourceRegion"))
        #expect(workspaceNavigator.lowerBound < library.lowerBound)
        #expect(library.lowerBound < sourceRegion.lowerBound)
        #expect(sidebarSource.contains("SidebarTriptychAttentionEntry("))
        #expect(sidebarSource.contains(".tint(ScholiumColorRole.primaryText.color)"))
        #expect(sidebarSource.contains("let workspaceNoteCounts: SidebarWorkspaceNoteCounts"))
        #expect(sidebarSource.contains("progress: sourceRevealProgress"))
        #expect(sidebarSource.contains(".clipped()"))
        #expect(sidebarSource.contains("sourceRevealTask?.cancel()"))
        #expect(sidebarSource.contains("ScholiumMotion.triptychWorkspaceSourceReveal("))
        #expect(!sidebarSource.contains(".transition(.move"))
        #expect(sidebarSource.contains("SidebarOutlineSourceList("))
        #expect(
            sidebarSource.components(separatedBy: "SidebarOutlineSourceList(").count
                == 2
        )
        #expect(
            sidebarSource.contains(
                "private var treeProjection: LibraryTreeProjectionVersion"
            ))
        #expect(sidebarSource.contains("context.treeProjection"))
        #expect(!sidebarSource.contains("treeProjection = context.treeProjection"))
        #expect(sidebarSource.contains("projectionRevision: treeProjection.revision"))
        #expect(!sidebarSource.contains("notesAreOrdered"))
        #expect(sidebarSource.contains("treeProjection.value.roots"))
        #expect(!sidebarSource.contains("return buildTree("))
        #expect(treeProjectionSource.contains("childFoldersByParent"))
        #expect(treeProjectionSource.contains("final class LibraryTreeProjectionCache"))
        #expect(treeProjectionSource.contains("requestedInput == input"))
        #expect(treeProjectionSource.contains("LibraryTreeProjection("))
        #expect(treeProjectionSource.contains("preorderedNotes notes:"))
        #expect(
            treeProjectionSource.components(
                separatedBy: ".sorted(by: notesAreOrdered)"
            ).count == 2
        )
        #expect(!treeProjectionSource.contains("folderMap.keys.compactMap"))

        #expect(sidebarSource.contains("libraryDisclosureButton"))
        #expect(sidebarSource.contains("SidebarLibraryFilterMenu("))
        #expect(sidebarSource.contains("let filterOptions: SidebarLibraryFilterOptions"))
        #expect(sidebarSource.contains("let canMutateLibrary: Bool"))
        #expect(!sidebarSource.contains("let canCreateNote: Bool"))
        #expect(!sidebarSource.contains("let currentVaultID: UUID?"))
        #expect(sidebarSource.contains("context.disclosureScope?.vaultID"))
        #expect(filterMenuSource.contains("struct SidebarLibraryFilterMenu: View"))
        #expect(filterMenuSource.contains("let filters: DiscoveryFilterState"))
        #expect(filterMenuSource.contains("let replaceFilters:"))
        #expect(filterMenuSource.components(separatedBy: "@State").count == 1)
        #expect(!filterMenuSource.contains("@ObservedObject"))
        #expect(!sidebarSource.contains("SidebarRemovalFocusPlan"))
        #expect(sidebarSource.contains("scholium.noteList"))
        #expect(sidebarSource.contains(".contextMenu"))
        #expect(sidebarSource.contains("rootCreationActions"))
        #expect(sidebarSource.contains("scholium.libraryCreate"))
        #expect(sidebarSource.contains("Label(\"New Note\", systemImage: \"doc.badge.plus\")"))
        #expect(sidebarSource.contains("Label(\"New Folder\", systemImage: \"folder.badge.plus\")"))
        #expect(sidebarSource.contains("dynamicTypeSize.isAccessibilitySize"))
        for retiredStickyPath in [
            "pinnedViews: [.sectionHeaders]",
            "SidebarRootHeaderOffsetPreference",
            ".onPreferenceChange(",
            ".visualEffect { effect, geometry in",
            "struct SidebarSourceSection",
            "sidebarSourceSections(",
            "sidebarSourceSectionHeight(",
        ] {
            #expect(!sidebarSource.contains(retiredStickyPath))
        }

        #expect(outlineSource.contains("struct SidebarOutlineSourceList: NSViewRepresentable"))
        #expect(outlineSource.contains("let outlineView = SidebarOutlineView()"))
        #expect(outlineSource.contains("outlineView.style = .sourceList"))
        #expect(outlineSource.contains("outlineView.floatsGroupRows = false"))
        #expect(outlineSource.contains("outlineView.usesAutomaticRowHeights = false"))
        #expect(outlineSource.contains("static func dismantleNSView("))
        #expect(outlineSource.contains("coordinator.detach(from: scrollView)"))
        #expect(!outlineSource.contains("final class Coordinator"))
        #expect(!outlineSource.contains("final class SidebarOutlineRowView"))

        #expect(outlineCoordinatorSource.contains("extension SidebarOutlineSourceList"))
        #expect(outlineCoordinatorSource.contains("NSOutlineViewDataSource"))
        #expect(outlineCoordinatorSource.contains("NSOutlineViewDelegate"))
        #expect(outlineCoordinatorSource.contains("configuration.accessibilityLocationName"))
        #expect(outlineCoordinatorSource.contains("private func reconcile("))
        #expect(outlineCoordinatorSource.contains("private func refreshAvailableRows("))
        #expect(outlineCoordinatorSource.contains("makeIfNecessary: false"))
        #expect(outlineCoordinatorSource.contains("pasteboardWriterForItem item: Any"))
        #expect(outlineCoordinatorSource.contains("validateDrop info: NSDraggingInfo"))
        #expect(outlineCoordinatorSource.contains("acceptDrop info: NSDraggingInfo"))
        #expect(outlineCoordinatorSource.contains("NSOutlineViewDropOnItemIndex"))
        #expect(outlineCoordinatorSource.contains("func outlineViewSelectionDidChange"))
        #expect(
            outlineCoordinatorSource.contains(
                "outlineView.action = #selector(activateOutlineClick(_:))"
            ))
        #expect(
            !outlineCoordinatorSource.contains(
                "} else if NSApp.currentEvent?.type == .leftMouseDown"
            ))

        #expect(outlineRowsSource.contains("final class SidebarOutlineHostingCell"))
        #expect(outlineRowsSource.contains("final class SidebarOutlineRowView"))
        #expect(outlineRowsSource.contains("final class SidebarOutlineView"))
        #expect(outlineRowsSource.contains("private var hoverTrackingArea: NSTrackingArea?"))
        #expect(outlineRowsSource.components(separatedBy: "NSTrackingArea(").count == 2)
        #expect(outlineRowsSource.contains("override func mouseMoved(with event: NSEvent)"))
        #expect(outlineRowsSource.contains("private var hoveredItemID: String?"))
        #expect(!outlineRowsSource.contains("for row in 0..<numberOfRows"))
        #expect(outlineRowsSource.contains("visibleRect.contains(point)"))
        #expect(outlineRowsSource.contains("window.mouseLocationOutsideOfEventStream"))
        #expect(outlineRowsSource.contains("private var isSelectedDocument = false"))
        #expect(outlineRowsSource.contains("sidebarOutlineDocumentIsSelected("))
        #expect(outlineRowsSource.contains("width: ScholiumMetrics.Library.selectionBoundaryWidth"))
        #expect(!outlineRowsSource.contains("NSViewRepresentable"))

        #expect(treeRowsSource.contains("sidebarLibraryRowLeadingInset(depth:"))
        #expect(!treeRowsSource.contains("SidebarPointerHoverBackground("))
        #expect(!sidebarSource.contains("NSTrackingArea("))
        #expect(!treeRowsSource.contains("@State private var rowIsHovering"))
        #expect(!sidebarSource.contains(".draggable(SidebarNoteDragItem.self)"))
        #expect(!sidebarSource.contains(".draggable(SidebarFolderDragItem.self)"))
        #expect(!sidebarSource.contains(".dropDestination("))
        #expect(!sidebarSource.contains(".dropConfiguration"))
        #expect(sidebarSource.contains("SidebarLibraryHeaderDropDestination("))
        #expect(nativeDropSource.contains("guard info.draggingSource != nil"))
        #expect(nativeDropSource.contains("override func draggingEntered("))
        #expect(nativeDropSource.contains("override func performDragOperation("))
        #expect(nativeDropSource.contains("commitSidebarNativeDrop("))
        #expect(sidebarSource.contains("scholium.libraryDisclosureToggle"))
        #expect(sidebarSource.contains("\"rectangle.compress.vertical\""))
        #expect(sidebarSource.contains("\"rectangle.expand.vertical\""))
        #expect(!sidebarSource.contains("shouldCollapse ? \"chevron"))
        #expect(
            componentsSource.contains(
                "VStack(spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment)"
            ))
        #expect(sidebarSource.contains("visibleExpandedFolderIDs"))
        #expect(!sidebarSource.contains("Reveal Current Note"))
        #expect(!sidebarSource.contains("Library Navigation"))
        #expect(treeRowsSource.contains("case .rename: \"Rename…\""))
        #expect(!sidebarSource.contains("Move or Rename…"))
        #expect(!treeRowsSource.contains("struct SidebarTreeBranch"))
        #expect(!sidebarSource.contains("filteredNotes.count"))
        #expect(
            sidebarSource.components(
                separatedBy: "ScholiumEditorialIconControl("
            ).count == 3)
        #expect(filterMenuSource.contains("ScholiumEditorialIconControl("))
        #expect(!sidebarSource.contains("ScholiumEditorialIconControlLabel("))
        #expect(!filterMenuSource.contains("ScholiumEditorialIconControlLabel("))
        #expect(componentsSource.contains("struct ScholiumEditorialIconControlLabel"))
        #expect(componentsSource.contains(".scholiumContentControlPointerFeedback("))
        #expect(
            componentsSource.contains(
                "@Environment(\\.scholiumContentControlIsEmphasized)"
            ))
        #expect(!componentsSource.contains("scholiumEditorialIconControlSurface"))
        #expect(
            componentsSource.contains(
                "ScholiumShape.editorialControlCornerRadius"
            ))
        #expect(
            componentsSource.contains(
                "width: ScholiumMetrics.Accessibility.preferredCustomTarget"
            ))
        #expect(
            designSystemSource.contains(
                ".environment(\\.scholiumContentControlIsEmphasized, isEmphasized)"
            ))
        #expect(!sidebarSource.contains(".scholiumContentControlPointerFeedback("))
        #expect(!filterMenuSource.contains(".scholiumContentControlPointerFeedback("))
        #expect(!sidebarSource.contains("@State private var createControlIsHovering"))
        #expect(!sidebarSource.contains("@State private var disclosureControlIsHovering"))
        #expect(!sidebarSource.contains(".scholiumEditorialIconControlSurface("))
        #expect(!filterMenuSource.contains("@State private var isControlHovering"))
        #expect(!filterMenuSource.contains(".scholiumEditorialIconControlSurface("))
        #expect(
            outlineRowsSource.contains(
                "ScholiumContentInteractionSurface.nsColor("
            ))
        #expect(!sidebarSource.contains("Hide Sidebar"))

        for section in ["Integrity", "Metadata", "Order", "Actions"] {
            #expect(filterMenuSource.contains("Section(\"\(section)\")"))
        }
        #expect(!sidebarSource.contains("Section(\"Integrity\")"))
        #expect(!sidebarSource.contains("Section(\"Review\")"))

        #expect(
            sidebarSource.contains(
                ".background(ScholiumColorRole.navigationSurfaceBackground.color)"
            ))
        #expect(!sidebarSource.contains("SidebarLiteratureSection("))
        #expect(!sidebarSource.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))

        let brandStart = try #require(sidebarSource.range(of: "private var brandHeader"))
        let brandEnd = try #require(
            sidebarSource.range(
                of: "// MARK: Library source region",
                range: brandStart.upperBound..<sidebarSource.endIndex
            ))
        let brandHeader = sidebarSource[brandStart.lowerBound..<brandEnd.lowerBound]
        #expect(brandHeader.contains("Menu {"))
        #expect(!brandHeader.contains("Image(systemName: \"chevron.down\")"))
        #expect(sidebarSource.contains("ScholiumTriptychWorkspaceNavigator("))
        #expect(
            componentsSource.contains(
                "struct ScholiumTriptychWorkspaceNavigator: View"
            ))
        #expect(componentsSource.contains("ScholiumTypography.interface(.body)"))
        #expect(componentsSource.contains("@FocusState private var focusedSlot"))
        #expect(componentsSource.contains(".onMoveCommand(perform: move)"))
        #expect(componentsSource.contains("case .up:"))
        #expect(componentsSource.contains("case .down:"))
        #expect(!sidebarSource.contains("private var scopeIndex"))
        #expect(!sidebarSource.contains(".font(.system(size: 12"))
    }

    @Test("System Trash uses one explicit confirmation and no internal lifecycle UI")
    func systemTrashConfirmationContract() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let confirmation = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/SystemTrashConfirmationView.swift"
            ),
            encoding: .utf8
        )
        let sidebar = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Sidebar/SidebarTreeRows.swift"
            ),
            encoding: .utf8
        )
        let app = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let content = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/ContentView.swift"
            ),
            encoding: .utf8
        )

        #expect(confirmation.contains("Finder owns file restoration"))
        #expect(confirmation.contains("Finished Research Records remain available"))
        #expect(!confirmation.contains("preview.records"))
        #expect(!confirmation.contains("unaffectedParticipants"))
        #expect(sidebar.contains("requestSystemTrash"))
        #expect(sidebar.contains("requestFolderSystemTrash"))
        #expect(app.contains(".keyboardShortcut(.delete, modifiers: [.command])"))
        #expect(content.contains("Archive Unreadable Research Actions?"))
        #expect(content.contains("Archive and Continue"))
        #expect(content.contains("secondaryButton: .destructive"))
    }

    @Test("Notifications search lives in the transient Workspace popover without custom close chrome")
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
        let componentsSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumComponents.swift"
            ),
            encoding: .utf8
        )
        let contentSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/ContentView.swift"
            ),
            encoding: .utf8
        )
        let actionStackStart = try #require(
            componentsSource.range(
                of: "struct ResearchActivityNotificationStack: View"
            )
        )
        let actionStackEnd = try #require(
            componentsSource.range(
                of: "private struct ResearchActivityNotificationBannerRow",
                range: actionStackStart.upperBound..<componentsSource.endIndex
            )
        )
        let actionStackSource = componentsSource[
            actionStackStart.lowerBound..<actionStackEnd.lowerBound
        ]
        let settlementRowStart = try #require(
            attentionSource.range(
                of: "struct SettlementRequirementNotificationRow: View"
            )
        )
        let settlementRowEnd = try #require(
            attentionSource.range(
                of: "struct AttentionQueueRow: View",
                range: settlementRowStart.upperBound..<attentionSource.endIndex
            )
        )
        let settlementRowSource = attentionSource[
            settlementRowStart.lowerBound..<settlementRowEnd.lowerBound
        ]
        #expect(attentionSource.contains("TextField(\"Search Notifications\""))
        #expect(attentionSource.contains("Picker(\"Notification Type\""))
        #expect(attentionSource.contains("Text(\"Action Activities\")"))
        #expect(attentionSource.contains("scholium.attentionSearch"))
        #expect(attentionSource.contains(".popover("))
        #expect(
            attentionSource.contains(
                "\\.scholiumAttentionPopoverIsPresented"
            ))
        #expect(attentionSource.contains("AttentionPopoverContent(session: session)"))
        #expect(attentionSource.contains("session.dismiss()"))
        #expect(
            attentionSource.contains(
                ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)"
            ))
        #expect(!attentionSource.contains(".searchable("))
        #expect(!attentionSource.contains("placement: .toolbar"))
        #expect(attentionSource.contains("private var issueSummary"))
        #expect(attentionSource.contains("in: Capsule(style: .continuous)"))
        #expect(attentionSource.contains("Text(\"/\")"))
        #expect(attentionSource.contains(".frame(maxWidth: .infinity, alignment: .trailing)"))
        #expect(!attentionSource.contains("case .changeAttributionNeeded"))
        #expect(appSource.contains("lazy var attentionPopoverSession"))
        #expect(!appSource.contains("Window(\"Attention\", id: \"scholium-attention\")"))
        #expect(!appSource.contains("AttentionWindowSession"))
        #expect(!attentionSource.contains("Button(\"Close\""))

        #expect(!attentionSource.contains(
            "ActionActivityNotificationPopoverContent"
        ))
        #expect(!attentionSource.contains("presentedActivityRunID"))
        #expect(!attentionSource.contains("notification.actionDetail"))
        #expect(actionStackSource.contains("if let firstItem = items.first"))
        #expect(actionStackSource.contains("banner(for: firstItem, disclosure: disclosure)"))
        #expect(actionStackSource.contains("settlementRequirement:"))
        #expect(actionStackSource.contains("reviewSettlementChanges:"))
        #expect(actionStackSource.contains("ResearchActivityNotificationBannerRow("))
        #expect(actionStackSource.contains("SettlementRequirementNotificationBanner("))
        #expect(settlementRowSource.contains("Button(\"Review Changes\""))
        #expect(settlementRowSource.contains(
            "if !requirement.pendingActivities.isEmpty"
        ))
        #expect(!settlementRowSource.contains("Button(\"Settle\""))
        #expect(actionStackSource.contains("private var expandedRows"))
        #expect(actionStackSource.contains("ForEach(Array(items.dropFirst()))"))
        #expect(actionStackSource.contains("return VStack(spacing:"))
        #expect(actionStackSource.contains("if isExpanded"))
        #expect(!actionStackSource.contains("summaryHeight"))
        #expect(!actionStackSource.contains("summaryButton"))
        #expect(!actionStackSource.contains("notificationSummary"))
        #expect(actionStackSource.contains("expansionRequestGeneration"))
        #expect(componentsSource.contains("Show Notifications"))
        #expect(componentsSource.contains("Hide Notifications"))
        #expect(componentsSource.contains("scholium.notificationStack.disclosure"))
        #expect(!actionStackSource.contains(".onChange(of: summaryIsFocused)"))
        #expect(!String(actionStackSource).localizedCaseInsensitiveContains("popover"))
        #expect(contentSource.contains("actionNotificationStackExpansionGeneration"))
        #expect(contentSource.contains("presentAgentChanges(for: requirement)"))
        #expect(!contentSource.contains(
            "reviewSettlementChanges: { _ in\n                    windowCoordinator.actions.showNoteResearchRecords()"
        ))
        #expect(!contentSource.contains(".scholiumAttentionPopover(anchor: .activityStack"))
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
            #expect(
                !FileManager.default.fileExists(
                    atPath: repository.appendingPathComponent(path).path))
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
        let sidebarRowsSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Sidebar/SidebarTreeRows.swift"
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
        #expect(sidebarRowsSource.contains("struct SidebarNoteRow"))
        #expect(!sidebarRowsSource.contains("struct NoteCardRow"))
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

        #expect(
            uiTestSource.contains(
                "testDocumentHeadingStudyWrapsLongMixedTitleUsingAcceptedBodyRhythm"))
        #expect(uiTestSource.contains("--scholium-document-heading-proof"))
        #expect(uiTestSource.contains("XCUIApplication(bundleIdentifier: \"com.scholium.qa\")"))
        #expect(uiTestSource.contains("workspace.screenshot()"))
        #expect(uiTestSource.contains("lineHeight: 2.00"))
        #expect(uiTestSource.contains("paragraphSpacing: 1.00"))
        #expect(uiTestSource.contains("letterSpacing: 0.020"))
        #expect(!uiTestSource.contains("lineHeight: 1.80"))
        #expect(!uiTestSource.contains("lineHeight: 1.65"))
        #expect(uiTestSource.contains("XCTAssertEqual(sliderNumericValue(lineWidth), 72)"))
        #expect(
            uiTestSource.contains(
                "Heading Study — accepted A — long mixed H1 — 1180×760 — Review — native window title"
            ))
        #expect(
            uiTestSource.contains(
                "Heading Study — accepted A — long mixed H1 — 900×760 — Review — native window title"
            ))
        #expect(uiTestSource.contains("在长期论证中保持证据边界：Reasons, Values"))
        #expect(!uiTestSource.contains("## Abstract"))
        #expect(
            uiTestSource.contains("XCTAssertEqual(try Data(contentsOf: noteURL), sourceBefore)"))
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

    @Test("Inspector modes and the Document Action rail keep distinct geometry owners")
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
        let aboutEditorSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Sidebar/AboutEditablePropertyRow.swift"
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
        let contentSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/ContentView.swift"
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
            ScholiumMetrics.Apparatus.connectionDirectionControlMaximumWidth == 240
        )
        #expect(ScholiumMetrics.Apparatus.connectionGroupContentSpacing == 8)
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
        #expect(ScholiumMetrics.Apparatus.relationGlyphSize == 14)
        #expect(ScholiumMetrics.Apparatus.relationGlyphToTextSpacing == 4)
        #expect(ScholiumMetrics.Apparatus.relationClusterSpacing == 12)
        #expect(ScholiumMetrics.Apparatus.relationRowMinimumHeight == 28)
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
        #expect(componentsSource.contains("ScholiumSegmentedControl("))
        #expect(sharedComponentsSource.contains("struct ScholiumSegmentedControl<Value: Hashable>"))
        #expect(sharedComponentsSource.contains("ScholiumShape.segmentedControlCornerRadius"))
        #expect(sharedComponentsSource.contains("ScholiumColorRole.surfaceBackground.color"))
        #expect(
            sharedComponentsSource.contains(
                "ScholiumContentInteractionSurface.selectionColor("
            )
        )
        #expect(!sharedComponentsSource.contains("private var selectedSurfaceColor"))
        #expect(sharedComponentsSource.contains(".scholiumElevation(.floatingControl)"))
        #expect(sharedComponentsSource.contains(".scholiumActivationFocus(focusedValue, equals: value)"))
        #expect(sharedComponentsSource.contains(".onMoveCommand(perform: move)"))
        #expect(sharedComponentsSource.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
        #expect(!sharedComponentsSource.contains(".tint(ScholiumColorRole.mutedText.color)"))
        #expect(!componentsSource.contains("struct ScholiumConnectionGlyph"))
        #expect(componentsSource.contains("ViewThatFits(in: .horizontal)"))
        #expect(componentsSource.contains("ForEach(visibleFacts)"))
        #expect(
            componentsSource.contains(
                "idealWidth: ScholiumMetrics.Apparatus.factValueMinimumWidth"
            ))
        #expect(sharedComponentsSource.contains("configuration.isPressed"))
        #expect(
            componentsSource.contains(
                "ScholiumTypography.interface(.compact, emphasis: .strong)"
            ))
        #expect(!componentsSource.contains(".accessibilityHint(detail"))
        #expect(
            componentsSource.contains(
                "width: ScholiumMetrics.Apparatus.iconColumnWidth"
            ))
        #expect(
            componentsSource.contains(
                ".padding(.bottom, ScholiumMetrics.Apparatus.sectionContentSpacing)"
            ))
        #expect(
            componentsSource.contains(
                ".lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)"
            ))
        #expect(
            researchSource.contains(
                ".padding(.horizontal, ScholiumMetrics.Apparatus.contentInset)"
            ))
        #expect(researchSource.contains("attentionSection"))
        #expect(!researchSource.contains("if !context.visibleAttentionItems.isEmpty"))
        #expect(researchSource.contains(".scholiumForeground(.attention)"))
        #expect(
            researchSource.contains(
                "ScholiumTypography.scholarly(.emphasis)"
            ))
        #expect(researchSource.contains("aboutSection"))
        #expect(researchSource.contains("aboutGroups"))
        #expect(researchSource.contains("ScholiumPropertyGroup("))
        #expect(!researchSource.contains("Text(group.group.label)"))
        #expect(sharedComponentsSource.contains("struct ScholiumPropertyGroup"))
        #expect(sharedComponentsSource.contains("semanticGroupSeparation"))
        #expect(sharedComponentsSource.contains("isVisuallyRevealed"))
        #expect(sharedComponentsSource.contains(".opacity(isVisuallyRevealed || isFocused ? 1 : 0)"))
        #expect(researchSource.contains("AboutEditablePropertyRow("))
        #expect(aboutEditorSource.contains("PropertyPresentationCatalog.choiceDisplayName("))
        #expect(researchSource.contains("ScholiumApparatusFactGrid(facts: fileHistoryFacts)"))
        #expect(researchSource.contains("ScholiumApparatusFactGrid(facts: settlementFacts)"))
        #expect(researchSource.contains("ResearchProjectionFreshnessView("))
        #expect(researchSource.contains("ScholiumApparatusStateView("))
        #expect(
            connectionsSource.contains(
                ".padding(.horizontal, ScholiumMetrics.Apparatus.contentInset)"
            ))
        #expect(
            connectionsSource.contains(
                "Image(systemName: cluster.presentation.systemSymbol.systemName)"
            ))
        #expect(componentsSource.contains("struct ScholiumDisclosureHeaderButton"))
        #expect(componentsSource.contains("Image(systemName: \"chevron.right\")"))
        #expect(
            componentsSource.contains(
                "ScholiumMotion.disclosure(reduceMotion: reduceMotion)"
            ))
        #expect(connectionsSource.contains("ScholiumDisclosureHeaderButton("))
        #expect(
            connectionsSource.contains(
                "ScholiumTypography.interface(.body)"
            ))
        #expect(actionsSource.contains("struct DocumentResearchActionRail"))
        #expect(actionsSource.contains("scholium.documentActionRail"))
        #expect(actionsSource.contains("scholium.documentActionRail.actions"))
        #expect(contentSource.contains(".overlay(alignment: .trailing)"))
        #expect(!contentSource.contains(".overlay(alignment: .topTrailing)"))
        #expect(!contentSource.contains("+ actionRailCenterOffset"))
        #expect(!actionsSource.contains("verticalCenterOffset"))
        #expect(sharedComponentsSource.contains("SettlementRequirementNotificationBanner("))
        #expect(contentSource.contains("settlementRequirement: currentSettlementRequirement"))
        #expect(actionsSource.contains("ScholiumContentControlButtonStyle("))
        #expect(actionsSource.contains(".scholiumEditorialSurface(.floatingControl"))
        #expect(actionsSource.contains(".fixedSize(horizontal: true, vertical: false)"))
        #expect(!actionsSource.contains("scholium.documentActionRail.review"))
        #expect(actionsSource.contains(".accessibilityLabel(Text(verbatim: item.title))"))
        #expect(actionsSource.contains("railIcon("))
        #expect(!actionsSource.contains("title: Text(verbatim: item.title)"))
        #expect(!actionsSource.contains("ResearchActionsInspectorView"))
        #expect(!actionsSource.contains("ResearchActionVisualSection"))
        #expect(!actionsSource.contains("BuiltInActionVisualGroup"))
        #expect(!actionsSource.contains("ScholiumApparatusSection(\"JUDGMENT\")"))
        #expect(!actionsSource.contains("@FocusedValue(\\.scholiumResearchActionActions)"))
        #expect(!actionsSource.contains("ScholiumControlActivation"))
        #expect(!sharedComponentsSource.contains("ScholiumControlActivation"))
        #expect(!actionsSource.contains("ScholiumStructuralRule()"))
        #expect(!actionsSource.contains("ResearchActionHelpModifier"))
        #expect(!actionsSource.contains("helpText"))
        #expect(actionsSource.contains(".accessibilityHint(Text(verbatim: item.detail"))
        #expect(contentSource.contains("documentResearchActionRail"))
        #expect(contentSource.contains(".overlay(alignment: .trailing)"))
        #expect(!noteSource.contains("case .actions:"))
        #expect(!researchSource.contains("scholium.researchOverview.review"))
        #expect(researchSource.contains("visibleAttentionKinds.prefix(3)"))
        #expect(!researchSource.contains("Text(item.message)"))
        #expect(!researchSource.contains("\"Show All\""))
        #expect(!researchSource.contains("ResearchUnit"))
        #expect(researchSource.contains("AboutProfileCatalog.groupedEntries"))
        #expect(researchSource.contains("presentManagedFields: Set(note.managedMetadataFields.keys)"))
        #expect(researchSource.contains("saveManagedAboutField"))
        #expect(researchSource.contains("saveAuthoredAboutField"))
        #expect(researchSource.contains("ScholiumApparatusSectionHeaderButton("))
        #expect(researchSource.contains("actionLabel: \"Add Field\""))
        #expect(researchSource.contains("accessibilityIdentifier: \"scholium.about.edit\""))
        #expect(researchSource.contains(".accessibilityIdentifier(\"scholium.about\")"))
        #expect(researchSource.contains("title: Text(\"Open in Zotero\")"))
        #expect(researchSource.contains("systemImage: \"arrow.up.forward.app\""))
        #expect(researchSource.contains("\"Link Zotero Item…\""))
        #expect(researchSource.contains("\"Manage Zotero Link…\""))
        #expect(researchSource.contains(
            ".accessibilityIdentifier(\"scholium.researchOverview.manageZoteroBinding\")"
        ))
        #expect(
            researchSource.contains(
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
        #expect(connectionsSource.contains("ScholiumSegmentedControl("))
        #expect(!connectionsSource.contains(".pickerStyle(.segmented)"))
        #expect(
            connectionsSource.contains(
                ".connectionDirectionControlMaximumWidth"
            ))
        #expect(
            connectionsSource.contains(
                ".frame(maxWidth: .infinity, alignment: .center)"
            ))
        #expect(connectionsSource.contains("if context.freshness.isActionable"))
        #expect(connectionsSource.contains("if isExpanded && !items.isEmpty"))
        #expect(connectionsSource.contains("connectionGroupContentSpacing"))
        #expect(connectionsSource.contains(".id(connectionScrollTopID)"))
        #expect(!connectionsSource.contains("Color.clear"))
        #expect(connectionsSource.contains("@State private var direction"))
        #expect(
            connectionsSource.contains(
                "ScholiumTypography.interface(.compact, emphasis: .strong)"
            ))
        #expect(
            connectionsSource.contains(
                "ScholiumTypography.interface(.body)"
            ))
        #expect(
            !connectionsSource.contains(
                "ScholiumTypography.scholarly(.body)"
            ))
        #expect(!connectionsSource.contains("relationPinnedGlyphTop"))
        #expect(!connectionsSource.contains("GeometryReader"))
        #expect(!connectionsSource.contains("symbolText"))
        #expect(connectionsSource.contains("Open relation source"))
        #expect(!connectionsSource.contains("Image(systemName: \"arrow.up.forward\")"))
        #expect(!connectionsSource.contains("Text(\"↗\")"))
        #expect(!connectionsSource.contains("DisclosureGroup(\n            isExpanded:"))
        #expect(noteSource.contains("ScholiumInspectorModeIndex("))
        #expect(appSource.contains("case .researchConfigurationInvalidated = event"))
        #expect(appSource.contains("refreshResearchActionAvailability()"))
    }

    @Test("Current matching segmented choices use the shared Scholium presentation")
    func segmentedControlPresentationOwner() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let consumerPaths = [
            "Scholium/UI/Components/ScholiumApparatusComponents.swift",
            "Scholium/Views/Backlinks/ConnectionsInspectorView.swift",
            "Scholium/Views/WorkspaceSettingsView.swift",
            "Scholium/Views/SearchWorkspaceView.swift",
            "Scholium/Views/Metadata/MetadataEditorView.swift",
            "Scholium/Views/ResearchRecord/ResearchRecordBrowserView.swift",
        ]
        let consumerSources = try consumerPaths.map { path in
            try String(
                contentsOf: repository.appendingPathComponent(path),
                encoding: .utf8
            )
        }
        let sharedSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumComponents.swift"
            ),
            encoding: .utf8
        )

        for source in consumerSources {
            #expect(source.contains("ScholiumSegmentedControl("))
            #expect(!source.contains(".pickerStyle(.segmented)"))
            #expect(!source.contains("NSSegmentedControl("))
        }
        #expect(
            consumerSources.reduce(0) {
                $0 + $1.components(separatedBy: "ScholiumSegmentedControl(").count - 1
            } == consumerPaths.count
        )
        #expect(sharedSource.contains("ScholiumColorRole.surfaceBackground.color"))
        #expect(
            sharedSource.contains(
                "ScholiumContentInteractionSurface.selectionColor("
            )
        )
        #expect(!sharedSource.contains("private var selectedSurfaceColor"))
        #expect(sharedSource.contains("ScholiumShape.segmentedControlCornerRadius"))
        #expect(sharedSource.contains("ScholiumShape.editorialControlCornerRadius"))
        #expect(sharedSource.contains(".accessibilityValue(Text(verbatim: selectedTitle))"))
    }

    @Test("The Library plane is opaque, Liquid Glass is absent, and no-note is restrained")
    func scholarlyEditorialWorkspaceSurfaceContract() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        #expect(
            !FileManager.default.fileExists(
                atPath: repository.appendingPathComponent(
                    "Scholium/Resources/Artwork/ScholiumFeaturedFolioLight.png"
                ).path))
        #expect(
            !FileManager.default.fileExists(
                atPath: repository.appendingPathComponent(
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
        #expect(content.contains("ScholiumContentStateView("))
        #expect(content.contains("\"No Document Selected\""))
        #expect(content.contains("detail: Text(\"Select a note in the Library to read or edit.\")"))
        #expect(content.contains(".accessibilityIdentifier(\"scholium.noDocumentState\")"))
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
        #expect(
            ScholiumWorkspaceToolbarController.Item.headingOutline.rawValue
                == "scholium.toolbar.headingOutline"
        )
        #expect(
            ScholiumWorkspaceToolbarController.Item.search.rawValue
                == "scholium.toolbar.search"
        )
        #expect(
            ScholiumWorkspaceToolbarController.Item.researchRecords.rawValue
                == "scholium.toolbar.researchRecords"
        )
        #expect(toolbar.contains("windowActions.showNoteResearchRecords()"))
        #expect(toolbar.contains("windowActions.showTriptychResearchRecords()"))
        #expect(toolbar.contains("hasRecords(in: presentation.scope) ? \"tray.full\" : \"tray\""))
        #expect(toolbar.contains("record.participatingNotes.contains { $0.noteID == noteID }"))
        #expect(!toolbar.contains("clock.arrow.circlepath"))
        #expect(!toolbar.contains("static let documentCommands"))
        #expect(!toolbar.contains("ScholiumWorkspaceDocumentCommandsToolbarView"))
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
        let forbiddenLiquidGlassAPIs = [
            "glassEffect(",
            "GlassEffectContainer",
            ".buttonStyle(.glass",
        ]
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: productionRoot,
                includingPropertiesForKeys: nil
            )
        )
        for case let sourceURL as URL in enumerator where sourceURL.pathExtension == "swift" {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            for forbiddenAPI in forbiddenLiquidGlassAPIs {
                #expect(
                    !source.contains(forbiddenAPI),
                    "\(sourceURL.lastPathComponent) must not use \(forbiddenAPI)"
                )
            }
        }

    }

    @Test("Page and pane states share presentation without sharing workflow ownership")
    func contentStatePresentationResponsibility() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let components = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumComponents.swift"
            ),
            encoding: .utf8
        )
        let note = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/NoteContentView.swift"
            ),
            encoding: .utf8
        )
        let records = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/ResearchRecord/ResearchRecordBrowserView.swift"
            ),
            encoding: .utf8
        )
        let search = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/SearchWorkspaceView.swift"
            ),
            encoding: .utf8
        )
        let sidebar = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Sidebar/SidebarView.swift"
            ),
            encoding: .utf8
        )

        #expect(components.contains("struct ScholiumContentStateView<Actions: View>"))
        #expect(components.contains("enum ScholiumContentStatePlacement"))
        #expect(components.contains("enum ScholiumContentStateDensity"))
        #expect(components.contains("maxWidth: ScholiumMetrics.ContentState.readableWidth"))
        #expect(components.contains("if placement == .centered || density == .page"))
        #expect(components.contains("private var contentGroupSpacing: CGFloat"))
        #expect(components.contains(".accessibilityElement(children: .contain)"))
        #expect(note.contains("\"Empty Note\""))
        #expect(note.contains("\"Review Mode Unavailable\""))
        #expect(records.contains("ScholiumContentStateView("))
        #expect(!records.contains("ContentUnavailableView"))
        #expect(
            !records.contains(
                ".padding(.bottom, ScholiumGrid.Spacing.regionContentInset)"
            ))
        #expect(search.contains("\"No Search Results\""))
        #expect(!search.contains("ContentUnavailableView"))
        #expect(sidebar.contains("placement: .leading"))
        #expect(sidebar.contains("density: .compact"))
    }

    @Test("Independent windows do not share presentation or document sessions")
    func windowIsolation() {
        let firstRouter = WindowPresentationRouter()
        let secondRouter = WindowPresentationRouter()
        firstRouter.present(.transactionRecovery)
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
        original.preparePresentationMode(.source)
        original.editingSource = "exact markdown bytes\n"

        let afterProjectionChange = store.session(for: key)
        #expect(afterProjectionChange === original)
        #expect(afterProjectionChange.presentationMode == .read)
        #expect(afterProjectionChange.pendingEditorMode == .source)
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

        controller.failSearch(.failed("stale"), for: firstRequest)
        #expect(controller.search.executionIssue == nil)
        #expect(controller.search.criteria.query == "second")

        controller.failSearch(.failed("current"), for: secondRequest)
        #expect(controller.search.executionIssue == .failed("current"))
    }

    @Test("Search preparation failures close only the matching pending projection")
    func searchPreparationFailureClosesPendingProjection() {
        let controller = DiscoveryController()
        let first = SearchWorkspaceState(query: "first", scope: .thisNote)
        let second = SearchWorkspaceState(query: "second", scope: .triptych)

        controller.replaceSearchCriteria(first)
        #expect(controller.search.isRunning)
        controller.replaceSearchCriteria(second)
        controller.failPendingSearch(.failed("late bridge failure"), for: first)

        #expect(controller.search.criteria == second)
        #expect(controller.search.isRunning)
        #expect(controller.search.executionIssue == nil)

        controller.failPendingSearch(.failed("current bridge failure"), for: second)
        #expect(!controller.search.isRunning)
        #expect(controller.search.executionIssue == .failed("current bridge failure"))
    }

    @Test("Search rejects a response whose contract request ID does not match the active request")
    func searchResponseRequestIDRejection() {
        let controller = DiscoveryController()
        let request = controller.beginSearch(
            SearchWorkspaceState(
                query: "identity",
                scope: .triptych
            ))
        let generation = SearchGenerationID(
            triptychID: UUID(),
            sequence: 1,
            sourceManifestHash: "manifest"
        )
        controller.receiveSearchResponse(
            SearchResponse(
                requestID: UUID(),
                scope: .triptych,
                explanation: SearchExplanation(
                    provider: .note,
                    providerWasExplicit: false,
                    scope: .triptych,
                    clauses: []
                ),
                freshnessToken: .triptych(generation),
                availability: .note(.current(generation)),
                results: [],
                hasMore: false
            ), for: request)

        #expect(controller.search.responseRequestID == nil)
        #expect(controller.search.results.isEmpty)
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
        let hit = NoteSearchResult(
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
        let first = controller.beginSearch(
            SearchWorkspaceState(
                query: "first",
                scope: .triptych
            ))
        controller.receiveSearchResponse(
            SearchResponse(
                requestID: first.id,
                scope: .triptych,
                explanation: SearchExplanation(
                    provider: .note,
                    providerWasExplicit: false,
                    scope: .triptych,
                    clauses: []
                ),
                freshnessToken: freshness,
                availability: .note(.current(generation)),
                results: [.note(hit)],
                hasMore: false
            ), for: first)
        #expect(controller.search.results.count == 1)
        #expect(controller.search.explanation?.provider == .note)
        #expect(controller.search.selectedResultID == nil)

        controller.updateSearchQuery("second")

        #expect(controller.search.criteria.query == "second")
        #expect(controller.search.explanation == nil)
        #expect(controller.search.selectedResultID == nil)
        #expect(controller.search.results.isEmpty)
        #expect(controller.search.isRunning)
        #expect(!controller.isCurrentSearch(first))

        let second = controller.beginSearch(controller.search.criteria)
        controller.receiveSearchResponse(
            SearchResponse(
                requestID: second.id,
                scope: .thisNote,
                explanation: SearchExplanation(
                    provider: .note,
                    providerWasExplicit: false,
                    scope: .thisNote,
                    clauses: []
                ),
                freshnessToken: freshness,
                availability: .note(.current(generation)),
                results: [.note(hit)],
                hasMore: false
            ), for: second)
        controller.selectSearchScope(.thisNote)
        #expect(controller.search.criteria.scope == .thisNote)
        #expect(controller.search.results.isEmpty)
        #expect(controller.search.isRunning)
        #expect(!controller.isCurrentSearch(second))

        let scoped = controller.beginSearch(controller.search.criteria)
        controller.receiveSearchResponse(
            SearchResponse(
                requestID: scoped.id,
                scope: .thisNote,
                explanation: SearchExplanation(
                    provider: .note,
                    providerWasExplicit: false,
                    scope: .thisNote,
                    clauses: []
                ),
                freshnessToken: freshness,
                availability: .note(.current(generation)),
                results: [.note(hit)],
                hasMore: false
            ), for: scoped)
        controller.replaceSearchCriteria(
            SearchWorkspaceState(
                query: "saved",
                scope: .currentVault
            ))
        #expect(controller.search.criteria.query == "saved")
        #expect(controller.search.criteria.scope == .currentVault)
        #expect(controller.search.results.isEmpty)
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
                range: searchBoundary.upperBound..<searchSource.endIndex
            )
        )
        let implementation = searchSource[
            searchBoundary.lowerBound..<dismissalBoundary.lowerBound
        ]
        #expect(implementation.contains("discoveryController.presentSearch(invocation)"))
        #expect(!implementation.contains("flushRegisteredEditorIfNeeded"))
        #expect(!implementation.contains("save"))
    }

    @Test("Search completion and results share one keyboard-selection path")
    func searchKeyboardSelectionIsExclusive() throws {
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

        #expect(source.contains("if !moveCompletion(.down) { moveSelection(.down) }"))
        #expect(source.contains("if !moveCompletion(.up) { moveSelection(.up) }"))
        let completionStart = try #require(
            source.range(of: "private func moveCompletion(")
        )
        let completionEnd = try #require(
            source.range(
                of: "private func acceptCompletion(",
                range: completionStart.upperBound..<source.endIndex
            ))
        let completionMove = source[
            completionStart.lowerBound..<completionEnd.lowerBound
        ]
        #expect(completionMove.contains("controller.selectSearchResult(nil)"))
        #expect(source.contains("completion.replacementText"))
        #expect(!source.contains("SearchToken("))
        #expect(!source.contains("SearchChip("))
    }

    @Test("Explain Query presents the typed response without reparsing the query")
    func typedSearchExplanationPresentation() throws {
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
        #expect(source.contains("controller.search.explanation"))
        #expect(source.contains("localizedScopeTitle(explanation.scope)"))
        #expect(source.contains("explanation.providerWasExplicit"))
        #expect(source.contains("explanation.operator"))
        #expect(source.contains("explanation.normalization"))
        #expect(source.contains("explanation.ordering"))
        #expect(source.contains("explanation.limitations"))
        #expect(!source.contains("SearchQueryParser.parse"))
        #expect(source.contains("switch clause.kind"))
        #expect(source.contains("case .lexical("))
        #expect(source.contains("case .structured("))
        #expect(source.contains("case .property("))
        #expect(source.contains("case .relation("))
        #expect(source.contains("case .record("))
        #expect(source.contains("Explain Query:"))
    }

    @Test("Search has no parallel Related provider or selection path")
    func searchHasOneResultPath() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "Scholium/Views/SearchWorkspaceView.swift",
            "Scholium/Features/Discovery/DiscoveryController.swift",
            "Scholium/App/Window/WindowDomainTypes.swift",
            "Scholium/App/Window/WindowSearchController.swift",
            "ScholiumContracts/UseCases.swift",
            "ScholiumApplication/Operations.swift",
        ]
        let sources = try relativePaths.map { path in
            try String(
                contentsOf: repository.appendingPathComponent(path),
                encoding: .utf8
            )
        }.joined(separator: "\n")

        for removed in [
            "Related" + "Search",
            "related" + "Items",
            "related" + "Availability",
            "related" + "Results(",
            "case " + "related(",
            "case ." + "related",
            "open(." + "related",
        ] {
            #expect(
                !sources.contains(removed),
                Comment(rawValue: "Search still contains removed path: \(removed)")
            )
        }
        #expect(sources.contains("case result(SearchResult)"))
        #expect(sources.contains("ForEach(controller.search.results)"))
    }

    @Test("Research Inspector has one trailing-context owner")
    func researchContextExclusivity() {
        let controller = ResearchController()
        #expect(!controller.inspector.isVisible)
        controller.showResearchInspector(true)
        #expect(controller.inspector.isVisible)
    }

    @Test("Research Records is a Triptych-bound auxiliary window with transient routing")
    func researchRecordsWindowOwnershipAndRouting() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let coordinator = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/App/Window/ResearchRecordsWindowCoordinator.swift"
            ),
            encoding: .utf8
        )
        let feature = try String(
            contentsOf: repository.appendingPathComponent(
                "ScholiumResearchRecordsFeature/ResearchRecordBrowserModel.swift"
            ),
            encoding: .utf8
        )
        let route = try String(
            contentsOf: repository.appendingPathComponent(
                "ScholiumResearchRecordsFeature/ResearchRecordsRoute.swift"
            ),
            encoding: .utf8
        )
        let browser = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/ResearchRecord/ResearchRecordBrowserView.swift"
            ),
            encoding: .utf8
        )
        let windowManagement = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWindowManagement.swift"
            ),
            encoding: .utf8
        )
        let splitView = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWorkspaceSplitView.swift"
            ),
            encoding: .utf8
        )

        #expect(app.contains("WindowGroup(\n            \"Research Records\""))
        #expect(app.contains("for: UUID.self"))
        #expect(app.contains("workspaceStore.workspaceCapabilities(id: triptychID)"))
        #expect(app.contains(".windowResizability(.contentMinSize)"))
        #expect(app.contains(".frame(minWidth: 700, minHeight: 520)"))
        #expect(app.contains(".restorationBehavior(.disabled)"))
        #expect(app.contains(".windowToolbarStyle(.unified(showsTitle: false))"))
        #expect(app.contains("@AppStorage(WindowColorSchemeChoice.defaultsKey)"))
        #expect(app.contains("WindowColorSchemeChoice(rawValue: storedColorScheme)"))
        #expect(coordinator.contains("final class ResearchRecordsWindowCoordinator"))
        #expect(coordinator.contains("pendingRequests"))
        #expect(coordinator.contains("openInExistingWorkspace"))
        #expect(!coordinator.contains("FileManager"))
        #expect(!coordinator.contains("WindowModel"))
        #expect(!browser.contains("HSplitView"))
        #expect(!browser.contains("List(selection:"))
        #expect(browser.contains("ResearchRecordsCollectionView"))
        #expect(browser.contains("ResearchRecordWorkspaceView"))
        #expect(!browser.contains("ResearchRecordRouteHeader"))
        #expect(browser.contains("ResearchRecordsBackToolbarButton"))
        #expect(browser.contains("scholium.researchRecord.toggleEvidence"))
        #expect(
            browser.contains(
                ".toolbarBackgroundVisibility(.hidden, for: .windowToolbar)"
            ))
        #expect(browser.contains("sharedBackgroundVisibility(.hidden)"))
        #expect(browser.contains("ResearchRecordsViewIndex"))
        #expect(browser.contains("ScholiumSegmentedControl("))
        #expect(!browser.contains("NSSegmentedControl("))
        #expect(!browser.contains("control.selectedSegmentBezelColor"))
        #expect(!browser.contains("ResearchRecordsViewIndexButton"))
        #expect(!browser.contains("ResearchRecordsViewIndexUnderline"))
        #expect(!browser.contains("ResearchRecordsRouteToolbarTitle(title: \"Record\")"))
        #expect(!browser.contains("recordStatusColumnWidth"))
        #expect(!browser.contains("recordReliabilityColumnWidth"))
        #expect(!browser.contains("recordCoverageColumnWidth"))
        #expect(browser.contains("recordAttentionColumnWidth"))
        #expect(!browser.contains("recordAttentionPillHeight"))
        #expect(browser.contains("Capsule(style: .continuous)"))
        #expect(browser.contains("ResearchRecordCollectionAttention"))
        #expect(!browser.contains("recordActionIconWidth"))
        #expect(!browser.contains("recordActionLabelGap"))
        #expect(!browser.contains("collectionSubtitle"))
        #expect(!browser.contains("provenanceLine"))
        #expect(!browser.contains("recordResultColumnWidth"))
        #expect(!browser.contains("recordTimeColumnWidth"))
        #expect(browser.contains("ResearchRecordsScopeMenu"))
        #expect(!browser.contains("ResearchRecordsWindowHeader"))
        #expect(browser.contains("scholium.researchRecords.scope"))
        #expect(browser.contains("scholium.researchRecords.view"))
        #expect(browser.contains(".tint(ScholiumColorRole.accent.color)"))
        #expect(browser.contains("ScholiumRecordDetailSplitView("))
        #expect(browser.contains(".ignoresSafeArea(.container, edges: .top)"))
        #expect(splitView.contains("ScholiumMetrics.ResearchRecords.evidenceWidthFraction"))
        #expect(splitView.contains("backgroundRole: .apparatus"))
        #expect(splitView.contains("structuralDepthRole: .readingEvidenceBoundary"))
        #expect(splitView.contains("allowsFullHeightLayout = true"))
        #expect(browser.contains(".font(ScholiumTypography.interface(.body))"))
        #expect(browser.contains("ScholiumNativeToolbarButton("))
        #expect(browser.contains("focusPresentation: .native"))
        let evidencePopoverStart = try #require(
            browser.range(
                of: "private struct ResearchRecordEvidenceCollectionPopover<Content: View>: View {"
            )
        )
        let evidencePopoverEnd = try #require(
            browser.range(
                of: "private struct ResearchRecordPreviewedEvidenceSection<",
                range: evidencePopoverStart.upperBound..<browser.endIndex
            )
        )
        let evidencePopover = browser[
            evidencePopoverStart.lowerBound..<evidencePopoverEnd.lowerBound
        ]
        #expect(evidencePopover.contains("@FocusState private var isScrollFocused: Bool"))
        #expect(evidencePopover.contains(".focusable()"))
        #expect(evidencePopover.contains(".focusEffectDisabled()"))
        #expect(evidencePopover.contains(".focused($isScrollFocused)"))
        #expect(evidencePopover.contains(".defaultFocus($isScrollFocused, true)"))
        #expect(!browser.contains("ResearchRecordContextUseSection"))
        #expect(!browser.contains("Context Used"))
        #expect(!browser.contains("ResearchRecordCollectionRowMainButtonStyle"))
        #expect(browser.contains("ScholiumContentControlButtonStyle("))
        #expect(browser.contains("ScholiumShape.researchRecordCollectionRowCornerRadius"))
        #expect(browser.contains("ScholiumShape.editorialControlCornerRadius"))
        #expect(browser.contains(".scholiumContentControlPointerFeedback("))
        #expect(!browser.contains("ResearchRecordsToolbar"))
        #expect(!browser.contains("ToolbarItemGroup(placement: .principal)"))
        #expect(windowManagement.contains("window.titleVisibility = .hidden"))
        #expect(!windowManagement.contains("if usesFullHeightContent"))
        #expect(windowManagement.contains("window.styleMask.insert(.fullSizeContentView)"))
        #expect(!app.contains("usesFullHeightContent: browserModel.route.recordID != nil"))
        #expect(windowManagement.contains("window.titlebarAppearsTransparent = true"))
        #expect(windowManagement.contains("window.titlebarSeparatorStyle = .none"))
        #expect(
            windowManagement.contains(
                "window.backgroundColor = ScholiumColorRole.documentBackground.nsColor"))
        #expect(!windowManagement.contains("window.minSize ="))
        #expect(feature.contains("package final class ResearchRecordBrowserModel"))
        #expect(feature.contains("package private(set) var route: ResearchRecordsRoute"))
        #expect(route.contains("package enum ResearchRecordsRoute"))
        #expect(!feature.contains("import SwiftUI"))
        #expect(!feature.contains("ResearchRecordsWindowCoordinator"))
        #expect(WindowColorSchemeChoice.dark.swiftUIColorScheme == .dark)
        #expect(WindowColorSchemeChoice.light.swiftUIColorScheme == .light)
        #expect(WindowColorSchemeChoice.system.swiftUIColorScheme == nil)

        let recordsSceneStart = try #require(
            app.range(of: "WindowGroup(\n            \"Research Records\"")
        )
        let settingsStart = try #require(
            app.range(
                of: "\n        Settings {",
                range: recordsSceneStart.upperBound..<app.endIndex
            )
        )
        let recordsScene = app[recordsSceneStart.lowerBound..<settingsStart.lowerBound]
        #expect(
            recordsScene.contains(
                ".windowToolbarStyle(.unified(showsTitle: false))"
            ))
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
        controller.failSearch(.failed("late"), for: request)

        #expect(controller.search.criteria.query.isEmpty)
        #expect(controller.search.criteria.scope == .currentVault)
        #expect(controller.search.ordinaryScope == .currentVault)
        #expect(controller.search.executionIssue == nil)
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

        #expect(
            splitSource.contains(
                "sidebarWithViewController: libraryBackgroundController"
            ))
        #expect(
            !splitSource.contains(
                "inspectorWithViewController: apparatusBackgroundController"
            ))
        #expect(splitSource.contains("splitControllerDidAttach(self)"))
        #expect(splitSource.contains("splitControllerDidDetach(self)"))
        #expect(windowManagementSource.contains("splitController.nativeSplitViewController"))
        #expect(!appSource.contains("ScholiumWorkspaceSplitRegistry"))
        #expect(!appSource.contains("findWorkspaceSplitView"))
        #expect(
            toolbarSource.components(
                separatedBy: "NSTrackingSeparatorToolbarItem("
            ).count == 3)
        #expect(toolbarSource.contains("dividerIndex: 0"))
        #expect(toolbarSource.contains("dividerIndex: 1"))
        #expect(!splitSource.contains("ScholiumSurfaceHostController"))
        #expect(splitSource.contains("ScholiumSurfaceContainerViewController"))
        #expect(!splitSource.contains("NSBackgroundExtensionView"))
        #expect(toolbarSource.contains("item.isBordered = false"))
        #expect(toolbarSource.contains("button.showsBorderOnlyWhileMouseInside = true"))
    }

    @Test("Native and WebKit color roles use one semantic vocabulary")
    func semanticColorParity() throws {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repository =
            sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let cssRoot = repository.appendingPathComponent("Scholium/Resources/Editor")
        let cssEnumerator = try #require(
            FileManager.default.enumerator(
                at: cssRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )
        var authoredCSS = ""
        while let file = cssEnumerator.nextObject() as? URL {
            guard file.pathExtension == "css" else { continue }
            authoredCSS += try String(contentsOf: file, encoding: .utf8)
            authoredCSS.append("\n")
        }
        #expect(!authoredCSS.isEmpty)

        let nativeNames = Set(ScholiumColorRole.allCases.map(\.cssVariableName))
        let expression = try NSRegularExpression(pattern: #"--scholium-color-[a-z-]+"#)
        let range = NSRange(
            authoredCSS.startIndex..<authoredCSS.endIndex,
            in: authoredCSS
        )
        let authoredCSSNames = Set(
            expression.matches(in: authoredCSS, range: range).compactMap { match in
                Range(match.range, in: authoredCSS).map { String(authoredCSS[$0]) }
            })

        #expect(authoredCSSNames.isSubset(of: nativeNames))
        #expect(Set(ScholiumWebDesignTokens.resolvedColorRoleCSSVariableNames) == nativeNames)

        for declarations in [
            ScholiumWebDesignTokens.rootCSSDeclarations,
            ScholiumWebDesignTokens.darkAppearanceCSSDeclarations,
            ScholiumWebDesignTokens.increasedContrastCSSDeclarations,
            ScholiumWebDesignTokens.darkIncreasedContrastCSSDeclarations,
        ] {
            let declarationRange = NSRange(
                declarations.startIndex..<declarations.endIndex,
                in: declarations
            )
            let declarationNames = Set(
                expression.matches(
                    in: declarations,
                    range: declarationRange
                ).compactMap { match in
                    Range(match.range, in: declarations).map {
                        String(declarations[$0])
                    }
                }
            )
            #expect(declarationNames == nativeNames)
        }

        let authoredColorDeclaration = try NSRegularExpression(
            pattern: #"--scholium-(?:color|mark-highlight)-[a-z-]+\s*:"#
        )
        let authoredHexColor = try NSRegularExpression(
            pattern: #"#[0-9A-Fa-f]{3,8}\b"#
        )
        #expect(
            authoredColorDeclaration.firstMatch(
                in: authoredCSS,
                range: range
            ) == nil
        )
        #expect(
            authoredHexColor.firstMatch(
                in: authoredCSS,
                range: range
            ) == nil
        )
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                ScholiumWebDesignTokens.rootCSSDeclarations
            )
        )
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                ScholiumWebDesignTokens.fixedDocumentSyntaxCSSDeclarations
            )
        )
    }

    @Test("Document and interface typography expose semantic roles")
    func semanticTypographyContract() throws {
        let appearance = DocumentAppearanceSettings.defaultSettings
        #expect(appearance.body.fontSizePoints == 12)
        #expect(appearance.body.lineHeight == 2)
        #expect(appearance.headings.title.scale == 2)
        #expect(appearance.headings.level1.scale == 1.5)
        #expect(appearance.headings.level2.scale == 1.15)
        #expect(appearance.headings.lineHeight == 1.8)

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let typographyURL = repository.appendingPathComponent(
            "Scholium/Styling/ScholiumTypography.swift"
        )
        let typographySource = try String(contentsOf: typographyURL, encoding: .utf8)
        for requiredDeclaration in [
            "enum ScholiumTypography",
            "enum InterfaceRole",
            "case primaryTitle",
            "enum ScholarlyRole",
            "enum ExactRole",
            "static func interface(",
            "static func scholarly(",
            "static func exact(",
            "case .primaryTitle:\n            (size, defaultWeight) = (17, .semibold)",
            "case .body:\n            font = ScholiumTypeface.scholarly(size: 13",
            "case .small:\n            ScholiumTypeface.exact(size: 10",
        ] {
            #expect(typographySource.contains(requiredDeclaration))
        }

        for retiredRole in [
            "ScholiumInterfaceTypography",
            "enum Library",
            "enum Apparatus",
            "enum ResearchRecords",
            "enum Chrome",
            "static let libraryHierarchy",
            "static let libraryFolderTitle",
            "static let apparatusResearchContent",
            "static let researchRecordBody",
            "static let researchRecordRowBody",
        ] {
            #expect(!typographySource.contains(retiredRole))
        }

        let applicationRoot = repository.appendingPathComponent("Scholium", isDirectory: true)
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: applicationRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ))
        let rawPointSizePattern = try NSRegularExpression(
            pattern: #"Font\.system\(\s*size:\s*\d|\.font\(\.system\(\s*size:\s*\d"#
        )
        let rawCustomTypefacePattern = try NSRegularExpression(
            pattern: #"Font\.custom\(\s*\"|\.font\(\.custom\(\s*\""#
        )
        let rawSemanticStylePattern = try NSRegularExpression(
            pattern:
                #"(?:Font\.|\.font\(\.)(?:body|caption2?|callout|footnote|headline|subheadline|title[23]?|largeTitle)\b|\.font\(\.system\(\.(?:body|caption2?|callout|footnote|headline|subheadline|title[23]?|largeTitle)\b"#
        )
        while let sourceURL = enumerator.nextObject() as? URL {
            guard sourceURL.pathExtension == "swift", sourceURL != typographyURL else { continue }
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)
            #expect(
                rawPointSizePattern.firstMatch(
                    in: source,
                    range: sourceRange
                ) == nil,
                "Fixed SwiftUI font size escaped the semantic typography owner: \(sourceURL.path)"
            )
            #expect(
                !source.contains(".font(.system("),
                "A SwiftUI system font escaped the semantic typography owner: \(sourceURL.path)"
            )
            #expect(
                rawCustomTypefacePattern.firstMatch(
                    in: source,
                    range: sourceRange
                ) == nil,
                "Custom typeface escaped the semantic typography owner: \(sourceURL.path)"
            )
            #expect(
                rawSemanticStylePattern.firstMatch(
                    in: source,
                    range: sourceRange
                ) == nil,
                "Raw SwiftUI text style escaped the semantic typography owner: \(sourceURL.path)"
            )
            #expect(
                !source.contains(".fontWeight("),
                "Leaf-owned font weight escaped the semantic typography owner: \(sourceURL.path)"
            )
            #expect(
                !source.contains("ScholiumTypeface"),
                "A leaf View bypasses the semantic typography owner: \(sourceURL.path)"
            )
        }
    }

    @Test("Research Records separate scholarly body from supporting interface copy")
    func researchRecordsBodyTypographyContract() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let browser = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/ResearchRecord/ResearchRecordBrowserView.swift"
            ),
            encoding: .utf8
        )
        let followUp = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/ResearchRecord/ResearchRecordFollowUpViews.swift"
            ),
            encoding: .utf8
        )

        for requiredSupportingPresentation in [
            "let bodyText: String?",
            "Text(bodyText)\n                        .font(ScholiumTypography.interface(.compact))",
            "Text(\"No researcher note has been added.\")\n                    .font(ScholiumTypography.interface(.compact))",
        ] {
            #expect(browser.contains(requiredSupportingPresentation))
        }
        #expect(
            followUp.contains(
                ".font(ScholiumTypography.interface(.compact))"
            )
        )
        #expect(
            browser.contains(
                "Text(entry.title)\n                        .font(ScholiumTypography.interface(.body))"
            )
        )
        let readingLeadRowStart = try #require(
            browser.range(
                of: "private struct ResearchLiteratureRecommendationListRow: View {"
            )
        )
        let readingLeadRowEnd = try #require(
            browser.range(
                of: "private struct ResearchLiteratureRecommendationDetailView: View {",
                range: readingLeadRowStart.upperBound..<browser.endIndex
            )
        )
        let readingLeadRow = browser[readingLeadRowStart.lowerBound..<readingLeadRowEnd.lowerBound]
        #expect(
            readingLeadRow.contains(
                "Text(occurrence.displayTitle)\n                        .font(ScholiumTypography.interface(.body))"
            )
        )
        #expect(readingLeadRow.contains(".font(ScholiumTypography.interface(.compact))"))
        #expect(
            readingLeadRow.contains(
                ".font(ScholiumTypography.interface(.compact, tabularDigits: true))"
            )
        )
        #expect(!readingLeadRow.contains("ScholiumTypography.scholarly"))
        let evidenceEntryStart = try #require(
            browser.range(of: "struct ResearchRecordEvidenceEntry: View {")
        )
        let evidenceEntryEnd = try #require(
            browser.range(
                of: "struct ResearchRecordEvidenceSectionHeader: View {",
                range: evidenceEntryStart.upperBound..<browser.endIndex
            )
        )
        let evidenceEntry = browser[evidenceEntryStart.lowerBound..<evidenceEntryEnd.lowerBound]
        #expect(
            evidenceEntry.contains(
                "Text(title)\n                    .font(ScholiumTypography.interface(.rowTitle))"
            )
        )
        #expect(
            evidenceEntry.contains(
                "private var metadataView: some View"
            )
        )
        #expect(evidenceEntry.contains(".font(ScholiumTypography.interface(.small))"))
        #expect(!evidenceEntry.contains("ScholiumTypography.interface(.sectionTitle)"))
        #expect(!evidenceEntry.contains(".small, emphasis:"))
        #expect(browser.contains(".font(ScholiumTypography.scholarly(.body))"))
        #expect(browser.contains(".font(ScholiumTypography.interface(.small, emphasis: .medium))"))
        #expect(browser.contains("private var metadataView: some View"))
    }

    @Test("Bundled native typefaces register with AppKit")
    func bundledNativeTypefacesRegister() {
        ScholiumFontRegistry.registerBundledFonts()

        for postScriptName in [
            "Alegreya-Regular",
            "Alegreya-Italic",
            "Alegreya-Bold",
            "Alegreya-BoldItalic",
            "VictorMono-Regular",
            "VictorMono-Italic",
            "VictorMono-Bold",
            "VictorMono-BoldItalic",
        ] {
            #expect(
                NSFont(name: postScriptName, size: 12) != nil,
                "Bundled native typeface did not register: \(postScriptName)"
            )
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
        #expect(ScholiumShape.searchOverlayCornerRadius == 12)
        #expect(
            ScholiumMetrics.Search.resultHorizontalInset == ScholiumGrid.Spacing.regionContentInset)
        #expect(
            ScholiumMetrics.Search.resultVerticalInset == ScholiumGrid.Spacing.labelAccessoryGap)
        #expect(
            ScholiumMetrics.Search.selectionIndicatorWidth
                == ScholiumGrid.Spacing.opticalAlignmentAdjustment)
        #expect(ScholiumShape.editorialControlCornerRadius == 8)
        #expect(ScholiumShape.editorialPanelCornerRadius == 10)
        #expect(ScholiumShape.editorialTextEditorCornerRadius == 6)
        #expect(
            ScholiumMetrics.Library.workspaceNavigatorTopSpacing
                == ScholiumGrid.Spacing.nestedContentInset
        )
        #expect(ScholiumMetrics.ResearchRecords.viewIndexWidth == 240)
        #expect(ScholiumMetrics.ResearchRecords.pageEdge == 28)
        #expect(ScholiumMetrics.ResearchRecords.collectionSearchMinimumWidth == 192)
        #expect(ScholiumMetrics.ResearchRecords.collectionColumnHeaderHeight == 28)
        #expect(ScholiumShape.researchRecordCollectionRowCornerRadius == 8)
        #expect(ScholiumMetrics.ResearchRecords.collectionRowHeight == 48)
        #expect(ScholiumMetrics.ResearchRecords.collectionColumnGap == 12)
        #expect(ScholiumMetrics.ResearchRecords.recordAttentionColumnWidth == 28)
        #expect(ScholiumMetrics.ResearchRecords.recordActionColumnWidth == 96)
        #expect(ScholiumMetrics.ResearchRecords.recordDateColumnWidth == 104)
        #expect(ScholiumMetrics.ResearchRecords.recordActionCapsuleHeight == 20)
        #expect(ScholiumMetrics.ResearchRecords.readingLeadHandledColumnWidth == 32)
        #expect(ScholiumMetrics.ResearchRecords.readingLeadSelectionGap == 8)
        #expect(ScholiumMetrics.ResearchRecords.readingLeadAuthorColumnWidth == 116)
        #expect(ScholiumMetrics.ResearchRecords.readingLeadYearColumnWidth == 48)
        #expect(ScholiumMetrics.ResearchRecords.readingLeadPublicationColumnWidth == 184)
        #expect(ScholiumMetrics.ResearchRecords.evidenceMinimumWidth == 260)
        #expect(ScholiumMetrics.ResearchRecords.evidenceMaximumWidth == 304)
        #expect(ScholiumMetrics.ResearchRecords.readingMeasure == 680)
    }

    @Test("Shared Native and WebKit corner roles stay in parity")
    func semanticCornerGeometryContract() throws {
        #expect(ScholiumCornerRole.editorialTextEditor.radius == 6)
        #expect(ScholiumCornerRole.boundedPanel.radius == 8)
        #expect(ScholiumCornerRole.documentControl.radius == 5)

        let webNames = Set(ScholiumCornerRole.allCases.compactMap(\.cssVariableName))
        #expect(ScholiumWebDesignTokens.resolvedCornerRoleCSSVariableNames == webNames)
        for declaration in ScholiumShape.webCSSDeclarations.split(separator: "\n") {
            #expect(
                ScholiumWebDesignTokens.documentPresentationCSS.contains(
                    declaration.trimmingCharacters(in: .whitespaces)
                ))
        }

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let designSystem = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Foundation/ScholiumDesignSystem.swift"
            ),
            encoding: .utf8
        )
        let search = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/SearchWorkspaceView.swift"
            ),
            encoding: .utf8
        )
        let bootstrap = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/WorkspaceSetupView.swift"
            ),
            encoding: .utf8
        )
        let frontmatter = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Metadata/MetadataEditorView.swift"
            ),
            encoding: .utf8
        )
        let review = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/SafeMarkdownReadWebView.swift"
            ),
            encoding: .utf8
        )
        #expect(designSystem.contains(".containerShape(shape)"))
        #expect(search.contains("in: ConcentricRectangle()"))
        #expect(search.contains("ScholiumShape.searchOverlayCornerRadius"))
        #expect(bootstrap.contains("ScholiumShape.editorialPanelCornerRadius"))
        #expect(frontmatter.contains("ScholiumShape.editorialTextEditorCornerRadius"))
        #expect(review.contains("var(--scholium-corner-editorial-text-editor)"))
    }

    @Test("Search and Properties consume purpose-named component dimensions")
    func searchAndPropertiesPurposeNamedDimensionAdoption() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let search = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/SearchWorkspaceView.swift"
            ),
            encoding: .utf8
        )
        let frontmatter = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Metadata/MetadataEditorView.swift"
            ),
            encoding: .utf8
        )
        let preferredTargetFrame = try NSRegularExpression(
            pattern:
                #"\.frame\(\s*minWidth:\s*ScholiumMetrics\.Accessibility\.preferredCustomTarget,\s*minHeight:\s*ScholiumMetrics\.Accessibility\.preferredCustomTarget\s*\)"#
        )
        let literalPurposeDimension = try NSRegularExpression(
            pattern: #"\.frame\([^\)]*(?:minWidth|minHeight|width|height):\s*(?:28|48)(?:\.0)?\b"#
        )

        func matchCount(_ expression: NSRegularExpression, in source: String) -> Int {
            expression.numberOfMatches(
                in: source,
                range: NSRange(source.startIndex..<source.endIndex, in: source)
            )
        }

        #expect(matchCount(preferredTargetFrame, in: search) == 3)
        #expect(matchCount(preferredTargetFrame, in: frontmatter) == 2)
        #expect(
            search.contains(
                ".frame(height: ScholiumGrid.Dimension.regionHeaderHeight)"
            ))
        #expect(matchCount(literalPurposeDimension, in: search) == 0)
        #expect(matchCount(literalPurposeDimension, in: frontmatter) == 0)
    }

    @Test("Shared editorial grid exposes reusable roles and explicit document units")
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
        #expect(ScholiumGrid.Dimension.researchActionTargetHeight == 44)
        #expect(ScholiumGrid.Dimension.regionHeaderHeight == 48)
        #expect(ScholiumGrid.Document.narrowWidthThresholdRootEms == 44)

        #expect(ScholiumMetrics.Library.contentInset == ScholiumGrid.Peripheral.contentInset)
        #expect(ScholiumMetrics.Apparatus.contentInset == ScholiumGrid.Peripheral.contentInset)
        #expect(
            ScholiumMetrics.Library.workspaceNavigatorTopSpacing
                == ScholiumGrid.Spacing.nestedContentInset
        )
        #expect(ScholiumMetrics.Library.sectionSpacing == ScholiumGrid.Spacing.sectionSeparation)
        #expect(
            ScholiumMetrics.Library.hierarchyRowHeight
                == ScholiumGrid.Dimension.libraryHierarchyRowHeight
        )
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

    @Test("Interface copy and empty-state AX remain purpose-owned")
    func interfaceCopyAndAccessibilityOwnership() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        func source(_ path: String) throws -> String {
            try String(
                contentsOf: repository.appendingPathComponent(path),
                encoding: .utf8
            )
        }
        let actions = try source(
            "Scholium/Views/ResearchActions/ResearchActionsInspectorView.swift"
        )
        let actionSheet = try source(
            "Scholium/Views/ResearchActions/ResearchActionPanelView.swift"
        )
        let connections = try source(
            "Scholium/Views/Backlinks/ConnectionsInspectorView.swift"
        )
        #expect(!actions.contains("ResearchActionHelpModifier"))
        #expect(!actions.contains("helpText"))
        #expect(!actionSheet.contains("interfaceSummary"))
        #expect(!connections.contains(".help(item.section.title)"))

        let localization = try source("Scholium/Resources/Localizable.xcstrings")
        for retiredSummary in [
            "Discuss this note or a selected passage without changing Markdown.",
            "Analyze the bound source and update this Analysis when warranted.",
            "Integrate Analyses, Sources, and reliable information into this Topic.",
            "Write to this Work within its explicit boundary.",
            "Produce bounded critical feedback before any separately authorized writing.",
            "Check content fidelity without modifying the note.",
        ] {
            #expect(!localization.contains(retiredSummary))
        }

        let records = try source(
            "Scholium/Views/ResearchRecord/ResearchRecordBrowserView.swift"
        )
        let collectionStart = try #require(
            records.range(of: "private struct ResearchRecordsCollectionView")
        )
        let collectionEnd = try #require(
            records.range(
                of: "private struct ResearchRecordsCollectionSearch",
                range: collectionStart.upperBound..<records.endIndex
            )
        )
        let collectionRoot = records[collectionStart.lowerBound..<collectionEnd.lowerBound]
        #expect(!collectionRoot.contains("scholium.researchRecords.collection"))
        #expect(
            records.components(separatedBy: "scholium.researchRecords.collection").count - 1
                == 2
        )
        #expect(
            records.components(separatedBy: "scholium.researchRecords.empty").count - 1
                == 1
        )
    }

    @Test("Heading Outline toolbar navigation has a matching View-menu route")
    func headingOutlineHasViewMenuRoute() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: repository.appendingPathComponent("Scholium/App/ScholiumApp.swift"),
            encoding: .utf8
        )
        let viewCommandsStart = try #require(
            app.range(of: "private struct ScholiumSidebarCommandContent")
        )
        let viewCommandsEnd = try #require(
            app.range(
                of: "private struct ScholiumAttentionCommandContent",
                range: viewCommandsStart.upperBound..<app.endIndex
            )
        )
        let viewCommands = app[
            viewCommandsStart.lowerBound..<viewCommandsEnd.lowerBound
        ]

        #expect(viewCommands.contains("Menu(\"Heading Outline\")"))
        #expect(
            viewCommands.contains(
                "appState?.pendingSourceLine = heading.span.start.line"
            )
        )
        #expect(viewCommands.contains("Button(\"No Headings\")"))
    }

    @Test("Research Action launchers assign no keyboard shortcuts")
    func researchActionLaunchersAssignNoKeyboardShortcuts() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(
                contentsOf: repository.appendingPathComponent(path),
                encoding: .utf8
            )
        }

        let app = try source("Scholium/App/ScholiumApp.swift")
        let researchMenuStart = try #require(app.range(of: "CommandMenu(\"Research\")"))
        let researchMenuEnd = try #require(
            app.range(
                of: "#if DEBUG",
                range: researchMenuStart.upperBound..<app.endIndex
            )
        )
        let researchMenu = app[
            researchMenuStart.lowerBound..<researchMenuEnd.lowerBound
        ]
        #expect(!researchMenu.contains(".keyboardShortcut"))

        let actionPresentation = try source(
            "Scholium/Views/ResearchActions/ResearchActionPanelView.swift"
        )
        #expect(!actionPresentation.contains("interfaceKeyboardShortcut"))
    }

    @Test("Research-facing sheets share editorial zones and purpose-owned sizes")
    func researchSheetLayoutOwnership() throws {
        #expect(
            ScholiumMetrics.ResearchSheet.contentInset
                == ScholiumGrid.Spacing.regionContentInset
        )
        #expect(
            ScholiumMetrics.ResearchSheet.headerDetailSpacing
                == ScholiumGrid.Spacing.labelAccessoryGap
        )
        #expect(
            ScholiumMetrics.ResearchSheet.bodySectionSpacing
                == ScholiumGrid.Spacing.sectionSeparation
        )
        #expect(
            ScholiumMetrics.ResearchSheet.footerControlSpacing
                == ScholiumGrid.Spacing.inlineControlGap
        )

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(
                contentsOf: repository.appendingPathComponent(path),
                encoding: .utf8
            )
        }

        let action = try source(
            "Scholium/Views/ResearchActions/ResearchActionPanelView.swift"
        )
        let records = try source(
            "Scholium/Views/ResearchRecord/ResearchRecordBrowserView.swift"
        )
        let processing = try source(
            "Scholium/Views/ResearchRecord/ResearchRecordProcessingViews.swift"
        )
        let followUp = try source(
            "Scholium/Views/ResearchRecord/ResearchRecordFollowUpViews.swift"
        )
        let comparison = try source(
            "Scholium/UI/Components/ExactSourceComparisonView.swift"
        )

        for token in [
            "ScholiumMetrics.ResearchSheet.Action.minimumWidth",
            "ScholiumMetrics.ResearchSheet.bodySectionSpacing",
            "ScholiumMetrics.ResearchSheet.footerControlSpacing",
        ] {
            #expect(action.contains(token))
        }
        for token in [
            "ScholiumMetrics.ResearchSheet.ReadingLeadNote.minimumWidth",
            "scholium.researchRecommendation.noteSheet",
        ] {
            #expect(records.contains(token))
        }
        for token in [
            "ScholiumMetrics.ResearchSheet.Action.minimumWidth",
            "scholium.researchFollowUp.sheet",
        ] {
            #expect(followUp.contains(token))
        }
        #expect(processing.contains("scholium.researchRecord.comparison"))
        #expect(comparison.contains(
            "ScholiumMetrics.ResearchSheet.Comparison.minimumWidth"
        ))
        #expect(
            (records + processing + followUp).components(
                separatedBy: ".font(ScholiumTypography.interface(.primaryTitle))"
            ).count >= 3
        )
        #expect(!action.contains(".frame(minWidth: 520, idealWidth: 660"))
        #expect(!processing.contains(".frame(minWidth: 620, idealWidth: 700"))
        #expect(!records.contains("minWidth: 440,"))
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
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/NoteContentView.swift"),
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
            "sourceCollapsedActiveLine",
            "foldGutter()",
        ] {
            #expect(!staticExtensions.contains(sourceOnlyExtension))
            #expect(editorSource.contains(sourceOnlyExtension))
        }
        #expect(!editorSource.contains("highlightActiveLineGutter()"))
        #expect(!editorSource.contains("highlightActiveLine()"))
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
        #expect(sourceModeExtensions.contains("sourceTextDirection"))
        #expect(!liveModeExtensions.contains("sourceTextDirection"))
        #expect(sourceModeExtensions.contains("editorModeFacet.of(\"source\")"))
        #expect(sourceModeExtensions.contains("EditorView.editorAttributes.of"))
        #expect(!sourceModeExtensions.contains("defaultHighlightStyle"))
        for liveOnlyExtension in [
            "liveProjectionIndex.extension",
            "liveSemanticLayout.extension",
            "liveFrontmatterGuardField",
            "liveSelection.extension",
            "liveMermaidProjection.extension",
            "liveStructuredBlockProjections.tableExtension",
            "liveDisplayMathProjection.extension",
            "liveStructuredBlockProjections.rawHTMLExtension",
            "liveStructuredBlockProjections.calloutExtension",
            "liveFootnoteProjection.extension",
            "livePreview",
            "liveProjectionNavigation.extension",
            "selectionActions.extension",
            "previewPopover.extension",
        ] {
            #expect(liveModeExtensions.contains(liveOnlyExtension))
            #expect(!sourceModeExtensions.contains(liveOnlyExtension))
            #expect(!staticExtensions.contains(liveOnlyExtension))
        }
        #expect(staticExtensions.contains("modeCompartment.of(sourceMode)"))
        #expect(staticExtensions.contains("bidiIsolates()"))
        #expect(staticExtensions.contains("EditorView.perLineTextDirection.of(true)"))
        #expect(editorSource.contains(#"combine: (modes) => modes[0] ?? "source""#))
        #expect(
            editorSource.contains(
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
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                "padding-block: var(--scholium-document-content-top-inset) var(--scholium-rhythm-trailing-scroll)"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                "calc(50% - var(--scholium-document-half-line-width))"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                "padding-block: var(--scholium-appearance-h3-before) var(--scholium-appearance-h3-after)"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                "--scholium-rhythm-title-rule-gap: 0.5em"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                ".scholium-live-mode .cm-live-document-title::after"
            ))
        #expect(
            !ScholiumWebDesignTokens.documentPresentationCSS.contains(
                ".cm-editor.scholium-live-mode .cm-live-paragraph-end"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                ".scholium-document li > ul"
            ))

        #expect(noteSource.contains("ScholiumDocumentPresentationConfiguration"))
        #expect(editorStyles.contains("var(--scholium-document-half-line-width)"))
        #expect(editorStyles.contains("var(--scholium-document-content-top-inset)"))
        #expect(editorStyles.contains("var(--scholium-document-text-scale)"))
        #expect(
            ScholiumDocumentPresentationConfiguration(textScale: 1).css.contains(
                "@media (max-width:"
            ))
    }

    @Test("Edit vertical geometry is owned by direct CodeMirror StateFields")
    func editVerticalGeometryUsesDirectStateFields() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(
                contentsOf: repository.appendingPathComponent(path),
                encoding: .utf8
            )
        }
        let editorSource = try source("WebEditor/editor.ts")
        let semanticLayout = try source("WebEditor/live-semantic-layout.ts")
        let mermaidProjection = try source("WebEditor/live-mermaid-projection.ts")
        let structuredBlocks = try source(
            "WebEditor/live-structured-block-projections.ts"
        )
        let displayMath = try source("WebEditor/live-display-math-projection.ts")
        let footnotes = try source("WebEditor/live-footnote-projection.ts")
        #expect(semanticLayout.components(separatedBy: "StateField.define").count == 3)
        #expect(mermaidProjection.contains("StateField.define<LiveMermaidProjectionState>"))
        #expect(structuredBlocks.components(separatedBy: "StateField.define").count == 4)
        #expect(displayMath.contains("StateField.define<LiveDisplayMathProjectionState>"))
        #expect(footnotes.contains("StateField.define<LiveFootnoteReferenceState>"))
        #expect(editorSource.contains("const liveFrontmatterGuardField = StateField.define"))

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
        #expect(!editorSource.contains("for (const nestedList of"))
    }

    @Test("Basic editor input paths do not materialize the complete CodeMirror document")
    func editorInputHotPathsAvoidCompleteDocumentCopies() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let editorSource = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/editor.ts"),
            encoding: .utf8
        )

        func section(
            in source: String = editorSource,
            from start: String,
            to end: String
        ) throws -> Substring {
            let startRange = try #require(source.range(of: start))
            let endRange = try #require(
                source.range(
                    of: end,
                    range: startRange.upperBound..<source.endIndex
                ))
            return source[startRange.lowerBound..<endRange.lowerBound]
        }

        let stateReporting = try section(
            from: "const stateReporter = EditorView.updateListener.of",
            to: "const linkActivation = EditorView.domEventHandlers"
        )
        #expect(stateReporting.contains("exactSourceMirror.apply(mirrorChanges)"))
        #expect(stateReporting.contains("update.startState.doc.sliceString(fromA, toA)"))
        #expect(!stateReporting.contains("doc.toString()"))
        #expect(!stateReporting.contains("normalizedDocumentText("))

        let linkActivation = try section(
            from: "const linkActivation = EditorView.domEventHandlers",
            to: "const saveKeymap = keymap.of"
        )
        #expect(linkActivation.contains("linkTargetAt(editor.state.doc, position)"))
        #expect(!linkActivation.contains("doc.toString()"))

        let structuralKeymap = try section(
            from: "const structuralInteractionKeymap = keymap.of",
            to: "const liveProjectionNavigation = createLiveProjectionNavigation"
        )
        #expect(structuralKeymap.contains("continueList(view.state.doc"))
        #expect(structuralKeymap.contains("tableTabAction(view.state.doc"))
        #expect(structuralKeymap.contains("indentList(view.state.doc"))
        #expect(!structuralKeymap.contains("doc.toString()"))

        let sessionSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/MarkdownEditorSession.swift"
            ),
            encoding: .utf8
        )
        let nativeDeltaReceiver = try section(
            in: sessionSource,
            from: "func acceptEditorChanges(",
            to: "func webContentProcessTerminated()"
        )
        #expect(nativeDeltaReceiver.contains("checkedSourceBuffer.apply(changes)"))
        #expect(nativeDeltaReceiver.contains("sourceChangeHandler?()"))
        #expect(!nativeDeltaReceiver.contains("MarkdownEditorDeltaApplier.apply"))
        #expect(!nativeDeltaReceiver.contains("sourceChangeHandler?(nextSource)"))

        let controllerSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Features/Document/DocumentController.swift"
            ),
            encoding: .utf8
        )
        let activityReceiver = try section(
            in: controllerSource,
            from: "func editorSourceDidChange(",
            to: "func scheduleAutosave("
        )
        #expect(!activityReceiver.contains("editingSource ="))
        let autosaveScheduler = try section(
            in: controllerSource,
            from: "func scheduleAutosave(",
            to: "func persistEditingSource("
        )
        #expect(autosaveScheduler.contains("autosaveDeadline"))
        #expect(!autosaveScheduler.contains("autosaveTask?.cancel"))
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
                ".background(ScholiumColorRole.navigationSurfaceBackground.color)"
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

    @Test("Autosave commits source before derived refresh and toolbar consumes cached headings")
    func autosaveAndHeadingProjectionOwnership() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let handleSource = try String(
            contentsOf: repository.appendingPathComponent(
                "ScholiumApplication/WorkspaceHandle.swift"
            ),
            encoding: .utf8
        )
        func sourceSection(
            _ source: String,
            from start: String,
            to end: String
        ) throws -> Substring {
            let startRange = try #require(source.range(of: start))
            let endRange = try #require(
                source.range(
                    of: end,
                    range: startRange.upperBound..<source.endIndex
                ))
            return source[startRange.lowerBound..<endRange.lowerBound]
        }
        let commit = try sourceSection(
            handleSource,
            from: "func commitDocument(\n        _ id:",
            to: "private func performDocumentSave("
        )
        #expect(commit.contains("completion: .sourceOnly"))
        #expect(handleSource.contains("completion: .sourceAndDerived"))
        #expect(handleSource.contains("scheduleSourceCommitRefresh(id: id, kind: .save)"))
        #expect(handleSource.contains("scheduleCommittedMutationRefresh("))
        #expect(handleSource.contains("Task(priority: .utility)"))

        let folderCreation = try sourceSection(
            handleSource,
            from: "func createUntitledFolder(",
            to: "func moveFolder("
        )
        #expect(folderCreation.contains("scheduleCommittedMutationRefresh("))
        #expect(folderCreation.contains("refreshFolderVaultIDs: [vaultID]"))
        #expect(!folderCreation.contains("await refreshFolderInventory"))

        let documentMove = try sourceSection(
            handleSource,
            from: "private func coordinatedMoveDocument(",
            to: "private func coordinatedMoveFolder("
        )
        #expect(documentMove.contains("scheduleCommittedMutationRefresh(refreshPayload)"))
        #expect(!documentMove.contains("cleanupWarnings"))
        #expect(!documentMove.contains("await refreshCoordinator.request(refreshPayload)"))

        let folderMove = try sourceSection(
            handleSource,
            from: "private func coordinatedMoveFolder(",
            to: "private func workspaceFolderMovePlan("
        )
        #expect(folderMove.contains("scheduleCommittedMutationRefresh(refreshPayload)"))
        #expect(!folderMove.contains("cleanupWarnings"))
        #expect(!folderMove.contains("try await refresh("))

        let folderPlan = try sourceSection(
            handleSource,
            from: "private func workspaceFolderMovePlan(",
            to: "private func workspaceMovePlan("
        )
        #expect(folderPlan.contains("snapshotCanAuthorizeFastPlan"))
        #expect(folderPlan.contains("graph.sourceManifestHash == sourceManifestHash"))
        #expect(
            folderPlan.contains(
                "IncomingLinkRewriter.folderPlanUsingValidatedSnapshot("
            ))
        #expect(folderPlan.contains("repository.markdownRelativePaths()"))

        let controllerSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Features/Document/DocumentController.swift"
            ),
            encoding: .utf8
        )
        let editorSave = try sourceSection(
            controllerSource,
            from: "private func saveDocument(",
            to: "private func loadDocument("
        )
        #expect(editorSave.contains("return try await commit("))
        #expect(!editorSave.contains("return try await save("))
        #expect(
            controllerSource.contains(
                "typealias DocumentCommitHandler = @MainActor (SaveResult) async -> Void"
            ))
        #expect(controllerSource.contains("await documentDidCommit(result)"))

        let appSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let documentBinding = try sourceSection(
            appSource,
            from: "documentController.bind(",
            to: "researchController.bind("
        )
        #expect(documentBinding.contains("replaceSavedDocument(result.document)"))
        #expect(!documentBinding.contains("cleanupWarning"))
        #expect(!appSource.contains("private func localizedCleanupWarnings("))
        #expect(!appSource.contains("case .displacedSourceCopy:"))
        #expect(!appSource.contains("case .transactionRecord:"))
        #expect(!appSource.contains("cleanupWarnings"))

        let toolbarSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWorkspaceToolbar.swift"
            ),
            encoding: .utf8
        )
        #expect(
            toolbarSource.contains(
                "appState.currentNote?.workspaceSnapshot?.headings ?? []"
            )
        )
        #expect(!toolbarSource.contains("MarkdownSemanticDocument("))
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
        let presentFeedbackSource = try #require(
            appSource.range(of: "func presentFeedback(")
        )
        let suffix = appSource[presentFeedbackSource.lowerBound...]
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
            #expect(
                rgbValue(of: role.nsColor(increasedContrast: false), appearance: darkAqua) == dark)
        }

        for (palette, declarations) in [
            (expectedLight, ScholiumWebDesignTokens.rootCSSDeclarations),
            (expectedDark, ScholiumWebDesignTokens.darkAppearanceCSSDeclarations),
            (
                expectedIncreasedContrastLight,
                ScholiumWebDesignTokens.increasedContrastCSSDeclarations
            ),
            (
                expectedIncreasedContrastDark,
                ScholiumWebDesignTokens.darkIncreasedContrastCSSDeclarations
            ),
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
        #expect(contrastRatio(0x28241D, 0xFF9A00) >= 7.0)
    }

    @Test("Reduce Motion removes app-defined transitions")
    func reducedMotionRemovesTransitions() {
        #expect(ScholiumMotion.bootstrapStep(reduceMotion: true) == nil)
        #expect(ScholiumMotion.documentReveal(reduceMotion: true) == nil)
        #expect(ScholiumMotion.searchPresentation(reduceMotion: true) == nil)
        #expect(ScholiumMotion.searchExpansion(reduceMotion: true) == nil)
        #expect(ScholiumMotion.disclosure(reduceMotion: true) == nil)
        #expect(ScholiumMotion.symbolReplacement(reduceMotion: true) == nil)
        #expect(ScholiumMotion.triptychWorkspaceSourceReveal(reduceMotion: true) == nil)
        #expect(ScholiumMotion.transientStatus(reduceMotion: true) == nil)

        #expect(ScholiumMotion.bootstrapStep(reduceMotion: false) != nil)
        #expect(ScholiumMotion.documentReveal(reduceMotion: false) != nil)
        #expect(ScholiumMotion.searchPresentation(reduceMotion: false) != nil)
        #expect(ScholiumMotion.searchExpansion(reduceMotion: false) != nil)
        #expect(ScholiumMotion.disclosure(reduceMotion: false) != nil)
        #expect(ScholiumMotion.symbolReplacement(reduceMotion: false) != nil)
        #expect(ScholiumMotion.triptychWorkspaceSourceReveal(reduceMotion: false) != nil)
        #expect(ScholiumMotion.transientStatus(reduceMotion: false) != nil)
        #expect(ScholiumMotion.triptychWorkspaceSourceOffset == 6)
    }

    @Test("Bootstrap step motion keeps one semantic recipe owner")
    func bootstrapStepMotionRecipeOwnership() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/WorkspaceSetupView.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("ScholiumMotion.bootstrapStepTransition("))
        #expect(source.contains("withAnimation(ScholiumMotion.bootstrapStep("))
        #expect(!source.contains("let offset = isMovingForward"))
        #expect(!source.contains(".asymmetric("))
    }

    @Test("Workspace motion keeps semantic transition recipe owners")
    func workspaceMotionRecipeOwnership() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/ContentView.swift"
            ),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/WorkspaceSettingsView.swift"
            ),
            encoding: .utf8
        )

        #expect(contentSource.contains("ScholiumMotion.documentRevealTransition("))
        #expect(contentSource.contains("ScholiumMotion.searchPresentationTransition("))
        #expect(contentSource.contains("ScholiumMotion.transientStatusTransition("))
        #expect(settingsSource.contains("ScholiumMotion.transientStatusTransition("))
        #expect(!contentSource.contains("scale(scale: 0.985"))
        #expect(!contentSource.contains("scale(scale: 0.995"))
        #expect(!settingsSource.contains(".move(edge: .bottom)"))
    }

    @Test("Reachable motion paths retain their reduced-motion boundary")
    func reachableMotionReductionContract() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(
                contentsOf: repository.appendingPathComponent(path),
                encoding: .utf8
            )
        }

        let contentSource = try source("Scholium/Views/ContentView.swift")
        let searchSource = try source("Scholium/Views/SearchWorkspaceView.swift")
        let recordSource = try source(
            "Scholium/Views/ResearchRecord/ResearchRecordBrowserView.swift"
        )
        let windowSource = try source(
            "Scholium/UI/Components/ScholiumWindowManagement.swift"
        )
        let splitSource = try source(
            "Scholium/UI/Components/ScholiumWorkspaceSplitView.swift"
        )
        let reviewSource = try source(
            "WebEditor/reader.ts"
        )
        let mermaidSource = try source("WebEditor/mermaid-runtime.ts")

        #expect(!contentSource.contains(".transition(.opacity.combined(with: .scale(0.98)))"))
        #expect(!searchSource.contains(".transition(.opacity.combined(with: .scale(scale: 0.9)))"))
        #expect(recordSource.contains("ScholiumMotion.symbolReplacementTransition("))
        #expect(
            recordSource.contains("ScholiumMotion.symbolReplacementContentTransition("))
        #expect(windowSource.contains("animated: !reduceMotion"))
        #expect(splitSource.contains("accessibilityDisplayShouldReduceMotion"))

        let reviewMotionProbe =
            "matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth'"
        #expect(reviewSource.components(separatedBy: reviewMotionProbe).count == 3)
        #expect(mermaidSource.contains("animation: none !important"))
        #expect(mermaidSource.contains("transition: none !important"))
    }

    @Test("Custom interface glyphs use resolved semantic colors")
    func customInterfaceGlyphColors() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/WorkspaceSetupView.swift"
            ),
            encoding: .utf8
        )
        let frontmatterSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Metadata/MetadataEditorView.swift"
            ),
            encoding: .utf8
        )
        let connectionsSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Backlinks/ConnectionsInspectorView.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("withAnimation(ScholiumMotion.bootstrapStep"))
        #expect(source.contains(".scholiumForeground(.accent)"))
        #expect(!source.contains(".foregroundStyle(.tint)"))
        #expect(frontmatterSource.contains(".tint(ScholiumColorRole.accent.color)"))
        #expect(frontmatterSource.contains(".scholiumForeground(.accent)"))
        #expect(!frontmatterSource.contains("Color.accentColor"))
        #expect(connectionsSource.contains(".scholiumForeground(.mutedText)"))

        let designSystemSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Foundation/ScholiumDesignSystem.swift"
            ),
            encoding: .utf8
        )
        let componentsSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/UI/Components/ScholiumComponents.swift"
            ),
            encoding: .utf8
        )
        let critiqueSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/CritiqueProvenanceView.swift"
            ),
            encoding: .utf8
        )
        let bootstrapSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/App/ApplicationBootstrapController.swift"
            ),
            encoding: .utf8
        )
        let recordSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/ResearchRecord/ResearchRecordBrowserView.swift"
            ),
            encoding: .utf8
        )

        #expect(!designSystemSource.contains("ScholiumInkIconButtonStyle"))
        #expect(designSystemSource.contains("ScholiumContentInteractionSurface"))
        #expect(designSystemSource.contains("ScholiumContentControlButtonStyle"))
        #expect(!componentsSource.contains("ScholiumTriptychWorkspaceButtonStyle"))
        #expect(designSystemSource.contains("isEnabled && isPressed ? pressedOpacity : 1"))
        #expect(designSystemSource.contains("isActive || isSelected || hasTransientEmphasis"))
        #expect(critiqueSource.contains("ScholiumMotion.disclosure(reduceMotion: reduceMotion)"))
        #expect(bootstrapSource.contains("ScholiumMotion.disclosure(reduceMotion: reduceMotion)"))
        #expect(!recordSource.contains("ResearchRecordCollectionRowMainButtonStyle"))
        #expect(!recordSource.contains("ResearchRecordsEditorialButtonStyle"))
        #expect(recordSource.contains("ScholiumContentControlButtonStyle("))
        #expect(recordSource.contains("ScholiumShape.researchRecordCollectionRowCornerRadius"))
    }

    @Test("Shared semantic surfaces, depth, and boundaries retain adaptation contracts")
    func semanticSurfaceRecipeContract() {
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

        #expect(
            ScholiumStructuralDepthRole.documentNavigationBoundary.style(
                isDark: false,
                increasedContrast: false,
                reduceTransparency: false,
                appearsActive: true,
                layoutDirection: .leftToRight
            ) == .init(opacity: 0.04, radius: 8, x: -2, y: 0))
        #expect(
            ScholiumStructuralDepthRole.documentNavigationBoundary.style(
                isDark: false,
                increasedContrast: false,
                reduceTransparency: false,
                appearsActive: true,
                layoutDirection: .rightToLeft
            ) == .init(opacity: 0.04, radius: 8, x: 2, y: 0))
        #expect(
            ScholiumStructuralDepthRole.readingEvidenceBoundary.style(
                isDark: false,
                increasedContrast: false,
                reduceTransparency: false,
                appearsActive: true,
                layoutDirection: .leftToRight
            ) == .init(opacity: 0.04, radius: 8, x: 2, y: 0))
        #expect(
            ScholiumStructuralDepthRole.readingEvidenceBoundary.style(
                isDark: false,
                increasedContrast: false,
                reduceTransparency: false,
                appearsActive: true,
                layoutDirection: .rightToLeft
            ) == .init(opacity: 0.04, radius: 8, x: -2, y: 0))
        for quietStyle in [
            ScholiumStructuralDepthRole.documentNavigationBoundary.style(
                isDark: true,
                increasedContrast: false,
                reduceTransparency: false,
                appearsActive: true,
                layoutDirection: .leftToRight
            ),
            ScholiumStructuralDepthRole.documentNavigationBoundary.style(
                isDark: false,
                increasedContrast: false,
                reduceTransparency: true,
                appearsActive: true,
                layoutDirection: .leftToRight
            ),
            ScholiumStructuralDepthRole.documentNavigationBoundary.style(
                isDark: false,
                increasedContrast: false,
                reduceTransparency: false,
                appearsActive: false,
                layoutDirection: .leftToRight
            ),
        ] {
            #expect(quietStyle.opacity == 0.02)
        }
        #expect(
            ScholiumStructuralDepthRole.documentNavigationBoundary.style(
                isDark: true,
                increasedContrast: true,
                reduceTransparency: true,
                appearsActive: false,
                layoutDirection: .rightToLeft
            ).opacity == 0)
        #expect(
            ScholiumElevationRole.floatingControl.style(
                increasedContrast: false,
                reduceTransparency: false,
                appearsActive: true
            ) == .init(opacity: 0.04, radius: 4, x: 0, y: 2))
        #expect(
            ScholiumElevationRole.boundedPanel.style(
                increasedContrast: false,
                reduceTransparency: false,
                appearsActive: true
            ) == .init(opacity: 0.08, radius: 8, x: 0, y: 4))
        #expect(
            ScholiumElevationRole.searchOverlay.style(
                increasedContrast: false,
                reduceTransparency: false,
                appearsActive: true
            ) == .init(opacity: 0.12, radius: 12, x: 0, y: 6))
        #expect(
            ScholiumElevationRole.searchOverlay.style(
                increasedContrast: false,
                reduceTransparency: true,
                appearsActive: false
            ).opacity == 0.036)
        #expect(
            ScholiumElevationRole.searchOverlay.style(
                increasedContrast: true,
                reduceTransparency: false,
                appearsActive: true
            ).opacity == 0)

        let elevationVariableNames = Set(
            ScholiumElevationRole.allCases.map(\.cssVariableName)
        )
        #expect(
            ScholiumWebDesignTokens.resolvedElevationRoleCSSVariableNames
                == elevationVariableNames
        )
        for name in elevationVariableNames {
            #expect(ScholiumWebDesignTokens.elevationCSSDeclarations.contains(name))
            #expect(
                ScholiumWebDesignTokens.reducedTransparencyElevationCSSDeclarations
                    .contains(name)
            )
            #expect(
                ScholiumWebDesignTokens.increasedContrastElevationCSSDeclarations
                    .contains("\(name): none;")
            )
        }
        let webPresentationCSS = ScholiumWebDesignTokens.documentPresentationCSS
        #expect(
            webPresentationCSS.contains(
                "box-shadow: var(--scholium-elevation-floating-control)"
            ))
        #expect(
            webPresentationCSS.contains(
                "box-shadow: var(--scholium-elevation-bounded-panel)"
            ))
        #expect(
            ScholiumPreviewStyles.css.contains(
                "box-shadow: var(--scholium-elevation-bounded-panel)"
            ))
        #expect(
            !ScholiumPreviewStyles.css.contains(
                "box-shadow: 0 0.75rem 2.25rem"
            ))

        #expect(
            ScholiumBoundaryRole.floatingBoundary.style(
                increasedContrast: false,
                reduceTransparency: false
            ).lineWidth == 0.75)
        #expect(
            ScholiumBoundaryRole.floatingBoundary.style(
                increasedContrast: true,
                reduceTransparency: false
            ).lineWidth == 1)
        #expect(
            ScholiumBoundaryRole.structuralDivider.style(
                increasedContrast: false,
                reduceTransparency: false
            ).opacity == 0.42)
        #expect(
            ScholiumBoundaryRole.structuralDivider.style(
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
                #expect((0...1).contains(insets.trailingViewportFraction))
            }
        }

        #expect(ScholiumDocumentRhythm.contentInsets(for: .read, widthClass: .regular).inline == 32)
        #expect(
            ScholiumDocumentRhythm.contentInsets(for: .livePreview, widthClass: .regular).inline
                == 32)
        #expect(
            ScholiumDocumentRhythm.contentInsets(for: .source, widthClass: .regular).inline == 40)
        #expect(ScholiumDocumentRhythm.contentInsets(for: .read, widthClass: .narrow).inline == 20)
        let defaults = DocumentAppearanceSettings.defaultSettings
        #expect(
            ScholiumWebDesignTokens.rhythmCSSDeclarations.contains(
                "--scholium-document-h1-size: 200%"
            ))
        #expect(
            ScholiumWebDesignTokens.rhythmCSSDeclarations.contains(
                "--scholium-document-h2-size: 150%"
            ))
        #expect(
            ScholiumWebDesignTokens.rhythmCSSDeclarations.contains(
                "--scholium-document-h3-size: 115%"
            ))
        #expect(
            ScholiumWebDesignTokens.rhythmCSSDeclarations.contains(
                "--scholium-document-h4-size: 115%"
            ))
        #expect(
            ScholiumWebDesignTokens.rhythmCSSDeclarations.contains(
                "--scholium-rhythm-heading-line-height: 1.8"
            ))
        #expect(
            ScholiumWebDesignTokens.rhythmCSSDeclarations.contains(
                "--scholium-document-heading-weight: 500"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                "font-weight: var(--scholium-document-heading-weight)"
            ))
        #expect(defaults.headings.level2.scale == 1.15)

        let sharedCSS = ScholiumWebDesignTokens.documentPresentationCSS
        let fixedDocumentSyntax = ScholiumWebDesignTokens.fixedDocumentSyntaxCSSDeclarations
        let editorHTML = try #require(MarkdownEditorWebView.editorHTML)
        for declaration in ScholiumWebDesignTokens.rhythmCSSDeclarations.split(separator: "\n") {
            let normalized = declaration.trimmingCharacters(in: .whitespaces)
            #expect(sharedCSS.contains(normalized))
        }
        #expect(editorHTML.contains(sharedCSS))
        #expect(SafeMarkdownReadWebView.Coordinator.baseCSS.contains(sharedCSS))
        #expect(fixedDocumentSyntax.contains("--scholium-mark-highlight-background: #ff9a00"))
        #expect(fixedDocumentSyntax.contains("--scholium-mark-highlight-text: #28241d"))
        #expect(sharedCSS.contains(fixedDocumentSyntax))
        #expect(sharedCSS.contains("background: var(--scholium-mark-highlight-background)"))
        #expect(sharedCSS.contains("color: var(--scholium-mark-highlight-text)"))
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
        #expect(!calloutCSS.contains(".cm-live-callout-role {"))
        #expect(calloutCSS.contains("--scholium-callout-surface: color-mix("))
        #expect(calloutCSS.contains("background: transparent;"))
        #expect(calloutCSS.contains(".scholium-callout-cite,\n.scholium-callout-flag {"))
        #expect(calloutCSS.contains("padding-block: .72rem .8rem;"))
        #expect(calloutCSS.contains("background: var(--scholium-callout-surface);"))
        #expect(
            calloutCSS.contains(
                ".scholium-callout-flag {\n  background: var(--scholium-callout-surface-emphasis);")
        )
        #expect(calloutCSS.contains("--scholium-callout-connect-content-indent: 1.1em;"))
        #expect(
            calloutCSS.contains(
                ".scholium-callout-connect .scholium-callout-body {\n  margin-top: .34rem;"))
        #expect(calloutCSS.contains("color: var(--scholium-callout-secondary-ink);"))
        #expect(
            calloutCSS.contains(
                ".scholium-callout-connect .scholium-callout-content > ul > li + li {"))
        #expect(
            !calloutCSS.contains(
                ".scholium-callout-connect .scholium-callout-content > ul > li::before"))
        #expect(!calloutCSS.contains("content: \"—\";"))
        #expect(!calloutCSS.contains("border-inline-start:"))
        #expect(calloutCSS.contains(".scholium-callout-orient > header .scholium-callout-heading,"))
        #expect(calloutCSS.contains("aside.scholium-callout-state > header,"))
        #expect(
            calloutCSS.contains(
                "aside.scholium-callout-state .scholium-callout-heading {\n  display: inline;"))
        #expect(calloutCSS.contains("aside.scholium-callout-illustrate {\n  display: grid;"))
        #expect(calloutCSS.contains("aside.scholium-callout-quote > header {\n  order: 2;"))
        #expect(calloutCSS.contains(".scholium-callout-quote .scholium-callout-quotation,"))
        #expect(calloutCSS.contains("background: radial-gradient("))
        #expect(calloutCSS.contains("var(--scholium-callout-fold-surface) 0%"))
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
        #expect(
            sharedCSS.contains(
                "border-inline-start: 3px solid var(--scholium-color-accent);"
            ))
        #expect(
            !sharedCSS.contains(
                "color-mix(in srgb, AccentColor"
            ))
        #expect(editorHTML.contains(sharedCSS))
        #expect(
            editorCSS.contains(
                "#editor .cm-editor.scholium-live-mode .cm-line.cm-live-quote"
            ))
        #expect(
            editorCSS.contains(
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
            contentsOf: repository.appendingPathComponent(
                "WebEditor/live-semantic-layout.ts"
            ),
            encoding: .utf8
        )

        #expect(
            editorSource.contains(
                #"if (headingLevel === 1) classes.add("cm-live-document-title");"#
            ))
        #expect(
            !editorSource.contains(
                "const isDocumentTitle = headingLevel === 1 && line.from === firstBodyLineFrom;"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                "text-align: start;"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                "text-align: center;"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                ".scholium-live-mode .cm-live-document-title,"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
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
        let fractionBarrier = try #require(
            fractionTail.range(
                of: "options.flushPresentationGeometry();"
            ))
        let fractionExtent = try #require(
            fractionTail.range(
                of: "const extent = Math.max(0, editor.scrollDOM.scrollHeight"
            ))
        #expect(fractionBarrier.lowerBound < fractionExtent.lowerBound)

        let anchorOperation = try #require(
            scrollSource.range(of: "function setAnchor(anchor: EditorScrollAnchor) {")
        )
        let anchorTail = scrollSource[anchorOperation.lowerBound...]
        let anchorBarrier = try #require(
            anchorTail.range(
                of: "options.flushPresentationGeometry();"
            ))
        let anchorGeometry = try #require(
            anchorTail.range(of: "requestedScrollTop(anchor)")
        )
        #expect(anchorBarrier.lowerBound < anchorGeometry.lowerBound)
        let requestedScrollTop = try #require(
            scrollSource.range(of: "function requestedScrollTop(anchor: EditorScrollAnchor) {")
        )
        #expect(scrollSource[requestedScrollTop.lowerBound...].contains(
            "editor.lineBlockAt(blockProbe)"
        ))
        let dynamicStyle = try #require(
            editorSource.range(of: "function setDynamicStyle(id: string, css: string) {")
        )
        let dynamicStyleTail = editorSource[dynamicStyle.lowerBound...]
        let capturedGeometry = try #require(
            dynamicStyleTail.range(of: "scrollCoordinator.captureGeometry()")
        )
        let styleMutation = try #require(
            dynamicStyleTail.range(of: "style.textContent = css")
        )
        let measuredRestoration = try #require(
            dynamicStyleTail.range(of: "scrollCoordinator.scheduleGeometryReport(geometry)")
        )
        #expect(capturedGeometry.lowerBound < styleMutation.lowerBound)
        #expect(styleMutation.lowerBound < measuredRestoration.lowerBound)
        #expect(scrollSource.contains("editor.requestMeasure({"))
        #expect(scrollSource.contains("editor.scrollDOM.scrollTop = scrollTop"))
        #expect(
            editorSource.contains(
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
        #expect(css.contains("scholium-font://bundled/KaTeX_"))
        #expect(!css.contains("data:font/woff2;base64,"))
        #expect(!css.contains("url(fonts/"))
        #expect(css.contains(".scholium-math-display"))
        #expect(
            css.contains("grid-template-columns: minmax(2.5em, 1fr) max-content minmax(2.5em, 1fr)")
        )
        #expect(css.contains("min-inline-size: max-content;"))
        #expect(!css.contains("grid-template-columns: minmax(2.5em, 1fr) minmax(0, auto)"))
        #expect(css.contains("counter-increment: scholium-equation"))
        #expect(css.contains("content: \"(\" counter(scholium-equation) \")\""))
        #expect(css.contains(".scholium-math-display .katex { font-style: italic; }"))
        #expect(editorHTML.contains(css))

        let plainReadHTML = SafeMarkdownReadWebView.Coordinator.documentHTML(
            body: "<p>Ordinary prose</p>"
        )
        let mathReadHTML = SafeMarkdownReadWebView.Coordinator.documentHTML(
            body: #"<span class="scholium-math scholium-math-inline" data-math-source="eA==" data-math-kind="inline"></span>"#
        )
        #expect(!plainReadHTML.contains(css))
        #expect(mathReadHTML.contains(css))
    }

    @Test("Read and Editor fonts use one allowlisted offline WebKit resource route")
    func sharedOfflineFontResources() throws {
        let editorHTML = try #require(MarkdownEditorWebView.editorHTML)
        let readHTML = SafeMarkdownReadWebView.Coordinator.documentHTML(
            body: "<p>Ordinary prose</p>"
        )
        let regularURL = try #require(URL(
            string: ScholiumWebFontResources.url(for: "Alegreya-Regular.ttf")
        ))
        let regular = try #require(ScholiumWebFontResources.resource(for: regularURL))

        #expect(regular.mimeType == "font/ttf")
        #expect(!regular.data.isEmpty)
        #expect(ScholiumWebFonts.css.contains(regularURL.absoluteString))
        #expect(!ScholiumWebFonts.css.contains("data:font/ttf;base64,"))
        #expect(editorHTML.contains("font-src scholium-font: data:"))
        #expect(readHTML.contains("font-src scholium-font: data:"))
        #expect(ScholiumWebFontResources.resource(
            for: URL(string: "scholium-font://bundled/../../Private.md")!
        ) == nil)
        #expect(ScholiumWebFontResources.resource(
            for: URL(string: "https://example.com/Alegreya-Regular.ttf")!
        ) == nil)
    }

    @Test("Initial WebKit prewarm is nonpersistent, source-free, and bounded")
    func initialWebKitPrewarmIsBounded() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Styling/ScholiumWebKitRuntime.swift"
            ),
            encoding: .utf8
        )
        #expect(source.contains("WKWebsiteDataStore.nonPersistent()"))
        #expect(source.contains("default-src 'none'"))
        #expect(source.contains("font-src scholium-font:"))
        #expect(source.contains("ScholiumWebFonts.css"))
        #expect(source.contains("Task.sleep(for: .seconds(5))"))
        #expect(source.contains("func takeReadWebView() -> WKWebView?"))
        #expect(!source.contains("WKProcessPool"))
        #expect(!source.contains("URLSession"))

        let readSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/SafeMarkdownReadWebView.swift"
            ),
            encoding: .utf8
        )
        #expect(readSource.contains("takeReadWebView()"))
    }

    @Test("Review and Edit share one offline fail-closed Mermaid runtime")
    func sharedMermaidRuntime() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let editorWebViewSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/MarkdownEditorWebView.swift"
            ),
            encoding: .utf8
        )
        let editorHTML = try #require(MarkdownEditorWebView.editorHTML)
        let readHTML = SafeMarkdownReadWebView.Coordinator.documentHTML(
            body: #"<pre><code class="language-mermaid">flowchart LR\nA --&gt; B</code></pre>"#,
        )
        let readRuntime = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/reader.ts"),
            encoding: .utf8
        )
        let css = ScholiumMermaidAssets.css

        #expect(ScholiumMermaidAssets.runtimeJavaScript.contains("scholiumMermaid"))
        #expect(ScholiumMermaidAssets.runtimeJavaScript.contains("securityLevel"))
        #expect(ScholiumMermaidAssets.runtimeJavaScript.contains("attachShadow"))
        #expect(css.contains(".scholium-mermaid-output"))
        #expect(css.contains("overflow-x: auto"))
        #expect(css.contains("contain: paint"))
        #expect(editorHTML.contains(css))
        #expect(
            !editorWebViewSource.contains(
                "source: ScholiumMermaidAssets.runtimeJavaScript"
            ))
        #expect(editorWebViewSource.contains("case .requestMermaidRuntime"))
        #expect(readHTML.contains(css))
        #expect(readRuntime.contains("readerWindow.scholiumMermaidReady"))
        #expect(readRuntime.contains("post('requestMermaidRuntime')"))
        #expect(readRuntime.contains("runtime.mount(output, result.svg)"))
        #expect(readRuntime.contains("document.querySelectorAll('pre > code')"))
        #expect(readRuntime.contains("name.toLowerCase() === 'language-mermaid'"))
        #expect(!readRuntime.contains("diagnostic.setAttribute('role', 'status')"))
    }

    @Test("Structured Appearance CSS maps the exported typography and callout profile")
    func structuredAppearanceCSS() {
        let profile = DocumentAppearanceProfile(name: "Custom")
        let css = DocumentAppearanceStyles.css(for: profile)

        #expect(css.contains("--scholium-document-prose-font-size: 12pt"))
        #expect(css.contains("--scholium-rhythm-prose-line-height: 2"))
        #expect(css.contains("--scholium-rhythm-title-before: 0em"))
        #expect(css.contains("--scholium-rhythm-title-after: 2em"))
        #expect(
            css.contains(
                "font-size: calc(var(--scholium-document-prose-font-size) * var(--scholium-document-text-scale-factor))"
            ))
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
        #expect(
            SafeMarkdownReadWebView.Coordinator.documentHTML(
                body: "<div class=\"scholium-table-scroll\"></div>"
            ).contains(css))
    }

    @Test("Review owns rendered footnotes while Edit reuses only the reference role")
    func footnotePresentationRespectsModeOwnership() throws {
        let editorHTML = try #require(MarkdownEditorWebView.editorHTML)
        let css = ScholiumFootnoteStyles.css

        #expect(css.contains(".footnote-reference"))
        #expect(css.contains(".footnotes"))
        #expect(css.contains(".cm-live-footnote-reference-widget"))
        #expect(!css.contains(".cm-live-footnotes-widget"))
        #expect(css.contains("padding-inline-end"))
        #expect(editorHTML.contains(css))
        #expect(
            SafeMarkdownReadWebView.Coordinator.documentHTML(
                body: "<section class=\"footnotes\"></section>"
            ).contains(css))
    }

    @Test("Review owns footnote preview while Edit locates one direct exact-source definition")
    func footnoteInteractionStaysWithinEachModeBoundary() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let editorSource = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/editor.ts"),
            encoding: .utf8
        )
        let footnoteSource = try String(
            contentsOf: repository.appendingPathComponent(
                "WebEditor/live-footnote-projection.ts"
            ),
            encoding: .utf8
        )
        let referenceStart = try #require(
            footnoteSource.range(of: "class FootnoteReferenceWidget")
        )
        let referenceEnd = try #require(
            footnoteSource.range(
                of: "function decorations(",
                range: referenceStart.upperBound..<footnoteSource.endIndex
            )
        )
        let editReference = String(
            footnoteSource[referenceStart.lowerBound..<referenceEnd.lowerBound])
        let readHTML = SafeMarkdownReadWebView.Coordinator.documentHTML(
            body:
                #"<p>Claim<button class="footnote-reference" data-footnote="1">1</button>.</p><section class="footnotes"><ol><li data-footnote="1"><div class="footnote-content">Basis.</div><button class="footnote-return">Return</button></li></ol></section>"#,
        )
        let readRuntime = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/reader.ts"),
            encoding: .utf8
        )

        #expect(footnoteSource.contains("reference.definitionContentFrom"))
        #expect(!editReference.contains("showFootnotePopover"))
        #expect(!editReference.contains("footnote-return"))
        #expect(
            editReference.contains(
                #"ignoreEvent(event: Event) { return event.type !== "mousedown"; }"#))
        #expect(editorSource.contains("projectedWidgetPointerStart"))
        #expect(editorSource.contains("createLiveSelectionController"))
        #expect(!editorSource.contains("beginProjectedPointerSelection"))
        #expect(!editorSource.contains("liveBlockActivationField"))
        #expect(!footnoteSource.contains("class FootnoteSectionWidget"))
        #expect(!footnoteSource.contains("cm-live-footnotes-widget"))
        #expect(!footnoteSource.contains("cm-live-footnote-definition-source"))
        #expect(readHTML.contains("class=\"footnote-reference\""))
        #expect(readHTML.contains("class=\"footnote-return\""))
        #expect(readRuntime.contains("showFootnotePopover"))
        #expect(readRuntime.contains("eventElement?.closest<HTMLButtonElement>('.footnote-reference')"))
        #expect(readRuntime.contains("eventElement?.closest<HTMLElement>('.footnote-return')"))
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
        #expect(css.contains("background: var(--scholium-color-surface-background)"))
        #expect(css.contains("border: 1px solid var(--scholium-color-separator)"))
        #expect(css.contains("box-shadow: var(--scholium-elevation-bounded-panel)"))
        #expect(!css.contains("Canvas"))
        #expect(!css.contains("backdrop-filter"))
        #expect(!css.contains("prefers-reduced-transparency: reduce"))
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
            syntax: .vectorWikilink,
            relationship: .supports,
            fragment: "Claim",
            htmlBody: "<p>Target body</p>"
        )
        let readHTML = SafeMarkdownReadWebView.Coordinator.documentHTML(
            body:
                #"<a class="wiki-link" data-source-utf16-start="0" data-source-utf16-end="10">Target</a>"#
        )
        let readRuntime = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/reader.ts"),
            encoding: .utf8
        )
        #expect(readHTML.contains(css))
        #expect(readRuntime.contains("previewByRange"))
        #expect(readRuntime.contains("showLinkPopover"))
        #expect(readRuntime.contains("showFootnotePopover"))
        #expect(readRuntime.contains("renderEmbeddedNotes"))
        #expect(readRuntime.contains("scholium-embedded-note-viewport"))
        #expect(previewControllerSource.contains("ViewPlugin.define"))
        #expect(previewControllerSource.contains("populatePreviewDocument"))
        #expect(previewControllerSource.contains("scheduleHide"))
        #expect(previewControllerSource.contains("document.removeEventListener"))
        #expect(previewControllerSource.contains("floatingSurfacePosition"))
        #expect(previewControllerSource.contains(#"addEventListener("scroll", handleViewportExit"#))
        #expect(previewControllerSource.contains(#"addEventListener("resize", handleViewportExit"#))
        #expect(previewControllerSource.contains(#"addEventListener("blur", handleViewportExit"#))
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
        let contextMenuSource = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/context-menu.ts"),
            encoding: .utf8
        )
        let editorMenuSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/Note/MarkdownEditorNativeWebView.swift"
            ),
            encoding: .utf8
        )
        let readHTML = SafeMarkdownReadWebView.Coordinator.documentHTML(
            body: #"<p data-source-line="2">A bounded claim.</p>"#
        )
        let readRuntime = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/reader.ts"),
            encoding: .utf8
        )

        #expect(
            readRuntime.contains(
                "localized('Return saves · Shift-Return adds a line · Escape cancels')"
            )
        )
        #expect(readRuntime.contains("commentSubmitted"))
        #expect(readRuntime.contains("Comment for"))
        #expect(readHTML.contains(#"class="scholium-selection-actions""#))
        #expect(readHTML.contains(#"class="scholium-selection-toolbar""#))
        #expect(
            readHTML.contains(
                #"id="comment-selection" class="scholium-selection-control""#
            ))
        #expect(readHTML.contains(#"class="scholium-selection-label"></span>"#))
        #expect(readRuntime.contains("textContent = localized('Comment')"))
        #expect(readRuntime.contains("scholium-selection-keyboard-focus"))
        #expect(readRuntime.contains("ResolveCommentSubmission"))
        #expect(readRuntime.contains("Your Comment is still here"))
        #expect(
            readHTML.contains(
                "#comment-text:focus-visible { box-shadow: inset 0 0 0 1px var(--scholium-content-focus-ring); }"
            ))
        #expect(
            !readHTML.contains(
                "#comment-text:focus-visible { outline: 2px solid var(--scholium-content-focus-ring)"
            ))
        #expect(readRuntime.contains("TextEncoder"))
        #expect(readRuntime.contains("makeRequestID"))
        #expect(readRuntime.contains("globalThis.crypto.getRandomValues"))
        #expect(readRuntime.contains("commentSelectionRange = range.cloneRange()"))
        #expect(readRuntime.contains("const range = commentSelectionRange?.cloneRange()"))
        #expect(readRuntime.contains("selection.addRange(range)"))
        #expect(!readHTML.contains("Copy and Open Agent App"))
        #expect(!readHTML.contains("Copy Only"))
        #expect(readRuntime.contains("startLine"))
        #expect(readRuntime.contains("endLine"))
        #expect(!readHTML.contains("quotation:"))
        #expect(!readHTML.contains("utf16Range"))
        #expect(selectionActionsSource.contains("view.composing"))
        #expect(selectionActionsSource.contains("scheduleFocusExit(view)"))
        #expect(selectionActionsSource.contains("root?.contains(document.activeElement)"))
        #expect(selectionActionsSource.contains("ViewPlugin.define"))
        #expect(selectionActionsSource.contains("destroy()"))
        #expect(selectionActionsSource.contains("root?.remove()"))
        #expect(!selectionActionsSource.contains("mode()"))
        #expect(selectionActionsSource.contains("selectionActionCommands"))
        #expect(selectionActionsSource.contains("floatingSurfacePosition"))
        #expect(selectionActionsSource.contains("reposition(view"))
        #expect(selectionActionsSource.contains("wikiGroup.append(wiki, vector)"))
        #expect(
            selectionActionsSource.contains(
                #"createMenu(vector, "scholium-selection-vector-menu")"#
            ))
        #expect(
            selectionActionsSource.contains(
                #"createMenu(more, "scholium-selection-more-menu")"#
            ))
        #expect(
            selectionActionsSource.contains(
                #"addMenuItem(moreMenu, localized("Comment"), "markdownComment", "", false, "eye-slash")"#
            ))
        #expect(selectionActionsSource.contains("systemSymbolElement"))
        #expect(selectionActionsSource.contains("synchronizeKeyboardFocusFeedback"))
        #expect(!selectionActionsSource.contains("createElementNS"))
        #expect(!selectionActionsSource.contains("[["))
        #expect(!selectionActionsSource.contains("%%"))
        #expect(selectionActionsSource.contains(#"root.className = "scholium-selection-actions""#))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                ".scholium-selection-actions"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                "background: var(--scholium-color-surface-background)"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                "border: 1px solid var(--scholium-color-separator)"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                ".scholium-selection-control:hover,"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                ".scholium-selection-menu-item:focus,"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                ".cm-tooltip-autocomplete.scholium-editor-suggestions > ul > li:hover {"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                "background: var(--scholium-content-hover-surface)"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                "background: var(--scholium-content-keyboard-focus-surface)"
            ))
        #expect(
            ScholiumWebDesignTokens.documentPresentationCSS.contains(
                "background: var(--scholium-color-raised-surface-background)"
            ))
        #expect(
            !ScholiumWebDesignTokens.documentPresentationCSS.contains(
                ".scholium-selection-actions {\n      backdrop-filter"
            ))
        #expect(!editorSource.contains("commentSubmitted"))
        #expect(!editorSource.contains("showCommentComposer"))
        #expect(selectionActionsSource.contains(#"wikiLabel.textContent = localized("Wiki")"#))
        #expect(!editorMenuSource.contains("Comment on Selection"))
        #expect(!editorMenuSource.contains("commentSubmitted"))
        #expect(!editorMenuSource.contains("onRequestComment"))
        #expect(!editorMenuSource.contains("rightMouseMonitor"))
        #expect(!editorMenuSource.contains("handleRightMouseDown"))
        #expect(!editorMenuSource.contains("popUpContextMenu"))
        #expect(!editorMenuSource.contains("override func menu(for"))
        #expect(editorMenuSource.contains("presentEditorContextMenu"))
        #expect(editorMenuSource.contains("#selector(NSText.cut(_:))"))
        #expect(editorMenuSource.contains("#selector(NSText.copy(_:))"))
        #expect(editorMenuSource.contains("#selector(NSText.paste(_:))"))
        #expect(editorSource.contains(#"type: "contextMenuRequested""#))
        #expect(contextMenuSource.contains("event.preventDefault()"))
        #expect(contextMenuSource.contains("selectionForContextClick"))
        #expect(contextMenuSource.contains("view.focus()"))
    }

    @Test("Relationship colors provide increased-contrast variants")
    func increasedContrastRelationshipColors() throws {
        let aqua = try #require(NSAppearance(named: .aqua))
        let darkAqua = try #require(NSAppearance(named: .darkAqua))

        #expect(
            ScholiumColorRole.connectionSupport.resolvedRGBValue(
                for: aqua,
                increasedContrast: false
            ) == 0x2F675E)
        #expect(
            ScholiumColorRole.connectionSupport.resolvedRGBValue(
                for: darkAqua,
                increasedContrast: false
            ) == 0x8CC5BA)
        #expect(
            ScholiumColorRole.connectionSupport.resolvedRGBValue(
                for: aqua,
                increasedContrast: true
            ) == 0x01423A)
        #expect(
            ScholiumColorRole.connectionSupport.resolvedRGBValue(
                for: darkAqua,
                increasedContrast: true
            ) == 0xB6F0E5)

        #expect(
            ScholiumColorRole.connectionIncompatible.resolvedRGBValue(
                for: aqua,
                increasedContrast: false
            ) == 0x72516A)
        #expect(
            ScholiumColorRole.connectionIncompatible.resolvedRGBValue(
                for: darkAqua,
                increasedContrast: false
            ) == 0xD2ADC8)
        #expect(
            ScholiumColorRole.connectionIncompatible.resolvedRGBValue(
                for: aqua,
                increasedContrast: true
            ) == 0x4A2C43)
        #expect(
            ScholiumColorRole.connectionIncompatible.resolvedRGBValue(
                for: darkAqua,
                increasedContrast: true
            ) == 0xFED7F4)

        #expect(ScholiumWebDesignTokens.increasedContrastCSSDeclarations.contains("#01423a"))
        #expect(ScholiumWebDesignTokens.increasedContrastCSSDeclarations.contains("#4a2c43"))
        #expect(ScholiumWebDesignTokens.darkIncreasedContrastCSSDeclarations.contains("#b6f0e5"))
        #expect(ScholiumWebDesignTokens.darkIncreasedContrastCSSDeclarations.contains("#fed7f4"))
    }

    @Test("The live Connections inspector uses one semantic presentation")
    func sharedConnectionPresentation() throws {
        let expected: [(ScholiumConnectionPresentation, String, ScholiumSystemSymbol)] = [
            (.supports, "Supports", .plusCircle),
            (.supportsThisNote, "Supports This Note", .plusCircle),
            (.opposes, "Opposes", .minusCircle),
            (.opposesThisNote, "Opposes This Note", .minusCircle),
            (.incompatible, "Incompatible", .xmarkCircle),
            (.neutral, "Related", .link),
        ]
        for (presentation, title, systemSymbol) in expected {
            #expect(presentation.title == title)
            #expect(presentation.systemSymbol == systemSymbol)
        }

        #expect(
            ScholiumConnectionPresentation(
                vectorKind: .supports,
                currentIsSource: true
            ) == .supports)
        #expect(
            ScholiumConnectionPresentation(
                vectorKind: .supports,
                currentIsSource: false
            ) == .supportsThisNote)
        #expect(
            ScholiumConnectionPresentation(
                vectorKind: .opposes,
                currentIsSource: true
            ) == .opposes)
        #expect(
            ScholiumConnectionPresentation(
                vectorKind: .opposes,
                currentIsSource: false
            ) == .opposesThisNote)
        #expect(
            ScholiumConnectionPresentation(
                vectorKind: .incompatible,
                currentIsSource: true
            ) == .incompatible)
        #expect(
            ScholiumConnectionPresentation(
                vectorKind: .incompatible,
                currentIsSource: false
            ) == .incompatible)
        #expect(
            ScholiumConnectionPresentation(
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

    @Test("Connection direction filters only directed relations")
    func connectionDirectionMembership() {
        #expect(
            ConnectionDirection.outgoing.includes(
                currentIsSource: true,
                vectorKind: .supports
            ))
        #expect(
            !ConnectionDirection.outgoing.includes(
                currentIsSource: false,
                vectorKind: .supports
            ))
        #expect(
            ConnectionDirection.incoming.includes(
                currentIsSource: false,
                vectorKind: .opposes
            ))
        #expect(
            !ConnectionDirection.incoming.includes(
                currentIsSource: true,
                vectorKind: .opposes
            ))
        for direction in ConnectionDirection.allCases {
            for vectorKind in [nil, .neutral, .incompatible] as [VectorLinkKind?] {
                #expect(direction.includes(currentIsSource: true, vectorKind: vectorKind))
                #expect(direction.includes(currentIsSource: false, vectorKind: vectorKind))
            }
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
            result =
                (UInt32((red * 255).rounded()) << 16)
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
