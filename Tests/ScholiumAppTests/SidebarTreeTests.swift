import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Library folder tree")
struct SidebarTreeTests {
    @Test("Folder actions retain the exact vault-relative path behind a hidden role root")
    func folderActionsUseExactVaultRelativePath() throws {
        let tree = buildTree(
            from: [
                .syntheticPreview(
                    relativePath: "papers/Ethics/Agency/Argument.md",
                    rawContent: "# Argument\n"
                ),
                .syntheticPreview(
                    relativePath: "papers/Ethics/Overview.md",
                    rawContent: "# Overview\n"
                ),
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
                .syntheticPreview(
                    relativePath: "papers/Shared/Analysis.md",
                    rawContent: "# Analysis\n"
                ),
                .syntheticPreview(
                    relativePath: "topics/Shared/Topic.md",
                    rawContent: "# Topic\n"
                ),
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
                .syntheticPreview(
                    relativePath: "papers/Ethics/Overview.md",
                    rawContent: "# Overview\n"
                ),
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

    @Test("Expanded hierarchy projects into stable top-level Sections and flat row order")
    func expandedHierarchyUsesFlatSectionProjection() throws {
        let tree = buildTree(
            from: [
                .syntheticPreview(
                    relativePath: "papers/Arguments/Agency/Reply.md",
                    rawContent: "# Reply\n"
                ),
                .syntheticPreview(
                    relativePath: "papers/Arguments/Overview.md",
                    rawContent: "# Overview\n"
                ),
                .syntheticPreview(
                    relativePath: "Loose.md",
                    rawContent: "# Loose\n"
                ),
            ],
            notesAreOrdered: { $0.relativePath < $1.relativePath }
        )

        let collapsed = sidebarSourceSections(from: tree, expandedFolders: [])
        let arguments = try #require(collapsed.first { $0.header?.id == "Arguments" })
        #expect(arguments.rows.isEmpty)

        let expanded = sidebarSourceSections(
            from: tree,
            expandedFolders: ["Arguments", "Arguments/Agency"]
        )
        let expandedArguments = try #require(
            expanded.first { $0.header?.id == "Arguments" }
        )
        #expect(expandedArguments.rows.map(\.id) == [
            "Arguments/Agency",
            "papers/Arguments/Agency/Reply.md",
            "papers/Arguments/Overview.md",
        ])
        #expect(expanded.first { $0.header?.id == nil }?.rows.map(\.id) == ["Loose.md"])
    }
}
