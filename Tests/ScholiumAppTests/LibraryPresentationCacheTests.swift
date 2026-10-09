import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Library presentation reuse")
@MainActor
struct LibraryPresentationCacheTests {
    @Test("Folder ordering reuses unchanged inventory and follows additions and removals")
    func folderOrderingInvalidation() throws {
        let cache = LibraryPresentationCache()
        let folders = try ["Folder-10", "Folder-2"].map(VaultRelativeFolderPath.init)
        let first = cache.orderedFolders(folders)
        #expect(first == ["Folder-2", "Folder-10"])
        #expect(sharesStorage(first, cache.orderedFolders(folders)))
        let equalInventory = try ["Folder-10", "Folder-2"].map(VaultRelativeFolderPath.init)
        #expect(sharesStorage(first, cache.orderedFolders(equalInventory)))

        let added = try folders + [VaultRelativeFolderPath("Folder-1")]
        #expect(cache.orderedFolders(added) == ["Folder-1", "Folder-2", "Folder-10"])
        #expect(cache.orderedFolders(Array(added.suffix(2))) == ["Folder-1", "Folder-2"])
        #expect(cache.orderedFolders([]).isEmpty)
        #expect(cache.orderedFolders(folders) == first)
    }

    @Test("Folder locale changes rebuild ordering while retaining the exact inventory")
    func folderOrderingLocaleInvalidation() throws {
        let cache = LibraryPresentationCache()
        let folders = try ["Folder-10", "Folder-2"].map(VaultRelativeFolderPath.init)
        let first = cache.orderedFolders(folders, localeIdentifier: "en")
        #expect(sharesStorage(first, cache.orderedFolders(folders, localeIdentifier: "en")))
        let revised = cache.orderedFolders(folders, localeIdentifier: "zh")
        #expect(revised == ["Folder-2", "Folder-10"])
        #expect(!sharesStorage(first, revised))
        #expect(sharesStorage(revised, cache.orderedFolders(folders, localeIdentifier: "zh")))
    }

    @Test("Folder ordering rejects canonically equivalent obsolete path spelling")
    func folderOrderingExactPathSpelling() throws {
        let cache = LibraryPresentationCache()
        let composed = "Caf\u{e9}"
        let decomposed = "Cafe\u{301}"
        let first = try ["A", composed].map(VaultRelativeFolderPath.init)
        let renamed = try ["A", decomposed].map(VaultRelativeFolderPath.init)
        #expect(first == renamed)
        _ = cache.orderedFolders(first)
        let current = cache.orderedFolders(renamed)
        #expect(current.count == 2)
        #expect(current.last?.utf8.elementsEqual(decomposed.utf8) == true)
    }

