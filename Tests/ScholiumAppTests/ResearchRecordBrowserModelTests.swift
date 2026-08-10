import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp
@testable import ScholiumResearchRecordsFeature

@MainActor
private final class ResearchRecordSearchProbe {
    var requests: [SearchRequest] = []
    let handler: @MainActor @Sendable (SearchRequest) async throws -> SearchResponse

    init(
        handler:
            @escaping @MainActor @Sendable (
                SearchRequest
            ) async throws -> SearchResponse
    ) {
        self.handler = handler
    }

    func search(_ request: SearchRequest) async throws -> SearchResponse {
        requests.append(request)
        return try await handler(request)
    }
}

@MainActor
private final class ResearchRecordProviderState {
    var records: [PortableResearchRecord]

    init(records: [PortableResearchRecord]) {
        self.records = records
    }
}

@Suite("Research Record browser")
@MainActor
struct ResearchRecordBrowserModelTests {
    @Test("Review-result routing grants direct undo only to the exact live window")
    func reviewResultRoutingOwnsTransientDirectUndoEligibility() throws {
        let record = try makeChangedAction(
            id: deterministicUUID(31),
            noteID: deterministicUUID(32),
            title: "Changed Analysis"
        )
        let resultFingerprint = try record.finalizedResultFingerprint()
        let secondRecord = try makeChangedAction(
            id: deterministicUUID(33),
            noteID: deterministicUUID(34),
            title: "Second Changed Analysis"
        )
        let secondResultFingerprint = try secondRecord.finalizedResultFingerprint()
        let recordFingerprint = DocumentFingerprint(content: "portable record bytes")

        let reviewModel = ResearchRecordBrowserModel()
        reviewModel.prepareForOpen(
            triptychID: record.triptychID,
            records: [record, secondRecord],
            fingerprints: [record.id: recordFingerprint],
            request: ResearchRecordsWindowRequest(
                triptychID: record.triptychID,
                purpose: .reviewResult,
                recordID: record.id,
                expectedFinalizedResultFingerprint: resultFingerprint
            )
        )
        #expect(reviewModel.selectedRecord?.id == record.id)
        #expect(reviewModel.hasDirectUndoEligibility(for: record))

        reviewModel.apply(ResearchRecordsWindowRequest(
            triptychID: secondRecord.triptychID,
            purpose: .reviewResult,
            recordID: secondRecord.id,
            expectedFinalizedResultFingerprint: secondResultFingerprint
        ))
        #expect(reviewModel.selectedRecord?.id == secondRecord.id)
        #expect(reviewModel.hasDirectUndoEligibility(for: record))
        #expect(reviewModel.hasDirectUndoEligibility(for: secondRecord))

        let kept = try replacingReviewDisposition(
            in: record,
            with: try PortableResearcherReviewDisposition(reviewedChanges: [
                try PortableResearcherReviewedChange(
                    noteID: record.confirmedChanges[0].noteID,
                    outcome: .keptAgentRevision,
                    observedRevision: record.confirmedChanges[0].endingRevision
                )
            ])
        )
        reviewModel.acceptUpdatedRecord(kept)
        #expect(reviewModel.hasDirectUndoEligibility(for: kept))

        let browseModel = ResearchRecordBrowserModel()
        browseModel.prepareForOpen(
            triptychID: record.triptychID,
            records: [record],
            fingerprints: [record.id: recordFingerprint],
            request: ResearchRecordsWindowRequest(
                triptychID: record.triptychID,
                recordID: record.id,
                expectedRecordFingerprint: recordFingerprint
            )
        )
        #expect(!browseModel.hasDirectUndoEligibility(for: record))

        let staleModel = ResearchRecordBrowserModel()
        staleModel.prepareForOpen(
            triptychID: record.triptychID,
            records: [record],
            fingerprints: [record.id: recordFingerprint],
            request: ResearchRecordsWindowRequest(
                triptychID: record.triptychID,
                purpose: .reviewResult,
                recordID: record.id,
                expectedFinalizedResultFingerprint: DocumentFingerprint(
                    content: "a different finalized result"
                )
            )
        )
        #expect(staleModel.selectedRecord == nil)
        #expect(!staleModel.hasDirectUndoEligibility(for: record))
        #expect(staleModel.isShowingError)
    }

    @Test("A Search Record locator selects only the exact Record revision and statement")
    func exactSearchRecordLocator() async throws {
        let record = try makeDiscussion(
            id: deterministicUUID(41),
            noteID: deterministicUUID(42),
            title: "Located Record",
            text: "The researcher's exact objection.",
            author: .researcher,
            finishedAt: Date(timeIntervalSince1970: 100)
        )
        let fingerprint = DocumentFingerprint(content: "exact record bytes")
        let model = ResearchRecordBrowserModel()
        model.bindRecordSearch { request in
            recordSearchResponse(
                request: request,
                triptychID: record.triptychID,
                records: [record],
                fingerprints: [record.id: fingerprint]
            )
        }

        model.prepareForOpen(
            triptychID: record.triptychID,
            records: [record],
            fingerprints: [record.id: fingerprint],
            request: ResearchRecordsWindowRequest(
                triptychID: record.triptychID,
                recordID: record.id,
                expectedRecordFingerprint: fingerprint,
                statementID: record.statements[0].id
            )
        )
        await model.waitForRecordSearchForTesting()

        #expect(model.selectedRecord?.id == record.id)
        #expect(model.focusedStatementID == record.statements[0].id)
        #expect(!model.isShowingError)
    }

    @Test("A stale, deleted, or missing-statement Search Record locator fails closed")
    func invalidSearchRecordLocatorsFailClosed() throws {
        let record = try makeDiscussion(
            id: deterministicUUID(51),
            noteID: deterministicUUID(52),
            title: "Changing Record",
            text: "A statement whose identity matters.",
            author: .agent,
            finishedAt: Date(timeIntervalSince1970: 100)
        )
        let currentFingerprint = DocumentFingerprint(content: "current record bytes")

        let stale = ResearchRecordBrowserModel()
        stale.prepareForOpen(
            triptychID: record.triptychID,
            records: [record],
            fingerprints: [record.id: currentFingerprint],
            request: ResearchRecordsWindowRequest(
                triptychID: record.triptychID,
                recordID: record.id,
                expectedRecordFingerprint: DocumentFingerprint(
                    content: "older record bytes"
                ),
                statementID: record.statements[0].id
            )
        )
        #expect(stale.selectedRecord == nil)
        #expect(stale.focusedStatementID == nil)
        #expect(stale.isShowingError)

        let deleted = ResearchRecordBrowserModel()
        deleted.prepareForOpen(
            triptychID: record.triptychID,
            records: [],
            fingerprints: [:],
            request: ResearchRecordsWindowRequest(
                triptychID: record.triptychID,
                recordID: record.id,
                expectedRecordFingerprint: currentFingerprint,
                statementID: record.statements[0].id
            )
        )
        #expect(deleted.selectedRecord == nil)
        #expect(deleted.focusedStatementID == nil)
        #expect(deleted.isShowingError)

        let missingStatement = ResearchRecordBrowserModel()
        missingStatement.prepareForOpen(
            triptychID: record.triptychID,
            records: [record],
            fingerprints: [record.id: currentFingerprint],
            request: ResearchRecordsWindowRequest(
                triptychID: record.triptychID,
                recordID: record.id,
                expectedRecordFingerprint: currentFingerprint,
                statementID: deterministicUUID(53)
            )
        )
        #expect(missingStatement.selectedRecord == nil)
        #expect(missingStatement.focusedStatementID == nil)
        #expect(missingStatement.isShowingError)
    }

