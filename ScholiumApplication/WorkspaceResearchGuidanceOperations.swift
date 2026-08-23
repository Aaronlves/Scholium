import Foundation
import ScholiumContracts
import ScholiumCore

// Machine-local source binding and citation settings remain Workspace-owned.
extension WorkspaceHandle {
    func researchSourceAccessStatus(
        for proposedTarget: ResearchActionNoteSnapshot
    ) async throws -> ResearchSourceAccessStatus {
        try requireActive()
        let target = try await researchActionRunCoordinator
            .validateResearchActionTarget(
            proposedTarget,
            expected: proposedTarget.fingerprint,
            host: self
        )
        guard target.note.schemaProfile == .analysis,
              proposedTarget.role == .analysis else {
            throw ResearchActionRunContractError.invalidTargetRole(
                actionID: .analyze,
                role: proposedTarget.role
            )
        }
        do {
            return .available(
                try await researchActionRunCoordinator.resolveResearchSourceAccess(
                    for: target
                ).reference
            )
        } catch let error as ResearchActionRunContractError {
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
        let target = try await researchActionRunCoordinator
            .validateResearchActionTarget(
            request.target,
            expected: request.target.fingerprint,
            host: self
        )
        guard target.note.schemaProfile == .analysis,
              request.target.role == .analysis else {
            throw ResearchActionRunContractError.invalidTargetRole(
                actionID: .analyze,
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
                let zoteroPath = try researchActionRunCoordinator
                    .validatedZoteroAttachmentURL(
                    attachment.fileURL
                )
                guard selectedPath.path == zoteroPath.path else {
                    throw ResearchActionRunContractError.sourceAccessUnavailable(
                        ResearchSourceAccessFailure(code: .zoteroIdentityMismatch)
                    )
                }
                let targetBinding = try await researchActionRunCoordinator
                    .portableTargetZoteroBinding(target)
                guard targetBinding == nil || targetBinding?.itemKey == attachment.itemKey else {
                    throw ResearchActionRunContractError.sourceAccessUnavailable(
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
            throw ResearchActionRunContractError.sourceAccessUnavailable(error.failure)
        } catch let error as ZoteroUseCaseError {
            throw ResearchActionRunContractError.sourceAccessUnavailable(
                ResearchSourceAccessFailure(
                    code: researchActionRunCoordinator.sourceFailureCode(for: error)
                )
            )
        }
    }

    func removeResearchSourceAccess(
        for proposedTarget: ResearchActionNoteSnapshot
    ) async throws {
        try requireActive()
        let target = try await researchActionRunCoordinator
            .validateResearchActionTarget(
            proposedTarget,
            expected: proposedTarget.fingerprint,
            host: self
        )
        guard target.note.schemaProfile == .analysis,
              proposedTarget.role == .analysis else {
            throw ResearchActionRunContractError.invalidTargetRole(
                actionID: .analyze,
                role: proposedTarget.role
            )
        }
        do {
            try await services.researchSourceAccessStore.remove(
                analysisNoteID: proposedTarget.noteID
            )
        } catch let error as ResearchSourceAccessStoreError {
            throw ResearchActionRunContractError.sourceAccessUnavailable(error.failure)
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
