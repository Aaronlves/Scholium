import Foundation
import ScholiumContracts
import ScholiumCore

struct ResolvedResearchActionContext: Sendable {
    enum ExecutionStorage: Sendable {
        case legacyFunction
        case localExecutionV2
    }

    let availability: ResearchActionAvailability
    let function: ResearchFunctionID
    let primaryPackageID: String
    let profileBinding: ResearchActionProfileBinding?
    let parameterValues: [String: ResearchActionParameterValue]
    let authority: ResearchAuthorityEnvelope
    let allowsLegacyFidelityExpansion: Bool
    let executionStorage: ExecutionStorage
}

private struct ResolvedResearchActionCandidate: Sendable {
    let availability: ResearchActionAvailability
    let function: ResearchFunctionID
    let primaryPackageID: String?
    let profileBinding: ResearchActionProfileBinding?
}

extension WorkspaceHandle {
    func researchActionAvailability(
        for target: ResearchActionNoteSnapshot
    ) async throws -> [ResearchActionAvailability] {
        try requireActive()
        let functionTarget = target.functionTarget
        return try await resolvedResearchActions(
            for: functionTarget,
            checkingSourceAccess: true
        )
            .map(\.availability)
    }

    func prepareResearchAction(
        _ request: ResearchActionExecutionRequest
    ) async throws -> ResearchActionPreparation {
        let resolved = try await resolvedResearchActionExecution(request)
        let functionPreparation = try await prepareResearchFunction(
            resolved.request,
            actionContext: resolved.context
        )
        guard let snapshot = functionPreparation.snapshot.actionSnapshot else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        return ResearchActionPreparation(
            snapshot: snapshot,
            runID: functionPreparation.runID,
            instructions: functionPreparation.instructions,
            state: functionPreparation.state,
            derivedRefreshWarning: functionPreparation.derivedRefreshWarning,
            nextActions: functionPreparation.nextActions ?? []
        )
    }

    func resolvedResearchActionExecution(
        _ request: ResearchActionExecutionRequest
    ) async throws -> (
        request: ResearchFunctionRequest,
        context: ResolvedResearchActionContext
    ) {
        try requireActive()
        let target = request.target.functionTarget
        let candidates = try await resolvedResearchActions(
            for: target,
            checkingSourceAccess: false
        )
        guard let candidate = candidates.first(where: {
            $0.availability.id == request.actionID
        }), candidate.availability.isEnabled,
        let primaryPackageID = candidate.primaryPackageID else {
            throw ResearchActionExecutionContractError.actionUnavailable(
                request.actionID
            )
        }

        let parameters = try ResearchActionParameterModel(
            deferringRequiredSourceFor: candidate.availability.profile.profile,
            rawValues: request.parameterValues
        )
        let prepared = try makeFunctionRequest(
            definition: candidate.availability.definition,
            target: target,
            profile: candidate.availability.profile.profile,
            parameters: parameters
        )
        let context = ResolvedResearchActionContext(
            availability: candidate.availability,
            function: candidate.function,
            primaryPackageID: primaryPackageID,
            profileBinding: candidate.profileBinding,
            parameterValues: parameters.values,
            authority: prepared.authority,
            allowsLegacyFidelityExpansion: false,
            executionStorage: .localExecutionV2
        )
        return (prepared.request, context)
    }

    func resolvedDefaultActionContext(
        for request: ResearchFunctionRequest,
        executionStorage: ResolvedResearchActionContext.ExecutionStorage = .localExecutionV2
    ) async throws -> ResolvedResearchActionContext {
        try request.validate()
        let definition = try ResearchActionFunctionMapping.definition(
            for: request.function,
            targetRole: request.target.role
        )
        let profile = try Self.defaultProfile(
            for: definition,
            targetRole: request.target.role.actionRole
        )
        let resolvedProfile = try ResearchActionResolvedProfileSnapshot(
            origin: .applicationDefault,
            profile: profile,
            profileRevision: profile.contentRevision(),
            profileDocumentRevision: nil
        )
        let method = try await services.researchSkillStore
            .functionBindingResolution(
                for: request.function,
                actionID: definition.id
            )
        guard method.issue == nil, let primaryPackageID = method.package?.id else {
            throw ResearchActionExecutionContractError.actionUnavailable(
                definition.id
            )
        }
        let values = try Self.parameterValues(
            from: request,
            profile: profile
        )
        let authority = try Self.authority(
            target: request.target.actionNote,
            additionalReads: request.materials.map(\.actionNote),
            profile: profile
        )
        return ResolvedResearchActionContext(
            availability: ResearchActionAvailability(
                definition: definition,
                buttonName: profile.buttonName,
                order: profile.order,
                group: definition.id == .manuscript
                    ? .researcherSkill
                    : .defaultAction,
                profile: resolvedProfile,
                isEnabled: true
            ),
            function: request.function,
            primaryPackageID: primaryPackageID,
            profileBinding: nil,
            parameterValues: values,
            authority: authority,
            allowsLegacyFidelityExpansion: true,
            executionStorage: executionStorage
        )
    }

