import Foundation
import ScholiumContracts
import ScholiumCore

struct WorkspaceResearchMethodImprovementDependencies: Sendable {
    let portableResearchRecordStore: PortableResearchRecordStore
    let localResearchExecutionStore: LocalResearchExecutionStore
    let researchAgentSessions: ResearchAgentSessionAuthority?
}

extension WorkspaceServices {
    var researchMethodImprovementDependencies:
        WorkspaceResearchMethodImprovementDependencies {
        WorkspaceResearchMethodImprovementDependencies(
            portableResearchRecordStore: portableResearchRecordStore,
            localResearchExecutionStore: localResearchExecutionStore,
            researchAgentSessions: researchAgentSessions
        )
    }
}

extension WorkspaceRuntime {
    public func researchMethodImprovementContext(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchMethodImprovementContext {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            allowFinalized: true
        )
        let handle = try await openWorkspace(id: authenticated.triptychID)
        return try await handle.authenticatedMethodImprovementContext(
            credential: credential,
            run: run
        )
    }

    public func submitResearchMethodImprovement(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        submission: ResearchMethodImprovementSubmission
    ) async throws -> ResearchMethodImprovementReceipt {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: submission.disposition == .replace,
            allowFinalized: true
        )
        let handle = try await openWorkspace(id: authenticated.triptychID)
        return try await handle.submitMethodImprovement(
            credential: credential,
            run: run,
            submission: submission
        )
    }
}

extension ResearchOperations {
    public func issueMethodImprovementHandoff(
        recordID: UUID,
        validity: TimeInterval = 10 * 60
    ) async throws -> ResearchAgentHandoff {
        let handle = try await reference.requireHandle()
        return try await handle.issueMethodImprovementHandoff(
            recordID: recordID,
            validity: validity
        )
    }

    public func methodImprovementContext(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchMethodImprovementContext {
        let handle = try await reference.requireHandle()
        return try await handle.authenticatedMethodImprovementContext(
            credential: credential,
            run: run
        )
    }

    public func submitMethodImprovement(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        submission: ResearchMethodImprovementSubmission
    ) async throws -> ResearchMethodImprovementReceipt {
        let handle = try await reference.requireHandle()
        return try await handle.submitMethodImprovement(
            credential: credential,
            run: run,
            submission: submission
        )
    }
}

extension WorkspaceHandle {
    func issueMethodImprovementHandoff(
        recordID: UUID,
        validity: TimeInterval
    ) async throws -> ResearchAgentHandoff {
        try requireActive()
        let portable = try await researchMethodImprovementDependencies.portableResearchRecordStore.record(
            id: recordID
        )
        guard let comment = portable.methodFeedbackComment,
              let methodReference = portable.method,
              let actionID = portable.action?.actionID else {
            throw ResearchMethodImprovementError.runUnavailable
        }
        let resultFingerprint = try portable.finalizedResultFingerprint()
        let parent = try await researchMethodImprovementDependencies.localResearchExecutionStore.record(
            id: recordID
        )
        guard parent.completion.map({
            [.complete, .unverified].contains($0.state)
        }) == true,
        parent.resultPayload != nil,
        parent.snapshot.actionSnapshot.method.registration.key
            == methodReference.registrationKey,
        parent.snapshot.actionSnapshot.actionID == actionID else {
            throw ResearchMethodImprovementError.runUnavailable
        }
        let method = try await currentResearchMethod(for: actionID)
        guard method.registration.key == methodReference.registrationKey,
              method.registration.isEnabled else {
            throw ResearchMethodImprovementError.methodChanged
        }

        let runID = Self.stableMethodImprovementRunID(
            recordID: recordID,
            feedbackRevision: comment.revision
        )
        let improvement: ResearchMethodImprovementRun
        if let existing = parent.methodImprovementRun,
           existing.id == runID,
           existing.feedbackRevision == comment.revision,
           existing.expectedResultFingerprint == resultFingerprint,
           existing.state != .completed,
           existing.state != .cancelled {
            improvement = existing
        } else {
            if let previous = parent.methodImprovementRun,
               previous.id != runID,
               previous.state == .writing {
                throw ResearchMethodImprovementError.runUnavailable
            }
            improvement = try ResearchMethodImprovementRun(
                id: runID,
                parentRecordID: recordID,
                triptychID: self.id,
                registrationKey: methodReference.registrationKey,
                actionID: actionID,
                method: method,
                feedbackRevision: comment.revision,
                feedbackText: comment.text,
                expectedResultFingerprint: resultFingerprint
            )
            if let previous = parent.methodImprovementRun,
               previous.id != runID {
                await researchMethodImprovementDependencies.researchAgentSessions?.revokeRun(previous.id)
            }
            _ = try await researchMethodImprovementDependencies.localResearchExecutionStore
                .installMethodImprovement(improvement)
        }
        guard let sessions = researchMethodImprovementDependencies.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        return try await sessions.issuePairing(
            runID: improvement.id,
            triptychID: self.id,
            canWrite: true,
            validity: validity
        )
    }

