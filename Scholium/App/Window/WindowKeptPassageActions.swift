import Foundation
import ScholiumContracts

extension WindowModel {
    func keepRelatedPassage(_ card: RelatedMaterialCard) {
        guard let capabilities = windowWorkspaceController.activeCapabilities,
            capabilities.assignment.vaults.values.contains(where: { $0.id == card.reference.vaultID })
        else {
            researchController.keptPassages.report(KeptPassageError.unavailable)
            return
        }
        researchController.keptPassages.retain(KeptPassage(card: card))
    }

    func keepLinkPassage(_ item: InspectorLinkItem) async {
        let kept = researchController.keptPassages
        guard let capabilities = windowWorkspaceController.activeCapabilities,
            capabilities.assignment.vaults.values.contains(where: { $0.id == item.edge.source.vaultID }),
            let id = KeptPassage.identity(for: item)
        else {
            kept.report(KeptPassageError.unavailable)
            return
        }
        guard let capture = kept.beginCapture(id: id) else { return }
        do {
            let document = try await capabilities.documents.load(item.edge.source)
            try Task.checkCancellation()
            guard windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity,
                kept.isCurrent(capture)
            else {
                kept.finish(capture)
                return
            }
            kept.finish(capture, entry: try KeptPassage(item: item, document: document))
        } catch {
            guard windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity else {
                kept.finish(capture)
                return
            }
            kept.finish(capture, error: error is CancellationError ? nil : error)
        }
    }

    func openKeptPassage(_ entry: KeptPassage) async {
        let kept = researchController.keptPassages
        let generation = kept.generation
        guard let lifetime = kept.entryLifetime(for: entry), let capabilities = windowWorkspaceController.activeCapabilities else { return }
        // Follow reconciled stable identity after a move; the captured snapshot
        // and its original displayed provenance remain unchanged.
        let stableID = entry.reference.stableNoteID.flatMap(UUID.init(uuidString:))
        let matchingReferences =
            workspaceCatalog?.notes.filter {
                $0.reference.vaultID == entry.reference.vaultID
                    && stableID != nil
                    && $0.reference.stableNoteID.flatMap(UUID.init(uuidString:)) == stableID
            }.map(\.reference) ?? []
        let reference = matchingReferences.count == 1 ? matchingReferences[0] : entry.reference
        do {
            let document = try await capabilities.documents.load(.init(vaultID: reference.vaultID, relativePath: reference.relativePath))
            try Task.checkCancellation()
            guard windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity,
                kept.generation == generation, kept.entryLifetime(for: entry) == lifetime
            else { return }
            if document.fingerprint != entry.fingerprint {
                kept.report(KeptPassageError.changedSource)
            } else {
                let owner = workspaceStore.documentLocations.existingOwner(of: reference, excluding: self) ?? self
                if let noteID = reference.stableNoteID.flatMap(UUID.init(uuidString:)),
                    let session = owner.documentController.retainedSession(for: .init(vaultID: reference.vaultID, noteID: noteID)),
                    session.hasUnsavedChanges || session.editorSession.isComposing
                {
                    kept.report(KeptPassageError.unverifiedSource)
                } else {
                    kept.dismissError()
                }
            }
            await openWorkspaceReference(
                reference, line: entry.sourceRange.line, sourceFingerprint: entry.fingerprint,
                validateDisplay: { [weak self, weak kept] in
                    guard let self, let kept,
                        self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity,
                        kept.generation == generation, kept.entryLifetime(for: entry) == lifetime
                    else { throw CancellationError() }
                },
                validateSource: {
                    _ = try await capabilities.documents.load(.init(vaultID: reference.vaultID, relativePath: reference.relativePath))
                })
        } catch {
            guard !(error is CancellationError),
                windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity,
                kept.generation == generation, kept.entryLifetime(for: entry) == lifetime
            else { return }
            kept.report(KeptPassageError.missingSource)
        }
    }
}
