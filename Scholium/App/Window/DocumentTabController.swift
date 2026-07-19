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

    func replaceSelectedTab(
        with document: WindowSelectedDocument,
        title: String,
        toolTip: String
    ) {
        guard let selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else {
            appendTab(for: document, title: title, toolTip: toolTip)
            return
        }
        tabs[index].document = document
        tabs[index].title = title
        tabs[index].toolTip = toolTip
    }

    @discardableResult
    func appendTab(
        for document: WindowSelectedDocument,
        title: String,
        toolTip: String
    ) -> UUID {
        let tab = DocumentTabItem(
            document: document,
            title: title,
            toolTip: toolTip
        )
        tabs.append(tab)
        selectedTabID = tab.id
        return tab.id
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
        guard let sessionKey = document.sessionKey else {
            guard let index = tabs.firstIndex(where: {
                $0.document.relativePath == document.relativePath
            }) else { return }
            tabs[index].document = document
            tabs[index].title = title
            tabs[index].toolTip = toolTip
            return
        }
        for index in tabs.indices where tabs[index].document.sessionKey == sessionKey {
            tabs[index].document = document
            tabs[index].title = title
            tabs[index].toolTip = toolTip
        }
    }

}
