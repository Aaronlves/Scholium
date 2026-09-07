import Foundation
import ScholiumContracts

extension WindowModel {
    @MainActor private var relatedMaterialChat: (any AgentChatContextReceiving)? { chatController }

    @MainActor
    func findRelatedMaterials() {
        let materials = researchController.relatedMaterials
        guard let capabilities = windowWorkspaceController.activeCapabilities,
              let descriptor = currentDocumentDescriptor, let note = currentNote,
              let stableID = note.workspaceSnapshot?.stableIdentity.resolvedID else {
            materials.report(RelatedMaterialsError.unavailable); return
        }
        let editor = documentController.session(for: descriptor).editorSession
        materials.find(capture: { [weak self] in
            let selection: MarkdownSourceSelectionSnapshot
            do { selection = try await editor.selectedSourceSnapshot() }
            catch { throw RelatedMaterialsError.selectionRequired }
            guard let self,
                  self.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
                  self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity else {
                throw CancellationError()
            }
            let seed = RelatedContentSeedSnapshot(
                noteID: VaultQualifiedNoteID(vaultID: descriptor.reference.vaultID, relativePath: note.relativePath),
                source: selection.source,
                focuses: [.init(kind: .selectedPassage, text: selection.excerpt)])
            return RelatedMaterialsSeed(request: .init(seed: seed), attachment: .init(
                noteID: stableID, vaultID: descriptor.reference.vaultID, relativePath: note.relativePath,
                text: selection.excerpt, fingerprint: seed.fingerprint, sourceLine: selection.line, sourceRange: selection.sourceRange))
        }, retrieve: { [discovery = capabilities.discovery] request in
            try await discovery.relatedContent(request)
        }, references: workspaceCatalog?.notes.map(\.reference) ?? [])
    }

    @MainActor
    func refreshRelatedMaterials() {
        guard let capabilities = windowWorkspaceController.activeCapabilities,
              let seed = researchController.relatedMaterials.seed else { return }
        researchController.relatedMaterials.find(capture: { seed }, retrieve: { [discovery = capabilities.discovery] request in
            _ = try await discovery.refresh()
            return try await discovery.relatedContent(request)
        }, references: workspaceCatalog?.notes.map(\.reference) ?? [])
    }

    /// The handoff speaks only in Note snapshots and generic chat context.
    /// Provider selection and runtime transport remain owned by Chat.
    @MainActor
    func useRelatedMaterial(_ card: RelatedMaterialCard, inChat: Bool) async -> Bool {
        let materials = researchController.relatedMaterials
        guard let capabilities = windowWorkspaceController.activeCapabilities,
              let seed = materials.seed else { return false }
        do {
            let document = try await capabilities.documents.load(card.candidate.note)
            guard windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity,
                  materials.seed?.request.id == seed.request.id else { return false }
            guard document.fingerprint == card.candidate.fingerprint,
                  workspaceCatalog?.notes.contains(where: { $0.reference == card.reference }) == true else {
                throw RelatedMaterialsError.changedSource
            }
            if let id = card.reference.stableNoteID.flatMap(UUID.init(uuidString:)),
               let retained = documentController.retainedSession(for: .init(vaultID: card.reference.vaultID, noteID: id)),
               retained.hasUnsavedChanges {
                throw RelatedMaterialsError.changedSource
            }
            if inChat {
                guard let attachment = card.attachment, let receiver = relatedMaterialChat,
                      receiver.attachContext([seed.attachment, attachment]) else {
                    throw RelatedMaterialsError.chatUnavailable
                }
            } else {
                await openWorkspaceReference(card.reference, line: card.passage.range.line, inspectorMode: .related)
            }
            return true
        } catch {
            materials.report(error)
            return false
        }
    }
}