    @Test("Ordering reuse retains exact current metadata and filtered membership")
    func orderingInvalidation() {
        let cache = LibraryPresentationCache()
        let vaultID = UUID()
        let stableID = UUID()
        let first = note(vaultID, stableID, path: "First.md", source: "# First\n", modified: 1)
        let second = note(vaultID, UUID(), path: "Second.md", source: "# Second\n", modified: 2)
        var comparisons = 0
        func ordered(_ notes: [WindowDocumentLocation], sort: NoteSortOrder = .modifiedNewest, locale: String = "en") -> [WindowDocumentLocation] {
            cache.ordered(notes, sortOrder: sort, localeIdentifier: locale) {
                comparisons += 1
                return sort == .modifiedOldest ? $0.fileModifiedAt < $1.fileModifiedAt : $0.fileModifiedAt > $1.fileModifiedAt
            }
        }
        let inputs = [first, second]
        #expect(ordered(inputs) == [second, first])
        let initialComparisons = comparisons
        #expect(initialComparisons > 0)
        for _ in 0..<5 { #expect(ordered(inputs) == [second, first]) }
        #expect(comparisons == initialComparisons)

        let revised = note(vaultID, stableID, path: "First.md", source: "# Revised\n", modified: 3)
        #expect(ordered([revised, second]) == [revised, second])
        #expect(ordered([second]) == [second])
        #expect(ordered([revised, second], sort: .modifiedOldest) == [second, revised])
        let priorLocaleComparisons = comparisons
        #expect(ordered([revised, second], sort: .modifiedOldest, locale: "zh") == [second, revised])
        #expect(comparisons > priorLocaleComparisons)
    }

    @Test("Reused drop inventory rejects changed revision, collisions and unavailable moves")
    func dropInvalidation() throws {
        let cache = LibraryPresentationCache()
        let vaultID = UUID()
        let stableID = UUID()
        let source = note(vaultID, stableID, path: "From/Note.md", source: "# Original\n", modified: 1)
        let item = SidebarNoteDragItem(try #require(NoteMutationTarget(source)))
        let policy = VaultPathComparisonPolicy(caseSensitive: true, normalizationSensitive: true)
        func inventory(
            notes: [WindowDocumentLocation] = [source], folders: [String] = ["From", "To"],
            vault: UUID? = vaultID, canMutate: Bool = true,
            policy: VaultPathComparisonPolicy? = policy, pending: Set<SidebarNoteDragID> = []
        ) -> SidebarTreeDropInventory {
            cache.drop(
                vaultID: vault, sourceScope: .library, role: .sourceCorpus, canMutate: canMutate,
                notes: notes, folders: folders, policy: policy, pendingNotes: pending, pendingFolders: [])
        }
        func destination(_ inventory: SidebarTreeDropInventory) -> String? {
            sidebarValidatedNoteDropDestination(item: item, folderRelativePath: "To", inventory: inventory)
        }
        for _ in 0..<5 { #expect(destination(inventory()) == "To/Note.md") }
        let revised = note(vaultID, stableID, path: source.relativePath, source: "# Changed\n", modified: 2)
        #expect(destination(inventory(notes: [revised])) == nil)
        #expect(destination(inventory(canMutate: false)) == nil)
        #expect(destination(inventory(policy: nil)) == nil)
        #expect(destination(inventory(vault: UUID())) == nil)
        #expect(destination(inventory(pending: [item.id])) == nil)
        #expect(destination(inventory(folders: ["From"])) == nil)
        let occupied = note(vaultID, UUID(), path: "To/note.md", source: "# Occupied\n", modified: 1)
        #expect(destination(inventory(notes: [source, occupied])) == "To/Note.md")
        #expect(destination(inventory(notes: [source, occupied], policy: .init(caseSensitive: false, normalizationSensitive: false))) == nil)
        #expect(destination(inventory()) == "To/Note.md")
    }

    @Test("Canonical Unicode path equivalence cannot retain an obsolete file route")
    func exactPathSpelling() throws {
        let cache = LibraryPresentationCache()
        let treeCache = LibraryTreeProjectionCache()
        let vaultID = UUID()
        let stableID = UUID()
        let composed = "Caf\u{e9}"
        let decomposed = "Cafe\u{301}"
        #expect(composed == decomposed)
        let first = note(vaultID, stableID, path: "\(composed)/Note.md", source: "# Same\n", modified: 1)
        let renamed = note(vaultID, stableID, path: "\(decomposed)/Note.md", source: "# Same\n", modified: 1)
        #expect(first == renamed)
        func ordered(_ note: WindowDocumentLocation) -> WindowDocumentLocation {
            cache.ordered([note], sortOrder: .modifiedNewest, by: { _, _ in false })[0]
        }
        _ = ordered(first)
        #expect(ordered(renamed).relativePath.utf8.elementsEqual(renamed.relativePath.utf8))

        let initialTree = treeCache.projection(preorderedNotes: [first], folderRelativePaths: [composed])
        let currentTree = treeCache.projection(preorderedNotes: [renamed], folderRelativePaths: [decomposed])
        #expect(currentTree.revision == initialTree.revision + 1)
        let folder = try #require(currentTree.value.roots.first)
        #expect(folder.id.utf8.elementsEqual(decomposed.utf8))
        #expect(folder.children.first?.note?.relativePath.utf8.elementsEqual(renamed.relativePath.utf8) == true)

        func drop(_ note: WindowDocumentLocation, folder: String) -> SidebarTreeDropInventory {
            cache.drop(
                vaultID: vaultID, sourceScope: .library, role: .sourceCorpus, canMutate: true,
                notes: [note], folders: [folder], policy: .init(caseSensitive: true, normalizationSensitive: true),
                pendingNotes: [], pendingFolders: [])
        }
        _ = drop(first, folder: composed)
        let currentDrop = drop(renamed, folder: decomposed)
        #expect(currentDrop.notes[0].relativePath.utf8.elementsEqual(renamed.relativePath.utf8))
        #expect(currentDrop.folderRelativePaths.first?.utf8.elementsEqual(decomposed.utf8) == true)
        let emptyCache = LibraryTreeProjectionCache()
        let empty = emptyCache.projection(preorderedNotes: [], folderRelativePaths: [composed])
        let renamedEmpty = emptyCache.projection(preorderedNotes: [], folderRelativePaths: [decomposed])
        #expect(renamedEmpty.revision == empty.revision + 1)
        #expect(renamedEmpty.value.roots.first?.id.utf8.elementsEqual(decomposed.utf8) == true)
    }

    private func sharesStorage(_ lhs: [String], _ rhs: [String]) -> Bool {
        lhs.withUnsafeBufferPointer { left in
            rhs.withUnsafeBufferPointer { right in left.baseAddress == right.baseAddress }
        }
    }

    private func note(_ vaultID: UUID, _ stableID: UUID, path: String, source: String, modified: TimeInterval) -> WindowDocumentLocation {
        let document = NoteDocument(relativePath: path, rawContent: source)
        return .workspace(
            WorkspaceNoteSnapshot(
                id: VaultQualifiedNoteID(vaultID: vaultID, relativePath: path), vaultRole: .sourceCorpus,
                stableIdentity: .resolved(stableID), document: document,
                fileMetadata: WorkspaceFileMetadata(
                    byteCount: document.sourceBytes.count, creationDate: nil, modificationDate: Date(timeIntervalSince1970: modified)),
                graphCounts: WorkspaceGraphCounts(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0)
            ).summary)
    }
}
