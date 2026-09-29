import AppKit
import SwiftUI

@MainActor
final class ScholiumApplicationDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let windowLifecycleRegistry = ScholiumWindowLifecycleRegistry()

    func applicationWillFinishLaunching(_ notification: Notification) {
        SystemNotificationService.shared.start()
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
        Task { @MainActor in
            do {
                try await windowLifecycleRegistry.flushAll()
                try await ExternalMarkdownWindowRegistry.shared.flushAll()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                windowLifecycleRegistry.endTerminationAttempt()
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}
