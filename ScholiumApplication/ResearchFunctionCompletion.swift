import Foundation
import ScholiumContracts
import ScholiumCore

private struct ResearchFunctionManuscriptChildEvidence: Sendable {
    let fidelity: ResearchFunctionCompletion?
    let hasRevision: Bool
}

private struct ResearchFunctionConfirmedWriteSet: Sendable {
    let report: ResearchRunWriteReport
    let currentFingerprints: [UUID: DocumentFingerprint]
}

// MARK: - Completion transaction

extension ResearchFunctionCoordinator {
    /// Completes one protected run as a single coordinator-owned transaction.
    /// The coordinator validates current source evidence before committing the
    /// Local Execution transition, then repairs any later portable-record or derived
    /// publication work idempotently on the same submission.
    func completeProtectedFunction<Host: ResearchFunctionCoordinatorHost>(
        _ submission: ResearchFunctionCompletionSubmission,
        acceptedSubmissionDigest: String? = nil,
        candidateResultPayload: ResearchRunResultPayload? = nil,
        host: isolated Host
    ) async throws -> ResearchFunctionCompletion {
        try requireMatchingActiveHost(host)
        let stored = try await record(runID: submission.runID)
        let snapshot = stored.snapshot
        guard candidateResultPayload?.runID == submission.runID
                || candidateResultPayload == nil,
              stored.resultPayload == nil
                || candidateResultPayload == nil
                || stored.resultPayload == candidateResultPayload else {
            throw ResearchAgentResultContractError.resultAlreadySubmitted
        }
        let submissionDigest = try acceptedSubmissionDigest
            ?? completionSubmissionDigest(submission)
        guard snapshot.confirmationToken == submission.confirmationToken else {
            throw ResearchFunctionContractError.confirmationMismatch
        }
        if let existing = stored.completion {
            switch existing.state {
            case .complete:
                guard case .local(let local) = stored,
                      local.completionSubmissionDigest == submissionDigest else {
                    throw ResearchFunctionContractError.completionAlreadyRecorded(
                        submission.runID
                    )
                }
                try await ensurePortableResearchRecord(
                    completion: existing,
                    stored: stored,
                    confirmedWrite: local.writeReport
                )
                await host.finalizeResearchAgentRunAccess(runID: existing.runID)
                return existing
            case .cancelled:
                throw ResearchFunctionContractError.completionAlreadyRecorded(submission.runID)
            case .prepared, .awaitingFidelity, .unverified, .stale:
                break
            }
        }
        try await validateResearchContinuation(snapshot, stored: stored)
        guard !submission.summary.isEmpty else {
            throw ResearchFunctionContractError.invalidCompletion(
                "A completion summary is required."
            )
        }
        if snapshot.actionSnapshot?.actionID == .analyze {
            guard let recommendations = submission.literatureRecommendations,
                  recommendations.count <= 256 else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "Analyze completion requires an explicit literatureRecommendations array with at most 256 entries."
                )
            }
        } else if submission.literatureRecommendations != nil {
            throw ResearchFunctionContractError.invalidCompletion(
                "Only Analyze completion accepts literatureRecommendations."
            )
        }
        if let existing = stored.completion,
           [.awaitingFidelity, .unverified, .stale].contains(existing.state),
           (existing.literatureRecommendations != submission.literatureRecommendations
               || existing.actuallyUsedMaterialNoteIDs
                    != submission.actuallyUsedMaterialNoteIDs) {
            throw ResearchFunctionContractError.invalidCompletion(
                "Advancing Fidelity cannot replace the Action's recorded recommendation or Material-use testimony."
            )
        }
        // A prepared Analyze never outlives its exact source authority. Check
        // before confirming bounded writes, then check again against the final
        // Target below so source loss cannot be converted into a completion.
        let validatedSourceAccess = try await validateSnapshotResearchSourceAccess(snapshot)
        try validateRecommendationSourcePrivacy(
            submission.literatureRecommendations,
            sourceAccess: validatedSourceAccess
        )

        switch snapshot.request.function {
        case .discuss:
            let durableStatements = try await validatedDiscussionStatements(
                snapshot: snapshot
            )
            guard let discussion = stored.discussionExecution,
                  discussion.responseContract.validationIssues.isEmpty,
                  durableStatements.contains(where: { statement in
                      statement.author == .agent
                          && statement.createdAt >= snapshot.preparedAt
                          && !statement.attribution.isEmpty
                          && !statement.text.isEmpty
                  }) else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "Keep a valid stored Discuss response contract and record a durable attributed reply before completing Discuss."
                )
            }
        case .critique, .develop, .fidelity, .revise, .manuscript:
            break
        }

        let confirmedWriteSet: ResearchFunctionConfirmedWriteSet?
        let finalTargetFingerprint: DocumentFingerprint
        let finalMaterialFingerprints: [UUID: DocumentFingerprint]
        if [.develop, .revise].contains(snapshot.request.function) {
            let confirmed = try await confirmBoundedWriteSet(
                stored: stored,
                snapshot: snapshot,
                completedAt: stored.writeReport?.completedAt
                    ?? stored.completion?.completedAt
                    ?? submission.submittedAt,
                host: host
            )
            confirmedWriteSet = confirmed
            if let current = confirmed.currentFingerprints[
                snapshot.request.target.noteID
            ] {
                finalTargetFingerprint = current
            } else {
                finalTargetFingerprint = try await currentFingerprint(
                    for: snapshot.request.target,
                    host: host
                )
            }
            var materialFingerprints: [UUID: DocumentFingerprint] = [:]
            for material in snapshot.request.materials {
                _ = try await validateResearchFunctionMaterial(
                    material,
                    expected: material.fingerprint,
                    host: host
                )
                materialFingerprints[material.noteID] = material.fingerprint
            }
            finalMaterialFingerprints = materialFingerprints
        } else {
            guard let submittedTargetFingerprint = submission.finalTargetFingerprint else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "This Action requires the exact final Target fingerprint."
                )
            }
            confirmedWriteSet = nil
            finalTargetFingerprint = submittedTargetFingerprint
            finalMaterialFingerprints = submission.finalMaterialFingerprints
        }

        let currentTarget = try await validateResearchFunctionTarget(
            snapshot.request.target,
            expected: finalTargetFingerprint,
            host: host
        )
        _ = try await validateSnapshotResearchSourceAccess(
            snapshot,
            currentTarget: currentTarget
        )
        let materialIDs = Set(snapshot.request.materials.map(\.noteID))
        guard Set(finalMaterialFingerprints.keys) == materialIDs else {
            throw ResearchFunctionContractError.invalidCompletion(
                "Final Material fingerprints must match the prepared Material set exactly."
            )
        }
        for material in snapshot.request.materials {
            guard finalMaterialFingerprints[material.noteID] == material.fingerprint else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "Material \(material.title) changed during the Action run."
                )
            }
            _ = try await validateResearchFunctionMaterial(
                material,
                expected: material.fingerprint,
                host: host
            )
        }
        if snapshot.actionSnapshot != nil,
           submission.actuallyUsedMaterialNoteIDs == nil {
            throw ResearchFunctionContractError.invalidCompletion(
                "A current Action completion must explicitly report the Materials actually used, including an empty report."
            )
        }
        let actuallyUsedMaterialNoteIDs = submission.actuallyUsedMaterialNoteIDs ?? []
        guard Set(actuallyUsedMaterialNoteIDs).count == actuallyUsedMaterialNoteIDs.count,
              Set(actuallyUsedMaterialNoteIDs).isSubset(of: materialIDs) else {
            throw ResearchFunctionContractError.invalidCompletion(
                "Actually-used Material identities must be a distinct subset of the prepared Material set."
            )
        }
        guard snapshot.request.commentIDs.isEmpty,
              snapshot.evidenceRevisions.isEmpty else {
            throw ResearchFunctionContractError.invalidCompletion(
                "Legacy Comment evidence cannot participate in a current Action run."
            )
        }

        let targetChanged = finalTargetFingerprint
            != snapshot.request.target.fingerprint
        let didConfirmWrite = confirmedWriteSet.map {
            !$0.report.confirmedModifiedNotes.isEmpty
        } ?? targetChanged
        let didConfirmTargetWrite = confirmedWriteSet.map { confirmed in
            confirmed.report.confirmedModifiedNotes.contains {
                $0.noteID == snapshot.request.target.noteID
            }
        } ?? targetChanged
        if snapshot.request.function.writesTarget {
            guard confirmedWriteSet != nil
                    || submission.didModifyTarget == targetChanged else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "Target modification status does not match its final fingerprint."
                )
            }
        } else {
            guard !submission.didModifyTarget, !targetChanged else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "This read-only Research Action cannot modify its Target."
                )
            }
        }

        let submittedChildRunIDs = submission.childRunIDs ?? []
        switch snapshot.request.function {
        case .develop, .revise:
            guard submittedChildRunIDs.count <= 1 else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "A write-capable Research Action may select at most one final Content Fidelity child run."
                )
            }
            guard didConfirmWrite || submittedChildRunIDs.isEmpty else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "An unchanged write-capable Action cannot select final Fidelity evidence."
                )
            }
            if let confirmedWriteSet,
               confirmedWriteSet.report.confirmedModifiedNotes.count > 1,
               !submittedChildRunIDs.isEmpty {
                throw ResearchFunctionContractError.invalidCompletion(
                    "A multi-note Write uses per-note Fidelity results and cannot attach one single-target child run."
                )
            }
        case .manuscript:
            break
        case .discuss, .fidelity, .critique:
            guard submittedChildRunIDs.isEmpty else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "This Research Action cannot select child Action runs."
                )
            }
        }
        let manuscriptChildren = snapshot.request.function == .manuscript
            ? try await completedManuscriptChildren(
                for: snapshot,
                childRunIDs: submittedChildRunIDs,
                finalTargetFingerprint: finalTargetFingerprint
            )
            : nil
        if snapshot.request.function == .manuscript,
           manuscriptChildren?.hasRevision != true,
           targetChanged {
            throw ResearchFunctionContractError.invalidCompletion(
                "A Manuscript Target can change only through a selected completed Write child run."
            )
        }
        let manuscriptFidelity = manuscriptChildren?.fidelity
        let linkedFinalFidelity: ResearchFunctionCompletion?
        if [.develop, .revise].contains(snapshot.request.function),
           let fidelityRunID = submittedChildRunIDs.first {
            linkedFinalFidelity = try await completedFinalFidelityChild(
                runID: fidelityRunID,
                for: snapshot,
                finalTargetFingerprint: finalTargetFingerprint,
                finalMaterialFingerprints: finalMaterialFingerprints
            )
        } else {
            linkedFinalFidelity = nil
        }
        let requiredChecks: Set<FidelityCheck>
        if snapshot.request.function == .fidelity {
            requiredChecks = snapshot.request.checks
        } else {
            requiredChecks = snapshot.fidelityHandoff?.checks ?? []
        }
        func validateFidelityOutcomes(_ outcomes: [FidelityCheckOutcome]) throws {
            let submittedChecks = outcomes.map(\.check)
            for outcome in outcomes { try outcome.validate() }
            guard Set(submittedChecks).count == submittedChecks.count else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "Each Fidelity check may be submitted only once per note."
                )
            }
            guard outcomes.isEmpty || Set(submittedChecks) == requiredChecks else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "Fidelity outcomes must cover the exact required check set."
                )
            }
            guard !requiredChecks.isEmpty || outcomes.isEmpty else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "This Action has no Fidelity handoff."
                )
            }
        }

        let targetSubmissions = submission.fidelityTargetSubmissions ?? []
        let fidelityTargetResults: [ResearchFunctionFidelityTargetResult]
        if snapshot.request.function == .fidelity,
           snapshot.request.resolvedFidelityTargets.count > 1 {
            guard submission.fidelityOutcomes.isEmpty else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "A shared Fidelity run reports outcomes per note, not as one aggregate result."
                )
            }
            let expected = Dictionary(
                uniqueKeysWithValues: snapshot.request.resolvedFidelityTargets.map {
                    ($0.noteID, $0)
                }
            )
            let submitted = Dictionary(
                targetSubmissions.map { ($0.noteID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            guard submitted.count == targetSubmissions.count,
                  Set(submitted.keys) == Set(expected.keys) else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "A shared Fidelity completion requires exactly one result for every prepared note."
                )
            }
            var results: [ResearchFunctionFidelityTargetResult] = []
            for target in snapshot.request.resolvedFidelityTargets {
                guard let item = submitted[target.noteID],
                      item.note == target.note,
                      item.fingerprint == target.fingerprint else {
                    throw ResearchFunctionContractError.invalidCompletion(
                        "A shared Fidelity result does not match its prepared note revision."
                    )
                }
                _ = try await validateResearchFunctionTarget(
                    target,
                    expected: target.fingerprint,
                    host: host
                )
                try validateFidelityOutcomes(item.outcomes)
                guard !item.outcomes.isEmpty else {
                    throw ResearchFunctionContractError.invalidCompletion(
                        "Every shared Fidelity target requires attributed outcomes."
                    )
                }
                results.append(ResearchFunctionFidelityTargetResult(
                    target: target,
                    outcomes: item.outcomes
                ))
            }
            fidelityTargetResults = results
        } else {
            guard targetSubmissions.isEmpty else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "Per-note Fidelity submissions require a shared multi-note Fidelity run."
                )
            }
            try validateFidelityOutcomes(submission.fidelityOutcomes)
            fidelityTargetResults = snapshot.request.function == .fidelity
                    && !submission.fidelityOutcomes.isEmpty
                ? [ResearchFunctionFidelityTargetResult(
                    target: snapshot.request.target,
                    outcomes: submission.fidelityOutcomes
                )]
                : []
        }
        if [.develop, .revise].contains(snapshot.request.function),
           !submission.fidelityOutcomes.isEmpty {
            throw ResearchFunctionContractError.invalidCompletion(
                "Write-capable runs must link an independently prepared final-fingerprint Fidelity child instead of submitting Fidelity outcomes directly."
            )
        }
        if snapshot.request.function != .fidelity,
           !targetSubmissions.isEmpty {
            throw ResearchFunctionContractError.invalidCompletion(
                "Only Fidelity accepts per-note target outcomes."
            )
        }

        var state: ResearchFunctionRunState
        if let manuscriptFidelity {
            state = manuscriptFidelity.state
        } else if let linkedFinalFidelity {
            state = linkedFinalFidelity.state
        } else if [.develop, .revise].contains(snapshot.request.function),
                  !didConfirmWrite {
            state = .complete
        } else if requiredChecks.isEmpty {
            state = .complete
        } else if snapshot.request.function == .fidelity,
                  !fidelityTargetResults.isEmpty,
                  fidelityTargetResults.flatMap(\.outcomes).contains(where: {
                      $0.state == .unavailable
                  }) {
            state = .unverified
        } else if submission.fidelityOutcomes.isEmpty
                    && fidelityTargetResults.isEmpty {
            state = .awaitingFidelity
        } else if submission.fidelityOutcomes.contains(where: { $0.state == .unavailable }) {
            state = .unverified
        } else {
            state = .complete
        }

        let directFidelityEvidenceKey = snapshot.request.function == .fidelity
                && snapshot.request.resolvedFidelityTargets.count == 1
            ? ResearchFidelityEvidenceKey(
                snapshot: snapshot,
                finalTargetFingerprint: finalTargetFingerprint,
                finalMaterialFingerprints: finalMaterialFingerprints,
                checks: requiredChecks
            )
            : nil
        let evidenceKey = manuscriptFidelity?.fidelityEvidenceKey
            ?? linkedFinalFidelity?.fidelityEvidenceKey
            ?? directFidelityEvidenceKey
        let reused: ResearchFunctionCompletion?
        if let evidenceKey, snapshot.request.function == .fidelity {
            reused = try await completedFidelityEvidence(
                for: evidenceKey,
                excluding: submission.runID
            )
        } else {
            reused = nil
        }
        let outcomes = manuscriptFidelity?.fidelityOutcomes
            ?? linkedFinalFidelity?.fidelityOutcomes
            ?? reused?.fidelityOutcomes
            ?? submission.fidelityOutcomes
        if reused != nil { state = .complete }
        let completion = ResearchFunctionCompletion(
            runID: submission.runID,
            function: snapshot.request.function,
            state: state,
            targetFingerprint: finalTargetFingerprint,
            materialFingerprints: finalMaterialFingerprints,
            actuallyUsedMaterialNoteIDs: submission.actuallyUsedMaterialNoteIDs,
            summary: stored.completion?.summary ?? submission.summary,
            didModifyTarget: didConfirmTargetWrite,
            fidelityOutcomes: outcomes,
            fidelityTargetResults: fidelityTargetResults,
            literatureRecommendations: submission.literatureRecommendations,
            fidelityEvidenceKey: evidenceKey,
            reusedFidelityRunID: manuscriptFidelity?.runID
                ?? linkedFinalFidelity?.runID
                ?? reused?.runID,
            childRunIDs: submittedChildRunIDs,
            completedAt: stored.completion?.completedAt ?? submission.submittedAt,
            derivedRefreshWarning: stored.completion?.derivedRefreshWarning
        )
        if snapshot.request.function == .develop,
           snapshot.request.target.role == .analysis {
            let finalCurrentTarget = try await validateResearchFunctionTarget(
                snapshot.request.target,
                expected: finalTargetFingerprint,
                host: host
            )
            _ = try await validateSnapshotResearchSourceAccess(
                snapshot,
                currentTarget: finalCurrentTarget
            )
        }
        if completion.function != .discuss,
           let candidateRecord = try await portableResearchRecord(
                completion: completion,
                stored: stored,
                confirmedWrite: confirmedWriteSet?.report,
                resultPayloadOverride: candidateResultPayload,
                storagePreflightForAwaitingFidelity: true
           ) {
            do {
                try PortableResearchRecordStore.validateStorageEncoding(
                    of: candidateRecord
                )
            } catch ResearchRecordStoreV1Error.recordTooLarge {
                throw ResearchFunctionContractError.invalidCompletion(
                    "The resulting Research Record exceeds the portable storage boundary."
                )
            }
        }
        try await persistCompletion(
            completion,
            in: stored,
            resultPayload: candidateResultPayload,
            writeReport: confirmedWriteSet?.report,
            submissionDigest: submissionDigest
        )
        // The substantive completion is authoritative before orchestration
        // begins. Automatic Fidelity preparation is therefore recoverable.
        if let advanced = try await advanceWithAutomaticFidelityIfAvailable(
            completion: completion,
            submission: submission,
            acceptedSubmissionDigest: submissionDigest,
            host: host
        ) {
            let refreshed = try await record(runID: advanced.runID)
            let refreshedWrite = [.develop, .revise].contains(
                refreshed.snapshot.request.function
            ) ? try await confirmBoundedWriteSet(
                stored: refreshed,
                snapshot: refreshed.snapshot,
                completedAt: advanced.completedAt,
                host: host
            ) : nil
            try await ensurePortableResearchRecord(
                completion: advanced,
                stored: refreshed,
                confirmedWrite: refreshedWrite?.report
            )
            if [.complete, .unverified, .stale, .cancelled].contains(advanced.state) {
                await host.finalizeResearchAgentRunAccess(runID: advanced.runID)
            }
            return advanced
        }

        if [.complete, .unverified].contains(completion.state),
           completion.function != .discuss {
            try await ensurePortableResearchRecord(
                completion: completion,
                stored: try await record(runID: completion.runID),
                confirmedWrite: confirmedWriteSet?.report
            )
        }

        let refreshWarning = try await host.publishCommittedResearchFunctionChange(
            "The Research Action completion"
        )
        if [.complete, .unverified, .stale, .cancelled].contains(completion.state) {
            await host.finalizeResearchAgentRunAccess(runID: completion.runID)
        }
        guard let refreshWarning else { return completion }
        return ResearchFunctionCompletion(
            runID: completion.runID,
            function: completion.function,
            state: completion.state,
            targetFingerprint: completion.targetFingerprint,
            materialFingerprints: completion.materialFingerprints,
            actuallyUsedMaterialNoteIDs: completion.actuallyUsedMaterialNoteIDs,
            summary: completion.summary,
            didModifyTarget: completion.didModifyTarget,
            fidelityOutcomes: completion.fidelityOutcomes,
            fidelityTargetResults: completion.fidelityTargetResults ?? [],
            literatureRecommendations: completion.literatureRecommendations,
            fidelityEvidenceKey: completion.fidelityEvidenceKey,
            reusedFidelityRunID: completion.reusedFidelityRunID,
            childRunIDs: completion.childRunIDs ?? [],
            completedAt: completion.completedAt,
            derivedRefreshWarning: refreshWarning
        )
    }
}

