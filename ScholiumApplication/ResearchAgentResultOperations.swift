import Foundation
import ScholiumContracts
import ScholiumCore

struct WorkspaceResearchAgentResultDependencies: Sendable {
    let researchAgentSessions: ResearchAgentSessionAuthority?
    let localResearchExecutionStore: LocalResearchExecutionStore
    let portableResearchRecordStore: PortableResearchRecordStore
    let researchSourceAccessStore: ResearchSourceAccessStore
}

extension WorkspaceServices {
    var researchAgentResultDependencies:
        WorkspaceResearchAgentResultDependencies {
        WorkspaceResearchAgentResultDependencies(
            researchAgentSessions: researchAgentSessions,
            localResearchExecutionStore: localResearchExecutionStore,
            portableResearchRecordStore: portableResearchRecordStore,
            researchSourceAccessStore: researchSourceAccessStore
        )
    }
}

extension WorkspaceRuntime {
    public func submitResearchAgentResult(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        submission: ResearchAgentResultSubmission
    ) async throws -> ResearchAgentResultReceipt {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false,
            allowFinalized: true
        )
        let handle = try await openWorkspace(id: authenticated.triptychID)
        return try await handle.submitResearchAgentResult(
            credential: credential,
            run: run,
            submission: submission
        )
    }
}

extension ResearchOperations {
    public func submitAgentResult(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        submission: ResearchAgentResultSubmission
    ) async throws -> ResearchAgentResultReceipt {
        let handle = try await reference.requireHandle()
        return try await handle.submitResearchAgentResult(
            credential: credential,
            run: run,
            submission: submission
        )
    }
}

extension WorkspaceHandle {
    func submitResearchAgentResult(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        submission: ResearchAgentResultSubmission
    ) async throws -> ResearchAgentResultReceipt {
        try requireActive()
        guard let sessions = researchAgentResultDependencies.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false,
            allowFinalized: true
        )
        guard authenticated.triptychID == self.id else {
            throw ResearchAgentSessionError.sessionRejected
        }

        let submissionFingerprint = try submission.contentFingerprint()
        let stored: LocalResearchExecutionRecord
        do {
            stored = try await researchAgentResultDependencies.localResearchExecutionStore.record(
                id: authenticated.runID
            )
        } catch LocalResearchExecutionStoreError.executionNotFound(let id) {
            guard await researchAgentResultDependencies.portableResearchRecordStore
                .isRecordPermanentlyDeleted(id: id) else {
                throw LocalResearchExecutionStoreError.executionNotFound(id)
            }
            throw ResearchFunctionContractError.invalidCompletion(
                "The Research Record for this Action was permanently deleted and cannot be recreated."
            )
        }
        guard stored.triptychID == self.id,
              let action = stored.snapshot.actionSnapshot,
              action.actionID != .discuss else {
            throw ResearchAgentConnectionError.runUnavailable
        }
        if let existing = stored.resultPayload {
            guard existing.submissionFingerprint == submissionFingerprint else {
                throw ResearchAgentResultContractError.resultAlreadySubmitted
            }
            if let completion = stored.completion,
               completion.state != .awaitingFidelity {
                let reconciled = try await researchFunctionCoordinator
                    .completeProtectedFunction(
                        ResearchFunctionCompletionSubmission(
                            runID: authenticated.runID,
                            confirmationToken: stored.snapshot.confirmationToken,
                            recordTitle: existing.recordTitle,
                            finalTargetFingerprint: completion.targetFingerprint,
                            finalMaterialFingerprints: completion.materialFingerprints,
                            actuallyUsedMaterialNoteIDs:
                                completion.actuallyUsedMaterialNoteIDs,
                            summary: completion.summary,
                            didModifyTarget: completion.didModifyTarget,
                            fidelityOutcomes: existing.fidelityOutcomes,
                            literatureRecommendations:
                                existing.literatureRecommendations,
                            childRunIDs: completion.childRunIDs ?? [],
                            submittedAt: existing.submittedAt
                        ),
                        acceptedSubmissionDigest:
                            existing.submissionFingerprint.sha256,
                        host: self
                    )
                let parent = try await researchFunctionCoordinator
                    .advanceAutomaticFidelityParent(
                        childRunID: reconciled.runID,
                        host: self
                    )
                return try resultReceipt(
                    disposition: existing.disposition,
                    completion: reconciled,
                    automaticParentCompletion: parent
                )
            }
        }

