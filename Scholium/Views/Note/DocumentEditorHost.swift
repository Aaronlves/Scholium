import SwiftUI

/// Owns only the native visibility handoff between two retained surfaces.
/// Initial Review -> editor entry waits for the requested bridge mode, while
/// an already presented CodeMirror surface stays visible during its atomic
/// Edit <-> Source compartment reconfiguration.
struct DocumentEditorPresentationGate: Equatable {
    private(set) var hasPresentedEditor = false

    mutating func reconcile(presentsEditor: Bool, editorIsReady: Bool) {
        if !presentsEditor {
            hasPresentedEditor = false
        } else if editorIsReady {
            hasPresentedEditor = true
        }
    }

    func showsEditor(presentsEditor: Bool, editorIsReady: Bool) -> Bool {
        presentsEditor && (hasPresentedEditor || editorIsReady)
    }

    func allowsReadHitTesting(
        presentsEditor: Bool,
        editorIsReady: Bool,
        allowsPendingRecovery: Bool
    ) -> Bool {
        !showsEditor(
            presentsEditor: presentsEditor,
            editorIsReady: editorIsReady
        ) && (!presentsEditor || allowsPendingRecovery)
    }

    func allowsEditorFocus(
        isEditing: Bool,
        isReturningToReview: Bool,
        editorIsReady: Bool,
        presentedModeMatchesIntent: Bool
    ) -> Bool {
        isEditing
            && !isReturningToReview
            && editorIsReady
            && presentedModeMatchesIntent
    }
}

/// Owns the presentation boundary between the committed Read projection and
/// the exact-source editor. Once the editor has been created, ordinary mode
/// switches change visibility and focus only; they do not remove either WebKit
/// surface from the hierarchy.
struct DocumentEditorHost<ReadSurface: View, EditorSurface: View>: View {
    let presentsEditor: Bool
    let retainsEditor: Bool
    let editorIsReady: Bool
    let allowsPendingReadRecovery: Bool
    private let readSurface: ReadSurface
    private let editorSurface: EditorSurface
    @State private var presentationGate = DocumentEditorPresentationGate()

    init(
        presentsEditor: Bool,
        retainsEditor: Bool,
        editorIsReady: Bool,
        allowsPendingReadRecovery: Bool = false,
        @ViewBuilder read: () -> ReadSurface,
        @ViewBuilder editor: () -> EditorSurface
    ) {
        self.presentsEditor = presentsEditor
        self.retainsEditor = retainsEditor
        self.editorIsReady = editorIsReady
        self.allowsPendingReadRecovery = allowsPendingReadRecovery
        readSurface = read()
        editorSurface = editor()
    }

    private var showsEditor: Bool {
        presentationGate.showsEditor(
            presentsEditor: presentsEditor,
            editorIsReady: editorIsReady
        )
    }

    var body: some View {
        ZStack {
            readSurface
                .opacity(showsEditor ? 0 : 1)
                .allowsHitTesting(presentationGate.allowsReadHitTesting(
                    presentsEditor: presentsEditor,
                    editorIsReady: editorIsReady,
                    allowsPendingRecovery: allowsPendingReadRecovery
                ))
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
        .onAppear {
            presentationGate.reconcile(
                presentsEditor: presentsEditor,
                editorIsReady: editorIsReady
            )
        }
        .onChange(of: presentsEditor) { _, _ in
            presentationGate.reconcile(
                presentsEditor: presentsEditor,
                editorIsReady: editorIsReady
            )
        }
        .onChange(of: editorIsReady) { _, _ in
            presentationGate.reconcile(
                presentsEditor: presentsEditor,
                editorIsReady: editorIsReady
            )
        }
    }
}
