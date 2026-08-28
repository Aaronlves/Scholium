import ScholiumContracts
import Combine
import Foundation

enum AttentionIssueGroup: String, CaseIterable, Identifiable, Sendable {
    case identityAndMetadata
    case structureAndConnections
    case revisionAndResearch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .identityAndMetadata: "Identity & Metadata"
        case .structureAndConnections: "Structure & Connections"
        case .revisionAndResearch: "Revision & Research"
        }
    }

    var kinds: [AttentionQueueKind] {
        switch self {
        case .identityAndMetadata:
            [.malformedMetadata, .unresolvedIdentity]
        case .structureAndConnections:
            [.possibleOrphan, .brokenConnection, .ambiguousConnection]
        case .revisionAndResearch:
            [.changedSinceSettled, .synthesisMaterialChanged]
        }
    }

    func contains(_ item: AttentionQueueItem) -> Bool {
        kinds.contains(item.kind)
    }
}

/// Session-only presentation owned by one Workspace window. The transient
/// popover owns visibility; this value owns only filtering, selection, the
/// optional workspace subset used by Inspector, and the optional current-Note
/// subset. A nil workspace is the complete Triptych queue.
@MainActor
final class AttentionPresentationState: ObservableObject {
    @Published var filter = AttentionQueueFilter()
    @Published var selectedItemID: String?
    @Published private(set) var workspaceSlot: WorkspaceVaultSlot?
    @Published private(set) var noteScope: VaultQualifiedNoteID?
    @Published private(set) var filterFocusRequestGeneration: UInt64 = 0

    private var previousVisibleItemIDs: [String] = []

    func present(
        workspaceSlot: WorkspaceVaultSlot?,
        noteScope: VaultQualifiedNoteID?
    ) {
        self.workspaceSlot = workspaceSlot
        self.noteScope = noteScope
    }

    /// A workspace change retargets an Inspector-scoped queue but never turns
    /// an already open Triptych queue into one workspace's subset.
    func selectWorkspaceSlot(_ slot: WorkspaceVaultSlot) {
        guard workspaceSlot != nil else { return }
        workspaceSlot = slot
        noteScope = nil
        selectedItemID = nil
        previousVisibleItemIDs = []
    }

    func select(_ itemID: String?) {
        selectedItemID = itemID
    }

    /// A Workspace-window change starts a fresh Attention visit. Machine-local
    /// dismissals remain intact, but transient query, kind, Note scope, and row
    /// focus never leak from the previously active window.
    func resetForWorkspaceSwitch() {
        filter = AttentionQueueFilter()
        selectedItemID = nil
        noteScope = nil
        previousVisibleItemIDs = []
    }

    /// Reconciles selection after refresh, dismissal, or resolution. The old
    /// ordered list supplies deterministic next/previous behavior; when no row
    /// remains, the native filter/search control becomes the restoration target.
    func reconcileVisibleItems(_ itemIDs: [String]) {
        defer { previousVisibleItemIDs = itemIDs }
        guard let selectedItemID else {
            if previousVisibleItemIDs.isEmpty { previousVisibleItemIDs = itemIDs }
            return
        }
        guard !itemIDs.contains(selectedItemID) else { return }

        let previous = previousVisibleItemIDs
        if let index = previous.firstIndex(of: selectedItemID) {
            if let next = previous.dropFirst(index + 1).first(where: itemIDs.contains) {
                self.selectedItemID = next
                return
            }
            if let prior = previous[..<index].reversed().first(where: itemIDs.contains) {
                self.selectedItemID = prior
                return
            }
        }
        self.selectedItemID = itemIDs.first
        if itemIDs.isEmpty { filterFocusRequestGeneration &+= 1 }
    }
}