        let academicResults = try validateAcademicResults(
            submission.academicResults,
            disposition: submission.disposition,
            contract: action.resultContract,
            actionID: action.actionID,
            fidelityOutcomes: submission.fidelityOutcomes
        )
        let fidelityContract = try await authenticatedFidelityContract(
            for: stored
        )
        try validateActionSpecificResultShape(
            submission,
            action: action,
            fidelityChecks: stored.snapshot.request.checks,
            requiredUnavailableChecks:
                fidelityContract?.requiredUnavailableChecks ?? []
        )
        let contextUseReport = try await verifiedContextUseReport(
            claims: submission.contextUseClaims,
            runID: authenticated.runID,
            triptychID: authenticated.triptychID,
            snapshot: stored.snapshot
        )
        let submittedAt = stored.resultPayload?.submittedAt ?? Date()
        let payload = try ResearchRunResultPayload(
            runID: authenticated.runID,
            submissionFingerprint: submissionFingerprint,
            recordTitle: submission.recordTitle,
            disposition: submission.disposition,
            academicResults: academicResults,
            contextUseReport: contextUseReport,
            fidelityOutcomes: submission.fidelityOutcomes,
            literatureRecommendations: submission.literatureRecommendations,
            submittedAt: submittedAt
        )
        if let existing = stored.resultPayload, existing != payload {
            throw ResearchAgentResultContractError.resultAlreadySubmitted
        }

