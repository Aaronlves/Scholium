import Foundation
import ScholiumContracts
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

    @Test("Record route identity is one window per originating workspace")
    func routeIdentityUsesTriptychAndSourceWindow() {
        let triptychID = UUID()
        let sourceWindowID = UUID()
        #expect(ResearchRecordsWindowRoute(
            triptychID: triptychID,
            sourceWindowID: sourceWindowID
        ) == ResearchRecordsWindowRoute(
            triptychID: triptychID,
            sourceWindowID: sourceWindowID
        ))
        #expect(ResearchRecordsWindowRoute(
            triptychID: triptychID,
            sourceWindowID: sourceWindowID
        ) != ResearchRecordsWindowRoute(
            triptychID: UUID(),
            sourceWindowID: sourceWindowID
        ))
        #expect(ResearchRecordsWindowRoute(
            triptychID: triptychID,
            sourceWindowID: sourceWindowID
        ) != ResearchRecordsWindowRoute(
            triptychID: triptychID,
            sourceWindowID: UUID()
        ))
    }

    @Test("A Record attachment routes only to its exact source workspace")
    func attachmentRoutesToExistingSourceWorkspace() {
        let coordinator = ResearchRecordsWindowCoordinator.shared
        let sourceWindowID = UUID()
        let otherWindowID = UUID()
        let reference = VaultNoteReference(
            vaultID: UUID(),
            vaultName: "Fixture Topics",
            vaultRole: .topicKnowledge,
            relativePath: "Topics/Agency.md",
            stableNoteID: UUID().uuidString.lowercased()
        )
        var openedReference: VaultNoteReference?
        let token = coordinator.registerWorkspace(windowID: sourceWindowID) {
            openedReference = $0
        }
        defer {
            coordinator.unregisterWorkspace(windowID: sourceWindowID, token: token)
        }

        #expect(!coordinator.openReference(reference, in: otherWindowID))
        #expect(openedReference == nil)
        #expect(coordinator.openReference(reference, in: sourceWindowID))
        #expect(openedReference == reference)
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
        let sceneSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        #expect(source.contains("Search records"))
        #expect(source.contains("ResearchRecordsSearchField"))
        #expect(source.contains(".frame(width: ScholiumMetrics.ResearchRecords.collectionWidth)"))
        #expect(source.contains("noteReferences(step)"))
        #expect(source.contains("openEvidence(item)"))
        #expect(source.contains("openReference("))
        #expect(source.contains("ScrollView(.horizontal)"))
        #expect(source.contains("LazyHStack"))
        #expect(source.contains(".scrollIndicators(.hidden)"))
        #expect(source.contains(".scrollBounceBehavior(.basedOnSize, axes: .horizontal)"))
        #expect(source.contains(".buttonStyle(.bordered)"))
        #expect(source.contains(".onExitCommand { dismissWindow() }"))
        #expect(source.contains("dismissWindow()"))
        #expect(sceneSource.contains(
            ".defaultSize(width: 980, height: 720)\n"
                + "        .windowStyle(.hiddenTitleBar)"
        ))
        #expect(source.contains(".tint(ScholiumColorRole.accent.color)"))
        #expect(source.contains("ScholiumContentStateView"))
        #expect(source.contains("ScholiumStructuralRule"))
        #expect(source.contains("ScholiumContentControlButtonStyle"))
        #expect(source.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
        #expect(source.contains("ScholiumMetrics.ResearchRecords"))
        #expect(!source.contains("NavigationSplitView"))
        #expect(!source.contains(".searchable("))
        #expect(!source.contains("Previous Record"))
        #expect(!source.contains("Next Record"))
        #expect(!source.contains("Refresh Records"))
        #expect(!source.contains("ResearchRecordsToolbar"))
        #expect(!source.contains(".toolbar {"))
        #expect(!source.contains(".toolbarBackgroundVisibility"))
        #expect(!source.contains(".overlay(alignment: .leading)"))
        #expect(!source.contains("id: \"scholium-main\""))
        #expect(!source.contains("HSplitView"))
        #expect(!source.contains(".inspector(isPresented:"))
        #expect(!source.contains("List(selection:"))
        #expect(!source.contains("ContentUnavailableView"))
        #expect(!source.contains("chevron.forward"))
        #expect(!source.contains("referenced"))
        #expect(!source.contains("TextEditor"))
        #expect(!source.contains("Save Record"))
        #expect(!source.contains("Delete Record"))
    }
}
