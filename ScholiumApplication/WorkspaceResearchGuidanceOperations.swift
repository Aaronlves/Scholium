import Foundation
import ScholiumContracts
import ScholiumCore

// Machine-local source binding and citation settings remain Workspace-owned.
extension WorkspaceHandle {
    func researchSourceAccessStatus(
        for proposedTarget: ResearchFunctionTarget
    ) async throws -> ResearchSourceAccessStatus {
        try requireActive()
        let target = try await researchFunctionCoordinator
            .validateResearchFunctionTarget(
            proposedTarget,
            expected: proposedTarget.fingerprint,
            host: self
        )
        guard target.note.schemaProfile == .analysis,
              proposedTarget.role == .analysis else {
            throw ResearchFunctionContractError.invalidTargetRole(
                function: .develop,
                role: proposedTarget.role
            )
        }
        do {
            return .available(
                try await researchFunctionCoordinator.resolveResearchSourceAccess(
                    for: target
                ).reference
            )
        } catch let error as ResearchFunctionContractError {
            if case .sourceAccessUnavailable(let failure) = error {
                let reference = try? await services.researchSourceAccessStore.reference(
                    analysisNoteID: proposedTarget.noteID
                )
                return .repairRequired(failure.code, reference: reference)
            }
            throw error
        }
    }

    func bindResearchSourceAccess(
        _ request: ResearchSourceBindingRequest
    ) async throws -> ResearchSourceReference {
        try requireActive()
        let target = try await researchFunctionCoordinator
            .validateResearchFunctionTarget(
            request.target,
            expected: request.target.fingerprint,
            host: self
        )
        guard target.note.schemaProfile == .analysis,
              request.target.role == .analysis else {
            throw ResearchFunctionContractError.invalidTargetRole(
                function: .develop,
                role: request.target.role
            )
        }
        do {
            switch request.selection {
            case .localFile(let selectedURL):
                return try await services.researchSourceAccessStore.bindLocalFile(
                    analysisNoteID: request.target.noteID,
                    selectedURL: selectedURL
                )
            case .zoteroAttachment(
                let itemKey,
                let attachmentKey,
                let selectedFileURL
            ):
                let attachment = try await services.zotero.resolveAttachment(
                    itemKey: itemKey,
                    attachmentKey: attachmentKey
                )
                let selectedPath = selectedFileURL.standardizedFileURL
                let zoteroPath = try researchFunctionCoordinator
                    .validatedZoteroAttachmentURL(
                    attachment.fileURL
                )
                guard selectedPath.path == zoteroPath.path else {
                    throw ResearchFunctionContractError.sourceAccessUnavailable(
                        ResearchSourceAccessFailure(code: .zoteroIdentityMismatch)
                    )
                }
                let targetItemKey = researchFunctionCoordinator
                    .normalizedTargetZoteroItemKey(target)
                guard targetItemKey == nil || targetItemKey == attachment.itemKey else {
                    throw ResearchFunctionContractError.sourceAccessUnavailable(
                        ResearchSourceAccessFailure(code: .zoteroIdentityMismatch)
                    )
                }
                return try await services.researchSourceAccessStore
                    .bindZoteroAttachment(
                        analysisNoteID: request.target.noteID,
                        itemKey: attachment.itemKey,
                        attachmentKey: attachment.attachmentKey,
                        selectedURL: selectedFileURL,
                        displayName: attachment.displayName
                    )
            }
        } catch let error as ResearchSourceAccessStoreError {
            throw ResearchFunctionContractError.sourceAccessUnavailable(error.failure)
        } catch let error as ZoteroUseCaseError {
            throw ResearchFunctionContractError.sourceAccessUnavailable(
                ResearchSourceAccessFailure(
                    code: researchFunctionCoordinator.sourceFailureCode(for: error)
                )
            )
        }
    }