    func authenticatedMethodImprovementContext(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchMethodImprovementContext {
        try requireActive()
        guard let sessions = researchMethodImprovementDependencies.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            allowFinalized: true
        )
        guard authenticated.triptychID == self.id else {
            throw ResearchAgentSessionError.sessionRejected
        }
        let improvement = try await researchMethodImprovementDependencies.localResearchExecutionStore
            .methodImprovement(id: authenticated.runID)
        guard improvement.triptychID == self.id,
              improvement.state == .prepared || improvement.state == .writing
        else { throw ResearchMethodImprovementError.runUnavailable }
        try await validateCurrentMethodImprovementOwners(improvement)
        return try ResearchMethodImprovementContext(
            run: run,
            improvement: improvement
        )
    }

    func submitMethodImprovement(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        submission: ResearchMethodImprovementSubmission
    ) async throws -> ResearchMethodImprovementReceipt {
        try requireActive()
        guard let sessions = researchMethodImprovementDependencies.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: submission.disposition == .replace,
            allowFinalized: true
        )
        guard authenticated.triptychID == self.id else {
            throw ResearchAgentSessionError.sessionRejected
        }
        var improvement = try await researchMethodImprovementDependencies.localResearchExecutionStore
            .methodImprovement(id: authenticated.runID)
        let fingerprint = try submission.contentFingerprint()
        if improvement.state == .completed {
            guard improvement.submissionFingerprint == fingerprint,
                  let receipt = improvement.receipt else {
                throw ResearchMethodImprovementError.resultAlreadySubmitted
            }
            await sessions.finalizeRun(improvement.id)
            return receipt
        }
        guard improvement.state == .prepared || improvement.state == .writing,
              submission.feedbackRevision == improvement.feedbackRevision,
              submission.expectedResultFingerprint
                == improvement.expectedResultFingerprint,
              let frozenTarget = try ResearchMethodImprovementContext(
                run: run,
                improvement: improvement
              ).targets.first(where: { $0.id == submission.targetID }),
              submission.expectedTargetRevision == frozenTarget.revision else {
            throw ResearchMethodImprovementError.invalidContract
        }
        let wasPrepared = improvement.state == .prepared
        if !wasPrepared {
            guard improvement.submissionFingerprint == fingerprint,
                  improvement.pendingSubmission == submission else {
                throw ResearchMethodImprovementError.resultAlreadySubmitted
            }
        }

