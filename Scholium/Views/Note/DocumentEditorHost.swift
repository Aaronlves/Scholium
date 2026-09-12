import SwiftUI

/// Owns only the native visibility handoff between two retained surfaces.
/// Initial Review -> editor entry waits for the requested bridge mode, while
/// an already presented CodeMirror surface stays visible during its atomic
/// Edit <-> Source compartment reconfiguration.
struct DocumentEditorPresentationGate: Equatable {
    private(set) var presentedDocumentID: String?

    mutating func reconcile(documentID: String, presentsEditor: Bool, editorIsReady: Bool) {
        if !presentsEditor {
            presentedDocumentID = nil
        } else if editorIsReady {
            presentedDocumentID = documentID
        }
    }

    func showsEditor(documentID: String, presentsEditor: Bool, editorIsReady: Bool) -> Bool {
        presentsEditor && (presentedDocumentID == documentID || editorIsReady)
    }

    func allowsReadHitTesting(
        documentID: String,
        presentsEditor: Bool,
        editorIsReady: Bool,
        allowsPendingRecovery: Bool
    ) -> Bool {
        !showsEditor(
            documentID: documentID,
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
    let documentID: String
    let presentsEditor: Bool
    let retainsEditor: Bool
    let editorIsReady: Bool
    let allowsPendingReadRecovery: Bool
    private let readSurface: ReadSurface
    private let editorSurface: EditorSurface
    @State private var presentationGate = DocumentEditorPresentationGate()

    init(
        documentID: String,
        presentsEditor: Bool,
        retainsEditor: Bool,
        editorIsReady: Bool,
        allowsPendingReadRecovery: Bool = false,
        @ViewBuilder read: () -> ReadSurface,
        @ViewBuilder editor: () -> EditorSurface
    ) {
        self.documentID = documentID
        self.presentsEditor = presentsEditor
        self.retainsEditor = retainsEditor
        self.editorIsReady = editorIsReady
        self.allowsPendingReadRecovery = allowsPendingReadRecovery
        readSurface = read()
        editorSurface = editor()
    }

    private var showsEditor: Bool {
        presentationGate.showsEditor(
            documentID: documentID,
            presentsEditor: presentsEditor,
            editorIsReady: editorIsReady
        )
    }

    var body: some View {
        ZStack {
            readSurface
                // Keep a retained Review WebView composited behind the active
                // editor. A zero-opacity WKWebView can be suspended by WebKit
                // and fail to repaint when Review becomes visible again.
                // During the initial editor handoff the clear cover still
                // hides the stale projection until CodeMirror is ready.
                .opacity(presentsEditor && !showsEditor && !allowsPendingReadRecovery ? 0 : 1)
                .allowsHitTesting(
                    presentationGate.allowsReadHitTesting(
                        documentID: documentID,
                        presentsEditor: presentsEditor,
                        editorIsReady: editorIsReady,
                        allowsPendingRecovery: allowsPendingReadRecovery
                    )
                )
                .accessibilityHidden(presentsEditor && !allowsPendingReadRecovery)
                .zIndex(showsEditor ? 0 : 1)

            if retainsEditor {
                editorSurface
                    // Retain both document planes at full opacity and let
                    // z-order, hit testing, and accessibility own visibility.
                    // This avoids treating opacity as a WebKit lifecycle
                    // signal while preserving one visible surface.
                    .opacity(1)
                    .allowsHitTesting(showsEditor)
                    .accessibilityHidden(!showsEditor)
                    .zIndex(showsEditor ? 1 : 0)
            }
            if presentsEditor && !showsEditor && !allowsPendingReadRecovery {
                // Keep WebKit participating in real layout while the document
                // plane covers preparation. Hiding the WebView itself defers
                // the very rendering work that determines readiness.
                Color.clear
                    .scholiumSurface(.document)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .zIndex(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { $0.animation = nil }
        .onChange(of: documentID) { _, _ in
            presentationGate.reconcile(documentID: documentID, presentsEditor: presentsEditor, editorIsReady: editorIsReady)
        }
        .onAppear {
            presentationGate.reconcile(
                documentID: documentID,
                presentsEditor: presentsEditor,
                editorIsReady: editorIsReady
            )
        }
        .onChange(of: presentsEditor) { _, _ in
            presentationGate.reconcile(
                documentID: documentID,
                presentsEditor: presentsEditor,
                editorIsReady: editorIsReady
            )
        }
        .onChange(of: editorIsReady) { _, _ in
            presentationGate.reconcile(
                documentID: documentID,
                presentsEditor: presentsEditor,
                editorIsReady: editorIsReady
            )
        }
    }
}
