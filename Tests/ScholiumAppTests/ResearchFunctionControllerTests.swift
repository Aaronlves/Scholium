import ScholiumContracts
import Foundation
import Testing
@testable import ScholiumApp

@Suite("Research Function controller")
@MainActor
struct ResearchFunctionControllerTests {
    @Test("Human Review draft survives a Properties handoff and advances revision")
    func humanReviewDraftHandoff() {
        let original = target(title: "Agency", path: "Topics/Agency.md")
        let persistedDraft = HumanReviewDraft(
            fingerprint: original.fingerprint,
            qualification: .qualified,
            reviewNote: "Persisted judgment"
        )
        let record = HumanReviewRecord(
            noteID: original.noteID,
            vaultID: original.note.vaultID,
            relativePath: original.note.relativePath,
            draft: persistedDraft
        )
        let presentationID = UUID()
        let controller = ResearchFunctionController()
        controller.begin(
            target: original,
            function: .review,
            selection: nil,
            presentationID: presentationID
        )
        controller.beginHumanReviewDraft(
            revision: original.fingerprint,
            record: record
        )

        #expect(controller.humanReviewRevision == original.fingerprint)
        #expect(controller.humanReviewQualification == .qualified)
        #expect(controller.humanReviewNote == "Persisted judgment")
        controller.humanReviewQualification = .unqualified
        controller.humanReviewNote = "Unsaved judgment retained across Properties"

        let updated = ResearchFunctionTarget(
            noteID: original.noteID,
            note: original.note,
            role: original.role,
            lifecycle: original.lifecycle,
            fingerprint: DocumentFingerprint(content: "# Agency\nresearch status declared\n"),
            title: original.title
        )
        controller.resumeHumanReviewDraft(
            presentationID: UUID(),
            target: updated
        )
        #expect(controller.humanReviewRevision == original.fingerprint)

        controller.resumeHumanReviewDraft(
            presentationID: presentationID,
            target: updated
        )
        #expect(controller.target == updated)
        #expect(controller.humanReviewRevision == updated.fingerprint)
        #expect(controller.humanReviewQualification == .unqualified)
        #expect(controller.humanReviewNote == "Unsaved judgment retained across Properties")

        controller.dismiss(presentationID: presentationID)
        #expect(controller.humanReviewRevision == nil)
        #expect(controller.humanReviewQualification == nil)
        #expect(controller.humanReviewNote.isEmpty)
    }

