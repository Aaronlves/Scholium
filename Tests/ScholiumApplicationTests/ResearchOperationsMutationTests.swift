import ScholiumContracts
import Foundation
@testable import ScholiumApplication
import Testing

@Suite("Application research operations")
struct ResearchOperationsMutationTests {
    @Test("Settlement is revision-bound and publishes research state")
    func settlementPublishesCurrentRevision() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let note = try #require(try await handle.snapshot().document(id: fixture.analysisID))
        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        _ = try #require(await iterator.next())
        let settled = try await handle.research.settle(
            fixture.analysisID,
            expectedRevision: note.fingerprint,
            rationale: "Stable for the current reconstruction."
        )
        #expect(settled.fingerprint == note.fingerprint)
        let event = try #require(await iterator.next())
        if case .researchRecordsChanged(let changed) = event {
            #expect(changed.research.settlements.contains { $0.id == settled.id })
        } else {
            Issue.record("A Settlement mutation did not publish researchRecordsChanged.")
        }

        try Data("# Analysis\n\nAn external revision.\n".utf8).write(
            to: fixture.analysesURL.appendingPathComponent("Analysis.md"),
            options: .atomic
        )
        await #expect(throws: VaultRepositoryError.self) {
            _ = try await handle.research.settle(
                fixture.analysisID,
                expectedRevision: note.fingerprint,
                rationale: "This stale Settlement must not land."
            )
        }
        await runtime.shutdown()
    }

    @Test("Checkpoint history follows identity across rename and restores exact bytes")
    func checkpointHistoryAndRestore() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let original = try await handle.documents.load(fixture.analysisID)
        let originalBytes = original.sourceBytes
        let checkpoint = try await handle.research.createCheckpoint(
            name: "Exact source",
            kind: .manual
        )

        let destinationPath = "Renamed Analysis.md"
        let move = try await handle.documents.move(
            fixture.analysisID,
            to: destinationPath,
            expectedRevision: original.fingerprint
        ).committedValue
        let moved = try await handle.documents.load(move.destination)
        let changed = try await handle.documents.save(
            move.destination,
            changeSet: .exactContent("# Changed\n\nA later revision.\n"),
            expectedRevision: moved.fingerprint
        ).committedValue

        let history = try await handle.research.noteCheckpoints(for: move.destination)
        #expect(history.contains { $0.id == checkpoint.id })
        let historical = try await handle.research.checkpointNoteContent(
            checkpoint.id,
            note: move.destination
        )
        #expect(Data(historical.utf8) == originalBytes)
        let comparison = try await handle.research.checkpointComparison(checkpoint.id)
        #expect(comparison.contains {
            $0.checkpointPath == fixture.analysisID.relativePath
                || $0.currentPath == destinationPath
        })

        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        _ = try #require(await iterator.next())
        let restored = try await handle.research.restoreNote(
            move.destination,
            from: checkpoint.id,
            expectedRevision: changed.document.fingerprint
        )
        #expect(restored.restoredFiles == [TriptychCheckpointFileKey(
            area: .analyses,
            relativePath: destinationPath
        )])
        let sourceEvent = try #require(await iterator.next())
        if case .sourceCommitted(let commit) = sourceEvent {
            if case .checkpointRestore(let restoredID) = commit.kind {
                #expect(restoredID == checkpoint.id)
            } else {
                Issue.record("Selective checkpoint restore used the wrong commit kind.")
            }
        } else {
            Issue.record("Selective checkpoint restore did not publish sourceCommitted.")
        }
        #expect(sourceEvent.snapshot.research.checkpointListing.checkpoints.contains {
            $0.id == restored.recoveryCheckpoint.id
        })

        let restoredData = try Data(contentsOf: fixture.analysesURL
            .appendingPathComponent(destinationPath))
        #expect(restoredData == originalBytes)
        #expect(restoredData.starts(with: [0xEF, 0xBB, 0xBF]))
        await runtime.shutdown()
    }

    @Test("Recovery operations stay inside the Application boundary")
    func recoveryOperations() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        // Seeding writes disposable fixture bytes before exercising only the
        // public delivery-neutral list/resolve surface and event publication.
        let recovery = TriptychMutationRecoveryRecord(
            triptychID: fixture.assignment.id,
            operation: .noteMove,
            failure: "Synthetic disposable-fixture rollback evidence",
            files: [TriptychMutationRecoveryFile(
                vaultID: fixture.analysisID.vaultID,
                path: fixture.analysisID.relativePath,
                role: .movedNote,
                beforeRevision: nil,
                intendedRevision: nil,
                observedRevision: nil,
                state: .externallyChanged,
                detail: "Fixture-only evidence"
            )]
        )
        try fixture.writeRecoveryFixture(recovery)
        _ = try await handle.discovery.refresh()
        #expect(try await handle.research.recoveryRecords().map(\.id) == [recovery.id])

        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        _ = try #require(await iterator.next())
        try await handle.research.resolveRecoveryRecord(recovery.id)
        let event = try #require(await iterator.next())
        if case .researchRecordsChanged(let changed) = event {
            #expect(changed.research.recoveryRecords.isEmpty)
        } else {
            Issue.record("Resolving recovery evidence did not publish researchRecordsChanged.")
        }
        #expect(try await handle.research.recoveryRecords().isEmpty)
        await runtime.shutdown()
    }

    @Test("Permanent Analysis deletion removes its machine-local source locator")
    func permanentDeletionPurgesSourceAccess() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let bindingURL = fixture.applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(fixture.assignment.id.uuidString, isDirectory: true)
            .appendingPathComponent("source-access", isDirectory: true)
            .appendingPathComponent("source-bindings-v1.json")
        let before = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: bindingURL)
            ) as? [String: Any]
        )
        let beforeBindings = try #require(before["bindings"] as? [[String: Any]])
        #expect(beforeBindings.contains {
            ($0["analysisNoteID"] as? String) == analysis.noteID.uuidString
                && ($0["canonicalPath"] as? String) == fixture.analysisSourceURL.path
        })

        let document = try await handle.documents.load(fixture.analysisID)
        let trashed = try await handle.documents.move(
            fixture.analysisID,
            to: "Trash/Analysis.md",
            expectedRevision: document.fingerprint
        ).committedValue
        let trashedDocument = try await handle.documents.load(trashed.destination)
        _ = try await handle.documents.deletePermanently(
            trashed.destination,
            expectedRevision: trashedDocument.fingerprint
        )

        let after = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: bindingURL)
            ) as? [String: Any]
        )
        let afterBindings = try #require(after["bindings"] as? [[String: Any]])
        #expect(!afterBindings.contains {
            ($0["analysisNoteID"] as? String) == analysis.noteID.uuidString
                || ($0["canonicalPath"] as? String) == fixture.analysisSourceURL.path
        })
        await runtime.shutdown()
    }

    @Test("A corrupt source store blocks permanent deletion before source bytes change")
    func corruptSourceStoreBlocksDeletionPreflight() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let document = try await handle.documents.load(fixture.analysisID)
        let trashed = try await handle.documents.move(
            fixture.analysisID,
            to: "Trash/Analysis.md",
            expectedRevision: document.fingerprint
        ).committedValue
        let trashedDocument = try await handle.documents.load(trashed.destination)
        let bindingURL = fixture.applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(fixture.assignment.id.uuidString, isDirectory: true)
            .appendingPathComponent("source-access", isDirectory: true)
            .appendingPathComponent("source-bindings-v1.json")
        try Data("corrupt".utf8).write(to: bindingURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: bindingURL.path
        )

        await #expect(throws: (any Error).self) {
            _ = try await handle.documents.deletePermanently(
                trashed.destination,
                expectedRevision: trashedDocument.fingerprint
            )
        }
        let unchanged = try Data(
            contentsOf: fixture.analysesURL.appendingPathComponent("Trash/Analysis.md")
        )
        #expect(unchanged == trashedDocument.sourceBytes)
        await runtime.shutdown()
    }
}


