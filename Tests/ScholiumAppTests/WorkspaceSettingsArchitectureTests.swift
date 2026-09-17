import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Workspace Settings architecture")
@MainActor
struct WorkspaceSettingsArchitectureTests {
    @Test("Settings model has no window or document session state")
    func constructionIsWindowIndependent() async {
        let model = WorkspaceSettingsModel(selectedPane: .workspace)
        let storedTypeNames = Mirror(reflecting: model).children.map {
            String(reflecting: type(of: $0.value))
        }

        #expect(storedTypeNames.allSatisfy { !$0.contains("WindowModel") })
        #expect(storedTypeNames.allSatisfy { !$0.contains("DocumentController") })
        #expect(storedTypeNames.allSatisfy { !$0.contains("DocumentSession") })
        #expect(model.selectedPane == .workspace)
        #expect(!model.hasWritableTriptychSettings)

        model.replaceSnapshot(
            WorkspaceSettingsSnapshot(
                settingsRevision: SettingsRevision(
                    fingerprint: DocumentFingerprint(content: "settings")
                )
            ))
        #expect(model.hasWritableTriptychSettings)
    }

    @Test("Settings top level exposes each canonical pane once")
    func topLevelPaneOwnership() throws {
        #expect(
            WorkspaceSettingsPane.allCases.map(\.rawValue) == [
                "workspace",
                "document",
                "writing",
                "agents",
                "shortcuts",
                "notifications",
                "zotero",
            ]
        )

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/WorkspaceSettingsView.swift"
            ),
            encoding: .utf8
        )
        let topLevelEnd = try #require(
            source.range(of: "struct ZoteroSettingsView")
        )
        let topLevel = String(source[..<topLevelEnd.lowerBound])

        #expect(topLevel.contains("ScholiumSettingsNavigationHost(title: destination.title, sidebar: sidebar, page: selectedPage)"))
        #expect(!topLevel.contains(".navigationTitle("))
        #expect(!topLevel.contains("NavigationSplitView"))
        #expect(!topLevel.contains("HSplitView"))
        #expect(topLevel.contains(".listStyle(.sidebar)"))
        #expect(topLevel.contains("ScholiumSettingsDestination.workspace"))
        #expect(!topLevel.contains("SettingsTriptychScopePicker"))
        #expect(topLevel.contains("ScholiumSettingsSearchField(text: $searchQuery)"))
        #expect(topLevel.contains("destinationBeforeSearch"))
        #expect(!topLevel.contains("Text(\"Settings\")"))
        #expect(!topLevel.contains("ZoteroSettingsView()"))

        #expect(ScholiumSettingsDestination.allCases.map(\.rawValue) == WorkspaceSettingsPane.allCases.map(\.rawValue))
        let taskPages = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scholium/Views/SettingsTaskPages.swift"),
            encoding: .utf8
        )
        #expect(taskPages.components(separatedBy: "ZoteroSettingsView()").count == 2)
        #expect(!taskPages.contains("SettingsInteractionCategory"))
        #expect(!taskPages.contains("SettingsIntegrationCategory"))

    }

    @Test("Settings keeps scope legible without page-wide banners")
    func settingsScopeAndPageHierarchy() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/WorkspaceSettingsView.swift"
            ),
            encoding: .utf8
        )
        let attentionSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/AttentionSettingsView.swift"
            ),
            encoding: .utf8
        )
        let allSettingsSource = source + attentionSource

        #expect(!source.contains("TriptychScopedSettingsView"))
        #expect(!source.contains("SettingsTriptychScopePicker"))
        #expect(!source.contains("var usesTriptychScope: Bool"))
        #expect(source.contains("scholium.settings.triptychScope"))
        let workspaceStart = try #require(
            source.range(of: "struct WorkspaceSettingsView: View")
        )
        let documentStart = try #require(
            source.range(
                of: "private struct AppearanceSettingsView: View",
                range: workspaceStart.upperBound..<source.endIndex
            )
        )
        let workspaceSource = source[
            workspaceStart.lowerBound..<documentStart.lowerBound
        ]
        #expect(workspaceSource.contains("scholium.settings.triptychScope"))
        #expect(source.contains("ScholiumL10n.Settings.workspace"))
        #expect(source.contains("ScholiumL10n.Settings.document"))
        #expect(source.contains("ScholiumL10n.Settings.notifications"))
        #expect(source.contains("ScholiumL10n.WritingAssistance.title"))
        #expect(source.contains("case agents"))
        #expect(source.contains("case shortcuts"))
        #expect(source.contains("case zotero"))
        #expect(!source.contains("SettingsScopeNotice"))
        #expect(!source.contains("Registration and folder access are local to this Mac"))
        #expect(!source.contains("Document content only"))
        #expect(!source.contains("These profiles change how Markdown is presented"))
        #expect(allSettingsSource.contains("This Triptych"))
        #expect(allSettingsSource.contains("This Mac"))
        #expect(attentionSource.contains("Reminder Timing"))
        #expect(attentionSource.contains("Dismissed Items on This Mac"))
        #expect(attentionSource.contains("Restore All Dismissed Items on This Mac"))
        #expect(!source.contains("case integrations"))
        #expect(source.contains("settingsTriptychLabel("))
        #expect(
            source.contains(
                ".onChange(of: settingsModel.snapshot.activeTriptychID)"
            ))

        let integration = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/AgentIntegrationSettingsView.swift"
            ),
            encoding: .utf8
        )
        #expect(integration.contains("Copy Codex Setup Command"))
        #expect(integration.contains("Copy Claude Setup Command"))
        #expect(integration.contains("Open Skills and Tools"))
        #expect(!integration.contains("Show Core Protocol in Finder…"))
        #expect(integration.contains("External Access"))
        #expect(integration.contains("ExternalAgentHostsSettingsView"))
        #expect(!integration.contains("detail: helperURL?.path"))
        #expect(!integration.contains("Not found at $HOME/.local/bin/scholium"))
        #expect(!integration.contains("DisclosureGroup(\"Connect an External Agent\""))

        let connection = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/AgentChatConnectionSettingsView.swift"
            ),
            encoding: .utf8
        )
        #expect(connection.contains("Custom Connection Paths"))
        #expect(!connection.contains(".sheet("))
        #expect(!integration.contains(".sheet("))
    }

    @Test("Explicit Settings save keeps the draft's frozen revision")
    func explicitSaveUsesFrozenRevision() async throws {
        let first = SettingsRevision(
            fingerprint: DocumentFingerprint(content: "revision-one")
        )
        let second = SettingsRevision(
            fingerprint: DocumentFingerprint(content: "revision-two")
        )
        let committed = SettingsRevision(
            fingerprint: DocumentFingerprint(content: "committed")
        )
        let triptychID = UUID()
        var observedRevision: SettingsRevision?
        let model = WorkspaceSettingsModel(
            snapshot: WorkspaceSettingsSnapshot(
                activeTriptychID: triptychID,
                settingsRevision: first
            ),
            saveSettings: { targetID, settings, expectedRevision in
                #expect(targetID == triptychID)
                observedRevision = expectedRevision
                return WorkspaceSettingsCommit(
                    triptychID: targetID,
                    snapshot: TriptychSettingsSnapshot(
                        settings: settings,
                        revision: committed
                    ),
                    derivedRefreshWarning: nil
                )
            }
        )
        model.replaceSnapshot(
            WorkspaceSettingsSnapshot(
                activeTriptychID: triptychID,
                settingsRevision: second
            ))

        var candidate = TriptychSettings()
        candidate.attentionDismissalDays = 14
        try await model.saveTriptychSettings(
            candidate,
            targetTriptychID: triptychID,
            expectedRevision: first
        )

        #expect(observedRevision == first)
        #expect(model.settingsRevision == committed)
        #expect(model.triptychSettings.attentionDismissalDays == 14)
    }

    @Test("A Metadata draft cannot cross into another Triptych with identical bytes")
    func saveTargetIncludesTriptychIdentity() async {
        let firstID = UUID()
        let secondID = UUID()
        let sharedRevision = SettingsRevision(
            fingerprint: DocumentFingerprint(content: "identical-default-settings")
        )
        var saverWasCalled = false
        let model = WorkspaceSettingsModel(
            snapshot: WorkspaceSettingsSnapshot(
                activeTriptychID: firstID,
                settingsRevision: sharedRevision
            ),
            saveSettings: { id, settings, revision in
                saverWasCalled = true
                return WorkspaceSettingsCommit(
                    triptychID: id,
                    snapshot: TriptychSettingsSnapshot(
                        settings: settings,
                        revision: revision
                    ),
                    derivedRefreshWarning: nil
                )
            }
        )
        model.replaceSnapshot(
            WorkspaceSettingsSnapshot(
                activeTriptychID: secondID,
                settingsRevision: sharedRevision
            ))

        await #expect(throws: WorkspaceSettingsMutationError.self) {
            try await model.saveTriptychSettings(
                TriptychSettings(),
                targetTriptychID: firstID,
                expectedRevision: sharedRevision
            )
        }
        #expect(!saverWasCalled)
        #expect(model.snapshot.activeTriptychID == secondID)
    }

    @Test("An uncertain Settings commit is authoritatively reread before retry")
    func uncertainCommitReconcilesAuthoritativeSettings() async throws {
        let triptychID = UUID()
        let initial = SettingsRevision(
            fingerprint: DocumentFingerprint(content: "initial")
        )
        let committed = SettingsRevision(
            fingerprint: DocumentFingerprint(content: "reread-committed")
        )
        var candidate = TriptychSettings()
        candidate.attentionDismissalDays = 30
        let model = WorkspaceSettingsModel(
            snapshot: WorkspaceSettingsSnapshot(
                activeTriptychID: triptychID,
                settingsRevision: initial
            ),
            loadPortableSettings: { id in
                WorkspacePortableSettingsRead(
                    triptychID: id,
                    settings: candidate,
                    state: .current(committed)
                )
            },
            saveSettings: { _, _, _ in
                throw ScholiumApplicationError.operationCommitUncertain(
                    operation: "fixture settings",
                    reason: "fixture final window"
                )
            }
        )

        let result = try await model.saveTriptychSettings(
            candidate,
            targetTriptychID: triptychID,
            expectedRevision: initial
        )

        #expect(result.warning != nil)
        #expect(result.targetIsCurrent)
        #expect(model.triptychSettings == candidate)
        #expect(model.settingsRevision == committed)
    }

    @Test("Committed Settings remain saved when only derived refresh fails")
    func committedSettingsPublishNewRevisionWithWarning() async throws {
        let triptychID = UUID()
        let initial = SettingsRevision(
            fingerprint: DocumentFingerprint(content: "before")
        )
        let committed = SettingsRevision(
            fingerprint: DocumentFingerprint(content: "after")
        )
        var candidate = TriptychSettings()
        candidate.attentionDismissalDays = 14
        let model = WorkspaceSettingsModel(
            snapshot: WorkspaceSettingsSnapshot(
                activeTriptychID: triptychID,
                settingsRevision: initial
            ),
            saveSettings: { id, settings, _ in
                WorkspaceSettingsCommit(
                    triptychID: id,
                    snapshot: TriptychSettingsSnapshot(
                        settings: settings,
                        revision: committed
                    ),
                    derivedRefreshWarning: "fixture derived refresh"
                )
            }
        )

        let result = try await model.saveTriptychSettings(
            candidate,
            targetTriptychID: triptychID,
            expectedRevision: initial
        )

        #expect(result.warning != nil)
        #expect(result.targetIsCurrent)
        #expect(model.triptychSettings == candidate)
        #expect(model.settingsRevision == committed)
    }

    @Test("An in-flight save reports a proven commit to its original Triptych")
    func inFlightTriptychSwitchPreservesCommitTruth() async throws {
        let entered = SettingsTestSignal()
        let release = SettingsTestSignal()
        let firstID = UUID()
        let secondID = UUID()
        let revision = SettingsRevision(
            fingerprint: DocumentFingerprint(content: "shared")
        )
        let committed = SettingsRevision(
            fingerprint: DocumentFingerprint(content: "first-committed")
        )
        var candidate = TriptychSettings()
        candidate.attentionDismissalDays = 30
        let model = WorkspaceSettingsModel(
            snapshot: WorkspaceSettingsSnapshot(
                activeTriptychID: firstID,
                settingsRevision: revision
            ),
            saveSettings: { id, settings, _ in
                await entered.signal()
                await release.wait()
                return WorkspaceSettingsCommit(
                    triptychID: id,
                    snapshot: TriptychSettingsSnapshot(
                        settings: settings,
                        revision: committed
                    ),
                    derivedRefreshWarning: nil
                )
            }
        )

        let save = Task { @MainActor in
            try await model.saveTriptychSettings(
                candidate,
                targetTriptychID: firstID,
                expectedRevision: revision
            )
        }
        await entered.wait()
        model.replaceSnapshot(
            WorkspaceSettingsSnapshot(
                activeTriptychID: secondID,
                settingsRevision: revision
            ))
        await release.signal()
        let result = try await save.value

        #expect(!result.targetIsCurrent)
        #expect(result.warning != nil)
        #expect(model.snapshot.activeTriptychID == secondID)
        #expect(model.settingsRevision == revision)
    }

    @Test("Failed authoritative reread blocks every Settings retry")
    func rereadFailureMaintainsReconciliationBlock() async {
        struct RereadFailure: Error {}
        let triptychID = UUID()
        let revision = SettingsRevision(
            fingerprint: DocumentFingerprint(content: "before-uncertain")
        )
        var saveCount = 0
        let model = WorkspaceSettingsModel(
            snapshot: WorkspaceSettingsSnapshot(
                activeTriptychID: triptychID,
                settingsRevision: revision
            ),
            loadPortableSettings: { _ in throw RereadFailure() },
            saveSettings: { _, _, _ in
                saveCount += 1
                throw ScholiumApplicationError.operationCommitUncertain(
                    operation: "fixture settings",
                    reason: "fixture uncertainty"
                )
            }
        )

        for _ in 0..<2 {
            await #expect(throws: WorkspaceSettingsMutationError.self) {
                try await model.saveTriptychSettings(
                    TriptychSettings(),
                    targetTriptychID: triptychID,
                    expectedRevision: revision
                )
            }
        }
        #expect(saveCount == 1)
        #expect(model.requiresSettingsReconciliation(for: triptychID))
    }

    @Test("Failed Settings refresh preserves the last confirmed snapshot")
    func failedRefreshDoesNotInstallStaleState() async {
        struct RefreshFailure: LocalizedError {
            var errorDescription: String? { "fixture refresh failed" }
        }
        let revision = SettingsRevision(
            fingerprint: DocumentFingerprint(content: "confirmed")
        )
        var confirmed = TriptychSettings()
        confirmed.attentionDismissalDays = 14
        let snapshot = WorkspaceSettingsSnapshot(
            triptychSettings: confirmed,
            settingsRevision: revision
        )
        let model = WorkspaceSettingsModel(
            snapshot: snapshot,
            loadSnapshot: { throw RefreshFailure() }
        )

        #expect(await model.refresh() == false)
        #expect(model.snapshot == snapshot)
        #expect(model.errorMessage == "fixture refresh failed")
    }

    @Test("Settings root and model cannot construct window-local owners")
    func sourceBoundary() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let modelURL = repositoryRoot.appendingPathComponent(
            "Scholium/Features/Settings/WorkspaceSettingsModel.swift"
        )
        let appURL = repositoryRoot.appendingPathComponent("Scholium/App/ScholiumApp.swift")
        let modelSource = try String(contentsOf: modelURL, encoding: .utf8)
        let appSource = try String(contentsOf: appURL, encoding: .utf8)
        let rootStart = try #require(appSource.range(of: "private struct ScholiumSettingsRoot"))
        let rootEnd = try #require(
            appSource.range(of: "struct ScholiumSearchActions", range: rootStart.upperBound..<appSource.endIndex)
        )
        let rootSource = String(appSource[rootStart.lowerBound..<rootEnd.lowerBound])

        let prohibitedConstructions = [
            "WindowModel(",
            "DocumentController(",
            "DocumentSessionStore(",
            "DocumentSessionModel(",
            "WindowSessionStore(",
            "WindowSessionSnapshotStore(",
        ]
        for construction in prohibitedConstructions {
            #expect(!modelSource.contains(construction))
            #expect(!rootSource.contains(construction))
        }
        #expect(rootSource.contains("capabilities: workspaceStore.settingsCapabilities()"))
        #expect(rootSource.contains("ScholiumSettingsView()"))
    }

    @Test("Settings descendants borrow only Settings state")
    func descendantsUseOnlySettingsOwners() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/WorkspaceSettingsView.swift"
            ),
            encoding: .utf8
        )
        #expect(!source.contains("@EnvironmentObject private var appState"))
        let declarations = source.components(separatedBy: "\n").filter {
            $0.contains("@EnvironmentObject")
        }
        #expect(!declarations.isEmpty)
        #expect(
            declarations.allSatisfy {
                $0.contains("WorkspaceSettingsModel")
            })
    }

    @Test("Appearance exposes basic controls and a reloadable advanced configuration file")
    func appearanceProfileSurface() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/WorkspaceSettingsView.swift"
            ),
            encoding: .utf8
        )
        let appearanceStart = try #require(
            source.range(of: "private struct AppearanceSettingsView: View")
        )
        let rowStart = try #require(
            source.range(
                of: "private struct CSSSnippetRow: View",
                range: appearanceStart.upperBound..<source.endIndex
            )
        )
        let appearanceSource = String(source[appearanceStart.lowerBound..<rowStart.lowerBound])

        #expect(appearanceSource.contains("store.createAppearance()"))
        #expect(appearanceSource.contains("store.duplicateAppearance"))
        #expect(appearanceSource.contains("store.renameAppearance"))
        #expect(appearanceSource.contains("store.removeAppearance"))
        #expect(appearanceSource.contains("AppearanceReadingEditor"))
        #expect(appearanceSource.contains("Picker(\"Body Font\", selection: $profile.settings.body.fontFamily)"))
        #expect(appearanceSource.contains("\"Line width\""))
        #expect(appearanceSource.contains("DocumentAppearanceSettings.lineWidthCharacterUnitsRange"))
        #expect(appearanceSource.contains("accessibilityUnit: \"character-width units\""))
        #expect(!appearanceSource.contains("Full width"))
        #expect(!appearanceSource.contains("Line width preset"))
        #expect(!appearanceSource.contains("Line width mode"))
        #expect(appearanceSource.contains("Picker(\"Source Font\", selection: $profile.settings.source.fontFamily)"))
        #expect(appearanceSource.contains("Picker(\"Heading Font\", selection: $profile.settings.headings.fontFamily)"))
        #expect(appearanceSource.contains("Section(\"Text Styles\")"))
        #expect(appearanceSource.contains(".scholiumSettingsFormStyle()"))
        #expect(appearanceSource.contains("roleFont(\"Body Bold Font\", selection: $profile.settings.body.cjkStrongFontFamily)"))
        #expect(appearanceSource.contains("roleFont(\"Body Italic Font\", selection: $profile.settings.body.cjkEmphasisFontFamily)"))
        #expect(appearanceSource.contains("roleFont(\"Heading Bold Font\", selection: $profile.settings.headings.cjkStrongFontFamily)"))
        #expect(appearanceSource.contains("roleFont(\"Heading Italic Font\", selection: $profile.settings.headings.cjkEmphasisFontFamily)"))
        #expect(!appearanceSource.contains("Semantic Typefaces"))
        #expect(!appearanceSource.contains("Strong (CJK)"))
        #expect(!appearanceSource.contains("Emphasis (CJK)"))
        #expect(appearanceSource.contains("cjkStrongFontFamily"))
        #expect(appearanceSource.contains("cjkEmphasisFontFamily"))
        #expect(!appearanceSource.contains("settingsEditorSection(\"Callout\")"))
        #expect(appearanceSource.contains("store.reloadAppearanceConfiguration()"))
        #expect(appearanceSource.contains("store.revealAppearanceConfiguration()"))
        #expect(!appearanceSource.contains("showsYAMLFrontmatter"))
        #expect(appearanceSource.contains("Section(\"Heading Hierarchy\")"))
        #expect(appearanceSource.contains("AppearanceHeadingLevelMatrix"))
        #expect(appearanceSource.contains("AppearanceHeadingLevelDetailRow"))
        #expect(!appearanceSource.contains("Edit Heading Levels…"))
        #expect(appearanceSource.contains("$headings.level3"))
        #expect(appearanceSource.contains("$headings.level6"))
        #expect(!appearanceSource.contains("H2–H6"))
        #expect(appearanceSource.contains("Picker(\"Heading Style\", selection: $profile.settings.headings.style)"))
        #expect(appearanceSource.contains("title: \"Heading Weight\", value: $profile.settings.headings.weight"))
        #expect(appearanceSource.contains("settingsEditorSection(\"Scale\")"))
        #expect(appearanceSource.contains("settingsEditorSection(\"Alignment\")"))
        #expect(appearanceSource.contains("\"Paragraph spacing\""))
        #expect(appearanceSource.contains("Section(\"CSS Snippets\")"))
        #expect(!appearanceSource.contains("CSS Snippets…"))
        #expect(appearanceSource.contains("Open CSS Folder"))
        #expect(appearanceSource.contains("store.reloadSnippets()"))
        #expect(!appearanceSource.contains("DocumentHyphenation"))
        #expect(!appearanceSource.contains("Use Kerning"))
        #expect(!appearanceSource.contains("Use Ligatures"))
        #expect(!appearanceSource.contains("Heading Letter Spacing"))
        #expect(!appearanceSource.contains("AppearanceSettingsSection"))
        #expect(appearanceSource.contains("TypographySettingsView"))
        #expect(appearanceSource.contains("scholium.settings.appearance"))
        #expect(!appearanceSource.contains("AdvancedTypographyScope"))
        #expect(!appearanceSource.contains("pickerStyle(.segmented)"))
        #expect(!appearanceSource.contains("AdvancedTypographySettingsView"))
        #expect(!appearanceSource.contains("showsAdvancedTypography"))
        #expect(!appearanceSource.contains("DisclosureGroup"))
        #expect(appearanceSource.contains("Button(\"Revert to Saved\")"))
        #expect(appearanceSource.contains("Restore Default Appearance…"))
        #expect(appearanceSource.contains("appearanceManagementMenu"))
        #expect(appearanceSource.contains("scholium.appearance.manage"))
        #expect(
            appearanceSource.contains(
                "Stepper(\"\", value: boundedValue"
            ))
        #expect(!appearanceSource.contains("AppearanceDoubleControl(\"Block spacing\""))
        #expect(!appearanceSource.contains("SafeMarkdownReadWebView"))
    }

    @Test("Settings keep peer details visible without decorative separators")
    func settingsAvoidDecorativeSeparatorsAndNestedPeerDisclosure() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        func read(_ path: String) throws -> String {
            try String(
                contentsOf: repositoryRoot.appendingPathComponent(path),
                encoding: .utf8
            )
        }

        let settingsSource = try read("Scholium/Views/WorkspaceSettingsView.swift")
        let settingsContentStart = try #require(
            settingsSource.range(of: "struct ScholiumSettingsView: View")
        )
        let settingsContentEnd = try #require(
            settingsSource.range(
                of: "struct ZoteroSettingsView",
                range: settingsContentStart.upperBound..<settingsSource.endIndex
            )
        )
        let settingsContent = String(
            settingsSource[settingsContentStart.lowerBound..<settingsContentEnd.lowerBound]
        )
        #expect(!settingsContent.contains("Divider()"))
        #expect(settingsContent.contains("ScholiumSettingsNavigationHost(title: destination.title, sidebar: sidebar, page: selectedPage)"))

        let interactionSource = try read(
            "Scholium/Views/SettingsTaskPages.swift"
        )
        #expect(!interactionSource.contains("Divider()"))

        for path in [
            "Scholium/Views/AgentChatConnectionSettingsView.swift",
            "Scholium/Views/AgentChatCapabilitiesSettingsView.swift",
            "Scholium/Views/AgentChatToolEditor.swift",
        ] {
            let source = try read(path)
            #expect(!source.contains("DisclosureGroup"))
        }

        let capabilities = try read("Scholium/Views/AgentChatCapabilitiesSettingsView.swift")
        #expect(capabilities.contains("Section(\"Skills\")"))
        #expect(capabilities.contains("Section(\"Core Protocol\")"))
        #expect(capabilities.contains("Always included in Scholium Chat"))
        #expect(capabilities.contains("Open Chat Workspace in Finder"))
        #expect(!capabilities.contains("Text(home.path)"))
        #expect(!capabilities.contains("Text(method.selection.path)"))
        #expect(!capabilities.contains("Text(configuration.address)"))
        #expect(!capabilities.contains(".help(path)"))
        #expect(!capabilities.contains(".help(coreProtocolURL.path)"))
        #expect(capabilities.contains("\"Connected Tools\""))
        #expect(!capabilities.contains(".sheet("))
        #expect(capabilities.contains("methodRow(method)"))
    }

    @Test("Selection Actions use an explicit native editing workflow and truthful preview")
    func selectionActionsSettingsSurface() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/SelectionActionsSettingsView.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("Table(state.actions"))
        #expect(source.contains("Button(\"Edit\")"))
        #expect(!source.contains(".sheet("))
        #expect(source.contains("Save Selection Actions"))
        #expect(source.contains("Cancel Action Changes"))
        #expect(source.contains("SelectionActionBarPreview"))
        #expect(source.contains("Shown when text is selected"))
        #expect(!source.contains(".formStyle(.grouped)"))
        #expect(source.contains("TextField("))
        #expect(source.contains("TextEditor(text:"))
        #expect(!source.contains("DisclosureGroup"))
    }

    @Test("Settings uses native sidebar navigation with stable window geometry")
    func settingsPresentationOwnership() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let componentSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/UI/Foundation/ScholiumSettingsPresentation.swift"
            ),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/WorkspaceSettingsView.swift"
            ),
            encoding: .utf8
        )
        let guidanceSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/SettingsTaskPages.swift"
            ),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let settingsRootSource =
            appSource
            .components(separatedBy: "private struct ScholiumSettingsRoot: View")
            .last?
            .components(separatedBy: "struct ScholiumSearchActions")
            .first ?? ""
        let settingsSceneSource =
            appSource
            .components(separatedBy: "\n        Settings {")
            .last?
            .components(separatedBy: "\n        #if DEBUG")
            .first ?? ""

        #expect(settingsSource.contains(".scholiumSettingsFormStyle()"))
        #expect(componentSource.contains("Color(nsColor: .windowBackgroundColor)"))
        #expect(!settingsSource.contains("NavigationSplitView"))
        #expect(!settingsSource.contains("HSplitView"))
        let navigationSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/UI/Foundation/ScholiumSettingsNavigationHost.swift"
            ),
            encoding: .utf8
        )
        #expect(!settingsSource.contains("SettingsWindowAttachment"))
        #expect(!settingsSource.contains("SettingsToolbarAttachment"))
        #expect(!settingsSource.contains(".navigationTitle("))
        #expect(navigationSource.contains("NSSplitViewController, NSToolbarDelegate"))
        #expect(navigationSource.contains("navigation.canCollapse = false"))
        #expect(navigationSource.contains("navigation.canCollapseFromWindowResize = false"))
        #expect(navigationSource.contains("navigation.minimumThickness = ScholiumMetrics.Settings.navigationWidth"))
        #expect(navigationSource.contains("navigation.maximumThickness = ScholiumMetrics.Settings.navigationWidth"))
        #expect(navigationSource.contains("window.title = pageTitle"))
        #expect(navigationSource.contains("NSTrackingSeparatorToolbarItem(identifier: identifier, splitView: splitView, dividerIndex: 0)"))
        #expect(!navigationSource.contains("toggleSidebar"))
        #expect(!navigationSource.contains("window.animator().setFrame"))
        #expect(!settingsSource.contains("window.animator().setFrame"))
        #expect(!settingsSource.contains("ScholiumWindowTopOverlayHost("))
        #expect(settingsSource.contains("ScholiumSettingsSearchField("))
        #expect(!settingsSceneSource.contains(".frame(width: 700, height: 560"))
        #expect(guidanceSource.contains(".scholiumSettingsPaneSurface()"))
        #expect(settingsRootSource.contains("WindowColorSchemeChoice(rawValue: storedColorScheme)"))

    }

    @Test("Settings model retains only delivery-neutral capabilities")
    func noCompatibilityStoreDependencies() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Features/Settings/WorkspaceSettingsModel.swift"
            ),
            encoding: .utf8
        )
        for prohibited in [
            "SharedTriptychRuntime",
            "TriptychControlStore",
            "ResearchSkillTransactionCoordinator",
            "workspaceRegistry",
            "identityRegistry",
            "portableControlAccessRegistry",
        ] {
            #expect(!source.contains(prohibited))
        }
        #expect(source.contains("private let capabilities: WorkspaceSettingsCapabilities?"))
        #expect(!source.contains("WorkspaceHandle"))
        #expect(!source.contains("WorkspaceStore"))
        #expect(!source.contains("import ScholiumApplication"))

        let boundaryStart = try #require(
            source.range(
                of: "struct WorkspaceSettingsCapabilities {"
            ))
        let boundaryEnd = try #require(
            source.range(
                of: "/// Application-lifetime Settings boundary",
                range: boundaryStart.upperBound..<source.endIndex
            ))
        let boundary = String(source[boundaryStart.lowerBound..<boundaryEnd.lowerBound])
        #expect(boundary.contains("let workspace: WorkspaceSettingsWorkspaceCapabilities"))
        #expect(boundary.contains("let machine: WorkspaceSettingsMachineCapabilities"))
        #expect(boundary.contains("let zotero: WorkspaceSettingsZoteroCapabilities"))
        #expect(
            boundary.components(separatedBy: "\n").filter {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("let ")
            }.count == 3)
    }

    @Test("Concurrent Settings restoration does not drop the visible Triptychs refresh")
    func concurrentRestorationKeepsLatestSnapshot() async {
        let entered = SettingsTestSignal()
        let releaseFirstLoad = SettingsTestSignal()
        let assignment = makeAssignment(name: "Restored Triptych")
        let restored = WorkspaceSettingsSnapshot(
            registeredVaults: Array(assignment.vaults.values),
            registeredTriptychs: [assignment],
            activeTriptychID: assignment.id
        )
        var loadCount = 0
        let model = WorkspaceSettingsModel(loadSnapshot: {
            loadCount += 1
            let call = loadCount
            await entered.signal()
            if call == 1 {
                await releaseFirstLoad.wait()
                return WorkspaceSettingsSnapshot()
            }
            return restored
        })

        let rootRestoration = Task { @MainActor in
            await model.restorePreferredWorkspaceIfNeeded()
        }
        await entered.wait()

        let vaultsPresentation = Task { @MainActor in
            await model.refreshRegisteredVaults()
        }
        await entered.wait()
        await vaultsPresentation.value

        #expect(model.registeredTriptychs.map(\.id) == [assignment.id])
        #expect(model.workspaceAssignment?.id == assignment.id)

        await releaseFirstLoad.signal()
        await rootRestoration.value

        #expect(model.registeredTriptychs.map(\.id) == [assignment.id])
        #expect(model.workspaceAssignment?.id == assignment.id)
        #expect(!model.isRefreshing)
    }

    @Test("A live activation remains usable while the broader Settings snapshot fails")
    func activationHintSurvivesSnapshotFailure() async {
        struct FixtureError: Error {}
        let activeID = UUID()
        let model = WorkspaceSettingsModel(loadSnapshot: {
            throw FixtureError()
        })

        await model.restorePreferredWorkspaceIfNeeded(activeTriptychID: activeID)

        #expect(model.activeTriptychServicesID == activeID)
        #expect(model.snapshot.activeTriptychID == activeID)
        #expect(model.errorMessage != nil)
    }

    @Test("Explicit Triptych activation supersedes an older Settings refresh")
    func activationSupersedesInFlightRefresh() async {
        let refreshEntered = SettingsTestSignal()
        let releaseRefresh = SettingsTestSignal()
        let first = makeAssignment(name: "First Triptych")
        let second = makeAssignment(name: "Second Triptych")
        let initial = WorkspaceSettingsSnapshot(
            registeredVaults: Array(first.vaults.values) + Array(second.vaults.values),
            registeredTriptychs: [first, second],
            activeTriptychID: first.id
        )
        let selected = WorkspaceSettingsSnapshot(
            registeredVaults: initial.registeredVaults,
            registeredTriptychs: initial.registeredTriptychs,
            activeTriptychID: second.id
        )
        let model = WorkspaceSettingsModel(
            snapshot: initial,
            loadSnapshot: {
                await refreshEntered.signal()
                await releaseRefresh.wait()
                return initial
            },
            activateTriptych: { id in
                #expect(id == second.id)
                return selected
            }
        )

        let staleRefresh = Task { @MainActor in await model.refresh() }
        await refreshEntered.wait()
        await model.activateRegisteredTriptych(id: second.id)

        #expect(model.workspaceAssignment?.id == second.id)

        await releaseRefresh.signal()
        _ = await staleRefresh.value

        #expect(model.workspaceAssignment?.id == second.id)
        #expect(!model.isRefreshing)
    }

    private func makeAssignment(name: String) -> TriptychAssignment {
        let analyses = RegisteredVault(
            name: "Analyses",
            role: .sourceCorpus,
            canonicalPath: "/tmp/\(name)/Analyses"
        )
        let topics = RegisteredVault(
            name: "Topics",
            role: .topicKnowledge,
            canonicalPath: "/tmp/\(name)/Topics"
        )
        let works = RegisteredVault(
            name: "Works",
            role: .draftProject,
            canonicalPath: "/tmp/\(name)/Works"
        )
        return TriptychAssignment(
            triptych: ScholiumTriptych(
                name: name,
                paperAnalysisVaultID: analyses.id,
                topicKnowledgeVaultID: topics.id,
                outputVaultID: works.id
            ),
            vaults: [
                .paperAnalysis: analyses,
                .topicKnowledge: topics,
                .output: works,
            ],
            hasCommonParent: true
        )
    }
}

private actor SettingsTestSignal {
    private var permits = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            permits += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
