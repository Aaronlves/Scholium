import AppKit
import SwiftUI

@MainActor
final class ScholiumApplicationDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let windowLifecycleRegistry = ScholiumWindowLifecycleRegistry()
    private var terminationInFlight = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        SystemNotificationService.shared.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        SystemNotificationService.shared.applicationBecameActive()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard windowLifecycleRegistry.hasRegisteredWindows else {
            return .terminateNow
        }
        guard !terminationInFlight else { return .terminateLater }
        terminationInFlight = true
        Task { @MainActor in
            do {
                try await windowLifecycleRegistry.flushAll()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                terminationInFlight = false
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}