        let target = try await exactCurrentNote(action.target)
        var materialFingerprints: [UUID: DocumentFingerprint] = [:]
        for material in stored.snapshot.request.materials {
            let current = try await exactCurrentMaterial(material)
            guard current.fingerprint == material.fingerprint else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "A frozen Material changed before Result finalization."
                )
            }
            materialFingerprints[material.noteID] = current.fingerprint
        }
        let actuallyUsedMaterialIDs = contextUseReport.map {
            actuallyUsedMaterialIDs(from: $0, in: stored.snapshot.request.materials)
        } ?? []
        let completionSubmission = ResearchFunctionCompletionSubmission(
            runID: authenticated.runID,
            confirmationToken: stored.snapshot.confirmationToken,
            recordTitle: submission.recordTitle,
            finalTargetFingerprint: target.fingerprint,
            finalMaterialFingerprints: materialFingerprints,
            actuallyUsedMaterialNoteIDs: actuallyUsedMaterialIDs,
            summary: resultSummary(
                academicResults,
                contract: action.resultContract,
                disposition: submission.disposition
            ),
            didModifyTarget: false,
            fidelityOutcomes: submission.fidelityOutcomes,
            literatureRecommendations: submission.literatureRecommendations,
            submittedAt: submittedAt
        )
        let completion = try await researchFunctionCoordinator
            .completeProtectedFunction(
                completionSubmission,
                acceptedSubmissionDigest: submissionFingerprint.sha256,
                candidateResultPayload: payload,
                host: self
            )
        let parent = try await researchFunctionCoordinator
            .advanceAutomaticFidelityParent(
                childRunID: completion.runID,
                host: self
            )
        return try resultReceipt(
            disposition: submission.disposition,
            completion: completion,
            automaticParentCompletion: parent
        )
    }

    private func validateAcademicResults(
        _ submitted: ResearchAcademicFieldValues,
        disposition: ResearchAgentResultDisposition,
        contract: ResearchResultContract,
        actionID: ResearchActionID,
        fidelityOutcomes: [FidelityCheckOutcome]
    ) throws -> ResearchAcademicFieldValues {
        let defaultFidelityFields = ResearchAcademicProfileCatalog
            .defaultProfiles.first(where: { $0.actionID == .checkFidelity })?
            .academicResultFields ?? []
        let values: ResearchAcademicFieldValues
        if actionID == .checkFidelity,
           contract.academicFields == defaultFidelityFields {
            guard submitted.values.isEmpty else {
                throw ResearchAgentResultContractError.invalidSubmission
            }
            values = try Self.derivedDefaultFidelityAcademicResults(
                from: fidelityOutcomes,
                definitions: contract.academicFields
            )
        } else {
            values = submitted
        }
        if disposition == .completed {
            let validated = try ResearchAcademicFieldValues(
                rawValues: values.values,
                definitions: contract.academicFields
            )
            try ResearchAcademicProfileCatalog.validatePlatformResultRules(
                validated,
                actionID: contract.actionID
            )
            return validated
        }
        let byID = Dictionary(uniqueKeysWithValues: contract.academicFields.map {
            ($0.fieldID.rawValue, $0)
        })
        guard values.values.keys.allSatisfy({ byID[$0] != nil }) else {
            throw ResearchAcademicProfileError.invalidFieldValues
        }
        for (fieldID, value) in values.values {
            guard let definition = byID[fieldID] else {
                throw ResearchAcademicProfileError.invalidFieldValues
            }
            _ = try ResearchAcademicFieldValues(
                rawValues: [fieldID: value],
                definitions: [definition]
            )
        }
        let validated = try ResearchAcademicFieldValues(
            rawValues: values.values,
            definitions: values.values.keys.compactMap { byID[$0] }
        )
        try ResearchAcademicProfileCatalog.validatePlatformResultRules(
            validated,
            actionID: contract.actionID
        )
        return validated
    }

    private static func derivedDefaultFidelityAcademicResults(
        from outcomes: [FidelityCheckOutcome],
        definitions: [ResearchAcademicFieldDefinition]
    ) throws -> ResearchAcademicFieldValues {
        let ordered = outcomes.sorted { $0.check.rawValue < $1.check.rawValue }
        let finding = ordered.map { outcome in
            let findings = outcome.findings.isEmpty
                ? ""
                : " Findings: " + outcome.findings.joined(separator: "; ")
            return "\(outcome.check.rawValue): \(outcome.summary)\(findings)"
        }.joined(separator: "\n")
        let status: String
        if ordered.contains(where: { $0.state == .issuesFound }) {
            status = "inconsistency-found"
        } else if ordered.contains(where: { $0.state == .unavailable }) {
            status = "unable-to-verify"
        } else {
            status = "no-inconsistency-in-checked-scope"
        }
        var raw: [String: ResearchAcademicFieldValue] = [
            "finding": .freeText(finding),
            "finding-status": .singleChoice(status),
        ]
        let corrections = ordered.flatMap(\.findings)
        if !corrections.isEmpty {
            raw["suggested-correction"] = .freeText(
                corrections.joined(separator: "\n")
            )
        }
        return try ResearchAcademicFieldValues(
            rawValues: raw,
            definitions: definitions
        )
    }

    private func validateActionSpecificResultShape(
        _ submission: ResearchAgentResultSubmission,
        action: ResearchActionSnapshot,
        fidelityChecks: Set<FidelityCheck>,
        requiredUnavailableChecks: Set<FidelityCheck>
    ) throws {
        if action.actionID == .analyze {
            guard submission.literatureRecommendations.map({ $0.count <= 256 })
                    ?? true else {
                throw ResearchAgentResultContractError.invalidSubmission
            }
        } else if submission.literatureRecommendations != nil {
            throw ResearchAgentResultContractError.invalidSubmission
        }
        if action.actionID == .checkFidelity {
            let expected = fidelityChecks
            let submitted = submission.fidelityOutcomes.map(\.check)
            guard Set(submitted).count == submitted.count,
                  Set(submitted) == expected else {
                throw ResearchAgentResultContractError.invalidSubmission
            }
            for outcome in submission.fidelityOutcomes {
                try outcome.validate()
                if requiredUnavailableChecks.contains(outcome.check),
                   outcome.state != .unavailable {
                    throw ResearchAgentResultContractError.invalidSubmission
                }
            }
        } else if !submission.fidelityOutcomes.isEmpty {
            throw ResearchAgentResultContractError.invalidSubmission
        }
    }

    private func verifiedContextUseReport(
        claims: [ResearchContextUseClaim],
        runID: UUID,
        triptychID: UUID,
        snapshot: ResearchFunctionSnapshot
    ) async throws -> ContextUseReport? {
        guard !claims.isEmpty else { return nil }
        var entries: [ContextUseEntry] = []
        for claim in claims {
            let reference = claim.sourceReference
            guard reference.authorizedScope.runID == runID,
                  reference.authorizedScope.triptychID == triptychID,
                  reference.owner.triptychID == triptychID,
                  reference.currentness == .current else {
                throw ResearchAgentResultContractError.invalidContextUse
            }
            let facts: [ContextUseVerificationFact]
            switch reference.sourceKind {
            case .note:
                facts = try await verifyNoteReference(reference)
            case .record:
                facts = try await verifyRecordReference(reference)
            case .material:
                facts = try await verifyMaterialReference(
                    reference,
                    snapshot: snapshot
                )
            case .researcherState:
                guard let action = snapshot.actionSnapshot else {
                    throw ResearchAgentResultContractError.invalidContextUse
                }
                guard try FoundationResearchContextProvider()
                    .isCurrentResearcherStateReference(
                        reference,
                        action: action,
                        workspace: currentSnapshot
                    ) else {
                    throw ResearchAgentResultContractError.invalidContextUse
                }
                facts = [
                    .authoritativeOwnerRead,
                    .revisionMatched,
                    .locatorResolved,
                ]
            }
            entries.append(try ContextUseEntry(
                sourceReference: reference,
                verificationFacts: facts,
                testimony: claim.testimony
            ))
        }
        return try ContextUseReport(
            runID: runID,
            triptychID: triptychID,
            entries: entries
        )
    }

    private func verifyNoteReference(
        _ reference: SourceReferenceEnvelope
    ) async throws -> [ContextUseVerificationFact] {
        guard reference.owner.kind == .note,
              let vaultID = reference.owner.vaultID,
              let relativePath = reference.owner.relativePath else {
            throw ResearchAgentResultContractError.invalidContextUse
        }
        let noteID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: relativePath)
        guard let snapshot = currentSnapshot.document(id: noteID),
              snapshot.lifecycle == .active,
              let stableID = snapshot.stableIdentity.resolvedID,
              reference.owner.stableObjectIdentity
                == stableID.uuidString.lowercased(),
              reference.fingerprint == snapshot.fingerprint,
              reference.vaultRole == snapshot.vaultRole,
              reference.objectRole == Self.objectRole(snapshot.vaultRole),
              reference.actorClass == .unknown,
              reference.evidentialLayer == Self.evidentialLayer(snapshot.vaultRole),
              Self.isNoteRetrievalReason(reference.retrievalReason)
        else {
            throw ResearchAgentResultContractError.invalidContextUse
        }
        let document = try await loadDocument(noteID)
        guard document.fingerprint == snapshot.fingerprint,
              Self.locator(reference.locator, isValidIn: document.rawContent) else {
            throw ResearchAgentResultContractError.invalidContextUse
        }
        return [.authoritativeOwnerRead, .revisionMatched, .locatorResolved]
    }

    private func verifyMaterialReference(
        _ reference: SourceReferenceEnvelope,
        snapshot: ResearchFunctionSnapshot
    ) async throws -> [ContextUseVerificationFact] {
        let frozen: ResearchSourceReference?
        if case .automatic(let parentRunID)? =
                snapshot.resolvedFidelityInvocation {
            frozen = try await researchAgentResultDependencies
                .localResearchExecutionStore.recordIfPresent(id: parentRunID)?
                .snapshot.sourceReference
        } else {
            frozen = snapshot.sourceReference
        }
        guard let frozen,
              ResearchContextMaterialProjection.isCurrentReference(
                reference,
                source: frozen,
                zoteroBibliographicContext:
                    snapshot.zoteroBibliographicContext,
                runID: snapshot.runID,
                triptychID: self.id
              ) else {
            throw ResearchAgentResultContractError.invalidContextUse
        }
        let status = await researchAgentResultDependencies.researchSourceAccessStore.status(
            analysisNoteID: snapshot.request.target.noteID
        )
        guard status.state == .available,
              status.reference == frozen else {
            throw ResearchAgentResultContractError.invalidContextUse
        }
        return [.authoritativeOwnerRead, .revisionMatched, .locatorResolved]
    }

    private func verifyRecordReference(
        _ reference: SourceReferenceEnvelope
    ) async throws -> [ContextUseVerificationFact] {
        guard reference.owner.kind == .record,
              let recordID = reference.owner.recordID,
              reference.owner.stableObjectIdentity
                == recordID.uuidString.lowercased(),
              reference.objectRole == .researchRecord,
              reference.vaultRole == nil,
              reference.evidentialLayer == .researchRecord,
              reference.retrievalReason == .recordSearch else {
            throw ResearchAgentResultContractError.invalidContextUse
        }
        let listing = try await researchAgentResultDependencies.portableResearchRecordStore.listing()
        guard listing.issues.isEmpty,
              let revision = listing.revisions.first(where: { $0.id == recordID }),
              reference.fingerprint == revision.fingerprint else {
            throw ResearchAgentResultContractError.invalidContextUse
        }
        switch reference.locator.kind {
        case .recordStatement:
            guard let statementID = reference.locator.statementID,
                  let statement = revision.record.statements.first(where: {
                      $0.id == statementID
                  }),
                  reference.actorClass == Self.actorClass(statement.author) else {
                throw ResearchAgentResultContractError.invalidContextUse
            }
        case .wholeObject:
            guard reference.actorClass == .unknown else {
                throw ResearchAgentResultContractError.invalidContextUse
            }
        case .sourceRange, .materialLocator, .unknown:
            throw ResearchAgentResultContractError.invalidContextUse
        }
        return [.authoritativeOwnerRead, .revisionMatched, .locatorResolved]
    }

    private func exactCurrentNote(
        _ target: ResearchActionNoteSnapshot
    ) async throws -> NoteDocument {
        guard let snapshot = currentSnapshot.document(id: target.note),
              snapshot.lifecycle == .active,
              snapshot.stableIdentity.resolvedID == target.noteID,
              snapshot.vaultRole == Self.vaultRole(target.role) else {
            throw ResearchFunctionContractError.targetIdentityChanged
        }
        return try await loadDocument(target.note)
    }

    private func exactCurrentMaterial(
        _ material: ResearchFunctionMaterial
    ) async throws -> NoteDocument {
        guard let snapshot = currentSnapshot.document(id: material.note),
              snapshot.lifecycle == .active,
              snapshot.stableIdentity.resolvedID == material.noteID,
              ResearchFunctionTargetRole(vaultRole: snapshot.vaultRole)
                == material.role else {
            throw ResearchFunctionContractError.targetIdentityChanged
        }
        return try await loadDocument(material.note)
    }

    private func actuallyUsedMaterialIDs(
        from report: ContextUseReport,
        in materials: [ResearchFunctionMaterial]
    ) -> [UUID] {
        let byStableIdentity = Dictionary(uniqueKeysWithValues: materials.map {
            ($0.noteID.uuidString.lowercased(), $0)
        })
        return Set(report.entries.compactMap { entry -> UUID? in
            guard entry.sourceReference.sourceKind == .note,
                  let material = byStableIdentity[
                    entry.sourceReference.owner.stableObjectIdentity
                  ],
                  entry.sourceReference.fingerprint == material.fingerprint else {
                return nil
            }
            return material.noteID
        }).sorted { $0.uuidString < $1.uuidString }
    }

    private func resultSummary(
        _ results: ResearchAcademicFieldValues,
        contract: ResearchResultContract,
        disposition: ResearchAgentResultDisposition
    ) -> String {
        let definitions = Dictionary(uniqueKeysWithValues: contract.academicFields.map {
            ($0.fieldID.rawValue, $0)
        })
        if case .freeText(let text)? = results.values[
            ResearchAcademicFieldID.academicOutcome.rawValue
        ], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        for definition in contract.academicFields {
            guard let value = results.values[definition.fieldID.rawValue] else { continue }
            switch value {
            case .freeText(let text):
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
            case .singleChoice(let choice):
                return definitions[definition.fieldID.rawValue]?.choices
                    .first(where: { $0.value == choice })?.label ?? choice
            case .multipleChoice(let choices):
                if !choices.isEmpty {
                    let labels = choices.map { choice in
                        definitions[definition.fieldID.rawValue]?.choices
                            .first(where: { $0.value == choice })?.label ?? choice
                    }
                    return labels.joined(separator: "; ")
                }
            }
        }
        return disposition == .blocked
            ? "The Agent reported that this bounded research result was blocked."
            : "The Agent completed a Run whose frozen Result Contract contained no academic prose field."
    }

    private func resultReceipt(
        disposition: ResearchAgentResultDisposition,
        completion: ResearchFunctionCompletion,
        automaticParentCompletion: ResearchFunctionCompletion? = nil
    ) throws -> ResearchAgentResultReceipt {
        let parentState: ResearchAgentResultFinalizationState?
        if let parent = automaticParentCompletion {
            switch parent.state {
            case .complete: parentState = .finalized
            case .unverified: parentState = .unverified
            case .prepared, .awaitingFidelity, .stale, .cancelled:
                throw ResearchAgentResultContractError.invalidSubmission
            }
        } else {
            parentState = nil
        }
        let parentRecordFormed = parentState.map { _ in true }
        switch completion.state {
        case .complete:
            return try ResearchAgentResultReceipt(
                disposition: disposition,
                state: .finalized,
                recordFormed: true,
                parentState: parentState,
                parentRecordFormed: parentRecordFormed,
                message: automaticParentCompletion == nil
                    ? "The canonical Result was finalized as one Research Record."
                    : "The Fidelity child formed its Research Record and automatically finalized the lineage-bound parent Research Record."
            )
        case .unverified:
            return try ResearchAgentResultReceipt(
                disposition: disposition,
                state: .unverified,
                recordFormed: true,
                parentState: parentState,
                parentRecordFormed: parentRecordFormed,
                message: automaticParentCompletion == nil
                    ? "The Result formed one Research Record with explicit unverified Fidelity evidence."
                    : "The Fidelity child and its lineage-bound parent each formed one Research Record with explicit unverified Fidelity evidence."
            )
        case .awaitingFidelity:
            return try ResearchAgentResultReceipt(
                disposition: disposition,
                state: .awaitingFidelity,
                recordFormed: false,
                parentState: parentState,
                parentRecordFormed: parentRecordFormed,
                message: "The Result is staged on this Run. Run scholium agent prepare-fidelity --run <this-parent-locator> to attach the exact-revision Fidelity child to the current protected Session."
            )
        case .prepared, .stale, .cancelled:
            throw ResearchAgentResultContractError.invalidSubmission
        }
    }

    static func locator(
        _ locator: ResearchContextSourceLocator,
        isValidIn source: String
    ) -> Bool {
        locator.isValid(in: source)
    }

    private static func vaultRole(_ role: ResearchActionTargetRole) -> VaultRole {
        switch role {
        case .analysis: .sourceCorpus
        case .topic: .topicKnowledge
        case .work: .draftProject
        }
    }

    static func objectRole(_ role: VaultRole) -> ResearchContextObjectRole? {
        switch role {
        case .sourceCorpus: .analysis
        case .topicKnowledge: .topic
        case .draftProject: .work
        case .other: nil
        }
    }

    static func evidentialLayer(_ role: VaultRole) -> EvidentialLayer {
        switch role {
        case .sourceCorpus: .paperAnalysis
        case .topicKnowledge, .other: .topicNote
        case .draftProject: .draftProse
        }
    }

    static func actorClass(
        _ author: PortableResearchStatementAuthor
    ) -> ResearchContextActorClass {
        switch author {
        case .researcher: .researcher
        case .agent: .agent
        }
    }

    static func isNoteRetrievalReason(
        _ reason: ResearchContextRetrievalReason
    ) -> Bool {
        switch reason {
        case .lexical, .canonicalSummary, .propertyPresence, .directRelation,
             .exactRead:
            true
        case .recordSearch, .explicitSelection, .researcherState:
            false
        }
    }
}
