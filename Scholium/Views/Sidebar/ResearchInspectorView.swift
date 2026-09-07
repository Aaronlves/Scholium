import ScholiumContracts
import SwiftUI

struct ResearchInspectorView: View {
    @ObservedObject private var shellState: WindowShellState

    @ObservedObject var research: ResearchController
    let note: WindowDocumentLocation
    let graph: GraphSnapshot?
    let catalog: WorkspaceCatalogSnapshot?
    let currentVaultID: UUID?
    let researchInspectorContentContext: ResearchInspectorContentContext
    let openReference: (VaultNoteReference, Int?) -> Void
    let editSource: (VaultNoteReference, Int) -> Void

    init(
        research: ResearchController,
        note: WindowDocumentLocation,
        shellState: WindowShellState,
        graph: GraphSnapshot?,
        catalog: WorkspaceCatalogSnapshot?,
        currentVaultID: UUID?,
        researchInspectorContentContext: ResearchInspectorContentContext,
        openReference: @escaping (VaultNoteReference, Int?) -> Void,
        editSource: @escaping (VaultNoteReference, Int) -> Void
    ) {
        self.research = research
        self.note = note
        _shellState = ObservedObject(wrappedValue: shellState)
        self.graph = graph
        self.catalog = catalog
        self.currentVaultID = currentVaultID
        self.researchInspectorContentContext = researchInspectorContentContext
        self.openReference = openReference
        self.editSource = editSource
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Retain the one field draft across Inspector projections. A
            // document departure drains it through the window flush owner.
            ResearchOverviewView(note: note, context: researchInspectorContentContext)
                .id(note.workspaceSnapshot?.stableIdentity.resolvedID)
                .opacity(shellState.inspector.mode == .about ? 1 : 0)
                .allowsHitTesting(shellState.inspector.mode == .about)
                .disabled(shellState.inspector.mode != .about)
                .accessibilityHidden(shellState.inspector.mode != .about)
            if shellState.inspector.mode == .links {
                ConnectionsInspectorView(
                    context: connectionsContext,
                    session: research.linksInspector
                )
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scholiumSurface(.apparatus)
        .tint(ScholiumColorRole.accent.color)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchInspector")
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
            editSource: editSource
        )
    }
}
