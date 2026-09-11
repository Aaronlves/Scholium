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
        let target = NoteDocumentAttachmentTarget(noteID: fixture.analysisNoteID, vaultID: note.id.vaultID, relativePath: note.id.relativePath)
        for index in 0..<21 {
            let material = fixture.root.appendingPathComponent("Material-\(index).txt")
            try Data("Unread".utf8).write(to: material)
            _ = try await handle.documents.attachDocument(at: material, to: target, management: .copyIntoTriptych)
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
        _ = try await handle.documents.saveMetadata(note.id, fields: ["title": .string(String(repeating: "大", count: 50_000))], expectedRevision: nil)
        #expect(await router.handle(.init(tool: .readNote, arguments: args)).error?.code == .invalidRequest)
        let plain = try result(await router.handle(.init(tool: .readNote, arguments: scope)))
        #expect(plain["source"] == read["source"] && plain["context"] == .null)
        #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
    }

    @Test("Optional Note context separates exact prose, managed bibliography, binding and unread attachments")
    func noteContextAuthorities() async throws {
        let source = "\u{feff}---\r\ntitle: Authored custom title\r\nsummary: Researcher's description\r\n---\r\n# Analysis\r\nExact prose.\r\n"
        let fixture = try await Fixture.make(exactAnalysis: source)
        defer { fixture.dispose() }
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let snapshot = try await handle.discovery.refresh()
        let note = try #require(snapshot.vaults.flatMap(\.documents).first { $0.stableIdentity.resolvedID == fixture.analysisNoteID })
        let fields: [String: YAMLValue] = [
            "title": .string("Saved academic title"),
            "authors": .array([.object(["family": .string("王"), "given": .string("小明")]), .object(["literal": .string("Research Group")])]),
        ]
        _ = try await handle.documents.saveMetadata(note.id, fields: fields, expectedRevision: nil)
        let bindings = try await handle.services.controlStore.zoteroBindings()
        _ = try await handle.services.controlStore.setZoteroBinding(
            .init(noteID: fixture.analysisNoteID, library: .group(42), itemKey: "ITEM0001"), expectedRevision: bindings.revision)
        let material = fixture.root.appendingPathComponent("原文.txt")
        let unread = Data("Private-to-this-fixture attachment text must not enter a listing.".utf8)
        try unread.write(to: material)
        let attachment = try await handle.documents.attachDocument(
            at: material,
            to: .init(noteID: fixture.analysisNoteID, vaultID: note.id.vaultID, relativePath: note.id.relativePath), management: .copyIntoTriptych)
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        var args: [String: MCPJSONValue] = ["triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.analysisNoteID.uuidString)]
        let plain = try result(await router.handle(.init(tool: .readNote, arguments: args)))
        #expect(plain["context"] == .null && plain["source"]?.stringValue == source)
        args["include_context"] = .bool(true)
        let read = try result(await router.handle(.init(tool: .readNote, arguments: args)))
        let context = try #require(read["context"]?.objectValue)
        #expect(read["source"] == plain["source"] && read["fingerprint"] == plain["fingerprint"])
        let metadata = try #require(context["metadata"]?.objectValue)
        #expect(metadata["fields"]?.objectValue?["title"]?.stringValue == "Saved academic title")
        #expect(metadata["fields"]?.objectValue?["summary"] == nil)
        #expect(metadata["fields"]?.objectValue?["authors"]?.arrayValue?.first?.objectValue?["family"]?.stringValue == "王")
        let savedMetadata = try await handle.documents.metadata(note.id)
        #expect(try decodedFingerprint(metadata["fingerprint"]) == savedMetadata?.revision)
        let binding = try #require(context["zotero_binding"]?.objectValue)
        #expect(binding["library"]?.objectValue?["group_id"]?.intValue == 42)
        #expect(binding["item_key"]?.stringValue == "ITEM0001")
        #expect(binding["reference"]?.stringValue == "zotero://select/groups/42/items/ITEM0001")
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
        #expect(context["metadata"] == .null && context["zotero_binding"] == .null && context["zotero_bindings_fingerprint"] == .null)
        #expect(context["attachments"]?.objectValue?["total"]?.intValue == 0)
        args["note_id"] = .string(fixture.analysisNoteID.uuidString)
        let analysis = try result(await router.handle(.init(tool: .readNote, arguments: args)))
        #expect(analysis["context"]?.objectValue?["zotero_binding"] == .null)
        #expect(analysis["context"]?.objectValue?["zotero_bindings_fingerprint"]?.objectValue != nil)
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
        let record = control.appendingPathComponent(fixture.analysisNoteID.uuidString.lowercased() + ".json")
        let damaged = Data("damaged metadata".utf8)
        try damaged.write(to: record)
        #expect(await router.handle(.init(tool: .readNote, arguments: args)).error != nil)
        #expect(try Data(contentsOf: record) == damaged)
    }
}
