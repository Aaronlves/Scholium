import AppKit

/// The explicit lifecycle boundary between the window shell and the native
/// workspace geometry. The split controller registers itself when it enters a
/// window; toolbar code asks this registry for that exact controller instead
/// of searching the rendered view hierarchy or retrying on a timer.
@MainActor
final class ScholiumWorkspaceSplitRegistry {
    static let shared = ScholiumWorkspaceSplitRegistry()
    static let didChangeNotification = Notification.Name(
        "scholium.workspaceSplitRegistry.didChange"
    )

    private final class Entry {
        weak var window: NSWindow?
        weak var splitViewController: NSSplitViewController?

        init(window: NSWindow, splitViewController: NSSplitViewController) {
            self.window = window
            self.splitViewController = splitViewController
        }
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    private init() {}

    func register(_ splitViewController: NSSplitViewController, in window: NSWindow) {
        removeReleasedEntries()
        entries[ObjectIdentifier(window)] = Entry(
            window: window,
            splitViewController: splitViewController
        )
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: window
        )
    }

    func unregister(_ splitViewController: NSSplitViewController, from window: NSWindow?) {
        guard let window else { return }
        let key = ObjectIdentifier(window)
        guard entries[key]?.splitViewController === splitViewController else { return }
        entries.removeValue(forKey: key)
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: window
        )
    }

    func splitView(for window: NSWindow) -> NSSplitView? {
        splitViewController(for: window)?.splitView
    }

    func splitViewController(for window: NSWindow) -> NSSplitViewController? {
        removeReleasedEntries()
        return entries[ObjectIdentifier(window)]?.splitViewController
    }

    private func removeReleasedEntries() {
        entries = entries.filter { _, entry in
            entry.window != nil && entry.splitViewController != nil
        }
    }
}
