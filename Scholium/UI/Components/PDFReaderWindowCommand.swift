import Foundation

/// Toolbar, overflow and View-menu routes share the exact window's pane state.
@MainActor
enum PDFReaderWindowCommand {
    static func isVisible(in model: WindowModel) -> Bool {
        model.pdfReaderController.isVisible && !model.shellState.isFocusLayoutActive
    }

    static func isAvailable(in model: WindowModel) -> Bool {
        !model.shellState.isFocusLayoutLockedByFullScreen
            && model.nativeWindowCoordinator?.isNativeCloseInProgress != true
            && (model.currentNote != nil || model.pdfReaderController.isVisible)
    }

    static func toggle(in model: WindowModel) {
        guard isAvailable(in: model) else { return }
        let shouldShow = !isVisible(in: model)
        model.sidePaneCoordinator.setPDFVisible(shouldShow)
    }
}
