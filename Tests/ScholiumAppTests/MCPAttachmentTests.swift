import CoreGraphics
import CoreText
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp
@testable import ScholiumApplication

extension MCPAppBridgeRequestRouterTests {
    @Test("Registered images become readable only through the current Note's authored image relationship")
    func attachmentImageRelationship() async throws {
        let fixture = try await Fixture.make(standardTriptych: true)
        defer { fixture.dispose() }
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let snapshot = try await handle.discovery.refresh()
        let note = try #require(snapshot.vaults.flatMap(\.documents).first { $0.stableIdentity.resolvedID == fixture.topicNoteID })
        let source = fixture.root.appendingPathComponent("Figure.png")
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        try png.write(to: source)
        let imported = try await handle.documents.importImageAttachment(at: source, for: note.id)
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        let scope: [String: MCPJSONValue] = ["triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.topicNoteID.uuidString)]
        let before = try result(await router.handle(.init(tool: .listAttachments, arguments: scope)))
        #expect(before["total"]?.intValue == 0)
        let noteURL = fixture.topicsURL.appendingPathComponent("Topic.md")
        let original = try Data(contentsOf: noteURL)
        try Data(("# Topic\n![Researcher figure](" + imported.markdownDestination + ")\n").utf8).write(to: noteURL)
        let listing = try result(await router.handle(.init(tool: .listAttachments, arguments: scope)))
        #expect(listing["total"]?.intValue == 1 && listing["attachments"]?.arrayValue?.first?.objectValue?["relationship"]?.stringValue == "authoredImage")
        let args = scope.merging([
            "attachment_id": MCPJSONValue.string(imported.record.id.uuidString), "expected_note_fingerprint": try #require(listing["note_fingerprint"]),
            "mode": .string("image"),
        ]) { _, new in new }
        let image = try result(await router.handle(.init(tool: .readAttachment, arguments: args)))
        #expect(image["kind"]?.stringValue == "image" && image["image"]?.objectValue?["pixel_width"]?.intValue == 1)
        #expect(image["text"] == .null && image["page"] == .null)
        try original.write(to: noteURL)
        #expect(await router.handle(.init(tool: .readAttachment, arguments: args)).error?.code == .staleRevision)
        #expect(try Data(contentsOf: source) == png)
        #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
    }

    @Test("Related attachment reads preserve UTF-8 bytes, scope, continuation versions and file containment")
    func attachmentTextScope() async throws {
        let fixture = try await Fixture.make(standardTriptych: true)
        defer { fixture.dispose() }
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let snapshot = try await handle.discovery.refresh()
        let note = try #require(snapshot.vaults.flatMap(\.documents).first { $0.stableIdentity.resolvedID == fixture.topicNoteID })
        let target = SourceAttachmentTarget(noteID: fixture.topicNoteID, vaultID: note.id.vaultID, relativePath: note.id.relativePath)
        let source = fixture.root.appendingPathComponent("原文.txt")
        let bytes = Data("\u{feff}α研究\r\nExact ending\r\n".utf8)
        try bytes.write(to: source)
        let attachment = try await handle.documents.prepareDocumentAttachment(at: source, to: target, management: .copyIntoTriptych)
        let attachmentBefore = try await handle.documents.load(note.id)
        let attachmentDocument = try await handle.documents.save(
            note.id,
            changeSet: .source(attachmentBefore.rawContent + "\n[Material](" + attachment.markdownDestination + ")\n"),
            expectedRevision: attachmentBefore.fingerprint
        ).committedValue.document
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        func call(_ tool: ScholiumMCPToolName, _ extra: [String: MCPJSONValue] = [:]) async -> ScholiumMCPBridgeResponse {
            await router.handle(
                .init(
                    tool: tool,
                    arguments: [
                        "triptych_id": .string(fixture.assignment.id.uuidString),
                        "note_id": .string(fixture.topicNoteID.uuidString),
                    ].merging(extra) { _, new in new }))
        }
        let listing = try result(await call(.listAttachments))
        #expect(listing["total"]?.intValue == 1 && listing["attachments"]?.arrayValue?.first?.objectValue?["available"]?.boolValue == true)
        #expect(await call(.listAttachments, ["offset": .integer(1)]).error?.code == .invalidRequest)
        #expect(
            try result(await call(.listAttachments, ["offset": .integer(1), "expected_listing_fingerprint": try #require(listing["listing_fingerprint"])]))[
                "attachments"]?.arrayValue?.isEmpty == true)
        var read: [String: MCPJSONValue] = [
            "attachment_id": .string(attachment.record.id.uuidString),
            "expected_note_fingerprint": try #require(listing["note_fingerprint"]), "mode": .string("text"), "max_utf8": .integer(5),
        ]
        let first = try result(await call(.readAttachment, read))
        #expect(first["text"]?.stringValue?.utf8.elementsEqual(bytes.prefix(5)) == true)
        #expect(first["end_utf8"]?.intValue == 5 && first["has_more"]?.boolValue == true)
        read["start_utf8"] = .integer(5)
        #expect(await call(.readAttachment, read).error?.code == .invalidRequest)
        read["expected_fingerprint"] = first["fingerprint"]
        read["max_utf8"] = .integer(65_536)
        let remainder = try result(await call(.readAttachment, read))
        #expect(remainder["text"]?.stringValue?.utf8.elementsEqual(bytes.dropFirst(5)) == true)
        #expect(remainder["has_more"]?.boolValue == false)
        let external = try await handle.documents.prepareDocumentAttachment(at: source, to: target, management: .referenceOriginal)
        let externalBefore = try await handle.documents.load(note.id)
        let externalDocument = try await handle.documents.save(
            note.id,
            changeSet: .source(externalBefore.rawContent + "\n[Material](" + external.markdownDestination + ")\n"),
            expectedRevision: externalBefore.fingerprint
        ).committedValue.document
        var externalRead = read
        externalRead["attachment_id"] = .string(external.record.id.uuidString)
        externalRead["start_utf8"] = .integer(0)
        externalRead["expected_note_fingerprint"] = .object([
            "sha256": .string(externalDocument.fingerprint.sha256), "byte_count": .integer(externalDocument.fingerprint.byteCount),
        ])
        let indexed = try result(await call(.readAttachment, externalRead))
        #expect(indexed["text"]?.stringValue?.utf8.elementsEqual(bytes) == true)
        #expect(
            await call(.listAttachments, ["offset": .integer(1), "expected_listing_fingerprint": try #require(listing["listing_fingerprint"])]).error?.code
                == .staleRevision)
        read["note_id"] = .string(fixture.analysisNoteID.uuidString)
        read["expected_note_fingerprint"] = .object([
            "sha256": .string(fixture.analysisFingerprint.sha256), "byte_count": .integer(fixture.analysisFingerprint.byteCount),
        ])
        #expect(await call(.readAttachment, read).error?.code == .notFound)
        read["note_id"] = nil
        read["expected_note_fingerprint"] = externalRead["expected_note_fingerprint"]
        guard case .vaultRelative(let path) = attachment.record.location else {
            Issue.record("Expected copied attachment")
            return
        }
        let copy = fixture.topicsURL.appendingPathComponent(path.rawValue)
        try Data("Changed original attachment".utf8).write(to: copy)
        #expect(await call(.readAttachment, read).error?.code == .staleRevision)
        try FileManager.default.removeItem(at: copy)
        try FileManager.default.createSymbolicLink(at: copy, withDestinationURL: source)
        #expect(await call(.readAttachment, read).error != nil)
        #expect(try Data(contentsOf: source) == bytes)
        #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
    }

    @Test("PDF attachments return only the selected text or rendered page with explicit coverage")
    func attachmentPDFPage() async throws {
        let fixture = try await Fixture.make(standardTriptych: true)
        defer { fixture.dispose() }
        let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
        let snapshot = try await handle.discovery.refresh()
        let note = try #require(snapshot.vaults.flatMap(\.documents).first { $0.stableIdentity.resolvedID == fixture.topicNoteID })
        let target = SourceAttachmentTarget(noteID: fixture.topicNoteID, vaultID: note.id.vaultID, relativePath: note.id.relativePath)
        let source = fixture.root.appendingPathComponent("Selected.pdf")
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: nil, nil))
        for text in ["First page excluded", "Second page selected"] {
            context.beginPDFPage(nil)
            context.textPosition = CGPoint(x: 40, y: 500)
            let value = NSAttributedString(
                string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 14, nil)])
            CTLineDraw(CTLineCreateWithAttributedString(value), context)
            context.endPDFPage()
        }
        context.closePDF()
        try (data as Data).write(to: source)
        let attachment = try await handle.documents.prepareDocumentAttachment(at: source, to: target, management: .copyIntoTriptych)
        let attachmentBefore = try await handle.documents.load(note.id)
        let attachmentDocument = try await handle.documents.save(
            note.id,
            changeSet: .source(attachmentBefore.rawContent + "\n[Material](" + attachment.markdownDestination + ")\n"),
            expectedRevision: attachmentBefore.fingerprint
        ).committedValue.document
        let router = MCPAppBridgeRequestRouter(runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        var args: [String: MCPJSONValue] = [
            "triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.topicNoteID.uuidString),
            "attachment_id": .string(attachment.record.id.uuidString),
            "expected_note_fingerprint": .object([
                "sha256": .string(attachmentDocument.fingerprint.sha256), "byte_count": .integer(attachmentDocument.fingerprint.byteCount),
            ]),
            "mode": .string("text"),
        ]
        #expect(await router.handle(.init(tool: .readAttachment, arguments: args)).error?.code == .invalidRequest)
        args["page"] = .integer(2)
        let text = try result(await router.handle(.init(tool: .readAttachment, arguments: args)))
        #expect(text["kind"]?.stringValue == "pdf_text" && text["page"]?.intValue == 2 && text["total_pages"]?.intValue == 2)
        #expect(text["text"]?.stringValue?.contains("Second page selected") == true && text["text"]?.stringValue?.contains("First") == false)
        args["mode"] = .string("image")
        let image = try result(await router.handle(.init(tool: .readAttachment, arguments: args)))
        #expect(image["kind"]?.stringValue == "pdf_page_image" && image["text"] == .null)
        let png = try #require(image["image"]?.objectValue)
        #expect(try #require(png["pixel_width"]?.intValue) <= 1_024 && #require(png["pixel_height"]?.intValue) <= 1_024)
        let base64 = try #require(png["data"]?.stringValue)
        let imageBytes = try #require(Data(base64Encoded: base64))
        #expect(imageBytes.starts(with: [137, 80, 78, 71]))
        args["page"] = .integer(3)
        #expect(await router.handle(.init(tool: .readAttachment, arguments: args)).error?.code == .invalidRequest)
        #expect(try Data(contentsOf: source) == data as Data)
    }
}
