import AppKit
import Foundation
import ScholiumContracts
import SwiftUI
import Testing
@testable import ScholiumApp

@Suite("Library folder tree")
struct SidebarTreeTests {
    @Test("Window tree cache ignores unrelated presentation publications")
    @MainActor
    func windowTreeProjectionCache() {
        let notes = [WindowDocumentLocation.syntheticPreview(
            relativePath: "Cluster/Note.md",
            rawContent: "# Note\n"
        )]
        let cache = LibraryTreeProjectionCache()
        let first = cache.projection(
            preorderedNotes: notes,
            folderRelativePaths: ["Empty"]
        )
        let repeated = cache.projection(
            preorderedNotes: notes,
            folderRelativePaths: ["Empty"]
        )

        #expect(repeated.revision == first.revision)
        #expect(repeated.value.roots.map(\.id) == ["Cluster", "Empty"])

        let changed = cache.projection(
            preorderedNotes: notes,
            folderRelativePaths: ["Empty", "Second"]
        )
        #expect(changed.revision == first.revision + 1)

        let revisedNotes = [WindowDocumentLocation.syntheticPreview(
            relativePath: "Cluster/Note.md",
            rawContent: "# Revised\n"
        )]
        let revised = cache.projection(
            preorderedNotes: revisedNotes,
            folderRelativePaths: ["Empty", "Second"]
        )
        #expect(revised.revision == changed.revision + 1)
        #expect(
            revised.value.roots
                .first(where: { $0.id == "Cluster" })?
                .children.first?
                .note?.rawContent == "# Revised\n"
        )
    }

    @Test("Ten thousand sibling folders build one bounded adjacency projection")
    func largeSiblingFolderProjection() {
        let folders = (0..<10_000).map { index in
            "Cluster-\(String(format: "%05d", index))"
        }
        let clock = ContinuousClock()
        let start = clock.now
        let projection = LibraryTreeProjection(
            preorderedNotes: [],
            folderRelativePaths: folders
        )
        let elapsed = start.duration(to: clock.now)
        print("LibraryTreeProjection diagnostic: 10,000 sibling folders in \(elapsed)")

        #expect(projection.roots.count == folders.count)
        #expect(projection.expandableFolderIDs.isEmpty)
        #expect(elapsed < .seconds(2))
    }

    @Test("Ten thousand preordered Notes build one bounded hierarchy projection")
    func largePreorderedNoteProjection() throws {
        let notes = (0..<10_000).map { index in
            WindowDocumentLocation.syntheticPreview(
                relativePath: "Cluster/Note-\(String(format: "%05d", index)).md",
                rawContent: ""
            )
        }
        let clock = ContinuousClock()
        let start = clock.now
        let projection = LibraryTreeProjection(
            preorderedNotes: notes
        )
        let elapsed = start.duration(to: clock.now)
        print("LibraryTreeProjection diagnostic: 10,000 preordered Notes in \(elapsed)")

        let folder = try #require(projection.roots.first)
        #expect(folder.id == "Cluster")
        #expect(folder.children.count == notes.count)
        #expect(folder.children.first?.id == "Cluster/Note-00000.md")
        #expect(folder.children.last?.id == "Cluster/Note-09999.md")
        #expect(elapsed < .seconds(2))
    }

    @Test("Context menus and accessibility actions share one lifecycle command projection")
    func noteCommandProjection() {
        let workspaceMenu = sidebarNoteCommandGroups(
            locationScope: .workspace,
            isManagedCritique: false,
            surface: .contextMenu
        ).flatMap(\.commands)
        #expect(workspaceMenu == [
            .openInNewTab,
            .duplicate,
            .rename,
            .setAside,
            .moveToTrash,
            .copyRelativePath,
            .revealInFinder,
        ])

        let workspaceAccessibility = sidebarNoteCommandGroups(
            locationScope: .workspace,
            isManagedCritique: false,
            surface: .accessibility
        ).flatMap(\.commands)
        #expect(workspaceAccessibility == [
            .openInNewTab,
            .duplicate,
            .rename,
            .move,
            .setAside,
            .moveToTrash,
            .copyRelativePath,
            .revealInFinder,
        ])

        let managedCritique = sidebarNoteCommandGroups(
            locationScope: .workspace,
            isManagedCritique: true,
            surface: .accessibility
        ).flatMap(\.commands)
        #expect(!managedCritique.contains(.duplicate))

        let setAside = sidebarNoteCommandGroups(
            locationScope: .setAside,
            isManagedCritique: false,
            surface: .accessibility
        ).flatMap(\.commands)
        #expect(setAside == [
            .openInNewTab,
            .putBack,
            .moveToTrash,
            .copyRelativePath,
            .revealInFinder,
        ])

        let trash = sidebarNoteCommandGroups(
            locationScope: .trash,
            isManagedCritique: false,
            surface: .accessibility
        ).flatMap(\.commands)
        #expect(trash == [
            .openInNewTab,
            .putBack,
            .deletePermanently,
            .copyRelativePath,
            .revealInFinder,
        ])
    }

    @Test("Library filter presentation counts only complete property filters")
    func libraryFilterPresentationProjection() {
        var filters = DiscoveryFilterState()
        #expect(sidebarActiveLibraryFilterCount(filters) == 0)

        filters.needsAttention = true
        filters.tag = "Agency"
        filters.propertyKey = "publication_status"
        #expect(sidebarActiveLibraryFilterCount(filters) == 2)

        filters.propertyValue = "forthcoming"
        #expect(sidebarActiveLibraryFilterCount(filters) == 3)

        filters.propertyValue = "  \n"
        #expect(sidebarActiveLibraryFilterCount(filters) == 3)
    }

    @Test("Modified ordering uses file time before the title tie-break")
    @MainActor
    func modifiedOrderingPreservesTitleTieBreak() {
        let window = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let vaultID = UUID()
        let older = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Zeta.md",
            source: "# Zeta\n",
            modificationDate: Date(timeIntervalSince1970: 1)
        )
        let newer = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Alpha.md",
            source: "# Alpha\n",
            modificationDate: Date(timeIntervalSince1970: 2)
        )

        window.discoveryController.selectSortOrder(.modifiedNewest)
        #expect(window.notesAreOrdered(newer, older))
        #expect(!window.notesAreOrdered(older, newer))

        window.discoveryController.selectSortOrder(.modifiedOldest)
        #expect(window.notesAreOrdered(older, newer))
        #expect(!window.notesAreOrdered(newer, older))

        let alphaTie = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Alpha Tie.md",
            source: "# Alpha\n",
            modificationDate: Date(timeIntervalSince1970: 1)
        )
        window.discoveryController.selectSortOrder(.modifiedNewest)
        #expect(window.notesAreOrdered(alphaTie, older))
    }

    @Test("Concurrent row removals retain independent vault-qualified focus plans")
    func concurrentRemovalFocusPlans() {
        let vaultID = UUID()
        let scope = LibraryDisclosureScope(
            vaultID: vaultID,
            locationScope: .setAside
        )
        let firstID = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Set Aside/A.md"
        )
        let secondID = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Set Aside/B.md"
        )
        let remainingID = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Set Aside/C.md"
        )
        let paths = [
            firstID.relativePath,
            secondID.relativePath,
            remainingID.relativePath,
        ]
        let first = sidebarRemovalFocusPlan(
            originDocumentID: firstID,
            originPath: firstID.relativePath,
            disclosureScope: scope,
            visibleNotePaths: paths
        )
        let second = sidebarRemovalFocusPlan(
            originDocumentID: secondID,
            originPath: secondID.relativePath,
            disclosureScope: scope,
            visibleNotePaths: paths
        )

        let afterFirst = sidebarRemovalFocusAfterCompletions(
            plans: [first, second],
            disclosureScope: scope,
            remainingDocumentIDs: [secondID, remainingID],
            remainingVisibleNotePaths: [
                secondID.relativePath,
                remainingID.relativePath,
            ]
        )
        #expect(afterFirst.pendingPlans == [second])
        #expect(afterFirst.destination == .row(secondID.relativePath))

        let afterSecond = sidebarRemovalFocusAfterCompletions(
            plans: afterFirst.pendingPlans,
            disclosureScope: scope,
            remainingDocumentIDs: [remainingID],
            remainingVisibleNotePaths: [remainingID.relativePath]
        )
        #expect(afterSecond.pendingPlans.isEmpty)
        #expect(afterSecond.destination == .row(remainingID.relativePath))
    }

    @Test("A failed removal restores only its own row and preserves another plan")
    func failedRemovalFocusPlan() {
        let vaultID = UUID()
        let scope = LibraryDisclosureScope(
            vaultID: vaultID,
            locationScope: .trash
        )
        let failedID = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Trash/A.md"
        )
        let pendingID = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Trash/B.md"
        )
        let failed = sidebarRemovalFocusPlan(
            originDocumentID: failedID,
            originPath: failedID.relativePath,
            disclosureScope: scope,
            visibleNotePaths: [failedID.relativePath, pendingID.relativePath]
        )
        let pending = sidebarRemovalFocusPlan(
            originDocumentID: pendingID,
            originPath: pendingID.relativePath,
            disclosureScope: scope,
            visibleNotePaths: [failedID.relativePath, pendingID.relativePath]
        )

        let result = sidebarRemovalFocusAfterFailure(
            plans: [failed, pending],
            originDocumentID: failedID,
            originPath: failedID.relativePath,
            disclosureScope: scope
        )
        #expect(result.pendingPlans == [pending])
        #expect(result.destination == .row(failedID.relativePath))
    }

    @Test("Every hierarchy level advances one shared Folder and Note leading axis")
    func hierarchyRowTitleAxes() {
        #expect(sidebarLibraryRowLeadingInset(depth: 0) == 12)
        #expect(sidebarLibraryRowLeadingInset(depth: 1) == 28)
        #expect(sidebarLibraryRowLeadingInset(depth: 2) == 44)
        #expect(sidebarLibraryRowLeadingInset(depth: 3) == 60)
    }

    @Test("A created Note reveals only its folder ancestors")
    func createdNoteFolderAncestors() {
        #expect(libraryFolderAncestors(forDocumentPath: "Untitled.md").isEmpty)
        #expect(
            libraryFolderAncestors(
                forDocumentPath: "papers/Arguments/Agency/Untitled.md"
            ) == ["papers", "papers/Arguments", "papers/Arguments/Agency"]
        )
        #expect(
            libraryFolderAncestors(
                forDocumentPath: "Set Aside/papers/Arguments/Untitled.md"
            ) == ["papers", "papers/Arguments"]
        )
    }

    @Test("Former role names remain ordinary researcher Folder roots")
    func formerRoleNamesRemainOrdinaryFolders() throws {
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
                .syntheticPreview(
                    relativePath: "topics/Debate/Position.md",
                    rawContent: "# Position\n"
                ),
                .syntheticPreview(
                    relativePath: "output/Chapter/Draft.md",
                    rawContent: "# Draft\n"
                ),
            ],
            notesAreOrdered: { $0.relativePath < $1.relativePath }
        )

        #expect(Set(tree.filter(\.isFolder).map(\.id)) == ["papers", "topics", "output"])
        let papers = try #require(tree.first { $0.id == "papers" })
        #expect(papers.folderRelativePath == "papers")
        let ethics = try #require(papers.children.first { $0.id == "papers/Ethics" })
        #expect(ethics.folderRelativePath == "papers/Ethics")
        let agency = try #require(ethics.children.first { $0.id == "papers/Ethics/Agency" })
        #expect(agency.folderRelativePath == "papers/Ethics/Agency")
        #expect(agency.folderIDs == ["papers/Ethics/Agency"])
    }

    @Test("Same-named subfolders under distinct roots retain distinct action paths")
    func sameNamedSubfoldersRemainDistinct() throws {
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

        let papers = try #require(tree.first { $0.id == "papers" })
        let topics = try #require(tree.first { $0.id == "topics" })
        let paperShared = try #require(papers.children.first { $0.id == "papers/Shared" })
        let topicShared = try #require(topics.children.first { $0.id == "topics/Shared" })
        #expect(paperShared.folderRelativePath == "papers/Shared")
        #expect(topicShared.folderRelativePath == "topics/Shared")
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

        let papers = try #require(tree.first { $0.id == "papers" })
        let ethics = try #require(papers.children.first { $0.id == "papers/Ethics" })
        let empty = try #require(ethics.children.first {
            $0.id == "papers/Ethics/Empty Archive"
        })
        #expect(empty.isFolder)
        #expect(empty.children.isEmpty)
        #expect(empty.folderRelativePath == "papers/Ethics/Empty Archive")
        let projection = LibraryTreeProjection(
            preorderedNotes: [],
            folderRelativePaths: [
                "papers",
                "papers/Ethics",
                "papers/Ethics/Empty Archive",
            ]
        )
        #expect(projection.expandableFolderIDs == ["papers", "papers/Ethics"])
        #expect(tree.contains { $0.id == "papers" })
    }

    @Test("Lifecycle categories strip only their category root")
    func lifecycleCategoriesShareFolderProjection() throws {
        let tree = buildTree(
            from: [
                .syntheticPreview(
                    relativePath: "Set Aside/papers/Arguments/Agency/Reply.md",
                    rawContent: "# Reply\n"
                ),
            ],
            folderRelativePaths: [
                "Set Aside",
                "Set Aside/papers",
                "Set Aside/papers/Arguments",
                "Set Aside/papers/Arguments/Empty Archive",
            ],
            notesAreOrdered: { $0.relativePath < $1.relativePath }
        )

        let papers = try #require(tree.first { $0.id == "papers" })
        #expect(papers.folderRelativePath == "Set Aside/papers")
        let arguments = try #require(papers.children.first { $0.id == "papers/Arguments" })
        #expect(arguments.folderRelativePath == "Set Aside/papers/Arguments")
        #expect(arguments.children.contains { $0.id == "papers/Arguments/Agency" })
        #expect(arguments.children.contains {
            $0.id == "papers/Arguments/Empty Archive"
        })
        #expect(!tree.contains { $0.id == "Set Aside" })
        #expect(libraryFolderAncestors(
            forDocumentPath: "Trash/topics/Debate/Objection.md"
        ) == ["topics", "topics/Debate"])
    }

    @Test("Native outline visibility stays deterministic")
    func expandedHierarchyUsesNativeOutlineProjection() throws {
        let tree = buildTree(
            from: [
                .syntheticPreview(
                    relativePath: "Arguments/Agency/Reply.md",
                    rawContent: "# Reply\n"
                ),
                .syntheticPreview(
                    relativePath: "Arguments/Overview.md",
                    rawContent: "# Overview\n"
                ),
                .syntheticPreview(
                    relativePath: "Loose.md",
                    rawContent: "# Loose\n"
                ),
            ],
            notesAreOrdered: { $0.relativePath < $1.relativePath }
        )

        let collapsed = sidebarVisibleTreeNodes(from: tree, expandedFolders: [])
        #expect(collapsed.map(\.id) == ["Arguments", "Loose.md"])

        let expanded = sidebarVisibleTreeNodes(
            from: tree,
            expandedFolders: ["Arguments", "Arguments/Agency"]
        )
        #expect(expanded.map(\.id) == [
            "Arguments",
            "Arguments/Agency",
            "Arguments/Agency/Reply.md",
            "Arguments/Overview.md",
            "Loose.md",
        ])
        #expect(sidebarOutlineRowHeight(usesAccessibilitySize: false) == 28)
        #expect(sidebarOutlineRowHeight(usesAccessibilitySize: true) == 44)
    }

    @Test("Native expansion synchronization runs only for changed disclosure or structure")
    func nativeExpansionSynchronizationInvalidation() {
        let disclosure: Set<String> = ["Cluster"]
        #expect(sidebarExpansionSynchronizationIsRequired(
            previouslyApplied: nil,
            desired: disclosure,
            structureChanged: false
        ))
        #expect(!sidebarExpansionSynchronizationIsRequired(
            previouslyApplied: disclosure,
            desired: disclosure,
            structureChanged: false
        ))
        #expect(sidebarExpansionSynchronizationIsRequired(
            previouslyApplied: disclosure,
            desired: ["Other"],
            structureChanged: false
        ))
        #expect(sidebarExpansionSynchronizationIsRequired(
            previouslyApplied: disclosure,
            desired: disclosure,
            structureChanged: true
        ))
    }

    @Test("An empty root Folder remains visible when disclosure state contains it")
    func emptyRootRemainsVisible() throws {
        let tree = buildTree(
            from: [],
            folderRelativePaths: ["Empty Archive"],
            notesAreOrdered: { $0.relativePath < $1.relativePath }
        )

        let projected = sidebarVisibleTreeNodes(
            from: tree,
            expandedFolders: ["Empty Archive"]
        )
        let empty = try #require(projected.first)
        #expect(projected.map(\.id) == ["Empty Archive"])
        #expect(empty.isFolder)
        #expect(empty.children.isEmpty)
    }

    @Test("An absent Note never becomes selected when no document is selected")
    func outlineSelectionRequiresTwoConcretePaths() {
        #expect(!sidebarOutlineDocumentIsSelected(
            notePath: nil,
            selectedDocumentPath: nil
        ))
        #expect(!sidebarOutlineDocumentIsSelected(
            notePath: "papers/Argument.md",
            selectedDocumentPath: nil
        ))
        #expect(!sidebarOutlineDocumentIsSelected(
            notePath: nil,
            selectedDocumentPath: "papers/Argument.md"
        ))
        #expect(sidebarOutlineDocumentIsSelected(
            notePath: "papers/Argument.md",
            selectedDocumentPath: "papers/Argument.md"
        ))
        #expect(!sidebarOutlineDocumentIsSelected(
            notePath: "papers/Argument.md",
            selectedDocumentPath: "papers/Reply.md"
        ))
    }

    @Test("Put Back is quiet at rest and appears for pointer or keyboard focus")
    func lifecyclePutBackVisibility() {
        #expect(!sidebarLifecyclePutBackControlIsVisible(
            isHovered: false,
            isNativeFocused: false
        ))
        #expect(sidebarLifecyclePutBackControlIsVisible(
            isHovered: true,
            isNativeFocused: false
        ))
        #expect(sidebarLifecyclePutBackControlIsVisible(
            isHovered: false,
            isNativeFocused: true
        ))
    }

    @Test("Only visibly expanded Folders request the Collapse All presentation")
    func visibleExpandedFolderState() throws {
        let tree = buildTree(
            from: [
                .syntheticPreview(
                    relativePath: "Arguments/Agency/Reply.md",
                    rawContent: "# Reply\n"
                ),
            ],
            notesAreOrdered: { $0.relativePath < $1.relativePath }
        )
        let arguments = try #require(tree.first { $0.id == "Arguments" })

        #expect(
            arguments.visibleExpandedFolderIDs(in: ["Arguments/Agency"])
                .isEmpty
        )
        #expect(
            arguments.visibleExpandedFolderIDs(
                in: ["Arguments", "Arguments/Agency"]
            ) == ["Arguments", "Arguments/Agency"]
        )
    }

    @Test("A dropped Note keeps its file name and changes only its containing folder")
    func droppedNoteDestination() {
        #expect(
            sidebarNoteDropDestination(
                sourceRelativePath: "papers/Cluster-01/Argument.md",
                folderRelativePath: "papers/Cluster-10"
            ) == "papers/Cluster-10/Argument.md"
        )
        #expect(
            sidebarNoteDropDestination(
                sourceRelativePath: "papers/Cluster-01/Argument.md",
                folderRelativePath: nil
            ) == "Argument.md"
        )
    }

    @Test("A dropped Folder can move into another Folder or back to the vault root")
    func droppedFolderDestination() {
        #expect(
            sidebarFolderDropDestination(
                sourceRelativePath: "papers/Cluster-01/Arguments",
                folderRelativePath: "papers/Cluster-10"
            ) == "papers/Cluster-10/Arguments"
        )
        #expect(
            sidebarFolderDropDestination(
                sourceRelativePath: "papers/Cluster-01/Arguments",
                folderRelativePath: nil
            ) == "Arguments"
        )
    }

    @Test("A Folder drop rejects no-op, self, and descendant destinations")
    func droppedFolderRejectsInvalidDestinations() {
        #expect(sidebarFolderDropDestination(
            sourceRelativePath: "Cluster-01/Arguments",
            folderRelativePath: "Cluster-01"
        ) == nil)
        #expect(sidebarFolderDropDestination(
            sourceRelativePath: "Cluster-01/Arguments",
            folderRelativePath: "Cluster-01/Arguments"
        ) == nil)
        #expect(sidebarFolderDropDestination(
            sourceRelativePath: "Cluster-01/Arguments",
            folderRelativePath: "Cluster-01/Arguments/Replies"
        ) == nil)
        #expect(sidebarFolderDropDestination(
            sourceRelativePath: "Arguments",
            folderRelativePath: nil
        ) == nil)
    }

    @Test("Native Note drop validation rejects stale, pending, and occupied moves")
    func nativeNoteDropValidation() throws {
        let vaultID = UUID()
        let stableID = UUID()
        let pathComparisonPolicy = VaultPathComparisonPolicy(
            caseSensitive: true,
            normalizationSensitive: true
        )
        let source = workspaceNote(
            vaultID: vaultID,
            stableID: stableID,
            path: "papers/Cluster-01/Argument.md",
            source: "# Argument\n"
        )
        let target = try #require(NoteLifecycleTarget(source))
        let item = SidebarNoteDragItem(target)
        let base = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            locationScope: .workspace,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [source],
            folderRelativePaths: [
                "papers/Cluster-01",
                "papers/Cluster-10",
            ],
            pathComparisonPolicy: pathComparisonPolicy,
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )

        #expect(sidebarValidatedNoteDropDestination(
            item: item,
            folderRelativePath: "papers/Cluster-10",
            inventory: base
        ) == "papers/Cluster-10/Argument.md")
        #expect(sidebarValidatedNoteDropDestination(
            item: item,
            folderRelativePath: nil,
            inventory: base
        ) == "Argument.md")

        let unavailablePolicy = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            locationScope: .workspace,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [source],
            folderRelativePaths: base.folderRelativePaths,
            pathComparisonPolicy: nil,
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(sidebarValidatedNoteDropDestination(
            item: item,
            folderRelativePath: "papers/Cluster-10",
            inventory: unavailablePolicy
        ) == nil)

        let stale = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            locationScope: .workspace,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [workspaceNote(
                vaultID: vaultID,
                stableID: stableID,
                path: target.relativePath,
                source: "# Changed while dragging\n"
            )],
            folderRelativePaths: base.folderRelativePaths,
            pathComparisonPolicy: pathComparisonPolicy,
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(sidebarValidatedNoteDropDestination(
            item: item,
            folderRelativePath: "papers/Cluster-10",
            inventory: stale
        ) == nil)

        let pending = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            locationScope: .workspace,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [source],
            folderRelativePaths: base.folderRelativePaths,
            pathComparisonPolicy: pathComparisonPolicy,
            pendingNoteMoves: [item.id],
            pendingFolderMoves: []
        )
        #expect(sidebarValidatedNoteDropDestination(
            item: item,
            folderRelativePath: "papers/Cluster-10",
            inventory: pending
        ) == nil)

        let collision = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            locationScope: .workspace,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [
                source,
                workspaceNote(
                    vaultID: vaultID,
                    stableID: UUID(),
                    path: "papers/Cluster-10/Argument.md",
                    source: "# Existing\n"
                ),
            ],
            folderRelativePaths: base.folderRelativePaths,
            pathComparisonPolicy: pathComparisonPolicy,
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(sidebarValidatedNoteDropDestination(
            item: item,
            folderRelativePath: "papers/Cluster-10",
            inventory: collision
        ) == nil)
    }

    @Test("Native Folder drop validation rejects pending and occupied moves")
    func nativeFolderDropValidation() {
        let vaultID = UUID()
        let pathComparisonPolicy = VaultPathComparisonPolicy(
            caseSensitive: true,
            normalizationSensitive: true
        )
        let item = SidebarFolderDragItem(FolderLifecycleTarget(
            vaultID: vaultID,
            relativePath: "papers/Cluster-01/Arguments"
        ))
        let folders: Set<String> = [
            "papers/Cluster-01",
            "papers/Cluster-01/Arguments",
            "papers/Cluster-10",
        ]
        let base = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            locationScope: .workspace,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [],
            folderRelativePaths: folders,
            pathComparisonPolicy: pathComparisonPolicy,
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(sidebarValidatedFolderDropDestination(
            item: item,
            folderRelativePath: "papers/Cluster-10",
            inventory: base
        ) == "papers/Cluster-10/Arguments")
        #expect(sidebarValidatedFolderDropDestination(
            item: item,
            folderRelativePath: nil,
            inventory: base
        ) == "Arguments")

        let unavailablePolicy = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            locationScope: .workspace,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [],
            folderRelativePaths: folders,
            pathComparisonPolicy: nil,
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(sidebarValidatedFolderDropDestination(
            item: item,
            folderRelativePath: "papers/Cluster-10",
            inventory: unavailablePolicy
        ) == nil)

        let pending = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            locationScope: .workspace,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [],
            folderRelativePaths: folders,
            pathComparisonPolicy: pathComparisonPolicy,
            pendingNoteMoves: [],
            pendingFolderMoves: [item.id]
        )
        #expect(sidebarValidatedFolderDropDestination(
            item: item,
            folderRelativePath: "papers/Cluster-10",
            inventory: pending
        ) == nil)

        let occupied = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            locationScope: .workspace,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [],
            folderRelativePaths: folders.union(["papers/Cluster-10/Arguments"]),
            pathComparisonPolicy: pathComparisonPolicy,
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(sidebarValidatedFolderDropDestination(
            item: item,
            folderRelativePath: "papers/Cluster-10",
            inventory: occupied
        ) == nil)
    }

    @Test("Native Note drop validation uses the mounted volume comparison policy")
    func nativeNoteDropUsesVolumeComparisonPolicy() throws {
        let vaultID = UUID()
        let source = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Source/Draft.md",
            source: "# Draft\n"
        )
        let caseVariant = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Target/draft.md",
            source: "# Existing\n"
        )
        let item = SidebarNoteDragItem(try #require(NoteLifecycleTarget(source)))
        let folders: Set<String> = ["Source", "Target"]

        let caseInsensitive = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            locationScope: .workspace,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [source, caseVariant],
            folderRelativePaths: folders,
            pathComparisonPolicy: VaultPathComparisonPolicy(
                caseSensitive: false,
                normalizationSensitive: true
            ),
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(sidebarValidatedNoteDropDestination(
            item: item,
            folderRelativePath: "Target",
            inventory: caseInsensitive
        ) == nil)

        let caseSensitive = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            locationScope: .workspace,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [source, caseVariant],
            folderRelativePaths: folders,
            pathComparisonPolicy: VaultPathComparisonPolicy(
                caseSensitive: true,
                normalizationSensitive: true
            ),
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(sidebarValidatedNoteDropDestination(
            item: item,
            folderRelativePath: "Target",
            inventory: caseSensitive
        ) == "Target/Draft.md")

        let unicodeSource = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Source/Café.md",
            source: "# Café\n"
        )
        let unicodeVariant = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Target/Cafe\u{301}.md",
            source: "# Existing\n"
        )
        let unicodeItem = SidebarNoteDragItem(
            try #require(NoteLifecycleTarget(unicodeSource))
        )
        let normalizationInsensitive = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            locationScope: .workspace,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [unicodeSource, unicodeVariant],
            folderRelativePaths: folders,
            pathComparisonPolicy: VaultPathComparisonPolicy(
                caseSensitive: true,
                normalizationSensitive: false
            ),
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(sidebarValidatedNoteDropDestination(
            item: unicodeItem,
            folderRelativePath: "Target",
            inventory: normalizationInsensitive
        ) == nil)
    }

    @Test("Native Folder drop validation uses the mounted volume comparison policy")
    func nativeFolderDropUsesVolumeComparisonPolicy() {
        let vaultID = UUID()
        let item = SidebarFolderDragItem(FolderLifecycleTarget(
            vaultID: vaultID,
            relativePath: "Source/Arguments"
        ))
        let folders: Set<String> = [
            "Source",
            "Source/Arguments",
            "Target",
            "Target/arguments",
        ]
        let caseInsensitive = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            locationScope: .workspace,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [],
            folderRelativePaths: folders,
            pathComparisonPolicy: VaultPathComparisonPolicy(
                caseSensitive: false,
                normalizationSensitive: true
            ),
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(sidebarValidatedFolderDropDestination(
            item: item,
            folderRelativePath: "Target",
            inventory: caseInsensitive
        ) == nil)

        let caseSensitive = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            locationScope: .workspace,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [],
            folderRelativePaths: folders,
            pathComparisonPolicy: VaultPathComparisonPolicy(
                caseSensitive: true,
                normalizationSensitive: true
            ),
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(sidebarValidatedFolderDropDestination(
            item: item,
            folderRelativePath: "Target",
            inventory: caseSensitive
        ) == "Target/Arguments")

        let currentParentWithDifferentCase = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            locationScope: .workspace,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [],
            folderRelativePaths: ["Source/Arguments", "source"],
            pathComparisonPolicy: VaultPathComparisonPolicy(
                caseSensitive: false,
                normalizationSensitive: true
            ),
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(sidebarValidatedFolderDropDestination(
            item: item,
            folderRelativePath: "source",
            inventory: currentParentWithDifferentCase
        ) == nil)
    }

    @Test("Rename changes only the file name inside the current folder")
    func renamedNoteDestination() {
        #expect(
            noteRenameDestination(
                sourceRelativePath: "papers/Cluster-01/Argument.md",
                requestedName: "Revised Argument"
            ) == "papers/Cluster-01/Revised Argument.md"
        )
        #expect(
            noteRenameDestination(
                sourceRelativePath: "Argument.md",
                requestedName: "Revised.md"
            ) == "Revised.md"
        )
        #expect(noteRenameDestination(
            sourceRelativePath: "Argument.md",
            requestedName: "Another/Folder"
        ) == nil)
    }

    @MainActor
    @Test("Sidebar drops queued reveal and focus callbacks across detach and reattach")
    func coordinatorDropsStaleTeardownCallbacks() async throws {
        _ = NSApplication.shared
        let vaultID = UUID()
        let firstNote = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Folder/First.md",
            source: "# First\n"
        )
        let secondNote = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Folder/Second.md",
            source: "# Second\n"
        )
        let projection = LibraryTreeProjection(
            preorderedNotes: [firstNote, secondNote]
        )
        let scope = LibraryDisclosureScope(
            vaultID: vaultID,
            locationScope: .workspace
        )
        let expandedFolderIDs: Set<String> = ["Folder"]
        var revealCount = 0
        var focusCount = 0

        let initialConfiguration = makeSidebarCoordinatorConfiguration(
            roots: projection.roots,
            notes: [firstNote, secondNote],
            scope: scope,
            expandedFolderIDs: expandedFolderIDs,
            revealRequest: DiscoveryLibraryRevealRequest(
                generation: 1,
                scope: scope,
                relativePath: firstNote.relativePath,
                alignment: .nearest
            ),
            requestedFocusPath: firstNote.relativePath,
            onConsumeRevealRequest: { _ in revealCount += 1 },
            onFocusRequestHandled: { focusCount += 1 }
        )
        let coordinator = SidebarOutlineSourceList.Coordinator(
            configuration: initialConfiguration
        )
        let firstFixture = makeSidebarCoordinatorOutline(coordinator)
        coordinator.apply(configuration: initialConfiguration)
        try await Task.sleep(for: .milliseconds(25))

        #expect(revealCount == 1)
        #expect(focusCount == 1)

        let staleConfiguration = makeSidebarCoordinatorConfiguration(
            roots: projection.roots,
            notes: [firstNote, secondNote],
            scope: scope,
            expandedFolderIDs: expandedFolderIDs,
            revealRequest: DiscoveryLibraryRevealRequest(
                generation: 2,
                scope: scope,
                relativePath: secondNote.relativePath,
                alignment: .center
            ),
            requestedFocusPath: secondNote.relativePath,
            onConsumeRevealRequest: { _ in revealCount += 1 },
            onFocusRequestHandled: { focusCount += 1 }
        )
        coordinator.apply(configuration: staleConfiguration)
        coordinator.detach(from: firstFixture.scrollView)
        try await Task.sleep(for: .milliseconds(25))

        #expect(revealCount == 1)
        #expect(focusCount == 1)

        let replacementConfiguration = makeSidebarCoordinatorConfiguration(
            roots: projection.roots,
            notes: [firstNote, secondNote],
            scope: scope,
            expandedFolderIDs: expandedFolderIDs,
            revealRequest: DiscoveryLibraryRevealRequest(
                generation: 3,
                scope: scope,
                relativePath: firstNote.relativePath,
                alignment: .nearest
            ),
            requestedFocusPath: firstNote.relativePath,
            onConsumeRevealRequest: { _ in revealCount += 1 },
            onFocusRequestHandled: { focusCount += 1 }
        )
        let replacementFixture = makeSidebarCoordinatorOutline(coordinator)
        coordinator.apply(configuration: replacementConfiguration)
        try await Task.sleep(for: .milliseconds(25))

        #expect(revealCount == 2)
        #expect(focusCount == 2)
        coordinator.detach(from: replacementFixture.scrollView)
    }

    private func workspaceNote(
        vaultID: UUID,
        stableID: UUID,
        path: String,
        source: String,
        modificationDate: Date? = nil
    ) -> WindowDocumentLocation {
        let document = NoteDocument(relativePath: path, rawContent: source)
        return .workspace(WorkspaceNoteSnapshot(
            id: VaultQualifiedNoteID(vaultID: vaultID, relativePath: path),
            vaultRole: .sourceCorpus,
            stableIdentity: .resolved(stableID),
            document: document,
            fileMetadata: WorkspaceFileMetadata(
                byteCount: document.sourceBytes.count,
                creationDate: nil,
                modificationDate: modificationDate
            ),
            lifecycle: .active,
            graphCounts: WorkspaceGraphCounts(
                incoming: 0,
                outgoing: 0,
                broken: 0,
                ambiguous: 0
            )
        ))
    }
}