    private func resolvedResearchActions(
        for target: ResearchFunctionTarget,
        checkingSourceAccess: Bool
    ) async throws -> [ResolvedResearchActionCandidate] {
        let functionAvailability = Dictionary(uniqueKeysWithValues:
            try await researchFunctionAvailability(
                for: target,
                checkingSourceAccess: checkingSourceAccess
            ).map {
                ($0.function, $0)
            }
        )
        var resolved: [ResolvedResearchActionCandidate] = []

        for definition in ResearchActionDefinition.defaultDefinitions(
            for: target.role.actionRole
        ) {
            let function = try ResearchActionFunctionMapping.function(
                for: definition,
                targetRole: target.role.actionRole
            )
            let profile = try Self.defaultProfile(
                for: definition,
                targetRole: target.role.actionRole
            )
            let profileSnapshot = try ResearchActionResolvedProfileSnapshot(
                origin: .applicationDefault,
                profile: profile,
                profileRevision: profile.contentRevision(),
                profileDocumentRevision: nil
            )
            let method = try await services.researchSkillStore
                .functionBindingResolution(for: function, actionID: definition.id)
            let functionState = functionAvailability[function]
            let reasons = (functionState?.repairReasons ?? []).map(
                Self.actionRepairReason
            )
            resolved.append(ResolvedResearchActionCandidate(
                availability: ResearchActionAvailability(
                    definition: definition,
                    buttonName: profile.buttonName,
                    order: profile.order,
                    group: .defaultAction,
                    profile: profileSnapshot,
                    isEnabled: functionState?.isEnabled == true
                        && method.issue == nil
                        && method.package != nil,
                    repairReasons: reasons.isEmpty && method.issue != nil
                        ? [Self.actionRepairReason(method.issue!)]
                        : reasons
                ),
                function: function,
                primaryPackageID: method.package?.id,
                profileBinding: nil
            ))
        }

        let profileSnapshot: ResearchActionProfileSnapshot?
        do {
            profileSnapshot = try await services.researchSkillStore.actionProfileSnapshot()
        } catch {
            profileSnapshot = nil
        }
        if let profileSnapshot {
            for binding in profileSnapshot.document.orderedBindings {
                let profile = binding.profile
                guard profile.showInActions,
                      profile.applicableRoles.contains(target.role.actionRole) else {
                    continue
                }
                let definition = profile.definition
                let function = try ResearchActionFunctionMapping.function(
                    for: definition,
                    targetRole: target.role.actionRole
                )
                let method = try await services.researchSkillStore
                    .profileActionBindingResolution(
                        for: function,
                        actionID: definition.id
                    )
                var reasons = await baseActionRepairReasons(
                    target: target,
                    function: function,
                    profile: profile,
                    checkingSourceAccess: checkingSourceAccess
                )
                if let issue = method.issue {
                    reasons.append(Self.actionRepairReason(issue))
                }
                if Self.requiresUnsupportedWriteCapability(profile, role: target.role.actionRole) {
                    reasons.append(ResearchActionRepairReason(
                        code: .unsupportedCapability,
                        packageID: binding.packageID
                    ))
                }
                if profile.sourceRequirement != .none,
                   profile.executionKind != .analysis {
                    reasons.append(ResearchActionRepairReason(
                        code: .unsupportedCapability,
                        packageID: binding.packageID
                    ))
                }
                let resolvedProfile = try ResearchActionResolvedProfileSnapshot(
                    origin: .researcher,
                    profile: profile,
                    profileRevision: profile.contentRevision(),
                    profileDocumentRevision: profileSnapshot.revision
                )
                resolved.append(ResolvedResearchActionCandidate(
                    availability: ResearchActionAvailability(
                        definition: definition,
                        buttonName: profile.buttonName,
                        order: profile.order,
                        group: .researcherSkill,
                        profile: resolvedProfile,
                        isEnabled: reasons.isEmpty
                            && method.package?.id == binding.packageID,
                        repairReasons: Self.unique(reasons)
                    ),
                    function: function,
                    primaryPackageID: method.package?.id,
                    profileBinding: binding
                ))
            }
        }

        let defaults = resolved.filter {
            $0.availability.group == .defaultAction
        }
        let researcher = resolved.filter {
            $0.availability.group == .researcherSkill
        }.sorted { lhs, rhs in
            if lhs.availability.order != rhs.availability.order {
                return lhs.availability.order < rhs.availability.order
            }
            return lhs.availability.id.rawValue < rhs.availability.id.rawValue
        }
        return defaults + researcher
    }

