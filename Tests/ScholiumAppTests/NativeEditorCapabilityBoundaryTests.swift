import AppKit
import Foundation
import Testing

@testable import ScholiumEditor

@MainActor
@Suite("Native editor capability boundary", .serialized)
struct NativeEditorCapabilityBoundaryTests {
    init() { _ = NSApplication.shared }

    @Test("Authored URLs are inert during rendering and only dispatched by explicit activation")
    func authoredDestinationsDoNotAcquireCapabilities() throws {
        let destinations = [
            "https://example.invalid/image.png", "file:///private/secret.png",
            "../../outside.png", "~/private.png", "data:image/png;base64,AAAA",
            "javascript:alert(1)",
        ]
        let source = "\u{FEFF}" + destinations.map { "![image](\($0))" }.joined(separator: "\r\n\r\n")
        let editor = EditorTextView.makeTextKit2(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            containerSize: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        var activated: [String] = []
        editor.onLinkActivation = { activated.append($0) }
        try editor.loadExactUTF8(Data(source.utf8))
        editor.viewMode = .reading
        editor.textLayoutManager?.ensureLayout(for: editor.textLayoutManager!.documentRange)
        #expect(activated.isEmpty)
        #expect(try editor.exactUTF8ForSaving() == Data(source.utf8))
        for destination in destinations {
            #expect(editor.imageOverlay(destination: destination) != nil)
            editor.followLinkDestination(destination)
        }
        #expect(activated == destinations)
        editor.onLinkActivation = nil
        editor.followWikiLink("../../outside#heading")
        #expect(try editor.exactUTF8ForSaving() == Data(source.utf8))
    }

    @Test("Renderer module exposes no document filesystem, network, or launch machinery")
    func rendererHasNoAmbientCapabilities() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ScholiumEditor")
        let files = try #require(
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey]))
        let forbidden = [
            "URLSession", "NSWorkspace", "NSDocumentController", "NSOpenPanel",
            "NSSavePanel", "Process()", "FileManager", "FileHandle", "startAccessingSecurityScopedResource",
            "NSImage(contentsOf:", "String(contentsOf:", "write(to:",
        ]
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for capability in forbidden {
                #expect(!source.contains(capability), "\(url.lastPathComponent) contains \(capability)")
            }
            if source.contains("Data(contentsOf:") {
                #expect(["ThemeStore.swift", "SyntaxDefinitionStore.swift"].contains(url.lastPathComponent))
                #expect(source.contains("Bundle.module.urls"))
            }
        }
    }
}
