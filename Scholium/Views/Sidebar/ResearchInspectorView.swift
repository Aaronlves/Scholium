import ScholiumContracts
import SwiftUI

enum ResearchInspectorLayout {
    static let contentInset = ScholiumSidebarLayout.textInset
    // macOS plain List adds an 8pt native cell gutter outside listRowInsets.
    // Count that gutter once so rows align with the non-list controls.
    static let listRowInset = contentInset - ScholiumGrid.Spacing.inlineControlGap
    static let topInset = ScholiumSidebarLayout.edgeInset
    static let sectionSpacing = ScholiumSidebarLayout.sectionSpacing
    static let bottomInset = ScholiumSidebarLayout.textInset
}

struct ResearchInspectorView: View {
    @ObservedObject private var shellState: WindowShellState

    @State private var externalProjectionKey: String?
    @State private var externalLinks: [SourceResourceReferences.ExternalLink] = []
    let editor: MarkdownEditorSession?
    let noteURL: URL?
    let vaultRoots: [URL]
    let openExternalURL: (URL) -> Void
    @ObservedObject var research: ResearchController
    let note: WindowDocumentLocation
    let graph: GraphSnapshot?
    let catalog: WorkspaceCatalogSnapshot?
    let currentVaultID: UUID?
    let researchInspectorContentContext: ResearchInspectorContentContext
    let openReference: (VaultNoteReference, Int?) -> Void
    let findRelated: @MainActor () -> Void
    let retryRelated: () -> Void
    let openRelated: (RelatedMaterialCard) -> Void
    let insertRelated: (RelatedMaterialCard) -> Void
    let discussRelated: (RelatedMaterialCard) -> Void

    init(
        research: ResearchController,
        editor: MarkdownEditorSession?,
        noteURL: URL?,
        vaultRoots: [URL],
        openExternalURL: @escaping (URL) -> Void,
        note: WindowDocumentLocation,
        shellState: WindowShellState,
        graph: GraphSnapshot?,
        catalog: WorkspaceCatalogSnapshot?,
        currentVaultID: UUID?,
        researchInspectorContentContext: ResearchInspectorContentContext,
        openReference: @escaping (VaultNoteReference, Int?) -> Void,
        findRelated: @escaping @MainActor () -> Void,
        retryRelated: @escaping () -> Void,
        openRelated: @escaping (RelatedMaterialCard) -> Void,
        insertRelated: @escaping (RelatedMaterialCard) -> Void,
        discussRelated: @escaping (RelatedMaterialCard) -> Void
    ) {
        self.editor = editor
        self.noteURL = noteURL
        self.vaultRoots = vaultRoots
        self.openExternalURL = openExternalURL
        self.research = research
        self.note = note
        _shellState = ObservedObject(wrappedValue: shellState)
        self.graph = graph
        self.catalog = catalog
        self.currentVaultID = currentVaultID
        self.researchInspectorContentContext = researchInspectorContentContext
        self.openReference = openReference
        self.findRelated = findRelated
        self.retryRelated = retryRelated
        self.openRelated = openRelated
        self.insertRelated = insertRelated
        self.discussRelated = discussRelated
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if shellState.inspector.mode == .related {
                RelatedMaterialsView(
                    session: research.relatedMaterials, isVisible: shellState.inspector.isVisible,
                    editor: editor, find: findRelated,
                    retry: retryRelated,
                    open: openRelated, addToChat: discussRelated, insert: insertRelated)
            }
            if shellState.inspector.mode == .links {
                ConnectionsInspectorView(
                    context: connectionsContext,
                    session: research.linksInspector
                )
            }
        }
        .task(id: resourceProjectionKey) {
            let source = note.document
            externalLinks = SourceResourceReferences.externalLinks(
                in: source.body, noteURL: noteURL, vaultRoots: vaultRoots)
            externalProjectionKey = resourceProjectionKey
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scholiumSurface(.apparatus)
        .tint(nil as Color?)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchInspector")
    }

    private var resourceProjectionKey: String {
        note.document.fingerprint.sha256 + ":" + (noteURL?.absoluteString ?? "") + ":"
            + vaultRoots.map(\.path).sorted().joined(separator: "|")
    }

    private var connectionsContext: ConnectionsInspectorContext {
        ConnectionsInspectorContext(
            graph: graph,
            catalog: catalog,
            current: currentVaultID.map {
                VaultQualifiedNoteID(vaultID: $0, relativePath: note.relativePath)
            },
            freshness: researchInspectorContentContext.freshness,
            retryRefresh: researchInspectorContentContext.retryRefresh,
            openReference: { reference, line in
                openReference(reference, line)
            },
            externalLinks: externalProjectionKey == resourceProjectionKey ? externalLinks : [],
            openExternalURL: openExternalURL
        )
    }
}
