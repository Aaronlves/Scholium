import Combine
import Foundation
import ScholiumContracts

enum AttentionNotificationFilter: Hashable, Sendable {
    case all
    case agentChanges
    case settlements

    var showsAgentChanges: Bool {
        self == .all || self == .agentChanges
    }

    var showsSettlements: Bool {
        self == .all || self == .settlements
    }
}

enum AttentionNotificationCopy {
    static func refreshing(locale: Locale = .current) -> String {
        ScholiumL10n.string(
            "Refreshing — showing the last available results.",
            locale: locale
        )
    }

    static func stale(
        reason: String,
        locale: Locale = .current
    ) -> String {
        String.localizedStringWithFormat(
            ScholiumL10n.string("Results may be out of date. %@", locale: locale),
            reason
        )
    }

    static func refreshFailed(
        reason: String,
        locale: Locale = .current
    ) -> String {
        String.localizedStringWithFormat(
            ScholiumL10n.string(
                "Refresh failed. Showing the last available results. %@",
                locale: locale
            ),
            reason
        )
    }
}

/// Session-only presentation owned by one Workspace window. The transient
/// popover owns visibility; this value owns only filtering, selection, the
/// optional workspace subset used by Inspector, and the optional current-Note
/// subset. A nil workspace is the complete Triptych queue.
@MainActor
final class AttentionPresentationState: ObservableObject {
    @Published var filter = AttentionQueueFilter()
    @Published var notificationFilter = AttentionNotificationFilter.all
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

    /// A Workspace-window change starts a fresh Notifications visit. Transient
    /// query, kind, Note scope, and row focus never leak from the previously
    /// active window.
    func resetForWorkspaceSwitch() {
        filter = AttentionQueueFilter()
        notificationFilter = .all
        selectedItemID = nil
        noteScope = nil
        previousVisibleItemIDs = []
    }

    /// Reconciles selection after refresh or resolution. The old ordered list
    /// supplies deterministic next/previous behavior; when no row remains, the
    /// native filter/search control becomes the restoration target.
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
