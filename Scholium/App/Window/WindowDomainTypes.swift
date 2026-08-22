import ScholiumContracts
import Foundation

/// The one Library projection owned by a window. The type keeps asynchronous
/// projection requests scoped without introducing alternate source locations.
enum LibrarySourceScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case library = "Library"

    var id: String { rawValue }

}

enum WorkspaceAccessKind: String, Hashable, Sendable {
    case vault
    case portableControl
    case unsupportedPortableControl
}

/// One narrowly scoped authorization repair for an already configured
/// Triptych. This is window presentation state, not a second setup workflow.
struct WorkspaceAccessRecovery: Identifiable, Hashable, Sendable {
    let kind: WorkspaceAccessKind
    let expectedPath: String
    let reason: String?

    init(kind: WorkspaceAccessKind, expectedPath: String, reason: String? = nil) {
        self.kind = kind
        self.expectedPath = expectedPath
        self.reason = reason
    }

    var id: String { "\(kind.rawValue):\(expectedPath):\(reason ?? "")" }
}

extension NoteMutationTarget {
    init?(_ location: WindowDocumentLocation) {
        guard let snapshot = location.workspaceSnapshot,
              let stableNoteID = snapshot.stableIdentity.resolvedID else {
            return nil
        }
        self.init(
            documentID: snapshot.id,
            stableNoteID: stableNoteID,
            revision: snapshot.fingerprint
        )
    }
}

enum NoteFileRequest: Identifiable, Equatable, Sendable {
    case duplicate(NoteMutationTarget)
    case rename(NoteMutationTarget)
    case move(NoteMutationTarget)

    var id: String {
        switch self {
        case .duplicate(let target): "duplicate:\(target.id)"
        case .rename(let target): "rename:\(target.id)"
        case .move(let target): "move:\(target.id)"
        }
    }
}

/// A folder is addressed only by its current vault-relative path. Unlike a
/// Note mutation target, it deliberately carries no stable identifier.
struct FolderMutationTarget: Identifiable, Equatable, Sendable {
    let vaultID: UUID
    let relativePath: String

    var id: String {
        "\(vaultID.uuidString.lowercased()):\(relativePath)"
    }

    var name: String {
        relativePath.split(separator: "/").last.map(String.init) ?? relativePath
    }
}

enum FolderFileRequest: Identifiable, Equatable, Sendable {
    case rename(FolderMutationTarget)
    case move(FolderMutationTarget)

    var target: FolderMutationTarget {
        switch self {
        case .rename(let target), .move(let target): target
        }
    }

    var id: String {
        switch self {
        case .rename(let target): "rename-folder:\(target.id)"
        case .move(let target): "move-folder:\(target.id)"
        }
    }
}

enum NoteSortOrder: String, CaseIterable, Identifiable, Sendable {
    case modifiedNewest
    case modifiedOldest
    case titleAscending
    case titleDescending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .modifiedNewest: ScholiumL10n.dynamicString("Recently Modified")
        case .modifiedOldest: ScholiumL10n.dynamicString("Least Recently Modified")
        case .titleAscending: ScholiumL10n.dynamicString("Title, A to Z")
        case .titleDescending: ScholiumL10n.dynamicString("Title, Z to A")
        }
    }

    var symbol: String {
        switch self {
        case .modifiedNewest: "clock.arrow.circlepath"
        case .modifiedOldest: "clock"
        case .titleAscending: "textformat.abc"
        case .titleDescending: "textformat.abc.dottedunderline"
        }
    }
}

/// How a document destination should enter the workspace.
///
/// Replacing the current document never creates hidden navigation state inside
/// a session. A new tab is another document page inside the current window's
/// central Document region; it does not create or reload a workspace window.
enum WindowOpenDisposition: String, Codable, Hashable, Sendable {
    case replaceCurrent
    case newTab
}

/// A resolved document destination emitted by a feature controller and routed
/// by the owning `WindowModel`. It carries no repository or presentation
/// service and therefore remains safe to pass across feature boundaries.
struct WindowDocumentRoute: Hashable, Sendable {
    let reference: VaultNoteReference
    let sourceLocator: SourceLocator?
    let disposition: WindowOpenDisposition

    init(
        reference: VaultNoteReference,
        sourceLocator: SourceLocator? = nil,
        disposition: WindowOpenDisposition = .replaceCurrent
    ) {
        self.reference = reference
        self.sourceLocator = sourceLocator
        self.disposition = disposition
    }
}

struct ResearchActionPanelRoute: Hashable, Sendable {
    let target: VaultNoteReference
    let actionID: ResearchActionID
    let presentationID: UUID

    init(
        target: VaultNoteReference,
        actionID: ResearchActionID,
        presentationID: UUID
    ) {
        self.target = target
        self.actionID = actionID
        self.presentationID = presentationID
    }
}

/// Typed Scholium Metadata presentation.
struct MetadataPanelRoute: Hashable, Sendable {
    let presentationID: UUID
    let path: String

    var id: String {
        "metadata:\(presentationID.uuidString.lowercased())"
    }

    init(
        presentationID: UUID = UUID(),
        path: String
    ) {
        self.presentationID = presentationID
        self.path = path
    }
}

/// The complete set of cross-feature requests understood by one window.
/// Commands and application operations remain direct calls; this is not a
/// general event bus.
enum WindowIntent: Equatable, Sendable {
    case openDocument(WindowDocumentRoute)
    case openSearchResult(SearchResultSelection, disposition: WindowOpenDisposition)
    case revealSourceLocator(vaultID: UUID, locator: SourceLocator)
    case switchVault(UUID)
    case presentResearchAction(ResearchActionPanelRoute)
    case presentNoteFileOperation(NoteFileRequest)
}

enum SearchResultIdentity {
    static func result(_ result: SearchResult) -> String {
        result.id
    }
}

/// A typed selection used by Search presentation instead of routing through
/// `WindowModel` static helpers.
enum SearchResultSelection: Hashable, Sendable {
    case result(SearchResult)

    var id: String {
        switch self {
        case .result(let result): SearchResultIdentity.result(result)
        }
    }
}
