import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Search state presentation")
struct SearchStatePresentationTests {
    private let noteGeneration = SearchGenerationID(
        triptychID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        sequence: 1,
        sourceManifestHash: "notes"
    )
    private let recordGeneration = RecordSearchGenerationID(
        triptychID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        sourceManifestHash: "records"
    )

    @Test("Note Search maps every non-current availability explicitly")
    func noteAvailabilityMapping() throws {
        let unavailable = try #require(SearchStatePresentation.note(.unavailable))
        let building = try #require(SearchStatePresentation.note(
            .building(SearchBuildProgress(completed: 1, total: 3))
        ))
        let refreshing = try #require(SearchStatePresentation.note(
            .refreshing(lastGood: noteGeneration)
        ))
        let stale = try #require(SearchStatePresentation.note(
            .stale(lastGood: noteGeneration, reason: "changed")
        ))
        let failed = try #require(SearchStatePresentation.note(
            .failed(lastGood: nil, reason: "broken")
        ))

        #expect(unavailable.meaning == .unavailable)
        #expect(unavailable.action == .refresh)
        #expect(building.meaning == .loading)
        #expect(building.action == nil)
        #expect(refreshing.meaning == .loading)
        #expect(stale.meaning == .stale)
        #expect(stale.action == .refresh)
        #expect(failed.meaning == .error)
        #expect(failed.action == .retry)
        #expect(SearchStatePresentation.note(.current(noteGeneration)) == nil)
    }

    @Test("Research Record stale and failed states remain distinct and provider-specific")
    func recordAvailabilityMapping() throws {
        let unavailable = try #require(SearchStatePresentation.record(.unavailable))
        let building = try #require(SearchStatePresentation.record(
            .building(SearchBuildProgress(completed: 0, total: 0))
        ))
        let refreshing = try #require(SearchStatePresentation.record(
            .refreshing(lastGood: recordGeneration)
        ))
        let stale = try #require(SearchStatePresentation.record(
            .stale(lastGood: recordGeneration, reason: "changed")
        ))
        let failed = try #require(SearchStatePresentation.record(
            .failed(lastGood: nil, reason: "broken")
        ))

        #expect(unavailable.meaning == .unavailable)
        #expect(unavailable.action == .refresh)
        #expect(building.meaning == .loading)
        #expect(refreshing.meaning == .loading)
        #expect(stale.meaning == .stale)
        #expect(stale.action == .refresh)
        #expect(failed.meaning == .error)
        #expect(failed.action == .retry)
        #expect(stale.title != failed.title)
        #expect(stale.message != failed.message)
        #expect(unavailable.title != stale.title)
        #expect(SearchStatePresentation.record(.current(recordGeneration)) == nil)
    }

    @Test("Completed zero-match searches retain No Results while unexplained projections do not")
    func noMatchPresentationBoundary() throws {
        #expect(!SearchStatePresentation.suppressesNoMatchContent(
            for: .note(.current(noteGeneration)),
            scope: .triptych,
            hasExecutionIssue: false
        ))
        #expect(!SearchStatePresentation.suppressesNoMatchContent(
            for: .record(.current(recordGeneration)),
            scope: .triptych,
            hasExecutionIssue: false
        ))
        #expect(SearchStatePresentation.suppressesNoMatchContent(
            for: .note(.unavailable),
            scope: .triptych,
            hasExecutionIssue: false
        ))
        #expect(SearchStatePresentation.suppressesNoMatchContent(
            for: .record(.failed(lastGood: nil, reason: "broken")),
            scope: .triptych,
            hasExecutionIssue: false
        ))
        #expect(!SearchStatePresentation.suppressesNoMatchContent(
            for: .note(.stale(lastGood: noteGeneration, reason: "changed")),
            scope: .triptych,
            hasExecutionIssue: false
        ))
        #expect(!SearchStatePresentation.suppressesNoMatchContent(
            for: .note(.unavailable),
            scope: .thisNote,
            hasExecutionIssue: false
        ))
        #expect(SearchStatePresentation.suppressesNoMatchContent(
            for: .note(.current(noteGeneration)),
            scope: .thisNote,
            hasExecutionIssue: true
        ))

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Views/SearchWorkspaceView.swift"
            ),
            encoding: .utf8
        )
        #expect(source.contains(
            "ContentUnavailableView.search(text: controller.search.criteria.query)"
        ))
    }

    @Test("Execution prerequisites remain unavailable while operation failures can retry")
    func executionIssueMapping() {
        let unavailable = SearchStatePresentation.executionIssue(
            .unavailable("Open a complete Triptych before searching.")
        )
        let failed = SearchStatePresentation.executionIssue(.failed("Database read failed."))

        #expect(unavailable.meaning == .unavailable)
        #expect(unavailable.action == nil)
        #expect(failed.meaning == .error)
        #expect(failed.action == .retry)
        #expect(unavailable.title != failed.title)
    }

    @Test("Search presentation uses semantic state Tokens")
    func semanticStateTokens() {
        #expect(SearchStatePresentationMeaning.loading.colorRole.rawValue == "information")
        #expect(SearchStatePresentationMeaning.unavailable.colorRole.rawValue == "attention")
        #expect(SearchStatePresentationMeaning.stale.colorRole.rawValue == "attention")
        #expect(SearchStatePresentationMeaning.error.colorRole.rawValue == "destructive")
    }
}
