import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp
@testable import ScholiumApplication

extension MCPAppBridgeRequestRouterTests {
    @Test("Note context pages material pointers and refuses oversized saved fields without losing source access")
    func noteContextBounds() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.dispose() }
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let snapshot = try await handle.discovery.refresh()
        let note = try #require(snapshot.vaults.flatMap(\.documents).first { $0.stableIdentity.resolvedID == fixture.analysisNoteID })
        let target = SourceAttachmentTarget(noteID: fixture.analysisNoteID, vaultID: note.id.vaultID, relativePath: note.id.relativePath)
        for index in 0..<21 {
            let material = fixture.root.appendingPathComponent("Material-\(index).txt")
            try Data("Unread".utf8).write(to: material)
            let prepared = try await handle.documents.prepareDocumentAttachment(at: material, to: target, management: .copyIntoTriptych)
            let current = try await handle.documents.load(note.id)
            _ = try await handle.documents.save(
                note.id, changeSet: .source(current.rawContent + "\n[Material](" + prepared.markdownDestination + ")\n"), expectedRevision: current.fingerprint)
        }
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        let scope: [String: MCPJSONValue] = ["triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.analysisNoteID.uuidString)]
        let args = scope.merging(["include_context": MCPJSONValue.bool(true)]) { _, new in new }
        let read = try result(await router.handle(.init(tool: .readNote, arguments: args)))
        let first = try #require(read["context"]?.objectValue?["attachments"]?.objectValue)
        #expect(first["total"]?.intValue == 21 && first["has_more"]?.boolValue == true)
        #expect(first["attachments"]?.arrayValue?.count == 20)
        let continuation = scope.merging(["offset": MCPJSONValue.integer(20), "expected_listing_fingerprint": try #require(first["listing_fingerprint"])]) {
            _, new in new
        }
        let last = try result(await router.handle(.init(tool: .listAttachments, arguments: continuation)))
        #expect(last["attachments"]?.arrayValue?.count == 1 && last["has_more"]?.boolValue == false)
        #expect(first["attachments"]?.arrayValue?.contains(try #require(last["attachments"]?.arrayValue?.first)) == false)
        let plain = try result(await router.handle(.init(tool: .readNote, arguments: scope)))
        #expect(plain["source"] == read["source"] && plain["context"] == .null)
        #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
    }

    @Test("Optional Note context separates exact prose, managed bibliography, binding and unread attachments")
    func noteContextAuthorities() async throws {
        var source = "\u{feff}---\r\ntitle: Authored custom title\r\nsummary: Researcher's description\r\n---\r\n# Analysis\r\nExact prose.\r\n"
        let fixture = try await Fixture.make(exactAnalysis: source)
        defer { fixture.dispose() }
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let snapshot = try await handle.discovery.refresh()
        let note = try #require(snapshot.vaults.flatMap(\.documents).first { $0.stableIdentity.resolvedID == fixture.analysisNoteID })
        let material = fixture.root.appendingPathComponent("原文.txt")
        let unread = Data("Private-to-this-fixture attachment text must not enter a listing.".utf8)
        try unread.write(to: material)
        let attachment = try await handle.documents.prepareDocumentAttachment(
            at: material,
            to: .init(noteID: fixture.analysisNoteID, vaultID: note.id.vaultID, relativePath: note.id.relativePath), management: .copyIntoTriptych)
        source += "\n[Material](" + attachment.markdownDestination + ")\n"
        _ = try await handle.documents.save(note.id, changeSet: .source(source), expectedRevision: note.fingerprint)
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        var args: [String: MCPJSONValue] = ["triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.analysisNoteID.uuidString)]
        let plain = try result(await router.handle(.init(tool: .readNote, arguments: args)))
        #expect(plain["context"] == .null && plain["source"]?.stringValue == source)
        args["include_context"] = .bool(true)
        let read = try result(await router.handle(.init(tool: .readNote, arguments: args)))
        let context = try #require(read["context"]?.objectValue)
        #expect(read["source"] == plain["source"] && read["fingerprint"] == plain["fingerprint"])
        #expect(Set(context.keys) == ["attachments"])
        let listing = try #require(context["attachments"]?.objectValue)
        #expect(listing["total"]?.intValue == 1)
        #expect(listing["attachments"]?.arrayValue?.first?.objectValue?["attachment_id"]?.stringValue == attachment.record.id.uuidString.lowercased())
        args["include_context"] = nil
        #expect(try result(await router.handle(.init(tool: .listAttachments, arguments: args))) == listing)
        #expect(!String(decoding: try JSONEncoder().encode(read), as: UTF8.self).contains(String(decoding: unread, as: UTF8.self)))
        #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
        #expect(try Data(contentsOf: fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")) == Data(source.utf8))
    }

    @Test("Absent context stays distinct from invalid records, stale source and closed workspace")
    func noteContextAbsenceAndRefusals() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.dispose() }
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        var args: [String: MCPJSONValue] = [
            "triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.topicNoteID.uuidString), "include_context": .bool(true),
        ]
        let read = try result(await router.handle(.init(tool: .readNote, arguments: args)))
        let context = try #require(read["context"]?.objectValue)
        #expect(context["attachments"]?.objectValue?["total"]?.intValue == 0)
        args["note_id"] = .string(fixture.analysisNoteID.uuidString)
        let analysis = try result(await router.handle(.init(tool: .readNote, arguments: args)))
        args["include_context"] = .string("true")
        #expect(await router.handle(.init(tool: .readNote, arguments: args)).error?.code == .invalidRequest)
        await #expect(throws: AgentCollaborationError.self) {
            try await handle.agentCollaboration.currentNoteContext(noteID: fixture.analysisNoteID, expectedFingerprint: .init(content: "Stale"))
        }
        args["include_context"] = .bool(true)
        let closed = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [] })
        #expect(await closed.handle(.init(tool: .readNote, arguments: args)).error != nil)
        let control = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent(".scholium/note-metadata/v1")
        try FileManager.default.createDirectory(at: control, withIntermediateDirectories: true)
        let orphan = control.appendingPathComponent("orphan.json")
        let bytes = Data("unsupported old record".utf8)
        try bytes.write(to: orphan)
        _ = try result(await router.handle(.init(tool: .readNote, arguments: args)))
        #expect(try Data(contentsOf: orphan) == bytes)

    }
}
