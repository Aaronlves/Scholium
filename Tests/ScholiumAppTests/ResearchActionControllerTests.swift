import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@MainActor
@Suite("Research Action controller")
struct ResearchActionControllerTests {
    @Test("Resolved Actions keep default and Researcher Skill order")
    func availabilityOrder() async throws {
        let controller = ResearchActionController()
        let custom = try #require(ResearchActionID(researcherOwnedRawValue: "counterexample"))
        controller.bind(client(actions: [
            try availability(custom, order: 1, group: .researcherSkill),
            try availability(.checkFidelity, order: 300),
            try availability(.discuss, order: 0),
            try availability(.synthesize, order: 100),
        ]))

        await controller.refreshAvailability(for: target())

        #expect(controller.availability.map(\.id) == [
            .discuss, .synthesize, .checkFidelity, custom,
        ])
    }

    @Test("The common sheet builds only declared module parameters")
    func declaredParameters() async throws {
        let requestID = try #require(ResearchActionModuleID(rawValue: "request"))
        let materialsID = try #require(ResearchActionModuleID(rawValue: "materials"))
        let checksID = try #require(ResearchActionModuleID(rawValue: "checks"))
        let content = try #require(ResearchActionModuleChoiceValue(rawValue: "content"))
        let citations = try #require(ResearchActionModuleChoiceValue(rawValue: "citations"))
        let modules = [
            try ResearchActionModuleDefinition.boundedText(
                id: requestID,
                label: "Request",
                isRequired: true,
                maximumTextUTF8ByteCount: 64,
                allowsMultipleLines: true
            ),
            try ResearchActionModuleDefinition.materialSelector(
                id: materialsID,
                label: "Materials",
                isRequired: false,
                roleScope: [.analysis, .topic, .work],
                maximumSelectionCount: 2
            ),
            try ResearchActionModuleDefinition.enumeration(
                id: checksID,
                label: "Checks",
                isRequired: true,
                choices: [
                    try ResearchActionModuleChoice(value: content, label: "Content"),
                    try ResearchActionModuleChoice(value: citations, label: "Citations"),
                ],
                maximumSelectionCount: 2
            ),
        ]
        let action = try availability(.discuss, order: 0, modules: modules)
        let candidate = target(title: "Material", path: "Analyses/Material.md", role: .analysis)
        var captured: ResearchActionExecutionRequest?
        let controller = ResearchActionController()
        controller.bind(client(
            actions: [action],
            candidates: [candidate],
            prepare: { request in
                captured = request
                throw TestFailure.stopAfterCapture
            }
        ))
        let target = target()
        controller.begin(
            target: target,
            actionID: .discuss,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { controller.phase == .editing }

        controller.setText("Compare the arguments", module: modules[0])
        controller.setNote(candidate.noteID, isSelected: true, module: modules[1])
        controller.setChoice(content, isSelected: true, module: modules[2])
        controller.setChoice(citations, isSelected: true, module: modules[2])
        #expect(controller.canPrepare)
        controller.prepare()
        await waitUntil { controller.phase == .failed }

        #expect(captured?.actionID == .discuss)
        #expect(captured?.expectedExecutionKind == action.definition.executionKind)
        #expect(captured?.expectedProfileRevision == action.profile.profileRevision)
        #expect(captured?.expectedProfileDocumentRevision
            == action.profile.profileDocumentRevision)
        #expect(captured?.target == target)
        #expect(captured?.parameterValues[requestID.rawValue] == .text("Compare the arguments"))
        #expect(captured?.parameterValues[materialsID.rawValue] == .notes([candidate]))
        #expect(captured?.parameterValues[checksID.rawValue] == .choices([citations, content]))
    }

    @Test("Single-selection modules replace the prior value")
    func singleSelectionReplacement() async throws {
        let choiceID = try #require(ResearchActionModuleID(rawValue: "approach"))
        let noteID = try #require(ResearchActionModuleID(rawValue: "focal-note"))
        let firstChoice = try #require(ResearchActionModuleChoiceValue(rawValue: "first"))
        let secondChoice = try #require(ResearchActionModuleChoiceValue(rawValue: "second"))
        let modules = [
            try ResearchActionModuleDefinition.enumeration(
                id: choiceID,
                label: "Approach",
                isRequired: true,
                choices: [
                    try ResearchActionModuleChoice(value: firstChoice, label: "First"),
                    try ResearchActionModuleChoice(value: secondChoice, label: "Second"),
                ],
                maximumSelectionCount: 1
            ),
            try ResearchActionModuleDefinition.notePicker(
                id: noteID,
                label: "Focal note",
                isRequired: false,
                roleScope: [.topic],
                maximumSelectionCount: 1
            ),
        ]
        let firstNote = target(title: "First note", path: "Topics/First.md")
        let secondNote = target(title: "Second note", path: "Topics/Second.md")
        let controller = ResearchActionController()
        controller.bind(client(
            actions: [try availability(.discuss, order: 0, modules: modules)],
            candidates: [firstNote, secondNote]
        ))
        controller.begin(
            target: target(),
            actionID: .discuss,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { controller.phase == .editing }

        #expect(controller.choiceValues[choiceID.rawValue]?.isEmpty == true)
        controller.setChoice(secondChoice, isSelected: true, module: modules[0])
        controller.setNote(firstNote.noteID, isSelected: true, module: modules[1])
        controller.setNote(secondNote.noteID, isSelected: true, module: modules[1])

        #expect(controller.choiceValues[choiceID.rawValue] == [secondChoice])
        #expect(controller.noteValues[noteID.rawValue] == [secondNote.noteID])
    }

    @Test("A required source remains fail closed until machine-local access is available")
    func sourceRequirement() async throws {
        let sourceID = try #require(ResearchActionModuleID(rawValue: "source"))
        let sourceModule = try ResearchActionModuleDefinition.sourceReference(
            id: sourceID,
            label: "Source",
            isRequired: true
        )
        let unavailableAction = try availability(
            .analyze,
            role: .analysis,
            order: 100,
            modules: [sourceModule],
            sourceRequirement: .required,
            enabled: false,
            repairReasons: [ResearchActionRepairReason(code: .sourceAccessRequired)]
        )
        let availableAction = try availability(
            .analyze,
            role: .analysis,
            order: 100,
            modules: [sourceModule],
            sourceRequirement: .required
        )
        let reference = try ResearchSourceReference(
            identity: .localFile(),
            displayName: "Source.pdf",
            fingerprint: DocumentFingerprint(content: "source")
        )
        var didBind = false
        let controller = ResearchActionController()
        controller.bind(ResearchActionClient(
            availableActions: { _ in didBind ? [availableAction] : [unavailableAction] },
            materialCandidates: { _, _ in [] },
            sourceAccess: { _ in .repairRequired(.missingBinding) },
            bindLocalSource: { _, _ in
                didBind = true
                return reference
            },
            prepare: { _ in throw TestFailure.stopAfterCapture },
            cancel: { _ in },
            openActiveDiscussion: { _ in }
        ))

        controller.begin(
            target: target(role: .analysis),
            actionID: .analyze,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { controller.phase == .editing }

        #expect(controller.sourceStatus?.state == .repairRequired)
        #expect(!controller.canPrepare)
        #expect(controller.activeAvailability?.canPresentInInterface == true)

        controller.bindLocalSource(URL(fileURLWithPath: "/Source.pdf"))
        await waitUntil { !controller.isBindingSource }

        #expect(controller.sourceStatus == .available(reference))
        #expect(controller.activeAvailability?.isEnabled == true)
        #expect(controller.canPrepare)
    }

    @Test("Changing Target invalidates the open Action draft")
    func targetChangeInvalidatesDraft() async throws {
        let controller = ResearchActionController()
        controller.bind(client(actions: [try availability(.synthesize, order: 100)]))
        controller.begin(
            target: target(),
            actionID: .synthesize,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { controller.phase == .editing }

        controller.invalidateIfTargetChanged(target(title: "Other", path: "Topics/Other.md"))

        #expect(!controller.isPresented)
        #expect(controller.target == nil)
        #expect(controller.phase == .idle)
    }

    @Test("Availability fails closed for a new Target and ignores a late prior result")
    func availabilityIsTargetBound() async throws {
        let first = target(title: "First", path: "Topics/First.md")
        let second = target(title: "Second", path: "Topics/Second.md")
        let firstActions = [try availability(.discuss, order: 0)]
        let secondActions = [try availability(.synthesize, order: 100)]
        var firstContinuation: CheckedContinuation<
            [ResearchActionAvailability],
            Never
        >?
        let controller = ResearchActionController()
        controller.bind(ResearchActionClient(
            availableActions: { target in
                if target == first {
                    return await withCheckedContinuation { continuation in
                        firstContinuation = continuation
                    }
                }
                return secondActions
            },
            materialCandidates: { _, _ in [] },
            sourceAccess: { _ in .repairRequired(.missingBinding) },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: { _ in throw TestFailure.stopAfterCapture },
            cancel: { _ in },
            openActiveDiscussion: { _ in }
        ))

        let firstRefresh = Task { await controller.refreshAvailability(for: first) }
        await waitUntil { controller.availabilityTarget == first }
        #expect(controller.availability.isEmpty)

        await controller.refreshAvailability(for: second)
        #expect(controller.availabilityTarget == second)
        #expect(controller.availability.map(\.id) == [.synthesize])

        firstContinuation?.resume(returning: firstActions)
        _ = await firstRefresh.value
        #expect(controller.availabilityTarget == second)
        #expect(controller.availability.map(\.id) == [.synthesize])
    }

    @Test("A late dependency load cannot overwrite a newer Action sheet")
    func dependencyLoadIsPresentationBound() async throws {
        let materialsID = try #require(ResearchActionModuleID(rawValue: "materials"))
        let module = try ResearchActionModuleDefinition.materialSelector(
            id: materialsID,
            label: "Materials",
            isRequired: false,
            roleScope: [.topic],
            maximumSelectionCount: 2
        )
        let action = try availability(.discuss, order: 0, modules: [module])
        let firstTarget = target(title: "First", path: "Topics/First.md")
        let secondTarget = target(title: "Second", path: "Topics/Second.md")
        let firstMaterial = target(title: "Old material", path: "Topics/Old.md")
        let secondMaterial = target(title: "Current material", path: "Topics/Current.md")
        var firstContinuation: CheckedContinuation<
            [ResearchActionNoteSnapshot],
            Never
        >?
        let controller = ResearchActionController()
        controller.bind(ResearchActionClient(
            availableActions: { _ in [action] },
            materialCandidates: { target, _ in
                if target == firstTarget {
                    return await withCheckedContinuation { continuation in
                        firstContinuation = continuation
                    }
                }
                return [secondMaterial]
            },
            sourceAccess: { _ in .repairRequired(.missingBinding) },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: { _ in throw TestFailure.stopAfterCapture },
            cancel: { _ in },
            openActiveDiscussion: { _ in }
        ))

        controller.begin(
            target: firstTarget,
            actionID: .discuss,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { firstContinuation != nil }
        controller.begin(
            target: secondTarget,
            actionID: .discuss,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { controller.phase == .editing }
        #expect(controller.materialCandidates == [secondMaterial])

        firstContinuation?.resume(returning: [firstMaterial])
        try? await Task.sleep(for: .milliseconds(20))
        #expect(controller.target == secondTarget)
        #expect(controller.materialCandidates == [secondMaterial])
    }

    @Test("Availability errors stay visible and fail closed")
    func availabilityFailure() async {
        let controller = ResearchActionController()
        controller.bind(ResearchActionClient(
            availableActions: { _ in throw TestFailure.stopAfterCapture },
            materialCandidates: { _, _ in [] },
            sourceAccess: { _ in .repairRequired(.missingBinding) },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: { _ in throw TestFailure.stopAfterCapture },
            cancel: { _ in },
            openActiveDiscussion: { _ in }
        ))

        await controller.refreshAvailability(for: target())

        #expect(controller.availability.isEmpty)
        #expect(!controller.isRefreshingAvailability)
        #expect(controller.availabilityError == TestFailure.stopAfterCapture.localizedDescription)
    }

    @Test("A sheet load failure discards the launcher Profile")
    func sheetLoadFailureDiscardsLauncherProfile() async throws {
        let action = try availability(.synthesize, order: 100)
        var resolutionCount = 0
        let controller = ResearchActionController()
        controller.bind(ResearchActionClient(
            availableActions: { _ in
                resolutionCount += 1
                if resolutionCount == 2 { throw TestFailure.stopAfterCapture }
                return [action]
            },
            materialCandidates: { _, _ in [] },
            sourceAccess: { _ in .repairRequired(.missingBinding) },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: { _ in throw TestFailure.stopAfterCapture },
            cancel: { _ in },
            openActiveDiscussion: { _ in }
        ))
        let target = target()

        await controller.refreshAvailability(for: target)
        #expect(controller.activeAvailability == nil)
        #expect(controller.availability.map(\.id) == [.synthesize])

        controller.begin(
            target: target,
            actionID: .synthesize,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { controller.phase == .failed }

        #expect(controller.availability.map(\.id) == [.synthesize])
        #expect(controller.activeAvailability == nil)
        #expect(controller.profile == nil)
        #expect(!controller.canPrepare)
        #expect(controller.availabilityError == TestFailure.stopAfterCapture.localizedDescription)
        #expect(controller.errorMessage == TestFailure.stopAfterCapture.localizedDescription)

        controller.dismiss()
        await controller.refreshAvailability(for: target)
        #expect(controller.availability.map(\.id) == [.synthesize])
        #expect(controller.availabilityError == nil)
    }

    @Test("Cancelling a sheet load preserves the launcher availability")
    func cancelledSheetLoadPreservesLauncherAvailability() async throws {
        let action = try availability(.synthesize, order: 100)
        var resolutionCount = 0
        var sheetContinuation: CheckedContinuation<
            [ResearchActionAvailability],
            Never
        >?
        let controller = ResearchActionController()
        controller.bind(ResearchActionClient(
            availableActions: { _ in
                resolutionCount += 1
                if resolutionCount == 1 { return [action] }
                return await withCheckedContinuation { continuation in
                    sheetContinuation = continuation
                }
            },
            materialCandidates: { _, _ in [] },
            sourceAccess: { _ in .repairRequired(.missingBinding) },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: { _ in throw TestFailure.stopAfterCapture },
            cancel: { _ in },
            openActiveDiscussion: { _ in }
        ))
        let target = target()
        await controller.refreshAvailability(for: target)

        controller.begin(
            target: target,
            actionID: .synthesize,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { sheetContinuation != nil }
        controller.dismiss()

        #expect(controller.availability.map(\.id) == [.synthesize])
        #expect(controller.profile == nil)
        sheetContinuation?.resume(returning: [action])
        try? await Task.sleep(for: .milliseconds(20))
        #expect(controller.availability.map(\.id) == [.synthesize])
        #expect(!controller.isPresented)
    }

    @Test("A failed abandoned-run cancellation remains retryable")
    func dismissedPreparationCancellationIsRetryable() async throws {
        let action = try availability(.discuss, order: 0)
        let target = target()
        let runID = UUID()
        let result = try preparation(action: action, target: target, runID: runID)
        var preparationContinuation: CheckedContinuation<
            ResearchActionPreparation,
            Never
        >?
        var cancelledRunIDs: [UUID] = []
        var cancellationAttempt = 0
        let controller = ResearchActionController()
        controller.bind(ResearchActionClient(
            availableActions: { _ in [action] },
            materialCandidates: { _, _ in [] },
            sourceAccess: { _ in .repairRequired(.missingBinding) },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: { _ in
                await withCheckedContinuation { continuation in
                    preparationContinuation = continuation
                }
            },
            cancel: {
                cancelledRunIDs.append($0)
                cancellationAttempt += 1
                if cancellationAttempt == 1 { throw TestFailure.stopAfterCapture }
            },
            openActiveDiscussion: { _ in }
        ))
        let presentationID = UUID()
        controller.begin(
            target: target,
            actionID: .discuss,
            selection: nil,
            presentationID: presentationID
        )
        await waitUntil { controller.phase == .editing }

        controller.prepare()
        await waitUntil { preparationContinuation != nil }
        #expect(controller.phase == .preparing)
        controller.dismiss(presentationID: presentationID)
        #expect(controller.hasCancellationBarrier)
        preparationContinuation?.resume(returning: result)
        await waitUntil {
            controller.cancellationRecoveries.contains { $0.runID == runID }
        }

        #expect(!controller.isPresented)
        #expect(controller.preparation == nil)
        #expect(cancelledRunIDs == [runID])
        #expect(
            controller.cancellationRecoveries.first(where: { $0.runID == runID })?.errorMessage
                == TestFailure.stopAfterCapture.localizedDescription
        )

        controller.retryCancellationRecovery(runID: runID)
        await waitUntil { controller.cancellationRecoveries.isEmpty }
        #expect(cancelledRunIDs == [runID, runID])
        #expect(!controller.retryingCancellationRecoveryIDs.contains(runID))
        #expect(!controller.hasCancellationBarrier)
    }

    @Test("A failed cancellation remains retryable when its sheet closes mid-request")
    func dismissedInFlightCancellationIsRetryable() async throws {
        let action = try availability(.discuss, order: 0)
        let target = target()
        let runID = UUID()
        let result = try preparation(action: action, target: target, runID: runID)
        var cancellationContinuation: CheckedContinuation<Void, Never>?
        var cancelledRunIDs: [UUID] = []
        let controller = ResearchActionController()
        controller.bind(ResearchActionClient(
            availableActions: { _ in [action] },
            materialCandidates: { _, _ in [] },
            sourceAccess: { _ in .repairRequired(.missingBinding) },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: { _ in result },
            cancel: { requestedRunID in
                cancelledRunIDs.append(requestedRunID)
                if cancelledRunIDs.count == 1 {
                    await withCheckedContinuation { continuation in
                        cancellationContinuation = continuation
                    }
                    throw TestFailure.stopAfterCapture
                }
            },
            openActiveDiscussion: { _ in }
        ))
        let presentationID = UUID()
        controller.begin(
            target: target,
            actionID: .discuss,
            selection: nil,
            presentationID: presentationID
        )
        await waitUntil { controller.phase == .editing }
        controller.prepare()
        await waitUntil { controller.phase == .prepared }

        controller.cancelPreparedRun()
        await waitUntil { cancellationContinuation != nil }
        #expect(controller.phase == .cancelling)
        controller.dismiss(presentationID: presentationID)
        #expect(controller.hasCancellationBarrier)
        cancellationContinuation?.resume()

        await waitUntil {
            controller.cancellationRecoveries.contains { $0.runID == runID }
        }
        #expect(cancelledRunIDs == [runID])
        #expect(controller.pendingCancellationBarrierCount == 0)
        #expect(controller.hasCancellationBarrier)

        controller.retryCancellationRecovery(runID: runID)
        await waitUntil { controller.cancellationRecoveries.isEmpty }
        #expect(cancelledRunIDs == [runID, runID])
        #expect(!controller.hasCancellationBarrier)
    }

    @Test("An in-flight durable boundary refuses a replacement Action")
    func inFlightBoundaryRefusesReplacementAction() async throws {
        let action = try availability(.discuss, order: 0)
        let firstTarget = target(title: "First", path: "Topics/First.md")
        let secondTarget = target(title: "Second", path: "Topics/Second.md")
        let runID = UUID()
        let result = try preparation(action: action, target: firstTarget, runID: runID)
        var preparationContinuation: CheckedContinuation<
            ResearchActionPreparation,
            Never
        >?
        var cancellationContinuation: CheckedContinuation<Void, Never>?
        let controller = ResearchActionController()
        controller.bind(ResearchActionClient(
            availableActions: { _ in [action] },
            materialCandidates: { _, _ in [] },
            sourceAccess: { _ in .repairRequired(.missingBinding) },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: { _ in
                await withCheckedContinuation { continuation in
                    preparationContinuation = continuation
                }
            },
            cancel: { _ in
                await withCheckedContinuation { continuation in
                    cancellationContinuation = continuation
                }
            },
            openActiveDiscussion: { _ in }
        ))
        let firstPresentationID = UUID()
        #expect(controller.begin(
            target: firstTarget,
            actionID: .discuss,
            selection: nil,
            presentationID: firstPresentationID
        ))
        await waitUntil { controller.phase == .editing }

        controller.prepare()
        await waitUntil { preparationContinuation != nil }
        #expect(controller.hasCancellationBarrier)
        #expect(!controller.begin(
            target: secondTarget,
            actionID: .discuss,
            selection: nil,
            presentationID: UUID()
        ))
        #expect(controller.target == firstTarget)
        #expect(controller.presentationID == firstPresentationID)
        #expect(controller.phase == .preparing)

        preparationContinuation?.resume(returning: result)
        await waitUntil { controller.phase == .prepared }
        controller.cancelPreparedRun()
        await waitUntil { cancellationContinuation != nil }
        #expect(controller.hasCancellationBarrier)
        #expect(!controller.begin(
            target: secondTarget,
            actionID: .discuss,
            selection: nil,
            presentationID: UUID()
        ))
        #expect(controller.target == firstTarget)
        #expect(controller.phase == .cancelling)

        cancellationContinuation?.resume()
        await waitUntil { controller.phase == .cancelled }
        #expect(!controller.hasCancellationBarrier)
        #expect(controller.begin(
            target: secondTarget,
            actionID: .discuss,
            selection: nil,
            presentationID: UUID()
        ))
        await waitUntil { controller.phase == .editing }
        #expect(controller.target == secondTarget)
    }

    private func client(
        actions: [ResearchActionAvailability],
        candidates: [ResearchActionNoteSnapshot] = [],
        sourceStatus: ResearchSourceAccessStatus = .repairRequired(.missingBinding),
        prepare: @escaping @MainActor (
            ResearchActionExecutionRequest
        ) async throws -> ResearchActionPreparation = { _ in throw TestFailure.stopAfterCapture }
    ) -> ResearchActionClient {
        ResearchActionClient(
            availableActions: { _ in actions },
            materialCandidates: { _, _ in candidates },
            sourceAccess: { _ in sourceStatus },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: prepare,
            cancel: { _ in },
            openActiveDiscussion: { _ in }
        )
    }

    private func availability(
        _ id: ResearchActionID,
        role: ResearchActionTargetRole = .topic,
        order: Int,
        group: ResearchActionAvailabilityGroup = .defaultAction,
        modules: [ResearchActionModuleDefinition] = [],
        sourceRequirement: ResearchActionSourceRequirement = .none,
        enabled: Bool = true,
        repairReasons: [ResearchActionRepairReason] = []
    ) throws -> ResearchActionAvailability {
        let definition: ResearchActionDefinition
        switch id {
        case .discuss: definition = .discuss
        case .analyze: definition = .analyze
        case .synthesize: definition = .synthesize
        case .write: definition = .write
        case .critique: definition = .critique
        case .checkFidelity: definition = .checkFidelity
        case .manuscript: definition = .manuscript
        default:
            definition = try ResearchActionDefinition(
                researcherOwnedID: id,
                executionKind: .discussion
            )
        }
        let profile = try ResearchActionProfile(
            definition: definition,
            buttonName: id.rawValue,
            order: order,
            applicableRoles: [role],
            showInActions: true,
            modules: modules,
            sourceRequirement: sourceRequirement,
            capabilities: ResearchActionCapabilityDeclaration(
                readableRoles: ResearchActionTargetRole.allCases
            ),
            feedbackRequirement: .none
        )
        return try ResearchActionAvailability(
            definition: definition,
            buttonName: profile.buttonName,
            order: order,
            group: group,
            profile: ResearchActionResolvedProfileSnapshot(
                origin: .applicationDefault,
                profile: profile,
                profileRevision: profile.contentRevision(),
                profileDocumentRevision: nil
            ),
            isEnabled: enabled,
            repairReasons: repairReasons
        )
    }

    private func preparation(
        action: ResearchActionAvailability,
        target: ResearchActionNoteSnapshot,
        runID: UUID
    ) throws -> ResearchActionPreparation {
        let profile = action.profile.profile
        let parameters = try ResearchActionParameterModel(
            profile: profile,
            values: [:]
        )
        let authority = try ResearchAuthorityEnvelope(
            readableNotes: [target],
            writableNotes: [],
            writeOperations: [],
            editablePropertyKeys: []
        )
        let snapshot = try ResearchActionSnapshot(
            definition: action.definition,
            target: target,
            method: try ResearchActionMethodSnapshot(
                packageID: "working-method",
                origin: .triptych,
                version: "1",
                packageRevision: DocumentFingerprint(content: "package"),
                loadedResources: [
                    ResearchActionResourceSnapshot(
                        relativePath: "SKILL.md",
                        revision: DocumentFingerprint(content: "method")
                    ),
                ]
            ),
            resolvedProfile: action.profile,
            parameters: parameters,
            authority: authority
        )
        return ResearchActionPreparation(
            snapshot: snapshot,
            runID: runID,
            instructions: "Prepared instructions",
            state: .prepared
        )
    }

    private func target(
        title: String = "Agency",
        path: String = "Topics/Agency.md",
        role: ResearchActionTargetRole = .topic
    ) -> ResearchActionNoteSnapshot {
        ResearchActionNoteSnapshot(
            noteID: UUID(),
            note: VaultQualifiedNoteID(vaultID: UUID(), relativePath: path),
            role: role,
            lifecycle: .active,
            fingerprint: DocumentFingerprint(content: title),
            title: title
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
        case stopAfterCapture

        var errorDescription: String? { "Stopped after capturing the request." }
    }
}
