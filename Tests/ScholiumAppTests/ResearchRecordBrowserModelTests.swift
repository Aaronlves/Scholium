import Foundation
import ScholiumContracts
@testable import ScholiumApp
import Testing

@MainActor
private final class ResearchRecordSearchProbe {
    var requests: [SearchRequest] = []
    let handler: @MainActor @Sendable (SearchRequest) async throws -> SearchResponse

    init(
        handler: @escaping @MainActor @Sendable (
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
                record.id: DocumentFingerprint(content: "changed record bytes"),
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
            finishedAt: now.addingTimeInterval(-20 * 86_400),
            isPinned: true
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
                records: [action, discussion],
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

        #expect(model.visibleEntries.map(\.id) == [action.id, discussion.id])
        #expect(probe.requests.last?.query.contains(
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
        #expect(model.visibleEntries.map(\.id) == [action.id, discussion.id])
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
                    record.id: DocumentFingerprint(content: "wrong record bytes"),
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
        #expect(model.selectedRecord?.id == record.id)
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
        firstContinuation?.resume(returning: recordSearchResponse(
            request: staleRequest,
            triptychID: first.triptychID,
            records: [first],
            fingerprints: fingerprints
        ))
        await Task.yield()

        #expect(model.visibleEntries.map(\.id) == [second.id])
        #expect(model.selectedRecord?.id == second.id)
    }

    @Test("Pin completion refreshes the provider row and preserves browser criteria")
    func pinCompletionReordersWithoutResettingFilters() async throws {
        let record = try makeDiscussion(
            id: deterministicUUID(1),
            noteID: deterministicUUID(2),
            title: "Focused Topic",
            text: "Researcher statement",
            author: .researcher,
            finishedAt: Date(timeIntervalSince1970: 100)
        )
        let model = ResearchRecordBrowserModel()
        let fingerprint = DocumentFingerprint(content: "focused record")
        let provider = ResearchRecordProviderState(records: [record])
        model.bindRecordSearch { request in
            recordSearchResponse(
                request: request,
                triptychID: record.triptychID,
                records: provider.records,
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
        model.searchText = "Focused"

        await model.setPinned(recordID: record.id) { _, requestedPin in
            #expect(requestedPin)
            let updated = try PortableResearchRecord(
                id: record.id,
                triptychID: record.triptychID,
                kind: record.kind,
                action: record.action,
                method: record.method,
                sourceReference: record.sourceReference,
                continuationLineage: record.continuationLineage,
                primaryNoteID: record.primaryNoteID,
                participatingNotes: record.participatingNotes,
                statements: record.statements,
                actuallyUsedMaterials: record.actuallyUsedMaterials,
                fidelityCompletion: record.fidelityCompletion,
                confirmedChanges: record.confirmedChanges,
                discrepancies: record.discrepancies,
                startedAt: record.startedAt,
                finishedAt: record.finishedAt,
                isPinned: true
            )
            provider.records = [updated]
            return updated
        }
        await model.waitForRecordSearchForTesting()

        #expect(model.searchText == "Focused")
        #expect(model.visibleEntries.first?.isPinned == true)
        #expect(model.selectedRecord?.isPinned == true)
    }

    @Test("Pin and confirmed deletion cannot race a removed record back into the browser")
    func pinAndDeletionAreSerializedPerRecord() async throws {
        let record = try makeDiscussion(
            id: deterministicUUID(11),
            noteID: deterministicUUID(12),
            title: "Concurrent Record",
            text: "One lifecycle mutation at a time",
            author: .researcher,
            finishedAt: Date(timeIntervalSince1970: 100)
        )
        let pinned = try PortableResearchRecord(
            id: record.id,
            triptychID: record.triptychID,
            kind: record.kind,
            action: record.action,
            method: record.method,
            sourceReference: record.sourceReference,
            continuationLineage: record.continuationLineage,
            primaryNoteID: record.primaryNoteID,
            participatingNotes: record.participatingNotes,
            statements: record.statements,
            actuallyUsedMaterials: record.actuallyUsedMaterials,
            fidelityCompletion: record.fidelityCompletion,
            confirmedChanges: record.confirmedChanges,
            discrepancies: record.discrepancies,
            startedAt: record.startedAt,
            finishedAt: record.finishedAt,
            isPinned: true
        )
        let model = ResearchRecordBrowserModel()
        let fingerprint = DocumentFingerprint(content: "concurrent record")
        let provider = ResearchRecordProviderState(records: [record])
        model.bindRecordSearch { request in
            recordSearchResponse(
                request: request,
                triptychID: record.triptychID,
                records: provider.records,
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
        var pinContinuation: CheckedContinuation<PortableResearchRecord, Never>?
        let pinTask = Task { @MainActor in
            await model.setPinned(recordID: record.id) { _, _ in
                await withCheckedContinuation { continuation in
                    pinContinuation = continuation
                }
            }
        }
        while pinContinuation == nil {
            await Task.yield()
        }

        var deletionCallCount = 0
        await model.deletePermanently(recordID: record.id) { _ in
            deletionCallCount += 1
        }
        #expect(deletionCallCount == 0)
        #expect(model.visibleEntries.map(\.id) == [record.id])

        provider.records = [pinned]
        pinContinuation?.resume(returning: pinned)
        await pinTask.value
        await model.waitForRecordSearchForTesting()
        #expect(model.visibleEntries.map(\.id) == [record.id])
        #expect(model.selectedRecord?.isPinned == true)

        // A concurrent reload/removal is also forbidden from being resurrected
        // by a late pin result, even if another caller bypasses the UI guards.
        var lateContinuation: CheckedContinuation<PortableResearchRecord, Never>?
        let latePinTask = Task { @MainActor in
            await model.setPinned(recordID: record.id) { _, _ in
                await withCheckedContinuation { continuation in
                    lateContinuation = continuation
                }
            }
        }
        while lateContinuation == nil {
            await Task.yield()
        }
        model.prepareForOpen(
            triptychID: record.triptychID,
            records: [],
            request: ResearchRecordsWindowRequest(triptychID: record.triptychID)
        )
        lateContinuation?.resume(returning: record)
        await latePinTask.value
        #expect(model.visibleEntries.isEmpty)
        #expect(model.selectedRecord == nil)
    }

    @Test("An Action row summarizes live participants without guessing its Target")
    func actionTitleSummarizesLiveParticipants() async throws {
        let targetID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let base = try makeAction(
            id: deterministicUUID(90),
            noteID: targetID,
            title: "Live Analysis",
            finishedAt: Date(timeIntervalSince1970: 100),
            isPinned: false
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

        #expect(model.visibleEntries.first?.contextTitle
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
        model.prepareForOpen(
            triptychID: record.triptychID,
            records: [record],
            request: ResearchRecordsWindowRequest(triptychID: record.triptychID)
        )

        await model.deletePermanently(recordID: record.id) { _ in }
        #expect(model.visibleEntries.isEmpty)
        #expect(model.selectedRecord == nil)
    }

    @Test("Closing a disposable comparison cancels its load")
    func comparisonCancellation() async throws {
        let record = try makeDiscussion(
            id: deterministicUUID(401),
            noteID: deterministicUUID(402),
            title: "Large Record",
            text: "Large comparison",
            author: .researcher,
            finishedAt: Date(timeIntervalSince1970: 100)
        )
        let model = ResearchRecordBrowserModel()
        model.prepareForOpen(
            triptychID: record.triptychID,
            records: [record],
            request: ResearchRecordsWindowRequest(triptychID: record.triptychID)
        )
        model.compare(recordID: record.id, noteID: record.participatingNotes[0].noteID) {
            _, _ in
            try await Task.sleep(for: .seconds(30))
            return ResearchRecordComparison(
                startingRevision: record.participatingNotes[0].startingRevision,
                endingRevision: record.participatingNotes[0].endingRevision!,
                startingHasUTF8BOM: false,
                endingHasUTF8BOM: false,
                lines: []
            )
        }
        #expect(model.comparingNoteID == record.participatingNotes[0].noteID)
        model.cancelComparison()
        await Task.yield()
        #expect(model.comparingNoteID == nil)
        #expect(model.comparison == nil)
        #expect(!model.isShowingError)
    }

    @Test("A stale noncooperative comparison cannot erase its replacement")
    func staleComparisonCannotReplaceCurrentResult() async throws {
        let record = try makeDiscussion(
            id: deterministicUUID(501),
            noteID: deterministicUUID(502),
            title: "Replacement Record",
            text: "Latest comparison wins",
            author: .researcher,
            finishedAt: Date(timeIntervalSince1970: 100)
        )
        let model = ResearchRecordBrowserModel()
        model.prepareForOpen(
            triptychID: record.triptychID,
            records: [record],
            request: ResearchRecordsWindowRequest(triptychID: record.triptychID)
        )
        let staleRevision = DocumentFingerprint(content: "stale")
        let currentRevision = DocumentFingerprint(content: "current")
        var staleContinuation: CheckedContinuation<ResearchRecordComparison, Never>?
        model.compare(recordID: record.id, noteID: record.participatingNotes[0].noteID) {
            _, _ in
            await withCheckedContinuation { continuation in
                staleContinuation = continuation
            }
        }
        await Task.yield()
        let continuation = try #require(staleContinuation)

        model.compare(recordID: record.id, noteID: record.participatingNotes[0].noteID) {
            _, _ in
            ResearchRecordComparison(
                startingRevision: currentRevision,
                endingRevision: currentRevision,
                startingHasUTF8BOM: false,
                endingHasUTF8BOM: false,
                lines: []
            )
        }
        await Task.yield()
        #expect(model.comparison?.startingRevision == currentRevision)

        continuation.resume(returning: ResearchRecordComparison(
            startingRevision: staleRevision,
            endingRevision: staleRevision,
            startingHasUTF8BOM: false,
            endingHasUTF8BOM: false,
            lines: []
        ))
        await Task.yield()
        #expect(model.comparison?.startingRevision == currentRevision)
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
            isPinned: false,
            recommendations: [try makeRecommendation(
                id: deterministicUUID(621),
                citation: "First source",
                doi: "https://doi.org/10.1000/same"
            )]
        )
        let second = try makeAction(
            id: deterministicUUID(612),
            noteID: secondNoteID,
            title: "Second Analysis",
            finishedAt: Date(timeIntervalSince1970: 200),
            isPinned: false,
            recommendations: [try makeRecommendation(
                id: deterministicUUID(622),
                citation: "Second source",
                doi: "doi:10.1000/same"
            )]
        )
        let model = ResearchRecordBrowserModel()
        let fingerprints = [
            first.id: DocumentFingerprint(content: "first record"),
            second.id: DocumentFingerprint(content: "second record"),
        ]
        let probe = ResearchRecordSearchProbe { request in
            let visible = request.query.contains(firstNoteID.uuidString.lowercased())
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
                isPinned: false,
                recommendations: [try makeRecommendation(
                    id: deterministicUUID(721),
                    citation: "Shared title",
                    doi: "https://doi.org/10.1000/exact",
                    zoteroItemKey: "ABCD1234"
                )]
            ),
            makeAction(
                id: deterministicUUID(712),
                noteID: noteID,
                title: "Analysis Two",
                finishedAt: Date(timeIntervalSince1970: 300),
                isPinned: false,
                recommendations: [try makeRecommendation(
                    id: deterministicUUID(722),
                    citation: "Shared title",
                    doi: "doi:10.1000/exact",
                    zoteroItemKey: "abcd1234"
                )]
            ),
            makeAction(
                id: deterministicUUID(713),
                noteID: noteID,
                title: "Analysis Three",
                finishedAt: Date(timeIntervalSince1970: 200),
                isPinned: false,
                recommendations: [try makeRecommendation(
                    id: deterministicUUID(723),
                    citation: "Shared title",
                    doi: "10.1000/exact",
                    zoteroItemKey: "CONFLICT"
                )]
            ),
            makeAction(
                id: deterministicUUID(714),
                noteID: noteID,
                title: "Analysis Four",
                finishedAt: Date(timeIntervalSince1970: 100),
                isPinned: false,
                recommendations: [try makeRecommendation(
                    id: deterministicUUID(724),
                    citation: "Shared title"
                )]
            ),
            makeAction(
                id: deterministicUUID(715),
                noteID: noteID,
                title: "Analysis Five",
                finishedAt: Date(timeIntervalSince1970: 50),
                isPinned: false,
                recommendations: [try makeRecommendation(
                    id: deterministicUUID(725),
                    citation: "A different work",
                    title: "Different work",
                    doi: "10.1000/exact",
                    zoteroItemKey: "ABCD1234"
                )]
            ),
        ]
        let index = ResearchLiteratureRecommendationDerivedIndex(records: records)
        let groups = index.query(text: "", noteID: nil, status: .all)

        #expect(groups.count == 4)
        #expect(groups.map(\.occurrences.count).sorted() == [1, 1, 1, 2])
        #expect(groups.flatMap(\.occurrences).count == 5)
        #expect(groups.filter(\.displaysSharedIdentityHeader).count == 1)
        #expect(groups.first { $0.occurrences.count == 1 }?
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
            records.append(try makeAction(
                id: deterministicUUID(20_000 + recordOrdinal),
                noteID: deterministicUUID(21_000 + recordOrdinal),
                title: "Analysis \(recordOrdinal)",
                finishedAt: Date(timeIntervalSince1970: Double(recordOrdinal)),
                isPinned: false,
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
            isPinned: false,
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
            isPinned: false,
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
        #expect(model.visibleRecommendationGroups.flatMap(\.occurrences).contains {
            $0.recommendation.id == targetID
        })
    }

    private func makeDiscussion(
        id: UUID,
        triptychID: UUID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        noteID: UUID,
        title: String,
        text: String,
        author: PortableResearchStatementAuthor,
        finishedAt: Date,
        isTombstone: Bool = false,
        isPinned: Bool = false
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
            kind: .discussion,
            action: nil,
            method: nil,
            primaryNoteID: noteID,
            participatingNotes: [note],
            statements: [statement],
            fidelityCompletion: .notApplicable,
            startedAt: finishedAt,
            finishedAt: finishedAt,
            isPinned: isPinned
        )
    }

    private func makeAction(
        id: UUID,
        noteID: UUID,
        title: String,
        finishedAt: Date,
        isPinned: Bool,
        recommendations: [ResearchLiteratureRecommendation] = []
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
            from: Data("""
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
            kind: .action,
            action: ResearchActionRecordIdentity(actionID: .analyze),
            method: method,
            sourceReference: try ResearchSourceReference(
                identity: .localFile(id: id),
                displayName: "Source.pdf",
                fingerprint: fingerprint
            ),
            participatingNotes: [note],
            statements: [try PortableResearchStatement(
                id: id,
                author: .agent,
                kind: .agentFeedback,
                attribution: "Agent",
                text: "The argument map was reviewed.",
                createdAt: finishedAt
            )],
            fidelityCompletion: .notRequired,
            literatureRecommendations: recommendations,
            startedAt: finishedAt,
            finishedAt: finishedAt,
            isPinned: isPinned
        )
    }

    private func makeRecommendation(
        id: UUID,
        citation: String,
        title: String = "Shared title",
        doi: String? = nil,
        zoteroItemKey: String? = nil
    ) throws -> ResearchLiteratureRecommendation {
        try ResearchLiteratureRecommendation(
            id: id,
            rawCitation: citation,
            title: title,
            doi: doi,
            zoteroItemKey: zoteroItemKey,
            reason: "The exact Analysis source identifies a relevant argument.",
            disposition: PortableResearchRecommendationDisposition(
                status: .unprocessed,
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
        let explanation = parsed.ast?.explanation(scope: request.presentationScope) ?? SearchExplanation(
            provider: .record,
            providerWasExplicit: true,
            scope: request.presentationScope,
            clauses: []
        )
        let results = records.compactMap { record -> SearchResult? in
            guard let fingerprint = fingerprints[record.id] else { return nil }
            let actionID = record.kind == .discussion
                ? ResearchActionID.discuss
                : record.action?.actionID ?? .discuss
            return .record(RecordSearchResult(
                recordID: record.id,
                matchedField: .context,
                matchedReason: "fixture provider result",
                context: record.researchRecordContextTitle ?? actionID.rawValue,
                actionID: actionID.rawValue,
                methodName: record.method?.displayName,
                sourceDisplayName: record.sourceReference?.displayName,
                finishedAt: record.finishedAt,
                pinned: record.isPinned,
                participatingNotes: record.participatingNotes.map(\.note),
                snippet: record.researchRecordContextTitle ?? actionID.rawValue,
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
            hasMore: false,
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
