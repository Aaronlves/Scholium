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

enum AttentionNotificationFilter: Hashable, Sendable {
    case all
    case activities
    case issues
    case issue(AttentionQueueKind)

    var showsActivities: Bool {
        switch self {
        case .all, .activities: true
        case .issues, .issue: false
        }
    }

    var issueKind: AttentionQueueKind? {
        switch self {
        case .issue(let kind): kind
        case .all, .activities, .issues: nil
        }
    }

    var showsIssues: Bool {
        switch self {
        case .all, .issues, .issue: true
        case .activities: false
        }
    }
}

extension AttentionQueueKind {
    var localizedDisplayNameResource: LocalizedStringResource {
        switch self {
        case .possibleOrphan: "Possible Orphan"
        case .changedSinceSettled: "Changed Since Settled"
        case .synthesisMaterialChanged: "Synthesis Material Changed"
        case .malformedMetadata: "Malformed Metadata"
        case .brokenConnection: "Broken Connection"
        case .ambiguousConnection: "Ambiguous Connection"
        case .unresolvedIdentity: "Unresolved Identity"
        }
    }

    func localizedDisplayName(locale: Locale = .current) -> String {
        switch self {
        case .possibleOrphan:
            ScholiumL10n.string("Possible Orphan", locale: locale)
        case .changedSinceSettled:
            ScholiumL10n.string("Changed Since Settled", locale: locale)
        case .synthesisMaterialChanged:
            ScholiumL10n.string("Synthesis Material Changed", locale: locale)
        case .malformedMetadata:
            ScholiumL10n.string("Malformed Metadata", locale: locale)
        case .brokenConnection:
            ScholiumL10n.string("Broken Connection", locale: locale)
        case .ambiguousConnection:
            ScholiumL10n.string("Ambiguous Connection", locale: locale)
        case .unresolvedIdentity:
            ScholiumL10n.string("Unresolved Identity", locale: locale)
        }
    }
}

enum AttentionStructuralNotificationSearch {
    static func apply(
        to items: [AttentionQueueItem],
        filter: AttentionQueueFilter,
        locale: Locale = .current
    ) -> [AttentionQueueItem] {
        let query = normalized(filter.query, locale: locale)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            let searchable = [
                item.kind.displayName,
                item.kind.localizedDisplayName(locale: locale),
                item.message,
                AttentionIssueCopy.message(for: item, locale: locale),
                item.note.vaultName,
                item.note.relativePath,
                item.locator.map { "line \($0.line)" } ?? "",
            ].joined(separator: " ")
            return normalized(searchable, locale: locale).contains(query)
        }
    }

    private static func normalized(_ value: String, locale: Locale) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: locale
            )
    }
}

enum AttentionIssueCopy {
    static func message(
        for item: AttentionQueueItem,
        locale: Locale = .current
    ) -> String {
        switch item.message {
        case "Invalid YAML":
            ScholiumL10n.string("Invalid YAML", locale: locale)
        case "Changed after this revision was settled":
            ScholiumL10n.string(
                "Changed after this revision was settled",
                locale: locale
            )
        case "No incoming or outgoing links":
            ScholiumL10n.string(
                "No incoming or outgoing links",
                locale: locale
            )
        case "Identity not confirmed":
            ScholiumL10n.string("Identity not confirmed", locale: locale)
        case "Multiple candidates":
            ScholiumL10n.string("Multiple candidates", locale: locale)
        case "Multiple matching Notes":
            ScholiumL10n.string("Multiple matching Notes", locale: locale)
        case "Multiple matching headings":
            ScholiumL10n.string("Multiple matching headings", locale: locale)
        case "Missing Note":
            ScholiumL10n.string("Missing Note", locale: locale)
        case "Missing heading":
            ScholiumL10n.string("Missing heading", locale: locale)
        case "Missing block":
            ScholiumL10n.string("Missing block", locale: locale)
        case "Invalid relationship endpoint":
            ScholiumL10n.string(
                "Invalid relationship endpoint",
                locale: locale
            )
        case "A selected Analysis changed after Synthesize":
            ScholiumL10n.string(
                "A selected Analysis changed after Synthesize",
                locale: locale
            )
        default:
            // Unknown projection copy remains visible rather than being
            // replaced with a misleading generic condition.
            item.message
        }
    }
}

enum AttentionNotificationCopy {
    static func emptyDescription(
        noteScoped: Bool,
        locale: Locale = .current
    ) -> String {
        noteScoped
            ? ScholiumL10n.string(
                "No Action activity or visible derived issue needs attention for this Note.",
                locale: locale
            )
            : ScholiumL10n.string(
                "No Action activity or visible derived issue needs attention in this Scope.",
                locale: locale
            )
    }

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

    /// A Workspace-window change starts a fresh Attention visit. Machine-local
    /// dismissals remain intact, but transient query, kind, Note scope, and row
    /// focus never leak from the previously active window.
    func resetForWorkspaceSwitch() {
        filter = AttentionQueueFilter()
        notificationFilter = .all
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