    @Test("An open Search Record locator fails closed after the Record changes")
    func openSearchRecordLocatorRevalidatesOnRefresh() async throws {
        let record = try makeDiscussion(
            id: deterministicUUID(61),
            noteID: deterministicUUID(62),
            title: "Initially Current Record",
            text: "The exact statement selected from Search.",
            author: .researcher,
            finishedAt: Date(timeIntervalSince1970: 100)
        )
        let initial = DocumentFingerprint(content: "initial record bytes")
        let model = ResearchRecordBrowserModel()
        model.bindRecordSearch { request in
            recordSearchResponse(
                request: request,
                triptychID: record.triptychID,
                records: [record],
                fingerprints: [record.id: initial]
            )
        }
        model.prepareForOpen(
            triptychID: record.triptychID,
            records: [record],
            fingerprints: [record.id: initial],
            request: ResearchRecordsWindowRequest(
                triptychID: record.triptychID,
                recordID: record.id,
                expectedRecordFingerprint: initial,
                statementID: record.statements[0].id
            )
        )
        await model.waitForRecordSearchForTesting()
        #expect(model.selectedRecord?.id == record.id)

        model.receive(
            triptychID: record.triptychID,
            records: [record],
            fingerprints: [
                record.id: DocumentFingerprint(content: "changed record bytes")
            ]
        )
        await model.waitForRecordSearchForTesting()

        #expect(model.selectedRecord == nil)
        #expect(model.focusedStatementID == nil)
        #expect(model.isShowingError)
    }

    @Test("The browser compiles filters for the Application Record provider")
    func browserCompilesRecordProviderRequest() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let topicID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let workID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let discussion = try makeDiscussion(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            noteID: topicID,
            title: "价值与理由",
            text: "Café reasons need a narrower objection.",
            author: .researcher,
            finishedAt: now.addingTimeInterval(-3_600)
        )
        let action = try makeAction(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            noteID: workID,
            title: "Argument Map",
            finishedAt: now.addingTimeInterval(-20 * 86_400)
        )
        let model = ResearchRecordBrowserModel()
        let fingerprints = [
            discussion.id: DocumentFingerprint(content: "discussion record"),
            action.id: DocumentFingerprint(content: "action record"),
        ]
        let probe = ResearchRecordSearchProbe { request in
            recordSearchResponse(
                request: request,
                triptychID: discussion.triptychID,
                records: [discussion, action],
                fingerprints: fingerprints
            )
        }
        model.bindRecordSearch { request in
            try await probe.search(request)
        }
        model.prepareForOpen(
            triptychID: discussion.triptychID,
            records: [discussion, action],
            fingerprints: fingerprints,
            request: ResearchRecordsWindowRequest(
                triptychID: discussion.triptychID,
                noteID: topicID
            )
        )
        await model.waitForRecordSearchForTesting()

