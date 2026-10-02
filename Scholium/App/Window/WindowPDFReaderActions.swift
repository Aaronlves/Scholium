import Foundation
import ScholiumContracts

extension WindowModel {
    func refreshPDFReaderContext() {
        guard let capabilities = windowWorkspaceController.activeCapabilities,
            let descriptor = currentDocumentDescriptor,
            let source = currentNote?.hydratedSnapshot?.document.rawContent
        else {
            sidePaneCoordinator.documentContextWillChange(to: nil)
            pdfReaderController.follow(nil, operations: nil)
            return
        }
        let target = SourceAttachmentTarget(
            noteID: descriptor.sessionKey.noteID, vaultID: descriptor.reference.vaultID, relativePath: descriptor.reference.relativePath)
        let session = documentController.session(for: descriptor)
        let currentSource = session.isEditing && session.editorSession.hasRecoverableBuffer ? session.editorSession.checkedSource : source
        let document = NoteDocument(relativePath: target.relativePath, rawContent: currentSource)
        let path: String?
        do {
            path = try PDFNoteBinding.path(in: document)
        } catch {
            let context = PDFReaderNoteContext(triptychID: capabilities.id, target: target, authoredPath: "")
            sidePaneCoordinator.documentContextWillChange(to: context)
            pdfReaderController.follow(
                context,
                operations: capabilities.pdfReader, sharedStoreID: capabilities.runtimeIdentity.activationID)
            return
        }
        let context = PDFReaderNoteContext(triptychID: capabilities.id, target: target, authoredPath: path)
        sidePaneCoordinator.documentContextWillChange(to: context)
        pdfReaderController.follow(
            context,
            operations: capabilities.pdfReader, sharedStoreID: capabilities.runtimeIdentity.activationID)
    }
}