    private func baseActionRepairReasons(
        target: ResearchFunctionTarget,
        function: ResearchFunctionID,
        profile: ResearchActionProfile,
        checkingSourceAccess: Bool
    ) async -> [ResearchActionRepairReason] {
        var reasons: [ResearchActionRepairReason] = []
        if let reason = await researchFunctionTargetRepairReason(target) {
            reasons.append(Self.actionRepairReason(reason))
        }
        if !function.allowedTargetRoles.contains(target.role)
            || !profile.applicableRoles.contains(target.role.actionRole) {
            reasons.append(ResearchActionRepairReason(code: .invalidTargetRole))
        }
        if checkingSourceAccess, profile.sourceRequirement == .required {
            do {
                let status = try await researchSourceAccessStatus(for: target)
                if let failure = status.failure {
                    reasons.append(ResearchActionRepairReason(
                        code: .sourceAccessRequired,
                        sourceAccessFailure: failure
                    ))
                }
            } catch {
                reasons.append(ResearchActionRepairReason(
                    code: .sourceAccessRequired,
                    sourceAccessFailure: ResearchSourceAccessFailure(
                        code: .sourceUnreadable
                    )
                ))
            }
        }
        return Self.unique(reasons)
    }

    private func makeFunctionRequest(
        definition: ResearchActionDefinition,
        target: ResearchFunctionTarget,
        profile: ResearchActionProfile,
        parameters: ResearchActionParameterModel
    ) throws -> (request: ResearchFunctionRequest, authority: ResearchAuthorityEnvelope) {
        let function = try ResearchActionFunctionMapping.function(
            for: definition,
            targetRole: target.role.actionRole
        )
        var notes: [ResearchActionNoteSnapshot] = []
        var passage: CommentAnchor?
        var textValues: [(String, String)] = []
        var checks: Set<FidelityCheck> = []
        for module in profile.modules {
            guard let value = parameters.values[module.id.rawValue] else { continue }
            switch value {
            case .notes(let selected):
                notes.append(contentsOf: selected)
            case .passage(let anchor):
                guard anchor.fingerprint == target.fingerprint else {
                    throw ResearchActionExecutionContractError.staleResolution
                }
                passage = anchor
            case .source, .boolean:
                break
            case .text(let text):
                textValues.append((module.id.rawValue, text))
            case .choices(let values):
                if function == .fidelity {
                    for value in values {
                        if value.rawValue == FidelityCheck.content.rawValue {
                            checks.insert(.content)
                        } else if value.rawValue == FidelityCheck.citations.rawValue {
                            checks.insert(.citations)
                        }
                    }
                }
            }
        }
        var seen: Set<UUID> = []
        let additionalReads = notes.filter {
            $0.noteID != target.noteID && seen.insert($0.noteID).inserted
        }
        let materials = additionalReads.map(\.functionMaterial)
        let authority = try Self.authority(
            target: target.actionNote,
            additionalReads: additionalReads,
            profile: profile
        )
        let instruction = textValues.first(where: {
            $0.0 == Self.researcherRequestModuleID.rawValue
        })?.1 ?? textValues.first?.1
        let writes = !authority.writableNotes.isEmpty
        let request = ResearchFunctionRequest(
            function: function,
            target: target,
            materials: materials,
            instruction: function == .discuss
                ? (instruction ?? "Discuss the current Target using the declared Action parameters.")
                : instruction,
            scope: passage.map(ResearchFunctionScope.passage),
            checks: function == .fidelity
                ? (checks.isEmpty ? [.content] : checks)
                : [],
            commentIDs: [],
            dialogueResponseModules: function == .discuss ? [] : nil,
            writeScope: writes ? .currentNote : nil,
            authorizedWriteTargets: writes ? [target] : []
        )
        try request.validate()
        return (request, authority)
    }

    private static func authority(
        target: ResearchActionNoteSnapshot,
        additionalReads: [ResearchActionNoteSnapshot],
        profile: ResearchActionProfile
    ) throws -> ResearchAuthorityEnvelope {
        let directWriteKind = [
            ResearchActionExecutionKind.analysis,
            .synthesis,
            .writing,
        ].contains(profile.executionKind)
        let writes = directWriteKind
            && profile.capabilities.candidateWritableRoles.contains(target.role)
            && profile.capabilities.candidateWriteOperations.contains(.modifyMarkdown)
        return try ResearchAuthorityEnvelope(
            readableNotes: [target] + additionalReads,
            writableNotes: writes ? [target] : [],
            writeOperations: writes ? [.modifyMarkdown] : [],
            editablePropertyKeys: []
        )
    }

