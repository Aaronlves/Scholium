import Foundation
import ScholiumContracts

extension WindowModel {
    /// This entry remains reachable while the Inspector is closed. It prepares
    /// discovery only; opening the pane and publishing cards remain explicit.
    func prepareRelatedMaterials() {
        let materials = researchController.relatedMaterials
        guard !isDetachedDocumentWindow, presentedDocumentMode != .read,
            let descriptor = currentDocumentDescriptor,
            let capabilities = windowWorkspaceController.activeCapabilities,
            let searchGeneration = workspaceProjectionController.searchGeneration
        else {
            materials.stopBackgroundPreparation()
            return
        }
        let editor = documentController.session(for: descriptor).editorSession
        guard editor.isReady, editor.isLoaded, !editor.isComposing else {
            materials.stopBackgroundPreparation()
            return
        }
        let key = RelatedMaterialsSession.BackgroundKey(
            runtime: capabilities.runtimeIdentity,
            note: .init(vaultID: descriptor.reference.vaultID, relativePath: descriptor.reference.relativePath),
            sessionID: editor.sessionID, documentID: editor.documentID,
            startingFingerprint: editor.startingFingerprint,
            editorGeneration: editor.generation, searchGeneration: searchGeneration)
        materials.prepareBackground(key: key) { [weak self] in
            guard let self,
                self.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
                self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == key.runtime,
                self.workspaceProjectionController.searchGeneration == key.searchGeneration,
                self.presentedDocumentMode != .read, !editor.isComposing,
                editor.sessionID == key.sessionID, editor.documentID == key.documentID,
                editor.startingFingerprint == key.startingFingerprint,
                editor.generation == key.editorGeneration
            else { throw CancellationError() }
            let snapshot = try await editor.currentTextSnapshot(for: key.documentID)
            try Task.checkCancellation()
            guard snapshot.generation == key.editorGeneration,
                self.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
                self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == key.runtime,
                editor.sessionID == key.sessionID, !editor.isComposing
            else { throw CancellationError() }
            try await capabilities.discovery.prepareRelatedContent(
                .init(seed: .init(noteID: key.note, source: snapshot.text)))
        }
    }
}
