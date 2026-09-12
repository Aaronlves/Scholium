import AppKit
import ScholiumContracts
import SwiftUI

extension EnvironmentValues {
    @Entry var openChatNoteInSeparateWindow: ((URL) -> Void)? = nil
}

/// All native Chat note surfaces share the same document-location action.
struct AgentChatNoteMenu: View {
    let url: URL
    @Environment(\.openURL) private var openURL
    @Environment(\.openChatNoteInSeparateWindow) private var openSeparate

    var body: some View {
        if AgentChatReference.parse(url) != nil {
            Button("Open Note") { openURL(url) }
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
