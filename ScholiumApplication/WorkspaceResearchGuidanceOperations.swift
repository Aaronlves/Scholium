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
        let snapshot = try await services.researchConfigurationStore
            .citationMethodSnapshot()
        return ResearchCitationMethodStatus(
            availableStyles: ResearchCitationStyleCatalog.options,
            activeCitationStyle: snapshot?.document.activeCitationStyle,
            configurationRevision: snapshot?.revision
        )
    }

    func activateResearchCitationMethod(
        _ selection: ResearchCitationMethodSelection,
        expectedConfigurationRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus {
        try requireActive()
        guard ResearchCitationStyleCatalog.option(
            for: selection.citationStyle
        ) != nil else {
            throw ResearchCitationMethodContractError.unsupportedCitationStyle(
                selection.citationStyle
            )
        }
        let mutationLease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationLease) }
        _ = try await services.researchConfigurationStore.saveCitationMethod(
            try ResearchCitationMethodDocument(
                triptychID: id,
                activeCitationStyle: selection.citationStyle
            ),
            expectedRevision: expectedConfigurationRevision
        )
        return try await researchCitationMethodStatus()
    }

    func clearResearchCitationMethod(
        expectedConfigurationRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus {
        try requireActive()
        let mutationLease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationLease) }
        _ = try await services.researchConfigurationStore.saveCitationMethod(
            try ResearchCitationMethodDocument(triptychID: id),
            expectedRevision: expectedConfigurationRevision
        )
        return try await researchCitationMethodStatus()
    }

}