// MARK: - Post-commit repair and portable record

extension ResearchFunctionCoordinator {
    private func advanceWithAutomaticFidelityIfAvailable<
        Host: ResearchFunctionCoordinatorHost
    >(
        completion: ResearchFunctionCompletion,
        submission: ResearchFunctionCompletionSubmission,
        acceptedSubmissionDigest: String,
        host: isolated Host
    ) async throws -> ResearchFunctionCompletion? {
        guard completion.state == .awaitingFidelity,
              completion.didModifyTarget,
              [.develop, .revise].contains(completion.function),
              (submission.childRunIDs ?? []).isEmpty else { return nil }
        do {
            let automatic = try await prepareAutomaticFidelity(
                parentRunID: completion.runID,
                host: host
            )
            guard [.complete, .unverified].contains(automatic.state) else {
                return nil
            }
            return try await completeProtectedFunction(
                ResearchFunctionCompletionSubmission(
                    runID: submission.runID,
                    confirmationToken: submission.confirmationToken,
                    finalTargetFingerprint: submission.finalTargetFingerprint,
                    finalMaterialFingerprints: submission.finalMaterialFingerprints,
                    actuallyUsedMaterialNoteIDs: submission.actuallyUsedMaterialNoteIDs,
                    summary: submission.summary,
                    didModifyTarget: submission.didModifyTarget,
                    fidelityOutcomes: submission.fidelityOutcomes,
                    literatureRecommendations: submission.literatureRecommendations,
                    childRunIDs: [automatic.effectiveFidelityRunID],
                    submittedAt: submission.submittedAt
                ),
                acceptedSubmissionDigest: acceptedSubmissionDigest,
                host: host
            )
        } catch {
            if let durable = try? await record(runID: completion.runID),
               let advanced = durable.completion,
               [.complete, .unverified].contains(advanced.state) {
                let write = try await confirmBoundedWriteSet(
                    stored: durable,
                    snapshot: durable.snapshot,
                    completedAt: advanced.completedAt,
                    host: host
                )
                try await ensurePortableResearchRecord(
                    completion: advanced,
                    stored: durable,
                    confirmedWrite: write.report
                )
                return advanced
            }
            return nil
        }
    }

