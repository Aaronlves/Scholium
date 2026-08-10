import Combine
import Foundation

enum DocumentNavigationDirection: Sendable {
    case back
    case forward
}

/// Window-local owner of the transient document visit sequence. It retains no
/// editor, tab, workspace, split-view, or persistence state; a successful
/// navigation asks `WindowModel` to reactivate the referenced document through
/// the ordinary save-before-transition boundary.
@MainActor
final class DocumentNavigationHistoryController: ObservableObject {
    @Published private var entries: [WindowSelectedDocument] = []
    @Published private var currentIndex: Int?

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
        let targetIndex = switch direction {
        case .back: currentIndex - 1
        case .forward: currentIndex + 1
        }
        guard entries.indices.contains(targetIndex) else { return nil }
        return entries[targetIndex]
    }

    func record(_ document: WindowSelectedDocument) {
        if let currentIndex, entries[currentIndex] == document {
            return
        }
        if let currentIndex, entries.indices.contains(currentIndex + 1) {
            entries.removeSubrange((currentIndex + 1)..<entries.endIndex)
        }
        entries.append(document)
        currentIndex = entries.index(before: entries.endIndex)
    }

    @discardableResult
    func commit(
        _ direction: DocumentNavigationDirection,
        to document: WindowSelectedDocument
    ) -> Bool {
        guard let currentIndex else { return false }
        let targetIndex = switch direction {
        case .back: currentIndex - 1
        case .forward: currentIndex + 1
        }
        guard entries.indices.contains(targetIndex), entries[targetIndex] == document else {
            return false
        }
        self.currentIndex = targetIndex
        return true
    }

    func removeAll() {
        entries = []
        currentIndex = nil
    }
}
