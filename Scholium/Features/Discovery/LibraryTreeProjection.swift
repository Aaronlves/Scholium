import Foundation
import OSLog
import ScholiumContracts

/// One immutable row in the native Library outline. Folder descendants and
/// expandability are cached when the projection is built so row menus and the
/// header disclosure command never rescan the complete tree.
struct TreeNode: Identifiable {
    let id: String
    let name: String
    let isFolder: Bool
    let note: WindowDocumentLocation?
    let folderRelativePath: String?
    let children: [TreeNode]
    let depth: Int
    let folderIDs: Set<String>

    func visibleExpandedFolderIDs(in expandedFolders: Set<String>) -> Set<String> {
        guard isFolder,
              !children.isEmpty,
              expandedFolders.contains(id) else { return [] }
        return children.reduce(into: Set([id])) {
            $0.formUnion($1.visibleExpandedFolderIDs(in: expandedFolders))
        }
    }
}

/// A single category-relative hierarchy projection reused throughout one
/// `SidebarView` value. Building it is linear in notes plus folder ancestors;
/// recursive row construction follows precomputed parent-child adjacency
/// instead of rescanning every folder key at every depth.
struct LibraryTreeProjection {
    let roots: [TreeNode]
    let expandableFolderIDs: Set<String>

#if DEBUG
    private static let diagnosticsLogger = Logger(
        subsystem: "com.scholium.app",
        category: "SidebarProjection"
    )

    private static var diagnosticStartNanoseconds: UInt64? {
        guard ProcessInfo.processInfo.arguments.contains(
            "--scholium-sidebar-projection-diagnostics"
        ) else { return nil }
        return DispatchTime.now().uptimeNanoseconds
    }

    private static func recordDiagnosticBuild(
        noteCount: Int,
        folderCount: Int,
        startNanoseconds: UInt64?
    ) {
        guard let startNanoseconds else { return }
        let elapsedMicroseconds = (
            DispatchTime.now().uptimeNanoseconds - startNanoseconds
        ) / 1_000
        diagnosticsLogger.notice(
            "build notes=\(noteCount, privacy: .public) folders=\(folderCount, privacy: .public) duration_us=\(elapsedMicroseconds, privacy: .public)"
        )
    }
#endif

    init(
        preorderedNotes notes: [WindowDocumentLocation],
        folderRelativePaths folders: [String] = []
    ) {
#if DEBUG
        let diagnosticStartNanoseconds = Self.diagnosticStartNanoseconds
#endif
        var rootNotes: [WindowDocumentLocation] = []
        var notesByFolder: [String: [WindowDocumentLocation]] = [:]
        var childFoldersByParent: [String: Set<String>] = [:]
        var actualFolderPaths: [String: String] = [:]
        var ambiguousFolderPaths: Set<String> = []
        var registeredActualAncestors: Set<String> = []
        var projectedExpandableFolderIDs: Set<String> = []

        func registerFolder(actualPath: String) {
            let visiblePath = libraryCategoryRelativeFolderPath(actualPath)
            guard !visiblePath.isEmpty else { return }
            // A populated Folder is encountered once for every contained Note.
            // Its complete ancestor chain was already registered on the first
            // encounter, so avoid repeating path splitting and reconstruction.
            guard !registeredActualAncestors.contains(actualPath) else { return }
            let visibleParts = visiblePath.split(separator: "/").map(String.init)
            let actualParts = actualPath.split(separator: "/").map(String.init)
            guard actualParts.count >= visibleParts.count else { return }
            let hiddenPrefixCount = actualParts.count - visibleParts.count

            for count in 1...visibleParts.count {
                let visibleAncestor = visibleParts.prefix(count).joined(separator: "/")
                let actualAncestor = actualParts
                    .prefix(hiddenPrefixCount + count)
                    .joined(separator: "/")
                guard registeredActualAncestors.insert(actualAncestor).inserted else {
                    continue
                }
                let parent = count == 1
                    ? ""
                    : visibleParts.prefix(count - 1).joined(separator: "/")
                childFoldersByParent[parent, default: []].insert(visibleAncestor)
                if let existing = actualFolderPaths[visibleAncestor],
                   existing != actualAncestor {
                    ambiguousFolderPaths.insert(visibleAncestor)
                } else {
                    actualFolderPaths[visibleAncestor] = actualAncestor
                }
            }
        }

        folders
            .filter(libraryPathIsVisible)
            .forEach { registerFolder(actualPath: $0) }
        for note in notes where libraryPathIsVisible(note.relativePath) {
            let visibleParts = libraryCategoryRelativeDocumentPath(note.relativePath)
                .split(separator: "/")
                .map(String.init)
            guard visibleParts.count > 1 else {
                rootNotes.append(note)
                continue
            }
            let visibleFolder = visibleParts.dropLast().joined(separator: "/")
            notesByFolder[visibleFolder, default: []].append(note)
            let actualFolder = note.relativePath
                .split(separator: "/")
                .dropLast()
                .joined(separator: "/")
            registerFolder(actualPath: actualFolder)
        }

        func noteNode(_ note: WindowDocumentLocation, depth: Int) -> TreeNode {
            TreeNode(
                id: note.relativePath,
                name: note.displayName,
                isFolder: false,
                note: note,
                folderRelativePath: nil,
                children: [],
                depth: depth,
                folderIDs: []
            )
        }

        func folderName(_ path: String) -> String {
            path.split(separator: "/").last.map(String.init) ?? path
        }

        func foldersAreOrdered(_ left: String, _ right: String) -> Bool {
            let comparison = folderName(left).localizedCaseInsensitiveCompare(
                folderName(right)
            )
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return left.localizedStandardCompare(right) == .orderedAscending
        }

        func buildFolder(path: String, depth: Int) -> TreeNode {
            let folderChildren = (childFoldersByParent[path] ?? [])
                .sorted(by: foldersAreOrdered)
                .map { buildFolder(path: $0, depth: depth + 1) }
            let noteChildren = (notesByFolder[path] ?? [])
                .map { noteNode($0, depth: depth + 1) }
            let children = folderChildren + noteChildren
            let folderIDs = children.reduce(into: Set([path])) {
                $0.formUnion($1.folderIDs)
            }
            if !children.isEmpty {
                projectedExpandableFolderIDs.insert(path)
            }
            return TreeNode(
                id: path,
                name: folderName(path),
                isFolder: true,
                note: nil,
                folderRelativePath: ambiguousFolderPaths.contains(path)
                    ? nil
                    : actualFolderPaths[path],
                children: children,
                depth: depth,
                folderIDs: folderIDs
            )
        }

        let folderRoots = (childFoldersByParent[""] ?? [])
            .sorted(by: foldersAreOrdered)
            .map { buildFolder(path: $0, depth: 0) }
        let noteRoots = rootNotes
            .map { noteNode($0, depth: 0) }
        roots = folderRoots + noteRoots
        expandableFolderIDs = projectedExpandableFolderIDs
#if DEBUG
        Self.recordDiagnosticBuild(
            noteCount: notes.count,
            folderCount: folders.count,
            startNanoseconds: diagnosticStartNanoseconds
        )
#endif
    }