    private func completionSubmissionDigest(
        _ submission: ResearchFunctionCompletionSubmission
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys]
        return DocumentFingerprint(data: try encoder.encode(submission)).sha256
    }

    func validatedDiscussionStatements(
        snapshot: ResearchFunctionSnapshot
    ) async throws -> [PortableResearchStatement] {
        let expected = try ResearchDiscussionFactory.make(
            snapshot: snapshot,
            triptychID: workspaceID
        )
        if let active = try await dependencies.portableResearchRecordStore
            .activeDiscussionIfPresent(id: snapshot.runID) {
            guard ResearchDiscussionFactory.activeMatches(active, expected: expected) else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "The portable Discussion no longer matches its frozen Action run."
                )
            }
            return active.statements
        }
        do {
            let finished = try await dependencies.portableResearchRecordStore.record(
                id: snapshot.runID
            )
            guard ResearchDiscussionFactory.finishedMatches(finished, expected: expected) else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "The finished Discussion no longer matches its frozen Action run."
                )
            }
            return finished.statements
        } catch ResearchRecordStoreV1Error.recordNotFound(_) {
            throw ResearchFunctionContractError.invalidCompletion(
                "Record a durable attributed reply before completing Discuss."
            )
        }
    }

    private func ensurePortableResearchRecord(
        completion: ResearchFunctionCompletion,
        stored: StoredFunctionRecord,
        confirmedWrite: ResearchRunWriteReport?
    ) async throws {
        guard [.complete, .unverified].contains(completion.state) else { return }
        do {
            _ = try await dependencies.portableResearchRecordStore.record(
                id: completion.runID
            )
            return
        } catch ResearchRecordStoreV1Error.recordNotFound(_) {
            // Construct the missing record from the validated completion.
        }
        guard let record = try await portableResearchRecord(
            completion: completion,
            stored: stored,
            confirmedWrite: confirmedWrite
        ) else { return }
        do {
            _ = try await dependencies.portableResearchRecordStore.createFinishedRecord(
                record
            )
        } catch ResearchRecordStoreV1Error.recordPermanentlyDeleted(let id)
            where id == completion.runID {
            throw ResearchFunctionContractError.invalidCompletion(
                "The Research Record for this Action was permanently deleted and cannot be recreated."
            )
        } catch ResearchRecordStoreV1Error.recordTooLarge {
            throw ResearchFunctionContractError.invalidCompletion(
                "The resulting Research Record exceeds the portable storage boundary."
            )
        }
    }

    private func validateRecommendationSourcePrivacy(
        _ recommendations: [ResearchLiteratureRecommendationSubmission]?,
        sourceAccess: ResolvedResearchSourceAccess?
    ) throws {
        guard let recommendations, let sourceAccess else { return }
        let forbiddenLocators = Set([
            sourceAccess.fileURL.path,
            sourceAccess.fileURL.standardizedFileURL.path,
            sourceAccess.fileURL.absoluteString,
            sourceAccess.fileURL.standardizedFileURL.absoluteString,
        ].filter { !$0.isEmpty })
        let containsLocator = { (value: String) in
            forbiddenLocators.contains { value.contains($0) }
        }
        let leaked = recommendations.contains { recommendation in
            let optionalValues = [
                recommendation.title,
                recommendation.doi,
                recommendation.zoteroItemKey,
                recommendation.uncertainty,
            ].compactMap { $0 }
            return containsLocator(recommendation.rawCitation)
                || containsLocator(recommendation.reason)
                || recommendation.authors.contains(where: containsLocator)
                || recommendation.sourceLocators.contains(where: containsLocator)
                || optionalValues.contains(where: containsLocator)
        }
        guard !leaked else {
            throw ResearchFunctionContractError.invalidCompletion(
                "Literature Recommendations cannot persist the transient machine-local source locator."
            )
        }
    }

    private func portableResearchRecord(
        completion: ResearchFunctionCompletion,
        stored: StoredFunctionRecord,
        confirmedWrite: ResearchRunWriteReport?,
        resultPayloadOverride: ResearchRunResultPayload? = nil,
        storagePreflightForAwaitingFidelity: Bool = false
    ) async throws -> PortableResearchRecord? {
        let canBuildRecord = [.complete, .unverified].contains(completion.state)
            || (storagePreflightForAwaitingFidelity
                && completion.state == .awaitingFidelity)
        guard canBuildRecord,
              completion.function != .discuss,
              let actionSnapshot = stored.snapshot.actionSnapshot else {
            return nil
        }
        guard let resultPayload = resultPayloadOverride ?? stored.resultPayload,
              resultPayload.runID == completion.runID else {
            throw ResearchFunctionContractError.invalidCompletion(
                "A current Action cannot form a Record without its canonical Result payload."
            )
        }
        let snapshot = stored.snapshot
        var noteSnapshots: [UUID: ResearchActionNoteSnapshot] = [
            actionSnapshot.target.noteID: actionSnapshot.target,
        ]
        for note in actionSnapshot.authority.readableNotes {
            noteSnapshots[note.noteID] = note
        }
        for note in actionSnapshot.authority.writableNotes {
            noteSnapshots[note.noteID] = note
        }
        let writeRecords = stored.documentWriteRecords
        var boundedWriteStartingRevisions: [UUID: DocumentFingerprint] = [:]
        for entry in stored.boundedWriteSet.entries {
            let starting = writeRecords
                .filter { $0.target == entry.handle }
                .min(by: { $0.startedAt < $1.startedAt })?
                .expectedRevision ?? entry.expectedRevision
            boundedWriteStartingRevisions[entry.noteID] = starting
            noteSnapshots[entry.noteID] = ResearchActionNoteSnapshot(
                noteID: entry.noteID,
                note: entry.note,
                role: entry.role,
                lifecycle: .active,
                fingerprint: starting,
                title: entry.title
            )
        }

        var endingRevisions: [UUID: DocumentFingerprint] = [:]
        endingRevisions[snapshot.request.target.noteID] = completion.targetFingerprint
        for (noteID, fingerprint) in completion.materialFingerprints {
            endingRevisions[noteID] = fingerprint
        }
        for (noteID, fingerprint) in confirmedWrite?.observedFingerprints ?? [:] {
            endingRevisions[noteID] = fingerprint
        }
        let participatingNotes = try noteSnapshots.values.map { note in
            try PortableResearchNoteRevision(
                noteID: note.noteID,
                note: note.note,
                role: note.role,
                title: note.title,
                startingRevision: note.fingerprint,
                endingRevision: endingRevisions[note.noteID] ?? note.fingerprint
            )
        }

        var changes: [PortableResearchConfirmedChange] = []
        if let confirmedWrite {
            for note in confirmedWrite.confirmedModifiedNotes {
                guard let starting = boundedWriteStartingRevisions[note.noteID],
                      let ending = confirmedWrite.observedFingerprints[note.noteID],
                      starting != ending else { continue }
                changes.append(try PortableResearchConfirmedChange(
                    noteID: note.noteID,
                    actor: .agent,
                    startingRevision: starting,
                    endingRevision: ending
                ))
            }
        } else if completion.targetFingerprint != actionSnapshot.target.fingerprint {
            changes.append(try PortableResearchConfirmedChange(
                noteID: actionSnapshot.target.noteID,
                actor: .agent,
                startingRevision: actionSnapshot.target.fingerprint,
                endingRevision: completion.targetFingerprint
            ))
        }
        let discrepancies: [PortableResearchDiscrepancy] = []

        let feedback = try PortableResearchStatement(
            id: completion.runID,
            author: .agent,
            kind: .agentFeedback,
            attribution: "Agent",
            text: completion.summary,
            createdAt: completion.completedAt
        )
        let academicResults = try actionSnapshot.resultContract.academicFields.map {
            definition in
            try PortableResearchAcademicFieldResult(
                definition: definition,
                value: resultPayload.academicResults.values[
                    definition.fieldID.rawValue
                ]
            )
        }
        let materialsByID = Dictionary(
            uniqueKeysWithValues: snapshot.request.materials.map { ($0.noteID, $0) }
        )
        guard let actuallyUsedMaterialNoteIDs = completion.actuallyUsedMaterialNoteIDs else {
            throw ResearchFunctionContractError.invalidCompletion(
                "A current Action completion has no explicit actually-used Material report."
            )
        }
        let actuallyUsedMaterials = try actuallyUsedMaterialNoteIDs
            .map { noteID -> PortableResearchMaterialUse in
                guard let material = materialsByID[noteID] else {
                    throw ResearchFunctionContractError.invalidCompletion(
                        "A recorded actually-used Material is outside the frozen request."
                    )
                }
                let role: ResearchActionTargetRole = switch material.role {
                case .analysis: .analysis
                case .topic: .topic
                case .work: .work
                }
                return try PortableResearchMaterialUse(
                    noteID: material.noteID,
                    note: material.note,
                    role: role,
                    title: material.title,
                    revision: material.fingerprint
                )
            }
        let recommendationSubmissions: [ResearchLiteratureRecommendationSubmission]
        if actionSnapshot.actionID == .analyze {
            guard let submitted = completion.literatureRecommendations,
                  submitted.count <= 256 else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "A completed Analyze run cannot repair a Research Record without its explicit bounded literatureRecommendations report."
                )
            }
            recommendationSubmissions = submitted
        } else {
            guard completion.literatureRecommendations == nil else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "Only Analyze completion can repair Literature Recommendations."
                )
            }
            recommendationSubmissions = []
        }
        let literatureRecommendations = try recommendationSubmissions
            .enumerated()
            .map { ordinal, submission in
                ResearchLiteratureRecommendation(
                    id: ResearchLiteratureRecommendation.stableID(
                        runID: completion.runID,
                        ordinal: ordinal
                    ),
                    submission: submission,
                    disposition: try PortableResearchRecommendationDisposition(
                        status: .unprocessed,
                        updatedAt: completion.completedAt
                    )
                )
            }
        return try PortableResearchRecord(
            id: completion.runID,
            triptychID: workspaceID,
            kind: .action,
            action: ResearchActionRecordIdentity(snapshot: actionSnapshot),
            method: try PortableResearchMethodReference(snapshot: actionSnapshot),
            sourceReference: snapshot.sourceReference,
            continuationLineage: snapshot.continuationLineage,
            primaryNoteID: actionSnapshot.target.noteID,
            participatingNotes: participatingNotes,
            statements: [feedback],
            resultDisposition: resultPayload.disposition,
            academicResults: academicResults,
            contextUseReport: resultPayload.contextUseReport,
            actuallyUsedMaterials: actuallyUsedMaterials,
            fidelityCompletion: storagePreflightForAwaitingFidelity
                    && completion.state == .awaitingFidelity
                ? .notRequired
                : try portableFidelityCompletion(for: completion),
            confirmedChanges: changes,
            discrepancies: discrepancies,
            literatureRecommendations: literatureRecommendations,
            startedAt: snapshot.preparedAt,
            finishedAt: completion.completedAt
        )
    }

    private func portableFidelityCompletion(
        for completion: ResearchFunctionCompletion
    ) throws -> PortableResearchFidelityCompletion {
        switch completion.state {
        case .complete:
            return completion.fidelityEvidenceKey == nil ? .notRequired : .completed
        case .unverified:
            guard completion.fidelityEvidenceKey != nil else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "An unverified Action record requires exact-revision Fidelity evidence."
                )
            }
            return .unverified
        case .prepared, .awaitingFidelity, .stale, .cancelled:
            throw ResearchFunctionContractError.invalidCompletion(
                "Only a complete or unverified Action can create a portable Research Record."
            )
        }
    }
}

