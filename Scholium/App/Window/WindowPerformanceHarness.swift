import Foundation

/// The measurement harness's editor commands. QA builds drive presentation
/// changes through notifications so a run can be timed from outside the app.
extension WindowModel {
    /// Drives the retained-editor performance scenario through the current
    /// document session instead of a one-shot SwiftUI presentation request.
    /// The editor bridge still performs the real mode transition and reports
    /// readiness only after CodeMirror acknowledges it.
    private func requestPerformanceEditorMode(_ mode: NotePresentationMode) {
        guard PerformanceProbe.shared.isEnabled,
            ProcessInfo.processInfo.arguments.contains(
                "--scholium-performance-editor-mode-notifications"
            ),
            mode != .read,
            canEditCurrentNote,
            let descriptor = currentDocumentDescriptor
        else { return }

        // The CJK correctness journey is not a latency measurement. Route it
        // through the same presentation-intent owner as the researcher menu so
        // it verifies the complete retained-editor transition without making
        // XCUITest traverse a system submenu while a 100k document is active.
        if PerformanceProbe.shared.exercisesLargeCJKCorrectness {
            requestDocumentMode(mode)
            return
        }

        let session = documentController.session(for: descriptor)
        guard session.isEditing, session.editorSession.isLoaded else {
            requestDocumentMode(mode)
            return
        }
        guard session.editorSession.context?.composing != true else { return }

        guard let editorMode = mode.editorMode else { return }
        PerformanceProbe.shared.beginEditorModeTransition(
            documentID: descriptor.reference.relativePath,
            mode: editorMode
        )
        session.switchEditorMode(to: editorMode)
        documentController.rememberPresentationMode(mode)
    }

    func handlePerformanceEditorRequest(_ name: String) {
        switch name {
        case "com.scholium.qa.performance-editor-mode.live-preview":
            requestPerformanceEditorMode(.livePreview)
        case "com.scholium.qa.performance-editor-mode.source":
            requestPerformanceEditorMode(.source)
        case "com.scholium.qa.performance-editor-activation":
            requestPerformanceEditActivation()
        case "com.scholium.qa.performance-editor-review":
            if currentNote == nil {
                // First-use Review is measured from the Library click. Arm
                // the workspace's presentation intent before a document
                // exists so setup does not create an unmeasured Editor.
                documentController.rememberPresentationMode(.read)
            } else {
                requestDocumentMode(.read)
            }
        case "com.scholium.qa.performance-editor-cached-preview":
            requestPerformanceCachedPreview()
        case "com.scholium.qa.performance-editor-visible-projection":
            guard let descriptor = currentDocumentDescriptor else { return }
            documentController.session(for: descriptor)
                .editorSession.measureVisibleProjection()
        case "com.scholium.qa.performance-editor-cjk-correctness":
            guard PerformanceProbe.shared.exercisesLargeCJKCorrectness,
                let descriptor = currentDocumentDescriptor
            else { return }
            let session = documentController.session(for: descriptor)
            PerformanceProbe.shared.recordLargeCJKCorrectness(
                documentID: descriptor.reference.relativePath,
                source: session.editingSource
            )
        default:
            return
        }
    }

    private func requestPerformanceEditActivation() {
        guard canEditCurrentNote,
            let descriptor = currentDocumentDescriptor
        else { return }
        let session = documentController.session(for: descriptor)
        guard !session.isEditing else { return }
        PerformanceProbe.shared.beginEditActivation(
            documentID: descriptor.reference.relativePath
        )
        requestDocumentMode(.livePreview)
    }

    private func requestPerformanceCachedPreview() {
        guard let descriptor = currentDocumentDescriptor else { return }
        let session = documentController.session(for: descriptor)
        guard session.isEditing else { return }
        Task { @MainActor in
            for _ in 0..<200 {
                guard currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
                    session.isEditing
                else { return }
                if let preview = session.previewCatalog?.links.first {
                    await session.editorSession.showPreview(
                        for: preview,
                        in: session.editingSource
                    )
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