    func visibleNodes(expandedFolders: Set<String>) -> [TreeNode] {
        sidebarVisibleTreeNodes(
            from: roots,
            expandedFolders: expandedFolders
        )
    }

    func visibleNotePaths(expandedFolders: Set<String>) -> [String] {
        visibleNodes(expandedFolders: expandedFolders)
            .compactMap { $0.note?.relativePath }
    }

    func visibleExpandedFolderIDs(
        expandedFolders: Set<String>
    ) -> Set<String> {
        roots.reduce(into: Set<String>()) {
            $0.formUnion($1.visibleExpandedFolderIDs(in: expandedFolders))
        }
    }
}

/// One window-local immutable tree version. Its revision advances only when
/// the ordered Note cohort or Folder inventory changes, so unrelated window
/// publications do not ask AppKit to reconcile the complete outline again.
struct LibraryTreeProjectionVersion {
    let revision: UInt64
    let value: LibraryTreeProjection
}

/// Exact-window memoization for the immutable Library hierarchy. This cache is
/// deliberately outside SwiftUI view identity: a `SidebarView` value may be
/// recreated for document loading, selection, focus, or toolbar state while
/// the underlying Source List remains unchanged.
@MainActor
final class LibraryTreeProjectionCache {
    private struct Input: Equatable {
        let preorderedNotes: [WindowDocumentLocation]
        let folderRelativePaths: [String]
    }

    private var input: Input?
    private var version: LibraryTreeProjectionVersion?
    private var nextRevision: UInt64 = 0

    func projection(
        preorderedNotes: [WindowDocumentLocation],
        folderRelativePaths: [String]
    ) -> LibraryTreeProjectionVersion {
        let requestedInput = Input(
            preorderedNotes: preorderedNotes,
            folderRelativePaths: folderRelativePaths
        )
        if requestedInput == input, let version {
            return version
        }

        nextRevision &+= 1
        let version = LibraryTreeProjectionVersion(
            revision: nextRevision,
            value: LibraryTreeProjection(
                preorderedNotes: preorderedNotes,
                folderRelativePaths: folderRelativePaths
            )
        )
        input = requestedInput
        self.version = version
        return version
    }
}

func libraryCategoryRelativeDocumentPath(_ path: String) -> String {
    return path
}

func libraryCategoryRelativeFolderPath(_ path: String) -> String {
    return path
}

/// App-owned attachment storage remains available to file operations without
/// masquerading as a researcher-authored Library folder or Note hierarchy.
func libraryPathIsVisible(_ path: String) -> Bool {
    path.split(separator: "/", omittingEmptySubsequences: true).first
        != "Attachments"
}

/// Folder row identities that must be disclosed to reveal one exact document
/// path in the Library hierarchy. The document itself is never treated as a
/// folder disclosure target.
func libraryFolderAncestors(forDocumentPath path: String) -> Set<String> {
    let parts = libraryCategoryRelativeDocumentPath(path)
        .split(separator: "/")
        .map(String.init)
    guard parts.count > 1 else { return [] }
    return Set((1..<parts.count).map { count in
        parts.prefix(count).joined(separator: "/")
    })
}

/// Returns the exact visible keyboard and focus order. AppKit owns hierarchy
/// expansion; this projection is intentionally used only for deterministic
/// focus recovery after a mutation.
func sidebarVisibleTreeNodes(
    from roots: [TreeNode],
    expandedFolders: Set<String>
) -> [TreeNode] {
    roots.flatMap { root in
        guard root.isFolder, expandedFolders.contains(root.id) else {
            return [root]
        }
        return [root] + root.children.flatMap {
            sidebarVisibleTreeNodes(from: [$0], expandedFolders: expandedFolders)
        }
    }
}

func buildTree(
    from notes: [WindowDocumentLocation],
    folderRelativePaths folders: [String] = [],
    notesAreOrdered: (WindowDocumentLocation, WindowDocumentLocation) -> Bool
) -> [TreeNode] {
    let preorderedNotes = notes.sorted(by: notesAreOrdered)
    return LibraryTreeProjection(
        preorderedNotes: preorderedNotes,
        folderRelativePaths: folders
    ).roots
}
