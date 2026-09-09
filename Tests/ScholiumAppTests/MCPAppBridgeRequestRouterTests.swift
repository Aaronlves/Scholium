import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApplication
@testable import ScholiumApp

@Suite("Running App MCP router", .serialized)
@MainActor
struct MCPAppBridgeRequestRouterTests {
    @Test("Chat move preview remains read-only and refers to the current Note location")
    func movePreviewChatReadOnly() async throws {
        let fixture = try await Fixture.make(standardTriptych: true)
        defer { fixture.dispose() }
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let snapshot = try await handle.discovery.refresh()
        let topic = try #require(snapshot.vaults.flatMap(\.documents).first { $0.stableIdentity.resolvedID == fixture.topicNoteID })
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        let controller = AgentChatController(triptychID: fixture.assignment.id, root: fixture.root.appendingPathComponent("Chat"), toolHandler: router.handle)
        func wait(_ predicate: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while !predicate() { try #require(ContinuousClock.now < deadline); try await Task.sleep(for: .milliseconds(10)) }
        }
        try await wait { controller.isLoaded }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let runtime = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: runtime, home: controller.runtimeHome, cli: runtime)
        try await wait { controller.state == .ready && controller.account != nil }
        controller.editDraft("hold source comparison"); controller.send()
        try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let token = try #require(controller.token)
        let result = try result(await controller.handle(.init(tool: .previewMove, arguments: [
            "note_id": .string(fixture.topicNoteID.uuidString), "relative_path": .string("Proposed.md"),
            "expected_fingerprint": .object(["sha256": .string(topic.fingerprint.sha256), "byte_count": .integer(topic.fingerprint.byteCount)])],
            conversationToken: token, runtimeContext: controller.runtimeContext(for: token))))
        #expect(result["can_move"]?.boolValue == true && controller.approvals.isEmpty)
        let activity = try #require(controller.selected?.messages.last(where: { $0.activity != nil })?.activity)
        #expect(activity.kind == .tool && activity.status == .completed)
        #expect(activity.files.first?.path == "Topic.md" && activity.files.first?.effect == nil)
        #expect(activity.detail.contains("Topic.md → Proposed.md"))
        #expect(!FileManager.default.fileExists(atPath: fixture.topicsURL.appendingPathComponent("Proposed.md").path))
        #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
        await controller.disconnect()
    }

