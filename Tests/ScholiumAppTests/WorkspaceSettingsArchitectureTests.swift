import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Workspace Settings architecture")
@MainActor
struct WorkspaceSettingsArchitectureTests {
    @Test("Settings model has no window or document session state")
    func constructionIsWindowIndependent() async {
        let model = WorkspaceSettingsModel(selectedPane: .metadata)
        let storedTypeNames = Mirror(reflecting: model).children.map {
            String(reflecting: type(of: $0.value))
        }

        #expect(storedTypeNames.allSatisfy { !$0.contains("WindowModel") })
        #expect(storedTypeNames.allSatisfy { !$0.contains("DocumentController") })
        #expect(storedTypeNames.allSatisfy { !$0.contains("DocumentSession") })
        #expect(model.selectedPane == .metadata)
        #expect(model.snapshot.triptychSettings.metadataFields.values.allSatisfy { $0.isEmpty })
        #expect(!model.hasWritableTriptychSettings)

        model.replaceSnapshot(WorkspaceSettingsSnapshot(
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
                "metadata",
                "notifications",
                "interaction",
                "integrations",
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
            source.range(of: "private struct AttentionSettingsView")
        )
        let topLevel = String(source[..<topLevelEnd.lowerBound])

        #expect(topLevel.contains("SettingsToolbarAttachment(destination: $destination)"))
        #expect(topLevel.contains("window.toolbarStyle = .preference"))
        #expect(topLevel.contains("accessibilityDisplayShouldReduceMotion"))
        #expect(topLevel.contains("ScholiumSettingsDestination.workspace"))
        #expect(!topLevel.contains("SettingsTriptychScopePicker"))
        #expect(topLevel.contains("ScholiumSettingsSearchField(text: $searchQuery)"))
        #expect(topLevel.contains("destinationBeforeSearch"))
        #expect(!topLevel.contains("Text(\"Settings\")"))
        #expect(!topLevel.contains("ZoteroSettingsView()"))

        let orderedDestinations = [
            "case workspace",
            "case document",
            "case metadata",
            "case notifications",
            "case interaction",
            "case integrations",
        ]
        let indices = try orderedDestinations.map { destination in
            try #require(topLevel.range(of: destination)).lowerBound
        }
        #expect(zip(indices, indices.dropFirst()).allSatisfy { pair in
            pair.0 < pair.1
        })

