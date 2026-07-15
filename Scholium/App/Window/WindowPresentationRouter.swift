import ScholiumContracts
import SwiftUI

enum WindowSheetRoute: Identifiable {
    case quickOpen
    case adaptiveContext
    case workspaceSetup
    case frontmatter(path: String)
    case scholia(path: String)
    case attention
    case qualityReview(path: String)
    case researcherComments(path: String)
    case createCheckpoint
    case restoreCheckpoint
    case lifecycle(NoteLifecycleRequest)
    case transactionRecovery
    case critique(path: String)
    case identityResolution(NoteIdentityAmbiguity)

    var id: String {
        switch self {
        case .quickOpen: "quick-open"
        case .adaptiveContext: "adaptive-context"
        case .workspaceSetup: "workspace-setup"
        case .frontmatter(let path): "frontmatter:\(path)"
        case .scholia(let path): "scholia:\(path)"
        case .attention: "attention"
        case .qualityReview(let path): "quality-review:\(path)"
        case .researcherComments(let path): "researcher-comments:\(path)"
        case .createCheckpoint: "create-checkpoint"
        case .restoreCheckpoint: "restore-checkpoint"
        case .lifecycle(let request): "lifecycle:\(request.id)"
        case .transactionRecovery: "transaction-recovery"
        case .critique(let path): "critique:\(path)"
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

    func setWorkspaceSetupPresented(
        _ isPresented: Bool,
        rootSetupOwnsPresentation: Bool
    ) {
        guard isPresented else {
            dismissSheet(if: "workspace-setup")
            return
        }
        guard !rootSetupOwnsPresentation else {
            dismissSheet(if: "workspace-setup")
            return
        }
        present(.workspaceSetup)
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