    @Test("Move preview binds all exact link effects and agrees with the existing identity-preserving writer")
    func movePreviewMatchesWriter() async throws {
        let fixture = try await Fixture.make(standardTriptych: true)
        defer { fixture.dispose() }
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let topicURL = fixture.topicsURL.appendingPathComponent("Topic.md")
        let analysisURL = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")
        let workURL = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Works/Draft.md")
        let topicBytes = Data("# Topic\r\n\r\n[[Topic]]{{Self reference, no inferred support.}}\r\n".utf8)
        let workBytes = Data("---\nsummary: 'Keep exactly'\n---\n[[Topic|议题]]{{研究者说明。}}\n".utf8)
        try topicBytes.write(to: topicURL); try workBytes.write(to: workURL)
        let analysisBytes = try Data(contentsOf: analysisURL)
        let snapshot = try await handle.discovery.refresh()
        let topic = try #require(snapshot.vaults.flatMap(\.documents).first { $0.stableIdentity.resolvedID == fixture.topicNoteID })
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        var arguments: [String: MCPJSONValue] = ["triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.topicNoteID.uuidString),
            "expected_fingerprint": .object(["sha256": .string(topic.fingerprint.sha256), "byte_count": .integer(topic.fingerprint.byteCount)]),
            "relative_path": .string("Renamed.md"), "limit": .integer(1)]
        let first = try result(await router.handle(.init(tool: .previewMove, arguments: arguments)))
        #expect(first["can_move"]?.boolValue == true && first["total"]?.intValue == 3 && first["has_more"]?.boolValue == true)
        let fingerprint = try #require(first["plan_fingerprint"])
        let repeated = try result(await router.handle(.init(tool: .previewMove, arguments: arguments)))
        #expect(repeated["plan_fingerprint"] == fingerprint)
        arguments["offset"] = .integer(1)
        #expect(await router.handle(.init(tool: .previewMove, arguments: arguments)).error?.code == .invalidRequest)
        arguments["expected_plan_fingerprint"] = fingerprint; arguments["limit"] = .integer(100)
        let next = try result(await router.handle(.init(tool: .previewMove, arguments: arguments)))
        let rows = try #require(first["entries"]?.arrayValue) + (try #require(next["entries"]?.arrayValue))
        #expect(rows.count == 3 && next["has_more"]?.boolValue == false)
        #expect(rows.allSatisfy { $0.objectValue?["rewritten_occurrences"]?.intValue == 1 })
        #expect(try Data(contentsOf: topicURL) == topicBytes)
        #expect(try Data(contentsOf: analysisURL) == analysisBytes)
        #expect(try Data(contentsOf: workURL) == workBytes)
        #expect(!FileManager.default.fileExists(atPath: fixture.topicsURL.appendingPathComponent("Renamed.md").path))
        #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
        let outcome = try await handle.documents.move(topic.id, to: "Renamed.md", expectedRevision: topic.fingerprint)
        #expect(outcome.identityRecoveryWarning == nil)
        let after = try await handle.discovery.refresh()
        for row in rows {
            let entry = try #require(row.objectValue)
            let noteID = try #require(entry["note_id"]?.stringValue.flatMap(UUID.init(uuidString:)))
            let actual = try #require(after.vaults.flatMap(\.documents).first { $0.stableIdentity.resolvedID == noteID })
            #expect(actual.id.relativePath == entry["relative_path"]?.stringValue)
            #expect(actual.fingerprint == (try decodedFingerprint(entry["after_fingerprint"])))
        }
        #expect(try Data(contentsOf: analysisURL) == Data("\u{feff}# Alpha\r\n\r\n[[Renamed]]{{A scoped reason.}}\r\n".utf8))
        #expect(try Data(contentsOf: workURL) == Data("---\nsummary: 'Keep exactly'\n---\n[[Renamed|议题]]{{研究者说明。}}\n".utf8))
    }

