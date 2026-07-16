import ScholiumContracts
import Foundation
import Testing
@testable import ScholiumApp

@Suite("Research Function controller")
@MainActor
struct ResearchFunctionControllerTests {
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
        await waitUntil { controller.phase == .editing }

        #expect(controller.target == second)
        #expect(controller.activeFunction == .develop)
        #expect(controller.phase == .editing)
        #expect(controller.materialCandidates.first?.material.title == "Material for Second")
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

        #expect(first.functions.activeFunction == .dialogue)
        #expect(first.functions.instruction == "Question the distinction.")
        #expect(second.functions.activeFunction == nil)
        #expect(second.functions.instruction.isEmpty)
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
        await waitUntil { controller.phase == .editing }
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
        await waitUntil { controller.phase == .editing }

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
        #expect(researchMenu.contains("researchFunctionActions?.open(.review)"))
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
        await waitUntil { controller.phase == .editing }
        #expect(controller.canPrepare)
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
        #expect(source.contains("Text(item.id.interfaceTitle)"))
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
            materialCandidates: { target, _ in
                await beforeLoad(target)
                let material = ResearchFunctionMaterial(
                    noteID: UUID(),
                    note: VaultQualifiedNoteID(
                        vaultID: target.note.vaultID,
                        relativePath: "Topics/Material-\(target.title).md"
                    ),
                    role: .topic,
                    fingerprint: DocumentFingerprint(content: "material"),
                    title: "Material for \(target.title)"
                )
                return [.init(material: material)]
            },
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

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
        #expect(condition())
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