@Suite("Application Research Function orchestration")
struct ResearchFunctionOperationsTests {}

struct LocalExecutionTestProjection: Decodable {
    let snapshot: ResearchFunctionSnapshot
    let preparedInstructions: String
    let completion: ResearchFunctionCompletion?

    private enum CodingKeys: String, CodingKey {
        case snapshot
        case preparedInstructions = "prepared_instructions"
        case completion
    }
}

actor ZoteroRequestScript {
    enum Step: Sendable {
        case response(status: Int, data: Data)
        case transportFailure
    }

    private var steps: [Step]
    private var requests: [URLRequest] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !steps.isEmpty else { throw URLError(.badServerResponse) }
        let step = steps.removeFirst()
        switch step {
        case .transportFailure:
            throw URLError(.cannotConnectToHost)
        case .response(let status, let data):
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badServerResponse)
            }
            return (data, response)
        }
    }

    func requestCount() -> Int { requests.count }
}

struct ResearchFixture: Sendable {
    let rootURL: URL
    let applicationSupportURL: URL
    let analysesURL: URL
    let analysisSourceURL: URL
    let assignment: TriptychAssignment
    let analysisID: VaultQualifiedNoteID
    let topicID: VaultQualifiedNoteID
    let workID: VaultQualifiedNoteID

