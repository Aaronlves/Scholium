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

struct WindowFeedback: Equatable, Identifiable {
    let id: UUID
    let message: String
    let kind: ScholiumFeedbackKind

    init(
        id: UUID = UUID(),
        message: String,
        kind: ScholiumFeedbackKind
    ) {
        self.id = id
        self.message = message
        self.kind = kind
    }
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
    @Published private(set) var feedbackItems: [WindowFeedback] = []
    @Published private(set) var actionNotificationStackExpansionGeneration:
        UInt64 = 0
    @Published private(set) var researchActivityNotifications:
        [ResearchActivityNotification] = []
    #if DEBUG
    private var qaResearchActivityNotifications:
        [ResearchActivityNotification] = []
    #endif
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
        feedbackItems.removeAll()
        actionNotificationStackExpansionGeneration = 0
        #if DEBUG
        qaResearchActivityNotifications.removeAll()
        #endif
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

    func presentFeedback(_ message: String, kind: ScholiumFeedbackKind) {
        feedbackItems.removeAll {
            $0.message == message && $0.kind == kind
        }
        feedbackItems.append(
            WindowFeedback(message: message, kind: kind)
        )
    }

    func dismissFeedback(id: WindowFeedback.ID) {
        feedbackItems.removeAll { $0.id == id }
    }

    var transientFeedbackItems: [WindowFeedback] {
        feedbackItems.filter { $0.kind.dismissesAutomatically }
    }

    var persistentFeedbackItems: [WindowFeedback] {
        feedbackItems.filter { !$0.kind.dismissesAutomatically }
    }

    func requestActionNotificationStackExpansion() {
        actionNotificationStackExpansionGeneration &+= 1
    }

    func receiveResearchActivityNotifications(
        _ notifications: [ResearchActivityNotification]
    ) {
        #if DEBUG
        let qaRunIDs = Set(qaResearchActivityNotifications.map(\.runID))
        researchActivityNotifications = qaResearchActivityNotifications
            + notifications.filter { !qaRunIDs.contains($0.runID) }
        #else
        researchActivityNotifications = notifications
        #endif
    }

    #if DEBUG
    func presentQAResearchActivityNotifications(
        _ notifications: [ResearchActivityNotification]
    ) {
        let previousQARunIDs = Set(qaResearchActivityNotifications.map(\.runID))
        let production = researchActivityNotifications.filter {
            !previousQARunIDs.contains($0.runID)
        }
        qaResearchActivityNotifications = notifications
        receiveResearchActivityNotifications(production)
    }

    @discardableResult
    func dismissQAResearchActivityNotification(runID: UUID) -> Bool {
        guard qaResearchActivityNotifications.contains(where: {
            $0.runID == runID
        }) else { return false }
        qaResearchActivityNotifications.removeAll { $0.runID == runID }
        researchActivityNotifications.removeAll { $0.runID == runID }
        return true
    }
    #endif

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
