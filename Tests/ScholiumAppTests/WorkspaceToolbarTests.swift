import AppKit
import Testing

@testable import ScholiumApp

@Suite("Workspace toolbar")
@MainActor
struct WorkspaceToolbarTests {
    @Test("The explicit Apparatus boundary does not invoke Inspector auto-discovery")
    func apparatusBoundaryHasOneGeometryOwner() {
        #expect(
            ScholiumWorkspaceToolbarController.Item.apparatusDivider
                != .inspectorTrackingSeparator
        )
    }

    @Test("Records uses Triptych scope when no Document is selected")
    func recordsUsesTriptychScopeWithoutDocument() {
        let presentation = ScholiumWorkspaceResearchRecordsToolbarState.resolve(
            hasTriptych: true,
            hasCurrentNote: false,
            currentNoteIsAvailable: false
        )

        #expect(presentation.scope == .triptych)
        #expect(presentation.title == "Triptych Records")
        #expect(presentation.isEnabled)
    }

    @Test("Records uses an available This Note scope independently of Edit mode")
    func recordsUsesResolvedCurrentNoteScope() {
        let presentation = ScholiumWorkspaceResearchRecordsToolbarState.resolve(
            hasTriptych: true,
            hasCurrentNote: true,
            currentNoteIsAvailable: true
        )

        #expect(presentation.scope == .note)
        #expect(presentation.title == "This Note Records")
        #expect(presentation.isEnabled)
    }

    @Test("A visible Inspector without a Document has an explicit content state")
    func inspectorHasNoDocumentState() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ContentView.swift"
            ),
            encoding: .utf8
        )
        let apparatusStart = try #require(content.range(
            of: "private var apparatusRegion: some View {"
        ))
        let detailStart = try #require(content.range(
            of: "private var detailContent: some View {",
            range: apparatusStart.upperBound..<content.endIndex
        ))
        let apparatus = content[apparatusStart.lowerBound..<detailStart.lowerBound]

        #expect(apparatus.contains("scholium.noDocumentInspectorState"))
        #expect(!apparatus.contains("Color.clear"))
    }
}
