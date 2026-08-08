import Combine
import Foundation
import ScholiumContracts

/// One document page inside a workspace window's central Document region.
/// The tab identity is presentation identity; the document keeps its own
/// stable identity and retained editor session in `DocumentController`.
struct DocumentTabItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var document: WindowSelectedDocument
    var title: String
    var toolTip: String

    init(
        id: UUID = UUID(),
        document: WindowSelectedDocument,
        title: String,
        toolTip: String
    ) {
        self.id = id
        self.document = document
        self.title = title
        self.toolTip = toolTip
    }
}

struct DocumentTabClosePlan: Equatable, Sendable {
    let workspace: WorkspaceVaultSlot
    let closingTabID: UUID
    let selectedTabIDAfterClose: UUID?
    let documentToActivate: WindowSelectedDocument?
}

enum DocumentTabPlacement: Equatable, Sendable {
    case replaceSelected
    case newTab
}

enum DocumentTabActivationResult: Equatable, Sendable {
    case created(UUID)
    case replaced(UUID)
    case selectedExisting(UUID)
}

private enum DocumentTabKey: Hashable, Sendable {
    case workspace(DocumentSessionKey)
    case unavailable(vaultID: UUID, relativePath: String)

    init(_ document: WindowSelectedDocument) {
        switch document {
        case .workspace(let descriptor):
            self = .workspace(descriptor.sessionKey)
        case .unavailable(let vaultID, let relativePath):
            self = .unavailable(vaultID: vaultID, relativePath: relativePath)
        }
    }
}

/// Window-local owner of document-tab order, selection, and document
/// references. It deliberately owns no editor, Library, Inspector, split-view,
/// toolbar, repository, or persistence state.
@MainActor
final class DocumentTabController: ObservableObject {
    @Published private var tabsByWorkspace: [WorkspaceVaultSlot: [DocumentTabItem]] = [:]
    @Published private var selectedTabIDsByWorkspace: [WorkspaceVaultSlot: UUID] = [:]

    var allTabs: [DocumentTabItem] {
        WorkspaceVaultSlot.allCases.flatMap { tabs(in: $0) }
    }

    func tabs(in workspace: WorkspaceVaultSlot) -> [DocumentTabItem] {
        tabsByWorkspace[workspace] ?? []
    }

    func selectedTabID(in workspace: WorkspaceVaultSlot) -> UUID? {
        selectedTabIDsByWorkspace[workspace]
    }

    func selectedTab(in workspace: WorkspaceVaultSlot) -> DocumentTabItem? {
        guard let selectedTabID = selectedTabID(in: workspace) else { return nil }
        return tabs(in: workspace).first { $0.id == selectedTabID }
    }

    @discardableResult
    func activate(
        document: WindowSelectedDocument,
        title: String,
        toolTip: String,
        placement: DocumentTabPlacement,
        in workspace: WorkspaceVaultSlot
    ) -> DocumentTabActivationResult {
        let key = DocumentTabKey(document)
        for candidate in WorkspaceVaultSlot.allCases {
            var candidateTabs = tabs(in: candidate)
            guard let existingIndex = candidateTabs.firstIndex(where: {
                DocumentTabKey($0.document) == key
            }) else { continue }
            candidateTabs[existingIndex].document = document
            candidateTabs[existingIndex].title = title
            candidateTabs[existingIndex].toolTip = toolTip
            tabsByWorkspace[candidate] = candidateTabs
            selectedTabIDsByWorkspace[candidate] = candidateTabs[existingIndex].id
            return .selectedExisting(candidateTabs[existingIndex].id)
        }

        var workspaceTabs = tabs(in: workspace)
        if placement == .replaceSelected,
           let selectedTabID = selectedTabID(in: workspace),
           let selectedIndex = workspaceTabs.firstIndex(where: { $0.id == selectedTabID }) {
            workspaceTabs[selectedIndex].document = document
            workspaceTabs[selectedIndex].title = title
            workspaceTabs[selectedIndex].toolTip = toolTip
            tabsByWorkspace[workspace] = workspaceTabs
            return .replaced(selectedTabID)
        }

        let tab = DocumentTabItem(
            document: document,
            title: title,
            toolTip: toolTip
        )
        workspaceTabs.append(tab)
        tabsByWorkspace[workspace] = workspaceTabs
        selectedTabIDsByWorkspace[workspace] = tab.id
        return .created(tab.id)
    }

