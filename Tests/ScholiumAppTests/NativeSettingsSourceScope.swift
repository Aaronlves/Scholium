import Foundation
import Testing

/// Settings is a system-owned presentation boundary, separate from Document ink.
enum NativeSettingsSourceScope {
    static let paths: Set<String> = [
        "Scholium/UI/Foundation/ScholiumSettingsPresentation.swift",
        "Scholium/Views/WorkspaceSettingsView.swift",
        "Scholium/Views/HotkeySettingsView.swift",
        "Scholium/Views/SelectionActionsSettingsView.swift",
        "Scholium/Views/AgentIntegrationSettingsView.swift",
        "Scholium/Views/AgentChatConnectionSettingsView.swift",
        "Scholium/Views/AgentChatCapabilitiesSettingsView.swift",
        "Scholium/Views/AgentChatToolEditor.swift",
        "Scholium/Features/Settings/AgentChatInputBehavior.swift",
    ]

    @Test("Settings uses system typography, colors and control styles")
    static func nativeSettingsPresentation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for path in paths {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            for productStyle in [
                "ScholiumTypography", ".scholiumForeground(",
                ".scholiumButtonStyle(", ".scholiumMenuStyle(",
            ] {
                #expect(!source.contains(productStyle), "\(path) overrides native Settings presentation")
            }
        }
    }
}
