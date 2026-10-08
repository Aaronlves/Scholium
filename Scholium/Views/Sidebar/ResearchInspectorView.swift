import ScholiumContracts
import SwiftUI

enum ResearchInspectorLayout {
    static let contentInset = ScholiumSidebarLayout.textInset
    // macOS plain List adds an 8pt native cell gutter outside listRowInsets.
    // Count that gutter once so rows align with the non-list controls.
    static let listRowInset = contentInset - ScholiumGrid.Spacing.inlineControlGap
    static let topInset = ScholiumSidebarLayout.edgeInset
}

struct ResearchInspectorView: View {
    @ObservedObject private var shellState: WindowShellState
    @Environment(\.scholiumReduceMotion) private var reduceMotion

    @State private var externalProjectionKey: String?
    @State private var externalLinks: [SourceResourceReferences.ExternalLink] = []
    let editor: MarkdownEditorSession?
    let termGroups: [SearchTermGroup]
    let noteURL: URL?
    let vaultRoots: [URL]
    let openExternalURL: (URL) -> Void
    @ObservedObject var research: ResearchController
    let note: WorkspaceNoteSnapshot
    let graph: GraphSnapshot?
    let catalog: WorkspaceCatalogSnapshot?
    let currentVaultID: UUID?
    let researchInspectorContentContext: ResearchInspectorContentContext
    let openReference: (VaultNoteReference, Int?, DocumentFingerprint?) -> Void
    let findRelated: @MainActor () -> Void
    let findRelatedWithTermGroup: @MainActor (SearchTermGroup?) -> Void
    let retryRelated: () -> Void
    let openRelated: (RelatedMaterialCard) -> Void
    let insertRelated: (RelatedMaterialCard) -> Void
    let insertRelatedParagraph: (RelatedMaterialCard) -> Void
    let canDiscussRelated: Bool
    let discussRelated: (RelatedMaterialCard) -> Void
    let keepRelated: (RelatedMaterialCard) -> Void
    let keepLink: (InspectorLinkItem) -> Void
    let openKept: (KeptPassage) -> Void

    init(
        research: ResearchController,
        editor: MarkdownEditorSession?,
        termGroups: [SearchTermGroup],
        noteURL: URL?,
        vaultRoots: [URL],
        openExternalURL: @escaping (URL) -> Void,
        note: WorkspaceNoteSnapshot,
        shellState: WindowShellState,
        graph: GraphSnapshot?,
        catalog: WorkspaceCatalogSnapshot?,
        currentVaultID: UUID?,
        researchInspectorContentContext: ResearchInspectorContentContext,
        openReference: @escaping (VaultNoteReference, Int?, DocumentFingerprint?) -> Void,
        findRelated: @escaping @MainActor () -> Void,
        findRelatedWithTermGroup: @escaping @MainActor (SearchTermGroup?) -> Void,
        retryRelated: @escaping () -> Void,
        openRelated: @escaping (RelatedMaterialCard) -> Void,
        insertRelated: @escaping (RelatedMaterialCard) -> Void,
        insertRelatedParagraph: @escaping (RelatedMaterialCard) -> Void,
        canDiscussRelated: Bool,
        discussRelated: @escaping (RelatedMaterialCard) -> Void,
        keepRelated: @escaping (RelatedMaterialCard) -> Void,
        keepLink: @escaping (InspectorLinkItem) -> Void,
        openKept: @escaping (KeptPassage) -> Void
    ) {
        self.editor = editor
        self.termGroups = termGroups
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
        self.findRelatedWithTermGroup = findRelatedWithTermGroup
        self.retryRelated = retryRelated
        self.openRelated = openRelated
        self.insertRelated = insertRelated
        self.insertRelatedParagraph = insertRelatedParagraph
        self.canDiscussRelated = canDiscussRelated
        self.discussRelated = discussRelated
        self.keepRelated = keepRelated
        self.keepLink = keepLink
        self.openKept = openKept
    }

    var body: some View {
        let showsRelated = shellState.inspector.mode == .related
        let linksActive = shellState.inspector.isVisible && !showsRelated
        let relatedActive = shellState.inspector.isVisible && showsRelated
        let paneAnimation: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.16)
        ZStack(alignment: .topLeading) {
            ConnectionsInspectorView(
                context: connectionsContext,
                session: research.linksInspector,
                keptPassages: research.keptPassages,
                keepLink: keepLink,
                openKept: openKept,
                isActive: linksActive
            )
            .animation(paneAnimation) { pane in
                pane.opacity(showsRelated ? 0 : 1)
            }
            .disabled(!linksActive)
            .allowsHitTesting(linksActive)
            .accessibilityHidden(!linksActive)

            RelatedMaterialsView(
                session: research.relatedMaterials,
                keptPassages: research.keptPassages,
                isVisible: relatedActive,
                editor: editor, termGroups: termGroups, find: findRelated,
                findWithTermGroup: findRelatedWithTermGroup,
                retry: retryRelated,
                open: openRelated, canAddToChat: canDiscussRelated, addToChat: discussRelated,
                insert: insertRelated, insertParagraph: insertRelatedParagraph,
                keepRelated: keepRelated, openKept: openKept
            )
            .animation(paneAnimation) { pane in
                pane.opacity(showsRelated ? 1 : 0)
            }
            .disabled(!relatedActive)
            .allowsHitTesting(relatedActive)
            .accessibilityHidden(!relatedActive)
        }
        .transaction {
            if reduceMotion {
                $0.animation = nil
                $0.disablesAnimations = true
            }
        }
        .task(id: resourceProjectionKey) {
            let source = note.document
            externalLinks = SourceResourceReferences.externalLinks(
                in: source.body, noteURL: noteURL, vaultRoots: vaultRoots)
            externalProjectionKey = resourceProjectionKey
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                VaultQualifiedNoteID(vaultID: $0, relativePath: note.id.relativePath)
            },
            freshness: researchInspectorContentContext.freshness,
            retryRefresh: researchInspectorContentContext.retryRefresh,
            openReference: { reference, line, fingerprint in
                openReference(reference, line, fingerprint)
            },
            externalLinks: externalProjectionKey == resourceProjectionKey ? externalLinks : [],
            openExternalURL: openExternalURL
        )
    }
}
