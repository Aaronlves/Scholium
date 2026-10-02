import AppKit
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Shared PDF choice identity", .serialized)
@MainActor
struct PDFReaderAttachmentChoiceTests {
    @Test("Identical names and source bytes remain distinct choices under catalog reordering")
    func duplicateNames() throws {
        let first = try record(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let second = try record(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let choices = PDFReaderAttachmentChoice.choices(records: [second, first], currentID: second.id)
        let reordered = PDFReaderAttachmentChoice.choices(records: [first, second], currentID: second.id)
        #expect(choices.map(\.id) == [first.id, second.id])
        #expect(choices.map(\.id) == reordered.map(\.id))
        #expect(choices.map(\.copyOrdinal) == [1, 2])
        #expect(choices.map(\.copyLabel) == reordered.map(\.copyLabel))
        #expect(choices[0].copyLabel != choices[1].copyLabel)
        #expect(choices.allSatisfy { $0.record.filename == "Paper 注释.pdf" })
        #expect(choices.allSatisfy { $0.copyLabel?.contains($0.id.uuidString) == false })
        #expect(choices.filter { $0.isCurrent }.map(\.id) == [second.id])
        #expect(choices[0].storedPath != choices[1].storedPath)
    }

    @Test("Unknown or stale loaded identity never marks another same-named PDF as current")
    func exactCurrentIdentity() throws {
        let records = try [record(), record()]
        let unproven = PDFReaderAttachmentChoice.choices(records: records, currentID: nil)
        let departed = PDFReaderAttachmentChoice.choices(records: records, currentID: UUID())
        #expect(unproven.allSatisfy { !$0.isCurrent })
        #expect(departed.allSatisfy { !$0.isCurrent })
        let distinct = try record(filename: "Another.pdf")
        let unique = PDFReaderAttachmentChoice.choices(records: [distinct], currentID: distinct.id)
        #expect(unique.first?.copyOrdinal == nil && unique.first?.copyLabel == nil)
        #expect(unique.first?.isCurrent == true)
    }

    @Test("Selection survives order changes and clears on removal without filename retargeting")
    func selectionIdentity() throws {
        let selected = try record()
        let sameName = try record()
        #expect(PDFReaderAttachmentChoice.retainedSelection(selected.id, records: [sameName, selected]) == selected.id)
        #expect(PDFReaderAttachmentChoice.retainedSelection(selected.id, records: [sameName]) == nil)
        #expect(PDFReaderAttachmentChoice.retainedSelection(nil, records: [sameName]) == nil)
    }

    @Test("Choice details retain exact stored path and source metadata with original PDF byte size")
    func provenance() throws {
        let source = try ZoteroPDFSource(
            library: ZoteroLibraryMetadata(identity: .user, name: "Fixture Library 注释"),
            item: ZoteroItemMetadata(key: "PARENT01", title: "Exact fixture item title"),
            attachmentKey: "PDF00001", attachmentVersion: 3, title: "Fixture attachment",
            filename: "Paper 注释.pdf", linkMode: .importedFile, serverID: "FIXTURE-DATABASE",
            attachmentMetadataFingerprint: DocumentFingerprint(content: "metadata"))
        let imported = try record(source: source)
        let choice = try #require(PDFReaderAttachmentChoice.choices(records: [imported], currentID: nil).first)
        let fingerprint = try #require(imported.importedSourceFingerprint)
        #expect(choice.originalSize == ByteCountFormatter.string(fromByteCount: Int64(fingerprint.byteCount), countStyle: .file))
        #expect(fingerprint.byteCount != source.attachmentMetadataFingerprint.byteCount)
        #expect(choice.sourceLabel == "Zotero · Fixture Library 注释")
        #expect(choice.record.zoteroSource?.item.title == "Exact fixture item title")
        #expect(choice.storedPath == ".scholium/attachments/files/\(imported.id.uuidString.lowercased())/Paper 注释.pdf")
        #expect(choice.record.importedSourceFingerprint == DocumentFingerprint(content: "synthetic original PDF bytes"))
        let localRecord = try record()
        let local = try #require(PDFReaderAttachmentChoice.choices(records: [localRecord], currentID: nil).first)
        #expect(local.sourceLabel == ScholiumL10n.string("Imported PDF"))
    }

    @Test("Native Detach remains reachable for an unreadable authored binding and writes only that binding")
    func unavailableDetachMenu() async throws {
        let context = PDFReaderNoteContext(
            triptychID: UUID(), target: SourceAttachmentTarget(noteID: UUID(), vaultID: UUID(), relativePath: "nested/fixture.md"),
            authoredPath: "../../.scholium/attachments/files/missing/Exact Missing.pdf")
        let operations = ControlledPDFReaderOperations(notes: [:])
        await operations.failNextLoad(with: .missing)
        var writes: [(String?, SourceAttachmentTarget, String?)] = []
        let reader = PDFReaderController(windowID: UUID(), setBinding: { writes.append(($0, $1, $2)) }, reportIssue: { _ in nil })
        defer {
            reader.shutdown()
            Task { await operations.cancelPending() }
        }
        reader.setVisible(true)
        reader.follow(context, operations: operations)
        try await eventually { reader.error != nil && !reader.isLoading }
        let button = PDFReaderNativeMenuButton(controller: reader, kind: .actions)
        defer { button.invalidate() }
        let menu = try #require(button.menu)
        let detach = try #require(menu.items.first { $0.representedObject as? String == "detach" })
        #expect(reader.document == nil && detach.isEnabled)
        #expect(NSApplication.shared.sendAction(try #require(detach.action), to: detach.target, from: detach))
        try await eventually { writes.count == 1 && !reader.isImporting }
        #expect(writes.first?.0 == nil && writes.first?.1 == context.target && writes.first?.2 == context.authoredPath)

        let unbound = PDFReaderNoteContext(triptychID: context.triptychID, target: context.target, authoredPath: nil)
        reader.follow(unbound, operations: operations)
        let menuOwner = try #require(menu.delegate as? PDFReaderCommandMenu)
        menuOwner.menuNeedsUpdate(menu)
        #expect(!detach.isEnabled)
        #expect(NSApplication.shared.sendAction(try #require(detach.action), to: detach.target, from: detach))
        await Task.yield()
        #expect(writes.count == 1)
    }

    private func record(id: UUID = UUID(), filename: String = "Paper 注释.pdf", source: ZoteroPDFSource? = nil) throws -> PortableAttachmentRecord {
        PortableAttachmentRecord(
            id: id, vaultID: nil,
            location: .triptychRelative(try AttachmentRelativePath("attachments/files/\(id.uuidString.lowercased())/\(filename)")),
            importedSourceFingerprint: DocumentFingerprint(content: "synthetic original PDF bytes"), zoteroSource: source)
    }

    private func eventually(_ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        try #require(condition(), "The native PDF command did not reach its expected boundary.")
    }
}
