import Foundation

/// Synthetic-fixture requests enter the same native read/edit transition as
/// researcher commands. A measured completion comes from native layout.
extension WindowModel {
    private func requestPerformanceEditorMode(_ mode: NotePresentationMode) {
        guard PerformanceProbe.shared.isEnabled,
            ProcessInfo.processInfo.arguments.contains("--scholium-performance-editor-mode-notifications"),
            let descriptor = currentDocumentDescriptor,
            mode == .read || canEditCurrentNote
        else { return }
        let session = documentController.session(for: descriptor)
        guard !session.editorSession.isComposing else { return }
        PerformanceProbe.shared.beginEditorModeTransition(
            documentID: descriptor.reference.relativePath, mode: mode == .read ? .read : .edit)
        requestDocumentMode(mode)
    }

    func handlePerformanceEditorRequest(_ name: String) {
        switch name {
        case "com.scholium.qa.performance-editor-mode.edit":
            requestPerformanceEditorMode(.edit)
        case "com.scholium.qa.performance-editor-mode.read":
            requestPerformanceEditorMode(.read)
        case "com.scholium.qa.performance-editor-activation":
            requestPerformanceEditActivation()
        case "com.scholium.qa.performance-editor-review":
            if currentNote == nil { documentController.rememberPresentationMode(.read) } else { requestDocumentMode(.read) }
        case "com.scholium.qa.performance-editor-cjk-correctness":
            guard PerformanceProbe.shared.exercisesLargeCJKCorrectness,
                let descriptor = currentDocumentDescriptor
            else { return }
            let session = documentController.session(for: descriptor)
            PerformanceProbe.shared.recordLargeCJKCorrectness(
                documentID: descriptor.reference.relativePath, source: session.editorSession.checkedSource)
        default: return
        }
    }

    private func requestPerformanceEditActivation() {
        guard canEditCurrentNote, let descriptor = currentDocumentDescriptor else { return }
        let session = documentController.session(for: descriptor)
        guard !session.isEditing else { return }
        PerformanceProbe.shared.beginEditActivation(documentID: descriptor.reference.relativePath)
        requestDocumentMode(.edit)
    }
}