        #expect(model.visibleEntries.map(\.id) == [discussion.id, action.id])
        #expect(probe.requests.last?.resolvedRecordSort == .finishedAtDescending)
        #expect(probe.requests.last?.limit == SearchContract.recordCollectionPageSize)
        #expect(
            probe.requests.last?.query.contains(
                "note:\"\(topicID.uuidString.lowercased())\""
            ) == true)

        model.scope = .triptych
        model.searchText = "cafe\u{301} 理由"
        model.actionFilterID = .analyze
        model.methodFilterName = "Argument Analysis"
        model.participantFilter = .author(.agent)
        model.dateFilter = .pastSevenDays
        await model.waitForRecordSearchForTesting()

        let query = try #require(probe.requests.last?.query)
        #expect(query.hasPrefix("kind:record"))
        #expect(query.contains("\"cafe\u{301}\""))
        #expect(query.contains("\"理由\""))
        #expect(query.contains("action:\"analyze\""))
        #expect(query.contains("skill:\"Argument Analysis\""))
        #expect(query.contains("participant:agent"))
        #expect(query.contains("date:7d"))
        #expect(model.visibleEntries.map(\.id) == [discussion.id, action.id])
    }

    @Test("Collection rows project exact Analyze Reliability and Coverage states")
    func collectionAcademicFieldProjection() async throws {
        let action = try makeAction(
            id: deterministicUUID(66),
            noteID: deterministicUUID(67),
            title: "Bounded source analysis",
            finishedAt: Date(timeIntervalSince1970: 200),
            academicResults: try analyzeLedgerResults()
        )
        let discussion = try makeDiscussion(
            id: deterministicUUID(68),
            noteID: deterministicUUID(69),
            title: "Open research exchange",
            text: "A discussion has no Analyze coverage contract.",
            author: .researcher,
            finishedAt: Date(timeIntervalSince1970: 100)
        )
        let fingerprints = [
            action.id: DocumentFingerprint(content: "analyze ledger record"),
            discussion.id: DocumentFingerprint(content: "discussion ledger record"),
        ]
        let model = ResearchRecordBrowserModel()
        model.bindRecordSearch { request in
            recordSearchResponse(
                request: request,
                triptychID: action.triptychID,
                records: [action, discussion],
                fingerprints: fingerprints
            )
        }
        model.prepareForOpen(
            triptychID: action.triptychID,
            records: [action, discussion],
            fingerprints: fingerprints,
            request: ResearchRecordsWindowRequest(triptychID: action.triptychID)
        )
        await model.waitForRecordSearchForTesting()

        let analyzeEntry = try #require(model.visibleEntries.first { $0.id == action.id })
        #expect(analyzeEntry.reliability == .value("Incomplete access, Unverified"))
        #expect(analyzeEntry.coverage == .value("Specified part only"))

        let discussionEntry = try #require(
            model.visibleEntries.first { $0.id == discussion.id }
        )
        #expect(discussionEntry.reliability == .notApplicable)
        #expect(discussionEntry.coverage == .notApplicable)
    }

    @Test("Binding the provider requeries and invalid provider or fingerprint fails closed")
    func providerBindingAndResponseValidation() async throws {
        let record = try makeDiscussion(
            id: deterministicUUID(71),
            noteID: deterministicUUID(72),
            title: "Provider-owned Record",
            text: "Application owns matching.",
            author: .researcher,
            finishedAt: Date(timeIntervalSince1970: 100)
        )
        let fingerprint = DocumentFingerprint(content: "record bytes")
        let model = ResearchRecordBrowserModel()
        model.prepareForOpen(
            triptychID: record.triptychID,
            records: [record],
            fingerprints: [record.id: fingerprint],
            request: ResearchRecordsWindowRequest(triptychID: record.triptychID)
        )
        #expect(model.visibleEntries.isEmpty)

        let valid = ResearchRecordSearchProbe { request in
            recordSearchResponse(
                request: request,
                triptychID: record.triptychID,
                records: [record],
                fingerprints: [record.id: fingerprint]
            )
        }
        model.bindRecordSearch { request in try await valid.search(request) }
        await model.waitForRecordSearchForTesting()
        #expect(valid.requests.count == 1)
        #expect(model.visibleEntries.map(\.id) == [record.id])

        model.dismissError()
        model.bindRecordSearch { request in
            noteProviderResponse(request: request, triptychID: record.triptychID)
        }
        await model.waitForRecordSearchForTesting()
        #expect(model.visibleEntries.isEmpty)
        #expect(model.selectedRecord == nil)
        #expect(model.isShowingError)

        model.dismissError()
        model.bindRecordSearch { request in
            recordSearchResponse(
                request: request,
                triptychID: record.triptychID,
                records: [record],
                fingerprints: [
                    record.id: DocumentFingerprint(content: "wrong record bytes")
                ]
            )
        }
        await model.waitForRecordSearchForTesting()
        #expect(model.visibleEntries.isEmpty)
        #expect(model.selectedRecord == nil)
        #expect(model.isShowingError)

        model.bindRecordSearch { request in try await valid.search(request) }
        await model.waitForRecordSearchForTesting()
        #expect(model.visibleEntries.map(\.id) == [record.id])
        #expect(model.route == .collection)
        #expect(model.selectedRecord == nil)
        #expect(!model.isShowingError)
        #expect(model.errorMessage.isEmpty)
    }

    @Test("A superseded noncooperative Record response cannot replace the current query")
    func supersededRecordResponseIsIgnored() async throws {
        let first = try makeDiscussion(
            id: deterministicUUID(81),
            noteID: deterministicUUID(82),
            title: "First Record",
            text: "A stale result.",
            author: .agent,
            finishedAt: Date(timeIntervalSince1970: 100)
        )
        let second = try makeDiscussion(
            id: deterministicUUID(83),
            noteID: deterministicUUID(84),
            title: "Second Record",
            text: "The current result.",
            author: .researcher,
            finishedAt: Date(timeIntervalSince1970: 200)
        )
        let fingerprints = [
            first.id: DocumentFingerprint(content: "first record"),
            second.id: DocumentFingerprint(content: "second record"),
        ]
        let model = ResearchRecordBrowserModel()
        model.prepareForOpen(
            triptychID: first.triptychID,
            records: [first, second],
            fingerprints: fingerprints,
            request: ResearchRecordsWindowRequest(triptychID: first.triptychID)
        )

        var firstContinuation: CheckedContinuation<SearchResponse, Never>?
        var callCount = 0
        model.bindRecordSearch { request in
            callCount += 1
            if callCount == 1 {
                return await withCheckedContinuation { continuation in
                    firstContinuation = continuation
                }
            }
            return recordSearchResponse(
                request: request,
                triptychID: first.triptychID,
                records: [second],
                fingerprints: fingerprints
            )
        }
        while firstContinuation == nil { await Task.yield() }

        model.searchText = "current"
        await model.waitForRecordSearchForTesting()
        #expect(model.visibleEntries.map(\.id) == [second.id])

        let staleRequest = SearchRequest(
            query: "kind:record",
            presentationScope: .triptych,
            executionScope: .triptych,
            limit: SearchContract.maximumInterfaceResults
        )
        firstContinuation?.resume(
            returning: recordSearchResponse(
                request: staleRequest,
                triptychID: first.triptychID,
                records: [first],
                fingerprints: fingerprints
            ))
        await Task.yield()

        #expect(model.visibleEntries.map(\.id) == [second.id])
        #expect(model.route == .collection)
    }

    @Test("An Action row keeps its frozen title and projects live note participants")
    func actionTitleSummarizesLiveParticipants() async throws {
        let targetID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let base = try makeAction(
            id: deterministicUUID(90),
            noteID: targetID,
            title: "Live Analysis",
            finishedAt: Date(timeIntervalSince1970: 100)
        )
        let topic = try makeParticipant(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            role: .analysis,
            title: "Additional Analysis"
        )
        let tombstone = try makeParticipant(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            role: .analysis,
            title: "Deleted Analysis",
            isTombstone: true
        )
        let record = try PortableResearchRecord(
            id: base.id,
            triptychID: base.triptychID,
            title: base.title,
            kind: base.kind,
            action: base.action,
            method: base.method,
            sourceReference: base.sourceReference,
            participatingNotes: base.participatingNotes + [topic, tombstone],
            statements: base.statements,
            fidelityCompletion: base.fidelityCompletion,
            startedAt: base.startedAt,
            finishedAt: base.finishedAt
        )

        let fingerprint = DocumentFingerprint(content: "action row")
        let model = ResearchRecordBrowserModel()
        model.bindRecordSearch { request in
            recordSearchResponse(
                request: request,
                triptychID: record.triptychID,
                records: [record],
                fingerprints: [record.id: fingerprint]
            )
        }
        model.prepareForOpen(
            triptychID: record.triptychID,
            records: [record],
            fingerprints: [record.id: fingerprint],
            request: ResearchRecordsWindowRequest(triptychID: record.triptychID)
        )
        await model.waitForRecordSearchForTesting()

        #expect(model.visibleEntries.first?.title == "Live Analysis")
        #expect(
            model.visibleEntries.first?.noteTitle
                == "Additional Analysis, Live Analysis")
    }

    @Test("Confirmed record deletion removes only the selected disposable projection")
    func recordDeletionLifecycle() async throws {
        let record = try makeDiscussion(
            id: deterministicUUID(301),
            noteID: deterministicUUID(302),
            title: "Recoverable Record",
            text: "Researcher-owned evidence",
            author: .researcher,
            finishedAt: Date(timeIntervalSince1970: 100)
        )
        let model = ResearchRecordBrowserModel()
        let fingerprint = DocumentFingerprint(content: "record to delete")
        let probe = ResearchRecordSearchProbe { request in
            recordSearchResponse(
                request: request,
                triptychID: record.triptychID,
                records: [record],
                fingerprints: [record.id: fingerprint]
            )
        }
        model.bindRecordSearch(probe.search)
        model.prepareForOpen(
            triptychID: record.triptychID,
            records: [record],
            fingerprints: [record.id: fingerprint],
            request: ResearchRecordsWindowRequest(
                triptychID: record.triptychID,
                noteID: record.participatingNotes[0].noteID
            )
        )
        await model.waitForRecordSearchForTesting()
        let requestsBeforeDeletion = probe.requests.count
        #expect(requestsBeforeDeletion > 0)

        var deletionContinuation: CheckedContinuation<Void, Never>?
        let deletionTask = Task { @MainActor in
            await model.deletePermanently(recordID: record.id) { _ in
                await withCheckedContinuation { continuation in
                    deletionContinuation = continuation
                }
            }
        }
        while deletionContinuation == nil {
            await Task.yield()
        }
        #expect(model.visibleEntries.isEmpty)
        #expect(model.selectedRecord == nil)
        deletionContinuation?.resume()
        await deletionTask.value
        #expect(!model.isShowingError)
        #expect(
            probe.requests.count == requestsBeforeDeletion,
            "An empty published Record corpus must not be reparsed as an unauthorized Note query."
        )
    }

    @Test("This Note without a Record candidate is a quiet empty collection")
    func emptyThisNoteScopeSkipsImpossibleRecordSearch() async throws {
        let record = try makeDiscussion(
            id: deterministicUUID(311),
            noteID: deterministicUUID(312),
            title: "Other Note Record",
            text: "Only another Note participates.",
            author: .agent,
            finishedAt: Date(timeIntervalSince1970: 100)
        )
        let model = ResearchRecordBrowserModel()
        let probe = ResearchRecordSearchProbe { _ in
            Issue.record("The provider must not receive an impossible This Note query.")
            throw CancellationError()
        }
        model.bindRecordSearch(probe.search)
        model.prepareForOpen(
            triptychID: record.triptychID,
            records: [record],
            request: ResearchRecordsWindowRequest(
                triptychID: record.triptychID,
                noteID: deterministicUUID(313)
            )
        )

        await model.waitForRecordSearchForTesting()
        #expect(probe.requests.isEmpty)
        #expect(model.visibleEntries.isEmpty)
        #expect(!model.isShowingError)
    }

    @Test("Scope and View remain independent while Record scope uses the provider")
    func scopeAndViewAreIndependent() async throws {
        let firstNoteID = deterministicUUID(601)
        let secondNoteID = deterministicUUID(602)
        let first = try makeAction(
            id: deterministicUUID(611),
            noteID: firstNoteID,
            title: "First Analysis",
            finishedAt: Date(timeIntervalSince1970: 300),
            recommendations: [
                try makeRecommendation(
                    id: deterministicUUID(621),
                    citation: "First source",
                    doi: "https://doi.org/10.1000/same"
                )
            ]
        )
        let second = try makeAction(
            id: deterministicUUID(612),
            noteID: secondNoteID,
            title: "Second Analysis",
            finishedAt: Date(timeIntervalSince1970: 200),
            recommendations: [
                try makeRecommendation(
                    id: deterministicUUID(622),
                    citation: "Second source",
                    doi: "doi:10.1000/same"
                )
            ]
        )
        let model = ResearchRecordBrowserModel()
        let fingerprints = [
            first.id: DocumentFingerprint(content: "first record"),
            second.id: DocumentFingerprint(content: "second record"),
        ]
        let probe = ResearchRecordSearchProbe { request in
            let visible =
                request.query.contains(firstNoteID.uuidString.lowercased())
                ? [first]
                : [first, second]
            return recordSearchResponse(
                request: request,
                triptychID: first.triptychID,
                records: visible,
                fingerprints: fingerprints
            )
        }
        model.bindRecordSearch { request in try await probe.search(request) }
        model.prepareForOpen(
            triptychID: first.triptychID,
            records: [first, second],
            fingerprints: fingerprints,
            request: ResearchRecordsWindowRequest(
                triptychID: first.triptychID,
                noteID: firstNoteID,
                initialView: .recommendations
            )
        )
        await model.waitForRecordSearchForTesting()

        #expect(model.scope == .thisNote)
        #expect(model.viewKind == .recommendations)
        #expect(model.visibleEntries.map(\.id) == [first.id])
        #expect(model.visibleRecommendationGroups.flatMap(\.occurrences).count == 1)

        model.scope = .triptych
        await model.waitForRecordSearchForTesting()
        #expect(model.viewKind == .recommendations)
        #expect(model.visibleEntries.count == 2)
        #expect(model.visibleRecommendationGroups.count == 1)
        #expect(model.visibleRecommendationGroups[0].occurrences.count == 2)
    }

    @Test("Recommendations group only by exact nonconflicting DOI or Zotero identity")
    func conservativeRecommendationGrouping() throws {
        let noteID = deterministicUUID(701)
        let records = try [
            makeAction(
                id: deterministicUUID(711),
                noteID: noteID,
                title: "Analysis One",
                finishedAt: Date(timeIntervalSince1970: 400),
                recommendations: [
                    try makeRecommendation(
                        id: deterministicUUID(721),
                        citation: "Shared title",
                        doi: "https://doi.org/10.1000/exact",
                        zoteroItemKey: "ABCD1234"
                    )
                ]
            ),
            makeAction(
                id: deterministicUUID(712),
                noteID: noteID,
                title: "Analysis Two",
                finishedAt: Date(timeIntervalSince1970: 300),
                recommendations: [
                    try makeRecommendation(
                        id: deterministicUUID(722),
                        citation: "Shared title",
                        doi: "doi:10.1000/exact",
                        zoteroItemKey: "abcd1234"
                    )
                ]
            ),
            makeAction(
                id: deterministicUUID(713),
                noteID: noteID,
                title: "Analysis Three",
                finishedAt: Date(timeIntervalSince1970: 200),
                recommendations: [
                    try makeRecommendation(
                        id: deterministicUUID(723),
                        citation: "Shared title",
                        doi: "10.1000/exact",
                        zoteroItemKey: "CONFLICT"
                    )
                ]
            ),
            makeAction(
                id: deterministicUUID(714),
                noteID: noteID,
                title: "Analysis Four",
                finishedAt: Date(timeIntervalSince1970: 100),
                recommendations: [
                    try makeRecommendation(
                        id: deterministicUUID(724),
                        citation: "Shared title"
                    )
                ]
            ),
            makeAction(
                id: deterministicUUID(715),
                noteID: noteID,
                title: "Analysis Five",
                finishedAt: Date(timeIntervalSince1970: 50),
                recommendations: [
                    try makeRecommendation(
                        id: deterministicUUID(725),
                        citation: "A different work",
                        title: "Different work",
                        doi: "10.1000/exact",
                        zoteroItemKey: "ABCD1234"
                    )
                ]
            ),
        ]
        let index = ResearchLiteratureRecommendationDerivedIndex(records: records)
        let groups = index.query(text: "", noteID: nil, status: .all)

        #expect(groups.count == 4)
        #expect(groups.map(\.occurrences.count).sorted() == [1, 1, 1, 2])
        #expect(groups.flatMap(\.occurrences).count == 5)
        #expect(groups.filter(\.displaysSharedIdentityHeader).count == 1)
        #expect(
            groups.first { $0.occurrences.count == 1 }?
                .displaysSharedIdentityHeader == false)
    }

    @Test("A growing exact-identity group performs one signature check per occurrence")
    func recommendationGroupingAvoidsPairwiseRescans() throws {
        var records: [PortableResearchRecord] = []
        for recordOrdinal in 0..<12 {
            let recommendations = try (0..<250).map { recommendationOrdinal in
                try makeRecommendation(
                    id: deterministicUUID(
                        30_000 + recordOrdinal * 250 + recommendationOrdinal
                    ),
                    citation: "Shared exact-identity source",
                    doi: "https://doi.org/10.1000/large-group"
                )
            }
            records.append(
                try makeAction(
                    id: deterministicUUID(20_000 + recordOrdinal),
                    noteID: deterministicUUID(21_000 + recordOrdinal),
                    title: "Analysis \(recordOrdinal)",
                    finishedAt: Date(timeIntervalSince1970: Double(recordOrdinal)),
                    recommendations: recommendations
                ))
        }

        let index = ResearchLiteratureRecommendationDerivedIndex(records: records)
        let groups = index.query(text: "", noteID: nil, status: .all)
        #expect(groups.count == 1)
        #expect(groups[0].occurrences.count == 3_000)
        #expect(index.groupingCompatibilityCheckCount(noteID: nil) <= 2_999)
        #expect(
            ResearchLiteratureRecommendationDerivedIndex(records: records)
                .query(text: "", noteID: nil, status: .all) == groups
        )
    }

    @Test("A failed researcher-note save remains recoverable by the presenting sheet")
    func recommendationNoteFailurePropagatesWithoutReplacingTheRecord() async throws {
        enum SaveFailure: LocalizedError {
            case notCommitted

            var errorDescription: String? {
                "The researcher note was not committed."
            }
        }

        let recommendation = try makeRecommendation(
            id: deterministicUUID(801),
            citation: "A recoverable reading lead"
        )
        let record = try makeAction(
            id: deterministicUUID(811),
            noteID: deterministicUUID(812),
            title: "Recoverable Analysis",
            finishedAt: Date(timeIntervalSince1970: 100),
            recommendations: [recommendation]
        )
        let model = ResearchRecordBrowserModel()
        model.prepareForOpen(
            triptychID: record.triptychID,
            records: [record],
            request: ResearchRecordsWindowRequest(
                triptychID: record.triptychID,
                initialView: .recommendations
            )
        )
        let storedRecommendation = try #require(record.literatureRecommendations.first)
        let occurrenceID = ResearchLiteratureRecommendationOccurrenceID(
            recordID: record.id,
            recommendationID: storedRecommendation.id
        )
        model.selectRecommendation(occurrenceID)

        await #expect(throws: SaveFailure.self) {
            try await model.setRecommendationNote(
                occurrenceID: occurrenceID,
                note: "Keep this draft available for retry."
            ) { _, _, _ in
                throw SaveFailure.notCommitted
            }
        }

        #expect(
            model.selectedRecommendationOccurrence?.recommendation.rawCitation
                == recommendation.rawCitation
        )
        #expect(model.mutatingRecommendationIDs.isEmpty)
        #expect(!model.isShowingError)
    }

    @Test("Handled changes are visible before the durable update returns in both directions")
    func recommendationDispositionUsesImmediateOptimisticFeedback() async throws {
        let recommendationID = deterministicUUID(821)
        let recordID = deterministicUUID(822)
        let noteID = deterministicUUID(823)
        let unprocessed = try makeAction(
            id: recordID,
            noteID: noteID,
            title: "Immediate Reading Lead Feedback",
            finishedAt: Date(timeIntervalSince1970: 100),
            recommendations: [
                try makeRecommendation(
                    id: recommendationID,
                    citation: "A reading lead whose disposition is responsive"
                )
            ]
        )
        let handled = try makeAction(
            id: recordID,
            noteID: noteID,
            title: "Immediate Reading Lead Feedback",
            finishedAt: Date(timeIntervalSince1970: 100),
            recommendations: [
                try makeRecommendation(
                    id: recommendationID,
                    citation: "A reading lead whose disposition is responsive",
                    status: .handled
                )
            ]
        )
        let model = ResearchRecordBrowserModel()
        model.prepareForOpen(
            triptychID: unprocessed.triptychID,
            records: [unprocessed],
            request: ResearchRecordsWindowRequest(
                triptychID: unprocessed.triptychID,
                initialView: .recommendations
            )
        )
        let occurrenceID = ResearchLiteratureRecommendationOccurrenceID(
            recordID: recordID,
            recommendationID: try #require(
                unprocessed.literatureRecommendations.first?.id
            )
        )

        model.setRecommendationDisposition(
            occurrenceID: occurrenceID,
            status: .handled
        ) { _, _, _ in
            try await Task.sleep(for: .milliseconds(50))
            return handled
        }

        #expect(model.recommendationDispositionStatus(for: occurrenceID) == .handled)
        #expect(model.mutatingRecommendationIDs.contains(occurrenceID))
        await model.waitForRecommendationMutationForTesting(occurrenceID)
        #expect(model.recommendationDispositionStatus(for: occurrenceID) == .handled)
        #expect(model.mutatingRecommendationIDs.isEmpty)

        model.setRecommendationDisposition(
            occurrenceID: occurrenceID,
            status: .unprocessed
        ) { _, _, _ in
            try await Task.sleep(for: .milliseconds(50))
            return unprocessed
        }

        #expect(model.recommendationDispositionStatus(for: occurrenceID) == .unprocessed)
        #expect(model.mutatingRecommendationIDs.contains(occurrenceID))
        await model.waitForRecommendationMutationForTesting(occurrenceID)
        #expect(model.recommendationDispositionStatus(for: occurrenceID) == .unprocessed)
        #expect(model.mutatingRecommendationIDs.isEmpty)
    }

    @Test("A failed Handled change rolls the immediate feedback back")
    func recommendationDispositionFailureRollsBackOptimisticFeedback() async throws {
        enum DispositionFailure: Error {
            case notCommitted
        }

        let record = try makeAction(
            id: deterministicUUID(831),
            noteID: deterministicUUID(832),
            title: "Recoverable Reading Lead Disposition",
            finishedAt: Date(timeIntervalSince1970: 100),
            recommendations: [
                try makeRecommendation(
                    id: deterministicUUID(833),
                    citation: "A reading lead whose failed change remains honest"
                )
            ]
        )
        let model = ResearchRecordBrowserModel()
        model.prepareForOpen(
            triptychID: record.triptychID,
            records: [record],
            request: ResearchRecordsWindowRequest(
                triptychID: record.triptychID,
                initialView: .recommendations
            )
        )
        let occurrenceID = ResearchLiteratureRecommendationOccurrenceID(
            recordID: record.id,
            recommendationID: try #require(record.literatureRecommendations.first?.id)
        )

        model.setRecommendationDisposition(
            occurrenceID: occurrenceID,
            status: .handled
        ) { _, _, _ in
            await Task.yield()
            throw DispositionFailure.notCommitted
        }

        #expect(model.recommendationDispositionStatus(for: occurrenceID) == .handled)
        await model.waitForRecommendationMutationForTesting(occurrenceID)
        #expect(model.recommendationDispositionStatus(for: occurrenceID) == .unprocessed)
        #expect(model.isShowingError)
    }

    @Test("Opening a Record recommendation clears filters that would hide its row")
    func recordRecommendationLinkMakesItsOccurrenceVisible() throws {
        let recordID = deterministicUUID(901)
        let first = try makeRecommendation(
            id: deterministicUUID(902),
            citation: "First searchable lead",
            title: "First lead"
        )
        let second = try makeRecommendation(
            id: deterministicUUID(903),
            citation: "Second target lead",
            title: "Second lead"
        )
        let record = try makeAction(
            id: recordID,
            noteID: deterministicUUID(904),
            title: "Linked Analysis",
            finishedAt: Date(timeIntervalSince1970: 100),
            recommendations: [first, second]
        )
        let targetID = record.literatureRecommendations[1].id
        let model = ResearchRecordBrowserModel()
        model.prepareForOpen(
            triptychID: record.triptychID,
            records: [record],
            request: ResearchRecordsWindowRequest(
                triptychID: record.triptychID,
                initialView: .recommendations
            )
        )
        model.recommendationSearchText = "First"
        #expect(model.visibleRecommendationGroups.flatMap(\.occurrences).count == 1)

        model.openRecommendation(recordID: record.id, recommendationID: targetID)

        #expect(model.recommendationSearchText.isEmpty)
        #expect(model.recommendationFilter == .all)
        #expect(model.selectedRecommendationID?.recommendationID == targetID)
        #expect(
            model.visibleRecommendationGroups.flatMap(\.occurrences).contains {
                $0.recommendation.id == targetID
            })
    }

    @Test(
        "Continue Research remains one portable child but folds beneath its parent collection row")
    func continueResearchFoldsBeneathParent() async throws {
        let parentID = deterministicUUID(951)
        let childID = deterministicUUID(952)
        let parent = try makeAction(
            id: parentID,
            noteID: deterministicUUID(953),
            title: "Parent Analysis",
            finishedAt: Date(timeIntervalSince1970: 100)
        )
        let child = try makeAction(
            id: childID,
            noteID: deterministicUUID(954),
            title: "Continued Analysis",
            finishedAt: Date(timeIntervalSince1970: 200),
            continuationLineage: ResearchContinuationLineage(
                groupID: deterministicUUID(955),
                parentRunID: parentID,
                requestID: deterministicUUID(956),
                kind: .continueResearch
            )
        )
        let model = ResearchRecordBrowserModel()
        let fingerprints = [
            parentID: DocumentFingerprint(content: "parent-record"),
            childID: DocumentFingerprint(content: "child-record"),
        ]
        model.bindRecordSearch { request in
            recordSearchResponse(
                request: request,
                triptychID: parent.triptychID,
                records: [parent, child],
                fingerprints: fingerprints
            )
        }
        model.prepareForOpen(
            triptychID: parent.triptychID,
            records: [parent, child],
            fingerprints: fingerprints,
            request: ResearchRecordsWindowRequest(triptychID: parent.triptychID)
        )
        await model.waitForRecordSearchForTesting()

        #expect(model.route == .collection)
        #expect(model.visibleEntries.map(\.id) == [parentID])
        #expect(model.totalRecordCount == 1)
        #expect(model.record(id: childID)?.id == childID)
        #expect(model.continuationChildren(for: parentID).map(\.id) == [childID])

        model.openRecord(id: childID)
        #expect(model.route == .record(childID))
        #expect(model.continuationParent(for: child)?.id == parentID)
    }

    @Test("Record and Reading Lead collections expose exact totals across 100-row pages")
    func collectionPaginationAndSorting() async throws {
        let triptychID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let records = try (0..<205).map { index in
            try makeDiscussion(
                id: deterministicUUID(10_000 + index),
                triptychID: triptychID,
                noteID: deterministicUUID(20_000 + index),
                title: String(format: "Record %03d", index),
                text: "A representative discussion turn for page \(index).",
                author: .researcher,
                finishedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let fingerprints = Dictionary(uniqueKeysWithValues: records.map {
            ($0.id, DocumentFingerprint(content: "record-\($0.id.uuidString)"))
        })
        let model = ResearchRecordBrowserModel()
        model.bindRecordSearch { request in
            recordSearchResponse(
                request: request,
                triptychID: triptychID,
                records: records,
                fingerprints: fingerprints
            )
        }
        model.prepareForOpen(
            triptychID: triptychID,
            records: records,
            fingerprints: fingerprints,
            request: ResearchRecordsWindowRequest(triptychID: triptychID)
        )
        await model.waitForRecordSearchForTesting()

        #expect(model.recordResultCount == 205)
        #expect(model.visibleEntries.count == 100)
        #expect(model.visibleEntries.first?.title == "Record 204")
        #expect(model.hasMoreRecords)

        model.loadMoreRecordsIfNeeded(currentID: try #require(model.visibleEntries.last?.id))
        await model.waitForRecordSearchForTesting()
        #expect(model.visibleEntries.count == 200)
        model.loadMoreRecordsIfNeeded(currentID: try #require(model.visibleEntries.last?.id))
        await model.waitForRecordSearchForTesting()
        #expect(model.visibleEntries.count == 205)
        #expect(!model.hasMoreRecords)

        model.recordSort = .titleAscending
        await model.waitForRecordSearchForTesting()
        #expect(model.visibleEntries.first?.title == "Record 000")

        let recommendations = try (0..<105).map { index in
            try makeRecommendation(
                id: deterministicUUID(30_000 + index),
                citation: "Citation \(index)",
                title: String(format: "Lead %03d", index)
            )
        }
        let analysis = try makeAction(
            id: deterministicUUID(40_000),
            noteID: deterministicUUID(40_001),
            title: "Reading Lead Pagination",
            finishedAt: Date(timeIntervalSince1970: 500),
            recommendations: recommendations
        )
        let leadFingerprint = DocumentFingerprint(content: "lead-parent")
        let leadModel = ResearchRecordBrowserModel()
        leadModel.bindRecordSearch { request in
            recordSearchResponse(
                request: request,
                triptychID: triptychID,
                records: [analysis],
                fingerprints: [analysis.id: leadFingerprint]
            )
        }
        leadModel.prepareForOpen(
            triptychID: triptychID,
            records: [analysis],
            fingerprints: [analysis.id: leadFingerprint],
            request: ResearchRecordsWindowRequest(
                triptychID: triptychID,
                initialView: .recommendations
            )
        )
        await leadModel.waitForRecordSearchForTesting()
        #expect(leadModel.recommendationResultCount == 105)
        #expect(leadModel.visibleRecommendationOccurrences.count == 100)
        leadModel.loadMoreRecommendationsIfNeeded(
            currentID: try #require(leadModel.visibleRecommendationOccurrences.last?.id)
        )
        #expect(leadModel.visibleRecommendationOccurrences.count == 105)
        #expect(!leadModel.hasMoreRecommendations)
    }

    @Test("A later Record page failure preserves loaded rows and remains retryable")
    func laterPageFailurePreservesRows() async throws {
        let triptychID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let records = try (0..<101).map { index in
            try makeDiscussion(
                id: deterministicUUID(50_000 + index),
                triptychID: triptychID,
                noteID: deterministicUUID(60_000 + index),
                title: String(format: "Retry Record %03d", index),
                text: "A record retained across a later-page failure.",
                author: .agent,
                finishedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let fingerprints = Dictionary(uniqueKeysWithValues: records.map {
            ($0.id, DocumentFingerprint(content: "retry-\($0.id.uuidString)"))
        })
        let model = ResearchRecordBrowserModel()
        model.bindRecordSearch { request in
            if request.resultOffset > 0 {
                throw CocoaError(.fileReadUnknown)
            }
            return recordSearchResponse(
                request: request,
                triptychID: triptychID,
                records: records,
                fingerprints: fingerprints
            )
        }
        model.prepareForOpen(
            triptychID: triptychID,
            records: records,
            fingerprints: fingerprints,
            request: ResearchRecordsWindowRequest(triptychID: triptychID)
        )
        await model.waitForRecordSearchForTesting()
        model.loadMoreRecordsIfNeeded(
            currentID: try #require(model.visibleEntries.last?.id)
        )
        await model.waitForRecordSearchForTesting()

        #expect(model.visibleEntries.count == 100)
        #expect(model.recordResultCount == 101)
        #expect(model.hasMoreRecords)
        #expect(model.recordLoadMoreErrorMessage != nil)
        #expect(!model.isShowingError)
    }

    private func makeDiscussion(
        id: UUID,
        triptychID: UUID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        noteID: UUID,
        title: String,
        text: String,
        author: PortableResearchStatementAuthor,
        finishedAt: Date,
        isTombstone: Bool = false
    ) throws -> PortableResearchRecord {
        let fingerprint = DocumentFingerprint(content: title)
        let note = try PortableResearchNoteRevision(
            noteID: noteID,
            note: VaultQualifiedNoteID(
                vaultID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
                relativePath: "Notes/\(noteID.uuidString).md"
            ),
            role: .topic,
            title: title,
            startingRevision: fingerprint,
            endingRevision: isTombstone ? nil : fingerprint,
            isTombstone: isTombstone
        )
        let statement = try PortableResearchStatement(
            id: id,
            author: author,
            kind: .discussionTurn,
            attribution: author == .agent ? "Agent" : "Researcher",
            text: text,
            createdAt: finishedAt
        )
        return try PortableResearchRecord(
            id: id,
            triptychID: triptychID,
            title: ResearchRecordTitle(title),
            kind: .discussion,
            action: nil,
            method: nil,
            primaryNoteID: noteID,
            participatingNotes: [note],
            statements: [statement],
            fidelityCompletion: .notApplicable,
            startedAt: finishedAt,
            finishedAt: finishedAt
        )
    }

    private func makeAction(
        id: UUID,
        noteID: UUID,
        title: String,
        finishedAt: Date,
        recommendations: [ResearchLiteratureRecommendation] = [],
        continuationLineage: ResearchContinuationLineage? = nil,
        academicResults: [PortableResearchAcademicFieldResult] = []
    ) throws -> PortableResearchRecord {
        let fingerprint = DocumentFingerprint(content: title)
        let note = try PortableResearchNoteRevision(
            noteID: noteID,
            note: VaultQualifiedNoteID(
                vaultID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
                relativePath: "Works/Argument.md"
            ),
            role: .analysis,
            title: title,
            startingRevision: fingerprint,
            endingRevision: fingerprint
        )
        let method = try JSONDecoder().decode(
            PortableResearchMethodReference.self,
            from: Data(
                """
                {"registration_key":"10000000-0000-0000-0000-000000000001","display_name":"Argument Analysis","practice_names":[],"profile_revision":{"sha256":"\(fingerprint.sha256)","byteCount":\(fingerprint.byteCount)}}
                """.utf8)
        )
        let recommendations = try recommendations.enumerated().map {
            ordinal, recommendation in
            try ResearchLiteratureRecommendation(
                id: ResearchLiteratureRecommendation.stableID(
                    runID: id,
                    ordinal: ordinal
                ),
                rawCitation: recommendation.rawCitation,
                title: recommendation.title,
                authors: recommendation.authors,
                year: recommendation.year,
                doi: recommendation.doi,
                zoteroItemKey: recommendation.zoteroItemKey,
                sourceLocators: recommendation.sourceLocators,
                reason: recommendation.reason,
                uncertainty: recommendation.uncertainty,
                disposition: recommendation.disposition
            )
        }
        return try PortableResearchRecord(
            id: id,
            triptychID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            title: ResearchRecordTitle(title),
            kind: .action,
            action: ResearchActionRecordIdentity(actionID: .analyze),
            method: method,
            sourceReference: try ResearchSourceReference(
                identity: .localFile(id: id),
                displayName: "Source.pdf",
                fingerprint: fingerprint
            ),
            continuationLineage: continuationLineage,
            participatingNotes: [note],
            statements: [
                try PortableResearchStatement(
                    id: id,
                    author: .agent,
                    kind: .agentFeedback,
                    attribution: "Agent",
                    text: "The argument map was reviewed.",
                    createdAt: finishedAt
                )
            ],
            academicResults: academicResults,
            fidelityCompletion: .notRequired,
            literatureRecommendations: recommendations,
            startedAt: finishedAt,
            finishedAt: finishedAt
        )
    }

    private func makeChangedAction(
        id: UUID,
        noteID: UUID,
        title: String
    ) throws -> PortableResearchRecord {
        let starting = DocumentFingerprint(content: "starting \(title)")
        let ending = DocumentFingerprint(content: "ending \(title)")
        let note = try PortableResearchNoteRevision(
            noteID: noteID,
            note: VaultQualifiedNoteID(
                vaultID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
                relativePath: "Works/Argument.md"
            ),
            role: .analysis,
            title: title,
            startingRevision: starting,
            endingRevision: ending
        )
        let method = try JSONDecoder().decode(
            PortableResearchMethodReference.self,
            from: Data(
                """
                {"registration_key":"10000000-0000-0000-0000-000000000001","display_name":"Argument Analysis","practice_names":[],"profile_revision":{"sha256":"\(starting.sha256)","byteCount":\(starting.byteCount)}}
                """.utf8
            )
        )
        return try PortableResearchRecord(
            id: id,
            triptychID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            title: ResearchRecordTitle(title),
            kind: .action,
            action: ResearchActionRecordIdentity(actionID: .synthesize),
            method: method,
            participatingNotes: [note],
            statements: [
                try PortableResearchStatement(
                    id: id,
                    author: .agent,
                    kind: .agentFeedback,
                    attribution: "Agent",
                    text: "The source was changed.",
                    createdAt: Date(timeIntervalSince1970: 100)
                )
            ],
            fidelityCompletion: .notRequired,
            confirmedChanges: [
                try PortableResearchConfirmedChange(
                    noteID: noteID,
                    actor: .agent,
                    startingRevision: starting,
                    endingRevision: ending
                )
            ],
            startedAt: Date(timeIntervalSince1970: 90),
            finishedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func replacingReviewDisposition(
        in record: PortableResearchRecord,
        with disposition: PortableResearcherReviewDisposition
    ) throws -> PortableResearchRecord {
        try PortableResearchRecord(
            id: record.id,
            triptychID: record.triptychID,
            title: record.title,
            kind: record.kind,
            action: record.action,
            method: record.method,
            sourceReference: record.sourceReference,
            continuationLineage: record.continuationLineage,
            primaryNoteID: record.primaryNoteID,
            participatingNotes: record.participatingNotes,
            statements: record.statements,
            resultDisposition: record.resultDisposition,
            academicResults: record.academicResults,
            contextUseReport: record.contextUseReport,
            actuallyUsedMaterials: record.actuallyUsedMaterials,
            fidelityCompletion: record.fidelityCompletion,
            confirmedChanges: record.confirmedChanges,
            discrepancies: record.discrepancies,
            literatureRecommendations: record.literatureRecommendations,
            startedAt: record.startedAt,
            finishedAt: record.finishedAt,
            researcherEvaluation: record.researcherEvaluation,
            methodFeedbackComment: record.methodFeedbackComment,
            researcherReviewDisposition: disposition
        )
    }

    private func analyzeLedgerResults() throws -> [PortableResearchAcademicFieldResult] {
        let profile = try #require(
            ResearchAcademicProfileCatalog.defaultProfiles.first {
                $0.actionID == .analyze
            }
        )
        let coverage = try #require(
            profile.academicResultFields.first { $0.fieldID.rawValue == "coverage" }
        )
        let reliability = try #require(
            profile.academicResultFields.first { $0.fieldID.rawValue == "reliability" }
        )
        return [
            try PortableResearchAcademicFieldResult(
                definition: coverage,
                value: .singleChoice("specified-part-only")
            ),
            try PortableResearchAcademicFieldResult(
                definition: reliability,
                value: .multipleChoice(["incomplete-access", "unverified"])
            ),
        ]
    }

    private func makeRecommendation(
        id: UUID,
        citation: String,
        title: String = "Shared title",
        doi: String? = nil,
        zoteroItemKey: String? = nil,
        status: ResearchLiteratureRecommendationDispositionStatus = .unprocessed
    ) throws -> ResearchLiteratureRecommendation {
        try ResearchLiteratureRecommendation(
            id: id,
            rawCitation: citation,
            title: title,
            doi: doi,
            zoteroItemKey: zoteroItemKey,
            reason: "The exact Analysis source identifies a relevant argument.",
            disposition: PortableResearchRecommendationDisposition(
                status: status,
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
    }

    private func makeParticipant(
        id: UUID,
        role: ResearchActionTargetRole,
        title: String,
        isTombstone: Bool = false
    ) throws -> PortableResearchNoteRevision {
        let fingerprint = DocumentFingerprint(content: title)
        return try PortableResearchNoteRevision(
            noteID: id,
            note: VaultQualifiedNoteID(
                vaultID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
                relativePath: "Notes/\(id.uuidString).md"
            ),
            role: role,
            title: title,
            startingRevision: fingerprint,
            endingRevision: isTombstone ? nil : fingerprint,
            isTombstone: isTombstone
        )
    }

    private func recordSearchResponse(
        request: SearchRequest,
        triptychID: UUID,
        records: [PortableResearchRecord],
        fingerprints: [UUID: DocumentFingerprint]
    ) -> SearchResponse {
        let generation = RecordSearchGenerationID(
            triptychID: triptychID,
            sourceManifestHash: records.map {
                fingerprints[$0.id]?.sha256 ?? $0.id.uuidString.lowercased()
            }.joined(separator: ":")
        )
        let freshness = SearchFreshnessToken.record(generation)
        let parsed = SearchQueryParser.parse(request.query)
        let explanation =
            parsed.ast?.explanation(scope: request.presentationScope)
            ?? SearchExplanation(
                provider: .record,
                providerWasExplicit: true,
                scope: request.presentationScope,
                clauses: []
            )
        var orderedRecords = records.filter {
            request.recordSort == nil
                || $0.continuationLineage?.kind != .continueResearch
        }
        orderedRecords.sort { lhs, rhs in
            let action: (PortableResearchRecord) -> String = {
                $0.kind == .discussion
                    ? ResearchActionID.discuss.rawValue
                    : ($0.action?.actionID ?? .discuss).rawValue
            }
            switch request.resolvedRecordSort {
            case .finishedAtDescending:
                if lhs.finishedAt != rhs.finishedAt { return lhs.finishedAt > rhs.finishedAt }
            case .finishedAtAscending:
                if lhs.finishedAt != rhs.finishedAt { return lhs.finishedAt < rhs.finishedAt }
            case .titleAscending, .titleDescending:
                let comparison = lhs.title.value.localizedStandardCompare(rhs.title.value)
                if comparison != .orderedSame {
                    return request.resolvedRecordSort == .titleAscending
                        ? comparison == .orderedAscending
                        : comparison == .orderedDescending
                }
            case .actionAscending, .actionDescending:
                let comparison = action(lhs).localizedStandardCompare(action(rhs))
                if comparison != .orderedSame {
                    return request.resolvedRecordSort == .actionAscending
                        ? comparison == .orderedAscending
                        : comparison == .orderedDescending
                }
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let totalResultCount = orderedRecords.count
        let lowerBound = min(request.resultOffset, totalResultCount)
        let upperBound = min(lowerBound + request.limit, totalResultCount)
        let page = orderedRecords[lowerBound..<upperBound]
        let results = page.compactMap { record -> SearchResult? in
            guard let fingerprint = fingerprints[record.id] else { return nil }
            let actionID =
                record.kind == .discussion
                ? ResearchActionID.discuss
                : record.action?.actionID ?? .discuss
            return .record(
                RecordSearchResult(
                    recordID: record.id,
                    matchedField: .context,
                    matchedReason: "fixture provider result",
                    context: record.title.value,
                    actionID: actionID.rawValue,
                    methodName: record.method?.displayName,
                    sourceDisplayName: record.sourceReference?.displayName,
                    finishedAt: record.finishedAt,
                    participatingNotes: record.participatingNotes.map(\.note),
                    snippet: record.title.value,
                    freshnessToken: freshness,
                    fingerprint: fingerprint
                ))
        }
        return SearchResponse(
            requestID: request.id,
            scope: request.presentationScope,
            explanation: explanation,
            freshnessToken: freshness,
            availability: .record(.current(generation)),
            results: results,
            hasMore: upperBound < totalResultCount,
            totalResultCount: totalResultCount,
            diagnostics: parsed.diagnostics
        )
    }

    private func noteProviderResponse(
        request: SearchRequest,
        triptychID: UUID
    ) -> SearchResponse {
        let generation = SearchGenerationID(
            triptychID: triptychID,
            sequence: 1,
            sourceManifestHash: "note-provider"
        )
        return SearchResponse(
            requestID: request.id,
            scope: request.presentationScope,
            explanation: SearchExplanation(
                provider: .note,
                providerWasExplicit: false,
                scope: request.presentationScope,
                clauses: []
            ),
            freshnessToken: .triptych(generation),
            availability: .note(.current(generation)),
            results: [],
            hasMore: false
        )
    }

    private func deterministicUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }
}
