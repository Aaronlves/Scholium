import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Workspace Settings architecture")
@MainActor
struct WorkspaceSettingsArchitectureTests {
    @Test("Settings model has no window or document session state")
    func constructionIsWindowIndependent() async {
        let model = WorkspaceSettingsModel(selectedPane: .properties)
        let storedTypeNames = Mirror(reflecting: model).children.map {
            String(reflecting: type(of: $0.value))
        }

        #expect(storedTypeNames.allSatisfy { !$0.contains("WindowModel") })
        #expect(storedTypeNames.allSatisfy { !$0.contains("DocumentController") })
        #expect(storedTypeNames.allSatisfy { !$0.contains("DocumentSession") })
        #expect(model.selectedPane == .properties)
        #expect(model.snapshot.propertyKeysBySlot.isEmpty)
    }

    @Test("Settings success feedback replaces stale messages and dismisses by identity")
    func settingsSuccessFeedback() {
        let model = WorkspaceSettingsModel()

        model.showToast("First")
        #expect(model.toastMessage == "First")

        model.showToast("Second")
        model.dismissToast("First")
        #expect(model.toastMessage == "Second")

        model.dismissToast("Second")
        #expect(model.toastMessage == nil)
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

    @Test("Settings descendants have one environment boundary")
    func descendantsUseOnlyWorkspaceSettingsModel() throws {
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
        #expect(declarations.allSatisfy { $0.contains("WorkspaceSettingsModel") })
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
        #expect(appearanceSource.contains("Section(\"Layout\")"))
        #expect(appearanceSource.contains("\"Line width\""))
        #expect(appearanceSource.contains("DocumentAppearanceSettings.lineWidthCharacterUnitsRange"))
        #expect(appearanceSource.contains("accessibilityUnit: \"character-width units\""))
        #expect(!appearanceSource.contains("Full width"))
        #expect(!appearanceSource.contains("Line width preset"))
        #expect(!appearanceSource.contains("Line width mode"))
        #expect(appearanceSource.contains("Section(\"Body\")"))
        #expect(appearanceSource.contains("Section(\"Headings\")"))
        #expect(appearanceSource.contains("Section(\"Callouts\")"))
        #expect(appearanceSource.contains("Section(\"Advanced CSS\")"))
        #expect(!appearanceSource.contains("SafeMarkdownReadWebView"))
    }

    @Test("Production Research Guidance is one categorized list-detail surface")
    func researchGuidanceUsesFrozenCategories() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ResearchGuidanceSettingsView.swift"
            ),
            encoding: .utf8
        )

        #expect(!source.contains("NavigationSplitView {"))
        #expect(source.contains("HSplitView"))
        for category in [
            "Methods",
            "Researcher Skills",
            "Permissions",
            "Sources & Integrations",
            "Recovery & Technical",
        ] {
            #expect(source.contains(category))
        }
        #expect(source.contains("scholium.researchGuidance.categoryList"))
        #expect(!source.contains("Prompt Templates"))
        #expect(!source.contains("card grid"))
    }

    @Test("Production Skills Settings reaches bounded editing and installation")
    func researchGuidanceOwnsCurrentSkillConfiguration() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ResearchGuidanceSettingsView.swift"
            ),
            encoding: .utf8
        )
        let settingsRootSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/WorkspaceSettingsView.swift"
            ),
            encoding: .utf8
        )
        #expect(source.contains("Edit Method"))
        #expect(source.contains("Compare with Bundled Reference"))
        #expect(source.contains("Restore Bundled Reference"))
        #expect(source.contains("Enable as Work Action"))
        #expect(source.contains("Install from Local Directory…"))
        #expect(source.contains("NSOpenPanel()"))
        #expect(source.contains("allowedContentTypes = [.folder]"))
        #expect(source.contains("Install Disabled"))
        #expect(source.contains("Discard Unsaved Changes"))
        #expect(source.contains("Add Declarative Module"))
        #expect(source.contains("NONEXECUTING ACTION SHEET PREVIEW"))
        #expect(source.contains("Save Copy to Triptychs"))
        #expect(source.contains("Move Earlier"))
        #expect(source.contains("Move Later"))
        #expect(source.contains("canMoveProfile"))
        #expect(source.contains("globallyConfigured"))
        #expect(source.contains("Delete Action Profile?"))
        #expect(source.contains("ResearchGuidanceDraftStore"))
        #expect(source.contains("ResearcherSkillDraftKey"))
        #expect(source.contains("ResearchActionProfileDraftKey"))
        #expect(
            source.components(separatedBy: "try Task.checkCancellation()").count - 1
                == 4
        )
        #expect(
            source.components(
                separatedBy: "settingsModel.activeTriptychServicesID == requestedTriptychID"
            ).count - 1 == 13
        )
        #expect(
            source.components(
                separatedBy: ".disabled(loadedTriptychID != settingsModel.activeTriptychServicesID)"
            ).count - 1 == 3
        )
        #expect(
            source.components(separatedBy: "newSkillDraft = nil").count - 1 == 2
        )
        #expect(settingsRootSource.contains(
            "@StateObject private var researchGuidanceDraftStore"
        ))
        #expect(settingsRootSource.contains(
            "ResearchGuidanceSettingsView(draftStore: researchGuidanceDraftStore)"
        ))
        #expect(source.contains("draftStore.hasUnsavedChanges"))
        #expect(source.contains(
            "actionID == .manuscript && binding.state == .researcherSkill"
        ))
        #expect(source.contains("Reveal Skills Folder"))
        #expect(source.contains("Reveal Legacy Data"))
        #expect(source.contains("AgentCLISettingsView()"))
        #expect(source.contains("ResearchCitationMethodSettingsView"))
        #expect(source.contains("RecommendedBibliographyMethodSettingsView()"))
        #expect(source.contains("ResearchPermissionSettingsView()"))
        #expect(source.contains("saveTriptychPermissionPolicy"))
        #expect(source.contains("saveSkillPermissionOverride"))
        #expect(source.contains("removeSkillPermissionOverride"))
        #expect(source.contains("Needs Renewal"))
        #expect(source.contains("do not monitor external agents or network activity"))
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
            "Agent changes will ask for permission every time. You can change this later for each Triptych or Skill in Research Guidance Settings."
        ))
        #expect(source.contains("scholium.guidedSetup.permissionDefault"))
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
            "ResearchSkillStore",
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
            of: "extension ResearchSkillMaintenancePreparation",
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

    @Test("Skill summary uses exact ownership and actual binding status")
    func skillSummaryPresentation() {
        let builtIn = makeSkill(
            id: "scholium-analyze",
            origin: .bundled,
            skillClass: .method,
            updatePolicy: "release-managed-duplicable",
            supportedFunctions: [.develop]
        )
        let triptych = makeSkill(
            id: "researcher-development",
            origin: .triptych,
            skillClass: .researcher,
            supportedFunctions: [.develop]
        )
        let manuscript = makeSkill(
            id: "scholium-manuscript",
            origin: .bundled,
            skillClass: .method,
            updatePolicy: "release-managed-duplicable",
            supportedFunctions: [.manuscript]
        )
        let defaultStatus = ResearchFunctionSkillBindingStatus(
            function: .develop,
            candidates: [],
            selection: ResearchFunctionSkillSelection(function: .develop),
            bindingRevision: nil,
            issue: nil
        )

        #expect(ResearchGuidancePresentation.ownershipLabel(for: builtIn) == "Built-in")
        #expect(ResearchGuidancePresentation.ownershipLabel(for: triptych) == "Triptych")
        #expect(ResearchGuidancePresentation.statusLabel(
            for: builtIn,
            allSkills: [builtIn, triptych],
            methodStatuses: [.develop: defaultStatus],
            citationStatus: nil,
            loadState: .loaded
        ) == "Active — Develop")
        #expect(ResearchGuidancePresentation.statusLabel(
            for: triptych,
            allSkills: [builtIn, triptych],
            methodStatuses: [.develop: defaultStatus],
            citationStatus: nil,
            loadState: .loaded
        ) == "Not active")
        let manuscriptStatus = ResearchFunctionSkillBindingStatus(
            function: .manuscript,
            candidates: [],
            selection: ResearchFunctionSkillSelection(function: .manuscript),
            bindingRevision: nil,
            issue: nil
        )
        #expect(ResearchGuidancePresentation.statusLabel(
            for: manuscript,
            allSkills: [manuscript],
            methodStatuses: [.manuscript: manuscriptStatus],
            citationStatus: nil,
            loadState: .loaded
        ) == "Not active")

        let boundStatus = ResearchFunctionSkillBindingStatus(
            function: .develop,
            candidates: [],
            selection: ResearchFunctionSkillSelection(
                function: .develop,
                primaryPackageID: triptych.id
            ),
            bindingRevision: nil,
            issue: nil
        )
        #expect(ResearchGuidancePresentation.statusLabel(
            for: triptych,
            allSkills: [builtIn, triptych],
            methodStatuses: [.develop: boundStatus],
            citationStatus: nil,
            loadState: .loaded
        ) == "Bound — Primary for Develop")
    }

    @Test("Missing and malformed guidance route to exact Advanced repair destinations")
    func repairDestinations() {
        let methodStatus = ResearchFunctionSkillBindingStatus(
            function: .revise,
            candidates: [],
            selection: ResearchFunctionSkillSelection(function: .revise),
            bindingRevision: nil,
            issue: ResearchFunctionSkillBindingIssue(code: .malformedBinding)
        )
        let citationStatus = ResearchCitationMethodStatus(
            bundledTemplateAvailable: true,
            candidates: [],
            activePackageID: nil,
            bindingRevision: nil,
            issue: ResearchCitationMethodIssue(code: .missing)
        )

        let prompts = ResearchGuidancePresentation.repairPrompts(
            methodStatuses: [.revise: methodStatus],
            citationStatus: citationStatus
        )
        #expect(prompts.map(\.destination) == [
            .citationMethod,
            .researchMethod(.revise),
        ])
        #expect(prompts.allSatisfy { $0.destination.anchorID.hasPrefix(
            "scholium.researchGuidance.advanced."
        ) })
    }

    @Test("Ownership labels do not weaken System and Method duplication rules")
    func duplicationRulesRemainClassSpecific() {
        let system = makeSkill(
            id: "scholium-core-protocol",
            origin: .bundled,
            skillClass: .system,
            updatePolicy: "release-managed-protected"
        )
        let method = makeSkill(
            id: "scholium-write",
            origin: .bundled,
            skillClass: .method,
            updatePolicy: "release-managed-duplicable",
            supportedFunctions: [.revise]
        )

        #expect(ResearchGuidancePresentation.ownershipLabel(for: system) == "Built-in")
        #expect(ResearchGuidancePresentation.ownershipLabel(for: method) == "Built-in")
        #expect(!system.canDuplicate)
        #expect(method.canDuplicate)
    }

    @Test("Concurrent Settings restoration does not drop the visible Vaults refresh")
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

    private func makeSkill(
        id: String,
        origin: ResearchSkillOrigin,
        skillClass: ResearchSkillClass,
        updatePolicy: String = "researcher-owned",
        supportedFunctions: [ResearchFunctionID] = []
    ) -> ResearchSkillPackage {
        ResearchSkillPackage(
            id: id,
            name: id,
            description: "Purpose",
            source: "---\nname: \(id)\ndescription: Purpose\n---\nInstructions.",
            origin: origin,
            skillClass: skillClass,
            updatePolicy: updatePolicy,
            supportedFunctions: supportedFunctions
        )
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
