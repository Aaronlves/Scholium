import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApplication
@testable import ScholiumApp

extension MCPAppBridgeRequestRouterTests {
    @Test("Chat Ask compares every moved source, rechecks approval and records the exact inverse")
    func agentMoveChatAdmission() async throws {
        let fixture = try await Fixture.make(standardTriptych: true)
        defer { fixture.dispose() }
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        let controller = AgentChatController(triptychID: fixture.assignment.id,
            root: fixture.root.appendingPathComponent("Chat"), previewUpdate: { try await router.previewUpdate($0) },
            toolHandler: { await router.handle($0) })
        func wait(_ predicate: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while !predicate() {
                try #require(ContinuousClock.now < deadline, "Synthetic move conversation did not reach its expected state")
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let executable = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        try await wait { controller.isLoaded }
        controller.connect(executable: executable, home: controller.runtimeHome, cli: executable)
        try await wait { controller.state == .ready && controller.account != nil }
        controller.editDraft("hold"); controller.send()
        try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let token = try #require(controller.token)
        let context = try #require(controller.runtimeContext(for: token))
        let topicURL = fixture.topicsURL.appendingPathComponent("Topic.md")
        let linkedURL = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")
        let topicBytes = try Data(contentsOf: topicURL)
        var arguments: [String: MCPJSONValue] = ["triptych_id": .string(fixture.assignment.id.uuidString),
            "note_id": .string(fixture.topicNoteID.uuidString), "relative_path": .string("Moved.md"),
            "expected_fingerprint": .object(["sha256": .string(DocumentFingerprint(data: topicBytes).sha256), "byte_count": .integer(topicBytes.count)])]
        arguments["expected_plan_fingerprint"] = try result(await router.handle(.init(tool: .previewMove, arguments: arguments)))["plan_fingerprint"]
        func request(_ tool: ScholiumMCPToolName, _ args: [String: MCPJSONValue]) -> ScholiumMCPBridgeRequest {
            .init(tool: tool, arguments: args, conversationToken: token, runtimeContext: context)
        }
        let initialRequest = request(.moveNote, arguments)
        let declined = Task { await controller.handle(initialRequest) }
        try await wait { controller.approvals.count == 1 }
        let comparison = try #require(controller.approvals.first?.updatePreview)
        #expect(comparison.movePreview?.effects.count == 2 && comparison.linkedComparisons.count == 1)
        #expect(comparison.movePreview?.effects.first { $0.noteID == fixture.topicNoteID }?.source.relativePath == "Topic.md")
        #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
        controller.answer(try #require(controller.approvals.first?.id), allow: false)
        #expect(await declined.value.error != nil && FileManager.default.fileExists(atPath: topicURL.path))

        let stale = Task { await controller.handle(initialRequest) }
        try await wait { controller.approvals.count == 1 }
        let linkedBytes = Data("\u{feff}[[Topic]]{{Changed while awaiting approval.}}\r\n".utf8)
        try linkedBytes.write(to: linkedURL)
        controller.answer(try #require(controller.approvals.first?.id), allow: true)
        #expect(await stale.value.error?.code == .staleRevision)
        #expect(try Data(contentsOf: linkedURL) == linkedBytes && FileManager.default.fileExists(atPath: topicURL.path))
        #expect(try await handle.agentCollaboration.agentChanges().isEmpty)

        arguments["expected_plan_fingerprint"] = nil
        arguments["expected_plan_fingerprint"] = try result(await router.handle(.init(tool: .previewMove, arguments: arguments)))["plan_fingerprint"]
        let currentRequest = request(.moveNote, arguments)
        let approved = Task { await controller.handle(currentRequest) }
        try await wait { controller.approvals.count == 1 }
        controller.answer(try #require(controller.approvals.first?.id), allow: true)
        let moved = try result(await approved.value)
        let files = try #require(controller.selected?.messages.last?.activity?.files)
        #expect(files.count == 2 && files.contains { $0.path == "Moved.md" && $0.effect == .moved })
        #expect(files.contains { $0.noteID == fixture.analysisNoteID && $0.effect == .edited })
        let undoArgs: [String: MCPJSONValue] = ["triptych_id": .string(fixture.assignment.id.uuidString),
            "note_id": .string(fixture.topicNoteID.uuidString), "change_id": try #require(moved["change_id"]),
            "expected_fingerprint": try #require(moved["after_fingerprint"])]
        let undo = Task { await controller.handle(request(.undoChange, undoArgs)) }
        try await wait { controller.approvals.count == 1 }
        let inverse = try #require(controller.approvals.first?.updatePreview)
        #expect(inverse.movePreview?.effects.first { $0.noteID == fixture.topicNoteID }?.destination.relativePath == "Topic.md")
        #expect(inverse.linkedComparisons.first?.comparison.endingRevision == DocumentFingerprint(data: linkedBytes))
        controller.answer(try #require(controller.approvals.first?.id), allow: true)
        #expect(await undo.value.error == nil)
        #expect(try Data(contentsOf: topicURL) == topicBytes && Data(contentsOf: linkedURL) == linkedBytes)
        #expect(controller.selected?.messages.last?.activity?.files.contains { $0.path == "Topic.md" && $0.effect == .moved } == true)
        #expect(try await handle.agentCollaboration.agentChanges().first?.state == .undone)

        controller.stop(); try await wait { !controller.isBusy }
        controller.editDraft("hold new turn"); controller.send()
        try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
        #expect(await controller.handle(request(.moveNote, arguments)).error != nil)
        #expect(controller.approvals.isEmpty && FileManager.default.fileExists(atPath: topicURL.path))
        await controller.disconnect()
    }

    @Test("Agent move preserves identity, metadata and exact linked preimages through complete Undo")
    func agentMoveExactUndo() async throws {
        let fixture = try await Fixture.make(standardTriptych: true)
        defer { fixture.dispose() }
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let topicURL = fixture.topicsURL.appendingPathComponent("Topic.md")
        let analysisURL = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")
        let workURL = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Works/Draft.md")
        let topicBytes = Data("# Topic\r\n[[Topic]]{{Self connection only.}}\r\n".utf8)
        let workBytes = Data("---\nsummary: 'keep this'\n---\n[[Topic|议题]]{{研究者评论。}}\n".utf8)
        try topicBytes.write(to: topicURL); try workBytes.write(to: workURL)
        try FileManager.default.createDirectory(at: fixture.topicsURL.appendingPathComponent("Nested"), withIntermediateDirectories: true)
        let originalAnalysis = try Data(contentsOf: analysisURL)
        let snapshot = try await handle.discovery.refresh()
        let topic = try #require(snapshot.vaults.flatMap(\.documents).first { $0.stableIdentity.resolvedID == fixture.topicNoteID })
        let metadata = try await handle.documents.saveMetadata(topic.id, fields: ["aliases": .array([.string("Topic Alias")])], expectedRevision: nil)
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        func call(_ tool: ScholiumMCPToolName, _ args: [String: MCPJSONValue]) async -> ScholiumMCPBridgeResponse {
            await router.handle(.init(tool: tool, arguments: ["triptych_id": .string(fixture.assignment.id.uuidString)].merging(args) { _, value in value }))
        }
        var args: [String: MCPJSONValue] = ["note_id": .string(fixture.topicNoteID.uuidString), "relative_path": .string("Nested/Renamed.md"),
            "expected_fingerprint": .object(["sha256": .string(topic.fingerprint.sha256), "byte_count": .integer(topic.fingerprint.byteCount)])]
        let preview = try result(await call(.previewMove, args))
        args["expected_plan_fingerprint"] = preview["plan_fingerprint"]
        let moved = try result(await call(.moveNote, args))
        #expect(moved["readback_verified"]?.boolValue == true && moved["effects"]?.arrayValue?.count == 3)
        #expect(!FileManager.default.fileExists(atPath: topicURL.path))
        #expect(await call(.moveNote, args).error != nil)
        let changeID = try #require(moved["change_id"])
        let after = try await handle.discovery.refresh()
        let current = try #require(after.vaults.flatMap(\.documents).first { $0.stableIdentity.resolvedID == fixture.topicNoteID })
        #expect(current.id.relativePath == "Nested/Renamed.md" && current.metadata?.record == metadata.committedValue.record)
        let review = try result(await call(.readChange, ["change_id": changeID]))
        #expect(review["can_undo"]?.boolValue == true && review["change"]?.objectValue?["operation"]?.stringValue == "move")
        #expect(review["effects"]?.objectValue?["total"]?.intValue == 3)
        let linkedReview = try result(await call(.readChange, ["change_id": changeID, "note_id": .string(fixture.analysisNoteID.uuidString)]))
        #expect(try decodedFingerprint(linkedReview["comparison"]?.objectValue?["before_fingerprint"]) == DocumentFingerprint(data: originalAnalysis))
        #expect(try result(await call(.listChanges, ["note_id": .string(fixture.analysisNoteID.uuidString)]))["total"]?.intValue == 1)
        let undo: [String: MCPJSONValue] = ["note_id": .string(fixture.topicNoteID.uuidString), "change_id": changeID,
            "expected_fingerprint": try #require(moved["after_fingerprint"])]
        let undone = try result(await call(.undoChange, undo))
        #expect(undone["relative_path"]?.stringValue == "Topic.md" && undone["effects"]?.arrayValue?.count == 3)
        #expect(try Data(contentsOf: topicURL) == topicBytes)
        #expect(try Data(contentsOf: analysisURL) == originalAnalysis)
        #expect(try Data(contentsOf: workURL) == workBytes)
        #expect(!FileManager.default.fileExists(atPath: fixture.topicsURL.appendingPathComponent("Nested/Renamed.md").path))
        #expect(await call(.undoChange, undo).error != nil)
        let final = try await handle.discovery.refresh()
        let restored = try #require(final.vaults.flatMap(\.documents).first { $0.stableIdentity.resolvedID == fixture.topicNoteID })
        #expect(restored.metadata?.record == metadata.committedValue.record)
        let changes = try await handle.agentCollaboration.agentChanges()
        #expect(changes.count == 1 && changes[0].state == .undone && changes[0].moveEffects?.count == 3)
    }

    @Test("Agent move refuses changed plans and Undo refuses new links or redirected original aliases")
    func agentMoveScopeAndResolutionGuards() async throws {
        let fixture = try await Fixture.make(standardTriptych: true)
        defer { fixture.dispose() }
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let initial = try await handle.discovery.refresh()
        let topic = try #require(initial.vaults.flatMap(\.documents).first { $0.stableIdentity.resolvedID == fixture.topicNoteID })
        _ = try await handle.documents.saveMetadata(topic.id, fields: ["aliases": .array([.string("Topic Alias")])], expectedRevision: nil)
        let analysis = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")
        try Data("[[Topic Alias]]{{Authored relation, no inferred evidence.}}\n".utf8).write(to: analysis)
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        func call(_ tool: ScholiumMCPToolName, _ args: [String: MCPJSONValue]) async -> ScholiumMCPBridgeResponse {
            await router.handle(.init(tool: tool, arguments: ["triptych_id": .string(fixture.assignment.id.uuidString)].merging(args) { _, value in value }))
        }
        var args: [String: MCPJSONValue] = ["note_id": .string(fixture.topicNoteID.uuidString), "relative_path": .string("Moved.md"),
            "expected_fingerprint": .object(["sha256": .string(topic.fingerprint.sha256), "byte_count": .integer(topic.fingerprint.byteCount)])]
        let preview = try result(await call(.previewMove, args))
        args["expected_plan_fingerprint"] = preview["plan_fingerprint"]
        let revised = Data("[[Topic Alias]]{{Revised researcher comment.}}\n".utf8)
        try revised.write(to: analysis)
        #expect(await call(.moveNote, args).error?.code == .staleRevision)
        #expect(try Data(contentsOf: analysis) == revised)
        #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
        args["expected_plan_fingerprint"] = nil
        args["expected_plan_fingerprint"] = try result(await call(.previewMove, args))["plan_fingerprint"]
        let moved = try result(await call(.moveNote, args))
        let ending = try Data(contentsOf: analysis)
        let undo: [String: MCPJSONValue] = ["note_id": .string(fixture.topicNoteID.uuidString), "change_id": try #require(moved["change_id"]),
            "expected_fingerprint": try #require(moved["after_fingerprint"])]
        let newLink = fixture.topicsURL.appendingPathComponent("New Incoming.md")
        try Data("[[Moved]]\n".utf8).write(to: newLink)
        #expect(await call(.undoChange, undo).error?.code == .invalidRequest)
        #expect(try Data(contentsOf: analysis) == ending)
        try FileManager.default.removeItem(at: newLink)
        let collision = analysis.deletingLastPathComponent().appendingPathComponent("Topic Alias.md")
        try Data("An unrelated local Note would capture the original alias.\n".utf8).write(to: collision)
        let refusal = await call(.undoChange, undo)
        #expect(refusal.error?.code == .invalidRequest)
        #expect(refusal.error?.message.contains("resolve differently") == true)
        #expect(try Data(contentsOf: analysis) == ending)
        try FileManager.default.removeItem(at: collision)
        let later = Data("Later source edit\n".utf8)
        try later.write(to: analysis)
        #expect(await call(.undoChange, undo).error != nil)
        #expect(try Data(contentsOf: analysis) == later)
        #expect(FileManager.default.fileExists(atPath: fixture.topicsURL.appendingPathComponent("Moved.md").path))
        #expect(try await handle.agentCollaboration.agentChanges().first?.state == .confirmed)
    }
}
