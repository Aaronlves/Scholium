import AppKit
import ScholiumContracts
import SwiftUI

private struct OpenChatNoteInSeparateWindowKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (URL) -> Void)? = nil
}

private struct OpenChatNoteInNewTabKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (URL) -> Void)? = nil
}

extension EnvironmentValues {
    var openChatNoteInNewTab: (@MainActor @Sendable (URL) -> Void)? {
        get { self[OpenChatNoteInNewTabKey.self] }
        set { self[OpenChatNoteInNewTabKey.self] = newValue }
    }

    var openChatNoteInSeparateWindow: (@MainActor @Sendable (URL) -> Void)? {
        get { self[OpenChatNoteInSeparateWindowKey.self] }
        set { self[OpenChatNoteInSeparateWindowKey.self] = newValue }
    }
}

/// All native Chat note surfaces share the same document-location action.
struct AgentChatNoteMenu: View {
    let url: URL
    @Environment(\.openURL) private var openURL
    @Environment(\.openChatNoteInNewTab) private var openNewTab
    @Environment(\.openChatNoteInSeparateWindow) private var openSeparate

    var body: some View {
        if AgentChatReference.parse(url) != nil {
            Button("Open Note") { openURL(url) }
            if let openNewTab {
                Button("Open in New Tab") { openNewTab(url) }
            }
            if let openSeparate {
                Button("Open in Separate Window") { openSeparate(url) }
            }
        }
    }
}

@MainActor
final class AgentChatNoteMenuItem: NSMenuItem {
    private let invoke: () -> Void
    init(_ title: String, invoke: @escaping () -> Void) {
        self.invoke = invoke
        super.init(title: title, action: #selector(performAction), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("Code-only menu item") }
    @objc private func performAction() { invoke() }
}
