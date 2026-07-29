import Combine
import Foundation

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
    @Published private(set) var tabs: [DocumentTabItem] = []
    @Published private(set) var selectedTabID: UUID?

    var selectedTab: DocumentTabItem? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    @discardableResult
    func activate(
        document: WindowSelectedDocument,
        title: String,
        toolTip: String,
        placement: DocumentTabPlacement
    ) -> DocumentTabActivationResult {
        let key = DocumentTabKey(document)
        if let existingIndex = tabs.firstIndex(where: {
            DocumentTabKey($0.document) == key
        }) {
            tabs[existingIndex].document = document
            tabs[existingIndex].title = title
            tabs[existingIndex].toolTip = toolTip
            selectedTabID = tabs[existingIndex].id
            return .selectedExisting(tabs[existingIndex].id)
        }

        if placement == .replaceSelected,
           let selectedTabID,
           let selectedIndex = tabs.firstIndex(where: { $0.id == selectedTabID }) {
            tabs[selectedIndex].document = document
            tabs[selectedIndex].title = title
            tabs[selectedIndex].toolTip = toolTip
            return .replaced(selectedTabID)
        }

        let tab = DocumentTabItem(
            document: document,
            title: title,
            toolTip: toolTip
        )
        tabs.append(tab)
        selectedTabID = tab.id
        return .created(tab.id)
    }

    func selectTab(withID id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    func closePlan(forTabWithID id: UUID) -> DocumentTabClosePlan? {
        guard let closingIndex = tabs.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        guard selectedTabID == id else {
            return DocumentTabClosePlan(
                closingTabID: id,
                selectedTabIDAfterClose: selectedTabID,
                documentToActivate: nil
            )
        }

        let neighbor: DocumentTabItem?
        if tabs.indices.contains(closingIndex + 1) {
            neighbor = tabs[closingIndex + 1]
        } else if closingIndex > tabs.startIndex {
            neighbor = tabs[closingIndex - 1]
        } else {
            neighbor = nil
        }
        return DocumentTabClosePlan(
            closingTabID: id,
            selectedTabIDAfterClose: neighbor?.id,
            documentToActivate: neighbor?.document
        )
    }

    func apply(_ plan: DocumentTabClosePlan) {
        guard tabs.contains(where: { $0.id == plan.closingTabID }) else { return }
        tabs.removeAll { $0.id == plan.closingTabID }
        if let selectedTabIDAfterClose = plan.selectedTabIDAfterClose,
           tabs.contains(where: { $0.id == selectedTabIDAfterClose }) {
            selectedTabID = selectedTabIDAfterClose
        } else {
            selectedTabID = nil
        }
    }

    func updateDocumentProjection(
        _ document: WindowSelectedDocument,
        title: String,
        toolTip: String
    ) {
        let key = DocumentTabKey(document)
        for index in tabs.indices where DocumentTabKey(tabs[index].document) == key {
            tabs[index].document = document
            tabs[index].title = title
            tabs[index].toolTip = toolTip
        }
    }

}
