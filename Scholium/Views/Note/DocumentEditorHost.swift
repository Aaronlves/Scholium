import SwiftUI

enum DocumentSurfaceVisibility: Equatable {
    case active
    case retained

    var isActive: Bool {
        self == .active
    }
}

private struct ScholiumDocumentSurfaceVisibilityKey: EnvironmentKey {
    static let defaultValue = DocumentSurfaceVisibility.active
}

extension EnvironmentValues {
    var scholiumDocumentSurfaceVisibility: DocumentSurfaceVisibility {
        get { self[ScholiumDocumentSurfaceVisibilityKey.self] }
        set { self[ScholiumDocumentSurfaceVisibilityKey.self] = newValue }
    }
}

/// Owns the editor acknowledgement and recovery handoff. Initial Review ->
/// editor entry waits for the requested bridge mode, while an already
/// presented CodeMirror surface stays visible during its atomic Edit <->
/// Source compartment reconfiguration.
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

    func mountsReadSurface(presentsEditor: Bool, allowsPendingRecovery: Bool) -> Bool {
        !presentsEditor || allowsPendingRecovery
    }

    func allowsReadHitTesting(
        documentID: String,
        presentsEditor: Bool,
        editorIsReady: Bool,
        allowsPendingRecovery: Bool
    ) -> Bool {
        (allowsPendingRecovery && !editorIsReady)
            || !showsEditor(
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
/// the exact-source editor. The read-only WebKit surface is mounted only while
/// Review or pending read recovery is presented. The editor remains retained
/// after allocation so its source, selection, composition, and Undo stay live.
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
        !allowsPendingReadRecovery
            && presentationGate.showsEditor(
                documentID: documentID,
                presentsEditor: presentsEditor,
                editorIsReady: editorIsReady
            )
    }

    var body: some View {
        ZStack {
            if presentationGate.mountsReadSurface(
                presentsEditor: presentsEditor,
                allowsPendingRecovery: allowsPendingReadRecovery
            ) {
                readSurface
                    .environment(\.scholiumDocumentSurfaceVisibility, .active)
                    .allowsHitTesting(
                        presentationGate.allowsReadHitTesting(
                            documentID: documentID,
                            presentsEditor: presentsEditor,
                            editorIsReady: editorIsReady,
                            allowsPendingRecovery: allowsPendingReadRecovery
                        )
                    )
                    .accessibilityHidden(false)
                    .zIndex(showsEditor ? 0 : 1)
            }

            if retainsEditor {
                editorSurface
                    .environment(
                        \.scholiumDocumentSurfaceVisibility,
                        showsEditor ? .active : .retained
                    )
                    .allowsHitTesting(showsEditor)
                    .accessibilityHidden(!showsEditor)
                    .zIndex(showsEditor ? 1 : 0)
            }
            if presentsEditor && !showsEditor && !allowsPendingReadRecovery {
                // Keep WebKit participating in real layout while the document
                // plane covers preparation. Hiding the WebView itself defers
                // the very rendering work that determines readiness.
                ScholiumContentStateView("Loading Document…", indicator: .progress)
                    .scholiumSurface(.document)
                    .accessibilityIdentifier("scholium.documentPreparing")
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
        .onChange(of: allowsPendingReadRecovery) { _, allowsRecovery in
            if allowsRecovery {
                presentationGate.reconcile(
                    documentID: documentID, presentsEditor: false, editorIsReady: false
                )
            }
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
