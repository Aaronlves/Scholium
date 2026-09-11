import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp
@testable import ScholiumApplication

extension MCPAppBridgeRequestRouterTests {
    @Test("Metadata patches preserve unmentioned fields and authored bytes, and have exact review and guarded Undo")
    func metadataMutationLifecycle() async throws {
        let fixture = try await Fixture.make(exactAnalysis: "\u{feff}---\r\nsummary: 'Original' # Keep\r\ncustom: yes\r\n---\r\nExact body\r\n")
        defer { fixture.dispose() }
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let source = try await handle.agentCollaboration.currentNoteSource(noteID: fixture.analysisNoteID)
        var receipts: [AgentChange] = []
        let router = MCPAppBridgeRequestRouter(
            runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] }, didConfirmChange: { receipts.append($0) })
        var args: [String: MCPJSONValue] = [
            "triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.analysisNoteID.uuidString),
            "expected_fingerprint": fp(source.fingerprint), "expected_metadata_fingerprint": .null,
            "set": .object(["title": .string("Academic title"), "language": .string("fr"), "authors": .array([.object(["literal": .string("研究小组")])])]),
        ]
        let preview = try await router.previewUpdate(.init(tool: .updateMetadata, arguments: args))
        #expect(preview.operation == .metadata && preview.comparison.startingRevision != preview.comparison.endingRevision)
        #expect(try await handle.documents.metadata(source.note) == nil)
        let first = try result(await router.handle(.init(tool: .updateMetadata, arguments: args)))
        #expect(receipts.count == 1 && receipts[0].operation == .metadata && first["readback_verified"] == .bool(true))
        #expect(try await handle.agentCollaboration.currentNoteSource(noteID: fixture.analysisNoteID).source == source.source)
        #expect(await router.handle(.init(tool: .updateMetadata, arguments: args)).error != nil)
        let current = try #require(try await handle.documents.metadata(source.note))
        args["expected_metadata_fingerprint"] = fp(current.revision)
        args["set"] = .object(["title": .string("Revised title")])
        args["remove"] = .array([.string("language")])
        let second = try result(await router.handle(.init(tool: .updateMetadata, arguments: args)))
        let fields = try #require(try await handle.documents.metadata(source.note)).record.fields
        #expect(fields["title"] == .string("Revised title") && fields["language"] == nil && fields["authors"] == current.record.fields["authors"])
        func undo(_ result: [String: MCPJSONValue]) async -> ScholiumMCPBridgeResponse {
            await router.handle(
                .init(
                    tool: .undoChange,
                    arguments: [
                        "triptych_id": .string(fixture.assignment.id.uuidString),
                        "note_id": .string(fixture.analysisNoteID.uuidString), "change_id": result["change_id"]!,
                        "expected_fingerprint": result["after_fingerprint"]!,
                    ]))
        }
        #expect(await undo(first).error != nil)
        let review = try await handle.agentCollaboration.agentChangeReview(id: receipts[1].id)
        #expect(review.isDirectUndoAvailable && review.comparison != nil)
        #expect(await undo(second).error == nil)
        #expect(try await handle.documents.metadata(source.note)?.record == current.record)
        #expect(await undo(first).error == nil)
        #expect(try await handle.documents.metadata(source.note) == nil)
        #expect(try await handle.agentCollaboration.currentNoteSource(noteID: fixture.analysisNoteID).source == source.source)
        #expect(try await handle.agentCollaboration.agentChanges().allSatisfy { $0.state == .undone })
    }

    @Test("Invalid, stale, overlapping and authored-YAML Metadata writes are refused without receipts")
    func metadataMutationRefusals() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.dispose() }
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let source = try await handle.agentCollaboration.currentNoteSource(noteID: fixture.analysisNoteID)
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        let args: [String: MCPJSONValue] = [
            "triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.analysisNoteID.uuidString),
            "expected_fingerprint": fp(source.fingerprint), "expected_metadata_fingerprint": .null, "set": .object(["title": .string("Title")]),
        ]
        for override: [String: MCPJSONValue] in [
            ["set": .object(["summary": .string("Cannot become managed")])], ["set": .object(["authors": .string("Wrong shape")])],
            ["expected_fingerprint": fp(.init(content: "Stale"))], ["expected_metadata_fingerprint": fp(.init(content: "Stale"))],
            ["remove": .array([.string("title")])], ["unexpected_path": .string("/tmp")], ["triptych_id": .string(UUID().uuidString)],
        ] {
            #expect(await router.handle(.init(tool: .updateMetadata, arguments: args.merging(override) { _, new in new })).error != nil)
        }
        var absent = args
        absent["expected_metadata_fingerprint"] = nil
        #expect(await router.handle(.init(tool: .updateMetadata, arguments: absent)).error != nil)
        var empty = args
        empty["set"] = .object([:])
        #expect(await router.handle(.init(tool: .updateMetadata, arguments: empty)).error?.code == .noChanges)
        #expect(try await handle.documents.metadata(source.note) == nil)
        #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
        #expect(try await handle.agentCollaboration.currentNoteSource(noteID: fixture.analysisNoteID).source == source.source)
    }

    @Test("Attachment add, replacement and removal share review and Undo while preserving original and copied files")
    func attachmentMutationLifecycle() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.dispose() }
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let sourceNote = try await handle.agentCollaboration.currentNoteSource(noteID: fixture.analysisNoteID)
        let targetNote = try await handle.agentCollaboration.currentNoteSource(noteID: fixture.topicNoteID)
        var originals: [DocumentAttachmentSnapshot] = []
        for name in ["First", "Second"] {
            let file = fixture.root.appendingPathComponent(name + ".txt")
            try Data((name + " paper\r\n").utf8).write(to: file)
            originals.append(
                try await handle.documents.attachDocument(
                    at: file,
                    to: .init(noteID: fixture.analysisNoteID, vaultID: sourceNote.note.vaultID, relativePath: sourceNote.note.relativePath),
                    management: .copyIntoTriptych))
        }
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        let targetID = UUID()
        func args(_ action: String, _ original: DocumentAttachmentSnapshot? = nil) async throws -> [String: MCPJSONValue] {
            let listing = try await handle.agentCollaboration.attachments(noteID: fixture.topicNoteID)
            var result: [String: MCPJSONValue] = [
                "triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.topicNoteID.uuidString),
                "expected_fingerprint": fp(targetNote.fingerprint), "action": .string(action), "attachment_id": .string(targetID.uuidString),
                "expected_listing_fingerprint": fp(try listing.fingerprint(triptychID: fixture.assignment.id, noteID: fixture.topicNoteID)),
            ]
            if let original {
                let sourceListing = try await handle.agentCollaboration.attachments(noteID: fixture.analysisNoteID)
                let content = try await handle.agentCollaboration.readAttachment(
                    noteID: fixture.analysisNoteID, attachmentID: original.record.id,
                    expectedNoteFingerprint: sourceNote.fingerprint, request: .init(mode: .text))
                result["source"] = .object([
                    "note_id": .string(fixture.analysisNoteID.uuidString), "attachment_id": .string(original.record.id.uuidString),
                    "expected_listing_fingerprint": fp(try sourceListing.fingerprint(triptychID: fixture.assignment.id, noteID: fixture.analysisNoteID)),
                    "expected_fingerprint": fp(content.fingerprint),
                ])
            }
            return result
        }
        let addArgs = try await args("add", originals[0])
        let preview = try await router.previewUpdate(.init(tool: .updateAttachment, arguments: addArgs))
        #expect(preview.operation == .attachment)
        #expect(try await handle.agentCollaboration.attachments(noteID: fixture.topicNoteID).attachments.isEmpty)
        var stale = addArgs
        var badSource = try #require(stale["source"]?.objectValue)
        badSource["expected_fingerprint"] = fp(.init(content: "Different original"))
        stale["source"] = .object(badSource)
        #expect(await router.handle(.init(tool: .updateAttachment, arguments: stale)).error?.code == .staleRevision)
        badSource["path"] = .string("/not-authorized")
        stale["source"] = .object(badSource)
        #expect(await router.handle(.init(tool: .updateAttachment, arguments: stale)).error?.code == .invalidRequest)
        #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
        let added = try result(await router.handle(.init(tool: .updateAttachment, arguments: addArgs)))
        #expect(await router.handle(.init(tool: .updateAttachment, arguments: addArgs)).error != nil)
        let replaced = try result(await router.handle(.init(tool: .updateAttachment, arguments: try await args("replace", originals[1]))))
        let removed = try result(await router.handle(.init(tool: .updateAttachment, arguments: try await args("remove"))))
        #expect(try await handle.agentCollaboration.attachments(noteID: fixture.topicNoteID).attachments.isEmpty)
        for (result, expectedName) in [(removed, "Second.txt"), (replaced, "First.txt"), (added, "")] {
            let receipt = try #require(result["change_id"]?.stringValue.flatMap(UUID.init(uuidString:)))
            #expect(try await handle.agentCollaboration.agentChangeReview(id: receipt).isDirectUndoAvailable)
            let undone = await router.handle(
                .init(
                    tool: .undoChange,
                    arguments: [
                        "triptych_id": .string(fixture.assignment.id.uuidString),
                        "note_id": .string(fixture.topicNoteID.uuidString), "change_id": result["change_id"]!,
                        "expected_fingerprint": result["after_fingerprint"]!,
                    ]))
            #expect(undone.error == nil)
            #expect(try await handle.agentCollaboration.attachments(noteID: fixture.topicNoteID).attachments.first?.filename ?? "" == expectedName)
        }
        for original in originals {
            let filename = original.record.filename
            let copy = fixture.topicsURL.appendingPathComponent("Attachments/\(original.record.id.uuidString.lowercased())/\(filename)")
            #expect(try Data(contentsOf: copy) == Data(contentsOf: fixture.root.appendingPathComponent(filename)))
        }
        #expect(try await handle.agentCollaboration.currentNoteSource(noteID: fixture.topicNoteID).source == targetNote.source)
        #expect(try await handle.agentCollaboration.currentNoteSource(noteID: fixture.analysisNoteID).source == sourceNote.source)
    }

    private func fp(_ value: DocumentFingerprint) -> MCPJSONValue {
        .object(["sha256": .string(value.sha256), "byte_count": .integer(value.byteCount)])
    }
}
