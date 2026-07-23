import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Library folder tree")
struct SidebarTreeTests {
    @Test("Folder actions retain the exact vault-relative path behind a hidden role root")
    func folderActionsUseExactVaultRelativePath() throws {
        let tree = buildTree(
            from: [
                .unclassified(NoteDocument(
                    relativePath: "papers/Ethics/Agency/Argument.md",
                    rawContent: "# Argument\n"
                )),
                .unclassified(NoteDocument(
                    relativePath: "papers/Ethics/Overview.md",
                    rawContent: "# Overview\n"
                )),
            ],
            notesAreOrdered: { $0.relativePath < $1.relativePath }
        )

        let ethics = try #require(tree.first { $0.id == "Ethics" })
        #expect(ethics.folderRelativePath == "papers/Ethics")
        let agency = try #require(ethics.children.first { $0.id == "Ethics/Agency" })
        #expect(agency.folderRelativePath == "papers/Ethics/Agency")
        #expect(agency.folderIDs == ["Ethics/Agency"])
    }

    @Test("Merged legacy display roots fail closed for contextual folder mutations")
    func ambiguousHiddenRootsHaveNoActionPath() throws {
        let tree = buildTree(
            from: [
                .unclassified(NoteDocument(
                    relativePath: "papers/Shared/Analysis.md",
                    rawContent: "# Analysis\n"
                )),
                .unclassified(NoteDocument(
                    relativePath: "topics/Shared/Topic.md",
                    rawContent: "# Topic\n"
                )),
            ],
            notesAreOrdered: { $0.relativePath < $1.relativePath }
        )

        let shared = try #require(tree.first { $0.id == "Shared" })
        #expect(shared.folderRelativePath == nil)
    }

    @Test("Empty folders participate in the same hierarchy as folders containing notes")
    func emptyFoldersAreVisible() throws {
        let tree = buildTree(
            from: [
                .unclassified(NoteDocument(
                    relativePath: "papers/Ethics/Overview.md",
                    rawContent: "# Overview\n"
                )),
            ],
            folderRelativePaths: [
                "papers",
                "papers/Ethics",
                "papers/Ethics/Empty Archive",
            ],
            notesAreOrdered: { $0.relativePath < $1.relativePath }
        )

        let ethics = try #require(tree.first { $0.id == "Ethics" })
        let empty = try #require(ethics.children.first {
            $0.id == "Ethics/Empty Archive"
        })
        #expect(empty.isFolder)
        #expect(empty.children.isEmpty)
        #expect(empty.folderRelativePath == "papers/Ethics/Empty Archive")
        #expect(!tree.contains { $0.id == "papers" })
    }
}
