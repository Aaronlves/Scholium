import SwiftUI

/// Owns the presentation boundary between the committed Read projection and
/// the exact-source editor. Once the editor has been created, ordinary mode
/// switches change visibility and focus only; they do not remove either WebKit
/// surface from the hierarchy.
struct DocumentEditorHost<ReadSurface: View, EditorSurface: View>: View {
    let presentsEditor: Bool
    let retainsEditor: Bool
    let editorIsReady: Bool
    private let readSurface: ReadSurface
    private let editorSurface: EditorSurface

    init(
        presentsEditor: Bool,
        retainsEditor: Bool,
        editorIsReady: Bool,
        @ViewBuilder read: () -> ReadSurface,
        @ViewBuilder editor: () -> EditorSurface
    ) {
        self.presentsEditor = presentsEditor
        self.retainsEditor = retainsEditor
        self.editorIsReady = editorIsReady
        readSurface = read()
        editorSurface = editor()
    }

    private var showsEditor: Bool {
        presentsEditor && editorIsReady
    }

    var body: some View {
        ZStack {
            readSurface
                .opacity(showsEditor ? 0 : 1)
                .allowsHitTesting(!presentsEditor)
                .accessibilityHidden(showsEditor)
                .zIndex(showsEditor ? 0 : 1)

            if retainsEditor {
                editorSurface
                    .opacity(showsEditor ? 1 : 0)
                    .allowsHitTesting(showsEditor)
                    .accessibilityHidden(!showsEditor)
                    .zIndex(showsEditor ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