    @Test("Human Review never loads hidden agent Materials")
    func humanReviewSkipsMaterials() async {
        let controller = ResearchFunctionController()
        var materialCandidateCalls = 0
        controller.bind(client(materialCandidates: { _, _ in
            materialCandidateCalls += 1
            return []
        }))
        controller.begin(
            target: target(title: "Agency", path: "Topics/Agency.md"),
            function: .review,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { controller.phase == .editing }

        #expect(materialCandidateCalls == 0)
        #expect(controller.materialsState.phase == .empty)
        #expect(controller.materialCandidates.isEmpty)
    }

    @Test("A superseded asynchronous panel load cannot replace the current Target")
    func staleLoadIsRejected() async throws {
        let controller = ResearchFunctionController()
        let gate = LoadGate()
        controller.bind(client(beforeLoad: { target in
            await gate.wait(target.title)
        }))
        let first = target(title: "First", path: "Topics/First.md")
        let second = target(title: "Second", path: "Topics/Second.md")

        controller.begin(
            target: first,
            function: .dialogue,
            selection: nil,
            presentationID: UUID()
        )
        await gate.waitUntilArrived("First", count: 2)
        controller.begin(
            target: second,
            function: .develop,
            selection: nil,
            presentationID: UUID()
        )
        gate.release("First")
        await gate.waitUntilPassed("First", count: 2)
        await Task.yield()
        #expect(controller.target == second)
        #expect(controller.materialCandidates.isEmpty)

        gate.release("Second")
        await gate.waitUntilPassed("Second", count: 2)
        await waitUntil { controller.canPrepare }

        #expect(controller.target == second)
        #expect(controller.activeFunction == .develop)
        #expect(controller.phase == .editing)
        #expect(controller.materialCandidates.first?.material.title == "Material for Second")
    }

    @Test("Dialogue defaults become an explicit request-scoped module selection")
    func dialogueDefaultsAndRequestConstruction() async throws {
        let controller = ResearchFunctionController()
        var capturedRequest: ResearchFunctionRequest?
        controller.bind(client(
            dialogueResponseProfile: {
                DialogueResponseProfile(modules: [
                    .researchDirections,
                    .criticalReflection,
                ])
            },
            prepare: { request in
                capturedRequest = request
                return ResearchFunctionPreparation(
                    snapshot: ResearchFunctionSnapshot(
                        request: request,
                        recordKind: .dialogue
                    ),
                    instructions: "Prepared"
                )
            }
        ))
        controller.begin(
            target: target(title: "Agency", path: "Topics/Agency.md"),
            function: .dialogue,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil {
            controller.phase == .editing
                && controller.dialogueResponseDefaultsLoaded
                && controller.materialCandidates.count == 1
        }

        #expect(controller.dialogueResponseDefaultsLoaded)
        #expect(controller.dialogueResponseModules == [
            .criticalReflection,
            .researchDirections,
        ])
        controller.setDialogueResponseModule(.researchDirections, isSelected: false)
        controller.setDialogueResponseModule(.remainingQuestions, isSelected: true)
        controller.instruction = "Which distinction needs further development?"
        #expect(controller.canPrepare)
        controller.prepare()
        await waitUntil { capturedRequest != nil }

        #expect(capturedRequest?.dialogueResponseModules == [
            .criticalReflection,
            .remainingQuestions,
        ])
    }

    @Test("Dialogue permits an explicit Academic Outcome only request and resets it")
    func dialogueExplicitEmptyAndReset() async throws {
        let controller = ResearchFunctionController()
        var capturedRequest: ResearchFunctionRequest?
        controller.bind(client(
            dialogueResponseProfile: {
                DialogueResponseProfile(modules: [.remainingQuestions])
            },
            prepare: { request in
                capturedRequest = request
                return ResearchFunctionPreparation(
                    snapshot: ResearchFunctionSnapshot(
                        request: request,
                        recordKind: .dialogue
                    ),
                    instructions: "Prepared"
                )
            }
        ))
        controller.begin(
            target: target(title: "Agency", path: "Topics/Agency.md"),
            function: .dialogue,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil {
            controller.phase == .editing
                && controller.dialogueResponseDefaultsLoaded
                && controller.materialCandidates.count == 1
        }
        controller.setDialogueResponseModule(.remainingQuestions, isSelected: false)
        controller.instruction = "Give the bounded academic outcome."
        #expect(controller.canPrepare)
        controller.prepare()
        await waitUntil { capturedRequest != nil }

        #expect(capturedRequest?.dialogueResponseModules == [])
        controller.dismiss()
        #expect(controller.dialogueResponseModules.isEmpty)
        #expect(!controller.dialogueResponseDefaultsLoaded)
    }

    @Test("Dialogue default loading fails closed and exposes the error")
    func dialogueDefaultLoadingFailure() async {
        let controller = ResearchFunctionController()
        controller.bind(client(dialogueResponseProfile: {
            throw TestFailure.dialogueDefaultsUnavailable
        }))
        controller.begin(
            target: target(title: "Agency", path: "Topics/Agency.md"),
            function: .dialogue,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { controller.phase == .failed }

        #expect(!controller.dialogueResponseDefaultsLoaded)
        #expect(!controller.canPrepare)
        #expect(controller.errorMessage == TestFailure.dialogueDefaultsUnavailable.localizedDescription)
    }

    @Test("A superseded Dialogue-default response cannot replace a new function draft")
    func staleDialogueDefaultsAreRejected() async {
        let controller = ResearchFunctionController()
        let gate = LoadGate()
        controller.bind(client(dialogueResponseProfile: {
            await gate.wait("Dialogue profile")
            return DialogueResponseProfile(modules: [.researchDirections])
        }))
        controller.begin(
            target: target(title: "First", path: "Topics/First.md"),
            function: .dialogue,
            selection: nil,
            presentationID: UUID()
        )
        await gate.waitUntilArrived("Dialogue profile", count: 1)
        controller.begin(
            target: target(title: "Second", path: "Topics/Second.md"),
            function: .develop,
            selection: nil,
            presentationID: UUID()
        )
        gate.release("Dialogue profile")
        await waitUntil { controller.canPrepare }

        #expect(controller.activeFunction == .develop)
        #expect(controller.dialogueResponseModules.isEmpty)
        #expect(!controller.dialogueResponseDefaultsLoaded)
    }

    @Test("Target identity and revision remain locked for one presentation")
    func targetLocking() async throws {
        let controller = ResearchFunctionController()
        controller.bind(client())
        let original = target(title: "Agency", path: "Topics/Agency.md")
        let presentationID = UUID()
        controller.begin(
            target: original,
            function: .develop,
            selection: nil,
            presentationID: presentationID
        )

        controller.invalidateIfTargetChanged(original)
        #expect(controller.presentationID == presentationID)

        let changed = ResearchFunctionTarget(
            noteID: original.noteID,
            note: original.note,
            role: original.role,
            fingerprint: DocumentFingerprint(content: "changed"),
            title: original.title
        )
        controller.invalidateIfTargetChanged(changed)
        #expect(controller.presentationID == nil)
        #expect(controller.target == nil)
    }

    @Test("Function drafts are isolated per window controller")
    func perWindowIsolation() {
        let first = ResearchController()
        let second = ResearchController()
        let target = target(title: "Agency", path: "Topics/Agency.md")

        first.functions.begin(
            target: target,
            function: .dialogue,
            selection: nil,
            presentationID: UUID()
        )
        first.functions.instruction = "Question the distinction."
        first.functions.sendMaterials(.setQuery("agency"))

        #expect(first.functions.activeFunction == .dialogue)
        #expect(first.functions.instruction == "Question the distinction.")
        #expect(first.functions.materialsViewState.query == "agency")
        #expect(second.functions.activeFunction == nil)
        #expect(second.functions.instruction.isEmpty)
        #expect(second.functions.materialsViewState.query.isEmpty)
    }

    @Test("Runtime rebinding invalidates an open draft")
    func runtimeRebinding() {
        let controller = ResearchFunctionController()
        controller.bind(client())
        controller.begin(
            target: target(title: "Agency", path: "Topics/Agency.md"),
            function: .fidelity,
            selection: nil,
            presentationID: UUID()
        )

        controller.bind(client())

        #expect(controller.target == nil)
        #expect(controller.presentationID == nil)
        #expect(controller.availability.isEmpty)
    }

    @Test("Workspace generations update a prepared run and retain its durable status")
    func durableRunStatusProjection() async throws {
        let controller = ResearchFunctionController()
        controller.bind(client())
        let target = target(title: "Agency", path: "Topics/Agency.md")
        controller.begin(
            target: target,
            function: .develop,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { controller.canPrepare }
        controller.prepare()
        await waitUntil { controller.preparation != nil }
        let preparation = try #require(controller.preparation)
        let completion = ResearchFunctionCompletion(
            runID: preparation.runID,
            function: .develop,
            state: .awaitingFidelity,
            targetFingerprint: target.fingerprint,
            materialFingerprints: [:],
            summary: "Substantive development reported.",
            didModifyTarget: true,
            fidelityOutcomes: []
        )
        controller.receive(
            [ResearchFunctionRecordProjection(
                snapshot: preparation.snapshot,
                completion: completion
            )],
            targetNoteID: target.noteID
        )

        #expect(controller.phase == .awaitingFidelity)
        #expect(controller.presentedRun?.completion?.state == .awaitingFidelity)
        controller.dismiss()
        #expect(controller.targetRuns.first?.completion?.state == .awaitingFidelity)
    }

    @Test("Reused Fidelity evidence is complete and never exposes cancellation for a nonexistent run")
    func reusedFidelityPreparation() async throws {
        let controller = ResearchFunctionController()
        let target = target(title: "Agency", path: "Topics/Agency.md")
        controller.bind(client(prepare: { request in
            let snapshot = ResearchFunctionSnapshot(
                request: request,
                recordKind: .functionEnvelope
            )
            let reused = ResearchFunctionCompletion(
                runID: UUID(),
                function: .fidelity,
                state: .complete,
                targetFingerprint: request.target.fingerprint,
                materialFingerprints: [:],
                summary: "Reused exact final-revision Fidelity evidence.",
                didModifyTarget: false,
                fidelityOutcomes: [.init(
                    check: .content,
                    state: .passed,
                    summary: "No unresolved fidelity issue."
                )]
            )
            return ResearchFunctionPreparation(
                snapshot: snapshot,
                instructions: "Existing evidence matches this revision.",
                state: .complete,
                reusedCompletion: reused
            )
        }))
        controller.begin(
            target: target,
            function: .fidelity,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { controller.canPrepare }

        controller.prepare()
        await waitUntil { controller.phase == .completed }

        #expect(controller.preparation?.state == .complete)
        #expect(controller.preparation?.reusedCompletion?.state == .complete)
        #expect(controller.presentedRun == nil)
        #expect(!controller.canCancelPreparedRun)
    }

    @Test("A captured source selection defaults the panel to Passage")
    func selectionDefaultsToPassage() {
        let controller = ResearchFunctionController()
        let target = target(title: "Agency", path: "Topics/Agency.md")
        let source = "# Agency\nA selected claim.\n"
        let lower = (source as NSString).range(of: "selected claim").location
        let anchor = ResearcherCommentAnchorBuilder.anchor(
            in: source,
            fingerprint: target.fingerprint,
            utf16Range: lower..<(lower + "selected claim".utf16.count)
        )

        controller.begin(
            target: target,
            function: .fidelity,
            selection: anchor,
            presentationID: UUID()
        )

        #expect(controller.scopeKind == .passage)
        #expect(controller.passageIsAvailable)
    }

    @Test("Read and editor selections resolve to the same Passage anchor")
    func readAndEditorSelectionProjectionMatches() throws {
        let source = "# Agency\n\nFreedom matters here.\n\nA second claim.\n"
        let selectedText = "Freedom matters here."
        let selectedRange = (source as NSString).range(of: selectedText)
        let editorSelection = MarkdownReviewSelection(
            startLine: 3,
            endLine: 3,
            excerpt: selectedText,
            utf16LowerBound: selectedRange.location,
            utf16UpperBound: NSMaxRange(selectedRange)
        )
        let readSelection = MarkdownReviewSelection(
            startLine: 3,
            endLine: 3,
            excerpt: selectedText,
            contextBefore: "# Agency\n\n",
            contextAfter: "\n\nA second claim."
        )

        let editorAnchor = try #require(ResearchFunctionSelectionCapture.anchor(
            for: editorSelection,
            in: source,
            relativePath: "Topics/Agency.md"
        ))
        let readAnchor = try #require(ResearchFunctionSelectionCapture.anchor(
            for: readSelection,
            in: source,
            relativePath: "Topics/Agency.md"
        ))

        #expect(editorAnchor.fingerprint == readAnchor.fingerprint)
        #expect(editorAnchor.utf16Range == readAnchor.utf16Range)
        #expect(editorAnchor.quotation == readAnchor.quotation)
    }

    @Test("Research menu and Strip share the focused selection-capturing action")
    func directCommandSelectionParity() throws {
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
        let noteSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/Note/NoteContentView.swift"
            ),
            encoding: .utf8
        )
        let webReadSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/Note/SafeMarkdownReadWebView.swift"
            ),
            encoding: .utf8
        )
        let nativeReadSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/Note/NativeMarkdownEditorView.swift"
            ),
            encoding: .utf8
        )
        let menuStart = try #require(appSource.range(of: "CommandMenu(\"Research\")"))
        let menuEnd = try #require(appSource.range(
            of: "#if DEBUG",
            range: menuStart.upperBound..<appSource.endIndex
        ))
        let researchMenu = String(appSource[menuStart.lowerBound..<menuEnd.lowerBound])

        #expect(researchMenu.contains("researchFunctionActions?.open(.dialogue)"))
        #expect(!researchMenu.contains("researchFunctionActions?.open(.review)"))
        #expect(researchMenu.contains("researchFunctionActions?.open(.critique)"))
        #expect(!researchMenu.contains("appState?.openResearchFunction"))
        #expect(noteSource.contains("select: openResearchFunction"))
        #expect(noteSource.contains("ScholiumFocusedResearchFunctionActions"))
        #expect(noteSource.contains("open: openResearchFunction"))
        #expect(noteSource.components(separatedBy: "onSelectionChange: { selection in").count == 3)
        #expect(webReadSource.contains("case \"selectionChanged\":"))
        #expect(webReadSource.contains("payload[\"documentID\"] as? String == documentID"))
        #expect(webReadSource.contains("selected.utf16.count <= Self.maximumSelectionLength"))
        #expect(nativeReadSource.contains("onSelectionChange?(reviewSelection"))
    }

    @Test("Unresolved availability is fail-closed while a function loads")
    func unresolvedAvailabilityIsDisabled() async throws {
        let controller = ResearchFunctionController()
        let gate = LoadGate()
        controller.bind(client(beforeLoad: { target in
            await gate.wait(target.title)
        }))
        controller.begin(
            target: target(title: "Agency", path: "Topics/Agency.md"),
            function: .develop,
            selection: nil,
            presentationID: UUID()
        )

        #expect(!controller.canPrepare)
        gate.release("Agency")
        await gate.waitUntilPassed("Agency", count: 2)
        await waitUntil { controller.canPrepare }
        #expect(controller.canPrepare)
    }

    @Test("Materials preserve role and folder ancestors while search and suggestions intersect")
    func materialsHierarchySearchAndSelection() throws {
        let target = target(title: "Source", path: "Source.md")
        let passage = ResearcherCommentAnchor(
            fingerprint: target.fingerprint,
            utf8Range: 12..<24,
            utf16Range: 12..<24,
            line: 1,
            endLine: 1,
            quotation: "selected link"
        )
        let suggested = materialCandidate(
            title: "Agency",
            path: "Debates/Agency.md",
            role: .topic,
            vaultID: target.note.vaultID,
            aliases: ["Freedom"],
            suggestionReasons: [suggestionReason(
                .linkedFromTarget,
                source: target.note,
                lowerBound: 16
            )]
        )
        let analysis = materialCandidate(
            title: "Other Source",
            path: "Archive/Other Source.md",
            role: .analysis
        )
        let work = materialCandidate(
            title: "Chapter",
            path: "Project/Chapter.md",
            role: .work
        )
        var state = ResearchFunctionMaterialsState()
        state.beginLoading()
        state.receive(
            [work, suggested, analysis],
            target: target.note,
            passage: passage
        )

        #expect(state.phase == .ready)
        #expect(state.selectedMaterialIDs.isEmpty)
        #expect(state.viewState.roots.map(\.title) == ["Analyses", "Topics", "Works"])
        let topicRoot = try #require(state.viewState.roots.first {
            $0.title == "Topics"
        })
        #expect(topicRoot.children.first?.title == "Debates")
        #expect(topicRoot.children.first?.children.first?.title == "Agency")
        let debates = try #require(topicRoot.children.first)
        #expect(debates.isExpanded)
        state.apply(.toggleFolder(debates.id))
        let collapsedTopic = try #require(state.viewState.roots.first {
            $0.title == "Topics"
        })
        #expect(collapsedTopic.children.first?.isExpanded == false)
        #expect(suggested.suggestionReasons.first?.kind == .linkedFromTarget)
        #expect(state.candidates.first { $0.id == suggested.id }?
            .suggestionReasons.first?.kind == .linkedFromSelectedPassage)

        state.apply(.setQuery("freedom"))
        state.apply(.setSuggestedOnly(true))
        #expect(state.viewState.roots.map(\.title) == ["Topics"])
        #expect(state.viewState.roots.first?.children.first?.title == "Debates")
        state.apply(.setSelected(suggested.id, true))
        #expect(state.viewState.selectedCandidates.map(\.id) == [suggested.id])

        state.freeze()
        let frozen = state
        state.apply(.setQuery("chapter"))
        state.apply(.remove(suggested.id))
        state.apply(.setSuggestedOnly(false))
        #expect(state == frozen)
        state.apply(.reset)
        #expect(state.phase == .idle)
        #expect(state.candidates.isEmpty)
        #expect(state.viewState.query.isEmpty)
        #expect(!state.isFrozen)
    }

    @Test("Materials failure rejects generation until an explicit retry succeeds")
    func materialsFailureAndRetry() async {
        let controller = ResearchFunctionController()
        var attemptCount = 0
        controller.bind(client(materialCandidates: { target, _ in
            attemptCount += 1
            if attemptCount == 1 { throw TestFailure.materialsUnavailable }
            return [materialCandidate(
                title: "Agency",
                path: "Debates/Agency.md",
                role: .topic,
                vaultID: target.note.vaultID
            )]
        }))
        controller.begin(
            target: target(title: "Source", path: "Source.md"),
            function: .develop,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil {
            if case .failed = controller.materialsState.phase { return true }
            return false
        }

        #expect(!controller.canPrepare)
        #expect(controller.materialCandidates.isEmpty)
        controller.sendMaterials(.retry)
        await waitUntil { controller.canPrepare }
        #expect(attemptCount == 2)
        #expect(controller.materialCandidates.map(\.material.title) == ["Agency"])
        #expect(controller.selectedMaterialIDs.isEmpty)
    }

    @Test("Preparing freezes the exact Materials selection")
    func preparationFreezesMaterials() async throws {
        let controller = ResearchFunctionController()
        var capturedRequest: ResearchFunctionRequest?
        controller.bind(client(prepare: { request in
            capturedRequest = request
            return ResearchFunctionPreparation(
                snapshot: ResearchFunctionSnapshot(
                    request: request,
                    recordKind: .functionEnvelope
                ),
                instructions: "Prepared"
            )
        }))
        controller.begin(
            target: target(title: "Source", path: "Source.md"),
            function: .develop,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { controller.canPrepare }
        let candidate = try #require(controller.materialCandidates.first)
        controller.sendMaterials(.setSelected(candidate.id, true))
        controller.prepare()
        #expect(controller.materialsState.isFrozen)
        controller.sendMaterials(.setSelected(candidate.id, false))
        controller.sendMaterials(.setQuery("different"))
        await waitUntil { capturedRequest != nil }

        #expect(capturedRequest?.materials == [candidate.material])
        #expect(controller.selectedMaterialIDs == [candidate.id])
        #expect(controller.materialsViewState.query.isEmpty)
    }

    @Test("Function leaves preserve the compiler-enforced delivery boundary")
    func sourceBoundaries() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let paths = [
            "Scholium/Features/ResearchFunctions/ResearchFunctionController.swift",
            "Scholium/Views/ResearchFunctions/ResearchFunctionPanelView.swift",
            "Scholium/Views/ResearchFunctions/ResearchStripView.swift",
        ]
        for path in paths {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(path),
                encoding: .utf8
            )
            #expect(!source.contains("import Scholium" + "Application"))
            #expect(!source.contains("import Scholium" + "Core"))
            #expect(!source.contains("WindowModel"))
            #expect(!source.contains("FileManager"))
            #expect(!source.contains("import Yams"))
            #expect(!source.contains("ResearchSkillInspector"))
        }
    }

    @Test("The Work Strip keeps every function available at compact editor widths")
    func compactStripUsesAnAdaptiveVisibleLabelRow() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ResearchFunctions/ResearchStripView.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("ViewThatFits(in: .horizontal)"))
        #expect(source.contains("isCompact: true"))
        #expect(source.contains("Text(item.id.interfaceTitleResource)"))
        #expect(!source.contains("Menu {"))
    }

    @Test("The Strip and direct actions never treat unresolved availability as enabled")
    func availabilityProjectionIsFailClosed() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )

        #expect(!source.contains("availability[function]?.isEnabled ?? true"))
        #expect(source.contains("availability[function]?.isEnabled == true"))
        #expect(source.contains("refreshAvailability(for: target)"))
        #expect(source.contains("Checking availability…"))
    }

    @Test("Guided Evolution requires two passes bound to the exact proposal")
    func guidedEvolutionApplyGate() {
        let source = "---\nname: Test\ndescription: Test\n---\nInstructions."
        let proposedPackage = ResearchSkillProposedPackage(files: [
            ResearchSkillMaintenanceFile(relativePath: "SKILL.md", source: source),
        ])
        let currentRevision = DocumentFingerprint(content: "current")
        let proposedRevision = DocumentFingerprint(content: "proposed")
        let request = ResearchSkillMaintenanceRequest(
            packageID: "test-skill",
            expectedPackageRevision: currentRevision,
            proposedPackage: proposedPackage,
            instruction: "Refine the real workflow."
        )
        let id = UUID()
        let token = ResearchSkillMaintenanceConfirmationToken(
            preparationID: id,
            packageID: request.packageID,
            expectedPackageRevision: currentRevision,
            proposedPackageRevision: proposedRevision,
            expiresAt: .distantFuture
        )
        let passed = ResearchSkillMaintenancePreparation(
            id: id,
            request: request,
            proposedPackageRevision: proposedRevision,
            changes: [],
            evaluation: ResearchSkillMaintenanceEvaluationResult(
                status: .passed,
                structuralStatus: .passed,
                externalStatus: .passed,
                evaluator: "External agent",
                method: "Boundary and adversarial cases",
                proposedPackageRevision: proposedRevision
            ),
            confirmationToken: token
        )
        let incomplete = ResearchSkillMaintenancePreparation(
            id: UUID(),
            request: request,
            proposedPackageRevision: proposedRevision,
            changes: [],
            evaluation: ResearchSkillMaintenanceEvaluationResult(
                status: .incomplete,
                structuralStatus: .passed,
                externalStatus: .incomplete
            ),
            confirmationToken: nil
        )

        #expect(passed.isReadyForSettingsApply)
        #expect(!incomplete.isReadyForSettingsApply)
    }

    @Test("Guided Evolution identifies the external report and its handoff truthfully")
    func guidedEvolutionPresentationIsAttributed() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ResearchSkillMaintenanceView.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("Structural Validation"))
        #expect(source.contains("Agent-Reported Evaluation"))
        #expect(source.contains("Copy Proposal Request"))
        #expect(source.contains("Import Proposal"))
        #expect(source.contains("Copy Evaluation Request"))
        #expect(source.contains("Package Comparison"))
        #expect(source.contains("Scholium does not run this philosophical evaluation."))
        #expect(!source.contains("Scholium evaluates the complete proposed package"))
    }

    private func client(
        beforeLoad: @escaping @MainActor (ResearchFunctionTarget) async -> Void = { _ in },
        dialogueResponseProfile: @escaping @MainActor () async throws -> DialogueResponseProfile = {
            DialogueResponseProfile(modules: [.remainingQuestions])
        },
        materialCandidates: (@MainActor (
            ResearchFunctionTarget,
            ResearchFunctionID
        ) async throws -> [ResearchFunctionMaterialCandidate])? = nil,
        prepare: (@MainActor (ResearchFunctionRequest) async throws -> ResearchFunctionPreparation)? = nil
    ) -> ResearchFunctionClient {
        ResearchFunctionClient(
            availableFunctions: { target in
                await beforeLoad(target)
                return target.role == .work
                    ? [.init(function: .critique, isEnabled: true)]
                    : [
                        .init(function: .dialogue, isEnabled: true),
                        .init(function: .develop, isEnabled: true),
                        .init(
                            function: .fidelity,
                            isEnabled: true,
                            fidelityChecks: [
                                .init(check: .content, isEnabled: true),
                                .init(check: .citations, isEnabled: false),
                            ]
                        ),
                    ]
            },
            materialCandidates: materialCandidates ?? { target, _ in
                await beforeLoad(target)
                return [materialCandidate(
                    title: "Material for \(target.title)",
                    path: "Material-\(target.title).md",
                    role: .topic,
                    vaultID: target.note.vaultID
                )]
            },
            dialogueResponseProfile: dialogueResponseProfile,
            prepare: prepare ?? { request in
                let snapshot = ResearchFunctionSnapshot(
                    request: request,
                    recordKind: .functionEnvelope
                )
                return ResearchFunctionPreparation(
                    snapshot: snapshot,
                    instructions: "Prepared"
                )
            },
            complete: { submission in
                ResearchFunctionCompletion(
                    runID: submission.runID,
                    function: .develop,
                    state: .complete,
                    targetFingerprint: submission.finalTargetFingerprint,
                    materialFingerprints: submission.finalMaterialFingerprints,
                    summary: submission.summary,
                    didModifyTarget: submission.didModifyTarget,
                    fidelityOutcomes: submission.fidelityOutcomes
                )
            },
            cancel: { _ in }
        )
    }

    private func target(title: String, path: String) -> ResearchFunctionTarget {
        ResearchFunctionTarget(
            noteID: UUID(),
            note: VaultQualifiedNoteID(vaultID: UUID(), relativePath: path),
            role: .topic,
            fingerprint: DocumentFingerprint(content: "# \(title)\nA selected claim.\n"),
            title: title
        )
    }

    private func materialCandidate(
        title: String,
        path: String,
        role: ResearchFunctionTargetRole,
        vaultID: UUID = UUID(),
        aliases: [String] = [],
        suggestionReasons: [ResearchFunctionMaterialSuggestionReason] = []
    ) -> ResearchFunctionMaterialCandidate {
        ResearchFunctionMaterialCandidate(
            material: ResearchFunctionMaterial(
                noteID: UUID(),
                note: VaultQualifiedNoteID(vaultID: vaultID, relativePath: path),
                role: role,
                fingerprint: DocumentFingerprint(content: title),
                title: title
            ),
            aliases: aliases,
            suggestionReasons: suggestionReasons
        )
    }

    private func suggestionReason(
        _ kind: ResearchFunctionMaterialSuggestionReason.Kind,
        source: VaultQualifiedNoteID,
        lowerBound: Int
    ) -> ResearchFunctionMaterialSuggestionReason {
        ResearchFunctionMaterialSuggestionReason(
            kind: kind,
            sourceNote: source,
            sourceSpan: SourceSpan(
                utf8LowerBound: lowerBound,
                utf8UpperBound: lowerBound + 4,
                utf16LowerBound: lowerBound,
                utf16UpperBound: lowerBound + 4,
                start: SourcePosition(
                    line: 1,
                    utf8Column: lowerBound + 1,
                    utf16Column: lowerBound + 1
                ),
                end: SourcePosition(
                    line: 1,
                    utf8Column: lowerBound + 5,
                    utf16Column: lowerBound + 5
                )
            )
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }

    private enum TestFailure: LocalizedError {
        case dialogueDefaultsUnavailable
        case materialsUnavailable

        var errorDescription: String? {
            switch self {
            case .dialogueDefaultsUnavailable:
                "Dialogue defaults are unavailable."
            case .materialsUnavailable:
                "Materials are unavailable."
            }
        }
    }

    @MainActor
    private final class LoadGate {
        private var released: Set<String> = []
        private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]
        private var arrivalCounts: [String: Int] = [:]
        private var arrivalWaiters: [
            String: [(Int, CheckedContinuation<Void, Never>)]
        ] = [:]
        private var passCounts: [String: Int] = [:]
        private var passWaiters: [String: [(Int, CheckedContinuation<Void, Never>)]] = [:]

        func wait(_ key: String) async {
            arrivalCounts[key, default: 0] += 1
            Self.resumeSatisfiedWaiters(
                for: key,
                counts: arrivalCounts,
                waiters: &arrivalWaiters
            )
            if !released.contains(key) {
                await withCheckedContinuation { continuation in
                    waiting[key, default: []].append(continuation)
                }
            }
            passCounts[key, default: 0] += 1
            resumeSatisfiedPassWaiters(for: key)
        }

        func release(_ key: String) {
            released.insert(key)
            let continuations = waiting.removeValue(forKey: key) ?? []
            continuations.forEach { $0.resume() }
        }

        func waitUntilPassed(_ key: String, count: Int) async {
            guard passCounts[key, default: 0] < count else { return }
            await withCheckedContinuation { continuation in
                passWaiters[key, default: []].append((count, continuation))
            }
        }

        func waitUntilArrived(_ key: String, count: Int) async {
            guard arrivalCounts[key, default: 0] < count else { return }
            await withCheckedContinuation { continuation in
                arrivalWaiters[key, default: []].append((count, continuation))
            }
        }

        private func resumeSatisfiedPassWaiters(for key: String) {
            Self.resumeSatisfiedWaiters(
                for: key,
                counts: passCounts,
                waiters: &passWaiters
            )
        }

        private static func resumeSatisfiedWaiters(
            for key: String,
            counts: [String: Int],
            waiters: inout [String: [(Int, CheckedContinuation<Void, Never>)]]
        ) {
            let count = counts[key, default: 0]
            let current = waiters.removeValue(forKey: key) ?? []
            var pending: [(Int, CheckedContinuation<Void, Never>)] = []
            for waiter in current {
                if waiter.0 <= count {
                    waiter.1.resume()
                } else {
                    pending.append(waiter)
                }
            }
            if !pending.isEmpty { waiters[key] = pending }
        }
    }
}