        var portableState = try await methodImprovementRecordState(improvement)
        var currentMethod = try await currentResearchMethod(
            for: improvement.actionID
        )
        guard currentMethod.registration.key == improvement.registrationKey,
              currentMethod.registration.isEnabled else {
            throw ResearchMethodImprovementError.methodChanged
        }
        var currentTarget = try Self.methodImprovementTarget(
            id: submission.targetID,
            in: currentMethod
        )
        let intendedRevision = submission.replacementSource.map(
            DocumentFingerprint.init(content:)
        )
        if wasPrepared {
            guard portableState.feedback == .current else {
                throw ResearchMethodImprovementError.feedbackChanged
            }
            guard currentTarget.revision == submission.expectedTargetRevision else {
                throw ResearchMethodImprovementError.methodChanged
            }
            if submission.disposition == .replace,
               intendedRevision == submission.expectedTargetRevision {
                throw ResearchMethodImprovementError.invalidContract
            }
            _ = try await researchMethodImprovementDependencies.localResearchExecutionStore
                .beginMethodImprovement(
                    runID: improvement.id,
                    submission: submission,
                    submissionFingerprint: fingerprint
                )
            improvement = try await researchMethodImprovementDependencies.localResearchExecutionStore
                .methodImprovement(id: improvement.id)
            portableState = try await methodImprovementRecordState(improvement)
            currentMethod = try await currentResearchMethod(
                for: improvement.actionID
            )
            currentTarget = try Self.methodImprovementTarget(
                id: submission.targetID,
                in: currentMethod
            )
            if portableState.feedback != .current,
               currentTarget.revision == submission.expectedTargetRevision {
                _ = try await researchMethodImprovementDependencies.localResearchExecutionStore
                    .cancelMethodImprovement(runID: improvement.id)
                await sessions.revokeRun(improvement.id)
                throw ResearchMethodImprovementError.feedbackChanged
            }
            if currentTarget.revision != submission.expectedTargetRevision,
               currentTarget.revision != intendedRevision {
                _ = try await researchMethodImprovementDependencies.localResearchExecutionStore
                    .cancelMethodImprovement(runID: improvement.id)
                await sessions.revokeRun(improvement.id)
                throw ResearchMethodImprovementError.methodChanged
            }
        }
        let portable = portableState.record
        let endingRevision: DocumentFingerprint
        switch submission.disposition {
        case .replace:
            guard let replacement = submission.replacementSource,
                  intendedRevision != submission.expectedTargetRevision else {
                throw ResearchMethodImprovementError.invalidContract
            }
            if currentTarget.revision == intendedRevision {
                endingRevision = currentTarget.revision
            } else {
                guard currentTarget.revision == submission.expectedTargetRevision else {
                    throw ResearchMethodImprovementError.methodChanged
                }
                guard portableState.feedback == .current else {
                    throw ResearchMethodImprovementError.feedbackChanged
                }
                let capability = try await sessions.issueMethodWriteCapability(
                    credential: credential,
                    run: run,
                    targetID: submission.targetID,
                    expectedRevision: submission.expectedTargetRevision,
                    requestID: submission.requestID
                )
                try await sessions.consumeMethodWriteCapability(
                    capability,
                    credential: credential,
                    run: run,
                    targetID: submission.targetID,
                    expectedRevision: submission.expectedTargetRevision,
                    requestID: submission.requestID
                )
                endingRevision = try await replaceMethodImprovementTarget(
                    currentTarget,
                    registrationKey: improvement.registrationKey,
                    source: replacement,
                    expectedRevision: submission.expectedTargetRevision
                )
            }
        case .diagnosedNoChange, .unavailable:
            guard currentTarget.revision == submission.expectedTargetRevision else {
                throw ResearchMethodImprovementError.methodChanged
            }
            guard portableState.feedback == .current else {
                throw ResearchMethodImprovementError.feedbackChanged
            }
            endingRevision = currentTarget.revision
        }

        let feedbackCleared: Bool
        switch portableState.feedback {
        case .absent:
            feedbackCleared = true
        case .changed:
            guard submission.disposition == .replace else {
                throw ResearchMethodImprovementError.feedbackChanged
            }
            feedbackCleared = false
        case .current:
            do {
                _ = try await researchMethodImprovementDependencies.portableResearchRecordStore
                    .saveResearcherResponse(
                        try ResearcherResponseDraft(
                            evaluation: try portable.researcherEvaluation.map(
                                ResearcherEvaluationDraft.init
                            ),
                            methodFeedbackText: nil
                        ),
                        recordID: portable.id,
                        expectedEvaluationRevision:
                            portable.researcherEvaluation?.revision,
                        expectedMethodFeedbackRevision: improvement.feedbackRevision,
                        expectedResultFingerprint:
                            improvement.expectedResultFingerprint
                    )
                feedbackCleared = true
            } catch {
                if submission.disposition != .replace { throw error }
                feedbackCleared = false
            }
        }
        let receipt = try ResearchMethodImprovementReceipt(
            runID: improvement.id,
            requestID: submission.requestID,
            disposition: submission.disposition,
            targetID: submission.targetID,
            startingRevision: submission.expectedTargetRevision,
            endingRevision: endingRevision,
            feedbackCleared: feedbackCleared,
            diagnosis: submission.diagnosis
        )
        _ = try await researchMethodImprovementDependencies.localResearchExecutionStore
            .completeMethodImprovement(
                runID: improvement.id,
                submissionFingerprint: fingerprint,
                receipt: receipt
            )
        await sessions.finalizeRun(improvement.id)
        return receipt
    }