// MARK: - Durable record and Fidelity evidence

extension ResearchFunctionCoordinator {
    /// Reads durable evidential authorities directly. A Workspace snapshot is
    /// disposable and may remain at its last-known-good generation after a
    /// committed refresh failure.
    func authoritativeFunctionRecords() async throws
        -> [ResearchFunctionRecordProjection] {
        let localRecords = try await dependencies.localExecutionStore.listing().records
        let local = localRecords.map {
            ResearchFunctionRecordProjection(
                snapshot: $0.snapshot,
                completion: $0.completion,
                preparedInstructions: $0.preparedInstructions
            )
        }
        var projected: [ResearchFunctionRecordProjection] = []
        projected.reserveCapacity(local.count)
        for record in local {
            projected.append(try await projectCurrentFunctionRecord(record))
        }
        return projected.sorted {
            if $0.snapshot.preparedAt != $1.snapshot.preparedAt {
                return $0.snapshot.preparedAt > $1.snapshot.preparedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func projectCurrentFunctionRecord(
        _ record: ResearchFunctionRecordProjection
    ) async throws -> ResearchFunctionRecordProjection {
        guard let completion = record.completion,
              completion.state != .cancelled,
              completion.state != .stale else {
            return record
        }
        guard try await functionCompletionIsCurrent(
            completion,
            snapshot: record.snapshot
        ) else {
            return ResearchFunctionRecordProjection(
                snapshot: record.snapshot,
                completion: ResearchFunctionCompletion(
                    runID: completion.runID,
                    function: completion.function,
                    state: .stale,
                    targetFingerprint: completion.targetFingerprint,
                    materialFingerprints: completion.materialFingerprints,
                    actuallyUsedMaterialNoteIDs: completion.actuallyUsedMaterialNoteIDs,
                    summary: completion.summary,
                    didModifyTarget: completion.didModifyTarget,
                    fidelityOutcomes: completion.fidelityOutcomes,
                    fidelityTargetResults: completion.fidelityTargetResults ?? [],
                    literatureRecommendations: completion.literatureRecommendations,
                    fidelityEvidenceKey: completion.fidelityEvidenceKey,
                    reusedFidelityRunID: completion.reusedFidelityRunID,
                    childRunIDs: completion.childRunIDs ?? [],
                    completedAt: completion.completedAt,
                    derivedRefreshWarning: completion.derivedRefreshWarning
                ),
                preparedInstructions: record.preparedInstructions
            )
        }
        return record
    }

    private func functionCompletionIsCurrent(
        _ completion: ResearchFunctionCompletion,
        snapshot: ResearchFunctionSnapshot
    ) async throws -> Bool {
        do {
            guard try await functionObjectIsCurrent(
                noteID: snapshot.request.target.noteID,
                note: snapshot.request.target.note,
                role: snapshot.request.target.role,
                lifecycle: snapshot.request.target.lifecycle,
                fingerprint: completion.targetFingerprint
            ) else { return false }

            guard Set(completion.materialFingerprints.keys)
                    == Set(snapshot.request.materials.map(\.noteID)) else {
                return false
            }
            let actuallyUsedIDs: [UUID]
            if let reported = completion.actuallyUsedMaterialNoteIDs {
                actuallyUsedIDs = reported
            } else if snapshot.actionSnapshot == nil {
                actuallyUsedIDs = []
            } else {
                return false
            }
            guard Set(actuallyUsedIDs).count == actuallyUsedIDs.count,
                  Set(actuallyUsedIDs).isSubset(
                    of: Set(snapshot.request.materials.map(\.noteID))
                  ) else {
                return false
            }
            for material in snapshot.request.materials {
                guard let fingerprint = completion.materialFingerprints[material.noteID],
                      try await functionObjectIsCurrent(
                          noteID: material.noteID,
                          note: material.note,
                          role: material.role,
                          lifecycle: material.lifecycle,
                          fingerprint: fingerprint
                      ) else { return false }
            }

            return snapshot.request.commentIDs.isEmpty
                && snapshot.evidenceRevisions.isEmpty
        } catch {
            // Missing, unreadable, moved, or identity-mismatched evidence is
            // stale for planning. The durable record remains untouched.
            return false
        }
    }

    private func functionObjectIsCurrent(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchFunctionTargetRole,
        lifecycle: WorkspaceDocumentLifecycle,
        fingerprint: DocumentFingerprint
    ) async throws -> Bool {
        guard let identity = try await dependencies.controlStore.identityRecord(
            vaultID: note.vaultID,
            relativePath: note.relativePath
        ), identity.id == noteID,
              ResearchFunctionTargetRole(vaultRole: try vault(id: note.vaultID).role) == role,
              WorkspaceDocumentLifecycle(relativePath: note.relativePath) == lifecycle else {
            return false
        }
        let document = try await repository(vaultID: note.vaultID)
            .load(relativePath: note.relativePath)
        return document.fingerprint == fingerprint
    }

    func completedFidelityEvidence(
        for key: ResearchFidelityEvidenceKey,
        excluding runID: UUID?
    ) async throws -> ResearchFunctionCompletion? {
        try await authoritativeFunctionRecords().first { record in
            guard record.snapshot.request.function == .fidelity,
                  let completion = record.completion else {
                return false
            }
            return completion.runID != runID
                && completion.state == .complete
                && completion.fidelityEvidenceKey == key
                && !completion.fidelityOutcomes.isEmpty
        }?.completion
    }

    private func completedFinalFidelityChild(
        runID: UUID,
        for parent: ResearchFunctionSnapshot,
        finalTargetFingerprint: DocumentFingerprint,
        finalMaterialFingerprints: [UUID: DocumentFingerprint]
    ) async throws -> ResearchFunctionCompletion {
        let records = try await authoritativeFunctionRecords()
        let lineageMatches: Bool
        if let parentLineage = parent.continuationLineage {
            lineageMatches = records.first(where: { $0.id == runID })?
                .snapshot.continuationLineage == ResearchContinuationLineage(
                    groupID: parentLineage.groupID,
                    parentRunID: parent.runID,
                    requestID: parentLineage.requestID,
                    kind: .fidelity
                )
        } else {
            lineageMatches = true
        }
        guard runID != parent.runID,
              let child = records.first(where: { $0.id == runID }),
              lineageMatches,
              child.snapshot.request.function == .fidelity,
              child.snapshot.preparedAt >= parent.preparedAt,
              let completion = child.completion,
              [.complete, .unverified].contains(completion.state),
              completion.fidelityEvidenceKey != nil,
              !completion.fidelityOutcomes.isEmpty else {
            throw ResearchFunctionContractError.invalidCompletion(
                "The selected final Fidelity child is unavailable, incomplete, stale, or not an independent Fidelity run."
            )
        }

        if case .automatic(let recordedParentRunID)? =
            child.snapshot.resolvedFidelityInvocation,
           recordedParentRunID != parent.runID {
            throw ResearchFunctionContractError.invalidCompletion(
                "The selected automatic Fidelity child belongs to another parent run."
            )
        }

        let parentRequest = parent.request
        let childRequest = child.snapshot.request
        let requiredChecks = parent.fidelityHandoff?.checks ?? []
        let parentScopeKind = parentRequest.scope?.kind ?? .whole
        let childScopeKind = childRequest.scope?.kind ?? .whole
        let parentEvidence = parent.evidenceRevisions.sorted {
            if $0.sha256 != $1.sha256 { return $0.sha256 < $1.sha256 }
            return $0.byteCount < $1.byteCount
        }
        let childEvidence = child.snapshot.evidenceRevisions.sorted {
            if $0.sha256 != $1.sha256 { return $0.sha256 < $1.sha256 }
            return $0.byteCount < $1.byteCount
        }

        guard childRequest.target.noteID == parentRequest.target.noteID,
              childRequest.target.note == parentRequest.target.note,
              childRequest.target.role == parentRequest.target.role,
              childRequest.target.lifecycle == parentRequest.target.lifecycle,
              childRequest.target.fingerprint == finalTargetFingerprint,
              completion.targetFingerprint == finalTargetFingerprint,
              !completion.didModifyTarget,
              childRequest.checks == requiredChecks,
              Set(completion.fidelityOutcomes.map(\.check)) == requiredChecks,
              Set(childRequest.materials) == Set(parentRequest.materials),
              completion.materialFingerprints == finalMaterialFingerprints,
              Set(childRequest.commentIDs) == Set(parentRequest.commentIDs),
              childEvidence == parentEvidence,
              childScopeKind == parentScopeKind else {
            throw ResearchFunctionContractError.invalidCompletion(
                "The selected Fidelity child does not match the final Target fingerprint, Materials, scope, Comments, or required checks of this handoff."
            )
        }
        return completion
    }

    private func completedManuscriptChildren(
        for manuscript: ResearchFunctionSnapshot,
        childRunIDs: [UUID],
        finalTargetFingerprint: DocumentFingerprint
    ) async throws -> ResearchFunctionManuscriptChildEvidence {
        guard !childRunIDs.isEmpty,
              Set(childRunIDs).count == childRunIDs.count else {
            throw ResearchFunctionContractError.invalidCompletion(
                "Manuscript completion must select one or more distinct child Action runs."
            )
        }
        let byID = Dictionary(
            uniqueKeysWithValues: try await authoritativeFunctionRecords().map { ($0.id, $0) }
        )
        let selected = try childRunIDs.map { runID in
            guard let child = byID[runID],
                  child.snapshot.runID != manuscript.runID,
                  child.snapshot.preparedAt >= manuscript.preparedAt,
                  child.snapshot.request.target.noteID == manuscript.request.target.noteID,
                  child.completion?.state == .complete,
                  [.critique, .revise, .fidelity].contains(
                    child.snapshot.request.function
                  ) else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "A selected Manuscript child is unavailable, incomplete, role-invalid, or belongs to another Target."
                )
            }
            return child
        }
        let revisions = selected.filter { $0.snapshot.request.function == .revise }
        let latestRevision = revisions.max { lhs, rhs in
            lhs.snapshot.preparedAt < rhs.snapshot.preparedAt
        }
        if let latestRevision {
            guard latestRevision.completion?.targetFingerprint == finalTargetFingerprint else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "The latest selected Write child does not match the final Work revision."
                )
            }
        }
        let fidelityRuns = selected.filter { child in
            child.snapshot.request.function == .fidelity
                && child.completion?.targetFingerprint == finalTargetFingerprint
                && child.completion?.fidelityEvidenceKey != nil
                && child.completion?.fidelityOutcomes.contains(where: {
                    $0.check == .content && $0.state != .unavailable
                }) == true
        }
        let finalFidelity = fidelityRuns.max { lhs, rhs in
            lhs.snapshot.preparedAt < rhs.snapshot.preparedAt
        }
        if let latestRevision {
            let revisionFidelity = latestRevision.completion.flatMap { completion in
                completion.targetFingerprint == finalTargetFingerprint
                    && completion.fidelityEvidenceKey != nil
                    && completion.fidelityOutcomes.contains(where: {
                        $0.check == .content && $0.state != .unavailable
                    })
                    ? completion
                    : nil
            }
            let laterIndependentFidelity = finalFidelity.flatMap { child in
                child.snapshot.preparedAt > latestRevision.snapshot.preparedAt
                    ? child.completion
                    : nil
            }
            guard let fidelity = laterIndependentFidelity ?? revisionFidelity else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "The latest selected Write must carry final Content Fidelity evidence, or be followed by a matching independent Fidelity child."
                )
            }
            return ResearchFunctionManuscriptChildEvidence(
                fidelity: fidelity,
                hasRevision: true
            )
        }
        return ResearchFunctionManuscriptChildEvidence(
            fidelity: finalFidelity?.completion,
            hasRevision: false
        )
    }
}