    static func make(
        analysisZoteroKey: String? = nil,
        workZoteroKey: String? = nil
    ) async throws -> Self {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = repositoryRoot
            .appendingPathComponent(".build/test-fixtures", isDirectory: true)
            .appendingPathComponent(
            "ScholiumApplicationResearchTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let appSupport = root.appendingPathComponent("Application Support", isDirectory: true)
        let registryURL = root.appendingPathComponent("Registry", isDirectory: true)
        let analyses = root.appendingPathComponent("Analyses", isDirectory: true)
        let topics = root.appendingPathComponent("Topics", isDirectory: true)
        let works = root.appendingPathComponent("Works", isDirectory: true)
        for directory in [appSupport, analyses, topics, works] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let analysisSourceFile = root.appendingPathComponent("Bound Source.pdf")
        try Data("Exact source fixture bytes.".utf8).write(
            to: analysisSourceFile,
            options: .atomic
        )

        let analysisKeyLine = analysisZoteroKey.map {
            "zotero_item_key: '\($0)'\r\n"
        } ?? ""
        let analysisSource = "\u{FEFF}---\r\ntitle: Analysis\r\n\(analysisKeyLine)research_unit:\r\n  completion: incomplete\r\nunknown_key: 'preserve me'\r\n---\r\n# Analysis\r\n\r\nExact philosophical claim with a narrow reconstruction. See [[Agency]].\r\n"
        try Data(analysisSource.utf8).write(
            to: analyses.appendingPathComponent("Analysis.md"),
            options: .atomic
        )
        try Data("---\ntitle: Agency\naliases:\n  - Freedom\n---\n# Agency\n\nSee [[Nested Topic]].\n".utf8).write(
            to: topics.appendingPathComponent("Agency.md"),
            options: .atomic
        )
        let debates = topics.appendingPathComponent("Debates", isDirectory: true)
        try FileManager.default.createDirectory(
            at: debates,
            withIntermediateDirectories: true
        )
        try Data("---\ntitle: Nested Topic\n---\n# Nested Topic\n".utf8).write(
            to: debates.appendingPathComponent("Nested Topic.md"),
            options: .atomic
        )
        let workKeyLine = workZoteroKey.map { "zotero_item_key: '\($0)'\n" } ?? ""
        try Data("---\ntitle: Draft Argument\nkind: chapter\n\(workKeyLine)---\n# Draft Argument\n\nA claim requiring Critique. See [[Analysis]].\n".utf8).write(
            to: works.appendingPathComponent("Draft Argument.md"),
            options: .atomic
        )

        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: appSupport,
            workspaceRegistryStorageURL: registryURL
        )))
        let handle = try await runtime.configureTriptych(
            paperAnalysisURL: analyses,
            topicKnowledgeURL: topics,
            outputURL: works,
            portableContainerURL: root,
            triptychName: "Research Operations Fixture"
        )
        let assignment = handle.assignment
        let analysisVaultID = try #require(assignment.vault(for: .paperAnalysis)?.id)
        let topicVaultID = try #require(assignment.vault(for: .topicKnowledge)?.id)
        let workVaultID = try #require(assignment.vault(for: .output)?.id)
        let analysisID = VaultQualifiedNoteID(
            vaultID: analysisVaultID,
            relativePath: "Analysis.md"
        )
        let sourceTarget = try await researchFunctionTarget(
            analysisID,
            role: .analysis,
            handle: handle
        )
        _ = try await handle.research.bindSourceAccess(ResearchSourceBindingRequest(
            target: sourceTarget,
            selection: .localFile(analysisSourceFile)
        ))
        await runtime.shutdown()
        return Self(
            rootURL: root,
            applicationSupportURL: appSupport,
            analysesURL: analyses,
            analysisSourceURL: analysisSourceFile,
            assignment: assignment,
            analysisID: analysisID,
            topicID: VaultQualifiedNoteID(
                vaultID: topicVaultID,
                relativePath: "Agency.md"
            ),
            workID: VaultQualifiedNoteID(
                vaultID: workVaultID,
                relativePath: "Draft Argument.md"
            )
        )
    }

    func runtime(zotero: ZoteroOperations? = nil) -> WorkspaceRuntime {
        WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: applicationSupportURL,
            assignments: [assignment]
        )), zotero: zotero)
    }

    func writeRecoveryFixture(_ record: TriptychMutationRecoveryRecord) throws {
        let storageURL = applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(assignment.id.uuidString, isDirectory: true)
            .appendingPathComponent("transactions", isDirectory: true)
        try FileManager.default.createDirectory(
            at: storageURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(RecoveryFixturePayload(records: [record]))
        try data.write(
            to: storageURL.appendingPathComponent("transaction-recovery.json"),
            options: .atomic
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

func researchFunctionTarget(
    _ id: VaultQualifiedNoteID,
    role: ResearchFunctionTargetRole,
    handle: WorkspaceHandle
) async throws -> ResearchFunctionTarget {
    let note = try #require(try await handle.snapshot().document(id: id))
    return ResearchFunctionTarget(
        noteID: try #require(note.stableIdentity.resolvedID),
        note: id,
        role: role,
        lifecycle: note.lifecycle,
        fingerprint: note.fingerprint,
        title: note.document.parsedFrontmatter["title"]?.scalarString ?? id.relativePath
    )
}

func expectSourceFailure(
    _ expected: ResearchSourceAccessFailureCode,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected source access failure \(expected.rawValue).")
    } catch let error as ResearchFunctionContractError {
        guard case .sourceAccessUnavailable(let failure) = error else {
            Issue.record("Unexpected Research Function failure: \(error)")
            return
        }
        #expect(failure.code == expected)
    } catch {
        Issue.record("Unexpected source access error: \(error)")
    }
}

func removingSourceReference(
    from value: Any,
    runID: UUID
) -> (value: Any, didRemove: Bool) {
    if var dictionary = value as? [String: Any] {
        var didRemove = false
        if let rawRunID = dictionary["runID"] as? String,
           UUID(uuidString: rawRunID) == runID,
           dictionary["request"] != nil {
            didRemove = dictionary.removeValue(forKey: "sourceReference") != nil
        }
        for (key, child) in dictionary {
            let result = removingSourceReference(from: child, runID: runID)
            dictionary[key] = result.value
            didRemove = didRemove || result.didRemove
        }
        return (dictionary, didRemove)
    }
    if let array = value as? [Any] {
        var didRemove = false
        let updated = array.map { child in
            let result = removingSourceReference(from: child, runID: runID)
            didRemove = didRemove || result.didRemove
            return result.value
        }
        return (updated, didRemove)
    }
    return (value, false)
}

func commentAnchor(
    in document: NoteDocument,
    quotation: String = "Exact philosophical claim"
) throws -> CommentAnchor {
    let range = try #require(document.rawContent.range(of: quotation))
    let lowerUTF16 = range.lowerBound.utf16Offset(in: document.rawContent)
    let upperUTF16 = range.upperBound.utf16Offset(in: document.rawContent)
    return try #require(CommentAnchorBuilder.anchor(
        in: document.rawContent,
        fingerprint: document.fingerprint,
        utf16Range: lowerUTF16..<upperUTF16
    ))
}

