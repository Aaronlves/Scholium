import Foundation
import ScholiumContracts

/// The library's visible ordering: which documents the researcher's active
/// filters admit, and the order they read in.
extension WindowModel {
    var filteredNotes: [WindowDocumentLocation] {
        var result = notes
        if isNeedsAttentionFilter, let paths = currentAttentionPaths {
            result = result.filter { paths.contains($0.relativePath) }
        }
        if isLinkAnnotationsFilter, let paths = currentLinkAnnotationPaths {
            result = result.filter { paths.contains($0.relativePath) }
        }
        if isMalformedMetadataFilter, let paths = currentMalformedMetadataPaths {
            result = result.filter { paths.contains($0.relativePath) }
        }
        if let tag = selectedTag { result = result.filter { $0.tags.contains(tag) } }
        if let author = selectedAuthor { result = result.filter { $0.authors.contains(author) } }
        if let key = selectedPropertyKey, let value = selectedPropertyValue {
            result = result.filter {
                $0.filterableProperties()[key]?.contains(value) == true
            }
        }
        return result.sorted(by: notesAreOrdered)
    }

    private var currentAttentionPaths: Set<String>? {
        guard let vaultID = currentRegisteredVault?.id,
            let workspaceCatalog
        else { return nil }
        return Set(
            workspaceCatalog.attention.compactMap { item in
                item.note.vaultID == vaultID ? item.note.relativePath : nil
            })
    }

    private var currentMalformedMetadataPaths: Set<String>? {
        guard let vaultID = currentRegisteredVault?.id,
            let workspaceCatalog
        else { return nil }
        return Set(
            workspaceCatalog.notes.compactMap { catalogNote in
                guard catalogNote.reference.vaultID == vaultID,
                    !catalogNote.validationWarnings.isEmpty
                else { return nil }
                return catalogNote.reference.relativePath
            })
    }

    private var currentLinkAnnotationPaths: Set<String>? {
        guard let vaultID = currentRegisteredVault?.id,
            let graph = linkGraph
        else { return nil }
        return Set(
            notes.compactMap { note in
                let noteID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: note.relativePath)
                let edges = (graph.outgoing[noteID] ?? []) + (graph.incoming[noteID] ?? [])
                let hasLinkAnnotation = edges.contains { $0.occurrence.annotation != nil }
                return hasLinkAnnotation ? note.relativePath : nil
            })
    }

    func notesAreOrdered(_ lhs: WindowDocumentLocation, _ rhs: WindowDocumentLocation) -> Bool {
        switch discoveryController.library.sortOrder {
        case .modifiedNewest:
            if lhs.fileModifiedAt != rhs.fileModifiedAt { return lhs.fileModifiedAt > rhs.fileModifiedAt }
        case .modifiedOldest:
            if lhs.fileModifiedAt != rhs.fileModifiedAt { return lhs.fileModifiedAt < rhs.fileModifiedAt }
        case .titleAscending:
            return lhs.displayName.localizedStandardCompare(
                rhs.displayName
            ) == .orderedAscending
        case .titleDescending:
            return lhs.displayName.localizedStandardCompare(
                rhs.displayName
            ) == .orderedDescending
        }
        return lhs.displayName.localizedStandardCompare(
            rhs.displayName
        ) == .orderedAscending
    }

    var availableAuthors: [String] {
        workspaceProjectionController.authors
    }

    func clearMetadataFilters() {
        selectedAuthor = nil
        selectedPropertyKey = nil
        selectedPropertyValue = nil
    }
}