    private static func parameterValues(
        from request: ResearchFunctionRequest,
        profile: ResearchActionProfile
    ) throws -> [String: ResearchActionParameterValue] {
        var values: [String: ResearchActionParameterValue] = [:]
        for module in profile.modules {
            switch module.kind {
            case .materialSelector:
                if !request.materials.isEmpty {
                    values[module.id.rawValue] = .notes(
                        request.materials.map(\.actionNote)
                    )
                }
            case .passageAnchor:
                if let selection = request.scope?.selection {
                    values[module.id.rawValue] = .passage(selection)
                }
            case .boundedText:
                if let instruction = request.instruction {
                    values[module.id.rawValue] = .text(instruction)
                }
            case .enumeration where request.function == .fidelity:
                values[module.id.rawValue] = .choices(
                    request.checks.compactMap {
                        ResearchActionModuleChoiceValue(rawValue: $0.rawValue)
                    }.sorted { $0.rawValue < $1.rawValue }
                )
            case .notePicker, .sourceReference, .boolean, .enumeration:
                break
            }
        }
        return values
    }

    static func defaultProfile(
        for definition: ResearchActionDefinition,
        targetRole: ResearchActionTargetRole
    ) throws -> ResearchActionProfile {
        let allRoles = ResearchActionTargetRole.allCases
        var modules: [ResearchActionModuleDefinition] = []
        if definition.executionKind != .checkFidelity {
            modules.append(try .boundedText(
                id: researcherRequestModuleID,
                label: "Request",
                isRequired: definition.executionKind == .discussion,
                maximumTextUTF8ByteCount: 16_384,
                allowsMultipleLines: true
            ))
        }
        modules.append(try .passageAnchor(
            id: passageModuleID,
            label: "Passage",
            isRequired: false
        ))
        modules.append(try .materialSelector(
            id: materialsModuleID,
            label: "Materials",
            isRequired: false,
            roleScope: allRoles,
            maximumSelectionCount: 16
        ))
        if definition.executionKind == .analysis {
            modules.append(try .sourceReference(
                id: sourceModuleID,
                label: "Source",
                isRequired: true
            ))
        }
        if definition.executionKind == .checkFidelity {
            modules.append(try .enumeration(
                id: fidelityChecksModuleID,
                label: "Checks",
                isRequired: true,
                choices: [
                    try ResearchActionModuleChoice(
                        value: ResearchActionModuleChoiceValue(rawValue: "content")!,
                        label: "Content"
                    ),
                    try ResearchActionModuleChoice(
                        value: ResearchActionModuleChoiceValue(rawValue: "citations")!,
                        label: "Citations"
                    ),
                ],
                maximumSelectionCount: 2
            ))
        }
        let writes = definition.executionKind.maximumCandidateWritableRoles
            .contains(targetRole)
        let capabilities = try ResearchActionCapabilityDeclaration(
            readableRoles: allRoles,
            candidateWritableRoles: writes ? [targetRole] : [],
            candidateWriteOperations: writes ? [.modifyMarkdown] : []
        )
        let feedbackRequirement: ResearchActionFeedbackRequirement = switch definition.executionKind {
        case .discussion, .checkFidelity: .none
        case .analysis, .synthesis, .writing, .critique, .manuscript: .requested
        }
        return try ResearchActionProfile(
            definition: definition,
            buttonName: buttonName(for: definition),
            order: defaultOrder(for: definition),
            applicableRoles: [targetRole],
            showInActions: true,
            modules: modules,
            sourceRequirement: definition.executionKind == .analysis
                ? .required
                : .none,
            capabilities: capabilities,
            feedbackRequirement: feedbackRequirement
        )
    }

    private static func buttonName(
        for definition: ResearchActionDefinition
    ) -> String {
        switch definition.id {
        case .discuss: "Discuss"
        case .analyze: "Analyze"
        case .synthesize: "Synthesize"
        case .write: "Write"
        case .critique: "Critique"
        case .checkFidelity: "Check Fidelity"
        case .manuscript: "Manuscript"
        default: definition.id.rawValue
        }
    }

    private static func defaultOrder(
        for definition: ResearchActionDefinition
    ) -> Int {
        switch definition.id {
        case .discuss: 0
        case .analyze, .synthesize, .write: 100
        case .critique: 200
        case .checkFidelity: 300
        case .manuscript: 400
        default: 500
        }
    }

