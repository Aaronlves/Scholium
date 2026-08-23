import Foundation
import ScholiumContracts
import ScholiumCore

// Current source, Material, Target, and repair evidence used by preparation.
extension ResearchFunctionCoordinator {
    func requiredResearchSourceAccess(
        for target: ValidatedFunctionObject,
        function: ResearchFunctionID,
        allowsResearcherProvidedSource: Bool = false
    ) async throws -> ResolvedResearchSourceAccess? {
        guard function == .develop, target.note.schemaProfile == .analysis else {
            return nil
        }
        if allowsResearcherProvidedSource {
            return nil
        }
        if try await usesExternalZoteroRoute(for: target) {
            // A Zotero relationship is an external data route. The Agent may
            // use its released Zotero/MCP adapter without Scholium resolving
            // an attachment bookmark or local file locator for this Run.
            return nil
        }
        // An explicit local source selection remains the preferred
        // source-material route when it is currently resolvable.
        return try await resolveResearchSourceAccess(for: target)
    }

    func hasExternalZoteroBinding<Host: ResearchFunctionCoordinatorHost>(
        for proposedTarget: ResearchFunctionTarget,
        host: isolated Host
    ) async throws -> Bool {
        return try await usesExternalZoteroRoute(for: validateResearchFunctionTarget(
            proposedTarget,
            expected: proposedTarget.fingerprint,
            host: host
        ))
    }

    private func usesExternalZoteroRoute(
        for target: ValidatedFunctionObject
    ) async throws -> Bool {
        guard try await portableTargetZoteroBinding(target) != nil else {
            return false
        }
        let sourceReference = try await dependencies.sourceAccessStore.reference(
            analysisNoteID: target.noteID
        )
        return sourceReference == nil
            || sourceReference?.identity.route == .zoteroAttachment
    }

    func zoteroBibliographicContext(
        for target: ValidatedFunctionObject,
        expectedBinding: AnalysisZoteroBinding? = nil
    ) async throws -> ZoteroBibliographicContext? {
        guard target.note.schemaProfile == .analysis else {
            return nil
        }
        let binding: AnalysisZoteroBinding
        if let expectedBinding {
            guard expectedBinding.noteID == target.noteID else {
                throw ResearchAgentConnectionError.newAnalysisReplayConflict
            }
            binding = expectedBinding
        } else {
            guard let current = try await portableTargetZoteroBinding(target) else {
                return nil
            }
            binding = current
        }
        let itemKey = binding.itemKey
        let capturedAt = researchFunctionRecordTimestamp()
        do {
            switch try await dependencies.zotero.resolve(binding: binding) {
            case .matched(let metadata, .itemKey):
                return ZoteroBibliographicContext(
                    itemKey: itemKey,
                    state: .resolved,
                    metadata: metadata,
                    capturedAt: capturedAt
                )
            case .matched, .ambiguous:
                return ZoteroBibliographicContext(
                    itemKey: itemKey,
                    state: .invalidResponse,
                    warning: "Zotero did not resolve the item key to exactly one parent item.",
                    capturedAt: capturedAt
                )
            case .notFound, .insufficientMetadata:
                return ZoteroBibliographicContext(
                    itemKey: itemKey,
                    state: .notFound,
                    warning: "Zotero item \(itemKey) was not found.",
                    capturedAt: capturedAt
                )
            }
        } catch let error as ZoteroUseCaseError {
            let state: ZoteroBibliographicContext.RetrievalState = switch error {
            case .itemMissing:
                .notFound
            case .invalidResponse, .invalidItemKey, .invalidAnalysisReference,
                 .attachmentIdentityMismatch, .invalidAttachmentURL:
                .invalidResponse
            case .attachmentMissing:
                .notFound
            case .appUnavailable, .apiDisabled:
                .unavailable
            }
            return ZoteroBibliographicContext(
                itemKey: itemKey,
                state: state,
                warning: error.localizedDescription,
                capturedAt: capturedAt
            )
        } catch {
            return ZoteroBibliographicContext(
                itemKey: itemKey,
                state: .unavailable,
                warning: "Zotero bibliographic metadata is unavailable for this task.",
                capturedAt: capturedAt
            )
        }
    }