@MainActor
private func makeSidebarCoordinatorConfiguration(
    roots: [TreeNode],
    notes: [WindowDocumentLocation],
    scope: LibraryDisclosureScope,
    expandedFolderIDs: Set<String>,
    revealRequest: DiscoveryLibraryRevealRequest?,
    requestedFocusPath: String?,
    onConsumeRevealRequest: @escaping (DiscoveryLibraryRevealRequest) -> Void,
    onFocusRequestHandled: @escaping () -> Void
) -> SidebarOutlineSourceList {
    let context = SidebarTreeContext(
        currentVaultID: scope.vaultID,
        currentVaultRole: .other,
        locationScope: .workspace,
        openNote: { _, _ in },
        requestLifecycle: { _ in },
        canMutateLibrary: false,
        createUntitledNote: { _ in },
        createUntitledFolder: { _ in },
        requestFolderLifecycle: { _ in },
        moveFolderToTrash: { _ in },
        copyRelativePath: { _ in },
        revealNote: { _ in },
        setAside: { _ in },
        moveToTrash: { _ in },
        deletePermanently: { _ in },
        showError: { _ in }
    )
    let dropInventory = SidebarTreeDropInventory(
        currentVaultID: scope.vaultID,
        locationScope: .workspace,
        currentVaultRole: .other,
        canMutate: false,
        notes: notes,
        folderRelativePaths: [],
        pathComparisonPolicy: nil,
        pendingNoteMoves: [],
        pendingFolderMoves: []
    )
    return SidebarOutlineSourceList(
        roots: roots,
        projectionRevision: 1,
        locale: Locale(identifier: "en_US"),
        expandedFolders: .constant(expandedFolderIDs),
        expandedFolderIDs: expandedFolderIDs,
        rowHeight: 24,
        selectedDocumentPath: nil,
        context: context,
        dropInventory: dropInventory,
        revealRequest: revealRequest,
        disclosureScope: scope,
        focusRequestGeneration: 0,
        requestedFocusPath: requestedFocusPath,
        onConsumeRevealRequest: onConsumeRevealRequest,
        onFocusRequestHandled: onFocusRequestHandled,
        onSelect: { _ in },
        putBackDocumentsInProgress: [],
        onMoveNoteDrop: { _, _ in },
        onMoveFolderDrop: { _, _ in },
        onPutBack: { _ in },
        onWillRemove: { _ in },
        onMutationFailed: { _ in }
    )
}

@MainActor
private func makeSidebarCoordinatorOutline(
    _ coordinator: SidebarOutlineSourceList.Coordinator
) -> (scrollView: NSScrollView, outlineView: SidebarOutlineView) {
    let scrollView = NSScrollView(
        frame: NSRect(x: 0, y: 0, width: 320, height: 320)
    )
    let outlineView = SidebarOutlineView(
        frame: NSRect(x: 0, y: 0, width: 320, height: 320)
    )
    outlineView.dataSource = coordinator
    outlineView.delegate = coordinator
    outlineView.style = .sourceList
    outlineView.floatsGroupRows = false
    outlineView.usesAutomaticRowHeights = false
    outlineView.rowHeight = 24
    outlineView.intercellSpacing = .zero
    let column = NSTableColumn(
        identifier: SidebarOutlineSourceList.Coordinator.columnIdentifier
    )
    outlineView.addTableColumn(column)
    outlineView.outlineTableColumn = column
    scrollView.documentView = outlineView
    coordinator.attach(outlineView: outlineView, scrollView: scrollView)
    return (scrollView, outlineView)
}