    @Test("Move preview detects effect drift, collisions, ambiguity and path escape without changing source")
    func movePreviewRefusals() async throws {
        let fixture = try await Fixture.make(standardTriptych: true)
        defer { fixture.dispose() }
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let snapshot = try await handle.discovery.refresh()
        let topic = try #require(snapshot.vaults.flatMap(\.documents).first { $0.stableIdentity.resolvedID == fixture.topicNoteID })
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        var args: [String: MCPJSONValue] = ["triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.topicNoteID.uuidString),
            "expected_fingerprint": .object(["sha256": .string(topic.fingerprint.sha256), "byte_count": .integer(topic.fingerprint.byteCount)]), "relative_path": .string("Moved.md")]
        let initial = try result(await router.handle(.init(tool: .previewMove, arguments: args)))
        let analysis = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")
        let later = Data("\u{feff}[[Topic]]{{Later researcher comment.}}\r\n".utf8)
        try later.write(to: analysis)
        args["expected_plan_fingerprint"] = initial["plan_fingerprint"]
        #expect(await router.handle(.init(tool: .previewMove, arguments: args)).error?.code == .staleRevision)
        args["expected_plan_fingerprint"] = nil
        for path in ["../escape.md", "/tmp/escape.md", "Attachments/file.md", "Missing.ext"] {
            args["relative_path"] = .string(path)
            #expect(await router.handle(.init(tool: .previewMove, arguments: args)).error?.code == .invalidRequest)
        }
        let occupied = fixture.topicsURL.appendingPathComponent("Occupied.md")
        try Data("Unrelated target".utf8).write(to: occupied)
        args["relative_path"] = .string("Occupied.md")
        #expect(await router.handle(.init(tool: .previewMove, arguments: args)).error?.code == .invalidRequest)
        let outside = fixture.root.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.topicsURL.appendingPathComponent("Escape"), withDestinationURL: outside)
        args["relative_path"] = .string("Escape/Target.md")
        #expect(await router.handle(.init(tool: .previewMove, arguments: args)).error != nil)
        let collision = analysis.deletingLastPathComponent().appendingPathComponent("Collision.md")
        try Data("Local name blocks a cross-role incoming link".utf8).write(to: collision)
        args["relative_path"] = .string("Collision.md")
        let blocked = try result(await router.handle(.init(tool: .previewMove, arguments: args)))
        #expect(blocked["can_move"]?.boolValue == false)
        let blocker = try #require(blocked["entries"]?.arrayValue?.first { $0.objectValue?["kind"]?.stringValue == "blocked" }?.objectValue)
        #expect(try decodedFingerprint(blocker["before_fingerprint"]) == DocumentFingerprint(data: later))
        #expect(blocker["note_id"]?.stringValue == fixture.analysisNoteID.uuidString.lowercased())
        #expect(blocked["entries"]?.arrayValue?.contains { $0.objectValue?["kind"]?.stringValue == "blocked" && $0.objectValue?["source_locator"]?.objectValue != nil } == true)
        #expect(try Data(contentsOf: analysis) == later)
        #expect(try Data(contentsOf: occupied) == Data("Unrelated target".utf8))
        #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
    }

    @Test("Restoration refuses dirty/external revisions, unavailable scope, creation and cancellation")
    func changeToolsSafety() async throws {
        let fixture = try await Fixture.make(standardTriptych: true)
        defer { fixture.dispose() }
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        let base: [String: MCPJSONValue] = ["triptych_id": .string(fixture.assignment.id.uuidString)]
        func call(_ tool: ScholiumMCPToolName, _ arguments: [String: MCPJSONValue]) async -> ScholiumMCPBridgeResponse {
            await router.handle(.init(tool: tool, arguments: base.merging(arguments) { _, new in new }))
        }
        let creation = try result(await call(.createNote, ["role": .string("topics"), "relative_path": .string("Created Evidence.md"), "body": .string("Created source.")]))
        let receipt = try #require(creation["change_id"])
        let read = try result(await call(.readChange, ["change_id": receipt]))
        #expect(read["comparison"] == .null && read["can_undo"]?.boolValue == false)
        #expect(await call(.undoChange, ["change_id": receipt, "note_id": try #require(creation["note_id"]), "expected_fingerprint": try #require(creation["fingerprint"])]).error?.code == .invalidRequest)
        let update = try result(await call(.updateNote, ["note_id": .string(fixture.analysisNoteID.uuidString),
            "expected_fingerprint": .object(["sha256": .string(fixture.analysisFingerprint.sha256), "byte_count": .integer(fixture.analysisFingerprint.byteCount)]),
            "mode": .string("body"), "content": .string("Temporary ending")]))
        let args = base.merging(["note_id": .string(fixture.analysisNoteID.uuidString), "change_id": try #require(update["change_id"]),
            "expected_fingerprint": try #require(update["after_fingerprint"])]) { _, new in new }
        let request = ScholiumMCPBridgeRequest(tool: .undoChange, arguments: args)
        _ = try await router.previewUpdate(request)
        let file = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")
        let ending = try Data(contentsOf: file)
        let cancelled = Task { await router.handle(request) }; cancelled.cancel()
        #expect(await cancelled.value.error != nil)
        #expect(try Data(contentsOf: file) == ending)
        let closed = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in Issue.record("Closed scope must not flush") }, openTriptychs: { [] })
        #expect(await closed.handle(request).error != nil)
        let later = Data("The saved dirty buffer must survive Undo.".utf8)
        let dirty = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in try later.write(to: file) }, openTriptychs: { [fixture.assignment] })
        #expect(await dirty.handle(request).error?.code == .staleRevision)
        #expect(try Data(contentsOf: file) == later)
        let review = try result(await call(.readChange, ["change_id": try #require(update["change_id"])]))
        #expect(review["ending_revision_state"]?.stringValue == "earlier_revision" && review["can_undo"]?.boolValue == false)
        #expect(review["change"]?.objectValue?["state"]?.stringValue == "confirmed")
        #expect(try result(await call(.listChanges, [:]))["total"]?.intValue == 2)
    }

    @Test("Change tools retain exact history, page safely and restore only the bound current ending")
    func changeToolsLifecycle() async throws {
        let fixture = try await Fixture.make(standardTriptych: true)
        defer { fixture.dispose() }
        var flushes = 0
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in flushes += 1 }, openTriptychs: { [fixture.assignment] })
        let file = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")
        let original = try Data(contentsOf: file)
        func call(_ tool: ScholiumMCPToolName, _ arguments: [String: MCPJSONValue] = [:]) async -> ScholiumMCPBridgeResponse {
            var args = arguments; args["triptych_id"] = .string(fixture.assignment.id.uuidString)
            return await router.handle(.init(tool: tool, arguments: args))
        }
        let empty = try result(await call(.listChanges))
        #expect(empty["total"]?.intValue == 0 && flushes == 0)
        let fingerprint: MCPJSONValue = .object(["sha256": .string(fixture.analysisFingerprint.sha256), "byte_count": .integer(fixture.analysisFingerprint.byteCount)])
        let changed = try result(await call(.updateNote, ["note_id": .string(fixture.analysisNoteID.uuidString),
            "expected_fingerprint": fingerprint, "mode": .string("edits"), "edits": .array([.object([
                "start_utf8": .integer(3), "end_utf8": .integer(original.count),
                "expected_text": .string(String(decoding: original.dropFirst(3), as: UTF8.self)), "replacement": .string("Changed\r\n第二行\r\n")])])]))
        let changeID = try #require(changed["change_id"])
        let after = try #require(changed["after_fingerprint"])
        let list = try result(await call(.listChanges, ["note_id": .string(fixture.analysisNoteID.uuidString), "limit": .integer(1)]))
        #expect(list["total"]?.intValue == 1 && list["has_more"]?.boolValue == false)
        #expect(await call(.listChanges, ["offset": .integer(1)]).error?.code == .invalidRequest)
        #expect(await call(.listChanges, ["offset": .integer(1), "expected_listing_fingerprint": try #require(empty["listing_fingerprint"])]).error?.code == .staleRevision)
        let review = try result(await call(.readChange, ["change_id": changeID, "limit": .integer(1)]))
        #expect(review["can_undo"]?.boolValue == true && review["ending_revision_state"]?.stringValue == "current")
        let comparison = try #require(review["comparison"]?.objectValue)
        #expect(comparison["before_fingerprint"] == fingerprint && comparison["after_fingerprint"] == after)
        #expect(comparison["before_has_bom"]?.boolValue == true && comparison["after_has_bom"]?.boolValue == true)
        #expect(comparison["rows"]?.arrayValue?.count == 1 && comparison["has_more"]?.boolValue == true)
        let tail = try result(await call(.readChange, ["change_id": changeID, "offset": .integer(1)]))
        #expect(tail["comparison"]?.objectValue?["has_more"]?.boolValue == false)
        #expect(tail["comparison"]?.objectValue?["rows"]?.arrayValue?.contains { $0.objectValue?["line_ending"]?.stringValue == "CRLF" } == true)
        var undoArgs: [String: MCPJSONValue] = ["triptych_id": .string(fixture.assignment.id.uuidString),
            "note_id": .string(fixture.analysisNoteID.uuidString), "change_id": changeID, "expected_fingerprint": after]
        let beforePreviewFlushes = flushes
        let preview = try await router.previewUpdate(.init(tool: .undoChange, arguments: undoArgs))
        #expect(flushes == beforePreviewFlushes)
        #expect(preview.comparison.startingRevision == (try decodedFingerprint(after)))
        #expect(preview.comparison.endingRevision == fixture.analysisFingerprint)
        undoArgs["note_id"] = .string(fixture.topicNoteID.uuidString)
        #expect(await router.handle(.init(tool: .undoChange, arguments: undoArgs)).error?.code == .invalidRequest)
        undoArgs["note_id"] = .string(fixture.analysisNoteID.uuidString)
        let undone = try result(await router.handle(.init(tool: .undoChange, arguments: undoArgs)))
        #expect(undone["undone"]?.boolValue == true && undone["readback_verified"]?.boolValue == true)
        #expect(undone["after_fingerprint"] == fingerprint && undone["change_id"] == changeID)
        #expect(try Data(contentsOf: file) == original)
        let later = Data("Later researcher edit; never replay Undo.".utf8)
        try later.write(to: file)
        #expect(await router.handle(.init(tool: .undoChange, arguments: undoArgs)).error?.code == .invalidRequest)
        #expect(try Data(contentsOf: file) == later)
        let restored = try result(await call(.readChange, ["change_id": changeID]))
        #expect(restored["change"]?.objectValue?["state"]?.stringValue == "undone" && restored["can_undo"]?.boolValue == false)
        #expect(try result(await call(.listChanges))["total"]?.intValue == 1)
        #expect(await call(.readChange, ["change_id": .string(UUID().uuidString)]).error?.code == .notFound)
    }

    @Test("Undo Chat approval shows the exact reverse comparison and decline cannot restore source")
    func changeUndoChatAdmission() async throws {
        let fixture = try await Fixture.make(standardTriptych: true)
        defer { fixture.dispose() }
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        let file = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")
        let original = try Data(contentsOf: file)
        let updated = try result(await router.handle(.init(tool: .updateNote, arguments: [
            "triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.analysisNoteID.uuidString),
            "expected_fingerprint": .object(["sha256": .string(fixture.analysisFingerprint.sha256), "byte_count": .integer(fixture.analysisFingerprint.byteCount)]),
            "mode": .string("body"), "content": .string("Agent ending\r\n") ])))
        let ending = try Data(contentsOf: file)
        let controller = AgentChatController(triptychID: fixture.assignment.id, root: fixture.root.appendingPathComponent("Chat"),
            previewUpdate: router.previewUpdate, toolHandler: router.handle)
        func wait(_ predicate: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while !predicate() { try #require(ContinuousClock.now < deadline); try await Task.sleep(for: .milliseconds(10)) }
        }
        try await wait { controller.isLoaded }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let runtime = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: runtime, home: controller.runtimeHome, cli: runtime)
        try await wait { controller.state == .ready && controller.account != nil }
        controller.editDraft("hold source comparison"); controller.send()
        try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let token = try #require(controller.token)
        let request = ScholiumMCPBridgeRequest(tool: .undoChange, arguments: ["note_id": .string(fixture.analysisNoteID.uuidString),
            "change_id": try #require(updated["change_id"]), "expected_fingerprint": try #require(updated["after_fingerprint"])],
            conversationToken: token, runtimeContext: controller.runtimeContext(for: token))
        let declined = Task { await controller.handle(request) }
        try await wait { !controller.approvals.isEmpty }
        let approval = try #require(controller.approvals.first)
        #expect(approval.updatePreview?.comparison.startingRevision == DocumentFingerprint(data: ending))
        #expect(approval.updatePreview?.comparison.endingRevision == fixture.analysisFingerprint)
        controller.answer(approval.id, allow: false)
        #expect(await declined.value.error != nil)
        #expect(try Data(contentsOf: file) == ending)
        let allowed = Task { await controller.handle(request) }
        try await wait { !controller.approvals.isEmpty }
        controller.answer(try #require(controller.approvals.first?.id), allow: true)
        let response = try result(await allowed.value)
        #expect(response["undone"]?.boolValue == true)
        #expect(try Data(contentsOf: file) == original)
        #expect(controller.selected?.messages.last(where: { $0.activity != nil })?.activity?.status == .completed)
        #expect(await controller.handle(request).error != nil)
        #expect(controller.approvals.isEmpty)
        await controller.disconnect()
    }

    @Test("Library browse is bounded, role-scoped, revision-paged and identity-stable across rename")
    func browseLibraryInventory() async throws {
        let fixture = try await Fixture.make(standardTriptych: true)
        defer { fixture.dispose() }
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let folder = fixture.topicsURL.appendingPathComponent("Agent Browse")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Empty"), withIntermediateDirectories: true)
        for name in ["A", "B", "C"] { try Data((name + " exact source").utf8).write(to: folder.appendingPathComponent(name + ".md")) }
        func call(_ arguments: [String: MCPJSONValue] = [:]) async -> ScholiumMCPBridgeResponse {
            var args = arguments; args["triptych_id"] = .string(fixture.assignment.id.uuidString)
            return await router.handle(.init(tool: .browse, arguments: args))
        }
        let roots = try result(await call())
        #expect(roots["total"]?.intValue == 3)
        #expect(Set(try #require(roots["entries"]?.arrayValue).compactMap { $0.objectValue?["role"]?.stringValue }) == Set(["analyses", "topics", "works"]))
        let scope: [String: MCPJSONValue] = ["role": .string("topics"), "directory": .string("Agent Browse"), "limit": .integer(2)]
        let first = try result(await call(scope))
        #expect(first["total"]?.intValue == 4 && first["has_more"]?.boolValue == true)
        let firstRows = try #require(first["entries"]?.arrayValue)
        #expect(firstRows.count == 2 && firstRows[0].objectValue?["kind"]?.stringValue == "directory")
        let originalID = try #require(firstRows[1].objectValue?["note_id"]?.stringValue)
        var continuation = scope; continuation["offset"] = .integer(2)
        #expect(await call(continuation).error?.code == .invalidRequest)
        continuation["expected_listing_fingerprint"] = first["listing_fingerprint"]
        let next = try result(await call(continuation))
        #expect(next["has_more"]?.boolValue == false)
        #expect(try #require(next["entries"]?.arrayValue).compactMap { $0.objectValue?["relative_path"]?.stringValue } == ["Agent Browse/B.md", "Agent Browse/C.md"])
        let snapshot = try await handle.discovery.refresh()
        let note = try #require(snapshot.vaults.flatMap(\.documents).first { $0.id.relativePath == "Agent Browse/A.md" })
        _ = try await handle.documents.move(note.id, to: "Agent Browse/Renamed.md", expectedRevision: note.fingerprint)
        #expect(await call(continuation).error?.code == .staleRevision)
        var all = scope; all["limit"] = .integer(100)
        let renamed = try result(await call(all))
        let renamedRow = try #require(renamed["entries"]?.arrayValue?.first { $0.objectValue?["relative_path"]?.stringValue == "Agent Browse/Renamed.md" }?.objectValue)
        #expect(renamedRow["note_id"]?.stringValue == originalID)
        #expect(try decodedFingerprint(renamedRow["fingerprint"]) == note.fingerprint)
        let empty = try result(await call(["role": .string("topics"), "directory": .string("Agent Browse/Empty")]))
        #expect(empty["total"]?.intValue == 0 && empty["has_more"]?.boolValue == false)
        var beyond = all; beyond["offset"] = .integer(Int.max); beyond["expected_listing_fingerprint"] = renamed["listing_fingerprint"]
        #expect(try result(await call(beyond))["entries"]?.arrayValue?.isEmpty == true)
        for path in ["../works", "/tmp", "Agent Browse/../Empty", "Attachments", "Absent"] {
            #expect(await call(["role": .string("topics"), "directory": .string(path)]).error != nil)
        }
        #expect(await call(["directory": .string("Agent Browse")]).error?.code == .invalidRequest)
        #expect(await call(["role": .string("other")]).error?.code == .invalidRequest)
        #expect(await call(["limit": .integer(101)]).error?.code == .invalidRequest)
        let closed = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in Issue.record("Closed workspace must not flush") }, openTriptychs: { [] })
        #expect(await closed.handle(.init(tool: .browse, arguments: ["triptych_id": .string(fixture.assignment.id.uuidString)])).error != nil)
        // Empty one disposable copied role; no original fixture or real vault is touched.
        for entry in try FileManager.default.contentsOfDirectory(at: fixture.topicsURL, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: entry)
        }
        let emptyVault = try result(await call(["role": .string("topics")]))
        #expect(emptyVault["total"]?.intValue == 0)
        #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
    }

    @Test("Exact patch preview, commit and guarded Undo share one source transformation")
    func exactPatchLifecycle() async throws {
        let envelope = "\u{feff}---\r\nunknown: 'keep quoted' # authored\r\n---\r\n"
        let source = envelope + "重复\r\n重复\r\n👩🏽‍🔬 e\u{301}"
        let fixture = try await Fixture.make(standardTriptych: true, exactAnalysis: source)
        defer { fixture.dispose() }
        let file = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        var flushes = 0
        var receipts: [AgentChange] = []
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime,
            flushEditors: { _ in flushes += 1 }, openTriptychs: { [fixture.assignment] },
            didConfirmChange: { receipts.append($0) })
        let start = envelope.utf8.count
        let slice = try result(await router.handle(.init(tool: .readNote, arguments: [
            "triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.analysisNoteID.uuidString),
            "start_line": .integer(4), "line_count": .integer(2)])))
        #expect(slice["start_utf8"]?.intValue == start && slice["end_utf8"]?.intValue == start + 16)
        #expect(slice["source"]?.stringValue == "重复\r\n重复\r\n")
        flushes = 0
        func edit(_ start: Int, _ end: Int, _ expected: String, _ replacement: String) -> MCPJSONValue {
            .object(["start_utf8": .integer(start), "end_utf8": .integer(end),
                     "expected_text": .string(expected), "replacement": .string(replacement)])
        }
        let request = ScholiumMCPBridgeRequest(tool: .updateNote, arguments: [
            "triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.analysisNoteID.uuidString),
            "expected_fingerprint": .object(["sha256": .string(fixture.analysisFingerprint.sha256),
                                            "byte_count": .integer(fixture.analysisFingerprint.byteCount)]),
            "mode": .string("edits"), "edits": .array([
                edit(source.utf8.count, source.utf8.count, "", "!"),
                edit(start + 8, start + 16, "重复\r\n", ""),
                edit(start, start + 6, "重复", "改写"),
            ])])
        let expected = Data((envelope + "改写\r\n👩🏽‍🔬 e\u{301}!").utf8)
        let preview = try await router.previewUpdate(request)
        #expect(flushes == 0 && receipts.isEmpty)
        #expect(try Data(contentsOf: file) == Data(source.utf8))
        #expect(preview.comparison.endingRevision == DocumentFingerprint(data: expected))
        let response = try result(await router.handle(request))
        #expect(response["readback_verified"]?.boolValue == true)
        #expect(try Data(contentsOf: file) == expected)
        #expect(receipts.count == 1 && flushes == 1)
        let change = try #require(receipts.first)
        let review = try await handle.agentCollaboration.agentChangeReview(id: change.id)
        #expect(review.isDirectUndoAvailable)
        #expect(await router.handle(request).error?.code == .staleRevision)
        #expect(receipts.count == 1)
        let external = Data((envelope + "Later researcher text.").utf8)
        try external.write(to: file)
        await #expect(throws: (any Error).self) {
            try await handle.agentCollaboration.undoAgentChange(id: change.id, expectedAfterFingerprint: DocumentFingerprint(data: expected))
        }
        #expect(try Data(contentsOf: file) == external)
        // A fixture-only restoration recreates the eligible ending; the ordinary owner performs Undo.
        try expected.write(to: file)
        _ = try await handle.agentCollaboration.undoAgentChange(id: change.id, expectedAfterFingerprint: DocumentFingerprint(data: expected))
        #expect(try Data(contentsOf: file) == Data(source.utf8))
        await #expect(throws: (any Error).self) {
            try await handle.agentCollaboration.undoAgentChange(id: change.id, expectedAfterFingerprint: DocumentFingerprint(data: expected))
        }
        #expect(try Data(contentsOf: file) == Data(source.utf8))
    }

    @Test("Invalid exact patches and a dirty-buffer revision create no mutation evidence")
    func exactPatchRejection() async throws {
        let source = "\u{feff}---\r\nsummary: 'exact'\r\n---\r\nBody 👩🏽‍🔬"
        let fixture = try await Fixture.make(standardTriptych: true, exactAnalysis: source)
        defer { fixture.dispose() }
        let file = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        let base: [String: MCPJSONValue] = [
            "triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.analysisNoteID.uuidString),
            "expected_fingerprint": .object(["sha256": .string(fixture.analysisFingerprint.sha256),
                                            "byte_count": .integer(fixture.analysisFingerprint.byteCount)]),
            "mode": .string("edits")]
        func request(start: Int, end: Int, expected: String, replacement: String) -> ScholiumMCPBridgeRequest {
            var arguments = base
            arguments["edits"] = .array([.object(["start_utf8": .integer(start), "end_utf8": .integer(end),
                "expected_text": .string(expected), "replacement": .string(replacement)])])
            return .init(tool: .updateNote, arguments: arguments)
        }
        let noop = request(start: 0, end: 0, expected: "", replacement: "")
        #expect(await router.handle(noop).error?.code == .noChanges)
        #expect(await router.handle(request(start: 1, end: 1, expected: "", replacement: "x")).error?.code == .invalidRequest)
        #expect(await router.handle(request(start: 0, end: 3, expected: "abc", replacement: "")).error?.code == .invalidRequest)
        let summaryStart = "\u{feff}---\r\nsummary: ".utf8.count
        #expect(await router.handle(request(start: summaryStart, end: summaryStart + 7, expected: "'exact'", replacement: "[")).error?.code == .invalidRequest)
        var mixed = noop.arguments; mixed["content"] = .string("forbidden mixed payload")
        #expect(await router.handle(.init(tool: .updateNote, arguments: mixed)).error?.code == .invalidRequest)
        #expect(try Data(contentsOf: file) == Data(source.utf8))
        let valid = request(start: source.utf8.count, end: source.utf8.count, expected: "", replacement: "!")
        _ = try await router.previewUpdate(valid)
        let cancelled = Task {
            try await handle.agentCollaboration.updateNote(noteID: fixture.analysisNoteID,
                expectedFingerprint: fixture.analysisFingerprint,
                update: .edits([.init(startUTF8: source.utf8.count, endUTF8: source.utf8.count, expectedText: "", replacement: "!")]))
        }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(try Data(contentsOf: file) == Data(source.utf8))
        let dirtyBytes = Data((source + " researcher draft").utf8)
        let dirtyRouter = MCPAppBridgeRequestRouter(runtime: fixture.runtime,
            flushEditors: { _ in try dirtyBytes.write(to: file) }, openTriptychs: { [fixture.assignment] })
        #expect(await dirtyRouter.handle(valid).error?.code == .staleRevision)
        #expect(try Data(contentsOf: file) == dirtyBytes)
        #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
    }

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


    func result(_ response: ScholiumMCPBridgeResponse) throws
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

    func decodedFingerprint(
        _ value: MCPJSONValue?
    ) throws -> DocumentFingerprint {
        let object = try self.object(value)
        return DocumentFingerprint(
            sha256: try #require(object["sha256"]?.stringValue),
            byteCount: try #require(object["byte_count"]?.intValue)
        )
    }

    struct Fixture: @unchecked Sendable {
        let root: URL
        let runtime: WorkspaceRuntime
        let assignment: TriptychAssignment
        let topicsURL: URL
        let analysisNoteID: UUID
        let topicNoteID: UUID
        let analysisFingerprint: DocumentFingerprint

        static func make(name: String = "MCP Fixture", standardTriptych: Bool = false, exactAnalysis: String? = nil) async throws -> Fixture {
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
            if standardTriptych {
                for (source, destination) in [("01-analyses", analyses), ("02-topics", topics), ("03-works", works)] {
                    let original = repositoryRoot.appendingPathComponent("TestVaults/" + source)
                    for entry in try FileManager.default.contentsOfDirectory(at: original, includingPropertiesForKeys: nil) {
                        try FileManager.default.copyItem(at: entry, to: destination.appendingPathComponent(entry.lastPathComponent))
                    }
                }
            }
            let analysisBytes = Data(
                [0xEF, 0xBB, 0xBF] + Array(
                    "# Alpha\r\n\r\n[[Topic]]{{A scoped reason.}}\r\n".utf8
                )
            )
            let initialBytes = exactAnalysis.map { Data($0.utf8) } ?? analysisBytes
            try initialBytes.write(to: analyses.appendingPathComponent("Alpha.md"))
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
