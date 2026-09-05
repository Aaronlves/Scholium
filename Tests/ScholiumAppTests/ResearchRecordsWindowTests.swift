import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Research Records window")
@MainActor
struct ResearchRecordsWindowTests {
    @Test("Record navigation starts at the list and Back retains the selected record")
    func sequentialNavigation() throws {
        let triptychID = UUID()
        let model = ResearchRecordsModel(triptychID: triptychID) {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let record = try ResearchRecord(
            triptychID: triptychID,
            question: "What changed in the argument?",
            steps: [ResearchRecordStep(
                submittedBy: ResearchRecordSubmitter(displayName: "Fixture Agent"),
                bodyMarkdown: "Clarified the premise."
            )]
        )
        let revision = ResearchRecordRevision(record: record, fingerprint: .init(content: "fixture"))
        #expect(!model.showsDetail)
        model.select(revision)
        #expect(!model.showsDetail) // Arrow navigation selects without opening.
        model.showRecord(revision)
        #expect(model.showsDetail)
        model.showCollection()
        #expect(!model.showsDetail)
        #expect(model.selectedRecordID == record.id)
        model.open(.init(triptychID: UUID(), sourceWindowID: UUID(), recordID: UUID(), stepID: nil))
        #expect(!model.showsDetail)
        #expect(model.selectedRecordID == record.id)
        model.open(.init(triptychID: triptychID, sourceWindowID: UUID(), recordID: record.id, stepID: record.steps[0].id))
        #expect(model.showsDetail)
        #expect(model.selectedStepID == record.steps[0].id)
    }

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
        #expect(source.contains("if model.showsDetail"))
        #expect(source.contains("model.showCollection()"))
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
            ".defaultSize(width: 560, height: 580)\n"
                + "        .windowStyle(.titleBar)"
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
