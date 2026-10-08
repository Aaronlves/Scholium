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
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationMenuDidSendAction(_:)),
            name: NSMenu.didSendActionNotification, object: nil)
    }

    @objc private func applicationMenuDidSendAction(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
            let item = notification.userInfo?["MenuItem"] as? NSMenuItem
        else { return }
        var root = menu
        while let parent = root.supermenu { root = parent }
        guard root === NSApp.mainMenu else { return }
        _ = synchronizeEditorSelectAll(item, responder: NSApp.keyWindow?.firstResponder)
    }

    /// System text controls keep their selection action. CodeMirror also needs
    /// an authoritative selection update after the native Select All completes.
    @discardableResult
    func synchronizeEditorSelectAll(_ item: NSMenuItem, responder: NSResponder?) -> Bool {
        guard item.action == #selector(NSResponder.selectAll(_:)),
            let editor = focusedMarkdownEditor(for: responder),
            let session = editor.editorSession, session.isReady, session.isLoaded, !session.isComposing
        else { return false }
        editor.performSelectAll(item)
        return true
    }

    func focusedMarkdownEditor(for responder: NSResponder?) -> WindowAttachedWebView? {
        var view = responder as? NSView
        while let candidate = view {
            if let editor = candidate as? WindowAttachedWebView,
                editor.editorSession?.preferredDocumentFocusTarget == .editor
            {
                return editor
            }
            view = candidate.superview
        }
        return nil
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        SystemNotificationService.shared.applicationBecameActive()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !windowLifecycleRegistry.isTerminationAttemptInProgress else { return .terminateLater }
        windowLifecycleRegistry.beginTerminationAttempt()
        markdownFiles.prepareTermination()
        Task { @MainActor in
            let outcome = await prepareApplicationTermination()
            sender.reply(toApplicationShouldTerminate: outcome == .ready)
            if outcome == .citationPending {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = ScholiumL10n.string("Citation Operation in Progress")
                alert.informativeText = ScholiumL10n.string("Finish or cancel the open Zotero dialog before quitting Scholium.")
                if let window = sender.keyWindow {
                    await alert.beginSheetModal(for: window)
                } else {
                    alert.runModal()
                }
            }
        }
        return .terminateLater
    }

    enum TerminationPreparation {
        case ready, citationPending, failed
    }

    /// The adapter owns admission even when its originating window has closed.
    /// Acquire it before flushing editors, which can revoke citation authority.
    func prepareApplicationTermination(
        citations: CitationTerminationCapabilities = WorkspaceStore.citationTermination
    ) async -> TerminationPreparation {
        guard await citations.begin() else {
            windowLifecycleRegistry.endTerminationAttempt()
            markdownFiles.cancelTermination()
            return .citationPending
        }
        do {
            try await windowLifecycleRegistry.flushAll()
            try await ExternalMarkdownWindowRegistry.shared.flushAll()
            return .ready
        } catch {
            await citations.cancel()
            windowLifecycleRegistry.endTerminationAttempt()
            markdownFiles.cancelTermination()
            return .failed
        }
    }
}
