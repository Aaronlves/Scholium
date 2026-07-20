import Combine
import Foundation

/// The Library disclosure namespace for one vault and lifecycle projection.
/// Folder paths are unique only inside this scope.
struct LibraryDisclosureScope: Hashable, Sendable {
    let vaultID: UUID
    let locationScope: NoteLocationScope
}

/// Outer workspace presentation owned by one complete window. Document tabs
/// deliberately borrow this state instead of copying Sidebar, Inspector, or
/// folder-disclosure state into each document page.
@MainActor
final class WindowPeripheralPresentationState: ObservableObject {
    @Published private var expandedFoldersByScope: [LibraryDisclosureScope: Set<String>] = [:]
    @Published private(set) var inspector = ResearchInspectorState()
    private var didRestoreInspector = false

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

    func selectInspectorMode(_ mode: ResearchInspectorMode) {
        inspector.mode = mode
    }

    func showResearchInspector(_ isVisible: Bool) {
        inspector.isVisible = isVisible
    }

    func restoreInspector(storedMode: String?, isVisible: Bool?) {
        guard !didRestoreInspector else { return }
        didRestoreInspector = true
        inspector.mode = ResearchInspectorMode(restoring: storedMode)
        inspector.isVisible = isVisible ?? false
    }
}
