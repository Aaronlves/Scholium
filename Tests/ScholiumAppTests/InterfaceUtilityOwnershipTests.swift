import AppKit
import Foundation
import Testing
@testable import ScholiumApp

@Suite("Interface utility ownership")
@MainActor
struct InterfaceUtilityOwnershipTests {
    @Test("Plain-text writing replaces the pasteboard exactly")
    func pasteboardWriterReplacesContents() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name(
                "com.scholium.tests.pasteboard.\(UUID().uuidString)"
            )
        )
        pasteboard.clearContents()
        #expect(pasteboard.setString("<p>old</p>", forType: .html))

        let writer = ScholiumPasteboardWriter(pasteboard: pasteboard)
        #expect(writer.writeText("exact candidate bytes"))
        #expect(pasteboard.string(forType: .string) == "exact candidate bytes")
        #expect(pasteboard.string(forType: .html) == nil)

        pasteboard.clearContents()
    }

    @Test("Copy workflows share one native writing boundary")
    func copyWorkflowOwnership() throws {
        let writer = try source("Scholium/UI/Components/ScholiumPasteboardWriting.swift")
        #expect(writer.contains("protocol PasteboardWriting"))
        #expect(writer.contains("pasteboard.clearContents()"))
        #expect(writer.contains("pasteboard.setString(text, forType: .string)"))

        for path in [
            "Scholium/App/ScholiumApp.swift",
            "Scholium/Views/AgentIntegrationSettingsView.swift",
            "Scholium/Views/Note/TransactionRecoveryView.swift",
        ] {
            let consumer = try source(path)
            #expect(consumer.contains("ScholiumPasteboardWriter.general.writeText("))
            #expect(!consumer.contains("NSPasteboard.general.clearContents()"))
        }
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