    private func validateCurrentMethodImprovementOwners(
        _ improvement: ResearchMethodImprovementRun
    ) async throws {
        let state = try await methodImprovementRecordState(improvement)
        guard state.feedback == .current else {
            throw ResearchMethodImprovementError.feedbackChanged
        }
        let method = try await currentResearchMethod(for: improvement.actionID)
        guard method.registration.key == improvement.registrationKey,
              method.registration.isEnabled else {
            throw ResearchMethodImprovementError.methodChanged
        }
    }

    private enum MethodFeedbackCurrentness: Equatable {
        case current
        case absent
        case changed
    }

    private func methodImprovementRecordState(
        _ improvement: ResearchMethodImprovementRun
    ) async throws -> (
        record: PortableResearchRecord,
        feedback: MethodFeedbackCurrentness
    ) {
        let record = try await researchMethodImprovementDependencies.portableResearchRecordStore.record(
            id: improvement.parentRecordID
        )
        guard record.method?.registrationKey == improvement.registrationKey,
              record.action?.actionID == improvement.actionID else {
            throw ResearchMethodImprovementError.runUnavailable
        }
        guard try record.finalizedResultFingerprint()
                == improvement.expectedResultFingerprint else {
            throw ResearchMethodImprovementError.resultChanged
        }
        let feedback: MethodFeedbackCurrentness
        if record.methodFeedbackComment?.revision == improvement.feedbackRevision,
           record.methodFeedbackComment?.text == improvement.feedbackText {
            feedback = .current
        } else if record.methodFeedbackComment == nil {
            feedback = .absent
        } else {
            feedback = .changed
        }
        return (record, feedback)
    }

    private func replaceMethodImprovementTarget(
        _ target: ResearchMethodImprovementTarget,
        registrationKey: ResearchSkillRegistrationKey,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> DocumentFingerprint {
        let updated = try await saveCurrentResearchMethod(
            registrationKey: registrationKey,
            source: source,
            expectedRevision: expectedRevision
        )
        guard updated.primaryMarkdownSource == source,
              updated.primaryMarkdownRevision
                == DocumentFingerprint(content: source) else {
            throw ResearchMethodImprovementError.methodChanged
        }
        return updated.primaryMarkdownRevision
    }

    private static func methodImprovementTarget(
        id: String,
        in method: ResearchMethodSnapshot
    ) throws -> ResearchMethodImprovementTarget {
        if id == "primary-method" {
            return try ResearchMethodImprovementTarget(
                id: id,
                title: method.registration.displayName,
                source: method.primaryMarkdownSource,
                revision: method.primaryMarkdownRevision
            )
        }
        throw ResearchMethodImprovementError.invalidContract
    }

    private static func stableMethodImprovementRunID(
        recordID: UUID,
        feedbackRevision: UUID
    ) -> UUID {
        let digest = DocumentFingerprint(
            content: "\(recordID.uuidString.lowercased()):method-improvement:\(feedbackRevision.uuidString.lowercased())"
        ).sha256
        return UUID(uuidString: [
            String(digest.prefix(8)),
            String(digest.dropFirst(8).prefix(4)),
            String(digest.dropFirst(12).prefix(4)),
            String(digest.dropFirst(16).prefix(4)),
            String(digest.dropFirst(20).prefix(12)),
        ].joined(separator: "-"))!
    }
}
