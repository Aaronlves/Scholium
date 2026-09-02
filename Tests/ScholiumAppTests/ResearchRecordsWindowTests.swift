import Foundation
import Testing
@testable import ScholiumApp

@Suite("Research Records window")
@MainActor
struct ResearchRecordsWindowTests {
    @Test("Basic Markdown projects while headings and unsupported structures stay literal")
    func boundedMarkdownProjection() {
        let projection = ResearchRecordMarkdownProjection("""
        A **strong** paragraph with [a link](https://example.com).

        - First
        2. Second
        > Quoted
        # Literal heading
        ![Literal image](image.png)
        ```
        **literal code**
        ```
        """)

        #expect(projection.blocks.map(\.kind) == [
            .paragraph,
            .unordered,
            .ordered(2),
            .quote,
            .literal,
            .literal,
            .literal,
            .literal,
            .literal,
        ])
        #expect(projection.blocks[0].text.contains("**strong**"))
        #expect(projection.blocks[4].text == "# Literal heading")
        #expect(projection.blocks[5].text == "![Literal image](image.png)")
        #expect(projection.blocks[7].text == "**literal code**")
    }

    @Test("Record route identity is one window per Triptych")
    func routeIdentityUsesTriptych() {
        let triptychID = UUID()
        #expect(ResearchRecordsWindowRoute(triptychID: triptychID)
            == ResearchRecordsWindowRoute(triptychID: triptychID))
        #expect(ResearchRecordsWindowRoute(triptychID: triptychID)
            != ResearchRecordsWindowRoute(triptychID: UUID()))
    }

    @Test("The Records surface follows the quiet read-only editorial pattern")
    func surfaceIsReadOnlyAndStructurallyContinuous() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/ResearchRecord/ResearchRecordsWindow.swift"
            ),
            encoding: .utf8
        )
        #expect(source.contains("Search records"))
        #expect(source.contains("NavigationSplitView"))
        #expect(source.contains(".searchable("))
        #expect(source.contains("noteReferences(step)"))
        #expect(source.contains("openEvidence(item)"))
        #expect(source.contains(".buttonStyle(.bordered)"))
        #expect(source.contains("ScholiumNativeToolbarButton"))
        #expect(source.contains("Previous Record"))
        #expect(source.contains("Next Record"))
        #expect(source.contains("Refresh Records"))
        #expect(source.contains(".toolbarBackgroundVisibility(.hidden"))
        #expect(source.contains(".tint(ScholiumColorRole.accent.color)"))
        #expect(source.contains("ScholiumContentStateView"))
        #expect(source.contains("ScholiumStructuralRule"))
        #expect(source.contains("ScholiumContentControlButtonStyle"))
        #expect(source.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
        #expect(source.contains("ScholiumMetrics.ResearchRecords"))
        #expect(!source.contains("HSplitView"))
        #expect(!source.contains(".inspector(isPresented:"))
        #expect(!source.contains("List(selection:"))
        #expect(!source.contains("ContentUnavailableView"))
        #expect(!source.contains("TextField(\"Search records\""))
        #expect(!source.contains("chevron.forward"))
        #expect(!source.contains("referenced"))
        #expect(!source.contains("TextEditor"))
        #expect(!source.contains("Save Record"))
        #expect(!source.contains("Delete Record"))
    }
}
