import Combine
import Foundation
import ScholiumContracts

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
/// popover owns visibility; this value owns filtering and selection within
/// the complete Triptych queue.
@MainActor
final class AttentionPresentationState: ObservableObject {
    @Published var filter = AttentionQueueFilter()
    @Published var selectedItemID: String?
    @Published private(set) var filterFocusRequestGeneration: UInt64 = 0

    private var previousVisibleItemIDs: [String] = []

    func select(_ itemID: String?) {
        guard selectedItemID != itemID else { return }
        selectedItemID = itemID
    }

    /// A Workspace-window change starts a fresh Notifications visit. Transient
    /// query and row focus never leak from the previously active window.
    func resetForWorkspaceSwitch() {
        filter = AttentionQueueFilter()
        selectedItemID = nil
        previousVisibleItemIDs = []
    }

    /// Reconciles selection after refresh or resolution. The old ordered list
    /// supplies deterministic next/previous behavior; when no row remains, the
    /// native filter/search control becomes the restoration target.
    func reconcileVisibleItems(_ itemIDs: [String]) {
        defer { previousVisibleItemIDs = itemIDs }
        guard let selectedItemID else { return }
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
