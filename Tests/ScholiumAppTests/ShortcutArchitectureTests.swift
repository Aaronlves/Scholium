import Foundation
import Testing

@testable import ScholiumApp

@Suite("Shortcut architecture")
struct ShortcutArchitectureTests {
    @Test("Shortcut policy does not import platform delivery layers")
    func policyHasNoPlatformDeliveryDependencies() throws {
        let source = try read("Scholium/Features/Settings/HotkeyPreferences.swift")

        #expect(!source.contains("import AppKit"))
        #expect(!source.contains("import SwiftUI"))
        #expect(!source.contains("NSEvent"))
        #expect(!source.contains("keyboardShortcut"))
        #expect(source.contains("static func command("))
        #expect(source.contains("for candidate: ScholiumHotkeyBinding"))
    }

    @Test("Event and menu adapters remain one-way delivery boundaries")
    func deliveryAdaptersStaySeparate() throws {
        let eventAdapter = try read("Scholium/App/ScholiumHotkeyEventAdapter.swift")
        let menuAdapter = try read("Scholium/App/ScholiumMenuShortcutModifier.swift")
        let router = try read("Scholium/App/ScholiumCommandKeyEquivalentRouter.swift")
        let documentBoundary = try read("Scholium/Views/Note/DocumentWebViewContainer.swift")
        let editorSurface = try read("Scholium/Views/Note/MarkdownEditorWebView.swift")
        let readerSurface = try read("Scholium/Views/Note/SafeMarkdownReadWebView.swift")
        let settingsView = try read("Scholium/Views/HotkeySettingsView.swift")
        let recorder = try read("Scholium/UI/Components/ScholiumHotkeyRecorder.swift")

        #expect(eventAdapter.contains("import AppKit"))
        #expect(eventAdapter.contains("ScholiumHotkeyPreferences.command(for: binding, defaults: defaults)"))
        #expect(!eventAdapter.contains("keyboardShortcut"))
        #expect(menuAdapter.contains("import SwiftUI"))
        #expect(menuAdapter.contains("content.keyboardShortcut"))
        #expect(!menuAdapter.contains("NSEvent"))
        #expect(router.contains("ScholiumHotkeyEventAdapter.command"))
        #expect(!documentBoundary.contains("ScholiumHotkeyPreferences"))
        #expect(!documentBoundary.contains("ScholiumCommandKeyEquivalentRouter"))
        #expect(!documentBoundary.contains("NSApp.mainMenu"))
        #expect(editorSurface.contains("keyEquivalentRoute: { event in"))
        #expect(readerSurface.contains("keyEquivalentRoute: { event in"))
        #expect(!settingsView.contains("import AppKit"))
        #expect(!settingsView.contains("NSViewRepresentable"))
        #expect(recorder.contains("NSViewRepresentable"))
        #expect(recorder.contains("ScholiumHotkeyEventAdapter.binding"))
    }

    private func read(_ relativePath: String) throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repository.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
