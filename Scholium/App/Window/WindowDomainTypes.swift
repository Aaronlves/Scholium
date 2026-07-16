import ScholiumContracts
import Foundation

/// The library location currently projected by one window.
///
/// This is presentation and navigation state. The corresponding lifecycle
/// operations remain fingerprint-gated application operations.
enum NoteLocationScope: String, CaseIterable, Identifiable, Sendable {
    case workspace = "Workspace"
    case unclassified = "Unclassified"
    case setAside = "Set Aside"
    case trash = "Trash"

    var id: String { rawValue }

    var prefix: String? {
        switch self {
        case .workspace, .unclassified: nil
        case .setAside: "Set Aside/"
        case .trash: "Trash/"
        }
    }
}

/// A lifecycle listing projection. `revision` is the authority used by the
/// eventual application operation; the location retains the immutable shared
/// snapshot rather than copying its writable source or derived state.
struct LifecycleLocationItem: Identifiable, Hashable {
    let note: WindowDocumentLocation
    let revision: DocumentFingerprint
    let noteID: UUID

    var id: String { note.relativePath }
}

enum NoteLifecycleRequest: Identifiable, Equatable, Sendable {
    case create
    case duplicate(String)
    case move(String)
    case putBack(String)
    case classify(String)

    var id: String {
        switch self {
        case .create: "create"
        case .duplicate(let path): "duplicate:\(path)"
        case .move(let path): "move:\(path)"
        case .putBack(let path): "put-back:\(path)"
        case .classify(let path): "classify:\(path)"
        }
    }
}

enum NoteSortOrder: String, CaseIterable, Identifiable, Sendable {
    case modifiedNewest
    case modifiedOldest
    case titleAscending
    case titleDescending
    case debateImportanceDescending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .modifiedNewest: "Recently Modified"
        case .modifiedOldest: "Least Recently Modified"
        case .titleAscending: "Title, A to Z"
        case .titleDescending: "Title, Z to A"
        case .debateImportanceDescending: "Debate Importance, High to Low"
        }
    }

    var symbol: String {
        switch self {
        case .modifiedNewest: "clock.arrow.circlepath"
        case .modifiedOldest: "clock"
        case .titleAscending: "textformat.abc"
        case .titleDescending: "textformat.abc.dottedunderline"
        case .debateImportanceDescending: "arrow.down.circle"
        }
    }
}

/// A resolved document destination emitted by a feature controller and routed
/// by the owning `WindowModel`. It carries no repository or presentation
/// service and therefore remains safe to pass across feature boundaries.
struct WindowDocumentRoute: Hashable, Sendable {
    let reference: VaultNoteReference
    let sourceLocator: SourceLocator?
    let opensInNewTab: Bool

    init(
        reference: VaultNoteReference,
        sourceLocator: SourceLocator? = nil,
        opensInNewTab: Bool = false
    ) {
        self.reference = reference
        self.sourceLocator = sourceLocator
        self.opensInNewTab = opensInNewTab
    }
}

struct ResearchFunctionPanelRoute: Hashable, Sendable {
    let target: VaultNoteReference
    let function: ResearchFunctionID
    let presentationID: UUID
}

/// The complete set of cross-feature requests understood by one window.
/// Commands and application operations remain direct calls; this is not a
/// general event bus.
enum WindowIntent: Equatable, Sendable {
    case openDocument(WindowDocumentRoute)
    case revealSourceLocator(vaultID: UUID, locator: SourceLocator)
    case switchVault(UUID)
    case presentResearchFunction(ResearchFunctionPanelRoute)
    case presentLifecycle(NoteLifecycleRequest)
}

enum SearchResultIdentity {
    static func lexical(_ hit: SearchHit) -> String {
        "\(hit.vaultID.uuidString.lowercased()):\(hit.relativePath)"
    }

    static func related(_ item: RelatedSearchItem) -> String {
        "related:\(item.id)"
    }
}

/// A typed selection used by Search presentation instead of routing through
/// `WindowModel` static helpers.
enum SearchResultSelection: Hashable, Sendable {
    case lexical(SearchHit)
    case related(RelatedSearchItem)

    var id: String {
        switch self {
        case .lexical(let hit): SearchResultIdentity.lexical(hit)
        case .related(let item): SearchResultIdentity.related(item)
        }
    }

    var documentRoute: WindowDocumentRoute {
        switch self {
        case .lexical(let hit):
            WindowDocumentRoute(
                reference: VaultNoteReference(
                    vaultID: hit.vaultID,
                    vaultName: hit.vaultName,
                    vaultRole: hit.vaultRole,
                    relativePath: hit.relativePath,
                    stableNoteID: hit.stableNoteID
                ),
                sourceLocator: SourceLocator(
                    file: hit.relativePath,
                    line: hit.sourceLine,
                    column: 1
                )
            )
        case .related(let item):
            WindowDocumentRoute(
                reference: item.note.reference,
                sourceLocator: item.sourceLine.map {
                    SourceLocator(
                        file: item.note.reference.relativePath,
                        line: $0,
                        column: 1
                    )
                }
            )
        }
    }
}
