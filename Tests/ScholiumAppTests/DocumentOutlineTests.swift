import AppKit
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Persistent document outline")
@MainActor
struct DocumentOutlineTests {
    @Test("Source hierarchy retains disclosure and passive refresh never navigates")
    func hierarchyAndDisclosure() throws {
        let projection = DocumentInformationProjection()
        let id = DocumentInformationDocumentID(vaultID: UUID(), relativePath: "Outline.md")
        projection.activate(id)
        let source = "# A\n\n## B\n\n### C\n\n# D\n"
        func headings(_ source: String) -> [HeadingNode] {
            MarkdownSemanticParser.parse(NoteDocument(relativePath: "Outline.md", rawContent: source)).headings
        }
        projection.publishOutline(headings(source), currentLine: nil, for: id)
        let outline = HeadingOutlineView()
        outline.addTableColumn(NSTableColumn(identifier: .init("heading")))
        let coordinator = DocumentHeadingOutline.Coordinator()
        coordinator.outline = outline
        outline.dataSource = coordinator
        outline.delegate = coordinator
        var navigations: [(Int, Bool)] = []
        let navigate: (Int, Bool) -> Void = { navigations.append(($0, $1)) }
        coordinator.update(projection, openHeading: navigate)
        #expect(outline.numberOfRows == 4)
        #expect(outline.level(forRow: 2) == 2)
        #expect(outline.selectedRow == -1)
        let first = try #require(outline.item(atRow: 0))
        outline.collapseItem(first)
        #expect(outline.numberOfRows == 2)
        projection.publishOutline(headings(source + "\nMore prose."), currentLine: 7, for: id)
        coordinator.update(projection, openHeading: navigate)
        #expect(!outline.isItemExpanded(first))
        #expect(outline.selectedRow == 1)
        #expect(navigations.isEmpty)
        outline.navigatingWithKeyboard = true
        outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        outline.navigatingWithKeyboard = false
        #expect(navigations.count == 1)
        #expect(navigations.first?.0 == 1 && navigations.first?.1 == false)
        coordinator.accept()
        #expect(navigations.last?.1 == true)
    }
}
