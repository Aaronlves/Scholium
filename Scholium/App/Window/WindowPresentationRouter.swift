import ScholiumContracts
import SwiftUI

enum WindowSheetRoute: Identifiable {
    case frontmatter(FrontmatterPanelRoute)
    case researchAction(ResearchActionPanelRoute)
    case agentNoteChange(UUID)
    case createCheckpoint
    case restoreCheckpoint
    case lifecycle(NoteLifecycleRequest)
    case folderLifecycle(FolderLifecycleRequest)
    case transactionRecovery
    case identityResolution(NoteIdentityAmbiguity)

    var id: String {
        switch self {
        case .frontmatter(let route): route.id
        case .researchAction(let route):
            "research-action:\(route.presentationID.uuidString.lowercased())"
        case .agentNoteChange(let requestID):
            "agent-note-change:\(requestID.uuidString.lowercased())"
        case .createCheckpoint: "create-checkpoint"
        case .restoreCheckpoint: "restore-checkpoint"
        case .lifecycle(let request): "lifecycle:\(request.id)"
        case .folderLifecycle(let request): "folder-lifecycle:\(request.id)"
        case .transactionRecovery: "transaction-recovery"
        case .identityResolution(let ambiguity): "identity-resolution:\(ambiguity.id)"
        }
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

    func presentFrontmatter(path: String) {
        present(.frontmatter(FrontmatterPanelRoute(path: path)))
    }

    func finishFrontmatter(_ route: FrontmatterPanelRoute) {
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
