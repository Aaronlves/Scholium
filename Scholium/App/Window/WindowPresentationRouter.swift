import ScholiumContracts
import SwiftUI

enum WindowSheetRoute: Identifiable {
    case metadata(MetadataPanelRoute)
    case noteFileOperation(NoteFileRequest)
    case folderFileOperation(FolderFileRequest)
    case systemTrash(SystemTrashDeletionPreview)
    case transactionRecovery
    case identityResolution(NoteIdentityAmbiguity)
    case zoteroBinding(ZoteroBindingPanelRoute)
    case agentChanges

    var id: String {
        switch self {
        case .metadata(let route): route.id
        case .noteFileOperation(let request): "note-file-operation:\(request.id)"
        case .folderFileOperation(let request): "folder-file-operation:\(request.id)"
        case .systemTrash(let preview):
            "system-trash:\(preview.id.uuidString.lowercased())"
        case .transactionRecovery: "transaction-recovery"
        case .identityResolution(let ambiguity): "identity-resolution:\(ambiguity.id)"
        case .zoteroBinding(let route): route.id
        case .agentChanges: "agent-changes"
        }
    }
}

enum ZoteroBindingPanelMode: String, Hashable {
    case manage
    case refresh
}

struct ZoteroBindingPanelRoute: Identifiable, Hashable {
    let noteID: UUID
    let currentBinding: AnalysisZoteroBinding?
    let mode: ZoteroBindingPanelMode

    init(
        noteID: UUID,
        currentBinding: AnalysisZoteroBinding?,
        mode: ZoteroBindingPanelMode = .manage
    ) {
        self.noteID = noteID
        self.currentBinding = currentBinding
        self.mode = mode
    }

    var id: String {
        "zotero-binding:\(mode.rawValue):\(noteID.uuidString.lowercased())"
    }
}

struct WindowOverlayRoute: OptionSet, Sendable {
    let rawValue: UInt8

    static let loading = Self(rawValue: 1 << 0)
    static let search = Self(rawValue: 1 << 1)
}

enum WindowAlertRoute: Identifiable, Equatable {
    case actionFailure(message: String)

    var id: String {
        switch self {
        case .actionFailure: "action-failure"
        }
    }

    var message: String {
        switch self {
        case .actionFailure(let message): message
        }
    }
}

enum WindowFileImportRequest: String, Identifiable, Sendable {
    case markdown

    var id: String { rawValue }
}

@MainActor
final class WindowPresentationRouter: ObservableObject {
    @Published var sheet: WindowSheetRoute?
    @Published private(set) var overlays: WindowOverlayRoute = []
    @Published var alert: WindowAlertRoute?
    @Published var fileImport: WindowFileImportRequest?

    func present(_ route: WindowSheetRoute) {
        sheet = route
    }

    func dismissSheet() {
        sheet = nil
    }

    func dismissSheet(if routeID: String) {
        guard sheet?.id == routeID else { return }
        sheet = nil
    }

    func presentMetadata(path: String) {
        present(.metadata(MetadataPanelRoute(path: path)))
    }

    func finishMetadata(_ route: MetadataPanelRoute) {
        guard sheet?.id == route.id else { return }
        dismissSheet()
    }

    func setOverlay(_ route: WindowOverlayRoute, isPresented: Bool) {
        if isPresented {
            overlays.insert(route)
        } else {
            overlays.remove(route)
        }
    }

    func presentsOverlay(_ route: WindowOverlayRoute) -> Bool {
        overlays.contains(route)
    }

    func dismissAll() {
        sheet = nil
        overlays = []
        alert = nil
        fileImport = nil
    }
}
