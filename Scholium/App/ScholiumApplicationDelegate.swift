import AppKit
import SwiftUI

@MainActor
final class ScholiumApplicationDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let windowLifecycleRegistry = ScholiumWindowLifecycleRegistry()
    let markdownFiles = MarkdownFileOpeningController()

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !windowLifecycleRegistry.isTerminationAttemptInProgress else { return }
        markdownFiles.requestOpen(urls)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        SystemNotificationService.shared.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        markdownFiles.finishLaunching()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        SystemNotificationService.shared.applicationBecameActive()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !windowLifecycleRegistry.isTerminationAttemptInProgress else { return .terminateLater }
        guard
            windowLifecycleRegistry.hasRegisteredWindows
                || ExternalMarkdownWindowRegistry.shared.hasOpenWindows
        else {
            return .terminateNow
        }
        windowLifecycleRegistry.beginTerminationAttempt()
        markdownFiles.prepareTermination()
        Task { @MainActor in
            do {
                try await windowLifecycleRegistry.flushAll()
                try await ExternalMarkdownWindowRegistry.shared.flushAll()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                windowLifecycleRegistry.endTerminationAttempt()
                markdownFiles.cancelTermination()
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}
