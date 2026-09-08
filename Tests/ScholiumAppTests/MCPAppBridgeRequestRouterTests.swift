import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApplication
@testable import ScholiumApp

@Suite("Running App MCP router", .serialized)
@MainActor
struct MCPAppBridgeRequestRouterTests {
    @Test("Update preview performs no editor flush or write and exactly matches the eventual source transformation")
    func readOnlyUpdatePreview() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.dispose() }
        var flushes = 0
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime,
            flushEditors: { _ in flushes += 1 }, openTriptychs: { [fixture.assignment] })
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let file = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")
        let source = try Data(contentsOf: file)
        let fingerprint: MCPJSONValue = .object(["sha256": .string(fixture.analysisFingerprint.sha256),
            "byte_count": .integer(fixture.analysisFingerprint.byteCount)])
        let request = ScholiumMCPBridgeRequest(tool: .updateNote, arguments: [
            "triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.analysisNoteID.uuidString),
            "expected_fingerprint": fingerprint, "mode": .string("body"), "content": .string("# Revised\r\n\r\nExact new body.\r\n")])
        let preview = try await router.previewUpdate(request)
        #expect(preview.noteID == fixture.analysisNoteID && preview.relativePath == "Alpha.md")
        #expect(preview.comparison.startingRevision == fixture.analysisFingerprint && preview.comparison.startingHasUTF8BOM)
        #expect(flushes == 0)
        #expect(try Data(contentsOf: file) == source)
        #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
        var completeSource = request.arguments
        let replacement = "\u{feff}---\r\ncustom: 'keep quoted'\r\n---\r\nWhole replacement.\r\n"
        completeSource["mode"] = .string("source")
        completeSource["content"] = .string(replacement)
        let whole = try await router.previewUpdate(.init(tool: .updateNote, arguments: completeSource))
        #expect(whole.comparison.endingRevision == DocumentFingerprint(data: Data(replacement.utf8)))
        #expect(whole.comparison.endingHasUTF8BOM && flushes == 0)
        let result = try result(await router.handle(request))
        #expect(try decodedFingerprint(result["after_fingerprint"]) == preview.comparison.endingRevision)
        #expect(DocumentFingerprint(data: try Data(contentsOf: file)) == preview.comparison.endingRevision)
        #expect(flushes == 1)
        #expect(try await handle.agentCollaboration.agentChanges().count == 1)
        await #expect(throws: ScholiumMCPFailure.self) { try await router.previewUpdate(request) }
        #expect(flushes == 1)
        let closed = MCPAppBridgeRequestRouter(runtime: fixture.runtime,
            flushEditors: { _ in Issue.record("Preview must not flush") }, openTriptychs: { [] })
        await #expect(throws: ScholiumMCPFailure.self) { try await closed.previewUpdate(request) }
    }

    @Test("Chat comparison preserves source on decline and rejects a later external revision after Allow Once")
    func chatComparisonAdmission() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.dispose() }
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime,
            flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        let controller = AgentChatController(triptychID: fixture.assignment.id,
            root: fixture.root.appendingPathComponent("Chat"), previewUpdate: router.previewUpdate, toolHandler: router.handle)
        func wait(_ predicate: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while !predicate() {
                try #require(ContinuousClock.now < deadline, "Chat comparison did not reach the expected state")
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        try await wait { controller.isLoaded }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let executable = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: executable, home: controller.runtimeHome, cli: executable)
        try await wait { controller.account != nil && controller.state == .ready }
        controller.editDraft("hold source comparison"); controller.send()
        try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let token = try #require(controller.token)
        let arguments: [String: MCPJSONValue] = [
            "note_id": .string(fixture.analysisNoteID.uuidString), "mode": .string("body"),
            "content": .string("Proposed source from the Agent."), "expected_fingerprint": .object([
                "sha256": .string(fixture.analysisFingerprint.sha256), "byte_count": .integer(fixture.analysisFingerprint.byteCount)])]
        let file = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")
        let original = try Data(contentsOf: file)
        let declined = Task { await controller.handle(.init(tool: .updateNote, arguments: arguments, conversationToken: token, runtimeContext: controller.runtimeContext(for: token))) }
        try await wait { !controller.approvals.isEmpty }
        let approval = try #require(controller.approvals.first)
        #expect(approval.updatePreview?.comparison.startingRevision == fixture.analysisFingerprint)
        #expect(approval.detail == "Alpha.md" && controller.isAwaitingDecision(approval.id))
        controller.answer(approval.id, allow: false)
        #expect(await declined.value.error != nil)
        #expect(try Data(contentsOf: file) == original)
        #expect(!controller.isAwaitingDecision(approval.id))
        let stale = Task { await controller.handle(.init(tool: .updateNote, arguments: arguments, conversationToken: token, runtimeContext: controller.runtimeContext(for: token))) }
        try await wait { !controller.approvals.isEmpty }
        let pending = try #require(controller.approvals.first)
        let external = Data("External revision must survive.\r\n".utf8)
        try external.write(to: file)
        controller.answer(pending.id, allow: true)
        #expect(await stale.value.error?.code == .staleRevision)
        #expect(try Data(contentsOf: file) == external)
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
        await controller.disconnect()
    }

    @Test("Status, scoped Search, exact paging, and authored links share one current generation")
    func readOnlyToolsUseCurrentAppOwners() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.dispose() }

        let router = MCPAppBridgeRequestRouter(
            runtime: fixture.runtime,
            flushEditors: { triptychID in
                #expect(triptychID == fixture.assignment.id)
            },
            openTriptychs: { [fixture] in [fixture.assignment] }
        )

        let status = try result(await router.handle(ScholiumMCPBridgeRequest(
            tool: .workspaceStatus
        )))
        #expect(status["status"]?.stringValue == "ok")
        #expect(status["current"]?.boolValue == true)
        #expect(status["triptych_id"]?.stringValue ==
            fixture.assignment.id.uuidString.lowercased())
        let sourceGeneration = try object(status["source_generation"])
        let searchGeneration = try object(status["search_generation"])
        let graphGeneration = try object(status["graph_generation"])
        #expect(sourceGeneration["manifest_sha256"]?.stringValue ==
            searchGeneration["manifest_sha256"]?.stringValue)
        #expect(sourceGeneration["manifest_sha256"]?.stringValue ==
            graphGeneration["manifest_sha256"]?.stringValue)

        let search = try result(await router.handle(ScholiumMCPBridgeRequest(
            tool: .search,
            arguments: [
                "triptych_id": .string(fixture.assignment.id.uuidString),
                "query": .string("agency"),
                "roles": .array([.string("topics")]),
            ]
        )))
        let noteGroup = try object(search["notes"])
        let hits = try array(noteGroup["results"])
        #expect(hits.count == 1)
        let hit = try object(hits[0])
        #expect(hit["note_id"]?.stringValue == fixture.topicNoteID.uuidString.lowercased())
        #expect(hit["role"]?.stringValue == "topics")

        let firstPage = try result(await router.handle(ScholiumMCPBridgeRequest(
            tool: .search,
            arguments: [
                "triptych_id": .string(fixture.assignment.id.uuidString),
                "query": .string("agency"),
                "limit": .integer(1),
            ]
        )))
        let secondPage = try result(await router.handle(ScholiumMCPBridgeRequest(
            tool: .search,
            arguments: [
                "triptych_id": .string(fixture.assignment.id.uuidString),
                "query": .string("agency"),
                "limit": .integer(1),
                "offset": .integer(1),
            ]
        )))
        let firstNoteGroup = try object(firstPage["notes"])
        let secondNoteGroup = try object(secondPage["notes"])
        let firstPageHits = try array(firstNoteGroup["results"])
        let secondPageHits = try array(secondNoteGroup["results"])
        #expect(firstNoteGroup["offset"]?.intValue == 0)
        #expect(secondNoteGroup["offset"]?.intValue == 1)
        #expect(firstNoteGroup["has_more"]?.boolValue == true)
        #expect(secondNoteGroup["has_more"]?.boolValue == false)
        #expect(firstPageHits.count == 1)
        #expect(secondPageHits.count == 1)
        #expect(try object(firstPageHits[0])["note_id"]?.stringValue
            != object(secondPageHits[0])["note_id"]?.stringValue)

        let read = try result(await router.handle(ScholiumMCPBridgeRequest(
            tool: .readNote,
            arguments: [
                "triptych_id": .string(fixture.assignment.id.uuidString),
                "note_id": .string(fixture.analysisNoteID.uuidString),
                "start_line": .integer(1),
                "line_count": .integer(2),
            ]
        )))
        #expect(read["source"]?.stringValue == "\u{FEFF}# Alpha\r\n\r\n")
        #expect(read["complete"]?.boolValue == false)
        #expect(read["next_line"]?.intValue == 3)
        let readFingerprint = try object(read["fingerprint"])
        #expect(readFingerprint["sha256"]?.stringValue ==
            fixture.analysisFingerprint.sha256)
        #expect(readFingerprint["byte_count"]?.intValue ==
            fixture.analysisFingerprint.byteCount)

        let links = try result(await router.handle(ScholiumMCPBridgeRequest(
            tool: .listLinks,
            arguments: [
                "triptych_id": .string(fixture.assignment.id.uuidString),
                "note_id": .string(fixture.analysisNoteID.uuidString),
                "direction": .string("outgoing"),
            ]
        )))
        let occurrences = try array(links["links"])
        #expect(occurrences.count == 1)
        let occurrence = try object(occurrences[0])
        #expect(occurrence["occurrence_markup"]?.stringValue ==
            "[[Topic]]{{A scoped reason.}}")
        #expect(occurrence["link_markup"]?.stringValue == "[[Topic]]")
        #expect(occurrence["annotation_markup"]?.stringValue == "{{A scoped reason.}}")
        #expect(occurrence["annotation_text"]?.stringValue == "A scoped reason.")
        #expect(occurrence["source_note_id"]?.stringValue ==
            fixture.analysisNoteID.uuidString.lowercased())
        #expect(occurrence["destination_note_id"]?.stringValue ==
            fixture.topicNoteID.uuidString.lowercased())
    }

    @Test("Several open Triptychs require explicit scope without using window recency")
    func statusRequiresExplicitSelection() async throws {
        let first = try await Fixture.make(name: "First")
        let second = try await Fixture.make(name: "Second")
        defer {
            first.dispose()
            second.dispose()
        }
        let router = MCPAppBridgeRequestRouter(
            runtime: first.runtime,
            flushEditors: { _ in },
            openTriptychs: { [first, second] in
                [second.assignment, first.assignment]
            }
        )
        let value = try result(await router.handle(ScholiumMCPBridgeRequest(
            tool: .workspaceStatus
        )))
        #expect(value["current"]?.boolValue == false)
        #expect(value["selection_required"]?.boolValue == true)
        let candidates = try array(value["triptychs"])
        #expect(candidates.count == 2)
        #expect(try object(candidates[0])["triptych_id"]?.stringValue ==
            min(first.assignment.id.uuidString, second.assignment.id.uuidString).lowercased())
    }

    @Test("Sequential updates retain noncumulative exact review and direct Undo")
    func mutationsUseApplicationTransactions() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.dispose() }
        var deliveredChanges: [AgentChange] = []
        let router = MCPAppBridgeRequestRouter(
            runtime: fixture.runtime,
            flushEditors: { _ in },
            openTriptychs: { [fixture] in [fixture.assignment] },
            didConfirmChange: { deliveredChanges.append($0) }
        )
        let triptychID = fixture.assignment.id.uuidString

        let created = try result(await router.handle(ScholiumMCPBridgeRequest(
            tool: .createNote,
            arguments: [
                "triptych_id": .string(triptychID),
                "role": .string("topics"),
                "relative_path": .string("Nested/Exact.md"),
                "body": .string("\n# Line 1\r\nLine 2\r\n"),
            ]
        )))
        let noteIDString = try #require(created["note_id"]?.stringValue)
        let noteID = try #require(UUID(uuidString: noteIDString))
        let createChangeIDString = try #require(
            created["change_id"]?.stringValue
        )
        let createChangeID = try #require(UUID(uuidString: createChangeIDString))
        let initialFingerprint = try decodedFingerprint(created["fingerprint"])
        let createdURL = fixture.topicsURL
            .appendingPathComponent("Nested/Exact.md")
        let initialSource = "\n# Line 1\r\nLine 2\r\n"
        #expect(try Data(contentsOf: createdURL) == Data(initialSource.utf8))

        let unchanged = await router.handle(ScholiumMCPBridgeRequest(
            tool: .updateNote,
            arguments: [
                "triptych_id": .string(triptychID),
                "note_id": .string(noteID.uuidString),
                "expected_fingerprint": fingerprintJSON(initialFingerprint),
                "mode": .string("source"),
                "content": .string(initialSource),
            ]
        ))
        #expect(unchanged.error?.code == .noChanges)
        #expect(deliveredChanges.map(\.id) == [createChangeID])
        #expect(try Data(contentsOf: createdURL) == Data(initialSource.utf8))

        let updated = try result(await router.handle(ScholiumMCPBridgeRequest(
            tool: .updateNote,
            arguments: [
                "triptych_id": .string(triptychID),
                "note_id": .string(noteID.uuidString),
                "expected_fingerprint": fingerprintJSON(initialFingerprint),
                "mode": .string("body"),
                "content": .string("Revised A\r\nRevised B\r\n"),
            ]
        )))
        let updateChangeIDString = try #require(
            updated["change_id"]?.stringValue
        )
        let updateChangeID = try #require(UUID(uuidString: updateChangeIDString))
        let afterFingerprint = try decodedFingerprint(updated["after_fingerprint"])
        #expect(updated["readback_verified"]?.boolValue == true)
        #expect(try Data(contentsOf: createdURL) == Data(
            "Revised A\r\nRevised B\r\n".utf8
        ))

        let stale = await router.handle(ScholiumMCPBridgeRequest(
            tool: .updateNote,
            arguments: [
                "triptych_id": .string(triptychID),
                "note_id": .string(noteID.uuidString),
                "expected_fingerprint": fingerprintJSON(initialFingerprint),
                "mode": .string("body"),
                "content": .string("Must not commit"),
            ]
        ))
        #expect(deliveredChanges.map(\.id) == [createChangeID, updateChangeID])
        #expect(deliveredChanges.allSatisfy { $0.state == .confirmed })
        #expect(stale.error?.code == .staleRevision)
        #expect(try Data(contentsOf: createdURL).contains(Data("Revised A".utf8)))

        let handle = try await fixture.runtime.openWorkspace(
            id: fixture.assignment.id
        )
        let changes = try await handle.agentCollaboration.agentChanges()
        #expect(changes.map(\.id).contains(createChangeID))
        #expect(changes.map(\.id).contains(updateChangeID))
        #expect(changes.allSatisfy { $0.state == .confirmed })
        let currentReview = try await handle.agentCollaboration.agentChangeReview(
            id: updateChangeID
        )
        #expect(currentReview.change.noteID == noteID)
        #expect(currentReview.endingRevisionState == .current)
        #expect(currentReview.isDirectUndoAvailable)
        let comparison = try #require(currentReview.comparison)
        #expect(comparison.startingRevision == initialFingerprint)
        #expect(comparison.endingRevision == afterFingerprint)
        #expect(comparison.lines.contains {
            $0.kind == .startingOnly && $0.text.isEmpty
        })
        #expect(comparison.lines.contains {
            $0.kind == .endingOnly && $0.text == "Revised A"
        })
        let secondUpdated = try result(await router.handle(ScholiumMCPBridgeRequest(
            tool: .updateNote,
            arguments: [
                "triptych_id": .string(triptychID),
                "note_id": .string(noteID.uuidString),
                "expected_fingerprint": fingerprintJSON(afterFingerprint),
                "mode": .string("body"),
                "content": .string("Revised A\r\nRevised C\r\n"),
            ]
        )))
        let secondChangeIDString = try #require(
            secondUpdated["change_id"]?.stringValue
        )
        let secondChangeID = try #require(UUID(uuidString: secondChangeIDString))
        let secondFingerprint = try decodedFingerprint(
            secondUpdated["after_fingerprint"]
        )
        let firstEarlierReview = try await handle.agentCollaboration.agentChangeReview(
            id: updateChangeID
        )
        #expect(firstEarlierReview.endingRevisionState == .earlierRevision)
        #expect(!firstEarlierReview.isDirectUndoAvailable)
        #expect(firstEarlierReview.comparison?.startingRevision == initialFingerprint)
        #expect(firstEarlierReview.comparison?.endingRevision == afterFingerprint)

        let secondReview = try await handle.agentCollaboration.agentChangeReview(
            id: secondChangeID
        )
        #expect(secondReview.endingRevisionState == .current)
        #expect(secondReview.isDirectUndoAvailable)
        #expect(secondReview.comparison?.startingRevision == afterFingerprint)
        #expect(secondReview.comparison?.endingRevision == secondFingerprint)
        #expect(secondReview.comparison?.lines.contains {
            $0.kind == .startingOnly && $0.text == "Revised B"
        } == true)
        #expect(secondReview.comparison?.lines.contains {
            $0.kind == .endingOnly && $0.text == "Revised C"
        } == true)

        let secondUndone = try await handle.agentCollaboration.undoAgentChange(
            id: secondChangeID,
            expectedAfterFingerprint: secondFingerprint
        )
        #expect(secondUndone.restoredFingerprint == afterFingerprint)
        #expect(try Data(contentsOf: createdURL) == Data(
            "Revised A\r\nRevised B\r\n".utf8
        ))
        let firstCurrentAgain = try await handle.agentCollaboration.agentChangeReview(
            id: updateChangeID
        )
        #expect(firstCurrentAgain.endingRevisionState == .current)
        #expect(firstCurrentAgain.isDirectUndoAvailable)

        let undone = try await handle.agentCollaboration.undoAgentChange(
            id: updateChangeID,
            expectedAfterFingerprint: afterFingerprint
        )
        #expect(undone.restoredFingerprint == initialFingerprint)
        #expect(try Data(contentsOf: createdURL) == Data(initialSource.utf8))
        let undoneReview = try await handle.agentCollaboration.agentChangeReview(
            id: updateChangeID
        )
        #expect(undoneReview.change.state == .undone)
        #expect(undoneReview.endingRevisionState == .earlierRevision)
        #expect(!undoneReview.isDirectUndoAvailable)
        let createReview = try await handle.agentCollaboration.agentChangeReview(
            id: createChangeID
        )
        #expect(createReview.comparison == nil)
        #expect(createReview.currentCreatedSource == initialSource)
    }


    private func result(_ response: ScholiumMCPBridgeResponse) throws
        -> [String: MCPJSONValue]
    {
        if let error = response.error { throw error }
        return try object(response.result)
    }

    private func object(_ value: MCPJSONValue?) throws
        -> [String: MCPJSONValue]
    {
        try #require(value?.objectValue)
    }

    private func array(_ value: MCPJSONValue?) throws -> [MCPJSONValue] {
        try #require(value?.arrayValue)
    }

    private func fingerprintJSON(
        _ fingerprint: DocumentFingerprint
    ) -> MCPJSONValue {
        .object([
            "sha256": .string(fingerprint.sha256),
            "byte_count": .integer(fingerprint.byteCount),
        ])
    }

    private func decodedFingerprint(
        _ value: MCPJSONValue?
    ) throws -> DocumentFingerprint {
        let object = try self.object(value)
        return DocumentFingerprint(
            sha256: try #require(object["sha256"]?.stringValue),
            byteCount: try #require(object["byte_count"]?.intValue)
        )
    }

    private struct Fixture: @unchecked Sendable {
        let root: URL
        let runtime: WorkspaceRuntime
        let assignment: TriptychAssignment
        let topicsURL: URL
        let analysisNoteID: UUID
        let topicNoteID: UUID
        let analysisFingerprint: DocumentFingerprint

        static func make(name: String = "MCP Fixture") async throws -> Fixture {
            let repositoryRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let root = repositoryRoot
                .appendingPathComponent(".build/app-unit-state", isDirectory: true)
                .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
            let support = root.appendingPathComponent("ApplicationSupport", isDirectory: true)
            let registry = support.appendingPathComponent("Workspace", isDirectory: true)
            let triptychRoot = root.appendingPathComponent("Triptych", isDirectory: true)
            let analyses = triptychRoot.appendingPathComponent("Analyses", isDirectory: true)
            let topics = triptychRoot.appendingPathComponent("Topics", isDirectory: true)
            let works = triptychRoot.appendingPathComponent("Works", isDirectory: true)
            for directory in [support, registry, analyses, topics, works] {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            }
            let analysisBytes = Data(
                [0xEF, 0xBB, 0xBF] + Array(
                    "# Alpha\r\n\r\n[[Topic]]{{A scoped reason.}}\r\n".utf8
                )
            )
            try analysisBytes.write(to: analyses.appendingPathComponent("Alpha.md"))
            try Data("# Topic\n\nAgency and reasons.\n".utf8).write(
                to: topics.appendingPathComponent("Topic.md")
            )
            try Data("# Draft\n\nAgency appears here too.\n".utf8).write(
                to: works.appendingPathComponent("Draft.md")
            )

            let runtime = WorkspaceRuntime(configuration: .live(.init(
                applicationSupportURL: support,
                workspaceRegistryStorageURL: registry
            )))
            let handle = try await runtime.configureTriptych(
                paperAnalysisURL: analyses,
                topicKnowledgeURL: topics,
                outputURL: works,
                portableContainerURL: triptychRoot,
                triptychName: name
            )
            let snapshot = try await handle.discovery.refresh()
            let analysis = try #require(snapshot.vaults.flatMap(\.documents).first {
                $0.id.relativePath == "Alpha.md"
            })
            let topic = try #require(snapshot.vaults.flatMap(\.documents).first {
                $0.id.relativePath == "Topic.md"
            })
            return Fixture(
                root: root,
                runtime: runtime,
                assignment: handle.assignment,
                topicsURL: topics,
                analysisNoteID: try #require(analysis.stableIdentity.resolvedID),
                topicNoteID: try #require(topic.stableIdentity.resolvedID),
                analysisFingerprint: analysis.fingerprint
            )
        }

        func dispose() {
            Task { await runtime.shutdown() }
            try? FileManager.default.removeItem(at: root)
        }
    }
}
