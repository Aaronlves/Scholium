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
    let closingTabID: UUID
    let selectedTabIDAfterClose: UUID?
    let documentToActivate: WindowSelectedDocument?
}

enum DocumentTabPlacement: Equatable, Sendable {
    case replaceSelected
    case newTab
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

/// Window-local owner of the single ordered document-tab collection.
/// Library scope never owns tab membership or selection.
@MainActor
final class DocumentTabController: ObservableObject {
    @Published private(set) var tabs: [DocumentTabItem] = []
    @Published private(set) var selectedTabID: UUID?

    var selectedTab: DocumentTabItem? {
        tabs.first { $0.id == selectedTabID }
    }

    func activate(
        document: WindowSelectedDocument,
        title: String,
        toolTip: String,
        placement: DocumentTabPlacement
    ) {
        let key = DocumentTabKey(document)
        if let index = tabs.firstIndex(where: { DocumentTabKey($0.document) == key }) {
            tabs[index].document = document
            tabs[index].title = title
            tabs[index].toolTip = toolTip
            selectedTabID = tabs[index].id
        } else if placement == .replaceSelected,
            let index = tabs.firstIndex(where: { $0.id == selectedTabID })
        {
            tabs[index].document = document
            tabs[index].title = title
            tabs[index].toolTip = toolTip
        } else {
            let tab = DocumentTabItem(document: document, title: title, toolTip: toolTip)
            tabs.append(tab)
            selectedTabID = tab.id
        }
    }

    func selectTab(withID id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    func closePlan(forTabWithID id: UUID) -> DocumentTabClosePlan? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        guard selectedTabID == id else {
            return DocumentTabClosePlan(
                closingTabID: id, selectedTabIDAfterClose: selectedTabID,
                documentToActivate: nil
            )
        }
        let neighbor =
            tabs.indices.contains(index + 1)
            ? tabs[index + 1] : (index > 0 ? tabs[index - 1] : nil)
        return DocumentTabClosePlan(
            closingTabID: id, selectedTabIDAfterClose: neighbor?.id,
            documentToActivate: neighbor?.document
        )
    }

    func apply(_ plan: DocumentTabClosePlan) {
        guard closePlan(forTabWithID: plan.closingTabID) == plan else { return }
        tabs.removeAll { $0.id == plan.closingTabID }
        selectedTabID = plan.selectedTabIDAfterClose
    }

    /// Removes proven-missing documents without inventing a replacement selection.
    func removeTabs(withIDs ids: Set<UUID>) {
        tabs.removeAll { ids.contains($0.id) }
        if selectedTabID.map(ids.contains) == true { selectedTabID = nil }
    }

    func updateDocumentProjection(
        _ document: WindowSelectedDocument, title: String, toolTip: String
    ) {
        let key = DocumentTabKey(document)
        for index in tabs.indices where DocumentTabKey(tabs[index].document) == key {
            tabs[index].document = document
            tabs[index].title = title
            tabs[index].toolTip = toolTip
        }
    }

    func removeAll() {
        tabs = []
        selectedTabID = nil
    }
}
