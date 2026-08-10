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
            "Scholium/Views/BootstrapAgentPreparationView.swift",
            "Scholium/Views/WorkspaceSettingsView.swift",
            "Scholium/Views/ResearchRecord/ResearchRecordProcessingViews.swift",
            "Scholium/Views/Note/TransactionRecoveryView.swift",
        ] {
            let consumer = try source(path)
            #expect(consumer.contains("ScholiumPasteboardWriter.general.writeText("))
            #expect(!consumer.contains("NSPasteboard.general.clearContents()"))
        }
    }

    @Test("Evidence preview disclosure has one presentation owner")
    func evidencePreviewOwnership() throws {
        let browser = try source(
            "Scholium/Views/ResearchRecord/ResearchRecordBrowserView.swift"
        )
        let shared = try slice(
            browser,
            from: "private struct ResearchRecordPreviewedEvidenceSection<",
            until: "private struct ResearchRecordContextUseSection: View {"
        )
        let contextUse = try slice(
            browser,
            from: "private struct ResearchRecordContextUseSection: View {",
            until: "private enum ResearchContextUseDestination {"
        )
        let participants = try slice(
            browser,
            from: "private struct ResearchRecordParticipantSection: View {",
            until: "private struct ResearchRecordStatementSection: View {"
        )

        #expect(shared.contains("@State private var isShowingAll = false"))
        #expect(shared.contains("ScholiumMetrics.ResearchRecords.evidencePreviewLimit"))
        #expect(shared.contains("ResearchRecordEvidenceSectionHeader("))
        #expect(shared.contains(".popover("))
        #expect(shared.contains("completeContent { isShowingAll = false }"))

        for consumer in [contextUse, participants] {
            #expect(consumer.contains("ResearchRecordPreviewedEvidenceSection("))
            #expect(consumer.contains("dismissPopover: dismissPopover"))
            #expect(!consumer.contains("@State private var isShowingAll"))
            #expect(!consumer.contains(".popover("))
        }

        #expect(
            browser.components(
                separatedBy: "@State private var isShowingAll = false"
            ).count == 2
        )
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func slice(
        _ source: String,
        from startMarker: String,
        until endMarker: String
    ) throws -> Substring {
        let start = try #require(source.range(of: startMarker))
        let end = try #require(
            source.range(
                of: endMarker,
                range: start.upperBound..<source.endIndex
            )
        )
        return source[start.lowerBound..<end.lowerBound]
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