// MARK: - Continuation validation

extension ResearchFunctionCoordinator {
    private func validateResearchContinuation(
        _ snapshot: ResearchFunctionSnapshot,
        stored: StoredFunctionRecord
    ) async throws {
        guard let lineage = snapshot.continuationLineage else { return }
        _ = stored

        switch lineage.kind {
        case .continueResearch:
            guard lineage.requestID == snapshot.runID,
                  let handoff = snapshot.continuationHandoff,
                  handoff.parentRecordID == lineage.parentRunID,
                  handoff.initiator == .agent,
                  let parent = try? await dependencies.portableResearchRecordStore
                    .record(id: lineage.parentRunID),
                  parent.triptychID == workspaceID,
                  parent.id != snapshot.runID else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "The Continue Research child no longer matches one finalized parent Record and its explicit Agent handoff."
                )
            }
        case .resynthesis:
            guard lineage.requestID == snapshot.runID,
                  let context = snapshot.resynthesisContext,
                  context.triptychID == workspaceID,
                  context.recordID == lineage.parentRunID,
                  context.topicNoteID == snapshot.request.target.noteID,
                  context.material.stableNoteID.flatMap(UUID.init(uuidString:))
                    == context.materialNoteID,
                  context.recordedRevision != context.currentRevision,
                  snapshot.request.function == .develop,
                  snapshot.request.target.role == .topic,
                  let action = snapshot.actionSnapshot,
                  action.actionID == .synthesize,
                  action.authority.writableNotes == [action.target],
                  snapshot.request.materials.contains(where: {
                      $0.noteID == context.materialNoteID
                          && $0.role == .analysis
                          && $0.note.vaultID == context.material.vaultID
                          && $0.note.relativePath == context.material.relativePath
                          && $0.fingerprint == context.currentRevision
                  }),
                  let checkpointID = snapshot.checkpointID,
                  let checkpoint = try? await dependencies.checkpointStore
                    .checkpoint(id: checkpointID),
                  checkpoint.triptychID == workspaceID,
                  checkpoint.kind == .researchContinuation,
                  checkpoint.files == [TriptychCheckpointFile(
                    key: researchContinuationCheckpointKey(
                        for: snapshot.request.target
                    ),
                    fingerprint: snapshot.request.target.fingerprint
                  )] else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "The Resynthesize child no longer matches its exact revision pair, Target, Material, or recovery checkpoint."
                )
            }
        case .fidelity:
            guard case .automatic(let fidelityParentID)? =
                    snapshot.resolvedFidelityInvocation,
                  fidelityParentID == lineage.parentRunID,
                  let parent = try await dependencies.localExecutionStore
                    .recordIfPresent(id: lineage.parentRunID),
                  let parentLineage = parent.snapshot.continuationLineage,
                  parentLineage.kind == .resynthesis,
                  parentLineage.groupID == lineage.groupID,
                  parentLineage.requestID == lineage.requestID,
                  parent.completion.map({
                      [.awaitingFidelity, .unverified, .complete]
                        .contains($0.state)
                  }) == true else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "The continuation Fidelity run no longer matches its independently completed write child."
                )
            }
            if parent.snapshot.resynthesisContext == nil {
                throw ResearchFunctionContractError.invalidCompletion(
                    "The continuation Fidelity run lost its Resynthesize preparation evidence."
                )
            }
        }
    }

}