func createCommentExchange(
    for target: ResearchFunctionTarget,
    anchor: CommentAnchor,
    researcherText: String,
    agentText: String,
    finish: Bool,
    handle: WorkspaceHandle
) async throws -> UUID {
    let discussion = try await handle.research.createDiscussion(
        target: target,
        focalNotes: [],
        passage: anchor,
        researcherMessage: researcherText
    )
    _ = try await handle.research.appendDiscussionStatement(
        discussionID: discussion.id,
        author: .agent,
        attribution: "Research Agent",
        text: agentText
    )
    if finish {
        _ = try await handle.research.finishDiscussion(discussionID: discussion.id)
    }
    return discussion.id
}

func writePreparedResearchDocument(
    for preparation: ResearchFunctionPreparation,
    content: String,
    handle: WorkspaceHandle,
    requestID: UUID = UUID()
) async throws -> ResearchDocumentWriteResult {
    let target = preparation.snapshot.request.target
    let role: ResearchActionTargetRole = switch target.role {
    case .analysis: .analysis
    case .topic: .topic
    case .work: .work
    }
    let handoff = try await handle.research.issueAgentHandoff(
        runID: preparation.runID
    )
    let credential = try await handle.research.pairAgent(
        run: handoff.run,
        pairingCode: handoff.pairingCode
    )
    return try await handle.research.writeAgentDocument(
        credential: credential,
        run: handoff.run,
        intent: try ResearchDocumentWriteIntent(
            requestID: requestID,
            role: role,
            relativePath: target.note.relativePath,
            content: content
        )
    )
}

