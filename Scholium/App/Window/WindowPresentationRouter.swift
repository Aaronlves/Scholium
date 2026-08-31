import ScholiumContracts
import ScholiumResearchRecordsFeature
import SwiftUI

enum WindowSheetRoute: Identifiable {
    case metadata(MetadataPanelRoute)
    case researchAction(ResearchActionPanelRoute)
    case noteFileOperation(NoteFileRequest)
    case folderFileOperation(FolderFileRequest)
    case systemTrash(SystemTrashDeletionPreview)
    case transactionRecovery
    case identityResolution(NoteIdentityAmbiguity)
    case zoteroBinding(ZoteroBindingPanelRoute)
    case agentChanges(AgentChangesPresentation)

    var id: String {
        switch self {
        case .metadata(let route): route.id
        case .researchAction(let route):
            "research-action:\(route.presentationID.uuidString.lowercased())"
        case .noteFileOperation(let request): "note-file-operation:\(request.id)"
        case .folderFileOperation(let request): "folder-file-operation:\(request.id)"
        case .systemTrash(let preview):
            "system-trash:\(preview.id.uuidString.lowercased())"
        case .transactionRecovery: "transaction-recovery"
        case .identityResolution(let ambiguity): "identity-resolution:\(ambiguity.id)"
        case .zoteroBinding(let route): route.id
        case .agentChanges(let presentation):
            "agent-changes:\(presentation.id.uuidString.lowercased())"
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
    case localExecutionRecovery(LocalResearchExecutionRecoveryPreview)

    var id: String {
        switch self {
        case .actionFailure: "action-failure"
        case .localExecutionRecovery(let preview):
            "local-execution-recovery:\(preview.id.uuidString.lowercased())"
        }
    }

    var message: String {
        switch self {
        case .actionFailure(let message): message
        case .localExecutionRecovery(let preview):
            "System Trash requires recovery for unreadable local Research Action storage (file count: \(preview.items.count))."
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
    @Published var researchRecordsWindowRequest: ResearchRecordsWindowRequest?

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
        researchRecordsWindowRequest = nil
    }
}
