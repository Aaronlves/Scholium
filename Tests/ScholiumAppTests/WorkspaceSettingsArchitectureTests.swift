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
                "triptychs",
                "metadata",
                "appearance",
                "hotkeys",
                "attention",
                "research-guidance",
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

        #expect(!topLevel.contains("TabView("))
        #expect(topLevel.contains("NavigationSplitView {"))
        #expect(topLevel.contains(
            ".navigationSplitViewColumnWidth("
        ))
        #expect(topLevel.contains("ScholiumSettingsDestination.application"))
        #expect(topLevel.contains("ScholiumSettingsDestination.triptych"))
        #expect(topLevel.contains("ScholiumSettingsDestination.researchGuidance"))
        #expect(!topLevel.contains("SettingsTriptychScopePicker"))
        #expect(topLevel.contains("ScholiumSettingsSearchField(text: $searchQuery)"))
        #expect(!topLevel.contains("Text(\"Settings\")"))
        #expect(!topLevel.contains("ZoteroSettingsView()"))

        let windowManagement = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWindowManagement.swift"
            ),
            encoding: .utf8
        )
        let settingsAttachmentStart = try #require(
            windowManagement.range(of: "struct SettingsWindowAttachment")
        )
        let bootstrapAttachmentStart = try #require(
            windowManagement.range(
                of: "struct BootstrapWindowAttachment",
                range: settingsAttachmentStart.upperBound..<windowManagement.endIndex
            )
        )
        let settingsAttachment = windowManagement[
            settingsAttachmentStart.lowerBound..<bootstrapAttachmentStart.lowerBound
        ]
        #expect(settingsAttachment.contains(
            "window.styleMask.insert(.fullSizeContentView)"
        ))

        let orderedDestinations = [
            "case triptychs",
            "case appearance",
            "case hotkeys",
            "case metadata",
            "case attention",
            "case skills",
            "case actionProfiles",
            "case externalToolsCitations",
        ]
        let indices = try orderedDestinations.map { destination in
            try #require(topLevel.range(of: destination)).lowerBound
        }
        #expect(zip(indices, indices.dropFirst()).allSatisfy { pair in
            pair.0 < pair.1
        })

        let sourcesAndIntegrations = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ResearchSourcesSettingsView.swift"
            ),
            encoding: .utf8
        )
        #expect(
            sourcesAndIntegrations.components(
                separatedBy: "ZoteroSettingsView()"
            ).count == 2
        )
    }

    @Test("Settings makes Triptych and machine-local scope explicit")
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
        #expect(source.contains("Section(\"Application\")"))
        #expect(source.contains("Section(\"This Triptych\")"))
        #expect(source.contains("scholium.settings.triptychScope"))
        let triptychsStart = try #require(
            source.range(of: "struct WorkspaceSettingsView: View")
        )
        let appearanceStart = try #require(
            source.range(
                of: "private struct AppearanceSettingsView: View",
                range: triptychsStart.upperBound..<source.endIndex
            )
        )
        let triptychsSource = source[
            triptychsStart.lowerBound..<appearanceStart.lowerBound
        ]
        #expect(triptychsSource.contains("scholium.settings.triptychScope"))
        #expect(source.contains("ScholiumL10n.Settings.triptychs"))
        #expect(source.contains("ScholiumL10n.Settings.metadata"))
        #expect(source.contains("ScholiumL10n.Settings.appearance"))
        #expect(source.contains("ScholiumL10n.Settings.attention"))
        #expect(source.contains("Reminder Timing for This Triptych"))
        #expect(source.contains("Dismissed Items on This Mac"))
        #expect(source.contains("Restore All Dismissed Items on This Mac"))
        #expect(source.contains("SCHOLIUM CLI ON THIS MAC"))
        #expect(source.contains("READ-ONLY ZOTERO ON THIS MAC"))
        #expect(source.contains("TRIPTYCH CITATION STYLE"))
        #expect(source.contains("settingsTriptychLabel("))
        #expect(source.contains(
            ".onChange(of: settingsModel.snapshot.activeTriptychID)"
        ))

        let machineIntegrationStart = try #require(
            source.range(of: "struct AgentCLISettingsView: View")
        )
        let triptychListStart = try #require(
            source.range(
                of: "struct WorkspaceSettingsView: View",
                range: machineIntegrationStart.upperBound..<source.endIndex
            )
        )
        let machineIntegrationSource = source[
            machineIntegrationStart.lowerBound..<triptychListStart.lowerBound
        ]
        #expect(!machineIntegrationSource.contains("GroupBox"))
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
            aboutConfigurations: saved.about,
            agentCreation: saved.analysisAgentCreation
        )

        #expect(candidate != saved)
        #expect(candidate.about[.paperAnalysis]?.visibleFields == ["authors"])
        try TriptychSettingsValidator.validate(candidate)
    }

    @Test("Archiving a custom field prunes only its About and Agent discovery selections")
    func archivedFieldPrunesDiscoverySelections() throws {
        var saved = TriptychSettings()
        saved.metadataFields[.paperAnalysis] = [
            MetadataFieldDefinition(key: "argument_stage", valueKind: .text),
        ]
        saved.about[.paperAnalysis]?.visibleFields.append("argument_stage")
        saved.analysisAgentCreation.preferredFieldsBySourceType[.journalArticle] = [
            "argument_stage",
        ]
        var archivedFields = saved.metadataFields
        archivedFields[.paperAnalysis]?[0].lifecycle = .archived

        let candidate = MetadataSettingsCandidateBuilder.build(
            from: saved,
            metadataFields: archivedFields,
            aboutConfigurations: saved.about,
            agentCreation: saved.analysisAgentCreation
        )

        #expect(candidate.metadataFields[.paperAnalysis]?[0].lifecycle == .archived)
        #expect(candidate.about[.paperAnalysis]?.visibleFields.contains(
            "argument_stage"
        ) == false)
        #expect(candidate.analysisAgentCreation.preferredFields(
            for: .journalArticle
        ).contains("argument_stage") == false)
        try TriptychSettingsValidator.validate(candidate)
        try TriptychSettingsValidator.validateTransition(from: saved, to: candidate)
    }

    @Test("Metadata Settings separates definitions, Agent preferences, and About order")
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
            of: "struct AgentCLISettingsView",
            range: start.upperBound..<source.endIndex
        ))
        let properties = String(source[start.lowerBound..<end.lowerBound])

        for section in ["Managed Fields", "Agent-Created Analyses", "settingsSectionTitle(\"About\")"] {
            #expect(properties.contains(section))
        }
        #expect(properties.contains("Every field is optional"))
        #expect(properties.contains("Archive Field"))
        #expect(properties.contains("Restore Field"))
        #expect(properties.contains("Used in "))
        #expect(properties.contains("description: normalizedOptionalText"))
        #expect(properties.contains("allowedValues:"))
        #expect(properties.contains("preferredFieldsBySourceType"))
        #expect(properties.contains("Restore About Defaults"))
        #expect(!properties.contains("Structured Editing"))
        #expect(!properties.contains("editableFields"))
        #expect(!properties.contains("YAML Added to New Notes"))
        #expect(!properties.contains("Clear New Note YAML"))
        #expect(properties.contains("TriptychSettingsValidator.validate(candidateSettings)"))
        #expect(properties.contains("settingsRevisionConflict"))
        #expect(properties.contains("hasWritableTriptychSettings"))
        #expect(properties.contains("Retry Metadata Settings"))
        #expect(properties.contains("savedSettingsRevision"))
        #expect(properties.contains("currentAgentDiagnostic"))
        #expect(properties.contains("ViewThatFits(in: .horizontal)"))
        #expect(properties.contains(".disabled(isSaving)"))
        #expect(properties.contains("candidateSettings != savedTriptychSettings"))
        #expect(properties.contains("savedTriptychID"))
        #expect(!properties.contains("TextEditor(text: selectedSeed"))
        #expect(!properties.contains("reason: error.localizedDescription"))
    }

    @Test("Metadata editor exposes chooser and deletion without YAML authority")
    func completePropertiesSurface() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/Metadata/MetadataEditorView.swift"
            ),
            encoding: .utf8
        )

        for action in [
            "Add a Field…",
            "Remove Field",
            "Undo Removal",
        ] {
            #expect(source.contains(action))
        }
        #expect(source.contains("PropertyChooserView"))
        #expect(source.contains("creatorListEditor"))
        #expect(source.contains("readOnlyFieldValue(for: field)"))
        #expect(source.contains("Text(\"Unsupported shape\")"))
        #expect(source.contains("ScholiumEditorialIconControl("))
        #expect(source.contains("systemImage: \"ellipsis\""))
        #expect(source.contains("isVisuallyRevealed: hoveredFieldKey == field.key"))
        #expect(source.contains("|| focusedFieldKey == field.key"))
        #expect(source.contains("@State private var hoveredFieldKey: String?"))
        #expect(source.contains(".scholiumHoverState { isHovering in"))
        #expect(source.contains(".accessibilityLabel(\"Field Actions\")"))
        #expect(!source.contains("Add YAML Properties…"))
        #expect(!source.contains("Keep Without YAML"))
        #expect(source.contains(".accessibilityValue(Text(verbatim: field.label))"))
        #expect(source.contains("ScholiumPropertyGroup("))
        #expect(source.contains("separatesFromPrevious: index > 0"))
        #expect(source.contains("ScholiumMetrics.Properties.fieldBlockSeparation"))
        #expect(!source.contains("Text(group.group.label)"))
        #expect(!source.contains("ScholiumMetrics.Properties.fieldVerticalInset"))
        #expect(!source.contains("configuredEditableFields"))
        #expect(source.contains(".help(propertyHelpText(for: field))"))
        #expect(source.contains("ScholiumTagCapsuleLabel("))
        #expect(source.contains("creatorRolePresentation(for: field.key)"))
        #expect(source.contains("creatorTextField(\"Family name\""))
        #expect(source.contains("creatorKindPicker(selection: binding.kind)"))
        #expect(source.contains(".labelsHidden()"))
        #expect(source.contains("PropertyPresentationCatalog.choiceDisplayName("))
        #expect(!source.contains("Text(value.capitalized)"))
        #expect(!source.contains("Text(\"Researcher Properties\")"))
        #expect(!source.contains("This value's source shape or the role allowlist does not permit a targeted edit."))

        let fieldHeaderStart = try #require(source.range(of: "private func fieldHeader("))
        let fieldHeaderRemainder = source[fieldHeaderStart.lowerBound...]
        let fieldHeaderEnd = try #require(
            fieldHeaderRemainder.range(of: "private func readOnlyFieldValue")
        )
        let fieldHeaderSource = fieldHeaderRemainder[..<fieldHeaderEnd.lowerBound]
        #expect(!fieldHeaderSource.contains("Text(field.key)"))
        let fieldEditorStart = try #require(source.range(of: "private func fieldEditor("))
        let fieldEditorRemainder = source[fieldEditorStart.lowerBound...]
        let fieldEditorEnd = try #require(
            fieldEditorRemainder.range(of: "private func fieldHeader(")
        )
        let fieldEditorSource = fieldEditorRemainder[..<fieldEditorEnd.lowerBound]
        #expect(!fieldEditorSource.contains("field.help"))
        #expect(!fieldEditorSource.contains("This property will be removed when Save succeeds."))
        #expect(!fieldEditorSource.contains("Not typical for"))
        #expect(source.contains("Text(\"Pending Removal\")"))
        #expect(source.contains("Text(\"Not typical\")"))
        #expect(source.components(separatedBy: ".buttonStyle(.borderedProminent)").count == 3)
        #expect(source.components(
            separatedBy: ".tint(ScholiumColorRole.accent.color)"
        ).count == 2)
        #expect(!source.contains(".tint(ScholiumColorRole.mutedText.color)"))
        #expect(source.contains("removedFieldKeys"))
        #expect(source.contains("List(selection: $selectionKey)"))
        #expect(!source.contains("onOpenSource"))
        #expect(!source.contains("Edit in Source"))
        #expect(!source.contains("YAML: "))
        #expect(source.contains("reloadCurrentNote()"))
        #expect(source.contains("displayedFieldErrors.isEmpty"))
        #expect(source.components(
            separatedBy: ".focused($focusedFieldKey, equals: field.key)"
        ).count >= 9)
        #expect(source.contains("measuredSizes(subviews, maximumWidth: bounds.width)"))
        #expect(source.contains(".disabled(isSaving)"))
        #expect(!source.contains("errors[key] = issue.message"))
        #expect(!source.contains("DatePicker("))
    }

    @Test("Settings feedback preserves distinct messages and dismisses by identity")
    func settingsFeedbackQueue() throws {
        let model = WorkspaceSettingsModel()

        model.presentFeedback("First", kind: .confirmation)
        let first = try #require(model.feedbackItems.first)
        #expect(first.message == "First")
        #expect(first.kind == .confirmation)
        #expect(first.kind.dismissesAutomatically)

        model.presentFeedback("Second", kind: .error)
        let second = try #require(model.feedbackItems.last)
        #expect(model.feedbackItems.map(\.message) == ["First", "Second"])
        #expect(second.kind == .error)
        #expect(!second.kind.dismissesAutomatically)

        model.dismissFeedback(id: first.id)
        #expect(model.feedbackItems == [second])

        model.dismissFeedback(id: second.id)
        #expect(model.feedbackItems.isEmpty)
    }

    @Test("Settings feedback deduplicates an identical live notice")
    func settingsFeedbackDeduplication() throws {
        let model = WorkspaceSettingsModel()

        model.presentFeedback("Saved", kind: .confirmation)
        let firstID = try #require(model.feedbackItems.first?.id)
        model.presentFeedback("Saved", kind: .confirmation)

        #expect(model.feedbackItems.count == 1)
        #expect(model.feedbackItems.first?.id != firstID)
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

    @Test("Settings descendants borrow only Settings state and app notification authorization")
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
                || $0.contains("ResearchResultNotificationCoordinator")
        })
    }

    @Test("Appearance owns named structured profiles without a generated CSS preview")
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
        #expect(appearanceSource.contains("settingsEditorSection(\"Layout\")"))
        #expect(appearanceSource.contains("\"Line width\""))
        #expect(appearanceSource.contains("DocumentAppearanceSettings.lineWidthCharacterUnitsRange"))
        #expect(appearanceSource.contains("accessibilityUnit: \"character-width units\""))
        #expect(!appearanceSource.contains("Full width"))
        #expect(!appearanceSource.contains("Line width preset"))
        #expect(!appearanceSource.contains("Line width mode"))
        #expect(appearanceSource.contains("settingsEditorSection(\"Body\")"))
        #expect(appearanceSource.contains("settingsEditorSection(\"Headings\")"))
        #expect(appearanceSource.contains("settingsEditorSection(\"Callouts\")"))
        #expect(appearanceSource.contains("DisclosureGroup(\"Advanced CSS\""))
        #expect(appearanceSource.contains("ScholiumDisclosureHeaderButton("))
        #expect(appearanceSource.contains("scholium.appearance.advanced"))
        #expect(appearanceSource.contains("showsAdvancedAppearance.toggle()"))
        #expect(appearanceSource.contains("Button(\"Revert to Saved\")"))
        #expect(appearanceSource.contains("Restore Default Appearance…"))
        #expect(appearanceSource.contains("appearanceManagementMenu"))
        #expect(appearanceSource.contains("scholium.appearance.manage"))
        #expect(appearanceSource.contains(
            "slider.trackFillColor = ScholiumColorRole.accent.nsColor"
        ))
        #expect(
            appearanceSource.components(
                separatedBy: "AppearanceDoubleControl(\"Block spacing\""
            ).count == 2
        )
        #expect(!appearanceSource.contains("SafeMarkdownReadWebView"))
    }

    @Test("Research Guidance shares the one Settings sidebar")
    func researchGuidanceUsesFrozenCategories() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let guidanceFiles = [
            "ResearchGuidanceSettingsView.swift",
            "ResearchMethodsSettingsView.swift",
            "ActionProfilesSettingsView.swift",
            "ResearchSourcesSettingsView.swift",
        ]
        let source = try guidanceFiles.map { fileName in
            try String(
                contentsOf: repositoryRoot.appendingPathComponent(
                    "Scholium/Views/\(fileName)"
                ),
                encoding: .utf8
            )
        }.joined(separator: "\n")
        let rootSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ResearchGuidanceSettingsView.swift"
            ),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/WorkspaceSettingsView.swift"
            ),
            encoding: .utf8
        )

        #expect(!source.contains("NavigationSplitView {"))
        #expect(!source.contains("HSplitView"))
        for category in [
            "Skills",
            "Action Profiles",
            "External Tools & Citations",
        ] {
            #expect(source.contains(category))
        }
        #expect(!source.contains("scholium.researchGuidance.categoryList"))
        #expect(settingsSource.contains("scholium.settings.sidebarList"))
        #expect(settingsSource.contains("ScholiumSettingsDestination.researchGuidance"))
        #expect(settingsSource.contains("ResearchGuidanceSettingsView(category: .skills)"))
        #expect(settingsSource.contains("ResearchGuidanceSettingsView(category: .externalToolsCitations)"))
        #expect(!source.contains("Prompt Templates"))
        #expect(!source.contains("card grid"))
        #expect(rootSource.contains("ResearchMethodsSettingsView()"))
        #expect(rootSource.contains("ActionProfilesSettingsView()"))
        #expect(!rootSource.contains("private struct WorkingMethodEditorContext"))
        #expect(!rootSource.contains("private struct ResearchActionProfileEditorView"))
    }

    @Test("Research Guidance collection rows share one presentation owner")
    func researchGuidanceCollectionRowOwnership() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let rootSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ResearchGuidanceSettingsView.swift"
            ),
            encoding: .utf8
        )
        let componentSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/UI/Foundation/ScholiumSettingsPresentation.swift"
            ),
            encoding: .utf8
        )
        let methodsSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ResearchMethodsSettingsView.swift"
            ),
            encoding: .utf8
        )
        let profilesSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ActionProfilesSettingsView.swift"
            ),
            encoding: .utf8
        )
        #expect(componentSource.contains("func researchSettingsCollectionRow<"))
        #expect(
            componentSource.contains(
                "ScholiumMetrics.ResearchGuidance.collectionRowColumnSpacing"
            )
        )
        #expect(
            componentSource.contains(
                "ScholiumMetrics.ResearchGuidance.collectionRowVerticalInset"
            )
        )
        #expect(rootSource.contains("let category: ResearchGuidanceCategory"))
        #expect(
            methodsSource.components(
                separatedBy: "researchSettingsCollectionRow {"
            ).count == 2
        )
        #expect(
            profilesSource.components(
                separatedBy: "researchSettingsCollectionRow {"
            ).count == 2
        )
        #expect(!methodsSource.contains("HStack(alignment: .top, spacing: 14)"))
        #expect(!profilesSource.contains("HStack(alignment: .top, spacing: 14)"))
        #expect(!methodsSource.contains(".padding(.vertical, 10)"))
        #expect(!profilesSource.contains(".padding(.vertical, 10)"))
        #expect(ScholiumMetrics.ResearchGuidance.collectionRowColumnSpacing == 14)
        #expect(ScholiumMetrics.ResearchGuidance.collectionRowVerticalInset == 10)
    }

    @Test("Settings shares one continuous editorial presentation over native controls")
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
                "Scholium/Views/ResearchGuidanceSettingsView.swift"
            ),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let windowManagementSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/UI/Components/ScholiumWindowManagement.swift"
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
        #expect(componentSource.contains(".scrollContentBackground(.hidden)"))
        #expect(componentSource.contains(
            "role: ScholiumColorRole = .surfaceBackground"
        ))
        #expect(componentSource.contains("func settingsSectionTitle("))
        #expect(componentSource.contains("func settingsEditorSection<"))
        #expect(settingsSource.components(
            separatedBy: ".scholiumSettingsForm()"
        ).count == 2)
        #expect(!settingsSource.contains(".formStyle(.grouped)"))
        #expect(!settingsSource.contains("GroupBox("))
        #expect(settingsSource.contains(
            ".scholiumSettingsPaneSurface(.navigationSurfaceBackground)"
        ))
        #expect(settingsSource.contains("NavigationSplitView {"))
        #expect(settingsSource.contains(".navigationSplitViewColumnWidth("))
        #expect(settingsSource.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(settingsSource.contains("ScholiumWindowTopOverlayHost("))
        #expect(!settingsSource.contains("geometry.safeAreaInsets.top"))
        #expect(!settingsSource.contains(".overlay(alignment: .leading)"))
        #expect(settingsSource.contains("ScholiumSettingsSearchField("))
        #expect(!componentSource.contains("struct ScholiumSettingsWindowBackground"))
        #expect(componentSource.contains("struct ScholiumSettingsSearchField"))
        #expect(settingsSceneSource.contains(
            ".frame(width: 700, height: 560, alignment: .topLeading)"
        ))
        #expect(settingsSceneSource.contains(
            ".windowToolbarStyle(.unified(showsTitle: false))"
        ))
        #expect(!settingsSceneSource.contains(".toolbarBackgroundVisibility("))
        #expect(!settingsSceneSource.contains(".containerBackground(for: .window)"))
        #expect(!settingsSceneSource.contains("ScholiumSettingsWindowBackground()"))
        #expect(settingsSceneSource.contains("SettingsWindowAttachment()"))
        #expect(windowManagementSource.contains("struct SettingsWindowAttachment"))
        #expect(windowManagementSource.contains("window.animationBehavior = .none"))
        #expect(windowManagementSource.contains(
            "window.backgroundColor = ScholiumColorRole.surfaceBackground.nsColor"
        ))
        #expect(!settingsSource.contains("TabView("))
        #expect(guidanceSource.contains(".scholiumSettingsPaneSurface()"))
        #expect(!settingsRootSource.isEmpty)
        #expect(settingsRootSource.contains(
            "@AppStorage(WindowColorSchemeChoice.defaultsKey)"
        ))
        #expect(settingsRootSource.contains(".tint(ScholiumColorRole.accent.color)"))
        #expect(settingsRootSource.contains(
            "WindowColorSchemeChoice(rawValue: storedColorScheme)"
        ))
        #expect(!settingsRootSource.contains(".frame(width: 700, height: 560"))
    }

    @Test("Skills has no in-App Markdown editing surface")
    func researchGuidanceHasNoMarkdownEditor() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let methodsSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ResearchMethodsSettingsView.swift"
            ),
            encoding: .utf8
        )
        #expect(!FileManager.default.fileExists(atPath: repositoryRoot
            .appendingPathComponent("Scholium/Views/ResearchGuidanceMarkdownSheet.swift")
            .path))
        for forbiddenEditor in [
            "ResearchGuidanceMarkdownEditSheet",
            "ResearchGuidanceMarkdownCreationSheet",
            "ResearchGuidanceMarkdownEditDraft",
            "ResearchGuidanceMarkdownCreationDraft",
            "Edit Primary Markdown",
            "Restore Scholium Default",
        ] {
            #expect(!methodsSource.contains(forbiddenEditor))
        }
        #expect(methodsSource.contains("Assign Skill Folder…"))
        #expect(methodsSource.contains("Show Skill Folder in Finder…"))
        #expect(methodsSource.contains("Scholium does not inspect or edit Skill contents"))
    }

    @Test("Research Guidance exposes the current owner surfaces without package semantics")
    func researchGuidanceOwnsCurrentSkillConfiguration() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try [
            "ResearchGuidanceSettingsView.swift",
            "ResearchMethodsSettingsView.swift",
            "ActionProfilesSettingsView.swift",
            "ResearchSourcesSettingsView.swift",
        ].map { fileName in
            try String(
                contentsOf: repositoryRoot.appendingPathComponent(
                    "Scholium/Views/\(fileName)"
                ),
                encoding: .utf8
            )
        }.joined(separator: "\n")
        let settingsRootSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/WorkspaceSettingsView.swift"
            ),
            encoding: .utf8
        )
        #expect(!source.contains("Edit Primary Markdown"))
        #expect(!source.contains("Restore Previous Edit"))
        #expect(!source.contains("Restore Scholium Default"))
        #expect(source.contains("Assign Skill Folder…"))
        #expect(source.contains("Show Skill Folder in Finder…"))
        #expect(source.contains("Skills"))
        #expect(source.contains("Action Profiles"))
        #expect(source.contains("does not inspect or edit Skill contents"))
        #expect(source.contains("Academic Inputs"))
        #expect(source.contains("Academic Results"))
        #expect(source.contains("Edit Academic Profile"))
        #expect(source.contains("Field Type"))
        #expect(source.contains("Single Choice"))
        #expect(source.contains("Multiple Choice"))
        #expect(source.contains("Not Included"))
        #expect(source.contains("saveAcademicActionProfiles"))
        #expect(source.contains("Assign one researcher-owned Skill folder to each Action"))
        #expect(!source.contains("ResearchGuidanceMarkdown"))
        #expect(!source.contains("ResearchGuidanceDraftStore"))
        #expect(!source.contains("ResearcherSkillDraftKey"))
        #expect(!source.contains("ResearchActionProfileDraftKey"))
        #expect(!source.contains("Install from Local Directory…"))
        #expect(!settingsRootSource.contains("researchGuidanceDraftStore"))
        #expect(settingsRootSource.contains("ResearchGuidanceSettingsView(category: .skills)"))
        #expect(settingsRootSource.contains("ResearchGuidanceSettingsView(category: .externalToolsCitations)"))
        #expect(source.contains("AgentCLISettingsView()"))
        #expect(source.contains("ResearchCitationMethodSettingsView"))
        #expect(!source.contains("ResearchPermissionSettingsView()"))
        #expect(!source.contains("saveCollaborationPolicy"))
        #expect(!source.contains("CONFIGURE MY AGENT"))
        #expect(!source.contains("agentConfigurationPrompt"))
        #expect(!source.contains("Copy Agent Configuration Prompt"))
        #expect(!source.contains("saveSkillPermissionOverride"))
        #expect(!source.contains("removeSkillPermissionOverride"))
        #expect(!source.contains("Choose when an Agent may extend a Run’s bounded write set"))
        for forbidden in [
            ".regularMaterial",
            ".ultraThinMaterial",
            "glassEffect(",
            "GroupBox(",
            " · ",
        ] {
            #expect(!source.contains(forbidden))
        }
    }

    @Test("Bootstrap states the quiet default and later customization route")
    func bootstrapExplainsStandingPermissionDefault() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/WorkspaceSetupView.swift"
            ),
            encoding: .utf8
        )
        #expect(source.contains(
            "Agent activity is attributed to its Run and recorded with exact document changes; relevant Notes do not require separate approval."
        ))
        #expect(source.contains("scholium.bootstrap.activityTracking"))
        #expect(!source.contains("Choose a permission policy"))
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
        #expect(boundary.contains("let researchGuidance: WorkspaceSettingsResearchGuidanceCapabilities"))
        #expect(boundary.components(separatedBy: "\n").filter {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("let ")
        }.count == 4)
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
        await staleRefresh.value

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