    func removeResearchSourceAccess(
        for proposedTarget: ResearchFunctionTarget
    ) async throws {
        try requireActive()
        let target = try await researchFunctionCoordinator
            .validateResearchFunctionTarget(
            proposedTarget,
            expected: proposedTarget.fingerprint,
            host: self
        )
        guard target.note.schemaProfile == .analysis,
              proposedTarget.role == .analysis else {
            throw ResearchFunctionContractError.invalidTargetRole(
                function: .develop,
                role: proposedTarget.role
            )
        }
        do {
            try await services.researchSourceAccessStore.remove(
                analysisNoteID: proposedTarget.noteID
            )
        } catch let error as ResearchSourceAccessStoreError {
            throw ResearchFunctionContractError.sourceAccessUnavailable(error.failure)
        }
    }

    func researchCitationMethodStatus() async throws -> ResearchCitationMethodStatus {
        try requireActive()
        let resolution = try await services.researchSkillStore
            .citationBindingResolution()
        let candidates = try await services.researchSkillStore.skills().filter { package in
            package.origin == .triptych
                && package.isValid
                && package.supports(.fidelity)
                && package.provides(.citationVerification)
                && package.provides(.citationFormatting)
                && !package.citationStyleResources.isEmpty
        }.map { package in
            ResearchCitationMethodCandidate(
                packageID: package.id,
                name: package.name,
                description: package.description,
                version: package.version,
                citationStyles: package.citationStyles.filter {
                    package.citationStyleResources[$0] != nil
                }
            )
        }
        return ResearchCitationMethodStatus(
            bundledTemplateAvailable: resolution.bundledTemplateAvailable,
            candidates: candidates,
            activePackageID: resolution.package?.id,
            activeCitationStyle: resolution.citationStyle,
            bindingRevision: resolution.bindingRevision,
            issue: citationMethodIssue(resolution.issue)
        )
    }

    func activateResearchCitationMethod(
        _ selection: ResearchCitationMethodSelection,
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus {
        try requireActive()
        guard !selection.citationStyle.isEmpty else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Choose an explicit citation style before activating this method."
            )
        }
        let citationStyle = selection.citationStyle
        _ = try await services.researchSkillStore.activateCitationBinding(
            packageID: selection.packageID,
            citationStyle: citationStyle,
            expectedBindingRevision: expectedBindingRevision
        )
        return try await researchCitationMethodStatus()
    }

    func clearResearchCitationMethod(
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus {
        try requireActive()
        _ = try await services.researchSkillStore.clearCitationBinding(
            expectedBindingRevision: expectedBindingRevision
        )
        return try await researchCitationMethodStatus()
    }

    func adoptBundledCitationStarter(
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus {
        try requireActive()
        _ = try await services.researchSkillStore.adoptAPACitationStarter(
            expectedBindingRevision: expectedBindingRevision
        )
        return try await researchCitationMethodStatus()
    }

    private func citationMethodIssue(
        _ issue: ResearchSkillBindingIssue?
    ) -> ResearchCitationMethodIssue? {
        guard let issue else { return nil }
        switch issue {
        case .missing, .disabled:
            return ResearchCitationMethodIssue(code: .missing)
        case .malformed:
            return ResearchCitationMethodIssue(code: .malformedBinding)
        case .invalidPackage(let id):
            return ResearchCitationMethodIssue(code: .invalidPackage, selectedPackageID: id)
        case .unsupportedFunction(let id, _):
            return ResearchCitationMethodIssue(code: .invalidPackage, selectedPackageID: id)
        case .unsupportedAction(let id, _):
            return ResearchCitationMethodIssue(code: .invalidPackage, selectedPackageID: id)
        case .missingCapability:
            return ResearchCitationMethodIssue(code: .missingCapability)
        case .citationStyleMissing(let id):
            return ResearchCitationMethodIssue(
                code: .citationStyleMissing,
                selectedPackageID: id
            )
        case .citationStyleMismatch(let id, _):
            return ResearchCitationMethodIssue(
                code: .citationStyleMismatch,
                selectedPackageID: id
            )
        }
    }
}