    func validateResearchFunctionMaterials<
        Host: ResearchFunctionCoordinatorHost
    >(
        _ materials: [ResearchFunctionMaterial],
        host: isolated Host
    ) async throws -> [ValidatedFunctionObject] {
        var result: [ValidatedFunctionObject] = []
        for material in materials {
            result.append(try await validateResearchFunctionMaterial(
                material,
                expected: material.fingerprint,
                host: host
            ))
        }
        return result
    }

    func validateResearchFunctionWriteTargets<
        Host: ResearchFunctionCoordinatorHost
    >(
        _ request: ResearchFunctionRequest,
        host: isolated Host
    ) async throws -> [ValidatedFunctionObject] {
        guard [.develop, .revise].contains(request.function) else { return [] }
        return [try await validateResearchFunctionTarget(
            request.target,
            expected: request.target.fingerprint,
            host: host
        )]
    }

    func validateResearchFunctionFidelityTargets<
        Host: ResearchFunctionCoordinatorHost
    >(
        _ request: ResearchFunctionRequest,
        host: isolated Host
    ) async throws -> [ValidatedFunctionObject] {
        guard request.function == .fidelity else { return [] }
        var validated: [ValidatedFunctionObject] = []
        for target in request.resolvedFidelityTargets {
            validated.append(try await validateResearchFunctionTarget(
                target,
                expected: target.fingerprint,
                host: host
            ))
        }
        return validated
    }

    func researchSourceAccessStatus<
        Host: ResearchFunctionCoordinatorHost
    >(
        for proposedTarget: ResearchFunctionTarget,
        host: isolated Host
    ) async throws -> ResearchSourceAccessStatus {
        let target = try await validateResearchFunctionTarget(
            proposedTarget,
            expected: proposedTarget.fingerprint,
            host: host
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
                try await resolveResearchSourceAccess(for: target).reference
            )
        } catch let error as ResearchFunctionContractError {
            if case .sourceAccessUnavailable(let failure) = error {
                let reference = try? await dependencies.sourceAccessStore.reference(
                    analysisNoteID: proposedTarget.noteID
                )
                return .repairRequired(failure.code, reference: reference)
            }
            throw error
        }
    }

    func researchFunctionTargetRepairReason<
        Host: ResearchFunctionCoordinatorHost
    >(
        _ target: ResearchFunctionTarget,
        host: isolated Host
    ) async -> ResearchFunctionRepairReason? {
        let currentSnapshot = host.researchFunctionCurrentSnapshot()
        guard let note = currentSnapshot.document(id: target.note) else {
            return ResearchFunctionRepairReason(code: .targetUnavailable)
        }
        guard case .resolved(let stableID) = note.stableIdentity,
              stableID == target.noteID else {
            return ResearchFunctionRepairReason(code: .targetIdentityChanged)
        }
        guard ResearchFunctionTargetRole(vaultRole: note.vaultRole) == target.role else {
            return ResearchFunctionRepairReason(code: .targetIdentityChanged)
        }
        do {
            let document = try await repository(vaultID: target.note.vaultID).load(
                relativePath: target.note.relativePath
            )
            if document.fingerprint != target.fingerprint {
                return ResearchFunctionRepairReason(code: .targetChanged)
            }
        } catch {
            return ResearchFunctionRepairReason(code: .targetUnavailable)
        }
        return nil
    }


    func researchFunctionTitle(for note: WorkspaceNoteSnapshot) -> String {
        ResearchNoteTitleResolver.resolve(
            document: note.document,
            profile: note.schemaProfile,
            metadata: note.metadata
        ).title
    }
}
