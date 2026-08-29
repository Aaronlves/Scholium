import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@MainActor
@Suite("Research Action controller", .serialized)
struct ResearchActionControllerTests {
    @Test("Resolved Platform Actions keep declared order")
    func availabilityOrder() async throws {
        let controller = ResearchActionController()
        controller.bind(client(actions: [
            try availability(.checkFidelity, order: 300),
            try availability(.discuss, order: 0),
            try availability(.synthesize, order: 100),
        ]))

        await controller.refreshAvailability(for: target())

        #expect(controller.availability.map(\.id) == [
            .discuss, .synthesize, .checkFidelity,
        ])
    }

    @Test("The common sheet separates academic values from protected Platform inputs")
    func declaredParameters() async throws {
        let requestID = try #require(ResearchAcademicFieldID(rawValue: "request"))
        let requestField = try ResearchAcademicFieldDefinition.freeText(
            id: requestID,
            label: "Request",
            requirement: .required,
            maximumTextUTF8Count: 64
        )
        let action = try availability(
            .checkFidelity,
            order: 0,
            academicInputFields: [requestField]
        )
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
            availability: action,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { controller.materialCandidates == [candidate] }

        controller.setText("Compare the arguments", field: requestField)
        controller.setFocalNote(candidate.noteID, isSelected: true)
        controller.setFidelityCheck(.content, isSelected: true)
        controller.setFidelityCheck(.citations, isSelected: true)
        #expect(controller.canPrepare)
        controller.prepare()
        await waitUntil { controller.phase == .failed }

        #expect(captured?.actionID == .checkFidelity)
        #expect(captured?.expectedProfileRevision == action.profile.profileRevision)
        #expect(captured?.expectedProfileDocumentRevision
            == action.profile.profileDocumentRevision)
        #expect(captured?.target == target)
        #expect(captured?.academicInputs.values[requestID.rawValue]
            == .freeText("Compare the arguments"))
        #expect(captured?.platformInputs.focalNotes == [candidate])
        #expect(captured?.platformInputs.fidelityChecks == [.citations, .content])
    }

    @Test("Resynthesize preselects the exact Material and preserves its revision context")
    func resynthesisContextReachesPreparation() async throws {
        let action = try availability(.synthesize, order: 100)
        let topic = target()
        let material = target(
            title: "Analysis",
            path: "Analysis.md",
            role: .analysis
        )
        let context = SynthesisMaterialChangedAttentionContext(
            triptychID: UUID(),
            recordID: UUID(),
            topicNoteID: topic.noteID,
            materialNoteID: material.noteID,
            material: VaultNoteReference(
                vaultID: material.note.vaultID,
                vaultName: "Analyses",
                vaultRole: .sourceCorpus,
                relativePath: material.note.relativePath,
                stableNoteID: material.noteID.uuidString.lowercased()
            ),
            recordedRevision: DocumentFingerprint(content: "recorded"),
            currentRevision: material.fingerprint
        )
        var capturedContext: SynthesisMaterialChangedAttentionContext?
        var capturedRequest: ResearchActionExecutionRequest?
        let controller = ResearchActionController()
        controller.bind(ResearchActionClient(
            availableActions: { _ in [action] },
            materialCandidates: { _, _ in [material] },
            sourceAccess: { _ in .repairRequired(.missingBinding) },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: { request, context in
                capturedRequest = request
                capturedContext = context
                throw TestFailure.stopAfterCapture
            },
            cancel: { _ in },
            openActiveDiscussion: { _ in }
        ))

        #expect(controller.begin(
            target: topic,
            availability: action,
            selection: nil,
            initialMaterialNoteIDs: [material.noteID],
            resynthesisContext: context,
            presentationID: UUID()
        ))
        await waitUntil { controller.materialCandidates == [material] }
        #expect(controller.selectedFocalNoteIDs == [material.noteID])
        #expect(controller.canPrepare)
        controller.prepare()
        await waitUntil { controller.phase == .failed }
        #expect(capturedContext == context)
        #expect(capturedRequest?.platformInputs.focalNotes == [material])
    }

    @Test("Single-choice academic fields replace the prior value")
    func singleSelectionReplacement() async throws {
        let choiceID = try #require(ResearchAcademicFieldID(rawValue: "approach"))
        let choiceField = try ResearchAcademicFieldDefinition.singleChoice(
            id: choiceID,
            label: "Approach",
            requirement: .required,
            choices: [
                try ResearchAcademicChoice(value: "first", label: "First"),
                try ResearchAcademicChoice(value: "second", label: "Second"),
            ]
        )
        let controller = ResearchActionController()
        let action = try availability(
            .discuss,
            order: 0,
            academicInputFields: [choiceField]
        )
        controller.bind(client(actions: [action]))
        controller.begin(
            target: target(),
            availability: action,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { controller.phase == .editing }

        #expect(controller.choiceValues[choiceID.rawValue]?.isEmpty == true)
        controller.setChoice("first", isSelected: true, field: choiceField)
        controller.setChoice("second", isSelected: true, field: choiceField)

        #expect(controller.choiceValues[choiceID.rawValue] == ["second"])
    }

    @Test("A required source remains fail closed until machine-local access is available")
    func sourceRequirement() async throws {
        let unavailableAction = try availability(
            .analyze,
            role: .analysis,
            order: 100,
            enabled: false,
            repairReasons: [ResearchActionRepairReason(code: .sourceAccessRequired)]
        )
        let availableAction = try availability(
            .analyze,
            role: .analysis,
            order: 100
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
            prepare: { _, _ in throw TestFailure.stopAfterCapture },
            cancel: { _ in },
            openActiveDiscussion: { _ in }
        ))

        controller.begin(
            target: target(role: .analysis),
            availability: unavailableAction,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { controller.sourceStatus != nil }

        #expect(controller.sourceStatus?.state == .repairRequired)
        #expect(!controller.canPrepare)
        #expect(controller.activeAvailability?.canPresentInInterface == true)

        controller.bindLocalSource(URL(fileURLWithPath: "/Source.pdf"))
        await waitUntil { !controller.isBindingSource }

        #expect(controller.sourceStatus == .available(reference))
        #expect(controller.activeAvailability?.isEnabled == true)
        #expect(controller.canPrepare)
    }

    @Test("Protected selector dependencies load independently and block preparation until settled")
    func moduleLoadsAreIndependent() async throws {
        let action = try availability(
            .analyze,
            role: .analysis,
            order: 100
        )
        let controller = ResearchActionController()
        controller.bind(ResearchActionClient(
            availableActions: { _ in [action] },
            materialCandidates: { _, _ in throw TestFailure.stopAfterCapture },
            sourceAccess: { _ in .repairRequired(.missingBinding) },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: { _, _ in throw TestFailure.stopAfterCapture },
            cancel: { _ in },
            openActiveDiscussion: { _ in }
        ))

        controller.begin(
            target: target(role: .analysis),
            availability: action,
            selection: nil,
            presentationID: UUID()
        )
        #expect(controller.isLoadingMaterialCandidates)
        #expect(controller.isLoadingSourceStatus)
        #expect(!controller.canPrepare)
        await waitUntil {
            !controller.isLoadingMaterialCandidates && !controller.isLoadingSourceStatus
        }

        #expect(controller.sourceStatus?.state == .repairRequired)
        #expect(controller.errorMessage == TestFailure.stopAfterCapture.localizedDescription)
        #expect(!controller.canPrepare)
    }

    @Test("Changing Target invalidates the open Action draft")
    func targetChangeInvalidatesDraft() async throws {
        let controller = ResearchActionController()
        let action = try availability(.synthesize, order: 100)
        controller.bind(client(actions: [action]))
        controller.begin(
            target: target(),
            availability: action,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { controller.canPrepare }

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
            prepare: { _, _ in throw TestFailure.stopAfterCapture },
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
        let action = try availability(.discuss, order: 0)
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
            prepare: { _, _ in throw TestFailure.stopAfterCapture },
            cancel: { _ in },
            openActiveDiscussion: { _ in }
        ))

        controller.begin(
            target: firstTarget,
            availability: action,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { firstContinuation != nil }
        controller.begin(
            target: secondTarget,
            availability: action,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { controller.materialCandidates == [secondMaterial] }
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
            prepare: { _, _ in throw TestFailure.stopAfterCapture },
            cancel: { _ in },
            openActiveDiscussion: { _ in }
        ))

        await controller.refreshAvailability(for: target())

        #expect(controller.availability.isEmpty)
        #expect(!controller.isRefreshingAvailability)
        #expect(controller.availabilityError == TestFailure.stopAfterCapture.localizedDescription)
    }

    @Test("Opening a sheet reuses the visible Profile without a second availability lookup")
    func sheetReusesVisibleProfile() async throws {
        let action = try availability(.synthesize, order: 100)
        var resolutionCount = 0
        let controller = ResearchActionController()
        controller.bind(ResearchActionClient(
            availableActions: { _ in
                resolutionCount += 1
                return [action]
            },
            materialCandidates: { _, _ in [] },
            sourceAccess: { _ in .repairRequired(.missingBinding) },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: { _, _ in throw TestFailure.stopAfterCapture },
            cancel: { _ in },
            openActiveDiscussion: { _ in }
        ))
        let target = target()

        await controller.refreshAvailability(for: target)
        #expect(controller.activeAvailability == nil)
        #expect(controller.availability.map(\.id) == [.synthesize])

        controller.begin(
            target: target,
            availability: action,
            selection: nil,
            presentationID: UUID()
        )
        #expect(controller.phase == .editing)

        #expect(controller.availability.map(\.id) == [.synthesize])
        #expect(controller.activeAvailability == action)
        #expect(controller.profile == action.profile.profile)
        #expect(controller.availabilityError == nil)
        #expect(resolutionCount == 1)
    }

    @Test("Dismissing a sheet while selector data loads preserves launcher availability")
    func cancelledDependencyLoadPreservesLauncherAvailability() async throws {
        let action = try availability(.synthesize, order: 100)
        var dependencyContinuation: CheckedContinuation<
            [ResearchActionNoteSnapshot],
            Never
        >?
        let controller = ResearchActionController()
        controller.bind(ResearchActionClient(
            availableActions: { _ in [action] },
            materialCandidates: { _, _ in
                return await withCheckedContinuation { continuation in
                    dependencyContinuation = continuation
                }
            },
            sourceAccess: { _ in .repairRequired(.missingBinding) },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: { _, _ in throw TestFailure.stopAfterCapture },
            cancel: { _ in },
            openActiveDiscussion: { _ in }
        ))
        let target = target()
        await controller.refreshAvailability(for: target)

        controller.begin(
            target: target,
            availability: action,
            selection: nil,
            presentationID: UUID()
        )
        await waitUntil { dependencyContinuation != nil }
        #expect(controller.phase == .editing)
        controller.dismiss()

        #expect(controller.availability.map(\.id) == [.synthesize])
        #expect(controller.profile == nil)
        dependencyContinuation?.resume(returning: [])
        try? await Task.sleep(for: .milliseconds(20))
        #expect(controller.availability.map(\.id) == [.synthesize])
        #expect(!controller.isPresented)
    }

    @Test("A late undelivered Run cleans up without blocking another Action")
    func dismissedPreparationCancellationDoesNotBlock() async throws {
        let action = try availability(.discuss, order: 0)
        let firstTarget = target(title: "First", path: "Topics/First.md")
        let secondTarget = target(title: "Second", path: "Topics/Second.md")
        let runID = UUID()
        let result = try preparation(
            action: action,
            target: firstTarget,
            runID: runID
        )
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
            prepare: { _, _ in
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
            target: firstTarget,
            availability: action,
            selection: nil,
            presentationID: presentationID
        )
        await waitUntil { controller.canPrepare }

        controller.prepare()
        await waitUntil { preparationContinuation != nil }
        #expect(controller.phase == .preparing)
        controller.dismiss(presentationID: presentationID)
        #expect(!controller.hasCancellationBarrier)
        #expect(controller.pendingCancellationBarrierCount == 0)
        #expect(controller.begin(
            target: secondTarget,
            availability: action,
            selection: nil,
            presentationID: UUID()
        ))
        await waitUntil { controller.phase == .editing }

        preparationContinuation?.resume(returning: result)
        await waitUntil { cancelledRunIDs == [runID] }

        #expect(controller.preparation == nil)
        #expect(controller.target == secondTarget)
        #expect(cancelledRunIDs == [runID])
        #expect(controller.cancellationRecoveries.isEmpty)
        #expect(!controller.hasCancellationBarrier)
    }

    @Test("Invalidation before handoff delivery cannot leave a global barrier")
    func dismissedHandoffDeliveryDoesNotBlock() async throws {
        let action = try availability(.discuss, order: 0)
        let firstTarget = target(title: "First", path: "Topics/First.md")
        let secondTarget = target(title: "Second", path: "Topics/Second.md")
        let runID = UUID()
        let result = try preparation(
            action: action,
            target: firstTarget,
            runID: runID
        )
        var handoffContinuation: CheckedContinuation<ResearchAgentHandoff, Never>?
        var cancelledRunIDs: [UUID] = []
        let controller = ResearchActionController()
        controller.bind(ResearchActionClient(
            availableActions: { _ in [action] },
            materialCandidates: { _, _ in [] },
            sourceAccess: { _ in .repairRequired(.missingBinding) },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: { _, _ in result },
            handoff: { _ in
                await withCheckedContinuation { continuation in
                    handoffContinuation = continuation
                }
            },
            cancel: { cancelledRunIDs.append($0) },
            openActiveDiscussion: { _ in }
        ))
        let presentationID = UUID()
        #expect(controller.begin(
            target: firstTarget,
            availability: action,
            selection: nil,
            presentationID: presentationID
        ))
        await waitUntil { controller.canPrepare }
        controller.prepare()
        await waitUntil { handoffContinuation != nil }
        #expect(controller.phase == .preparing)
        #expect(controller.preparation?.runID == runID)

        controller.dismiss(presentationID: presentationID)
        #expect(!controller.hasCancellationBarrier)
        #expect(controller.pendingCancellationBarrierCount == 0)
        #expect(controller.begin(
            target: secondTarget,
            availability: action,
            selection: nil,
            presentationID: UUID()
        ))
        await waitUntil { controller.phase == .editing }

        handoffContinuation?.resume(returning: try testHandoff(runID: runID))
        await waitUntil { cancelledRunIDs == [runID] }
        #expect(controller.target == secondTarget)
        #expect(controller.agentHandoff == nil)
        #expect(controller.cancellationRecoveries.isEmpty)
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
            prepare: { _, _ in result },
            handoff: { try testHandoff(runID: $0) },
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
            availability: action,
            selection: nil,
            presentationID: presentationID
        )
        await waitUntil { controller.canPrepare }
        controller.prepare()
        await waitUntil { controller.phase == .prepared }
        #expect(controller.phase == .prepared)
        #expect(controller.errorMessage == nil)

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
            prepare: { _, _ in
                await withCheckedContinuation { continuation in
                    preparationContinuation = continuation
                }
            },
            handoff: { try testHandoff(runID: $0) },
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
            availability: action,
            selection: nil,
            presentationID: firstPresentationID
        ))
        await waitUntil { controller.canPrepare }

        controller.prepare()
        await waitUntil { preparationContinuation != nil }
        #expect(!controller.hasCancellationBarrier)
        #expect(!controller.begin(
            target: secondTarget,
            availability: action,
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
            availability: action,
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
            availability: action,
            selection: nil,
            presentationID: UUID()
        ))
        await waitUntil { controller.phase == .editing }
        #expect(controller.target == secondTarget)
    }

    @Test("A prepared Run can replace only its short pairing handoff")
    func regeneratePairingHandoff() async throws {
        let action = try availability(.discuss, order: 0)
        let target = target()
        let runID = UUID()
        let result = try preparation(action: action, target: target, runID: runID)
        let codes = [
            "23456789ABCDEFGHJKLMNPQR",
            "98765432RQPONMLKJHGFEDCB",
        ]
        var handoffCount = 0
        let controller = ResearchActionController()
        controller.bind(ResearchActionClient(
            availableActions: { _ in [action] },
            materialCandidates: { _, _ in [] },
            sourceAccess: { _ in .repairRequired(.missingBinding) },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: { _, _ in result },
            handoff: { _ in
                let code = try #require(ResearchPairingCode(
                    rawValue: codes[handoffCount]
                ))
                handoffCount += 1
                return ResearchAgentHandoff(
                    triptychID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    run: ResearchRunLocator(rawValue: "controllerfixturelocator")!,
                    pairingCode: code,
                    expiresAt: .distantFuture
                )
            },
            cancel: { _ in },
            openActiveDiscussion: { _ in }
        ))
        #expect(controller.begin(
            target: target,
            availability: action,
            selection: nil,
            presentationID: UUID()
        ))
        await waitUntil { controller.canPrepare }
        controller.prepare()
        await waitUntil { controller.phase == .prepared }
        let first = try #require(controller.agentHandoff)

        controller.regenerateHandoff()
        await waitUntil {
            controller.phase == .prepared
                && controller.agentHandoff?.pairingCode != first.pairingCode
        }

        #expect(controller.preparation?.runID == runID)
        #expect(handoffCount == 2)
    }

    @Test("Agent-chosen Continue Research is projected beneath the parent Action")
    func continueResearchBelongsToParentAction() async throws {
        let action = try availability(.synthesize, order: 0)
        let target = target()
        let runID = UUID()
        let prepared = try preparation(action: action, target: target, runID: runID)
        let controller = ResearchActionController()
        controller.bind(client(actions: [action], prepare: { _ in prepared }))
        #expect(controller.begin(
            target: target,
            availability: action,
            selection: nil,
            presentationID: UUID()
        ))
        await waitUntil { controller.canPrepare }
        controller.prepare()
        await waitUntil { controller.phase == .prepared }

        let parent = try portableActionRecord(
            id: runID,
            snapshot: prepared.snapshot
        )
        let child = try portableActionRecord(
            id: UUID(),
            snapshot: prepared.snapshot,
            continuationLineage: ResearchContinuationLineage(
                groupID: UUID(),
                parentRunID: runID,
                requestID: UUID(),
                kind: .continueResearch
            )
        )

        controller.receive(records: [child, parent])
        #expect(controller.resultRecord?.id == runID)
        #expect(controller.continuationRecords.map(\.id) == [child.id])

        controller.receive(records: [parent])
        #expect(controller.continuationRecords.isEmpty)
    }

    @Test("An activity opens a compact status presentation without rebuilding academic input")
    func activityStatusPresentation() async throws {
        let action = try availability(.synthesize, order: 100)
        let target = target()
        let runID = UUID()
        let prepared = try preparation(action: action, target: target, runID: runID)
        let waiting = researchActivity(
            runID: runID,
            actionID: action.id,
            targetNoteID: target.noteID,
            state: .waitingForAgent,
            updatedAt: 10
        )
        var actionRunRequests: [UUID] = []
        var handoffRequests: [UUID] = []
        var cancelledRunIDs: [UUID] = []
        let controller = ResearchActionController()
        controller.bind(ResearchActionClient(
            availableActions: { _ in throw TestFailure.stopAfterCapture },
            materialCandidates: { _, _ in throw TestFailure.stopAfterCapture },
            sourceAccess: { _ in throw TestFailure.stopAfterCapture },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: { _, _ in throw TestFailure.stopAfterCapture },
            actionRun: {
                actionRunRequests.append($0)
                return prepared
            },
            handoff: {
                handoffRequests.append($0)
                return try testHandoff(runID: $0)
            },
            cancel: { cancelledRunIDs.append($0) },
            openActiveDiscussion: { _ in }
        ))

        #expect(controller.beginStatus(
            target: target,
            availability: action,
            activity: waiting,
            presentationID: UUID()
        ))
        await waitUntil { controller.phase == .prepared }

        #expect(controller.isStatusPresentation)
        #expect(controller.statusActivity == waiting)
        #expect(controller.textValues.isEmpty)
        #expect(controller.selectedFocalNoteIDs.isEmpty)
        #expect(actionRunRequests == [runID])

        controller.receive(activities: [waiting])
        controller.regenerateHandoff()
        await waitUntil { controller.agentHandoff != nil }
        #expect(handoffRequests == [runID])

        controller.endActivity(runID: runID)
        await waitUntil { cancelledRunIDs == [runID] }
        #expect(controller.cancellationRecoveries.isEmpty)
    }

    @Test("A failed compact-status recopy remains retryable on the same Run")
    func activityStatusRecopyRetries() async throws {
        let action = try availability(.synthesize, order: 100)
        let target = target()
        let runID = UUID()
        let prepared = try preparation(action: action, target: target, runID: runID)
        let waiting = researchActivity(
            runID: runID,
            actionID: action.id,
            targetNoteID: target.noteID,
            state: .waitingForAgent,
            updatedAt: 10
        )
        var handoffAttempt = 0
        let controller = ResearchActionController()
        controller.bind(ResearchActionClient(
            availableActions: { _ in [] },
            materialCandidates: { _, _ in [] },
            sourceAccess: { _ in .repairRequired(.missingBinding) },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: { _, _ in throw TestFailure.stopAfterCapture },
            actionRun: { _ in prepared },
            handoff: {
                handoffAttempt += 1
                if handoffAttempt == 1 { throw TestFailure.stopAfterCapture }
                return try testHandoff(runID: $0)
            },
            cancel: { _ in },
            openActiveDiscussion: { _ in }
        ))
        #expect(controller.beginStatus(
            target: target,
            availability: action,
            activity: waiting,
            presentationID: UUID()
        ))
        await waitUntil { controller.phase == .prepared }

        controller.regenerateHandoff()
        await waitUntil { controller.phase == .failed }
        #expect(controller.canEndPreparedRun)
        #expect(controller.canResumePreparedRun)
        #expect(controller.agentHandoff == nil)

        controller.receive(activities: [researchActivity(
            runID: runID,
            actionID: action.id,
            targetNoteID: target.noteID,
            state: .running,
            repairReason: .resultRequired,
            updatedAt: 20
        )])
        #expect(!controller.canEndPreparedRun)
        #expect(controller.canResumePreparedRun)

        controller.retryHandoff()
        await waitUntil { controller.phase == .prepared }
        #expect(controller.agentHandoff != nil)
        #expect(handoffAttempt == 2)
        #expect(controller.preparation?.runID == runID)
    }

    private func client(
        actions: [ResearchActionAvailability],
        candidates: [ResearchActionNoteSnapshot] = [],
        sourceStatus: ResearchSourceAccessStatus = .repairRequired(.missingBinding),
        prepare: @escaping @MainActor (
            ResearchActionExecutionRequest
        ) async throws -> ResearchActionPreparation = { _ in
            throw TestFailure.stopAfterCapture
        }
    ) -> ResearchActionClient {
        ResearchActionClient(
            availableActions: { _ in actions },
            materialCandidates: { _, _ in candidates },
            sourceAccess: { _ in sourceStatus },
            bindLocalSource: { _, _ in throw TestFailure.stopAfterCapture },
            prepare: { request, _ in try await prepare(request) },
            handoff: { try testHandoff(runID: $0) },
            cancel: { _ in },
            openActiveDiscussion: { _ in }
        )
    }

    private func testHandoff(runID: UUID) throws -> ResearchAgentHandoff {
        ResearchAgentHandoff(
            triptychID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            run: ResearchRunLocator(rawValue: "controllerfixturelocator")!,
            pairingCode: ResearchPairingCode(
                rawValue: "23456789ABCDEFGHJKLMNPQR"
            )!,
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func availability(
        _ id: ResearchActionID,
        role: ResearchActionTargetRole = .topic,
        order: Int,
        academicInputFields: [ResearchAcademicFieldDefinition] = [],
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
        }
        let resultField = try ResearchAcademicFieldDefinition.freeText(
            id: .academicOutcome,
            label: "Academic Outcome",
            requirement: .required
        )
        let profile = try ResearchAcademicActionProfile(
            actionID: id,
            displayName: id.rawValue,
            order: order,
            isEnabled: enabled,
            applicableRoles: [role],
            academicInputFields: academicInputFields,
            academicResultFields: [resultField]
        )
        return try ResearchActionAvailability(
            definition: definition,
            buttonName: profile.displayName,
            order: order,
            profile: ResearchActionResolvedProfileSnapshot(
                profile: profile,
                profileRevision: try profile.contentRevision(),
                profileDocumentRevision: DocumentFingerprint(content: "profiles")
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
        let registration = try ResearchSkillRegistration(
            key: ResearchSkillRegistrationKey(
                rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000008")!
            ),
            actionID: action.id,
            displayName: action.buttonName,
            primaryMarkdown: .machineLocal()
        )
        let authority = try ResearchAuthorityEnvelope(
            readableNotes: [target],
            writableNotes: [],
            writeOperations: [],
            editableMetadataKeys: []
        )
        let snapshot = try ResearchActionSnapshot(
            definition: action.definition,
            target: target,
            method: try ResearchMethodSnapshot(
                registration: registration,
                primaryMarkdownSource: "# Method\n\nExact controller fixture.\n"
            ),
            resolvedProfile: action.profile,
            platformInputs: try ResearchActionPlatformInputs(),
            academicInputs: try ResearchAcademicFieldValues(
                values: [:],
                definitions: profile.academicInputFields
            ),
            resultContract: try ResearchResultContract(
                profile: profile,
                registrationKey: registration.key,
                profileRevision: action.profile.profileRevision
            ),
            authority: authority
        )
        return ResearchActionPreparation(
            snapshot: snapshot,
            runID: runID,
            instructions: "Prepared instructions",
            state: .prepared
        )
    }

    private func portableActionRecord(
        id: UUID,
        snapshot: ResearchActionSnapshot,
        continuationLineage: ResearchContinuationLineage? = nil
    ) throws -> PortableResearchRecord {
        let target = snapshot.target
        let participant = try PortableResearchNoteRevision(
            noteID: target.noteID,
            note: target.note,
            role: target.role,
            title: target.title,
            startingRevision: target.fingerprint,
            endingRevision: target.fingerprint
        )
        return try PortableResearchRecord(
            id: id,
            triptychID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            title: try ResearchRecordTitle("Controller test result"),
            kind: .action,
            action: try ResearchActionRecordIdentity(snapshot: snapshot),
            method: PortableResearchMethodReference(snapshot: snapshot),
            continuationLineage: continuationLineage,
            primaryNoteID: target.noteID,
            participatingNotes: [participant],
            statements: [],
            fidelityCompletion: .notRequired,
            startedAt: Date(timeIntervalSince1970: 100),
            finishedAt: Date(timeIntervalSince1970: 100)
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
            fingerprint: DocumentFingerprint(content: title),
            title: title
        )
    }

    private func researchActivity(
        runID: UUID = UUID(),
        actionID: ResearchActionID,
        targetNoteID: UUID,
        state: WorkspaceResearchActivityState,
        recordID: UUID? = nil,
        fingerprint: DocumentFingerprint? = nil,
        repairReason: WorkspaceResearchActivityRepairReason? = nil,
        updatedAt: TimeInterval
    ) -> WorkspaceResearchActivity {
        WorkspaceResearchActivity(
            runID: runID,
            actionID: actionID,
            targetNoteID: targetNoteID,
            state: state,
            recordID: recordID,
            recordFingerprint: fingerprint,
            repairReason: repairReason,
            updatedAt: Date(timeIntervalSinceReferenceDate: updatedAt)
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
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