    private static func requiresUnsupportedWriteCapability(
        _ profile: ResearchActionProfile,
        role: ResearchActionTargetRole
    ) -> Bool {
        if profile.capabilities.candidateWriteOperations.contains(.modifyProperties) {
            return true
        }
        let requiresWrite = [
            ResearchActionExecutionKind.analysis,
            .synthesis,
            .writing,
        ].contains(profile.executionKind)
        guard requiresWrite else { return false }
        return !profile.capabilities.candidateWritableRoles.contains(role)
            || !profile.capabilities.candidateWriteOperations.contains(.modifyMarkdown)
    }

    private static func actionRepairReason(
        _ reason: ResearchFunctionRepairReason
    ) -> ResearchActionRepairReason {
        let code: ResearchActionRepairReasonCode = switch reason.code {
        case .targetUnavailable: .targetUnavailable
        case .targetChanged: .targetChanged
        case .targetIdentityChanged: .targetIdentityChanged
        case .invalidTargetRole: .invalidTargetRole
        case .inactiveTarget: .inactiveTarget
        case .sourceAccessRequired: .sourceAccessRequired
        case .missingWorkflow, .missingCapability: .methodMissing
        case .invalidWorkflow: .methodInvalid
        case .malformedBinding: .profileInvalid
        }
        return ResearchActionRepairReason(
            code: code,
            packageID: reason.packageID,
            sourceAccessFailure: reason.sourceAccessFailure
        )
    }

    private static func actionRepairReason(
        _ issue: ResearchSkillBindingIssue
    ) -> ResearchActionRepairReason {
        switch issue {
        case .missing:
            ResearchActionRepairReason(code: .methodMissing)
        case .disabled:
            ResearchActionRepairReason(code: .methodDisabled)
        case .malformed:
            ResearchActionRepairReason(code: .profileInvalid)
        case .invalidPackage(let packageID),
             .unsupportedFunction(let packageID, _),
             .unsupportedAction(let packageID, _):
            ResearchActionRepairReason(code: .methodInvalid, packageID: packageID)
        case .missingCapability, .citationStyleMissing, .citationStyleMismatch:
            ResearchActionRepairReason(code: .unsupportedCapability)
        }
    }

    private static func unique(
        _ reasons: [ResearchActionRepairReason]
    ) -> [ResearchActionRepairReason] {
        var seen: Set<ResearchActionRepairReason> = []
        return reasons.filter { seen.insert($0).inserted }
    }

    private static let researcherRequestModuleID = ResearchActionModuleID(
        rawValue: "researcher-request"
    )!
    private static let passageModuleID = ResearchActionModuleID(
        rawValue: "passage"
    )!
    private static let materialsModuleID = ResearchActionModuleID(
        rawValue: "materials"
    )!
    private static let sourceModuleID = ResearchActionModuleID(
        rawValue: "source"
    )!
    private static let fidelityChecksModuleID = ResearchActionModuleID(
        rawValue: "fidelity-checks"
    )!
}

extension ResearchFunctionTarget {
    var actionNote: ResearchActionNoteSnapshot {
        ResearchActionNoteSnapshot(
            noteID: noteID,
            note: note,
            role: role.actionRole,
            lifecycle: lifecycle,
            fingerprint: fingerprint,
            title: title
        )
    }
}

extension ResearchFunctionMaterial {
    var actionNote: ResearchActionNoteSnapshot {
        ResearchActionNoteSnapshot(
            noteID: noteID,
            note: note,
            role: role.actionRole,
            lifecycle: lifecycle,
            fingerprint: fingerprint,
            title: title
        )
    }
}

private extension ResearchActionNoteSnapshot {
    var functionTarget: ResearchFunctionTarget {
        ResearchFunctionTarget(
            noteID: noteID,
            note: note,
            role: role.functionRole,
            lifecycle: lifecycle,
            fingerprint: fingerprint,
            title: title
        )
    }

    var functionMaterial: ResearchFunctionMaterial {
        ResearchFunctionMaterial(
            noteID: noteID,
            note: note,
            role: role.functionRole,
            lifecycle: lifecycle,
            fingerprint: fingerprint,
            title: title
        )
    }
}

private extension ResearchFunctionTargetRole {
    var actionRole: ResearchActionTargetRole {
        switch self {
        case .analysis: .analysis
        case .topic: .topic
        case .work: .work
        }
    }
}

private extension ResearchActionTargetRole {
    var functionRole: ResearchFunctionTargetRole {
        switch self {
        case .analysis: .analysis
        case .topic: .topic
        case .work: .work
        }
    }
}
