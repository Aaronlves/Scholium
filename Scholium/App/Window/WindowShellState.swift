import Combine
import Foundation
import ScholiumContracts
import SwiftUI

/// The Library disclosure namespace for one vault projection.
/// Folder paths are unique only inside this scope.
struct LibraryDisclosureScope: Hashable, Sendable {
    let vaultID: UUID
    let sourceScope: LibrarySourceScope
}

enum WindowColorSchemeChoice: String, CaseIterable {
    case dark, light, system

    static let defaultsKey = "colorScheme"

    var swiftUIColorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

struct WindowToast: Equatable {
    enum Kind: Equatable {
        case success
        case information
        case warning
        case error

        var symbol: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .information: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }

        var colorRole: ScholiumColorRole {
            switch self {
            case .success: .confirmed
            case .information: .information
            case .warning: .attention
            case .error: .destructive
            }
        }
    }

    let message: String
    let kind: Kind
}

/// Presentation state owned by one complete configured window.
///
/// Documents and feature controllers borrow this state instead of copying
/// Library, Inspector, appearance, or transient shell facts into their own
/// lifetimes. It owns no Triptych capability, document buffer, repository,
/// split geometry, or durable research state.
@MainActor
final class WindowShellState: ObservableObject {
    @Published private var expandedFoldersByScope: [LibraryDisclosureScope: Set<String>] = [:]
    @Published private(set) var inspector = ResearchInspectorState()
    @Published private(set) var selectedWorkspace: WorkspaceVaultSlot = .paperAnalysis
    @Published private var inspectorModesByWorkspace: [WorkspaceVaultSlot: ResearchInspectorMode]
    @Published private(set) var libraryVisible = true
    @Published private(set) var hasCompletedInitialRestore = false
    @Published var colorScheme: WindowColorSchemeChoice {
        didSet {
            userDefaults.set(
                colorScheme.rawValue,
                forKey: WindowColorSchemeChoice.defaultsKey
            )
        }
    }
    @Published private(set) var documentTextScale = ScholiumMetrics.Document.defaultTextScale
    @Published private(set) var toastMessage: WindowToast?
    @Published private(set) var researchResultNotice:
        ResearchResultReviewDestination?
    @Published private(set) var researchNotificationPermissionNotice:
        ResearchNotificationPermissionNotice?
    @Published private(set) var refreshStatusText: String?
    @Published private(set) var windowSessionPersistenceError: String?

    private let userDefaults: UserDefaults
    private var didRestoreInspector = false

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        var initialInspectorModes: [WorkspaceVaultSlot: ResearchInspectorMode] = [:]
        for workspace in WorkspaceVaultSlot.allCases {
            initialInspectorModes[workspace] = .overview
        }
        inspectorModesByWorkspace = initialInspectorModes
        colorScheme = userDefaults.string(forKey: WindowColorSchemeChoice.defaultsKey)
            .flatMap(WindowColorSchemeChoice.init(rawValue:))
            ?? .system
    }

    func expandedFolders(in scope: LibraryDisclosureScope?) -> Set<String> {
        guard let scope else { return [] }
        return expandedFoldersByScope[scope] ?? []
    }

    func setExpandedFolders(
        _ folders: Set<String>,
        in scope: LibraryDisclosureScope?
    ) {
        guard let scope else { return }
        if folders.isEmpty {
            expandedFoldersByScope[scope] = nil
        } else {
            expandedFoldersByScope[scope] = folders
        }
    }

    func recordLibraryVisibility(_ isVisible: Bool) {
        guard libraryVisible != isVisible else { return }
        libraryVisible = isVisible
    }

    func restoreLibraryVisibility(_ isVisible: Bool) {
        libraryVisible = isVisible
    }

    func selectInspectorMode(_ mode: ResearchInspectorMode) {
        inspectorModesByWorkspace[selectedWorkspace] = mode
        inspector.mode = mode
    }

    func inspectorMode(for workspace: WorkspaceVaultSlot) -> ResearchInspectorMode {
        inspectorModesByWorkspace[workspace] ?? .overview
    }

    func selectWorkspace(_ workspace: WorkspaceVaultSlot) {
        guard selectedWorkspace != workspace else { return }
        selectedWorkspace = workspace
        inspector.mode = inspectorMode(for: workspace)
    }

    func resetWorkspaceSessions() {
        selectedWorkspace = .paperAnalysis
        var resetInspectorModes: [WorkspaceVaultSlot: ResearchInspectorMode] = [:]
        for workspace in WorkspaceVaultSlot.allCases {
            resetInspectorModes[workspace] = .overview
        }
        inspectorModesByWorkspace = resetInspectorModes
        inspector.mode = .overview
    }

    func showResearchInspector(_ isVisible: Bool) {
        inspector.isVisible = isVisible
    }

    func restoreInspector(
        modesByWorkspace: [WorkspaceVaultSlot: String],
        isVisible: Bool?
    ) {
        guard !didRestoreInspector else { return }
        didRestoreInspector = true
        var restoredInspectorModes: [WorkspaceVaultSlot: ResearchInspectorMode] = [:]
        for workspace in WorkspaceVaultSlot.allCases {
            restoredInspectorModes[workspace] =
                ResearchInspectorMode(restoring: modesByWorkspace[workspace])
        }
        inspectorModesByWorkspace = restoredInspectorModes
        inspector.mode = inspectorMode(for: selectedWorkspace)
        inspector.isVisible = isVisible ?? false
    }

    func completeInitialRestore() {
        hasCompletedInitialRestore = true
    }

    func setDocumentTextScale(_ requestedScale: Double) {
        let adjusted = min(
            ScholiumMetrics.Document.maximumTextScale,
            max(ScholiumMetrics.Document.minimumTextScale, requestedScale)
        )
        documentTextScale = (adjusted * 10).rounded() / 10
    }

    func resetDocumentTextScale() {
        documentTextScale = ScholiumMetrics.Document.defaultTextScale
    }

    func showToast(_ message: String, kind: WindowToast.Kind) {
        let toast = WindowToast(message: message, kind: kind)
        toastMessage = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.toastMessage == toast {
                self?.toastMessage = nil
            }
        }
    }

    func presentResearchResultNotice(
        _ destination: ResearchResultReviewDestination
    ) {
        researchResultNotice = destination
    }

    func dismissResearchResultNotice(
        matching destination: ResearchResultReviewDestination? = nil
    ) {
        if let destination, researchResultNotice != destination { return }
        researchResultNotice = nil
    }

    func presentResearchNotificationPermissionNotice(
        _ notice: ResearchNotificationPermissionNotice
    ) {
        researchNotificationPermissionNotice = notice
    }

    func dismissResearchNotificationPermissionNotice() {
        researchNotificationPermissionNotice = nil
    }

    func setRefreshStatus(_ status: String?) {
        refreshStatusText = status
    }

    func recordWindowSessionPersistenceFailure(_ message: String) {
        windowSessionPersistenceError = message
        refreshStatusText = "Window state not saved"
    }

    func clearWindowSessionPersistenceFailure() {
        if windowSessionPersistenceError != nil {
            windowSessionPersistenceError = nil
        }
        if refreshStatusText == "Window state not saved" {
            refreshStatusText = nil
        }
    }
}