struct TestResearchAgentClient {
    let run: ResearchRunLocator
    let credential: ResearchConnectionCredential
}

func connectTestResearchAgent(
    to preparation: ResearchFunctionPreparation,
    handle: WorkspaceHandle
) async throws -> TestResearchAgentClient {
    let handoff = try await handle.research.issueAgentHandoff(
        runID: preparation.runID
    )
    let credential = try await handle.research.pairAgent(
        run: handoff.run,
        pairingCode: handoff.pairingCode
    )
    return TestResearchAgentClient(run: handoff.run, credential: credential)
}

func testAcademicResults(
    for action: ResearchActionSnapshot
) throws -> ResearchAcademicFieldValues {
    var rawValues: [String: ResearchAcademicFieldValue] = [:]
    for definition in action.resultContract.academicFields
        where definition.requirement != .excluded {
        let value: ResearchAcademicFieldValue = switch definition.kind {
        case .freeText:
            .freeText("Bounded test result for \(definition.label).")
        case .singleChoice:
            .singleChoice(try #require(definition.choices.first?.value))
        case .multipleChoice:
            .multipleChoice([try #require(definition.choices.first?.value)])
        }
        rawValues[definition.fieldID.rawValue] = value
    }
    let results = try ResearchAcademicFieldValues(
        rawValues: rawValues,
        definitions: action.resultContract.academicFields
    )
    try ResearchAcademicProfileCatalog.validatePlatformResultRules(
        results,
        actionID: action.actionID
    )
    return results
}

func makeTestAgentResultSubmission(
    for preparation: ResearchFunctionPreparation,
    disposition: ResearchAgentResultDisposition = .completed,
    contextUseClaims: [ResearchContextUseClaim] = [],
    fidelityOutcomes: [FidelityCheckOutcome] = [],
    literatureRecommendations: [ResearchLiteratureRecommendationSubmission]? = nil
) throws -> ResearchAgentResultSubmission {
    let action = try #require(preparation.snapshot.actionSnapshot)
    return try ResearchAgentResultSubmission(
        recordTitle: ResearchRecordTitle("Test research result"),
        disposition: disposition,
        academicResults: testAcademicResults(for: action),
        contextUseClaims: contextUseClaims,
        fidelityOutcomes: fidelityOutcomes,
        literatureRecommendations: literatureRecommendations
    )
}

func submitTestAgentResult(
    _ submission: ResearchAgentResultSubmission,
    client: TestResearchAgentClient,
    handle: WorkspaceHandle
) async throws -> ResearchAgentResultReceipt {
    try await handle.research.submitAgentResult(
        credential: client.credential,
        run: client.run,
        submission: submission
    )
}

func submitTestAgentResult(
    for preparation: ResearchFunctionPreparation,
    handle: WorkspaceHandle,
    disposition: ResearchAgentResultDisposition = .completed,
    contextUseClaims: [ResearchContextUseClaim] = [],
    fidelityOutcomes: [FidelityCheckOutcome] = [],
    literatureRecommendations: [ResearchLiteratureRecommendationSubmission]? = nil
) async throws -> ResearchAgentResultReceipt {
    let client = try await connectTestResearchAgent(
        to: preparation,
        handle: handle
    )
    return try await submitTestAgentResult(
        makeTestAgentResultSubmission(
            for: preparation,
            disposition: disposition,
            contextUseClaims: contextUseClaims,
            fidelityOutcomes: fidelityOutcomes,
            literatureRecommendations: literatureRecommendations
        ),
        client: client,
        handle: handle
    )
}

/// Legacy orchestration tests exercise the internal completion validator
/// directly. Current production runs first stage one strict Agent Result, so
/// this helper retries only the otherwise-valid missing-Result boundary after
/// installing a canonical test payload in the real Local Execution store.
func completeTestProtectedFunction(
    handle: WorkspaceHandle,
    submission: ResearchFunctionCompletionSubmission
) async throws -> ResearchFunctionCompletion {
    do {
        return try await handle.research.completeProtectedFunction(submission)
    } catch ResearchFunctionContractError.invalidCompletion(let reason)
        where reason.contains("canonical Result payload") {
        let local = try await handle.services.localResearchExecutionStore.record(
            id: submission.runID
        )
        let action = try #require(local.snapshot.actionSnapshot)
        let academicResults = try testAcademicResults(for: action)
        let payload = try ResearchRunResultPayload(
            runID: submission.runID,
            submissionFingerprint: DocumentFingerprint(
                content: "test-result:\(submission.runID.uuidString.lowercased())"
            ),
            recordTitle: submission.recordTitle,
            disposition: .completed,
            academicResults: academicResults,
            contextUseReport: nil,
            fidelityOutcomes: submission.fidelityOutcomes,
            literatureRecommendations: submission.literatureRecommendations,
            submittedAt: submission.submittedAt
        )
        _ = try await handle.services.localResearchExecutionStore
            .stageResultPayload(payload)
        return try await handle.research.completeProtectedFunction(submission)
    }
}

extension FidelityCheckOutcome {
    static let passedContent = passed(.content)

    static func passed(_ check: FidelityCheck) -> Self {
        Self(
            check: check,
            state: .passed,
            summary: "The named check found no unresolved issue in this fixture revision."
        )
    }
}

struct RecoveryFixturePayload: Codable {
    let records: [TriptychMutationRecoveryRecord]
}

struct LegacyResearchFileCanary: Equatable {
    let bytes: Data
    let digest: DocumentFingerprint
    let mode: Int
    let modificationDate: Date

    init(url: URL) throws {
        bytes = try Data(contentsOf: url)
        digest = DocumentFingerprint(data: bytes)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        mode = try #require((attributes[.posixPermissions] as? NSNumber)?.intValue)
        modificationDate = try #require(attributes[.modificationDate] as? Date)
    }
}

extension JSONDecoder {
    static var scholium: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
