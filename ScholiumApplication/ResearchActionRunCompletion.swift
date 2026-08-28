import Foundation
import ScholiumContracts
import ScholiumCore

private struct ResearchActionRunConfirmedWriteSet: Sendable {
    let report: ResearchRunWriteReport
    let currentFingerprints: [UUID: DocumentFingerprint]
}

// MARK: - Completion transaction

extension ResearchActionRunCoordinator {
    /// Completes one protected run as a single coordinator-owned transaction.
    /// The coordinator validates current source evidence before committing the
    /// Local Execution transition, then repairs any later portable-record or derived
    /// publication work idempotently on the same submission.
    func completeActionRun<Host: ResearchActionRunCoordinatorHost>(
        _ submission: ResearchActionRunCompletionSubmission,
        acceptedSubmissionDigest: String? = nil,
        candidateResultPayload: ResearchRunResultPayload? = nil,
        host: isolated Host
    ) async throws -> ResearchActionRunCompletion {
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
            throw ResearchActionRunContractError.confirmationMismatch
        }
        if let existing = stored.completion {
            switch existing.state {
            case .complete:
                guard stored.completionSubmissionDigest == submissionDigest else {
                    throw ResearchActionRunContractError.completionAlreadyRecorded(
                        submission.runID
                    )
                }
                try await ensurePortableResearchRecord(
                    completion: existing,
                    stored: stored,
                    confirmedWrite: stored.writeReport
                )
                await host.finalizeResearchAgentRunAccess(runID: existing.runID)
                return existing
            case .cancelled:
                throw ResearchActionRunContractError.completionAlreadyRecorded(submission.runID)
            case .prepared, .unverified, .stale:
                break
            }
        }
        try await validateResearchContinuation(snapshot, stored: stored)
        guard !submission.summary.isEmpty else {
            throw ResearchActionRunContractError.invalidCompletion(
                "A completion summary is required."
            )
        }
        if snapshot.actionSnapshot.actionID == .analyze {
            guard submission.literatureRecommendations.map({ $0.count <= 256 })
                    ?? true else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "Analyze literatureRecommendations must contain at most 256 entries when supplied."
                )
            }
        } else if submission.literatureRecommendations != nil {
            throw ResearchActionRunContractError.invalidCompletion(
                "Only Analyze completion accepts literatureRecommendations."
            )
        }
        if let existing = stored.completion,
           [.unverified, .stale].contains(existing.state),
           (existing.literatureRecommendations != submission.literatureRecommendations
               || existing.actuallyUsedMaterialNoteIDs
                    != submission.actuallyUsedMaterialNoteIDs) {
            throw ResearchActionRunContractError.invalidCompletion(
                "A completion retry cannot replace the Action's recorded recommendation or Material-use testimony."
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

        switch snapshot.request.actionID {
        case .discuss:
            let durableStatements = try await validatedDiscussionStatements(
                snapshot: snapshot
            )
            guard let discussion = stored.discussion,
                  discussion.responseContract.validationIssues.isEmpty,
                  durableStatements.contains(where: { statement in
                      statement.author == .agent
                          && statement.createdAt >= snapshot.preparedAt
                          && !statement.attribution.isEmpty
                          && !statement.text.isEmpty
                  }) else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "Keep a valid stored Discuss response contract and record a durable attributed reply before completing Discuss."
                )
            }
        case .critique, .analyze, .synthesize, .checkFidelity, .write:
            break
        }

        let confirmedWriteSet: ResearchActionRunConfirmedWriteSet?
        let finalTargetFingerprint: DocumentFingerprint
        let finalMaterialFingerprints: [UUID: DocumentFingerprint]
        if snapshot.request.actionID.writesTarget {
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
                _ = try await validateResearchActionMaterial(
                    material,
                    expected: material.fingerprint,
                    host: host
                )
                materialFingerprints[material.noteID] = material.fingerprint
            }
            finalMaterialFingerprints = materialFingerprints
        } else {
            guard let submittedTargetFingerprint = submission.finalTargetFingerprint else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "This Action requires the exact final Target fingerprint."
                )
            }
            confirmedWriteSet = nil
            finalTargetFingerprint = submittedTargetFingerprint
            finalMaterialFingerprints = submission.finalMaterialFingerprints
        }

        let currentTarget = try await validateResearchActionTarget(
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
            throw ResearchActionRunContractError.invalidCompletion(
                "Final Material fingerprints must match the prepared Material set exactly."
            )
        }
        for material in snapshot.request.materials {
            guard finalMaterialFingerprints[material.noteID] == material.fingerprint else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "Material \(material.title) changed during the Action run."
                )
            }
            _ = try await validateResearchActionMaterial(
                material,
                expected: material.fingerprint,
                host: host
            )
        }
        if submission.actuallyUsedMaterialNoteIDs == nil {
            throw ResearchActionRunContractError.invalidCompletion(
                "A current Action completion must explicitly report the Materials actually used, including an empty report."
            )
        }
        let actuallyUsedMaterialNoteIDs = submission.actuallyUsedMaterialNoteIDs ?? []
        guard Set(actuallyUsedMaterialNoteIDs).count == actuallyUsedMaterialNoteIDs.count,
              Set(actuallyUsedMaterialNoteIDs).isSubset(of: materialIDs) else {
            throw ResearchActionRunContractError.invalidCompletion(
                "Actually-used Material identities must be a distinct subset of the prepared Material set."
            )
        }
        let targetChanged = finalTargetFingerprint
            != snapshot.request.target.fingerprint
        let didConfirmTargetWrite = confirmedWriteSet.map { confirmed in
            confirmed.report.confirmedModifiedNotes.contains {
                $0.noteID == snapshot.request.target.noteID
            }
        } ?? targetChanged
        if snapshot.request.actionID.writesTarget {
            guard confirmedWriteSet != nil
                    || submission.didModifyTarget == targetChanged else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "Target modification status does not match its final fingerprint."
                )
            }
        } else {
            guard !submission.didModifyTarget, !targetChanged else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "This read-only Research Action cannot modify its Target."
                )
            }
        }

        let submittedChildRunIDs = submission.childRunIDs ?? []
        switch snapshot.request.actionID {
        case .analyze, .synthesize, .write:
            guard submittedChildRunIDs.isEmpty else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "A write-capable Research Action cannot select a Check Fidelity child run."
                )
            }
        case .discuss, .checkFidelity, .critique:
            guard submittedChildRunIDs.isEmpty else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "This Research Action cannot select child Action runs."
                )
            }
        }
        let requiredChecks: Set<FidelityCheck>
        if snapshot.request.actionID == .checkFidelity {
            requiredChecks = snapshot.request.checks
        } else {
            requiredChecks = []
        }
        func validateFidelityOutcomes(_ outcomes: [FidelityCheckOutcome]) throws {
            let submittedChecks = outcomes.map(\.check)
            for outcome in outcomes { try outcome.validate() }
            guard Set(submittedChecks).count == submittedChecks.count else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "Each Fidelity check may be submitted only once per note."
                )
            }
            guard Set(submittedChecks) == requiredChecks else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "Fidelity outcomes must cover the exact required check set."
                )
            }
            guard !requiredChecks.isEmpty || outcomes.isEmpty else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "This Action has no Fidelity checks."
                )
            }
        }

        let targetSubmissions = submission.fidelityTargetSubmissions ?? []
        let fidelityTargetResults: [ResearchActionFidelityTargetResult]
        if snapshot.request.actionID == .checkFidelity,
           snapshot.request.resolvedFidelityTargets.count > 1 {
            guard submission.fidelityOutcomes.isEmpty else {
                throw ResearchActionRunContractError.invalidCompletion(
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
                throw ResearchActionRunContractError.invalidCompletion(
                    "A shared Fidelity completion requires exactly one result for every prepared note."
                )
            }
            var results: [ResearchActionFidelityTargetResult] = []
            for target in snapshot.request.resolvedFidelityTargets {
                guard let item = submitted[target.noteID],
                      item.note == target.note,
                      item.fingerprint == target.fingerprint else {
                    throw ResearchActionRunContractError.invalidCompletion(
                        "A shared Fidelity result does not match its prepared note revision."
                    )
                }
                _ = try await validateResearchActionTarget(
                    target,
                    expected: target.fingerprint,
                    host: host
                )
                try validateFidelityOutcomes(item.outcomes)
                guard !item.outcomes.isEmpty else {
                    throw ResearchActionRunContractError.invalidCompletion(
                        "Every shared Fidelity target requires attributed outcomes."
                    )
                }
                results.append(ResearchActionFidelityTargetResult(
                    target: target,
                    outcomes: item.outcomes
                ))
            }
            fidelityTargetResults = results
        } else {
            guard targetSubmissions.isEmpty else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "Per-note Fidelity submissions require a shared multi-note Fidelity run."
                )
            }
            try validateFidelityOutcomes(submission.fidelityOutcomes)
            fidelityTargetResults = snapshot.request.actionID == .checkFidelity
                    && !submission.fidelityOutcomes.isEmpty
                ? [ResearchActionFidelityTargetResult(
                    target: snapshot.request.target,
                    outcomes: submission.fidelityOutcomes
                )]
                : []
        }
        if snapshot.request.actionID.writesTarget,
           !submission.fidelityOutcomes.isEmpty {
            throw ResearchActionRunContractError.invalidCompletion(
                "Write-capable runs perform their bounded fidelity self-check in the Method; they cannot submit Check Fidelity outcomes."
            )
        }
        if snapshot.request.actionID != .checkFidelity,
           !targetSubmissions.isEmpty {
            throw ResearchActionRunContractError.invalidCompletion(
                "Only Fidelity accepts per-note target outcomes."
            )
        }

        var state: ResearchActionRunState
        if requiredChecks.isEmpty {
            state = .complete
        } else if snapshot.request.actionID == .checkFidelity,
                  !fidelityTargetResults.isEmpty,
                  fidelityTargetResults.flatMap(\.outcomes).contains(where: {
                      $0.state == .unavailable
                  }) {
            state = .unverified
        } else if submission.fidelityOutcomes.contains(where: { $0.state == .unavailable }) {
            state = .unverified
        } else {
            state = .complete
        }

        let directFidelityEvidenceKey = snapshot.request.actionID == .checkFidelity
                && snapshot.request.resolvedFidelityTargets.count == 1
            ? ResearchFidelityEvidenceKey(
                snapshot: snapshot,
                finalTargetFingerprint: finalTargetFingerprint,
                finalMaterialFingerprints: finalMaterialFingerprints,
                checks: requiredChecks
            )
            : nil
        let evidenceKey = directFidelityEvidenceKey
        let reused: ResearchActionRunCompletion?
        if let evidenceKey, snapshot.request.actionID == .checkFidelity {
            reused = try await completedFidelityEvidence(
                for: evidenceKey,
                excluding: submission.runID
            )
        } else {
            reused = nil
        }
        let outcomes = reused?.fidelityOutcomes
            ?? submission.fidelityOutcomes
        if reused != nil { state = .complete }
        let completion = ResearchActionRunCompletion(
            runID: submission.runID,
            actionID: snapshot.request.actionID,
            state: state,
            recordTitle: stored.completion?.recordTitle ?? submission.recordTitle,
            targetFingerprint: finalTargetFingerprint,
            materialFingerprints: finalMaterialFingerprints,
            actuallyUsedMaterialNoteIDs: submission.actuallyUsedMaterialNoteIDs,
            summary: stored.completion?.summary ?? submission.summary,
            didModifyTarget: didConfirmTargetWrite,
            fidelityOutcomes: outcomes,
            fidelityTargetResults: fidelityTargetResults,
            literatureRecommendations: submission.literatureRecommendations,
            fidelityEvidenceKey: evidenceKey,
            reusedFidelityRunID: reused?.runID,
            childRunIDs: submittedChildRunIDs,
            completedAt: stored.completion?.completedAt ?? submission.submittedAt,
            derivedRefreshWarning: stored.completion?.derivedRefreshWarning
        )
        if snapshot.request.actionID == .analyze {
            let finalCurrentTarget = try await validateResearchActionTarget(
                snapshot.request.target,
                expected: finalTargetFingerprint,
                host: host
            )
            _ = try await validateSnapshotResearchSourceAccess(
                snapshot,
                currentTarget: finalCurrentTarget
            )
        }
        if completion.actionID != .discuss,
           let candidateRecord = try await portableResearchRecord(
                completion: completion,
                stored: stored,
                confirmedWrite: confirmedWriteSet?.report,
                resultPayloadOverride: candidateResultPayload,
           ) {
            do {
                try PortableResearchRecordStore.validateStorageEncoding(
                    of: candidateRecord
                )
            } catch ResearchRecordStoreV1Error.recordTooLarge {
                throw ResearchActionRunContractError.invalidCompletion(
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
        if [.complete, .unverified].contains(completion.state),
           completion.actionID != .discuss {
            try await ensurePortableResearchRecord(
                completion: completion,
                stored: try await record(runID: completion.runID),
                confirmedWrite: confirmedWriteSet?.report
            )
        }

        let refreshWarning = try await host.publishCommittedResearchActionChange(
            "The Research Action completion"
        )
        if [.complete, .unverified, .stale, .cancelled].contains(completion.state) {
            await host.finalizeResearchAgentRunAccess(runID: completion.runID)
        }
        guard let refreshWarning else { return completion }
        return ResearchActionRunCompletion(
            runID: completion.runID,
            actionID: completion.actionID,
            state: completion.state,
            recordTitle: completion.recordTitle,
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

extension ResearchActionRunCoordinator {
    private func completionSubmissionDigest(
        _ submission: ResearchActionRunCompletionSubmission
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys]
        return DocumentFingerprint(data: try encoder.encode(submission)).sha256
    }

    func validatedDiscussionStatements(
        snapshot: ResearchActionRunSnapshot
    ) async throws -> [PortableResearchStatement] {
        let expected = try ResearchDiscussionFactory.make(
            snapshot: snapshot,
            triptychID: workspaceID
        )
        if let active = try await dependencies.portableResearchRecordStore
            .activeDiscussionIfPresent(id: snapshot.runID) {
            guard ResearchDiscussionFactory.activeMatches(active, expected: expected) else {
                throw ResearchActionRunContractError.invalidCompletion(
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
                throw ResearchActionRunContractError.invalidCompletion(
                    "The finished Discussion no longer matches its frozen Action run."
                )
            }
            return finished.statements
        } catch ResearchRecordStoreV1Error.recordNotFound(_) {
            throw ResearchActionRunContractError.invalidCompletion(
                "Record a durable attributed reply before completing Discuss."
            )
        }
    }

    private func ensurePortableResearchRecord(
        completion: ResearchActionRunCompletion,
        stored: LocalResearchExecutionRecord,
        confirmedWrite: ResearchRunWriteReport?
    ) async throws {
        guard [.complete, .unverified].contains(completion.state) else { return }
        do {
            _ = try await dependencies.portableResearchRecordStore.record(
                id: completion.runID
            )
            _ = try await dependencies.localExecutionStore.compactCompleted(
                runID: completion.runID
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
            _ = try await dependencies.localExecutionStore.compactCompleted(
                runID: completion.runID
            )
        } catch ResearchRecordStoreV1Error.recordPermanentlyDeleted(let id)
            where id == completion.runID {
            throw ResearchActionRunContractError.invalidCompletion(
                "The Research Record for this Action was permanently deleted and cannot be recreated."
            )
        } catch ResearchRecordStoreV1Error.recordTooLarge {
            throw ResearchActionRunContractError.invalidCompletion(
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
            throw ResearchActionRunContractError.invalidCompletion(
                "Literature Recommendations cannot persist the transient machine-local source locator."
            )
        }
    }

    private func portableResearchRecord(
        completion: ResearchActionRunCompletion,
        stored: LocalResearchExecutionRecord,
        confirmedWrite: ResearchRunWriteReport?,
        resultPayloadOverride: ResearchRunResultPayload? = nil
    ) async throws -> PortableResearchRecord? {
        guard [.complete, .unverified].contains(completion.state),
              completion.actionID != .discuss else {
            return nil
        }
        let actionSnapshot = stored.snapshot.actionSnapshot
        guard let resultPayload = resultPayloadOverride ?? stored.resultPayload,
              resultPayload.runID == completion.runID else {
            throw ResearchActionRunContractError.invalidCompletion(
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
        var firstCommittedWrites: [UUID: ResearchDocumentWriteRecord] = [:]
        for entry in stored.boundedWriteSet.entries {
            if entry.expectsAbsence { continue }
            let firstCommitted = writeRecords
                .filter {
                    $0.target == entry.handle
                        && $0.actor == .agent
                        && $0.state == .committed
                }
                .min(by: { $0.startedAt < $1.startedAt })
            if let firstCommitted {
                firstCommittedWrites[entry.noteID] = firstCommitted
            }
            if noteSnapshots[entry.noteID] == nil {
                let startingRevision: DocumentFingerprint?
                if firstCommitted?.operation == .createNote {
                    startingRevision = firstCommitted?.observedRevision
                } else {
                    startingRevision = entry.expectedRevision
                }
                guard let startingRevision else {
                    throw ResearchActionRunContractError.invalidCompletion(
                        "A created bounded-write participant has no committed revision."
                    )
                }
                noteSnapshots[entry.noteID] = ResearchActionNoteSnapshot(
                    noteID: entry.noteID,
                    note: entry.note,
                    role: entry.role,
                    fingerprint: startingRevision,
                    title: entry.title
                )
            }
        }

        var endingRevisions: [UUID: DocumentFingerprint] = [:]
        endingRevisions[snapshot.request.target.noteID] = completion.targetFingerprint
        for (noteID, fingerprint) in completion.materialFingerprints {
            endingRevisions[noteID] = fingerprint
        }
        for (noteID, fingerprint) in confirmedWrite?.observedFingerprints ?? [:] {
            endingRevisions[noteID] = fingerprint
        }
        var changes: [PortableResearchConfirmedChange] = []
        if let confirmedWrite {
            for note in confirmedWrite.confirmedModifiedNotes {
                guard let firstCommitted = firstCommittedWrites[note.noteID],
                      let ending = confirmedWrite.observedFingerprints[note.noteID]
                else { continue }
                let starting = firstCommitted.operation == .createNote
                    ? nil
                    : firstCommitted.expectedRevision
                guard starting.map({ $0 != ending }) ?? true else { continue }
                changes.append(try PortableResearchConfirmedChange(
                    noteID: note.noteID,
                    actor: .agent,
                    startingRevision: starting,
                    endingRevision: ending
                ))
            }
        }
        let discrepancies: [PortableResearchDiscrepancy] = []

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
            throw ResearchActionRunContractError.invalidCompletion(
                "A current Action completion has no explicit actually-used Material report."
            )
        }
        let actuallyUsedMaterials = try actuallyUsedMaterialNoteIDs
            .map { noteID -> PortableResearchMaterialUse in
                guard let material = materialsByID[noteID] else {
                    throw ResearchActionRunContractError.invalidCompletion(
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
        var participantIDs: Set<UUID> = [actionSnapshot.target.noteID]
        participantIDs.formUnion(changes.map(\.noteID))
        participantIDs.formUnion(actuallyUsedMaterials.map(\.noteID))
        for entry in resultPayload.contextUseReport?.entries ?? []
            where entry.sourceReference.owner.kind == .note {
            let owner = entry.sourceReference.owner
            guard owner.triptychID == workspaceID,
                  let stableID = UUID(uuidString: owner.stableObjectIdentity),
                  let note = noteSnapshots[stableID],
                  note.note.vaultID == owner.vaultID,
                  note.note.relativePath == owner.relativePath else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "An actually-used Note reference is outside the frozen Action authority."
                )
            }
            participantIDs.insert(note.noteID)
        }
        let participatingNotes = try participantIDs.map { noteID in
            guard let note = noteSnapshots[noteID] else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "A factual Research Record participant is outside the frozen Action authority."
                )
            }
            return try PortableResearchNoteRevision(
                noteID: note.noteID,
                note: note.note,
                role: note.role,
                title: note.title,
                startingRevision: note.fingerprint,
                endingRevision: endingRevisions[note.noteID] ?? note.fingerprint
            )
        }
        let recommendationSubmissions: [ResearchLiteratureRecommendationSubmission]
        if actionSnapshot.actionID == .analyze {
            guard completion.literatureRecommendations.map({ $0.count <= 256 })
                    ?? true else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "Analyze literatureRecommendations must contain at most 256 entries when supplied."
                )
            }
            recommendationSubmissions = completion.literatureRecommendations ?? []
        } else {
            guard completion.literatureRecommendations == nil else {
                throw ResearchActionRunContractError.invalidCompletion(
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
            title: completion.recordTitle,
            kind: .action,
            action: ResearchActionRecordIdentity(snapshot: actionSnapshot),
            method: try PortableResearchMethodReference(snapshot: actionSnapshot),
            sourceReference: snapshot.sourceReference,
            zoteroBibliographicContext: snapshot.zoteroBibliographicContext,
            analysisSourceRoute: snapshot.analysisSourceRoute,
            continuationLineage: snapshot.continuationLineage,
            primaryNoteID: actionSnapshot.target.noteID,
            participatingNotes: participatingNotes,
            statements: [],
            resultDisposition: resultPayload.disposition,
            academicResults: academicResults,
            contextUseReport: resultPayload.contextUseReport,
            actuallyUsedMaterials: actuallyUsedMaterials,
            fidelityCompletion: try portableFidelityCompletion(for: completion),
            confirmedChanges: changes,
            discrepancies: discrepancies,
            literatureRecommendations: literatureRecommendations,
            startedAt: snapshot.preparedAt,
            finishedAt: completion.completedAt
        )
    }

    private func portableFidelityCompletion(
        for completion: ResearchActionRunCompletion
    ) throws -> PortableResearchFidelityCompletion {
        switch completion.state {
        case .complete:
            return completion.fidelityEvidenceKey == nil ? .notRequired : .completed
        case .unverified:
            guard completion.fidelityEvidenceKey != nil else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "An unverified Action record requires exact-revision Fidelity evidence."
                )
            }
            return .unverified
        case .prepared, .stale, .cancelled:
            throw ResearchActionRunContractError.invalidCompletion(
                "Only a complete or unverified Action can create a portable Research Record."
            )
        }
    }
}

// MARK: - Durable record and Fidelity evidence

extension ResearchActionRunCoordinator {
    /// Reads durable evidential authorities directly. A Workspace snapshot is
    /// disposable and may remain at its last-known-good generation after a
    /// committed refresh failure.
    func authoritativeActionRecords() async throws
        -> [ResearchActionRunRecordProjection] {
        let localRecords = try await dependencies.localExecutionStore.listing().records
        let local = localRecords.map {
            ResearchActionRunRecordProjection(
                snapshot: $0.snapshot,
                completion: $0.completion,
                preparedInstructions: $0.preparedInstructions
            )
        }
        var projected: [ResearchActionRunRecordProjection] = []
        projected.reserveCapacity(local.count)
        for record in local {
            projected.append(try await projectCurrentActionRecord(record))
        }
        return projected.sorted {
            if $0.snapshot.preparedAt != $1.snapshot.preparedAt {
                return $0.snapshot.preparedAt > $1.snapshot.preparedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func projectCurrentActionRecord(
        _ record: ResearchActionRunRecordProjection
    ) async throws -> ResearchActionRunRecordProjection {
        guard let completion = record.completion,
              completion.state != .cancelled,
              completion.state != .stale else {
            return record
        }
        guard try await functionCompletionIsCurrent(
            completion,
            snapshot: record.snapshot
        ) else {
            return ResearchActionRunRecordProjection(
                snapshot: record.snapshot,
                completion: ResearchActionRunCompletion(
                    runID: completion.runID,
                    actionID: completion.actionID,
                    state: .stale,
                    recordTitle: completion.recordTitle,
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
        _ completion: ResearchActionRunCompletion,
        snapshot: ResearchActionRunSnapshot
    ) async throws -> Bool {
        do {
            guard try await functionObjectIsCurrent(
                noteID: snapshot.request.target.noteID,
                note: snapshot.request.target.note,
                role: snapshot.request.target.role,
                fingerprint: completion.targetFingerprint
            ) else { return false }

            guard Set(completion.materialFingerprints.keys)
                    == Set(snapshot.request.materials.map(\.noteID)) else {
                return false
            }
            let actuallyUsedIDs: [UUID]
            if let reported = completion.actuallyUsedMaterialNoteIDs {
                actuallyUsedIDs = reported
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
                          fingerprint: fingerprint
                      ) else { return false }
            }

            return true
        } catch {
            // Missing, unreadable, moved, or identity-mismatched evidence is
            // stale for planning. The durable record remains untouched.
            return false
        }
    }

    private func functionObjectIsCurrent(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        fingerprint: DocumentFingerprint
    ) async throws -> Bool {
        guard let identity = try await dependencies.controlStore.identityRecord(
            vaultID: note.vaultID,
            relativePath: note.relativePath
        ), identity.id == noteID,
              ResearchActionTargetRole(vaultRole: try vault(id: note.vaultID).role) == role else {
            return false
        }
        let document = try await repository(vaultID: note.vaultID)
            .load(relativePath: note.relativePath)
        return document.fingerprint == fingerprint
    }

    func completedFidelityEvidence(
        for key: ResearchFidelityEvidenceKey,
        excluding runID: UUID?
    ) async throws -> ResearchActionRunCompletion? {
        try await authoritativeActionRecords().first { record in
            guard record.snapshot.request.actionID == .checkFidelity,
                  let completion = record.completion else {
                return false
            }
            return completion.runID != runID
                && completion.state == .complete
                && completion.fidelityEvidenceKey == key
                && !completion.fidelityOutcomes.isEmpty
        }?.completion
    }

}

// MARK: - Continuation validation

extension ResearchActionRunCoordinator {
    private func validateResearchContinuation(
        _ snapshot: ResearchActionRunSnapshot,
        stored: LocalResearchExecutionRecord
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
                throw ResearchActionRunContractError.invalidCompletion(
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
                  snapshot.request.actionID == .synthesize,
                  snapshot.actionSnapshot.actionID == .synthesize,
                  snapshot.actionSnapshot.authority.writableNotes
                    == [snapshot.actionSnapshot.target],
                  snapshot.request.materials.contains(where: {
                      $0.noteID == context.materialNoteID
                          && $0.role == .analysis
                          && $0.note.vaultID == context.material.vaultID
                          && $0.note.relativePath == context.material.relativePath
                          && $0.fingerprint == context.currentRevision
                  }),
                  let evidence = try? await dependencies.agentChangeEvidenceStore
                    .evidence(
                        runID: snapshot.runID,
                        noteID: snapshot.request.target.noteID
                    ),
                  evidence.triptychID == workspaceID,
                  evidence.runID == snapshot.runID,
                  evidence.noteID == snapshot.request.target.noteID,
                  evidence.startingRevision == snapshot.request.target.fingerprint else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "The Resynthesize child no longer matches its exact revision pair, Target, Material, or Agent change evidence."
                )
            }
        }
    }

}

// MARK: - Current evidence and bounded-write validation

extension ResearchActionRunCoordinator {
    private func confirmBoundedWriteSet<Host: ResearchActionRunCoordinatorHost>(
        stored: LocalResearchExecutionRecord,
        snapshot: ResearchActionRunSnapshot,
        completedAt: Date,
        host: isolated Host
    ) async throws -> ResearchActionRunConfirmedWriteSet {
        let writeSet = stored.boundedWriteSet
        let writes = stored.documentWriteRecords
        let bindingWrites = stored.zoteroBindingWriteRecords
        let resolvedConflictIDs = Set(
            stored.writeConflictResolutionRecords.map(\.conflictOperationID)
        )
        let hasPendingWriteRecovery = try await host.hasPendingResearchWriteRecovery(
            runID: snapshot.runID,
            writes: writes
        )
        var blockers: [String] = []
        if writeSet.runID != snapshot.runID || writeSet.triptychID != workspaceID {
            blockers.append("write-set identity")
        }
        if writeSet.entries.isEmpty { blockers.append("empty write set") }
        if !writeSet.entries.allSatisfy({
            [.ready, .consumed, .stale, .abandoned].contains($0.state)
        }) { blockers.append("unfinished target") }
        if !writes.allSatisfy({
            ![.writing, .recoveryRequired].contains($0.state)
        }) { blockers.append("unfinished document write") }
        if !bindingWrites.allSatisfy({
            ![.writing, .recoveryRequired].contains($0.state)
        }) { blockers.append("unfinished binding write") }
        if !writes.filter({ $0.state == .conflict }).allSatisfy({
            resolvedConflictIDs.contains($0.id)
        }) { blockers.append("unresolved conflict") }
        if hasPendingWriteRecovery { blockers.append("pending recovery") }
        guard blockers.isEmpty else {
            throw ResearchActionRunContractError.invalidCompletion(
                "Every started bounded document or Zotero-binding write must have a known, recoverable outcome before Result finalization. Blocked by: \(blockers.joined(separator: ", "))."
            )
        }
        var currentFingerprints: [UUID: DocumentFingerprint] = [:]
        var references: [ResearchRunWriteNoteReference] = []
        for entry in writeSet.entries {
            if entry.expectsAbsence { continue }
            guard let expectedRevision = entry.expectedRevision else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "A bounded-write participant has no current committed revision."
                )
            }
            let role: ResearchActionTargetRole = switch entry.role {
            case .analysis: .analysis
            case .topic: .topic
            case .work: .work
            }
            let target = ResearchActionNoteSnapshot(
                noteID: entry.noteID,
                note: entry.note,
                role: role,
                fingerprint: expectedRevision,
                title: entry.title
            )
            let current = try await currentFingerprint(
                for: target,
                host: host
            )
            guard ![.ready, .consumed].contains(entry.state)
                    || current == expectedRevision else {
                throw ResearchActionRunContractError.invalidCompletion(
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
        return ResearchActionRunConfirmedWriteSet(
            report: report,
            currentFingerprints: currentFingerprints
        )
    }

    private func currentFingerprint<Host: ResearchActionRunCoordinatorHost>(
        for target: ResearchActionNoteSnapshot,
        host: isolated Host
    ) async throws -> DocumentFingerprint {
        try await host.researchActionControlledFingerprint(for: target)
    }

    func validateResearchActionTarget<Host: ResearchActionRunCoordinatorHost>(
        _ target: ResearchActionNoteSnapshot,
        expected: DocumentFingerprint,
        host: isolated Host
    ) async throws -> ValidatedActionNote {
        guard try await host.researchActionControlledFingerprint(for: target)
                == expected else {
            throw ResearchActionRunContractError.targetChanged
        }
        let currentSnapshot = host.researchActionCurrentSnapshot()
        guard let note = currentSnapshot.document(id: target.note) else {
            throw ResearchActionRunContractError.targetUnavailable
        }
        guard case .resolved(let stableID) = note.stableIdentity,
              stableID == target.noteID else {
            throw ResearchActionRunContractError.targetIdentityChanged
        }
        guard let role = ResearchActionTargetRole(vaultRole: note.vaultRole),
              role == target.role else {
            throw ResearchActionRunContractError.targetIdentityChanged
        }
        return ValidatedActionNote(noteID: stableID, note: note)
    }

    func validateResearchActionMaterial<Host: ResearchActionRunCoordinatorHost>(
        _ material: ResearchActionNoteSnapshot,
        expected: DocumentFingerprint,
        host: isolated Host
    ) async throws -> ValidatedActionNote {
        let controlledTarget = ResearchActionNoteSnapshot(
            noteID: material.noteID,
            note: material.note,
            role: material.role,
            fingerprint: material.fingerprint,
            title: material.title
        )
        do {
            guard try await host.researchActionControlledFingerprint(
                for: controlledTarget
            ) == expected else {
                throw ResearchActionRunContractError.materialChanged(material.title)
            }
        } catch {
            throw ResearchActionRunContractError.materialChanged(material.title)
        }
        let currentSnapshot = host.researchActionCurrentSnapshot()
        guard let note = currentSnapshot.document(id: material.note),
              case .resolved(let stableID) = note.stableIdentity,
              stableID == material.noteID,
              ResearchActionTargetRole(vaultRole: note.vaultRole) == material.role else {
            throw ResearchActionRunContractError.materialChanged(material.title)
        }
        return ValidatedActionNote(noteID: stableID, note: note)
    }

    func resolveResearchSourceAccess(
        for target: ValidatedActionNote
    ) async throws -> ResolvedResearchSourceAccess {
        let resolved = try await resolveResearchSourceBinding(
            analysisNoteID: target.noteID
        )
        guard resolved.reference.identity.route == .zoteroAttachment else {
            return resolved
        }
        guard let itemKey = resolved.reference.identity.zoteroItemKey else {
            throw ResearchActionRunContractError.sourceAccessUnavailable(
                ResearchSourceAccessFailure(code: .zoteroIdentityMismatch)
            )
        }
        let targetBinding = try await portableTargetZoteroBinding(target)
        guard targetBinding == nil || targetBinding?.itemKey == itemKey else {
            throw ResearchActionRunContractError.sourceAccessUnavailable(
                ResearchSourceAccessFailure(code: .zoteroIdentityMismatch)
            )
        }
        return resolved
    }

    func validateSnapshotResearchSourceAccess(
        _ snapshot: ResearchActionRunSnapshot,
        currentTarget: ValidatedActionNote? = nil
    ) async throws -> ResolvedResearchSourceAccess? {
        guard snapshot.request.actionID == .analyze else {
            return nil
        }
        switch snapshot.analysisSourceRoute {
        case .researcherProvided:
            guard snapshot.sourceReference == nil,
                  snapshot.zoteroBibliographicContext == nil else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "A researcher-provided source route cannot claim Scholium source or Zotero context."
                )
            }
            return nil
        case .externalZotero:
            guard snapshot.sourceReference == nil,
                  snapshot.zoteroBibliographicContext != nil else {
                throw ResearchActionRunContractError.sourceAccessUnavailable(
                    ResearchSourceAccessFailure(code: .missingBinding)
                )
            }
            return nil
        case .scholiumSource:
            break
        case nil:
            throw ResearchActionRunContractError.sourceAccessUnavailable(
                ResearchSourceAccessFailure(code: .missingBinding)
            )
        }
        guard let expected = snapshot.sourceReference else {
            throw ResearchActionRunContractError.sourceAccessUnavailable(
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
            throw ResearchActionRunContractError.sourceAccessUnavailable(
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
            throw ResearchActionRunContractError.sourceAccessUnavailable(error.failure)
        }
        guard resolved.reference.identity.route == .zoteroAttachment else {
            return resolved
        }
        guard let itemKey = resolved.reference.identity.zoteroItemKey,
              let attachmentKey = resolved.reference.identity.zoteroAttachmentKey else {
            throw ResearchActionRunContractError.sourceAccessUnavailable(
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
                throw ResearchActionRunContractError.sourceAccessUnavailable(
                    ResearchSourceAccessFailure(code: .zoteroIdentityMismatch)
                )
            }
            return resolved
        } catch let error as ResearchActionRunContractError {
            throw error
        } catch let error as ZoteroUseCaseError {
            throw ResearchActionRunContractError.sourceAccessUnavailable(
                ResearchSourceAccessFailure(code: sourceFailureCode(for: error))
            )
        } catch {
            throw ResearchActionRunContractError.sourceAccessUnavailable(
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
            throw ResearchActionRunContractError.sourceAccessUnavailable(
                ResearchSourceAccessFailure(code: .zoteroIdentityMismatch)
            )
        }
        return proposedURL.standardizedFileURL
    }

    func portableTargetZoteroBinding(
        _ target: ValidatedActionNote
    ) async throws -> AnalysisZoteroBinding? {
        try await dependencies.controlStore.zoteroBindings()
            .binding(for: target.noteID)
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
