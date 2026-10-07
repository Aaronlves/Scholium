import Combine
import Foundation
import ScholiumContracts

enum DocumentNavigationDirection: Sendable {
    case back
    case forward
}

struct DocumentNavigationVisitPosition: Equatable, Sendable {
    let sourceFingerprint: String
    let scrollPosition: ObservedScrollPosition
}

/// Window-local owner of the transient document visit sequence. It retains no
/// editor, tab, workspace, split-view, or persistence state; a successful
/// navigation asks `WindowModel` to reactivate the referenced document through
/// the ordinary save-before-transition boundary.
@MainActor
final class DocumentNavigationHistoryController: ObservableObject {
    private struct Visit: Equatable {
        var document: WindowSelectedDocument
        var position: DocumentNavigationVisitPosition?
    }
    @Published private var entries: [Visit] = []
    @Published private var currentIndex: Int?
    private(set) var revision: UInt64 = 0

    var canGoBack: Bool {
        guard let currentIndex else { return false }
        return currentIndex > entries.startIndex
    }

    var canGoForward: Bool {
        guard let currentIndex else { return false }
        return entries.indices.contains(currentIndex + 1)
    }

    var count: Int { entries.count }

    func target(for direction: DocumentNavigationDirection) -> WindowSelectedDocument? {
        guard let currentIndex else { return nil }
        let targetIndex =
            switch direction {
            case .back: currentIndex - 1
            case .forward: currentIndex + 1
            }
        guard entries.indices.contains(targetIndex) else { return nil }
        return entries[targetIndex].document
    }

    func position(for direction: DocumentNavigationDirection) -> DocumentNavigationVisitPosition? {
        guard let currentIndex else { return nil }
        let targetIndex =
            switch direction {
            case .back: currentIndex - 1
            case .forward: currentIndex + 1
            }
        guard entries.indices.contains(targetIndex) else { return nil }
        return entries[targetIndex].position
    }

    var currentDocument: WindowSelectedDocument? {
        currentIndex.map { entries[$0].document }
    }

    func captureCurrent(
        document: WindowSelectedDocument,
        position: DocumentNavigationVisitPosition?
    ) {
        guard let currentIndex,
            entries[currentIndex].document.editingTarget == document.editingTarget,
            let position
        else { return }
        entries[currentIndex].document = document
        entries[currentIndex].position = position
    }

    func record(_ document: WindowSelectedDocument) {
        if let currentIndex,
            entries[currentIndex].document.editingTarget == document.editingTarget
        {
            entries[currentIndex].document = document
            return
        }
        if let currentIndex, entries.indices.contains(currentIndex + 1) {
            entries.removeSubrange((currentIndex + 1)..<entries.endIndex)
        }
        entries.append(Visit(document: document, position: nil))
        currentIndex = entries.index(before: entries.endIndex)
        revision &+= 1
    }

    @discardableResult
    func commit(
        _ direction: DocumentNavigationDirection,
        to document: WindowSelectedDocument
    ) -> Bool {
        guard let currentIndex else { return false }
        let targetIndex =
            switch direction {
            case .back: currentIndex - 1
            case .forward: currentIndex + 1
            }
        guard entries.indices.contains(targetIndex),
            entries[targetIndex].document.editingTarget == document.editingTarget
        else {
            return false
        }
        entries[targetIndex].document = document
        self.currentIndex = targetIndex
        revision &+= 1
        return true
    }

    func removeAll() {
        entries = []
        currentIndex = nil
        revision &+= 1
    }

    /// Visits retain return positions, while their location follows the same
    /// stable Note identity as open tabs. A reused path cannot claim a visit.
    func migratePath(from source: String, to destination: String, key: DocumentSessionKey) {
        var changed = false
        for index in entries.indices {
            guard let descriptor = entries[index].document.workspaceDescriptor,
                descriptor.sessionKey == key,
                descriptor.reference.relativePath == source
            else { continue }
            entries[index].document = relocated(descriptor, to: destination)
            changed = true
        }
        if changed { revision &+= 1 }
    }

    func receive(_ snapshot: WorkspaceSnapshot) {
        var changed = false
        for index in entries.indices {
            guard let descriptor = entries[index].document.workspaceDescriptor,
                let note = snapshot.vault(id: descriptor.sessionKey.vaultID)?.documents.first(where: {
                    $0.stableIdentity.resolvedID == descriptor.sessionKey.noteID
                }), note.id.relativePath != descriptor.reference.relativePath
            else { continue }
            entries[index].document = relocated(descriptor, to: note.id.relativePath)
            changed = true
        }
        if changed { revision &+= 1 }
    }

    private func relocated(_ descriptor: WindowDocumentDescriptor, to path: String) -> WindowSelectedDocument {
        .workspace(
            .init(
                sessionKey: descriptor.sessionKey,
                reference: .init(
                    vaultID: descriptor.reference.vaultID,
                    vaultName: descriptor.reference.vaultName,
                    vaultRole: descriptor.reference.vaultRole,
                    relativePath: path,
                    stableNoteID: descriptor.reference.stableNoteID
                )
            ))
    }
}