// MARK: - Current evidence and bounded-write validation

extension ResearchFunctionCoordinator {
    private func confirmBoundedWriteSet<Host: ResearchFunctionCoordinatorHost>(
        stored: StoredFunctionRecord,
        snapshot: ResearchFunctionSnapshot,
        completedAt: Date,
        host: isolated Host
    ) async throws -> ResearchFunctionConfirmedWriteSet {
        let writeSet = stored.boundedWriteSet
        let writes = stored.documentWriteRecords
        let resolvedConflictIDs = Set(
            stored.writeConflictResolutionRecords.map(\.conflictOperationID)
        )
        let hasPendingWriteRecovery = try await host.hasPendingResearchWriteRecovery(
            runID: snapshot.runID,
            writes: writes
        )
        guard writeSet.runID == snapshot.runID,
              writeSet.triptychID == workspaceID,
              !writeSet.entries.isEmpty,
              writeSet.entries.allSatisfy({
                  [.ready, .stale, .abandoned].contains($0.state)
              }),
              writes.allSatisfy({
                  ![.writing, .recoveryRequired].contains($0.state)
              }),
              writes.filter({ $0.state == .conflict }).allSatisfy({
                  resolvedConflictIDs.contains($0.id)
              }), !hasPendingWriteRecovery else {
            throw ResearchFunctionContractError.invalidCompletion(
                "Every started bounded document write must have a known, recoverable outcome before Result finalization."
            )
        }
        var currentFingerprints: [UUID: DocumentFingerprint] = [:]
        var references: [ResearchRunWriteNoteReference] = []
        for entry in writeSet.entries {
            let role: ResearchFunctionTargetRole = switch entry.role {
            case .analysis: .analysis
            case .topic: .topic
            case .work: .work
            }
            let target = ResearchFunctionTarget(
                noteID: entry.noteID,
                note: entry.note,
                role: role,
                lifecycle: .active,
                fingerprint: entry.expectedRevision,
                title: entry.title
            )
            let current = try await currentFingerprint(
                for: target,
                host: host
            )
            guard entry.state != .ready || current == entry.expectedRevision else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "A bounded write-set member changed after its last confirmed operation."
                )
            }
            currentFingerprints[entry.noteID] = current
            references.append(try ResearchRunWriteNoteReference(
                noteID: entry.noteID,
                note: entry.note,
                role: role,
                title: entry.title
            ))
        }

        let handlesWithCommittedWrites = Set(writes.compactMap { write in
            write.state == .committed && write.intendedRevision != write.expectedRevision
                ? write.target
                : nil
        })
        let changedIDs = Set(writeSet.entries.compactMap { entry in
            handlesWithCommittedWrites.contains(entry.handle) ? entry.noteID : nil
        })
        let report = try ResearchRunWriteReport(
            runID: snapshot.runID,
            confirmedModifiedNotes: references.filter {
                changedIDs.contains($0.noteID)
            },
            unmodifiedNotes: references.filter {
                !changedIDs.contains($0.noteID)
            },
            observedFingerprints: currentFingerprints,
            completedAt: completedAt
        )
        return ResearchFunctionConfirmedWriteSet(
            report: report,
            currentFingerprints: currentFingerprints
        )
    }

    private func currentFingerprint<Host: ResearchFunctionCoordinatorHost>(
        for target: ResearchFunctionTarget,
        host: isolated Host
    ) async throws -> DocumentFingerprint {
        let currentSnapshot = host.researchFunctionCurrentSnapshot()
        guard let note = currentSnapshot.document(id: target.note),
              note.lifecycle == .active,
              case .resolved(let stableID) = note.stableIdentity,
              stableID == target.noteID,
              ResearchFunctionTargetRole(vaultRole: note.vaultRole) == target.role else {
            throw ResearchFunctionContractError.targetIdentityChanged
        }
        let document = try await repository(vaultID: target.note.vaultID).load(
            relativePath: target.note.relativePath
        )
        return document.fingerprint
    }

    func validateResearchFunctionTarget<Host: ResearchFunctionCoordinatorHost>(
        _ target: ResearchFunctionTarget,
        expected: DocumentFingerprint,
        host: isolated Host
    ) async throws -> ValidatedFunctionObject {
        let currentSnapshot = host.researchFunctionCurrentSnapshot()
        guard let note = currentSnapshot.document(id: target.note) else {
            throw ResearchFunctionContractError.targetUnavailable
        }
        guard case .resolved(let stableID) = note.stableIdentity,
              stableID == target.noteID else {
            throw ResearchFunctionContractError.targetIdentityChanged
        }
        guard note.lifecycle == .active else {
            throw ResearchFunctionContractError.inactiveTarget
        }
        guard let role = ResearchFunctionTargetRole(vaultRole: note.vaultRole),
              role == target.role else {
            throw ResearchFunctionContractError.targetIdentityChanged
        }
        let document = try await repository(vaultID: target.note.vaultID).load(
            relativePath: target.note.relativePath
        )
        guard document.fingerprint == expected else {
            throw ResearchFunctionContractError.targetChanged
        }
        return ValidatedFunctionObject(noteID: stableID, note: note)
    }

    func validateResearchFunctionMaterial<Host: ResearchFunctionCoordinatorHost>(
        _ material: ResearchFunctionMaterial,
        expected: DocumentFingerprint,
        host: isolated Host
    ) async throws -> ValidatedFunctionObject {
        let currentSnapshot = host.researchFunctionCurrentSnapshot()
        guard let note = currentSnapshot.document(id: material.note),
              note.lifecycle == .active,
              case .resolved(let stableID) = note.stableIdentity,
              stableID == material.noteID,
              ResearchFunctionTargetRole(vaultRole: note.vaultRole) == material.role else {
            throw ResearchFunctionContractError.materialChanged(material.title)
        }
        let document = try await repository(vaultID: material.note.vaultID).load(
            relativePath: material.note.relativePath
        )
        guard document.fingerprint == expected else {
            throw ResearchFunctionContractError.materialChanged(material.title)
        }
        return ValidatedFunctionObject(noteID: stableID, note: note)
    }

    func resolveResearchSourceAccess(
        for target: ValidatedFunctionObject
    ) async throws -> ResolvedResearchSourceAccess {
        let resolved = try await resolveResearchSourceBinding(
            analysisNoteID: target.noteID
        )
        guard resolved.reference.identity.route == .zoteroAttachment else {
            return resolved
        }
        guard let itemKey = resolved.reference.identity.zoteroItemKey else {
            throw ResearchFunctionContractError.sourceAccessUnavailable(
                ResearchSourceAccessFailure(code: .zoteroIdentityMismatch)
            )
        }
        let targetItemKey = normalizedTargetZoteroItemKey(target)
        guard targetItemKey == nil || targetItemKey == itemKey else {
            throw ResearchFunctionContractError.sourceAccessUnavailable(
                ResearchSourceAccessFailure(code: .zoteroIdentityMismatch)
            )
        }
        return resolved
    }

    func validateSnapshotResearchSourceAccess(
        _ snapshot: ResearchFunctionSnapshot,
        currentTarget: ValidatedFunctionObject? = nil
    ) async throws -> ResolvedResearchSourceAccess? {
        guard snapshot.request.function == .develop,
              snapshot.request.target.role == .analysis else {
            return nil
        }
        guard let expected = snapshot.sourceReference else {
            throw ResearchFunctionContractError.sourceAccessUnavailable(
                ResearchSourceAccessFailure(code: .missingBinding)
            )
        }
        let resolved: ResolvedResearchSourceAccess
        if let currentTarget {
            resolved = try await resolveResearchSourceAccess(for: currentTarget)
        } else {
            resolved = try await resolveResearchSourceBinding(
                analysisNoteID: snapshot.request.target.noteID
            )
        }
        guard resolved.reference == expected else {
            throw ResearchFunctionContractError.sourceAccessUnavailable(
                ResearchSourceAccessFailure(code: .sourceChanged)
            )
        }
        return resolved
    }

    private func resolveResearchSourceBinding(
        analysisNoteID: UUID
    ) async throws -> ResolvedResearchSourceAccess {
        let resolved: ResolvedResearchSourceAccess
        do {
            resolved = try await dependencies.sourceAccessStore.resolve(
                analysisNoteID: analysisNoteID
            )
        } catch let error as ResearchSourceAccessStoreError {
            throw ResearchFunctionContractError.sourceAccessUnavailable(error.failure)
        }
        guard resolved.reference.identity.route == .zoteroAttachment else {
            return resolved
        }
        guard let itemKey = resolved.reference.identity.zoteroItemKey,
              let attachmentKey = resolved.reference.identity.zoteroAttachmentKey else {
            throw ResearchFunctionContractError.sourceAccessUnavailable(
                ResearchSourceAccessFailure(code: .zoteroIdentityMismatch)
            )
        }
        do {
            let attachment = try await dependencies.zotero.resolveAttachment(
                itemKey: itemKey,
                attachmentKey: attachmentKey
            )
            let currentURL = try validatedZoteroAttachmentURL(attachment.fileURL)
            guard currentURL.path == resolved.fileURL.path else {
                throw ResearchFunctionContractError.sourceAccessUnavailable(
                    ResearchSourceAccessFailure(code: .zoteroIdentityMismatch)
                )
            }
            return resolved
        } catch let error as ResearchFunctionContractError {
            throw error
        } catch let error as ZoteroUseCaseError {
            throw ResearchFunctionContractError.sourceAccessUnavailable(
                ResearchSourceAccessFailure(code: sourceFailureCode(for: error))
            )
        } catch {
            throw ResearchFunctionContractError.sourceAccessUnavailable(
                ResearchSourceAccessFailure(code: .zoteroUnavailable)
            )
        }
    }

    func sourceFailureCode(
        for error: ZoteroUseCaseError
    ) -> ResearchSourceAccessFailureCode {
        switch error {
        case .appUnavailable, .apiDisabled:
            .zoteroUnavailable
        case .itemMissing, .attachmentMissing:
            .zoteroAttachmentMissing
        case .invalidResponse, .invalidItemKey, .invalidAnalysisReference,
             .attachmentIdentityMismatch, .invalidAttachmentURL:
            .zoteroIdentityMismatch
        }
    }

    func validatedZoteroAttachmentURL(_ proposedURL: URL) throws -> URL {
        guard proposedURL.isFileURL,
              proposedURL.host == nil,
              proposedURL.path.hasPrefix("/") else {
            throw ResearchFunctionContractError.sourceAccessUnavailable(
                ResearchSourceAccessFailure(code: .zoteroIdentityMismatch)
            )
        }
        return proposedURL.standardizedFileURL
    }

    func normalizedTargetZoteroItemKey(
        _ target: ValidatedFunctionObject
    ) -> String? {
        guard let key = target.note.document.parsedFrontmatter[
            "zotero_item_key"
        ]?.scalarString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            return nil
        }
        return key.uppercased()
    }

    func repository(vaultID: UUID) throws -> VaultRepository {
        guard let repository = dependencies.repositories[vaultID] else {
            throw ScholiumApplicationError.vaultNotInWorkspace(vaultID)
        }
        return repository
    }

    func vault(id: UUID) throws -> RegisteredVault {
        guard let vault = dependencies.vaults[id] else {
            throw ScholiumApplicationError.vaultNotInWorkspace(id)
        }
        return vault
    }
}