        let interactionsAndIntegrations = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/SettingsInteractionAndIntegrationsView.swift"
            ),
            encoding: .utf8
        )
        #expect(
            interactionsAndIntegrations.contains("SettingsIntegrationsView")
        )
        #expect(interactionsAndIntegrations.contains("SettingsIntegrationCategory"))
        #expect(interactionsAndIntegrations.contains("ZoteroSettingsPageView"))
        #expect(!interactionsAndIntegrations.contains("ResearchGuidanceCategory"))
        #expect(
            interactionsAndIntegrations.components(
                separatedBy: "ZoteroSettingsView()"
            ).count == 2
        )
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
        #expect(source.contains("ScholiumL10n.Settings.metadata"))
        #expect(source.contains("ScholiumL10n.Settings.notifications"))
        #expect(source.contains("ScholiumL10n.Settings.interaction"))
        #expect(source.contains("ScholiumL10n.Settings.integrations"))
        #expect(!source.contains("SettingsScopeNotice"))
        #expect(!source.contains("Registration and folder access are local to this Mac"))
        #expect(!source.contains("Document content only"))
        #expect(!source.contains("These profiles change how Markdown is presented"))
        #expect(source.contains("This Triptych"))
        #expect(source.contains("This Mac"))
        #expect(source.contains("Reminder Timing"))
        #expect(source.contains("Dismissed Items on This Mac"))
        #expect(source.contains("Restore All Dismissed Items on This Mac"))
        #expect(source.contains("case integrations"))
        #expect(source.contains("settingsTriptychLabel("))
        #expect(source.contains(
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
        #expect(integration.contains("Show Core Protocol in Finder…"))
        #expect(integration.contains("External Agent Hosts"))
        #expect(integration.contains("ExternalAgentHostsSettingsView"))
        #expect(!integration.contains("detail: cliURL?.path"))
        #expect(!integration.contains("Not found at $HOME/.local/bin/scholium"))
        #expect(!integration.contains("ScrollView"))
        #expect(!integration.contains("DisclosureGroup(\"Connect an External Agent\""))

        let connection = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/AgentChatConnectionSettingsView.swift"
            ),
            encoding: .utf8
        )
        #expect(connection.contains("Advanced Connection Settings…"))
        #expect(connection.contains("Skills and Tools…"))
        #expect(connection.contains("External Agent Hosts…"))
        #expect(connection.contains("AgentChatCapabilitiesSettingsSheet"))
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
        model.replaceSnapshot(WorkspaceSettingsSnapshot(
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
        model.replaceSnapshot(WorkspaceSettingsSnapshot(
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
        model.replaceSnapshot(WorkspaceSettingsSnapshot(
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

    @Test("A normalized repair candidate is dirty and directly saveable")
    func repairableCandidateDiffersFromRawSettings() throws {
        let raw = Data(#"{"visibleFields":[" authors ","authors"]}"#.utf8)
        let decoded = try JSONDecoder().decode(
            VaultAboutConfiguration.self,
            from: raw
        )
        var saved = TriptychSettings()
        saved.about[.paperAnalysis] = decoded
        let candidate = MetadataSettingsCandidateBuilder.build(
            from: saved,
            metadataFields: saved.metadataFields,
            aboutConfigurations: saved.about
        )

        #expect(candidate != saved)
        #expect(candidate.about[.paperAnalysis]?.visibleFields == ["authors"])
        try TriptychSettingsValidator.validate(candidate)
    }

    @Test("Archiving a custom field prunes its About selection")
    func archivedFieldPrunesDiscoverySelections() throws {
        var saved = TriptychSettings()
        saved.metadataFields[.paperAnalysis] = [
            MetadataFieldDefinition(key: "argument_stage", valueKind: .text),
        ]
        saved.about[.paperAnalysis]?.visibleFields.append("argument_stage")
        var archivedFields = saved.metadataFields
        archivedFields[.paperAnalysis]?[0].lifecycle = .archived

        let candidate = MetadataSettingsCandidateBuilder.build(
            from: saved,
            metadataFields: archivedFields,
            aboutConfigurations: saved.about
        )

        #expect(candidate.metadataFields[.paperAnalysis]?[0].lifecycle == .archived)
        #expect(candidate.about[.paperAnalysis]?.visibleFields.contains(
            "argument_stage"
        ) == false)
        try TriptychSettingsValidator.validate(candidate)
        try TriptychSettingsValidator.validateTransition(from: saved, to: candidate)
    }

    @Test("Metadata Settings separates definitions and About always-shown order")
    func propertiesSettingsSurface() throws {
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
        let start = try #require(source.range(of: "private struct MetadataSettingsView"))
        let end = try #require(source.range(
            of: "struct WorkspaceSettingsView: View",
            range: start.upperBound..<source.endIndex
        ))
        let properties = String(source[start.lowerBound..<end.lowerBound])

        for section in [
            "Managed Fields",
            "settingsEditorSection(\"Always Shown in About\")",
        ] {
            #expect(properties.contains(section))
        }
        #expect(properties.contains("Archive Field"))
        #expect(properties.contains("Restore Field"))
        #expect(properties.contains("Used in "))
        #expect(properties.contains("moveField"))
        #expect(properties.contains("moveChoice"))
        #expect(properties.contains("Move Up"))
        #expect(properties.contains("Move Down"))
        #expect(properties.contains("description: normalizedOptionalText"))
        #expect(properties.contains("allowedValues:"))
        #expect(!properties.contains("Agent-Created Analyses"))
        #expect(properties.contains("Restore Always-Shown Defaults"))
        #expect(!properties.contains("Structured Editing"))
        #expect(!properties.contains("editableFields"))
        #expect(!properties.contains("YAML Added to New Notes"))
        #expect(!properties.contains("Clear New Note YAML"))
        #expect(properties.contains("TriptychSettingsValidator.validate(candidateSettings)"))
        #expect(properties.contains("settingsRevisionConflict"))
        #expect(properties.contains("hasWritableTriptychSettings"))
        #expect(properties.contains("Retry Metadata Settings"))
        #expect(properties.contains("savedSettingsRevision"))
        #expect(!properties.contains("currentAgentDiagnostic"))
        #expect(properties.contains("ViewThatFits(in: .horizontal)"))
        #expect(properties.contains(".disabled(isSaving)"))
        #expect(properties.contains("candidateSettings != savedTriptychSettings"))
        #expect(properties.contains("savedTriptychID"))
        #expect(!properties.contains("TextEditor(text: selectedSeed"))
        #expect(!properties.contains("reason: error.localizedDescription"))
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
        #expect(declarations.allSatisfy {
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
        #expect(appearanceSource.contains("AppearanceProfileEditor"))
        #expect(appearanceSource.contains("settingsEditorSection(\"Body Font\")"))
        #expect(appearanceSource.contains("\"Line width\""))
        #expect(appearanceSource.contains("DocumentAppearanceSettings.lineWidthCharacterUnitsRange"))
        #expect(appearanceSource.contains("accessibilityUnit: \"character-width units\""))
        #expect(!appearanceSource.contains("Full width"))
        #expect(!appearanceSource.contains("Line width preset"))
        #expect(!appearanceSource.contains("Line width mode"))
        #expect(appearanceSource.contains("settingsEditorSection(\"Source Font\")"))
        #expect(appearanceSource.contains("settingsEditorSection(\"Heading Font\")"))
        #expect(!appearanceSource.contains("settingsEditorSection(\"Callout\")"))
        #expect(appearanceSource.contains("store.reloadAppearanceConfiguration()"))
        #expect(appearanceSource.contains("store.revealAppearanceConfiguration()"))
        #expect(!appearanceSource.contains("showsYAMLFrontmatter"))
        #expect(appearanceSource.contains("settingsSectionTitle(\"Headings\")"))
        #expect(appearanceSource.contains("settingsEditorSection(\"Heading Style\")"))
        #expect(appearanceSource.contains("settingsEditorSection(\"Heading Weight\")"))
        #expect(appearanceSource.contains("Text(\"Scale\")"))
        #expect(appearanceSource.contains("Text(\"Alignment\")"))
        #expect(appearanceSource.contains("\"Paragraph spacing\""))
        #expect(appearanceSource.contains("AdvancedTypographySettingsView"))
        #expect(appearanceSource.contains("Advanced Typography"))
        #expect(appearanceSource.contains("showsAdvancedTypography"))
        #expect(!appearanceSource.contains("DisclosureGroup"))
        #expect(appearanceSource.contains("Button(\"Revert to Saved\")"))
        #expect(appearanceSource.contains("Restore Default Appearance…"))
        #expect(appearanceSource.contains("appearanceManagementMenu"))
        #expect(appearanceSource.contains("scholium.appearance.manage"))
        #expect(appearanceSource.contains(
            "Stepper(\"\", value: boundedValue"
        ))
        #expect(!appearanceSource.contains("AppearanceDoubleControl(\"Block spacing\""))
        #expect(!appearanceSource.contains("SafeMarkdownReadWebView"))
    }

    @Test("Settings use whitespace for groups and keep peer details visible")
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
            settingsSource.range(of: "private var settingsContent")
        )
        let toolbarAttachmentStart = try #require(
            settingsSource.range(
                of: "private struct SettingsToolbarAttachment",
                range: settingsContentStart.upperBound..<settingsSource.endIndex
            )
        )
        let settingsContent = String(
            settingsSource[settingsContentStart.lowerBound..<toolbarAttachmentStart.lowerBound]
        )
        #expect(!settingsContent.contains("Divider()"))

        let interactionSource = try read(
            "Scholium/Views/SettingsInteractionAndIntegrationsView.swift"
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
        #expect(capabilities.contains("settingsEditorSection(\"Skills\")"))
        #expect(capabilities.contains("settingsEditorSection(\"Core Protocol\")"))
        #expect(capabilities.contains("Always included in Scholium Chat"))
        #expect(capabilities.contains("skillFolderName"))
        #expect(!capabilities.contains("Text(home.path)"))
        #expect(!capabilities.contains("Text(method.selection.path)"))
        #expect(!capabilities.contains("Text(configuration.address)"))
        #expect(!capabilities.contains(".help(path)"))
        #expect(!capabilities.contains(".help(coreProtocolURL.path)"))
        #expect(capabilities.contains("settingsEditorSection(\"Connected Tools\")"))
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

        #expect(source.contains("Table(draft"))
        #expect(source.contains("Edit…"))
        #expect(source.contains("SelectionActionEditorSheet"))
        #expect(source.contains(".sheet(item: $editingAction)"))
        #expect(source.contains("SelectionActionBarPreview"))
        #expect(source.contains("Shown when text is selected"))
        #expect(!source.contains(".formStyle(.grouped)"))
        #expect(source.contains("TextField("))
        #expect(source.contains("TextEditor(text:"))
        #expect(!source.contains("DisclosureGroup"))
    }

    @Test("Settings uses native preferences chrome and adaptive window geometry")
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
                "Scholium/Views/SettingsInteractionAndIntegrationsView.swift"
            ),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let settingsRootSource = appSource
            .components(separatedBy: "private struct ScholiumSettingsRoot: View")
            .last?
            .components(separatedBy: "struct ScholiumSearchActions")
            .first ?? ""
        let settingsSceneSource = appSource
            .components(separatedBy: "\n        Settings {")
            .last?
            .components(separatedBy: "\n        #if DEBUG")
            .first ?? ""

        #expect(componentSource.contains(".formStyle(.columns)"))
        #expect(componentSource.contains("Color(nsColor: .windowBackgroundColor)"))
        #expect(settingsSource.contains("window.toolbarStyle = .preference"))
        #expect(settingsSource.contains("toolbar.selectedItemIdentifier"))
        #expect(settingsSource.contains("accessibilityDisplayShouldReduceMotion"))
        #expect(settingsSource.contains("window.animator().setFrame(frame, display: true)"))
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

        let boundaryStart = try #require(source.range(
            of: "struct WorkspaceSettingsCapabilities {"
        ))
        let boundaryEnd = try #require(source.range(
            of: "/// Application-lifetime Settings boundary",
            range: boundaryStart.upperBound..<source.endIndex
        ))
        let boundary = String(source[boundaryStart.lowerBound..<boundaryEnd.lowerBound])
        #expect(boundary.contains("let workspace: WorkspaceSettingsWorkspaceCapabilities"))
        #expect(boundary.contains("let machine: WorkspaceSettingsMachineCapabilities"))
        #expect(boundary.contains("let zotero: WorkspaceSettingsZoteroCapabilities"))
        #expect(boundary.components(separatedBy: "\n").filter {
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
