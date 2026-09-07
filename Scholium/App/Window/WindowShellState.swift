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

enum WindowOperationIssueKind: Equatable, Sendable {
    case information, warning, error
}

struct WindowOperationIssue: Equatable, Identifiable {
    let id: UUID
    let message: String
    let kind: WindowOperationIssueKind
    let detail: String?
    let offersRefresh: Bool

    init(
        id: UUID = UUID(),
        message: String,
        kind: WindowOperationIssueKind,
        detail: String? = nil,
        offersRefresh: Bool = false
    ) {
        self.id = id
        self.message = message
        self.kind = kind
        self.detail = detail
        self.offersRefresh = offersRefresh
    }
}

enum SidebarContent: Int, CaseIterable {
    case triptych, outline
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
    @Published private(set) var sidebarContent: SidebarContent = .triptych
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
    @Published private(set) var operationIssues: [WindowOperationIssue] = []
    @Published private(set) var refreshStatusText: String?
    @Published private(set) var windowSessionPersistenceError: String?

    private let userDefaults: UserDefaults
    private var didRestoreInspector = false

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        var initialInspectorModes: [WorkspaceVaultSlot: ResearchInspectorMode] = [:]
        for workspace in WorkspaceVaultSlot.allCases {
            initialInspectorModes[workspace] = .about
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

    /// Returns the visibility requested from the native split owner.
    func activateSidebar(_ content: SidebarContent) -> Bool {
        let shouldShow = !libraryVisible || sidebarContent != content
        sidebarContent = content
        return shouldShow
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
        inspectorModesByWorkspace[workspace] ?? .about
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
            resetInspectorModes[workspace] = .about
        }
        inspectorModesByWorkspace = resetInspectorModes
        inspector.mode = .about
        operationIssues.removeAll()
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

    @discardableResult
    func reportOperationIssue(_ message: String, kind: WindowOperationIssueKind,
                              detail: String? = nil, offersRefresh: Bool = false) -> UUID {
        if let existing = operationIssues.first(where: {
            $0.message == message && $0.kind == kind && $0.detail == detail
                && $0.offersRefresh == offersRefresh
        }) { return existing.id }
        let issue = WindowOperationIssue(
            message: message, kind: kind, detail: detail, offersRefresh: offersRefresh
        )
        operationIssues.append(issue)
        return issue.id
    }

    func dismissOperationIssue(id: UUID) {
        operationIssues.removeAll { $0.id == id }
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