    func selectTab(withID id: UUID) {
        guard let workspace = workspace(containingTabWithID: id) else { return }
        selectedTabIDsByWorkspace[workspace] = id
    }

    func closePlan(forTabWithID id: UUID) -> DocumentTabClosePlan? {
        guard let workspace = workspace(containingTabWithID: id) else {
            return nil
        }
        let workspaceTabs = tabs(in: workspace)
        guard let closingIndex = workspaceTabs.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let selectedTabID = selectedTabID(in: workspace)
        guard selectedTabID == id else {
            return DocumentTabClosePlan(
                workspace: workspace,
                closingTabID: id,
                selectedTabIDAfterClose: selectedTabID,
                documentToActivate: nil
            )
        }

        let neighbor: DocumentTabItem?
        if workspaceTabs.indices.contains(closingIndex + 1) {
            neighbor = workspaceTabs[closingIndex + 1]
        } else if closingIndex > workspaceTabs.startIndex {
            neighbor = workspaceTabs[closingIndex - 1]
        } else {
            neighbor = nil
        }
        return DocumentTabClosePlan(
            workspace: workspace,
            closingTabID: id,
            selectedTabIDAfterClose: neighbor?.id,
            documentToActivate: neighbor?.document
        )
    }

    func apply(_ plan: DocumentTabClosePlan) {
        var workspaceTabs = tabs(in: plan.workspace)
        guard workspaceTabs.contains(where: { $0.id == plan.closingTabID }) else { return }
        workspaceTabs.removeAll { $0.id == plan.closingTabID }
        tabsByWorkspace[plan.workspace] = workspaceTabs
        if let selectedTabIDAfterClose = plan.selectedTabIDAfterClose,
           workspaceTabs.contains(where: { $0.id == selectedTabIDAfterClose }) {
            selectedTabIDsByWorkspace[plan.workspace] = selectedTabIDAfterClose
        } else {
            selectedTabIDsByWorkspace[plan.workspace] = nil
        }
    }

    /// Removes a proven-missing batch without inventing a replacement
    /// selection. WindowModel first attempts the ordinary close plan so a
    /// surviving adjacent tab can be activated; this is the safe fallback if
    /// that projection can no longer be activated.
    func removeTabs(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for workspace in WorkspaceVaultSlot.allCases {
            var workspaceTabs = tabs(in: workspace)
            workspaceTabs.removeAll { ids.contains($0.id) }
            tabsByWorkspace[workspace] = workspaceTabs
            if selectedTabID(in: workspace).map(ids.contains) == true {
                selectedTabIDsByWorkspace[workspace] = nil
            }
        }
    }

    func updateDocumentProjection(
        _ document: WindowSelectedDocument,
        title: String,
        toolTip: String
    ) {
        let key = DocumentTabKey(document)
        for workspace in WorkspaceVaultSlot.allCases {
            var workspaceTabs = tabs(in: workspace)
            for index in workspaceTabs.indices
            where DocumentTabKey(workspaceTabs[index].document) == key {
                workspaceTabs[index].document = document
                workspaceTabs[index].title = title
                workspaceTabs[index].toolTip = toolTip
            }
            tabsByWorkspace[workspace] = workspaceTabs
        }
    }

    func restoreTabs(
        _ tabs: [DocumentTabItem],
        selectedTabID: UUID?,
        in workspace: WorkspaceVaultSlot
    ) {
        tabsByWorkspace[workspace] = tabs
        if let selectedTabID, tabs.contains(where: { $0.id == selectedTabID }) {
            selectedTabIDsByWorkspace[workspace] = selectedTabID
        } else {
            selectedTabIDsByWorkspace[workspace] = nil
        }
    }

    func removeAll() {
        tabsByWorkspace = [:]
        selectedTabIDsByWorkspace = [:]
    }

    private func workspace(containingTabWithID id: UUID) -> WorkspaceVaultSlot? {
        WorkspaceVaultSlot.allCases.first { workspace in
            tabs(in: workspace).contains { $0.id == id }
        }
    }

}
